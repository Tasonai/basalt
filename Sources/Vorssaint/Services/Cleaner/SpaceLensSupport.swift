// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import CoreGraphics
import CryptoKit
import Darwin
import Foundation
import UniformTypeIdentifiers

struct SpaceLensNode: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let bytes: Int64
    let categoryIndex: Int
    let url: URL?
    let isDirectory: Bool
    let path: String
    let children: [SpaceLensNode]

    var name: String { title }

    init(id: String,
         title: String,
         bytes: Int64,
         categoryIndex: Int,
         url: URL? = nil,
         isDirectory: Bool = false,
         children: [SpaceLensNode] = []) {
        self.id = id
        self.title = title
        self.bytes = bytes
        self.categoryIndex = categoryIndex
        self.url = url
        self.isDirectory = isDirectory
        self.path = url?.path ?? ""
        self.children = children
    }

    init(id: String,
         name: String,
         path: String,
         bytes: Int64,
         isDirectory: Bool,
         children: [SpaceLensNode] = [],
         categoryIndex: Int = 0) {
        self.id = id
        self.title = name
        self.bytes = bytes
        self.categoryIndex = categoryIndex
        self.url = path.isEmpty ? nil : URL(fileURLWithPath: path)
        self.isDirectory = isDirectory
        self.path = path
        self.children = children
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
        let leftovers = Self.relatedLeftovers(bundleID: metadata.bundleID,
                                              appName: metadata.name,
                                              libraryDirectory: libraryDir)
        DispatchQueue.main.async { [weak self] in
            self?.detectedAppName = metadata.name
            self?.detectedLeftovers = leftovers
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

// MARK: - Wave 8: Deep Space Lens Engine, Sunburst Geometry, Collect Basket, Startup Agents & Duplicates

private final class SpaceLensInodeTracker: @unchecked Sendable {
    private struct InodeKey: Hashable {
        let dev: Int32
        let ino: UInt64
    }

    private let lock = NSLock()
    private var seen: Set<InodeKey> = []

    func shouldCount(url: URL, linkCount: Int?) -> Bool {
        guard let linkCount, linkCount > 1 else { return true }
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return true }
        let key = InodeKey(dev: st.st_dev, ino: UInt64(st.st_ino))
        lock.lock()
        defer { lock.unlock() }
        return seen.insert(key).inserted
    }
}

/// Unbounded multi-threaded `TaskGroup` disk scanner that skips symlinks/mount-points,
/// deduplicates hardlinks, honors `Task.isCancelled`, and caches hierarchical `SpaceLensNode`
/// trees for instant drill-down across full-disk scans.
final class SpaceLensDeepScanner: @unchecked Sendable {
    static let shared = SpaceLensDeepScanner()

    private static let maxCachedTreeDepth = 6
    private static let maxChildrenPerNode = 1000
    private static let skippedSystemPaths: Set<String> = [
        "/dev",
        "/home",
        "/net",
        "/System/Volumes",
    ]
    private static let resourceKeys: [URLResourceKey] = [
        .isRegularFileKey,
        .isDirectoryKey,
        .isPackageKey,
        .isSymbolicLinkKey,
        .isVolumeKey,
        .fileSizeKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .linkCountKey,
    ]

    private let cacheLock = NSLock()
    private var cachedTrees: [String: SpaceLensNode] = [:]

    func cachedTree(for directoryURL: URL) -> SpaceLensNode? {
        let targetPath = Self.canonicalPath(directoryURL.path)
        cacheLock.lock()
        let snapshot = cachedTrees
        cacheLock.unlock()

        if let exact = snapshot[targetPath] {
            return exact
        }
        for (_, root) in snapshot {
            if let found = findMaterializedDescendant(in: root, canonicalTargetPath: targetPath, currentDepth: 0) {
                return found
            }
        }
        return nil
    }

    func invalidateCache(for directoryURL: URL? = nil) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let directoryURL else {
            cachedTrees.removeAll()
            return
        }
        let targetPath = Self.canonicalPath(directoryURL.path)
        cachedTrees = cachedTrees.filter { cachedPath, _ in
            !(cachedPath == targetPath
              || cachedPath.hasPrefix(targetPath + "/")
              || targetPath.hasPrefix(cachedPath + "/"))
        }
    }

    static func scan(at rootURL: URL,
                     includeHidden: Bool = true,
                     useCache: Bool = true) async -> SpaceLensNode {
        await shared.scanTree(at: rootURL, includeHidden: includeHidden, useCache: useCache)
    }

    func scanTree(at rootURL: URL,
                  includeHidden: Bool = true,
                  useCache: Bool = true) async -> SpaceLensNode {
        let standardizedURL = rootURL.standardizedFileURL
        if useCache, let cached = cachedTree(for: standardizedURL) {
            return cached
        }
        guard !Task.isCancelled else {
            return SpaceLensNode(
                id: standardizedURL.path,
                name: standardizedURL.lastPathComponent.isEmpty ? standardizedURL.path : standardizedURL.lastPathComponent,
                path: standardizedURL.path,
                bytes: 0,
                isDirectory: true,
                children: []
            )
        }

        let fileManager = FileManager.default
        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        let keySet = Set(Self.resourceKeys)
        let topEntries = (try? fileManager.contentsOfDirectory(
            at: standardizedURL,
            includingPropertiesForKeys: Self.resourceKeys,
            options: options
        )) ?? []

        let inodeTracker = SpaceLensInodeTracker()
        var directNodes: [SpaceLensNode] = []
        var directoryWork: [(index: Int, url: URL, isPackage: Bool)] = []

        for (index, childURL) in topEntries.enumerated() {
            if Task.isCancelled { break }
            let values = try? childURL.resourceValues(forKeys: keySet)
            if values?.isSymbolicLink == true { continue }
            if Self.shouldSkipSystemMount(childURL, values: values) { continue }

            if values?.isDirectory == true {
                directoryWork.append((index, childURL, values?.isPackage == true))
            } else {
                let bytes = Self.regularFileBytes(from: values, url: childURL, inodeTracker: inodeTracker)
                guard bytes > 0 else { continue }
                directNodes.append(SpaceLensNode(
                    id: childURL.path,
                    name: childURL.lastPathComponent,
                    path: childURL.path,
                    bytes: bytes,
                    isDirectory: false,
                    children: [],
                    categoryIndex: index
                ))
            }
        }

        let maxConcurrent = max(4, min(12, ProcessInfo.processInfo.activeProcessorCount * 2))
        var scannedDirectories: [SpaceLensNode] = []
        scannedDirectories.reserveCapacity(directoryWork.count)

        await withTaskGroup(of: SpaceLensNode?.self) { group in
            var nextWorkIndex = 0
            let initialCount = min(maxConcurrent, directoryWork.count)
            while nextWorkIndex < initialCount {
                let work = directoryWork[nextWorkIndex]
                nextWorkIndex += 1
                group.addTask {
                    Self.scanChildDirectory(
                        at: work.url,
                        isPackage: work.isPackage,
                        categoryIndex: work.index,
                        depth: 1,
                        includeHidden: includeHidden,
                        inodeTracker: inodeTracker
                    )
                }
            }

            while let completed = await group.next() {
                if let completed {
                    scannedDirectories.append(completed)
                }
                if !Task.isCancelled, nextWorkIndex < directoryWork.count {
                    let work = directoryWork[nextWorkIndex]
                    nextWorkIndex += 1
                    group.addTask {
                        Self.scanChildDirectory(
                            at: work.url,
                            isPackage: work.isPackage,
                            categoryIndex: work.index,
                            depth: 1,
                            includeHidden: includeHidden,
                            inodeTracker: inodeTracker
                        )
                    }
                }
            }
        }

        let allChildren = Self.boundedSortedChildren(directNodes + scannedDirectories, parentPath: standardizedURL.path)
        let totalBytes = allChildren.reduce(Int64(0)) { $0 + $1.bytes }
        let rootName = standardizedURL.lastPathComponent.isEmpty ? standardizedURL.path : standardizedURL.lastPathComponent
        let rootNode = SpaceLensNode(
            id: standardizedURL.path,
            name: rootName,
            path: standardizedURL.path,
            bytes: totalBytes,
            isDirectory: true,
            children: allChildren
        )

        if !Task.isCancelled {
            storeCachedTree(rootNode, for: Self.canonicalPath(standardizedURL.path))
        }
        return rootNode
    }

    private static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func storeCachedTree(_ rootNode: SpaceLensNode, for path: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cachedTrees[path] = rootNode
    }

    private func findMaterializedDescendant(in node: SpaceLensNode,
                                            canonicalTargetPath: String,
                                            currentDepth: Int) -> SpaceLensNode? {
        let nodeCanonical = Self.canonicalPath(node.path)
        if nodeCanonical == canonicalTargetPath, node.isDirectory, currentDepth < Self.maxCachedTreeDepth - 1 {
            return node
        }
        let prefix = nodeCanonical == "/" ? "/" : nodeCanonical + "/"
        guard canonicalTargetPath.hasPrefix(prefix),
              currentDepth < Self.maxCachedTreeDepth - 1 else {
            return nil
        }
        for child in node.children where child.isDirectory {
            if let match = findMaterializedDescendant(
                in: child,
                canonicalTargetPath: canonicalTargetPath,
                currentDepth: currentDepth + 1
            ) {
                return match
            }
        }
        return nil
    }

    private static func scanChildDirectory(at directoryURL: URL,
                                           isPackage: Bool,
                                           categoryIndex: Int,
                                           depth: Int,
                                           includeHidden: Bool,
                                           inodeTracker: SpaceLensInodeTracker) -> SpaceLensNode? {
        guard !Task.isCancelled else { return nil }
        if isPackage || depth >= maxCachedTreeDepth {
            let bytes = unboundedDirectoryBytes(
                at: directoryURL,
                includeHidden: includeHidden,
                inodeTracker: inodeTracker
            )
            guard bytes > 0 else { return nil }
            return SpaceLensNode(
                id: directoryURL.path,
                name: directoryURL.lastPathComponent,
                path: directoryURL.path,
                bytes: bytes,
                isDirectory: !isPackage,
                children: [],
                categoryIndex: categoryIndex
            )
        }

        let fileManager = FileManager.default
        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        let keySet = Set(resourceKeys)
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: resourceKeys,
            options: options
        ) else {
            return nil
        }

        var children: [SpaceLensNode] = []
        children.reserveCapacity(entries.count)
        for (idx, childURL) in entries.enumerated() {
            if Task.isCancelled { return nil }
            let values = try? childURL.resourceValues(forKeys: keySet)
            if values?.isSymbolicLink == true { continue }
            if shouldSkipSystemMount(childURL, values: values) { continue }

            if values?.isDirectory == true {
                if let subNode = scanChildDirectory(
                    at: childURL,
                    isPackage: values?.isPackage == true,
                    categoryIndex: idx,
                    depth: depth + 1,
                    includeHidden: includeHidden,
                    inodeTracker: inodeTracker
                ) {
                    children.append(subNode)
                }
            } else {
                let bytes = regularFileBytes(from: values, url: childURL, inodeTracker: inodeTracker)
                guard bytes > 0 else { continue }
                children.append(SpaceLensNode(
                    id: childURL.path,
                    name: childURL.lastPathComponent,
                    path: childURL.path,
                    bytes: bytes,
                    isDirectory: false,
                    children: [],
                    categoryIndex: idx
                ))
            }
        }

        let bounded = boundedSortedChildren(children, parentPath: directoryURL.path)
        let totalBytes = bounded.reduce(Int64(0)) { $0 + $1.bytes }
        guard totalBytes > 0 else { return nil }
        return SpaceLensNode(
            id: directoryURL.path,
            name: directoryURL.lastPathComponent,
            path: directoryURL.path,
            bytes: totalBytes,
            isDirectory: true,
            children: bounded,
            categoryIndex: categoryIndex
        )
    }

    private static func unboundedDirectoryBytes(at directoryURL: URL,
                                                includeHidden: Bool,
                                                inodeTracker: SpaceLensInodeTracker) -> Int64 {
        let keySet = Set(resourceKeys)
        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: resourceKeys,
            options: options,
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if Task.isCancelled { break }
            let values = try? fileURL.resourceValues(forKeys: keySet)
            if values?.isSymbolicLink == true || shouldSkipSystemMount(fileURL, values: values) {
                enumerator.skipDescendants()
                continue
            }
            guard values?.isDirectory != true else { continue }
            total += regularFileBytes(from: values, url: fileURL, inodeTracker: inodeTracker)
        }
        return total
    }

    private static func boundedSortedChildren(_ nodes: [SpaceLensNode], parentPath: String) -> [SpaceLensNode] {
        let positive = nodes.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
        guard positive.count > maxChildrenPerNode else { return positive }
        let kept = Array(positive.prefix(maxChildrenPerNode - 1))
        let overflowBytes = positive.dropFirst(maxChildrenPerNode - 1).reduce(Int64(0)) { $0 + $1.bytes }
        let overflowNode = SpaceLensNode(
            id: "\(parentPath)#other",
            name: "Other",
            path: parentPath,
            bytes: overflowBytes,
            isDirectory: false,
            children: [],
            categoryIndex: kept.count
        )
        return kept + [overflowNode]
    }

    private static func shouldSkipSystemMount(_ url: URL, values: URLResourceValues?) -> Bool {
        if skippedSystemPaths.contains(url.path) { return true }
        if values?.isVolume == true { return true }
        return false
    }

    private static func regularFileBytes(from values: URLResourceValues?,
                                         url: URL,
                                         inodeTracker: SpaceLensInodeTracker) -> Int64 {
        let rawBytes: Int64
        if let allocated = values?.totalFileAllocatedSize, allocated > 0 {
            rawBytes = Int64(allocated)
        } else if let fileSize = values?.fileSize, fileSize > 0 {
            rawBytes = Int64(fileSize)
        } else {
            rawBytes = Int64(values?.fileAllocatedSize ?? 0)
        }
        guard rawBytes > 0 else { return 0 }
        guard inodeTracker.shouldCount(url: url, linkCount: values?.linkCount) else { return 0 }
        return rawBytes
    }
}

