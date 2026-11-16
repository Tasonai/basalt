// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import CoreGraphics
import CryptoKit
import Foundation
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
