// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation
import IOKit
import os

/// Snapshot of Apple Silicon package/subsystem power and Neural Engine activity.
struct AppleSiliconPowerSnapshot: Equatable, Sendable {
    let cpuWatts: Double
    let gpuWatts: Double
    let aneWatts: Double
    let packageWatts: Double
    let aneActivityPercent: Double
    let isHardwareBacked: Bool
    let sampledAt: Date

    init(
        cpuWatts: Double,
        gpuWatts: Double,
        aneWatts: Double,
        packageWatts: Double,
        aneActivityPercent: Double,
        isHardwareBacked: Bool,
        sampledAt: Date = Date()
    ) {
        self.cpuWatts = cpuWatts
        self.gpuWatts = gpuWatts
        self.aneWatts = aneWatts
        self.packageWatts = packageWatts
        self.aneActivityPercent = aneActivityPercent
        self.isHardwareBacked = isHardwareBacked
        self.sampledAt = sampledAt
    }

    static func unavailable(at date: Date = Date()) -> AppleSiliconPowerSnapshot {
        AppleSiliconPowerSnapshot(
            cpuWatts: 0,
            gpuWatts: 0,
            aneWatts: 0,
            packageWatts: 0,
            aneActivityPercent: 0,
            isHardwareBacked: false,
            sampledAt: date
        )
    }
}

/// Dynamically loads `/usr/lib/libIOReport.dylib` to read Apple Silicon Energy Model Watts and ANE residency.
final class AppleSiliconIOReportSampler: @unchecked Sendable {
    static let shared = AppleSiliconIOReportSampler()

    private struct API {
        typealias CopyChannelsInGroupFn = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
        typealias MergeChannelsFn = @convention(c) (CFMutableDictionary, CFMutableDictionary, CFTypeRef?) -> Void
        typealias CreateSubscriptionFn = @convention(c) (UnsafeMutableRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64, CFTypeRef?) -> Unmanaged<CFTypeRef>?
        typealias CreateSamplesFn = @convention(c) (CFTypeRef, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
        typealias CreateSamplesDeltaFn = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
        typealias IterateFn = @convention(c) (CFDictionary, @convention(block) (CFDictionary) -> Int32) -> Int32
        typealias GetStringFn = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
        typealias SimpleGetIntegerValueFn = @convention(c) (CFDictionary, Int32) -> Int64
        typealias StateGetCountFn = @convention(c) (CFDictionary) -> Int32
        typealias StateGetNameForIndexFn = @convention(c) (CFDictionary, Int32) -> Unmanaged<CFString>?
        typealias StateGetResidencyFn = @convention(c) (CFDictionary, Int32) -> Int64

        let copyChannelsInGroup: CopyChannelsInGroupFn
        let mergeChannels: MergeChannelsFn
        let createSubscription: CreateSubscriptionFn
        let createSamples: CreateSamplesFn
        let createSamplesDelta: CreateSamplesDeltaFn
        let iterate: IterateFn
        let channelGetGroup: GetStringFn
        let channelGetSubGroup: GetStringFn
        let channelGetChannelName: GetStringFn
        let channelGetUnitLabel: GetStringFn
        let simpleGetIntegerValue: SimpleGetIntegerValueFn
        let stateGetCount: StateGetCountFn?
        let stateGetNameForIndex: StateGetNameForIndexFn?
        let stateGetResidency: StateGetResidencyFn?
    }

    private final class AccumulationState {
        var explicitCPUWatts = 0.0
        var clusterCPUWatts = 0.0
        var perCoreCPUWatts = 0.0
        var explicitGPUWatts = 0.0
        var componentGPUWatts = 0.0
        var explicitANEWatts = 0.0
        var componentANEWatts = 0.0
        var reportedPackageWatts = 0.0
        var otherDomainWatts = 0.0
        var aneResidencyPercents: [Double] = []
    }

    private var lock = os_unfair_lock()
    private var dlHandle: UnsafeMutableRawPointer?
    private var api: API?
    private var subscription: CFTypeRef?
    private var subscribedChannels: CFMutableDictionary?
    private var previousSample: CFDictionary?
    private var previousSampleDate: Date?

    init() {
        configureLocked()
    }

    deinit {
        os_unfair_lock_lock(&lock)
        previousSample = nil
        previousSampleDate = nil
        subscribedChannels = nil
        subscription = nil
        api = nil
        if let handle = dlHandle {
            dlclose(handle)
            dlHandle = nil
        }
        os_unfair_lock_unlock(&lock)
    }

