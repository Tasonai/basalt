// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreGraphics
import CryptoKit
import Darwin
import Foundation
import os
import Security
import SwiftUI
import Vision

/// Named theme board holding pinned clipboard item identifiers.
struct ClipboardPinboard: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var colorHex: String
    var entryIDs: [UUID]

    init(id: UUID = UUID(), name: String, colorHex: String = "#3B82F6", entryIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.entryIDs = entryIDs
    }
}

/// Persists thematic Clipboard 2.0 pinboards in injectable `UserDefaults` storage.
final class ClipboardPinboardStore: ObservableObject {
    static let shared = ClipboardPinboardStore()

    @Published private(set) var pinboards: [ClipboardPinboard] = []
    @Published var activePinboardID: UUID?

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "clipboardPinboardsJSON") {
        self.defaults = defaults
        self.key = key
        load()
    }

    @discardableResult
    func createBoard(name: String, colorHex: String = "#3B82F6") -> ClipboardPinboard {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let board = ClipboardPinboard(name: trimmed.isEmpty ? "Board" : trimmed, colorHex: colorHex)
        pinboards.append(board)
        save()
        return board
    }

    func renameBoard(id: UUID, name: String) {
        guard let idx = pinboards.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pinboards[idx].name = trimmed
        save()
    }

    func deleteBoard(id: UUID) {
        pinboards.removeAll { $0.id == id }
        if activePinboardID == id { activePinboardID = nil }
        save()
    }

    func updateBoardColor(id: UUID, colorHex: String) {
        guard let idx = pinboards.firstIndex(where: { $0.id == id }) else { return }
        pinboards[idx].colorHex = colorHex
        save()
    }

    func isEntry(_ entryID: UUID, in boardID: UUID) -> Bool {
        pinboards.first(where: { $0.id == boardID })?.entryIDs.contains(entryID) == true
    }

    @discardableResult
    func mergeImportedBoards(_ imported: [ClipboardPinboard]) -> Int {
        var addedOrMerged = 0
        for board in imported {
            if let idx = pinboards.firstIndex(where: { $0.id == board.id }) {
                var existingSet = Set(pinboards[idx].entryIDs)
                for entryID in board.entryIDs where existingSet.insert(entryID).inserted {
                    pinboards[idx].entryIDs.append(entryID)
                    addedOrMerged += 1
                }
            } else {
                pinboards.append(board)
                addedOrMerged += 1
            }
        }
        if addedOrMerged > 0 { save() }
        return addedOrMerged
    }

    func assignEntry(_ entryID: UUID, to boardID: UUID) {
        guard let idx = pinboards.firstIndex(where: { $0.id == boardID }) else { return }
        if !pinboards[idx].entryIDs.contains(entryID) {
            pinboards[idx].entryIDs.append(entryID)
            save()
        }
    }

    func removeEntry(_ entryID: UUID, from boardID: UUID) {
        guard let idx = pinboards.firstIndex(where: { $0.id == boardID }) else { return }
        pinboards[idx].entryIDs.removeAll { $0 == entryID }
        save()
    }

    func entries(in boardID: UUID?, from all: [ClipboardHistoryEntry]) -> [ClipboardHistoryEntry] {
        guard let boardID, let board = pinboards.first(where: { $0.id == boardID }) else {
            return all
        }
        let ids = Set(board.entryIDs)
        return all.filter { ids.contains($0.id) }
    }

    private func load() {
        guard let raw = defaults.string(forKey: key),
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([ClipboardPinboard].self, from: data) else {
            pinboards = []
            return
        }
        pinboards = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(pinboards),
              let raw = String(data: data, encoding: .utf8) else { return }
        defaults.set(raw, forKey: key)
    }
}

/// FIFO sequential paste stack (`⌘⌃V`) for Clipboard 2.0.
final class ClipboardPasteStack: ObservableObject {
    static let shared = ClipboardPasteStack()

    @Published private(set) var queue: [ClipboardHistoryEntry] = []
    @Published var isRecording = false

    var count: Int { queue.count }
    var isActive: Bool { isRecording || !queue.isEmpty }

    func enqueue(_ entry: ClipboardHistoryEntry) {
        queue.append(entry)
    }

    func enqueueBatch(_ entries: [ClipboardHistoryEntry]) {
        queue.append(contentsOf: entries)
    }

    func peekNext() -> ClipboardHistoryEntry? {
        queue.first
    }

    @discardableResult
    func popNext() -> ClipboardHistoryEntry? {
        guard !queue.isEmpty else { return nil }
        return queue.removeFirst()
    }

    func clear() {
        queue.removeAll()
    }
}

