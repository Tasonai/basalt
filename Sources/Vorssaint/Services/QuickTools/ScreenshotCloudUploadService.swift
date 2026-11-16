// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CryptoKit
import Foundation
import Security

/// Supported custom cloud upload providers for Screenshot Pro.
enum ScreenshotCloudProvider: String, CaseIterable, Codable, Sendable, Identifiable {
    case disabled
    case s3Compatible
    case customWebhook

    var id: String { rawValue }

    var shortBadge: String {
        switch self {
        case .disabled: return ""
        case .s3Compatible: return "S3 / R2"
        case .customWebhook: return "Webhook"
        }
    }
}

/// Non-secret configuration persisted in `UserDefaults`. Secrets always live in Keychain.
struct ScreenshotCloudConfig: Codable, Equatable, Sendable {
    var provider: ScreenshotCloudProvider
    var endpointURLString: String
    var region: String
    var bucket: String
    var keyPrefix: String
    var publicBaseURL: String
    var accessKeyID: String
    var webhookHeaderName: String
    var webhookResponseURLKeyPath: String

    init(provider: ScreenshotCloudProvider = .disabled,
         endpointURLString: String = "",
         region: String = "auto",
         bucket: String = "",
         keyPrefix: String = "",
         publicBaseURL: String = "",
         accessKeyID: String = "",
         webhookHeaderName: String = "Authorization",
         webhookResponseURLKeyPath: String = "url") {
        self.provider = provider
        self.endpointURLString = endpointURLString
        self.region = region
        self.bucket = bucket
        self.keyPrefix = keyPrefix
        self.publicBaseURL = publicBaseURL
        self.accessKeyID = accessKeyID
        self.webhookHeaderName = webhookHeaderName
        self.webhookResponseURLKeyPath = webhookResponseURLKeyPath
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case endpointURLString
        case region
        case bucket
        case keyPrefix
        case publicBaseURL
        case accessKeyID
        case webhookHeaderName
        case webhookResponseURLKeyPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decodeIfPresent(ScreenshotCloudProvider.self, forKey: .provider) ?? .disabled
        endpointURLString = try container.decodeIfPresent(String.self, forKey: .endpointURLString) ?? ""
        region = try container.decodeIfPresent(String.self, forKey: .region) ?? "auto"
        bucket = try container.decodeIfPresent(String.self, forKey: .bucket) ?? ""
        keyPrefix = try container.decodeIfPresent(String.self, forKey: .keyPrefix) ?? ""
        publicBaseURL = try container.decodeIfPresent(String.self, forKey: .publicBaseURL) ?? ""
        accessKeyID = try container.decodeIfPresent(String.self, forKey: .accessKeyID) ?? ""
        webhookHeaderName = try container.decodeIfPresent(String.self, forKey: .webhookHeaderName) ?? "Authorization"
        webhookResponseURLKeyPath = try container.decodeIfPresent(String.self, forKey: .webhookResponseURLKeyPath) ?? "url"
    }

    var normalizedRegion: String {
        let trimmed = region.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "auto" : trimmed
    }

    var normalizedEndpointURL: URL? {
        Self.validatedHTTPURL(endpointURLString)
    }

    var normalizedPublicBaseURL: URL? {
        Self.validatedHTTPURL(publicBaseURL)
    }

    var hasRequiredFields: Bool {
        switch provider {
        case .disabled:
            return false
        case .s3Compatible:
            return normalizedEndpointURL != nil
                && !bucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .customWebhook:
            return normalizedEndpointURL != nil
        }
    }

    static let defaultsKey = "screenshotCloudUploadConfigJSON"

    static func load(from defaults: UserDefaults = .standard,
                     key: String = defaultsKey) -> ScreenshotCloudConfig {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(ScreenshotCloudConfig.self, from: data)
        else { return ScreenshotCloudConfig() }
        return decoded
    }

    func save(to defaults: UserDefaults = .standard, key: String = defaultsKey) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: key)
    }

    static func validatedHTTPURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty else {
            return nil
        }
        return url
    }
}

