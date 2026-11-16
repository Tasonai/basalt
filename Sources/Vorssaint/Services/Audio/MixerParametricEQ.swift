// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Accelerate
import Combine
import CoreAudio
import Foundation
import os

/// Named AutoEQ / studio frequency curve with preamp and 10 ISO band gains in dB.
struct MixerEQPreset: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let name: String
    let category: String
    let preampDB: Float
    let gainsDB: [Float]

    static let isoFrequenciesHz: [Double] = [31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    static let builtInPresets: [MixerEQPreset] = [
        MixerEQPreset(id: "flat", name: "Flat", category: "Reference", preampDB: 0, gainsDB: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        MixerEQPreset(id: "airpods-pro-2", name: "AirPods Pro 2 (Harman)", category: "AutoEQ", preampDB: -1.5, gainsDB: [0.5, 1.0, -0.5, -1.5, 0.5, 1.5, 1.0, -0.5, 1.5, 0.5]),
        MixerEQPreset(id: "airpods-max", name: "AirPods Max (AutoEQ)", category: "AutoEQ", preampDB: -2.0, gainsDB: [1.0, 0.5, -1.0, -1.5, 0.0, 1.0, 2.5, 2.0, 0.5, 1.0]),
        MixerEQPreset(id: "sony-wh1000xm5", name: "Sony WH-1000XM5", category: "AutoEQ", preampDB: -2.5, gainsDB: [-3.5, -4.0, -2.5, 0.0, 1.5, 2.0, 2.5, 1.5, 2.0, 1.0]),
        MixerEQPreset(id: "sennheiser-hd600", name: "Sennheiser HD 600", category: "AutoEQ", preampDB: -3.0, gainsDB: [4.5, 3.0, 1.0, -0.5, 0.0, 0.0, -1.5, -1.0, 0.5, 1.5]),
        MixerEQPreset(id: "sennheiser-hd650", name: "Sennheiser HD 650", category: "AutoEQ", preampDB: -3.0, gainsDB: [4.0, 2.5, 0.5, -1.0, 0.0, 0.5, 1.0, 2.0, 1.5, 2.0]),
        MixerEQPreset(id: "dt-770-pro", name: "Beyerdynamic DT 770 Pro", category: "AutoEQ", preampDB: -2.5, gainsDB: [2.5, 1.5, -1.0, -0.5, 2.0, 1.0, 0.5, -4.5, -3.5, 1.0]),
        MixerEQPreset(id: "dt-990-pro", name: "Beyerdynamic DT 990 Pro", category: "AutoEQ", preampDB: -3.0, gainsDB: [3.5, 2.0, -1.0, 0.0, 1.5, 0.5, 1.0, -5.0, -4.0, 0.5]),
        MixerEQPreset(id: "ath-m50x", name: "Audio-Technica ATH-M50x", category: "AutoEQ", preampDB: -2.0, gainsDB: [-1.0, -2.0, -1.5, 0.5, 1.5, 1.0, -1.0, -2.0, 0.5, 0.0]),
        MixerEQPreset(id: "mbp-speakers", name: "MacBook Pro Speakers", category: "AutoEQ", preampDB: -1.5, gainsDB: [3.5, 3.0, 1.0, -1.5, -1.0, 0.5, 1.5, 1.0, 2.0, 2.5]),
        MixerEQPreset(id: "shure-sm7b", name: "Shure SM7B Presence", category: "Studio", preampDB: -1.5, gainsDB: [-6.0, -3.0, 0.5, -1.5, 0.0, 1.5, 2.5, 3.5, 2.0, 1.0]),
        MixerEQPreset(id: "studio-warm", name: "Studio Monitor Warm", category: "Studio", preampDB: -1.0, gainsDB: [1.5, 2.0, 1.5, 0.5, 0.0, -0.5, -0.5, 0.0, 0.5, 1.0]),
        MixerEQPreset(id: "bass-boost", name: "Bass Boost", category: "Tone", preampDB: -4.0, gainsDB: [5.5, 5.0, 3.5, 1.5, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5]),
        MixerEQPreset(id: "treble-air", name: "Treble & Air", category: "Tone", preampDB: -2.0, gainsDB: [0.0, 0.0, 0.0, 0.0, 0.5, 1.0, 2.0, 3.5, 4.5, 4.0]),
        MixerEQPreset(id: "vocal-clarity", name: "Vocal Clarity", category: "Voice", preampDB: -1.5, gainsDB: [-4.0, -2.5, -1.0, 0.0, 1.5, 2.5, 3.5, 2.5, 1.0, 0.0]),
        MixerEQPreset(id: "podcast-voice", name: "Podcast Broadcast", category: "Voice", preampDB: -2.0, gainsDB: [-6.0, -2.0, 1.5, -1.5, 0.5, 1.5, 2.5, 3.0, 1.5, 0.5]),
        MixerEQPreset(id: "late-night", name: "Late Night Whisper", category: "Utility", preampDB: 1.0, gainsDB: [-3.0, -2.0, 0.0, 1.5, 2.0, 2.5, 2.0, 1.0, -1.0, -2.0]),
        MixerEQPreset(id: "electronic", name: "Electronic Club", category: "Genre", preampDB: -3.5, gainsDB: [4.5, 4.0, 2.0, 0.0, -1.5, 0.5, 1.5, 2.5, 3.5, 3.0]),
        MixerEQPreset(id: "acoustic", name: "Acoustic Natural", category: "Genre", preampDB: -1.5, gainsDB: [1.5, 1.5, 1.0, 0.5, 1.5, 1.5, 2.0, 2.5, 2.0, 1.5]),
        MixerEQPreset(id: "classical", name: "Classical Concert", category: "Genre", preampDB: -1.5, gainsDB: [2.0, 1.5, 0.5, 0.0, -0.5, 0.0, 1.0, 2.0, 2.5, 3.0]),
        MixerEQPreset(id: "rock", name: "Modern Rock", category: "Genre", preampDB: -3.0, gainsDB: [3.5, 3.0, 1.5, -1.0, -1.5, 0.5, 2.0, 3.0, 3.0, 2.5]),
        MixerEQPreset(id: "jazz", name: "Warm Jazz", category: "Genre", preampDB: -1.5, gainsDB: [2.5, 2.0, 1.0, 1.5, -1.0, -0.5, 0.5, 1.5, 2.0, 2.0]),
        MixerEQPreset(id: "gaming", name: "Gaming Footsteps", category: "Utility", preampDB: -2.0, gainsDB: [-2.0, -1.5, 0.0, 1.0, 2.0, 2.5, 4.0, 4.5, 2.0, 0.5]),
        MixerEQPreset(id: "lofi", name: "Lo-Fi Warmth", category: "Tone", preampDB: -1.5, gainsDB: [2.0, 2.5, 2.0, 1.0, 0.5, -0.5, -2.0, -3.5, -4.5, -6.0]),
        MixerEQPreset(id: "cinema", name: "Cinema Sub", category: "Media", preampDB: -3.5, gainsDB: [5.0, 4.0, 2.0, 0.5, 1.0, 1.5, 2.5, 2.0, 1.0, 0.5]),
    ]
}

/// Realtime lock-free 10-band parametric EQ (`vDSP_biquadm`), preamp, equal-power L/R pan, and mute.
final class MixerParametricEQ: @unchecked Sendable {
    static let bandCount = 10

    private var lock = os_unfair_lock()
    private var setup: vDSP_biquadm_Setup?
    private var activeChannelCount = 2
    private var gainsDB = [Float](repeating: 0, count: 10)
    private var preampDB: Float = 0
    private var pan: Float = 0
    private var isMuted = false
    private var explicitBypass = false
    private var hasFlatGains = true
    private var bypassFlagBits: Int32 = 1
    private var flatFlagBits: Int32 = 1
    private let sampleRate: Double
    private let qFactor: Double

    // Preallocated raw scratch buffers and pointer arrays to guarantee zero
    // allocations in realtime audio callbacks.
    private let maxScratchFrames: Int
    private let leftInScratch: UnsafeMutablePointer<Float>
    private let rightInScratch: UnsafeMutablePointer<Float>
    private let leftOutScratch: UnsafeMutablePointer<Float>
    private let rightOutScratch: UnsafeMutablePointer<Float>
    private let inPtrs: UnsafeMutablePointer<UnsafePointer<Float>>
    private let outPtrs: UnsafeMutablePointer<UnsafeMutablePointer<Float>>

    /// O(1) lock-free atomic flag: `true` when EQ is explicitly bypassed or completely flat unity.
    var isBypassed: Bool {
        withUnsafeMutablePointer(to: &bypassFlagBits) { ptr in
            OSAtomicAdd32Barrier(0, ptr) != 0
        }
    }

    /// O(1) lock-free atomic flag: `true` when all 10 EQ bands are within 0.01 dB of 0 dB.
    var isFlatCurve: Bool {
        withUnsafeMutablePointer(to: &flatFlagBits) { ptr in
            OSAtomicAdd32Barrier(0, ptr) != 0
        }
    }

    var currentGainsDB: [Float] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return gainsDB
    }

    var currentPreampDB: Float {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return preampDB
    }

    var currentPan: Float {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return pan
    }

    var currentIsMuted: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return isMuted
    }

    var currentIsExplicitlyBypassed: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return explicitBypass
    }

    init(sampleRate: Double = 48_000, qFactor: Double = 1.41, maxBlockFrames: Int = 4096) {
        self.sampleRate = max(8_000, sampleRate)
        self.qFactor = qFactor
        let capacity = max(256, maxBlockFrames)
        self.maxScratchFrames = capacity
        self.leftInScratch = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        self.rightInScratch = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        self.leftOutScratch = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        self.rightOutScratch = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        self.leftInScratch.initialize(repeating: 0, count: capacity)
        self.rightInScratch.initialize(repeating: 0, count: capacity)
        self.leftOutScratch.initialize(repeating: 0, count: capacity)
        self.rightOutScratch.initialize(repeating: 0, count: capacity)
        self.inPtrs = UnsafeMutablePointer<UnsafePointer<Float>>.allocate(capacity: 2)
        self.outPtrs = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: 2)
        self.inPtrs.initialize(to: UnsafePointer(self.leftInScratch))
        (self.inPtrs + 1).initialize(to: UnsafePointer(self.rightInScratch))
        self.outPtrs.initialize(to: self.leftOutScratch)
        (self.outPtrs + 1).initialize(to: self.rightOutScratch)
        let coeffs = Self.buildStereoBiquadCoefficients(gainsDB: gainsDB,
                                                          sampleRate: self.sampleRate,
                                                          qFactor: self.qFactor)
        self.setup = vDSP_biquadm_CreateSetup(coeffs, vDSP_Length(Self.bandCount), vDSP_Length(activeChannelCount))
    }

    deinit {
        if let setup {
            vDSP_biquadm_DestroySetup(setup)
        }
        inPtrs.deinitialize(count: 2)
        outPtrs.deinitialize(count: 2)
        inPtrs.deallocate()
        outPtrs.deallocate()
        leftInScratch.deinitialize(count: maxScratchFrames)
        rightInScratch.deinitialize(count: maxScratchFrames)
        leftOutScratch.deinitialize(count: maxScratchFrames)
        rightOutScratch.deinitialize(count: maxScratchFrames)
        leftInScratch.deallocate()
        rightInScratch.deallocate()
        leftOutScratch.deallocate()
        rightOutScratch.deallocate()
    }

    func setBypassed(_ bypassed: Bool) {
        update(isBypassed: bypassed)
    }

    func applyPreset(_ preset: MixerEQPreset) {
        update(gainsDB: preset.gainsDB, preampDB: preset.preampDB, pan: pan, isMuted: isMuted)
    }

    func update(gainsDB newGains: [Float]? = nil,
                preampDB newPreamp: Float? = nil,
                pan newPan: Float? = nil,
                isMuted newMuted: Bool? = nil,
                isBypassed newBypassed: Bool? = nil) {
        os_unfair_lock_lock(&lock)
        let baseGains = gainsDB
        let basePreamp = preampDB
        let basePan = pan
        let baseMuted = isMuted
        let baseBypassed = explicitBypass
        os_unfair_lock_unlock(&lock)

        var resolvedGains = baseGains
        if let newGains {
            resolvedGains = Array(newGains.prefix(Self.bandCount))
            while resolvedGains.count < Self.bandCount { resolvedGains.append(0) }
            resolvedGains = resolvedGains.map { $0.isFinite ? min(max($0, -18), 18) : 0 }
        }
        let rawPreamp = newPreamp ?? basePreamp
        let resolvedPreamp: Float = rawPreamp.isFinite ? min(max(rawPreamp, -18), 18) : 0
        let rawPan = newPan ?? basePan
        let resolvedPan: Float = rawPan.isFinite ? min(max(rawPan, -1), 1) : 0
        let resolvedMute = newMuted ?? baseMuted
        let resolvedExplicitBypass = newBypassed ?? baseBypassed

        let gainsFlat = resolvedGains.allSatisfy { abs($0) < 0.01 }
        let effectivelyBypassed = resolvedExplicitBypass
            || (gainsFlat && abs(resolvedPreamp) < 0.01 && abs(resolvedPan) < 0.001 && !resolvedMute)

        let newSetup: vDSP_biquadm_Setup?
        if gainsFlat {
            newSetup = nil
        } else {
            let newCoeffs = Self.buildStereoBiquadCoefficients(gainsDB: resolvedGains,
                                                                 sampleRate: sampleRate,
                                                                 qFactor: qFactor)
            newSetup = vDSP_biquadm_CreateSetup(newCoeffs, vDSP_Length(Self.bandCount), vDSP_Length(activeChannelCount))
        }

        os_unfair_lock_lock(&lock)
        var oldSetup: vDSP_biquadm_Setup?
        if let newSetup {
            oldSetup = setup
            if let existing = setup {
                vDSP_biquadm_CopyState(newSetup, existing)
            }
            setup = newSetup
        } else if gainsFlat, let existing = setup {
            vDSP_biquadm_ResetState(existing)
        }
        gainsDB = resolvedGains
        preampDB = resolvedPreamp
        pan = resolvedPan
        isMuted = resolvedMute
        explicitBypass = resolvedExplicitBypass
        hasFlatGains = gainsFlat
        Self.atomicStoreInt32(gainsFlat ? 1 : 0, into: &flatFlagBits)
        Self.atomicStoreInt32(effectivelyBypassed ? 1 : 0, into: &bypassFlagBits)
        os_unfair_lock_unlock(&lock)

        if let oldSetup {
            vDSP_biquadm_DestroySetup(oldSetup)
        }
    }

    private static func atomicStoreInt32(_ value: Int32, into storage: UnsafeMutablePointer<Int32>) {
        while true {
            let current = OSAtomicAdd32Barrier(0, storage)
            if OSAtomicCompareAndSwap32Barrier(current, value, storage) { return }
        }
    }

    /// Processes stereo deinterleaved or planar buffers lock-free without allocating on the audio thread.
    @discardableResult
    func processStereo(left: UnsafeMutablePointer<Float>,
                       right: UnsafeMutablePointer<Float>,
                       frameCount: Int) -> Bool {
        guard frameCount > 0 else { return true }
        if isBypassed { return true }
        guard os_unfair_lock_trylock(&lock) else { return false }
        defer { os_unfair_lock_unlock(&lock) }
        processStereoLocked(left: left, right: right, frameCount: frameCount)
        return true
    }

    /// Processes a CoreAudio `AudioBufferList` (interleaved stereo/multichannel or non-interleaved planar)
    /// lock-free with strictly zero heap allocations on the audio thread.
    @discardableResult
    func processAudioBufferList(_ output: UnsafeMutableAudioBufferListPointer, frames: Int) -> Bool {
        guard frames > 0, !output.isEmpty else { return true }
        if isBypassed { return true }
        guard os_unfair_lock_trylock(&lock) else { return false }
        defer { os_unfair_lock_unlock(&lock) }

        if isMuted {
            for buffer in output {
                let channels = Int(buffer.mNumberChannels)
                guard channels > 0, let base = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let safeFrames = min(frames, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels))
                if safeFrames > 0 {
                    vDSP_vclr(base, 1, vDSP_Length(safeFrames * channels))
                }
            }
            return true
        }

        // Non-interleaved planar stereo (or wider planar list where buffer 0 & 1 are Left & Right)
        if output.count >= 2,
           output[0].mNumberChannels == 1,
           output[1].mNumberChannels == 1,
           let leftRaw = output[0].mData?.assumingMemoryBound(to: Float.self),
           let rightRaw = output[1].mData?.assumingMemoryBound(to: Float.self) {
            let framesL = Int(output[0].mDataByteSize) / MemoryLayout<Float>.size
            let framesR = Int(output[1].mDataByteSize) / MemoryLayout<Float>.size
            let safeFrames = min(frames, min(framesL, framesR))
            if safeFrames > 0 {
                processStereoLocked(left: leftRaw, right: rightRaw, frameCount: safeFrames)
            }
            if output.count > 2 {
                var preampGain = powf(10.0, preampDB / 20.0)
                if abs(preampGain - 1.0) > 0.0001 {
                    for index in 2..<output.count {
                        let channels = Int(output[index].mNumberChannels)
                        guard channels > 0,
                              let base = output[index].mData?.assumingMemoryBound(to: Float.self) else { continue }
                        let extraFrames = min(frames, Int(output[index].mDataByteSize) / (MemoryLayout<Float>.size * channels))
                        if extraFrames > 0 {
                            vDSP_vsmul(base, 1, &preampGain, base, 1, vDSP_Length(extraFrames * channels))
                        }
                    }
                }
            }
            return true
        }

        // Standard interleaved Stereo / Multichannel or Single Mono buffer
        for buffer in output {
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0, let base = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let safeFrames = min(frames, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels))
            guard safeFrames > 0 else { continue }
            if channels == 1 {
                processMonoLocked(samples: base, frameCount: safeFrames)
            } else {
                processInterleavedStereoLocked(interleaved: base, channels: channels, frameCount: safeFrames)
            }
        }
        return true
    }

    private func processStereoLocked(left: UnsafeMutablePointer<Float>,
                                     right: UnsafeMutablePointer<Float>,
                                     frameCount: Int) {
        if isMuted {
            vDSP_vclr(left, 1, vDSP_Length(frameCount))
            vDSP_vclr(right, 1, vDSP_Length(frameCount))
            return
        }

        if let setup, !hasFlatGains {
            let chunkFrames = min(frameCount, maxScratchFrames)
            let floatSize = MemoryLayout<Float>.size
            var offset = 0
            while offset < frameCount {
                let count = min(chunkFrames, frameCount - offset)
                memcpy(leftInScratch, left + offset, count * floatSize)
                memcpy(rightInScratch, right + offset, count * floatSize)
                vDSP_biquadm(setup, inPtrs, 1, outPtrs, 1, vDSP_Length(count))
                memcpy(left + offset, leftOutScratch, count * floatSize)
                memcpy(right + offset, rightOutScratch, count * floatSize)
                offset += count
            }
        }

        applyStereoPreampAndPan(left: left, right: right, stride: 1, frameCount: frameCount)
    }

    private func processInterleavedStereoLocked(interleaved: UnsafeMutablePointer<Float>,
                                                channels: Int,
                                                frameCount: Int) {
        if let setup, !hasFlatGains {
            let chunkFrames = min(frameCount, maxScratchFrames)
            var offset = 0
            while offset < frameCount {
                let count = min(chunkFrames, frameCount - offset)
                let base = interleaved + offset * channels
                for frame in 0..<count {
                    let sampleIndex = frame * channels
                    leftInScratch[frame] = base[sampleIndex]
                    rightInScratch[frame] = base[sampleIndex + 1]
                }
                vDSP_biquadm(setup, inPtrs, 1, outPtrs, 1, vDSP_Length(count))
                for frame in 0..<count {
                    let sampleIndex = frame * channels
                    base[sampleIndex] = leftOutScratch[frame]
                    base[sampleIndex + 1] = rightOutScratch[frame]
                }
                offset += count
            }
        }

        applyStereoPreampAndPan(left: interleaved,
                                right: interleaved + 1,
                                stride: vDSP_Stride(channels),
                                frameCount: frameCount)

        if channels > 2 {
            var preampGain = powf(10.0, preampDB / 20.0)
            if abs(preampGain - 1.0) > 0.0001 {
                for ch in 2..<channels {
                    vDSP_vsmul(interleaved + ch,
                               vDSP_Stride(channels),
                               &preampGain,
                               interleaved + ch,
                               vDSP_Stride(channels),
                               vDSP_Length(frameCount))
                }
            }
        }
    }

    private func processMonoLocked(samples: UnsafeMutablePointer<Float>, frameCount: Int) {
        if let setup, !hasFlatGains {
            let chunkFrames = min(frameCount, maxScratchFrames)
            let floatSize = MemoryLayout<Float>.size
            var offset = 0
            while offset < frameCount {
                let count = min(chunkFrames, frameCount - offset)
                memcpy(leftInScratch, samples + offset, count * floatSize)
                vDSP_vclr(rightInScratch, 1, vDSP_Length(count))
                vDSP_biquadm(setup, inPtrs, 1, outPtrs, 1, vDSP_Length(count))
                memcpy(samples + offset, leftOutScratch, count * floatSize)
                offset += count
            }
        }

        var preampGain = powf(10.0, preampDB / 20.0)
        if abs(preampGain - 1.0) > 0.0001 {
            vDSP_vsmul(samples, 1, &preampGain, samples, 1, vDSP_Length(frameCount))
        }
    }

    private func applyStereoPreampAndPan(left: UnsafeMutablePointer<Float>,
                                         right: UnsafeMutablePointer<Float>,
                                         stride: vDSP_Stride,
                                         frameCount: Int) {
        let preampGain = powf(10.0, preampDB / 20.0)
        var leftGain: Float
        var rightGain: Float
        if abs(pan) < 0.001 {
            leftGain = preampGain
            rightGain = preampGain
        } else {
            let angle = Double((pan + 1.0) * 0.5) * (.pi * 0.5)
            leftGain = min(preampGain, preampGain * Float(cos(angle) * sqrt(2.0)))
            rightGain = min(preampGain, preampGain * Float(sin(angle) * sqrt(2.0)))
        }
        if abs(leftGain - 1.0) > 0.0001 {
            vDSP_vsmul(left, stride, &leftGain, left, stride, vDSP_Length(frameCount))
        }
        if abs(rightGain - 1.0) > 0.0001 {
            vDSP_vsmul(right, stride, &rightGain, right, stride, vDSP_Length(frameCount))
        }
    }

    static func peakingBiquadCoefficients(frequencyHz: Double,
                                          sampleRate: Double,
                                          q: Double,
                                          gainDB: Float) -> (b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        if abs(gainDB) < 0.01 || frequencyHz >= sampleRate * 0.48 {
            return (1, 0, 0, 0, 0)
        }
        let a = pow(10.0, Double(gainDB) / 40.0)
        let w0 = 2.0 * Double.pi * frequencyHz / sampleRate
        let cosW0 = cos(w0)
        let sinW0 = sin(w0)
        let alpha = sinW0 / (2.0 * max(0.2, q))

        let b0 = 1.0 + alpha * a
        let b1 = -2.0 * cosW0
        let b2 = 1.0 - alpha * a
        let a0 = 1.0 + alpha / a
        let a1 = -2.0 * cosW0
        let a2 = 1.0 - alpha / a

        return (b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)
    }

    private static func buildStereoBiquadCoefficients(gainsDB: [Float],
                                                      sampleRate: Double,
                                                      qFactor: Double) -> [Double] {
        // vDSP_biquadm orders coefficients section-major across channels:
        // for each section[s], channel[0..1], 5 doubles [b0, b1, b2, a1, a2].
        var coeffs: [Double] = []
        coeffs.reserveCapacity(bandCount * 2 * 5)
        for index in 0..<bandCount {
            let freq = MixerEQPreset.isoFrequenciesHz[index]
            let gain = index < gainsDB.count ? gainsDB[index] : 0
            let c = peakingBiquadCoefficients(frequencyHz: freq, sampleRate: sampleRate, q: qFactor, gainDB: gain)
            let quintuple = [c.b0, c.b1, c.b2, c.a1, c.a2]
            coeffs.append(contentsOf: quintuple)
            coeffs.append(contentsOf: quintuple)
        }
        return coeffs
    }
}

