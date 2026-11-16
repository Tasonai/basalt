// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Corner placement for the Screen Recorder Studio camera bubble overlay.
enum RecorderCameraBubbleCorner: String, Codable, CaseIterable, Identifiable, Sendable {
    case bottomLeading
    case bottomTrailing
    case topLeading
    case topTrailing

    var id: String { rawValue }

    var cornerIndex: Int {
        switch self {
        case .topLeading: return 0
        case .topTrailing: return 1
        case .bottomLeading: return 2
        case .bottomTrailing: return 3
        }
    }

    init(cornerIndex: Int) {
        switch cornerIndex {
        case 0: self = .topLeading
        case 1: self = .topTrailing
        case 2: self = .bottomLeading
        default: self = .bottomTrailing
        }
    }
}

/// Visual mask geometry for the Screen Recorder Studio camera overlay.
enum CameraBubbleShape: String, Codable, CaseIterable, Identifiable, Sendable {
    case circle
    case squircle
    case verticalPortrait
    case hidden

    var id: String { rawValue }
}

/// Time-anchored camera layout keyframe resolved chronologically during playback and export.
struct SceneLayoutKeyframe: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var timeSeconds: Double
    var shape: CameraBubbleShape
    var cornerIndex: Int
    var scale: Double

    init(id: UUID = UUID(),
         timeSeconds: Double,
         shape: CameraBubbleShape,
         cornerIndex: Int = 2,
         scale: Double = 1.0) {
        self.id = id
        self.timeSeconds = timeSeconds.isFinite ? max(0, timeSeconds) : 0
        self.shape = shape
        self.cornerIndex = min(3, max(0, cornerIndex))
        self.scale = scale.isFinite ? min(2.5, max(0.35, scale)) : 1.0
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let rawTime = try c.decodeIfPresent(Double.self, forKey: .timeSeconds) ?? 0
        timeSeconds = rawTime.isFinite ? max(0, rawTime) : 0
        shape = try c.decodeIfPresent(CameraBubbleShape.self, forKey: .shape) ?? .circle
        let rawCorner = try c.decodeIfPresent(Int.self, forKey: .cornerIndex) ?? 2
        cornerIndex = min(3, max(0, rawCorner))
        let rawScale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? 1.0
        scale = rawScale.isFinite ? min(2.5, max(0.35, rawScale)) : 1.0
    }

    var corner: RecorderCameraBubbleCorner {
        RecorderCameraBubbleCorner(cornerIndex: cornerIndex)
    }

    static func activeKeyframe(at time: Double, keyframes: [SceneLayoutKeyframe]) -> SceneLayoutKeyframe? {
        guard time.isFinite, !keyframes.isEmpty else { return nil }
        let ordered = keyframes
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.timeSeconds != rhs.element.timeSeconds {
                    return lhs.element.timeSeconds < rhs.element.timeSeconds
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
        return ordered.last { $0.timeSeconds <= time + 0.0001 }
    }

    static func activeShape(at time: Double,
                            keyframes: [SceneLayoutKeyframe],
                            defaultShape: CameraBubbleShape) -> CameraBubbleShape {
        activeKeyframe(at: time, keyframes: keyframes)?.shape ?? defaultShape
    }
}

/// Output aspect presets supporting automatic cursor-centered reframing.
enum StudioOutputAspect: String, Codable, CaseIterable, Identifiable, Sendable {
    case native
    case vertical9x16
    case square1x1
    case cinema16x9

    var id: String { rawValue }

    var aspectRatio: CGFloat? {
        switch self {
        case .native: return nil
        case .vertical9x16: return 9.0 / 16.0
        case .square1x1: return 1.0
        case .cinema16x9: return 16.0 / 9.0
        }
    }

