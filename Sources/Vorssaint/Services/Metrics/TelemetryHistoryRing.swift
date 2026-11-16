// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation
import SQLite3
import os

/// Time window selectable for telemetry scrubbing in System Monitor.
enum TelemetryHorizon: String, CaseIterable, Identifiable, Sendable {
    case oneMinute = "1m"
    case oneHour = "1h"
    case twentyFourHours = "24h"
    case sevenDays = "7d"

    var id: String { rawValue }

    var capacity: Int {
        switch self {
        case .oneMinute: return TelemetryHistoryRing.minuteCapacity
        case .oneHour: return TelemetryHistoryRing.hourCapacity
        case .twentyFourHours: return TelemetryHistoryRing.dayCapacity
        case .sevenDays: return TelemetryHistoryRing.sevenDayCapacity
        }
    }
}

typealias TelemetryHistoryHorizon = TelemetryHorizon

enum TelemetryMetricKind: String, CaseIterable, Equatable, Sendable {
    case cpu
    case gpu
    case memory
    case network
}

struct TelemetryPoint: Equatable, Sendable {
    let timestamp: TimeInterval
    let cpu: Double
    let gpu: Double
    let memory: Double
    let networkBytesPerSec: Double
    let netRxBytesPerSec: Double
    let netTxBytesPerSec: Double
    let watts: Double

    var cpuPercent: Double { cpu }
    var gpuPercent: Double { gpu }
    var memoryPercent: Double { memory }

    init(
        timestamp: TimeInterval,
        cpu: Double,
        gpu: Double,
        memory: Double,
        networkBytesPerSec: Double,
        netRxBytesPerSec: Double? = nil,
        netTxBytesPerSec: Double = 0,
        watts: Double = 0
    ) {
        self.timestamp = timestamp
        self.cpu = cpu
        self.gpu = gpu
        self.memory = memory
        self.networkBytesPerSec = networkBytesPerSec
        self.netRxBytesPerSec = netRxBytesPerSec ?? networkBytesPerSec
        self.netTxBytesPerSec = netTxBytesPerSec
        self.watts = watts
    }
}

/// Bounded lock-protected ring store retaining 1m (60), 1h (360), 24h (1440), and 7d (2016)
/// downsampled telemetry buckets, optionally backed by a SQLite WAL store.
final class TelemetryHistoryRing: ObservableObject, @unchecked Sendable {
    static let shared = TelemetryHistoryRing()

    static let minuteCapacity = 60
    static let hourCapacity = 360
    static let dayCapacity = 1440
    static let sevenDayCapacity = 2016

    private static let autoFlushThreshold = 10
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private var lock = os_unfair_lock()
    private var minuteRing: [TelemetryPoint] = []
    private var hourRing: [TelemetryPoint] = []
    private var dayRing: [TelemetryPoint] = []
    private var sevenDayRing: [TelemetryPoint] = []
    private var lastHourBucket: TimeInterval = -1
    private var lastDayBucket: TimeInterval = -1
    private var lastSevenDayBucket: TimeInterval = -1

    private var sqliteDB: OpaquePointer?
    private var pendingInserts: [(horizon: TelemetryHorizon, point: TelemetryPoint)] = []
    private var recordsSinceFlush = 0

    deinit {
        closeSQLiteStore()
    }

    func record(_ sample: TelemetryPoint) {
        let clean = sanitize(sample)

        os_unfair_lock_lock(&lock)
        append(clean, to: &minuteRing, capacity: Self.minuteCapacity)
        enqueuePendingInsertLocked(horizon: .oneMinute, point: clean)

        let hourBucket = floor(clean.timestamp / 10.0) * 10.0
        if hourBucket > lastHourBucket || hourRing.isEmpty {
            lastHourBucket = hourBucket
            append(clean, to: &hourRing, capacity: Self.hourCapacity)
            enqueuePendingInsertLocked(horizon: .oneHour, point: clean)
        }

        let dayBucket = floor(clean.timestamp / 60.0) * 60.0
        if dayBucket > lastDayBucket || dayRing.isEmpty {
            lastDayBucket = dayBucket
            append(clean, to: &dayRing, capacity: Self.dayCapacity)
            enqueuePendingInsertLocked(horizon: .twentyFourHours, point: clean)
        }

        let sevenDayBucket = floor(clean.timestamp / 300.0) * 300.0
        if sevenDayBucket > lastSevenDayBucket || sevenDayRing.isEmpty {
            lastSevenDayBucket = sevenDayBucket
            append(clean, to: &sevenDayRing, capacity: Self.sevenDayCapacity)
            enqueuePendingInsertLocked(horizon: .sevenDays, point: clean)
        }

        if sqliteDB != nil {
            recordsSinceFlush += 1
            if recordsSinceFlush >= Self.autoFlushThreshold || pendingInserts.count >= Self.autoFlushThreshold {
                flushSQLiteStoreLocked()
            }
        }
        os_unfair_lock_unlock(&lock)

        notifyObservers()
    }

