// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation
import Combine
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Watches screenshot and Desktop folders when opt-in auto-optimization is enabled,
/// debounces newly landed images/videos until size stabilizes, keeps a temporary
/// backup for 1-click undo, and replaces files when compression saves > 5%.
@MainActor
final class MediaAutoOptimizerService: ObservableObject {
    static let shared = MediaAutoOptimizerService()
    static let enabledDefaultsKey = "mediaAutoOptimizeEnabled"

    struct SavingsSummary: Equatable, Sendable {
        let fileName: String
        let originalBytes: Int64
        let optimizedBytes: Int64
        let savedPercent: Int
        let fileURL: URL
        let backupURL: URL
    }

    @Published private(set) var lastSavingsSummary: SavingsSummary?
    @Published private(set) var isWatching = false

    private nonisolated let queue = DispatchQueue(label: "com.vorssaint.utils.media-auto-optimizer", qos: .utility)
    private nonisolated(unsafe) var sources: [DispatchSourceFileSystemObject] = []
    private nonisolated(unsafe) var watchedDirectories: [URL] = []
    private nonisolated(unsafe) var knownFilePaths: Set<String> = []
    private nonisolated(unsafe) var pendingPaths: Set<String> = []
    private nonisolated(unsafe) var processedPaths: Set<String> = []
    private nonisolated let stateLock = NSLock()
    private nonisolated static let supportedExtensions: Set<String> = ["png", "jpg", "jpeg", "mp4", "mov"]

    private init() {}

    nonisolated static func compressionSavingsPercent(before: Int64, after: Int64) -> Int {
        guard before > 0, after >= 0, after < before else { return 0 }
        let ratio = (Double(before - after) / Double(before)) * 100.0
        return min(100, max(0, Int(ratio.rounded())))
    }

