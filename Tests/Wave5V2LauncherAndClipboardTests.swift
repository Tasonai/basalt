// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum Wave5V2LauncherAndClipboardContract {
    static func run(_ suite: TestSuite) {
        testQuickAIContextResolverAndAnthropicSSE(suite)
        testSnippets2ArgumentSpecsAndRTFExpansion(suite)
        testClipboardSyntaxHighlighterAndOpenGraph(suite)
        testClipboardOCRSearchAndVaultSecrets(suite)
        testWave5SourceWiring(suite)
    }

    private static func readRepo(_ path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    private static func testQuickAIContextResolverAndAnthropicSSE(_ suite: TestSuite) {
        let resolved = QuickAIContextResolver.resolvePrompt(
            "Summarize @clipboard for @frontApp using @selection from @browser",
            clipboard: "SELECT * FROM users;",
            frontAppName: "Xcode",
            selectedText: "func hello()",
            browserInfo: "Docs — https://example.com"
        )
        suite.expect(resolved.contains("SELECT * FROM users;")
                     && resolved.contains("Xcode")
                     && resolved.contains("func hello()")
                     && resolved.contains("https://example.com"),
                     "QuickAIContextResolver expands @clipboard, @frontApp, @selection, and @browser")

        let chipSnapshot = QuickAIContextSnapshot(
            clipboard: "Clipboard snippet",
            frontAppName: "Safari",
            selectedText: nil,
            browserInfo: nil
        )
        let chipResolved = QuickAIContextResolver.resolvePrompt(
            "Explain this",
            attachedTokens: [.clipboard, .frontApp],
            snapshot: chipSnapshot
        )
        suite.expect(chipResolved.contains("[Context]")
                     && chipResolved.contains("Clipboard snippet")
                     && chipResolved.contains("Safari"),
                     "QuickAIContextResolver prepends attached context chips cleanly")

        let delta = CommandBarQuickAIService.parseAnthropicSSELine(
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello Claude"}}"#
        )
        let stop = CommandBarQuickAIService.parseAnthropicSSELine(
            #"event: message_stop"#
        )
        suite.expect(delta.token == "Hello Claude" && !delta.done
                     && stop.token == nil && stop.done,
                     "CommandBarQuickAIService parses Anthropic content_block_delta and message_stop SSE events")
    }

    private static func testSnippets2ArgumentSpecsAndRTFExpansion(_ suite: TestSuite) {
        let template = "Hi {{arg:name=Friend}}, review {{arg:pr=42}} by {{arg:name=IgnoredDuplicate}}! {{cursor}}-- {{arg:team}}"
        let specs = TextSnippetProEngine.extractArgumentSpecs(from: template)
        suite.expect(specs.count == 3
                     && specs[0].name == "name" && specs[0].defaultValue == "Friend"
                     && specs[1].name == "pr" && specs[1].defaultValue == "42"
                     && specs[2].name == "team" && specs[2].defaultValue == "",
                     "TextSnippetProEngine extracts unique argument specs preserving first default and order")

        let expanded = TextSnippetProEngine.expandAdvanced(
            "**bold** {{arg:item=report}} {{cursor}}end",
            arguments: ["item": "build"]
        )
        suite.expect(expanded.text == "**bold** build end"
                     && expanded.cursorMoveBackUTF16 == 3
                     && expanded.containsMarkdownFormatting
                     && expanded.markdownRTFAttributed != nil,
                     "TextSnippetProEngine renders RTF Markdown attributes and exact cursor rewind")
    }

    private static func testClipboardSyntaxHighlighterAndOpenGraph(_ suite: TestSuite) {
        let swiftSample = """
        // comment
        func greet(name: String) -> Int {
            return 42
        }
        """
        let tokenized = ClipboardSyntaxHighlighter.tokenize(swiftSample)
        suite.expect(tokenized.language == .swift
                     && tokenized.tokens.contains(where: { $0.kind == .keyword })
                     && tokenized.tokens.contains(where: { $0.kind == .comment })
                     && tokenized.tokens.contains(where: { $0.kind == .number }),
                     "ClipboardSyntaxHighlighter detects Swift and emits keyword/comment/number tokens")

        let jsonSample = #"{"service":"vorssaint","count":7,"ok":true}"#
        let jsonTok = ClipboardSyntaxHighlighter.tokenize(jsonSample)
        suite.expect(jsonTok.language == .json
                     && jsonTok.tokens.contains(where: { $0.kind == .key })
                     && jsonTok.tokens.contains(where: { $0.kind == .string }),
                     "ClipboardSyntaxHighlighter detects JSON and tokenizes keys/strings")

        let html = """
        <html><head>
        <title>Fallback Title</title>
        <meta property="og:title" content="Vorssaint &amp; Utilities" />
        <meta property="og:description" content="Native macOS suite" />
        <meta property="og:site_name" content="Vorssaint" />
        </head></html>
        """
        let meta = ClipboardLinkMetadataParser.parse(html: html,
                                                     sourceURL: URL(string: "https://example.com/post")!)
        suite.expect(meta.title == "Vorssaint & Utilities"
                     && meta.description == "Native macOS suite"
                     && meta.siteName == "Vorssaint",
                     "ClipboardLinkMetadataParser parses OpenGraph tags and unescapes HTML entities")
    }

    private static func testClipboardOCRSearchAndVaultSecrets(_ suite: TestSuite) {
        let ocrEntry = ClipboardHistoryEntry(
            text: "Screenshot.png",
            kind: .image,
            imageFile: "shot.png",
            imageHash: "abc123",
            imageWidth: 800,
            imageHeight: 600,
            ocrText: "Invoice #INV-9021 Total $49"
        )
        suite.expect(ClipboardHistorySearch.matches(ocrEntry, query: "INV-9021")
                     && !ClipboardHistorySearch.matches(ocrEntry, query: "MissingToken"),
                     "ClipboardHistorySearch indexes and matches background image OCR text")

        let store = InMemoryClipboardVaultSecretStore()
        suite.expect(store.saveSecret("vault-pass-123")
                     && store.loadSecret() == "vault-pass-123"
                     && store.deleteSecret()
                     && store.loadSecret() == nil,
                     "ClipboardVaultSecretStore persists and clears vault passphrase cleanly")
    }

    private static func testWave5SourceWiring(_ suite: TestSuite) {
        let cmdView = readRepo("Sources/Vorssaint/UI/CommandBar/CommandBarView.swift")
        let runner = readRepo("Sources/Vorssaint/Services/CommandBar/CommandBarScriptRunner.swift")
        let cmdSettings = readRepo("Sources/Vorssaint/UI/Settings/CommandBarSettings.swift")
        let fillIn = readRepo("Sources/Vorssaint/UI/Snippets/SnippetFillInPopover.swift")
        let snippetSvc = readRepo("Sources/Vorssaint/Services/Snippets/TextSnippetService.swift")
        let clipSvc = readRepo("Sources/Vorssaint/Services/Clipboard/ClipboardHistoryService.swift")
        let pasteHUD = readRepo("Sources/Vorssaint/UI/Clipboard/ClipboardPasteStackHUDController.swift")
        let dockView = readRepo("Sources/Vorssaint/UI/Clipboard/ClipboardDockModeView.swift")
        let sidebar = readRepo("Sources/Vorssaint/UI/MenuPanel/ClipboardEntryPreviewSidebar.swift")
        let clipSettings = readRepo("Sources/Vorssaint/UI/Settings/ClipboardSettings.swift")

        suite.expect(cmdView.contains("splitDetailResultsView")
                     && cmdView.contains("gridResultsView")
                     && cmdView.contains("CommandBarDroplet.shared.hurry()"),
                     "CommandBarView renders split-detail and grid modes while keeping CommandBarDroplet.hurry()")
        suite.expect(runner.contains("ScriptCommandHeaderParser.parseMetadata")
                     && cmdSettings.contains("QuickAIProvider"),
                     "CommandBarScriptRunner parses v2 headers and CommandBarSettings exposes Quick AI Keychain config")
        suite.expect(fillIn.contains("OverlayPanel")
                     && snippetSvc.contains("expandAdvanced")
                     && snippetSvc.contains("kVK_LeftArrow"),
                     "SnippetFillInPopover extends OverlayPanel and TextSnippetService wires RTF/cursor rewind")
        suite.expect(clipSvc.contains("ClipboardImageOCRIndexer.recognizeText")
                     && pasteHUD.contains("OverlayPanel")
                     && dockView.contains("DockCarouselCard")
                     && sidebar.contains("ClipboardLinkMetadataFetcher")
                     && clipSettings.contains("ClipboardSyncVault"),
                     "Clipboard 2.0 wires background OCR, Paste Stack HUD, Dock Carousel, OpenGraph sidebar, and Vault sync")
    }
}
