// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation
import PDFKit

enum Wave4OverhaulContract {
    static func run(_ suite: TestSuite) {
        testDDCAndAmbientLightSyncAndVirtualHiDPI(suite)
        testWorkspacesCustomGridAndTitlebarGestures(suite)
        testShelfProActionsImagePDFAndBatchRename(suite)
        testTelemetryHistoryRingClustersAndTwoRow(suite)
        testSpaceLensTreemapAndTrashWatcher(suite)
        testCleanerViewAndDevPolishInvariants(suite)
    }

    private static func testDDCAndAmbientLightSyncAndVirtualHiDPI(_ suite: TestSuite) {
        let volPacket = DDCPacketBuilder.buildSetVCPPacket(code: .audioSpeakerVolume, value: 65)
        let contrastPacket = DDCPacketBuilder.buildSetVCPPacket(code: .contrast, value: 80)
        let kvmPacket = DDCPacketBuilder.buildSetVCPPacket(code: .inputSource, value: DisplayInputSourcePreset.usbC.rawValue)
        suite.expect(volPacket.count == 7 && volPacket[3] == 0x62
                     && DDCPacketBuilder.verifySetVCPPacket(volPacket)
                     && contrastPacket[3] == 0x12 && DDCPacketBuilder.verifySetVCPPacket(contrastPacket)
                     && kvmPacket[3] == 0x60 && DDCPacketBuilder.verifySetVCPPacket(kvmPacket),
                     "DDCPacketBuilder constructs valid checksummed VCP packets for contrast, volume, and KVM")

        let darkLux = AmbientLightSyncService.targetBrightness(forLux: 5)
        let officeLux = AmbientLightSyncService.targetBrightness(forLux: 350)
        let sunLux = AmbientLightSyncService.targetBrightness(forLux: 8000)
        suite.expect(darkLux < officeLux && officeLux < sunLux
                     && (0.05...1.0).contains(darkLux) && (0.05...1.0).contains(sunLux),
                     "AmbientLightSyncService maps lux monotonically onto clamped normalized brightness")

        let als = AmbientLightSyncService()
        als.userBias = 0.1
        als.update(lux: 300)
        suite.expect(als.targetNormalizedBrightness > AmbientLightSyncService.targetBrightness(forLux: 300, userBias: 0),
                     "AmbientLightSyncService applies user bias cleanly")

        let hiDPI = VirtualDisplayManager.presets
        suite.expect(hiDPI.count >= 4 && hiDPI.contains(where: { $0.logicalWidth == 2560 && $0.backingPixelWidth == 5120 }),
                     "VirtualDisplayManager exposes 2x HiDPI scaled presets")
    }

    private static func testWorkspacesCustomGridAndTitlebarGestures(_ suite: TestSuite) {
        let grid = CustomSnapGridSpec(columns: 4, rows: 2, gap: 10)
        let screen = CGRect(x: 0, y: 0, width: 1650, height: 1030)
        let leftCell = grid.cellFrame(in: screen, colRange: 0...1, rowRange: 0...1)
        let rightCell = grid.cellFrame(in: screen, colRange: 2...3, rowRange: 0...1)
        suite.expect(leftCell.width > 780 && rightCell.minX > leftCell.maxX
                     && abs(leftCell.maxX + 10 - rightCell.minX) <= 1.0,
                     "CustomSnapGridSpec computes gap-aware spanning frames cleanly")

        let suiteName = "vorss.tests.wave4.workspaces.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WindowWorkspaceStore(defaults: defaults, key: "ws")
        let slot = WindowWorkspaceSlot(bundleID: "com.apple.Terminal",
                                       normalizedX: 0, normalizedY: 0, normalizedWidth: 0.5, normalizedHeight: 1.0)
        let saved = store.savePreset(name: "Coding", slots: [slot])
        let reloaded = WindowWorkspaceStore(defaults: defaults, key: "ws")
        suite.expect(reloaded.presets.count == 1 && reloaded.presets.first?.id == saved.id,
                     "WindowWorkspaceStore persists workspace layout snapshots")

        let win = CGRect(x: 100, y: 100, width: 800, height: 600)
        let titlebarPoint = CGPoint(x: 300, y: 688)
        let contentPoint = CGPoint(x: 300, y: 400)
        suite.expect(TitlebarGestureService.classify(point: titlebarPoint, inWindowFrame: win, eventKind: .doubleClick) == .maximize
                     && TitlebarGestureService.classify(point: titlebarPoint, inWindowFrame: win, eventKind: .scrollUp) == .rollUp
                     && TitlebarGestureService.classify(point: contentPoint, inWindowFrame: win, eventKind: .doubleClick) == nil,
                     "TitlebarGestureService restricts titlebar actions strictly to top titlebar band")
    }

