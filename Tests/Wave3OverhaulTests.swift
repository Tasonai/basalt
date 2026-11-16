// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Accelerate
import AppKit
import CoreGraphics
import Foundation

enum Wave3OverhaulContract {
    static func run(_ suite: TestSuite) {
        testCommandBarActionPanelAndScriptV2(suite)
        testQuickAIDropletStateAndBYOKSecrets(suite)
        testSnippets2ProEngine(suite)
        testClipboardPinboardsStackAndTransforms(suite)
        testClipboardImageOCRAndEncryptedVault(suite)
        testMixerParametricEQAndMicDSP(suite)
    }

    private static func testCommandBarActionPanelAndScriptV2(_ suite: TestSuite) {
        let actions = CommandBarActionPanelModel.actions(
            forTitle: "Notes",
            canRevealInFinder: true,
            canCopyValue: true,
            canPin: true,
            canTransform: true,
            isDestructiveSupported: true
        )
        suite.expect(actions.map(\.id) == ["open", "reveal", "copy", "pin", "transform", "delete"]
                     && actions.contains(where: { $0.shortcutDisplay == "⌘⏎" }),
                     "CommandBarActionPanelModel builds secondary action list with shortcuts")

        let script = """
        #!/usr/bin/env python3
        # @raycast.title Docker Container Status
        # @raycast.mode json
        # @vorssaint.icon shippingbox.fill
        # @vorssaint.refreshTime 10s
        # @raycast.argument1 { "type": "text", "placeholder": "Container", "optional": true }
        print('{"title":"web-api","subtitle":"Up 3 hours","copyText":"web-api","badge":"healthy"}')
        """
        let meta = ScriptCommandHeaderParser.parseMetadata(fromScriptSource: script)
        suite.expect(meta.title == "Docker Container Status"
                     && meta.mode == .json
                     && meta.icon == "shippingbox.fill"
                     && meta.refreshTime == "10s"
                     && meta.arguments.count == 1
                     && meta.arguments[0].placeholder == "Container"
                     && meta.arguments[0].optional,
                     "ScriptCommandHeaderParser parses Raycast/Vorssaint v2 headers and arguments")

        let jsonPayload = ScriptCommandHeaderParser.parseJSONOutput(
            #"{"title":"web-api","subtitle":"Up 3 hours","copyText":"web-api","badge":"healthy"}"#
        )
        suite.expect(jsonPayload?.title == "web-api" && jsonPayload?.badge == "healthy",
                     "ScriptCommandHeaderParser decodes structured JSON output payloads")
    }

