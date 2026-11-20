// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The counters read so far and where reading stopped in each log, kept in
/// the app's own cache folder so a launch reads only what the agents wrote
/// since, instead of every log of the last thirteen weeks again. It holds
/// what the store holds in memory and nothing more: no prompt, reply or tool
/// output. Removed when the AI section is turned off.
///
/// A compact binary layout with shared strings: months of history hold
/// hundreds of thousands of responses that repeat a few models, folders and
/// sessions. A checksum covers everything after the magic, and every value
/// read back is checked the way the parser checks it. Anything unexpected,
/// including a file another build wrote, reads as nothing, and the logs are
/// read from their start as before.
enum AgentUsageArchive {
    struct Contents: Equatable {
        var providers: Set<AgentProvider>
        var store: AgentUsageStore.Saved
        var cursors: [AgentLogCursor.Saved]
    }

    private static let fileName = "agent-usage.bin"
    private static let magic: [UInt8] = Array("VAUA".utf8)
    private static let format = 4

    /// The parser and the store change between versions; what one build
    /// read is not taken for what another would have.
    static var build: String { build(info: Bundle.main.infoDictionary) }

    /// A Developer build keeps the version of the release it comes from, so
    /// its build stamp tells two of them apart.
    static func build(info: [String: Any]?) -> String {
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "")-\(info?["CFBundleVersion"] as? String ?? "")"
        guard let stamp = info?["VorssaintBuildCommit"] as? String else { return version }
        return "\(version) \(stamp)"
    }

    /// A cache the logs can rebuild: Time Machine leaves it out of backups,
    /// and if macOS clears it the next launch reads the logs from their start.
    private static var folder: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
              let bundleID = Bundle.main.bundleIdentifier else { return nil }
        return caches.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("AgentUsage", isDirectory: true)
    }

    private static var url: URL? {
        folder?.appendingPathComponent(fileName, isDirectory: false)
    }

    /// Minimum encoded byte length of one archive record on the wire (1 key,
    /// 1 provider, 8 date, 3 model/project/session, 1 requests, 5 tokens,
    /// 1 optional-cost tag, 8 savings, 1 same-billable tag, 5 billable flags/
    /// counts, 1 sources count = 35 bytes). Bounds `reserveCapacity` on
    /// malformed files.
    private static let minimumRecordWireBytes = 35

    static func load() -> Contents? {
        autoreleasepool {
            guard let url, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
            return decode(data, build: build)
        }
    }

    static func loadAndResume(expectedProviders: Set<AgentProvider>, logs found: Set<String>, since horizon: Date)
        -> (store: AgentUsageStore, cursors: [String: AgentLogCursor], unchanged: Bool)? {
        autoreleasepool {
            guard let url, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
            return decodeAndResume(data, build: build, expectedProviders: expectedProviders, logs: found, since: horizon)
        }
    }

    @discardableResult
    static func save(_ contents: Contents) -> Bool {
        autoreleasepool {
            guard let folder, let url, PrivateFileStore.createDirectory(at: folder, container: folder) else { return false }
            return PrivateFileStore.write(encode(contents, build: build), to: url)
        }
    }

    /// Encodes and streams directly from `AgentUsageStore` to disk via an
    /// atomic owner-only temp file, avoiding `[Saved.Record]`, `header.bytes`,
    /// and full-file `Data` allocations.
    @discardableResult
    static func save(providers: Set<AgentProvider>, store: AgentUsageStore, cursors: [AgentLogCursor.Saved]) -> Bool {
        autoreleasepool {
            guard let folder, let url, PrivateFileStore.createDirectory(at: folder, container: folder) else { return false }
            return writeStream(providers: providers, store: store, cursors: cursors, build: build, to: url)
        }
    }

    @discardableResult
    static func writeStream(providers: Set<AgentProvider>, store: AgentUsageStore,
                            cursors: [AgentLogCursor.Saved], build: String, to url: URL) -> Bool {
        autoreleasepool {
            let body = encodeBody(providers: providers, store: store, cursors: cursors, build: build)
            return streamWrite(body: body, to: url)
        }
    }

    /// The store and cursors a launch resumes with, given the logs `found`
    /// now, left as reading every log from its start would leave them. A log
    /// gone, replaced or rewritten since gives back what it gave, and one
    /// still there is read from its start again. A response it shared with
    /// another log kept the largest count either gave, so those logs are read
    /// again too. Limits and the plan describe the account when they were
    /// read, not the log, so the latest reading stays: a fresh read would
    /// fall back to an older one. `unchanged` tells whether the result is
    /// still what was saved.
    static func resume(_ contents: Contents, logs found: Set<String>, since horizon: Date)
        -> (store: AgentUsageStore, cursors: [String: AgentLogCursor], unchanged: Bool) {
        let store = AgentUsageStore(saved: contents.store)
        var cursors: [String: AgentLogCursor] = [:]
        for saved in contents.cursors where found.contains(saved.path) {
            cursors[saved.path] = AgentLogCursor(saved: saved)
        }
        var gone = store.files.subtracting(cursors.keys)
        let sharing = store.files(sharingWith: gone).subtracting(gone)
        for file in sharing { cursors[file] = nil }
        gone.formUnion(sharing)
        store.forget(files: gone)
        // Prices may be newer than the ones the counts were saved with.
        store.reprice()
        store.dropRecords(before: horizon)
        return (store, cursors, cursors.count == contents.cursors.count && store.matchesSaved(contents.store))
    }

    static func remove() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Layout

    static func encode(_ contents: Contents, build: String) -> Data {
        var body = Writer()
        body.string(build)
        body.count(contents.providers.count)
        for provider in contents.providers.sorted(by: { $0.rawValue < $1.rawValue }) { body.provider(provider) }
        let store = contents.store
        body.count(store.records.count)
        for entry in store.records {
            body.string(entry.key)
            body.record(entry.record)
            // The billed tokens are nearly always the recorded ones.
            let same = entry.billable.tokens == entry.record.tokens
            body.bool(same)
            if !same { body.tokens(entry.billable.tokens) }
            body.bool(entry.billable.isAggregate)
            body.int(entry.billable.longCacheWrite)
            body.bool(entry.billable.fast)
            body.bool(entry.billable.domestic)
            body.int(entry.billable.webSearches)
            body.count(entry.sources.count)
            for source in entry.sources { body.string(source) }
        }
        body.count(store.limits.count)
        for limits in store.limits { body.limits(limits) }
        body.optional(store.codexPlan) { $0.string($1) }
        body.date(store.codexPlanObserved)
        for sessions in [store.turns, store.waiting] {
            body.count(sessions.count)
            for session in sessions { body.session(session) }
        }
        body.count(contents.cursors.count)
        for cursor in contents.cursors {
            body.cursor(cursor)
        }
        return finalize(body: body)
    }

    /// Produces the exact same binary format as `encode(_:build:)` while
    /// streaming directly from `AgentUsageStore`'s compact internal storage.
    static func encode(providers: Set<AgentProvider>, store: AgentUsageStore,
                       cursors: [AgentLogCursor.Saved], build: String) -> Data {
        let body = encodeBody(providers: providers, store: store, cursors: cursors, build: build)
        return finalize(body: body)
    }

    private static func encodeBody(providers: Set<AgentProvider>, store: AgentUsageStore,
                                   cursors: [AgentLogCursor.Saved], build: String) -> Writer {
        let recordCount = store.archivableRecordCount
        var body = Writer()
        body.reserve(records: recordCount)
        body.string(build)
        body.count(providers.count)
        for provider in providers.sorted(by: { $0.rawValue < $1.rawValue }) { body.provider(provider) }
        body.count(recordCount)
        store.forEachArchivableRecord { key, record, billable, sourceList in
            body.string(key)
            body.record(record)
            let same = billable.tokens == record.tokens
            body.bool(same)
            if !same { body.tokens(billable.tokens) }
            body.bool(billable.isAggregate)
            body.int(billable.longCacheWrite)
            body.bool(billable.fast)
            body.bool(billable.domestic)
            body.int(billable.webSearches)
            body.count(sourceList.count)
            sourceList.forEachResolvedPath { body.string($0) }
        }
        let limits = store.archivableLimits
        body.count(limits.count)
        for limit in limits { body.limits(limit) }
        body.optional(store.codexPlan) { $0.string($1) }
        body.date(store.codexPlanObserved)
        for sessions in [store.archivableTurns, store.archivableWaiting] {
            body.count(sessions.count)
            for session in sessions { body.session(session) }
        }
        body.count(cursors.count)
        for cursor in cursors {
            body.cursor(cursor)
        }
        return body
    }

    private static let fnvOffsetBasis: UInt64 = 0xCBF2_9CE4_8422_2325
    private static let fnvPrime: UInt64 = 0x100_0000_01B3

    private static func zigzag(_ value: Int) -> UInt64 {
        UInt64(bitPattern: Int64(value) << 1 ^ Int64(value) >> 63)
    }

    private static func varintByteCount(_ value: UInt64) -> Int {
        var v = value
        var n = 1
        while v >= 0x80 {
            v >>= 7
            n += 1
        }
        return n
    }

    private static func appendVarint(_ value: UInt64, to buffer: inout [UInt8]) {
        var v = value
        while v >= 0x80 {
            buffer.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        buffer.append(UInt8(v))
    }

    private static func appendVarint(_ value: UInt64, to data: inout Data, hash: inout UInt64) {
        var v = value
        while v >= 0x80 {
            let byte = UInt8(v & 0x7F) | 0x80
            data.append(byte)
            hash = (hash ^ UInt64(byte)) &* fnvPrime
            v >>= 7
        }
        let byte = UInt8(v)
        data.append(byte)
        hash = (hash ^ UInt64(byte)) &* fnvPrime
    }

    private static func headerByteCount(strings: [String]) -> Int {
        var total = varintByteCount(zigzag(format)) + varintByteCount(UInt64(strings.count))
        for string in strings {
            let utf8Count = string.utf8.count
            total += varintByteCount(UInt64(utf8Count)) + utf8Count
        }
        return total
    }

    /// Writes `magic` + header + `body.bytes` + FNV-1a checksum into a single
    /// pre-sized `Data` without allocating an intermediate `header.bytes` array.
    private static func finalize(body: Writer) -> Data {
        let headerBytes = headerByteCount(strings: body.strings)
        var data = Data()
        data.reserveCapacity(magic.count + headerBytes + body.bytes.count + MemoryLayout<UInt64>.size)
        data.append(contentsOf: magic)
        var hash = fnvOffsetBasis
        appendVarint(zigzag(format), to: &data, hash: &hash)
        appendVarint(UInt64(body.strings.count), to: &data, hash: &hash)
        for string in body.strings {
            let utf8 = string.utf8
            appendVarint(UInt64(utf8.count), to: &data, hash: &hash)
            for byte in utf8 {
                hash = (hash ^ UInt64(byte)) &* fnvPrime
            }
            data.append(contentsOf: utf8)
        }
        for byte in body.bytes {
            hash = (hash ^ UInt64(byte)) &* fnvPrime
        }
        data.append(contentsOf: body.bytes)
        withUnsafeBytes(of: hash.littleEndian) { data.append(contentsOf: $0) }
        return data
    }

    /// Streams `magic` + header + `body.bytes` + FNV-1a checksum in 64 KB
    /// chunks directly to an atomic owner-only file (eliminating both
    /// `header.bytes` and the full-file `Data` buffer).
    private static func streamWrite(body: Writer, to url: URL) -> Bool {
        let chunkLimit = 64 * 1024
        return PrivateFileStore.writeStream(to: url) { emit in
            guard magic.withUnsafeBytes({ emit($0) }) else { return false }
            var hash = fnvOffsetBasis
            var staging: [UInt8] = []
            staging.reserveCapacity(chunkLimit)

            func flushStaging() -> Bool {
                guard !staging.isEmpty else { return true }
                for byte in staging {
                    hash = (hash ^ UInt64(byte)) &* fnvPrime
                }
                let ok = staging.withUnsafeBytes { emit($0) }
                staging.removeAll(keepingCapacity: true)
                return ok
            }

            appendVarint(zigzag(format), to: &staging)
            appendVarint(UInt64(body.strings.count), to: &staging)
            for string in body.strings {
                let utf8 = string.utf8
                if staging.count + 10 + utf8.count > chunkLimit && !staging.isEmpty {
                    guard flushStaging() else { return false }
                }
                appendVarint(UInt64(utf8.count), to: &staging)
                if staging.count + utf8.count <= chunkLimit {
                    staging.append(contentsOf: utf8)
                } else {
                    guard flushStaging() else { return false }
                    var chunk: [UInt8] = []
                    chunk.reserveCapacity(min(chunkLimit, utf8.count))
                    for byte in utf8 {
                        chunk.append(byte)
                        if chunk.count == chunkLimit {
                            for b in chunk { hash = (hash ^ UInt64(b)) &* fnvPrime }
                            guard chunk.withUnsafeBytes({ emit($0) }) else { return false }
                            chunk.removeAll(keepingCapacity: true)
                        }
                    }
                    if !chunk.isEmpty {
                        for b in chunk { hash = (hash ^ UInt64(b)) &* fnvPrime }
                        guard chunk.withUnsafeBytes({ emit($0) }) else { return false }
                    }
                }
            }
            guard flushStaging() else { return false }

            for byte in body.bytes {
                hash = (hash ^ UInt64(byte)) &* fnvPrime
            }
            guard body.bytes.withUnsafeBytes({ emit($0) }) else { return false }
            return withUnsafeBytes(of: hash.littleEndian) { emit($0) }
        }
    }

    private static func checksum(_ buffer: UnsafeRawBufferPointer) -> UInt64 {
        var hash = fnvOffsetBasis
        for byte in buffer { hash = (hash ^ UInt64(byte)) &* fnvPrime }
        return hash
    }

    static func decode(_ data: Data, build: String) -> Contents? {
        let sumSize = MemoryLayout<UInt64>.size
        guard data.count > magic.count + sumSize else { return nil }
        return data.withUnsafeBytes { rawBuffer -> Contents? in
            guard let base = rawBuffer.baseAddress, rawBuffer.count > magic.count + sumSize else { return nil }
            for i in 0..<magic.count where rawBuffer[i] != magic[i] { return nil }
            let payloadCount = rawBuffer.count - magic.count - sumSize
            let payload = UnsafeRawBufferPointer(start: base.advanced(by: magic.count), count: payloadCount)
            var sum: UInt64 = 0
            for i in stride(from: rawBuffer.count - 1, through: rawBuffer.count - sumSize, by: -1) {
                sum = (sum << 8) | UInt64(rawBuffer[i])
            }
            guard checksum(payload) == sum else { return nil }
            var reader = Reader(bytes: payload)
            do {
                guard try reader.int() == format else { return nil }
                let strings = try reader.count()
                reader.strings.reserveCapacity(strings)
                for _ in 0..<strings {
                    let length = try reader.count()
                    reader.strings.append(String(decoding: try reader.take(length), as: UTF8.self))
                }
                guard try reader.string() == build else { return nil }
                var providers = Set<AgentProvider>()
                for _ in 0..<(try reader.count()) { providers.insert(try reader.provider()) }
                var store = AgentUsageStore.Saved()
                let records = try reader.count()
                guard records <= reader.remainingBytes / minimumRecordWireBytes else { return nil }
                store.records.reserveCapacity(records)
                for _ in 0..<records {
                    let key = try reader.string()
                    let record = try reader.record()
                    let same = try reader.bool()
                    let billable = AgentBillable(tokens: same ? record.tokens : try reader.tokens(),
                                                 isAggregate: try reader.bool(),
                                                 longCacheWrite: try reader.amount(), fast: try reader.bool(),
                                                 domestic: try reader.bool(), webSearches: try reader.amount())
                    var sources: [String] = []
                    for _ in 0..<(try reader.count()) { sources.append(try reader.string()) }
                    store.records.append(.init(key: key, record: record, billable: billable, sources: sources))
                }
                for _ in 0..<(try reader.count()) { store.limits.append(try reader.limits()) }
                store.codexPlan = try reader.optional { try $0.string() }
                store.codexPlanObserved = try reader.date()
                for _ in 0..<(try reader.count()) { store.turns.append(try reader.session()) }
                for _ in 0..<(try reader.count()) { store.waiting.append(try reader.session()) }
                var cursors: [AgentLogCursor.Saved] = []
                for _ in 0..<(try reader.count()) {
                    cursors.append(try reader.cursor())
                }
                guard reader.atEnd else { return nil }
                return Contents(providers: providers, store: store, cursors: cursors)
            } catch {
                return nil
            }
        }
    }

    /// Decodes directly into `AgentUsageStore` and resumes in a single pass
    /// without allocating an intermediate `[AgentUsageStore.Saved.Record]` array.
    static func decodeAndResume(_ data: Data, build: String, expectedProviders: Set<AgentProvider>,
                                logs found: Set<String>, since horizon: Date)
        -> (store: AgentUsageStore, cursors: [String: AgentLogCursor], unchanged: Bool)? {
        let sumSize = MemoryLayout<UInt64>.size
        guard data.count > magic.count + sumSize else { return nil }
        return data.withUnsafeBytes { rawBuffer -> (store: AgentUsageStore, cursors: [String: AgentLogCursor], unchanged: Bool)? in
            guard let base = rawBuffer.baseAddress, rawBuffer.count > magic.count + sumSize else { return nil }
            for i in 0..<magic.count where rawBuffer[i] != magic[i] { return nil }
            let payloadCount = rawBuffer.count - magic.count - sumSize
            let payload = UnsafeRawBufferPointer(start: base.advanced(by: magic.count), count: payloadCount)
            var sum: UInt64 = 0
            for i in stride(from: rawBuffer.count - 1, through: rawBuffer.count - sumSize, by: -1) {
                sum = (sum << 8) | UInt64(rawBuffer[i])
            }
            guard checksum(payload) == sum else { return nil }
            var reader = Reader(bytes: payload)
            do {
                guard try reader.int() == format else { return nil }
                let strings = try reader.count()
                reader.strings.reserveCapacity(strings)
                for _ in 0..<strings {
                    let length = try reader.count()
                    reader.strings.append(String(decoding: try reader.take(length), as: UTF8.self))
                }
                guard try reader.string() == build else { return nil }
                var providers = Set<AgentProvider>()
                for _ in 0..<(try reader.count()) { providers.insert(try reader.provider()) }
                guard providers == expectedProviders else { return nil }

                let store = AgentUsageStore()
                let recordCount = try reader.count()
                guard recordCount <= reader.remainingBytes / minimumRecordWireBytes else { return nil }
                store.reserveArchiveCapacity(recordCount)
                let interner = AgentStringInterner.shared
                var hadNonArchivableContent = false
                for _ in 0..<recordCount {
                    let key = try reader.string()
                    let record = try reader.record()
                    if record.provider == .opencode { hadNonArchivableContent = true }
                    let same = try reader.bool()
                    let billable = AgentBillable(tokens: same ? record.tokens : try reader.tokens(),
                                                 isAggregate: try reader.bool(),
                                                 longCacheWrite: try reader.amount(), fast: try reader.bool(),
                                                 domestic: try reader.bool(), webSearches: try reader.amount())
                    var sourceIDs = AgentUsageStore.SourceList()
                    for _ in 0..<(try reader.count()) {
                        let path = try reader.string()
                        if path.isEmpty {
                            hadNonArchivableContent = true
                        } else {
                            let id = interner.intern(path)
                            if sourceIDs.contains(id) { hadNonArchivableContent = true }
                            sourceIDs.appendUnique(id)
                        }
                    }
                    if store.appendArchivedRecord(key: key, record: record, billable: billable, sourceIDs: sourceIDs) {
                        hadNonArchivableContent = true
                    }
                }
                var rawLimits: [AgentLimits] = []
                for _ in 0..<(try reader.count()) { rawLimits.append(try reader.limits()) }
                let codexPlan = try reader.optional { try $0.string() }
                let codexPlanObserved = try reader.date()
                var rawTurns: [AgentLiveSession] = []
                for _ in 0..<(try reader.count()) { rawTurns.append(try reader.session()) }
                var rawWaiting: [AgentLiveSession] = []
                for _ in 0..<(try reader.count()) { rawWaiting.append(try reader.session()) }
                store.restoreArchivedMetadata(limits: rawLimits, codexPlan: codexPlan,
                                              codexPlanObserved: codexPlanObserved,
                                              turns: rawTurns, waiting: rawWaiting)
                if store.archivableLimits != rawLimits
                    || store.archivableTurns != rawTurns
                    || store.archivableWaiting != rawWaiting {
                    hadNonArchivableContent = true
                }
                let rawCursorCount = try reader.count()
                var cursors: [String: AgentLogCursor] = [:]
                cursors.reserveCapacity(min(rawCursorCount, found.count))
                for _ in 0..<rawCursorCount {
                    let savedCursor = try reader.cursor()
                    if found.contains(savedCursor.path) {
                        cursors[savedCursor.path] = AgentLogCursor(saved: savedCursor)
                    }
                }
                guard reader.atEnd else { return nil }

                var gone = store.files.subtracting(cursors.keys)
                let sharing = store.files(sharingWith: gone).subtracting(gone)
                for file in sharing { cursors[file] = nil }
                gone.formUnion(sharing)
                store.forget(files: gone)
                let repriced = store.repriceReturningChanged()
                let dropped = store.dropRecordsReturningChanged(before: horizon)
                let unchanged = !hadNonArchivableContent
                    && cursors.count == rawCursorCount
                    && gone.isEmpty
                    && !repriced
                    && !dropped
                return (store, cursors, unchanged)
            } catch {
                return nil
            }
        }
    }

    // MARK: Writing

    private struct Writer {
        var bytes: [UInt8] = []
        private(set) var strings: [String] = []
        private var positions: [String: Int] = [:]

        mutating func reserve(records: Int) {
            guard records > 0 else { return }
            bytes.reserveCapacity(records * 64)
            strings.reserveCapacity(records + 1024)
            positions.reserveCapacity(records + 1024)
        }

        mutating func unsigned(_ value: UInt64) {
            var value = value
            while value >= 0x80 {
                bytes.append(UInt8(value & 0x7F) | 0x80)
                value >>= 7
            }
            bytes.append(UInt8(value))
        }

        mutating func int(_ value: Int) {
            unsigned(UInt64(bitPattern: Int64(value) << 1 ^ Int64(value) >> 63))
        }

        mutating func count(_ value: Int) { unsigned(UInt64(value)) }
        mutating func bool(_ value: Bool) { bytes.append(value ? 1 : 0) }

        mutating func double(_ value: Double) {
            withUnsafeBytes(of: value.bitPattern.littleEndian) { bytes.append(contentsOf: $0) }
        }

        mutating func date(_ value: Date) { double(value.timeIntervalSinceReferenceDate) }

        mutating func string(_ value: String) {
            if let position = positions[value] {
                count(position)
            } else {
                positions[value] = strings.count
                count(strings.count)
                strings.append(value)
            }
        }

        mutating func optional<Value>(_ value: Value?, _ write: (inout Writer, Value) -> Void) {
            bool(value != nil)
            if let value { write(&self, value) }
        }

        mutating func dictionary<Value>(_ values: [String: Value], _ write: (inout Writer, Value) -> Void) {
            count(values.count)
            for key in values.keys.sorted() {
                string(key)
                if let value = values[key] { write(&self, value) }
            }
        }

        mutating func provider(_ value: AgentProvider) { string(value.rawValue) }

        mutating func tokens(_ value: AgentTokens) {
            int(value.input)
            int(value.cacheWrite)
            int(value.cacheRead)
            int(value.output)
            int(value.reasoning)
        }

        mutating func record(_ value: AgentUsageRecord) {
            provider(value.provider)
            date(value.date)
            string(value.model)
            string(value.project)
            string(value.session)
            int(value.requests)
            tokens(value.tokens)
            optional(value.cost) { $0.double($1) }
            double(value.savings)
        }

        mutating func limits(_ value: AgentLimits) {
            provider(value.provider)
            count(value.windows.count)
            for window in value.windows {
                string(window.id)
                string(window.kind.rawValue)
                optional(window.minutes) { $0.int($1) }
                optional(window.scope) { $0.string($1) }
                double(window.usedPercent)
                optional(window.resetsAt) { $0.date($1) }
                optional(window.estimatedResetsAt) { $0.date($1) }
            }
            date(value.observedAt)
            switch value.source {
            case .sessionLog: count(0)
            case .claudeApp: count(1)
            case .account: count(2)
            }
        }

        mutating func session(_ value: AgentLiveSession) {
            string(value.id)
            provider(value.provider)
            date(value.started)
            date(value.lastActivity)
            string(value.model)
            string(value.project)
            tokens(value.tokens)
            double(value.cost)
        }

        mutating func state(_ value: AgentLogState) {
            string(value.session)
            string(value.project)
            string(value.model)
            bool(value.turnOpen)
            bool(value.sawUsageRecords)
            optional(value.lastTotal) { $0.tokens($1) }
            bool(value.fast)
            bool(value.codexSubagent)
            bool(value.codexHeaderRead)
            string(value.codexRoot)
            string(value.codexTotalsSession)
            dictionary(value.copilotTotals) { $0.tokens($1) }
            dictionary(value.copilotRequests) { $0.int($1) }
            dictionary(value.copilotRequestModels) { $0.string($1) }
            dictionary(value.copilotReportedRequests) { $0.int($1) }
            optional(value.copilotTurnID) { $0.string($1) }
            bool(value.copilotFinalResponse)
        }

        mutating func cursor(_ cursor: AgentLogCursor.Saved) {
            string(cursor.path)
            provider(cursor.provider)
            unsigned(cursor.offset)
            unsigned(cursor.identity)
            bool(cursor.discarding)
            date(cursor.modified)
            state(cursor.state)
            unsigned(cursor.fingerprint)
        }
    }

    // MARK: Reading

    private struct Malformed: Error {}

    private struct Reader {
        let bytes: UnsafeRawBufferPointer
        var position = 0
        var strings: [String] = []

        init(bytes: UnsafeRawBufferPointer) { self.bytes = bytes }

        var atEnd: Bool { position == bytes.count }
        var remainingBytes: Int { bytes.count - position }

        mutating func byte() throws -> UInt8 {
            guard position < bytes.count else { throw Malformed() }
            defer { position += 1 }
            return bytes[position]
        }

        mutating func take(_ length: Int) throws -> UnsafeRawBufferPointer {
            guard length >= 0, length <= bytes.count - position else { throw Malformed() }
            guard let base = bytes.baseAddress else {
                guard length == 0 else { throw Malformed() }
                return UnsafeRawBufferPointer(start: nil, count: 0)
            }
            let slice = UnsafeRawBufferPointer(start: base.advanced(by: position), count: length)
            position += length
            return slice
        }

        mutating func unsigned() throws -> UInt64 {
            var value: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                let next = try byte()
                guard shift < 64 else { throw Malformed() }
                value |= UInt64(next & 0x7F) << shift
                if next < 0x80 { return value }
                shift += 7
            }
        }

        mutating func int() throws -> Int {
            let raw = try unsigned()
            return Int(Int64(bitPattern: raw >> 1) ^ -Int64(bitPattern: raw & 1))
        }

        /// A count can never exceed the bytes left, which keeps a damaged
        /// file from asking for an enormous allocation.
        mutating func count() throws -> Int {
            let value = try unsigned()
            guard value <= UInt64(bytes.count - position) else { throw Malformed() }
            return Int(value)
        }

        mutating func bool() throws -> Bool {
            switch try byte() {
            case 0: return false
            case 1: return true
            default: throw Malformed()
            }
        }

        mutating func double() throws -> Double {
            var raw: UInt64 = 0
            for (shift, byte) in try take(8).enumerated() { raw |= UInt64(byte) << (8 * UInt64(shift)) }
            let value = Double(bitPattern: raw)
            guard value.isFinite else { throw Malformed() }
            return value
        }

        mutating func date() throws -> Date { Date(timeIntervalSinceReferenceDate: try double()) }

        mutating func string() throws -> String {
            let position = try unsigned()
            guard position < UInt64(strings.count) else { throw Malformed() }
            return strings[Int(position)]
        }

        mutating func optional<Value>(_ read: (inout Reader) throws -> Value) throws -> Value? {
            try bool() ? try read(&self) : nil
        }

        mutating func dictionary<Value>(_ read: (inout Reader) throws -> Value) throws -> [String: Value] {
            var values: [String: Value] = [:]
            for _ in 0..<(try count()) {
                let key = try string()
                guard values[key] == nil else { throw Malformed() }
                values[key] = try read(&self)
            }
            return values
        }

        mutating func provider() throws -> AgentProvider {
            guard let provider = AgentProvider(rawValue: try string()) else { throw Malformed() }
            return provider
        }

        /// Counts are never negative in a log, and never more than the rest
        /// of the file here.
        mutating func tokens() throws -> AgentTokens {
            AgentTokens(input: try amount(), cacheWrite: try amount(), cacheRead: try amount(),
                        output: try amount(), reasoning: try amount())
        }

        mutating func amount() throws -> Int {
            let value = try int()
            guard value >= 0 else { throw Malformed() }
            return value
        }

        mutating func record() throws -> AgentUsageRecord {
            AgentUsageRecord(provider: try provider(), date: try date(), model: try string(), project: try string(),
                             session: try string(), requests: try amount(),
                             tokens: try tokens(), cost: try optional { try $0.double() },
                             savings: try double())
        }

        mutating func limits() throws -> AgentLimits {
            let provider = try provider()
            var windows: [AgentLimitWindow] = []
            for _ in 0..<(try count()) {
                let id = try string()
                guard let kind = AgentLimitWindow.Kind(rawValue: try string()) else { throw Malformed() }
                windows.append(AgentLimitWindow(id: id, kind: kind, minutes: try optional { try $0.int() },
                                                scope: try optional { try $0.string() }, usedPercent: try double(),
                                                resetsAt: try optional { try $0.date() },
                                                estimatedResetsAt: try optional { try $0.date() }))
            }
            let observed = try date()
            let source: AgentLimits.Source
            switch try unsigned() {
            case 0: source = .sessionLog
            case 1: source = .claudeApp
            case 2: source = .account
            default: throw Malformed()
            }
            return AgentLimits(provider: provider, windows: windows, observedAt: observed, source: source)
        }

        mutating func session() throws -> AgentLiveSession {
            AgentLiveSession(id: try string(), provider: try provider(), started: try date(),
                             lastActivity: try date(), model: try string(), project: try string(),
                             tokens: try tokens(), cost: try double())
        }

        mutating func state() throws -> AgentLogState {
            var value = AgentLogState(session: try string(), project: try string(), model: try string(), turnOpen: try bool(),
                                      sawUsageRecords: try bool(), lastTotal: try optional { try $0.tokens() }, fast: try bool())
            value.codexSubagent = try bool()
            value.codexHeaderRead = try bool()
            value.codexRoot = try string()
            value.codexTotalsSession = try string()
            value.copilotTotals = try dictionary { try $0.tokens() }
            value.copilotRequests = try dictionary { try $0.amount() }
            value.copilotRequestModels = try dictionary { try $0.string() }
            value.copilotReportedRequests = try dictionary { try $0.amount() }
            value.copilotTurnID = try optional { try $0.string() }
            value.copilotFinalResponse = try bool()
            return value
        }

        mutating func cursor() throws -> AgentLogCursor.Saved {
            AgentLogCursor.Saved(path: try string(), provider: try provider(),
                                 offset: try unsigned(), identity: try unsigned(),
                                 discarding: try bool(), modified: try date(),
                                 state: try state(), fingerprint: try unsigned())
        }
    }
}
