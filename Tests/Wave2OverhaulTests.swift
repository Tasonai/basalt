// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation

enum Wave2OverhaulContract {
    static func run(_ suite: TestSuite) {
        testRecorderEditDocumentBackwardCompatibility(suite)
        testRecorderStudioTracks(suite)
        testMetalDirectionalMotionBlur(suite)
        testSmartRedactPatternsAndLuhn(suite)
        testPixelRulerContrastSpan(suite)
        testOKLCHColorFormatting(suite)
        testDesktopIconWindowExclusion(suite)
        testRecorderInspectorHasNoSubtitleIdentifier(suite)
    }

    private static func testRecorderEditDocumentBackwardCompatibility(_ suite: TestSuite) {
        // Legacy JSON missing all Wave 2 studio keys decodes safely with clean defaults.
        let legacyJSON = Data("{\"trimStart\":1.5,\"trimEnd\":9.0,\"zoomAmount\":2.2}".utf8)
        let decodedLegacy = RecorderEditDocument.decoded(legacyJSON)
        suite.expect(decodedLegacy.trimStart == 1.5 && decodedLegacy.zoomAmount == 2.2
                     && !decodedLegacy.motionBlurEnabled
                     && !decodedLegacy.cameraBubble.isEnabled
                     && decodedLegacy.clickSFXStyle == RecorderClickSFXStyle.off.rawValue
                     && decodedLegacy.captions.isEmpty,
                     "RecorderEditDocument decodes legacy JSON with Wave 2 defaults")

        var studioDoc = RecorderEditDocument(
            motionBlurEnabled: true,
            motionBlurStrength: 1.7,
            clickSFXStyle: RecorderClickSFXStyle.mechanical.rawValue,
            cameraBubble: RecorderCameraBubbleConfig(isEnabled: true, corner: .bottomTrailing,
                                                   diameterFraction: 0.22, autoShrinkOnPointerNear: true),
            keystrokesEnabled: true,
            keystrokes: [RecorderKeystrokeEvent(timestamp: 1.25, label: "K", modifiers: ["⌘"])],
            captionsEnabled: true,
            captions: [RecorderCaptionSegment(start: 0.5, end: 2.5, text: "Hello world")]
        )
        studioDoc = studioDoc.sanitized(duration: 10)
        suite.expect(studioDoc.motionBlurStrength <= 1.0,
                     "sanitized clamps out-of-range motionBlurStrength")
        let roundTrip = RecorderEditDocument.decoded(studioDoc.encoded())
        suite.expect(roundTrip == studioDoc,
                     "RecorderEditDocument round-trips Wave 2 studio fields cleanly")
        suite.expect(studioDoc.affectsPicture(RecorderEditDocument()),
                     "Studio overlays mark affectsPicture true")
        suite.expect(studioDoc.affectsAudio(RecorderEditDocument()),
                     "Click SFX selection marks affectsAudio true")
    }

    private static func testRecorderStudioTracks(_ suite: TestSuite) {
        let bubble = RecorderCameraBubbleConfig(isEnabled: true, corner: .bottomLeading,
                                                diameterFraction: 0.20, autoShrinkOnPointerNear: true)
        let farScale = bubble.effectiveScale(pointerNormalized: CGPoint(x: 0.9, y: 0.1))
        let nearScale = bubble.effectiveScale(pointerNormalized: CGPoint(x: 0.15, y: 0.86))
        suite.expect(farScale == 1.0 && nearScale < 0.75,
                     "camera bubble auto-shrinks near pointer and stays full size away")

        let keystroke = RecorderKeystrokeEvent(timestamp: 2.0, label: "C", modifiers: ["⌘", "⇧"])
        suite.expect(keystroke.formattedCapString == "⌘⇧C",
                     "keystroke formats modifier symbols cleanly")
        suite.expect(RecorderKeystrokeEvent.activeEvents(in: [keystroke], at: 2.5).count == 1
                     && RecorderKeystrokeEvent.activeEvents(in: [keystroke], at: 5.0).isEmpty,
                     "activeEvents windows keystroke display over holdDuration")

        suite.expect(!RecorderKeystrokeCaptureGate.canRecordKeystrokes(secureInputActive: true)
                     && RecorderKeystrokeCaptureGate.canRecordKeystrokes(secureInputActive: false),
                     "keystroke gate refuses recording when macOS Secure Input is active")

        let offSamples = RecorderClickSFXStyle.synthesizeClickPCM(style: .off)
        let mechSamples = RecorderClickSFXStyle.synthesizeClickPCM(style: .mechanical, gain: 0.6)
        suite.expect(offSamples.isEmpty && !mechSamples.isEmpty
                     && mechSamples.contains(where: { abs($0) > 0.05 }),
                     "procedural click SFX produces bounded PCM impulse samples when active")

        let segments = [
            RecorderCaptionSegment(start: 1.25, end: 3.5, text: "First line"),
            RecorderCaptionSegment(start: 4.0, end: 5.5, text: "Um removed line", isCut: true),
            RecorderCaptionSegment(start: 6.0, end: 8.2, text: "Second line"),
        ]
        let srt = RecorderCaptionSegment.formatSRT(segments)
        suite.expect(srt.contains("1\n00:00:01,250 --> 00:00:03,500\nFirst line")
                     && !srt.contains("Um removed line")
                     && srt.contains("2\n00:00:06,000 --> 00:00:08,200\nSecond line"),
                     "SRT export skips cut lines and sequentially renumbers blocks")
        let cuts = RecorderCaptionSegment.cutsFromDeletedCaptions(segments)
        suite.expect(cuts.count == 1 && abs(cuts[0].start - 4.0) < 0.001 && abs(cuts[0].end - 5.5) < 0.001,
                     "deleted caption segments map to rough-cut timeline cuts")
    }

