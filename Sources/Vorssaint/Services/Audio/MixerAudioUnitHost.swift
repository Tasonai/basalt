// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Accelerate
import AppKit
@preconcurrency import AudioToolbox
@preconcurrency import AVFoundation
import Combine
import CoreAudio
import CoreAudioKit
import Foundation
import os

/// Descriptor for a discovered system AUv3 / Audio Unit effect component.
struct MixerAudioUnitComponentItem: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let manufacturerName: String
    let componentDescription: AudioComponentDescription

    init(component: AVAudioUnitComponent) {
        let desc = component.audioComponentDescription
        self.id = Self.identifier(for: desc)
        self.name = component.name
        self.manufacturerName = component.manufacturerName
        self.componentDescription = desc
    }

    init(name: String, manufacturerName: String, componentDescription: AudioComponentDescription) {
        self.id = Self.identifier(for: componentDescription)
        self.name = name
        self.manufacturerName = manufacturerName
        self.componentDescription = componentDescription
    }

    static func identifier(for desc: AudioComponentDescription) -> String {
        "\(desc.componentType):\(desc.componentSubType):\(desc.componentManufacturer)"
    }

    static func == (lhs: MixerAudioUnitComponentItem, rhs: MixerAudioUnitComponentItem) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.manufacturerName == rhs.manufacturerName
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Atomic, owner-only (`0o600`) binary property-list persistence for each AUv3 insert slot's
/// `fullState`, keyed by `componentID` and sanitized before serialization to avoid uncatchable
/// Objective-C exceptions on malformed third-party AU dictionaries.
struct MixerAUStateStore: Sendable {
    let directoryURL: URL?
    private let containerRootURL: URL?

    init(
        directoryURL: URL? = PrivateFileStore.containerURL?.appendingPathComponent("MixerAUState", isDirectory: true),
        containerRootURL: URL? = PrivateFileStore.containerURL
    ) {
        self.directoryURL = directoryURL
        self.containerRootURL = containerRootURL ?? directoryURL
    }

    func fileURL(forSlot slot: Int) -> URL? {
        guard slot >= 0 && slot < MixerAudioUnitHost.slotCount else { return nil }
        return directoryURL?.appendingPathComponent("slot-\(slot).plist", isDirectory: false)
    }

    static func sanitizeFullState(_ state: [String: Any]) -> [String: Any] {
        (sanitizePropertyListValue(state) as? [String: Any]) ?? [:]
    }

