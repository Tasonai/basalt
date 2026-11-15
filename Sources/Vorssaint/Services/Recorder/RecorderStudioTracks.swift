// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Speech

/// Corner placement for the Screen Recorder Studio camera bubble overlay.
enum RecorderCameraBubbleCorner: String, Codable, CaseIterable, Identifiable {
    case bottomLeading
    case bottomTrailing
    case topLeading
    case topTrailing

    var id: String { rawValue }
}

/// Configuration for the circular webcam / avatar overlay rendered by
/// `RecorderComposer` with cursor-proximity auto-shrink.
struct RecorderCameraBubbleConfig: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var corner: RecorderCameraBubbleCorner
    /// Fraction of the minor output dimension in `0.10...0.32`.
    var diameterFraction: Double
    var autoShrinkOnPointerNear: Bool
    var borderHex: String

    init(isEnabled: Bool = false,
         corner: RecorderCameraBubbleCorner = .bottomLeading,
         diameterFraction: Double = 0.20,
         autoShrinkOnPointerNear: Bool = true,
         borderHex: String = "#FFFFFF") {
        self.isEnabled = isEnabled
        self.corner = corner
        self.diameterFraction = min(0.32, max(0.10, diameterFraction))
        self.autoShrinkOnPointerNear = autoShrinkOnPointerNear
        self.borderHex = borderHex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        corner = try c.decodeIfPresent(RecorderCameraBubbleCorner.self, forKey: .corner) ?? .bottomLeading
        let frac = try c.decodeIfPresent(Double.self, forKey: .diameterFraction) ?? 0.20
        diameterFraction = min(0.32, max(0.10, frac))
        autoShrinkOnPointerNear = try c.decodeIfPresent(Bool.self, forKey: .autoShrinkOnPointerNear) ?? true
        borderHex = try c.decodeIfPresent(String.self, forKey: .borderHex) ?? "#FFFFFF"
    }

    /// Normalized `(0...1, 0...1)` center position in top-left image space.
    var normalizedCenter: CGPoint {
        let inset = 0.14
        switch corner {
        case .topLeading: return CGPoint(x: inset, y: inset)
        case .topTrailing: return CGPoint(x: 1 - inset, y: inset)
        case .bottomLeading: return CGPoint(x: inset, y: 1 - inset)
        case .bottomTrailing: return CGPoint(x: 1 - inset, y: 1 - inset)
        }
    }

    /// Shrinks smoothly to `0.62` when the recorded cursor approaches the bubble.
    func effectiveScale(pointerNormalized: CGPoint?) -> CGFloat {
        guard autoShrinkOnPointerNear, let pointerNormalized else { return 1.0 }
        let center = normalizedCenter
        let dx = Double(pointerNormalized.x - center.x)
        let dy = Double(pointerNormalized.y - center.y)
        let distance = hypot(dx, dy)
        let triggerRadius = max(0.22, diameterFraction + 0.08)
        return distance <= triggerRadius ? 0.62 : 1.0
    }
}

/// One recorded keyboard shortcut chord shown as a translucent keycap pill.
struct RecorderKeystrokeEvent: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Double
    let label: String
    let modifiers: [String]

    init(id: UUID = UUID(),
         timestamp: Double,
         label: String,
         modifiers: [String] = []) {
        self.id = id
        self.timestamp = max(0, timestamp)
        self.label = label
        self.modifiers = modifiers
    }

    var formattedCapString: String {
        (modifiers + [label])
            .filter { !$0.isEmpty }
            .joined()
    }

    static func activeEvents(in events: [RecorderKeystrokeEvent],
                             at time: Double,
                             holdDuration: Double = 1.35) -> [RecorderKeystrokeEvent] {
        let window = max(0.2, holdDuration)
        return events.filter { time >= $0.timestamp && time <= $0.timestamp + window }
    }
}

/// Never records keystrokes while macOS Secure Event Input is active (password
/// fields, 1Password, Terminal sudo prompts).
enum RecorderKeystrokeCaptureGate {
    static func canRecordKeystrokes(secureInputActive: Bool = IsSecureEventInputEnabled()) -> Bool {
        !secureInputActive
    }
}

/// Procedural click sound synthesis styles (zero external audio files needed).
enum RecorderClickSFXStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case softTap
    case mechanical
    case crispPop

    var id: String { rawValue }

    static func sanitized(_ raw: String) -> RecorderClickSFXStyle {
        RecorderClickSFXStyle(rawValue: raw) ?? .off
    }

    /// Generates mono Float32 PCM samples for one pointer click impulse.
    static func synthesizeClickPCM(style: RecorderClickSFXStyle,
                                   sampleRate: Double = 44_100,
                                   gain: Float = 0.45) -> [Float] {
        guard style != .off, sampleRate >= 8_000 else { return [] }
        let duration: Double
        let baseFreq: Double
        let decay: Double
        let clampedGain = max(0, min(1, gain))
        switch style {
        case .off: return []
        case .softTap:
            duration = 0.032
            baseFreq = 520
            decay = 115
        case .mechanical:
            duration = 0.045
            baseFreq = 1_380
            decay = 88
        case .crispPop:
            duration = 0.028
            baseFreq = 860
            decay = 140
        }
        let frameCount = max(1, Int((duration * sampleRate).rounded()))
        var out = [Float](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let env = exp(-decay * t)
            let primary = sin(2.0 * .pi * baseFreq * t)
            let harmonic = 0.35 * sin(2.0 * .pi * (baseFreq * 2.15) * t)
            out[i] = Float((primary + harmonic) * env) * clampedGain
        }
        return out
    }
}

