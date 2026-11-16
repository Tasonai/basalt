// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Accelerate
import CoreAudio
import Foundation
import os

/// Curated catalog of 16 Harman / AutoEQ target compensation presets for popular
/// headphones, IEMs, and laptop speakers mapped onto the 10 ISO EQ bands.
enum MixerAutoEQCatalog {
    static let presets: [MixerEQPreset] = [
        MixerEQPreset(
            id: "autoeq-airpods-pro-2",
            name: "AirPods Pro (2nd Gen)",
            category: "AutoEQ",
            preampDB: -1.8,
            gainsDB: [0.5, 1.0, -0.5, -1.5, 0.5, 1.5, 1.0, -0.5, 1.5, 0.5]
        ),
        MixerEQPreset(
            id: "autoeq-airpods-max",
            name: "AirPods Max",
            category: "AutoEQ",
            preampDB: -2.8,
            gainsDB: [1.2, 0.6, -1.0, -1.6, 0.0, 1.2, 2.8, 2.2, 0.5, 1.0]
        ),
        MixerEQPreset(
            id: "autoeq-sony-wh1000xm5",
            name: "Sony WH-1000XM5",
            category: "AutoEQ",
            preampDB: -2.6,
            gainsDB: [-3.2, -4.2, -2.6, -0.4, 1.4, 2.0, 2.6, 1.6, 1.8, 0.8]
        ),
        MixerEQPreset(
            id: "autoeq-sony-wh1000xm4",
            name: "Sony WH-1000XM4",
            category: "AutoEQ",
            preampDB: -3.2,
            gainsDB: [-4.5, -5.5, -3.5, -1.0, 1.2, 2.2, 3.2, 1.8, 2.5, 1.5]
        ),
        MixerEQPreset(
            id: "autoeq-bose-qc-ultra",
            name: "Bose QuietComfort Ultra",
            category: "AutoEQ",
            preampDB: -2.5,
            gainsDB: [-2.0, -2.8, -1.8, -0.5, 0.8, 1.6, 2.5, 1.2, -1.0, 1.0]
        ),
        MixerEQPreset(
            id: "autoeq-sennheiser-hd600",
            name: "Sennheiser HD 600",
            category: "AutoEQ",
            preampDB: -5.2,
            gainsDB: [5.2, 3.2, 0.8, -0.6, 0.0, 0.0, -1.4, -0.8, 0.6, 1.8]
        ),
        MixerEQPreset(
            id: "autoeq-sennheiser-hd650",
            name: "Sennheiser HD 650",
            category: "AutoEQ",
            preampDB: -5.0,
            gainsDB: [5.0, 2.8, 0.4, -1.2, -0.2, 0.5, 1.2, 2.2, 1.6, 2.4]
        ),
        MixerEQPreset(
            id: "autoeq-sennheiser-hd800s",
            name: "Sennheiser HD 800 S",
            category: "AutoEQ",
            preampDB: -5.5,
            gainsDB: [5.5, 3.5, 0.5, -0.5, 0.4, 0.8, 2.6, -1.5, -4.2, 1.0]
        ),
        MixerEQPreset(
            id: "autoeq-dt770-pro-80",
            name: "Beyerdynamic DT 770 Pro (80 Ohm)",
            category: "AutoEQ",
            preampDB: -3.2,
            gainsDB: [2.8, 1.2, -1.2, 1.8, 1.5, 0.8, 1.2, -3.5, -4.8, 1.0]
        ),
        MixerEQPreset(
            id: "autoeq-dt990-pro-250",
            name: "Beyerdynamic DT 990 Pro (250 Ohm)",
            category: "AutoEQ",
            preampDB: -4.2,
            gainsDB: [4.2, 2.0, -1.5, -0.4, 1.6, 1.0, 1.4, -4.0, -5.8, 0.5]
        ),
        MixerEQPreset(
            id: "autoeq-ath-m50x",
            name: "Audio-Technica ATH-M50x",
            category: "AutoEQ",
            preampDB: -2.2,
            gainsDB: [-1.0, -2.4, -1.8, 0.8, 1.8, 1.0, -1.2, -2.4, -0.6, 0.5]
        ),
        MixerEQPreset(
            id: "autoeq-mbp-speakers",
            name: "MacBook Pro 14/16 Speakers",
            category: "AutoEQ",
            preampDB: -4.2,
            gainsDB: [4.2, 3.4, 1.0, -1.8, -1.2, 0.6, 1.4, 0.8, 1.8, 2.4]
        ),
        MixerEQPreset(
            id: "autoeq-hifiman-sundara",
            name: "HiFiMAN Sundara",
            category: "AutoEQ",
            preampDB: -4.5,
            gainsDB: [4.5, 2.2, 0.4, 0.0, -0.4, 0.0, 2.2, 0.8, -2.2, 1.2]
        ),
        MixerEQPreset(
            id: "autoeq-focal-bathys",
            name: "Focal Bathys",
            category: "AutoEQ",
            preampDB: -2.4,
            gainsDB: [1.5, 0.4, -1.0, -1.4, 0.2, -0.8, 1.8, 2.4, -0.8, 1.2]
        ),
        MixerEQPreset(
            id: "autoeq-sennheiser-momentum-4",
            name: "Sennheiser Momentum 4",
            category: "AutoEQ",
            preampDB: -2.8,
            gainsDB: [-3.8, -4.2, -2.2, -0.5, 1.2, 1.8, 2.8, 1.6, 0.8, 1.2]
        ),
        MixerEQPreset(
            id: "autoeq-koss-porta-pro",
            name: "Koss Porta Pro",
            category: "AutoEQ",
            preampDB: -4.8,
            gainsDB: [4.8, 1.5, -3.2, -3.5, -1.0, 0.5, 1.8, 3.2, 4.2, 4.5]
        ),
    ]