    static func sanitizePropertyListValue(_ value: Any) -> Any? {
        if value is NSNull {
            return nil
        }
        if let string = value as? String {
            return string
        }
        if let data = value as? Data {
            return data
        }
        if let date = value as? Date {
            return date
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue
            }
            let doubleValue = number.doubleValue
            guard !doubleValue.isNaN && !doubleValue.isInfinite else { return nil }
            if number is NSDecimalNumber {
                return Double(doubleValue)
            }
            return number
        }
        if let array = value as? [Any] {
            return array.compactMap { sanitizePropertyListValue($0) }
        }
        if let dict = value as? [AnyHashable: Any] {
            var sanitized: [String: Any] = [:]
            sanitized.reserveCapacity(dict.count)
            for (rawKey, rawValue) in dict {
                guard let key = rawKey as? String,
                      let cleanValue = sanitizePropertyListValue(rawValue) else {
                    continue
                }
                sanitized[key] = cleanValue
            }
            return sanitized
        }
        return nil
    }

    @discardableResult
    func saveState(_ fullState: [String: Any], componentID: String, forSlot slot: Int) -> Bool {
        guard !componentID.isEmpty,
              let dir = directoryURL,
              let url = fileURL(forSlot: slot) else {
            return false
        }
        guard PrivateFileStore.createDirectory(at: dir, container: containerRootURL ?? dir) else {
            return false
        }
        let sanitizedState = Self.sanitizeFullState(fullState)
        let payload: [String: Any] = [
            "version": 1,
            "componentID": componentID,
            "fullState": sanitizedState,
        ]
        guard PropertyListSerialization.propertyList(payload, isValidFor: .binary),
              let data = try? PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0) else {
            return false
        }
        return PrivateFileStore.writeStream(to: url) { emit in
            data.withUnsafeBytes { rawBuffer in
                emit(rawBuffer)
            }
        }
    }

    func loadState(forSlot slot: Int, componentID: String) -> [String: Any]? {
        guard !componentID.isEmpty,
              let url = fileURL(forSlot: slot),
              let data = try? Data(contentsOf: url),
              !data.isEmpty,
              let raw = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let payload = raw as? [String: Any],
              (payload["version"] as? Int) == 1,
              (payload["componentID"] as? String) == componentID,
              let state = payload["fullState"] as? [String: Any] else {
            return nil
        }
        return Self.sanitizeFullState(state)
    }

    func removeState(forSlot slot: Int) {
        guard let url = fileURL(forSlot: slot) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

/// Real-time lock-free 3-slot serial AUv3 insert chain + Fletcher-Munson loudness EQ processor.
/// Preallocates all scratch buffers and pull-input state off the audio thread so CoreAudio IOProc callbacks
/// perform strictly zero heap allocations and never block waiting on UI slot swaps.
final class MixerRealtimeAUChainProcessor: @unchecked Sendable {
    static let shared = MixerRealtimeAUChainProcessor()
    static let slotCount = 3
    static let maxFrames = 4096
    static let maxChannels = 8

    private final class SlotRuntime {
        let audioUnit: AUAudioUnit
        let legacyAudioUnit: AudioUnit?
        let renderBlock: AURenderBlock
        let channelCount: Int
        let sampleRate: Double
        var bypassed: Bool

        init(
            audioUnit: AUAudioUnit,
            legacyAudioUnit: AudioUnit?,
            renderBlock: @escaping AURenderBlock,
            channelCount: Int,
            sampleRate: Double,
            bypassed: Bool
        ) {
            self.audioUnit = audioUnit
            self.legacyAudioUnit = legacyAudioUnit
            self.renderBlock = renderBlock
            self.channelCount = channelCount
            self.sampleRate = sampleRate
            self.bypassed = bypassed
        }
    }

    private struct PullInputState {
        var channelPtrs: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
        var activeChannels: Int
        var activeFrames: Int
    }

    private let channelCapacity: Int
    private let configLock = NSLock()
    private var renderLock = os_unfair_lock()
    private var activeAUSlotsFlagBits: Int32 = 0
    private var stoppingFlagBits: Int32 = 0
    private var invalidatedFlagBits: Int32 = 0

    private var slot0: SlotRuntime?
    private var slot1: SlotRuntime?
    private var slot2: SlotRuntime?
    private var sampleTimeCursor: Float64 = 0

    private let loudnessProcessor = FletcherMunsonLoudness.LoudnessBiquadProcessor()

    // Preallocated scratch storage (allocated off audio thread before any slot activates).
    private var scratchAllocated = false
    private var inputScratchChannels: UnsafeMutablePointer<UnsafeMutablePointer<Float>>?
    private var outputScratchChannels: UnsafeMutablePointer<UnsafeMutablePointer<Float>>?
    private var outputABLRaw: UnsafeMutableRawPointer?
    private var outputABLPtr: UnsafeMutablePointer<AudioBufferList>?
    private var pullState: UnsafeMutablePointer<PullInputState>?
    private var pullInputBlock: AURenderPullInputBlock?

    var hasActiveSlots: Bool {
        guard !isStoppingOrInvalidated else { return false }
        return withUnsafeMutablePointer(to: &activeAUSlotsFlagBits) { ptr in
            OSAtomicAdd32Barrier(0, ptr) != 0
        }
    }

    var isInvalidated: Bool {
        withUnsafeMutablePointer(to: &invalidatedFlagBits) { ptr in
            OSAtomicAdd32Barrier(0, ptr) != 0
        }
    }

    var isStoppingOrInvalidated: Bool {
        let stopping = withUnsafeMutablePointer(to: &stoppingFlagBits) { ptr in
            OSAtomicAdd32Barrier(0, ptr) != 0
        }
        return stopping || isInvalidated
    }

    /// Synchronously prevents new AU control/configuration mutations as soon as an engine starts stopping.
    func markStopping() {
        Self.atomicStoreInt32(1, into: &stoppingFlagBits)
    }

    /// Runs `body` under `configLock` only while this processor is neither stopping nor invalidated,
    /// providing strict mutual exclusion against teardown `invalidate()`.
    func withActiveConfigLock(_ body: () -> Void) {
        configLock.lock()
        defer { configLock.unlock() }
        guard !isStoppingOrInvalidated else { return }
        body()
    }

    var isLoudnessBypassed: Bool {
        loudnessProcessor.isBypassed
    }

    init(channelCapacity: Int = MixerRealtimeAUChainProcessor.maxChannels, deferScratchAllocation: Bool = false) {
        self.channelCapacity = min(max(channelCapacity, 2), Self.maxChannels)
        if !deferScratchAllocation {
            configLock.lock()
            allocateScratchBuffersLocked()
            configLock.unlock()
        }
    }

    deinit {
        if let s0 = slot0, !isUnitReferencedInSlots(s0.audioUnit, excluding: 0) {
            Self.setRenderCallback(nil, refCon: nil, on: s0.legacyAudioUnit)
            s0.audioUnit.deallocateRenderResources()
        }
        if let s1 = slot1, !isUnitReferencedInSlots(s1.audioUnit, excluding: 1) {
            Self.setRenderCallback(nil, refCon: nil, on: s1.legacyAudioUnit)
            s1.audioUnit.deallocateRenderResources()
        }
        if let s2 = slot2, !isUnitReferencedInSlots(s2.audioUnit, excluding: 2) {
            Self.setRenderCallback(nil, refCon: nil, on: s2.legacyAudioUnit)
            s2.audioUnit.deallocateRenderResources()
        }
        if scratchAllocated {
            pullState?.deinitialize(count: 1)
            pullState?.deallocate()
            outputABLRaw?.deallocate()
            if let inCh = inputScratchChannels, let outCh = outputScratchChannels {
                for ch in 0..<channelCapacity {
                    inCh[ch].deinitialize(count: Self.maxFrames)
                    outCh[ch].deinitialize(count: Self.maxFrames)
                    inCh[ch].deallocate()
                    outCh[ch].deallocate()
                }
                inCh.deinitialize(count: channelCapacity)
                outCh.deinitialize(count: channelCapacity)
                inCh.deallocate()
                outCh.deallocate()
            }
        }
    }

    @inline(__always)
    private static func fillPullInputBuffers(
        state: PullInputState,
        frameCount: UInt32,
        ioData: UnsafeMutableAudioBufferListPointer
    ) {
        let copyFrames = min(Int(frameCount), state.activeFrames)
        let copyBytes = max(0, copyFrames) * MemoryLayout<Float>.size

        for ch in 0..<ioData.count {
            if ch < state.activeChannels {
                let src = state.channelPtrs[ch]
                if let dst = ioData[ch].mData {
                    let maxBytes = Int(ioData[ch].mDataByteSize)
                    let bytesToCopy = min(copyBytes, maxBytes)
                    if bytesToCopy > 0 {
                        memcpy(dst, src, bytesToCopy)
                    }
                    if maxBytes > bytesToCopy {
                        memset(dst.advanced(by: bytesToCopy), 0, maxBytes - bytesToCopy)
                    }
                    ioData[ch].mDataByteSize = UInt32(bytesToCopy)
                } else {
                    ioData[ch].mData = UnsafeMutableRawPointer(src)
                    ioData[ch].mDataByteSize = UInt32(copyBytes)
                }
            } else if let dst = ioData[ch].mData {
                memset(dst, 0, Int(ioData[ch].mDataByteSize))
            }
        }
    }

    // Legacy AUv2 / AUAudioUnitV2Bridge render callback sharing the lock-free preallocated `PullInputState`.
    private static let v2RenderCallback: AURenderCallback = { inRefCon, _, _, _, inNumberFrames, ioData in
        guard let ioData else { return noErr }
        let state = inRefCon.assumingMemoryBound(to: PullInputState.self).pointee
        MixerRealtimeAUChainProcessor.fillPullInputBuffers(
            state: state,
            frameCount: inNumberFrames,
            ioData: UnsafeMutableAudioBufferListPointer(ioData)
        )
        return noErr
    }

    private static func setRenderCallback(
        _ callback: AURenderCallback?,
        refCon: UnsafeMutableRawPointer?,
        on legacyUnit: AudioUnit?
    ) {
        guard let legacyUnit else { return }
        var cb = AURenderCallbackStruct(inputProc: callback, inputProcRefCon: refCon)
        AudioUnitSetProperty(
            legacyUnit,
            kAudioUnitProperty_SetRenderCallback,
            kAudioUnitScope_Input,
            0,
            &cb,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )
    }

    private func allocateScratchBuffersLocked() {
        guard !scratchAllocated else { return }
        let capacity = channelCapacity
        let inPtrs = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: capacity)
        let outPtrs = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: capacity)
        for ch in 0..<capacity {
            let inBuf = UnsafeMutablePointer<Float>.allocate(capacity: Self.maxFrames)
            let outBuf = UnsafeMutablePointer<Float>.allocate(capacity: Self.maxFrames)
            inBuf.initialize(repeating: 0, count: Self.maxFrames)
            outBuf.initialize(repeating: 0, count: Self.maxFrames)
            (inPtrs + ch).initialize(to: inBuf)
            (outPtrs + ch).initialize(to: outBuf)
        }
        self.inputScratchChannels = inPtrs
        self.outputScratchChannels = outPtrs

        let buffersOffset = MemoryLayout<AudioBufferList>.offset(of: \.mBuffers) ?? MemoryLayout<UInt32>.size
        let ablByteCount = buffersOffset + capacity * MemoryLayout<AudioBuffer>.stride
        let rawABL = UnsafeMutableRawPointer.allocate(byteCount: ablByteCount,
                                                      alignment: MemoryLayout<AudioBufferList>.alignment)
        memset(rawABL, 0, ablByteCount)
        self.outputABLRaw = rawABL
        let ablPtr = rawABL.assumingMemoryBound(to: AudioBufferList.self)
        ablPtr.pointee.mNumberBuffers = UInt32(capacity)
        self.outputABLPtr = ablPtr

        let statePtr = UnsafeMutablePointer<PullInputState>.allocate(capacity: 1)
        statePtr.initialize(to: PullInputState(channelPtrs: inPtrs, activeChannels: min(2, capacity), activeFrames: 0))
        self.pullState = statePtr

        // Constructed once off the audio thread capturing only a trivial raw pointer (zero ARC/heap allocations per render).
        self.pullInputBlock = { _, _, frameCount, _, inputDataPtr in
            Self.fillPullInputBuffers(
                state: statePtr.pointee,
                frameCount: frameCount,
                ioData: UnsafeMutableAudioBufferListPointer(inputDataPtr)
            )
            return noErr
        }
        self.scratchAllocated = true
    }

    /// Permanently tears down all slot Audio Units for an engine that has stopped.
    func invalidate() {
        Self.atomicStoreInt32(1, into: &stoppingFlagBits)
        Self.atomicStoreInt32(1, into: &invalidatedFlagBits)
        configLock.lock()
        os_unfair_lock_lock(&renderLock)
        let removed0 = slot0
        let removed1 = slot1
        let removed2 = slot2
        slot0 = nil
        slot1 = nil
        slot2 = nil
        recomputeActiveSlotsFlagLocked()
        os_unfair_lock_unlock(&renderLock)
        configLock.unlock()

        var deallocated: [AUAudioUnit] = []
        for runtime in [removed0, removed1, removed2] {
            guard let runtime else { continue }
            Self.setRenderCallback(nil, refCon: nil, on: runtime.legacyAudioUnit)
            let unit = runtime.audioUnit
            if !deallocated.contains(where: { $0 === unit }) {
                unit.deallocateRenderResources()
                deallocated.append(unit)
            }
        }
    }

    /// Configures a single insert slot (`0..<3`) off the audio thread: allocates render
    /// resources at `maxFrames = 4096`, captures `renderBlock`, and swaps into place under `os_unfair_lock`.
    func configureSlot(
        _ slot: Int,
        audioUnit: AUAudioUnit?,
        legacyAudioUnit: AudioUnit? = nil,
        bypassed: Bool,
        sampleRate: Double = 48_000,
        channels: Int = 2
    ) {
        guard slot >= 0 && slot < Self.slotCount else { return }
        let safeRate = sampleRate.isFinite && sampleRate >= 8_000 ? sampleRate : 48_000
        let safeChannels = min(max(channels, 1), channelCapacity)

        configLock.lock()
        defer { configLock.unlock() }

        if isStoppingOrInvalidated && audioUnit != nil {
            return
        }

        guard let au = audioUnit else {
            os_unfair_lock_lock(&renderLock)
            let oldRuntime = getSlotLocked(slot)
            setSlotLocked(slot, nil)
            recomputeActiveSlotsFlagLocked()
            os_unfair_lock_unlock(&renderLock)

            if let oldRuntime, !isAudioUnitActiveInAnySlot(oldRuntime.audioUnit) {
                Self.setRenderCallback(nil, refCon: nil, on: oldRuntime.legacyAudioUnit)
                oldRuntime.audioUnit.deallocateRenderResources()
            }
            return
        }

        allocateScratchBuffersLocked()

        // Fast path: same AU instance at identical format only needs bypass state update.
        // If format/channels differ on the currently active unit, pull the live slot off `renderLock`
        // BEFORE deallocating render resources or mutating bus formats.
        var removedExistingForReconfigure: SlotRuntime?
        os_unfair_lock_lock(&renderLock)
        if let existing = getSlotLocked(slot), existing.audioUnit === au {
            if existing.legacyAudioUnit == legacyAudioUnit,
               abs(existing.sampleRate - safeRate) <= 1.0,
               existing.channelCount == safeChannels,
               au.renderResourcesAllocated {
                existing.bypassed = bypassed
                recomputeActiveSlotsFlagLocked()
                os_unfair_lock_unlock(&renderLock)
                au.shouldBypassEffect = bypassed
                return
            }
            removedExistingForReconfigure = existing
            setSlotLocked(slot, nil)
            recomputeActiveSlotsFlagLocked()
        }
        os_unfair_lock_unlock(&renderLock)

        if let removed = removedExistingForReconfigure, !isAudioUnitActiveInAnySlot(au) {
            Self.setRenderCallback(nil, refCon: nil, on: removed.legacyAudioUnit)
            au.deallocateRenderResources()
        }

        // Prepare render resources off the render lock.
        if au.renderResourcesAllocated && !isAudioUnitActiveInAnySlot(au) {
            au.deallocateRenderResources()
        }
        if let pullState {
            Self.setRenderCallback(
                Self.v2RenderCallback,
                refCon: UnsafeMutableRawPointer(pullState),
                on: legacyAudioUnit
            )
        }
        au.maximumFramesToRender = AUAudioFrameCount(Self.maxFrames)

        var resolvedChannels = 0
        let candidateCounts = safeChannels == 2 ? [2] : [safeChannels, 2]
        for candidateChannels in candidateCounts {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: safeRate,
                                             channels: AVAudioChannelCount(candidateChannels)) else {
                continue
            }
            do {
                if au.inputBusses.count > 0 {
                    try au.inputBusses[0].setFormat(format)
                }
                if au.outputBusses.count > 0 {
                    try au.outputBusses[0].setFormat(format)
                }
                try au.allocateRenderResources()
                let outCount = au.outputBusses.count > 0
                    ? Int(au.outputBusses[0].format.channelCount)
                    : candidateChannels
                if outCount >= 1 && outCount <= channelCapacity {
                    resolvedChannels = outCount
                    break
                } else {
                    au.deallocateRenderResources()
                }
            } catch {
                if au.renderResourcesAllocated {
                    au.deallocateRenderResources()
                }
            }
        }

        // Fallback: try allocating with the AU's existing bus format if compatible with Float32 PCM.
        if resolvedChannels == 0,
           au.outputBusses.count > 0,
           let currentFormat = Optional(au.outputBusses[0].format),
           currentFormat.commonFormat == .pcmFormatFloat32,
           currentFormat.channelCount >= 1,
           currentFormat.channelCount <= UInt32(channelCapacity) {
            do {
                try au.allocateRenderResources()
                resolvedChannels = Int(currentFormat.channelCount)
            } catch {
                if au.renderResourcesAllocated {
                    au.deallocateRenderResources()
                }
            }
        }

        guard resolvedChannels > 0 else {
            Self.setRenderCallback(nil, refCon: nil, on: legacyAudioUnit)
            os_unfair_lock_lock(&renderLock)
            let oldRuntime = getSlotLocked(slot)
            setSlotLocked(slot, nil)
            recomputeActiveSlotsFlagLocked()
            os_unfair_lock_unlock(&renderLock)
            if let oldRuntime,
               oldRuntime.audioUnit !== au,
               !isAudioUnitActiveInAnySlot(oldRuntime.audioUnit) {
                Self.setRenderCallback(nil, refCon: nil, on: oldRuntime.legacyAudioUnit)
                oldRuntime.audioUnit.deallocateRenderResources()
            }
            return
        }

        if isStoppingOrInvalidated {
            Self.setRenderCallback(nil, refCon: nil, on: legacyAudioUnit)
            au.deallocateRenderResources()
            return
        }

        au.shouldBypassEffect = bypassed
        let capturedRenderBlock = au.renderBlock
        let newRuntime = SlotRuntime(
            audioUnit: au,
            legacyAudioUnit: legacyAudioUnit,
            renderBlock: capturedRenderBlock,
            channelCount: resolvedChannels,
            sampleRate: safeRate,
            bypassed: bypassed
        )

        os_unfair_lock_lock(&renderLock)
        if isStoppingOrInvalidated {
            os_unfair_lock_unlock(&renderLock)
            Self.setRenderCallback(nil, refCon: nil, on: legacyAudioUnit)
            au.deallocateRenderResources()
            return
        }
        let oldRuntime = getSlotLocked(slot)
        setSlotLocked(slot, newRuntime)
        recomputeActiveSlotsFlagLocked()
        os_unfair_lock_unlock(&renderLock)

        if let oldRuntime,
           oldRuntime.audioUnit !== au,
           !isAudioUnitActiveInAnySlot(oldRuntime.audioUnit) {
            Self.setRenderCallback(nil, refCon: nil, on: oldRuntime.legacyAudioUnit)
            oldRuntime.audioUnit.deallocateRenderResources()
        }
    }

    func setSlotBypassed(_ bypassed: Bool, atSlot slot: Int) {
        guard slot >= 0 && slot < Self.slotCount else { return }
        configLock.lock()
        defer { configLock.unlock() }
        guard !isStoppingOrInvalidated else { return }

        os_unfair_lock_lock(&renderLock)
        let target = getSlotLocked(slot)
        target?.bypassed = bypassed
        recomputeActiveSlotsFlagLocked()
        os_unfair_lock_unlock(&renderLock)

        target?.audioUnit.shouldBypassEffect = bypassed
    }

    func isSlotActive(_ slot: Int) -> Bool {
        guard slot >= 0 && slot < Self.slotCount else { return false }
        os_unfair_lock_lock(&renderLock)
        defer { os_unfair_lock_unlock(&renderLock) }
        return getSlotLocked(slot) != nil
    }

    func isSlotBypassed(_ slot: Int) -> Bool {
        guard slot >= 0 && slot < Self.slotCount else { return true }
        os_unfair_lock_lock(&renderLock)
        defer { os_unfair_lock_unlock(&renderLock) }
        return getSlotLocked(slot)?.bypassed ?? true
    }

    func setLoudnessState(volume: Double, enabled: Bool, sampleRate: Double = 48_000) {
        loudnessProcessor.update(volume: volume, enabled: enabled, sampleRate: sampleRate)
    }

    func reset() {
        os_unfair_lock_lock(&renderLock)
        sampleTimeCursor = 0
        os_unfair_lock_unlock(&renderLock)
        loudnessProcessor.reset()
    }

    /// Processes an interleaved Float32 buffer through active AUv3 slots and loudness EQ
    /// with strictly zero heap allocations.
    @discardableResult
    func processInterleaved(
        _ samples: UnsafeMutablePointer<Float>,
        frames: Int,
        channels: Int,
        sampleRate: Double = 48_000
    ) -> Bool {
        guard frames > 0, channels > 0 else { return true }
        let byteSize = UInt32(frames * channels * MemoryLayout<Float>.size)
        let audioBuffer = AudioBuffer(
            mNumberChannels: UInt32(channels),
            mDataByteSize: byteSize,
            mData: UnsafeMutableRawPointer(samples)
        )
        var bufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)
        return withUnsafeMutablePointer(to: &bufferList) { ptr in
            processAudioBufferList(UnsafeMutableAudioBufferListPointer(ptr),
                                   frames: frames,
                                   sampleRate: sampleRate)
        }
    }

    /// Processes only the 3-slot AUv3 insert chain (without shared loudness EQ),
    /// allowing each `TapGainEngine` to run its own per-stream loudness biquad
    /// at its native sample rate without cross-app IIR filter state bleed.
    @discardableResult
    func processAUChainOnly(
        _ bufferList: UnsafeMutableAudioBufferListPointer,
        frames: Int,
        sampleRate: Double = 48_000
    ) -> Bool {
        guard frames > 0, !bufferList.isEmpty else { return true }
        guard !isStoppingOrInvalidated, hasActiveSlots else { return true }
        if os_unfair_lock_trylock(&renderLock) {
            processAUChainLocked(bufferList, frames: frames, sampleRate: sampleRate)
            os_unfair_lock_unlock(&renderLock)
            return true
        }
        return false
    }

    /// Processes an `AudioBufferList` (interleaved or non-interleaved Float32) through up to
    /// 3 serial AUv3 slots followed by Fletcher-Munson loudness EQ with zero heap allocations.
    @discardableResult
    func processAudioBufferList(
        _ bufferList: UnsafeMutableAudioBufferListPointer,
        frames: Int,
        sampleRate: Double = 48_000
    ) -> Bool {
        guard frames > 0, !bufferList.isEmpty else { return true }

        let auSucceeded = processAUChainOnly(bufferList, frames: frames, sampleRate: sampleRate)
        let loudnessSucceeded = loudnessProcessor.processAudioBufferList(bufferList, frames: frames)
        return auSucceeded && loudnessSucceeded
    }

    private func processAUChainLocked(
        _ bufferList: UnsafeMutableAudioBufferListPointer,
        frames: Int,
        sampleRate: Double
    ) {
        guard scratchAllocated,
              let inputScratchChannels,
              let outputScratchChannels,
              let outputABLPtr,
              let pullState,
              let pullInputBlock else {
            return
        }

        var allSingleChannel = true
        for index in 0..<bufferList.count {
            if bufferList[index].mNumberChannels != 1 {
                allSingleChannel = false
                break
            }
        }

        if allSingleChannel {
            let channelCount = bufferList.count
            guard channelCount >= 1 && channelCount <= channelCapacity else { return }
            var safeFrames = frames
            for ch in 0..<channelCount {
                guard bufferList[ch].mData != nil else { return }
                let capFrames = Int(bufferList[ch].mDataByteSize) / MemoryLayout<Float>.size
                safeFrames = min(safeFrames, capFrames)
            }
            guard safeFrames > 0 else { return }

            var offset = 0
            while offset < safeFrames {
                let count = min(Self.maxFrames, safeFrames - offset)
                for ch in 0..<channelCount {
                    guard let src = bufferList[ch].mData?.assumingMemoryBound(to: Float.self) else { continue }
                    let dst = inputScratchChannels[ch]
                    copySanitizingNonFinite(from: src + offset, to: dst, count: count)
                }
                for ch in channelCount..<channelCapacity {
                    vDSP_vclr(inputScratchChannels[ch], 1, vDSP_Length(count))
                }

                var processedChannels = channelCount
                let modified = runSlotsOnScratchLocked(chunkFrames: count,
                                                       currentChannels: &processedChannels,
                                                       sampleRate: sampleRate,
                                                       inputScratchChannels: inputScratchChannels,
                                                       outputScratchChannels: outputScratchChannels,
                                                       outputABLPtr: outputABLPtr,
                                                       pullState: pullState,
                                                       pullInputBlock: pullInputBlock)
                if modified {
                    for ch in 0..<channelCount {
                        guard let dst = bufferList[ch].mData?.assumingMemoryBound(to: Float.self) else { continue }
                        if channelCount == 1 {
                            if processedChannels == 1 {
                                memcpy(dst + offset, inputScratchChannels[0], count * MemoryLayout<Float>.size)
                            } else {
                                let left = inputScratchChannels[0]
                                let right = inputScratchChannels[1]
                                let target = dst + offset
                                for frame in 0..<count {
                                    let sum = 0.5 * (left[frame] + right[frame])
                                    target[frame] = sum.isFinite ? sum : 0
                                }
                            }
                        } else {
                            memcpy(dst + offset, inputScratchChannels[ch], count * MemoryLayout<Float>.size)
                        }
                    }
                }
                offset += count
            }
            return
        }

        // Interleaved buffer(s)
        for index in 0..<bufferList.count {
            let buf = bufferList[index]
            let channels = Int(buf.mNumberChannels)
            guard channels >= 1 && channels <= channelCapacity,
                  let base = buf.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let capFrames = Int(buf.mDataByteSize) / (MemoryLayout<Float>.size * channels)
            let safeFrames = min(frames, capFrames)
            guard safeFrames > 0 else { continue }

            var offset = 0
            while offset < safeFrames {
                let count = min(Self.maxFrames, safeFrames - offset)
                let chunkBase = base + offset * channels

                if channels == 1 {
                    copySanitizingNonFinite(from: chunkBase, to: inputScratchChannels[0], count: count)
                } else {
                    for frame in 0..<count {
                        let baseSample = frame * channels
                        for ch in 0..<channels {
                            let sample = chunkBase[baseSample + ch]
                            inputScratchChannels[ch][frame] = sample.isFinite ? sample : 0
                        }
                    }
                }
                for ch in channels..<channelCapacity {
                    vDSP_vclr(inputScratchChannels[ch], 1, vDSP_Length(count))
                }

                var processedChannels = channels
                let modified = runSlotsOnScratchLocked(chunkFrames: count,
                                                       currentChannels: &processedChannels,
                                                       sampleRate: sampleRate,
                                                       inputScratchChannels: inputScratchChannels,
                                                       outputScratchChannels: outputScratchChannels,
                                                       outputABLPtr: outputABLPtr,
                                                       pullState: pullState,
                                                       pullInputBlock: pullInputBlock)
                if modified {
                    if channels == 1 {
                        if processedChannels == 1 {
                            memcpy(chunkBase, inputScratchChannels[0], count * MemoryLayout<Float>.size)
                        } else {
                            let left = inputScratchChannels[0]
                            let right = inputScratchChannels[1]
                            for frame in 0..<count {
                                let sum = 0.5 * (left[frame] + right[frame])
                                chunkBase[frame] = sum.isFinite ? sum : 0
                            }
                        }
                    } else {
                        for frame in 0..<count {
                            let baseSample = frame * channels
                            for ch in 0..<channels {
                                let sample = inputScratchChannels[ch][frame]
                                chunkBase[baseSample + ch] = sample.isFinite ? sample : 0
                            }
                        }
                    }
                }
                offset += count
            }
        }
    }

    private func runSlotsOnScratchLocked(
        chunkFrames: Int,
        currentChannels: inout Int,
        sampleRate: Double,
        inputScratchChannels: UnsafeMutablePointer<UnsafeMutablePointer<Float>>,
        outputScratchChannels: UnsafeMutablePointer<UnsafeMutablePointer<Float>>,
        outputABLPtr: UnsafeMutablePointer<AudioBufferList>,
        pullState: UnsafeMutablePointer<PullInputState>,
        pullInputBlock: @escaping AURenderPullInputBlock
    ) -> Bool {
        var modified = false

        if processSingleSlotLocked(slot0,
                                   chunkFrames: chunkFrames,
                                   currentChannels: &currentChannels,
                                   sampleRate: sampleRate,
                                   inputScratchChannels: inputScratchChannels,
                                   outputScratchChannels: outputScratchChannels,
                                   outputABLPtr: outputABLPtr,
                                   pullState: pullState,
                                   pullInputBlock: pullInputBlock) {
            modified = true
        }
        if processSingleSlotLocked(slot1,
                                   chunkFrames: chunkFrames,
                                   currentChannels: &currentChannels,
                                   sampleRate: sampleRate,
                                   inputScratchChannels: inputScratchChannels,
                                   outputScratchChannels: outputScratchChannels,
                                   outputABLPtr: outputABLPtr,
                                   pullState: pullState,
                                   pullInputBlock: pullInputBlock) {
            modified = true
        }
        if processSingleSlotLocked(slot2,
                                   chunkFrames: chunkFrames,
                                   currentChannels: &currentChannels,
                                   sampleRate: sampleRate,
                                   inputScratchChannels: inputScratchChannels,
                                   outputScratchChannels: outputScratchChannels,
                                   outputABLPtr: outputABLPtr,
                                   pullState: pullState,
                                   pullInputBlock: pullInputBlock) {
            modified = true
        }

        sampleTimeCursor += Float64(chunkFrames)
        if !sampleTimeCursor.isFinite || sampleTimeCursor > 1e14 {
            sampleTimeCursor = 0
        }
        return modified
    }

    private func processSingleSlotLocked(
        _ slot: SlotRuntime?,
        chunkFrames: Int,
        currentChannels: inout Int,
        sampleRate: Double,
        inputScratchChannels: UnsafeMutablePointer<UnsafeMutablePointer<Float>>,
        outputScratchChannels: UnsafeMutablePointer<UnsafeMutablePointer<Float>>,
        outputABLPtr: UnsafeMutablePointer<AudioBufferList>,
        pullState: UnsafeMutablePointer<PullInputState>,
        pullInputBlock: @escaping AURenderPullInputBlock
    ) -> Bool {
        guard let slot, !slot.bypassed else { return false }
        if sampleRate.isFinite && sampleRate > 0 && abs(sampleRate - slot.sampleRate) > 1.0 {
            return false
        }

        let slotChannels = min(max(slot.channelCount, 1), channelCapacity)
        if currentChannels == 1 && slotChannels >= 2 {
            memcpy(inputScratchChannels[1], inputScratchChannels[0], chunkFrames * MemoryLayout<Float>.size)
            currentChannels = 2
        } else if currentChannels >= 2 && slotChannels == 1 {
            // Downmix stereo to mono cleanly before feeding a 1-channel AU so
            // left & right remain coherent instead of leaving channel 1 dry.
            let left = inputScratchChannels[0]
            let right = inputScratchChannels[1]
            for frame in 0..<chunkFrames {
                let sum = 0.5 * (left[frame] + right[frame])
                left[frame] = sum.isFinite ? sum : 0
            }
        }

        pullState.pointee.channelPtrs = inputScratchChannels
        pullState.pointee.activeChannels = slotChannels
        pullState.pointee.activeFrames = chunkFrames

        outputABLPtr.pointee.mNumberBuffers = UInt32(slotChannels)
        let abl = UnsafeMutableAudioBufferListPointer(outputABLPtr)
        let byteCount = UInt32(chunkFrames * MemoryLayout<Float>.size)
        for ch in 0..<slotChannels {
            vDSP_vclr(outputScratchChannels[ch], 1, vDSP_Length(chunkFrames))
            abl[ch].mNumberChannels = 1
            abl[ch].mDataByteSize = byteCount
            abl[ch].mData = UnsafeMutableRawPointer(outputScratchChannels[ch])
        }

        var flags = AudioUnitRenderActionFlags(rawValue: 0)
        var timestamp = AudioTimeStamp()
        timestamp.mSampleTime = sampleTimeCursor
        timestamp.mFlags = .sampleTimeValid

        let status = slot.renderBlock(
            &flags,
            &timestamp,
            AUAudioFrameCount(chunkFrames),
            0,
            outputABLPtr,
            pullInputBlock
        )
        guard status == noErr else { return false }

        for ch in 0..<slotChannels {
            let outPtr = outputScratchChannels[ch]
            for frame in 0..<chunkFrames {
                if !outPtr[frame].isFinite {
                    outPtr[frame] = 0
                }
            }
            let tmp = inputScratchChannels[ch]
            inputScratchChannels[ch] = outPtr
            outputScratchChannels[ch] = tmp
        }
        if currentChannels >= 2 && slotChannels == 1 {
            let copyBytes = chunkFrames * MemoryLayout<Float>.size
            for ch in 1..<currentChannels where ch < channelCapacity {
                memcpy(inputScratchChannels[ch], inputScratchChannels[0], copyBytes)
            }
        }
        return true
    }

    private func copySanitizingNonFinite(
        from src: UnsafePointer<Float>,
        to dst: UnsafeMutablePointer<Float>,
        count: Int
    ) {
        for index in 0..<count {
            let value = src[index]
            dst[index] = value.isFinite ? value : 0
        }
    }

    private func getSlotLocked(_ slot: Int) -> SlotRuntime? {
        switch slot {
        case 0: return slot0
        case 1: return slot1
        case 2: return slot2
        default: return nil
        }
    }

    private func setSlotLocked(_ slot: Int, _ runtime: SlotRuntime?) {
        switch slot {
        case 0: slot0 = runtime
        case 1: slot1 = runtime
        case 2: slot2 = runtime
        default: break
        }
    }

    private func recomputeActiveSlotsFlagLocked() {
        let anyActive = (slot0 != nil && slot0?.bypassed == false)
            || (slot1 != nil && slot1?.bypassed == false)
            || (slot2 != nil && slot2?.bypassed == false)
        Self.atomicStoreInt32(anyActive ? 1 : 0, into: &activeAUSlotsFlagBits)
    }

    private func isAudioUnitActiveInAnySlot(_ unit: AUAudioUnit) -> Bool {
        os_unfair_lock_lock(&renderLock)
        defer { os_unfair_lock_unlock(&renderLock) }
        return slot0?.audioUnit === unit || slot1?.audioUnit === unit || slot2?.audioUnit === unit
    }

    private func isUnitReferencedInSlots(_ unit: AUAudioUnit, excluding: Int) -> Bool {
        (excluding != 0 && slot0?.audioUnit === unit)
            || (excluding != 1 && slot1?.audioUnit === unit)
            || (excluding != 2 && slot2?.audioUnit === unit)
    }

    private static func atomicStoreInt32(_ value: Int32, into storage: UnsafeMutablePointer<Int32>) {
        while true {
            let current = OSAtomicAdd32Barrier(0, storage)
            if OSAtomicCompareAndSwap32Barrier(current, value, storage) { return }
        }
    }
}

