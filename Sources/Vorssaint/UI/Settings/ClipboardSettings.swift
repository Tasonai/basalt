// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ClipboardSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var history = ClipboardHistoryService.shared
    @ObservedObject private var pastePlain = PastePlainService.shared
    @ObservedObject private var permissions = Permissions.shared
    @State private var clearingIDs: [UUID: Date]?
    @State private var vaultExpanded = false
    @State private var vaultPassphraseInput = ""
    @State private var hasStoredVaultPassphrase = false
    @State private var vaultStatusMessage: String?
    @State private var vaultStatusIsError = false
    @State private var isVaultBusy = false
    private let vaultSecretStore = KeychainClipboardVaultSecretStore()
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

    private var v2Strings: OverhaulV2Strings {
        OverhaulV2Strings.localized(l10n.language)
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
                clipboardVaultCard
                clipboardStatsCard
            }
        }
        .onAppear {
            limit = Defaults.sanitizedClipboardHistoryLimit(limit)
            retentionDays = Defaults.sanitizedClipboardHistoryRetentionDays(retentionDays)
            autoClearDelay = Defaults.sanitizedClipboardAutoClearDelay(autoClearDelay)
            menuBarPreviewLength = Defaults.sanitizedClipboardMenuBarPreviewLength(menuBarPreviewLength)
            refreshVaultPassphraseStatus()
        }
        .onDisappear {
            commitVaultPassphraseIfEdited()
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

    private var clipboardVaultCard: some View {
        let trimmedInput = vaultPassphraseInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return SettingsDisclosureCard(
            title: v2Strings.clipboardVaultTitle,
            symbol: "lock.shield",
            badge: hasStoredVaultPassphrase ? "Keychain" : nil,
            isExpanded: $vaultExpanded
        ) {
            SettingsRow(
                symbol: "key.fill",
                title: v2Strings.clipboardVaultPassphraseLabel,
                caption: hasStoredVaultPassphrase ? "Stored securely in macOS Keychain" : nil
            ) {
                HStack(spacing: 8) {
                    SecureField(
                        hasStoredVaultPassphrase ? "•••••••• (Keychain)" : v2Strings.clipboardVaultPassphraseLabel,
                        text: $vaultPassphraseInput
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 190)
                    .onSubmit {
                        commitVaultPassphraseIfEdited()
                    }
                    if !trimmedInput.isEmpty {
                        VorssaintActionChip(title: text.save, tone: .clipboardFiles, prominent: true) {
                            commitVaultPassphraseIfEdited()
                        }
                    } else if hasStoredVaultPassphrase {
                        VorssaintActionChip(title: text.delete, destructive: true) {
                            _ = vaultSecretStore.deleteSecret()
                            refreshVaultPassphraseStatus()
                            vaultStatusIsError = false
                            vaultStatusMessage = "Vault passphrase removed from Keychain."
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                VorssaintActionChip(
                    title: "Export .vorssaintvault…",
                    symbol: "square.and.arrow.up",
                    tone: .clipboardFiles
                ) {
                    exportVault()
                }
                .disabled(isVaultBusy)

                VorssaintActionChip(
                    title: "Import .vorssaintvault…",
                    symbol: "square.and.arrow.down",
                    tone: .clipboardFiles
                ) {
                    importVault()
                }
                .disabled(isVaultBusy)

                if isVaultBusy {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
            }

            if let vaultStatusMessage {
                Label(vaultStatusMessage,
                      systemImage: vaultStatusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(vaultStatusIsError ? Color.red : Color.green)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, settingsRowTextInset)
            }
        }
    }

    private func refreshVaultPassphraseStatus() {
        hasStoredVaultPassphrase = vaultSecretStore.loadSecret()?.isEmpty == false
    }

    private func commitVaultPassphraseIfEdited() {
        let trimmed = vaultPassphraseInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if vaultSecretStore.saveSecret(trimmed) {
            vaultPassphraseInput = ""
            refreshVaultPassphraseStatus()
            vaultStatusIsError = false
            vaultStatusMessage = "Vault passphrase saved in Keychain."
            VorssaintHaptics.alignment()
        } else {
            vaultStatusIsError = true
            vaultStatusMessage = "Unable to store vault passphrase in Keychain."
        }
    }

    private func resolveVaultPassphrase() -> String? {
        let trimmed = vaultPassphraseInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            commitVaultPassphraseIfEdited()
            return trimmed
        }
        if let saved = vaultSecretStore.loadSecret(), !saved.isEmpty {
            return saved
        }
        vaultStatusIsError = true
        vaultStatusMessage = "Enter and save a vault passphrase before exporting or importing."
        NSSound.beep()
        return nil
    }

    private func exportVault() {
        guard let passphrase = resolveVaultPassphrase() else { return }
        let panel = NSSavePanel()
        if let vaultType = UTType(filenameExtension: "vorssaintvault") {
            panel.allowedContentTypes = [vaultType, .data]
        }
        panel.nameFieldStringValue = "Vorssaint-Clipboard.vorssaintvault"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let entriesSnapshot = history.entries
        let pinboardsSnapshot = ClipboardPinboardStore.shared.pinboards
        isVaultBusy = true
        vaultStatusMessage = nil

        Task { @MainActor in
            do {
                let count = try await Task.detached(priority: .userInitiated) {
                    let snapshot = ClipboardVaultSnapshot(entries: entriesSnapshot, pinboards: pinboardsSnapshot)
                    let data = try JSONEncoder().encode(snapshot)
                    try ClipboardSyncVault.seal(data, to: url, passphrase: passphrase)
                    return snapshot.entries.count
                }.value
                isVaultBusy = false
                vaultStatusIsError = false
                vaultStatusMessage = "Exported \(count) encrypted entries to \(url.lastPathComponent)."
                VorssaintHaptics.alignment()
            } catch {
                isVaultBusy = false
                vaultStatusIsError = true
                vaultStatusMessage = vaultErrorMessage(error)
            }
        }
    }

    private func importVault() {
        guard let passphrase = resolveVaultPassphrase() else { return }
        let panel = NSOpenPanel()
        if let vaultType = UTType(filenameExtension: "vorssaintvault") {
            panel.allowedContentTypes = [vaultType, .data]
        }
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isVaultBusy = true
        vaultStatusMessage = nil

        Task { @MainActor in
            do {
                let snapshot = try await Task.detached(priority: .userInitiated) { () -> ClipboardVaultSnapshot in
                    let plaintext = try ClipboardSyncVault.open(from: url, passphrase: passphrase)
                    let decoder = JSONDecoder()
                    if let decoded = try? decoder.decode(ClipboardVaultSnapshot.self, from: plaintext) {
                        return decoded
                    }
                    let entries = try decoder.decode([ClipboardHistoryEntry].self, from: plaintext)
                    return ClipboardVaultSnapshot(entries: entries)
                }.value
                let added = history.mergeVaultSnapshot(snapshot)
                isVaultBusy = false
                vaultStatusIsError = false
                vaultStatusMessage = added > 0
                    ? "Imported \(added) new entries from \(url.lastPathComponent)."
                    : "Vault decrypted cleanly — all entries are already present."
                VorssaintHaptics.alignment()
            } catch {
                isVaultBusy = false
                vaultStatusIsError = true
                vaultStatusMessage = vaultErrorMessage(error)
            }
        }
    }

    private func vaultErrorMessage(_ error: Error) -> String {
        if let vaultError = error as? ClipboardSyncVault.VaultError {
            switch vaultError {
            case .emptyPassphrase:
                return "Vault passphrase cannot be empty."
            case .invalidEnvelope:
                return "Selected file is not a valid .vorssaintvault archive."
            case .wrongPassphraseOrTampered:
                return "Wrong passphrase or the .vorssaintvault file was tampered with."
            }
        }
        return "Vault sync failed: \(error.localizedDescription)"
    }

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
