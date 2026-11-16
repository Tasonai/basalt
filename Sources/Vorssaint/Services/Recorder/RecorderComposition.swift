// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation

/// The two sound sources a take can carry. Their stable identifiers live in
/// track metadata so new recordings never depend on track order.
enum RecorderAudioSource: String, CaseIterable, Hashable {
    case system
    case microphone

    private var contentIdentifier: String {
        "com.vorssaint.recorder.audio." + rawValue
    }

    var trackMetadata: [AVMetadataItem] {
        let item = AVMutableMetadataItem()
        item.identifier = .quickTimeMetadataContentIdentifier
        item.value = contentIdentifier as NSString
        item.dataType = kCMMetadataBaseDataType_UTF8 as String
        return [item]
    }

    static func tracks(in asset: AVAsset) async -> [RecorderAudioSource: AVAssetTrack] {
        let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        var result: [RecorderAudioSource: AVAssetTrack] = [:]
        var unmatched: [AVAssetTrack] = []

        for track in tracks {
            let metadata = (try? await track.load(.metadata)) ?? []
            var source: RecorderAudioSource?
            for item in metadata where item.identifier == .quickTimeMetadataContentIdentifier {
                guard let value = try? await item.load(.stringValue) else { continue }
                source = allCases.first { $0.contentIdentifier == value }
                if source != nil { break }
            }
            if let source, result[source] == nil {
                result[source] = track
            } else {
                unmatched.append(track)
            }
        }

        // Takes from before track metadata existed carried only system sound.
        // The fallback also keeps hand-authored files usable in the editor.
        for source in allCases where result[source] == nil {
            guard !unmatched.isEmpty else { break }
            result[source] = unmatched.removeFirst()
        }
        return result
    }
}

/// Turns the stretches of a recording that survive the trim and the cuts into
/// one continuous asset.
///
/// Both the editor preview and the export read from this, which is what makes
/// the preview honest: a piece cut out of the middle is genuinely absent while
/// scrubbing, not hidden by a player that skips over it.
enum RecorderComposition {

    struct Result {
        let asset: AVMutableComposition
        let audioTrackIDs: [RecorderAudioSource: CMPersistentTrackID]
        let duration: CMTime
    }

    static func audioMix(trackIDs: [RecorderAudioSource: CMPersistentTrackID],
                         clickSFXTrackID: CMPersistentTrackID? = nil,
                         document: RecorderEditDocument) -> AVAudioMix? {
        guard !trackIDs.isEmpty || clickSFXTrackID != nil else { return nil }
        let mix = AVMutableAudioMix()
        var inputs: [AVMutableAudioMixInputParameters] = RecorderAudioSource.allCases.compactMap { source in
            guard let trackID = trackIDs[source] else { return nil }
            let parameters = AVMutableAudioMixInputParameters()
            parameters.trackID = trackID
            let kept: Bool
            let gain: Double
            switch source {
            case .system:
                kept = document.keepsSystemAudio
                gain = document.systemAudioGain
            case .microphone:
                kept = document.keepsMicrophone
                gain = document.microphoneGain
            }
            parameters.setVolume(kept ? Float(RecorderSupport.sanitizedAudioGain(gain)) : 0,
                                 at: .zero)
            return parameters
        }
        if let clickSFXTrackID {
            let sfx = AVMutableAudioMixInputParameters()
            sfx.trackID = clickSFXTrackID
            sfx.setVolume(1.0, at: .zero)
            inputs.append(sfx)
        }
        mix.inputParameters = inputs
        return mix
    }

