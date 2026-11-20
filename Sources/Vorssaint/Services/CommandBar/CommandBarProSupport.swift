// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import Foundation
import Security

/// Presentation modes supported by Command Bar 2.0 (`list` classic, `splitDetail`
/// master/inspector, and `grid` for visual launchers/actions).
enum CommandBarLayoutMode: String, CaseIterable, Codable, Equatable, Sendable {
    case list
    case splitDetail
    case grid
}

/// One message turn in Command Bar 3.0 Quick AI multi-turn threads, with optional PNG vision payload.
struct AIChatMessage: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let role: String
    let text: String
    let imagePNGDataBase64: String?
    let createdAt: Date

    init(id: UUID = UUID(),
         role: String,
         text: String,
         imagePNGDataBase64: String? = nil,
         createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.imagePNGDataBase64 = imagePNGDataBase64
        self.createdAt = createdAt
    }
}

/// Persistent in-session Quick AI conversation thread for Command Bar 3.0.
struct AIChatThread: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var messages: [AIChatMessage]
    var updatedAt: Date

    init(id: UUID = UUID(),
         title: String = "New Chat",
         messages: [AIChatMessage] = [],
         updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.messages = messages
        self.updatedAt = updatedAt
    }
}

/// Actions offered by the floating Inline AI Selection HUD over selected text.
enum InlineAIRewriteAction: String, CaseIterable, Identifiable, Sendable {
    case improveWriting
    case fixGrammar
    case summarize
    case translate
    case explainCode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .improveWriting: return "Improve Writing"
        case .fixGrammar: return "Fix Grammar"
        case .summarize: return "Summarize"
        case .translate: return "Translate"
        case .explainCode: return "Explain Code"
        }
    }

    var symbolName: String {
        switch self {
        case .improveWriting: return "wand.and.stars"
        case .fixGrammar: return "textformat.abc"
        case .summarize: return "text.alignleft"
        case .translate: return "globe"
        case .explainCode: return "chevron.left.forwardslash.chevron.right"
        }
    }

    func prompt(for selectedText: String) -> String {
        switch self {
        case .improveWriting:
            return "Improve the clarity, flow, and tone of the following text. Return only the improved text:\n\n\(selectedText)"
        case .fixGrammar:
            return "Fix grammar, spelling, and punctuation in the following text without changing its meaning. Return only the corrected text:\n\n\(selectedText)"
        case .summarize:
            return "Summarize the following text concisely:\n\n\(selectedText)"
        case .translate:
            return "Translate the following text into clear natural English (or into Spanish if it is already in English), preserving formatting. Return only the translation:\n\n\(selectedText)"
        case .explainCode:
            return "Explain clearly what the following code or technical snippet does:\n\n\(selectedText)"
        }
    }
}

/// Action kind declared by rich JSON script plugin outputs.
enum PluginActionKind: String, Codable, Sendable {
    case copy
    case openURL
    case paste
    case runSubcommand
}

/// Interactive button descriptor emitted in a script plugin's JSON payload.
struct PluginActionItem: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let kind: PluginActionKind
    let value: String

    init(id: String, title: String, kind: PluginActionKind, value: String) {
        self.id = id
        self.title = title
        self.kind = kind
        self.value = value
    }
}

/// Declarative form field emitted by rich JSON plugin outputs.
struct PluginFormField: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let label: String
    let defaultValue: String
    let options: [String]

    init(id: String, label: String, defaultValue: String = "", options: [String] = []) {
        self.id = id
        self.label = label
        self.defaultValue = defaultValue
        self.options = options
    }

    enum CodingKeys: String, CodingKey {
        case id, label, defaultValue, options
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedLabel = try container.decode(String.self, forKey: .label)
        self.label = decodedLabel
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? decodedLabel
        self.defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue) ?? ""
        self.options = try container.decodeIfPresent([String].self, forKey: .options) ?? []
    }
}

/// Secondary action descriptor displayed in the `⌘K` Action Panel.
struct CommandBarActionItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let symbolName: String
    let shortcutDisplay: String
    let isDestructive: Bool

    init(id: String,
         title: String,
         symbolName: String,
         shortcutDisplay: String,
         isDestructive: Bool = false) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.shortcutDisplay = shortcutDisplay
        self.isDestructive = isDestructive
    }
}

/// Builds deterministic action menus for Command Bar rows and clipboard items.
enum CommandBarActionPanelModel {
    static func actions(forTitle title: String,
                        canRevealInFinder: Bool,
                        canCopyValue: Bool,
                        canPin: Bool,
                        canTransform: Bool = false,
                        isDestructiveSupported: Bool = false) -> [CommandBarActionItem] {
        var items: [CommandBarActionItem] = [
            CommandBarActionItem(id: "open",
                                 title: "Open \(title)",
                                 symbolName: "arrow.up.right.square",
                                 shortcutDisplay: "⏎"),
        ]
        if canRevealInFinder {
            items.append(CommandBarActionItem(id: "reveal",
                                              title: "Reveal in Finder",
                                              symbolName: "folder",
                                              shortcutDisplay: "⌘⏎"))
        }
        if canCopyValue {
            items.append(CommandBarActionItem(id: "copy",
                                              title: "Copy Value",
                                              symbolName: "doc.on.doc",
                                              shortcutDisplay: "⌘C"))
        }
        if canPin {
            items.append(CommandBarActionItem(id: "pin",
                                              title: "Toggle Pin",
                                              symbolName: "pin",
                                              shortcutDisplay: "⌘P"))
        }
        if canTransform {
            items.append(CommandBarActionItem(id: "transform",
                                              title: "Transform Text",
                                              symbolName: "wand.and.stars",
                                              shortcutDisplay: "⌘⇧T"))
        }
        if isDestructiveSupported {
            items.append(CommandBarActionItem(id: "delete",
                                              title: "Remove",
                                              symbolName: "trash",
                                              shortcutDisplay: "⌘⌫",
                                              isDestructive: true))
        }
        return items
    }
}

