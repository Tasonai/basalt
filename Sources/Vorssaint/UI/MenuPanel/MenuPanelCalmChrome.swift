// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

private struct MenuPanelDensityKey: EnvironmentKey {
    static let defaultValue: PanelDensityMode = .calm
}

extension EnvironmentValues {
    var menuPanelDensity: PanelDensityMode {
        get { self[MenuPanelDensityKey.self] }
        set { self[MenuPanelDensityKey.self] = newValue }
    }
}

/// Compact pill switch toggling `MenuPanelView` between Calm (decluttered) and Pro (full dense metrics).
struct MenuPanelDensitySwitcher: View {
    @Binding var mode: PanelDensityMode
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let strings = OverhaulV3Strings.localized(l10n.language)
        VorssaintSegmentedTabs(
            selection: $mode,
            options: [
                .init(.calm, title: strings.panelDensityCalm),
                .init(.pro, title: strings.panelDensityPro),
            ],
            tone: .brand
        )
    }
}

/// Progressive disclosure wrapper: in Calm mode, secondary notes stay muted/hidden
/// unless the user explicitly switches to Pro mode.
struct CalmSecondaryDetailModifier: ViewModifier {
    @Environment(\.menuPanelDensity) private var density

    func body(content: Content) -> some View {
        if density == .pro {
            content
        }
    }
}

extension View {
    func proOnlyDetail() -> some View {
        modifier(CalmSecondaryDetailModifier())
    }
}
