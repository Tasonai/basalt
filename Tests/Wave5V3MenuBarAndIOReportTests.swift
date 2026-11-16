// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum Wave5V3MenuBarAndIOReportContract {
    static func run(_ suite: TestSuite) {
        testIOReportAndSMARTReaders(suite)
        testTelemetrySevenDaySQLiteRoundTrip(suite)
        testMenuBarOverflowPanelAndUIContracts(suite)
    }

    private static func testIOReportAndSMARTReaders(_ suite: TestSuite) {
        let power = AppleSiliconIOReportSampler.shared.sample()
        suite.expect(power.cpuWatts.isFinite && power.cpuWatts >= 0
                     && power.gpuWatts.isFinite && power.gpuWatts >= 0
                     && power.aneWatts.isFinite && power.aneWatts >= 0
                     && power.packageWatts.isFinite && power.packageWatts >= 0
                     && power.aneActivityPercent.isFinite && power.aneActivityPercent >= 0,
                     "AppleSiliconIOReportSampler produces finite non-negative power snapshot")

        let smart = NVMeSMARTHealthReader.readPrimaryDisk()
        if let temp = smart.temperatureCelsius {
            suite.expect(temp.isFinite && temp > -50 && temp < 150,
                         "NVMeSMARTHealthReader reports bounded temperature when available")
        }
        if let wear = smart.wearUsedPercent {
            suite.expect(wear >= 0 && wear <= 100,
                         "NVMeSMARTHealthReader clamps wear percent within 0...100")
        }
        let parsed = NVMeSMARTHealthReader.parseSMARTDictionary([
            "Percentage Used": 7,
            "Temperature": 38,
            "Power On Hours": 412,
            "Media Errors": 0,
        ])
        suite.expect(parsed.wearUsedPercent == 7
                     && parsed.temperatureCelsius == 38
                     && parsed.powerOnHours == 412
                     && parsed.statusVerified,
                     "NVMeSMARTHealthReader parses standard IOKit SMART properties cleanly")
    }

    private static func testTelemetrySevenDaySQLiteRoundTrip(_ suite: TestSuite) {
        suite.expect(TelemetryHistoryHorizon.allCases.contains(.sevenDays)
                     && TelemetryHistoryHorizon.sevenDays.rawValue == "7d",
                     "TelemetryHistoryHorizon includes 7d horizon")

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("vorssaint-telemetry-sqlite-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbURL = tempDir.appendingPathComponent("telemetry.sqlite")
        let ring = TelemetryHistoryRing()
        ring.attachSQLiteStore(at: dbURL)
        ring.record(cpuPercent: 34.5, gpuPercent: 18.2, memoryPercent: 61.0,
                    netRxBytesPerSec: 12_000, netTxBytesPerSec: 3_400, watts: 9.7)
        ring.flushSQLiteStore()
        ring.closeSQLiteStore()

        let reloaded = TelemetryHistoryRing()
        reloaded.attachSQLiteStore(at: dbURL)
        let sevenDaySeries = reloaded.samples(for: .sevenDays)
        reloaded.closeSQLiteStore()

        suite.expect(!sevenDaySeries.isEmpty,
                     "TelemetryHistoryRing persists and reloads 7d samples from SQLite WAL store")
    }

    private static func testMenuBarOverflowPanelAndUIContracts(_ suite: TestSuite) {
        let manager = (try? String(contentsOfFile: "Sources/Vorssaint/Services/MenuBar/MenuBarIconManagerService.swift", encoding: .utf8)) ?? ""
        let overflowPanel = (try? String(contentsOfFile: "Sources/Vorssaint/UI/MenuBar/MenuBarOverflowBarController.swift", encoding: .utf8)) ?? ""
        let generalSettings = (try? String(contentsOfFile: "Sources/Vorssaint/UI/Settings/GeneralSettings.swift", encoding: .utf8)) ?? ""
        let systemSection = (try? String(contentsOfFile: "Sources/Vorssaint/UI/MenuPanel/SystemSection.swift", encoding: .utf8)) ?? ""
        let diskSection = (try? String(contentsOfFile: "Sources/Vorssaint/UI/MenuPanel/DiskSection.swift", encoding: .utf8)) ?? ""
        let featureCatalog = (try? String(contentsOfFile: "Sources/Vorssaint/Core/FeatureCatalog.swift", encoding: .utf8)) ?? ""

        suite.expect(manager.contains("com.vorssaint.menubar.divider")
                     && manager.contains("NSStatusItem"),
                     "MenuBarIconManagerService manages collapsible NSStatusItem divider")

        suite.expect(overflowPanel.contains(": OverlayPanel"),
                     "MenuBarOverflowBarController subclasses OverlayPanel for non-activating overlay hygiene")

        suite.expect(generalSettings.contains("OverhaulV3Strings.menuBarManagerToggle")
                     && !generalSettings.contains(".toggleStyle(.switch)")
                     && !generalSettings.contains(".toggleStyle(.checkbox)"),
                     "GeneralSettings exposes Menu Bar Manager toggle using VorssaintDesignKit")

        suite.expect(systemSection.contains("OverhaulV3Strings.wattsPackageLabel")
                     && systemSection.contains("OverhaulV3Strings.telemetrySevenDayHorizon")
                     && !systemSection.contains(".toggleStyle(.switch)")
                     && !systemSection.contains(".toggleStyle(.checkbox)"),
                     "SystemSection exposes IOReport Watts and 7d telemetry horizon")

        suite.expect(diskSection.contains("OverhaulV3Strings.smartHealthTitle")
                     && !diskSection.contains(".toggleStyle(.switch)")
                     && !diskSection.contains(".toggleStyle(.checkbox)"),
                     "DiskSection displays NVMe SMART health telemetry")

        suite.expect(!featureCatalog.contains("case menuBarManager"),
                     "FeatureCatalog enum AppFeature was not modified for MenuBarIconManager")
    }
}