/// Peak & RMS meter math (`0...1` normalized meter bars + dBFS) accelerated via vDSP.
enum MixerPeakMeterMath {
    struct Levels: Equatable, Sendable {
        let rmsDBFS: Float
        let peakDBFS: Float
        let normalizedBar: Float
    }

    static func measure(_ samples: UnsafePointer<Float>, count: Int) -> Levels {
        guard count > 0 else {
            return Levels(rmsDBFS: -96, peakDBFS: -96, normalizedBar: 0)
        }
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(count))
        var meanSq: Float = 0
        vDSP_measqv(samples, 1, &meanSq, vDSP_Length(count))
        let rms = sqrtf(max(meanSq, 0))
        let peakDB = 20.0 * log10f(max(peak, 1e-5))
        let rmsDB = 20.0 * log10f(max(rms, 1e-5))
        // Map -60 dBFS...0 dBFS cleanly into 0...1 UI bar
        let normalized = min(max((peakDB + 60.0) / 60.0, 0), 1)
        return Levels(rmsDBFS: rmsDB, peakDBFS: peakDB, normalizedBar: normalized)
    }
}

/// Realtime microphone DSP processor: hysteresis noise gate + speech RMS leveler.
final class AudioMicDSPProcessor {
    var noiseGateEnabled: Bool
    var levelerEnabled: Bool
    let openThresholdDB: Float
    let closeThresholdDB: Float
    let targetSpeechDB: Float