/// Local Vision framework OCR extractor for indexing copied screenshots and images offline.
enum ClipboardImageOCRIndexer {
    static func recognizeText(in cgImage: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }
        let lines = (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first?.string
        }
        return lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

/// Built-in deterministic text and developer data transformations.
enum ClipboardTransformKind: String, CaseIterable, Identifiable, Sendable {
    case jsonPretty
    case jsonMinify
    case base64Encode
    case base64Decode
    case jwtDecode
    case urlEncode
    case urlDecode
    case sha256
    case colorOKLCH

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .jsonPretty: return "Pretty JSON"
        case .jsonMinify: return "Minify JSON"
        case .jwtDecode: return "JWT Decode"
        case .base64Encode: return "Base64 Encode"
        case .base64Decode: return "Base64 Decode"
        case .urlEncode: return "URL Encode"
        case .urlDecode: return "URL Decode"
        case .sha256: return "SHA-256"
        case .colorOKLCH: return "OKLCH"
        }
    }

    var compactLabel: String {
        switch self {
        case .jsonPretty: return "Pretty JSON"
        case .jsonMinify: return "Minify JSON"
        case .jwtDecode: return "JWT Decode"
        case .base64Encode: return "Base64 +"
        case .base64Decode: return "Base64 −"
        case .urlEncode: return "URL +"
        case .urlDecode: return "URL −"
        case .sha256: return "SHA-256"
        case .colorOKLCH: return "OKLCH"
        }
    }
}

enum ClipboardTransformEngine {
    static func apply(_ kind: ClipboardTransformKind, to input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .jsonPretty:
            return formatJSON(trimmed, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        case .jsonMinify:
            return formatJSON(trimmed, options: [.sortedKeys, .withoutEscapingSlashes])
        case .base64Encode:
            return Data(input.utf8).base64EncodedString()
        case .base64Decode:
            var normalized = trimmed
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            let mod = normalized.count % 4
            if mod > 0 { normalized += String(repeating: "=", count: 4 - mod) }
            guard let data = Data(base64Encoded: normalized),
                  let str = String(data: data, encoding: .utf8) else { return nil }
            return str
        case .jwtDecode:
            return decodeJWT(trimmed)
        case .urlEncode:
            return input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        case .urlDecode:
            return input.removingPercentEncoding
        case .sha256:
            let digest = SHA256.hash(data: Data(input.utf8))
            return digest.map { String(format: "%02x", $0) }.joined()
        case .colorOKLCH:
            guard let color = ColorValue(text: trimmed) else { return nil }
            return ColorValue.string(red: color.red,
                                     green: color.green,
                                     blue: color.blue,
                                     alpha: color.alpha < 0.999 ? color.alpha : nil,
                                     format: .oklch)
        }
    }

    private static func formatJSON(_ raw: String, options: JSONSerialization.WritingOptions) -> String? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let formatted = try? JSONSerialization.data(withJSONObject: object, options: options) else {
            return nil
        }
        return String(data: formatted, encoding: .utf8)
    }

    private static func decodeJWT(_ token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2,
              let headerStr = apply(.base64Decode, to: parts[0]),
              let payloadStr = apply(.base64Decode, to: parts[1]) else {
            return nil
        }
        let headerOut = formatJSON(headerStr, options: [.prettyPrinted, .sortedKeys]) ?? headerStr
        let payloadOut = formatJSON(payloadStr, options: [.prettyPrinted, .sortedKeys]) ?? payloadStr
        return "HEADER:\n\(headerOut)\n\nPAYLOAD:\n\(payloadOut)"
    }
}

/// Zero-CloudKit end-to-end encrypted `.vorssaintvault` sync archive powered by `CryptoKit` (`HKDF` + `AES.GCM`).
enum ClipboardSyncVault {
    enum VaultError: Error, Equatable {
        case emptyPassphrase
        case invalidEnvelope
        case wrongPassphraseOrTampered
    }

    private static let magic = Data("VVLT1".utf8)
    private static let version: UInt8 = 1
    private static let saltLength = 16
    private static let hkdfInfo = Data("vorssaint.clipboard.vault.v1".utf8)

    static func encrypt(_ plaintext: Data, passphrase: String) throws -> Data {
        guard !passphrase.isEmpty else { throw VaultError.emptyPassphrase }

        var saltBytes = [UInt8](repeating: 0, count: saltLength)
        let status = SecRandomCopyBytes(kSecRandomDefault, saltLength, &saltBytes)
        let salt = status == errSecSuccess ? Data(saltBytes) : Data(SHA256.hash(data: Data(UUID().uuidString.utf8)).prefix(saltLength))

        let key = deriveKey(passphrase: passphrase, salt: salt)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw VaultError.invalidEnvelope }

        var envelope = Data()
        envelope.append(magic)
        envelope.append(version)
        envelope.append(salt)
        envelope.append(combined)
        return envelope
    }

    static func decrypt(_ envelope: Data, passphrase: String) throws -> Data {
        guard !passphrase.isEmpty else { throw VaultError.emptyPassphrase }
        let headerSize = magic.count + 1 + saltLength
        guard envelope.count > headerSize + 28,
              envelope.prefix(magic.count) == magic,
              envelope[envelope.startIndex + magic.count] == version else {
            throw VaultError.invalidEnvelope
        }

        let saltStart = envelope.startIndex + magic.count + 1
        let saltEnd = saltStart + saltLength
        let salt = envelope[saltStart..<saltEnd]
        let combined = envelope[saltEnd..<envelope.endIndex]

        let key = deriveKey(passphrase: passphrase, salt: salt)
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw VaultError.wrongPassphraseOrTampered
        }
    }

    static func seal(_ plaintext: Data, to fileURL: URL, passphrase: String) throws {
        let envelope = try encrypt(plaintext, passphrase: passphrase)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try envelope.write(to: fileURL, options: .atomic)
    }

    static func open(from fileURL: URL, passphrase: String) throws -> Data {
        let envelope = try Data(contentsOf: fileURL)
        return try decrypt(envelope, passphrase: passphrase)
    }

    private static func deriveKey(passphrase: String, salt: Data) -> SymmetricKey {
        let ikm = SymmetricKey(data: Data(passphrase.utf8))
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm,
                                      salt: salt,
                                      info: hkdfInfo,
                                      outputByteCount: 32)
    }
}