    func record(
        cpuPercent: Double,
        gpuPercent: Double,
        memoryPercent: Double,
        netRxBytesPerSec: Double,
        netTxBytesPerSec: Double,
        watts: Double = 0,
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) {
        let rx = netRxBytesPerSec.isFinite ? max(0, netRxBytesPerSec) : 0
        let tx = netTxBytesPerSec.isFinite ? max(0, netTxBytesPerSec) : 0
        record(TelemetryPoint(
            timestamp: timestamp,
            cpu: cpuPercent,
            gpu: gpuPercent,
            memory: memoryPercent,
            networkBytesPerSec: rx + tx,
            netRxBytesPerSec: rx,
            netTxBytesPerSec: tx,
            watts: watts
        ))
    }

    func points(for horizon: TelemetryHorizon) -> [TelemetryPoint] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        switch horizon {
        case .oneMinute: return minuteRing
        case .oneHour: return hourRing
        case .twentyFourHours: return dayRing
        case .sevenDays: return sevenDayRing
        }
    }

    func samples(for horizon: TelemetryHorizon) -> [TelemetryPoint] {
        points(for: horizon)
    }

    func series(for metric: TelemetryMetricKind, horizon: TelemetryHorizon) -> [Double] {
        let list = points(for: horizon)
        guard !list.isEmpty else { return [] }
        switch metric {
        case .cpu:
            return list.map { min(1.0, max(0.0, $0.cpu / 100.0)) }
        case .gpu:
            return list.map { min(1.0, max(0.0, $0.gpu / 100.0)) }
        case .memory:
            return list.map { min(1.0, max(0.0, $0.memory / 100.0)) }
        case .network:
            let peak = max(list.map(\.networkBytesPerSec).max() ?? 0, 1.0)
            return list.map { min(1.0, max(0.0, $0.networkBytesPerSec / peak)) }
        }
    }

    func scrubPoint(for horizon: TelemetryHorizon, normalizedX: Double) -> TelemetryPoint? {
        let list = points(for: horizon)
        guard !list.isEmpty else { return nil }
        let clamped = min(max(normalizedX, 0), 1)
        let index = min(list.count - 1, max(0, Int((clamped * Double(list.count - 1)).rounded())))
        return list[index]
    }

    func attachSQLiteStore(at url: URL) {
        let parentDir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        os_unfair_lock_lock(&lock)
        closeSQLiteStoreLocked()

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK, let db else {
            if let db {
                sqlite3_close(db)
            }
            os_unfair_lock_unlock(&lock)
            return
        }

        sqlite3_busy_timeout(db, 500)
        _ = sqlite3_exec(db, "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;", nil, nil, nil)

        let schemaSQL = """
        CREATE TABLE IF NOT EXISTS telemetry_samples (
            horizon TEXT NOT NULL,
            timestamp REAL NOT NULL,
            cpu REAL NOT NULL,
            gpu REAL NOT NULL,
            memory REAL NOT NULL,
            net_rx REAL NOT NULL,
            net_tx REAL NOT NULL,
            watts REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_telemetry_samples_horizon_ts
            ON telemetry_samples (horizon, timestamp);
        """
        guard sqlite3_exec(db, schemaSQL, nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(db)
            os_unfair_lock_unlock(&lock)
            return
        }

        sqliteDB = db
        let loadedAny = loadRingsFromSQLiteLocked(db: db)
        os_unfair_lock_unlock(&lock)

        if loadedAny {
            notifyObservers()
        }
    }

    func flushSQLiteStore() {
        os_unfair_lock_lock(&lock)
        flushSQLiteStoreLocked()
        os_unfair_lock_unlock(&lock)
    }

    func closeSQLiteStore() {
        os_unfair_lock_lock(&lock)
        closeSQLiteStoreLocked()
        os_unfair_lock_unlock(&lock)
    }

    private func closeSQLiteStoreLocked() {
        flushSQLiteStoreLocked()
        if let db = sqliteDB {
            sqlite3_close(db)
            sqliteDB = nil
        }
        pendingInserts.removeAll(keepingCapacity: false)
        recordsSinceFlush = 0
    }

    private func enqueuePendingInsertLocked(horizon: TelemetryHorizon, point: TelemetryPoint) {
        guard sqliteDB != nil else { return }
        pendingInserts.append((horizon: horizon, point: point))
        if pendingInserts.count > 8192 {
            pendingInserts.removeFirst(pendingInserts.count - 8192)
        }
    }

    private func flushSQLiteStoreLocked() {
        guard let db = sqliteDB, !pendingInserts.isEmpty else {
            recordsSinceFlush = 0
            return
        }

        guard sqlite3_exec(db, "BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK else {
            return
        }

        let insertSQL = """
        INSERT INTO telemetry_samples (horizon, timestamp, cpu, gpu, memory, net_rx, net_tx, watts)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        var insertStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK, let insertStmt else {
            _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            return
        }
        defer { sqlite3_finalize(insertStmt) }

        var dirtyHorizons: Set<TelemetryHorizon> = []
        for entry in pendingInserts {
            sqlite3_reset(insertStmt)
            sqlite3_clear_bindings(insertStmt)

            let horizonStr = entry.horizon.rawValue
            sqlite3_bind_text(insertStmt, 1, horizonStr, -1, Self.sqliteTransient)
            sqlite3_bind_double(insertStmt, 2, entry.point.timestamp)
            sqlite3_bind_double(insertStmt, 3, entry.point.cpu)
            sqlite3_bind_double(insertStmt, 4, entry.point.gpu)
            sqlite3_bind_double(insertStmt, 5, entry.point.memory)
            sqlite3_bind_double(insertStmt, 6, entry.point.netRxBytesPerSec)
            sqlite3_bind_double(insertStmt, 7, entry.point.netTxBytesPerSec)
            sqlite3_bind_double(insertStmt, 8, entry.point.watts)

            guard sqlite3_step(insertStmt) == SQLITE_DONE else {
                _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                return
            }
            dirtyHorizons.insert(entry.horizon)
        }

        let pruneSQL = """
        DELETE FROM telemetry_samples
        WHERE horizon = ?
          AND rowid NOT IN (
              SELECT rowid FROM telemetry_samples
              WHERE horizon = ?
              ORDER BY timestamp DESC, rowid DESC
              LIMIT ?
          );
        """
        var pruneStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, pruneSQL, -1, &pruneStmt, nil) == SQLITE_OK, let pruneStmt {
            defer { sqlite3_finalize(pruneStmt) }
            for horizon in dirtyHorizons {
                sqlite3_reset(pruneStmt)
                sqlite3_clear_bindings(pruneStmt)
                let h = horizon.rawValue
                sqlite3_bind_text(pruneStmt, 1, h, -1, Self.sqliteTransient)
                sqlite3_bind_text(pruneStmt, 2, h, -1, Self.sqliteTransient)
                sqlite3_bind_int64(pruneStmt, 3, Int64(horizon.capacity))
                guard sqlite3_step(pruneStmt) == SQLITE_DONE else {
                    _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                    return
                }
            }
        }

        if sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK {
            pendingInserts.removeAll(keepingCapacity: true)
            recordsSinceFlush = 0
        } else {
            _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
        }
    }

    private func loadRingsFromSQLiteLocked(db: OpaquePointer) -> Bool {
        let selectSQL = """
        SELECT timestamp, cpu, gpu, memory, net_rx, net_tx, watts
        FROM telemetry_samples
        WHERE horizon = ?
        ORDER BY timestamp DESC, rowid DESC
        LIMIT ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return false
        }
        defer { sqlite3_finalize(stmt) }

        var loadedAny = false
        for horizon in TelemetryHorizon.allCases {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_bind_text(stmt, 1, horizon.rawValue, -1, Self.sqliteTransient)
            sqlite3_bind_int64(stmt, 2, Int64(horizon.capacity))

            var rows: [TelemetryPoint] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let ts = sqlite3_column_double(stmt, 0)
                let cpu = sqlite3_column_double(stmt, 1)
                let gpu = sqlite3_column_double(stmt, 2)
                let mem = sqlite3_column_double(stmt, 3)
                let rx = max(0, sqlite3_column_double(stmt, 4))
                let tx = max(0, sqlite3_column_double(stmt, 5))
                let watts = max(0, sqlite3_column_double(stmt, 6))
                rows.append(TelemetryPoint(
                    timestamp: ts,
                    cpu: cpu,
                    gpu: gpu,
                    memory: mem,
                    networkBytesPerSec: rx + tx,
                    netRxBytesPerSec: rx,
                    netTxBytesPerSec: tx,
                    watts: watts
                ))
            }

            guard !rows.isEmpty else { continue }
            loadedAny = true
            rows.reverse()

            switch horizon {
            case .oneMinute:
                mergeLoaded(rows, into: &minuteRing, capacity: Self.minuteCapacity)
            case .oneHour:
                mergeLoaded(rows, into: &hourRing, capacity: Self.hourCapacity)
                if let last = hourRing.last {
                    lastHourBucket = floor(last.timestamp / 10.0) * 10.0
                }
            case .twentyFourHours:
                mergeLoaded(rows, into: &dayRing, capacity: Self.dayCapacity)
                if let last = dayRing.last {
                    lastDayBucket = floor(last.timestamp / 60.0) * 60.0
                }
            case .sevenDays:
                mergeLoaded(rows, into: &sevenDayRing, capacity: Self.sevenDayCapacity)
                if let last = sevenDayRing.last {
                    lastSevenDayBucket = floor(last.timestamp / 300.0) * 300.0
                }
            }
        }
        return loadedAny
    }

    private func mergeLoaded(_ loaded: [TelemetryPoint], into ring: inout [TelemetryPoint], capacity: Int) {
        if ring.isEmpty {
            ring = loaded
        } else {
            ring = loaded + ring
        }
        if ring.count > capacity {
            ring.removeFirst(ring.count - capacity)
        }
    }

    private func sanitize(_ sample: TelemetryPoint) -> TelemetryPoint {
        let ts = sample.timestamp.isFinite ? sample.timestamp : Date().timeIntervalSince1970
        let cpu = sample.cpu.isFinite ? sample.cpu : 0
        let gpu = sample.gpu.isFinite ? sample.gpu : 0
        let mem = sample.memory.isFinite ? sample.memory : 0
        let rx = sample.netRxBytesPerSec.isFinite ? max(0, sample.netRxBytesPerSec) : 0
        let tx = sample.netTxBytesPerSec.isFinite ? max(0, sample.netTxBytesPerSec) : 0
        let net = sample.networkBytesPerSec.isFinite ? max(0, sample.networkBytesPerSec) : (rx + tx)
        let watts = sample.watts.isFinite ? max(0, sample.watts) : 0
        return TelemetryPoint(
            timestamp: ts,
            cpu: cpu,
            gpu: gpu,
            memory: mem,
            networkBytesPerSec: net,
            netRxBytesPerSec: rx,
            netTxBytesPerSec: tx,
            watts: watts
        )
    }

    private func notifyObservers() {
        if Thread.isMainThread {
            objectWillChange.send()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.objectWillChange.send()
            }
        }
    }

    private func append(_ point: TelemetryPoint, to ring: inout [TelemetryPoint], capacity: Int) {
        ring.append(point)
        if ring.count > capacity {
            ring.removeFirst(ring.count - capacity)
        }
    }
}