    func sample(thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState) -> AppleSiliconPowerSnapshot {
        _ = thermalState
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let now = Date()
        guard let api,
              let subscription,
              let subscribedChannels,
              let currentSample = api.createSamples(subscription, subscribedChannels, nil)?.takeRetainedValue() else {
            return .unavailable(at: now)
        }

        guard let prevSample = previousSample,
              let prevDate = previousSampleDate else {
            previousSample = currentSample
            previousSampleDate = now
            return .unavailable(at: now)
        }

        let dt = max(0.1, now.timeIntervalSince(prevDate))
        previousSample = currentSample
        previousSampleDate = now

        guard let delta = api.createSamplesDelta(prevSample, currentSample, nil)?.takeRetainedValue() else {
            return .unavailable(at: now)
        }

        let state = AccumulationState()
        _ = api.iterate(delta) { sample in
            Self.accumulateSample(sample, dt: dt, api: api, into: state)
            return 0
        }

        let cpuWatts = Self.sanitizedNonNegative(
            state.explicitCPUWatts > 0
                ? max(state.explicitCPUWatts, state.clusterCPUWatts)
                : (state.clusterCPUWatts > 0 ? state.clusterCPUWatts : state.perCoreCPUWatts)
        )
        let gpuWatts = Self.sanitizedNonNegative(
            state.explicitGPUWatts > 0 ? max(state.explicitGPUWatts, state.componentGPUWatts) : state.componentGPUWatts
        )
        let aneWatts = Self.sanitizedNonNegative(
            state.explicitANEWatts > 0 ? max(state.explicitANEWatts, state.componentANEWatts) : state.componentANEWatts
        )
        let subsystemSum = cpuWatts + gpuWatts + aneWatts
        let domainCombined = subsystemSum + Self.sanitizedNonNegative(state.otherDomainWatts)
        let packageBase = state.reportedPackageWatts > 0
            ? max(subsystemSum, Self.sanitizedNonNegative(state.reportedPackageWatts))
            : domainCombined
        let packageWatts = Self.sanitizedNonNegative(max(subsystemSum, packageBase))

        let aneActivityPercent: Double
        if !state.aneResidencyPercents.isEmpty {
            let avg = state.aneResidencyPercents.reduce(0, +) / Double(state.aneResidencyPercents.count)
            aneActivityPercent = min(100.0, Self.sanitizedNonNegative(avg))
        } else if aneWatts > 0 {
            aneActivityPercent = min(100.0, Self.sanitizedNonNegative((aneWatts / 8.0) * 100.0))
        } else {
            aneActivityPercent = 0
        }

        return AppleSiliconPowerSnapshot(
            cpuWatts: cpuWatts,
            gpuWatts: gpuWatts,
            aneWatts: aneWatts,
            packageWatts: packageWatts,
            aneActivityPercent: aneActivityPercent,
            isHardwareBacked: true,
            sampledAt: now
        )
    }

    private func configureLocked() {
        guard let handle = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY) else { return }

        guard let copyChannelsSym = dlsym(handle, "IOReportCopyChannelsInGroup"),
              let mergeChannelsSym = dlsym(handle, "IOReportMergeChannels"),
              let createSubSym = dlsym(handle, "IOReportCreateSubscription"),
              let createSamplesSym = dlsym(handle, "IOReportCreateSamples"),
              let createDeltaSym = dlsym(handle, "IOReportCreateSamplesDelta"),
              let iterateSym = dlsym(handle, "IOReportIterate"),
              let getGroupSym = dlsym(handle, "IOReportChannelGetGroup"),
              let getSubGroupSym = dlsym(handle, "IOReportChannelGetSubGroup"),
              let getNameSym = dlsym(handle, "IOReportChannelGetChannelName"),
              let getUnitSym = dlsym(handle, "IOReportChannelGetUnitLabel"),
              let simpleIntSym = dlsym(handle, "IOReportSimpleGetIntegerValue") else {
            dlclose(handle)
            return
        }

