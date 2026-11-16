// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Role-based curated starter setups presented in Onboarding Step 2 alongside
/// `FeaturePreset` compatibility.
enum OnboardingRoleProfile: String, CaseIterable, Identifiable {
    case developer
    case creator
    case minimalist
    case power

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .developer: return "chevron.left.forwardslash.chevron.right"
        case .creator: return "sparkles.tv"
        case .minimalist: return "sparkle"
        case .power: return "bolt.shield"
        }
    }

    var tone: SemanticCategoryTone {
        switch self {
        case .developer: return .mouseKeyboard
        case .creator: return .tools
        case .minimalist: return .dynamicIsland
        case .power: return .brand
        }
    }

    func title(in language: AppLanguage) -> String {
        let v3 = OverhaulV3Strings.localized(language)
        switch self {
        case .developer: return v3.onboardingRoleDeveloper
        case .creator: return v3.onboardingRoleCreator
        case .minimalist: return v3.onboardingRoleMinimalist
        case .power: return v3.onboardingRolePower
        }
    }

    func subtitle(in language: AppLanguage) -> String {
        let overhaul = OverhaulStrings.localized(language)
        switch self {
        case .developer: return overhaul.workspaceDeveloperDesc
        case .creator: return overhaul.workspaceCreatorDesc
        case .minimalist: return overhaul.workspaceMinimalistDesc
        case .power: return overhaul.workspaceFullPowerDesc
        }
    }

    var features: Set<AppFeature> {
        switch self {
        case .developer:
            return [
                .switcher,
                .windowLayout,
                .commandBar,
                .clipboardHistory,
                .textSnippets,
                .portManager,
                .killProcess,
                .homebrew,
                .notch,
                .notchAgents,
                .notchMascot,
                .monitorCPU,
                .monitorMemory,
                .monitorNetwork,
                .monitorDisk,
            ]
        case .creator:
            return [
                .screenshot,
                .screenRecorder,
                .screenOCR,
                .colorPicker,
                .mediaTools,
                .shelf,
                .mixer,
                .brightness,
                .extraBrightness,
                .notch,
                .notchLyrics,
                .notchDownloads,
                .notchMascot,
            ]
        case .minimalist:
            return [
                .mixer,
                .keepAwake,
                .monitorCPU,
                .monitorPower,
                .notch,
                .notchMascot,
            ]
        case .power:
            return Set(AppFeature.allCases)
        }
    }

    var recommendedEnableKeys: [String] {
        switch self {
        case .developer:
            return [
                DefaultsKey.switcherEnabled,
                DefaultsKey.windowLayoutShortcutsEnabled,
                DefaultsKey.windowEdgeSnapEnabled,
                DefaultsKey.commandBarShortcutEnabled,
                DefaultsKey.clipboardHistoryEnabled,
                DefaultsKey.textSnippetsEnabled,
                DefaultsKey.notchEnabled,
                DefaultsKey.notchAgentsEnabled,
                DefaultsKey.notchMascotEnabled,
            ]
        case .creator:
            return [
                DefaultsKey.screenshotShortcutEnabled,
                DefaultsKey.recorderShortcutEnabled,
                DefaultsKey.shelfEnabled,
                DefaultsKey.brightnessControlEnabled,
                DefaultsKey.extraBrightnessEnabled,
                DefaultsKey.notchEnabled,
                DefaultsKey.notchLyricsEnabled,
                DefaultsKey.notchDownloadsEnabled,
                DefaultsKey.notchMascotEnabled,
            ]
        case .minimalist:
            return [
                DefaultsKey.notchEnabled,
                DefaultsKey.notchMascotEnabled,
            ]
        case .power:
            return [
                DefaultsKey.switcherEnabled,
                DefaultsKey.windowLayoutShortcutsEnabled,
                DefaultsKey.windowEdgeSnapEnabled,
                DefaultsKey.commandBarShortcutEnabled,
                DefaultsKey.clipboardHistoryEnabled,
                DefaultsKey.textSnippetsEnabled,
                DefaultsKey.shelfEnabled,
                DefaultsKey.brightnessControlEnabled,
                DefaultsKey.extraBrightnessEnabled,
                DefaultsKey.screenshotShortcutEnabled,
                DefaultsKey.recorderShortcutEnabled,
                DefaultsKey.notchEnabled,
                DefaultsKey.notchNotificationsEnabled,
                DefaultsKey.notchAgentsEnabled,
                DefaultsKey.notchLyricsEnabled,
                DefaultsKey.notchDownloadsEnabled,
                DefaultsKey.notchMascotEnabled,
            ]
        }
    }
}

