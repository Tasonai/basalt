// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation
import os

/// Time window selectable for telemetry scrubbing in System Monitor.
enum TelemetryHorizon: String, CaseIterable, Identifiable, Sendable {
    case oneMinute = "1m"
    case oneHour = "1h"
    case twentyFourHours = "24h"

    var id: String { rawValue }
}

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
}

/// Bounded lock-protected ring store retaining 1m (60), 1h (360), and 24h (1440) downsampled telemetry buckets.
final class TelemetryHistoryRing: ObservableObject, @unchecked Sendable {
    static let shared = TelemetryHistoryRing()

    static let minuteCapacity = 60
    static let hourCapacity = 360
    static let dayCapacity = 1440

    private var lock = os_unfair_lock()
    private var minuteRing: [TelemetryPoint] = []
    private var hourRing: [TelemetryPoint] = []
    private var dayRing: [TelemetryPoint] = []
    private var lastHourBucket: TimeInterval = -1
    private var lastDayBucket: TimeInterval = -1

    func record(_ sample: TelemetryPoint) {
        os_unfair_lock_lock(&lock)
        append(sample, to: &minuteRing, capacity: Self.minuteCapacity)

        let hourBucket = floor(sample.timestamp / 10.0) * 10.0
        if hourBucket > lastHourBucket || hourRing.isEmpty {
            lastHourBucket = hourBucket
            append(sample, to: &hourRing, capacity: Self.hourCapacity)
        }

        let dayBucket = floor(sample.timestamp / 60.0) * 60.0
        if dayBucket > lastDayBucket || dayRing.isEmpty {
            lastDayBucket = dayBucket
            append(sample, to: &dayRing, capacity: Self.dayCapacity)
        }
        os_unfair_lock_unlock(&lock)
        if Thread.isMainThread {
            objectWillChange.send()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.objectWillChange.send()
            }
        }
    }

    func points(for horizon: TelemetryHorizon) -> [TelemetryPoint] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        switch horizon {
        case .oneMinute: return minuteRing
        case .oneHour: return hourRing
        case .twentyFourHours: return dayRing
        }
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