/// Discovers, instantiates, bypasses, and hosts native Cocoa UI for a 3-slot serial chain
/// of installed AUv3 Audio Unit effects (with slot 0 mirrored to legacy properties).
///
/// Each active `TapGainEngine` registers an isolated `MixerRealtimeAUChainProcessor` running
/// at that engine's native sample rate and channel count and receives dedicated cloned
/// `AUAudioUnit` instances synchronized from the master editor unit, while persisting `fullState`
/// atomically per slot across restarts.
@MainActor
final class MixerAudioUnitHost: ObservableObject {
    static let shared = MixerAudioUnitHost()
    nonisolated static let slotCount = 3

    private nonisolated(unsafe) static var activeChainSlotsFlagBits: Int32 = 0

    /// Lock-free cross-thread query used by `AppVolumeMixer` to know whether any
    /// unbypassed AUv3 chain slot requires tapping active audio apps.
    nonisolated static var hasActiveChainSlots: Bool {
        withUnsafeMutablePointer(to: &activeChainSlotsFlagBits) { ptr in
            OSAtomicAdd32Barrier(0, ptr) != 0
        }
    }

    private static let selectedEffectDefaultsKey = "vorssaintSelectedAudioUnitEffectID"
    private static let bypassedDefaultsKey = "vorssaintAudioUnitEffectBypassed"

