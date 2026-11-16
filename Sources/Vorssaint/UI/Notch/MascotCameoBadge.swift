// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Tasteful cameo companion badge carrying the Vorssaint Mascot's personality
/// into standalone utilities (Cleaner, Uninstaller, Media, App Updates, Ports).
struct MascotCameoBadge: View {
    var mood: NotchMascotMood = .idle
    var reaction: NotchMascotReaction? = nil
    var tone: SemanticCategoryTone = .brand
    var size: CGFloat = 46
    var interactiveCue: Bool = true

    @State private var cueID = 0
    @State private var currentCue: NotchMascotCue?
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let glowColor = tone.color(scheme: colorScheme, highContrast: colorSchemeContrast == .increased)
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            glowColor.opacity(isHovered ? 0.24 : 0.14),
                            glowColor.opacity(0.02),
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: size * 0.72
                    )
                )
                .frame(width: size * 1.32, height: size * 1.32)

            Circle()
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04))
                .frame(width: size + 8, height: size + 8)
                .overlay(
                    Circle()
                        .strokeBorder(glowColor.opacity(0.28), lineWidth: 1)
                )

            NotchMascotView(
                look: NotchMascotSupport.look(),
                mood: mood,
                size: size,
                idles: true,
                cue: currentCue,
                cueID: cueID,
                reaction: reaction
            )
            .frame(width: size, height: size)
        }
        .scaleEffect(isHovered && !reduceMotion ? 1.04 : 1.0)
        .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.78), value: isHovered)
        .onHover { hovered in
            isHovered = hovered
            if hovered, interactiveCue {
                currentCue = .glance
                cueID &+= 1
            }
        }
        .onTapGesture {
            guard interactiveCue else { return }
            VorssaintHaptics.generic()
            currentCue = .celebrate
            cueID &+= 1
        }
        .accessibilityHidden(true)
    }
}