/// Portable encrypted vault payload capturing clipboard entries and thematic pinboards.
struct ClipboardVaultSnapshot: Codable, Equatable, Sendable {
    var entries: [ClipboardHistoryEntry]
    var pinboards: [ClipboardPinboard]
    var exportedAt: Date

    init(entries: [ClipboardHistoryEntry],
         pinboards: [ClipboardPinboard] = [],
         exportedAt: Date = Date()) {
        self.entries = entries
        self.pinboards = pinboards
        self.exportedAt = exportedAt
    }
}

/// Abstraction for persisting the `.vorssaintvault` sync passphrase cleanly in macOS Keychain or memory.
protocol ClipboardVaultSecretStore {
    func saveSecret(_ value: String, account: String) -> Bool
    func loadSecret(account: String) -> String?
    func deleteSecret(account: String) -> Bool
}

extension ClipboardVaultSecretStore {
    @discardableResult
    func saveSecret(_ value: String) -> Bool {
        saveSecret(value, account: KeychainClipboardVaultSecretStore.defaultAccount)
    }

    func loadSecret() -> String? {
        loadSecret(account: KeychainClipboardVaultSecretStore.defaultAccount)
    }

    @discardableResult
    func deleteSecret() -> Bool {
        deleteSecret(account: KeychainClipboardVaultSecretStore.defaultAccount)
    }
}

/// Keychain-backed store (`kSecClassGenericPassword`, service `com.tasonai.basalt.vault`) for vault passphrases.
struct KeychainClipboardVaultSecretStore: ClipboardVaultSecretStore {
    static let defaultService = "com.tasonai.basalt.vault"
    private static let legacyService = "com.vorssaint.utils.vault"
    static let defaultAccount = "vorssaint.clipboard.vault.passphrase"
    private let service: String

    init(service: String = KeychainClipboardVaultSecretStore.defaultService) {
        self.service = service
    }