    private static func testShelfProActionsImagePDFAndBatchRename(_ suite: TestSuite) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorss-shelfpro-test-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            // 1) Create a synthetic PNG image & convert+resize via ShelfProActions
            let srcImgURL = tempDir.appendingPathComponent("sample.png")
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 100,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                       isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = ctx
                NSColor.systemTeal.setFill()
                NSRect(x: 0, y: 0, width: 200, height: 100).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            let pngData = rep.representation(using: .png, properties: [:])!
            try pngData.write(to: srcImgURL)

            let outURL = try ShelfProActions.convertAndResizeImage(at: srcImgURL,
                                                                   to: .jpeg,
                                                                   maxDimension: 100,
                                                                   outputDirectory: tempDir)
            let outImg = NSImage(contentsOf: outURL)
            suite.expect(FileManager.default.fileExists(atPath: outURL.path) && (outImg?.size.width ?? 0) <= 100,
                         "ShelfProActions converts and resizes dropped images")

            // 2) Create 2 1-page PDFs & merge into 2-page PDF
            let pdf1URL = tempDir.appendingPathComponent("a.pdf")
            let pdf2URL = tempDir.appendingPathComponent("b.pdf")
            let mergedURL = tempDir.appendingPathComponent("merged.pdf")
            let d1 = PDFDocument(); d1.insert(PDFPage(), at: 0); d1.write(to: pdf1URL)
            let d2 = PDFDocument(); d2.insert(PDFPage(), at: 0); d2.write(to: pdf2URL)
            let totalPages = try ShelfProActions.mergePDFs(at: [pdf1URL, pdf2URL], outputURL: mergedURL)
            let mergedDoc = PDFDocument(url: mergedURL)
            suite.expect(totalPages == 2 && mergedDoc?.pageCount == 2,
                         "ShelfProActions merges PDFs preserving all pages")