    private var gateGain: Float = 1.0
    private var isGateOpen = true
    private var levelerGain: Float = 1.0

    init(noiseGateEnabled: Bool = true,
         levelerEnabled: Bool = true,
         openThresholdDB: Float = -38,
         closeThresholdDB: Float = -46,
         targetSpeechDB: Float = -18) {
        self.noiseGateEnabled = noiseGateEnabled
        self.levelerEnabled = levelerEnabled
        self.openThresholdDB = openThresholdDB
        self.closeThresholdDB = closeThresholdDB
        self.targetSpeechDB = targetSpeechDB
    }

    func processInPlace(_ samples: UnsafeMutablePointer<Float>, count: Int) {
        guard count > 0 else { return }
        let levels = MixerPeakMeterMath.measure(samples, count: count)

        if noiseGateEnabled {
            if isGateOpen {
                if levels.rmsDBFS < closeThresholdDB { isGateOpen = false }
            } else if levels.rmsDBFS > openThresholdDB {
                isGateOpen = true
            }
            let targetGate: Float = isGateOpen ? 1.0 : 0.02
            gateGain = gateGain * 0.4 + targetGate * 0.6
        } else {
            isGateOpen = true
            gateGain = 1.0
        }

        if levelerEnabled, isGateOpen, levels.rmsDBFS > closeThresholdDB {
            let neededDB = min(max(targetSpeechDB - levels.rmsDBFS, -9), 14)
            let desiredGain = powf(10.0, neededDB / 20.0)
            levelerGain = levelerGain * 0.75 + desiredGain * 0.25
        } else if !levelerEnabled {
            levelerGain = 1.0
        }

        var combinedGain = gateGain * levelerGain
        if abs(combinedGain - 1.0) > 0.0001 {
            vDSP_vsmul(samples, 1, &combinedGain, samples, 1, vDSP_Length(count))
        }
        // Soft limiter to prevent digital clipping after boost
        for i in 0..<count {
            let x = samples[i]
            if abs(x) > 0.95 {
                samples[i] = tanhf(x)
            }
        }
    }
}