struct SpaceLensSunburstArc: Identifiable, Equatable, Sendable {
    let id: String
    let nodeID: String
    let name: String
    let path: String
    let bytes: Int64
    let ringDepth: Int
    let startAngle: Double
    let endAngle: Double
    let isOtherGroup: Bool
}

enum SpaceLensSunburst {
    private static let minimumVisibleShare = 0.015
    private static let collapseThresholdCount = 12

    static func buildArcs(root: SpaceLensNode, maxDepth: Int = 5) -> [SpaceLensSunburstArc] {
        let depthCap = min(5, max(0, maxDepth))
        guard depthCap >= 1, root.bytes > 0 else { return [] }
        var output: [SpaceLensSunburstArc] = []
        appendArcs(
            parent: root,
            depth: 1,
            maxDepth: depthCap,
            startAngle: 0.0,
            endAngle: 2.0 * Double.pi,
            into: &output
        )
        return output
    }

    private static func appendArcs(parent: SpaceLensNode,
                                   depth: Int,
                                   maxDepth: Int,
                                   startAngle: Double,
                                   endAngle: Double,
                                   into output: inout [SpaceLensSunburstArc]) {
        guard depth <= maxDepth else { return }
        let positive = parent.children.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
        guard !positive.isEmpty else { return }

        let totalChildBytes = positive.reduce(Int64(0)) { $0 + $1.bytes }
        guard totalChildBytes > 0 else { return }
        let parentSpan = endAngle - startAngle
        guard parentSpan > 1e-9 else { return }

        var major: [SpaceLensNode] = []
        var minor: [SpaceLensNode] = []
        if positive.count > collapseThresholdCount {
            for child in positive {
                let share = Double(child.bytes) / Double(totalChildBytes)
                if share >= minimumVisibleShare {
                    major.append(child)
                } else {
                    minor.append(child)
                }
            }
            if major.isEmpty {
                major = Array(positive.prefix(collapseThresholdCount))
                minor = Array(positive.dropFirst(collapseThresholdCount))
            }
        } else {
            major = positive
        }

        var cursor = startAngle
        for (index, child) in major.enumerated() {
            let isLast = (index == major.count - 1) && minor.isEmpty
            let share = Double(child.bytes) / Double(totalChildBytes)
            let arcEnd = isLast ? endAngle : min(endAngle, cursor + parentSpan * share)
            if arcEnd > cursor + 1e-9 {
                let arc = SpaceLensSunburstArc(
                    id: "\(depth)-\(index)-\(child.id)",
                    nodeID: child.id,
                    name: child.name,
                    path: child.path,
                    bytes: child.bytes,
                    ringDepth: depth,
                    startAngle: cursor,
                    endAngle: arcEnd,
                    isOtherGroup: false
                )
                output.append(arc)
                if depth < maxDepth, !child.children.isEmpty {
                    appendArcs(
                        parent: child,
                        depth: depth + 1,
                        maxDepth: maxDepth,
                        startAngle: cursor,
                        endAngle: arcEnd,
                        into: &output
                    )
                }
            }
            cursor = arcEnd
        }

        if !minor.isEmpty, endAngle > cursor + 1e-9 {
            let otherBytes = minor.reduce(Int64(0)) { $0 + $1.bytes }
            if otherBytes > 0 {
                output.append(SpaceLensSunburstArc(
                    id: "\(depth)-other-\(parent.id)",
                    nodeID: "\(parent.id)#other",
                    name: "Other",
                    path: parent.path,
                    bytes: otherBytes,
                    ringDepth: depth,
                    startAngle: cursor,
                    endAngle: endAngle,
                    isOtherGroup: true
                ))
            }
        }
    }
}