    func syncWithPreferences() {
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
        if enabled {
            start()
        } else {
            stop()
        }
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.enabledDefaultsKey)
        syncWithPreferences()
    }

    func start() {
        let directories = Self.targetDirectories()
        queue.async { [weak self] in
            self?.startOnQueue(directories: directories)
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopOnQueue()
        }
    }

    @discardableResult
    func undoLastOptimization() -> Bool {
        guard let summary = lastSavingsSummary else { return false }
        let fm = FileManager.default
        guard fm.fileExists(atPath: summary.backupURL.path) else {
            lastSavingsSummary = nil
            return false
        }

        stateLock.lock()
        processedPaths.insert(summary.fileURL.path)
        knownFilePaths.insert(summary.fileURL.path)
        stateLock.unlock()

        do {
            if fm.fileExists(atPath: summary.fileURL.path) {
                _ = try fm.replaceItemAt(summary.fileURL, withItemAt: summary.backupURL)
            } else {
                try fm.moveItem(at: summary.backupURL, to: summary.fileURL)
            }
            lastSavingsSummary = nil
            return true
        } catch {
            return false
        }
    }

    private static func targetDirectories() -> [URL] {
        var urls: [URL] = [SystemScreenshotWatcher.targetDirectory]
        if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            urls.append(desktop)
        }
        var seen = Set<String>()
        return urls.filter { url in
            let standardized = url.standardizedFileURL.path
            guard !seen.contains(standardized) else { return false }
            seen.insert(standardized)
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: standardized, isDirectory: &isDir) && isDir.boolValue
        }
    }

    private nonisolated func startOnQueue(directories: [URL]) {
        stopOnQueue()

        var initialKnown = Set<String>()
        for dir in directories {
            for file in Self.candidateMediaFiles(in: dir) {
                initialKnown.insert(file.path)
            }
        }
        stateLock.lock()
        knownFilePaths = initialKnown
        watchedDirectories = directories
        stateLock.unlock()

        var createdSources: [DispatchSourceFileSystemObject] = []
        for dir in directories {
            let fd = open(dir.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: .write,
                queue: queue
            )
            source.setEventHandler { [weak self] in
                self?.scanDirectoryChangesOnQueue(in: dir)
            }
            source.setCancelHandler {
                close(fd)
            }
            createdSources.append(source)
            source.resume()
        }
        sources = createdSources
        let active = !createdSources.isEmpty
        DispatchQueue.main.async { [weak self] in
            self?.isWatching = active
        }
    }

    private nonisolated func stopOnQueue() {
        for source in sources {
            source.cancel()
        }
        sources.removeAll()
        watchedDirectories.removeAll()
        stateLock.lock()
        pendingPaths.removeAll()
        stateLock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.isWatching = false
        }
    }

    private nonisolated static func candidateMediaFiles(in directory: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return []
        }
        return contents.filter { url in
            let name = url.lastPathComponent
            if name.hasPrefix(".") { return false }
            let ext = url.pathExtension.lowercased()
            return supportedExtensions.contains(ext)
        }
    }

    private nonisolated func scanDirectoryChangesOnQueue(in directory: URL) {
        let current = Self.candidateMediaFiles(in: directory)
        var newlyAdded: [URL] = []

        stateLock.lock()
        for url in current {
            let path = url.path
            if !knownFilePaths.contains(path) && !pendingPaths.contains(path) && !processedPaths.contains(path) {
                knownFilePaths.insert(path)
                pendingPaths.insert(path)
                newlyAdded.append(url)
            }
        }
        stateLock.unlock()

        for url in newlyAdded {
            scheduleStabilizationCheck(for: url, lastSize: nil, stableReads: 0, attempts: 0)
        }
    }

    private nonisolated func scheduleStabilizationCheck(for url: URL,
                                                        lastSize: Int64?,
                                                        stableReads: Int,
                                                        attempts: Int) {
        queue.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            guard fm.fileExists(atPath: url.path),
                  let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let currentSize = (attrs[.size] as? NSNumber)?.int64Value,
                  currentSize > 0 else {
                self.finishPending(path: url.path)
                return
            }

            if let lastSize, lastSize == currentSize {
                let nextStable = stableReads + 1
                if nextStable >= 1 {
                    self.optimizeFileAfterStabilization(at: url, originalBytes: currentSize)
                    return
                }
                self.scheduleStabilizationCheck(for: url, lastSize: currentSize, stableReads: nextStable, attempts: attempts + 1)
                return
            }

            if attempts >= 8 {
                self.finishPending(path: url.path)
                return
            }
            self.scheduleStabilizationCheck(for: url, lastSize: currentSize, stableReads: 0, attempts: attempts + 1)
        }
    }

    private nonisolated func finishPending(path: String) {
        stateLock.lock()
        pendingPaths.remove(path)
        stateLock.unlock()
    }

    private nonisolated func optimizeFileAfterStabilization(at url: URL, originalBytes: Int64) {
        guard !sources.isEmpty else {
            finishPending(path: url.path)
            return
        }
        let ext = url.pathExtension.lowercased()
        if ext == "png" || ext == "jpg" || ext == "jpeg" {
            let resultURL = optimizeImage(at: url, ext: ext)
            finalizeOptimization(originalURL: url, originalBytes: originalBytes, candidateOutputURL: resultURL)
        } else if ext == "mp4" || ext == "mov" {
            Task.detached(priority: .utility) { [weak self] in
                let resultURL = await Self.optimizeVideo(at: url, ext: ext)
                self?.queue.async {
                    self?.finalizeOptimization(originalURL: url, originalBytes: originalBytes, candidateOutputURL: resultURL)
                }
            }
        } else {
            finishPending(path: url.path)
        }
    }

    private nonisolated func finalizeOptimization(originalURL: URL,
                                                  originalBytes: Int64,
                                                  candidateOutputURL: URL?) {
        defer { finishPending(path: originalURL.path) }
        let fm = FileManager.default
        guard let tempOutURL = candidateOutputURL,
              let outAttrs = try? fm.attributesOfItem(atPath: tempOutURL.path),
              let afterBytes = (outAttrs[.size] as? NSNumber)?.int64Value else {
            return
        }

        let savedPercent = Self.compressionSavingsPercent(before: originalBytes, after: afterBytes)
        guard savedPercent > 5 else {
            try? fm.removeItem(at: tempOutURL)
            return
        }

        let backupDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("vorssaint-clop-backups", isDirectory: true)
        try? fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let backupURL = backupDir.appendingPathComponent("\(UUID().uuidString)-\(originalURL.lastPathComponent)")

        do {
            try fm.copyItem(at: originalURL, to: backupURL)
            stateLock.lock()
            processedPaths.insert(originalURL.path)
            stateLock.unlock()
            _ = try fm.replaceItemAt(originalURL, withItemAt: tempOutURL)

            let summary = SavingsSummary(
                fileName: originalURL.lastPathComponent,
                originalBytes: originalBytes,
                optimizedBytes: afterBytes,
                savedPercent: savedPercent,
                fileURL: originalURL,
                backupURL: backupURL
            )
            DispatchQueue.main.async { [weak self] in
                self?.lastSavingsSummary = summary
                QuickToolHUD.show(icon: "sparkles", message: "Saved \(savedPercent)%")
            }
        } catch {
            try? fm.removeItem(at: tempOutURL)
            try? fm.removeItem(at: backupURL)
        }
    }

    private nonisolated func optimizeImage(at url: URL, ext: String) -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let targetType: UTType = (ext == "png") ? .png : .jpeg
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("vorssaint-opt-\(UUID().uuidString).\(ext)")
        guard let destination = CGImageDestinationCreateWithURL(
            tempURL as CFURL,
            targetType.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.78,
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: tempURL)
            return nil
        }
        return tempURL
    }

    private nonisolated static func optimizeVideo(at url: URL, ext: String) async -> URL? {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
            return nil
        }
        let targetFileType: AVFileType = (ext == "mov") ? .mov : .mp4
        let compatible = await withCheckedContinuation { continuation in
            session.determineCompatibleFileTypes { types in
                continuation.resume(returning: types.contains(targetFileType))
            }
        }
        guard compatible else {
            return nil
        }
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("vorssaint-opt-\(UUID().uuidString).\(ext)")
        session.outputURL = tempURL
        session.outputFileType = targetFileType
        session.shouldOptimizeForNetworkUse = true
        nonisolated(unsafe) let exportSession = session
        let completed = await withCheckedContinuation { continuation in
            exportSession.exportAsynchronously {
                continuation.resume(returning: exportSession.status == .completed)
            }
        }
        guard completed else {
            try? FileManager.default.removeItem(at: tempURL)
            return nil
        }
        return tempURL
    }
}
