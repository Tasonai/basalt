// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum Wave6V3StudioAndScreenshot3Contract {
    static func run(_ suite: TestSuite) {
        testRecorderStudioModelsAndMath(suite)
        testScreenshotSmartGuidesAndSocialPresets(suite)
        testRecorderAndScreenshotUIContracts(suite)
    }

    private static func testRecorderStudioModelsAndMath(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let kf0 = SceneLayoutKeyframe(id: UUID(), timeSeconds: 0, shape: .circle, cornerIndex: 3, scale: 1.0)
        let kf1 = SceneLayoutKeyframe(id: UUID(), timeSeconds: 4.5, shape: .verticalPortrait, cornerIndex: 1, scale: 1.15)
        let kf2 = SceneLayoutKeyframe(id: UUID(), timeSeconds: 9.0, shape: .hidden, cornerIndex: 3, scale: 1.0)
        let keyframes = [kf2, kf0, kf1]

        suite.expect(SceneLayoutKeyframe.activeShape(at: 2.0, keyframes: keyframes, defaultShape: .squircle) == .circle
                     && SceneLayoutKeyframe.activeShape(at: 6.0, keyframes: keyframes, defaultShape: .squircle) == .verticalPortrait
                     && SceneLayoutKeyframe.activeShape(at: 11.0, keyframes: keyframes, defaultShape: .squircle) == .hidden,
                     "SceneLayoutKeyframe resolves chronologically across unsorted keyframes")

        let source = CGSize(width: 1920, height: 1080)
        let portraitSize = StudioOutputAspect.vertical9x16.targetCanvasSize(sourceSize: source)
        let crop = StudioOutputAspect.vertical9x16.cursorReframeCropRect(
            sourceSize: source,
            normalizedCursor: CGPoint(x: 0.95, y: 0.15)
        )
        suite.expect(abs(portraitSize.width / portraitSize.height - (9.0 / 16.0)) < 0.02
                     && crop.minX >= 0 && crop.maxX <= source.width + 0.01
                     && crop.minY >= 0 && crop.maxY <= source.height + 0.01,
                     "StudioOutputAspect 9:16 computes vertical dimensions and clamps cursor reframe crop inside frame")

        let tiltFlat = PerspectiveTiltSample.cursorPerspectiveTilt(normalizedCursor: CGPoint(x: 1, y: 0), enabled: false)
        let tiltRight = PerspectiveTiltSample.cursorPerspectiveTilt(normalizedCursor: CGPoint(x: 1, y: 0.5), maxAngleDegrees: 8, enabled: true)
        suite.expect(tiltFlat.pitchDegrees == 0 && tiltFlat.yawDegrees == 0
                     && abs(tiltRight.yawDegrees) > 1.0 && abs(tiltRight.yawDegrees) <= 8.01,
                     "PerspectiveTiltSample clamps 3D tilt angles when enabled and returns zero when disabled")

        let whisperJSON = """
        {
          "transcription": [
            {
              "tokens": [
                {"text": "Hello", "offsets": {"from": 100, "to": 450}},
                {"text": " world", "offsets": {"from": 460, "to": 900}}
              ]
            }
          ],
          "createdAt": "\(now.timeIntervalSince1970)"
        }
        """.data(using: .utf8) ?? Data()
        let words = WhisperCLITranscriptParser.parseWhisperJSON(whisperJSON)
        suite.expect(words.count == 2
                     && words[0].word == "Hello"
                     && words[1].word == "world"
                     && WhisperCLITranscriptParser.activeWordIndex(at: 0.65, tokens: words) == 1,
                     "WhisperCLITranscriptParser parses whisper-cli JSON word tokens and highlights active timestamp")

        let ducked = AudioAutoDuckingMath.systemGainLinear(micRMS: 0.12, thresholdRMS: 0.025, duckedDB: -12.0, enabled: true)
        let unducked = AudioAutoDuckingMath.systemGainLinear(micRMS: 0.005, thresholdRMS: 0.025, duckedDB: -12.0, enabled: true)
        suite.expect(ducked < 0.35 && ducked > 0.15 && abs(unducked - 1.0) < 0.001,
                     "AudioAutoDuckingMath attenuates system gain cleanly when mic RMS exceeds threshold")
    }

    private static func testScreenshotSmartGuidesAndSocialPresets(_ suite: TestSuite) {
        let canvas = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let peer = CGRect(x: 100, y: 200, width: 160, height: 80)
        let moving = CGRect(x: 102.5, y: 398, width: 140, height: 60)
        let snapped = ScreenshotSmartGuides.snap(moving: moving, peers: [peer], canvas: canvas, threshold: 4.0)

        suite.expect(abs(snapped.rect.minX - 100) < 0.01 && !snapped.guides.isEmpty,
                     "ScreenshotSmartGuides snaps moving annotation edge within 4px threshold and emits guides")

        let xPost = SocialExportFramePreset.xPost1600x900.targetPixelSize(for: 1600)
        let linkedIn = SocialExportFramePreset.linkedIn1200x627.targetPixelSize(for: 1200)
        suite.expect(abs(xPost.width - 1600) < 1 && abs(xPost.height - 900) < 1
                     && abs(linkedIn.width - 1200) < 1 && abs(linkedIn.height - 627) < 1,
                     "SocialExportFramePreset computes exact X and LinkedIn export frame dimensions")

        let entry = CloudUploadHistoryEntry(
            id: UUID(),
            filename: "shot.png",
            publicURL: "https://cdn.example.com/shot.png",
            objectKey: "uploads/shot.png",
            uploadedAt: Date(),
            isDeletedRemotely: false
        )
        let deleteURL = URL(string: "https://s3.us-east-1.amazonaws.com/vorssaint-shots/\(entry.objectKey)")!
        let req = S3SigV4Signer.signedDeleteRequest(
            url: deleteURL,
            accessKeyID: "AKIAEXAMPLE12345",
            secretAccessKey: "secret-key-example-67890",
            region: "us-east-1"
        )
        suite.expect(req.httpMethod == "DELETE"
                     && req.value(forHTTPHeaderField: "Authorization")?.contains("AWS4-HMAC-SHA256") == true,
                     "S3SigV4Signer signs AWS4-HMAC-SHA256 DELETE request for remote revocation")
    }

    private static func testRecorderAndScreenshotUIContracts(_ suite: TestSuite) {
        let composer = (try? String(contentsOfFile: "Sources/Vorssaint/Services/Recorder/RecorderComposer.swift", encoding: .utf8)) ?? ""
        let inspector = (try? String(contentsOfFile: "Sources/Vorssaint/UI/Recorder/RecorderInspector.swift", encoding: .utf8)) ?? ""
        let shotEditor = (try? String(contentsOfFile: "Sources/Vorssaint/UI/Screenshot/ScreenshotEditorView.swift", encoding: .utf8)) ?? ""
        let shotSettings = (try? String(contentsOfFile: "Sources/Vorssaint/UI/Settings/ScreenshotSettings.swift", encoding: .utf8)) ?? ""

        suite.expect(composer.contains("VNGeneratePersonSegmentationRequest")
                     && composer.contains("AudioAutoDuckingMath"),
                     "RecorderComposer integrates Vision person segmentation blur and mic auto-ducking")

        suite.expect(inspector.contains("OverhaulV3Strings.recorderCameraShapeTitle")
                     && inspector.contains("OverhaulV3Strings.recorderPersonBlurToggle")
                     && inspector.contains("OverhaulV3Strings.recorderTilt3DToggle")
                     && inspector.contains("OverhaulV3Strings.recorderAspectTitle")
                     && inspector.contains("OverhaulV3Strings.recorderMicDuckingToggle")
                     && !inspector.contains(".toggleStyle(.switch)")
                     && !inspector.contains(".toggleStyle(.checkbox)"),
                     "RecorderInspector exposes Wave 6 Studio 3.0 controls using VorssaintDesignKit")

        suite.expect(shotEditor.contains("OverhaulV3Strings.screenshotSocialFramesTitle")
                     && shotEditor.contains("OverhaulV3Strings.screenshotSmartGuidesToggle")
                     && shotEditor.contains("Slider(value:")
                     && !shotEditor.contains(".toggleStyle(.switch)")
                     && !shotEditor.contains(".toggleStyle(.checkbox)"),
                     "ScreenshotEditorView wires social export presets and magnetic Smart Guides while preserving locked spotlight Slider")

        suite.expect(shotSettings.contains("OverhaulV3Strings.screenshotCloudHistoryTitle")
                     && shotSettings.contains("OverhaulV3Strings.screenshotCloudDeleteAction")
                     && !shotSettings.contains(".toggleStyle(.switch)")
                     && !shotSettings.contains(".toggleStyle(.checkbox)"),
                     "ScreenshotSettings exposes Cloud Upload History with remote delete and VorssaintDesignKit")
    }
}