/// One timed transcript/caption segment supporting `.srt` export and rough-cut editing.
struct RecorderCaptionSegment: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var start: Double
    var end: Double
    var text: String
    var isCut: Bool

    init(id: UUID = UUID(),
         start: Double,
         end: Double,
         text: String,
         isCut: Bool = false) {
        self.id = id
        self.start = max(0, start)
        self.end = max(self.start, end)
        self.text = text
        self.isCut = isCut
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let rawStart = try c.decodeIfPresent(Double.self, forKey: .start) ?? 0
        let rawEnd = try c.decodeIfPresent(Double.self, forKey: .end) ?? rawStart
        start = max(0, rawStart)
        end = max(start, rawEnd)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        isCut = try c.decodeIfPresent(Bool.self, forKey: .isCut) ?? false
    }

    /// Formats non-deleted, non-empty caption segments in standard SubRip (`.srt`) syntax.
    static func formatSRT(_ segments: [RecorderCaptionSegment]) -> String {
        let active = segments
            .filter { !$0.isCut && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.start < $1.start }
        return active.enumerated().map { idx, seg in
            let line = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(idx + 1)\n\(srtTimestamp(seg.start)) --> \(srtTimestamp(seg.end))\n\(line)"
        }.joined(separator: "\n\n")
    }

    /// Maps caption segments marked `isCut == true` into video timeline cuts.
    static func cutsFromDeletedCaptions(_ segments: [RecorderCaptionSegment]) -> [RecorderTimeline.Cut] {
        segments
            .filter { $0.isCut && $0.end - $0.start > 0.05 }
            .map { RecorderTimeline.Cut(start: $0.start, end: $0.end) }
            .sorted { $0.start < $1.start }
    }

    static func activeCaption(in segments: [RecorderCaptionSegment], at time: Double) -> RecorderCaptionSegment? {
        segments.first { !$0.isCut && time >= $0.start && time <= $0.end }
    }

    private static func srtTimestamp(_ seconds: Double) -> String {
        let totalMillis = max(0, Int((seconds * 1000.0).rounded()))
        let hours = totalMillis / 3_600_000
        let minutes = (totalMillis % 3_600_000) / 60_000
        let secs = (totalMillis % 60_000) / 1_000
        let millis = totalMillis % 1_000
        return String(format: "%02d:%02d:%02d,%03d",
                      locale: Locale(identifier: "en_US_POSIX"),
                      hours, minutes, secs, millis)
    }
}

/// Offline / on-device speech recognition wrapper producing timed caption segments.
enum RecorderSpeechTranscriber {
    static func transcribeAudio(at mediaURL: URL,
                                locale: Locale = .current) async -> [RecorderCaptionSegment] {
        let auth = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard auth else { return [] }
        let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else { return [] }

        let request = SFSpeechURLRecognitionRequest(url: mediaURL)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        return await withCheckedContinuation { cont in
            var resumed = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !resumed else { return }
                if let error {
                    _ = error
                    resumed = true
                    cont.resume(returning: [])
                    return
                }
                guard let result, result.isFinal else { return }
                resumed = true
                let segments = groupSegments(from: result.bestTranscription.segments)
                cont.resume(returning: segments)
            }
        }
    }

    /// Groups word-level recognition segments into readable ~6-word caption lines.
    static func groupSegments(from words: [SFTranscriptionSegment]) -> [RecorderCaptionSegment] {
        guard !words.isEmpty else { return [] }
        var result: [RecorderCaptionSegment] = []
        var bucket: [SFTranscriptionSegment] = []
        for word in words {
            if let prev = bucket.last,
               (word.timestamp - (prev.timestamp + prev.duration) > 0.85 || bucket.count >= 6) {
                result.append(makeSegment(from: bucket))
                bucket = []
            }
            bucket.append(word)
        }
        if !bucket.isEmpty {
            result.append(makeSegment(from: bucket))
        }
        return result
    }

    private static func makeSegment(from bucket: [SFTranscriptionSegment]) -> RecorderCaptionSegment {
        let start = bucket.first?.timestamp ?? 0
        let lastEnd = (bucket.last?.timestamp ?? start) + (bucket.last?.duration ?? 0.5)
        let text = bucket.map(\.substring).joined(separator: " ")
        return RecorderCaptionSegment(start: start, end: max(start + 0.3, lastEnd), text: text)
    }
}
