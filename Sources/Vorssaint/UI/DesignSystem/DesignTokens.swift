// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Concentric corner radii across panels, cards, inner groups, and tiles.
enum DesignRadius {
    static let window: CGFloat = 20
    static let panel: CGFloat = 16
    static let card: CGFloat = 14
    static let innerGroup: CGFloat = 10
    static let pill: CGFloat = 8
    static let iconTile: CGFloat = 7
}

/// Five elevation & surface tiers shared across Settings, Editors, HUDs, and the Island.
enum DesignSurfaceTier {
    case canvas
    case card
    case elevated
    case glass
    case island

    func fillColor(for scheme: ColorScheme) -> Color {
        switch self {
        case .canvas:
            return scheme == .dark ? Color(white: 0.115) : Color(white: 0.965)
        case .card:
            return scheme == .dark ? Color.white.opacity(0.045) : Color.black.opacity(0.03)
        case .elevated:
            return scheme == .dark ? Color(white: 0.17) : Color.white.opacity(0.94)
        case .glass:
            return scheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.76)
        case .island:
            return Color.black
        }
    }
}

/// Shared motion language aligned with Apple spring physics and Reduce Motion.
enum DesignMotion {
    static let snappy = Animation.spring(response: 0.24, dampingFraction: 0.82)
    static let smooth = Animation.spring(response: 0.34, dampingFraction: 0.86)
    static let gentle = Animation.easeOut(duration: 0.22)

    static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

/// Subtle directional specular hairline stroke so cards and dark editors separate cleanly.
struct HairlineSpecularBorder: ViewModifier {
    let cornerRadius: CGFloat
    let opacity: Double
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let baseWhite: Double = colorScheme == .dark ? 1.0 : 0.0
        let topOpacity = colorScheme == .dark ? opacity : opacity * 0.42
        let bottomOpacity = colorScheme == .dark ? opacity * 0.22 : opacity * 0.14
        return content.overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color(white: baseWhite, opacity: topOpacity),
                            Color(white: baseWhite, opacity: bottomOpacity),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
                .allowsHitTesting(false)
        }
    }
}

extension View {
    func hairlineSpecularBorder(cornerRadius: CGFloat = DesignRadius.card, opacity: Double = 0.18) -> some View {
        modifier(HairlineSpecularBorder(cornerRadius: cornerRadius, opacity: opacity))
    }
}
