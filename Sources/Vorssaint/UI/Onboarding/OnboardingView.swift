// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// First-run experience, also reachable later through Settings › About.
/// The person chooses what they want first; only then does the app explain and
/// request the permissions that choice actually needs.
enum OnboardingMode {
    case full

    func title(_ strings: Strings) -> String {
        strings.obStepWelcomeTitle
    }
}

enum OnboardingStep {
    case welcome, purpose, permissions, done
}

struct OnboardingView: View {
    var mode: OnboardingMode = .full
    var onFinish: () -> Void

    @ObservedObject private var l10n = L10n.shared
    /// Persisted so the flow resumes where it stopped — macOS relaunches the
    /// app when Screen Recording is granted mid-onboarding.
    @AppStorage(DefaultsKey.onboardingStep) private var index = 0
    @State private var selectedFeatures: Set<AppFeature>
    @State private var selectedPreset: FeaturePreset?
    @State private var selectedRole: OnboardingRoleProfile?
    @State private var activeEnableKeys: [String]
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(mode: OnboardingMode = .full, onFinish: @escaping () -> Void) {
        self.mode = mode
        self.onFinish = onFinish
        let defaults = UserDefaults.standard
        let selectionWasApplied = defaults.bool(forKey: DefaultsKey.hasOnboarded)
            || defaults.integer(forKey: DefaultsKey.onboardingStep) >= 2
        let features = selectionWasApplied
            ? Set(AppFeature.allCases.filter(\.isAvailable))
            : FeaturePreset.essential.features
        _selectedFeatures = State(initialValue: features)
        _selectedPreset = State(initialValue: selectionWasApplied ? nil : .essential)
        _selectedRole = State(initialValue: nil)
        _activeEnableKeys = State(initialValue: selectionWasApplied ? [] : FeaturePreset.essential.enableKeys)
    }

    private var setupPermissions: [AppPermission] {
        let permissions = Set(selectedFeatures.flatMap(\.onboardingPermissions))
        return [.accessibility, .screenRecording].filter { permissions.contains($0) }
    }
    private var steps: [OnboardingStep] {
        [.welcome, .purpose, .permissions, .done]
    }
    private var current: OnboardingStep { steps[min(max(0, index), steps.count - 1)] }

    var body: some View {
        VStack(spacing: 0) {
            // Scrollable so a step taller than the window (the menu bar
            // metrics list outgrew it, issue #176) can never push the
            // navigation bar out of the fixed frame — without a scroll, the
            // footer was clipped away and the flow looked stuck.
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .top)
            }

