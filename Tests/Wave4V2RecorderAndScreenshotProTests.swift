// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum Wave4V2RecorderAndScreenshotProContract {
    static func run(_ suite: TestSuite) {
        testS3SigV4AndCloudURLHelper(suite)
        testScreenshotPinProAndCounters(suite)
        testRecorderStudioProExtensions(suite)
        testWave4SourceWiring(suite)
    }

    private static func readRepo(_ path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    private static func testS3SigV4AndCloudURLHelper(_ suite: TestSuite) {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14T22:13:20Z
        let targetURL = URL(string: "https://account.r2.cloudflarestorage.com/shots/capture%201.png")!
        let payload = Data([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3, 4])

        let reqA = S3SigV4Signer.signedPutRequest(
            url: targetURL,
            payload: payload,
            accessKeyID: "AKIAIOSFODNN7EXAMPLE",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            region: "auto",
            date: fixedDate
        )
        let reqB = S3SigV4Signer.signedPutRequest(
            url: targetURL,
            payload: payload,
            accessKeyID: "AKIAIOSFODNN7EXAMPLE",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            region: "auto",
            date: fixedDate
        )
        let authA = reqA.value(forHTTPHeaderField: "Authorization") ?? ""
        let authB = reqB.value(forHTTPHeaderField: "Authorization") ?? ""
        suite.expect(authA == authB
                     && authA.hasPrefix("AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20231114/auto/s3/aws4_request")
                     && reqA.value(forHTTPHeaderField: "x-amz-content-sha256") == S3SigV4Signer.sha256Hex(payload)
                     && reqA.value(forHTTPHeaderField: "x-amz-date") == "20231114T221320Z",
                     "S3SigV4Signer produces deterministic AWS4-HMAC-SHA256 headers for R2/S3 PUT")

        let secretStore = InMemoryScreenshotCloudSecretStore()
        suite.expect(secretStore.saveSecret("top-secret-key", account: "s3SecretAccessKey")
                     && secretStore.loadSecret(account: "s3SecretAccessKey") == "top-secret-key"
                     && secretStore.deleteSecret(account: "s3SecretAccessKey")
                     && secretStore.loadSecret(account: "s3SecretAccessKey") == nil,
                     "ScreenshotCloudSecretStore saves, reads, and deletes credentials cleanly")

        let jsonNested = Data(#"{"data":{"result":{"link":"https://cdn.example.com/shots/demo.png"}}}"#.utf8)
        let jsonUnsafe = Data(#"{"url":"javascript:alert(1)"}"#.utf8)
        suite.expect(ScreenshotCloudURLHelper.extractURL(fromJSON: jsonNested, keyPath: "data.result.link")?.absoluteString == "https://cdn.example.com/shots/demo.png"
                     && ScreenshotCloudURLHelper.extractURL(fromJSON: jsonUnsafe, keyPath: "url") == nil,
                     "ScreenshotCloudURLHelper resolves dot-separated JSON keypaths and blocks non-HTTP URLs")
    }

    private static func testScreenshotPinProAndCounters(_ suite: TestSuite) {
        suite.expect(abs(ScreenshotPinOpacityMath.clampedOpacity(0.01) - 0.20) < 0.001
                     && abs(ScreenshotPinOpacityMath.clampedOpacity(1.5) - 1.0) < 0.001
                     && abs(ScreenshotPinOpacityMath.clampedOpacity(.nan) - 1.0) < 0.001,
                     "ScreenshotPinWindow clamps scroll opacity safely between 0.20 and 1.0")

        suite.expect(ScreenshotCounterBadgeStyle.numeric.formattedLabel(for: 3) == "3"
                     && ScreenshotCounterBadgeStyle.alphabetic.formattedLabel(for: 1) == "A"
                     && ScreenshotCounterBadgeStyle.alphabetic.formattedLabel(for: 27) == "AA",
                     "ScreenshotCounterBadgeStyle formats numeric and alphabetic step badges accurately")
    }

    private static func testRecorderStudioProExtensions(_ suite: TestSuite) {
        let legacyJSON = Data(#"{"trimStart":0.5,"trimEnd":4.0,"zoomAmount":2.0}"#.utf8)
        let legacyDoc = RecorderEditDocument.decoded(legacyJSON)
        suite.expect(!legacyDoc.perspectiveTiltEnabled
                     && !legacyDoc.ambientGlowEnabled
                     && !legacyDoc.exportsProRes4444,
                     "RecorderEditDocument decodes legacy JSON with Wave 4 Studio defaults false")

        var studioDoc = RecorderEditDocument(
            clickSFXStyle: RecorderClickSFXStyle.mechanical.rawValue,
            perspectiveTiltEnabled: true,
            ambientGlowEnabled: true,
            exportsProRes4444: true
        )
        studioDoc = studioDoc.sanitized(duration: 12)
        let roundTrip = RecorderEditDocument.decoded(studioDoc.encoded())
        suite.expect(roundTrip == studioDoc
                     && studioDoc.affectsPicture(RecorderEditDocument()),
                     "RecorderEditDocument round-trips perspectiveTilt, ambientGlow, and ProRes 4444")

        suite.expect(!RecorderKeystrokeCaptureGate.canRecordKeystrokes(secureInputActive: true)
                     && RecorderKeystrokeCaptureGate.canRecordKeystrokes(secureInputActive: false),
                     "RecorderKeystrokeCaptureGate suppresses capture while Secure Input is active")

        let clickPCM = RecorderClickSFXStyle.synthesizeClickPCM(style: .mechanical, gain: 0.7)
        suite.expect(!clickPCM.isEmpty && clickPCM.allSatisfy { $0.isFinite && abs($0) <= 1.0 },
                     "RecorderClickSFXStyle synthesizes bounded finite PCM impulse samples")
    }

    private static func testWave4SourceWiring(_ suite: TestSuite) {
        let cameraCap = readRepo("Sources/Vorssaint/Services/Recorder/RecorderCameraCapture.swift")
        let keySampler = readRepo("Sources/Vorssaint/Services/Recorder/RecorderKeystrokeSampler.swift")
        let composer = readRepo("Sources/Vorssaint/Services/Recorder/RecorderComposer.swift")
        let composition = readRepo("Sources/Vorssaint/Services/Recorder/RecorderComposition.swift")
        let exporter = readRepo("Sources/Vorssaint/Services/Recorder/RecorderExporter.swift")
        let timeline = readRepo("Sources/Vorssaint/UI/Recorder/RecorderMultiTrackTimelineView.swift")
        let inspector = readRepo("Sources/Vorssaint/UI/Recorder/RecorderInspector.swift")
        let pinCtrl = readRepo("Sources/Vorssaint/Services/QuickTools/ScreenshotPinController.swift")
        let settings = readRepo("Sources/Vorssaint/UI/Settings/ScreenshotSettings.swift")

        suite.expect(cameraCap.contains("AVCaptureSession") && cameraCap.contains("AVCaptureMovieFileOutput"),
                     "RecorderCameraCapture uses AVCaptureSession + AVCaptureMovieFileOutput")
        suite.expect(keySampler.contains("IsSecureEventInputEnabled()")
                     && composer.contains("CameraFrameSampler")
                     && composer.contains("CIPerspectiveTransform"),
                     "RecorderKeystrokeSampler gates on Secure Input and RecorderComposer renders live camera + perspective")
        suite.expect(composition.contains("attachClickSFXTrack")
                     && exporter.contains("proRes4444"),
                     "RecorderComposition mixes Click SFX WAV and RecorderExporter supports ProRes 4444")
        suite.expect(timeline.contains("KeystrokeTimelineLane")
                     && timeline.contains("ClickSFXTimelineLane")
                     && !inspector.contains("subtitle"),
                     "RecorderMultiTrackTimelineView exposes studio tracks and RecorderInspector avoids 'subtitle'")
        suite.expect(pinCtrl.contains("scrollWheel(with")
                     && pinCtrl.contains("toggleCollapsedPill()")
                     && settings.contains("cloudUploadCard"),
                     "ScreenshotPinController and ScreenshotSettings wire Pin Pro and Cloud Upload UI")
    }
}
