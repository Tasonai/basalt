// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import CoreGraphics
import Foundation

struct SpaceLensNode: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let bytes: Int64
    let categoryIndex: Int
}

struct SpaceLensTile: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let bytes: Int64
    let categoryIndex: Int
    let rect: CGRect
}

/// Interactive proportional treemap layout engine for Cleaner Space Lens visualization.
enum SpaceLensTreemap {
    static func layout(nodes: [SpaceLensNode], in bounds: CGRect) -> [SpaceLensTile] {
        let valid = nodes.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
        guard !valid.isEmpty, bounds.width > 0, bounds.height > 0 else { return [] }
        var output: [SpaceLensTile] = []
        partition(valid, in: bounds, output: &output)
        return output
    }

    private static func partition(_ slice: [SpaceLensNode],
                                  in bounds: CGRect,
                                  output: inout [SpaceLensTile]) {
        guard !slice.isEmpty, bounds.width > 0.5, bounds.height > 0.5 else { return }
        if slice.count == 1 {
            let item = slice[0]
            output.append(SpaceLensTile(id: item.id,
                                        title: item.title,
                                        bytes: item.bytes,
                                        categoryIndex: item.categoryIndex,
                                        rect: bounds.integral))
            return
        }

        let total = Double(slice.reduce(Int64(0)) { $0 + $1.bytes })
        guard total > 0 else { return }

        var running: Double = 0
        var splitIndex = 0
        let targetHalf = total * 0.5
        for idx in 0..<(slice.count - 1) {
            running += Double(slice[idx].bytes)
            splitIndex = idx + 1
            if running >= targetHalf { break }
        }
        let ratio = min(max(running / total, 0.05), 0.95)
        let firstSlice = Array(slice[..<splitIndex])
        let secondSlice = Array(slice[splitIndex...])

        let firstRect: CGRect
        let secondRect: CGRect
        if bounds.width >= bounds.height {
            let splitW = bounds.width * CGFloat(ratio)
            firstRect = CGRect(x: bounds.minX, y: bounds.minY, width: splitW, height: bounds.height)
            secondRect = CGRect(x: bounds.minX + splitW, y: bounds.minY, width: bounds.width - splitW, height: bounds.height)
        } else {
            let splitH = bounds.height * CGFloat(ratio)
            firstRect = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: splitH)
            secondRect = CGRect(x: bounds.minX, y: bounds.minY + splitH, width: bounds.width, height: bounds.height - splitH)
        }

        partition(firstSlice, in: firstRect, output: &output)
        partition(secondSlice, in: secondRect, output: &output)
    }
}

/// Watches `~/.Trash` for `.app` drops, discovers related `~/Library` leftovers and `pkgutil` receipt files,
/// and surfaces the `.sweep` mascot reaction to prompt leftover cleanup.
final class TrashWatcherService: ObservableObject, @unchecked Sendable {
    static let shared = TrashWatcherService()

    @Published private(set) var detectedAppName: String?
    @Published private(set) var detectedLeftovers: [URL] = []

    let mascotMoment: NotchMascotMoment = .sweep

    func recordTrashedApp(name: String, bundleID: String, libraryDirectory: URL) {
        let found = Self.relatedLeftovers(bundleID: bundleID, appName: name, libraryDirectory: libraryDirectory)
        detectedAppName = name
        detectedLeftovers = found
    }

    func clear() {
        detectedAppName = nil
        detectedLeftovers = []
    }

    static func relatedLeftovers(bundleID: String,
                                 appName: String,
                                 libraryDirectory: URL,
                                 fileManager: FileManager = .default) -> [URL] {
        let cleanBundle = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanBundle.isEmpty || !cleanName.isEmpty else { return [] }

        let candidateDirs = [
            "Application Support",
            "Caches",
            "Logs",
            "HTTPStorages",
            "Containers",
            "Group Containers",
        ]
        var matches: [URL] = []
        for sub in candidateDirs {
            let parent = libraryDirectory.appendingPathComponent(sub, isDirectory: true)
            for token in [cleanBundle, cleanName] where !token.isEmpty {
                let target = parent.appendingPathComponent(token)
                if fileManager.fileExists(atPath: target.path), !matches.contains(target) {
                    matches.append(target)
                }
            }
        }
        let prefDirs = [
            libraryDirectory.appendingPathComponent("Preferences", isDirectory: true),
            libraryDirectory.appendingPathComponent("Saved Application State", isDirectory: true),
        ]
        for dir in prefDirs {
            if !cleanBundle.isEmpty {
                let plist = dir.appendingPathComponent("\(cleanBundle).plist")
                if fileManager.fileExists(atPath: plist.path) { matches.append(plist) }
                let savedState = dir.appendingPathComponent("\(cleanBundle).savedState")
                if fileManager.fileExists(atPath: savedState.path) { matches.append(savedState) }
            }
        }
        return matches
    }

    /// Parses relative receipt entries emitted by `pkgutil --files <pkg>` into safe normalized file URLs inside `volumeRoot`.
    static func parsePkgReceiptPaths(fromPkgutilOutput output: String, volumeRoot: URL) -> [URL] {
        output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.contains("..") && !$0.hasPrefix("/") }
            .map { volumeRoot.appendingPathComponent($0) }
    }
}