/// Synchronizes Quick AI streaming lifecycle with the Command Bar mascot droplet.
enum CommandBarQuickAIDropletState: String, Equatable, Sendable {
    case idle
    case thinking
    case celebrate
}

/// Provider options for Command Bar 2.0 Quick AI (local models, CLI tools, or BYOK).
enum QuickAIProvider: String, CaseIterable, Identifiable, Equatable, Sendable {
    case ollama
    case claudeCLI
    case codexCLI
    case byokOpenAI
    case byokAnthropic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama: return "Ollama (Local)"
        case .claudeCLI: return "Claude CLI"
        case .codexCLI: return "Codex CLI"
        case .byokOpenAI: return "OpenAI (Keychain)"
        case .byokAnthropic: return "Anthropic (Keychain)"
        }
    }
}

/// Secret storage abstraction so production persists API keys in Keychain while tests avoid UI prompts.
protocol QuickAISecretStore {
    func saveSecret(_ value: String, account: String) -> Bool
    func loadSecret(account: String) -> String?
    func deleteSecret(account: String) -> Bool
}

struct KeychainQuickAISecretStore: QuickAISecretStore {
    private static let service = "com.tasonai.basalt.quickai"
    private static let legacyService = "com.vorssaint.utils.quickai"

    func saveSecret(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    func loadSecret(account: String) -> String? {
        if let value = loadSecret(account: account, service: Self.service) {
            return value
        }
        return loadSecret(account: account, service: Self.legacyService)
    }

    private func loadSecret(account: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func deleteSecret(account: String) -> Bool {
        let primary = deleteSecret(account: account, service: Self.service)
        let legacy = deleteSecret(account: account, service: Self.legacyService)
        return primary && legacy
    }

    private func deleteSecret(account: String, service: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

final class InMemoryQuickAISecretStore: QuickAISecretStore {
    private var entries: [String: String] = [:]

    func saveSecret(_ value: String, account: String) -> Bool {
        entries[account] = value
        return true
    }

    func loadSecret(account: String) -> String? {
        entries[account]
    }

    func deleteSecret(account: String) -> Bool {
        entries.removeValue(forKey: account)
        return true
    }
}

/// Context injection tokens supported in Command Bar 2.0 Quick AI prompts.
enum QuickAIContextToken: String, CaseIterable, Identifiable, Equatable, Sendable {
    case clipboard
    case frontApp
    case selection
    case browser

    var id: String { rawValue }

    var token: String {
        switch self {
        case .clipboard: return "@clipboard"
        case .frontApp: return "@frontApp"
        case .selection: return "@selection"
        case .browser: return "@browser"
        }
    }

    var displayTitle: String {
        switch self {
        case .clipboard: return "Clipboard"
        case .frontApp: return "Front App"
        case .selection: return "Selection"
        case .browser: return "Browser"
        }
    }

    var symbolName: String {
        switch self {
        case .clipboard: return "doc.on.clipboard"
        case .frontApp: return "app.dashed"
        case .selection: return "text.cursor"
        case .browser: return "globe"
        }
    }
}

/// Snapshot of live desktop context captured for Quick AI token expansion.
struct QuickAIContextSnapshot: Equatable, Sendable {
    let clipboard: String?
    let frontAppName: String?
    let selectedText: String?
    let browserInfo: String?

    init(clipboard: String? = nil,
         frontAppName: String? = nil,
         selectedText: String? = nil,
         browserInfo: String? = nil) {
        self.clipboard = clipboard
        self.frontAppName = frontAppName
        self.selectedText = selectedText
        self.browserInfo = browserInfo
    }
}

/// Pure prompt token expander plus live desktop context reader for Quick AI.
enum QuickAIContextResolver {
    private static let maxInlineSnippetChars = 6000
    private static let maxShortTokenChars = 2000

    private static let safariBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
    ]

    private static let chromiumBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "company.thebrowser.Browser",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "org.chromium.Chromium",
    ]

    private static let axFallbackBrowserBundleIDs: Set<String> = [
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "app.zen-browser.zen",
        "com.kagi.kagimacOS",
    ]

    static func tokensPresent(in prompt: String) -> [QuickAIContextToken] {
        var found: [QuickAIContextToken] = []
        let lowered = prompt.lowercased()
        for token in QuickAIContextToken.allCases {
            if lowered.contains(token.token.lowercased()), !found.contains(token) {
                found.append(token)
            }
        }
        return found
    }

    /// Expands `@clipboard`, `@frontApp`, `@selection`, and `@browser` tokens deterministically.
    static func resolvePrompt(
        _ prompt: String,
        clipboard: String? = nil,
        frontAppName: String? = nil,
        selectedText: String? = nil,
        browserInfo: String? = nil
    ) -> String {
        guard prompt.contains("@"),
              let regex = try? NSRegularExpression(
                pattern: #"@(clipboard|frontApp|frontapp|selection|browser)(?![A-Za-z0-9_])"#
              ) else {
            return prompt
        }

        let cleanClip = sanitize(clipboard, limit: maxInlineSnippetChars)
        let cleanApp = sanitize(frontAppName, limit: maxShortTokenChars)
        let cleanSelection = sanitize(selectedText, limit: maxInlineSnippetChars)
        let cleanBrowser = sanitize(browserInfo, limit: maxShortTokenChars)

        var output = prompt
        let nsRange = NSRange(output.startIndex..<output.endIndex, in: output)
        for match in regex.matches(in: output, range: nsRange).reversed() {
            guard match.numberOfRanges >= 2,
                  let fullRange = Range(match.range(at: 0), in: output),
                  let nameRange = Range(match.range(at: 1), in: output) else { continue }
            let key = String(output[nameRange]).lowercased()
            let replacement: String
            switch key {
            case "clipboard": replacement = cleanClip ?? ""
            case "frontapp": replacement = cleanApp ?? ""
            case "selection": replacement = cleanSelection ?? ""
            case "browser": replacement = cleanBrowser ?? ""
            default: replacement = ""
            }
            output.replaceSubrange(fullRange, with: replacement)
        }
        return output
            .replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Resolves inline `@tokens` and prepends a compact `[Context]` block for any
    /// attached chips not explicitly referenced inline in `prompt`.
    static func resolvePrompt(
        _ prompt: String,
        attachedTokens: Set<QuickAIContextToken>,
        snapshot: QuickAIContextSnapshot
    ) -> String {
        let inlineTokens = Set(tokensPresent(in: prompt))
        let expandedPrompt = resolvePrompt(
            prompt,
            clipboard: snapshot.clipboard,
            frontAppName: snapshot.frontAppName,
            selectedText: snapshot.selectedText,
            browserInfo: snapshot.browserInfo
        )
        let extraTokens = QuickAIContextToken.allCases.filter {
            attachedTokens.contains($0) && !inlineTokens.contains($0)
        }
        guard !extraTokens.isEmpty else { return expandedPrompt }

        var contextLines: [String] = []
        for token in extraTokens {
            let value: String?
            switch token {
            case .clipboard: value = sanitize(snapshot.clipboard, limit: maxInlineSnippetChars)
            case .frontApp: value = sanitize(snapshot.frontAppName, limit: maxShortTokenChars)
            case .selection: value = sanitize(snapshot.selectedText, limit: maxInlineSnippetChars)
            case .browser: value = sanitize(snapshot.browserInfo, limit: maxShortTokenChars)
            }
            if let value, !value.isEmpty {
                contextLines.append("\(token.displayTitle): \(value)")
            }
        }
        guard !contextLines.isEmpty else { return expandedPrompt }
        return "[Context]\n" + contextLines.joined(separator: "\n") + "\n\n" + expandedPrompt
    }

    static func captureLiveContext(
        includeClipboard: Bool = true,
        includeFrontApp: Bool = true,
        includeSelection: Bool = true,
        includeBrowser: Bool = true
    ) async -> QuickAIContextSnapshot {
        let captured = await MainActor.run { () -> (
            clipboard: String?,
            frontAppName: String?,
            frontPID: pid_t?,
            frontBundleID: String?,
            runningBrowsers: [(pid: pid_t, bundleID: String)]
        ) in
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let front = NSWorkspace.shared.frontmostApplication
            let usableFront = (front?.processIdentifier != ownPID) ? front : nil
            let clip = includeClipboard ? NSPasteboard.general.string(forType: .string) : nil
            let knownBrowsers = safariBundleIDs.union(chromiumBundleIDs).union(axFallbackBrowserBundleIDs)
            let browsers = NSWorkspace.shared.runningApplications.compactMap { app -> (pid_t, String)? in
                guard !app.isTerminated,
                      let bid = app.bundleIdentifier,
                      knownBrowsers.contains(bid) else { return nil }
                return (app.processIdentifier, bid)
            }
            return (
                clip,
                includeFrontApp ? (usableFront?.localizedName ?? front?.localizedName) : nil,
                usableFront?.processIdentifier,
                usableFront?.bundleIdentifier,
                browsers
            )
        }

        return await Task.detached(priority: .userInitiated) {
            let selected = includeSelection
                ? captured.frontPID.flatMap { readSelectedText(processID: $0) }
                : nil
            let browser = includeBrowser
                ? readBrowserInfo(
                    preferredPID: captured.frontPID,
                    preferredBundleID: captured.frontBundleID,
                    runningBrowsers: captured.runningBrowsers
                )
                : nil
            return QuickAIContextSnapshot(
                clipboard: captured.clipboard,
                frontAppName: captured.frontAppName,
                selectedText: selected,
                browserInfo: browser
            )
        }.value
    }

    private static func sanitize(_ raw: String?, limit: Int) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        if trimmed.count <= limit { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }

    private static func readSelectedText(processID: pid_t) -> String? {
        guard AXIsProcessTrusted(),
              processID != ProcessInfo.processInfo.processIdentifier else { return nil }
        let appElement = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(appElement, 0.35)
        var focusedRaw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRaw) == .success,
              let focusedRaw,
              CFGetTypeID(focusedRaw) == AXUIElementGetTypeID() else { return nil }
        let focused = focusedRaw as! AXUIElement
        AXUIElementSetMessagingTimeout(focused, 0.35)

        if let text = copyAXString(focused, attribute: kAXSelectedTextAttribute as CFString),
           !text.isEmpty {
            return String(text.prefix(maxInlineSnippetChars))
        }
        var markerRaw: CFTypeRef?
        if AXUIElementCopyAttributeValue(focused, "AXSelectedTextMarkerRange" as CFString, &markerRaw) == .success,
           let markerRaw {
            var strRaw: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                focused,
                "AXStringForTextMarkerRange" as CFString,
                markerRaw,
                &strRaw
            ) == .success,
               let str = strRaw as? String, !str.isEmpty {
                return String(str.prefix(maxInlineSnippetChars))
            }
        }
        return nil
    }

    private static func readBrowserInfo(
        preferredPID: pid_t?,
        preferredBundleID: String?,
        runningBrowsers: [(pid: pid_t, bundleID: String)]
    ) -> String? {
        var candidates: [(pid: pid_t, bundleID: String)] = []
        if let preferredPID, let preferredBundleID,
           safariBundleIDs.contains(preferredBundleID)
            || chromiumBundleIDs.contains(preferredBundleID)
            || axFallbackBrowserBundleIDs.contains(preferredBundleID) {
            candidates.append((preferredPID, preferredBundleID))
        }
        for browser in runningBrowsers where !candidates.contains(where: { $0.pid == browser.pid }) {
            candidates.append(browser)
        }
        guard !candidates.isEmpty else { return nil }

        for candidate in candidates {
            if safariBundleIDs.contains(candidate.bundleID) {
                let script = "tell application id \"\(candidate.bundleID)\" to if (count of windows) > 0 then return (name of current tab of front window) & \"\\n\" & (URL of current tab of front window)"
                if let info = runBrowserAppleScript(script) { return info }
            } else if chromiumBundleIDs.contains(candidate.bundleID) {
                let script = "tell application id \"\(candidate.bundleID)\" to if (count of windows) > 0 then return (title of active tab of front window) & \"\\n\" & (URL of active tab of front window)"
                if let info = runBrowserAppleScript(script) { return info }
            }
            if let title = readFocusedWindowTitle(processID: candidate.pid) {
                return title
            }
        }
        return nil
    }

    private static func runBrowserAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        guard error == nil, let raw = descriptor.stringValue else { return nil }
        let parts = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        if parts.count >= 2 {
            return "\(parts[0]) (\(parts[1]))"
        }
        return parts[0]
    }

