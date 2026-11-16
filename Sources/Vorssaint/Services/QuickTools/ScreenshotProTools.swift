// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation
import Vision

/// On-device smart PII/secret redaction and optical pixel-edge measurement
/// utilities for the Screenshot Pro editor and magnifier.
enum ScreenshotSmartRedact {
    enum RedactKind: String, CaseIterable, Sendable {
        case email
        case cardNumber
        case apiSecret
        case ipAddress
        case phone
        case face
    }

    struct RedactMatch: Equatable, Sendable {
        let kind: RedactKind
        /// Top-left image pixel coordinates matching ScreenshotSupport.Annotation rects.
        let rect: CGRect
        let previewLabel: String
    }

    /// Scans recognized text lines for PII/credentials using regex + Luhn validation.
    static func detectSensitiveTokens(in text: String) -> [RedactKind] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var found: [RedactKind] = []

        if matchesRegex(#"[A-Z0-9a-z._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#, in: trimmed) {
            found.append(.email)
        }
        if containsValidPaymentCard(in: trimmed) {
            found.append(.cardNumber)
        }
        if matchesRegex(#"(?:sk-[A-Za-z0-9_\-]{16,}|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_\-]{30,}|AKIA[0-9A-Z]{16}|eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{5,})"#, in: trimmed) {
            found.append(.apiSecret)
        }
        if matchesRegex(#"\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b"#, in: trimmed) {
            found.append(.ipAddress)
        }
        if matchesRegex(#"(?:\+\d{1,3}[\s\-]?)?(?:\(\d{2,4}\)[\s\-]?|\d{3}[\s\-])\d{3}[\s\-]\d{2,4}\b"#, in: trimmed) {
            found.append(.phone)
        }
        return found
    }

    /// Runs Vision text + face detection on `image` and returns image-space pixel
    /// rectangles (top-left origin) for sensitive content and faces.
    static func detectRegions(in image: CGImage) -> [RedactMatch] {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        guard width > 0, height > 0 else { return [] }

        var matches: [RedactMatch] = []
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = false

        let faceRequest = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([textRequest, faceRequest])

        for observation in textRequest.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let kinds = detectSensitiveTokens(in: candidate.string)
            guard let firstKind = kinds.first else { continue }
            let pixelRect = topLeftPixelRect(fromVisionBox: observation.boundingBox,
                                             imageSize: CGSize(width: width, height: height))
                .insetBy(dx: -4, dy: -3)
            matches.append(RedactMatch(kind: firstKind,
                                       rect: pixelRect.intersection(CGRect(x: 0, y: 0, width: width, height: height)),
                                       previewLabel: firstKind.rawValue))
        }

        for face in faceRequest.results ?? [] {
            let pixelRect = topLeftPixelRect(fromVisionBox: face.boundingBox,
                                             imageSize: CGSize(width: width, height: height))
                .insetBy(dx: -4, dy: -4)
            matches.append(RedactMatch(kind: .face,
                                       rect: pixelRect.intersection(CGRect(x: 0, y: 0, width: width, height: height)),
                                       previewLabel: RedactKind.face.rawValue))
        }
        return matches
    }

    private static func topLeftPixelRect(fromVisionBox box: CGRect, imageSize: CGSize) -> CGRect {
        let x = box.minX * imageSize.width
        let y = (1 - box.maxY) * imageSize.height
        return CGRect(x: x,
                      y: y,
                      width: box.width * imageSize.width,
                      height: box.height * imageSize.height)
    }

    private static func matchesRegex(_ pattern: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private static func containsValidPaymentCard(in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"\b(?:\d[\s\-]?){13,19}\b"#) else {
            return false
        }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        for match in regex.matches(in: text, options: [], range: range) {
            let digits = ns.substring(with: match.range).filter(\.isNumber)
            guard (13...19).contains(digits.count), passesLuhn(digits) else { continue }
            return true
        }
        return false
    }

    static func passesLuhn(_ digits: String) -> Bool {
        let numbers = digits.compactMap(\.wholeNumberValue)
        guard numbers.count == digits.count, numbers.count >= 13 else { return false }
        var sum = 0
        for (offset, digit) in numbers.reversed().enumerated() {
            if offset.isMultiple(of: 2) {
                sum += digit
            } else {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            }
        }
        return sum % 10 == 0
    }
}

/// Raycasts 4 orthogonal directions from a point in a `CGImage` until pixel
/// luminance jumps across UI element boundaries, measuring exact pixel spans.
enum ScreenshotPixelRuler {
    struct Measurement: Equatable, Sendable {
        let origin: CGPoint
        let leftEdgeX: Int
        let rightEdgeX: Int
        let topEdgeY: Int
        let bottomEdgeY: Int

        var width: Int { max(0, rightEdgeX - leftEdgeX) }
        var height: Int { max(0, bottomEdgeY - topEdgeY) }
    }