            Divider()
            navigationBar
        }
        .frame(width: 640, height: 590)
        .background(DesignSurfaceTier.canvas.fillColor(for: colorScheme))
        .onAppear {
            if !steps.indices.contains(index) { index = 0 }
            // Onboarding narrates the permission trip itself; the floating
            // guide card would just double the voice.
            PermissionGuideOverlay.suppressed = true
        }
        .onDisappear {
            PermissionGuideOverlay.suppressed = false
        }
    }

    @ViewBuilder
    private var content: some View {
        switch current {
        case .welcome:
            WelcomeStep()
        case .purpose:
            PurposeStep(
                selectedFeatures: $selectedFeatures,
                selectedPreset: $selectedPreset,
                selectedRole: $selectedRole,
                activeEnableKeys: $activeEnableKeys
            )
        case .permissions:
            SelectedPermissionsStep(features: selectedFeatures, permissions: setupPermissions)
        case .done:
            DoneStep()
        }
    }

    private var navigationBar: some View {
        let activeTint = SemanticCategoryTone.brand.color(
            scheme: colorScheme,
            highContrast: colorSchemeContrast == .increased
        )
        return HStack(spacing: DesignSpace.md) {
            VorssaintActionChip(
                title: l10n.s.obBack,
                symbol: "chevron.left",
                tone: .brand
            ) {
                withAnimation(DesignMotion.resolve(DesignMotion.fluidX, reduceMotion: reduceMotion)) {
                    index = max(0, index - 1)
                }
            }
            .disabled(index == 0)

            Spacer(minLength: DesignSpace.sm)

            HStack(spacing: DesignSpace.sm) {
                ForEach(steps.indices, id: \.self) { i in
                    Capsule(style: .continuous)
                        .fill(i == index ? activeTint : Color.primary.opacity(0.16))
                        .frame(width: i == index ? 20 : 7, height: 7)
                        .animation(DesignMotion.resolve(DesignMotion.fluidX, reduceMotion: reduceMotion), value: index)
                }
            }

            Spacer(minLength: DesignSpace.sm)

            VorssaintActionChip(
                title: primaryButtonTitle,
                symbol: index >= steps.count - 1 ? "checkmark" : "arrow.right",
                tone: .brand,
                prominent: true
            ) {
                if index >= steps.count - 1 {
                    index = 0
                    onFinish()
                } else {
                    if current == .purpose {
                        let enableKeys = selectedRole?.recommendedEnableKeys
                            ?? selectedPreset?.enableKeys
                            ?? activeEnableKeys
                        FeatureRuntime.shared.replaceAvailable(
                            with: selectedFeatures,
                            enabling: enableKeys
                        )
                    }
                    withAnimation(DesignMotion.resolve(DesignMotion.fluidX, reduceMotion: reduceMotion)) {
                        index += 1
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, DesignSpace.lg)
        .padding(.vertical, DesignSpace.md)
    }

    private var primaryButtonTitle: String {
        if index >= steps.count - 1 { return l10n.s.obStart }
        return l10n.s.obContinue
    }
}

// MARK: - Step 1: welcome & interactive stage

private struct WelcomeStep: View {
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpace.md) {
            OnboardingInteractiveStageView(showsBrandHeader: true, showsSandboxCards: true)

            HStack(spacing: DesignSpace.md) {
                Picker(l10n.s.obLanguageLabel, selection: $l10n.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                // A menu (not segmented): with fifteen languages a segmented
                // control would overflow, and several names use their own script.
                .pickerStyle(.menu)
            }
            .padding(.horizontal, DesignSpace.md)
            .padding(.vertical, DesignSpace.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignRadius.innerGroup, style: .continuous)
                    .fill(DesignSurfaceTier.card.fillColor(for: colorScheme))
            )
            .hairlineSpecularBorder(cornerRadius: DesignRadius.innerGroup, opacity: 0.14)

            VStack(spacing: DesignSpace.sm) {
                featureRow(
                    icon: "bolt.fill",
                    tone: .brand,
                    title: l10n.s.obWelcomeBullet1Title,
                    text: l10n.s.obWelcomeBullet1Body
                )
                featureRow(
                    icon: "gauge.with.dots.needle.50percent",
                    tone: .monitor,
                    title: l10n.s.obWelcomeBullet2Title,
                    text: l10n.s.obWelcomeBullet2Body
                )
                featureRow(
                    icon: "rectangle.on.rectangle",
                    tone: .windowsDock,
                    title: l10n.s.obWelcomeBullet3Title,
                    text: l10n.s.obWelcomeBullet3Body
                )
            }
        }
        .padding(.horizontal, DesignSpace.xxl)
        .padding(.vertical, DesignSpace.lg)
    }

    private func featureRow(
        icon: String,
        tone: SemanticCategoryTone,
        title: String,
        text: String
    ) -> some View {
        let tint = tone.color(scheme: colorScheme, highContrast: colorSchemeContrast == .increased)
        return HStack(alignment: .top, spacing: DesignSpace.md) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignRadius.iconTile, style: .continuous)
                    .fill(tint.opacity(colorScheme == .dark ? 0.18 : 0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: DesignSpace.xxs) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(text)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignSpace.md)
        .padding(.vertical, DesignSpace.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous)
                .fill(DesignSurfaceTier.card.fillColor(for: colorScheme))
        )
        .hairlineSpecularBorder(cornerRadius: DesignRadius.card, opacity: 0.14)
    }
}

// MARK: - Purpose step