    private static func readFocusedWindowTitle(processID: pid_t) -> String? {
        guard AXIsProcessTrusted(),
              processID != ProcessInfo.processInfo.processIdentifier else { return nil }
        let appElement = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(appElement, 0.3)
        var winRaw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &winRaw) == .success,
              let winRaw,
              CFGetTypeID(winRaw) == AXUIElementGetTypeID() else { return nil }
        let window = winRaw as! AXUIElement
        AXUIElementSetMessagingTimeout(window, 0.3)
        return copyAXString(window, attribute: kAXTitleAttribute as CFString)
    }

    private static func copyAXString(_ element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        return value as? String
    }
}

/// Manages Quick AI sessions (`Tab` in Command Bar), Keychain BYOK keys, CLI probing, and droplet mood sync.
final class CommandBarQuickAIService: ObservableObject, @unchecked Sendable {
    static let shared = CommandBarQuickAIService(defaults: .standard)

    private static let providerStorageKey = "commandBarQuickAIProvider"

    @Published private(set) var isStreaming = false
    @Published private(set) var responseText = ""
    @Published private(set) var lastPrompt = ""
    @Published private(set) var errorText: String?
    @Published private(set) var missingKeyProvider: QuickAIProvider?
    @Published private(set) var dropletState: CommandBarQuickAIDropletState = .idle
    @Published var selectedProvider: QuickAIProvider {
        didSet {
            guard oldValue != selectedProvider else { return }
            defaults?.set(selectedProvider.rawValue, forKey: Self.providerStorageKey)
        }
    }

