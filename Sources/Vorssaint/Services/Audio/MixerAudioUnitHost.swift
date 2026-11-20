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

/// Real-time lock-free 3-slot serial AUv3 insert chain + Fletcher-Munson loudness EQ processor.
/// Preallocates all scratch buffers and pull-input state in `init()` so CoreAudio IOProc callbacks
/// perform strictly zero heap allocations and never block waiting on UI slot swaps.
final class MixerRealtimeAUChainProcessor: @unchecked Sendable {
    static let shared = MixerRealtimeAUChainProcessor()
    static let slotCount = 3
    static let maxFrames = 4096
    static let maxChannels = 8

    private final class SlotRuntime {
        let audioUnit: AUAudioUnit
        let renderBlock: AURenderBlock
        let channelCount: Int
        let sampleRate: Double
        var bypassed: Bool

        init(
            audioUnit: AUAudioUnit,
            renderBlock: @escaping AURenderBlock,
            channelCount: Int,
            sampleRate: Double,
            bypassed: Bool
        ) {
            self.audioUnit = audioUnit
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

    private let configLock = NSLock()
    private var renderLock = os_unfair_lock()
    private var activeAUSlotsFlagBits: Int32 = 0

    private var slot0: SlotRuntime?
    private var slot1: SlotRuntime?
    private var slot2: SlotRuntime?
    private var sampleTimeCursor: Float64 = 0

    private let loudnessProcessor = FletcherMunsonLoudness.LoudnessBiquadProcessor()

    // Preallocated scratch storage (zero allocations on audio thread)
    private let inputScratchChannels: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    private let outputScratchChannels: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    private let outputABLRaw: UnsafeMutableRawPointer
    private let outputABLPtr: UnsafeMutablePointer<AudioBufferList>
    private let pullState: UnsafeMutablePointer<PullInputState>
    private let pullInputBlock: AURenderPullInputBlock

    var hasActiveSlots: Bool {
        withUnsafeMutablePointer(to: &activeAUSlotsFlagBits) { ptr in
            OSAtomicAdd32Barrier(0, ptr) != 0
        }
    }

    var isLoudnessBypassed: Bool {
        loudnessProcessor.isBypassed
    }

    init() {
        let inPtrs = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: Self.maxChannels)
        let outPtrs = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: Self.maxChannels)
        for ch in 0..<Self.maxChannels {
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
        let ablByteCount = buffersOffset + Self.maxChannels * MemoryLayout<AudioBuffer>.stride
        let rawABL = UnsafeMutableRawPointer.allocate(byteCount: ablByteCount,
                                                      alignment: MemoryLayout<AudioBufferList>.alignment)
        memset(rawABL, 0, ablByteCount)
        self.outputABLRaw = rawABL
        let ablPtr = rawABL.assumingMemoryBound(to: AudioBufferList.self)
        ablPtr.pointee.mNumberBuffers = UInt32(Self.maxChannels)
        self.outputABLPtr = ablPtr

        let statePtr = UnsafeMutablePointer<PullInputState>.allocate(capacity: 1)
        statePtr.initialize(to: PullInputState(channelPtrs: inPtrs, activeChannels: 2, activeFrames: 0))
        self.pullState = statePtr

        // Constructed once at init capturing only a trivial raw pointer (zero ARC/heap allocations per render).
        self.pullInputBlock = { _, _, frameCount, _, inputDataPtr in
            let state = statePtr.pointee
            let inputData = UnsafeMutableAudioBufferListPointer(inputDataPtr)
            let copyFrames = min(Int(frameCount), state.activeFrames)
            let copyBytes = max(0, copyFrames) * MemoryLayout<Float>.size

            for ch in 0..<inputData.count {
                if ch < state.activeChannels {
                    let src = state.channelPtrs[ch]
                    if let dst = inputData[ch].mData {
                        let maxBytes = Int(inputData[ch].mDataByteSize)
                        let bytesToCopy = min(copyBytes, maxBytes)
                        if bytesToCopy > 0 {
                            memcpy(dst, src, bytesToCopy)
                        }
                        if maxBytes > bytesToCopy {
                            memset(dst.advanced(by: bytesToCopy), 0, maxBytes - bytesToCopy)
                        }
                        inputData[ch].mDataByteSize = UInt32(bytesToCopy)
                    } else {
                        inputData[ch].mData = UnsafeMutableRawPointer(src)
                        inputData[ch].mDataByteSize = UInt32(copyBytes)
                    }
                } else if let dst = inputData[ch].mData {
                    memset(dst, 0, Int(inputData[ch].mDataByteSize))
                }
            }
            return noErr
        }
    }

