// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import CoreMedia
import Foundation
import QuartzCore

/// Captures an optional corner webcam sidecar (`camera.mov`) synchronized with
/// the screen recording session. Gracefully no-ops without blocking errors when
/// camera permission is not granted or no video capture device is connected.
final class RecorderCameraCapture: NSObject,
                                   AVCaptureFileOutputRecordingDelegate,
                                   @unchecked Sendable {
    static let defaultPreferenceKey = "recorderCameraBubbleEnabled"

    static func isCaptureRequested(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: defaultPreferenceKey) || RecorderCameraBubbleConfig().isEnabled
    }

    static func isAvailable() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized && preferredVideoDevice() != nil
    }

    private let queue = DispatchQueue(label: "com.vorssaint.recorder.camera",
                                      qos: .userInitiated)
    private let stateLock = NSLock()
    private let pauseClock: RecorderPauseClock?

    private var session: AVCaptureSession?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var stopRequested = false
    private var recordingStarted = false
    private var recordingFinished = false
    private var desiredPaused = false
    private var timeoutWork: DispatchWorkItem?
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var recordingStartHostTime: CFTimeInterval?

    init(pauseClock: RecorderPauseClock? = nil) {
        self.pauseClock = pauseClock
        super.init()
    }

    @discardableResult
    func start(to outputURL: URL) -> Bool {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
              let device = Self.preferredVideoDevice()
        else { return false }

        let shouldBegin = stateLock.withLock { () -> Bool in
            guard !stopRequested, !recordingStarted else { return false }
            return true
        }
        guard shouldBegin else { return false }

        queue.async { [self] in
            let aborted = stateLock.withLock { stopRequested || recordingStarted }
            guard !aborted else { return }

            guard let input = try? AVCaptureDeviceInput(device: device) else {
                stateLock.withLock { recordingFinished = true }
                return
            }

            let captureSession = AVCaptureSession()
            let output = AVCaptureMovieFileOutput()

            captureSession.beginConfiguration()
            if captureSession.canSetSessionPreset(.hd1280x720) {
                captureSession.sessionPreset = .hd1280x720
            } else if captureSession.canSetSessionPreset(.medium) {
                captureSession.sessionPreset = .medium
            }
            guard captureSession.canAddInput(input), captureSession.canAddOutput(output) else {
                captureSession.commitConfiguration()
                stateLock.withLock { recordingFinished = true }
                return
            }
            captureSession.addInput(input)
            captureSession.addOutput(output)
            captureSession.commitConfiguration()

            try? FileManager.default.removeItem(at: outputURL)
            captureSession.startRunning()
            guard captureSession.isRunning else {
                for existing in captureSession.inputs { captureSession.removeInput(existing) }
                for existing in captureSession.outputs { captureSession.removeOutput(existing) }
                stateLock.withLock { recordingFinished = true }
                return
            }

            let startOffset = pauseClock?.elapsed(at: CACurrentMediaTime()) ?? 0
            let createdItem = AVMutableMetadataItem()
            createdItem.identifier = .quickTimeMetadataCreationDate
            createdItem.value = ISO8601DateFormatter().string(from: Date()) as NSString
            createdItem.dataType = kCMMetadataBaseDataType_UTF8 as String
            let offsetItem = AVMutableMetadataItem()
            offsetItem.identifier = .quickTimeMetadataContentIdentifier
            offsetItem.value = String(format: "com.vorssaint.recorder.camera.offset:%.4f",
                                      locale: Locale(identifier: "en_US_POSIX"),
                                      startOffset) as NSString
            offsetItem.dataType = kCMMetadataBaseDataType_UTF8 as String
            output.metadata = [createdItem, offsetItem]

            self.session = captureSession
            self.movieOutput = output

            let abortBeforeRecord = stateLock.withLock { () -> Bool in
                if stopRequested {
                    recordingFinished = true
                    return true
                }
                recordingStarted = true
                recordingStartHostTime = CACurrentMediaTime()
                return false
            }
            if abortBeforeRecord {
                teardownSessionOnQueue()
                return
            }
            output.startRecording(to: outputURL, recordingDelegate: self)
        }
        return true
    }

    func pause() {
        stateLock.withLock { desiredPaused = true }
        queue.async { [self] in
            guard let movieOutput, movieOutput.isRecording, !movieOutput.isRecordingPaused else { return }
            movieOutput.pauseRecording()
        }
    }

    func resume() {
        stateLock.withLock { desiredPaused = false }
        queue.async { [self] in
            guard let movieOutput, movieOutput.isRecording, movieOutput.isRecordingPaused else { return }
            movieOutput.resumeRecording()
        }
    }

    func stop() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                let shouldWait = stateLock.withLock { () -> Bool in
                    stopRequested = true
                    if !recordingStarted || recordingFinished {
                        return false
                    }
                    finishWaiters.append(continuation)
                    return true
                }
                if !shouldWait {
                    teardownSessionOnQueue()
                    continuation.resume()
                    return
                }
                if let movieOutput, movieOutput.isRecording {
                    movieOutput.stopRecording()
                } else {
                    let waiters = stateLock.withLock { () -> [CheckedContinuation<Void, Never>] in
                        recordingFinished = true
                        let copy = finishWaiters
                        finishWaiters.removeAll()
                        return copy
                    }
                    teardownSessionOnQueue()
                    waiters.forEach { $0.resume() }
                    return
                }
                let timeout = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    let waiters = self.stateLock.withLock { () -> [CheckedContinuation<Void, Never>] in
                        guard !self.recordingFinished else { return [] }
                        self.recordingFinished = true
                        self.timeoutWork = nil
                        let copy = self.finishWaiters
                        self.finishWaiters.removeAll()
                        return copy
                    }
                    guard !waiters.isEmpty else { return }
                    self.teardownSessionOnQueue()
                    waiters.forEach { $0.resume() }
                }
                stateLock.withLock { timeoutWork = timeout }
                queue.asyncAfter(deadline: .now() + 5.0, execute: timeout)
            }
        }
    }

    // MARK: - AVCaptureFileOutputRecordingDelegate

    func fileOutput(_ output: AVCaptureFileOutput,
                    didStartRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection]) {
        let shouldPause = stateLock.withLock { desiredPaused && !stopRequested }
        if shouldPause {
            queue.async { [self] in
                guard let movieOutput, movieOutput.isRecording, !movieOutput.isRecordingPaused else { return }
                movieOutput.pauseRecording()
            }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        let succeeded: Bool
        if let nsError = error as NSError? {
            succeeded = (nsError.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) == true
        } else {
            succeeded = true
        }
        if !succeeded {
            try? FileManager.default.removeItem(at: outputFileURL)
        }
        queue.async { [self] in
            let waiters = stateLock.withLock { () -> [CheckedContinuation<Void, Never>] in
                recordingFinished = true
                timeoutWork?.cancel()
                timeoutWork = nil
                let copy = finishWaiters
                finishWaiters.removeAll()
                return copy
            }
            teardownSessionOnQueue()
            waiters.forEach { $0.resume() }
        }
    }

    // MARK: - Helpers

    private func teardownSessionOnQueue() {
        guard let captureSession = session else { return }
        session = nil
        movieOutput = nil
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }
        for output in captureSession.outputs {
            captureSession.removeOutput(output)
        }
    }

    private static func preferredVideoDevice() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        if let preferred = AVCaptureDevice.userPreferredCamera,
           discovery.devices.contains(where: { $0.uniqueID == preferred.uniqueID }) {
            return preferred
        }
        return discovery.devices.first ?? AVCaptureDevice.default(for: .video)
    }
}