    private let secretStore: any QuickAISecretStore
    private let defaults: UserDefaults?
    private var streamTask: Task<Void, Never>?
    private let processLock = NSLock()
    private var activeProcess: Process?
    private var completionHandler: ((String) -> Void)?

    init(secretStore: any QuickAISecretStore = KeychainQuickAISecretStore(),
         defaults: UserDefaults? = nil) {
        self.secretStore = secretStore
        self.defaults = defaults
        if let raw = defaults?.string(forKey: Self.providerStorageKey),
           let stored = QuickAIProvider(rawValue: raw) {
            self.selectedProvider = stored
        } else {
            self.selectedProvider = .ollama
        }
    }

    deinit {
        streamTask?.cancel()
        terminateActiveProcess()
    }

    static func installedCLITools(
        searchPaths: [String] = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"],
        fileManager: FileManager = .default
    ) -> [QuickAIProvider] {
        var found: [QuickAIProvider] = []
        let claudeExists = searchPaths.contains { fileManager.isExecutableFile(atPath: "\($0)/claude") }
        let codexExists = searchPaths.contains { fileManager.isExecutableFile(atPath: "\($0)/codex") }
        if claudeExists { found.append(.claudeCLI) }
        if codexExists { found.append(.codexCLI) }
        return found
    }

