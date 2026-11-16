// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

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
    private static let service = "com.vorssaint.utils.quickai"

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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
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

/// Manages Quick AI sessions (`Tab` in Command Bar), Keychain BYOK keys, CLI probing, and droplet mood sync.
final class CommandBarQuickAIService: ObservableObject, @unchecked Sendable {
    static let shared = CommandBarQuickAIService()

    @Published private(set) var isStreaming = false
    @Published private(set) var responseText = ""
    @Published private(set) var lastPrompt = ""
    @Published private(set) var errorText: String?
    @Published private(set) var dropletState: CommandBarQuickAIDropletState = .idle
    @Published var selectedProvider: QuickAIProvider = .ollama

    private let secretStore: any QuickAISecretStore
    private var streamTask: Task<Void, Never>?

    init(secretStore: any QuickAISecretStore = KeychainQuickAISecretStore()) {
        self.secretStore = secretStore
    }

    deinit {
        streamTask?.cancel()
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

    func beginThinking(prompt: String) {
        streamTask?.cancel()
        lastPrompt = prompt
        responseText = ""
        errorText = nil
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
    }

    func finishWithError(_ message: String) {
        isStreaming = false
        errorText = message
        dropletState = .idle
    }

    func reset() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        responseText = ""
        errorText = nil
        dropletState = .idle
    }

    /// Parses one NDJSON line emitted by Ollama's `/api/generate` endpoint.
    static func parseOllamaStreamLine(_ line: String) -> (token: String?, done: Bool) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, false)
        }
        let token = object["response"] as? String
        let done = object["done"] as? Bool ?? false
        return (token, done)
    }

    /// Parses an SSE `data:` line in OpenAI/Anthropic chat completion streams.
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

    private final class WeakBox<T: AnyObject>: @unchecked Sendable {
        weak var value: T?
        init(_ value: T) { self.value = value }
    }

    func askLocalOllama(prompt: String, model: String = "llama3.2", endpoint: URL = URL(string: "http://127.0.0.1:11434/api/generate")!) {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { return }
        beginThinking(prompt: cleanPrompt)
        let box = WeakBox(self)
        streamTask = Task {
            do {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 30
                let body: [String: Any] = ["model": model, "prompt": cleanPrompt, "stream": true]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
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
                of: #"^@(raycast|vorssaint)\.([A-Za-z0-9_]+)\s+(.+)$"#,
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