            // 3) Batch rename preview & collision check
            let r1 = tempDir.appendingPathComponent("one.txt")
            let r2 = tempDir.appendingPathComponent("two.txt")
            try Data("1".utf8).write(to: r1)
            try Data("2".utf8).write(to: r2)
            let preview = ShelfProActions.previewBatchRename(urls: [r1, r2], prefix: "Shot", startIndex: 1)
            suite.expect(preview.map(\.targetName) == ["Shot_1.txt", "Shot_2.txt"]
                         && preview.allSatisfy { !$0.hasCollision },
                         "ShelfProActions batch rename formats indexed names cleanly")
            let renamed = try ShelfProActions.applyBatchRename(preview)
            suite.expect(renamed.count == 2 && FileManager.default.fileExists(atPath: renamed[0].path),
                         "ShelfProActions applies non-colliding batch renames cleanly")
        } catch {
            suite.expect(false, "ShelfProActions unexpected error: \(error)")
        }
        try? FileManager.default.removeItem(at: tempDir)
    }

    private static func testTelemetryHistoryRingClustersAndTwoRow(_ suite: TestSuite) {
        let ring = TelemetryHistoryRing()
        for idx in 0..<75 {
            ring.record(TelemetryPoint(timestamp: Double(idx * 15),
                                       cpu: Double(idx % 100),
                                       gpu: 20,
                                       memory: 50,
                                       networkBytesPerSec: 125_000))
        }
        suite.expect(ring.points(for: .oneMinute).count == TelemetryHistoryRing.minuteCapacity
                     && ring.points(for: .oneHour).count <= TelemetryHistoryRing.hourCapacity
                     && ring.points(for: .twentyFourHours).count >= 18
                     && ring.scrubPoint(for: .oneMinute, normalizedX: 0.5) != nil,
                     "TelemetryHistoryRing bounds 1m/1h/24h buckets and supports normalized scrubbing")

        let cluster = AppleSiliconClusterEstimator.estimate(coreLoads: [10, 12, 8, 10, 80, 90, 70, 80],
                                                            efficiencyCoreCount: 4,
                                                            gpuLoad: 40)
        suite.expect(abs(cluster.eCorePercent - 10) < 0.1
                     && abs(cluster.pCorePercent - 80) < 0.1
                     && cluster.aneActivityPercent > 15,
                     "AppleSiliconClusterEstimator separates E-core, P-core, and ANE utilization cleanly")

        let stacked = MenuBarTwoRowFormatter.formatTwoRowMetric(
            topLabel: "NET",
            bottomValue: MenuBarTwoRowFormatter.compactRate(bytesPerSec: 2_400_000)
        )
        suite.expect(stacked == "NET\n2.4M",
                     "MenuBarTwoRowFormatter formats fixed compact stacked labels")
    }

    private static func testSpaceLensTreemapAndTrashWatcher(_ suite: TestSuite) {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 200)
        let nodes = [
            SpaceLensNode(id: "dev", title: "DerivedData", bytes: 4_000_000, categoryIndex: 0),
            SpaceLensNode(id: "cache", title: "Caches", bytes: 2_000_000, categoryIndex: 1),
            SpaceLensNode(id: "logs", title: "Logs", bytes: 1_000_000, categoryIndex: 2),
        ]
        let tiles = SpaceLensTreemap.layout(nodes: nodes, in: bounds)
        let totalTileArea = tiles.reduce(0.0) { $0 + Double($1.rect.width * $1.rect.height) }
        suite.expect(tiles.count == 3
                     && tiles.allSatisfy { $0.rect.width > 0 && $0.rect.height > 0 }
                     && abs(totalTileArea - Double(bounds.width * bounds.height)) < 900,
                     "SpaceLensTreemap allocates proportional positive non-degenerate tiles")

        let tempLib = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorss-trashwatch-\(UUID().uuidString)", isDirectory: true)
        do {
            let support = tempLib.appendingPathComponent("Application Support/com.example.App", isDirectory: true)
            let cache = tempLib.appendingPathComponent("Caches/com.example.App", isDirectory: true)
            let prefs = tempLib.appendingPathComponent("Preferences", isDirectory: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: prefs, withIntermediateDirectories: true)
            try Data("ok".utf8).write(to: prefs.appendingPathComponent("com.example.App.plist"))

            let watcher = TrashWatcherService()
            watcher.recordTrashedApp(name: "Example", bundleID: "com.example.App", libraryDirectory: tempLib)
            suite.expect(watcher.detectedAppName == "Example"
                         && watcher.detectedLeftovers.count == 3
                         && watcher.mascotMoment == .sweep,
                         "TrashWatcherService detects Library leftovers and triggers .sweep mascot moment")

            let pkgPaths = TrashWatcherService.parsePkgReceiptPaths(
                fromPkgutilOutput: "Applications/Tool.app\n../escape\nLibrary/Preferences/com.tool.plist\n",
                volumeRoot: URL(fileURLWithPath: "/")
            )
            suite.expect(pkgPaths.count == 2 && !pkgPaths.contains(where: { $0.path.contains("..") }),
                         "TrashWatcherService rejects parent-traversal pkg receipt paths")
        } catch {
            suite.expect(false, "TrashWatcherService unexpected error: \(error)")
        }
        try? FileManager.default.removeItem(at: tempLib)
    }

    private static func testCleanerViewAndDevPolishInvariants(_ suite: TestSuite) {
        let cleaner = (try? String(contentsOfFile: "Sources/Vorssaint/UI/Cleaner/CleanerView.swift", encoding: .utf8)) ?? ""
        let port = (try? String(contentsOfFile: "Sources/Vorssaint/UI/PortManager/PortManagerView.swift", encoding: .utf8)) ?? ""
        let kill = (try? String(contentsOfFile: "Sources/Vorssaint/UI/KillProcess/KillProcessView.swift", encoding: .utf8)) ?? ""
        suite.expect(cleaner.contains("SpaceLensTreemap")
                     && cleaner.components(separatedBy: "cleanSelected(").count == 2
                     && !port.contains("\\(entry.port)") && !port.contains("\\(entry.pid)")
                     && !kill.contains("hoveredPID"),
                     "Wave 4 Cleaner and Dev Tool polish maintain existing AST/string contract invariants")
    }
}