    func saveAPIKey(_ key: String, for provider: QuickAIProvider) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return secretStore.saveSecret(trimmed, account: provider.rawValue)
    }

    func apiKey(for provider: QuickAIProvider) -> String? {
        secretStore.loadSecret(account: provider.rawValue)
    }

    @discardableResult
    func removeAPIKey(for provider: QuickAIProvider) -> Bool {
        secretStore.deleteSecret(account: provider.rawValue)
    }

    func beginThinking(prompt: String, onCompletion: ((String) -> Void)? = nil) {
        streamTask?.cancel()
        streamTask = nil
        terminateActiveProcess()
        completionHandler = onCompletion
        lastPrompt = prompt
        responseText = ""
        errorText = nil
        missingKeyProvider = nil
        isStreaming = true
        dropletState = .thinking
    }

    func appendStreamChunk(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        responseText += chunk
    }

    func finishSuccess() {
        isStreaming = false
        dropletState = .celebrate
        let handler = completionHandler
        completionHandler = nil
        handler?(responseText)
    }

    func finishWithError(_ message: String) {
        isStreaming = false
        errorText = message
        dropletState = .idle
        completionHandler = nil
    }

    func reset() {
        streamTask?.cancel()
        streamTask = nil
        terminateActiveProcess()
        completionHandler = nil
        isStreaming = false
        responseText = ""
        errorText = nil
        missingKeyProvider = nil
        dropletState = .idle
    }

    private func terminateActiveProcess() {
        let process = processLock.withLock { () -> Process? in
            let current = activeProcess
            activeProcess = nil
            return current
        }
        if let process, process.isRunning {
            process.terminate()
        }
    }

    /// Parses one NDJSON line emitted by Ollama's `/api/generate` or `/api/chat` endpoint.
    static func parseOllamaStreamLine(_ line: String) -> (token: String?, done: Bool) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, false)
        }
        let messageContent = (object["message"] as? [String: Any])?["content"] as? String
        let token = (object["response"] as? String) ?? messageContent
        let done = object["done"] as? Bool ?? false
        return (token, done)
    }

    /// Parses an SSE `data:` line in OpenAI chat completion streams.
    static func parseOpenAISSELine(_ line: String) -> (token: String?, done: Bool) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return (nil, false) }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return (nil, true) }
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, false)
        }
        if let choices = object["choices"] as? [[String: Any]],
           let first = choices.first,
           let delta = first["delta"] as? [String: Any],
           let content = delta["content"] as? String {
            return (content, false)
        }
        if let delta = object["delta"] as? [String: Any],
           let text = delta["text"] as? String {
            return (text, false)
        }
        return (nil, false)
    }

    /// Parses an SSE `event:` / `data:` line emitted by Anthropic's `/v1/messages` stream.
    static func parseAnthropicSSELine(_ line: String) -> (token: String?, done: Bool) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, false) }
        if trimmed.hasPrefix("event:") {
            let eventName = trimmed.dropFirst(6).trimmingCharacters(in: .whitespaces)
            return (nil, eventName == "message_stop")
        }
        guard trimmed.hasPrefix("data:") else { return (nil, false) }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return (nil, true) }
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, false)
        }
        let eventType = object["type"] as? String
        if eventType == "message_stop" {
            return (nil, true)
        }
        if eventType == nil || eventType == "content_block_delta" {
            if let delta = object["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                return (text, false)
            }
        }
        return (nil, false)
    }

    private static func parseSSEErrorMessage(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonText: String
        if trimmed.hasPrefix("data:") {
            jsonText = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        } else {
            jsonText = trimmed
        }
        guard let data = jsonText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }
        return nil
    }

    private final class WeakBox<T: AnyObject>: @unchecked Sendable {
        weak var value: T?
        init(_ value: T) { self.value = value }
    }

    private final class StreamBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()

        func appendAndDecodeUTF8(_ chunk: Data) -> String {
            lock.withLock {
                buffer.append(chunk)
                return decodeAvailableUTF8()
            }
        }

        func drainLossy() -> String {
            lock.withLock {
                guard !buffer.isEmpty else { return "" }
                let str = String(decoding: buffer, as: UTF8.self)
                buffer.removeAll()
                return str
            }
        }

        private func decodeAvailableUTF8() -> String {
            guard !buffer.isEmpty else { return "" }
            if let full = String(data: buffer, encoding: .utf8) {
                buffer.removeAll()
                return full
            }
            // Hold back up to 3 trailing incomplete UTF-8 continuation/lead bytes until the next chunk.
            for drop in 1...min(3, buffer.count) {
                let candidate = buffer.dropLast(drop)
                if let decoded = String(data: candidate, encoding: .utf8) {
                    buffer = Data(buffer.suffix(drop))
                    return decoded
                }
            }
            let decoded = String(decoding: buffer, as: UTF8.self)
            buffer.removeAll()
            return decoded
        }
    }

    /// Sends a multi-turn thread (with optional PNG base64 vision attachments on turns)
    /// while resolving `@clipboard`, `@frontApp`, `@selection`, and `@browser` context on the latest user turn.
    func sendConversation(
        messages: [AIChatMessage],
        attachedTokens: Set<QuickAIContextToken> = [],
        rawModel: String? = nil,
        onCompletion: ((String) -> Void)? = nil
    ) {
        let nonEmpty = messages.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || ($0.imagePNGDataBase64?.isEmpty == false)
        }
        guard let last = nonEmpty.last else { return }

        let allTokens = attachedTokens.union(QuickAIContextResolver.tokensPresent(in: last.text))
        if allTokens.isEmpty {
            dispatchConversation(nonEmpty, rawModel: rawModel, onCompletion: onCompletion)
            return
        }

        beginThinking(prompt: last.text, onCompletion: onCompletion)
        let box = WeakBox(self)
        streamTask = Task {
            let snapshot = await QuickAIContextResolver.captureLiveContext(
                includeClipboard: allTokens.contains(.clipboard),
                includeFrontApp: allTokens.contains(.frontApp),
                includeSelection: allTokens.contains(.selection),
                includeBrowser: allTokens.contains(.browser)
            )
            if Task.isCancelled { return }
            let resolvedText = QuickAIContextResolver.resolvePrompt(
                last.text,
                attachedTokens: attachedTokens,
                snapshot: snapshot
            )
            var updated = nonEmpty
            let replacement = AIChatMessage(
                id: last.id,
                role: last.role,
                text: resolvedText,
                imagePNGDataBase64: last.imagePNGDataBase64,
                createdAt: last.createdAt
            )
            updated[updated.count - 1] = replacement
            let finalMessages = updated
            await MainActor.run {
                guard let service = box.value, service.isStreaming else { return }
                service.streamTask = nil
                service.dispatchConversation(finalMessages, rawModel: rawModel, onCompletion: onCompletion)
            }
        }
    }

    private func dispatchConversation(
        _ messages: [AIChatMessage],
        rawModel: String? = nil,
        onCompletion: ((String) -> Void)? = nil
    ) {
        guard let last = messages.last else { return }
        let customModel = rawModel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = (customModel?.isEmpty == false) ? customModel : nil

        switch selectedProvider {
        case .ollama:
            let hasVisionOrHistory = messages.count > 1 || messages.contains(where: { $0.imagePNGDataBase64?.isEmpty == false })
            if hasVisionOrHistory {
                askLocalOllamaConversation(messages: messages, model: model ?? "llama3.2", onCompletion: onCompletion)
            } else {
                askLocalOllama(prompt: last.text, model: model ?? "llama3.2", onCompletion: onCompletion)
            }
        case .claudeCLI:
            askCLI(provider: .claudeCLI, prompt: Self.flattenedConversationPrompt(messages), onCompletion: onCompletion)
        case .codexCLI:
            askCLI(provider: .codexCLI, prompt: Self.flattenedConversationPrompt(messages), onCompletion: onCompletion)
        case .byokOpenAI:
            askOpenAIConversation(messages: messages, model: model ?? "gpt-4o-mini", onCompletion: onCompletion)
        case .byokAnthropic:
            askAnthropicConversation(messages: messages, model: model ?? "claude-3-5-sonnet-latest", onCompletion: onCompletion)
        }
    }

    private static func flattenedConversationPrompt(_ messages: [AIChatMessage]) -> String {
        if messages.count == 1, let only = messages.first, only.imagePNGDataBase64 == nil {
            return only.text
        }
        return messages.map { message in
            let speaker = message.role == "assistant" ? "Assistant" : "User"
            if let b64 = message.imagePNGDataBase64, !b64.isEmpty {
                return "\(speaker): [Attached PNG image (\(b64.count) base64 chars)]\n\(message.text)"
            }
            return "\(speaker): \(message.text)"
        }.joined(separator: "\n\n")
    }

    /// Resolves `@clipboard`, `@frontApp`, `@selection`, and `@browser` context tokens
    /// asynchronously off the main thread before dispatching to the active provider.
    func sendContextualPrompt(
        _ rawPrompt: String,
        attachedTokens: Set<QuickAIContextToken> = [],
        rawModel: String? = nil
    ) {
        let cleanPrompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { return }

        let allTokens = attachedTokens.union(QuickAIContextResolver.tokensPresent(in: cleanPrompt))
        if allTokens.isEmpty {
            sendPrompt(cleanPrompt, rawModel: rawModel)
            return
        }

        beginThinking(prompt: cleanPrompt)
        let box = WeakBox(self)
        streamTask = Task {
            let snapshot = await QuickAIContextResolver.captureLiveContext(
                includeClipboard: allTokens.contains(.clipboard),
                includeFrontApp: allTokens.contains(.frontApp),
                includeSelection: allTokens.contains(.selection),
                includeBrowser: allTokens.contains(.browser)
            )
            if Task.isCancelled { return }
            let resolved = QuickAIContextResolver.resolvePrompt(
                cleanPrompt,
                attachedTokens: attachedTokens,
                snapshot: snapshot
            )
            await MainActor.run {
                guard let service = box.value, service.isStreaming else { return }
                service.streamTask = nil
                service.sendPrompt(resolved, rawModel: rawModel)
            }
        }
    }

    func sendPrompt(_ prompt: String, rawModel: String? = nil) {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { return }
        let customModel = rawModel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = (customModel?.isEmpty == false) ? customModel : nil

        switch selectedProvider {
        case .ollama:
            askLocalOllama(prompt: cleanPrompt, model: model ?? "llama3.2")
        case .claudeCLI:
            askCLI(provider: .claudeCLI, prompt: cleanPrompt)
        case .codexCLI:
            askCLI(provider: .codexCLI, prompt: cleanPrompt)
        case .byokOpenAI:
            askOpenAI(prompt: cleanPrompt, model: model ?? "gpt-4o-mini")
        case .byokAnthropic:
            askAnthropic(prompt: cleanPrompt, model: model ?? "claude-3-5-sonnet-latest")
        }
    }

    func askLocalOllama(
        prompt: String,
        model: String = "llama3.2",
        endpoint: URL = URL(string: "http://127.0.0.1:11434/api/generate")!,
        onCompletion: ((String) -> Void)? = nil
    ) {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { return }
        let body: [String: Any] = ["model": model, "prompt": cleanPrompt, "stream": true]
        streamOllamaRequest(promptTitle: cleanPrompt, endpoint: endpoint, body: body, onCompletion: onCompletion)
    }

    func askLocalOllamaConversation(
        messages: [AIChatMessage],
        model: String = "llama3.2",
        endpoint: URL = URL(string: "http://127.0.0.1:11434/api/chat")!,
        onCompletion: ((String) -> Void)? = nil
    ) {
        guard let last = messages.last else { return }
        let payloadMessages: [[String: Any]] = messages.map { msg in
            var entry: [String: Any] = [
                "role": msg.role == "assistant" ? "assistant" : "user",
                "content": msg.text,
            ]
            if let b64 = msg.imagePNGDataBase64, !b64.isEmpty {
                entry["images"] = [b64]
            }
            return entry
        }
        let body: [String: Any] = ["model": model, "messages": payloadMessages, "stream": true]
        streamOllamaRequest(promptTitle: last.text, endpoint: endpoint, body: body, onCompletion: onCompletion)
    }

    private func streamOllamaRequest(
        promptTitle: String,
        endpoint: URL,
        body: [String: Any],
        onCompletion: ((String) -> Void)?
    ) {
        beginThinking(prompt: promptTitle, onCompletion: onCompletion)
        guard let encodedBody = try? JSONSerialization.data(withJSONObject: body) else {
            finishWithError("Failed to encode Ollama request.")
            return
        }
        let box = WeakBox(self)
        streamTask = Task {
            do {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 30
                request.httpBody = encodedBody
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    await MainActor.run {
                        box.value?.finishWithError("HTTP \(http.statusCode)")
                    }
                    return
                }
                for try await line in bytes.lines {
                    if Task.isCancelled { return }
                    let parsed = Self.parseOllamaStreamLine(line)
                    await MainActor.run {
                        if let token = parsed.token { box.value?.appendStreamChunk(token) }
                        if parsed.done { box.value?.finishSuccess() }
                    }
                }
                await MainActor.run {
                    if box.value?.isStreaming == true { box.value?.finishSuccess() }
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    box.value?.finishWithError(error.localizedDescription)
                }
            }
        }
    }

    func askOpenAI(
        prompt: String,
        model: String = "gpt-4o-mini",
        endpoint: URL = URL(string: "https://api.openai.com/v1/chat/completions")!
    ) {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { return }
        askOpenAIConversation(
            messages: [AIChatMessage(role: "user", text: cleanPrompt)],
            model: model,
            endpoint: endpoint
        )
    }

    func askOpenAIConversation(
        messages: [AIChatMessage],
        model: String = "gpt-4o-mini",
        endpoint: URL = URL(string: "https://api.openai.com/v1/chat/completions")!,
        onCompletion: ((String) -> Void)? = nil
    ) {
        guard let last = messages.last else { return }
        beginThinking(prompt: last.text, onCompletion: onCompletion)
        guard let key = apiKey(for: .byokOpenAI), !key.isEmpty else {
            missingKeyProvider = .byokOpenAI
            finishWithError("OpenAI API key is not configured in Keychain.")
            return
        }

        let payloadMessages: [[String: Any]] = messages.map { msg in
            let role = msg.role == "assistant" ? "assistant" : "user"
            if role == "user", let b64 = msg.imagePNGDataBase64, !b64.isEmpty {
                let parts: [[String: Any]] = [
                    ["type": "text", "text": msg.text.isEmpty ? "Describe this image." : msg.text],
                    ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(b64)"]],
                ]
                return ["role": role, "content": parts]
            }
            return ["role": role, "content": msg.text]
        }
        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": payloadMessages,
        ]
        guard let encodedBody = try? JSONSerialization.data(withJSONObject: body) else {
            finishWithError("Failed to encode OpenAI request.")
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        request.httpBody = encodedBody
        streamSSERequest(request) { Self.parseOpenAISSELine($0) }
    }

    func askAnthropic(
        prompt: String,
        model: String = "claude-3-5-sonnet-latest",
        endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!
    ) {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { return }
        askAnthropicConversation(
            messages: [AIChatMessage(role: "user", text: cleanPrompt)],
            model: model,
            endpoint: endpoint
        )
    }

    func askAnthropicConversation(
        messages: [AIChatMessage],
        model: String = "claude-3-5-sonnet-latest",
        endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
        onCompletion: ((String) -> Void)? = nil
    ) {
        guard let last = messages.last else { return }
        beginThinking(prompt: last.text, onCompletion: onCompletion)
        guard let key = apiKey(for: .byokAnthropic), !key.isEmpty else {
            missingKeyProvider = .byokAnthropic
            finishWithError("Anthropic API key is not configured in Keychain.")
            return
        }

        // Normalize alternating user/assistant turns required by Anthropic's Messages API.
        var normalizedTurns: [(role: String, blocks: [[String: Any]])] = []
        for msg in messages {
            let role = msg.role == "assistant" ? "assistant" : "user"
            var blocks: [[String: Any]] = []
            if role == "user", let b64 = msg.imagePNGDataBase64, !b64.isEmpty {
                blocks.append([
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": "image/png",
                        "data": b64,
                    ],
                ])
            }
            let text = msg.text.isEmpty ? "Describe this image." : msg.text
            blocks.append(["type": "text", "text": text])
            if let lastTurn = normalizedTurns.last, lastTurn.role == role {
                normalizedTurns[normalizedTurns.count - 1].blocks.append(contentsOf: blocks)
            } else {
                normalizedTurns.append((role: role, blocks: blocks))
            }
        }
        let payloadMessages: [[String: Any]] = normalizedTurns.map { turn in
            ["role": turn.role, "content": turn.blocks]
        }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "stream": true,
            "messages": payloadMessages,
        ]
        guard let encodedBody = try? JSONSerialization.data(withJSONObject: body) else {
            finishWithError("Failed to encode Anthropic request.")
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 60
        request.httpBody = encodedBody
        streamSSERequest(request) { Self.parseAnthropicSSELine($0) }
    }

    private func streamSSERequest(
        _ request: URLRequest,
        parseLine: @escaping @Sendable (String) -> (token: String?, done: Bool)
    ) {
        let box = WeakBox(self)
        streamTask = Task {
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    var errorDetail: String?
                    for try await line in bytes.lines.prefix(8) {
                        if let parsed = Self.parseSSEErrorMessage(from: line) {
                            errorDetail = parsed
                            break
                        }
                    }
                    let message = errorDetail ?? "HTTP \(http.statusCode)"
                    await MainActor.run { box.value?.finishWithError(message) }
                    return
                }
                for try await line in bytes.lines {
                    if Task.isCancelled { return }
                    if let err = Self.parseSSEErrorMessage(from: line) {
                        await MainActor.run { box.value?.finishWithError(err) }
                        return
                    }
                    let parsed = parseLine(line)
                    await MainActor.run {
                        if let token = parsed.token { box.value?.appendStreamChunk(token) }
                        if parsed.done { box.value?.finishSuccess() }
                    }
                }
                await MainActor.run {
                    if box.value?.isStreaming == true { box.value?.finishSuccess() }
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run { box.value?.finishWithError(error.localizedDescription) }
            }
        }
    }

    func askCLI(
        provider: QuickAIProvider,
        prompt: String,
        searchPaths: [String] = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"],
        onCompletion: ((String) -> Void)? = nil
    ) {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { return }

        let binaryName: String
        let args: [String]
        switch provider {
        case .claudeCLI:
            binaryName = "claude"
            args = ["-p", cleanPrompt]
        case .codexCLI:
            binaryName = "codex"
            args = ["exec", cleanPrompt]
        default:
            beginThinking(prompt: cleanPrompt, onCompletion: onCompletion)
            finishWithError("\(provider.displayName) is not a CLI provider.")
            return
        }

        beginThinking(prompt: cleanPrompt, onCompletion: onCompletion)

        let fileManager = FileManager.default
        guard let executablePath = searchPaths
            .map({ "\($0)/\(binaryName)" })
            .first(where: { fileManager.isExecutableFile(atPath: $0) }) else {
            finishWithError("\(binaryName) CLI was not found in \(searchPaths.joined(separator: ", ")).")
            return
        }

        let box = WeakBox(self)
        let outBuffer = StreamBuffer()
        let errBuffer = StreamBuffer()

        streamTask = Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = args
            var env = ProcessInfo.processInfo.environment
            let existingPath = env["PATH"] ?? ""
            let combinedPaths = (searchPaths + existingPath.split(separator: ":").map(String.init))
            var seenPath = Set<String>()
            env["PATH"] = combinedPaths.filter { seenPath.insert($0).inserted }.joined(separator: ":")
            process.environment = env
            process.standardInput = FileHandle.nullDevice

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                let text = outBuffer.appendAndDecodeUTF8(data)
                if !text.isEmpty {
                    DispatchQueue.main.async {
                        guard let service = box.value, service.isStreaming else { return }
                        service.appendStreamChunk(text)
                    }
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                _ = errBuffer.appendAndDecodeUTF8(data)
            }

            process.terminationHandler = { proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                let trailingOut = outBuffer.drainLossy()
                let errText = errBuffer.drainLossy().trimmingCharacters(in: .whitespacesAndNewlines)

                DispatchQueue.main.async {
                    guard let service = box.value else { return }
                    service.processLock.withLock {
                        if service.activeProcess === proc { service.activeProcess = nil }
                    }
                    guard service.isStreaming else { return }
                    if !trailingOut.isEmpty {
                        service.appendStreamChunk(trailingOut)
                    }
                    if proc.terminationStatus == 0 {
                        service.finishSuccess()
                    } else {
                        let detail = !errText.isEmpty
                            ? errText
                            : "\(binaryName) exited with status \(proc.terminationStatus)."
                        service.finishWithError(detail)
                    }
                }
            }

            do {
                box.value?.processLock.withLock {
                    box.value?.activeProcess = process
                }
                try process.run()
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                box.value?.processLock.withLock {
                    if box.value?.activeProcess === process { box.value?.activeProcess = nil }
                }
                await MainActor.run {
                    guard let service = box.value, service.isStreaming else { return }
                    service.finishWithError(error.localizedDescription)
                }
            }
        }
    }
}

