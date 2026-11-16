// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Accelerate
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
final class MixerParametricEQ {
    static let bandCount = 10

    private var lock = os_unfair_lock()
    private var setup: vDSP_biquadm_Setup?
    private var activeChannelCount = 2
    private var gainsDB = [Float](repeating: 0, count: 10)
    private var preampDB: Float = 0
    private var pan: Float = 0
    private var isMuted = false
    private let sampleRate: Double
    private let qFactor: Double

    // Preallocated scratch buffers to guarantee zero allocations in realtime audio callbacks.
    private let maxScratchFrames: Int
    private var leftInScratch: [Float]
    private var rightInScratch: [Float]
    private var leftOutScratch: [Float]
    private var rightOutScratch: [Float]

    init(sampleRate: Double = 48_000, qFactor: Double = 1.41, maxBlockFrames: Int = 4096) {
        self.sampleRate = max(8_000, sampleRate)
        self.qFactor = qFactor
        self.maxScratchFrames = max(256, maxBlockFrames)
        self.leftInScratch = [Float](repeating: 0, count: self.maxScratchFrames)
        self.rightInScratch = [Float](repeating: 0, count: self.maxScratchFrames)
        self.leftOutScratch = [Float](repeating: 0, count: self.maxScratchFrames)
        self.rightOutScratch = [Float](repeating: 0, count: self.maxScratchFrames)
        let coeffs = Self.buildStereoBiquadCoefficients(gainsDB: gainsDB,
                                                          sampleRate: self.sampleRate,
                                                          qFactor: self.qFactor)
        self.setup = vDSP_biquadm_CreateSetup(coeffs, vDSP_Length(Self.bandCount), vDSP_Length(activeChannelCount))
    }

    deinit {
        if let setup {
            vDSP_biquadm_DestroySetup(setup)
        }
    }

    func applyPreset(_ preset: MixerEQPreset) {
        update(gainsDB: preset.gainsDB, preampDB: preset.preampDB, pan: pan, isMuted: isMuted)
    }

    func update(gainsDB newGains: [Float]? = nil,
                preampDB newPreamp: Float? = nil,
                pan newPan: Float? = nil,
                isMuted newMuted: Bool? = nil) {
        var resolvedGains = gainsDB
        if let newGains {
            resolvedGains = Array(newGains.prefix(Self.bandCount))
            while resolvedGains.count < Self.bandCount { resolvedGains.append(0) }
            resolvedGains = resolvedGains.map { min(max($0, -18), 18) }
        }
        let resolvedPreamp = min(max(newPreamp ?? preampDB, -18), 18)
        let resolvedPan = min(max(newPan ?? pan, -1), 1)
        let resolvedMute = newMuted ?? isMuted
        let newCoeffs = Self.buildStereoBiquadCoefficients(gainsDB: resolvedGains,
                                                             sampleRate: sampleRate,
                                                             qFactor: qFactor)
        let newSetup = vDSP_biquadm_CreateSetup(newCoeffs, vDSP_Length(Self.bandCount), vDSP_Length(activeChannelCount))

        os_unfair_lock_lock(&lock)
        let oldSetup = setup
        if let setup, let existing = newSetup {
            vDSP_biquadm_CopyState(existing, setup)
        }
        setup = newSetup ?? setup
        gainsDB = resolvedGains
        preampDB = resolvedPreamp
        pan = resolvedPan
        isMuted = resolvedMute
        os_unfair_lock_unlock(&lock)

        if let oldSetup, newSetup != nil {
            vDSP_biquadm_DestroySetup(oldSetup)
        }
    }

    /// Processes stereo deinterleaved or planar buffers lock-free without allocating on the audio thread.
    @discardableResult
    func processStereo(left: UnsafeMutablePointer<Float>,
                       right: UnsafeMutablePointer<Float>,
                       frameCount: Int) -> Bool {
        guard frameCount > 0 else { return true }
        guard os_unfair_lock_trylock(&lock) else { return false }
        defer { os_unfair_lock_unlock(&lock) }

        if isMuted {
            vDSP_vclr(left, 1, vDSP_Length(frameCount))
            vDSP_vclr(right, 1, vDSP_Length(frameCount))
            return true
        }

        let isFlat = gainsDB.allSatisfy { abs($0) < 0.01 }
        let chunkFrames = min(frameCount, maxScratchFrames)

        if let setup, !isFlat {
            var offset = 0
            while offset < frameCount {
                let count = min(chunkFrames, frameCount - offset)
                let srcL = UnsafePointer(left + offset)
                let srcR = UnsafePointer(right + offset)
                leftInScratch.withUnsafeMutableBufferPointer { inL in
                    rightInScratch.withUnsafeMutableBufferPointer { inR in
                        leftOutScratch.withUnsafeMutableBufferPointer { outL in
                            rightOutScratch.withUnsafeMutableBufferPointer { outR in
                                memcpy(inL.baseAddress!, srcL, count * MemoryLayout<Float>.size)
                                memcpy(inR.baseAddress!, srcR, count * MemoryLayout<Float>.size)
                                var inPtrs: [UnsafePointer<Float>] = [UnsafePointer(inL.baseAddress!),
                                                                      UnsafePointer(inR.baseAddress!)]
                                var outPtrs: [UnsafeMutablePointer<Float>] = [outL.baseAddress!, outR.baseAddress!]
                                inPtrs.withUnsafeMutableBufferPointer { pIn in
                                    outPtrs.withUnsafeMutableBufferPointer { pOut in
                                        vDSP_biquadm(setup,
                                                     pIn.baseAddress!, 1,
                                                     pOut.baseAddress!, 1,
                                                     vDSP_Length(count))
                                    }
                                }
                                memcpy(left + offset, outL.baseAddress!, count * MemoryLayout<Float>.size)
                                memcpy(right + offset, outR.baseAddress!, count * MemoryLayout<Float>.size)
                            }
                        }
                    }
                }
                offset += count
            }
        }

        // Preamp + equal-power stereo balance
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
            vDSP_vsmul(left, 1, &leftGain, left, 1, vDSP_Length(frameCount))
        }
        if abs(rightGain - 1.0) > 0.0001 {
            vDSP_vsmul(right, 1, &rightGain, right, 1, vDSP_Length(frameCount))
        }
        return true
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