    private final class EngineChainEntry {
        let id: UUID
        let instanceToken = UUID()
        weak var processor: MixerRealtimeAUChainProcessor?
        let sampleRate: Double
        let channels: Int
        var slotClones: [AVAudioUnit?] = Array(repeating: nil, count: MixerAudioUnitHost.slotCount)
        var slotGenerations: [Int] = Array(repeating: 0, count: MixerAudioUnitHost.slotCount)

        init(id: UUID, processor: MixerRealtimeAUChainProcessor, sampleRate: Double, channels: Int) {
            self.id = id
            self.processor = processor
            self.sampleRate = sampleRate
            self.channels = channels
        }
    }

    @Published private(set) var availableEffects: [MixerAudioUnitComponentItem] = []
    @Published private(set) var chainSlots: [MixerAudioUnitComponentItem?]
    @Published private(set) var slotBypassStates: [Bool]
    @Published private(set) var slotAudioUnits: [AVAudioUnit?]
    @Published private(set) var slotSelectedIDs: [String?]
    @Published private(set) var slotLoadingStates: [Bool]

    // Legacy slot 0 mirrored state
    @Published private(set) var selectedEffectID: String?
    @Published private(set) var activeEffect: MixerAudioUnitComponentItem?
    @Published private(set) var activeAudioUnit: AVAudioUnit?
    @Published var isBypassed: Bool {
        didSet {
            guard !isSyncingSlot0Bypass else { return }
            setSlotBypassed(isBypassed, atSlot: 0)
        }
    }
    @Published private(set) var isLoading = false
    @Published private(set) var isEditorWindowVisible = false
    @Published private(set) var lastError: String?

