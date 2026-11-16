// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import CoreGraphics
import Foundation
import IOKit
import ObjectiveC.runtime

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

/// Reads the built-in Apple ambient light sensor via `AppleLMUController`.
/// Safely returns `nil` on desktop Macs, clamshell setups without ALS, or VMs.
enum AppleLMUSensorReader {
    private static let serviceName = "AppleLMUController"
    private static let getSensorReadingSelector: UInt32 = 0

    static var isAvailable: Bool {
        guard let matching = IOServiceMatching(serviceName) else { return false }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else { return false }
        IOObjectRelease(service)
        return true
    }

    static func readNormalizedLux() -> Double? {
        guard let matching = IOServiceMatching(serviceName) else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        var connect: io_connect_t = IO_OBJECT_NULL
        guard IOServiceOpen(service, mach_task_self_, 0, &connect) == KERN_SUCCESS,
              connect != IO_OBJECT_NULL else {
            return nil
        }
        defer { IOServiceClose(connect) }

        var values = [UInt64](repeating: 0, count: 2)
        var outputCount = UInt32(values.count)
        let status = IOConnectCallScalarMethod(connect, getSensorReadingSelector,
                                               nil, 0, &values, &outputCount)
        guard status == KERN_SUCCESS, outputCount > 0 else { return nil }

        return luxEstimate(fromCounts: Array(values.prefix(Int(outputCount))))
    }

    static func luxEstimate(fromCounts counts: [UInt64]) -> Double? {
        guard !counts.isEmpty else { return nil }
        let average = counts.map { Double($0) }.reduce(0, +) / Double(counts.count)
        // AppleLMUController raw channel counts span 0...~67,092,480.
        let estimatedLux = average / 6_709.248
        return min(max(estimatedLux, 0), 10_000)
    }
}

/// Syncs external monitor brightness logarithmically with macOS ambient light lux readings.
final class AmbientLightSyncService: ObservableObject, @unchecked Sendable {
    static let shared = AmbientLightSyncService()
    static let pollInterval: TimeInterval = 2.5
    static let pollTolerance: TimeInterval = 0.4

    @Published var isEnabled = false {
        didSet {
            if oldValue != isEnabled {
                syncPollingState()
            }
        }
    }
    @Published var userBias: Double = 0 {
        didSet {
            if oldValue != userBias {
                recomputeTargetForCurrentLux()
            }
        }
    }
    @Published private(set) var lastLux: Double = 250
    @Published private(set) var targetNormalizedBrightness: Double = 0.65
    @Published private(set) var hasAmbientSensor: Bool = AppleLMUSensorReader.isAvailable

    var onTargetBrightnessChanged: ((Double) -> Void)?

    private var pollTimer: Timer?
    private var hasDispatchedSinceEnable = false

    deinit {
        pollTimer?.invalidate()
    }

    func update(lux: Double) {
        let sanitizedLux = max(0, lux)
        let previousTarget = targetNormalizedBrightness
        let nextTarget = Self.targetBrightness(forLux: sanitizedLux, userBias: userBias)
        lastLux = sanitizedLux
        targetNormalizedBrightness = nextTarget
        if isEnabled && (!hasDispatchedSinceEnable || abs(nextTarget - previousTarget) > 0.002) {
            hasDispatchedSinceEnable = true
            onTargetBrightnessChanged?(nextTarget)
        }
    }

    func pollNow() {
        guard isEnabled else { return }
        if let lux = AppleLMUSensorReader.readNormalizedLux() {
            if !hasAmbientSensor { hasAmbientSensor = true }
            update(lux: lux)
        } else {
            let available = AppleLMUSensorReader.isAvailable
            if hasAmbientSensor != available { hasAmbientSensor = available }
        }
    }

    /// Maps 0...10,000 lux onto 0.05...1.0 brightness using a perceptual log curve plus user bias.
    static func targetBrightness(forLux lux: Double, userBias: Double = 0) -> Double {
        let clampedLux = max(0, min(lux, 10_000))
        // log10(lux + 1) maps 0 -> 0, 10 -> 1.04, 100 -> 2.0, 1000 -> 3.0, 10000 -> 4.0
        let normalizedLog = log10(clampedLux + 1.0) / 4.0
        let raw = 0.12 + 0.88 * normalizedLog + userBias
        return min(max(raw, 0.05), 1.0)
    }