    static func preset(id: String) -> MixerEQPreset? {
        presets.first { $0.id == id }
    }

    static func search(_ query: String) -> [MixerEQPreset] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return presets }
        let tokens = trimmed
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return presets }

        return presets.filter { preset in
            let haystack = "\(preset.name) \(preset.id) \(preset.category)"
            return tokens.allSatisfy { token in
                haystack.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }
}

/// Parses EqualizerAPO / AutoEQ `ParametricEQ.txt` profiles and projects their combined
/// biquad frequency response onto `MixerParametricEQ`'s 10 ISO center frequencies.
enum AutoEQProfileParser {
    enum FilterType: String, Equatable, Codable, Sendable {
        case pk
        case lsc
        case hsc
        case ls
        case hs
        case lp
        case hp
        case lpq
        case hpq
    }

    struct Band: Equatable, Codable, Sendable {
        let type: FilterType
        let frequencyHz: Double
        let gainDB: Double
        let q: Double
    }

    struct ParsedProfile: Equatable, Sendable {
        let preampDB: Float
        let bands: [Band]
    }

    private static let minFrequencyHz = 20.0
    private static let maxFrequencyHz = 20_000.0
    private static let minGainDB = -15.0
    private static let maxGainDB = 15.0
    private static let minQ = 0.1
    private static let maxQ = 12.0
    private static let maxPreampDB = 12.0
    private static let evaluationSampleRate = 96_000.0