    static func measureContrastSpan(in image: CGImage,
                                    from point: CGPoint,
                                    luminanceThreshold: Double = 0.12) -> Measurement? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        let startX = min(max(0, Int(point.x.rounded())), width - 1)
        let startY = min(max(0, Int(point.y.rounded())), height - 1)

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(data: &rgba,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: width * 4,
                                  space: space,
                                  bitmapInfo: bitmapInfo)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        func luminance(x: Int, y: Int) -> Double {
            let offset = (y * width + x) * 4
            let r = Double(rgba[offset]) / 255.0
            let g = Double(rgba[offset + 1]) / 255.0
            let b = Double(rgba[offset + 2]) / 255.0
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }

        let originLum = luminance(x: startX, y: startY)
        let threshold = max(0.02, luminanceThreshold)

        var leftX = startX
        while leftX > 0 && abs(luminance(x: leftX - 1, y: startY) - originLum) < threshold {
            leftX -= 1
        }
        var rightX = startX + 1
        while rightX < width && abs(luminance(x: rightX, y: startY) - originLum) < threshold {
            rightX += 1
        }
        var topY = startY
        while topY > 0 && abs(luminance(x: startX, y: topY - 1) - originLum) < threshold {
            topY -= 1
        }
        var bottomY = startY + 1
        while bottomY < height && abs(luminance(x: startX, y: bottomY) - originLum) < threshold {
            bottomY += 1
        }

        return Measurement(origin: CGPoint(x: startX, y: startY),
                           leftEdgeX: leftX,
                           rightEdgeX: rightX,
                           topEdgeY: topY,
                           bottomEdgeY: bottomY)
    }
}

/// Formatting style for sequential step counter annotations (`1, 2, 3` or `A, B, C`).
enum ScreenshotCounterBadgeStyle: String, CaseIterable, Codable, Sendable {
    case numeric
    case alphabetic

    static func sanitized(_ raw: String?) -> ScreenshotCounterBadgeStyle {
        ScreenshotCounterBadgeStyle(rawValue: raw ?? "") ?? .numeric
    }

    /// Formats a 1-based counter index (`1 -> "1"` / `"A"`, `27 -> "27"` / `"AA"`).
    func formattedLabel(for number: Int) -> String {
        let positive = max(1, number)
        switch self {
        case .numeric:
            return "\(positive)"
        case .alphabetic:
            var value = positive
            var scalars: [UnicodeScalar] = []
            while value > 0 {
                let remainder = (value - 1) % 26
                if let scalar = UnicodeScalar(65 + remainder) {
                    scalars.append(scalar)
                }
                value = (value - 1) / 26
            }
            return String(String.UnicodeScalarView(scalars.reversed()))
        }
    }

    var symbolName: String {
        switch self {
        case .numeric: return "1.circle"
        case .alphabetic: return "a.circle"
        }
    }
}

/// Social media and presentation canvas aspect ratio presets for Screenshot Pro 3.0 export.
enum SocialExportFramePreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case widescreen16x9
    case classic4x3
    case square1x1
    case story9x16
    case xPost1600x900
    case linkedIn1200x627

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .widescreen16x9: return "16:9 Widescreen"
        case .classic4x3: return "4:3 Classic"
        case .square1x1: return "1:1 Square"
        case .story9x16: return "9:16 Story"
        case .xPost1600x900: return "X Post (1600×900)"
        case .linkedIn1200x627: return "LinkedIn (1200×627)"
        }
    }

    var aspectRatio: CGFloat {
        switch self {
        case .widescreen16x9: return 16.0 / 9.0
        case .classic4x3: return 4.0 / 3.0
        case .square1x1: return 1.0
        case .story9x16: return 9.0 / 16.0
        case .xPost1600x900: return 1600.0 / 900.0
        case .linkedIn1200x627: return 1200.0 / 627.0
        }
    }

    /// Computes finite, integral pixel dimensions for the given base width.
    func targetPixelSize(for baseWidth: CGFloat) -> CGSize {
        let defaultWidth: CGFloat = switch self {
        case .xPost1600x900: 1600
        case .linkedIn1200x627: 1200
        default: 1200
        }
        let safeWidth = (baseWidth.isFinite && baseWidth > 0) ? max(1, baseWidth.rounded()) : defaultWidth
        switch self {
        case .xPost1600x900 where Int(safeWidth) == 1600:
            return CGSize(width: 1600, height: 900)
        case .linkedIn1200x627 where Int(safeWidth) == 1200:
            return CGSize(width: 1200, height: 627)
        default:
            let safeHeight = max(1, (safeWidth / aspectRatio).rounded())
            return CGSize(width: safeWidth, height: safeHeight)
        }
    }

    /// Computes the smallest integral canvas size matching `aspectRatio` that fully encloses `contentSize`.
    func fittedCanvasSize(for contentSize: CGSize) -> CGSize {
        let width = contentSize.width.isFinite ? max(1, contentSize.width.rounded()) : 1
        let height = contentSize.height.isFinite ? max(1, contentSize.height.rounded()) : 1
        let ratio = aspectRatio
        guard ratio.isFinite, ratio > 0 else {
            return CGSize(width: width, height: height)
        }
        if width / height < ratio {
            return CGSize(width: max(width, (height * ratio).rounded()), height: height)
        } else {
            return CGSize(width: width, height: max(height, (width / ratio).rounded()))
        }
    }
}