/// Lock-free realtime audio meter computing peak (`vDSP_maxmgv`) and RMS (`vDSP_measqv`)
/// inside the audio callback with strictly zero heap allocations.
final class RealtimeAudioMeter: @unchecked Sendable {
    private var normalizedBits: Int32 = 0
    private var peakDBBits: Int32 = Int32(bitPattern: Float(-96).bitPattern)
    private var rmsDBBits: Int32 = Int32(bitPattern: Float(-96).bitPattern)

    /// Lock-free normalized peak level (`0...1`), suitable for 30Hz UI polling.
    var normalizedLevel: Float {
        Self.atomicLoadFloat(&normalizedBits)
    }

    var peakDBFS: Float {
        Self.atomicLoadFloat(&peakDBBits)
    }

    var rmsDBFS: Float {
        Self.atomicLoadFloat(&rmsDBBits)
    }

    func reset() {
        Self.atomicStoreFloat(0, into: &normalizedBits)
        Self.atomicStoreFloat(-96, into: &peakDBBits)
        Self.atomicStoreFloat(-96, into: &rmsDBBits)
    }

    func record(_ bufferList: UnsafeMutableAudioBufferListPointer, frames: Int) {
        guard frames > 0, !bufferList.isEmpty else { return }
        var maxPeak: Float = 0
        var sumMeanSq: Float = 0
        var totalSamples: Int = 0

        for buffer in bufferList {
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0,
                  let ptr = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let safeFrames = min(frames, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels))
            let sampleCount = safeFrames * channels
            guard sampleCount > 0 else { continue }
            var bufPeak: Float = 0
            vDSP_maxmgv(ptr, 1, &bufPeak, vDSP_Length(sampleCount))
            if bufPeak.isFinite && bufPeak > maxPeak {
                maxPeak = bufPeak
            }
            var bufMeanSq: Float = 0
            vDSP_measqv(ptr, 1, &bufMeanSq, vDSP_Length(sampleCount))
            if bufMeanSq.isFinite {
                sumMeanSq += bufMeanSq * Float(sampleCount)
                totalSamples += sampleCount
            }
        }