/// Role profiles and presets offer instant starting setups, while the
/// collapsible catalog below allows per-feature customization.
private struct PurposeStep: View {
    @ObservedObject private var l10n = L10n.shared
    @Binding var selectedFeatures: Set<AppFeature>
    @Binding var selectedPreset: FeaturePreset?
    @Binding var selectedRole: OnboardingRoleProfile?
    @Binding var activeEnableKeys: [String]
    @State private var hoveredPreset: FeaturePreset?
    @State private var hoveredRole: OnboardingRoleProfile?
    @State private var hoveredFeature: AppFeature?
    @State private var showingCustomCatalog = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hub: FeatureHubStrings { FeatureStrings.hub(l10n.language) }
    private var v3: OverhaulV3Strings { OverhaulV3Strings.localized(l10n.language) }

    var body: some View {
        VStack(spacing: DesignSpace.lg) {
            StepHeader(
                icon: "sparkles.rectangle.stack",
                title: l10n.s.obPurposeTitle,
                subtitle: l10n.s.obPurposeBody
            )

            VStack(alignment: .leading, spacing: DesignSpace.sm) {
                Text(v3.onboardingRoleTitle)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.4)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: DesignSpace.sm),
                        GridItem(.flexible(), spacing: DesignSpace.sm),
                    ],
                    spacing: DesignSpace.sm
                ) {
                    ForEach(OnboardingRoleProfile.allCases) { profile in
                        roleCard(profile)
                    }
                }
            }
            .padding(.horizontal, DesignSpace.xxl)

            VStack(alignment: .leading, spacing: DesignSpace.sm) {
                Text(hub.presetsTitle)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.4)

                HStack(spacing: DesignSpace.sm) {
                    ForEach(FeaturePreset.allCases) { preset in
                        presetPill(preset)
                    }
                }
            }
            .padding(.horizontal, DesignSpace.xxl)

            VStack(alignment: .leading, spacing: 0) {
                DisclosureGroup(isExpanded: $showingCustomCatalog) {
                    // Eager, like the Features hub (#2311, #2642): a lazy stack nested
                    // here re-estimated the cards below the fold on every scroll step
                    // and re-anchored the viewport until the app hung.
                    VStack(spacing: DesignSpace.md) {
                        ForEach(FeatureGroup.allCases, id: \.self) { group in
                            VStack(alignment: .leading, spacing: DesignSpace.xs + 2) {
                                Text(groupTitle(group))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(AppFeature.features(in: group), id: \.self) { feature in
                                    featureCard(feature)
                                }
                            }
                        }
                    }
                    .padding(.top, DesignSpace.md)
                } label: {
                    HStack(spacing: DesignSpace.sm) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(
                                SemanticCategoryTone.brand.color(
                                    scheme: colorScheme,
                                    highContrast: colorSchemeContrast == .increased
                                )
                            )
                        Text(hub.tabFeatures)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.primary)
                        Spacer(minLength: DesignSpace.sm)
                        Text(
                            String(
                                format: hub.activeCountFormat,
                                locale: l10n.language.formattingLocale(),
                                selectedFeatures.count,
                                FeatureRuntime.shared.installableCount
                            )
                        )
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, DesignSpace.xs)
                }
            }
            .padding(DesignSpace.md)
            .background(
                RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous)
                    .fill(DesignSurfaceTier.card.fillColor(for: colorScheme))
            )
            .hairlineSpecularBorder(cornerRadius: DesignRadius.card, opacity: 0.16)
            .padding(.horizontal, DesignSpace.xxl)
            .animation(DesignMotion.resolve(DesignMotion.snappy, reduceMotion: reduceMotion), value: showingCustomCatalog)

            Text(l10n.s.obPurposeSkip)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignSpace.section)
                .padding(.bottom, DesignSpace.md)

            Spacer(minLength: 0)
        }
    }

    private func name(_ preset: FeaturePreset) -> String {
        switch preset {
        case .essential: return hub.presetEssentialName
        case .windows: return hub.presetWindowsName
        case .battery: return hub.presetBatteryName
        }
    }

    private func caption(_ preset: FeaturePreset) -> String {
        switch preset {
        case .essential: return hub.presetEssentialDesc
        case .windows: return hub.presetWindowsDesc
        case .battery: return hub.presetBatteryDesc
        }
    }

    private func roleCard(_ profile: OnboardingRoleProfile) -> some View {
        let selected = selectedRole == profile
        let hovered = hoveredRole == profile
        let accent = profile.tone.color(
            scheme: colorScheme,
            highContrast: colorSchemeContrast == .increased
        )
        return Button {
            selectedRole = profile
            selectedPreset = nil
            selectedFeatures = profile.features
            activeEnableKeys = profile.recommendedEnableKeys
            VorssaintHaptics.alignment()
        } label: {
            HStack(alignment: .top, spacing: DesignSpace.sm + 2) {
                Image(systemName: profile.symbolName)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: DesignRadius.iconTile, style: .continuous)
                            .fill(accent.gradient)
                    )
                VStack(alignment: .leading, spacing: DesignSpace.xxs) {
                    Text(profile.title(in: l10n.language))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(profile.subtitle(in: l10n.language))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(accent)
                }
            }
            .padding(DesignSpace.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous)
                    .fill(
                        selected
                            ? accent.opacity(colorScheme == .dark ? 0.16 : 0.11)
                            : Color.primary.opacity(hovered ? 0.075 : 0.045)
                    )
            )
            .hairlineSpecularBorder(cornerRadius: DesignRadius.card, opacity: selected ? 0.34 : 0.16)
            .contentShape(RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous))
        }
        .buttonStyle(VorssaintScalePressButtonStyle(cornerRadius: DesignRadius.card))
        .onHover { hovering in
            if hovering {
                hoveredRole = profile
            } else if hoveredRole == profile {
                hoveredRole = nil
            }
        }
        .accessibilityLabel("\(profile.title(in: l10n.language)). \(profile.subtitle(in: l10n.language))")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(DesignMotion.resolve(DesignMotion.snappy, reduceMotion: reduceMotion), value: selected)
    }

    private func presetPill(_ preset: FeaturePreset) -> some View {
        let selected = selectedPreset == preset
        let isHovered = hoveredPreset == preset
        let accent = SemanticCategoryTone.brand.color(
            scheme: colorScheme,
            highContrast: colorSchemeContrast == .increased
        )
        return Button {
            selectedPreset = preset
            selectedRole = nil
            selectedFeatures = preset.features
            activeEnableKeys = preset.enableKeys
            VorssaintHaptics.alignment()
        } label: {
            HStack(spacing: DesignSpace.sm) {
                Image(systemName: preset.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? accent : .secondary)
                    .accessibilityHidden(true)
                Text(name(preset))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? accent : Color.secondary.opacity(isHovered ? 0.65 : 0.35))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DesignSpace.md)
            .padding(.vertical, DesignSpace.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignRadius.pill, style: .continuous)
                    .fill(
                        selected
                            ? accent.opacity(isHovered ? 0.16 : 0.12)
                            : Color.primary.opacity(isHovered ? 0.08 : 0.045)
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: DesignRadius.pill, style: .continuous)
                    .strokeBorder(
                        selected ? accent.opacity(0.42) : Color.primary.opacity(isHovered ? 0.14 : 0.08),
                        lineWidth: 0.75
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: DesignRadius.pill, style: .continuous))
        }
        .buttonStyle(VorssaintScalePressButtonStyle(cornerRadius: DesignRadius.pill))
        .help(caption(preset))
        .onHover { hovering in
            if hovering {
                hoveredPreset = preset
            } else if hoveredPreset == preset {
                hoveredPreset = nil
            }
        }
        .accessibilityLabel("\(name(preset)). \(caption(preset))")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(DesignMotion.resolve(DesignMotion.snappy, reduceMotion: reduceMotion), value: selectedPreset)
    }

    private func featureCard(_ feature: AppFeature) -> some View {
        let selected = selectedFeatures.contains(feature)
        let isHovered = hoveredFeature == feature
        // The picker writes availability through the same runtime gate as the
        // hub, so a feature this Mac cannot run would silently stay off after
        // being ticked here. It is shown and refused instead, exactly as the
        // hub row does it.
        let blocked = feature.installBlockedReason
        let tone = SemanticCategoryPalette.tone(for: feature)
        let tint = tone.color(scheme: colorScheme, highContrast: colorSchemeContrast == .increased)
        let binding = Binding<Bool>(
            get: { selectedFeatures.contains(feature) },
            set: { isOn in
                selectedPreset = nil
                selectedRole = nil
                if isOn {
                    selectedFeatures.formUnion(feature.initialInstallGroup)
                } else {
                    selectedFeatures.remove(feature)
                    if feature == .notch {
                        selectedFeatures.subtract(AppFeature.dynamicIslandExtensions)
                    }
                }
            }
        )
        let card = Toggle(isOn: binding) {
            HStack(spacing: DesignSpace.sm + 2) {
                RoundedRectangle(cornerRadius: DesignRadius.iconTile, style: .continuous)
                    .fill(selected ? tint : Color.secondary.opacity(0.16))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: feature.symbolName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(selected ? Color.white : Color.secondary)
                            .accessibilityHidden(true)
                    }
                VStack(alignment: .leading, spacing: DesignSpace.xxs) {
                    Text(feature.hubTitle(l10n.s, hub: hub))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(feature.hubDescription(hub))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: DesignSpace.xs)
            }
        }
        .toggleStyle(VorssaintCheckPillStyle(tone: tone))
        .padding(.horizontal, DesignSpace.md)
        .padding(.vertical, DesignSpace.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignRadius.innerGroup, style: .continuous)
                .fill(selected
                      ? tint.opacity(isHovered ? 0.13 : 0.09)
                      : Color.primary.opacity(isHovered ? 0.065 : 0.035))
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignRadius.innerGroup, style: .continuous)
                .strokeBorder(selected
                              ? tint.opacity(isHovered ? 0.35 : 0.18)
                              : Color.primary.opacity(isHovered ? 0.12 : 0),
                              lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: DesignRadius.innerGroup, style: .continuous))
        .onHover { hovering in
            guard blocked == nil else { return }
            if hovering {
                hoveredFeature = feature
            } else if hoveredFeature == feature {
                hoveredFeature = nil
            }
        }
        .disabled(blocked != nil)
        .opacity(blocked == nil ? 1 : 0.4)
        .saturation(blocked == nil ? 1 : 0)
        .accessibilityLabel("\(feature.hubTitle(l10n.s, hub: hub)). \(feature.hubDescription(hub))"
                            + (blocked.map { ". \($0)" } ?? ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
        // .help() never fires on a disabled control, so the tooltip sits on a
        // wrapper outside it, the same way the Features hub row does it.
        return HStack(spacing: 0) { card }.help(blocked ?? "")
    }

    private func groupTitle(_ group: FeatureGroup) -> String {
        switch group {
        case .windowsDock: return hub.groupWindowsDock
        case .mouseKeyboard: return hub.groupMouseKeyboard
        case .clipboardFiles: return hub.groupClipboardFiles
        case .sound: return hub.groupSound
        case .energyDisplay: return hub.groupEnergyDisplay
        case .tools: return hub.groupTools
        case .dynamicIsland: return FeatureStrings.notch(l10n.language).title
        case .monitor: return hub.groupMonitor
        }
    }
}