struct SpaceLensCollectItem: Identifiable, Equatable, Sendable {
    let id: String
    let path: String
    let sizeBytes: Int64
    let name: String
}

struct SpaceLensCollectBasket: Equatable, Sendable {
    private(set) var items: [SpaceLensCollectItem] = []

    var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.sizeBytes }
    }

    mutating func add(path: String, sizeBytes: Int64, name: String) {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard !normalized.isEmpty else { return }
        guard !items.contains(where: { URL(fileURLWithPath: $0.path).standardizedFileURL.path == normalized }) else {
            return
        }
        let resolvedName = name.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : name
        items.append(SpaceLensCollectItem(
            id: normalized,
            path: path,
            sizeBytes: max(0, sizeBytes),
            name: resolvedName
        ))
    }

    mutating func remove(id: String) {
        items.removeAll { $0.id == id }
    }

    mutating func clear() {
        items.removeAll()
    }

    @discardableResult
    mutating func trashAll(fileManager: FileManager = .default) -> Int {
        var trashedCount = 0
        var remaining: [SpaceLensCollectItem] = []
        for item in items {
            let url = URL(fileURLWithPath: item.path)
            if fileManager.fileExists(atPath: url.path),
               (try? fileManager.trashItem(at: url, resultingItemURL: nil)) != nil {
                trashedCount += 1
            } else {
                remaining.append(item)
            }
        }
        items = remaining
        return trashedCount
    }
}