        let resolvedAPI = API(
            copyChannelsInGroup: unsafeBitCast(copyChannelsSym, to: API.CopyChannelsInGroupFn.self),
            mergeChannels: unsafeBitCast(mergeChannelsSym, to: API.MergeChannelsFn.self),
            createSubscription: unsafeBitCast(createSubSym, to: API.CreateSubscriptionFn.self),
            createSamples: unsafeBitCast(createSamplesSym, to: API.CreateSamplesFn.self),
            createSamplesDelta: unsafeBitCast(createDeltaSym, to: API.CreateSamplesDeltaFn.self),
            iterate: unsafeBitCast(iterateSym, to: API.IterateFn.self),
            channelGetGroup: unsafeBitCast(getGroupSym, to: API.GetStringFn.self),
            channelGetSubGroup: unsafeBitCast(getSubGroupSym, to: API.GetStringFn.self),
            channelGetChannelName: unsafeBitCast(getNameSym, to: API.GetStringFn.self),
            channelGetUnitLabel: unsafeBitCast(getUnitSym, to: API.GetStringFn.self),
            simpleGetIntegerValue: unsafeBitCast(simpleIntSym, to: API.SimpleGetIntegerValueFn.self),
            stateGetCount: dlsym(handle, "IOReportStateGetCount").map { unsafeBitCast($0, to: API.StateGetCountFn.self) },
            stateGetNameForIndex: dlsym(handle, "IOReportStateGetNameForIndex").map { unsafeBitCast($0, to: API.StateGetNameForIndexFn.self) },
            stateGetResidency: dlsym(handle, "IOReportStateGetResidency").map { unsafeBitCast($0, to: API.StateGetResidencyFn.self) }
        )

        let energyDict = resolvedAPI.copyChannelsInGroup("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue()
        let pmpDict = resolvedAPI.copyChannelsInGroup("PMP" as CFString, nil, 0, 0, 0)?.takeRetainedValue()
        let aneDict = resolvedAPI.copyChannelsInGroup("ANE" as CFString, nil, 0, 0, 0)?.takeRetainedValue()

        let populatedDicts = [energyDict, pmpDict, aneDict].compactMap { dict -> CFMutableDictionary? in
            guard let dict, Self.hasChannels(dict) else { return nil }
            return dict
        }

        // Only consider hardware power telemetry available if Energy Model has channels.
        guard let energyDict, Self.hasChannels(energyDict),
              let firstDict = populatedDicts.first,
              let merged = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, firstDict) else {
            dlclose(handle)
            return
        }

        for extra in populatedDicts.dropFirst() {
            resolvedAPI.mergeChannels(merged, extra, nil)
        }

        var subbedUnmanaged: Unmanaged<CFMutableDictionary>?
        guard let subUnmanaged = resolvedAPI.createSubscription(nil, merged, &subbedUnmanaged, 0, nil),
              let subbedChannels = subbedUnmanaged?.takeRetainedValue() else {
            _ = subbedUnmanaged
            dlclose(handle)
            return
        }
        let sub = subUnmanaged.takeRetainedValue()

        self.dlHandle = handle
        self.api = resolvedAPI
        self.subscription = sub
        self.subscribedChannels = subbedChannels
        self.previousSample = resolvedAPI.createSamples(sub, subbedChannels, nil)?.takeRetainedValue()
        self.previousSampleDate = self.previousSample != nil ? Date() : nil
    }

    private static func hasChannels(_ dict: CFDictionary) -> Bool {
        guard let nsDict = dict as NSDictionary?,
              let channels = nsDict["IOReportChannels"] else {
            return false
        }
        if let array = channels as? [Any] {
            return !array.isEmpty
        }
        if let dictChannels = channels as? [AnyHashable: Any] {
            return !dictChannels.isEmpty
        }
        return true
    }