/// Keychain abstraction so production stores cloud credentials in Keychain while
/// tests run deterministically in memory without UI prompts.
protocol ScreenshotCloudSecretStore: Sendable {
    func saveSecret(_ value: String, account: String) -> Bool
    func loadSecret(account: String) -> String?
    @discardableResult
    func deleteSecret(account: String) -> Bool
}

struct KeychainScreenshotCloudSecretStore: ScreenshotCloudSecretStore {
    static let service = "com.vorssaint.utils.cloud"

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

final class InMemoryScreenshotCloudSecretStore: ScreenshotCloudSecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: String] = [:]

    func saveSecret(_ value: String, account: String) -> Bool {
        lock.withLock { entries[account] = value }
        return true
    }

    func loadSecret(account: String) -> String? {
        lock.withLock { entries[account] }
    }

    @discardableResult
    func deleteSecret(account: String) -> Bool {
        lock.withLock { _ = entries.removeValue(forKey: account) }
        return true
    }
}

/// Pure CryptoKit AWS Signature Version 4 signer for S3-compatible PUT uploads
/// (AWS S3, Cloudflare R2, MinIO, Backblaze B2 S3, etc.).
enum S3SigV4Signer {
    static let signedHeaders = "host;x-amz-content-sha256;x-amz-date"

    static func sha256Hex(_ data: Data) -> String {
        hexString(SHA256.hash(data: data))
    }