enum StartupAgentDomain: String, CaseIterable, Codable, Sendable {
    case userAgent
    case globalAgent
    case systemDaemon
}

struct StartupAgentEntry: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let label: String
    let program: String
    let runAtLoad: Bool
    let keepAlive: Bool
    let domain: StartupAgentDomain
    let plistURL: URL
    var isEnabled: Bool
}

enum StartupAgentInspector {
    static func parsePlistData(_ data: Data,
                               domain: StartupAgentDomain,
                               plistURL: URL) -> StartupAgentEntry? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = plist as? [String: Any] else {
            return nil
        }

        let rawLabel = (dict["Label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let directProgram = (dict["Program"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstArgument = ((dict["ProgramArguments"] as? [Any])?.first as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let program = (directProgram?.isEmpty == false ? directProgram : firstArgument) ?? ""
        let label = (rawLabel?.isEmpty == false ? rawLabel : nil)
            ?? (program.isEmpty ? nil : plistURL.deletingPathExtension().lastPathComponent)
        guard let resolvedLabel = label, !resolvedLabel.isEmpty else { return nil }

        let runAtLoad = (dict["RunAtLoad"] as? Bool) ?? false
        let keepAlive: Bool
        if let boolVal = dict["KeepAlive"] as? Bool {
            keepAlive = boolVal
        } else if let dictVal = dict["KeepAlive"] as? [String: Any] {
            keepAlive = !dictVal.isEmpty
        } else {
            keepAlive = false
        }
        let disabled = (dict["Disabled"] as? Bool) ?? false

        return StartupAgentEntry(
            id: "\(domain.rawValue):\(plistURL.path)",
            label: resolvedLabel,
            program: program,
            runAtLoad: runAtLoad,
            keepAlive: keepAlive,
            domain: domain,
            plistURL: plistURL,
            isEnabled: !disabled
        )
    }

    static func scanSystemAgents(fileManager: FileManager = .default) -> [StartupAgentEntry] {
        let roots: [(StartupAgentDomain, URL)] = [
            (.userAgent, fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents", isDirectory: true)),
            (.globalAgent, URL(fileURLWithPath: "/Library/LaunchAgents", isDirectory: true)),
            (.systemDaemon, URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true)),
        ]

        var entries: [StartupAgentEntry] = []
        for (domain, directory) in roots {
            guard let files = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            ) else {
                continue
            }
            for fileURL in files where fileURL.pathExtension.lowercased() == "plist" {
                guard let data = try? Data(contentsOf: fileURL),
                      let entry = parsePlistData(data, domain: domain, plistURL: fileURL) else {
                    continue
                }
                entries.append(entry)
            }
        }

        return entries.sorted { lhs, rhs in
            if lhs.domain != rhs.domain {
                return domainSortOrder(lhs.domain) < domainSortOrder(rhs.domain)
            }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    @discardableResult
    static func setUserAgentEnabled(_ entry: StartupAgentEntry, enabled: Bool) -> Bool {
        guard entry.domain == .userAgent else { return false }
        let userAgentsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .standardizedFileURL.path
        let parentDir = entry.plistURL.standardizedFileURL.deletingLastPathComponent().path
        guard parentDir == userAgentsDir else { return false }

        guard let data = try? Data(contentsOf: entry.plistURL),
              var dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return false
        }
        dict["Disabled"] = !enabled
        guard let updatedData = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0) else {
            return false
        }
        do {
            try updatedData.write(to: entry.plistURL, options: .atomic)
        } catch {
            return false
        }

        if !entry.label.isEmpty {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = [enabled ? "enable" : "disable", "gui/\(getuid())/\(entry.label)"]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
        return true
    }

    private static func domainSortOrder(_ domain: StartupAgentDomain) -> Int {
        switch domain {
        case .userAgent: return 0
        case .globalAgent: return 1
        case .systemDaemon: return 2
        }
    }
}

struct DuplicateFileGroup: Identifiable, Equatable, Sendable {
    let id: String
    let sha256Hex: String
    let byteSize: Int64
    let urls: [URL]
}

enum FastDuplicateScanner {
    private static let partialWindowBytes = 4096
    private static let fullStreamChunkBytes = 65_536

