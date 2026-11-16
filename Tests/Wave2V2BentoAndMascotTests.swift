// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum Wave2V2BentoAndMascotContract {
    static func run(_ suite: TestSuite) {
        testArtworkColorExtraction(suite)
        testArtworkHashDeterminism(suite)
        testMascotCameoAndBentoSourcePresence(suite)
    }

    private static func testArtworkColorExtraction(_ suite: TestSuite) {
        func makeSolidImage(r: UInt8, g: UInt8, b: UInt8, width: Int = 32, height: Int = 32) -> CGImage? {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            var data = [UInt8](repeating: 0, count: width * height * 4)
            for idx in stride(from: 0, to: data.count, by: 4) {
                data[idx] = r
                data[idx + 1] = g
                data[idx + 2] = b
                data[idx + 3] = 255
            }
            return data.withUnsafeMutableBytes { buf -> CGImage? in
                guard let ctx = CGContext(
                    data: buf.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return nil }
                return ctx.makeImage()
            }
        }

        if let cyanImage = makeSolidImage(r: 20, g: 190, b: 245) {
            let color = NotchArtworkColorExtractor.dominantVibrantRGB(from: cyanImage)
            suite.expect(color != nil && (color?.blue ?? 0) > (color?.red ?? 1) && (color?.saturation ?? 0) > 0.4,
                         "NotchArtworkColorExtractor extracts vibrant blue-cyan tone for ambient island glow")
        } else {
            suite.expect(false, "Could not create synthetic cyan CGImage")
        }

        if let grayImage = makeSolidImage(r: 120, g: 120, b: 120),
           let blackImage = makeSolidImage(r: 8, g: 8, b: 8) {
            suite.expect(NotchArtworkColorExtractor.dominantVibrantRGB(from: grayImage) == nil
                         && NotchArtworkColorExtractor.dominantVibrantRGB(from: blackImage) == nil,
                         "NotchArtworkColorExtractor filters out neutral gray and near-black covers")
        }
    }

    private static func testArtworkHashDeterminism(_ suite: TestSuite) {
        let a = Data(repeating: 0x4A, count: 256)
        let b = Data(repeating: 0x4B, count: 256)
        suite.expect(NotchArtworkColorExtractor.artworkHash(for: a) == NotchArtworkColorExtractor.artworkHash(for: a)
                     && NotchArtworkColorExtractor.artworkHash(for: a) != NotchArtworkColorExtractor.artworkHash(for: b),
                     "artworkHash produces stable distinct keys for different artwork buffers")
    }

    private static func testMascotCameoAndBentoSourcePresence(_ suite: TestSuite) {
        let menuPanel = (try? String(contentsOfFile: "Sources/Vorssaint/UI/MenuPanel/MenuPanelView.swift", encoding: .utf8)) ?? ""
        suite.expect(menuPanel.contains("BentoQuickModesDeck") && menuPanel.contains("BentoQuickToggleTileView"),
                     "MenuPanelView renders Bento quick-control deck and 2-column Bento toggle grid")

        for path in [
            "Sources/Vorssaint/UI/Cleaner/CleanerView.swift",
            "Sources/Vorssaint/UI/Uninstall/UninstallerView.swift",
            "Sources/Vorssaint/UI/Media/MediaWorkspaceView.swift",
            "Sources/Vorssaint/UI/AppUpdates/AppUpdatesListView.swift",
            "Sources/Vorssaint/UI/PortManager/PortManagerView.swift",
        ] {
            let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            suite.expect(content.contains("MascotCameoBadge"),
                         "\(path) integrates MascotCameoBadge cameo state")
        }
    }
}