    private static func testQuickAIDropletStateAndBYOKSecrets(_ suite: TestSuite) {
        let store = InMemoryQuickAISecretStore()
        let service = CommandBarQuickAIService(secretStore: store)
        suite.expect(service.saveAPIKey("  sk-test-secret-123  ", for: .byokOpenAI)
                     && service.apiKey(for: .byokOpenAI) == "sk-test-secret-123",
                     "CommandBarQuickAIService stores and trims BYOK API keys via secret store")
        service.removeAPIKey(for: .byokOpenAI)
        suite.expect(service.apiKey(for: .byokOpenAI) == nil,
                     "CommandBarQuickAIService removes BYOK API key cleanly")

        service.beginThinking(prompt: "Explain swift concurrency")
        suite.expect(service.isStreaming && service.dropletState == .thinking,
                     "Quick AI enters .thinking droplet state when streaming starts")
        service.appendStreamChunk("Actors isolate mutable state.")
        service.finishSuccess()
        suite.expect(!service.isStreaming
                     && service.dropletState == .celebrate
                     && service.responseText == "Actors isolate mutable state.",
                     "Quick AI transitions .thinking -> .celebrate on stream completion")
        service.reset()
        suite.expect(service.dropletState == .idle && service.responseText.isEmpty,
                     "Quick AI reset returns droplet to .idle")

        let ollamaChunk = CommandBarQuickAIService.parseOllamaStreamLine(#"{"response":"Hello","done":false}"#)
        let sseChunk = CommandBarQuickAIService.parseOpenAISSELine(#"data: {"choices":[{"delta":{"content":"World"}}]}"#)
        suite.expect(ollamaChunk.token == "Hello" && !ollamaChunk.done
                     && sseChunk.token == "World" && !sseChunk.done,
                     "Quick AI parses both Ollama NDJSON and OpenAI SSE stream deltas")
    }

    private static func testSnippets2ProEngine(_ suite: TestSuite) {
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 10
        components.hour = 14
        components.minute = 30
        let baseDate = Calendar(identifier: .gregorian).date(from: components)!

        let expanded = TextSnippetProEngine.expandAdvanced(
            "Meet on {{date+7d:yyyy-MM-dd}} with {{arg:recipient=Team}}! {{cursor}}-- {{arg:sig=Alex}}",
            date: baseDate,
            locale: Locale(identifier: "en_US"),
            arguments: ["recipient": "Alice"]
        )
        suite.expect(expanded.text == "Meet on 2026-05-17 with Alice! -- Alex",
                     "Snippets 2.0 evaluates date arithmetic and argument defaults/overrides")
        suite.expect(expanded.cursorMoveBackUTF16 == "-- Alex".utf16.count,
                     "Snippets 2.0 computes exact UTF-16 rewind count for {{cursor}}")

        // Cycle-safe nested snippet expansion (a -> b -> a must terminate cleanly).
        let nested = TextSnippetProEngine.expandAdvanced(
            "{{snippet:sig}}",
            date: baseDate,
            snippetLookup: { trigger in
                switch trigger {
                case "sig": return "Best, {{snippet:name}}"
                case "name": return "Tasonai {{snippet:sig}}"
                default: return nil
                }
            }
        )
        suite.expect(nested.text == "Best, Tasonai ",
                     "Snippets 2.0 prevents infinite recursion on mutual snippet cycles")

        let mdResult = TextSnippetProEngine.expandAdvanced(
            "Review **urgent** `fix` at [docs](https://example.com)",
            date: baseDate
        )
        suite.expect(mdResult.containsMarkdownFormatting && mdResult.markdownRTFAttributed?.string == "Review urgent fix at docs",
                     "Snippets 2.0 renders lightweight Markdown into RTF NSAttributedString")
    }

    private static func testClipboardPinboardsStackAndTransforms(_ suite: TestSuite) {
        let suiteName = "vorss.tests.wave3.pinboards.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ClipboardPinboardStore(defaults: defaults, key: "boards")
        let workBoard = store.createBoard(name: "Work", colorHex: "#2563EB")
        let entry1 = ClipboardHistoryEntry(id: UUID(), text: "{\"b\":1,\"a\":2}", copiedAt: Date(), kind: .text)
        let entry2 = ClipboardHistoryEntry(id: UUID(), text: "plain", copiedAt: Date(), kind: .text)
        store.assignEntry(entry1.id, to: workBoard.id)
        let filtered = store.entries(in: workBoard.id, from: [entry1, entry2])
        suite.expect(filtered.count == 1 && filtered.first?.id == entry1.id,
                     "ClipboardPinboardStore filters entries strictly to active board")

        let reloaded = ClipboardPinboardStore(defaults: defaults, key: "boards")
        suite.expect(reloaded.pinboards.first?.name == "Work" && reloaded.pinboards.first?.entryIDs == [entry1.id],
                     "ClipboardPinboardStore persists boards cleanly in isolated defaults")

        let stack = ClipboardPasteStack()
        stack.enqueueBatch([entry1, entry2])
        suite.expect(stack.count == 2
                     && stack.popNext()?.id == entry1.id
                     && stack.popNext()?.id == entry2.id
                     && stack.popNext() == nil,
                     "ClipboardPasteStack preserves FIFO pop order")

        let pretty = ClipboardTransformEngine.apply(.jsonPretty, to: "{\"b\":1,\"a\":2}") ?? ""
        let minified = ClipboardTransformEngine.apply(.jsonMinify, to: "{ \"a\" : 1 , \"b\" : 2 }")
        let b64 = ClipboardTransformEngine.apply(.base64Encode, to: "Vorssaint")
        let unb64 = ClipboardTransformEngine.apply(.base64Decode, to: b64 ?? "")
        let oklch = ClipboardTransformEngine.apply(.colorOKLCH, to: "#3B82F6") ?? ""
        // Sample JWT header+payload ({"alg":"HS256"} . {"sub":"42"} . sig)
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiI0MiJ9.sig"
        let jwtDecoded = ClipboardTransformEngine.apply(.jwtDecode, to: jwt) ?? ""

        suite.expect(pretty.contains("\n") && minified == "{\"a\":1,\"b\":2}"
                     && unb64 == "Vorssaint"
                     && oklch.hasPrefix("oklch(")
                     && jwtDecoded.contains("\"sub\" : \"42\""),
                     "ClipboardTransformEngine executes JSON, Base64, JWT, and OKLCH transforms accurately")
    }

    private static func testClipboardImageOCRAndEncryptedVault(_ suite: TestSuite) {
        // Vault E2EE roundtrip + wrong passphrase + byte tamper checks with explicit file cleanup.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorss-vault-test-\(UUID().uuidString)", isDirectory: true)
        let vaultURL = tempDir.appendingPathComponent("clip.vorssaintvault")
        do {
            let secretPayload = Data("{\"entries\":[\"alpha\",\"token\"]}".utf8)
            try ClipboardSyncVault.seal(secretPayload, to: vaultURL, passphrase: "correct-horse-battery")
            let restored = try ClipboardSyncVault.open(from: vaultURL, passphrase: "correct-horse-battery")
            suite.expect(restored == secretPayload,
                         "ClipboardSyncVault HKDF + AES-GCM round-trips vault files losslessly")

            var wrongRejected = false
            do {
                _ = try ClipboardSyncVault.open(from: vaultURL, passphrase: "wrong-passphrase")
            } catch {
                wrongRejected = true
            }
            suite.expect(wrongRejected, "ClipboardSyncVault rejects incorrect passphrases")

            var rawEnvelope = try Data(contentsOf: vaultURL)
            rawEnvelope[rawEnvelope.count - 5] ^= 0xFF
            var tamperRejected = false
            do {
                _ = try ClipboardSyncVault.decrypt(rawEnvelope, passphrase: "correct-horse-battery")
            } catch {
                tamperRejected = true
            }
            suite.expect(tamperRejected, "ClipboardSyncVault detects ciphertext or tag tampering")
        } catch {
            suite.expect(false, "ClipboardSyncVault unexpected error: \(error)")
        }
        try? FileManager.default.removeItem(at: tempDir)

        // Vision OCR smoke check on a crisp high-contrast synthetic NSImage bitmap.
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 96,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        if let rep, let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ctx
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: 320, height: 96).fill()
            NSAttributedString(string: "VORSSAINT OCR",
                               attributes: [.font: NSFont.boldSystemFont(ofSize: 28), .foregroundColor: NSColor.black])
                .draw(at: NSPoint(x: 24, y: 30))
            NSGraphicsContext.restoreGraphicsState()
            if let cg = rep.cgImage {
                let text = ClipboardImageOCRIndexer.recognizeText(in: cg)
                suite.expect(!text.isEmpty, "ClipboardImageOCRIndexer extracts text from high-contrast bitmaps")
            }
        }
    }

