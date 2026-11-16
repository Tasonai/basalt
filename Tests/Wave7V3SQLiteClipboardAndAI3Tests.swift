// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CryptoKit
import Foundation

enum Wave7V3SQLiteClipboardAndAI3Contract {
    static func run(_ suite: TestSuite) {
        testClipboardSQLiteFTS5AndVaultSync(suite)
        testCommandBarAIThreadsAndPlugins(suite)
        testSnippetsRecursionChoiceDateAndPack(suite)
        testWave7UIAndFileHandleHygiene(suite)
    }

    private static func testClipboardSQLiteFTS5AndVaultSync(_ suite: TestSuite) {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("vorssaint-clip-sqlite-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbURL = tempDir.appendingPathComponent("clipboard.sqlite")
        let store = ClipboardSQLiteStore(databaseURL: dbURL, maxCapacity: 500)
        defer { store.close() }

        var batch: [ClipboardSQLiteRow] = []
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<250 {
            batch.append(ClipboardSQLiteRow(
                id: UUID(),
                contentKind: "text",
                plainText: i == 137
                    ? "SELECT bm25(clipboard_fts) FROM vorssaint_telemetry WHERE id = 137;"
                    : "Sample clipboard snippet entry number \(i) for FTS5 benchmark validation",
                sourceAppBundleID: "com.apple.Terminal",
                sourceAppName: "Terminal",
                isPinned: i == 0,
                byteCount: 64,
                createdAt: baseDate.addingTimeInterval(Double(i))
            ))
        }
        store.upsertBatch(batch)
        suite.expect(store.totalCount() == 250,
                     "ClipboardSQLiteStore inserts batch cleanly into SQLite WAL + FTS5 tables")

        let ftsStart = CFAbsoluteTimeGetCurrent()
        let hits = store.search(query: "vorssaint_telemetry bm25", limit: 20)
        let ftsElapsedMs = (CFAbsoluteTimeGetCurrent() - ftsStart) * 1000.0
        suite.expect(hits.count == 1 && hits.first?.plainText.contains("id = 137") == true && ftsElapsedMs < 250.0,
                     "ClipboardSQLiteStore FTS5 BM25 query locates exact match quickly")

        let regexHits = store.search(query: "/id = 13[0-9]/", limit: 20)
        suite.expect(regexHits.count == 1,
                     "ClipboardSQLiteStore supports /regex/ query filtering")

        let legacyURL = tempDir.appendingPathComponent("legacy_clipboard.json")
        let legacyRow = ClipboardSQLiteRow(
            id: UUID(),
            contentKind: "text",
            plainText: "Legacy migrated clipboard phrase zeta99",
            sourceAppBundleID: nil,
            sourceAppName: "Notes",
            isPinned: true,
            byteCount: 38,
            createdAt: baseDate.addingTimeInterval(-100)
        )
        if let encoded = try? JSONEncoder().encode([legacyRow]) {
            try? encoded.write(to: legacyURL)
        }
        let migratedCount = store.migrateLegacyJSONIfNeeded(from: legacyURL)
        let secondMigrate = store.migrateLegacyJSONIfNeeded(from: legacyURL)
        suite.expect(migratedCount == 1 && secondMigrate == 0
                     && store.search(query: "zeta99", limit: 10).count == 1,
                     "ClipboardSQLiteStore migrates legacy JSON once without duplicates")

        let key = SymmetricKey(size: .bits256)
        do {
            let envelope = try ClipboardLiveVaultSyncService.encodeEnvelope(row: legacyRow, key: key)
            let decoded = try ClipboardLiveVaultSyncService.decodeEnvelope(data: envelope, key: key)
            suite.expect(decoded == legacyRow,
                         "ClipboardLiveVaultSyncService encrypts and decrypts E2EE AES.GCM envelopes losslessly")
        } catch {
            suite.expect(false, "ClipboardLiveVaultSyncService AES.GCM round-trip threw error: \(error)")
        }
    }

    private static func testCommandBarAIThreadsAndPlugins(_ suite: TestSuite) {
        let msg1 = AIChatMessage(id: UUID(), role: "user", text: "Summarize this UI screenshot", imagePNGDataBase64: "iVBORw0KGgo=", createdAt: Date())
        let msg2 = AIChatMessage(id: UUID(), role: "assistant", text: "Clean grid spacing.", imagePNGDataBase64: nil, createdAt: Date())
        let thread = AIChatThread(id: UUID(), title: "UI Audit", messages: [msg1, msg2], updatedAt: Date())
        let roundTrip = try? JSONDecoder().decode(AIChatThread.self, from: JSONEncoder().encode(thread))
        suite.expect(roundTrip?.messages.count == 2 && roundTrip?.messages.first?.imagePNGDataBase64 == "iVBORw0KGgo=",
                     "AIChatThread preserves multi-turn messages and Vision PNG base64 attachments across Codable")

        suite.expect(InlineAIRewriteAction.allCases.count >= 5,
                     "InlineAIRewriteAction exposes full rewrite/grammar/summarize/translate/explain suite")

        let action = PluginActionItem(id: "copy-id", title: "Copy Output", kind: .copy, value: "ok")
        let field = PluginFormField(id: "branch", label: "Branch", defaultValue: "main", options: ["main", "dev"])
        let encodedAction = try? JSONEncoder().encode(action)
        let decodedAction = encodedAction.flatMap { try? JSONDecoder().decode(PluginActionItem.self, from: $0) }
        suite.expect(decodedAction == action && field.options.count == 2,
                     "Rich JSON PluginActionItem and PluginFormField round-trip via Codable")
    }

    private static func testSnippetsRecursionChoiceDateAndPack(_ suite: TestSuite) {
        let sig = SnippetPackItem(trigger: ";sig", title: "Signature", content: "Best,\nVorssaint Team")
        let reply = SnippetPackItem(trigger: ";reply", title: "Quick Reply", content: "Status: {{choice: State | Green | Yellow}} on {{date:+2d:yyyy-MM-dd}}\n{{snippet:;sig}}")
        let cycleA = SnippetPackItem(trigger: ";a", title: "Cycle A", content: "A->{{snippet:;b}}")
        let cycleB = SnippetPackItem(trigger: ";b", title: "Cycle B", content: "B->{{snippet:;a}}")

        let resolved = TextSnippetProEngine.resolveAdvancedTemplate(
            reply.content,
            choiceSelections: ["State": "Green"],
            snippetsByTrigger: [sig.trigger: sig.content, cycleA.trigger: cycleA.content, cycleB.trigger: cycleB.content],
            referenceDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        suite.expect(resolved.contains("Status: Green")
                     && resolved.contains("2023-11-16")
                     && resolved.contains("Vorssaint Team"),
                     "TextSnippetProEngine expands choice dropdowns, date math, and nested snippets together")

        let cycleGuarded = TextSnippetProEngine.resolveAdvancedTemplate(
            cycleA.content,
            choiceSelections: [:],
            snippetsByTrigger: [cycleA.trigger: cycleA.content, cycleB.trigger: cycleB.content]
        )
        suite.expect(!cycleGuarded.isEmpty && cycleGuarded.count < 256,
                     "TextSnippetProEngine terminates recursive snippet cycles safely within maxDepth 5")

        let pack = SnippetExportPack(version: 1, snippets: [sig, reply])
        if let packData = try? JSONEncoder().encode(pack),
           let imported = try? JSONDecoder().decode(SnippetExportPack.self, from: packData) {
            suite.expect(imported.snippets.count == 2 && imported.snippets.first?.trigger == ";sig",
                         ".vorssaintsnippets JSON pack serializes and decodes losslessly")
        } else {
            suite.expect(false, ".vorssaintsnippets pack Codable round-trip failed")
        }
    }

    private static func testWave7UIAndFileHandleHygiene(_ suite: TestSuite) {
        let clipPro = (try? String(contentsOfFile: "Sources/Vorssaint/Services/Clipboard/ClipboardProSupport.swift", encoding: .utf8)) ?? ""
        let inlineHUD = (try? String(contentsOfFile: "Sources/Vorssaint/UI/CommandBar/InlineAISelectionHUDController.swift", encoding: .utf8)) ?? ""
        let clipSettings = (try? String(contentsOfFile: "Sources/Vorssaint/UI/Settings/ClipboardSettings.swift", encoding: .utf8)) ?? ""
        let cmdView = (try? String(contentsOfFile: "Sources/Vorssaint/UI/CommandBar/CommandBarView.swift", encoding: .utf8)) ?? ""
        let snippetSettings = (try? String(contentsOfFile: "Sources/Vorssaint/UI/Settings/TextSnippetsSettings.swift", encoding: .utf8)) ?? ""

        suite.expect(clipPro.contains("setCancelHandler") && clipPro.contains("close("),
                     "ClipboardLiveVaultSyncService closes O_EVTONLY descriptor inside setCancelHandler")

        suite.expect(inlineHUD.contains(": OverlayPanel"),
                     "InlineAISelectionHUDController subclasses OverlayPanel for non-activating overlay hygiene")

        suite.expect(clipSettings.contains("OverhaulV3Strings.clipboardLiveSyncToggle")
                     && clipSettings.contains("OverhaulV3Strings.clipboardFTSBadgeFormat")
                     && !clipSettings.contains(".toggleStyle(.switch)")
                     && !clipSettings.contains(".toggleStyle(.checkbox)"),
                     "ClipboardSettings exposes FTS5 badge and iCloud Live Sync toggle with VorssaintDesignKit")

        suite.expect(cmdView.contains("OverhaulV3Strings.aiNewThreadButton")
                     && cmdView.contains("OverhaulV3Strings.aiAttachImageButton"),
                     "CommandBarView exposes multi-turn AI thread and Vision image attachment controls")

        suite.expect(snippetSettings.contains("OverhaulV3Strings.snippetsImportPackButton")
                     && !snippetSettings.contains(".toggleStyle(.switch)")
                     && !snippetSettings.contains(".toggleStyle(.checkbox)"),
                     "TextSnippetsSettings exposes .vorssaintsnippets pack import/export with VorssaintDesignKit")
    }
}
