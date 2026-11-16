// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum Wave6V2SystemAndAutomationContract {
    static func run(_ suite: TestSuite) {
        testMultiMonitorWorkspacesAndGestures(suite)
        testTelemetryRingAndClusterEstimator(suite)
        testSpaceLensScannerAndTrashLeftovers(suite)
        testClopMathAndAutomationRouter(suite)
        testWave6SourceContracts(suite)
    }

    private static func readRepo(_ path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    private static func testMultiMonitorWorkspacesAndGestures(_ suite: TestSuite) {
        let legacyJSON = """
        {"bundleID":"com.apple.Safari","normalizedX":0.0,"normalizedY":0.0,"normalizedWidth":0.5,"normalizedHeight":1.0}
        """
        let decodedLegacy = try? JSONDecoder().decode(WindowWorkspaceSlot.self, from: Data(legacyJSON.utf8))
        suite.expect(decodedLegacy?.bundleID == "com.apple.Safari" && decodedLegacy?.displayIndex == 0,
                     "WindowWorkspaceSlot decodes legacy JSON without displayIndex defaulting to display 0")

        let screens = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 1440, y: 0, width: 2560, height: 1440),
        ]
        let visibleScreens = [
            CGRect(x: 0, y: 0, width: 1440, height: 875),
            CGRect(x: 1440, y: 0, width: 2560, height: 1415),
        ]

        suite.expect(WindowWorkspaceSlot.displayBounds(forIndex: 1, screens: screens) == screens[1],
                     "displayBounds returns secondary screen when present")
        suite.expect(WindowWorkspaceSlot.displayBounds(forIndex: 4, screens: screens) == screens[0],
                     "displayBounds falls back to primary screen when disconnected")

        let secondaryWindow = CGRect(x: 1440, y: 0, width: 1280, height: 1415)
        let captured = WindowWorkspaceSlot.normalizedSlot(
            bundleID: "com.apple.dt.Xcode",
            windowFrame: secondaryWindow,
            screenFrames: screens,
            visibleFrames: visibleScreens
        )
        suite.expect(captured?.displayIndex == 1
                     && abs((captured?.normalizedWidth ?? 0) - 0.5) < 0.002,
                     "normalizedSlot captures secondary displayIndex and normalized width")

        let restoredFrame = captured?.frame(inScreens: visibleScreens)
        suite.expect(restoredFrame == CGRect(x: 1440, y: 0, width: 1280, height: 1415),
                     "frame(inScreens:) restores secondary monitor window frame accurately")

        let winFrame = CGRect(x: 100, y: 200, width: 800, height: 500)
        suite.expect(TitlebarGestureService.classify(point: CGPoint(x: 300, y: 690),
                                                     inWindowFrame: winFrame,
                                                     titlebarHeight: 30,
                                                     eventKind: .scrollDown) == .fill,
                     "TitlebarGestureService classifies titlebar downward scroll as fill")
        suite.expect(TitlebarGestureService.classify(point: CGPoint(x: 300, y: 400),
                                                     inWindowFrame: winFrame,
                                                     titlebarHeight: 30,
                                                     eventKind: .scrollDown) == nil,
                     "TitlebarGestureService ignores scroll events below titlebar band")
    }

    private static func testTelemetryRingAndClusterEstimator(_ suite: TestSuite) {
        let ring = TelemetryHistoryRing()
        ring.record(TelemetryPoint(timestamp: 1000, cpu: 25, gpu: 10, memory: 40, networkBytesPerSec: 500))
        ring.record(TelemetryPoint(timestamp: 1001, cpu: 75, gpu: 50, memory: 60, networkBytesPerSec: 1500))
        ring.record(TelemetryPoint(timestamp: 1065, cpu: 50, gpu: 30, memory: 80, networkBytesPerSec: 1000))

        suite.expect(ring.points(for: .oneMinute).count == 3,
                     "TelemetryHistoryRing stores every 1m sample")
        suite.expect(ring.points(for: .oneHour).count == 2
                     && ring.points(for: .twentyFourHours).count == 2,
                     "TelemetryHistoryRing downsamples 1h (10s) and 24h (60s) buckets")

        let cpuSeries = ring.series(for: .cpu, horizon: .oneMinute)
        suite.expect(cpuSeries.count == 3 && abs(cpuSeries[1] - 0.75) < 0.001,
                     "TelemetryHistoryRing series normalizes CPU to 0...1")
        let scrubbed = ring.scrubPoint(for: .twentyFourHours, normalizedX: 1.0)
        suite.expect(scrubbed?.memory == 80,
                     "TelemetryHistoryRing scrubPoint resolves timeline end accurately")

        let clusters = AppleSiliconClusterEstimator.estimate(
            coreLoads: [80, 60, 20, 40],
            efficiencyCoreCount: 2,
            gpuLoad: 40
        )
        suite.expect(abs(clusters.eCorePercent - 70) < 0.001
                     && abs(clusters.pCorePercent - 30) < 0.001
                     && clusters.aneActivityPercent > 0,
                     "AppleSiliconClusterEstimator splits E-core and P-core loads accurately")

        suite.expect(MenuBarTwoRowFormatter.formatTwoRowMetric(topLabel: "CPU", bottomValue: "42%") == "CPU\n42%"
                     && MenuBarTwoRowFormatter.compactRate(bytesPerSec: 2_500_000) == "2.5M",
                     "MenuBarTwoRowFormatter formats two-row stacked label and compact bandwidth")
    }

    private static func testSpaceLensScannerAndTrashLeftovers(_ suite: TestSuite) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("vorssaint-wave6-test-\(UUID().uuidString)", isDirectory: true)
        let bigDir = root.appendingPathComponent("BigFolder", isDirectory: true)
        let nestedDir = bigDir.appendingPathComponent("Sub", isDirectory: true)
        let libDir = root.appendingPathComponent("Library", isDirectory: true)
        defer { try? fm.removeItem(at: root) }

        do {
            try fm.createDirectory(at: nestedDir, withIntermediateDirectories: true)
            try Data(repeating: 0xAA, count: 4096).write(to: nestedDir.appendingPathComponent("chunk.bin"))
            try Data(repeating: 0xBB, count: 512).write(to: root.appendingPathComponent("Small.bin"))

            let appSupport = libDir.appendingPathComponent("Application Support/DemoApp", isDirectory: true)
            let caches = libDir.appendingPathComponent("Caches/com.example.demoapp", isDirectory: true)
            let prefs = libDir.appendingPathComponent("Preferences", isDirectory: true)
            try fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
            try fm.createDirectory(at: caches, withIntermediateDirectories: true)
            try fm.createDirectory(at: prefs, withIntermediateDirectories: true)
            try Data("test".utf8).write(to: prefs.appendingPathComponent("com.example.demoapp.plist"))
        } catch {
            suite.expect(false, "Failed creating temporary Wave 6 Space Lens fixture: \(error)")
            return
        }

        let nodes = SpaceLensDirectoryScanner.scanChildren(at: root, maxEntries: 10)
        suite.expect(nodes.count == 3
                     && nodes[0].title == "BigFolder"
                     && nodes[0].isDirectory
                     && nodes[0].bytes >= 4096,
                     "SpaceLensDirectoryScanner sorts directories descending and preserves drill-down metadata")

        let tiles = SpaceLensTreemap.layout(nodes: nodes, in: CGRect(x: 0, y: 0, width: 400, height: 240))
        suite.expect(tiles.count == 3 && tiles.allSatisfy { $0.url != nil },
                     "SpaceLensTreemap propagates drill-down URLs onto layout tiles")

        let leftovers = TrashWatcherService.relatedLeftovers(
            bundleID: "com.example.demoapp",
            appName: "DemoApp",
            libraryDirectory: libDir
        )
        suite.expect(leftovers.count == 3,
                     "TrashWatcherService discovers Application Support, Caches, and Preferences leftovers")

        let receiptURLs = TrashWatcherService.parsePkgReceiptPaths(
            fromPkgutilOutput: "Applications/Demo.app\n../escape\nLibrary/Preferences/a.plist\n/abs/skip",
            volumeRoot: root
        )
        suite.expect(receiptURLs.count == 2 && receiptURLs[0].path.hasSuffix("Applications/Demo.app"),
                     "TrashWatcherService filters path traversal and absolute receipt paths")
    }

    private static func testClopMathAndAutomationRouter(_ suite: TestSuite) {
        suite.expect(Wave6MediaCompressionMath.compressionSavingsPercent(before: 1000, after: 350) == 65
                     && Wave6MediaCompressionMath.compressionSavingsPercent(before: 1000, after: 1100) == 0
                     && Wave6MediaCompressionMath.compressionSavingsPercent(before: 0, after: 0) == 0,
                     "MediaAutoOptimizerService compressionSavingsPercent clamps edge cases cleanly")

        let cases: [(String, VorssaintAutomationCommand?)] = [
            ("vorssaint://clean", .clean),
            ("vorssaint://clipboard/search?q=swift%206", .clipboardSearch(query: "swift 6")),
            ("vorssaint://record/start", .recordStart),
            ("vorssaint://record/stop", .recordStop),
            ("vorssaint://screenshot/area", .screenshotArea),
            ("vorssaint://workspace/apply?name=Coding", .workspaceApply(name: "Coding")),
            ("vorssaint://mixer/preset?name=Podcast", .mixerPreset(name: "Podcast")),
            ("vorssaint://display/brightness?value=75", .displayBrightness(percent: 75)),
            ("vorssaint://display/brightness?percent=150", .displayBrightness(percent: 100)),
            ("vorssaint://workspace/apply", nil),
            ("https://clean", nil),
        ]
        for (raw, expected) in cases {
            guard let url = URL(string: raw) else {
                suite.expect(false, "Invalid test URL: \(raw)")
                continue
            }
            let parsed = Wave6AutomationParser.parseCommand(from: url)
            suite.expect(parsed == expected, "VorssaintAutomationRouter parses \(raw)")
        }
    }

    private static func testWave6SourceContracts(_ suite: TestSuite) {
        let infoPlist = readRepo("Resources/Info.plist")
        suite.expect(infoPlist.contains("<string>vorssaint</string>")
                     && infoPlist.contains("CFBundleURLSchemes"),
                     "Resources/Info.plist registers vorssaint:// URL scheme")

        let tapSource = readRepo("Sources/Vorssaint/Services/WindowLayout/TitlebarScrollTap.swift")
        let tapCreates = tapSource.components(separatedBy: "CGEvent.tapCreate(").count - 1
        let tapInvalidates = tapSource.components(separatedBy: "CFMachPortInvalidate(").count - 1
        suite.expect(tapCreates == 1 && tapInvalidates >= 1 && tapSource.contains("SessionActivity"),
                     "TitlebarScrollTap pairs CGEvent.tapCreate with CFMachPortInvalidate and SessionActivity")

        let gridOverlay = readRepo("Sources/Vorssaint/UI/WindowLayout/CustomSnapGridOverlayController.swift")
        let multiShelf = readRepo("Sources/Vorssaint/UI/Shelf/ShelfAdditionalInstanceController.swift")
        suite.expect(gridOverlay.contains(": OverlayPanel")
                     && !gridOverlay.contains(": NSPanel")
                     && multiShelf.contains(": OverlayPanel")
                     && !multiShelf.contains(": NSPanel"),
                     "CustomSnapGridOverlayController and ShelfAdditionalInstanceController subclass OverlayPanel")
    }
}
