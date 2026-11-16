// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import os
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Normalized clipboard item record stored in the local SQLite WAL + FTS5 index.
struct ClipboardSQLiteRow: Equatable, Codable, Sendable {
    let id: UUID
    let contentKind: String
    let plainText: String
    let sourceAppBundleID: String?
    let sourceAppName: String?
    let isPinned: Bool
    let byteCount: Int
    let createdAt: Date

    init(id: UUID = UUID(),
         contentKind: String = "text",
         plainText: String,
         sourceAppBundleID: String? = nil,
         sourceAppName: String? = nil,
         isPinned: Bool = false,
         byteCount: Int? = nil,
         createdAt: Date = Date()) {
        self.id = id
        self.contentKind = contentKind
        self.plainText = plainText
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
        self.isPinned = isPinned
        self.byteCount = byteCount ?? plainText.utf8.count
        self.createdAt = createdAt
    }
}

/// Thread-safe SQLite3 WAL + FTS5 full-text clipboard store supporting up to 50k items.
final class ClipboardSQLiteStore: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.vorssaint.utils", category: "ClipboardSQLiteStore")

    private let databaseURL: URL
    private let maxCapacity: Int
    private let lock = NSLock()
    private var db: OpaquePointer?

    init(databaseURL: URL, maxCapacity: Int = 50_000) {
        self.databaseURL = databaseURL
        self.maxCapacity = max(1, maxCapacity)
        openAndConfigure()
    }

    deinit {
        close()
    }

    func upsert(_ row: ClipboardSQLiteRow) {
        upsertBatch([row])
    }

    func upsertBatch(_ rows: [ClipboardSQLiteRow]) {
        guard !rows.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }

        guard executeTransactionLocked(db: db, work: {
            try upsertRowsLocked(rows, db: db)
            try enforceCapacityLocked(db: db)
        }) else {
            return
        }
    }

    func search(query: String, limit: Int = 200) -> [ClipboardSQLiteRow] {
        let effectiveLimit = max(1, limit)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }

        if trimmed.isEmpty {
            return fetchRecentLocked(db: db, limit: effectiveLimit)
        }

        if trimmed.count > 2, trimmed.hasPrefix("/"), trimmed.hasSuffix("/") {
            let pattern = String(trimmed.dropFirst().dropLast())
            return searchRegexLocked(db: db, pattern: pattern, limit: effectiveLimit)
        }

        let matchExpression = Self.fts5MatchQuery(for: trimmed)
        guard !matchExpression.isEmpty else {
            return searchLiteralFallbackLocked(db: db, needle: trimmed, limit: effectiveLimit)
        }
        return searchFTS5Locked(db: db, matchExpression: matchExpression, rawQuery: trimmed, limit: effectiveLimit)
    }

    func delete(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        let idString = id.uuidString

        _ = executeTransactionLocked(db: db) {
            try deleteByIDLocked(idString: idString, db: db)
        }
    }

    func clearNonPinned() {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }

        _ = executeTransactionLocked(db: db) {
            try executeSQL(
                "DELETE FROM clipboard_fts WHERE id IN (SELECT id FROM clipboard_items WHERE is_pinned = 0);",
                db: db
            )
            try executeSQL("DELETE FROM clipboard_items WHERE is_pinned = 0;", db: db)
        }
    }

    func totalCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return 0 }
        return totalCountLocked(db: db)
    }

    @discardableResult
    func migrateLegacyJSONIfNeeded(from jsonURL: URL) -> Int {
        let sentinelKey = "legacy_json_migrated::\(jsonURL.standardizedFileURL.path)"

        lock.lock()
        defer { lock.unlock() }
        guard let db else { return 0 }

        if metaValueLocked(forKey: sentinelKey, db: db) != nil {
            return 0
        }
        guard FileManager.default.fileExists(atPath: jsonURL.path),
              let data = try? Data(contentsOf: jsonURL),
              let legacyRows = Self.decodeLegacyRows(from: data) else {
            return 0
        }

        var importedCount = 0
        let succeeded = executeTransactionLocked(db: db) {
            if metaValueLocked(forKey: sentinelKey, db: db) != nil {
                return
            }
            importedCount = try insertLegacyRowsIgnoringDuplicatesLocked(legacyRows, db: db)
            try setMetaValueLocked("1", forKey: sentinelKey, db: db)
            try enforceCapacityLocked(db: db)
        }
        return succeeded ? importedCount : 0
    }

    func close() {
        lock.lock()
        let handle = db
        db = nil
        lock.unlock()

        if let handle {
            let status = sqlite3_close_v2(handle)
            if status != SQLITE_OK {
                Self.logger.error("sqlite3_close_v2 returned status \(status)")
            }
        }
    }

    // MARK: - Private Setup & Helpers

    private enum StoreError: Error {
        case sqliteFailure(Int32, String)
    }

    private struct LegacyHistoryEntryPayload: Decodable {
        let id: UUID?
        let text: String
        let copiedAt: Date?
        let pinnedAt: Date?
        let kind: String?
        let filePaths: [String]?
        let imageFile: String?
        let imageWidth: Int?
        let imageHeight: Int?
        let sourceBundleID: String?
        let ocrText: String?
    }

    private func openAndConfigure() {
        lock.lock()
        defer { lock.unlock() }

        if databaseURL.isFileURL {
            do {
                try FileManager.default.createDirectory(
                    at: databaseURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                Self.logger.error("Failed creating SQLite directory: \(error.localizedDescription, privacy: .public)")
            }
        }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let openStatus = sqlite3_open_v2(databaseURL.path, &handle, flags, nil)
        guard openStatus == SQLITE_OK, let handle else {
            let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            Self.logger.error("Failed opening SQLite database: \(message, privacy: .public)")
            if let handle { sqlite3_close_v2(handle) }
            return
        }

        sqlite3_busy_timeout(handle, 5_000)

        do {
            try executeSQL("PRAGMA journal_mode=WAL;", db: handle)
            try executeSQL("PRAGMA synchronous=NORMAL;", db: handle)
            try executeSQL("PRAGMA temp_store=MEMORY;", db: handle)
            try executeSQL(
                """
                CREATE TABLE IF NOT EXISTS clipboard_items (
                    id TEXT PRIMARY KEY NOT NULL,
                    content_kind TEXT NOT NULL,
                    plain_text TEXT NOT NULL,
                    source_app_bundle_id TEXT,
                    source_app_name TEXT,
                    is_pinned INTEGER NOT NULL DEFAULT 0,
                    byte_count INTEGER NOT NULL DEFAULT 0,
                    created_at REAL NOT NULL
                );
                """,
                db: handle
            )
            try executeSQL(
                "CREATE INDEX IF NOT EXISTS idx_clipboard_items_created_at ON clipboard_items(created_at DESC);",
                db: handle
            )
            try executeSQL(
                "CREATE INDEX IF NOT EXISTS idx_clipboard_items_pin_created ON clipboard_items(is_pinned ASC, created_at ASC);",
                db: handle
            )
            try executeSQL(
                """
                CREATE VIRTUAL TABLE IF NOT EXISTS clipboard_fts USING fts5(
                    id UNINDEXED,
                    plain_text,
                    source_app_name,
                    content_kind,
                    tokenize='unicode61'
                );
                """,
                db: handle
            )
            try executeSQL(
                """
                CREATE TABLE IF NOT EXISTS clipboard_meta (
                    key TEXT PRIMARY KEY NOT NULL,
                    value TEXT NOT NULL
                );
                """,
                db: handle
            )
            self.db = handle
            if databaseURL.isFileURL {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: databaseURL.path
                )
            }
        } catch {
            Self.logger.error("Failed configuring SQLite schema: \(error.localizedDescription, privacy: .public)")
            sqlite3_close_v2(handle)
        }
    }

    private func executeTransactionLocked(db: OpaquePointer, work: () throws -> Void) -> Bool {
        do {
            try executeSQL("BEGIN IMMEDIATE TRANSACTION;", db: db)
            try work()
            try executeSQL("COMMIT TRANSACTION;", db: db)
            return true
        } catch {
            _ = sqlite3_exec(db, "ROLLBACK TRANSACTION;", nil, nil, nil)
            Self.logger.error("SQLite transaction rolled back: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func upsertRowsLocked(_ rows: [ClipboardSQLiteRow], db: OpaquePointer) throws {
        let deleteFTSSQL = "DELETE FROM clipboard_fts WHERE id = ?;"
        let upsertItemSQL = """
            INSERT OR REPLACE INTO clipboard_items (
                id, content_kind, plain_text, source_app_bundle_id,
                source_app_name, is_pinned, byte_count, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """
        let insertFTSSQL = """
            INSERT INTO clipboard_fts (id, plain_text, source_app_name, content_kind)
            VALUES (?, ?, ?, ?);
            """

        var deleteFTSStmt: OpaquePointer?
        var upsertItemStmt: OpaquePointer?
        var insertFTSStmt: OpaquePointer?
        defer {
            if let deleteFTSStmt { sqlite3_finalize(deleteFTSStmt) }
            if let upsertItemStmt { sqlite3_finalize(upsertItemStmt) }
            if let insertFTSStmt { sqlite3_finalize(insertFTSStmt) }
        }

        try prepareStatement(deleteFTSSQL, db: db, into: &deleteFTSStmt)
        try prepareStatement(upsertItemSQL, db: db, into: &upsertItemStmt)
        try prepareStatement(insertFTSSQL, db: db, into: &insertFTSStmt)

        for row in rows {
            let idString = row.id.uuidString

            sqlite3_reset(deleteFTSStmt)
            sqlite3_clear_bindings(deleteFTSStmt)
            bindText(deleteFTSStmt, index: 1, value: idString)
            try stepDone(deleteFTSStmt, db: db)

            sqlite3_reset(upsertItemStmt)
            sqlite3_clear_bindings(upsertItemStmt)
            bindText(upsertItemStmt, index: 1, value: idString)
            bindText(upsertItemStmt, index: 2, value: row.contentKind)
            bindText(upsertItemStmt, index: 3, value: row.plainText)
            bindText(upsertItemStmt, index: 4, value: row.sourceAppBundleID)
            bindText(upsertItemStmt, index: 5, value: row.sourceAppName)
            sqlite3_bind_int(upsertItemStmt, 6, row.isPinned ? 1 : 0)
            sqlite3_bind_int64(upsertItemStmt, 7, Int64(row.byteCount))
            sqlite3_bind_double(upsertItemStmt, 8, row.createdAt.timeIntervalSince1970)
            try stepDone(upsertItemStmt, db: db)

            sqlite3_reset(insertFTSStmt)
            sqlite3_clear_bindings(insertFTSStmt)
            bindText(insertFTSStmt, index: 1, value: idString)
            bindText(insertFTSStmt, index: 2, value: row.plainText)
            bindText(insertFTSStmt, index: 3, value: row.sourceAppName)
            bindText(insertFTSStmt, index: 4, value: row.contentKind)
            try stepDone(insertFTSStmt, db: db)
        }
    }

    private func insertLegacyRowsIgnoringDuplicatesLocked(_ rows: [ClipboardSQLiteRow], db: OpaquePointer) throws -> Int {
        guard !rows.isEmpty else { return 0 }
        let insertItemSQL = """
            INSERT OR IGNORE INTO clipboard_items (
                id, content_kind, plain_text, source_app_bundle_id,
                source_app_name, is_pinned, byte_count, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """
        let deleteFTSSQL = "DELETE FROM clipboard_fts WHERE id = ?;"
        let insertFTSSQL = """
            INSERT INTO clipboard_fts (id, plain_text, source_app_name, content_kind)
            VALUES (?, ?, ?, ?);
            """

        var insertItemStmt: OpaquePointer?
        var deleteFTSStmt: OpaquePointer?
        var insertFTSStmt: OpaquePointer?
        defer {
            if let insertItemStmt { sqlite3_finalize(insertItemStmt) }
            if let deleteFTSStmt { sqlite3_finalize(deleteFTSStmt) }
            if let insertFTSStmt { sqlite3_finalize(insertFTSStmt) }
        }

        try prepareStatement(insertItemSQL, db: db, into: &insertItemStmt)
        try prepareStatement(deleteFTSSQL, db: db, into: &deleteFTSStmt)
        try prepareStatement(insertFTSSQL, db: db, into: &insertFTSStmt)

        var inserted = 0
        for row in rows {
            let idString = row.id.uuidString

            sqlite3_reset(insertItemStmt)
            sqlite3_clear_bindings(insertItemStmt)
            bindText(insertItemStmt, index: 1, value: idString)
            bindText(insertItemStmt, index: 2, value: row.contentKind)
            bindText(insertItemStmt, index: 3, value: row.plainText)
            bindText(insertItemStmt, index: 4, value: row.sourceAppBundleID)
            bindText(insertItemStmt, index: 5, value: row.sourceAppName)
            sqlite3_bind_int(insertItemStmt, 6, row.isPinned ? 1 : 0)
            sqlite3_bind_int64(insertItemStmt, 7, Int64(row.byteCount))
            sqlite3_bind_double(insertItemStmt, 8, row.createdAt.timeIntervalSince1970)
            try stepDone(insertItemStmt, db: db)

            if sqlite3_changes(db) > 0 {
                inserted += 1

                sqlite3_reset(deleteFTSStmt)
                sqlite3_clear_bindings(deleteFTSStmt)
                bindText(deleteFTSStmt, index: 1, value: idString)
                try stepDone(deleteFTSStmt, db: db)

                sqlite3_reset(insertFTSStmt)
                sqlite3_clear_bindings(insertFTSStmt)
                bindText(insertFTSStmt, index: 1, value: idString)
                bindText(insertFTSStmt, index: 2, value: row.plainText)
                bindText(insertFTSStmt, index: 3, value: row.sourceAppName)
                bindText(insertFTSStmt, index: 4, value: row.contentKind)
                try stepDone(insertFTSStmt, db: db)
            }
        }
        return inserted
    }

    private func deleteByIDLocked(idString: String, db: OpaquePointer) throws {
        var deleteFTSStmt: OpaquePointer?
        var deleteItemStmt: OpaquePointer?
        defer {
            if let deleteFTSStmt { sqlite3_finalize(deleteFTSStmt) }
            if let deleteItemStmt { sqlite3_finalize(deleteItemStmt) }
        }

        try prepareStatement("DELETE FROM clipboard_fts WHERE id = ?;", db: db, into: &deleteFTSStmt)
        bindText(deleteFTSStmt, index: 1, value: idString)
        try stepDone(deleteFTSStmt, db: db)

        try prepareStatement("DELETE FROM clipboard_items WHERE id = ?;", db: db, into: &deleteItemStmt)
        bindText(deleteItemStmt, index: 1, value: idString)
        try stepDone(deleteItemStmt, db: db)
    }

    private func enforceCapacityLocked(db: OpaquePointer) throws {
        let total = totalCountLocked(db: db)
        guard total > maxCapacity else { return }
        let excess = total - maxCapacity

        let deleteFTSExcessSQL = """
            DELETE FROM clipboard_fts WHERE id IN (
                SELECT id FROM clipboard_items
                ORDER BY is_pinned ASC, created_at ASC
                LIMIT ?
            );
            """
        let deleteItemsExcessSQL = """
            DELETE FROM clipboard_items WHERE id IN (
                SELECT id FROM clipboard_items
                ORDER BY is_pinned ASC, created_at ASC
                LIMIT ?
            );
            """

        var ftsStmt: OpaquePointer?
        var itemStmt: OpaquePointer?
        defer {
            if let ftsStmt { sqlite3_finalize(ftsStmt) }
            if let itemStmt { sqlite3_finalize(itemStmt) }
        }

        try prepareStatement(deleteFTSExcessSQL, db: db, into: &ftsStmt)
        sqlite3_bind_int64(ftsStmt, 1, Int64(excess))
        try stepDone(ftsStmt, db: db)

        try prepareStatement(deleteItemsExcessSQL, db: db, into: &itemStmt)
        sqlite3_bind_int64(itemStmt, 1, Int64(excess))
        try stepDone(itemStmt, db: db)
    }

    private func fetchRecentLocked(db: OpaquePointer, limit: Int) -> [ClipboardSQLiteRow] {
        let sql = """
            SELECT id, content_kind, plain_text, source_app_bundle_id,
                   source_app_name, is_pinned, byte_count, created_at
            FROM clipboard_items
            ORDER BY created_at DESC
            LIMIT ?;
            """
        var stmt: OpaquePointer?
        defer { if let stmt { sqlite3_finalize(stmt) } }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return []
        }
        sqlite3_bind_int64(stmt, 1, Int64(limit))
        return collectRows(from: stmt)
    }

    private func searchFTS5Locked(db: OpaquePointer,
                                  matchExpression: String,
                                  rawQuery: String,
                                  limit: Int) -> [ClipboardSQLiteRow] {
        let sql = """
            SELECT ci.id, ci.content_kind, ci.plain_text, ci.source_app_bundle_id,
                   ci.source_app_name, ci.is_pinned, ci.byte_count, ci.created_at
            FROM clipboard_fts
            JOIN clipboard_items ci ON ci.id = clipboard_fts.id
            WHERE clipboard_fts MATCH ?
            ORDER BY bm25(clipboard_fts) ASC, ci.created_at DESC
            LIMIT ?;
            """
        var stmt: OpaquePointer?
        defer { if let stmt { sqlite3_finalize(stmt) } }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return searchLiteralFallbackLocked(db: db, needle: rawQuery, limit: limit)
        }
        bindText(stmt, index: 1, value: matchExpression)
        sqlite3_bind_int64(stmt, 2, Int64(limit))
        return collectRows(from: stmt)
    }

    private func searchRegexLocked(db: OpaquePointer, pattern: String, limit: Int) -> [ClipboardSQLiteRow] {
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let sql = """
            SELECT id, content_kind, plain_text, source_app_bundle_id,
                   source_app_name, is_pinned, byte_count, created_at
            FROM clipboard_items
            ORDER BY created_at DESC;
            """
        var stmt: OpaquePointer?
        defer { if let stmt { sqlite3_finalize(stmt) } }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return []
        }

        var results: [ClipboardSQLiteRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let row = readRow(from: stmt) else { continue }
            let matched: Bool
            if let regex {
                let textRange = NSRange(row.plainText.startIndex..<row.plainText.endIndex, in: row.plainText)
                if regex.firstMatch(in: row.plainText, range: textRange) != nil {
                    matched = true
                } else if let appName = row.sourceAppName {
                    let appRange = NSRange(appName.startIndex..<appName.endIndex, in: appName)
                    matched = regex.firstMatch(in: appName, range: appRange) != nil
                } else {
                    matched = false
                }
            } else {
                matched = row.plainText.localizedCaseInsensitiveContains(pattern)
                    || (row.sourceAppName?.localizedCaseInsensitiveContains(pattern) == true)
            }
            if matched {
                results.append(row)
                if results.count >= limit { break }
            }
        }
        return results
    }

    private func searchLiteralFallbackLocked(db: OpaquePointer, needle: String, limit: Int) -> [ClipboardSQLiteRow] {
        let sql = """
            SELECT id, content_kind, plain_text, source_app_bundle_id,
                   source_app_name, is_pinned, byte_count, created_at
            FROM clipboard_items
            ORDER BY created_at DESC;
            """
        var stmt: OpaquePointer?
        defer { if let stmt { sqlite3_finalize(stmt) } }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return []
        }

        var results: [ClipboardSQLiteRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let row = readRow(from: stmt) else { continue }
            if row.plainText.localizedCaseInsensitiveContains(needle)
                || (row.sourceAppName?.localizedCaseInsensitiveContains(needle) == true) {
                results.append(row)
                if results.count >= limit { break }
            }
        }
        return results
    }

    private func totalCountLocked(db: OpaquePointer) -> Int {
        var stmt: OpaquePointer?
        defer { if let stmt { sqlite3_finalize(stmt) } }
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM clipboard_items;", -1, &stmt, nil) == SQLITE_OK,
              let stmt,
              sqlite3_step(stmt) == SQLITE_ROW else {
            return 0
        }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private func metaValueLocked(forKey key: String, db: OpaquePointer) -> String? {
        var stmt: OpaquePointer?
        defer { if let stmt { sqlite3_finalize(stmt) } }
        guard sqlite3_prepare_v2(db, "SELECT value FROM clipboard_meta WHERE key = ? LIMIT 1;", -1, &stmt, nil) == SQLITE_OK,
              let stmt else {
            return nil
        }
        bindText(stmt, index: 1, value: key)
        guard sqlite3_step(stmt) == SQLITE_ROW, let cStr = sqlite3_column_text(stmt, 0) else {
            return nil
        }
        return String(cString: cStr)
    }

    private func setMetaValueLocked(_ value: String, forKey key: String, db: OpaquePointer) throws {
        var stmt: OpaquePointer?
        defer { if let stmt { sqlite3_finalize(stmt) } }
        try prepareStatement("INSERT OR REPLACE INTO clipboard_meta (key, value) VALUES (?, ?);", db: db, into: &stmt)
        bindText(stmt, index: 1, value: key)
        bindText(stmt, index: 2, value: value)
        try stepDone(stmt, db: db)
    }

    private func collectRows(from stmt: OpaquePointer) -> [ClipboardSQLiteRow] {
        var rows: [ClipboardSQLiteRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let row = readRow(from: stmt) {
                rows.append(row)
            }
        }
        return rows
    }

    private func readRow(from stmt: OpaquePointer) -> ClipboardSQLiteRow? {
        guard let idCStr = sqlite3_column_text(stmt, 0),
              let id = UUID(uuidString: String(cString: idCStr)),
              let kindCStr = sqlite3_column_text(stmt, 1),
              let plainCStr = sqlite3_column_text(stmt, 2) else {
            return nil
        }
        let bundleID = sqlite3_column_type(stmt, 3) == SQLITE_NULL
            ? nil
            : sqlite3_column_text(stmt, 3).map { String(cString: $0) }
        let appName = sqlite3_column_type(stmt, 4) == SQLITE_NULL
            ? nil
            : sqlite3_column_text(stmt, 4).map { String(cString: $0) }
        let isPinned = sqlite3_column_int(stmt, 5) != 0
        let byteCount = Int(sqlite3_column_int64(stmt, 6))
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))

        return ClipboardSQLiteRow(
            id: id,
            contentKind: String(cString: kindCStr),
            plainText: String(cString: plainCStr),
            sourceAppBundleID: bundleID,
            sourceAppName: appName,
            isPinned: isPinned,
            byteCount: byteCount,
            createdAt: createdAt
        )
    }

    private func executeSQL(_ sql: String, db: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if status != SQLITE_OK {
            let msg = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(errorMessage)
            throw StoreError.sqliteFailure(status, msg)
        }
    }

    private func prepareStatement(_ sql: String, db: OpaquePointer, into stmt: inout OpaquePointer?) throws {
        let status = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        if status != SQLITE_OK {
            throw StoreError.sqliteFailure(status, String(cString: sqlite3_errmsg(db)))
        }
    }

    private func stepDone(_ stmt: OpaquePointer?, db: OpaquePointer) throws {
        let status = sqlite3_step(stmt)
        if status != SQLITE_DONE && status != SQLITE_ROW {
            throw StoreError.sqliteFailure(status, String(cString: sqlite3_errmsg(db)))
        }
    }

    private func bindText(_ stmt: OpaquePointer?, index: Int32, value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private static func fts5MatchQuery(for query: String) -> String {
        let tokens = query
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return "" }
        return tokens.map { token in
            let escaped = token.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\"*"
        }.joined(separator: " ")
    }

    private static func decodeLegacyRows(from data: Data) -> [ClipboardSQLiteRow]? {
        let decoder = JSONDecoder()
        if let rows = try? decoder.decode([ClipboardSQLiteRow].self, from: data) {
            return rows
        }
        guard let entries = try? decoder.decode([LegacyHistoryEntryPayload].self, from: data) else {
            return nil
        }
        return entries.map { entry in
            let kind = entry.kind ?? "text"
            let searchableText: String
            switch kind {
            case "image":
                let dims = (entry.imageWidth != nil && entry.imageHeight != nil)
                    ? "\(entry.imageWidth!)×\(entry.imageHeight!)"
                    : nil
                searchableText = [entry.ocrText, dims, entry.imageFile]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            case "files":
                let filesText = (entry.filePaths ?? []).joined(separator: "\n")
                searchableText = [filesText, entry.ocrText]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
            default:
                searchableText = entry.text
            }
            return ClipboardSQLiteRow(
                id: entry.id ?? UUID(),
                contentKind: kind,
                plainText: searchableText,
                sourceAppBundleID: entry.sourceBundleID,
                sourceAppName: nil,
                isPinned: entry.pinnedAt != nil,
                byteCount: searchableText.utf8.count,
                createdAt: entry.copiedAt ?? Date()
            )
        }
    }
}