    static func parseEqualizerAPO(_ content: String, name: String) -> MixerEQPreset? {
        guard let parsed = parseBands(content) else { return nil }

        var isoGainsDB: [Float] = []
        isoGainsDB.reserveCapacity(MixerEQPreset.isoFrequenciesHz.count)

        for centerFreq in MixerEQPreset.isoFrequenciesHz {
            var totalDB = 0.0
            for band in parsed.bands {
                totalDB += magnitudeDB(for: band,
                                       atFrequencyHz: centerFreq,
                                       sampleRate: evaluationSampleRate)
            }
            let clamped = totalDB.isFinite ? min(max(totalDB, minGainDB), maxGainDB) : 0.0
            let rounded = (clamped * 100.0).rounded() / 100.0
            isoGainsDB.append(Float(rounded))
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? "Imported AutoEQ" : String(trimmedName.prefix(64))
        let slug = slugify(resolvedName)
        let resolvedID = slug.isEmpty ? "autoeq-\(UUID().uuidString)" : "autoeq-\(slug)"

        return MixerEQPreset(
            id: resolvedID,
            name: resolvedName,
            category: "AutoEQ",
            preampDB: parsed.preampDB,
            gainsDB: isoGainsDB
        )
    }

    static func parseBands(_ content: String) -> ParsedProfile? {
        var preampDB: Float = 0
        var bands: [Band] = []

        let lines = content.components(separatedBy: .newlines)
        for rawLine in lines {
            let lineWithoutComment: Substring
            if let commentIndex = rawLine.firstIndex(of: "#") {
                lineWithoutComment = rawLine[..<commentIndex]
            } else {
                lineWithoutComment = rawLine[...]
            }
            let trimmed = lineWithoutComment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix(";") else { continue }
            guard let colonIndex = trimmed.firstIndex(of: ":") else { continue }

            let header = trimmed[..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let body = trimmed[trimmed.index(after: colonIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }

            let headerLower = header.lowercased()
            if headerLower == "preamp" {
                if let parsedPreamp = parsePreampDB(body) {
                    preampDB = parsedPreamp
                }
                continue
            }

            if isFilterHeader(headerLower), let band = parseFilterBand(body) {
                bands.append(band)
            }
        }

        guard !bands.isEmpty else { return nil }
        return ParsedProfile(preampDB: preampDB, bands: bands)
    }

    private static func isFilterHeader(_ headerLower: String) -> Bool {
        let parts = headerLower
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        guard parts.first == "filter" else { return false }
        if parts.count == 1 { return true }
        return parts.count == 2 && Int(parts[1]) != nil
    }

    private static func parsePreampDB(_ body: String) -> Float? {
        let tokens = body
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        guard let first = tokens.first,
              let value = parseNumeric(first, suffix: "db") else {
            return nil
        }
        let clamped = min(max(value, -maxPreampDB), maxPreampDB)
        return Float(clamped)
    }

    private static func parseFilterBand(_ body: String) -> Band? {
        let tokens = body
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        guard tokens.count >= 4 else { return nil }
        guard tokens[0].lowercased() == "on" else { return nil }
        guard let filterType = parseFilterType(tokens[1]) else { return nil }

        var rawFreq: Double?
        var rawGain: Double?
        var rawQ: Double?

        var index = 2
        while index < tokens.count {
            let key = tokens[index].lowercased()
            if key == "fc", index + 1 < tokens.count {
                rawFreq = parseNumeric(tokens[index + 1], suffix: "hz")
                index += 2
                if index < tokens.count, tokens[index].lowercased() == "hz" {
                    index += 1
                }
            } else if key == "gain", index + 1 < tokens.count {
                rawGain = parseNumeric(tokens[index + 1], suffix: "db")
                index += 2
                if index < tokens.count, tokens[index].lowercased() == "db" {
                    index += 1
                }
            } else if key == "q", index + 1 < tokens.count {
                rawQ = parseNumeric(tokens[index + 1], suffix: "")
                index += 2
            } else {
                index += 1
            }
        }

        guard let freq = rawFreq, freq.isFinite, freq > 0 else { return nil }
        let clampedFreq = min(max(freq, minFrequencyHz), maxFrequencyHz)

        let requiresGain: Bool
        switch filterType {
        case .pk, .lsc, .hsc, .ls, .hs:
            requiresGain = true
        case .lp, .hp, .lpq, .hpq:
            requiresGain = false
        }

        let clampedGain: Double
        if let gain = rawGain {
            guard gain.isFinite else { return nil }
            clampedGain = min(max(gain, minGainDB), maxGainDB)
        } else if requiresGain {
            return nil
        } else {
            clampedGain = 0.0
        }

        let clampedQ: Double
        if let q = rawQ {
            guard q.isFinite, q > 0 else { return nil }
            clampedQ = min(max(q, minQ), maxQ)
        } else {
            clampedQ = filterType == .pk ? 1.41 : 0.7071067811865476
        }

        return Band(
            type: filterType,
            frequencyHz: clampedFreq,
            gainDB: clampedGain,
            q: clampedQ
        )
    }

    private static func parseFilterType(_ token: String) -> FilterType? {
        switch token.lowercased() {
        case "pk", "peq":
            return .pk
        case "lsc":
            return .lsc
        case "hsc":
            return .hsc
        case "ls":
            return .ls
        case "hs":
            return .hs
        case "lp":
            return .lp
        case "hp":
            return .hp
        case "lpq":
            return .lpq
        case "hpq":
            return .hpq
        default:
            return nil
        }
    }

    private static func parseNumeric(_ token: String, suffix: String) -> Double? {
        var cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !suffix.isEmpty, cleaned.hasSuffix(suffix) {
            cleaned = String(cleaned.dropLast(suffix.count))
        }
        cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else {
            return nil
        }
        return value
    }

    private static func magnitudeDB(for band: Band, atFrequencyHz freq: Double, sampleRate: Double) -> Double {
        let coeffs = biquadCoefficients(for: band, sampleRate: sampleRate)
        let w = 2.0 * Double.pi * freq / sampleRate
        let cosW = cos(w)
        let sinW = sin(w)
        let cos2W = cos(2.0 * w)
        let sin2W = sin(2.0 * w)

        let numReal = coeffs.b0 + coeffs.b1 * cosW + coeffs.b2 * cos2W
        let numImag = -(coeffs.b1 * sinW + coeffs.b2 * sin2W)
        let denReal = 1.0 + coeffs.a1 * cosW + coeffs.a2 * cos2W
        let denImag = -(coeffs.a1 * sinW + coeffs.a2 * sin2W)

        let numSq = numReal * numReal + numImag * numImag
        let denSq = max(denReal * denReal + denImag * denImag, 1e-24)
        let magSq = max(numSq / denSq, 1e-12)
        return 10.0 * log10(magSq)
    }

    private static func biquadCoefficients(
        for band: Band,
        sampleRate: Double
    ) -> (b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        let fc = min(max(band.frequencyHz, minFrequencyHz), sampleRate * 0.48)
        let q = min(max(band.q, minQ), maxQ)

        switch band.type {
        case .pk:
            return MixerParametricEQ.peakingBiquadCoefficients(
                frequencyHz: fc,
                sampleRate: sampleRate,
                q: q,
                gainDB: Float(band.gainDB)
            )
        case .lsc, .ls:
            return FletcherMunsonLoudness.lowShelfCoefficients(
                frequencyHz: fc,
                sampleRate: sampleRate,
                q: q,
                gainDB: band.gainDB
            )
        case .hsc, .hs:
            return FletcherMunsonLoudness.highShelfCoefficients(
                frequencyHz: fc,
                sampleRate: sampleRate,
                q: q,
                gainDB: band.gainDB
            )
        case .lp, .lpq:
            let w0 = 2.0 * Double.pi * fc / sampleRate
            let cosW0 = cos(w0)
            let alpha = sin(w0) / (2.0 * q)
            let b0 = (1.0 - cosW0) * 0.5
            let b1 = 1.0 - cosW0
            let b2 = b0
            let a0 = 1.0 + alpha
            let a1 = -2.0 * cosW0
            let a2 = 1.0 - alpha
            return (b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)
        case .hp, .hpq:
            let w0 = 2.0 * Double.pi * fc / sampleRate
            let cosW0 = cos(w0)
            let alpha = sin(w0) / (2.0 * q)
            let b0 = (1.0 + cosW0) * 0.5
            let b1 = -(1.0 + cosW0)
            let b2 = b0
            let a0 = 1.0 + alpha
            let a1 = -2.0 * cosW0
            let a2 = 1.0 - alpha
            return (b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)
        }
    }

    private static func slugify(_ input: String) -> String {
        let lower = input.lowercased()
        var result = ""
        var previousWasDash = false
        for scalar in lower.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII {
                result.unicodeScalars.append(scalar)
                previousWasDash = false
            } else if !previousWasDash && !result.isEmpty {
                result.append("-")
                previousWasDash = true
            }
        }
        while result.last == "-" {
            result.removeLast()
        }
        return result
    }
}

/// ISO-226 / Fletcher-Munson equal-loudness contour compensation and lock-free
/// real-time dual-biquad shelf processor.
public enum FletcherMunsonLoudness {
    public static let lowShelfFrequencyHz: Double = 95.0
    public static let highShelfFrequencyHz: Double = 9500.0
    private static let shelfQ: Double = 0.7071067811865476

    public static func compensationGains(volume: Double, enabled: Bool) -> (lowShelfDB: Double, highShelfDB: Double) {
        guard enabled, volume.isFinite else { return (0, 0) }
        let clamped = min(max(volume, 0.0), 1.0)
        if clamped >= 0.999 {
            return (0, 0)
        }
        let attenuation = 1.0 - clamped
        let lowShelfDB = 8.5 * pow(attenuation, 1.2)
        let highShelfDB = 4.5 * pow(attenuation, 1.35)
        return (lowShelfDB, highShelfDB)
    }

    fileprivate static func lowShelfCoefficients(
        frequencyHz: Double,
        sampleRate: Double,
        q: Double,
        gainDB: Double
    ) -> (b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        guard gainDB.isFinite, frequencyHz.isFinite, sampleRate.isFinite,
              sampleRate >= 8_000, abs(gainDB) >= 0.01, frequencyHz < sampleRate * 0.48 else {
            return (1, 0, 0, 0, 0)
        }
        let a = pow(10.0, gainDB / 40.0)
        let sqrtA = sqrt(a)
        let w0 = 2.0 * Double.pi * max(20.0, frequencyHz) / sampleRate
        let cosW0 = cos(w0)
        let sinW0 = sin(w0)
        let alpha = sinW0 / (2.0 * max(0.1, q))
        let twoSqrtAAlpha = 2.0 * sqrtA * alpha

        let b0 = a * ((a + 1.0) - (a - 1.0) * cosW0 + twoSqrtAAlpha)
        let b1 = 2.0 * a * ((a - 1.0) - (a + 1.0) * cosW0)
        let b2 = a * ((a + 1.0) - (a - 1.0) * cosW0 - twoSqrtAAlpha)
        let a0 = (a + 1.0) + (a - 1.0) * cosW0 + twoSqrtAAlpha
        let a1 = -2.0 * ((a - 1.0) + (a + 1.0) * cosW0)
        let a2 = (a + 1.0) + (a - 1.0) * cosW0 - twoSqrtAAlpha

        guard a0.isFinite, abs(a0) > 1e-12 else { return (1, 0, 0, 0, 0) }
        return (b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)
    }

    fileprivate static func highShelfCoefficients(
        frequencyHz: Double,
        sampleRate: Double,
        q: Double,
        gainDB: Double
    ) -> (b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        guard gainDB.isFinite, frequencyHz.isFinite, sampleRate.isFinite,
              sampleRate >= 8_000, abs(gainDB) >= 0.01, frequencyHz < sampleRate * 0.48 else {
            return (1, 0, 0, 0, 0)
        }
        let a = pow(10.0, gainDB / 40.0)
        let sqrtA = sqrt(a)
        let w0 = 2.0 * Double.pi * max(20.0, frequencyHz) / sampleRate
        let cosW0 = cos(w0)
        let sinW0 = sin(w0)
        let alpha = sinW0 / (2.0 * max(0.1, q))
        let twoSqrtAAlpha = 2.0 * sqrtA * alpha

        let b0 = a * ((a + 1.0) + (a - 1.0) * cosW0 + twoSqrtAAlpha)
        let b1 = -2.0 * a * ((a - 1.0) + (a + 1.0) * cosW0)
        let b2 = a * ((a + 1.0) + (a - 1.0) * cosW0 - twoSqrtAAlpha)
        let a0 = (a + 1.0) - (a - 1.0) * cosW0 + twoSqrtAAlpha
        let a1 = 2.0 * ((a - 1.0) - (a + 1.0) * cosW0)
        let a2 = (a + 1.0) - (a - 1.0) * cosW0 - twoSqrtAAlpha

        guard a0.isFinite, abs(a0) > 1e-12 else { return (1, 0, 0, 0, 0) }
        return (b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)
    }

    /// Lock-free multi-channel (up to 8 channels) dual-biquad processor applying
    /// Fletcher-Munson 95 Hz low-shelf and 9500 Hz high-shelf compensation with zero
    /// heap allocations on the real-time audio thread.
    public final class LoudnessBiquadProcessor: @unchecked Sendable {
        public static let maxChannels = 8

        private var lock = os_unfair_lock()
        private var bypassFlagBits: Int32 = 1
        private var isBypassedState = true
        private var sampleRate: Double

        private var lowB0: Double = 1
        private var lowB1: Double = 0
        private var lowB2: Double = 0
        private var lowA1: Double = 0
        private var lowA2: Double = 0

        private var highB0: Double = 1
        private var highB1: Double = 0
        private var highB2: Double = 0
        private var highA1: Double = 0
        private var highA2: Double = 0

        private let lowZ1: UnsafeMutablePointer<Double>
        private let lowZ2: UnsafeMutablePointer<Double>
        private let highZ1: UnsafeMutablePointer<Double>
        private let highZ2: UnsafeMutablePointer<Double>

        public var isBypassed: Bool {
            withUnsafeMutablePointer(to: &bypassFlagBits) { ptr in
                OSAtomicAdd32Barrier(0, ptr) != 0
            }
        }

        public init(sampleRate: Double = 48_000) {
            self.sampleRate = sampleRate.isFinite && sampleRate >= 8_000 ? sampleRate : 48_000
            self.lowZ1 = UnsafeMutablePointer<Double>.allocate(capacity: Self.maxChannels)
            self.lowZ2 = UnsafeMutablePointer<Double>.allocate(capacity: Self.maxChannels)
            self.highZ1 = UnsafeMutablePointer<Double>.allocate(capacity: Self.maxChannels)
            self.highZ2 = UnsafeMutablePointer<Double>.allocate(capacity: Self.maxChannels)
            self.lowZ1.initialize(repeating: 0, count: Self.maxChannels)
            self.lowZ2.initialize(repeating: 0, count: Self.maxChannels)
            self.highZ1.initialize(repeating: 0, count: Self.maxChannels)
            self.highZ2.initialize(repeating: 0, count: Self.maxChannels)
        }

        deinit {
            lowZ1.deinitialize(count: Self.maxChannels)
            lowZ2.deinitialize(count: Self.maxChannels)
            highZ1.deinitialize(count: Self.maxChannels)
            highZ2.deinitialize(count: Self.maxChannels)
            lowZ1.deallocate()
            lowZ2.deallocate()
            highZ1.deallocate()
            highZ2.deallocate()
        }

        public func update(volume: Double, enabled: Bool, sampleRate: Double = 48_000) {
            let safeRate = sampleRate.isFinite && sampleRate >= 8_000 ? sampleRate : 48_000
            let gains = FletcherMunsonLoudness.compensationGains(volume: volume, enabled: enabled)
            let shouldBypass = !enabled || !volume.isFinite
                || (abs(gains.lowShelfDB) < 0.01 && abs(gains.highShelfDB) < 0.01)

            let low = shouldBypass
                ? (b0: 1.0, b1: 0.0, b2: 0.0, a1: 0.0, a2: 0.0)
                : FletcherMunsonLoudness.lowShelfCoefficients(
                    frequencyHz: FletcherMunsonLoudness.lowShelfFrequencyHz,
                    sampleRate: safeRate,
                    q: FletcherMunsonLoudness.shelfQ,
                    gainDB: gains.lowShelfDB
                )
            let high = shouldBypass
                ? (b0: 1.0, b1: 0.0, b2: 0.0, a1: 0.0, a2: 0.0)
                : FletcherMunsonLoudness.highShelfCoefficients(
                    frequencyHz: FletcherMunsonLoudness.highShelfFrequencyHz,
                    sampleRate: safeRate,
                    q: FletcherMunsonLoudness.shelfQ,
                    gainDB: gains.highShelfDB
                )

            os_unfair_lock_lock(&lock)
            let rateChanged = abs(safeRate - self.sampleRate) > 1.0
            let stateTransition = shouldBypass || self.isBypassedState
            if rateChanged || stateTransition {
                resetStatesLocked()
            }
            self.sampleRate = safeRate
            self.isBypassedState = shouldBypass

            self.lowB0 = low.b0
            self.lowB1 = low.b1
            self.lowB2 = low.b2
            self.lowA1 = low.a1
            self.lowA2 = low.a2

            self.highB0 = high.b0
            self.highB1 = high.b1
            self.highB2 = high.b2
            self.highA1 = high.a1
            self.highA2 = high.a2

            Self.atomicStoreInt32(shouldBypass ? 1 : 0, into: &bypassFlagBits)
            os_unfair_lock_unlock(&lock)
        }

        public func reset() {
            os_unfair_lock_lock(&lock)
            resetStatesLocked()
            os_unfair_lock_unlock(&lock)
        }

        @discardableResult
        public func process(
            channelCount: Int,
            frames: Int,
            channels: UnsafePointer<UnsafeMutablePointer<Float>>
        ) -> Bool {
            guard frames > 0, channelCount > 0 else { return true }
            if isBypassed { return true }
            guard os_unfair_lock_trylock(&lock) else { return false }
            defer { os_unfair_lock_unlock(&lock) }
            if isBypassedState { return true }

            let activeChannels = min(channelCount, Self.maxChannels)
            for ch in 0..<activeChannels {
                processChannelLocked(samples: channels[ch], stride: 1, frames: frames, channelIndex: ch)
            }
            return true
        }

        @discardableResult
        public func processAudioBufferList(
            _ bufferList: UnsafeMutableAudioBufferListPointer,
            frames: Int
        ) -> Bool {
            guard frames > 0, !bufferList.isEmpty else { return true }
            if isBypassed { return true }
            guard os_unfair_lock_trylock(&lock) else { return false }
            defer { os_unfair_lock_unlock(&lock) }
            if isBypassedState { return true }

            var allSingleChannel = true
            for index in 0..<bufferList.count {
                if bufferList[index].mNumberChannels != 1 {
                    allSingleChannel = false
                    break
                }
            }

            if allSingleChannel {
                let activeChannels = min(bufferList.count, Self.maxChannels)
                for ch in 0..<activeChannels {
                    guard let base = bufferList[ch].mData?.assumingMemoryBound(to: Float.self) else { continue }
                    let safeFrames = min(frames, Int(bufferList[ch].mDataByteSize) / MemoryLayout<Float>.size)
                    if safeFrames > 0 {
                        processChannelLocked(samples: base, stride: 1, frames: safeFrames, channelIndex: ch)
                    }
                }
                return true
            }

            var channelOffset = 0
            for index in 0..<bufferList.count {
                let buf = bufferList[index]
                let channels = Int(buf.mNumberChannels)
                guard channels > 0 else { continue }
                defer { channelOffset += channels }
                guard channelOffset < Self.maxChannels,
                      let base = buf.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let safeFrames = min(frames, Int(buf.mDataByteSize) / (MemoryLayout<Float>.size * channels))
                guard safeFrames > 0 else { continue }

                let limit = min(channels, Self.maxChannels - channelOffset)
                for ch in 0..<limit {
                    processChannelLocked(samples: base + ch,
                                         stride: channels,
                                         frames: safeFrames,
                                         channelIndex: channelOffset + ch)
                }
            }
            return true
        }

        private func processChannelLocked(
            samples: UnsafeMutablePointer<Float>,
            stride: Int,
            frames: Int,
            channelIndex: Int
        ) {
            var lz1 = lowZ1[channelIndex]
            var lz2 = lowZ2[channelIndex]
            var hz1 = highZ1[channelIndex]
            var hz2 = highZ2[channelIndex]
            if !lz1.isFinite || !lz2.isFinite {
                lz1 = 0
                lz2 = 0
            }
            if !hz1.isFinite || !hz2.isFinite {
                hz1 = 0
                hz2 = 0
            }

            let lb0 = lowB0
            let lb1 = lowB1
            let lb2 = lowB2
            let la1 = lowA1
            let la2 = lowA2

            let hb0 = highB0
            let hb1 = highB1
            let hb2 = highB2
            let ha1 = highA1
            let ha2 = highA2

            var sampleOffset = 0
            for _ in 0..<frames {
                let raw = samples[sampleOffset]
                let x = raw.isFinite ? Double(raw) : 0.0

                var mid = lb0 * x + lz1
                var nlz1 = lb1 * x - la1 * mid + lz2
                var nlz2 = lb2 * x - la2 * mid
                if !mid.isFinite || !nlz1.isFinite || !nlz2.isFinite {
                    mid = x
                    nlz1 = 0
                    nlz2 = 0
                } else {
                    if abs(nlz1) < 1e-18 { nlz1 = 0 }
                    if abs(nlz2) < 1e-18 { nlz2 = 0 }
                }
                lz1 = nlz1
                lz2 = nlz2

                var y = hb0 * mid + hz1
                var nhz1 = hb1 * mid - ha1 * y + hz2
                var nhz2 = hb2 * mid - ha2 * y
                if !y.isFinite || !nhz1.isFinite || !nhz2.isFinite {
                    y = mid
                    nhz1 = 0
                    nhz2 = 0
                } else {
                    if abs(nhz1) < 1e-18 { nhz1 = 0 }
                    if abs(nhz2) < 1e-18 { nhz2 = 0 }
                }
                hz1 = nhz1
                hz2 = nhz2

                samples[sampleOffset] = y.isFinite ? Float(y) : 0
                sampleOffset += stride
            }

            lowZ1[channelIndex] = lz1
            lowZ2[channelIndex] = lz2
            highZ1[channelIndex] = hz1
            highZ2[channelIndex] = hz2
        }

        private func resetStatesLocked() {
            for ch in 0..<Self.maxChannels {
                lowZ1[ch] = 0
                lowZ2[ch] = 0
                highZ1[ch] = 0
                highZ2[ch] = 0
            }
        }

        private static func atomicStoreInt32(_ value: Int32, into storage: UnsafeMutablePointer<Int32>) {
            while true {
                let current = OSAtomicAdd32Barrier(0, storage)
                if OSAtomicCompareAndSwap32Barrier(current, value, storage) { return }
            }
        }
    }
}