        guard totalSamples > 0 else {
            decayTowardSilence()
            return
        }

        let meanSq = max(sumMeanSq / Float(totalSamples), 0)
        let rms = sqrtf(meanSq)
        let peakDB = 20.0 * log10f(max(maxPeak, 1e-5))
        let rmsDB = 20.0 * log10f(max(rms, 1e-5))
        let rawNormalized = min(max((peakDB + 60.0) / 60.0, 0), 1)
        let previous = Self.atomicLoadFloat(&normalizedBits)
        let smoothed = rawNormalized >= previous
            ? rawNormalized
            : (previous * 0.72 + rawNormalized * 0.28)
        let finalLevel = smoothed < 0.002 ? Float(0) : smoothed

        Self.atomicStoreFloat(finalLevel, into: &normalizedBits)
        Self.atomicStoreFloat(peakDB, into: &peakDBBits)
        Self.atomicStoreFloat(rmsDB, into: &rmsDBBits)
    }

    func record(samples: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(count))
        var meanSq: Float = 0
        vDSP_measqv(samples, 1, &meanSq, vDSP_Length(count))
        let rms = sqrtf(max(meanSq, 0))
        let peakDB = 20.0 * log10f(max(peak.isFinite ? peak : 0, 1e-5))
        let rmsDB = 20.0 * log10f(max(rms.isFinite ? rms : 0, 1e-5))
        let rawNormalized = min(max((peakDB + 60.0) / 60.0, 0), 1)
        let previous = Self.atomicLoadFloat(&normalizedBits)
        let smoothed = rawNormalized >= previous
            ? rawNormalized
            : (previous * 0.72 + rawNormalized * 0.28)
        let finalLevel = smoothed < 0.002 ? Float(0) : smoothed

        Self.atomicStoreFloat(finalLevel, into: &normalizedBits)
        Self.atomicStoreFloat(peakDB, into: &peakDBBits)
        Self.atomicStoreFloat(rmsDB, into: &rmsDBBits)
    }

    private func decayTowardSilence() {
        let previous = Self.atomicLoadFloat(&normalizedBits)
        let next = previous * 0.72
        Self.atomicStoreFloat(next < 0.002 ? 0 : next, into: &normalizedBits)
        Self.atomicStoreFloat(-96, into: &peakDBBits)
        Self.atomicStoreFloat(-96, into: &rmsDBBits)
    }

    private static func atomicLoadFloat(_ storage: UnsafeMutablePointer<Int32>) -> Float {
        Float(bitPattern: UInt32(bitPattern: OSAtomicAdd32Barrier(0, storage)))
    }

    private static func atomicStoreFloat(_ value: Float, into storage: UnsafeMutablePointer<Int32>) {
        let replacement = Int32(bitPattern: value.bitPattern)
        while true {
            let current = OSAtomicAdd32Barrier(0, storage)
            if OSAtomicCompareAndSwap32Barrier(current, replacement, storage) { return }
        }
    }
}

