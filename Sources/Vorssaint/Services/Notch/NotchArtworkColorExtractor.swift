// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import os

/// Pure CoreGraphics helper that extracts a dominant vibrant RGB color from
/// album artwork by downsampling into an 8x8 RGBA context, filtering near-black,
/// near-white, and desaturated pixels, and scoring by saturation * luminance weight.
enum NotchArtworkColorExtractor {
    struct RGBAColor: Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double
        let saturation: Double
    }

    private final class CacheEntry: NSObject {
        let color: RGBAColor?

        init(color: RGBAColor?) {
            self.color = color
        }
    }

    private final class CacheBox: @unchecked Sendable {
        let cache: NSCache<NSString, CacheEntry> = {
            let cache = NSCache<NSString, CacheEntry>()
            cache.countLimit = 64
            return cache
        }()
        let lock = OSAllocatedUnfairLock()
    }

    private static let cacheBox = CacheBox()

    /// Computes a lightweight O(1) hash key from raw artwork bytes.
    static func artworkHash(for data: Data) -> String {
        guard !data.isEmpty else { return "d-0" }
        var hash: UInt64 = 14_695_981_039_346_656_037
        let count = data.count
        let sampleCount = min(count, 128)
        let step = max(1, count / sampleCount)
        data.withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            var index = 0
            var sampled = 0
            while index < count && sampled < sampleCount {
                hash ^= UInt64(bytes[index])
                hash &*= 1_099_511_628_211
                index += step
                sampled += 1
            }
            hash ^= UInt64(bytes[count - 1])
            hash &*= 1_099_511_628_211
        }
        return "d-\(count)-\(String(hash, radix: 16))"
    }

    static func dominantVibrantRGB(from cgImage: CGImage) -> RGBAColor? {
        dominantVibrantRGB(from: cgImage, artworkHash: nil)
    }

    static func dominantVibrantRGB(from cgImage: CGImage, artworkHash: String?) -> RGBAColor? {
        let keyString = artworkHash ?? self.artworkHash(for: cgImage)
        if let keyString {
            let key = keyString as NSString
            if let entry = cachedEntry(forKey: key) {
                return entry.color
            }
            let extracted = extractDominantVibrantRGB(from: cgImage)
            storeEntry(CacheEntry(color: extracted), forKey: key)
            return extracted
        }
        return extractDominantVibrantRGB(from: cgImage)
    }

    private static func cachedEntry(forKey key: NSString) -> CacheEntry? {
        cacheBox.lock.lock()
        defer { cacheBox.lock.unlock() }
        return cacheBox.cache.object(forKey: key)
    }

    private static func storeEntry(_ entry: CacheEntry, forKey key: NSString) {
        cacheBox.lock.lock()
        defer { cacheBox.lock.unlock() }
        cacheBox.cache.setObject(entry, forKey: key)
    }

    private static func artworkHash(for cgImage: CGImage) -> String? {
        guard let data = cgImage.dataProvider?.data else { return nil }
        let length = CFDataGetLength(data)
        guard length > 0, let bytes = CFDataGetBytePtr(data) else { return nil }

        var hash: UInt64 = 14_695_981_039_346_656_037
        let sampleCount = min(length, 128)
        let step = max(1, length / sampleCount)
        var index = 0
        var sampled = 0
        while index < length && sampled < sampleCount {
            hash ^= UInt64(bytes[index])
            hash &*= 1_099_511_628_211
            index += step
            sampled += 1
        }
        hash ^= UInt64(bytes[length - 1])
        hash &*= 1_099_511_628_211

        return "cg-\(cgImage.width)x\(cgImage.height)-\(cgImage.bytesPerRow)-\(cgImage.bitmapInfo.rawValue)-\(length)-\(String(hash, radix: 16))"
    }

    private static func extractDominantVibrantRGB(from cgImage: CGImage) -> RGBAColor? {
        guard cgImage.width > 0, cgImage.height > 0 else { return nil }

        let sampleSide = 8
        let pixelCount = sampleSide * sampleSide
        let bytesPerPixel = 4
        let bytesPerRow = sampleSide * bytesPerPixel
        var buffer = [UInt8](repeating: 0, count: pixelCount * bytesPerPixel)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB() as CGColorSpace? else {
            return nil
        }
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        let drawn = buffer.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                      data: baseAddress,
                      width: sampleSide,
                      height: sampleSide,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: colorSpace,
                      bitmapInfo: bitmapInfo
                  ) else {
                return false
            }
            context.interpolationQuality = .medium
            context.clear(CGRect(x: 0, y: 0, width: sampleSide, height: sampleSide))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleSide, height: sampleSide))
            return true
        }
        guard drawn else { return nil }

        struct HueBucket {
            var totalScore: Double = 0
            var redSum: Double = 0
            var greenSum: Double = 0
            var blueSum: Double = 0
            var saturationSum: Double = 0
        }

        var buckets = [HueBucket](repeating: HueBucket(), count: 12)

        for i in 0..<pixelCount {
            let offset = i * bytesPerPixel
            let alpha = Double(buffer[offset + 3]) / 255.0
            guard alpha >= 0.5 else { continue }

            let red = min(1.0, max(0.0, (Double(buffer[offset]) / 255.0) / alpha))
            let green = min(1.0, max(0.0, (Double(buffer[offset + 1]) / 255.0) / alpha))
            let blue = min(1.0, max(0.0, (Double(buffer[offset + 2]) / 255.0) / alpha))

            let maxC = max(red, max(green, blue))
            let minC = min(red, min(green, blue))
            let delta = maxC - minC

            // Filter near-black, near-white, and desaturated washed pixels.
            guard maxC >= 0.12, minC <= 0.88 else { continue }
            let saturation = maxC > 0 ? (delta / maxC) : 0
            guard saturation >= 0.18 else { continue }

            let lightness = (maxC + minC) * 0.5
            let luminanceWeight = max(0.15, sin(lightness * .pi))
            let score = saturation * luminanceWeight

            let hueSegment: Double
            if delta <= 0 {
                hueSegment = 0
            } else if maxC == red {
                hueSegment = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxC == green {
                hueSegment = (blue - red) / delta + 2
            } else {
                hueSegment = (red - green) / delta + 4
            }
            let normalizedHue = hueSegment < 0 ? hueSegment + 6 : hueSegment
            let bucketIndex = min(11, max(0, Int(normalizedHue * 2.0)))

            buckets[bucketIndex].totalScore += score
            buckets[bucketIndex].redSum += red * score
            buckets[bucketIndex].greenSum += green * score
            buckets[bucketIndex].blueSum += blue * score
            buckets[bucketIndex].saturationSum += saturation * score
        }

        guard let winner = buckets.max(by: { $0.totalScore < $1.totalScore }),
              winner.totalScore > 0 else {
            return nil
        }

        let inv = 1.0 / winner.totalScore
        return RGBAColor(
            red: min(1.0, max(0.0, winner.redSum * inv)),
            green: min(1.0, max(0.0, winner.greenSum * inv)),
            blue: min(1.0, max(0.0, winner.blueSum * inv)),
            saturation: min(1.0, max(0.0, winner.saturationSum * inv))
        )
    }
}
