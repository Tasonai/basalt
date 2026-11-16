// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Standardized scrollable container for every Settings detail page, unifying
/// header typography, 4pt/8pt rhythm, trailing-aligned switches, and `760pt`
/// readable measure.
struct SettingsPageContainer<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title2.bold())
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                content
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(22)
        }
        .toggleStyle(TrailingSwitchToggleStyle())
    }
}

/// Collapsible card container replacing raw `DisclosureGroup` + `Form` rows in Settings.
struct SettingsDisclosureCard<Content: View>: View {
    let title: String
    var symbol: String? = nil
    var badge: String? = nil
    @Binding var isExpanded: Bool
    let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    init(title: String,
         symbol: String? = nil,
         badge: String? = nil,
         isExpanded: Binding<Bool>,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.badge = badge
        _isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        SettingsCard {
            Button {
                if reduceMotion {
                    isExpanded.toggle()
                } else {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                        isExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    if let symbol {
                        let tint = SemanticCategoryPalette.color(
                            forSymbol: symbol,
                            scheme: colorScheme,
                            highContrast: colorSchemeContrast == .increased
                        )
                        Image(systemName: symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tint)
                            .frame(width: 26, height: 26)
                            .background(tint.opacity(colorScheme == .dark ? 0.16 : 0.12),
                                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let badge {
                        Text(badge)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                content
            }
        }
    }
}