/// Execution mode parsed from Script Command v2 headers (`@vorssaint.mode` or `@raycast.mode`).
enum ScriptCommandOutputMode: String, CaseIterable, Codable, Equatable, Sendable {
    case compact
    case fullOutput
    case inline
    case silent
    case json
}

struct ScriptCommandArgumentSpec: Equatable, Codable, Sendable {
    let index: Int
    let type: String
    let placeholder: String
    let optional: Bool
    let secure: Bool
}

struct ScriptCommandMetadata: Equatable, Sendable {
    var title: String?
    var mode: ScriptCommandOutputMode = .compact
    var icon: String?
    var packageName: String?
    var description: String?
    var refreshTime: String?
    var arguments: [ScriptCommandArgumentSpec] = []
}

struct ScriptCommandJSONPayload: Decodable, Equatable, Sendable {
    let title: String
    let subtitle: String?
    let copyText: String?
    let badge: String?
    let openURL: String?
    let markdownBody: String?
    let actions: [PluginActionItem]?
    let formFields: [PluginFormField]?

    init(title: String,
         subtitle: String? = nil,
         copyText: String? = nil,
         badge: String? = nil,
         openURL: String? = nil,
         markdownBody: String? = nil,
         actions: [PluginActionItem]? = nil,
         formFields: [PluginFormField]? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.copyText = copyText
        self.badge = badge
        self.openURL = openURL
        self.markdownBody = markdownBody
        self.actions = actions
        self.formFields = formFields
    }
}

