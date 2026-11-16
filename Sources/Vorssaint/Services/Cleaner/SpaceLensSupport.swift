// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import CoreGraphics
import Darwin
import Foundation

struct SpaceLensNode: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let bytes: Int64
    let categoryIndex: Int
    let url: URL?
    let isDirectory: Bool

    init(id: String,
         title: String,
         bytes: Int64,
         categoryIndex: Int,
         url: URL? = nil,
         isDirectory: Bool = false) {
        self.id = id
        self.title = title
        self.bytes = bytes
        self.categoryIndex = categoryIndex
        self.url = url
        self.isDirectory = isDirectory
    }
}

struct SpaceLensTile: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let bytes: Int64
    let categoryIndex: Int
    let rect: CGRect
    let url: URL?
    let isDirectory: Bool

    init(id: String,
         title: String,
         bytes: Int64,
         categoryIndex: Int,
         rect: CGRect,
         url: URL? = nil,
         isDirectory: Bool = false) {
        self.id = id
        self.title = title
        self.bytes = bytes
        self.categoryIndex = categoryIndex
        self.rect = rect
        self.url = url
        self.isDirectory = isDirectory
    }
}

struct SpaceLensDirectoryEntry: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL
    let name: String
    let bytes: Int64
    let isDirectory: Bool
    let categoryIndex: Int
}

enum SpaceLensDirectoryScanner {
    static func scanEntries(at directoryURL: URL,
                            maxEntries: Int = 24,
                            maxFilesPerSubtree: Int = 4000,
                            fileManager: FileManager = .default) -> [SpaceLensDirectoryEntry] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isPackageKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
        ]
        guard let children = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var entries: [SpaceLensDirectoryEntry] = []
        entries.reserveCapacity(children.count)
        for (index, childURL) in children.enumerated() {
            let values = try? childURL.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true { continue }
            let isDir = (values?.isDirectory == true) && (values?.isPackage != true)
            let bytes: Int64
            if values?.isDirectory == true {
                bytes = directoryByteSize(at: childURL, maxFiles: maxFilesPerSubtree, fileManager: fileManager)
            } else {
                bytes = fileByteSize(from: values)
            }
            guard bytes > 0 else { continue }
            entries.append(SpaceLensDirectoryEntry(
                id: childURL.path,
                url: childURL,
                name: childURL.lastPathComponent,
                bytes: bytes,
                isDirectory: isDir,
                categoryIndex: index
            ))
        }
        return Array(entries.sorted { $0.bytes > $1.bytes }.prefix(max(1, maxEntries)))
    }

    static func scanChildren(at directoryURL: URL, maxEntries: Int = 24) -> [SpaceLensNode] {
        scanEntries(at: directoryURL, maxEntries: maxEntries).map { entry in
            SpaceLensNode(
                id: entry.id,
                title: entry.name,
                bytes: entry.bytes,
                categoryIndex: entry.categoryIndex,
                url: entry.url,
                isDirectory: entry.isDirectory
            )
        }
    }

    private static func directoryByteSize(at directoryURL: URL,
                                          maxFiles: Int,
                                          fileManager: FileManager) -> Int64 {
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
        ]
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }
        var total: Int64 = 0
        var scannedFiles = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values?.isRegularFile == true else { continue }
            total += fileByteSize(from: values)
            scannedFiles += 1
            if scannedFiles >= maxFiles { break }
        }
        return total
    }

    private static func fileByteSize(from values: URLResourceValues?) -> Int64 {
        if let fileSize = values?.fileSize, fileSize > 0 {
            return Int64(fileSize)
        }
        return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
    }
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
                                        rect: bounds.integral,
                                        url: item.url,
                                        isDirectory: item.isDirectory))
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

    private let watchQueue = DispatchQueue(label: "com.vorssaint.utils.trash-watcher", qos: .utility)
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var knownTrashAppPaths: Set<String> = []
    private let stateLock = NSLock()

    func startWatchingTrash() {
        stopWatchingTrash()
        let trashURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
        guard FileManager.default.fileExists(atPath: trashURL.path) else { return }

        let initialApps = Set(Self.trashedAppURLs(in: trashURL).map(\.path))
        stateLock.lock()
        knownTrashAppPaths = initialApps
        stateLock.unlock()

        let fd = open(trashURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: watchQueue
        )
        source.setEventHandler { [weak self] in
            self?.handleTrashEvent(in: trashURL)
        }
        source.setCancelHandler {
            close(fd)
        }
        dispatchSource = source
        source.resume()
    }

    func stopWatchingTrash() {
        dispatchSource?.cancel()
        dispatchSource = nil
    }

    func recordTrashedApp(name: String, bundleID: String, libraryDirectory: URL) {
        let found = Self.relatedLeftovers(bundleID: bundleID, appName: name, libraryDirectory: libraryDirectory)
        detectedAppName = name
        detectedLeftovers = found
    }

    @discardableResult
    func removeDetectedLeftovers(fileManager: FileManager = .default) -> Int {
        let targets = detectedLeftovers
        guard !targets.isEmpty else {
            clear()
            return 0
        }
        var removed = 0
        for url in targets where fileManager.fileExists(atPath: url.path) {
            if (try? fileManager.trashItem(at: url, resultingItemURL: nil)) != nil {
                removed += 1
            } else if (try? fileManager.removeItem(at: url)) != nil {
                removed += 1
            }
        }
        clear()
        return removed
    }

    func clear() {
        detectedAppName = nil
        detectedLeftovers = []
    }

    private func handleTrashEvent(in trashURL: URL) {
        let currentApps = Self.trashedAppURLs(in: trashURL)
        let currentPaths = Set(currentApps.map(\.path))

        stateLock.lock()
        let added = currentApps.filter { !knownTrashAppPaths.contains($0.path) }
        knownTrashAppPaths = currentPaths
        stateLock.unlock()

        guard let newestApp = added.last else { return }
        let metadata = Self.readAppBundleMetadata(at: newestApp)
        let libraryDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        DispatchQueue.main.async { [weak self] in
            self?.recordTrashedApp(name: metadata.name, bundleID: metadata.bundleID, libraryDirectory: libraryDir)
        }
    }

    private static func trashedAppURLs(in trashURL: URL, fileManager: FileManager = .default) -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: trashURL,
            includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants]
        ) else {
            return []
        }
        return contents.filter { $0.pathExtension.lowercased() == "app" }
    }

    private static func readAppBundleMetadata(at appURL: URL) -> (name: String, bundleID: String) {
        let fallbackName = appURL.deletingPathExtension().lastPathComponent
        let plistCandidates = [
            appURL.appendingPathComponent("Contents/Info.plist"),
            appURL.appendingPathComponent("Info.plist"),
        ]
        for plistURL in plistCandidates {
            guard let data = try? Data(contentsOf: plistURL),
                  let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                continue
            }
            let bundleID = (dict["CFBundleIdentifier"] as? String) ?? ""
            let displayName = (dict["CFBundleDisplayName"] as? String)
                ?? (dict["CFBundleName"] as? String)
                ?? fallbackName
            return (displayName, bundleID)
        }
        return (fallbackName, "")
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