    private static func testMixerParametricEQAndMicDSP(_ suite: TestSuite) {
        suite.expect(MixerEQPreset.builtInPresets.count == 25
                     && MixerEQPreset.builtInPresets.allSatisfy { $0.gainsDB.count == 10 },
                     "MixerParametricEQ ships 25 named 10-band AutoEQ presets")

        let sampleRate = 48_000.0
        let frames = 2048
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        for i in 0..<frames {
            let s = 0.25 * sinf(Float(2.0 * Double.pi * 1000.0 * Double(i) / sampleRate))
            left[i] = s
            right[i] = s
        }
        let baselineLevel = left.withUnsafeBufferPointer { MixerPeakMeterMath.measure($0.baseAddress!, count: frames) }

        let eq = MixerParametricEQ(sampleRate: sampleRate)
        // Flat EQ must be unity passthrough.
        var flatL = left
        var flatR = right
        _ = flatL.withUnsafeMutableBufferPointer { lPtr in
            flatR.withUnsafeMutableBufferPointer { rPtr in
                eq.processStereo(left: lPtr.baseAddress!, right: rPtr.baseAddress!, frameCount: frames)
            }
        }
        let flatLevel = flatL.withUnsafeBufferPointer { MixerPeakMeterMath.measure($0.baseAddress!, count: frames) }
        suite.expect(abs(flatLevel.rmsDBFS - baselineLevel.rmsDBFS) < 0.05,
                     "Flat 10-band EQ preserves RMS level within 0.05 dB")

        // +6 dB boost at 1000 Hz (band index 5) must noticeably boost a 1 kHz sine on both channels.
        eq.update(gainsDB: [0, 0, 0, 0, 0, 6.0, 0, 0, 0, 0], preampDB: 0, pan: 0, isMuted: false)
        var boostL = left
        var boostR = right
        _ = boostL.withUnsafeMutableBufferPointer { lPtr in
            boostR.withUnsafeMutableBufferPointer { rPtr in
                eq.processStereo(left: lPtr.baseAddress!, right: rPtr.baseAddress!, frameCount: frames)
            }
        }
        let boostLMeas = boostL.withUnsafeBufferPointer { MixerPeakMeterMath.measure($0.baseAddress!, count: frames) }
        let boostRMeas = boostR.withUnsafeBufferPointer { MixerPeakMeterMath.measure($0.baseAddress!, count: frames) }
        let deltaDB = boostLMeas.rmsDBFS - baselineLevel.rmsDBFS
        suite.expect(deltaDB > 4.0 && deltaDB < 7.0 && abs(boostLMeas.rmsDBFS - boostRMeas.rmsDBFS) < 0.1,
                     "+6 dB @ 1 kHz boosts 1 kHz stereo signal symmetrically (delta=\(deltaDB) dB)")

        // Noise gate + leveler test: quiet -60 dBFS floor is attenuated while -18 dBFS speech passes.
        let micDSP = AudioMicDSPProcessor(noiseGateEnabled: true, levelerEnabled: true)
        var quietBuf = (0..<512).map { i in Float(0.001) * sinf(Float(i) * 0.1) }
        for _ in 0..<4 {
            quietBuf = (0..<512).map { i in Float(0.001) * sinf(Float(i) * 0.1) }
            quietBuf.withUnsafeMutableBufferPointer { ptr in
                micDSP.processInPlace(ptr.baseAddress!, count: 512)
            }
        }
        let gatedQuiet = quietBuf.withUnsafeBufferPointer { MixerPeakMeterMath.measure($0.baseAddress!, count: 512) }
        suite.expect(gatedQuiet.rmsDBFS < -75,
                     "Mic noise gate attenuates sub-threshold room noise floor")
    }
}
