// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum Wave5V3MenuBarAndIOReportContract {
    static func run(_ suite: TestSuite) {
        testIOReportAndSMARTReaders(suite)
        testTelemetrySevenDaySQLiteRoundTrip(suite)
        testTelemetryRecordingAndIntelPowerPolicy(suite)
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

    private static func testTelemetryRecordingAndIntelPowerPolicy(_ suite: TestSuite) {
        // 1. Non-telemetry ticks (peripheralBattery, disk, temp, fan, USB) never record.
        let peripheralOnly = SystemMonitorTelemetryPolicy.TelemetrySampleInput()
        suite.expect(SystemMonitorTelemetryPolicy.decideTelemetrySample(peripheralOnly) == nil,
                     "peripheralBattery/disk/temp-only ticks never write telemetry samples")

        // 2. Battery/power-only ticks without CPU+Memory never poison SQLite with 0% rows.
        let batteryOnly = SystemMonitorTelemetryPolicy.TelemetrySampleInput(
            planNeedsPower: true,
            sampledPower: true,
            watts: 18.4
        )
        suite.expect(SystemMonitorTelemetryPolicy.decideTelemetrySample(batteryOnly) == nil,
                     "power-only ticks without CPU and Memory do not write all-zero rows")

        // 3. CPU tick 0 before baseline produces nil cpuFraction -> skipped.
        let cpuTickZero = SystemMonitorTelemetryPolicy.TelemetrySampleInput(
            planNeedsCPU: true,
            sampledCPU: true,
            cpuFraction: nil
        )
        suite.expect(SystemMonitorTelemetryPolicy.decideTelemetrySample(cpuTickZero) == nil,
                     "initial CPU baseline tick with nil cpuFraction does not record empty sample")

        // 4. CPU-only menu bar pin updates 1m sparkline without writing 0% RAM dips to 1h/24h/7d SQLite.
        let cpuOnly = SystemMonitorTelemetryPolicy.TelemetrySampleInput(
            planNeedsCPU: true,
            sampledCPU: true,
            cpuFraction: 0.42,
            netRxBytesPerSec: 20_000_000
        )
        let cpuOnlyDecision = SystemMonitorTelemetryPolicy.decideTelemetrySample(cpuOnly)
        suite.expect(cpuOnlyDecision != nil
                     && cpuOnlyDecision?.persistHistory == false
                     && abs((cpuOnlyDecision?.point.cpu ?? 0) - 42.0) < 0.01
                     && cpuOnlyDecision?.point.netRxBytesPerSec == 0,
                     "CPU-only pin updates 1m sparkline, omits stale network when !planNeedsNetwork, and does not persist 0% RAM to SQLite")

        // 5. Network-only idle tick at 0 B/s records 1m decay without touching SQLite.
        let netIdle = SystemMonitorTelemetryPolicy.TelemetrySampleInput(
            planNeedsNetwork: true,
            sampledNetwork: true,
            netRxBytesPerSec: 0,
            netTxBytesPerSec: 0
        )
        let netIdleDecision = SystemMonitorTelemetryPolicy.decideTelemetrySample(netIdle)
        suite.expect(netIdleDecision != nil
                     && netIdleDecision?.persistHistory == false
                     && netIdleDecision?.point.networkBytesPerSec == 0,
                     "Network-only idle tick at 0 B/s updates 1m sparkline decay without polluting SQLite")

        // 6. Core system tick (CPU + Memory + Intel SMC watts) persists to 1h/24h/7d history.
        let fullTick = SystemMonitorTelemetryPolicy.TelemetrySampleInput(
            planNeedsCPU: true,
            planNeedsGPU: true,
            planNeedsMemory: true,
            planNeedsNetwork: true,
            planNeedsPower: true,
            sampledCPU: true,
            sampledMemory: true,
            cpuFraction: 0.35,
            gpuFraction: 0.12,
            memoryPercent: 64.5,
            netRxBytesPerSec: 1_500,
            netTxBytesPerSec: 500,
            watts: 31.2
        )
        let fullDecision = SystemMonitorTelemetryPolicy.decideTelemetrySample(fullTick)
        suite.expect(fullDecision?.persistHistory == true
                     && abs((fullDecision?.point.cpu ?? 0) - 35.0) < 0.01
                     && abs((fullDecision?.point.memory ?? 0) - 64.5) < 0.01
                     && abs((fullDecision?.point.watts ?? 0) - 31.2) < 0.01,
                     "core CPU+Memory tick persists real CPU, Memory, Network, and SMC Watts")

        // 7. Ring honors persistHistory == false (updates 1m only, leaves 1h/24h/7d empty).
        let sparkRing = TelemetryHistoryRing()
        if let decision = cpuOnlyDecision {
            sparkRing.record(decision.point, persistHistory: decision.persistHistory)
        }
        suite.expect(sparkRing.points(for: .oneMinute).count == 1
                     && sparkRing.points(for: .oneHour).isEmpty
                     && sparkRing.points(for: .twentyFourHours).isEmpty
                     && sparkRing.points(for: .sevenDays).isEmpty,
                     "TelemetryHistoryRing.record(persistHistory: false) updates 1m sparkline only")

        // 8. Intel SMC power resolution falls back cleanly and survives transient empty SMC reads.
        let unavailableIOReport = AppleSiliconPowerSnapshot.unavailable()
        let freshIntel = SystemMonitorTelemetryPolicy.WattsReading(systemWatts: 44.5, cpuWatts: 22.0, gpuWatts: 8.5)
        let firstResolved = SystemMonitorTelemetryPolicy.resolvePowerSnapshot(
            ioReport: unavailableIOReport,
            freshSMC: freshIntel,
            cachedSMC: nil
        )
        suite.expect(firstResolved.snapshot.isHardwareBacked
                     && abs(firstResolved.snapshot.packageWatts - 44.5) < 0.01
                     && abs(firstResolved.snapshot.cpuWatts - 22.0) < 0.01
                     && abs(firstResolved.snapshot.gpuWatts - 8.5) < 0.01
                     && firstResolved.updatedCache == freshIntel,
                     "resolvePowerSnapshot populates hardware-backed Intel SMC watts when IOReport is unavailable")

        let transientEmpty = SystemMonitorTelemetryPolicy.WattsReading(systemWatts: nil, cpuWatts: nil, gpuWatts: nil)
        let secondResolved = SystemMonitorTelemetryPolicy.resolvePowerSnapshot(
            ioReport: unavailableIOReport,
            freshSMC: transientEmpty,
            cachedSMC: firstResolved.updatedCache
        )
        suite.expect(secondResolved.snapshot.isHardwareBacked
                     && abs(secondResolved.snapshot.packageWatts - 44.5) < 0.01,
                     "resolvePowerSnapshot retains last valid Intel SMC watts across transient empty SMC reads")

        let appleSilicon = AppleSiliconPowerSnapshot(
            cpuWatts: 6.2, gpuWatts: 3.1, aneWatts: 0.4,
            packageWatts: 9.7, aneActivityPercent: 12, isHardwareBacked: true
        )
        let siliconResolved = SystemMonitorTelemetryPolicy.resolvePowerSnapshot(
            ioReport: appleSilicon,
            freshSMC: freshIntel,
            cachedSMC: firstResolved.updatedCache
        )
        suite.expect(siliconResolved.snapshot == appleSilicon,
                     "resolvePowerSnapshot prefers native hardware-backed IOReport on Apple Silicon")
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
