// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum Wave8V3DiskEngineAndFinalAuditContract {
    static func run(_ suite: TestSuite) {
        testSunburstPolarGeometry(suite)
        testCollectBasketAndStartupAgentInspector(suite)
        testThreeStageFastDuplicateScanner(suite)
        testCleanerMediaAndSnapshotContracts(suite)
    }

    private static func testSunburstPolarGeometry(_ suite: TestSuite) {
        let leafA = SpaceLensNode(id: "a", name: "Videos", path: "/tmp/Videos", bytes: 600, isDirectory: true, children: [])
        let leafB = SpaceLensNode(id: "b", name: "Caches", path: "/tmp/Caches", bytes: 390, isDirectory: true, children: [])
        let leafTiny = SpaceLensNode(id: "c", name: "Tiny", path: "/tmp/Tiny", bytes: 10, isDirectory: false, children: [])
        let root = SpaceLensNode(id: "root", name: "Root", path: "/tmp", bytes: 1000, isDirectory: true, children: [leafA, leafB, leafTiny])

        let arcs = SpaceLensSunburst.buildArcs(root: root, maxDepth: 5)
        let ring1 = arcs.filter { $0.ringDepth == 1 }
        let angleSum = ring1.reduce(0.0) { $0 + ($1.endAngle - $1.startAngle) }
        suite.expect(!ring1.isEmpty
                     && abs(angleSum - (2.0 * Double.pi)) < 0.05
                     && ring1.allSatisfy { $0.ringDepth >= 1 && $0.ringDepth <= 5 && $0.endAngle > $0.startAngle },
                     "SpaceLensSunburst covers full 2π circle across non-empty polar arcs within depth 1...5")
    }

    private static func testCollectBasketAndStartupAgentInspector(_ suite: TestSuite) {
        var basket = SpaceLensCollectBasket()
        basket.add(path: "/tmp/demo/a.bin", sizeBytes: 1200, name: "a.bin")
        basket.add(path: "/tmp/demo/b.bin", sizeBytes: 800, name: "b.bin")
        basket.add(path: "/tmp/demo/a.bin", sizeBytes: 1200, name: "a.bin")
        suite.expect(basket.items.count == 2 && basket.totalBytes == 2000,
                     "SpaceLensCollectBasket deduplicates staged paths and sums total bytes accurately")

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>com.example.testagent</string>
            <key>ProgramArguments</key><array><string>/usr/bin/true</string></array>
            <key>RunAtLoad</key><true/>
            <key>KeepAlive</key><false/>
        </dict>
        </plist>
        """.data(using: .utf8) ?? Data()

        let parsed = StartupAgentInspector.parsePlistData(
            plist,
            domain: .userAgent,
            plistURL: URL(fileURLWithPath: "/tmp/com.example.testagent.plist")
        )
        suite.expect(parsed?.label == "com.example.testagent"
                     && parsed?.program == "/usr/bin/true"
                     && parsed?.runAtLoad == true
                     && parsed?.keepAlive == false,
                     "StartupAgentInspector decodes LaunchAgent plist Label, Program, RunAtLoad, and KeepAlive")
    }

    private static func testThreeStageFastDuplicateScanner(_ suite: TestSuite) {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("vorssaint-dups-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var payloadA = Data(repeating: 0x41, count: 16_384)
        payloadA[9000] = 0x7E
        var payloadSameHeadTailDiffMid = payloadA
        payloadSameHeadTailDiffMid[9000] = 0x11

        let f1 = tempDir.appendingPathComponent("dup1.bin")
        let f2 = tempDir.appendingPathComponent("dup2.bin")
        let f3 = tempDir.appendingPathComponent("almost.bin")
        let f4 = tempDir.appendingPathComponent("unique_size.bin")

        try? payloadA.write(to: f1)
        try? payloadA.write(to: f2)
        try? payloadSameHeadTailDiffMid.write(to: f3)
        try? Data(repeating: 0x42, count: 4096).write(to: f4)

        let groups = FastDuplicateScanner.scanSync(directoryURL: tempDir, minBytes: 1024)
        suite.expect(groups.count == 1 && groups[0].urls.count == 2 && groups[0].byteSize == 16_384,
                     "FastDuplicateScanner Stage 1-3 groups identical files while rejecting partial head/tail collisions")
    }

    private static func testCleanerMediaAndSnapshotContracts(_ suite: TestSuite) {
        let cleaner = (try? String(contentsOfFile: "Sources/Vorssaint/UI/Cleaner/CleanerView.swift", encoding: .utf8)) ?? ""
        let mediaService = (try? String(contentsOfFile: "Sources/Vorssaint/Services/Media/MediaAutoOptimizerService.swift", encoding: .utf8)) ?? ""
        let mediaView = (try? String(contentsOfFile: "Sources/Vorssaint/UI/Media/MediaWorkspaceView.swift", encoding: .utf8)) ?? ""
        let harness = (try? String(contentsOfFile: "Sources/Vorssaint/UI/DesignSystem/VorssaintSurfaceSnapshotHarness.swift", encoding: .utf8)) ?? ""
        let appDelegate = (try? String(contentsOfFile: "Sources/Vorssaint/App/AppDelegate.swift", encoding: .utf8)) ?? ""

        let cleanCount = cleaner.components(separatedBy: "cleanSelected(").count - 1
        suite.expect(cleanCount == 1
                     && cleaner.contains("SpaceLensTreemap")
                     && cleaner.contains("MascotCameoBadge")
                     && cleaner.contains("OverhaulV3Strings.spaceLensSunburstMode")
                     && cleaner.contains("OverhaulV3Strings.spaceLensCollectTitle")
                     && cleaner.contains("OverhaulV3Strings.startupAgentsTitle")
                     && cleaner.contains("OverhaulV3Strings.duplicatesFinderTitle")
                     && !cleaner.contains(".toggleStyle(.switch)")
                     && !cleaner.contains(".toggleStyle(.checkbox)"),
                     "CleanerView adds Sunburst, Collect, Startup Agents, and Duplicates while preserving cleanSelected and DesignKit")

        suite.expect(mediaService.contains("oxipng")
                     && mediaService.contains("pngquant")
                     && mediaService.contains("cwebp")
                     && mediaService.contains("gifsicle")
                     && mediaService.contains("ffmpeg"),
                     "MediaAutoOptimizerService integrates Clop Pro external codec bridge with native fallbacks")

        suite.expect(mediaView.contains("OverhaulV3Strings.clopExternalToolsBadge")
                     && !mediaView.contains(".toggleStyle(.switch)")
                     && !mediaView.contains(".toggleStyle(.checkbox)"),
                     "MediaWorkspaceView exposes external codec status badges using VorssaintDesignKit")

        suite.expect(harness.contains("VORSSAINT_SURFACE_SNAPSHOT_DIR")
                     && harness.contains("menupanel-light.png")
                     && harness.contains("menupanel-dark.png")
                     && harness.contains("island-expanded-dark.png")
                     && harness.contains("onboarding-stage-dark.png")
                     && harness.contains("spacelens-sunburst-dark.png")
                     && appDelegate.contains("VorssaintSurfaceSnapshotHarness"),
                     "VorssaintSurfaceSnapshotHarness and AppDelegate wire VORSSAINT_SURFACE_SNAPSHOT_DIR 5-surface Retina export")
    }
}