/// Persists user custom 10-band EQ curves in `UserDefaults` (`vorssaintCustomEQPresets`)
/// and combines them seamlessly with `MixerEQPreset.builtInPresets`.
final class CustomEQPresetStore: ObservableObject, @unchecked Sendable {
    static let shared = CustomEQPresetStore()
    static let defaultsKey = "vorssaintCustomEQPresets"

    @Published private(set) var customPresets: [MixerEQPreset] = []

    private let lock = NSLock()
    private let userDefaults: UserDefaults
    private var storedPresets: [MixerEQPreset] = []

    var allPresets: [MixerEQPreset] {
        let custom = lock.withLock { storedPresets }
        return MixerEQPreset.builtInPresets + custom
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let loaded = Self.load(from: userDefaults)
        self.storedPresets = loaded
        self.customPresets = loaded
    }

    func preset(id: String) -> MixerEQPreset? {
        allPresets.first { $0.id == id }
    }

    func isCustomPreset(id: String) -> Bool {
        lock.withLock {
            storedPresets.contains { $0.id == id }
        }
    }

    @discardableResult
    func savePreset(name: String,
                    gainsDB: [Float],
                    preampDB: Float = 0,
                    id: String? = nil) -> MixerEQPreset {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmed.isEmpty ? "Custom EQ" : String(trimmed.prefix(48))
        let normalizedGains = Self.normalizedGains(gainsDB)
        let normalizedPreamp: Float = preampDB.isFinite ? min(max(preampDB, -18), 18) : 0
        let resolvedID = id ?? "custom-\(UUID().uuidString)"
        let preset = MixerEQPreset(id: resolvedID,
                                   name: resolvedName,
                                   category: "Custom",
                                   preampDB: normalizedPreamp,
                                   gainsDB: normalizedGains)

        let updated: [MixerEQPreset] = lock.withLock {
            var next = storedPresets
            if let existingIndex = next.firstIndex(where: { $0.id == resolvedID }) {
                next[existingIndex] = preset
            } else {
                next.append(preset)
            }
            storedPresets = next
            Self.persist(next, to: userDefaults)
            return next
        }
        publish(updated)
        return preset
    }