/// Interactive Onboarding 2.0 stage combining a live MacBook notch companion,
/// style and palette customization, and three tactile sandbox demos.
struct OnboardingInteractiveStageView: View {
    var showsBrandHeader: Bool = true
    var showsSandboxCards: Bool = true

    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchMascotStyle) private var mascotStyleRaw = NotchMascotStyle.minimal.rawValue
    @AppStorage(DefaultsKey.notchMascotShape) private var mascotShapeRaw = NotchMascotShape.ball.rawValue
    @AppStorage(DefaultsKey.notchMascotPalette) private var mascotPaletteRaw = NotchMascotPalette.pearl.rawValue

    @State private var mascotMood: NotchMascotMood = .idle
    @State private var mascotCue: NotchMascotCue?
    @State private var mascotCueID = 0
    @State private var mascotReaction: NotchMascotReaction? = .wakeUp
    @State private var isHoveringNotch = false
    @State private var islandExpanded = false
    @State private var commandBarPreviewOpen = false
    @State private var shelfCardDropped = false
    @State private var shelfDropSequence = 0

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var currentLook: NotchMascotLook {
        NotchMascotLook(
            style: NotchMascotStyle(rawValue: mascotStyleRaw) ?? .minimal,
            shape: NotchMascotShape(rawValue: mascotShapeRaw) ?? .ball,
            palette: NotchMascotPalette(rawValue: mascotPaletteRaw) ?? .pearl
        )
    }

    private var paletteAccent: Color {
        Color(cgColor: currentLook.palette.light.cgColor)
    }

    private var v3: OverhaulV3Strings {
        OverhaulV3Strings.localized(l10n.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpace.sm) {
            if showsBrandHeader {
                brandHeader
            }

            liveMacBookStage

            mascotCustomizationStrip

            if showsSandboxCards {
                sandboxCardsRow
                if commandBarPreviewOpen {
                    commandBarMiniPreview
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
                if shelfCardDropped {
                    shelfMiniStrip
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
            }
        }
        .animation(DesignMotion.resolve(DesignMotion.fluidY, reduceMotion: reduceMotion), value: commandBarPreviewOpen)
        .animation(DesignMotion.resolve(DesignMotion.fluidY, reduceMotion: reduceMotion), value: shelfCardDropped)
    }

    // MARK: - Brand Header

    private var brandHeader: some View {
        HStack(spacing: DesignSpace.md) {
            BrandBadge(size: 36)
            VStack(alignment: .leading, spacing: DesignSpace.xxs) {
                Text(AppInfo.name)
                    .font(.system(size: 16, weight: .bold))
                Text(l10n.s.obStepWelcomeBody)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Live Miniature MacBook Notch Stage

    private var liveMacBookStage: some View {
        let islandTone = SemanticCategoryTone.dynamicIsland.color(
            scheme: colorScheme,
            highContrast: colorSchemeContrast == .increased
        )
        return GeometryReader { geo in
            ZStack(alignment: .top) {
                Theme.spaceGradient

                RadialGradient(
                    colors: [
                        paletteAccent.opacity(islandExpanded ? 0.24 : (isHoveringNotch ? 0.16 : 0.08)),
                        islandTone.opacity(islandExpanded ? 0.14 : 0.04),
                        Color.clear,
                    ],
                    center: UnitPoint(x: 0.5, y: 0.18),
                    startRadius: 8,
                    endRadius: geo.size.width * 0.52
                )

                miniMenuBar(width: geo.size.width)

                hardwareNotchSilhouette(islandTone: islandTone)

                VStack {
                    Spacer(minLength: 0)
                    greetingCaptionPill(islandTone: islandTone)
                        .padding(.bottom, DesignSpace.sm)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous))
            .hairlineSpecularBorder(
                cornerRadius: DesignRadius.card,
                opacity: isHoveringNotch || islandExpanded ? 0.30 : 0.18
            )
            .contentShape(RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous))
            .onContinuousHover { phase in
                handleStageHover(phase, size: geo.size)
            }
            .onTapGesture {
                petMascotOnStage()
            }
        }
        .frame(height: 114)
        .animation(DesignMotion.resolve(DesignMotion.fluidX, reduceMotion: reduceMotion), value: islandExpanded)
        .animation(DesignMotion.resolve(DesignMotion.snappy, reduceMotion: reduceMotion), value: isHoveringNotch)
    }

    private func miniMenuBar(width: CGFloat) -> some View {
        HStack(spacing: DesignSpace.sm) {
            HStack(spacing: DesignSpace.xs + 2) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.28))
                    .frame(width: 14, height: 4)
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.20))
                    .frame(width: 24, height: 4)
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 20, height: 4)
            }
            Spacer(minLength: 0)
            HStack(spacing: DesignSpace.xs + 1) {
                Circle()
                    .fill(Color.white.opacity(0.24))
                    .frame(width: 5, height: 5)
                Circle()
                    .fill(Color.white.opacity(0.20))
                    .frame(width: 5, height: 5)
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.26))
                    .frame(width: 14, height: 5)
            }
        }
        .padding(.horizontal, DesignSpace.md)
        .frame(width: width, height: 22)
        .background(Color.white.opacity(0.06))
        .accessibilityHidden(true)
    }

    private func hardwareNotchSilhouette(islandTone: Color) -> some View {
        let notchWidth: CGFloat = islandExpanded ? 248 : 156
        let notchHeight: CGFloat = islandExpanded ? 54 : 36
        return ZStack {
            OnboardingMiniNotchShape(shoulder: 8, bottomRadius: islandExpanded ? 14 : 10)
                .fill(
                    LinearGradient(
                        colors: [Color.black, Color(white: 0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    OnboardingMiniNotchShape(shoulder: 8, bottomRadius: islandExpanded ? 14 : 10)
                        .stroke(
                            Color.white.opacity(islandExpanded || isHoveringNotch ? 0.24 : 0.12),
                            lineWidth: 0.75
                        )
                )
                .shadow(
                    color: (islandExpanded ? islandTone : Color.black).opacity(islandExpanded ? 0.34 : 0.45),
                    radius: islandExpanded ? 12 : 6,
                    x: 0,
                    y: 4
                )

            HStack(spacing: DesignSpace.sm) {
                NotchMascotView(
                    look: currentLook,
                    mood: mascotMood,
                    size: islandExpanded ? 32 : 26,
                    idles: true,
                    cue: mascotCue,
                    cueID: mascotCueID,
                    followsDrag: true,
                    reaction: mascotReaction
                )
                .frame(width: islandExpanded ? 34 : 28, height: islandExpanded ? 34 : 28)

                cameraLensDot

                if islandExpanded {
                    HStack(spacing: DesignSpace.xs + 2) {
                        ZStack {
                            RoundedRectangle(cornerRadius: DesignRadius.iconTile, style: .continuous)
                                .fill(SemanticCategoryTone.sound.badgeColor.opacity(0.24))
                                .frame(width: 24, height: 24)
                            Image(systemName: "music.note")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(SemanticCategoryTone.sound.badgeColor)
                        }
                        OnboardingMiniEqualizerView(
                            tint: paletteAccent,
                            active: islandExpanded,
                            reduceMotion: reduceMotion
                        )
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                } else {
                    Capsule(style: .continuous)
                        .fill(paletteAccent.opacity(isHoveringNotch ? 0.65 : 0.28))
                        .frame(width: 18, height: 4)
                }
            }
            .padding(.horizontal, DesignSpace.md)
            .padding(.top, 2)
        }
        .frame(width: notchWidth, height: notchHeight)
    }

    private var cameraLensDot: some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.14))
                .frame(width: 7, height: 7)
            Circle()
                .fill(Color.cyan.opacity(0.45))
                .frame(width: 2.5, height: 2.5)
                .offset(x: -0.8, y: -0.8)
        }
        .accessibilityHidden(true)
    }

    private func greetingCaptionPill(islandTone: Color) -> some View {
        HStack(spacing: DesignSpace.xs + 2) {
            Image(systemName: isHoveringNotch || islandExpanded ? "sparkles" : "hand.point.up.left")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(isHoveringNotch || islandExpanded ? paletteAccent : .white.opacity(0.76))
            Text(v3.onboardingMascotGreeting)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(isHoveringNotch || islandExpanded ? 0.95 : 0.78))
                .lineLimit(1)
        }
        .padding(.horizontal, DesignSpace.md)
        .padding(.vertical, DesignSpace.xs + 1)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(isHoveringNotch || islandExpanded ? 0.14 : 0.08))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            (isHoveringNotch || islandExpanded ? islandTone : Color.white).opacity(0.22),
                            lineWidth: 0.75
                        )
                )
        )
    }

    // MARK: - Mascot Style & Palette Customizer

    private var mascotCustomizationStrip: some View {
        let mascotStrings = FeatureStrings.notchMascot(l10n.language)
        let overhaul = OverhaulStrings.localized(l10n.language)
        let activeTone = SemanticCategoryTone.dynamicIsland.color(
            scheme: colorScheme,
            highContrast: colorSchemeContrast == .increased
        )

        return HStack(spacing: DesignSpace.md) {
            Text(overhaul.mascotCustomizeTitle)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: DesignSpace.xs)

            HStack(spacing: DesignSpace.xs + 2) {
                ForEach(NotchMascotPalette.allCases) { palette in
                    let selected = palette.rawValue == mascotPaletteRaw
                    Button {
                        mascotPaletteRaw = palette.rawValue
                        VorssaintHaptics.alignment()
                        mascotReaction = .love
                        mascotMood = .love
                        triggerCue(.celebrate)
                    } label: {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(cgColor: palette.light.cgColor),
                                        Color(cgColor: palette.shade.cgColor),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 17, height: 17)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        selected ? activeTone : Color.primary.opacity(0.18),
                                        lineWidth: selected ? 2.0 : 0.75
                                    )
                            )
                    }
                    .buttonStyle(VorssaintScalePressButtonStyle(cornerRadius: 9))
                    .help(mascotStrings.palette(palette))
                    .accessibilityLabel(mascotStrings.palette(palette))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }

            HStack(spacing: DesignSpace.xs) {
                ForEach(NotchMascotStyle.allCases) { style in
                    let active = style.rawValue == mascotStyleRaw
                    Button {
                        mascotStyleRaw = style.rawValue
                        VorssaintHaptics.alignment()
                        mascotReaction = .perk
                        mascotMood = .wink
                        triggerCue(.glance)
                    } label: {
                        Text(mascotStrings.style(style))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(active ? .white : .primary)
                            .padding(.horizontal, DesignSpace.sm + 2)
                            .frame(height: 24)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(active ? activeTone : Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.06))
                            )
                    }
                    .buttonStyle(VorssaintScalePressButtonStyle(cornerRadius: DesignRadius.pill))
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, DesignSpace.md)
        .padding(.vertical, DesignSpace.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignRadius.innerGroup, style: .continuous)
                .fill(DesignSurfaceTier.card.fillColor(for: colorScheme))
        )
        .hairlineSpecularBorder(cornerRadius: DesignRadius.innerGroup, opacity: 0.16)
    }

    // MARK: - 3 Interactive Sandbox Cards

    private var sandboxCardsRow: some View {
        HStack(spacing: DesignSpace.sm) {
            sandboxActionCard(
                title: v3.onboardingTryIsland,
                symbol: "waveform",
                tone: .dynamicIsland,
                isActive: islandExpanded
            ) {
                islandExpanded.toggle()
                VorssaintHaptics.alignment()
                mascotReaction = .perk
                mascotMood = islandExpanded ? .alert : (isHoveringNotch ? .happy : .idle)
                triggerCue(islandExpanded ? .celebrate : .look(nil))
            }

            sandboxActionCard(
                title: v3.onboardingTryCommandBar,
                symbol: "command",
                tone: .mouseKeyboard,
                isActive: commandBarPreviewOpen
            ) {
                commandBarPreviewOpen.toggle()
                VorssaintHaptics.alignment()
                mascotMood = commandBarPreviewOpen ? .searching : (isHoveringNotch ? .happy : .idle)
                triggerCue(commandBarPreviewOpen ? .glance : .look(nil))
            }

            sandboxActionCard(
                title: v3.onboardingTryShelf,
                symbol: "tray.full",
                tone: .clipboardFiles,
                isActive: shelfCardDropped
            ) {
                shelfCardDropped.toggle()
                if shelfCardDropped {
                    shelfDropSequence &+= 1
                }
                VorssaintHaptics.alignment()
                mascotReaction = .celebrate
                mascotMood = shelfCardDropped ? .happy : (isHoveringNotch ? .happy : .idle)
                triggerCue(shelfCardDropped ? .celebrate : .look(nil))
            }
        }
    }

    private func sandboxActionCard(
        title: String,
        symbol: String,
        tone: SemanticCategoryTone,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let tint = tone.color(scheme: colorScheme, highContrast: colorSchemeContrast == .increased)
        return Button(action: action) {
            HStack(spacing: DesignSpace.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: DesignRadius.iconTile, style: .continuous)
                        .fill(isActive ? tint : tint.opacity(colorScheme == .dark ? 0.18 : 0.12))
                        .frame(width: 26, height: 26)
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isActive ? Color.white : tint)
                }

                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isActive {
                    Circle()
                        .fill(tint)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(DesignSpace.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous)
                    .fill(
                        isActive
                            ? tint.opacity(colorScheme == .dark ? 0.18 : 0.11)
                            : DesignSurfaceTier.card.fillColor(for: colorScheme)
                    )
            )
            .hairlineSpecularBorder(
                cornerRadius: DesignRadius.card,
                opacity: isActive ? 0.34 : 0.16
            )
            .contentShape(RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous))
        }
        .buttonStyle(VorssaintScalePressButtonStyle(cornerRadius: DesignRadius.card))
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .animation(DesignMotion.resolve(DesignMotion.snappy, reduceMotion: reduceMotion), value: isActive)
    }

    // MARK: - Inline Mini Command Bar Preview

    private var commandBarMiniPreview: some View {
        let tone = SemanticCategoryTone.mouseKeyboard.color(
            scheme: colorScheme,
            highContrast: colorSchemeContrast == .increased
        )
        let islandTone = SemanticCategoryTone.dynamicIsland.color(
            scheme: colorScheme,
            highContrast: colorSchemeContrast == .increased
        )
        return VStack(alignment: .leading, spacing: DesignSpace.sm) {
            HStack(spacing: DesignSpace.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tone)
                Text(FeatureStrings.commandBar(l10n.language).pageTitle)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Text("2+2*3  ·  @clipboard")
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: DesignSpace.sm) {
                miniCommandBarResultPill(
                    symbol: "equal.square",
                    query: "2+2*3",
                    result: "8",
                    tint: tone
                )
                miniCommandBarResultPill(
                    symbol: "sparkles",
                    query: "@clipboard",
                    result: "AI",
                    tint: islandTone
                )
            }
        }
        .padding(DesignSpace.md)
        .background(
            RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous)
                .fill(DesignSurfaceTier.elevated.fillColor(for: colorScheme))
        )
        .hairlineSpecularBorder(cornerRadius: DesignRadius.card, opacity: 0.22)
    }

    private func miniCommandBarResultPill(
        symbol: String,
        query: String,
        result: String,
        tint: Color
    ) -> some View {
        HStack(spacing: DesignSpace.xs + 2) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(query)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.primary)
            Image(systemName: "arrow.right")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(result)
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(tint)
                .padding(.horizontal, DesignSpace.xs + 2)
                .padding(.vertical, DesignSpace.xxs)
                .background(
                    Capsule(style: .continuous)
                        .fill(tint.opacity(colorScheme == .dark ? 0.20 : 0.13))
                )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignSpace.sm)
        .padding(.vertical, DesignSpace.xs + 2)
        .background(
            RoundedRectangle(cornerRadius: DesignRadius.innerGroup, style: .continuous)
                .fill(DesignSurfaceTier.card.fillColor(for: colorScheme))
        )
    }

    // MARK: - Inline Mini Shelf Strip

    private var shelfMiniStrip: some View {
        let shelfTone = SemanticCategoryTone.clipboardFiles.color(
            scheme: colorScheme,
            highContrast: colorSchemeContrast == .increased
        )
        let toolsTone = SemanticCategoryTone.tools.color(
            scheme: colorScheme,
            highContrast: colorSchemeContrast == .increased
        )
        return HStack(spacing: DesignSpace.md) {
            MascotCameoBadge(
                mood: .happy,
                reaction: .celebrate,
                tone: .clipboardFiles,
                size: 32,
                interactiveCue: true
            )
            .id(shelfDropSequence)

            HStack(spacing: DesignSpace.sm) {
                miniShelfSampleCard(
                    symbol: "doc.richtext.fill",
                    title: "Vorssaint_Brief.pdf",
                    badge: "1.4 MB",
                    tint: shelfTone
                )
                miniShelfSampleCard(
                    symbol: "photo.fill",
                    title: "Mockup_v3.png",
                    badge: "840 KB",
                    tint: toolsTone
                )
            }

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(shelfTone)
        }
        .padding(DesignSpace.md)
        .background(
            RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous)
                .fill(DesignSurfaceTier.elevated.fillColor(for: colorScheme))
        )
        .hairlineSpecularBorder(cornerRadius: DesignRadius.card, opacity: 0.22)
    }

    private func miniShelfSampleCard(
        symbol: String,
        title: String,
        badge: String,
        tint: Color
    ) -> some View {
        HStack(spacing: DesignSpace.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignRadius.iconTile, style: .continuous)
                    .fill(tint.opacity(colorScheme == .dark ? 0.20 : 0.13))
                    .frame(width: 24, height: 24)
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(badge)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignSpace.sm)
        .padding(.vertical, DesignSpace.xs + 2)
        .background(
            RoundedRectangle(cornerRadius: DesignRadius.innerGroup, style: .continuous)
                .fill(DesignSurfaceTier.card.fillColor(for: colorScheme))
        )
    }

    // MARK: - Pointer Hover & Mascot Cues

    private func handleStageHover(_ phase: HoverPhase, size: CGSize) {
        switch phase {
        case .active(let location):
            let wasIdle = !isHoveringNotch
            isHoveringNotch = true
            if wasIdle {
                VorssaintHaptics.alignment()
            }
            let dx = max(-1, min(1, (location.x - size.width * 0.5) / max(1, size.width * 0.34)))
            let dy = max(-1, min(1, (location.y - 22) / max(1, size.height * 0.65)))
            triggerCue(.look(CGPoint(x: dx * 0.14, y: dy * 0.10)))
            if !islandExpanded {
                if abs(dx) < 0.22 && location.y < 52 {
                    mascotMood = .love
                } else if abs(dx) > 0.50 {
                    // Inquisitive head tilt while exploring the wings.
                    mascotMood = .thinking
                } else {
                    mascotMood = .happy
                }
            }
        case .ended:
            isHoveringNotch = false
            triggerCue(.look(nil))
            if !islandExpanded {
                mascotMood = .idle
            }
        }
    }

    private func petMascotOnStage() {
        VorssaintHaptics.alignment()
        mascotReaction = .love
        mascotMood = .love
        triggerCue(.celebrate)
    }

    private func triggerCue(_ cue: NotchMascotCue) {
        mascotCue = cue
        mascotCueID &+= 1
    }
}