    func targetCanvasSize(sourceSize: CGSize) -> CGSize {
        let validSource = sourceSize.width.isFinite && sourceSize.height.isFinite
            && sourceSize.width > 0 && sourceSize.height > 0
        let safeSource = validSource ? sourceSize : CGSize(width: 1920, height: 1080)
        guard let ratio = aspectRatio, ratio.isFinite, ratio > 0 else {
            return safeSource
        }

        let srcRatio = safeSource.width / safeSource.height
        let rawWidth: CGFloat
        let rawHeight: CGFloat
        if srcRatio >= ratio {
            rawHeight = safeSource.height
            rawWidth = rawHeight * ratio
        } else {
            rawWidth = safeSource.width
            rawHeight = rawWidth / ratio
        }

        let width: CGFloat
        let height: CGFloat
        if min(rawWidth, rawHeight) >= 64 {
            width = Self.evenDimension(rawWidth)
            height = Self.evenDimension(rawHeight)
        } else {
            width = max(1, rawWidth)
            height = max(1, rawHeight)
        }
        return CGSize(width: width, height: height)
    }

    func cursorReframeCropRect(sourceSize: CGSize, normalizedCursor: CGPoint) -> CGRect {
        let validSource = sourceSize.width.isFinite && sourceSize.height.isFinite
            && sourceSize.width > 0 && sourceSize.height > 0
        guard validSource else {
            return CGRect(origin: .zero, size: targetCanvasSize(sourceSize: sourceSize))
        }
        guard let ratio = aspectRatio, ratio.isFinite, ratio > 0 else {
            return CGRect(origin: .zero, size: sourceSize)
        }

        let nx = normalizedCursor.x.isFinite ? min(1, max(0, normalizedCursor.x)) : 0.5
        let ny = normalizedCursor.y.isFinite ? min(1, max(0, normalizedCursor.y)) : 0.5

        let srcRatio = sourceSize.width / sourceSize.height
        let cropWidth: CGFloat
        let cropHeight: CGFloat
        if srcRatio >= ratio {
            cropHeight = sourceSize.height
            cropWidth = min(sourceSize.width, cropHeight * ratio)
        } else {
            cropWidth = sourceSize.width
            cropHeight = min(sourceSize.height, cropWidth / ratio)
        }

        let centerX = nx * sourceSize.width
        let centerY = ny * sourceSize.height
        let maxOriginX = max(0, sourceSize.width - cropWidth)
        let maxOriginY = max(0, sourceSize.height - cropHeight)
        let originX = min(max(0, centerX - cropWidth * 0.5), maxOriginX)
        let originY = min(max(0, centerY - cropHeight * 0.5), maxOriginY)
        return CGRect(x: originX, y: originY, width: cropWidth, height: cropHeight)
    }

    private static func evenDimension(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 2 }
        let rounded = max(2, (value / 2.0).rounded() * 2.0)
        return rounded
    }
}

/// Smoothed 3D perspective tilt angles derived from normalized cursor coordinates.
struct PerspectiveTiltSample: Equatable, Sendable {
    let pitchDegrees: Double
    let yawDegrees: Double

    static func cursorPerspectiveTilt(normalizedCursor: CGPoint,
                                      maxAngleDegrees: Double = 8.0,
                                      enabled: Bool) -> PerspectiveTiltSample {
        guard enabled else {
            return PerspectiveTiltSample(pitchDegrees: 0, yawDegrees: 0)
        }
        let maxAngle = maxAngleDegrees.isFinite ? min(45.0, max(0.0, abs(maxAngleDegrees))) : 8.0
        let nx = normalizedCursor.x.isFinite ? min(1.0, max(0.0, Double(normalizedCursor.x))) : 0.5
        let ny = normalizedCursor.y.isFinite ? min(1.0, max(0.0, Double(normalizedCursor.y))) : 0.5

        func smoothSigned(_ unit: Double) -> Double {
            let clamped = min(1.0, max(-1.0, unit))
            let mag = abs(clamped)
            let eased = mag * mag * (3.0 - 2.0 * mag)
            return clamped < 0 ? -eased : eased
        }

        let yaw = smoothSigned((nx - 0.5) * 2.0) * maxAngle
        let pitch = smoothSigned((0.5 - ny) * 2.0) * maxAngle
        return PerspectiveTiltSample(pitchDegrees: pitch, yawDegrees: yaw)
    }
}