    private static func accumulateSample(_ sample: CFDictionary, dt: Double, api: API, into state: AccumulationState) {
        let group = (api.channelGetGroup(sample)?.takeUnretainedValue() as String?) ?? ""
        let subGroup = (api.channelGetSubGroup(sample)?.takeUnretainedValue() as String?) ?? ""
        let name = (api.channelGetChannelName(sample)?.takeUnretainedValue() as String?) ?? ""
        let unit = (api.channelGetUnitLabel(sample)?.takeUnretainedValue() as String?)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let groupLower = group.lowercased()
        let subLower = subGroup.lowercased()
        let nameLower = name.lowercased()

        if groupLower == "energy model" {
            let raw = api.simpleGetIntegerValue(sample, 0)
            if raw != Int64.min, raw > 0,
               let watts = convertEnergyOrPowerToWatts(value: Double(raw), unit: unit, dt: dt) {
                classifyEnergyWatts(watts, channelNameLower: nameLower, into: state)
            }
            return
        }

        if groupLower == "pmp" || groupLower == "ane" || subLower.contains("ane") || nameLower.contains("ane") {
            let isANEChannel = groupLower == "ane" || subLower.contains("ane") || nameLower.contains("ane") || nameLower.contains("neural")
            guard isANEChannel else { return }

            if let stateGetCount = api.stateGetCount,
               let stateGetName = api.stateGetNameForIndex,
               let stateGetResidency = api.stateGetResidency {
                let count = stateGetCount(sample)
                if count > 0 {
                    var totalTicks: Int64 = 0
                    var activeTicks: Int64 = 0
                    for idx in 0..<count {
                        let residency = stateGetResidency(sample, idx)
                        guard residency > 0 else { continue }
                        totalTicks = totalTicks.saturatingAdd(residency)
                        let stateName = ((stateGetName(sample, idx)?.takeUnretainedValue() as String?) ?? "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .uppercased()
                        if !isIdleStateName(stateName) {
                            activeTicks = activeTicks.saturatingAdd(residency)
                        }
                    }
                    if totalTicks > 0 {
                        let pct = min(100.0, max(0.0, (Double(activeTicks) / Double(totalTicks)) * 100.0))
                        state.aneResidencyPercents.append(pct)
                        return
                    }
                }
            }

            if unit == "%" {
                let raw = api.simpleGetIntegerValue(sample, 0)
                if raw != Int64.min, raw >= 0 {
                    state.aneResidencyPercents.append(min(100.0, Double(raw)))
                }
            }
        }
    }

    private static func classifyEnergyWatts(_ watts: Double, channelNameLower name: String, into state: AccumulationState) {
        if name == "package" || name == "total" || name == "all" || name == "system"
            || name.contains("package energy") || name.contains("total power") || name.contains("system energy") {
            state.reportedPackageWatts = max(state.reportedPackageWatts, watts)
            return
        }
        if name == "cpu energy" || name == "cpu" || name == "cpu total" {
            state.explicitCPUWatts += watts
            return
        }
        if name == "ecpu" || name == "pcpu" || name == "eacc_cpu" || name == "pacc_cpu"
            || name == "e-cluster" || name == "p-cluster"
            || (name.hasPrefix("pacc") && name.hasSuffix("_cpu"))
            || (name.hasPrefix("eacc") && name.hasSuffix("_cpu")) {
            state.clusterCPUWatts += watts
            return
        }
        if (name.contains("ecpu") || name.contains("pcpu") || name.contains("cpu")
            || name.contains("eacc") || name.contains("pacc") || name == "cpm")
            && !name.contains("gpu") {
            state.perCoreCPUWatts += watts
            return
        }
        if name == "gpu energy" || name == "gpu" || name == "gpu total" {
            state.explicitGPUWatts += watts
            return
        }
        if name.contains("gpu") || name.contains("gfx") {
            state.componentGPUWatts += watts
            return
        }
        if name == "ane energy" || name == "ane" {
            state.explicitANEWatts += watts
            return
        }
        if name.contains("ane") || name.contains("neural") {
            state.componentANEWatts += watts
            return
        }
        state.otherDomainWatts += watts
    }

    private static func convertEnergyOrPowerToWatts(value: Double, unit: String, dt: Double) -> Double? {
        guard value.isFinite, value >= 0, dt > 0 else { return nil }
        let normalized = unit
            .replacingOccurrences(of: "\u{00B5}", with: "u")
            .replacingOccurrences(of: "\u{03BC}", with: "u")
            .lowercased()
        switch normalized {
        case "w", "watt", "watts":
            return value
        case "mw":
            return value * 1e-3
        case "uw":
            return value * 1e-6
        case "nw":
            return value * 1e-9
        case "j", "joule", "joules":
            return value / dt
        case "mj":
            return (value * 1e-3) / dt
        case "uj":
            return (value * 1e-6) / dt
        case "nj":
            return (value * 1e-9) / dt
        case "pj":
            return (value * 1e-12) / dt
        default:
            return nil
        }
    }

    private static func isIdleStateName(_ uppercased: String) -> Bool {
        uppercased == "OFF"
            || uppercased == "IDLE"
            || uppercased == "DOWN"
            || uppercased == "SLEEP"
            || uppercased == "INACTIVE"
            || uppercased == "0"
    }

    private static func sanitizedNonNegative(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return max(0, value)
    }
}

private extension Int64 {
    func saturatingAdd(_ other: Int64) -> Int64 {
        let (result, overflow) = addingReportingOverflow(other)
        return overflow ? Int64.max : result
    }
}

/// Snapshot of primary NVMe / SSD S.M.A.R.T. health indicators.
struct NVMeSMARTHealthSnapshot: Equatable, Sendable {
    let wearUsedPercent: Int?
    let temperatureCelsius: Double?
    let powerOnHours: Int?
    let mediaErrors: Int?
    let criticalWarning: Int?
    let statusVerified: Bool