/// Breaks aggregate per-core utilization into Efficiency (E), Performance (P), and ANE activity estimates.
enum AppleSiliconClusterEstimator {
    struct Breakdown: Equatable, Sendable {
        let eCorePercent: Double
        let pCorePercent: Double
        let aneActivityPercent: Double
    }

    static func estimate(coreLoads: [Double], efficiencyCoreCount: Int = 4, gpuLoad: Double = 0) -> Breakdown {
        guard !coreLoads.isEmpty else {
            return Breakdown(eCorePercent: 0, pCorePercent: 0, aneActivityPercent: 0)
        }
        let eCount = min(max(1, efficiencyCoreCount), coreLoads.count)
        let eSlice = coreLoads.prefix(eCount)
        let pSlice = coreLoads.dropFirst(eCount)
        let eAvg = eSlice.reduce(0, +) / Double(eSlice.count)
        let pAvg = pSlice.isEmpty ? eAvg : pSlice.reduce(0, +) / Double(pSlice.count)
        let ane = min(100, max(0, (pAvg * 0.15 + gpuLoad * 0.25)))
        return Breakdown(
            eCorePercent: min(100, max(0, eAvg)),
            pCorePercent: min(100, max(0, pAvg)),
            aneActivityPercent: ane
        )
    }
}

/// Formats fixed-width two-row stacked menu bar telemetry strings (`CPU` / `42%`).
enum MenuBarTwoRowFormatter {
    static func formatTwoRowMetric(topLabel: String, bottomValue: String) -> String {
        "\(topLabel)\n\(bottomValue)"
    }

    static func compactPercent(_ fraction0to100: Double) -> String {
        let clamped = Int(min(max(fraction0to100, 0), 100).rounded())
        return "\(clamped)%"
    }

    static func compactRate(bytesPerSec: Double) -> String {
        let b = max(0, bytesPerSec)
        let posix = Locale(identifier: "en_US_POSIX")
        if b >= 1_000_000_000 { return String(format: "%.1fG", locale: posix, b / 1_000_000_000) }
        if b >= 1_000_000 { return String(format: "%.1fM", locale: posix, b / 1_000_000) }
        if b >= 1_000 { return String(format: "%.0fK", locale: posix, b / 1_000) }
        return String(format: "%.0fB", locale: posix, b)
    }
}