    static func hmacSHA256(key: Data, data: Data) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))
        return Data(mac)
    }

    static func hmacSHA256Hex(key: Data, data: Data) -> String {
        hexString(hmacSHA256(key: key, data: data))
    }

    /// Percent-encodes per AWS SigV4 URI rules (unreserved: `A-Z a-z 0-9 - _ . ~`).
    static func uriEncode(_ string: String, encodeSlash: Bool) -> String {
        let hexDigits = Array("0123456789ABCDEF".utf8)
        var output = String()
        output.reserveCapacity(string.utf8.count)
        for byte in string.utf8 {
            let isUnreserved = (byte >= 0x41 && byte <= 0x5A) // A-Z
                || (byte >= 0x61 && byte <= 0x7A) // a-z
                || (byte >= 0x30 && byte <= 0x39) // 0-9
                || byte == 0x2D // -
                || byte == 0x2E // .
                || byte == 0x5F // _
                || byte == 0x7E // ~
            if isUnreserved || (!encodeSlash && byte == 0x2F) {
                output.append(Character(UnicodeScalar(byte)))
            } else {
                output.append("%")
                output.append(Character(UnicodeScalar(hexDigits[Int(byte >> 4)])))
                output.append(Character(UnicodeScalar(hexDigits[Int(byte & 0x0F)])))
            }
        }
        return output
    }

    static func canonicalURI(for url: URL) -> String {
        let rawPercentPath = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
        let decoded = rawPercentPath.removingPercentEncoding ?? url.path
        let normalized = decoded.isEmpty ? "/" : (decoded.hasPrefix("/") ? decoded : "/" + decoded)
        return uriEncode(normalized, encodeSlash: false)
    }

    static func canonicalQuery(for url: URL) -> String {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              !items.isEmpty else { return "" }
        return items
            .map { (key: uriEncode($0.name, encodeSlash: true),
                    value: uriEncode($0.value ?? "", encodeSlash: true)) }
            .sorted {
                if $0.key != $1.key { return $0.key < $1.key }
                return $0.value < $1.value
            }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
    }

    static func hostHeaderValue(for url: URL) -> String {
        guard let host = url.host else { return "" }
        guard let port = url.port else { return host }
        let scheme = url.scheme?.lowercased()
        if (scheme == "http" && port == 80) || (scheme == "https" && port == 443) {
            return host
        }
        return "\(host):\(port)"
    }

    static func amzTimestamps(for date: Date) -> (amzDate: String, dateStamp: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = formatter.string(from: date)
        let dateStamp = String(amzDate.prefix(8))
        return (amzDate, dateStamp)
    }

    static func signingKey(secretAccessKey: String,
                           dateStamp: String,
                           region: String,
                           service: String = "s3") -> Data {
        let kSecret = Data(("AWS4" + secretAccessKey).utf8)
        let kDate = hmacSHA256(key: kSecret, data: Data(dateStamp.utf8))
        let kRegion = hmacSHA256(key: kDate, data: Data(region.utf8))
        let kService = hmacSHA256(key: kRegion, data: Data(service.utf8))
        return hmacSHA256(key: kService, data: Data("aws4_request".utf8))
    }

    static func canonicalRequest(method: String,
                                 url: URL,
                                 payloadHash: String,
                                 amzDate: String) -> String {
        let uri = canonicalURI(for: url)
        let query = canonicalQuery(for: url)
        let host = hostHeaderValue(for: url)
        let canonicalHeaders = "host:\(host)\nx-amz-content-sha256:\(payloadHash)\nx-amz-date:\(amzDate)\n"
        return "\(method)\n\(uri)\n\(query)\n\(canonicalHeaders)\n\(signedHeaders)\n\(payloadHash)"
    }

    static func stringToSign(amzDate: String,
                             dateStamp: String,
                             region: String,
                             service: String = "s3",
                             canonicalRequestHash: String) -> String {
        let scope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        return "AWS4-HMAC-SHA256\n\(amzDate)\n\(scope)\n\(canonicalRequestHash)"
    }

    static func authorizationHeader(method: String,
                                    url: URL,
                                    payloadHash: String,
                                    accessKeyID: String,
                                    secretAccessKey: String,
                                    region: String,
                                    service: String = "s3",
                                    date: Date) -> (authorization: String, amzDate: String, host: String) {
        let timestamps = amzTimestamps(for: date)
        let host = hostHeaderValue(for: url)
        let canonical = canonicalRequest(method: method,
                                         url: url,
                                         payloadHash: payloadHash,
                                         amzDate: timestamps.amzDate)
        let canonicalHash = sha256Hex(Data(canonical.utf8))
        let toSign = stringToSign(amzDate: timestamps.amzDate,
                                  dateStamp: timestamps.dateStamp,
                                  region: region,
                                  service: service,
                                  canonicalRequestHash: canonicalHash)
        let key = signingKey(secretAccessKey: secretAccessKey,
                             dateStamp: timestamps.dateStamp,
                             region: region,
                             service: service)
        let signature = hmacSHA256Hex(key: key, data: Data(toSign.utf8))
        let scope = "\(timestamps.dateStamp)/\(region)/\(service)/aws4_request"
        let header = "AWS4-HMAC-SHA256 Credential=\(accessKeyID)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        return (header, timestamps.amzDate, host)
    }

    static func signedPutRequest(url: URL,
                                 payload: Data,
                                 contentType: String = "image/png",
                                 accessKeyID: String,
                                 secretAccessKey: String,
                                 region: String,
                                 service: String = "s3",
                                 date: Date = Date()) -> URLRequest {
        let payloadHash = sha256Hex(payload)
        let signed = authorizationHeader(method: "PUT",
                                         url: url,
                                         payloadHash: payloadHash,
                                         accessKeyID: accessKeyID,
                                         secretAccessKey: secretAccessKey,
                                         region: region,
                                         service: service,
                                         date: date)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(signed.amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(signed.authorization, forHTTPHeaderField: "Authorization")
        return request
    }

    private static func hexString<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map { byte in
            let hex = String(byte, radix: 16, uppercase: false)
            return hex.count == 1 ? "0" + hex : hex
        }.joined()
    }
}

enum ScreenshotCloudUploadError: Error, LocalizedError, Equatable, Sendable {
    case notConfigured
    case invalidEndpoint
    case missingSecret
    case invalidImage
    case networkFailure(String)
    case httpStatus(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Cloud upload is not configured"
        case .invalidEndpoint: return "Invalid cloud endpoint URL"
        case .missingSecret: return "Missing Keychain credential"
        case .invalidImage: return "Invalid PNG screenshot payload"
        case .networkFailure(let detail): return detail
        case .httpStatus(let code): return "Upload failed (HTTP \(code))"
        case .invalidResponse: return "Could not resolve uploaded URL from response"
        }
    }
}