    /// Synthesizes a temporary 48 kHz mono Float32 `.wav` track containing click
    /// impulses aligned to exported output timestamps and attaches it to
    /// `composition`. Caller removes `tempURL` after export finishes reading.
    static func attachClickSFXTrack(to composition: AVMutableComposition,
                                    clicks: [RecorderMotion.Click],
                                    style: RecorderClickSFXStyle,
                                    trim: RecorderSupport.Trim,
                                    cuts: [RecorderTimeline.Cut],
                                    playbackSpeed: Double,
                                    outputDuration: Double) async -> (trackID: CMPersistentTrackID, tempURL: URL)? {
        guard style != .off, outputDuration > 0 else { return nil }
        let sampleRate = 48_000.0
        let impulse = RecorderClickSFXStyle.synthesizeClickPCM(style: style,
                                                               sampleRate: sampleRate,
                                                               gain: 0.52)
        guard !impulse.isEmpty else { return nil }

        let timing = RecorderExportTiming(speed: playbackSpeed)
        let totalFrames = Int((outputDuration * sampleRate).rounded(.up))
        guard totalFrames > 0 else { return nil }

        let clickFrames: [Int] = clicks.compactMap { click in
            guard click.isDown,
                  let edited = RecorderTimeline.outputTime(forSource: click.time,
                                                           trim: trim,
                                                           cuts: cuts)
            else { return nil }
            let outTime = timing.outputTime(forSourceTime: edited)
            guard outTime >= 0, outTime < outputDuration else { return nil }
            let frame = Int((outTime * sampleRate).rounded())
            return (0..<totalFrames).contains(frame) ? frame : nil
        }.sorted()
        guard !clickFrames.isEmpty else { return nil }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-clicksfx-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: sampleRate,
                                         channels: 1,
                                         interleaved: false),
              let file = try? AVAudioFile(forWriting: tempURL,
                                          settings: settings,
                                          commonFormat: .pcmFormatFloat32,
                                          interleaved: false)
        else { return nil }

        let chunkFrames = 48_000
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(chunkFrames)),
              let channel = buffer.floatChannelData?[0]
        else {
            try? FileManager.default.removeItem(at: tempURL)
            return nil
        }

        var cursor = 0
        var firstActive = 0
        do {
            while cursor < totalFrames {
                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: tempURL)
                    return nil
                }
                let count = min(chunkFrames, totalFrames - cursor)
                buffer.frameLength = AVAudioFrameCount(count)
                channel.initialize(repeating: 0, count: count)
                while firstActive < clickFrames.count,
                      clickFrames[firstActive] + impulse.count <= cursor {
                    firstActive += 1
                }
                var idx = firstActive
                while idx < clickFrames.count, clickFrames[idx] < cursor + count {
                    let start = clickFrames[idx]
                    let localStart = max(0, start - cursor)
                    let localEnd = min(count, start + impulse.count - cursor)
                    for outPos in localStart..<localEnd {
                        let impPos = cursor + outPos - start
                        let mixed = channel[outPos] + impulse[impPos]
                        channel[outPos] = max(-1, min(1, mixed))
                    }
                    idx += 1
                }
                try file.write(from: buffer)
                cursor += count
            }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            return nil
        }

        let sfxAsset = AVURLAsset(url: tempURL)
        guard let sourceTrack = try? await sfxAsset.loadTracks(withMediaType: .audio).first,
              let sfxTrack = composition.addMutableTrack(
                  withMediaType: .audio,
                  preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            try? FileManager.default.removeItem(at: tempURL)
            return nil
        }
        let sfxDuration = (try? await sfxAsset.load(.duration)) ?? .zero
        let targetDuration = CMTimeMinimum(
            CMTime(seconds: outputDuration, preferredTimescale: 60_000),
            sfxDuration)
        guard targetDuration.seconds > 0 else {
            composition.removeTrack(sfxTrack)
            try? FileManager.default.removeItem(at: tempURL)
            return nil
        }
        do {
            try sfxTrack.insertTimeRange(CMTimeRange(start: .zero, duration: targetDuration),
                                         of: sourceTrack,
                                         at: .zero)
        } catch {
            composition.removeTrack(sfxTrack)
            try? FileManager.default.removeItem(at: tempURL)
            return nil
        }
        return (sfxTrack.trackID, tempURL)
    }

    static func build(from asset: AVAsset,
                      ranges: [ClosedRange<Double>],
                      includesAudio: Bool,
                      playbackSpeed: Double = 1) async -> Result? {
        guard !ranges.isEmpty else { return nil }
        let composition = AVMutableComposition()
        guard let sourceVideo = try? await asset.loadTracks(withMediaType: .video).first,
              let video = composition.addMutableTrack(withMediaType: .video,
                                                      preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return nil }
        video.preferredTransform = (try? await sourceVideo.load(.preferredTransform)) ?? .identity

        let sourceAudio = includesAudio ? await RecorderAudioSource.tracks(in: asset) : [:]
        var audio: [(source: RecorderAudioSource, from: AVAssetTrack,
                     sourceRange: CMTimeRange, to: AVMutableCompositionTrack)] = []
        for source in RecorderAudioSource.allCases {
            guard let from = sourceAudio[source] else { continue }
            guard let track = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            let sourceRange = (try? await from.load(.timeRange)) ?? .invalid
            audio.append((source, from, sourceRange, track))
        }

        var cursor = CMTime.zero
        for range in ranges {
            let start = CMTime(seconds: range.lowerBound, preferredTimescale: 600)
            let duration = CMTime(seconds: range.upperBound - range.lowerBound,
                                  preferredTimescale: 600)
            guard duration.seconds > 0 else { continue }
            let window = CMTimeRange(start: start, duration: duration)
            do {
                try video.insertTimeRange(window, of: sourceVideo, at: cursor)
            } catch {
                // A range the source cannot serve is skipped rather than
                // failing the whole export; the rest of the recording is still
                // worth having.
                continue
            }
            for pair in audio {
                let overlap = CMTimeRangeGetIntersection(window,
                                                         otherRange: pair.sourceRange)
                guard overlap.isValid, !overlap.isEmpty else { continue }
                let offset = CMTimeSubtract(overlap.start, window.start)
                try? pair.to.insertTimeRange(overlap,
                                             of: pair.from,
                                             at: CMTimeAdd(cursor, offset))
            }
            cursor = CMTimeAdd(cursor, duration)
        }
        guard cursor.seconds > 0 else { return nil }
        let timing = RecorderExportTiming(speed: playbackSpeed)
        if timing.speed != 1 {
            // Scale the whole edited timeline once, including audio gaps and
            // offsets. Retiming only video timestamps would leave PCM audio
            // at its old duration. The default preview path stays untouched.
            let outputDuration = CMTime(
                seconds: timing.outputTime(forSourceTime: cursor.seconds),
                preferredTimescale: 60_000)
            composition.scaleTimeRange(CMTimeRange(start: .zero, duration: cursor),
                                       toDuration: outputDuration)
            cursor = outputDuration
        }
        return Result(asset: composition,
                      audioTrackIDs: Dictionary(uniqueKeysWithValues: audio.map {
                          ($0.source, $0.to.trackID)
                      }),
                      duration: cursor)
    }
}