    init(
        wearUsedPercent: Int? = nil,
        temperatureCelsius: Double? = nil,
        powerOnHours: Int? = nil,
        mediaErrors: Int? = nil,
        criticalWarning: Int? = nil,
        statusVerified: Bool = false
    ) {
        self.wearUsedPercent = wearUsedPercent
        self.temperatureCelsius = temperatureCelsius
        self.powerOnHours = powerOnHours
        self.mediaErrors = mediaErrors
        self.criticalWarning = criticalWarning
        self.statusVerified = statusVerified
    }

    static let empty = NVMeSMARTHealthSnapshot()
}

/// Reads NVMe S.M.A.R.T. telemetry directly via IOKit registry properties and NVMeSMARTLib plugin.
enum NVMeSMARTHealthReader {
    private struct IONVMeSMARTInterfaceRaw {
        var _reserved: UnsafeMutableRawPointer?
        var queryInterface: (@convention(c) (UnsafeMutableRawPointer?, CFUUIDBytes, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> HRESULT)?
        var addRef: (@convention(c) (UnsafeMutableRawPointer?) -> UInt32)?
        var release: (@convention(c) (UnsafeMutableRawPointer?) -> UInt32)?
        var version: UInt16
        var revision: UInt16
        var smartReadData: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> IOReturn)?
    }

    static func readPrimaryDisk() -> NVMeSMARTHealthSnapshot {
        let serviceClasses = [
            "IOBlockStorageDevice",
            "IONVMeController",
            "AppleANS3NVMeController",
            "AppleANS2Controller",
        ]

        for className in serviceClasses {
            guard let matching = IOServiceMatching(className) else { continue }
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else {
                continue
            }
            defer { IOObjectRelease(iterator) }

            var service = IOIteratorNext(iterator)
            while service != 0 {
                if let snapshot = inspectServiceAndAncestors(service) {
                    IOObjectRelease(service)
                    return snapshot
                }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
        }

        return .empty
    }

    static func parseSMARTDictionary(_ dict: [String: Any]) -> NVMeSMARTHealthSnapshot {
        var flat: [String: Any] = [:]
        flattenDictionary(dict, into: &flat)

        var wearUsed = parseWearUsed(from: flat)
        var temperature = parseTemperature(from: flat)
        var powerOnHours = parseNonNegativeCounter(
            primaryKeys: ["poweronhours", "poweronhours0"],
            highWordKey: "poweronhours1",
            in: flat
        )
        var mediaErrors = parseNonNegativeCounter(
            primaryKeys: ["mediaerrors", "mediaerrors0", "mediaanddataintegrityerrors"],
            highWordKey: "mediaerrors1",
            in: flat
        )
        var criticalWarning = parseInt(forKeys: ["criticalwarning"], in: flat)

        if let rawData = firstSMARTDataBlob(in: flat) {
            let fromData = parseNVMeSMARTData(rawData)
            if wearUsed == nil { wearUsed = fromData.wearUsedPercent }
            if temperature == nil { temperature = fromData.temperatureCelsius }
            if powerOnHours == nil { powerOnHours = fromData.powerOnHours }
            if mediaErrors == nil { mediaErrors = fromData.mediaErrors }
            if criticalWarning == nil { criticalWarning = fromData.criticalWarning }
        }

        let verified = (wearUsed != nil || temperature != nil || powerOnHours != nil)
        return NVMeSMARTHealthSnapshot(
            wearUsedPercent: wearUsed,
            temperatureCelsius: temperature,
            powerOnHours: powerOnHours,
            mediaErrors: mediaErrors,
            criticalWarning: criticalWarning,
            statusVerified: verified
        )
    }

    private static func inspectServiceAndAncestors(_ service: io_service_t) -> NVMeSMARTHealthSnapshot? {
        if let pluginSnapshot = readViaNVMeSMARTPlugin(service: service), pluginSnapshot.statusVerified {
            return pluginSnapshot
        }

        if let directProps = registryProperties(for: service) {
            let parsed = parseSMARTDictionary(directProps)
            if parsed.statusVerified {
                return parsed
            }
        }

        var current = service
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }

        for _ in 0..<4 {
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == kIOReturnSuccess, parent != 0 else {
                break
            }
            IOObjectRelease(current)
            current = parent

            if let props = registryProperties(for: current) {
                let parsed = parseSMARTDictionary(props)
                if parsed.statusVerified {
                    return parsed
                }
            }
        }

        return nil
    }