/// Hardened-Runtime-safe custom cloud uploader supporting S3-compatible object storage
/// (AWS S3, Cloudflare R2) and custom HTTP webhooks with Keychain-backed secrets.
final class ScreenshotCloudUploadService: ObservableObject {
    typealias UploadTransport = @Sendable (URLRequest, Data) async throws -> (Data, URLResponse)

    static let s3SecretAccount = "s3SecretAccessKey"
    static let webhookTokenAccount = "webhookBearerToken"

    @MainActor static let shared = ScreenshotCloudUploadService()

    @MainActor @Published var config: ScreenshotCloudConfig {
        didSet {
            config.save(to: defaults, key: defaultsKey)
        }
    }
    @MainActor @Published private(set) var isUploading = false
    @MainActor @Published private(set) var lastUploadedURL: URL?
    @MainActor @Published private(set) var lastErrorMessage: String?
    @MainActor @Published private(set) var hasStoredSecret: Bool

    private let defaults: UserDefaults
    private let defaultsKey: String
    private let secretStore: any ScreenshotCloudSecretStore
    private let transport: UploadTransport
    private let pasteboardWriter: @MainActor (URL) -> Bool
    private let feedbackHandler: @MainActor (URL) -> Void

    @MainActor
    init(defaults: UserDefaults = .standard,
         defaultsKey: String = ScreenshotCloudConfig.defaultsKey,
         secretStore: any ScreenshotCloudSecretStore = KeychainScreenshotCloudSecretStore(),
         transport: UploadTransport? = nil,
         pasteboardWriter: (@MainActor (URL) -> Bool)? = nil,
         feedbackHandler: (@MainActor (URL) -> Void)? = nil) {
        self.defaults = defaults
        self.defaultsKey = defaultsKey
        self.secretStore = secretStore
        let loaded = ScreenshotCloudConfig.load(from: defaults, key: defaultsKey)
        self.config = loaded
        self.hasStoredSecret = Self.hasSecret(for: loaded.provider, in: secretStore)
        if let transport {
            self.transport = transport
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.httpCookieAcceptPolicy = .never
            configuration.httpShouldSetCookies = false
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 120
            configuration.waitsForConnectivity = false
            let session = URLSession(configuration: configuration)
            self.transport = { request, body in
                try await session.upload(for: request, from: body)
            }
        }
        self.pasteboardWriter = pasteboardWriter ?? { url in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.declareVorssaintSource()
            return pasteboard.setString(url.absoluteString, forType: .string)
        }
        self.feedbackHandler = feedbackHandler ?? { url in
            // VorssaintDesignKit exposes alignment/levelChange/generic haptics.
            VorssaintHaptics.alignment()
            let strings = OverhaulV2Strings.localized(L10n.shared.language)
            let label = url.host.map { "\(strings.cloudCopiedBadge) · \($0)" } ?? strings.cloudCopiedBadge
            QuickToolHUD.show(icon: "icloud.and.arrow.up", message: label)
        }
    }

    @MainActor
    var isConfigured: Bool {
        guard config.hasRequiredFields else { return false }
        if config.provider == .s3Compatible {
            return hasStoredSecret
        }
        return true
    }

    @MainActor
    func refreshSecretStatus() {
        hasStoredSecret = Self.hasSecret(for: config.provider, in: secretStore)
    }

    @MainActor
    func currentSecret(for provider: ScreenshotCloudProvider? = nil) -> String? {
        let target = provider ?? config.provider
        guard let account = Self.secretAccount(for: target) else { return nil }
        return secretStore.loadSecret(account: account)
    }

