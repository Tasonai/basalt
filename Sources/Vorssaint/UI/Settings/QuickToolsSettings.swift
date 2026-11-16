// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct QuickToolsSettings: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var micMute = MicMuteService.shared
    @ObservedObject private var quickToggles = QuickTogglesService.shared
    @ObservedObject private var launcher = QuickLauncherService.shared
    @ObservedObject private var cameraPreview = CameraPreviewService.shared
    @ObservedObject private var scratchpad = ScratchpadService.shared
    @ObservedObject private var brightness = BrightnessService.shared
    @AppStorage(DefaultsKey.quickLauncherShortcutEnabled) private var launcherShortcutEnabled = true
    @AppStorage(DefaultsKey.micMuteShortcutEnabled) private var micShortcutEnabled = false
    @AppStorage(DefaultsKey.quitAppsShortcutEnabled) private var quitAllShortcutEnabled = false
    @AppStorage(DefaultsKey.quitAppsExceptFrontShortcutEnabled) private var quitOthersShortcutEnabled = false
    @AppStorage(DefaultsKey.cameraPreviewShortcutEnabled) private var cameraShortcutEnabled = false
    @AppStorage(DefaultsKey.scratchpadShortcutEnabled) private var scratchpadShortcutEnabled = false
    @AppStorage(DefaultsKey.scratchpadRetention) private var scratchpadRetention = ScratchpadRetention.never.rawValue
    @AppStorage(DefaultsKey.scratchpadCloseOnClickOutside) private var scratchpadCloseOnClickOutside = true
    @AppStorage(DefaultsKey.scratchpadBackgroundOpacity) private var scratchpadBackgroundOpacity = 0.0
    @AppStorage(DefaultsKey.scratchpadTextSize) private var scratchpadTextSize = ScratchpadSupport.defaultTextSize
    @AppStorage(DefaultsKey.micMuteMenuBarIndicator) private var micMenuBarIndicator = false
    @AppStorage(DefaultsKey.cleaningModeKeepScreenVisible) private var cleaningModeKeepScreenVisible = false

    var body: some View {
        SettingsPageContainer(title: l10n.s.quickToolsTab) {
            if AppFeature.quickLauncher.isAvailable {
                quickLauncherCard
                    .settingsSectionAnchor(.quickLauncher, cornerRadius: 16)
            }

            if AppFeature.quickToggles.isAvailable {
                quickTogglesCard
                    .settingsSectionAnchor(.quickToggles, cornerRadius: 16)
                    .onAppear { brightness.refreshKeyboardLight() }
            }

            if AppFeature.quitApps.isAvailable {
                quitAppsCard
                    .settingsSectionAnchor(.quitApps, cornerRadius: 16)
            }

            if AppFeature.micMute.isAvailable {
                micMuteCard
                    .settingsSectionAnchor(.micMute, cornerRadius: 16)
            }

            if AppFeature.cameraPreview.isAvailable {
                cameraPreviewCard
                    .settingsSectionAnchor(.cameraPreview, cornerRadius: 16)
            }

            if AppFeature.wallpaper.isAvailable {
                wallpaperCard
                    .settingsSectionAnchor(.wallpaper, cornerRadius: 16)
            }

            if AppFeature.scratchpad.isAvailable {
                scratchpadCard
                    .settingsSectionAnchor(.scratchpad, cornerRadius: 16)
            }

            if AppFeature.cleaningMode.isAvailable {
                cleaningModeCard
                    .settingsSectionAnchor(.cleaningMode, cornerRadius: 16)
            }
        }
    }

    private var quickLauncherCard: some View {
        SettingsCard(title: l10n.s.launcherName) {
            SettingsRow(symbol: "square.grid.2x2", title: l10n.s.launcherName,
                        caption: l10n.s.launcherCaption) {
                Button {
                    QuickLauncherService.shared.show()
                } label: {
                    Label(l10n.s.launcherOpenNow, systemImage: "square.grid.2x2")
                }
            }
            Text(l10n.s.launcherEditHint)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, settingsRowTextInset)
            Divider()
            SettingsRow(symbol: "keyboard", title: l10n.s.quickToolShortcutToggle) {
                Toggle(l10n.s.quickToolShortcutToggle, isOn: $launcherShortcutEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: launcherShortcutEnabled) { _, _ in
                        QuickLauncherService.shared.syncWithPreferences()
                    }
            }
            ShortcutPreferenceRow(role: .quickLauncher,
                                  isEnabled: launcherShortcutEnabled) {
                QuickLauncherService.shared.syncWithPreferences()
            }
            .padding(.leading, settingsRowTextInset)
            if launcherShortcutEnabled, launcher.shortcutRegistrationFailed {
                Text(l10n.s.shortcutUnavailable)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.leading, settingsRowTextInset)
            }
        }
    }

    private var quickTogglesCard: some View {
        let qtStrings = FeatureStrings.quickToggles(l10n.language)
        return SettingsCard(title: qtStrings.pageTitle) {
            SettingsRow(symbol: colorScheme == .dark ? "sun.max.fill" : "moon.fill",
                        title: colorScheme == .dark ? qtStrings.darkModeToLight : qtStrings.darkModeToDark,
                        caption: qtStrings.panelCaption) {
                Button {
                    QuickTogglesService.shared.toggleDarkMode()
                } label: {
                    Label(colorScheme == .dark ? qtStrings.darkModeToLight : qtStrings.darkModeToDark,
                          systemImage: colorScheme == .dark ? "sun.max.fill" : "moon.fill")
                }
            }
            if brightness.keyboardLightEnabled != nil {
                Divider()
                SettingsRow(symbol: "keyboard",
                            title: FeatureStrings.brightness(l10n.language).keyboardLight) {
                    Toggle(FeatureStrings.brightness(l10n.language).keyboardLight, isOn: Binding(
                        get: { brightness.keyboardLightEnabled ?? false },
                        set: { brightness.setKeyboardLightEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                HStack(spacing: 8) {
                    Slider(value: Binding(
                        get: { Double(brightness.keyboardLightLevel ?? 0) },
                        set: { brightness.setKeyboardLightLevel(Float($0)) }
                    ), in: 0...1, onEditingChanged: brightness.keyboardLightDragChanged)
                    .accessibilityLabel(
                        FeatureStrings.brightness(l10n.language).keyboardLight)
                    Text("\(Int(((brightness.keyboardLightLevel ?? 0) * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
                .padding(.leading, settingsRowTextInset)
            }
            Divider()
            DiskExclusionsList()
        }
    }

    private var quitAppsCard: some View {
        let qtStrings = FeatureStrings.quickToggles(l10n.language)
        return SettingsCard(title: l10n.s.quitAppsName) {
            SettingsRow(symbol: "xmark.app", title: qtStrings.quitAllTitle,
                        caption: l10n.s.quitAppsCaption) {
                Button {
                    QuickTogglesService.shared.showQuitApps()
                } label: {
                    Label(qtStrings.quitAllTitle, systemImage: "xmark.app")
                }
            }
            Divider()
            QuitAllExceptionsList()
            Divider()
            SettingsRow(symbol: "keyboard",
                        title: "\(l10n.s.quickToolShortcutToggle): \(qtStrings.quitAllTitle)") {
                Toggle("\(l10n.s.quickToolShortcutToggle): \(qtStrings.quitAllTitle)",
                       isOn: $quitAllShortcutEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: quitAllShortcutEnabled) { _, _ in
                        QuickTogglesService.shared.syncWithPreferences()
                    }
            }
            ShortcutPreferenceRow(role: .quitAll,
                                  isEnabled: quitAllShortcutEnabled) {
                QuickTogglesService.shared.syncWithPreferences()
            }
            .padding(.leading, settingsRowTextInset)
            if quitAllShortcutEnabled, quickToggles.shortcutRegistrationFailed {
                Text(l10n.s.shortcutUnavailable)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.leading, settingsRowTextInset)
            }
            Divider()
            SettingsRow(symbol: "keyboard",
                        title: "\(l10n.s.quickToolShortcutToggle): \(qtStrings.quitOthersTitle)") {
                Toggle("\(l10n.s.quickToolShortcutToggle): \(qtStrings.quitOthersTitle)",
                       isOn: $quitOthersShortcutEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: quitOthersShortcutEnabled) { _, _ in
                        QuickTogglesService.shared.syncWithPreferences()
                    }
            }
            ShortcutPreferenceRow(role: .quitAllExceptFront,
                                  isEnabled: quitOthersShortcutEnabled) {
                QuickTogglesService.shared.syncWithPreferences()
            }
            .padding(.leading, settingsRowTextInset)
            if quitOthersShortcutEnabled, quickToggles.othersShortcutRegistrationFailed {
                Text(l10n.s.shortcutUnavailable)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.leading, settingsRowTextInset)
            }
        }
    }

    private var micMuteCard: some View {
        SettingsCard(title: l10n.s.micMuteName) {
            SettingsRow(symbol: micMute.isMuted ? "mic.slash.fill" : "mic",
                        title: micMute.isMuted ? l10n.s.micUnmuteName : l10n.s.micMuteName,
                        caption: l10n.s.micMuteCaption) {
                Button {
                    MicMuteService.shared.toggle()
                } label: {
                    Label(micMute.isMuted ? l10n.s.micUnmuteName : l10n.s.micMuteName,
                          systemImage: micMute.isMuted ? "mic.slash.fill" : "mic")
                }
            }
            if micMute.isMuted {
                Label(l10n.s.micMutedHUD, systemImage: "mic.slash.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.leading, settingsRowTextInset)
            }
            Divider()
            SettingsRow(symbol: "mic.circle", title: l10n.s.micMuteMenuBarToggle,
                        caption: l10n.s.micMuteMenuBarCaption) {
                Toggle(l10n.s.micMuteMenuBarToggle, isOn: $micMenuBarIndicator)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            Divider()
            SettingsRow(symbol: "keyboard", title: l10n.s.quickToolShortcutToggle) {
                Toggle(l10n.s.quickToolShortcutToggle, isOn: $micShortcutEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: micShortcutEnabled) { _, _ in
                        MicMuteService.shared.syncWithPreferences()
                    }
            }
            ShortcutPreferenceRow(role: .micMute,
                                  isEnabled: micShortcutEnabled) {
                MicMuteService.shared.syncWithPreferences()
            }
            .padding(.leading, settingsRowTextInset)
            if micShortcutEnabled, micMute.shortcutRegistrationFailed {
                Text(l10n.s.shortcutUnavailable)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.leading, settingsRowTextInset)
            }
        }
    }

    private var cameraPreviewCard: some View {
        let camStrings = FeatureStrings.cameraPreview(l10n.language)
        return SettingsCard(title: camStrings.pageTitle) {
            SettingsRow(symbol: "web.camera", title: camStrings.pageTitle,
                        caption: camStrings.panelCaption) {
                Button {
                    CameraPreviewService.shared.show()
                } label: {
                    Label(camStrings.openButton, systemImage: "web.camera")
                }
            }
            Divider()
            SettingsRow(symbol: "keyboard", title: l10n.s.quickToolShortcutToggle) {
                Toggle(l10n.s.quickToolShortcutToggle, isOn: $cameraShortcutEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: cameraShortcutEnabled) { _, _ in
                        CameraPreviewService.shared.syncWithPreferences()
                    }
            }
            ShortcutPreferenceRow(role: .cameraPreview,
                                  isEnabled: cameraShortcutEnabled) {
                CameraPreviewService.shared.syncWithPreferences()
            }
            .padding(.leading, settingsRowTextInset)
            if cameraShortcutEnabled, cameraPreview.shortcutRegistrationFailed {
                Text(l10n.s.shortcutUnavailable)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.leading, settingsRowTextInset)
            }
            if permissions.camera == .denied {
                Divider()
                CameraPermissionRow()
            }
        }
    }

    private var wallpaperCard: some View {
        let wpStrings = FeatureStrings.wallpaper(l10n.language)
        return SettingsCard(title: wpStrings.pageTitle) {
            SettingsRow(symbol: "photo.on.rectangle.angled", title: wpStrings.applyAllDisplays) {
                Toggle(wpStrings.applyAllDisplays, isOn: Binding(
                    get: { WallpaperService.shared.applyAllDisplays },
                    set: { WallpaperService.shared.applyAllDisplays = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            Divider()
            Button {
                WallpaperService.shared.openSystemWallpaperSettings()
            } label: {
                Label(wpStrings.openSystemSettings, systemImage: "gearshape")
            }
        }
    }

    private var scratchpadCard: some View {
        let padStrings = FeatureStrings.scratchpad(l10n.language)
        return SettingsCard(title: padStrings.pageTitle) {
            SettingsRow(symbol: "note.text", title: padStrings.pageTitle,
                        caption: padStrings.panelCaption) {
                Button {
                    ScratchpadService.shared.show()
                } label: {
                    Label(padStrings.openButton, systemImage: "note.text")
                }
            }
            Divider()
            SettingsRow(symbol: "clock.arrow.circlepath", title: padStrings.retentionTitle,
                        caption: padStrings.retentionCaption) {
                Picker(padStrings.retentionTitle, selection: $scratchpadRetention) {
                    Text(padStrings.retentionNever)
                        .tag(ScratchpadRetention.never.rawValue)
                    Text(padStrings.retentionDay)
                        .tag(ScratchpadRetention.day.rawValue)
                    Text(padStrings.retentionWeek)
                        .tag(ScratchpadRetention.week.rawValue)
                    Text(padStrings.retentionMonth)
                        .tag(ScratchpadRetention.month.rawValue)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
            Divider()
            SettingsRow(symbol: "cursorarrow.click", title: padStrings.closeOnClickOutside) {
                Toggle(padStrings.closeOnClickOutside, isOn: $scratchpadCloseOnClickOutside)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: scratchpadCloseOnClickOutside) { _, _ in
                        ScratchpadService.shared.outsideClickPreferenceDidChange()
                    }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(padStrings.textSize)
                    Spacer()
                    Text("\(Int(ScratchpadSupport.sanitizedTextSize(scratchpadTextSize)))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: scratchpadTextSizeBinding,
                       in: ScratchpadSupport.textSizeRange,
                       step: 1)
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text(padStrings.backgroundOpacity)
                Slider(value: scratchpadBackgroundOpacityBinding,
                       in: ScratchpadSupport.backgroundOpacityRange,
                       step: 0.05)
                HStack {
                    Text(padStrings.backgroundTranslucent)
                    Spacer()
                    Text(padStrings.backgroundOpaque)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Divider()
            SettingsRow(symbol: "keyboard", title: l10n.s.quickToolShortcutToggle) {
                Toggle(l10n.s.quickToolShortcutToggle, isOn: $scratchpadShortcutEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: scratchpadShortcutEnabled) { _, _ in
                        ScratchpadService.shared.syncWithPreferences()
                    }
            }
            ShortcutPreferenceRow(role: .scratchpad,
                                  isEnabled: scratchpadShortcutEnabled) {
                ScratchpadService.shared.syncWithPreferences()
            }
            .padding(.leading, settingsRowTextInset)
            if scratchpadShortcutEnabled, scratchpad.shortcutRegistrationFailed {
                Text(l10n.s.shortcutUnavailable)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.leading, settingsRowTextInset)
            }
        }
    }

    private var cleaningModeCard: some View {
        SettingsCard(title: l10n.s.cleaningMenuItem) {
            SettingsRow(symbol: "bubbles.and.sparkles", title: l10n.s.cleaningMenuItem,
                        caption: l10n.s.cleaningPanelCaption) {
                Button {
                    CleaningModeManager.shared.activate()
                } label: {
                    Label(l10n.s.cleaningStartNow, systemImage: "bubbles.and.sparkles")
                }
            }
            Divider()
            SettingsRow(symbol: "display", title: l10n.s.cleaningKeepScreenVisibleToggle,
                        caption: l10n.s.cleaningKeepScreenVisibleCaption) {
                Toggle(l10n.s.cleaningKeepScreenVisibleToggle, isOn: $cleaningModeKeepScreenVisible)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    private var scratchpadBackgroundOpacityBinding: Binding<Double> {
        Binding(
            get: { ScratchpadSupport.sanitizedBackgroundOpacity(scratchpadBackgroundOpacity) },
            set: { scratchpadBackgroundOpacity = ScratchpadSupport.sanitizedBackgroundOpacity($0) }
        )
    }

    private var scratchpadTextSizeBinding: Binding<Double> {
        Binding(
            get: { ScratchpadSupport.sanitizedTextSize(scratchpadTextSize) },
            set: { scratchpadTextSize = ScratchpadSupport.sanitizedTextSize($0) }
        )
    }
}

/// The camera state has no re-prompt once denied, so the row goes straight
/// to System Settings instead of offering a dead request button.
private struct CameraPermissionRow: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                Text(FeatureStrings.cameraPreview(l10n.language).permName)
                Spacer()
                Text(l10n.s.permissionMissing)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button(l10n.s.permissionOpenSettings) {
                Permissions.shared.openCameraSettings()
            }
            .controlSize(.small)
        }
    }
}