/// Alignment guide emitted by magnetic Smart Guides during annotation drags.
struct SmartGuideLine: Equatable, Sendable {
    enum Axis: String, Sendable {
        case vertical
        case horizontal
    }

    let axis: Axis
    let position: CGFloat
}

/// Resulting snapped rectangle and active guide lines from `ScreenshotSmartGuides.snap`.
struct SmartSnapResult: Equatable, Sendable {
    let rect: CGRect
    let guides: [SmartGuideLine]
}

/// Magnetic edge and center snapping against peer annotations and canvas centerlines.
enum ScreenshotSmartGuides {
    static func snap(moving: CGRect,
                     peers: [CGRect],
                     canvas: CGRect,
                     threshold: CGFloat = 4.0) -> SmartSnapResult {
        let m = moving.standardized
        let c = canvas.standardized
        guard threshold.isFinite, threshold > 0,
              m.origin.x.isFinite, m.origin.y.isFinite,
              m.width.isFinite, m.height.isFinite else {
            return SmartSnapResult(rect: m, guides: [])
        }

        var xTargets: [CGFloat] = []
        var yTargets: [CGFloat] = []
        if c.width > 0, c.midX.isFinite {
            xTargets.append(c.midX)
        }
        if c.height > 0, c.midY.isFinite {
            yTargets.append(c.midY)
        }
        for peer in peers {
            let p = peer.standardized
            guard p.origin.x.isFinite, p.origin.y.isFinite,
                  p.width.isFinite, p.height.isFinite else { continue }
            xTargets.append(contentsOf: [p.minX, p.midX, p.maxX])
            yTargets.append(contentsOf: [p.minY, p.midY, p.maxY])
        }

        let snappedX = bestSnapOffset(
            anchors: [m.minX, m.midX, m.maxX],
            targets: xTargets,
            threshold: threshold
        )
        let snappedY = bestSnapOffset(
            anchors: [m.minY, m.midY, m.maxY],
            targets: yTargets,
            threshold: threshold
        )

        let resultRect = CGRect(
            x: m.origin.x + (snappedX ?? 0),
            y: m.origin.y + (snappedY ?? 0),
            width: m.width,
            height: m.height
        )

        var guides: [SmartGuideLine] = []
        if snappedX != nil {
            let finalXAnchors = [resultRect.minX, resultRect.midX, resultRect.maxX]
            for target in xTargets where finalXAnchors.contains(where: { abs($0 - target) < 0.01 }) {
                appendUniqueGuide(SmartGuideLine(axis: .vertical, position: target), to: &guides)
            }
        }
        if snappedY != nil {
            let finalYAnchors = [resultRect.minY, resultRect.midY, resultRect.maxY]
            for target in yTargets where finalYAnchors.contains(where: { abs($0 - target) < 0.01 }) {
                appendUniqueGuide(SmartGuideLine(axis: .horizontal, position: target), to: &guides)
            }
        }
        return SmartSnapResult(rect: resultRect, guides: guides)
    }

    private static func bestSnapOffset(anchors: [CGFloat],
                                       targets: [CGFloat],
                                       threshold: CGFloat) -> CGFloat? {
        var bestDelta: CGFloat?
        var bestDistance = threshold + .ulpOfOne
        for anchor in anchors {
            for target in targets {
                let delta = target - anchor
                let distance = abs(delta)
                if distance <= threshold, distance < bestDistance {
                    bestDistance = distance
                    bestDelta = delta
                }
            }
        }
        return bestDelta
    }

    private static func appendUniqueGuide(_ guide: SmartGuideLine, to guides: inout [SmartGuideLine]) {
        let alreadyPresent = guides.contains {
            $0.axis == guide.axis && abs($0.position - guide.position) < 0.01
        }
        if !alreadyPresent {
            guides.append(guide)
        }
    }
}

/// Persisted record for a cloud-uploaded screenshot supporting 1-click copy and remote deletion.
struct CloudUploadHistoryEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let filename: String
    let publicURL: String
    let objectKey: String
    let uploadedAt: Date
    var isDeletedRemotely: Bool

    init(id: UUID = UUID(),
         filename: String,
         publicURL: String,
         objectKey: String,
         uploadedAt: Date = Date(),
         isDeletedRemotely: Bool = false) {
        self.id = id
        self.filename = filename
        self.publicURL = publicURL
        self.objectKey = objectKey
        self.uploadedAt = uploadedAt
        self.isDeletedRemotely = isDeletedRemotely
    }
}