/// A small, fixed summary of an audio track for the editor timeline. Reading
/// happens once off the main thread and keeps no decoded audio afterwards.
enum RecorderAudioWaveform {
    static func load(asset: AVAsset,
                     track: AVAssetTrack,
                     duration: Double,
                     count: Int) -> [Float] {
        guard duration > 0, count > 0,
              let reader = try? AVAssetReader(asset: asset) else { return [] }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else { return [] }

        var peaks = Array(repeating: Float.zero, count: count)
        while let sample = output.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                return []
            }
            guard let block = CMSampleBufferGetDataBuffer(sample),
                  let format = CMSampleBufferGetFormatDescription(sample),
                  let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)
            else { continue }
            var lengthAtOffset = 0
            var totalLength = 0
            var bytes: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(block,
                                              atOffset: 0,
                                              lengthAtOffsetOut: &lengthAtOffset,
                                              totalLengthOut: &totalLength,
                                              dataPointerOut: &bytes) == kCMBlockBufferNoErr,
                  let bytes else { continue }
            let channels = max(1, Int(description.pointee.mChannelsPerFrame))
            let frames = min(CMSampleBufferGetNumSamples(sample), totalLength / (4 * channels))
            let sampleRate = max(1, description.pointee.mSampleRate)
            let start = max(0, CMSampleBufferGetPresentationTimeStamp(sample).seconds)
            bytes.withMemoryRebound(to: Float.self, capacity: frames * channels) { values in
                for frame in 0..<frames {
                    let time = start + Double(frame) / sampleRate
                    let index = min(count - 1, max(0, Int(time / duration * Double(count))))
                    var peak = peaks[index]
                    for channel in 0..<channels {
                        peak = max(peak, abs(values[frame * channels + channel]))
                    }
                    peaks[index] = min(1, peak)
                }
            }
        }
        return peaks
    }
}
