// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Jewel-tone category accents replacing flat monochrome accentColor across
/// Settings rows, sidebar badges, Feature Hub cards, and previews.
enum SemanticCategoryTone: String, CaseIterable, Equatable, Sendable {
    case windowsDock
    case mouseKeyboard
    case clipboardFiles
    case sound
    case energyDisplay
    case tools
    case dynamicIsland
    case monitor
    case brand

    struct RGB: Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double
    }

    struct Triad: Equatable, Sendable {
        let light: RGB
        let dark: RGB
        let highContrast: RGB

        func resolved(scheme: ColorScheme, highContrast isHighContrast: Bool) -> Color {
            let c: RGB
            if isHighContrast {
                c = highContrast
            } else {
                c = scheme == .dark ? dark : light
            }
            return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: 1)
        }
    }

    var rgbTriad: Triad {
        switch self {
        case .windowsDock:
            return Triad(light: RGB(red: 0.11, green: 0.42, blue: 0.90),
                         dark: RGB(red: 0.31, green: 0.62, blue: 1.00),
                         highContrast: RGB(red: 0.04, green: 0.30, blue: 0.80))
        case .mouseKeyboard:
            return Triad(light: RGB(red: 0.36, green: 0.34, blue: 0.86),
                         dark: RGB(red: 0.51, green: 0.50, blue: 0.98),
                         highContrast: RGB(red: 0.28, green: 0.25, blue: 0.78))
        case .clipboardFiles:
            return Triad(light: RGB(red: 0.04, green: 0.56, blue: 0.62),
                         dark: RGB(red: 0.22, green: 0.78, blue: 0.84),
                         highContrast: RGB(red: 0.02, green: 0.44, blue: 0.50))
        case .sound:
            return Triad(light: RGB(red: 0.86, green: 0.27, blue: 0.29),
                         dark: RGB(red: 0.98, green: 0.44, blue: 0.45),
                         highContrast: RGB(red: 0.76, green: 0.16, blue: 0.20))
        case .energyDisplay:
            return Triad(light: RGB(red: 0.80, green: 0.48, blue: 0.04),
                         dark: RGB(red: 0.98, green: 0.69, blue: 0.20),
                         highContrast: RGB(red: 0.68, green: 0.38, blue: 0.00))
        case .tools:
            return Triad(light: RGB(red: 0.08, green: 0.58, blue: 0.38),
                         dark: RGB(red: 0.24, green: 0.80, blue: 0.56),
                         highContrast: RGB(red: 0.04, green: 0.46, blue: 0.28))
        case .dynamicIsland:
            return Triad(light: RGB(red: 0.55, green: 0.29, blue: 0.88),
                         dark: RGB(red: 0.72, green: 0.49, blue: 0.99),
                         highContrast: RGB(red: 0.44, green: 0.18, blue: 0.78))
        case .monitor:
            return Triad(light: RGB(red: 0.14, green: 0.56, blue: 0.29),
                         dark: RGB(red: 0.30, green: 0.78, blue: 0.47),
                         highContrast: RGB(red: 0.08, green: 0.44, blue: 0.20))
        case .brand:
            return Triad(light: RGB(red: 0.38, green: 0.33, blue: 0.92),
                         dark: RGB(red: 0.55, green: 0.51, blue: 0.99),
                         highContrast: RGB(red: 0.28, green: 0.22, blue: 0.82))
        }
    }

    func color(scheme: ColorScheme = .dark, highContrast: Bool = false) -> Color {
        rgbTriad.resolved(scheme: scheme, highContrast: highContrast)
    }

    var badgeColor: Color {
        rgbTriad.resolved(scheme: .dark, highContrast: false)
    }
}

enum SemanticCategoryPalette {
    static func tone(for group: FeatureGroup) -> SemanticCategoryTone {
        switch group {
        case .windowsDock: return .windowsDock
        case .mouseKeyboard: return .mouseKeyboard
        case .clipboardFiles: return .clipboardFiles
        case .sound: return .sound
        case .energyDisplay: return .energyDisplay
        case .tools: return .tools
        case .dynamicIsland: return .dynamicIsland
        case .monitor: return .monitor
        }
    }

    static func tone(for feature: AppFeature) -> SemanticCategoryTone {
        tone(for: feature.group)
    }

    /// Maps an SF Symbol name or identifier keyword to its semantic tone so
    /// SettingsRow and sidebar rows automatically adopt jewel-tone accents.
    static func tone(forSymbol symbol: String?) -> SemanticCategoryTone {
        guard let symbol = symbol?.lowercased(), !symbol.isEmpty else { return .brand }
        if symbol.contains("speaker") || symbol.contains("music") || symbol.contains("waveform")
            || symbol.contains("mic") || symbol.contains("airplay") || symbol.contains("headphones") {
            return .sound
        }
        if symbol.contains("battery") || symbol.contains("bolt") || symbol.contains("sun")
            || symbol.contains("display") || symbol.contains("cup") || symbol.contains("moon") {
            return .energyDisplay
        }
        if symbol.contains("dock") || symbol.contains("macwindow") || symbol.contains("rectangle.3")
            || symbol.contains("rectangle.on") || symbol.contains("squares") || symbol.contains("shield") {
            return .windowsDock
        }
        if symbol.contains("cursorarrow") || symbol.contains("scroll") || symbol.contains("keyboard")
            || symbol.contains("command") || symbol.contains("hand.tap") || symbol.contains("arrow.up.arrow")
            || symbol.contains("arrow.left") {
            return .mouseKeyboard
        }
        if symbol.contains("clipboard") || symbol.contains("tray") || symbol.contains("doc")
            || symbol.contains("folder") || symbol.contains("trash") || symbol.contains("arrow.down.doc")
            || symbol.contains("shippingbox") {
            return .clipboardFiles
        }
        if symbol.contains("sparkles") || symbol.contains("face.smiling") || symbol.contains("bell")
            || symbol.contains("island") || symbol.contains("paintpalette") || symbol.contains("calendar")
            || symbol.contains("web.camera") || symbol.contains("timer") {
            return .dynamicIsland
        }
        if symbol.contains("cpu") || symbol.contains("memory") || symbol.contains("gauge")
            || symbol.contains("fan") || symbol.contains("thermometer") || symbol.contains("network")
            || symbol.contains("internaldrive") {
            return .monitor
        }
        if symbol.contains("camera") || symbol.contains("video") || symbol.contains("record")
            || symbol.contains("eyedropper") || symbol.contains("text.viewfinder") || symbol.contains("photo") {
            return .tools
        }
        return .brand
    }

    static func color(for group: FeatureGroup, scheme: ColorScheme = .dark, highContrast: Bool = false) -> Color {
        tone(for: group).color(scheme: scheme, highContrast: highContrast)
    }

    static func color(forSymbol symbol: String?, scheme: ColorScheme = .dark, highContrast: Bool = false) -> Color {
        tone(forSymbol: symbol).color(scheme: scheme, highContrast: highContrast)
    }
}