/// Word-level transcript token for karaoke caption highlighting and timeline scrubbing.
struct WhisperWordToken: Codable, Equatable, Sendable {
    let word: String
    let startSeconds: Double
    let endSeconds: Double

    init(word: String, startSeconds: Double, endSeconds: Double) {
        self.word = word
        let safeStart = startSeconds.isFinite ? max(0, startSeconds) : 0
        let safeEnd = endSeconds.isFinite ? max(safeStart, endSeconds) : safeStart
        self.startSeconds = safeStart
        self.endSeconds = safeEnd
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawWord = try c.decodeIfPresent(String.self, forKey: .word) ?? ""
        let rawStart = try c.decodeIfPresent(Double.self, forKey: .startSeconds) ?? 0
        let rawEnd = try c.decodeIfPresent(Double.self, forKey: .endSeconds) ?? rawStart
        self.init(word: rawWord, startSeconds: rawStart, endSeconds: rawEnd)
    }
}

/// Parses `whisper-cli -ojf` JSON output and word-timestamp arrays into `WhisperWordToken`s.
enum WhisperCLITranscriptParser {
    static func parseWhisperJSON(_ data: Data) -> [WhisperWordToken] {
        guard !data.isEmpty,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }

        var collected: [WhisperWordToken] = []

        if let transcription = root["transcription"] as? [[String: Any]] {
            for segment in transcription {
                if let tokens = segment["tokens"] as? [[String: Any]] {
                    collected.append(contentsOf: parseTokenArray(tokens))
                } else if let words = segment["words"] as? [[String: Any]] {
                    collected.append(contentsOf: parseTokenArray(words))
                }
            }
        }

        if collected.isEmpty, let segments = root["segments"] as? [[String: Any]] {
            for segment in segments {
                if let tokens = segment["tokens"] as? [[String: Any]] {
                    collected.append(contentsOf: parseTokenArray(tokens))
                } else if let words = segment["words"] as? [[String: Any]] {
                    collected.append(contentsOf: parseTokenArray(words))
                }
            }
        }

        if collected.isEmpty, let words = root["words"] as? [[String: Any]] {
            collected.append(contentsOf: parseTokenArray(words))
        }

        return collected
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.startSeconds != rhs.element.startSeconds {
                    return lhs.element.startSeconds < rhs.element.startSeconds
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    static func activeWordIndex(at time: Double, tokens: [WhisperWordToken]) -> Int? {
        guard time.isFinite, !tokens.isEmpty else { return nil }
        return tokens.lastIndex { token in
            time >= token.startSeconds && time <= token.endSeconds
        }
    }

    private static func parseTokenArray(_ array: [[String: Any]]) -> [WhisperWordToken] {
        var result: [WhisperWordToken] = []
        result.reserveCapacity(array.count)
        for item in array {
            let rawText = (item["word"] as? String) ?? (item["text"] as? String) ?? ""
            guard let cleaned = cleanTokenWord(rawText),
                  let (start, end) = extractTimestampRange(from: item)
            else { continue }
            result.append(WhisperWordToken(word: cleaned, startSeconds: start, endSeconds: end))
        }
        return result
    }

    private static func cleanTokenWord(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") { return nil }
        if trimmed.hasPrefix("<|") && trimmed.hasSuffix("|>") { return nil }
        return trimmed
    }

    private static func extractTimestampRange(from item: [String: Any]) -> (Double, Double)? {
        if let offsets = item["offsets"] as? [String: Any],
           let fromMS = numericValue(offsets["from"]),
           let toMS = numericValue(offsets["to"]) {
            let start = max(0, fromMS / 1000.0)
            let end = max(start, toMS / 1000.0)
            return (start, end)
        }
        if let start = numericValue(item["startSeconds"]),
           let end = numericValue(item["endSeconds"]) {
            let s = max(0, start)
            return (s, max(s, end))
        }
        if let start = numericValue(item["start"]),
           let end = numericValue(item["end"]) {
            let s = max(0, start)
            return (s, max(s, end))
        }
        if let fromMS = numericValue(item["start_ms"]),
           let toMS = numericValue(item["end_ms"]) {
            let s = max(0, fromMS / 1000.0)
            return (s, max(s, toMS / 1000.0))
        }
        if let timestamps = item["timestamps"] as? [String: Any],
           let fromStr = timestamps["from"] as? String,
           let toStr = timestamps["to"] as? String,
           let start = parseSRTTimestamp(fromStr),
           let end = parseSRTTimestamp(toStr) {
            return (start, max(start, end))
        }
        return nil
    }

    private static func numericValue(_ raw: Any?) -> Double? {
        if let num = raw as? NSNumber {
            let d = num.doubleValue
            return d.isFinite ? d : nil
        }
        if let str = raw as? String, let d = Double(str), d.isFinite {
            return d
        }
        return nil
    }

    private static func parseSRTTimestamp(_ raw: String) -> Double? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let parts = normalized.split(separator: ":")
        guard parts.count == 3,
              let h = Double(parts[0]),
              let m = Double(parts[1]),
              let s = Double(parts[2]),
              h.isFinite, m.isFinite, s.isFinite else { return nil }
        return max(0, h * 3600 + m * 60 + s)
    }
}

