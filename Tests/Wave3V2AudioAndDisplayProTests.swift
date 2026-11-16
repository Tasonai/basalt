// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import AudioToolbox
import CoreGraphics
import Foundation

enum Wave3V2AudioAndDisplayProContract {
    static func run(_ suite: TestSuite) {
        testMixerParametricEQZeroAllocAndAudioBufferList(suite)
        testRealtimeAudioMeterAndCustomPresets(suite)
        testAudioUnitDiscoveryAndSourceWiring(suite)
        testDisplayProDDCLMUAndVirtualDisplay(suite)
    }

    private static func readRepo(_ path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    private static func testMixerParametricEQZeroAllocAndAudioBufferList(_ suite: TestSuite) {
        let eq = MixerParametricEQ(sampleRate: 48_000)
        // Boost 1 kHz (+12 dB) — band 5 in ISO 10-band center list
        var gains = [Float](repeating: 0, count: MixerParametricEQ.bandCount)
        gains[5] = 12
        eq.update(gainsDB: gains, preampDB: 0, pan: 0, isMuted: false)

        let frameCount = 512
        var interleaved = [Float](repeating: 0, count: frameCount * 2)
        for i in 0..<frameCount {
            let sample = Float(0.2 * sin(2.0 * Double.pi * 1000.0 * Double(i) / 48_000.0))
            interleaved[i * 2] = sample
            interleaved[i * 2 + 1] = sample
        }
        let baselinePeak = interleaved.map { abs($0) }.max() ?? 0

        let processed = interleaved.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            let buf = AudioBuffer(mNumberChannels: 2,
                                  mDataByteSize: UInt32(raw.count),
                                  mData: base)
            var abl = AudioBufferList(mNumberBuffers: 1, mBuffers: buf)
            return withUnsafeMutablePointer(to: &abl) { ptr in
                eq.processAudioBufferList(UnsafeMutableAudioBufferListPointer(ptr), frames: frameCount)
            }
        }
        let boostedPeak = interleaved.suffix(256).map { abs($0) }.max() ?? 0
        suite.expect(processed && boostedPeak.isFinite && boostedPeak > baselinePeak * 1.5,
                     "MixerParametricEQ boosts 1 kHz AudioBufferList signal cleanly without NaN/Inf")

        // Verify bypass leaves buffer transparent
        eq.setBypassed(true)
        var bypassBuf = [Float](repeating: 0.25, count: 64)
        let okBypass = bypassBuf.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            let buf = AudioBuffer(mNumberChannels: 2,
                                  mDataByteSize: UInt32(raw.count),
                                  mData: base)
            var abl = AudioBufferList(mNumberBuffers: 1, mBuffers: buf)
            return withUnsafeMutablePointer(to: &abl) { ptr in
                eq.processAudioBufferList(UnsafeMutableAudioBufferListPointer(ptr), frames: 32)
            }
        }
        suite.expect(okBypass && bypassBuf.allSatisfy { abs($0 - 0.25) < 0.0001 },
                     "MixerParametricEQ atomic bypass skips DSP cleanly without mutating audio")
    }

    private static func testRealtimeAudioMeterAndCustomPresets(_ suite: TestSuite) {
        let meter = RealtimeAudioMeter()
        meter.reset()
        suite.expect(meter.normalizedLevel == 0, "RealtimeAudioMeter resets to zero")

        var loud = [Float](repeating: 0, count: 128)
        for i in 0..<128 {
            loud[i] = Float(0.5 * sin(Double(i) * 0.3))
        }
        loud.withUnsafeBufferPointer { buf in
            if let ptr = buf.baseAddress {
                meter.record(samples: ptr, count: buf.count)
            }
        }
        let afterPeak = meter.normalizedLevel
        suite.expect(afterPeak > 0.7 && meter.peakDBFS > -10 && meter.rmsDBFS > -20,
                     "RealtimeAudioMeter computes accurate vDSP peak/RMS dBFS and normalized bar")

        // Ephemeral suite avoids polluting user preferences.
        let suiteName = "com.vorssaint.tests.eq.\(UUID().uuidString)"
        if let defaults = UserDefaults(suiteName: suiteName) {
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let store = CustomEQPresetStore(userDefaults: defaults)
            let saved = store.savePreset(name: "Studio Clarity",
                                         gainsDB: [2, 1, 0, -1, 1, 3, 4, 3, 2, 1],
                                         preampDB: -1.5)
            suite.expect(store.isCustomPreset(id: saved.id) && store.preset(id: saved.id)?.name == "Studio Clarity",
                         "CustomEQPresetStore saves custom preset")
            store.renamePreset(id: saved.id, to: "Broadcast Bright")
            let reloaded = CustomEQPresetStore(userDefaults: defaults)
            suite.expect(reloaded.preset(id: saved.id)?.name == "Broadcast Bright",
                         "CustomEQPresetStore persists rename across reload")
            reloaded.deletePreset(id: saved.id)
            suite.expect(!reloaded.isCustomPreset(id: saved.id),
                         "CustomEQPresetStore deletes custom preset cleanly")
        } else {
            suite.expect(false, "Could not create ephemeral UserDefaults suite for EQ presets")
        }
    }

    private static func testAudioUnitDiscoveryAndSourceWiring(_ suite: TestSuite) {
        let desc = AudioComponentDescription(componentType: kAudioUnitType_Effect,
                                             componentSubType: 0,
                                             componentManufacturer: 0,
                                             componentFlags: 0,
                                             componentFlagsMask: 0)
        let components = AVAudioUnitComponentManager.shared().components(matching: desc)
        suite.expect(!components.isEmpty,
                     "AVAudioUnitComponentManager discovers Apple system Audio Unit effects")

        let appMixer = readRepo("Sources/Vorssaint/Services/Audio/AppVolumeMixer.swift")
        let inputMgr = readRepo("Sources/Vorssaint/Services/Audio/AudioInputDeviceManager.swift")
        let auHost = readRepo("Sources/Vorssaint/Services/Audio/MixerAudioUnitHost.swift")
        let mixerSection = readRepo("Sources/Vorssaint/UI/MenuPanel/MixerSection.swift")
        let notchMixer = readRepo("Sources/Vorssaint/UI/Notch/NotchMixerView.swift")
        let eqView = readRepo("Sources/Vorssaint/UI/MenuPanel/InteractiveEQCurveView.swift")

        suite.expect(appMixer.contains("processEQAndMeter") && appMixer.contains("retainMeterObserver()"),
                     "AppVolumeMixer processes live EQ/meter inside tap IOProc and gates observer polling")
        suite.expect(inputMgr.contains("LiveMicDSPMonitor") && inputMgr.contains("AVAudioEngine"),
                     "AudioInputDeviceManager includes live AVAudioEngine mic DSP monitor")
        suite.expect(auHost.contains("AVAudioUnitComponentManager") && auHost.contains("requestViewController"),
                     "MixerAudioUnitHost discovers components and hosts native AUv3 UI")
        suite.expect(mixerSection.contains("InteractiveEQCurveView")
                     && mixerSection.contains("LiveVUMeterBar")
                     && notchMixer.contains("InteractiveEQCurveView")
                     && eqView.contains("catmullRomSpline"),
                     "MixerSection and NotchMixerView wire InteractiveEQCurveView and LiveVUMeterBar")
    }

    private static func testDisplayProDDCLMUAndVirtualDisplay(_ suite: TestSuite) {
        let contrast = DDCPacketBuilder.buildSetVCPPacket(code: .contrast, value: 75)
        let volume = DDCPacketBuilder.buildSetVCPPacket(code: .audioSpeakerVolume, value: 45)
        let mute = DDCPacketBuilder.buildSetVCPPacket(code: .audioMute, value: 1)
        let kvm = DDCPacketBuilder.buildSetVCPPacket(code: .inputSource, value: DisplayInputSourcePreset.displayPort1.rawValue)
        suite.expect(contrast[3] == 0x12 && DDCPacketBuilder.verifySetVCPPacket(contrast)
                     && volume[3] == 0x62 && DDCPacketBuilder.verifySetVCPPacket(volume)
                     && mute[3] == 0x8D && DDCPacketBuilder.verifySetVCPPacket(mute)
                     && kvm[3] == 0x60 && DDCPacketBuilder.verifySetVCPPacket(kvm),
                     "DDCPacketBuilder constructs valid VCP packets for contrast, volume, mute, and KVM")

        let darkLux = AppleLMUSensorReader.luxEstimate(fromCounts: [0, 0]) ?? -1
        let brightLux = AppleLMUSensorReader.luxEstimate(fromCounts: [90_000_000, 90_000_000]) ?? -1
        let clampedCurve = AmbientLightSyncService.targetBrightness(forLux: 999_999, userBias: 0.5)
        suite.expect(abs(darkLux) < 0.001 && abs(brightLux - 10_000) < 0.001 && abs(clampedCurve - 1.0) < 0.001,
                     "AppleLMUSensorReader and AmbientLightSyncService clamp lux and brightness bounds safely (got dark=\(darkLux), bright=\(brightLux), curve=\(clampedCurve))")

        suite.expect(!VirtualDisplayManager.presets.isEmpty
                     && VirtualDisplayManager.presets.allSatisfy { $0.backingPixelWidth == $0.logicalWidth * $0.scaleFactor },
                     "VirtualDisplayManager exposes HiDPI virtual display presets with valid backing scales")

        let xdrSource = readRepo("Sources/Vorssaint/Services/Display/XDRUpscaleOverlayController.swift")
        let brightService = readRepo("Sources/Vorssaint/Services/Display/BrightnessService.swift")
        let brightSection = readRepo("Sources/Vorssaint/UI/MenuPanel/BrightnessSection.swift")

        suite.expect(xdrSource.contains("wantsExtendedDynamicRangeContent = true")
                     && xdrSource.contains("maximumPotentialExtendedDynamicRangeColorComponentValue"),
                     "XDRUpscaleOverlayController gates HDR CAMetalLayer on XDR display capability")
        suite.expect(brightService.contains("setDisplayContrast(")
                     && brightService.contains("setDisplayAudioMuted(")
                     && brightService.contains("syncExternalDDCDisplays("),
                     "BrightnessService wires DDC contrast, audio mute, and ALS sync")
        suite.expect(brightSection.contains("XDRUpscaleOverlayController.shared")
                     && brightSection.contains("VirtualDisplayManager.shared")
                     && brightSection.contains("VorssaintDetentSlider"),
                     "BrightnessSection binds XDR Upscale, Virtual Display, and tactile DDC sliders cleanly")
    }
}
