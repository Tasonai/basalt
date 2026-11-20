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
    case powerMode = 0xD6
}

/// VESA MCCS VCP `0xD6` power states for external monitors.
enum DDCPowerState: UInt16, Sendable, CaseIterable {
    case on = 0x01
    case standby = 0x04
    case off = 0x05
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
        setVCPValuePacket(code: code.rawValue, value: value)
    }

    static func setVCPValuePacket(code: UInt8, value: UInt16) -> [UInt8] {
        let high = UInt8((value >> 8) & 0xFF)
        let low = UInt8(value & 0xFF)
        let body: [UInt8] = [hostSourceAddress, 0x84, 0x03, code, high, low]
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

/// Reads the built-in Apple ambient light sensor via `AppleLMUController`,
/// falling back on T2 Intel and Apple Silicon Macs to the HID ambient light
/// sensor service (`PrimaryUsagePage` 0x20 / 0x41 or 0xFF00 / 4).
/// Safely returns `nil` on desktop Macs, clamshell setups without ALS, or VMs.
enum AppleLMUSensorReader {
    private static let serviceName = "AppleLMUController"
    private static let getSensorReadingSelector: UInt32 = 0

    private enum HIDAmbientLightBridge {
        typealias CreateClientFn = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
        typealias SetMatchingFn = @convention(c) (CFTypeRef, CFDictionary) -> Void
        typealias CopyServicesFn = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
        typealias CopyEventFn = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
        typealias GetFloatValueFn = @convention(c) (CFTypeRef, UInt32) -> Double
        typealias GetIntegerValueFn = @convention(c) (CFTypeRef, UInt32) -> Int64
        typealias CopyPropertyFn = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
        typealias SetPropertyFn = @convention(c) (CFTypeRef, CFString, CFTypeRef) -> Bool

        private static let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
        static let createClient: CreateClientFn? = symbol("IOHIDEventSystemClientCreate")
        static let setMatching: SetMatchingFn? = symbol("IOHIDEventSystemClientSetMatching")
        static let copyServices: CopyServicesFn? = symbol("IOHIDEventSystemClientCopyServices")
        static let copyEvent: CopyEventFn? = symbol("IOHIDServiceClientCopyEvent")
        static let getFloatValue: GetFloatValueFn? = symbol("IOHIDEventGetFloatValue")
        static let getIntegerValue: GetIntegerValueFn? = symbol("IOHIDEventGetIntegerValue")
        static let copyProperty: CopyPropertyFn? = symbol("IOHIDServiceClientCopyProperty")
        static let setProperty: SetPropertyFn? = symbol("IOHIDServiceClientSetProperty")

        private static let usagePairs: [(page: Int, usage: Int)] = [
            (0x20, 0x41),   // kHIDPage_Sensor / kHIDUsage_Snsr_Light_AmbientLight (T2 Intel Macs)
            (0xFF00, 0x04), // kHIDPage_AppleVendor / Apple ALS (Apple Silicon / legacy HID)
        ]

        private static let activeReportIntervalMicroseconds: Int64 = 500_000
        private static let sessionLock = NSLock()
        private static var sessionClient: CFTypeRef?
        private static var sessionServices: [AnyObject] = []
        private static var sessionRefCount = 0

        private static func symbol<T>(_ name: String) -> T? {
            guard let handle, let ptr = dlsym(handle, name) else { return nil }
            return unsafeBitCast(ptr, to: T.self)
        }

        private static func matchedServices(using client: CFTypeRef) -> [AnyObject] {
            guard let setMatching, let copyServices else { return [] }
            for pair in usagePairs {
                let matching: NSDictionary = [
                    "PrimaryUsagePage": pair.page,
                    "PrimaryUsage": pair.usage,
                ]
                setMatching(client, matching)
                if let services = copyServices(client)?.takeRetainedValue() as? [AnyObject],
                   !services.isEmpty {
                    return services
                }
            }
            return []
        }

        /// Opens a persistent HID ALS client and requests a non-zero
        /// `ReportInterval` while Ambient Light Sync is active, so T2 Intel
        /// ALS sensors report live lux even when macOS Auto-Brightness is idle.
        static func beginSession() {
            sessionLock.lock()
            defer { sessionLock.unlock() }
            sessionRefCount += 1
            guard sessionClient == nil,
                  let createClient,
                  let client = createClient(kCFAllocatorDefault)?.takeRetainedValue() else {
                return
            }
            let services = matchedServices(using: client)
            if let setProperty {
                let interval = NSNumber(value: activeReportIntervalMicroseconds)
                for service in services {
                    _ = setProperty(service, "ReportInterval" as CFString, interval)
                }
            }
            sessionClient = client
            sessionServices = services
        }

        /// Releases the persistent HID ALS client and resets `ReportInterval`
        /// when Ambient Light Sync stops.
        static func endSession() {
            sessionLock.lock()
            defer { sessionLock.unlock() }
            guard sessionRefCount > 0 else { return }
            sessionRefCount -= 1
            guard sessionRefCount == 0 else { return }
            if let setProperty {
                let zero = NSNumber(value: 0)
                for service in sessionServices {
                    _ = setProperty(service, "ReportInterval" as CFString, zero)
                }
            }
            sessionServices.removeAll()
            sessionClient = nil
        }

        static func hasSensor() -> Bool {
            sessionLock.lock()
            if !sessionServices.isEmpty {
                sessionLock.unlock()
                return true
            }
            sessionLock.unlock()
            guard let createClient,
                  let client = createClient(kCFAllocatorDefault)?.takeRetainedValue() else {
                return false
            }
            return !matchedServices(using: client).isEmpty
        }

        static func readLux() -> Double? {
            guard let copyEvent, let getFloatValue else { return nil }
            let services: [AnyObject]
            let retainedClient: CFTypeRef
            sessionLock.lock()
            if let activeClient = sessionClient {
                if sessionServices.isEmpty {
                    sessionServices = matchedServices(using: activeClient)
                    if let setProperty {
                        let interval = NSNumber(value: activeReportIntervalMicroseconds)
                        for service in sessionServices {
                            _ = setProperty(service, "ReportInterval" as CFString, interval)
                        }
                    }
                }
                services = sessionServices
                retainedClient = activeClient
                sessionLock.unlock()
            } else {
                sessionLock.unlock()
                guard let createClient,
                      let client = createClient(kCFAllocatorDefault)?.takeRetainedValue() else {
                    return nil
                }
                retainedClient = client
                services = matchedServices(using: client)
            }

            // kIOHIDEventTypeAmbientLightSensor = 12
            // field 0 = Level, fields 1...4 = RawChannel0...3
            let eventType: Int64 = 12
            let levelField: UInt32 = 12 << 16
            return withExtendedLifetime(retainedClient) {
                for service in services {
                    guard let event = copyEvent(service, eventType, 0, 0)?.takeRetainedValue() else {
                        continue
                    }
                    let lux = getFloatValue(event, levelField)
                    var rawChannels: [Int64] = []
                    if let getIntegerValue {
                        rawChannels = (1...4).map { idx in
                            getIntegerValue(event, (12 << 16) | UInt32(idx))
                        }
                    }
                    let reportInterval = (copyProperty?(service, "ReportInterval" as CFString)?.takeRetainedValue() as? NSNumber)?.int64Value
                    if let validLux = AppleLMUSensorReader.sanitizedHIDLux(
                        level: lux,
                        rawChannels: rawChannels,
                        reportInterval: reportInterval
                    ) {
                        return validLux
                    }
                }
                return nil
            }
        }
    }

    static func beginHIDSession() {
        HIDAmbientLightBridge.beginSession()
    }

    static func endHIDSession() {
        HIDAmbientLightBridge.endSession()
    }

    /// Rejects unpopulated/all-zero T2 HID ALS events (`Level == 0` with every
    /// raw photodiode channel `CH0...3 == 0`), preventing external DDC monitors
    /// from being slammed to 12% brightness when the T2 bridge does not feed
    /// live sensor readings to userspace.
    static func sanitizedHIDLux(level: Double, rawChannels: [Int64], reportInterval: Int64?) -> Double? {
        guard level.isFinite, level >= 0 else { return nil }
        let allChannelsZero = rawChannels.allSatisfy { $0 == 0 }
        if level == 0 && allChannelsZero {
            return nil
        }
        return min(max(level, 0), 10_000)
    }

    static var isAvailable: Bool {
        if let matching = IOServiceMatching(serviceName) {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
            if service != IO_OBJECT_NULL {
                IOObjectRelease(service)
                return true
            }
        }
        return HIDAmbientLightBridge.hasSensor()
    }

    static func readNormalizedLux() -> Double? {
        if let lmuLux = readLMULux() {
            return lmuLux
        }
        return HIDAmbientLightBridge.readLux()
    }

    private static func readLMULux() -> Double? {
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
    private var hidSessionActive = false

    deinit {
        pollTimer?.invalidate()
        if hidSessionActive {
            AppleLMUSensorReader.endHIDSession()
        }
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
                if self.hidSessionActive {
                    self.hidSessionActive = false
                    AppleLMUSensorReader.endHIDSession()
                }
                return
            }
            if !self.hidSessionActive {
                self.hidSessionActive = true
                AppleLMUSensorReader.beginHIDSession()
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
        if hidSessionActive {
            hidSessionActive = false
            AppleLMUSensorReader.endHIDSession()
        }
    }
}

/// Computes a smooth 24-hour circadian solar luminance curve for external monitors.
struct SolarSyncCurve: Sendable {
    static func targetLuminance(hour: Double, minLevel: Double = 0.22, maxLevel: Double = 0.92) -> Double {
        let safeMinRaw = minLevel.isFinite ? minLevel : 0.22
        let safeMaxRaw = maxLevel.isFinite ? maxLevel : 0.92
        let clampedMin = min(max(safeMinRaw, 0.05), 1.0)
        let clampedMax = min(max(safeMaxRaw, clampedMin), 1.0)

        guard hour.isFinite else { return clampedMin }

        var normalizedHour = hour.truncatingRemainder(dividingBy: 24.0)
        if normalizedHour < 0 {
            normalizedHour += 24.0
        }
        if normalizedHour >= 24.0 {
            normalizedHour -= 24.0
        }

        guard normalizedHour >= 6.0 && normalizedHour < 22.0 else {
            return clampedMin
        }

        // Smooth raised-cosine solar elevation from 06:00 (0) through 14:00 (1) to 22:00 (0).
        let dayProgress = (normalizedHour - 6.0) / 16.0
        let solarElevation = 0.5 * (1.0 - cos(2.0 * Double.pi * dayProgress))
        let target = clampedMin + (clampedMax - clampedMin) * solarElevation
        return min(max(target, clampedMin), clampedMax)
    }
}

/// Standard refresh rate presets for virtual HiDPI hardware mirror targets.
enum CustomRefreshRatePreset: Int, CaseIterable, Identifiable, Sendable {
    case hz60 = 60
    case hz75 = 75
    case hz100 = 100
    case hz120 = 120
    case hz144 = 144

    var id: Int { rawValue }
    var label: String { "\(rawValue) Hz" }
}

/// Tracks the 15-second confirmation window before a hardware mirror binding auto-reverts.
struct MirrorConfirmationGate: Equatable, Sendable {
    private(set) var isPending: Bool = false
    private(set) var targetDisplayID: CGDirectDisplayID?
    private(set) var virtualDisplayID: CGDirectDisplayID?
    private(set) var deadline: Date?

    mutating func begin(
        targetDisplayID: CGDirectDisplayID,
        virtualDisplayID: CGDirectDisplayID,
        now: Date = Date(),
        timeout: TimeInterval = 15
    ) {
        let safeTimeout = timeout.isFinite ? max(0, timeout) : 15
        isPending = true
        self.targetDisplayID = targetDisplayID
        self.virtualDisplayID = virtualDisplayID
        deadline = now.addingTimeInterval(safeTimeout)
    }

    mutating func confirm() {
        isPending = false
        deadline = nil
    }

    func shouldAutoRevert(now: Date = Date()) -> Bool {
        guard isPending, let deadline else { return false }
        return now >= deadline
    }

    func remainingSeconds(now: Date = Date()) -> Int {
        guard isPending, let deadline else { return 0 }
        let remaining = deadline.timeIntervalSince(now)
        guard remaining > 0 else { return 0 }
        return min(max(Int(ceil(remaining)), 0), 15)
    }

    mutating func cancel() {
        isPending = false
        targetDisplayID = nil
        virtualDisplayID = nil
        deadline = nil
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
        ScaledPreset(id: "uw1080-hidpi", logicalWidth: 2560, logicalHeight: 1080, scaleFactor: 2),
        ScaledPreset(id: "3k-hidpi", logicalWidth: 3008, logicalHeight: 1692, scaleFactor: 2),
        ScaledPreset(id: "uwqhd-hidpi", logicalWidth: 3440, logicalHeight: 1440, scaleFactor: 2),
        ScaledPreset(id: "4k-hidpi", logicalWidth: 3840, logicalHeight: 2160, scaleFactor: 2),
    ]

    /// True on macOS releases exposing user-space `CGVirtualDisplay` without DriverKit entitlements.
    static var isRuntimeSupported: Bool {
        NSClassFromString("CGVirtualDisplay") != nil
    }

    @Published private(set) var activePresetIDs: [String] = []
    @Published private(set) var virtualDisplayIDs: [String: CGDirectDisplayID] = [:]
    @Published private(set) var mirrorGate = MirrorConfirmationGate()
    @Published private(set) var mirrorConfirmationRemainingSeconds: Int = 0
    @Published private(set) var mirroredPhysicalDisplayID: CGDirectDisplayID?
    @Published var selectedMirrorRefreshHz: Int = CustomRefreshRatePreset.hz60.rawValue

    private struct VirtualDisplaySpec: Equatable {
        let name: String
        let logicalWidth: Int
        let logicalHeight: Int
        let scaleFactor: Int
        let refreshRate: Double
        let productID: UInt32
        let serialNum: UInt32
        let sizeInMillimeters: CGSize?

        var backingPixelWidth: Int { logicalWidth * scaleFactor }
        var backingPixelHeight: Int { logicalHeight * scaleFactor }
    }

    private var virtualDisplays: [String: AnyObject] = [:]
    private var mirrorVirtualDisplay: AnyObject?
    private var mirrorVirtualDisplayID: CGDirectDisplayID?
    private var mirrorVirtualSpec: VirtualDisplaySpec?
    private var mirrorTimer: Timer?
    private let displayQueue = DispatchQueue(label: "com.vorssaint.virtualdisplay")
    private let stateLock = NSLock()

    deinit {
        mirrorTimer?.invalidate()
        mirrorTimer = nil
        stateLock.lock()
        let removed = Array(virtualDisplays.values)
        let removedMirror = mirrorVirtualDisplay
        virtualDisplays.removeAll()
        mirrorVirtualDisplay = nil
        mirrorVirtualDisplayID = nil
        mirrorVirtualSpec = nil
        stateLock.unlock()
        _ = removed
        _ = removedMirror
    }

    func togglePreset(_ preset: ScaledPreset) {
        if activePresetIDs.contains(preset.id) {
            deactivatePreset(preset)
        } else {
            activatePreset(preset)
        }
    }

    func activatePreset(_ preset: ScaledPreset) {
        stateLock.lock()
        let existingDisplay = virtualDisplays[preset.id]
        stateLock.unlock()

        guard existingDisplay == nil else {
            if !activePresetIDs.contains(preset.id) {
                activePresetIDs.append(preset.id)
            }
            return
        }
        let presetIndex = Self.presets.firstIndex(of: preset) ?? 0
        let spec = VirtualDisplaySpec(
            name: "Basalt Virtual \(preset.logicalWidth)x\(preset.logicalHeight)",
            logicalWidth: preset.logicalWidth,
            logicalHeight: preset.logicalHeight,
            scaleFactor: preset.scaleFactor,
            refreshRate: 60.0,
            productID: UInt32(0x4844 + presetIndex),
            serialNum: UInt32(presetIndex + 1),
            sizeInMillimeters: nil
        )
        guard let created = createRuntimeVirtualDisplay(spec: spec) else {
            activePresetIDs.removeAll { $0 == preset.id }
            virtualDisplayIDs.removeValue(forKey: preset.id)
            return
        }
        if !activePresetIDs.contains(preset.id) {
            activePresetIDs.append(preset.id)
        }
        stateLock.lock()
        virtualDisplays[preset.id] = created.display
        stateLock.unlock()
        virtualDisplayIDs[preset.id] = created.id
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
        if mirroredPhysicalDisplayID != nil || mirrorGate.isPending || mirrorVirtualDisplayID != nil {
            revertMirrorBinding()
        }
        activePresetIDs.removeAll()
        virtualDisplayIDs.removeAll()
        stateLock.lock()
        let removed = Array(virtualDisplays.values)
        virtualDisplays.removeAll()
        stateLock.unlock()
        _ = removed
    }

    @discardableResult
    func bindHardwareMirror(physicalDisplayID: CGDirectDisplayID, refreshRateHz: Double) -> Bool {
        guard Self.isRuntimeSupported else { return false }
        guard physicalDisplayID != kCGNullDirectDisplay else { return false }
        guard refreshRateHz.isFinite, refreshRateHz > 0 else { return false }
        guard !virtualDisplayIDs.values.contains(physicalDisplayID) else { return false }
        guard isOnlineDisplay(physicalDisplayID) else { return false }

        let sanitizedHz = min(max(refreshRateHz, 24.0), 240.0)

        stateLock.lock()
        let existingMirrorDisplay = mirrorVirtualDisplay
        let existingMirrorID = mirrorVirtualDisplayID
        let existingMirrorSpec = mirrorVirtualSpec
        stateLock.unlock()

        guard physicalDisplayID != existingMirrorID else { return false }

        let targetSpec: VirtualDisplaySpec
        let targetVirtual: (display: AnyObject, id: CGDirectDisplayID)
        let createdNewVirtual: Bool

        if mirroredPhysicalDisplayID == physicalDisplayID,
           let existingMirrorDisplay,
           let existingMirrorID,
           let existingMirrorSpec,
           isOnlineDisplay(existingMirrorID),
           abs(existingMirrorSpec.refreshRate - sanitizedHz) < 0.01 {
            targetSpec = existingMirrorSpec
            targetVirtual = (existingMirrorDisplay, existingMirrorID)
            createdNewVirtual = false
        } else {
            if mirroredPhysicalDisplayID != nil || mirrorGate.isPending || existingMirrorDisplay != nil {
                revertMirrorBinding()
            }
            guard let resolvedSpec = makeMirrorVirtualSpec(for: physicalDisplayID, refreshRate: sanitizedHz),
                  let created = createRuntimeVirtualDisplay(spec: resolvedSpec) else {
                return false
            }
            targetSpec = resolvedSpec
            targetVirtual = created
            createdNewVirtual = true
        }

        guard targetVirtual.id != kCGNullDirectDisplay,
              targetVirtual.id != physicalDisplayID,
              configureMirror(display: physicalDisplayID, master: targetVirtual.id) else {
            if !createdNewVirtual {
                revertMirrorBinding()
            } else {
                _ = targetVirtual.display
            }
            return false
        }

        stateLock.lock()
        mirrorVirtualDisplay = targetVirtual.display
        mirrorVirtualDisplayID = targetVirtual.id
        mirrorVirtualSpec = targetSpec
        stateLock.unlock()

        let roundedHz = Int(sanitizedHz.rounded())
        if selectedMirrorRefreshHz != roundedHz {
            selectedMirrorRefreshHz = roundedHz
        }
        mirroredPhysicalDisplayID = physicalDisplayID

        let now = Date()
        mirrorGate.begin(targetDisplayID: physicalDisplayID, virtualDisplayID: targetVirtual.id, now: now, timeout: 15)
        mirrorConfirmationRemainingSeconds = mirrorGate.remainingSeconds(now: now)
        startMirrorCountdownTimer()
        return true
    }

    func confirmMirrorBinding() {
        stopMirrorCountdownTimer()
        mirrorGate.confirm()
        mirrorConfirmationRemainingSeconds = 0
    }

    func revertMirrorBinding() {
        stopMirrorCountdownTimer()
        let physicalID = mirroredPhysicalDisplayID ?? mirrorGate.targetDisplayID
        if let physicalID, physicalID != kCGNullDirectDisplay {
            _ = configureMirror(display: physicalID, master: kCGNullDirectDisplay)
        }
        mirrorGate.cancel()
        mirrorConfirmationRemainingSeconds = 0
        mirroredPhysicalDisplayID = nil
        clearMirrorVirtualDisplay()
    }

    private func isOnlineDisplay(_ displayID: CGDirectDisplayID) -> Bool {
        var count: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        guard CGGetOnlineDisplayList(UInt32(displays.count), &displays, &count) == .success else {
            return CGDisplayIsOnline(displayID) != 0
        }
        return displays.prefix(Int(count)).contains(displayID)
    }

    private func makeMirrorVirtualSpec(for physicalDisplayID: CGDirectDisplayID, refreshRate: Double) -> VirtualDisplaySpec? {
        let currentMode = CGDisplayCopyDisplayMode(physicalDisplayID)
        let width = currentMode?.width ?? CGDisplayPixelsWide(physicalDisplayID)
        let height = currentMode?.height ?? CGDisplayPixelsHigh(physicalDisplayID)
        guard width > 0, height > 0 else { return nil }

        let scaleFactor = (width * 2 <= 7680 && height * 2 <= 4320) ? 2 : 1
        let screenSize = CGDisplayScreenSize(physicalDisplayID)
        let sizeMM = (screenSize.width > 0 && screenSize.height > 0) ? screenSize : nil

        return VirtualDisplaySpec(
            name: "Basalt HiDPI Mirror \(width)x\(height)",
            logicalWidth: width,
            logicalHeight: height,
            scaleFactor: scaleFactor,
            refreshRate: refreshRate,
            productID: 0x4850,
            serialNum: UInt32(truncatingIfNeeded: physicalDisplayID),
            sizeInMillimeters: sizeMM
        )
    }

    private func configureMirror(display: CGDirectDisplayID, master: CGDirectDisplayID) -> Bool {
        guard display != kCGNullDirectDisplay, display != master else { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else {
            return false
        }
        guard CGConfigureDisplayMirrorOfDisplay(config, display, master) == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return CGCompleteDisplayConfiguration(config, .forSession) == .success
    }

    private func clearMirrorVirtualDisplay() {
        stateLock.lock()
        let removed = mirrorVirtualDisplay
        mirrorVirtualDisplay = nil
        mirrorVirtualDisplayID = nil
        mirrorVirtualSpec = nil
        stateLock.unlock()
        _ = removed
    }

    private func startMirrorCountdownTimer() {
        let schedule: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            self.mirrorTimer?.invalidate()
            self.mirrorTimer = nil
            guard self.mirrorGate.isPending else { return }
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self else { return }
                let now = Date()
                guard self.mirrorGate.isPending else {
                    self.stopMirrorCountdownTimer()
                    self.mirrorConfirmationRemainingSeconds = 0
                    return
                }
                if self.mirrorGate.shouldAutoRevert(now: now) {
                    self.revertMirrorBinding()
                    return
                }
                let remaining = self.mirrorGate.remainingSeconds(now: now)
                if self.mirrorConfirmationRemainingSeconds != remaining {
                    self.mirrorConfirmationRemainingSeconds = remaining
                }
            }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common)
            self.mirrorTimer = timer
        }
        if Thread.isMainThread {
            schedule()
        } else {
            DispatchQueue.main.async(execute: schedule)
        }
    }

    private func stopMirrorCountdownTimer() {
        if Thread.isMainThread {
            mirrorTimer?.invalidate()
            mirrorTimer = nil
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.mirrorTimer?.invalidate()
                self?.mirrorTimer = nil
            }
        }
    }

    private func createRuntimeVirtualDisplay(spec: VirtualDisplaySpec) -> (display: AnyObject, id: CGDirectDisplayID)? {
        guard let descriptorClass = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
              let modeClass = NSClassFromString("CGVirtualDisplayMode"),
              let settingsClass = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type,
              let displayClass = NSClassFromString("CGVirtualDisplay") else {
            return nil
        }

        let descriptor = descriptorClass.init()
        let physicalSize = spec.sizeInMillimeters ?? CGSize(
            width: Double(spec.logicalWidth) * 0.23,
            height: Double(spec.logicalHeight) * 0.23
        )
        setIfResponds(descriptor, key: "name", value: spec.name)
        setIfResponds(descriptor, key: "maxPixelsWide", value: NSNumber(value: UInt32(spec.backingPixelWidth)))
        setIfResponds(descriptor, key: "maxPixelsHigh", value: NSNumber(value: UInt32(spec.backingPixelHeight)))
        setIfResponds(descriptor, key: "sizeInMillimeters", value: NSValue(size: physicalSize))
        setIfResponds(descriptor, key: "vendorID", value: NSNumber(value: UInt32(0x5653)))
        setIfResponds(descriptor, key: "productID", value: NSNumber(value: spec.productID))
        setIfResponds(descriptor, key: "serialNum", value: NSNumber(value: spec.serialNum))
        setIfResponds(descriptor, key: "queue", value: displayQueue)

        guard let mode = allocateVirtualDisplayMode(
            modeClass: modeClass,
            width: UInt32(spec.logicalWidth),
            height: UInt32(spec.logicalHeight),
            refreshRate: spec.refreshRate
        ) else {
            return nil
        }

        let settings = settingsClass.init()
        setIfResponds(settings, key: "hiDPI", value: NSNumber(value: UInt32(spec.scaleFactor > 1 ? 1 : 0)))
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