    private let stateStore: MixerAUStateStore
    private let auConfigQueue = DispatchQueue(label: "com.vorssaint.utils.mixer.au-config", qos: .userInitiated)
    private var registeredEngines: [UUID: EngineChainEntry] = [:]
    private var editorWindows: [Int: NSWindow] = [:]
    private var windowCloseObservers: [Int: NSObjectProtocol] = [:]
    private var slotLoadGenerations: [Int] = Array(repeating: 0, count: slotCount)
    private var parameterObserverTokens: [Int: AUParameterObserverToken] = [:]
    private var presetObservations: [Int: NSKeyValueObservation] = [:]
    private var persistWorkItems: [Int: DispatchWorkItem] = [:]
    private var lastSyncedStates: [Int: [String: Any]] = [:]
    private var persistedSlotStateOnDisk: Set<Int> = []
    private var terminateObserver: NSObjectProtocol?
    private var hasScannedEffects = false
    private var isSyncingSlot0Bypass = false
    private var currentSampleRate: Double = 48_000

    private init(stateStore: MixerAUStateStore = MixerAUStateStore()) {
        self.stateStore = stateStore
        var initialIDs: [String?] = Array(repeating: nil, count: Self.slotCount)
        var initialBypassed: [Bool] = Array(repeating: false, count: Self.slotCount)
        for slot in 0..<Self.slotCount {
            initialIDs[slot] = UserDefaults.standard.string(forKey: Self.selectedEffectDefaultsKey(forSlot: slot))
            initialBypassed[slot] = UserDefaults.standard.bool(forKey: Self.bypassedDefaultsKey(forSlot: slot))
        }
        self.chainSlots = Array(repeating: nil, count: Self.slotCount)
        self.slotAudioUnits = Array(repeating: nil, count: Self.slotCount)
        self.slotLoadingStates = Array(repeating: false, count: Self.slotCount)
        self.slotSelectedIDs = initialIDs
        self.slotBypassStates = initialBypassed
        self.selectedEffectID = initialIDs[0]
        self.isBypassed = initialBypassed[0]
        updateActiveChainSlotsFlag()
        self.terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.persistAllSlotStates()
            }
        }
    }

    /// Registers a per-engine `MixerRealtimeAUChainProcessor` running at its own native format
    /// so every populated insert slot gets an isolated AUv3 clone at `sampleRate` and `channels`.
    nonisolated static func registerEngineChain(
        id: UUID,
        processor: MixerRealtimeAUChainProcessor,
        sampleRate: Double,
        channels: Int
    ) {
        let safeRate = sampleRate.isFinite && sampleRate >= 8_000 ? sampleRate : 48_000
        let safeChannels = min(max(channels, 1), MixerRealtimeAUChainProcessor.maxChannels)
        DispatchQueue.main.async { [weak processor] in
            MainActor.assumeIsolated {
                guard let processor, !processor.isStoppingOrInvalidated else { return }
                let host = MixerAudioUnitHost.shared
                host.pruneDeadEngineChains()
                if let existing = host.registeredEngines[id] {
                    for slot in 0..<Self.slotCount {
                        existing.slotGenerations[slot] &+= 1
                    }
                }
                let entry = EngineChainEntry(id: id, processor: processor, sampleRate: safeRate, channels: safeChannels)
                host.registeredEngines[id] = entry
                for slot in 0..<Self.slotCount where host.chainSlots[slot] != nil {
                    host.syncSlot(slot, toEngine: entry)
                }
            }
        }
    }

    /// Unregisters a stopping engine chain and clears any pending AU clone loads for it.
    nonisolated static func unregisterEngineChain(id: UUID) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let host = MixerAudioUnitHost.shared
                guard let removed = host.registeredEngines.removeValue(forKey: id) else { return }
                for slot in 0..<Self.slotCount {
                    removed.slotGenerations[slot] &+= 1
                    removed.slotClones[slot] = nil
                }
                if let processor = removed.processor, !processor.isInvalidated {
                    processor.markStopping()
                    host.auConfigQueue.async {
                        processor.invalidate()
                    }
                }
            }
        }
    }

    /// Flushes `fullState` of every populated slot immediately to owner-only binary plist storage.
    func persistAllSlotStates() {
        for slot in 0..<Self.slotCount {
            persistWorkItems.removeValue(forKey: slot)?.cancel()
            persistAndSyncStateIfNeeded(forSlot: slot, syncClones: false, forceCloneSync: false)
        }
    }

    func refreshAvailableEffects() {
        let shouldRestoreSaved = !hasScannedEffects
        hasScannedEffects = true
        DispatchQueue.global(qos: .userInitiated).async {
            let desc = AudioComponentDescription(componentType: kAudioUnitType_Effect,
                                                 componentSubType: 0,
                                                 componentManufacturer: 0,
                                                 componentFlags: 0,
                                                 componentFlagsMask: 0)
            let components = AVAudioUnitComponentManager.shared().components(matching: desc)
            var seen = Set<String>()
            var items: [MixerAudioUnitComponentItem] = []
            items.reserveCapacity(components.count)
            for component in components {
                let item = MixerAudioUnitComponentItem(component: component)
                guard seen.insert(item.id).inserted else { continue }
                items.append(item)
            }
            items.sort {
                let nameCmp = $0.name.localizedCaseInsensitiveCompare($1.name)
                if nameCmp != .orderedSame { return nameCmp == .orderedAscending }
                return $0.manufacturerName.localizedCaseInsensitiveCompare($1.manufacturerName) == .orderedAscending
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.availableEffects != items {
                    self.availableEffects = items
                }
                if shouldRestoreSaved {
                    for slot in 0..<Self.slotCount {
                        if let savedID = self.slotSelectedIDs[slot],
                           self.slotAudioUnits[slot] == nil,
                           items.contains(where: { $0.id == savedID }) {
                            self.selectEffect(id: savedID, atSlot: slot)
                        }
                    }
                }
            }
        }
    }

    func selectEffect(id: String?) {
        selectEffect(id: id, atSlot: 0)
    }

    func selectEffect(_ item: MixerAudioUnitComponentItem?) {
        selectEffect(item, atSlot: 0)
    }

    func selectEffect(id: String?, atSlot slot: Int) {
        guard slot >= 0 && slot < Self.slotCount else { return }
        guard let id, !id.isEmpty else {
            clearSlot(slot)
            return
        }
        guard let item = availableEffects.first(where: { $0.id == id }) else {
            lastError = L10n.shared.language == .ru
                ? "Выбранный Audio Unit не найден"
                : "Selected Audio Unit is unavailable"
            return
        }
        selectEffect(item, atSlot: slot)
    }

    func selectEffect(_ item: MixerAudioUnitComponentItem?, atSlot slot: Int) {
        guard slot >= 0 && slot < Self.slotCount else { return }
        guard let item else {
            clearSlot(slot)
            return
        }
        if chainSlots[slot]?.id == item.id && slotAudioUnits[slot] != nil {
            return
        }

        slotLoadGenerations[slot] &+= 1
        let generation = slotLoadGenerations[slot]
        persistWorkItems.removeValue(forKey: slot)?.cancel()
        detachMasterObservers(forSlot: slot)
        lastSyncedStates.removeValue(forKey: slot)
        persistedSlotStateOnDisk.remove(slot)
        slotSelectedIDs[slot] = item.id
        if slot == 0 {
            selectedEffectID = item.id
        }
        UserDefaults.standard.set(item.id, forKey: Self.selectedEffectDefaultsKey(forSlot: slot))
        slotLoadingStates[slot] = true
        isLoading = slotLoadingStates.contains(true)
        lastError = nil

        let instantiationOptions = Self.instantiationOptions(for: item)
        AVAudioUnit.instantiate(with: item.componentDescription, options: instantiationOptions) { [weak self] audioUnit, error in
            DispatchQueue.main.async {
                guard let self, self.slotLoadGenerations[slot] == generation else { return }
                self.slotLoadingStates[slot] = false
                self.isLoading = self.slotLoadingStates.contains(true)

                if let error {
                    self.detachMasterObservers(forSlot: slot)
                    self.slotAudioUnits[slot] = nil
                    self.chainSlots[slot] = nil
                    self.updateActiveChainSlotsFlag()
                    if slot == 0 {
                        self.activeAudioUnit = nil
                        self.activeEffect = nil
                    }
                    self.clearRegisteredEngines(slot: slot)
                    MixerRealtimeAUChainProcessor.shared.configureSlot(
                        slot,
                        audioUnit: nil,
                        bypassed: self.slotBypassStates[slot],
                        sampleRate: self.currentSampleRate
                    )
                    self.lastError = error.localizedDescription
                    return
                }
                guard let audioUnit else {
                    self.detachMasterObservers(forSlot: slot)
                    self.slotAudioUnits[slot] = nil
                    self.chainSlots[slot] = nil
                    self.updateActiveChainSlotsFlag()
                    if slot == 0 {
                        self.activeAudioUnit = nil
                        self.activeEffect = nil
                    }
                    self.clearRegisteredEngines(slot: slot)
                    MixerRealtimeAUChainProcessor.shared.configureSlot(
                        slot,
                        audioUnit: nil,
                        bypassed: self.slotBypassStates[slot],
                        sampleRate: self.currentSampleRate
                    )
                    self.lastError = L10n.shared.language == .ru
                        ? "Не удалось создать экземпляр Audio Unit"
                        : "Failed to instantiate Audio Unit"
                    return
                }

                // Restore persisted `fullState` BEFORE wiring live parameter observers and cloning to engines.
                if let savedState = self.stateStore.loadState(forSlot: slot, componentID: item.id) {
                    let sanitizedSaved = MixerAUStateStore.sanitizeFullState(savedState)
                    if !sanitizedSaved.isEmpty {
                        audioUnit.auAudioUnit.fullState = sanitizedSaved
                        self.lastSyncedStates[slot] = sanitizedSaved
                        self.persistedSlotStateOnDisk.insert(slot)
                    }
                } else if let initialRaw = audioUnit.auAudioUnit.fullState {
                    self.lastSyncedStates[slot] = MixerAUStateStore.sanitizeFullState(initialRaw)
                }

                let bypassed = self.slotBypassStates[slot]
                audioUnit.auAudioUnit.shouldBypassEffect = bypassed
                self.slotAudioUnits[slot] = audioUnit
                self.chainSlots[slot] = item
                self.updateActiveChainSlotsFlag()
                if slot == 0 {
                    self.activeAudioUnit = audioUnit
                    self.activeEffect = item
                    self.selectedEffectID = item.id
                }
                self.lastError = nil

                self.attachMasterObservers(for: audioUnit, atSlot: slot)
                self.syncSlotToAllRegisteredEngines(slot)

                if self.editorWindows[slot]?.isVisible == true {
                    self.attachViewController(for: audioUnit, title: item.name, slot: slot)
                }
            }
        }
    }

    func setBypassed(_ bypassed: Bool) {
        setSlotBypassed(bypassed, atSlot: 0)
    }

    func setSlotBypassed(_ bypassed: Bool, atSlot slot: Int) {
        guard slot >= 0 && slot < Self.slotCount else { return }
        if slotBypassStates[slot] != bypassed {
            slotBypassStates[slot] = bypassed
        }
        updateActiveChainSlotsFlag()
        UserDefaults.standard.set(bypassed, forKey: Self.bypassedDefaultsKey(forSlot: slot))
        slotAudioUnits[slot]?.auAudioUnit.shouldBypassEffect = bypassed
        MixerRealtimeAUChainProcessor.shared.setSlotBypassed(bypassed, atSlot: slot)

        pruneDeadEngineChains()
        for entry in registeredEngines.values {
            guard let processor = entry.processor, !processor.isStoppingOrInvalidated else { continue }
            let clone = entry.slotClones[slot]
            auConfigQueue.async { [weak processor, clone] in
                guard let processor, !processor.isStoppingOrInvalidated else { return }
                processor.withActiveConfigLock {
                    clone?.auAudioUnit.shouldBypassEffect = bypassed
                }
                processor.setSlotBypassed(bypassed, atSlot: slot)
            }
        }

        if slot == 0 && isBypassed != bypassed {
            isSyncingSlot0Bypass = true
            isBypassed = bypassed
            isSyncingSlot0Bypass = false
        }
    }

    func openEffectUI() {
        openEditorWindow(forSlot: 0)
    }

    func openEditorWindow() {
        openEditorWindow(forSlot: 0)
    }

    func openEditorWindow(forSlot slot: Int) {
        guard slot >= 0 && slot < Self.slotCount,
              let audioUnit = slotAudioUnits[slot] else { return }
        let baseTitle = chainSlots[slot]?.name ?? audioUnit.name
        let title = Self.slotCount > 1 ? "\(baseTitle) (\(slot + 1))" : baseTitle
        if let window = editorWindows[slot], window.isVisible {
            window.title = title
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            refreshEditorWindowVisibility()
            return
        }
        attachViewController(for: audioUnit, title: title, slot: slot)
    }

    func closeEffectUI() {
        for slot in 0..<Self.slotCount {
            closeEditorWindow(forSlot: slot)
        }
        isEditorWindowVisible = false
    }

    func closeEditorWindow(forSlot slot: Int) {
        persistWorkItems.removeValue(forKey: slot)?.cancel()
        persistAndSyncStateIfNeeded(forSlot: slot, syncClones: true, forceCloneSync: false)
        guard let window = editorWindows[slot] else { return }
        window.orderOut(nil)
        window.contentViewController = nil
        refreshEditorWindowVisibility()
    }

    func removeEffect() {
        clearSlot(0)
    }

    func clearSlot(_ slot: Int) {
        guard slot >= 0 && slot < Self.slotCount else { return }
        slotLoadGenerations[slot] &+= 1
        persistWorkItems.removeValue(forKey: slot)?.cancel()
        detachMasterObservers(forSlot: slot)
        lastSyncedStates.removeValue(forKey: slot)
        persistedSlotStateOnDisk.remove(slot)
        slotAudioUnits[slot]?.auAudioUnit.shouldBypassEffect = true
        slotAudioUnits[slot] = nil
        chainSlots[slot] = nil
        slotSelectedIDs[slot] = nil
        slotLoadingStates[slot] = false
        updateActiveChainSlotsFlag()
        isLoading = slotLoadingStates.contains(true)
        lastError = nil
        closeEditorWindow(forSlot: slot)
        stateStore.removeState(forSlot: slot)
        clearRegisteredEngines(slot: slot)
        MixerRealtimeAUChainProcessor.shared.configureSlot(
            slot,
            audioUnit: nil,
            bypassed: true,
            sampleRate: currentSampleRate
        )
        UserDefaults.standard.removeObject(forKey: Self.selectedEffectDefaultsKey(forSlot: slot))

        if slot == 0 {
            activeAudioUnit = nil
            activeEffect = nil
            selectedEffectID = nil
        }
    }

    func updateSampleRate(_ sampleRate: Double) {
        let safeRate = sampleRate.isFinite && sampleRate >= 8_000 ? sampleRate : 48_000
        guard abs(safeRate - currentSampleRate) > 1.0 else { return }
        currentSampleRate = safeRate
        if MixerRealtimeAUChainProcessor.shared.hasActiveSlots {
            for slot in 0..<Self.slotCount {
                if let unit = slotAudioUnits[slot] {
                    MixerRealtimeAUChainProcessor.shared.configureSlot(
                        slot,
                        audioUnit: unit.auAudioUnit,
                        legacyAudioUnit: unit.audioUnit,
                        bypassed: slotBypassStates[slot],
                        sampleRate: safeRate
                    )
                }
            }
        }
    }

    private func attachViewController(for audioUnit: AVAudioUnit, title: String, slot: Int) {
        let targetUnitID = chainSlots[slot]?.id
        audioUnit.auAudioUnit.requestViewController { [weak self] viewController in
            DispatchQueue.main.async {
                guard let self,
                      self.slotAudioUnits[slot] === audioUnit,
                      self.chainSlots[slot]?.id == targetUnitID else { return }
                let resolvedController: NSViewController
                if let viewController {
                    resolvedController = viewController
                } else {
                    let generic = AUGenericViewController()
                    generic.auAudioUnit = audioUnit.auAudioUnit
                    resolvedController = generic
                }
                self.presentEditorWindow(with: resolvedController, title: title, slot: slot)
            }
        }
    }

    private func presentEditorWindow(with viewController: NSViewController, title: String, slot: Int) {
        let window: NSWindow
        if let existing = editorWindows[slot] {
            window = existing
        } else {
            let created = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 340),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow],
                backing: .buffered,
                defer: false
            )
            created.level = .floating
            created.isReleasedWhenClosed = false
            created.collectionBehavior = [.moveToActiveSpace, .transient]
            editorWindows[slot] = created
            windowCloseObservers[slot] = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: created,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.persistWorkItems.removeValue(forKey: slot)?.cancel()
                    self.persistAndSyncStateIfNeeded(forSlot: slot, syncClones: true, forceCloneSync: false)
                    self.refreshEditorWindowVisibility()
                }
            }
            window = created
        }

        window.title = title
        window.contentViewController = viewController
        let preferredSize = viewController.preferredContentSize
        if preferredSize.width >= 180 && preferredSize.height >= 120 {
            window.setContentSize(NSSize(width: min(max(preferredSize.width, 320), 960),
                                         height: min(max(preferredSize.height, 200), 720)))
        }
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isEditorWindowVisible = true
    }

    private func refreshEditorWindowVisibility() {
        isEditorWindowVisible = editorWindows.values.contains { $0.isVisible }
    }

    private func updateActiveChainSlotsFlag() {
        let anyActive = (0..<Self.slotCount).contains { chainSlots[$0] != nil && !slotBypassStates[$0] }
        withUnsafeMutablePointer(to: &Self.activeChainSlotsFlagBits) { ptr in
            let target: Int32 = anyActive ? 1 : 0
            while true {
                let current = OSAtomicAdd32Barrier(0, ptr)
                if current == target || OSAtomicCompareAndSwap32Barrier(current, target, ptr) {
                    return
                }
            }
        }
    }

    private func pruneDeadEngineChains() {
        let deadIDs = registeredEngines.compactMap { $0.value.processor == nil ? $0.key : nil }
        for id in deadIDs {
            registeredEngines.removeValue(forKey: id)
        }
    }

    private func clearRegisteredEngines(slot: Int) {
        pruneDeadEngineChains()
        for entry in registeredEngines.values {
            entry.slotGenerations[slot] &+= 1
            entry.slotClones[slot] = nil
            guard let processor = entry.processor, !processor.isStoppingOrInvalidated else { continue }
            let rate = entry.sampleRate
            let channels = entry.channels
            auConfigQueue.async { [weak processor] in
                guard let processor, !processor.isStoppingOrInvalidated else { return }
                processor.configureSlot(slot, audioUnit: nil, bypassed: true, sampleRate: rate, channels: channels)
            }
        }
    }

    private func syncSlotToAllRegisteredEngines(_ slot: Int) {
        pruneDeadEngineChains()
        for entry in registeredEngines.values {
            syncSlot(slot, toEngine: entry)
        }
    }

    private func syncSlot(_ slot: Int, toEngine entry: EngineChainEntry) {
        guard let item = chainSlots[slot],
              let processor = entry.processor,
              !processor.isStoppingOrInvalidated else {
            return
        }
        entry.slotGenerations[slot] &+= 1
        let engineGeneration = entry.slotGenerations[slot]
        let engineID = entry.id
        let entryToken = entry.instanceToken
        let componentID = item.id
        let sampleRate = entry.sampleRate
        let channels = entry.channels
        let instantiationOptions = Self.instantiationOptions(for: item)

        AVAudioUnit.instantiate(with: item.componentDescription, options: instantiationOptions) { [weak self] clone, _ in
            DispatchQueue.main.async {
                guard let self,
                      let currentEntry = self.registeredEngines[engineID],
                      currentEntry.instanceToken == entryToken,
                      currentEntry.slotGenerations[slot] == engineGeneration,
                      self.chainSlots[slot]?.id == componentID,
                      let currentMaster = self.slotAudioUnits[slot],
                      let liveProcessor = currentEntry.processor,
                      !liveProcessor.isStoppingOrInvalidated,
                      let clone else {
                    return
                }

                let bypassed = self.slotBypassStates[slot]
                let paramPairs = Self.snapshotParameterValues(from: currentMaster.auAudioUnit)
                if let masterState = currentMaster.auAudioUnit.fullState, !masterState.isEmpty {
                    let sanitized = MixerAUStateStore.sanitizeFullState(masterState)
                    if !sanitized.isEmpty {
                        clone.auAudioUnit.fullState = sanitized
                    }
                }
                Self.applyParameterValues(paramPairs, to: clone.auAudioUnit)
                clone.auAudioUnit.shouldBypassEffect = bypassed
                currentEntry.slotClones[slot] = clone

                self.auConfigQueue.async { [weak liveProcessor, clone] in
                    guard let liveProcessor, !liveProcessor.isStoppingOrInvalidated else { return }
                    liveProcessor.configureSlot(
                        slot,
                        audioUnit: clone.auAudioUnit,
                        legacyAudioUnit: clone.audioUnit,
                        bypassed: bypassed,
                        sampleRate: sampleRate,
                        channels: channels
                    )
                }
            }
        }
    }

    private func attachMasterObservers(for audioUnit: AVAudioUnit, atSlot slot: Int) {
        let unitID = ObjectIdentifier(audioUnit)
        if let tree = audioUnit.auAudioUnit.parameterTree {
            parameterObserverTokens[slot] = tree.token(byAddingParameterObserver: { [weak self] address, value in
                DispatchQueue.main.async { [weak self] in
                    self?.handleMasterParameterChanged(slot: slot, unitID: unitID, address: address, value: value)
                }
            })
        }
        presetObservations[slot] = audioUnit.auAudioUnit.observe(\.currentPreset, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { [weak self] in
                self?.handleMasterPresetChanged(slot: slot, unitID: unitID)
            }
        }
    }

    private func detachMasterObservers(forSlot slot: Int) {
        if let token = parameterObserverTokens.removeValue(forKey: slot),
           let tree = slotAudioUnits[slot]?.auAudioUnit.parameterTree {
            tree.removeParameterObserver(token)
        }
        presetObservations.removeValue(forKey: slot)?.invalidate()
    }

    private func handleMasterParameterChanged(
        slot: Int,
        unitID: ObjectIdentifier,
        address: AUParameterAddress,
        value: AUValue
    ) {
        guard let masterUnit = slotAudioUnits[slot], ObjectIdentifier(masterUnit) == unitID else { return }
        pruneDeadEngineChains()
        for entry in registeredEngines.values {
            guard let processor = entry.processor,
                  !processor.isStoppingOrInvalidated,
                  let clone = entry.slotClones[slot] else {
                continue
            }
            auConfigQueue.async { [weak processor, clone] in
                processor?.withActiveConfigLock {
                    guard let cloneParam = clone.auAudioUnit.parameterTree?.parameter(withAddress: address),
                          abs(cloneParam.value - value) > 1e-6 else {
                        return
                    }
                    cloneParam.value = value
                }
            }
        }
        schedulePersistSlotState(slot)
    }

    private func handleMasterPresetChanged(slot: Int, unitID: ObjectIdentifier) {
        guard let masterUnit = slotAudioUnits[slot], ObjectIdentifier(masterUnit) == unitID else { return }
        persistWorkItems.removeValue(forKey: slot)?.cancel()
        persistAndSyncStateIfNeeded(forSlot: slot, syncClones: true, forceCloneSync: true)
    }

    private func schedulePersistSlotState(_ slot: Int) {
        persistWorkItems.removeValue(forKey: slot)?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.persistWorkItems.removeValue(forKey: slot)
                self.persistAndSyncStateIfNeeded(forSlot: slot, syncClones: false, forceCloneSync: false)
            }
        }
        persistWorkItems[slot] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func persistAndSyncStateIfNeeded(forSlot slot: Int, syncClones: Bool, forceCloneSync: Bool) {
        guard slot >= 0 && slot < Self.slotCount,
              let item = chainSlots[slot],
              let masterUnit = slotAudioUnits[slot],
              let rawState = masterUnit.auAudioUnit.fullState else {
            return
        }
        let sanitized = MixerAUStateStore.sanitizeFullState(rawState)
        guard !sanitized.isEmpty else { return }
        let stateChanged = lastSyncedStates[slot].map {
            !NSDictionary(dictionary: sanitized).isEqual(to: $0)
        } ?? true

        if stateChanged {
            lastSyncedStates[slot] = sanitized
        }
        if stateChanged || !persistedSlotStateOnDisk.contains(slot) {
            if stateStore.saveState(sanitized, componentID: item.id, forSlot: slot) {
                persistedSlotStateOnDisk.insert(slot)
            }
        }

        if syncClones && (forceCloneSync || stateChanged) {
            pruneDeadEngineChains()
            let paramPairs = Self.snapshotParameterValues(from: masterUnit.auAudioUnit)
            let stateData: Data? = PropertyListSerialization.propertyList(sanitized, isValidFor: .binary)
                ? (try? PropertyListSerialization.data(fromPropertyList: sanitized, format: .binary, options: 0))
                : nil
            for entry in registeredEngines.values {
                guard let processor = entry.processor,
                      !processor.isStoppingOrInvalidated,
                      let clone = entry.slotClones[slot] else { continue }
                auConfigQueue.async { [weak processor, clone] in
                    processor?.withActiveConfigLock {
                        if let stateData,
                           let restored = (try? PropertyListSerialization.propertyList(
                               from: stateData, options: [], format: nil
                           )) as? [String: Any] {
                            clone.auAudioUnit.fullState = restored
                        }
                        Self.applyParameterValues(paramPairs, to: clone.auAudioUnit)
                    }
                }
            }
        }
    }

    nonisolated private static func snapshotParameterValues(from master: AUAudioUnit) -> [(AUParameterAddress, AUValue)] {
        guard let masterParams = master.parameterTree?.allParameters else { return [] }
        return masterParams.map { ($0.address, $0.value) }
    }

    nonisolated private static func applyParameterValues(
        _ pairs: [(AUParameterAddress, AUValue)],
        to clone: AUAudioUnit
    ) {
        guard !pairs.isEmpty, let cloneTree = clone.parameterTree else { return }
        for (address, value) in pairs {
            if let target = cloneTree.parameter(withAddress: address),
               abs(target.value - value) > 1e-6 {
                target.value = value
            }
        }
    }

    private static func instantiationOptions(for item: MixerAudioUnitComponentItem) -> AudioComponentInstantiationOptions {
        item.componentDescription.componentManufacturer == kAudioUnitManufacturer_Apple
            ? [.loadInProcess]
            : []
    }

    private static func selectedEffectDefaultsKey(forSlot slot: Int) -> String {
        slot == 0 ? selectedEffectDefaultsKey : "\(selectedEffectDefaultsKey)Slot\(slot)"
    }

    private static func bypassedDefaultsKey(forSlot slot: Int) -> String {
        slot == 0 ? bypassedDefaultsKey : "\(bypassedDefaultsKey)Slot\(slot)"
    }
}