    private static func registryProperties(for entry: io_registry_entry_t) -> [String: Any]? {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return dict
    }

    private static func readViaNVMeSMARTPlugin(service: io_service_t) -> NVMeSMARTHealthSnapshot? {
        let capable = (IORegistryEntryCreateCFProperty(service, "NVMe SMART Capable" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool) ?? false
        let plugInTypes = IORegistryEntryCreateCFProperty(service, "IOCFPlugInTypes" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any]
        let hasNVMePlugin = plugInTypes?["AA0FA6F9-C2D6-457F-B10B-59A13253292F"] != nil
        guard capable || hasNVMePlugin else { return nil }

        guard let userClientID = CFUUIDGetConstantUUIDWithBytes(
                nil, 0xAA, 0x0F, 0xA6, 0xF9, 0xC2, 0xD6, 0x45, 0x7F,
                0xB1, 0x0B, 0x59, 0xA1, 0x32, 0x53, 0x29, 0x2F
              ),
              let pluginID = CFUUIDGetConstantUUIDWithBytes(
                nil, 0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4,
                0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F
              ),
              let smartInterfaceID = CFUUIDGetConstantUUIDWithBytes(
                nil, 0xCC, 0xD1, 0xDB, 0x19, 0xFD, 0x9A, 0x4D, 0xAF,
                0xBF, 0x95, 0x12, 0x45, 0x4B, 0x23, 0x0A, 0xB6
              ) else {
            return nil
        }

        var plugIn: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0
        guard IOCreatePlugInInterfaceForService(service, userClientID, pluginID, &plugIn, &score) == kIOReturnSuccess,
              let plugIn,
              let vtbl = plugIn.pointee?.pointee else {
            return nil
        }
        defer { _ = vtbl.Release(plugIn) }

        var rawInterface: UnsafeMutableRawPointer?
        guard vtbl.QueryInterface(plugIn, CFUUIDGetUUIDBytes(smartInterfaceID), &rawInterface) == 0,
              let rawInterface else {
            return nil
        }

        let smartPtr = rawInterface.assumingMemoryBound(to: UnsafeMutablePointer<IONVMeSMARTInterfaceRaw>.self)
        let smartVtbl = smartPtr.pointee.pointee
        defer { _ = smartVtbl.release?(rawInterface) }

        var buffer = [UInt8](repeating: 0, count: 512)
        let readResult = buffer.withUnsafeMutableBytes { raw -> IOReturn in
            guard let base = raw.baseAddress else { return kIOReturnBadArgument }
            return smartVtbl.smartReadData?(rawInterface, base) ?? kIOReturnUnsupported
        }
        guard readResult == kIOReturnSuccess else { return nil }

        return parseNVMeSMARTData(Data(buffer))
    }

    private static func parseNVMeSMARTData(_ data: Data) -> NVMeSMARTHealthSnapshot {
        guard data.count >= 176 else { return .empty }
        let criticalWarning = Int(data[0])
        let rawTempKelvin = data.withUnsafeBytes { raw -> UInt16 in
            UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: 1, as: UInt16.self))
        }
        let percentageUsed = min(100, max(0, Int(data[5])))
        let powerOnHoursRaw = data.withUnsafeBytes { raw -> UInt64 in
            UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: 128, as: UInt64.self))
        }
        let mediaErrorsRaw = data.withUnsafeBytes { raw -> UInt64 in
            UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: 160, as: UInt64.self))
        }

        let tempCelsius: Double? = rawTempKelvin > 0 ? normalizedTemperature(Double(rawTempKelvin)) : nil
        let powerOnHours = powerOnHoursRaw <= UInt64(Int.max) ? Int(powerOnHoursRaw) : Int.max
        let mediaErrors = mediaErrorsRaw <= UInt64(Int.max) ? Int(mediaErrorsRaw) : Int.max

        return NVMeSMARTHealthSnapshot(
            wearUsedPercent: percentageUsed,
            temperatureCelsius: tempCelsius,
            powerOnHours: powerOnHours,
            mediaErrors: mediaErrors,
            criticalWarning: criticalWarning,
            statusVerified: true
        )
    }

    private static func flattenDictionary(_ dict: [String: Any], into flat: inout [String: Any], depth: Int = 0) {
        guard depth <= 3 else { return }
        let nestedContainerKeys: Set<String> = [
            "smartdata",
            "nvmesmart",
            "nvmesmartdata",
            "smartdevicespecifickeysmayvarynotguaranteed",
            "smart",
        ]
        for (key, value) in dict {
            let norm = normalizeKey(key)
            if nestedContainerKeys.contains(norm), let sub = value as? [String: Any] {
                flattenDictionary(sub, into: &flat, depth: depth + 1)
            } else if flat[norm] == nil {
                flat[norm] = value
            }
        }
    }

    private static func firstSMARTDataBlob(in flat: [String: Any]) -> Data? {
        for key in ["smartdata", "nvmesmart", "nvmesmartdata"] {
            if let data = flat[key] as? Data, data.count >= 176 {
                return data
            }
        }
        return nil
    }

    private static func normalizeKey(_ key: String) -> String {
        key.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private static func parseWearUsed(from flat: [String: Any]) -> Int? {
        guard let raw = parseInt(
            forKeys: ["percentageused", "wear", "wearlevelingcount", "mediawearoutindicator"],
            in: flat
        ) else {
            return nil
        }
        return min(100, max(0, raw))
    }

    private static func parseTemperature(from flat: [String: Any]) -> Double? {
        let keys = ["temperature", "compositetemperature", "temperaturecelsius", "drivetemperature"]
        for key in keys {
            if let value = parseDouble(flat[key]), let normalized = normalizedTemperature(value) {
                return normalized
            }
        }
        return nil
    }

    private static func normalizedTemperature(_ raw: Double) -> Double? {
        guard raw.isFinite else { return nil }
        let celsius: Double
        if raw > 200 {
            celsius = ((raw - 273.15) * 100.0).rounded() / 100.0
        } else {
            celsius = raw
        }
        guard celsius.isFinite, celsius >= -50, celsius <= 150 else { return nil }
        return celsius
    }

    private static func parseNonNegativeCounter(primaryKeys: [String], highWordKey: String, in flat: [String: Any]) -> Int? {
        guard let low = parseInt(forKeys: primaryKeys, in: flat), low >= 0 else {
            return nil
        }
        if let high = parseInt(forKeys: [highWordKey], in: flat), high > 0 {
            let highU = UInt64(high)
            if highU <= UInt64(Int32.max) {
                let combined = (highU << 32) | UInt64(low)
                return combined <= UInt64(Int.max) ? Int(combined) : Int.max
            }
        }
        return low
    }

    private static func parseInt(forKeys keys: [String], in flat: [String: Any]) -> Int? {
        for key in keys {
            guard let raw = flat[key] else { continue }
            switch raw {
            case let value as Int:
                return value
            case let value as UInt:
                return value <= UInt(Int.max) ? Int(value) : Int.max
            case let value as UInt64:
                return value <= UInt64(Int.max) ? Int(value) : Int.max
            case let value as Int64:
                return Int(clamping: value)
            case let value as Double:
                guard value.isFinite else { continue }
                return Int(value.rounded())
            case let value as NSNumber:
                let i64 = value.int64Value
                return Int(clamping: i64)
            case let value as String:
                if let parsed = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return parsed
                }
            default:
                continue
            }
        }
        return nil
    }

    private static func parseDouble(_ raw: Any?) -> Double? {
        guard let raw else { return nil }
        switch raw {
        case let value as Double:
            return value.isFinite ? value : nil
        case let value as Float:
            return value.isFinite ? Double(value) : nil
        case let value as Int:
            return Double(value)
        case let value as UInt64:
            return Double(value)
        case let value as NSNumber:
            let d = value.doubleValue
            return d.isFinite ? d : nil
        case let value as String:
            if let d = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)), d.isFinite {
                return d
            }
            return nil
        default:
            return nil
        }
    }
}
