// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import CoreGraphics
import Foundation

/// Custom multi-column/row snap grid specification with gap calculation.
struct CustomSnapGridSpec: Codable, Equatable, Sendable {
    var columns: Int
    var rows: Int
    var gap: CGFloat

    init(columns: Int = 3, rows: Int = 2, gap: CGFloat = 8) {
        self.columns = max(1, min(columns, 8))
        self.rows = max(1, min(rows, 6))
        self.gap = max(0, gap)
    }

    func cellFrame(in screenBounds: CGRect,
                   colRange: ClosedRange<Int>,
                   rowRange: ClosedRange<Int>) -> CGRect {
        let cStart = max(0, min(colRange.lowerBound, columns - 1))
        let cEnd = max(cStart, min(colRange.upperBound, columns - 1))
        let rStart = max(0, min(rowRange.lowerBound, rows - 1))
        let rEnd = max(rStart, min(rowRange.upperBound, rows - 1))

        let totalHGap = gap * CGFloat(columns + 1)
        let totalVGap = gap * CGFloat(rows + 1)
        let cellW = max(1, (screenBounds.width - totalHGap) / CGFloat(columns))
        let cellH = max(1, (screenBounds.height - totalVGap) / CGFloat(rows))

        let spanCols = CGFloat(cEnd - cStart + 1)
        let spanRows = CGFloat(rEnd - rStart + 1)

        let x = screenBounds.minX + gap * CGFloat(cStart + 1) + cellW * CGFloat(cStart)
        let y = screenBounds.minY + gap * CGFloat(rStart + 1) + cellH * CGFloat(rStart)
        let w = cellW * spanCols + gap * CGFloat(cEnd - cStart)
        let h = cellH * spanRows + gap * CGFloat(rEnd - rStart)
        return CGRect(x: x.rounded(), y: y.rounded(), width: w.rounded(), height: h.rounded())
    }
}

/// Relative window slot stored inside a reusable Workspace layout snapshot.
struct WindowWorkspaceSlot: Codable, Equatable, Sendable {
    let bundleID: String
    let normalizedX: Double
    let normalizedY: Double
    let normalizedWidth: Double
    let normalizedHeight: Double

    func frame(in bounds: CGRect) -> CGRect {
        CGRect(x: (bounds.minX + bounds.width * normalizedX).rounded(),
               y: (bounds.minY + bounds.height * normalizedY).rounded(),
               width: (bounds.width * normalizedWidth).rounded(),
               height: (bounds.height * normalizedHeight).rounded())
    }
}

struct WindowWorkspacePreset: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var slots: [WindowWorkspaceSlot]

    init(id: UUID = UUID(), name: String, slots: [WindowWorkspaceSlot]) {
        self.id = id
        self.name = name
        self.slots = slots
    }
}

/// Persists named multi-window Workspace presets in injectable `UserDefaults`.
final class WindowWorkspaceStore: ObservableObject {
    static let shared = WindowWorkspaceStore()
    static let maxPresets = 8

    @Published private(set) var presets: [WindowWorkspacePreset] = []

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "windowWorkspacesJSON") {
        self.defaults = defaults
        self.key = key
        load()
    }

    @discardableResult
    func savePreset(name: String, slots: [WindowWorkspaceSlot]) -> WindowWorkspacePreset {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = WindowWorkspacePreset(name: trimmed.isEmpty ? "Workspace" : trimmed, slots: slots)
        presets.insert(preset, at: 0)
        if presets.count > Self.maxPresets {
            presets = Array(presets.prefix(Self.maxPresets))
        }
        persist()
        return preset
    }

    func deletePreset(id: UUID) {
        presets.removeAll { $0.id == id }
        persist()
    }

    private func load() {
        guard let raw = defaults.string(forKey: key),
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([WindowWorkspacePreset].self, from: data) else {
            presets = []
            return
        }
        presets = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(presets),
              let raw = String(data: data, encoding: .utf8) else { return }
        defaults.set(raw, forKey: key)
    }
}

/// Actions triggered by double-click, right-click, or scroll gestures inside a window's titlebar band.
enum TitlebarGestureAction: String, CaseIterable, Equatable, Sendable {
    case maximize
    case fill
    case center
    case minimize
    case rollUp
}

final class TitlebarGestureService: ObservableObject {
    static let shared = TitlebarGestureService()

    enum GestureEventKind: Equatable, Sendable {
        case doubleClick
        case rightClick
        case scrollUp
        case scrollDown
    }

    static func classify(point: CGPoint,
                         inWindowFrame windowFrame: CGRect,
                         titlebarHeight: CGFloat = 28,
                         eventKind: GestureEventKind) -> TitlebarGestureAction? {
        guard windowFrame.width > 0, windowFrame.height > 0,
              point.x >= windowFrame.minX, point.x <= windowFrame.maxX else {
            return nil
        }
        // Standard Cocoa screen coordinates put the titlebar along the top edge (maxY - titlebarHeight...maxY).
        let band = CGRect(x: windowFrame.minX,
                          y: windowFrame.maxY - titlebarHeight,
                          width: windowFrame.width,
                          height: titlebarHeight)
        guard band.contains(point) else { return nil }
        switch eventKind {
        case .doubleClick: return .maximize
        case .rightClick: return .center
        case .scrollUp: return .rollUp
        case .scrollDown: return .fill
        }
    }
}