    func saveSecret(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    func loadSecret(account: String) -> String? {
        if let value = loadSecret(account: account, service: service) {
            return value
        }
        if service == Self.defaultService {
            return loadSecret(account: account, service: Self.legacyService)
        }
        return nil
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
        let primary = deleteSecret(account: account, service: service)
        if service == Self.defaultService {
            let legacy = deleteSecret(account: account, service: Self.legacyService)
            return primary && legacy
        }
        return primary
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

/// Ephemeral in-memory vault secret store for deterministic unit testing without Keychain prompts.
final class InMemoryClipboardVaultSecretStore: ClipboardVaultSecretStore {
    private var entries: [String: String] = [:]

    func saveSecret(_ value: String, account: String) -> Bool {
        entries[account] = value
        return true
    }

    func loadSecret(account: String) -> String? {
        entries[account]
    }

    @discardableResult
    func deleteSecret(account: String) -> Bool {
        entries.removeValue(forKey: account)
        return true
    }
}

/// Pure tokenizer and syntax highlighter for Clipboard 2.0 code & JSON previews.
enum ClipboardSyntaxHighlighter {
    enum Language: String, CaseIterable, Equatable, Sendable {
        case json
        case swift
        case python
        case js
        case sql
        case shell
        case plain

        var badgeTitle: String {
            switch self {
            case .json: return "JSON"
            case .swift: return "Swift"
            case .python: return "Python"
            case .js: return "JS / TS"
            case .sql: return "SQL"
            case .shell: return "Shell"
            case .plain: return "Text"
            }
        }
    }

    enum TokenKind: String, Equatable, Sendable {
        case keyword
        case string
        case comment
        case number
        case key
        case plain
    }

    struct Token: Equatable, Sendable {
        let kind: TokenKind
        let range: Range<String.Index>
    }

    static let maxHighlightCharacters = 40_000

    private static let jsonRegex = try? NSRegularExpression(
        pattern: #"("(?:[^"\\\r\n]|\\.)*")(?=\s*:)|("(?:[^"\\\r\n]|\\.)*")|(-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b)|\b(true|false|null)\b"#
    )
    private static let swiftRegex = try? NSRegularExpression(
        pattern: #"(//[^\r\n]*|/\*[\s\S]*?\*/)|("(?:[^"\\\r\n]|\\.)*")|(\b[A-Za-z_][A-Za-z0-9_]*\b(?=\s*:))|(\b(?:0x[0-9A-Fa-f]+|\d+(?:\.\d+)?)\b)|(\b(?:import|struct|class|enum|protocol|extension|func|var|let|if|else|guard|switch|case|default|for|while|repeat|return|throw|throws|try|catch|async|await|actor|private|fileprivate|internal|public|static|final|override|init|deinit|self|Self|true|false|nil|in|where|as|is|some|any)\b)"#
    )
    private static let pythonRegex = try? NSRegularExpression(
        pattern: #"(#[^\r\n]*)|("(?:[^"\\\r\n]|\\.)*"|'(?:[^'\\\r\n]|\\.)*')|(\b[A-Za-z_][A-Za-z0-9_]*\b(?=\s*:))|(\b(?:0x[0-9A-Fa-f]+|\d+(?:\.\d+)?)\b)|(\b(?:def|class|import|from|as|if|elif|else|for|while|break|continue|return|yield|try|except|finally|raise|with|pass|lambda|async|await|and|or|not|in|is|True|False|None|self)\b)"#
    )
    private static let jsRegex = try? NSRegularExpression(
        pattern: #"(//[^\r\n]*|/\*[\s\S]*?\*/)|("(?:[^"\\\r\n]|\\.)*"|'(?:[^'\\\r\n]|\\.)*'|`[^`\r\n]*`)|(\b[A-Za-z_$][A-Za-z0-9_$]*\b(?=\s*:))|(\b(?:0x[0-9A-Fa-f]+|\d+(?:\.\d+)?)\b)|(\b(?:import|export|from|default|const|let|var|function|return|if|else|switch|case|for|while|do|break|continue|try|catch|finally|throw|async|await|class|extends|new|this|typeof|instanceof|true|false|null|undefined|interface|type)\b)"#
    )
    private static let sqlRegex = try? NSRegularExpression(
        pattern: #"(--[^\r\n]*|/\*[\s\S]*?\*/)|('(?:[^'\\\r\n]|\\.)*'|"(?:[^"\\\r\n]|\\.)*")|(\b\d+(?:\.\d+)?\b)|(\b(?:SELECT|FROM|WHERE|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|ALTER|DROP|TABLE|INDEX|JOIN|INNER|LEFT|RIGHT|ON|GROUP|BY|ORDER|HAVING|LIMIT|OFFSET|AS|AND|OR|NOT|NULL|IS|IN|EXISTS|DISTINCT|UNION|WITH|ASC|DESC|CASE|WHEN|THEN|ELSE|END)\b)"#,
        options: [.caseInsensitive]
    )
    private static let shellRegex = try? NSRegularExpression(
        pattern: #"(#[^\r\n]*)|("(?:[^"\\\r\n]|\\.)*"|'(?:[^'\\\r\n]|\\.)*'|`[^`\r\n]*`)|(\b\d+(?:\.\d+)?\b)|(\b(?:if|then|else|elif|fi|for|in|do|done|while|case|esac|function|export|local|readonly|return|exit|sudo|echo|true|false)\b)"#
    )

    static func detectLanguage(for text: String) -> Language {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .plain }
        let sample = String(trimmed.prefix(16_384))

        if let first = sample.first, first == "{" || first == "[",
           let data = trimmed.data(using: .utf8),
           trimmed.utf8.count <= 262_144,
           (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil {
            return .json
        }

        if sample.range(of: #"^(?:#!.*sh\b|\$\s+\w)"#, options: .regularExpression) != nil
            || sample.range(of: #"(?m)^(?:\$\s*)?(?:export\s+[A-Z0-9_]+=|sudo\s+|brew\s+|git\s+|curl\s+|docker\s+|kubectl\s+|chmod\s+|npm\s+|pnpm\s+|pip3?\s+)"#, options: .regularExpression) != nil {
            return .shell
        }

        if sample.range(of: #"(?i)\b(?:SELECT\b[\s\S]+?\bFROM\b|INSERT\s+INTO\b|UPDATE\b[\s\S]+?\bSET\b|DELETE\s+FROM\b|CREATE\s+(?:TABLE|INDEX|VIEW)\b|ALTER\s+TABLE\b)"#, options: .regularExpression) != nil {
            return .sql
        }

        if sample.contains("#!/usr/bin/env python")
            || sample.range(of: #"(?m)^\s*(?:async\s+)?def\s+[A-Za-z_][A-Za-z0-9_]*\s*\([^)]*\)\s*:|^\s*from\s+[A-Za-z0-9_.]+\s+import\s+|^\s*if\s+__name__\s*==\s*['"]__main__['"]\s*:"#, options: .regularExpression) != nil {
            return .python
        }

        if sample.range(of: #"(?m)\b(?:import\s+(?:SwiftUI|Foundation|AppKit|Combine|CryptoKit)|guard\s+let\s+|if\s+let\s+|func\s+[A-Za-z_][A-Za-z0-9_]*\s*\(|@(?:MainActor|Published|State|ObservedObject|Environment)\b|(?:struct|enum|protocol|actor)\s+[A-Za-z_][A-Za-z0-9_]*)"#, options: .regularExpression) != nil {
            return .swift
        }

        if sample.range(of: #"(?m)(?:\b(?:const|function)\s+[A-Za-z_$]|=>\s*\{|\bexport\s+(?:default|const|function)\b|\bimport\s+[\s\S]+?\s+from\s+['"]|console\.log\s*\(|\binterface\s+[A-Za-z_])"#, options: .regularExpression) != nil {
            return .js
        }

        return .plain
    }

    static func tokenize(_ text: String, language: Language? = nil) -> (language: Language, tokens: [Token]) {
        let resolved = language ?? detectLanguage(for: text)
        guard resolved != .plain, !text.isEmpty, text.count <= maxHighlightCharacters else {
            return (resolved, [])
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let tokens: [Token]
        switch resolved {
        case .json:
            tokens = scan(text: text, regex: jsonRegex, range: nsRange, groupMap: [
                (1, .key), (2, .string), (3, .number), (4, .keyword),
            ])
        case .swift:
            tokens = scan(text: text, regex: swiftRegex, range: nsRange, groupMap: [
                (1, .comment), (2, .string), (3, .key), (4, .number), (5, .keyword),
            ])
        case .python:
            tokens = scan(text: text, regex: pythonRegex, range: nsRange, groupMap: [
                (1, .comment), (2, .string), (3, .key), (4, .number), (5, .keyword),
            ])
        case .js:
            tokens = scan(text: text, regex: jsRegex, range: nsRange, groupMap: [
                (1, .comment), (2, .string), (3, .key), (4, .number), (5, .keyword),
            ])
        case .sql:
            tokens = scan(text: text, regex: sqlRegex, range: nsRange, groupMap: [
                (1, .comment), (2, .string), (3, .number), (4, .keyword),
            ])
        case .shell:
            tokens = scan(text: text, regex: shellRegex, range: nsRange, groupMap: [
                (1, .comment), (2, .string), (3, .number), (4, .keyword),
            ])
        case .plain:
            tokens = []
        }
        return (resolved, tokens)
    }

    static func attributedString(_ text: String,
                                 language: Language? = nil,
                                 darkAppearance: Bool = true) -> AttributedString {
        let (_, tokens) = tokenize(text, language: language)
        var attributed = AttributedString(text)
        attributed.foregroundColor = swiftUIColor(for: .plain, darkAppearance: darkAppearance)
        for token in tokens {
            guard let attrRange = Range(token.range, in: attributed) else { continue }
            attributed[attrRange].foregroundColor = swiftUIColor(for: token.kind, darkAppearance: darkAppearance)
        }
        return attributed
    }

    static func nsAttributedString(_ text: String,
                                   language: Language? = nil,
                                   darkAppearance: Bool = true,
                                   font: NSFont = .monospacedSystemFont(ofSize: 11.5, weight: .regular)) -> NSAttributedString {
        let (_, tokens) = tokenize(text, language: language)
        return nsAttributedString(text, tokens: tokens, darkAppearance: darkAppearance, font: font)
    }

    static func nsAttributedString(_ text: String,
                                   tokens: [Token],
                                   darkAppearance: Bool = true,
                                   font: NSFont = .monospacedSystemFont(ofSize: 11.5, weight: .regular)) -> NSAttributedString {
        let mutable = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: nsColor(for: .plain, darkAppearance: darkAppearance),
            ]
        )
        for token in tokens {
            let nsRange = NSRange(token.range, in: text)
            mutable.addAttribute(.foregroundColor,
                                 value: nsColor(for: token.kind, darkAppearance: darkAppearance),
                                 range: nsRange)
        }
        return mutable
    }

    private static func scan(text: String,
                             regex: NSRegularExpression?,
                             range: NSRange,
                             groupMap: [(Int, TokenKind)]) -> [Token] {
        guard let regex else { return [] }
        var result: [Token] = []
        for match in regex.matches(in: text, range: range) {
            for (groupIndex, kind) in groupMap {
                let cap = match.range(at: groupIndex)
                if cap.location != NSNotFound, let swiftRange = Range(cap, in: text) {
                    result.append(Token(kind: kind, range: swiftRange))
                    break
                }
            }
        }
        return result
    }

    private static func rgb(for kind: TokenKind, darkAppearance: Bool) -> (Double, Double, Double) {
        switch (kind, darkAppearance) {
        case (.keyword, true): return (0.99, 0.45, 0.65)
        case (.keyword, false): return (0.67, 0.05, 0.57)
        case (.string, true): return (0.99, 0.52, 0.43)
        case (.string, false): return (0.77, 0.10, 0.09)
        case (.comment, true): return (0.48, 0.56, 0.62)
        case (.comment, false): return (0.42, 0.47, 0.53)
        case (.number, true): return (0.82, 0.75, 0.41)
        case (.number, false): return (0.11, 0.00, 0.81)
        case (.key, true): return (0.42, 0.82, 0.90)
        case (.key, false): return (0.15, 0.43, 0.53)
        case (.plain, true): return (0.92, 0.93, 0.95)
        case (.plain, false): return (0.12, 0.13, 0.16)
        }
    }

    private static func swiftUIColor(for kind: TokenKind, darkAppearance: Bool) -> Color {
        let (r, g, b) = rgb(for: kind, darkAppearance: darkAppearance)
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    private static func nsColor(for kind: TokenKind, darkAppearance: Bool) -> NSColor {
        let (r, g, b) = rgb(for: kind, darkAppearance: darkAppearance)
        return NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
    }
}

/// Extracted OpenGraph / HTML metadata for copied HTTPS links.
struct ClipboardLinkMetadata: Equatable, Codable, Sendable {
    let title: String?
    let description: String?
    let siteName: String?
    let imageURLString: String?
    let urlString: String?

    init(title: String? = nil,
         description: String? = nil,
         siteName: String? = nil,
         imageURLString: String? = nil,
         urlString: String? = nil) {
        self.title = title
        self.description = description
        self.siteName = siteName
        self.imageURLString = imageURLString
        self.urlString = urlString
    }

    var domain: String? {
        guard let urlString, let host = URL(string: urlString)?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// Pure HTML parser extracting OpenGraph and `<title>` metadata without WebKit or UI dependencies.
enum ClipboardLinkMetadataParser {
    private static let metaTagRegex = try? NSRegularExpression(
        pattern: #"<meta\b([^>]+)>"#,
        options: [.caseInsensitive]
    )
    private static let attrRegex = try? NSRegularExpression(
        pattern: #"([a-zA-Z0-9_:\-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))"#,
        options: []
    )
    private static let titleTagRegex = try? NSRegularExpression(
        pattern: #"<title\b[^>]*>([\s\S]*?)</title>"#,
        options: [.caseInsensitive]
    )

    static func parse(html: String, sourceURL: URL) -> ClipboardLinkMetadata {
        var metaMap: [String: String] = [:]
        if let metaTagRegex {
            let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)
            for match in metaTagRegex.matches(in: html, range: fullRange) {
                guard match.numberOfRanges >= 2,
                      let attrRange = Range(match.range(at: 1), in: html) else { continue }
                let attrs = parseAttributes(String(html[attrRange]))
                let key = (attrs["property"] ?? attrs["name"] ?? "").lowercased()
                guard !key.isEmpty, let content = attrs["content"] else { continue }
                let clean = cleanText(content)
                if !clean.isEmpty, metaMap[key] == nil {
                    metaMap[key] = clean
                }
            }
        }

        var fallbackTitle: String?
        if let titleTagRegex {
            let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)
            if let match = titleTagRegex.firstMatch(in: html, range: fullRange),
               match.numberOfRanges >= 2,
               let range = Range(match.range(at: 1), in: html) {
                let candidate = cleanText(String(html[range]))
                if !candidate.isEmpty { fallbackTitle = candidate }
            }
        }

        let title = metaMap["og:title"] ?? metaMap["twitter:title"] ?? fallbackTitle
        let description = metaMap["og:description"] ?? metaMap["twitter:description"] ?? metaMap["description"]
        let fallbackSite = sourceURL.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
        let siteName = metaMap["og:site_name"] ?? fallbackSite

        let rawImage = metaMap["og:image"] ?? metaMap["twitter:image"]
        let resolvedImageURL: String?
        if let rawImage,
           let url = URL(string: rawImage, relativeTo: sourceURL)?.absoluteURL,
           let scheme = url.scheme?.lowercased(),
           scheme == "https" || scheme == "http" {
            resolvedImageURL = url.absoluteString
        } else {
            resolvedImageURL = nil
        }

        return ClipboardLinkMetadata(
            title: title,
            description: description,
            siteName: siteName,
            imageURLString: resolvedImageURL,
            urlString: sourceURL.absoluteString
        )
    }

    private static func parseAttributes(_ raw: String) -> [String: String] {
        guard let attrRegex else { return [:] }
        var result: [String: String] = [:]
        let nsRange = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        for match in attrRegex.matches(in: raw, range: nsRange) {
            guard match.numberOfRanges >= 5,
                  let nameRange = Range(match.range(at: 1), in: raw) else { continue }
            let name = raw[nameRange].lowercased()
            let valueRange = (2...4).lazy
                .map { match.range(at: $0) }
                .first { $0.location != NSNotFound }
                .flatMap { Range($0, in: raw) }
            if let valueRange {
                result[name] = String(raw[valueRange])
            }
        }
        return result
    }

    private static func cleanText(_ raw: String) -> String {
        let decoded = decodeHTMLEntities(raw)
        return decoded
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        if let numericRegex = try? NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#) {
            let fullRange = NSRange(out.startIndex..<out.endIndex, in: out)
            for match in numericRegex.matches(in: out, range: fullRange).reversed() {
                guard match.numberOfRanges >= 2,
                      let full = Range(match.range(at: 0), in: out),
                      let digits = Range(match.range(at: 1), in: out) else { continue }
                let token = String(out[digits])
                let codePoint: UInt32? = token.hasPrefix("x") || token.hasPrefix("X")
                    ? UInt32(token.dropFirst(), radix: 16)
                    : UInt32(token, radix: 10)
                if let codePoint, let scalar = UnicodeScalar(codePoint) {
                    out.replaceSubrange(full, with: String(scalar))
                }
            }
        }
        return out
    }
}

/// Thread-safe bounded LRU cache for parsed OpenGraph link metadata.
final class ClipboardLinkMetadataCache: @unchecked Sendable {
    private let lock = NSLock()
    private let capacity: Int
    private var storage: [String: ClipboardLinkMetadata] = [:]
    private var order: [String] = []

    init(capacity: Int = 128) {
        self.capacity = max(1, capacity)
    }

    var count: Int {
        lock.withLock { storage.count }
    }

    func metadata(for url: URL) -> ClipboardLinkMetadata? {
        let key = url.absoluteString
        return lock.withLock {
            guard let hit = storage[key] else { return nil }
            touchKeyLocked(key)
            return hit
        }
    }

    func store(_ metadata: ClipboardLinkMetadata, for url: URL) {
        let key = url.absoluteString
        lock.withLock {
            storage[key] = metadata
            touchKeyLocked(key)
            while order.count > capacity {
                let oldest = order.removeFirst()
                storage.removeValue(forKey: oldest)
            }
        }
    }

    func clear() {
        lock.withLock {
            storage.removeAll()
            order.removeAll()
        }
    }

    private func touchKeyLocked(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}

/// Safe HTTPS-only ephemeral OpenGraph metadata fetcher backed by `ClipboardLinkMetadataCache`.
enum ClipboardLinkMetadataFetcher {
    static let sharedCache = ClipboardLinkMetadataCache(capacity: 128)
    private static let maxResponseBytes = 512 * 1024

    private static let ephemeralSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 8
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config)
    }()

    static func eligibleURL(from rawText: String) -> URL? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              let host = url.host,
              !host.isEmpty else {
            return nil
        }
        return url
    }

    static func fetchMetadata(for url: URL,
                              cache: ClipboardLinkMetadataCache = sharedCache,
                              session: URLSession? = nil) async -> ClipboardLinkMetadata? {
        guard url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty else {
            return nil
        }
        if let cached = cache.metadata(for: url) {
            return cached
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 6
        request.setValue("text/html,application/xhtml+xml;q=0.9,*/*;q=0.1", forHTTPHeaderField: "Accept")

        do {
            let activeSession = session ?? ephemeralSession
            let (data, response) = try await activeSession.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                return nil
            }
            if let mime = http.mimeType?.lowercased(),
               !mime.contains("html") && !mime.hasPrefix("text/") {
                return nil
            }
            let bounded = data.prefix(maxResponseBytes)
            let html = String(data: bounded, encoding: .utf8)
                ?? String(data: bounded, encoding: .isoLatin1)
            guard let html else { return nil }
            let parsed = ClipboardLinkMetadataParser.parse(html: html, sourceURL: url)
            cache.store(parsed, for: url)
            return parsed
        } catch {
            return nil
        }
    }
}

/// Zero-CloudKit end-to-end encrypted live folder sync for Clipboard 3.0 rows via iCloud Drive.
final class ClipboardLiveVaultSyncService: @unchecked Sendable {
    enum LiveSyncError: Error, Equatable {
        case emptyPayload
        case invalidEnvelope
    }