/// Parses Raycast-compatible and Vorssaint-native comment metadata headers and JSON outputs.
enum ScriptCommandHeaderParser {
    static func parseMetadata(fromScriptSource source: String) -> ScriptCommandMetadata {
        var meta = ScriptCommandMetadata()
        var argsByIndex: [Int: ScriptCommandArgumentSpec] = [:]

        for rawLine in source.components(separatedBy: .newlines).prefix(40) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") || trimmed.hasPrefix("//") else { continue }
            let withoutComment = trimmed
                .replacingOccurrences(of: #"^(#|//)\s*"#, with: "", options: .regularExpression)
            guard let tagRange = withoutComment.range(
                of: #"^@(raycast|vorssaint|basalt)\.([A-Za-z0-9_]+)\s+(.+)$"#,
                options: .regularExpression
            ) else { continue }
            let matched = String(withoutComment[tagRange])
            let parts = matched.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard parts.count == 2 else { continue }
            let key = parts[0].split(separator: ".").last.map(String.init) ?? ""
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            switch key {
            case "title":
                meta.title = value
            case "mode":
                if let parsed = ScriptCommandOutputMode(rawValue: value) {
                    meta.mode = parsed
                }
            case "icon":
                meta.icon = value
            case "packageName":
                meta.packageName = value
            case "description":
                meta.description = value
            case "refreshTime":
                meta.refreshTime = value
            case "argument1", "argument2", "argument3":
                let index = Int(String(key.last ?? "1")) ?? 1
                if let spec = parseArgumentJSON(value, index: index) {
                    argsByIndex[index] = spec
                }
            default:
                break
            }
        }
        meta.arguments = argsByIndex.keys.sorted().compactMap { argsByIndex[$0] }
        return meta
    }

    private static func parseArgumentJSON(_ jsonText: String, index: Int) -> ScriptCommandArgumentSpec? {
        guard let data = jsonText.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let type = dict["type"] as? String ?? "text"
        let placeholder = dict["placeholder"] as? String ?? ""
        let optional = dict["optional"] as? Bool ?? false
        let secure = dict["secure"] as? Bool ?? (type == "password")
        return ScriptCommandArgumentSpec(index: index,
                                         type: type,
                                         placeholder: placeholder,
                                         optional: optional,
                                         secure: secure)
    }

    static func parseJSONOutput(_ stdout: String) -> ScriptCommandJSONPayload? {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ScriptCommandJSONPayload.self, from: data)
    }
}