    @MainActor
    @discardableResult
    func saveSecret(_ value: String, for provider: ScreenshotCloudProvider? = nil) -> Bool {
        let target = provider ?? config.provider
        guard let account = Self.secretAccount(for: target) else { return false }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return deleteSecret(for: target)
        }
        let saved = secretStore.saveSecret(trimmed, account: account)
        refreshSecretStatus()
        return saved
    }

    @MainActor
    @discardableResult
    func deleteSecret(for provider: ScreenshotCloudProvider? = nil) -> Bool {
        let target = provider ?? config.provider
        guard let account = Self.secretAccount(for: target) else { return false }
        let removed = secretStore.deleteSecret(account: account)
        refreshSecretStatus()
        return removed
    }

    static func secretAccount(for provider: ScreenshotCloudProvider) -> String? {
        switch provider {
        case .disabled: return nil
        case .s3Compatible: return s3SecretAccount
        case .customWebhook: return webhookTokenAccount
        }
    }

    private static func hasSecret(for provider: ScreenshotCloudProvider,
                                  in store: any ScreenshotCloudSecretStore) -> Bool {
        guard let account = secretAccount(for: provider),
              let value = store.loadSecret(account: account) else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Pure URL & Request Builders

    static func objectKey(prefix: String, fileName: String) -> String {
        let safeFile = (fileName as NSString).lastPathComponent
        let cleanName = safeFile.isEmpty ? "screenshot.png" : safeFile
        let cleanPrefix = prefix
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
            .joined(separator: "/")
        return cleanPrefix.isEmpty ? cleanName : "\(cleanPrefix)/\(cleanName)"
    }

    static func s3PutURL(config: ScreenshotCloudConfig, objectKey: String) -> URL? {
        guard let endpoint = config.normalizedEndpointURL else { return nil }
        let bucket = config.bucket.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !bucket.isEmpty else { return nil }
        var url = endpoint.appendingPathComponent(bucket, isDirectory: true)
        let components = objectKey.split(separator: "/").map(String.init)
        for (index, part) in components.enumerated() {
            url = url.appendingPathComponent(part, isDirectory: index < components.count - 1)
        }
        return url
    }

    static func resolvedS3PublicURL(config: ScreenshotCloudConfig,
                                    objectKey: String,
                                    putURL: URL) -> URL {
        guard let base = config.normalizedPublicBaseURL else { return putURL }
        var url = base
        let components = objectKey.split(separator: "/").map(String.init)
        for (index, part) in components.enumerated() {
            url = url.appendingPathComponent(part, isDirectory: index < components.count - 1)
        }
        return url
    }

    static func webhookRequest(endpoint: URL,
                               pngData: Data,
                               fileName: String,
                               headerName: String,
                               token: String?) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("image/png", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let safeName = (fileName as NSString).lastPathComponent
        if !safeName.isEmpty {
            request.setValue(safeName, forHTTPHeaderField: "X-File-Name")
        }
        let cleanHeader = headerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetHeader = cleanHeader.isEmpty ? "Authorization" : cleanHeader
        if let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            if targetHeader.caseInsensitiveCompare("Authorization") == .orderedSame,
               !token.lowercased().hasPrefix("bearer "),
               !token.lowercased().hasPrefix("basic "),
               !token.lowercased().hasPrefix("token ") {
                request.setValue("Bearer \(token)", forHTTPHeaderField: targetHeader)
            } else {
                request.setValue(token, forHTTPHeaderField: targetHeader)
            }
        }
        return request
    }

    /// Walks dot-separated JSON keypaths (e.g. `"url"`, `"data.url"`, `"result.link"`)
    /// and validates the extracted string as an HTTP(S) URL.
    static func extractURL(fromJSON data: Data, keyPath: String) -> URL? {
        let trimmedPath = keyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty,
              let root = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        var current: Any = root
        for segment in trimmedPath.split(separator: ".").map(String.init) {
            if let dict = current as? [String: Any], let next = dict[segment] {
                current = next
            } else if let array = current as? [Any], let idx = Int(segment), array.indices.contains(idx) {
                current = array[idx]
            } else {
                return nil
            }
        }
        guard let rawURL = current as? String else { return nil }
        return ScreenshotCloudConfig.validatedHTTPURL(rawURL)
    }

    // MARK: - Upload Entry

    @MainActor
    @discardableResult
    func upload(pngData: Data, fileName: String) async throws -> URL {
        guard !pngData.isEmpty else { throw ScreenshotCloudUploadError.invalidImage }
        let snapshot = config
        guard snapshot.provider != .disabled else { throw ScreenshotCloudUploadError.notConfigured }
        guard snapshot.hasRequiredFields else { throw ScreenshotCloudUploadError.notConfigured }

        let request: URLRequest
        let resolvedFallbackURL: URL
        let webhookKeyPath: String

        switch snapshot.provider {
        case .disabled:
            throw ScreenshotCloudUploadError.notConfigured
        case .s3Compatible:
            guard let secret = secretStore.loadSecret(account: Self.s3SecretAccount)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !secret.isEmpty else {
                throw ScreenshotCloudUploadError.missingSecret
            }
            let key = Self.objectKey(prefix: snapshot.keyPrefix, fileName: fileName)
            guard let putURL = Self.s3PutURL(config: snapshot, objectKey: key) else {
                throw ScreenshotCloudUploadError.invalidEndpoint
            }
            request = S3SigV4Signer.signedPutRequest(
                url: putURL,
                payload: pngData,
                contentType: "image/png",
                accessKeyID: snapshot.accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines),
                secretAccessKey: secret,
                region: snapshot.normalizedRegion
            )
            resolvedFallbackURL = Self.resolvedS3PublicURL(config: snapshot, objectKey: key, putURL: putURL)
            webhookKeyPath = ""
        case .customWebhook:
            guard let endpoint = snapshot.normalizedEndpointURL else {
                throw ScreenshotCloudUploadError.invalidEndpoint
            }
            let token = secretStore.loadSecret(account: Self.webhookTokenAccount)
            request = Self.webhookRequest(
                endpoint: endpoint,
                pngData: pngData,
                fileName: fileName,
                headerName: snapshot.webhookHeaderName,
                token: token
            )
            resolvedFallbackURL = endpoint
            let configuredPath = snapshot.webhookResponseURLKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)
            webhookKeyPath = configuredPath.isEmpty ? "url" : configuredPath
        }

        isUploading = true
        lastErrorMessage = nil
        defer { isUploading = false }

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await transport(request, pngData)
        } catch {
            let err = ScreenshotCloudUploadError.networkFailure(error.localizedDescription)
            lastErrorMessage = err.localizedDescription
            throw err
        }

        guard let http = response as? HTTPURLResponse else {
            lastErrorMessage = ScreenshotCloudUploadError.invalidResponse.localizedDescription
            throw ScreenshotCloudUploadError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let err = ScreenshotCloudUploadError.httpStatus(http.statusCode)
            lastErrorMessage = err.localizedDescription
            throw err
        }

        let publicURL: URL
        switch snapshot.provider {
        case .disabled:
            throw ScreenshotCloudUploadError.notConfigured
        case .s3Compatible:
            publicURL = resolvedFallbackURL
        case .customWebhook:
            if let extracted = Self.extractURL(fromJSON: responseData, keyPath: webhookKeyPath) {
                publicURL = extracted
            } else if let location = http.value(forHTTPHeaderField: "Location"),
                      let headerURL = ScreenshotCloudConfig.validatedHTTPURL(location) {
                publicURL = headerURL
            } else if let plain = String(data: responseData, encoding: .utf8),
                      let textURL = ScreenshotCloudConfig.validatedHTTPURL(plain) {
                publicURL = textURL
            } else {
                lastErrorMessage = ScreenshotCloudUploadError.invalidResponse.localizedDescription
                throw ScreenshotCloudUploadError.invalidResponse
            }
        }

        _ = pasteboardWriter(publicURL)
        lastUploadedURL = publicURL
        feedbackHandler(publicURL)
        return publicURL
    }
}