    private static func testMetalDirectionalMotionBlur(_ suite: TestSuite) {
        let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
        let input = CIImage(color: .red).cropped(to: extent)
        let out = VorssaintMetalShaders.shared.applyDirectionalMotionBlur(
            to: input,
            velocity: CGVector(dx: 12, dy: -6),
            samples: 7
        )
        suite.expect(out.extent.integral == extent,
                     "directional motion blur preserves input extent even under fallback or GPU path")
    }

    private static func testSmartRedactPatternsAndLuhn(_ suite: TestSuite) {
        let emailKinds = ScreenshotSmartRedact.detectSensitiveTokens(in: "Contact support@vorssaint.app today")
        suite.expect(emailKinds.contains(.email), "detects email addresses")

        let secretKinds = ScreenshotSmartRedact.detectSensitiveTokens(in: "OPENAI=sk-projAbCdEf1234567890abcd")
        suite.expect(secretKinds.contains(.apiSecret), "detects sk- API keys")

        let awsKinds = ScreenshotSmartRedact.detectSensitiveTokens(in: "key AKIAIOSFODNN7EXAMPLE")
        suite.expect(awsKinds.contains(.apiSecret), "detects AWS AKIA keys")

        let validCard = ScreenshotSmartRedact.detectSensitiveTokens(in: "4111 1111 1111 1111")
        let invalidCard = ScreenshotSmartRedact.detectSensitiveTokens(in: "4111 1111 1111 1112")
        suite.expect(validCard.contains(.cardNumber) && !invalidCard.contains(.cardNumber),
                     "payment card detector requires Luhn checksum pass")

        let ipKinds = ScreenshotSmartRedact.detectSensitiveTokens(in: "host 192.168.1.42 ready")
        suite.expect(ipKinds.contains(.ipAddress), "detects IPv4 addresses")
    }

    private static func testPixelRulerContrastSpan(_ suite: TestSuite) {
        // Build a 40x20 image with a dark outer frame and white 20x10 inner box at x=10..<30, y=5..<15.
        let width = 40
        let height = 20
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let inside = (10..<30).contains(x) && (5..<15).contains(y)
                let val: UInt8 = inside ? 255 : 20
                let i = (y * width + x) * 4
                rgba[i] = val; rgba[i + 1] = val; rgba[i + 2] = val; rgba[i + 3] = 255
            }
        }
        let cg = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: CGDataProvider(data: Data(rgba) as CFData)!,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        let m = ScreenshotPixelRuler.measureContrastSpan(in: cg, from: CGPoint(x: 20, y: 10))
        suite.expect(m?.width == 20 && m?.height == 10,
                     "pixel ruler measures exact inner bright rectangle bounds (\(m?.width ?? -1)x\(m?.height ?? -1))")
    }

    private static func testOKLCHColorFormatting(_ suite: TestSuite) {
        let white = ColorValue.string(red: 1, green: 1, blue: 1, format: .oklch)
        let black = ColorValue.string(red: 0, green: 0, blue: 0, format: .oklch)
        let redAlpha = ColorValue.string(red: 1, green: 0, blue: 0, alpha: 0.5, format: .oklch)
        suite.expect(white.hasPrefix("oklch(100.0% 0.000 "),
                     "OKLCH formats white lightness at 100%")
        suite.expect(black.hasPrefix("oklch(0.0% 0.000 "),
                     "OKLCH formats black lightness at 0%")
        suite.expect(redAlpha.hasPrefix("oklch(62.") && redAlpha.contains("/ 0.5)"),
                     "OKLCH includes alpha channel when non-nil: \(redAlpha)")
        suite.expect(ColorCopyFormat.sanitized("oklch") == .oklch,
                     "ColorCopyFormat recognizes oklch")
        suite.expect(CommandBarColors.convert("#FF0000 to oklch")?.formatted.hasPrefix("oklch(") == true,
                     "CommandBarColors converts to oklch")
    }

    private static func testDesktopIconWindowExclusion(_ suite: TestSuite) {
        let iconLayer = Int(CGWindowLevelForKey(.desktopIconWindow))
        let wallLayer = Int(CGWindowLevelForKey(.desktopWindow))
        let windows: [(id: CGWindowID, ownerBundleID: String?, layer: Int)] = [
            (id: 101, ownerBundleID: "com.apple.finder", layer: iconLayer),
            (id: 102, ownerBundleID: "com.apple.finder", layer: wallLayer),
            (id: 103, ownerBundleID: "com.apple.finder", layer: 0),
            (id: 104, ownerBundleID: "com.apple.Safari", layer: iconLayer),
        ]
        let excluded = ScreenshotCapturePolicy.desktopIconWindowIDs(in: windows)
        suite.expect(excluded == Set([101]),
                     "desktop icon masking targets Finder desktop-icon layer without touching wallpaper or normal windows")
    }

    private static func testRecorderInspectorHasNoSubtitleIdentifier(_ suite: TestSuite) {
        let inspector = (try? String(contentsOfFile: "Sources/Vorssaint/UI/Recorder/RecorderInspector.swift",
                                     encoding: .utf8)) ?? ""
        suite.expect(!inspector.isEmpty && !inspector.contains("subtitle"),
                     "RecorderInspector preserves forbidden-identifier contract from ScreenshotFeatureTests")
    }
}