// MARK: - Supporting Shapes & Equalizer

private struct OnboardingMiniNotchShape: Shape {
    var shoulder: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(shoulder, bottomRadius) }
        set {
            shoulder = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let s = max(3, min(rect.width * 0.2, shoulder))
        let r = max(3, min(bottomRadius, rect.height * 0.55, (rect.width - s * 2) * 0.5))
        let k: CGFloat = 0.55228475
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: rect.width, y: 0))
        p.addCurve(
            to: CGPoint(x: rect.width - s, y: s),
            control1: CGPoint(x: rect.width - s * k, y: 0),
            control2: CGPoint(x: rect.width - s, y: s * (1 - k))
        )
        p.addLine(to: CGPoint(x: rect.width - s, y: rect.height - r))
        p.addCurve(
            to: CGPoint(x: rect.width - s - r, y: rect.height),
            control1: CGPoint(x: rect.width - s, y: rect.height - r * (1 - k)),
            control2: CGPoint(x: rect.width - s - r * (1 - k), y: rect.height)
        )
        p.addLine(to: CGPoint(x: s + r, y: rect.height))
        p.addCurve(
            to: CGPoint(x: s, y: rect.height - r),
            control1: CGPoint(x: s + r * (1 - k), y: rect.height),
            control2: CGPoint(x: s, y: rect.height - r * (1 - k))
        )
        p.addLine(to: CGPoint(x: s, y: s))
        p.addCurve(
            to: .zero,
            control1: CGPoint(x: s, y: s * (1 - k)),
            control2: CGPoint(x: s * k, y: 0)
        )
        p.closeSubpath()
        return p
    }
}

private struct OnboardingMiniEqualizerView: View {
    let tint: Color
    let active: Bool
    let reduceMotion: Bool

    private static let phases: [Double] = [0.0, 1.3, 2.5, 0.7, 2.0]
    private static let staticHeights: [CGFloat] = [9, 16, 12, 18, 10]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !active || reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<Self.phases.count, id: \.self) { index in
                    let height: CGFloat = reduceMotion
                        ? Self.staticHeights[index]
                        : 6 + 13 * CGFloat((sin(t * 5.2 + Self.phases[index]) + 1) * 0.5)
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint, SemanticCategoryTone.dynamicIsland.badgeColor],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 3, height: height)
                }
            }
            .frame(height: 20, alignment: .center)
        }
        .accessibilityHidden(true)
    }
}