private struct SelectedPermissionsStep: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var showingOtherPermissions = false
    let features: Set<AppFeature>
    let permissions: [AppPermission]

    @Environment(\.colorScheme) private var colorScheme

    private var hub: FeatureHubStrings { FeatureStrings.hub(l10n.language) }
    private var otherPermissions: [AppPermission] {
        AppPermission.allCases.filter { !permissions.contains($0) }
    }

    var body: some View {
        VStack(spacing: DesignSpace.lg) {
            StepHeader(
                icon: "key.horizontal.fill",
                title: hub.tabPermissions,
                subtitle: hub.permissionsIntro
            )

            VStack(alignment: .leading, spacing: DesignSpace.md) {
                Text(hub.onboardingSelectedPermissionsTitle)
                    .font(.headline)

                if permissions.isEmpty {
                    Label(
                        hub.onboardingNoSelectedPermissions,
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(permissions.enumerated()), id: \.offset) { index, permission in
                            if index > 0 { Divider().padding(.vertical, DesignSpace.md) }
                            VStack(alignment: .leading, spacing: DesignSpace.sm) {
                                PermissionRow(
                                    kind: permission == .accessibility
                                        ? .accessibility : .screenRecording
                                )
                                Text(permission.explainer(hub))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(
                                    String(
                                        format: hub.usedByFormat,
                                        locale: l10n.language.formattingLocale(),
                                        featureNames(for: permission)
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .padding(DesignSpace.lg)
            .background(
                RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous)
                    .fill(DesignSurfaceTier.card.fillColor(for: colorScheme))
            )
            .hairlineSpecularBorder(cornerRadius: DesignRadius.card, opacity: 0.18)
            .padding(.horizontal, DesignSpace.xxl)
            .animation(.easeOut(duration: 0.16), value: showingOtherPermissions)

            DisclosureGroup(isExpanded: $showingOtherPermissions) {
                VStack(alignment: .leading, spacing: 14) {
                    PermissionsPortalSections(
                        hub: hub,
                        visiblePermissions: otherPermissions
                    )
                }
                .padding(.top, DesignSpace.md)
            } label: {
                VStack(alignment: .leading, spacing: DesignSpace.xxs) {
                    Text(hub.onboardingOtherPermissionsTitle)
                        .font(.headline)
                    Text(hub.onboardingOtherPermissionsCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(DesignSpace.lg)
            .background(
                RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous)
                    .fill(DesignSurfaceTier.card.fillColor(for: colorScheme))
            )
            .hairlineSpecularBorder(cornerRadius: DesignRadius.card, opacity: 0.18)
            .padding(.horizontal, DesignSpace.xxl)
            .animation(.easeOut(duration: 0.16), value: showingOtherPermissions)

            Text(l10n.s.permissionRestartNote)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignSpace.section)

            Spacer(minLength: 0)
        }
    }

    private func featureNames(for permission: AppPermission) -> String {
        features
            .filter { $0.onboardingPermissions.contains(permission) }
            .map { $0.hubTitle(l10n.s, hub: hub) }
            // Localized: a plain sort orders by Unicode scalar, which throws
            // every accented name past Z. On the first screen someone sees,
            // in a language with accents, that reads as a list in no order.
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .joined(separator: ", ")
    }
}

// MARK: - Done & interactive sandbox

private struct DoneStep: View {
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let overhaul = OverhaulStrings.localized(l10n.language)
        return VStack(spacing: DesignSpace.lg) {
            VStack(spacing: DesignSpace.sm) {
                BrandBadge(size: 44)
                Text(l10n.s.obStepDoneTitle)
                    .font(.system(size: 21, weight: .bold))
                Text(l10n.s.obStepDoneBody)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, DesignSpace.lg)

            VStack(alignment: .leading, spacing: DesignSpace.sm) {
                Text(overhaul.sandboxTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                OnboardingInteractiveStageView(showsBrandHeader: false, showsSandboxCards: true)
            }
            .padding(.horizontal, DesignSpace.xxl)

            HStack(spacing: DesignSpace.md) {
                Image(systemName: "menubar.arrow.up.rectangle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(l10n.s.obDoneHint)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(DesignSpace.md)
            .background(
                RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous)
                    .fill(DesignSurfaceTier.card.fillColor(for: colorScheme))
            )
            .hairlineSpecularBorder(cornerRadius: DesignRadius.card, opacity: 0.14)
            .padding(.horizontal, DesignSpace.xxl)
            .padding(.bottom, DesignSpace.md)

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Shared header

private struct StepHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: DesignSpace.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous)
                    .fill(Theme.spaceGradient)
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text(title)
                .font(.system(size: 18, weight: .bold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DesignSpace.section)
        }
        .padding(.top, DesignSpace.lg)
    }
}
