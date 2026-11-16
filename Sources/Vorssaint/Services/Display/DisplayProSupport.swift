// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// MCCS / DDC/CI Virtual Control Panel codes for external monitors.
enum DDCControlCode: UInt8, CaseIterable, Sendable {
    case luminance = 0x10
    case contrast = 0x12
    case inputSource = 0x60
    case audioSpeakerVolume = 0x62
    case audioMute = 0x8D
}

/// Standard DisplayPort / HDMI / USB-C VCP input source values.
enum DisplayInputSourcePreset: UInt16, CaseIterable, Identifiable, Sendable {
    case displayPort1 = 0x0F
    case displayPort2 = 0x10
    case hdmi1 = 0x11
    case hdmi2 = 0x12
    case usbC = 0x1B

    var id: UInt16 { rawValue }

    var label: String {
        switch self {
        case .displayPort1: return "DisplayPort 1"
        case .displayPort2: return "DisplayPort 2"
        case .hdmi1: return "HDMI 1"
        case .hdmi2: return "HDMI 2"
        case .usbC: return "USB-C"
        }
    }
}

/// Constructs and validates DDC/CI 7-byte Set-VCP packets with XOR checksum (`0x6E ^ payload`).
enum DDCPacketBuilder {
    static let slaveWriteAddress: UInt8 = 0x6E
    static let hostSourceAddress: UInt8 = 0x51

    static func buildSetVCPPacket(code: DDCControlCode, value: UInt16) -> [UInt8] {
        let high = UInt8((value >> 8) & 0xFF)
        let low = UInt8(value & 0xFF)
        let body: [UInt8] = [hostSourceAddress, 0x84, 0x03, code.rawValue, high, low]
        let checksum = body.reduce(slaveWriteAddress, ^)
        return body + [checksum]
    }

    static func verifySetVCPPacket(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 7, bytes[0] == hostSourceAddress, bytes[1] == 0x84, bytes[2] == 0x03 else {
            return false
        }
        let expected = bytes.prefix(6).reduce(slaveWriteAddress, ^)
        return bytes[6] == expected
    }
}

/// Syncs external monitor brightness logarithmically with macOS ambient light lux readings.
final class AmbientLightSyncService: ObservableObject, @unchecked Sendable {
    static let shared = AmbientLightSyncService()

    @Published var isEnabled = false
    @Published var userBias: Double = 0
    @Published private(set) var lastLux: Double = 250
    @Published private(set) var targetNormalizedBrightness: Double = 0.65

    func update(lux: Double) {
        lastLux = max(0, lux)
        targetNormalizedBrightness = Self.targetBrightness(forLux: lux, userBias: userBias)
    }

    /// Maps 0...10,000 lux onto 0.05...1.0 brightness using a perceptual log curve plus user bias.
    static func targetBrightness(forLux lux: Double, userBias: Double = 0) -> Double {
        let clampedLux = max(0, min(lux, 10_000))
        // log10(lux + 1) maps 0 -> 0, 10 -> 1.04, 100 -> 2.0, 1000 -> 3.0, 10000 -> 4.0
        let normalizedLog = log10(clampedLux + 1.0) / 4.0
        let raw = 0.12 + 0.88 * normalizedLog + userBias
        return min(max(raw, 0.05), 1.0)
    }
}

/// User-space HiDPI / virtual display manager backed safely by runtime `CGVirtualDisplay` lookup.
final class VirtualDisplayManager: ObservableObject, @unchecked Sendable {
    static let shared = VirtualDisplayManager()

    struct ScaledPreset: Identifiable, Equatable, Sendable {
        let id: String
        let logicalWidth: Int
        let logicalHeight: Int
        let scaleFactor: Int

        var backingPixelWidth: Int { logicalWidth * scaleFactor }
        var backingPixelHeight: Int { logicalHeight * scaleFactor }
        var title: String { "\(logicalWidth)x\(logicalHeight) (\(scaleFactor)x HiDPI)" }
    }

    static let presets: [ScaledPreset] = [
        ScaledPreset(id: "1080p-hidpi", logicalWidth: 1920, logicalHeight: 1080, scaleFactor: 2),
        ScaledPreset(id: "1440p-hidpi", logicalWidth: 2560, logicalHeight: 1440, scaleFactor: 2),
        ScaledPreset(id: "3k-hidpi", logicalWidth: 3008, logicalHeight: 1692, scaleFactor: 2),
        ScaledPreset(id: "4k-hidpi", logicalWidth: 3840, logicalHeight: 2160, scaleFactor: 2),
    ]

    /// True on macOS releases exposing user-space `CGVirtualDisplay` without DriverKit entitlements.
    static var isRuntimeSupported: Bool {
        NSClassFromString("CGVirtualDisplay") != nil
    }

    @Published private(set) var activePresetIDs: [String] = []

    func togglePreset(_ preset: ScaledPreset) {
        if let idx = activePresetIDs.firstIndex(of: preset.id) {
            activePresetIDs.remove(at: idx)
        } else {
            activePresetIDs.append(preset.id)
        }
    }
}