/// Computes linear system-audio attenuation when microphone speech RMS crosses threshold.
enum AudioAutoDuckingMath {
    static func systemGainLinear(micRMS: Float,
                                 thresholdRMS: Float = 0.025,
                                 duckedDB: Float = -12.0,
                                 enabled: Bool) -> Float {
        guard enabled,
              micRMS.isFinite,
              thresholdRMS.isFinite,
              micRMS >= max(0, thresholdRMS)
        else { return 1.0 }

        let safeDB = duckedDB.isFinite ? min(0.0, duckedDB) : -12.0
        let linear = powf(10.0, safeDB / 20.0)
        guard linear.isFinite else { return 1.0 }
        return min(1.0, max(0.0, linear))
    }
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
    var shape: CameraBubbleShape
    var personSegmentationBlurEnabled: Bool
    var sceneKeyframes: [SceneLayoutKeyframe]

    init(isEnabled: Bool = false,
         corner: RecorderCameraBubbleCorner = .bottomLeading,
         diameterFraction: Double = 0.20,
         autoShrinkOnPointerNear: Bool = true,
         borderHex: String = "#FFFFFF",
         shape: CameraBubbleShape = .circle,
         personSegmentationBlurEnabled: Bool = false,
         sceneKeyframes: [SceneLayoutKeyframe] = []) {
        self.isEnabled = isEnabled
        self.corner = corner
        self.diameterFraction = min(0.32, max(0.10, diameterFraction))
        self.autoShrinkOnPointerNear = autoShrinkOnPointerNear
        self.borderHex = borderHex
        self.shape = shape
        self.personSegmentationBlurEnabled = personSegmentationBlurEnabled
        self.sceneKeyframes = sceneKeyframes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        corner = try c.decodeIfPresent(RecorderCameraBubbleCorner.self, forKey: .corner) ?? .bottomLeading
        let frac = try c.decodeIfPresent(Double.self, forKey: .diameterFraction) ?? 0.20
        diameterFraction = min(0.32, max(0.10, frac))
        autoShrinkOnPointerNear = try c.decodeIfPresent(Bool.self, forKey: .autoShrinkOnPointerNear) ?? true
        borderHex = try c.decodeIfPresent(String.self, forKey: .borderHex) ?? "#FFFFFF"
        shape = try c.decodeIfPresent(CameraBubbleShape.self, forKey: .shape) ?? .circle
        personSegmentationBlurEnabled = try c.decodeIfPresent(Bool.self,
                                                              forKey: .personSegmentationBlurEnabled) ?? false
        sceneKeyframes = try c.decodeIfPresent([SceneLayoutKeyframe].self,
                                               forKey: .sceneKeyframes) ?? []
    }

    /// Normalized `(0...1, 0...1)` center position in top-left image space.
    var normalizedCenter: CGPoint {
        Self.normalizedCenter(for: corner)
    }

    static func normalizedCenter(for corner: RecorderCameraBubbleCorner) -> CGPoint {
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
