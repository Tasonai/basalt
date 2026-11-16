// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct ClipboardSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var history = ClipboardHistoryService.shared
    @ObservedObject private var pastePlain = PastePlainService.shared
    @ObservedObject private var permissions = Permissions.shared
    @State private var clearingIDs: [UUID: Date]?
    @AppStorage(DefaultsKey.pastePlainEnabled) private var pastePlainEnabled = false
    @AppStorage(DefaultsKey.clipboardHistoryEnabled) private var enabled = false
    @AppStorage(DefaultsKey.clipboardHistoryLimit) private var limit = 50
    @AppStorage(DefaultsKey.clipboardHistoryRetentionDays) private var retentionDays = 0
    @AppStorage(DefaultsKey.clipboardHistoryFilterSensitiveText) private var skipSensitive = false
    @AppStorage(DefaultsKey.clipboardHistoryIncludeImagesFiles) private var includeImagesFiles = true
    @AppStorage(DefaultsKey.clipboardHistoryShortcutEnabled) private var shortcutEnabled = true
    @AppStorage(DefaultsKey.clipboardHistoryShowSourceAppIcons) private var showSourceAppIcons = false
    @AppStorage(DefaultsKey.clipboardHistoryLayout) private var historyLayout = ClipboardHistoryLayout.list
    @AppStorage(DefaultsKey.clipboardHistoryMenuBarPreview) private var menuBarPreview = false
    @AppStorage(DefaultsKey.clipboardHistoryMenuBarPreviewLength)
    private var menuBarPreviewLength = Defaults.defaultClipboardMenuBarPreviewLength
    @AppStorage(DefaultsKey.panelUtilityClipboard) private var showInPanel = true
    @AppStorage(DefaultsKey.finderPasteImageAsFile) private var pasteImageAsFile = false
    @AppStorage(DefaultsKey.clipboardAutoClearOnDelay) private var autoClearOnDelay = false
    @AppStorage(DefaultsKey.clipboardAutoClearDelay)
    private var autoClearDelay = Defaults.defaultClipboardAutoClearDelay
    @AppStorage(DefaultsKey.clipboardAutoClearOnSleep) private var autoClearOnSleep = false
    @AppStorage(DefaultsKey.clipboardAutoClearOnDisplaySleep) private var autoClearOnDisplaySleep = false
    @AppStorage(DefaultsKey.clipboardAutoClearOnScreenLock) private var autoClearOnScreenLock = false

    private var text: ClipboardFeatureStrings {
        FeatureStrings.clipboard(l10n.language)
    }

    private var retentionText: ClipboardRetentionStrings {
        FeatureStrings.clipboardRetention(l10n.language)
    }

    var body: some View {
        SettingsPageContainer(title: text.title) {
            if AppFeature.clipboardHistory.isAvailable {
                SettingsCard {
                    SettingsRow(symbol: "doc.on.clipboard", title: text.enable, caption: text.caption) {
                        Toggle(text.enable, isOn: $enabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: enabled) { _, _ in
                                ClipboardHistoryService.shared.syncWithPreferences()
                            }
                    }
                    Text(text.localNote)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, settingsRowTextInset)
                    if enabled, history.isRunning {
                        Label(text.active, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .padding(.leading, settingsRowTextInset)
                    }
                }
                .settingsSectionAnchor(.clipboardHistory, cornerRadius: 16)

                clipboardShortcutCard
                clipboardMenuBarPreviewCard

                SettingsCard {
                    SettingsRow(symbol: "photo.on.rectangle", title: text.includeImagesFiles,
                                caption: text.includeImagesFilesCaption) {
                        Toggle(text.includeImagesFiles, isOn: $includeImagesFiles)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .disabled(!enabled)
                    }
                    SettingsRow(symbol: "shield.lefthalf.filled", title: text.skipSensitive,
                                caption: text.skipSensitiveCaption) {
                        Toggle(text.skipSensitive, isOn: $skipSensitive)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .disabled(!enabled)
                    }
                    Divider()
                    ClipboardIgnoredAppsList()
                        .disabled(!enabled)
                    Divider()
                    SettingsMenuRow(symbol: "tray.full", title: text.limit, selection: $limit) {
                        ForEach(Defaults.allowedClipboardHistoryLimits, id: \.self) { value in
                            Text(value == 0 ? text.limitUnlimited : "\(value)").tag(value)
                        }
                    }
                    .disabled(!enabled)
                    SettingsMenuRow(symbol: "clock", title: retentionText.title, selection: $retentionDays) {
                        ForEach(Defaults.allowedClipboardHistoryRetentionDays, id: \.self) { value in
                            Text(retentionText.label(days: value)).tag(value)
                        }
                    }
                    .disabled(!enabled)
                    Text(retentionText.caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, settingsRowTextInset)
                }

                // Its own card because it is the one setting here that keeps
                // working with capture off: the panel entry stays, saying so,
                // and still opens the saved items. Sitting among the disabled
                // rows it read as one that had been missed.
                SettingsCard {
                    SettingsRow(symbol: "sidebar.left", title: text.showInPanel) {
                        Toggle(text.showInPanel, isOn: $showInPanel)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }

                clipboardAutoClearCard
            }

            if AppFeature.finderCutPaste.isAvailable {
                SettingsCard {
                    SettingsRow(symbol: "doc.badge.plus", title: text.pasteImageAsFile,
                                caption: text.pasteImageAsFileCaption) {
                        Toggle(text.pasteImageAsFile, isOn: $pasteImageAsFile)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: pasteImageAsFile) { _, _ in
                                FinderCutPaste.shared.syncWithPreferences()
                            }
                    }
                    if pasteImageAsFile, !permissions.accessibility {
                        Divider()
                        PermissionRow(kind: .accessibility)
                    }
                }
            }

            if AppFeature.pastePlain.isAvailable {
                SettingsCard(title: l10n.s.pastePlainName) {
                    SettingsRow(symbol: "doc.plaintext", title: l10n.s.pastePlainName,
                                caption: l10n.s.pastePlainCaption) {
                        Toggle(l10n.s.pastePlainName, isOn: $pastePlainEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: pastePlainEnabled) { _, _ in
                                PastePlainService.shared.syncWithPreferences()
                            }
                    }
                    ShortcutPreferenceRow(role: .pastePlain,
                                          isEnabled: pastePlainEnabled) {
                        PastePlainService.shared.syncWithPreferences()
                    }
                    .padding(.leading, settingsRowTextInset)
                    if pastePlainEnabled, pastePlain.shortcutRegistrationFailed {
                        Text(l10n.s.shortcutUnavailable)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, settingsRowTextInset)
                    }
                    if pastePlainEnabled, !permissions.accessibility {
                        Divider()
                        PermissionRow(kind: .accessibility)
                    }
                }
                .settingsSectionAnchor(.pastePlain, cornerRadius: 16)
            }

            if AppFeature.clipboardHistory.isAvailable {
                clipboardStatsCard
            }
        }
        .onAppear {
            limit = Defaults.sanitizedClipboardHistoryLimit(limit)
            retentionDays = Defaults.sanitizedClipboardHistoryRetentionDays(retentionDays)
            autoClearDelay = Defaults.sanitizedClipboardAutoClearDelay(autoClearDelay)
            menuBarPreviewLength = Defaults.sanitizedClipboardMenuBarPreviewLength(menuBarPreviewLength)
        }
        .onChange(of: limit) { _, value in
            let sanitized = Defaults.sanitizedClipboardHistoryLimit(value)
            if sanitized != value { limit = sanitized }
            ClipboardHistoryService.shared.trimToLimit()
        }
        .onChange(of: retentionDays) { _, value in
            let sanitized = Defaults.sanitizedClipboardHistoryRetentionDays(value)
            if sanitized != value { retentionDays = sanitized }
            ClipboardHistoryService.shared.trimToLimit()
        }
        // No syncWithPreferences() here, unlike the auto-clear toggles: the
        // running poll reads this value from UserDefaults on every tick, so a
        // new delay takes effect on the next one. Syncing would just tear the
        // timer down and restart the wait.
        .onChange(of: autoClearDelay) { _, value in
            let sanitized = Defaults.sanitizedClipboardAutoClearDelay(value)
            if sanitized != value { autoClearDelay = sanitized }
        }
        .onChange(of: menuBarPreviewLength) { _, value in
            let sanitized = Defaults.sanitizedClipboardMenuBarPreviewLength(value)
            if sanitized != value { menuBarPreviewLength = sanitized }
        }
    }

    private var clipboardShortcutCard: some View {
        SettingsCard(title: text.shortcut) {
            SettingsRow(symbol: "keyboard", title: text.shortcut, caption: text.shortcutCaption) {
                Toggle(text.shortcut, isOn: $shortcutEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: shortcutEnabled) { _, _ in
                        ClipboardHistoryService.shared.syncHotkey()
                    }
                    .disabled(!enabled)
            }
            ShortcutPreferenceRow(role: .clipboard,
                                  isEnabled: enabled && shortcutEnabled,
                                  additionalConflict: WindowLayoutService.shared.shortcutConflictTitle) {
                ClipboardHistoryService.shared.syncHotkey()
            }
            .padding(.leading, settingsRowTextInset)
            if enabled, shortcutEnabled, history.shortcutRegistrationFailed {
                Text(l10n.s.shortcutUnavailable)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, settingsRowTextInset)
            }
            Divider()
            // Not disabled with capture off: the window still opens on the
            // saved items, like the button below.
            SettingsChoiceRow(symbol: "square.grid.2x2", title: text.historyLayout, selection: $historyLayout) {
                Text(text.historyLayoutList).tag(ClipboardHistoryLayout.list)
                Text(text.historyLayoutCards).tag(ClipboardHistoryLayout.cards)
            }
            SettingsRow(symbol: "app.badge", title: text.showSourceAppIconsInList) {
                Toggle(text.showSourceAppIconsInList, isOn: $showSourceAppIcons)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            Divider()
            HStack {
                VorssaintActionChip(title: text.shortcut, symbol: "doc.on.clipboard", tone: .clipboardFiles) {
                    ClipboardHistoryService.shared.showHistoryWindow()
                }
                .disabled(history.entries.isEmpty)
                Spacer()
            }
        }
    }

    private var clipboardMenuBarPreviewCard: some View {
        SettingsCard {
            SettingsRow(symbol: "menubar.rectangle", title: text.menuBarPreview,
                        caption: text.menuBarPreviewCaption) {
                Toggle(text.menuBarPreview, isOn: $menuBarPreview)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!enabled)
            }
            SettingsRow(symbol: "textformat", title: text.menuBarPreviewLength) {
                HStack(spacing: 6) {
                    TextField("", value: $menuBarPreviewLength, formatter: Self.menuBarPreviewLengthFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                        .multilineTextAlignment(.trailing)
                    Text(text.menuBarPreviewLengthSuffix)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!enabled || !menuBarPreview)
        }
    }

    private static let menuBarPreviewLengthFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = NSNumber(value: Defaults.allowedClipboardMenuBarPreviewLengthRange.lowerBound)
        formatter.maximum = NSNumber(value: Defaults.allowedClipboardMenuBarPreviewLengthRange.upperBound)
        formatter.usesGroupingSeparator = false
        return formatter
    }()

    // Never disabled by the capture toggle, unlike the cards above it:
    // emptying the pasteboard is a security setting in its own right, and
    // someone who keeps no history is exactly who reaches for it.
    private var clipboardAutoClearCard: some View {
        SettingsCard {
            SettingsRow(symbol: "timer", title: text.autoClearEnable) {
                HStack(spacing: 8) {
                    TextField("", value: $autoClearDelay, formatter: Self.delayFieldFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        .disabled(!autoClearOnDelay)
                    Text(text.autoClearSecondsSuffix)
                        .foregroundStyle(.secondary)
                    Toggle(text.autoClearEnable, isOn: $autoClearOnDelay)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: autoClearOnDelay) { _, _ in
                            ClipboardAutoClearService.shared.syncWithPreferences()
                        }
                }
            }
            SettingsRow(symbol: "moon.zzz", title: text.autoClearOnSleep) {
                Toggle(text.autoClearOnSleep, isOn: $autoClearOnSleep)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: autoClearOnSleep) { _, _ in
                        ClipboardAutoClearService.shared.syncWithPreferences()
                    }
            }
            SettingsRow(symbol: "display", title: text.autoClearOnDisplaySleep) {
                Toggle(text.autoClearOnDisplaySleep, isOn: $autoClearOnDisplaySleep)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: autoClearOnDisplaySleep) { _, _ in
                        ClipboardAutoClearService.shared.syncWithPreferences()
                    }
            }
            SettingsRow(symbol: "lock", title: text.autoClearOnScreenLock) {
                Toggle(text.autoClearOnScreenLock, isOn: $autoClearOnScreenLock)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: autoClearOnScreenLock) { _, _ in
                        ClipboardAutoClearService.shared.syncWithPreferences()
                    }
            }
            Text(text.autoClearCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, settingsRowTextInset)
        }
    }

    private static let delayFieldFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = NSNumber(value: Defaults.allowedClipboardAutoClearDelayRange.lowerBound)
        formatter.maximum = NSNumber(value: Defaults.allowedClipboardAutoClearDelayRange.upperBound)
        formatter.usesGroupingSeparator = false
        return formatter
    }()

    private var clipboardStatsCard: some View {
        SettingsCard {
            HStack(spacing: 6) {
                Text("\(history.pinnedEntries.count)")
                    .monospacedDigit()
                Text(text.pinned)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("\(history.recentEntries.count)")
                    .monospacedDigit()
                Text(text.recent)
                    .foregroundStyle(.secondary)
                Spacer()
                VorssaintActionChip(title: text.clearRecent, symbol: "trash", destructive: true) {
                    clearingIDs = history.recentEntriesSnapshot
                }
                .disabled(history.recentEntries.isEmpty)
                .modifier(ClipboardClearRecentConfirmation(entryIDs: $clearingIDs))
            }
        }
    }
}