    static let shared = ClipboardLiveVaultSyncService()

    private static let logger = Logger(subsystem: "com.vorssaint.utils", category: "ClipboardLiveVaultSync")
    private static let hkdfSalt = Data("vorssaint.clipboard.livevault.salt.v1".utf8)
    private static let hkdfInfo = Data("vorssaint.clipboard.livevault.key.v1".utf8)
    private static let rowFileExtension = "vorssaintrow"
    private static let debounceInterval: TimeInterval = 0.15
    private static let selfEchoSuppressionWindow: TimeInterval = 15.0

    private let stateLock = NSLock()
    private let watchQueue = DispatchQueue(label: "com.vorssaint.utils.clipboard-live-vault", qos: .utility)
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var pendingScanWorkItem: DispatchWorkItem?
    private var recentlyWrittenIDs: [UUID: Date] = [:]
    private var seenFileSignatures: [String: String] = [:]
    private var watchedDirectoryURL: URL?

    private init() {}

    deinit {
        stopWatching()
    }

    static func defaultDirectoryURL(fileManager: FileManager = .default) -> URL {
        let iCloudDocuments = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: iCloudDocuments.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return iCloudDocuments.appendingPathComponent("VorssaintVault", isDirectory: true)
        }
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let bundleID = Bundle.main.bundleIdentifier ?? "com.vorssaint.utils"
        return appSupport
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("VorssaintVault", isDirectory: true)
    }