    func renamePreset(id: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let safeName = String(trimmed.prefix(48))
        let updated: [MixerEQPreset]? = lock.withLock {
            guard let index = storedPresets.firstIndex(where: { $0.id == id }) else { return nil }
            let old = storedPresets[index]
            var next = storedPresets
            next[index] = MixerEQPreset(id: old.id,
                                        name: safeName,
                                        category: old.category,
                                        preampDB: old.preampDB,
                                        gainsDB: old.gainsDB)
            storedPresets = next
            Self.persist(next, to: userDefaults)
            return next
        }
        if let updated {
            publish(updated)
        }
    }

    func deletePreset(id: String) {
        let updated: [MixerEQPreset]? = lock.withLock {
            guard storedPresets.contains(where: { $0.id == id }) else { return nil }
            let next = storedPresets.filter { $0.id != id }
            storedPresets = next
            Self.persist(next, to: userDefaults)
            return next
        }
        if let updated {
            publish(updated)
        }
    }

    private func publish(_ updated: [MixerEQPreset]) {
        if Thread.isMainThread {
            customPresets = updated
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.customPresets = updated
            }
        }
    }

    private static func normalizedGains(_ gains: [Float]) -> [Float] {
        var normalized = Array(gains.prefix(MixerParametricEQ.bandCount)).map {
            $0.isFinite ? min(max($0, -18), 18) : Float(0)
        }
        while normalized.count < MixerParametricEQ.bandCount {
            normalized.append(0)
        }
        return normalized
    }

    private static func load(from userDefaults: UserDefaults) -> [MixerEQPreset] {
        guard let data = userDefaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([MixerEQPreset].self, from: data) else {
            return []
        }
        return decoded.map { preset in
            MixerEQPreset(id: preset.id,
                          name: preset.name,
                          category: preset.category,
                          preampDB: preset.preampDB.isFinite ? min(max(preset.preampDB, -18), 18) : 0,
                          gainsDB: normalizedGains(preset.gainsDB))
        }
    }

    private static func persist(_ presets: [MixerEQPreset], to userDefaults: UserDefaults) {
        if presets.isEmpty {
            userDefaults.removeObject(forKey: defaultsKey)
        } else if let encoded = try? JSONEncoder().encode(presets) {
            userDefaults.set(encoded, forKey: defaultsKey)
        }
    }
}