    deinit {
        if let s0 = slot0, !isUnitReferencedInSlots(s0.audioUnit, excluding: 0) {
            s0.audioUnit.deallocateRenderResources()
        }
        if let s1 = slot1, !isUnitReferencedInSlots(s1.audioUnit, excluding: 1) {
            s1.audioUnit.deallocateRenderResources()
        }
        if let s2 = slot2, !isUnitReferencedInSlots(s2.audioUnit, excluding: 2) {
            s2.audioUnit.deallocateRenderResources()
        }
        pullState.deinitialize(count: 1)
        pullState.deallocate()
        outputABLRaw.deallocate()
        for ch in 0..<Self.maxChannels {
            inputScratchChannels[ch].deinitialize(count: Self.maxFrames)
            outputScratchChannels[ch].deinitialize(count: Self.maxFrames)
            inputScratchChannels[ch].deallocate()
            outputScratchChannels[ch].deallocate()
        }
        inputScratchChannels.deinitialize(count: Self.maxChannels)
        outputScratchChannels.deinitialize(count: Self.maxChannels)
        inputScratchChannels.deallocate()
        outputScratchChannels.deallocate()
    }

    /// Configures a single insert slot (`0..<3`) off the audio thread: allocates render
    /// resources at `maxFrames = 4096`, captures `renderBlock`, and swaps into place under `os_unfair_lock`.
    func configureSlot(
        _ slot: Int,
        audioUnit: AUAudioUnit?,
        bypassed: Bool,
        sampleRate: Double = 48_000,
        channels: Int = 2
    ) {
        guard slot >= 0 && slot < Self.slotCount else { return }
        let safeRate = sampleRate.isFinite && sampleRate >= 8_000 ? sampleRate : 48_000
        let safeChannels = min(max(channels, 1), Self.maxChannels)

        configLock.lock()
        defer { configLock.unlock() }

        guard let au = audioUnit else {
            os_unfair_lock_lock(&renderLock)
            let oldRuntime = getSlotLocked(slot)
            setSlotLocked(slot, nil)
            recomputeActiveSlotsFlagLocked()
            os_unfair_lock_unlock(&renderLock)

            if let oldRuntime, !isAudioUnitActiveInAnySlot(oldRuntime.audioUnit) {
                oldRuntime.audioUnit.deallocateRenderResources()
            }
            return
        }

        // Fast path: same AU instance at identical format only needs bypass state update.
        os_unfair_lock_lock(&renderLock)
        if let existing = getSlotLocked(slot),
           existing.audioUnit === au,
           abs(existing.sampleRate - safeRate) <= 1.0,
           existing.channelCount == safeChannels,
           au.renderResourcesAllocated {
            existing.bypassed = bypassed
            recomputeActiveSlotsFlagLocked()
            os_unfair_lock_unlock(&renderLock)
            au.shouldBypassEffect = bypassed
            return
        }
        os_unfair_lock_unlock(&renderLock)

        // Prepare render resources off the render lock.
        if au.renderResourcesAllocated {
            au.deallocateRenderResources()
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
                if outCount >= 1 && outCount <= Self.maxChannels {
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
           currentFormat.channelCount <= UInt32(Self.maxChannels) {
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
            os_unfair_lock_lock(&renderLock)
            let oldRuntime = getSlotLocked(slot)
            setSlotLocked(slot, nil)
            recomputeActiveSlotsFlagLocked()
            os_unfair_lock_unlock(&renderLock)
            if let oldRuntime,
               oldRuntime.audioUnit !== au,
               !isAudioUnitActiveInAnySlot(oldRuntime.audioUnit) {
                oldRuntime.audioUnit.deallocateRenderResources()
            }
            return
        }

        au.shouldBypassEffect = bypassed
        let capturedRenderBlock = au.renderBlock
        let newRuntime = SlotRuntime(
            audioUnit: au,
            renderBlock: capturedRenderBlock,
            channelCount: resolvedChannels,
            sampleRate: safeRate,
            bypassed: bypassed
        )

        os_unfair_lock_lock(&renderLock)
        let oldRuntime = getSlotLocked(slot)
        setSlotLocked(slot, newRuntime)
        recomputeActiveSlotsFlagLocked()
        os_unfair_lock_unlock(&renderLock)

        if let oldRuntime,
           oldRuntime.audioUnit !== au,
           !isAudioUnitActiveInAnySlot(oldRuntime.audioUnit) {
            oldRuntime.audioUnit.deallocateRenderResources()
        }
    }

    func setSlotBypassed(_ bypassed: Bool, atSlot slot: Int) {
        guard slot >= 0 && slot < Self.slotCount else { return }
        configLock.lock()
        defer { configLock.unlock() }

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
        guard hasActiveSlots else { return true }
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
        var allSingleChannel = true
        for index in 0..<bufferList.count {
            if bufferList[index].mNumberChannels != 1 {
                allSingleChannel = false
                break
            }
        }

        if allSingleChannel {
            let channelCount = bufferList.count
            guard channelCount >= 1 && channelCount <= Self.maxChannels else { return }
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
                for ch in channelCount..<Self.maxChannels {
                    vDSP_vclr(inputScratchChannels[ch], 1, vDSP_Length(count))
                }

                let modified = runSlotsOnScratchLocked(chunkFrames: count,
                                                       sourceChannels: channelCount,
                                                       sampleRate: sampleRate)
                if modified {
                    for ch in 0..<channelCount {
                        guard let dst = bufferList[ch].mData?.assumingMemoryBound(to: Float.self) else { continue }
                        if channelCount == 1 {
                            let left = inputScratchChannels[0]
                            let right = inputScratchChannels[1]
                            let target = dst + offset
                            for frame in 0..<count {
                                let sum = 0.5 * (left[frame] + right[frame])
                                target[frame] = sum.isFinite ? sum : 0
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
            guard channels >= 1 && channels <= Self.maxChannels,
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
                for ch in channels..<Self.maxChannels {
                    vDSP_vclr(inputScratchChannels[ch], 1, vDSP_Length(count))
                }

                let modified = runSlotsOnScratchLocked(chunkFrames: count,
                                                       sourceChannels: channels,
                                                       sampleRate: sampleRate)
                if modified {
                    if channels == 1 {
                        let left = inputScratchChannels[0]
                        let right = inputScratchChannels[1]
                        for frame in 0..<count {
                            let sum = 0.5 * (left[frame] + right[frame])
                            chunkBase[frame] = sum.isFinite ? sum : 0
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
        sourceChannels: Int,
        sampleRate: Double
    ) -> Bool {
        var modified = false
        var currentChannels = sourceChannels

        if processSingleSlotLocked(slot0,
                                   chunkFrames: chunkFrames,
                                   currentChannels: &currentChannels,
                                   sampleRate: sampleRate) {
            modified = true
        }
        if processSingleSlotLocked(slot1,
                                   chunkFrames: chunkFrames,
                                   currentChannels: &currentChannels,
                                   sampleRate: sampleRate) {
            modified = true
        }
        if processSingleSlotLocked(slot2,
                                   chunkFrames: chunkFrames,
                                   currentChannels: &currentChannels,
                                   sampleRate: sampleRate) {
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
        sampleRate: Double
    ) -> Bool {
        guard let slot, !slot.bypassed else { return false }
        if sampleRate.isFinite && sampleRate > 0 && abs(sampleRate - slot.sampleRate) > 1.0 {
            return false
        }

        let slotChannels = min(max(slot.channelCount, 1), Self.maxChannels)
        if currentChannels == 1 && slotChannels >= 2 {
            memcpy(inputScratchChannels[1], inputScratchChannels[0], chunkFrames * MemoryLayout<Float>.size)
            currentChannels = 2
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
@MainActor
final class MixerAudioUnitHost: ObservableObject {
    static let shared = MixerAudioUnitHost()
    static let slotCount = 3

    private static let selectedEffectDefaultsKey = "vorssaintSelectedAudioUnitEffectID"
    private static let bypassedDefaultsKey = "vorssaintAudioUnitEffectBypassed"

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

    private var editorWindows: [Int: NSWindow] = [:]
    private var windowCloseObservers: [Int: NSObjectProtocol] = [:]
    private var slotLoadGenerations: [Int] = Array(repeating: 0, count: slotCount)
    private var hasScannedEffects = false
    private var isSyncingSlot0Bypass = false
    private var currentSampleRate: Double = 48_000

    private init() {
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
        slotSelectedIDs[slot] = item.id
        if slot == 0 {
            selectedEffectID = item.id
        }
        UserDefaults.standard.set(item.id, forKey: Self.selectedEffectDefaultsKey(forSlot: slot))
        slotLoadingStates[slot] = true
        isLoading = slotLoadingStates.contains(true)
        lastError = nil

        let instantiationOptions: AudioComponentInstantiationOptions =
            item.componentDescription.componentManufacturer == kAudioUnitManufacturer_Apple
            ? [.loadInProcess]
            : []
        AVAudioUnit.instantiate(with: item.componentDescription, options: instantiationOptions) { [weak self] audioUnit, error in
            DispatchQueue.main.async {
                guard let self, self.slotLoadGenerations[slot] == generation else { return }
                self.slotLoadingStates[slot] = false
                self.isLoading = self.slotLoadingStates.contains(true)

                if let error {
                    self.slotAudioUnits[slot] = nil
                    self.chainSlots[slot] = nil
                    if slot == 0 {
                        self.activeAudioUnit = nil
                        self.activeEffect = nil
                    }
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
                    self.slotAudioUnits[slot] = nil
                    self.chainSlots[slot] = nil
                    if slot == 0 {
                        self.activeAudioUnit = nil
                        self.activeEffect = nil
                    }
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

                let bypassed = self.slotBypassStates[slot]
                audioUnit.auAudioUnit.shouldBypassEffect = bypassed
                self.slotAudioUnits[slot] = audioUnit
                self.chainSlots[slot] = item
                if slot == 0 {
                    self.activeAudioUnit = audioUnit
                    self.activeEffect = item
                    self.selectedEffectID = item.id
                }
                self.lastError = nil

                MixerRealtimeAUChainProcessor.shared.configureSlot(
                    slot,
                    audioUnit: audioUnit.auAudioUnit,
                    bypassed: bypassed,
                    sampleRate: self.currentSampleRate
                )

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
        UserDefaults.standard.set(bypassed, forKey: Self.bypassedDefaultsKey(forSlot: slot))
        slotAudioUnits[slot]?.auAudioUnit.shouldBypassEffect = bypassed
        MixerRealtimeAUChainProcessor.shared.setSlotBypassed(bypassed, atSlot: slot)

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
        closeEditorWindow(forSlot: slot)
        slotAudioUnits[slot]?.auAudioUnit.shouldBypassEffect = true
        MixerRealtimeAUChainProcessor.shared.configureSlot(
            slot,
            audioUnit: nil,
            bypassed: true,
            sampleRate: currentSampleRate
        )
        slotAudioUnits[slot] = nil
        chainSlots[slot] = nil
        slotSelectedIDs[slot] = nil
        slotLoadingStates[slot] = false
        isLoading = slotLoadingStates.contains(true)
        lastError = nil
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
        for slot in 0..<Self.slotCount {
            if let unit = slotAudioUnits[slot] {
                MixerRealtimeAUChainProcessor.shared.configureSlot(
                    slot,
                    audioUnit: unit.auAudioUnit,
                    bypassed: slotBypassStates[slot],
                    sampleRate: safeRate
                )
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
                    self?.refreshEditorWindowVisibility()
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

    private static func selectedEffectDefaultsKey(forSlot slot: Int) -> String {
        slot == 0 ? selectedEffectDefaultsKey : "\(selectedEffectDefaultsKey)Slot\(slot)"
    }

    private static func bypassedDefaultsKey(forSlot slot: Int) -> String {
        slot == 0 ? bypassedDefaultsKey : "\(bypassedDefaultsKey)Slot\(slot)"
    }
}