    static func deriveKey(from passphrase: String) -> SymmetricKey {
        let inputKey = SymmetricKey(data: Data(passphrase.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: hkdfSalt,
            info: hkdfInfo,
            outputByteCount: 32
        )
    }

    static func encodeEnvelope(row: ClipboardSQLiteRow, key: SymmetricKey) throws -> Data {
        let plaintext = try JSONEncoder().encode(row)
        guard !plaintext.isEmpty else { throw LiveSyncError.emptyPayload }
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined, combined.count > 28 else {
            throw LiveSyncError.invalidEnvelope
        }
        return combined
    }

    static func decodeEnvelope(data: Data, key: SymmetricKey) throws -> ClipboardSQLiteRow {
        guard data.count > 28 else { throw LiveSyncError.invalidEnvelope }
        let plaintext: Data
        do {
            let box = try AES.GCM.SealedBox(combined: data)
            plaintext = try AES.GCM.open(box, using: key)
        } catch {
            throw LiveSyncError.invalidEnvelope
        }
        guard !plaintext.isEmpty else { throw LiveSyncError.emptyPayload }
        return try JSONDecoder().decode(ClipboardSQLiteRow.self, from: plaintext)
    }

    func startWatching(directoryURL: URL, onIncomingFile: @escaping @Sendable (URL) -> Void) {
        stopWatching()

        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            Self.logger.error("Unable to create live vault directory: \(error.localizedDescription, privacy: .public)")
            return
        }

        let fd = open(directoryURL.path, O_EVTONLY)
        guard fd >= 0 else {
            Self.logger.error("Unable to open O_EVTONLY descriptor for \(directoryURL.path, privacy: .public)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .extend],
            queue: watchQueue
        )

        source.setEventHandler { [weak self] in
            self?.scheduleDirectoryScan(directoryURL: directoryURL, onIncomingFile: onIncomingFile)
        }

        source.setCancelHandler {
            close(fd)
        }

        stateLock.lock()
        watchedDirectoryURL = directoryURL
        seenFileSignatures.removeAll()
        dispatchSource = source
        stateLock.unlock()

        source.resume()
        scheduleDirectoryScan(directoryURL: directoryURL, onIncomingFile: onIncomingFile)
    }

    func stopWatching() {
        stateLock.lock()
        pendingScanWorkItem?.cancel()
        pendingScanWorkItem = nil
        let existingSource = dispatchSource
        dispatchSource = nil
        watchedDirectoryURL = nil
        seenFileSignatures.removeAll()
        stateLock.unlock()

        existingSource?.cancel()
    }

    func publishRow(_ row: ClipboardSQLiteRow, to directoryURL: URL, key: SymmetricKey? = nil) {
        let resolvedKey: SymmetricKey
        if let key {
            resolvedKey = key
        } else if let passphrase = KeychainClipboardVaultSecretStore().loadSecret(), !passphrase.isEmpty {
            resolvedKey = Self.deriveKey(from: passphrase)
        } else {
            resolvedKey = Self.deriveKey(from: Bundle.main.bundleIdentifier ?? "com.vorssaint.utils.livevault")
        }

        do {
            let envelope = try Self.encodeEnvelope(row: row, key: resolvedKey)
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )

            let fileName = "\(row.id.uuidString).\(Self.rowFileExtension)"
            let destinationURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)
            let now = Date()

            stateLock.lock()
            pruneRecentlyWrittenLocked(now: now)
            recentlyWrittenIDs[row.id] = now
            seenFileSignatures[fileName] = "\(envelope.count)"
            stateLock.unlock()

            try envelope.write(to: destinationURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destinationURL.path)

            if let attrs = try? FileManager.default.attributesOfItem(atPath: destinationURL.path),
               let modDate = attrs[.modificationDate] as? Date,
               let fileSize = attrs[.size] as? NSNumber {
                stateLock.lock()
                seenFileSignatures[fileName] = "\(fileSize.int64Value)-\(modDate.timeIntervalSince1970)"
                stateLock.unlock()
            }
        } catch {
            Self.logger.error("Failed publishing live vault row: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleDirectoryScan(directoryURL: URL, onIncomingFile: @escaping @Sendable (URL) -> Void) {
        stateLock.lock()
        guard watchedDirectoryURL == directoryURL, dispatchSource != nil else {
            stateLock.unlock()
            return
        }
        pendingScanWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.scanDirectory(directoryURL: directoryURL, onIncomingFile: onIncomingFile)
        }
        pendingScanWorkItem = workItem
        stateLock.unlock()

        watchQueue.asyncAfter(deadline: .now() + Self.debounceInterval, execute: workItem)
    }

    private func scanDirectory(directoryURL: URL, onIncomingFile: @escaping @Sendable (URL) -> Void) {
        stateLock.lock()
        let active = watchedDirectoryURL == directoryURL && dispatchSource != nil
        stateLock.unlock()
        guard active else { return }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let sorted = contents.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let now = Date()
        var deliveries: [URL] = []

        stateLock.lock()
        pruneRecentlyWrittenLocked(now: now)
        for url in sorted {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
            guard values?.isRegularFile == true else { continue }

            let stem = url.deletingPathExtension().lastPathComponent
            if let uuid = UUID(uuidString: stem), recentlyWrittenIDs[uuid] != nil {
                continue
            }

            let fileName = url.lastPathComponent
            let size = values?.fileSize ?? 0
            let mod = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            let signature = "\(size)-\(mod)"
            if seenFileSignatures[fileName] == signature {
                continue
            }
            seenFileSignatures[fileName] = signature
            deliveries.append(url)
        }
        stateLock.unlock()

        for url in deliveries {
            onIncomingFile(url)
        }
    }

    private func pruneRecentlyWrittenLocked(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.selfEchoSuppressionWindow)
        recentlyWrittenIDs = recentlyWrittenIDs.filter { $0.value >= cutoff }
    }
}