    private func recomputeTargetForCurrentLux() {
        let previousTarget = targetNormalizedBrightness
        let nextTarget = Self.targetBrightness(forLux: lastLux, userBias: userBias)
        targetNormalizedBrightness = nextTarget
        if isEnabled && (!hasDispatchedSinceEnable || abs(nextTarget - previousTarget) > 0.002) {
            hasDispatchedSinceEnable = true
            onTargetBrightnessChanged?(nextTarget)
        }
    }

    private func syncPollingState() {
        let apply = { [weak self] in
            guard let self else { return }
            self.pollTimer?.invalidate()
            self.pollTimer = nil
            guard self.isEnabled else {
                self.hasDispatchedSinceEnable = false
                return
            }
            self.hasDispatchedSinceEnable = false
            self.pollNow()
            let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
                guard let self, self.isEnabled else {
                    self?.stopTimer()
                    return
                }
                self.pollNow()
            }
            timer.tolerance = Self.pollTolerance
            RunLoop.main.add(timer, forMode: .common)
            self.pollTimer = timer
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private func stopTimer() {
        pollTimer?.invalidate()
        pollTimer = nil
        hasDispatchedSinceEnable = false
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
    @Published private(set) var virtualDisplayIDs: [String: CGDirectDisplayID] = [:]

    private var virtualDisplays: [String: AnyObject] = [:]
    private let displayQueue = DispatchQueue(label: "com.vorssaint.virtualdisplay")
    private let stateLock = NSLock()

    deinit {
        stateLock.lock()
        let removed = Array(virtualDisplays.values)
        virtualDisplays.removeAll()
        stateLock.unlock()
        _ = removed
    }

    func togglePreset(_ preset: ScaledPreset) {
        if activePresetIDs.contains(preset.id) {
            deactivatePreset(preset)
        } else {
            activatePreset(preset)
        }
    }

    func activatePreset(_ preset: ScaledPreset) {
        if !activePresetIDs.contains(preset.id) {
            activePresetIDs.append(preset.id)
        }
        stateLock.lock()
        let existingDisplay = virtualDisplays[preset.id]
        stateLock.unlock()

        guard existingDisplay == nil else { return }
        if let created = createRuntimeVirtualDisplay(for: preset) {
            let stillActive = activePresetIDs.contains(preset.id)
            if stillActive {
                stateLock.lock()
                virtualDisplays[preset.id] = created.display
                stateLock.unlock()
                virtualDisplayIDs[preset.id] = created.id
            }
        }
    }

    func deactivatePreset(_ preset: ScaledPreset) {
        activePresetIDs.removeAll { $0 == preset.id }
        virtualDisplayIDs.removeValue(forKey: preset.id)
        stateLock.lock()
        let removed = virtualDisplays.removeValue(forKey: preset.id)
        stateLock.unlock()
        _ = removed
    }

    func deactivateAll() {
        activePresetIDs.removeAll()
        virtualDisplayIDs.removeAll()
        stateLock.lock()
        let removed = Array(virtualDisplays.values)
        virtualDisplays.removeAll()
        stateLock.unlock()
        _ = removed
    }

    private func createRuntimeVirtualDisplay(for preset: ScaledPreset) -> (display: AnyObject, id: CGDirectDisplayID)? {
        guard let descriptorClass = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
              let modeClass = NSClassFromString("CGVirtualDisplayMode"),
              let settingsClass = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type,
              let displayClass = NSClassFromString("CGVirtualDisplay") else {
            return nil
        }

        let descriptor = descriptorClass.init()
        let presetIndex = Self.presets.firstIndex(of: preset) ?? 0
        setIfResponds(descriptor, key: "name", value: "Vorssaint Virtual \(preset.logicalWidth)x\(preset.logicalHeight)")
        setIfResponds(descriptor, key: "maxPixelsWide", value: NSNumber(value: UInt32(preset.backingPixelWidth)))
        setIfResponds(descriptor, key: "maxPixelsHigh", value: NSNumber(value: UInt32(preset.backingPixelHeight)))
        setIfResponds(descriptor, key: "sizeInMillimeters", value: NSValue(size: CGSize(
            width: Double(preset.logicalWidth) * 0.23,
            height: Double(preset.logicalHeight) * 0.23
        )))
        setIfResponds(descriptor, key: "vendorID", value: NSNumber(value: UInt32(0x5653)))
        setIfResponds(descriptor, key: "productID", value: NSNumber(value: UInt32(0x4844 + presetIndex)))
        setIfResponds(descriptor, key: "serialNum", value: NSNumber(value: UInt32(presetIndex + 1)))
        setIfResponds(descriptor, key: "queue", value: displayQueue)

        guard let mode = allocateVirtualDisplayMode(
            modeClass: modeClass,
            width: UInt32(preset.logicalWidth),
            height: UInt32(preset.logicalHeight),
            refreshRate: 60.0
        ) else {
            return nil
        }

        let settings = settingsClass.init()
        setIfResponds(settings, key: "hiDPI", value: NSNumber(value: UInt32(preset.scaleFactor > 1 ? 1 : 0)))
        setIfResponds(settings, key: "modes", value: [mode] as NSArray)

        guard let display = allocateVirtualDisplay(displayClass: displayClass, descriptor: descriptor) else {
            return nil
        }

        let applySel = NSSelectorFromString("applySettings:")
        typealias ApplySettingsFn = @convention(c) (AnyObject, Selector, AnyObject) -> ObjCBool
        guard let applyMethod = class_getInstanceMethod(displayClass, applySel) else {
            return nil
        }
        let applyFn = unsafeBitCast(method_getImplementation(applyMethod), to: ApplySettingsFn.self)
        guard applyFn(display, applySel, settings).boolValue else {
            return nil
        }

        let idSel = NSSelectorFromString("displayID")
        typealias DisplayIDFn = @convention(c) (AnyObject, Selector) -> UInt32
        guard let idMethod = class_getInstanceMethod(displayClass, idSel) else {
            return nil
        }
        let idFn = unsafeBitCast(method_getImplementation(idMethod), to: DisplayIDFn.self)
        let displayID = idFn(display, idSel)
        guard displayID != kCGNullDirectDisplay else {
            return nil
        }
        return (display, displayID)
    }

    private func setIfResponds(_ object: NSObject, key: String, value: Any) {
        let capitalized = key.prefix(1).uppercased() + key.dropFirst()
        let setter = NSSelectorFromString("set\(capitalized):")
        guard object.responds(to: setter) else { return }
        object.setValue(value, forKey: key)
    }

    private func allocateVirtualDisplayMode(
        modeClass: AnyClass,
        width: UInt32,
        height: UInt32,
        refreshRate: Double
    ) -> AnyObject? {
        let allocSel = NSSelectorFromString("alloc")
        let initSel = NSSelectorFromString("initWithWidth:height:refreshRate:")
        guard let metaclass = object_getClass(modeClass),
              let allocMethod = class_getClassMethod(modeClass, allocSel),
              let initMethod = class_getInstanceMethod(modeClass, initSel) else {
            return nil
        }
        _ = metaclass
        typealias AllocFn = @convention(c) (AnyClass, Selector) -> UnsafeMutableRawPointer?
        typealias InitFn = @convention(c) (UnsafeMutableRawPointer, Selector, UInt32, UInt32, Double) -> Unmanaged<AnyObject>?
        let allocFn = unsafeBitCast(method_getImplementation(allocMethod), to: AllocFn.self)
        let initFn = unsafeBitCast(method_getImplementation(initMethod), to: InitFn.self)
        guard let rawInstance = allocFn(modeClass, allocSel),
              let initialized = initFn(rawInstance, initSel, width, height, refreshRate) else {
            return nil
        }
        return initialized.takeRetainedValue()
    }

    private func allocateVirtualDisplay(displayClass: AnyClass, descriptor: NSObject) -> AnyObject? {
        let allocSel = NSSelectorFromString("alloc")
        let initSel = NSSelectorFromString("initWithDescriptor:")
        guard let allocMethod = class_getClassMethod(displayClass, allocSel),
              let initMethod = class_getInstanceMethod(displayClass, initSel) else {
            return nil
        }
        typealias AllocFn = @convention(c) (AnyClass, Selector) -> UnsafeMutableRawPointer?
        typealias InitFn = @convention(c) (UnsafeMutableRawPointer, Selector, AnyObject) -> Unmanaged<AnyObject>?
        let allocFn = unsafeBitCast(method_getImplementation(allocMethod), to: AllocFn.self)
        let initFn = unsafeBitCast(method_getImplementation(initMethod), to: InitFn.self)
        guard let rawInstance = allocFn(displayClass, allocSel),
              let initialized = initFn(rawInstance, initSel, descriptor) else {
            return nil
        }
        return initialized.takeRetainedValue()
    }
}