    private final class CancelBox: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }
    }

    static func scanSync(directoryURL: URL, minBytes: Int64 = 1024) -> [DuplicateFileGroup] {
        scanInternal(directoryURL: directoryURL, minBytes: minBytes, isCancelled: { false })
    }

    static func scan(directoryURL: URL, minBytes: Int64 = 1024) async -> [DuplicateFileGroup] {
        let cancelBox = CancelBox()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let results = scanInternal(
                        directoryURL: directoryURL,
                        minBytes: minBytes,
                        isCancelled: { cancelBox.isCancelled }
                    )
                    continuation.resume(returning: results)
                }
            }
        } onCancel: {
            cancelBox.cancel()
        }
    }

    private static func scanInternal(directoryURL: URL,
                                     minBytes: Int64,
                                     isCancelled: () -> Bool) -> [DuplicateFileGroup] {
        let threshold = max(1, minBytes)
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .linkCountKey,
        ]
        let keySet = Set(keys)
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        // Stage 1: Group regular non-symlink files >= minBytes by exact byte size.
        let inodeTracker = SpaceLensInodeTracker()
        var sizeBuckets: [Int64: [URL]] = [:]
        for case let fileURL as URL in enumerator {
            if isCancelled() { return [] }
            let values = try? fileURL.resourceValues(forKeys: keySet)
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values?.isRegularFile == true,
                  let rawSize = values?.fileSize else {
                continue
            }
            let size = Int64(rawSize)
            guard size >= threshold else { continue }
            guard inodeTracker.shouldCount(url: fileURL, linkCount: values?.linkCount) else { continue }
            sizeBuckets[size, default: []].append(fileURL)
        }

        var groups: [DuplicateFileGroup] = []
        for (byteSize, candidates) in sizeBuckets where candidates.count >= 2 {
            if isCancelled() { return [] }

            // Stage 2: Partial SHA-256 over head 4096 bytes + tail 4096 bytes + size.
            var partialBuckets: [String: [URL]] = [:]
            for url in candidates {
                if isCancelled() { return [] }
                guard let partialHex = partialSHA256Hex(for: url, byteSize: byteSize) else { continue }
                partialBuckets[partialHex, default: []].append(url)
            }

            // Stage 3: Full streaming 64 KB chunk SHA-256 for partial collisions >= 2.
            for (_, partialCollisions) in partialBuckets where partialCollisions.count >= 2 {
                if isCancelled() { return [] }
                var fullBuckets: [String: [URL]] = [:]
                for url in partialCollisions {
                    if isCancelled() { return [] }
                    guard let fullHex = fullSHA256Hex(for: url, isCancelled: isCancelled) else { continue }
                    fullBuckets[fullHex, default: []].append(url)
                }

                for (sha256Hex, duplicates) in fullBuckets where duplicates.count >= 2 {
                    let sortedURLs = duplicates.sorted { $0.path < $1.path }
                    groups.append(DuplicateFileGroup(
                        id: "\(byteSize)-\(sha256Hex)",
                        sha256Hex: sha256Hex,
                        byteSize: byteSize,
                        urls: sortedURLs
                    ))
                }
            }
        }

        return groups.sorted { lhs, rhs in
            let wastedLHS = lhs.byteSize * Int64(max(0, lhs.urls.count - 1))
            let wastedRHS = rhs.byteSize * Int64(max(0, rhs.urls.count - 1))
            if wastedLHS != wastedRHS { return wastedLHS > wastedRHS }
            if lhs.byteSize != rhs.byteSize { return lhs.byteSize > rhs.byteSize }
            return lhs.sha256Hex < rhs.sha256Hex
        }
    }

    private static func partialSHA256Hex(for url: URL, byteSize: Int64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        do {
            let head = try handle.read(upToCount: partialWindowBytes) ?? Data()
            var hasher = SHA256()
            var sizeLE = byteSize.littleEndian
            withUnsafeBytes(of: &sizeLE) { hasher.update(bufferPointer: $0) }
            hasher.update(data: head)

            if byteSize > Int64(partialWindowBytes) {
                let tailOffset = UInt64(max(0, byteSize - Int64(partialWindowBytes)))
                try handle.seek(toOffset: tailOffset)
                if let tail = try handle.read(upToCount: partialWindowBytes) {
                    hasher.update(data: tail)
                }
            }
            return digestHex(hasher.finalize())
        } catch {
            return nil
        }
    }

    private static func fullSHA256Hex(for url: URL, isCancelled: () -> Bool) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        do {
            while true {
                if isCancelled() { return nil }
                guard let chunk = try handle.read(upToCount: fullStreamChunkBytes), !chunk.isEmpty else {
                    break
                }
                hasher.update(data: chunk)
            }
            return digestHex(hasher.finalize())
        } catch {
            return nil
        }
    }

    private static func digestHex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
