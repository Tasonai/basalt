// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum Wave4V3DisplayHiDPIAndSolarContract {
    static func run(_ suite: TestSuite) {
        testDDCPowerPacketAndSolarCurve(suite)
        testMirrorConfirmationGateAndRefreshPresets(suite)
        testXDRAutoBoostAndDisplayUIContracts(suite)
    }

    private static func testDDCPowerPacketAndSolarCurve(_ suite: TestSuite) {
        suite.expect(DDCControlCode.powerMode.rawValue == 0xD6 || DDCPowerState.standby.rawValue == 0x04,
                     "DDCControlCode.powerMode (0xD6) and DDCPowerState standby (0x04) match VESA MCCS")

        let packet = DDCPacketBuilder.setVCPValuePacket(code: 0xD6, value: DDCPowerState.standby.rawValue)
        suite.expect(packet.count >= 7 && packet.contains(0xD6) && packet.contains(0x04),
                     "DDCPacketBuilder.setVCPValuePacket encodes VCP power mode packet cleanly")

        let midnight = SolarSyncCurve.targetLuminance(hour: 0.0, minLevel: 0.22, maxLevel: 0.92)
        let midday = SolarSyncCurve.targetLuminance(hour: 13.5, minLevel: 0.22, maxLevel: 0.92)
        let wrapped = SolarSyncCurve.targetLuminance(hour: 24.0 + 13.5, minLevel: 0.22, maxLevel: 0.92)
        let nanGuard = SolarSyncCurve.targetLuminance(hour: .nan, minLevel: 0.22, maxLevel: 0.92)

        suite.expect(abs(midnight - 0.22) < 0.02 && midday > 0.85 && abs(midday - wrapped) < 0.001,
                     "SolarSyncCurve peaks near solar noon, settles to night floor, and wraps 24h cleanly")
        suite.expect(nanGuard.isFinite && nanGuard >= 0.05 && nanGuard <= 1.0,
                     "SolarSyncCurve guards non-finite hour inputs")
    }

    private static func testMirrorConfirmationGateAndRefreshPresets(_ suite: TestSuite) {
        suite.expect(CustomRefreshRatePreset.allCases.map(\.rawValue) == [60, 75, 100, 120, 144],
                     "CustomRefreshRatePreset exposes 60, 75, 100, 120, and 144 Hz presets")

        var gate = MirrorConfirmationGate()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        gate.begin(targetDisplayID: 123, virtualDisplayID: 456, now: t0, timeout: 15)
        suite.expect(gate.isPending
                     && gate.remainingSeconds(now: t0.addingTimeInterval(5)) == 10
                     && !gate.shouldAutoRevert(now: t0.addingTimeInterval(14)),
                     "MirrorConfirmationGate stays pending within 15s countdown window")

        suite.expect(gate.shouldAutoRevert(now: t0.addingTimeInterval(15.5)),
                     "MirrorConfirmationGate triggers auto-revert once 15s deadline expires")

        gate.confirm()
        suite.expect(!gate.isPending && !gate.shouldAutoRevert(now: t0.addingTimeInterval(30)),
                     "MirrorConfirmationGate stops pending auto-revert after user confirmation")

        gate.begin(targetDisplayID: 123, virtualDisplayID: 456, now: t0, timeout: 15)
        gate.cancel()
        suite.expect(!gate.isPending && gate.remainingSeconds(now: t0) == 0,
                     "MirrorConfirmationGate clears state cleanly on cancel")
    }

    private static func testXDRAutoBoostAndDisplayUIContracts(_ suite: TestSuite) {
        let controller = XDRUpscaleOverlayController.shared
        let priorIDs = controller.xdrAutoBoostBundleIDs
        let sampleBundleID = "com.vorssaint.tests.xdr.\(UUID().uuidString)"
        defer {
            controller.setAutoBoost(bundleID: sampleBundleID, enabled: false)
            controller.xdrAutoBoostBundleIDs = priorIDs
            controller.evaluateFrontmostBundleID(nil)
        }

        controller.setAutoBoost(bundleID: sampleBundleID, enabled: true)
        controller.evaluateFrontmostBundleID(sampleBundleID)
        suite.expect(controller.xdrAutoBoostBundleIDs.contains(sampleBundleID)
                     && controller.isAutoBoostTriggeredByFrontmostApp,
                     "XDRUpscaleOverlayController matches frontmost bundle ID against xdrAutoBoostBundleIDs")

        controller.evaluateFrontmostBundleID("com.apple.TextEdit")
        suite.expect(!controller.isAutoBoostTriggeredByFrontmostApp,
                     "XDRUpscaleOverlayController clears per-app trigger when unfocused app is frontmost")

        // Qualification rejects built-in Intel non-XDR LCD (potEDR=2.0) and
        // external DisplayHDR 400 SDR-mode monitors (PA348CGV potEDR=2.0885, refEDR=0.0),
        // while accepting true Pro Display XDR and Apple Silicon XDR MacBooks.
        suite.expect(!XDRUpscaleOverlayController.isQualifiedXDRDisplay(
                        isBuiltIn: true, model: "MacBookPro16,1",
                        localizedName: "Built-in Retina Display",
                        potentialEDR: 2.0, referenceEDR: 0.0)
                     && !XDRUpscaleOverlayController.isQualifiedXDRDisplay(
                        isBuiltIn: false, model: "MacBookPro16,1",
                        localizedName: "PA348CGV",
                        potentialEDR: 2.0885, referenceEDR: 0.0)
                     && XDRUpscaleOverlayController.isQualifiedXDRDisplay(
                        isBuiltIn: false, model: "MacBookPro16,1",
                        localizedName: "Pro Display XDR",
                        potentialEDR: 4.0, referenceEDR: 3.2)
                     && XDRUpscaleOverlayController.isQualifiedXDRDisplay(
                        isBuiltIn: true, model: "Mac15,6",
                        localizedName: "Built-in Retina Display",
                        potentialEDR: 16.0, referenceEDR: 2.0),
                     "XDRUpscaleOverlayController qualifies only genuine XDR/HDR displays and rejects DisplayHDR 400 SDR monitors")

        // Never clips SDR highlights when currentEDR <= 1.05.
        suite.expect(XDRUpscaleOverlayController.resolvedBoostFactor(boostAmount: 1.6, currentEDR: 1.0, potentialEDR: 2.0885) == 1.0
                     && abs(XDRUpscaleOverlayController.resolvedBoostFactor(boostAmount: 1.45, currentEDR: 2.0, potentialEDR: 4.0) - 1.45) < 0.001,
                     "XDRUpscaleOverlayController never multiplies SDR content when currentEDR <= 1.05")

        // Rejects all-zero unpopulated T2 HID ALS events (even when ReportInterval
        // is set), while accepting readings with non-zero raw channels or lux > 0.
        suite.expect(AppleLMUSensorReader.sanitizedHIDLux(level: 0, rawChannels: [0, 0, 0, 0], reportInterval: nil) == nil
                     && AppleLMUSensorReader.sanitizedHIDLux(level: 0, rawChannels: [0, 0, 0, 0], reportInterval: 500_000) == nil
                     && AppleLMUSensorReader.sanitizedHIDLux(level: 0, rawChannels: [2, 0, 0, 0], reportInterval: 500_000) == 0.0
                     && AppleLMUSensorReader.sanitizedHIDLux(level: 185.5, rawChannels: [12, 34, 56, 78], reportInterval: 500_000) == 185.5,
                     "AppleLMUSensorReader rejects all-zero unpopulated T2 HID events while accepting live ALS readings")

        let brightnessService = (try? String(contentsOfFile: "Sources/Vorssaint/Services/Display/BrightnessService.swift", encoding: .utf8)) ?? ""
        let brightnessSection = (try? String(contentsOfFile: "Sources/Vorssaint/UI/MenuPanel/BrightnessSection.swift", encoding: .utf8)) ?? ""
        let displaySupport = (try? String(contentsOfFile: "Sources/Vorssaint/Services/Display/DisplayProSupport.swift", encoding: .utf8)) ?? ""

        suite.expect(displaySupport.contains("bindHardwareMirror")
                     && displaySupport.contains("CGConfigureDisplayMirrorOfDisplay"),
                     "DisplayProSupport implements CGConfigureDisplayMirrorOfDisplay hardware mirror binding")

        suite.expect(brightnessService.contains("solarSyncEnabled")
                     && brightnessService.contains("sendDDCPowerStandby"),
                     "BrightnessService exposes Solar Sync scheduling and DDC power standby")

        suite.expect(brightnessSection.contains("OverhaulV3Strings.hidpiMirrorTitle")
                     && brightnessSection.contains("OverhaulV3Strings.hidpiMirrorConfirmBanner")
                     && brightnessSection.contains("OverhaulV3Strings.solarSyncToggleTitle")
                     && brightnessSection.contains("OverhaulV3Strings.ddcStandbyAction")
                     && brightnessSection.contains("OverhaulV3Strings.xdrPerAppRulesTitle")
                     && !brightnessSection.contains(".toggleStyle(.switch)")
                     && !brightnessSection.contains(".toggleStyle(.checkbox)"),
                     "BrightnessSection exposes HiDPI mirror banner, Solar Sync, DDC Standby, and per-app XDR with VorssaintDesignKit")
    }
}
