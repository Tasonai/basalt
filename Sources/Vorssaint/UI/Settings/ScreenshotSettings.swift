// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Screenshot-specific sections inside the shared screen-capture page.
struct ScreenshotCaptureSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = ScreenshotService.shared
    @ObservedObject private var sharing = ScreenshotShareService.shared
    @ObservedObject private var cloudUpload = ScreenshotCloudUploadService.shared
    @AppStorage(DefaultsKey.screenshotFullScreenShortcutEnabled)
    private var fullScreenShortcutEnabled = false
    @AppStorage(DefaultsKey.screenshotLastCaptureShortcutEnabled)
    private var lastCaptureShortcutEnabled = false
    @AppStorage(DefaultsKey.screenshotClipboardShortcutEnabled)
    private var clipboardShortcutEnabled = false
    @AppStorage(DefaultsKey.screenshotFreeze) private var freeze = true
    @AppStorage(DefaultsKey.screenshotHideVorssaintWindows) private var hideVorssaintWindows = true
    @AppStorage(DefaultsKey.screenshotHideDesktopIcons) private var hideDesktopIcons = false
    @AppStorage(DefaultsKey.screenshotSaveFolder) private var saveFolder = ""
    @AppStorage(DefaultsKey.screenshotSaveSubfolder) private var saveSubfolder = ""
    @AppStorage(DefaultsKey.screenshotFileNamePattern) private var fileNamePattern = ""
    @AppStorage(DefaultsKey.screenshotFileNumberStart) private var numberStart = 1
    @AppStorage(DefaultsKey.screenshotFileNumberNext) private var nextNumber = 1
    @AppStorage(DefaultsKey.screenshotIncludePointer) private var includePointer = false
    @AppStorage(DefaultsKey.screenshotShowLastRegion) private var showLastRegion = true
    @AppStorage(DefaultsKey.screenshotHighlightWindows) private var highlightWindows = true
    @AppStorage(DefaultsKey.screenshotLoupeStartsOn) private var loupeStartsOn = false
    @AppStorage(DefaultsKey.screenshotLoupeRememberZoom) private var rememberLoupeZoom = false
    @AppStorage(DefaultsKey.screenshotLoupeDefaultZoom) private var loupeDefaultZoom = 1.0
    @AppStorage(DefaultsKey.screenshotLoupeSteppedZoomByDefault)
    private var steppedLoupeZoomByDefault = false
    @AppStorage(DefaultsKey.screenshotDownscale) private var downscale = false
    @AppStorage(DefaultsKey.screenshotDelay) private var delay = 0
    @AppStorage(DefaultsKey.screenshotDefaultAction) private var defaultActionRaw = ""
    @AppStorage(DefaultsKey.screenshotToolOrder) private var toolOrderRaw =
        ScreenshotSupport.Tool.defaultOrderStorage
    @AppStorage(DefaultsKey.screenshotToolShortcutsEnabled) private var toolShortcutsEnabled = true
    @AppStorage(DefaultsKey.screenshotCopyToClipboard) private var copyToClipboard = false
    @AppStorage(DefaultsKey.screenshotCopyImageOnly) private var copyImageOnly = false
    @AppStorage(DefaultsKey.screenshotAddToShelf) private var addToShelf = false
    @AppStorage(DefaultsKey.shelfEnabled) private var shelfEnabled = false
    @AppStorage(AppFeature.shelf.availabilityKey) private var shelfAvailable = false
    @AppStorage(DefaultsKey.screenshotPreviewPosition) private var previewPositionRaw = ""
    @AppStorage(DefaultsKey.screenshotPreviewTakesFocus) private var previewTakesFocus = true
    @AppStorage(DefaultsKey.screenshotPreviewEnabled) private var previewEnabled = true
    @AppStorage(DefaultsKey.screenshotPreviewDuration) private var previewDuration =
        ScreenshotSupport.defaultConfirmationPreviewDuration
    @AppStorage(DefaultsKey.screenshotSharingEnabled) private var sharingEnabled = true
    @AppStorage(DefaultsKey.screenshotUploadShortcutEnabled) private var uploadShortcutEnabled = false
    @AppStorage(DefaultsKey.screenshotUploadDuration) private var uploadDuration = ScreenshotShareDuration.oneHour.rawValue
    @State private var showingSharedLinks = false
    @State private var showingSharePrivacy = false
    @State private var cloudExpanded = ScreenshotCloudUploadService.shared.config.provider != .disabled
    @State private var cloudSecretInput = ""
    @State private var deletingUploadID: UUID?
    @State private var cloudDeleteError: String?

    private var strings: ScreenshotFeatureStrings {
        FeatureStrings.screenshot(l10n.language)
    }

    private var v2Strings: OverhaulV2Strings {
        OverhaulV2Strings.localized(l10n.language)
    }

    private func v3(_ keyPath: KeyPath<OverhaulV3Strings, String>) -> String {
        OverhaulV3Strings.localized(l10n.language)[keyPath: keyPath]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: strings.pageTitle) {
                HStack(spacing: 10) {
                    Button {
                        ScreenshotService.shared.capture()
                    } label: {
                        Label(strings.captureButton, systemImage: "camera.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    Button {
                        ScreenshotService.shared.captureScrolling()
                    } label: {
                        Label(strings.scrollingCaptureButton, systemImage: "rectangle.stack")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                Text(strings.panelCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                SettingsRow(symbol: "arrow.up.left.and.arrow.down.right",
                            title: strings.fullScreenShortcutTitle) {
                    Toggle(strings.fullScreenShortcutTitle, isOn: $fullScreenShortcutEnabled)
                        .labelsHidden()
                        .toggleStyle(VorssaintCompactSwitchStyle())
                        .onChange(of: fullScreenShortcutEnabled) { _, _ in
                            ScreenshotService.shared.syncWithPreferences()
                        }
                }
                ShortcutPreferenceRow(role: .screenshotFullScreen,
                                      isEnabled: fullScreenShortcutEnabled) {
                    ScreenshotService.shared.syncWithPreferences()
                }
                .padding(.leading, settingsRowTextInset)
                if fullScreenShortcutEnabled, service.fullScreenShortcutRegistrationFailed {
                    Text(l10n.s.shortcutUnavailable)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, settingsRowTextInset)
                }
                SettingsRow(symbol: "photo.on.rectangle", title: strings.editLastCapture) {
                    Toggle(strings.editLastCapture, isOn: $lastCaptureShortcutEnabled)
                        .labelsHidden()
                        .toggleStyle(VorssaintCompactSwitchStyle())
                        .onChange(of: lastCaptureShortcutEnabled) { _, _ in
                            ScreenshotService.shared.syncWithPreferences()
                        }
                }
                ShortcutPreferenceRow(role: .screenshotLastCapture,
                                      isEnabled: lastCaptureShortcutEnabled) {
                    ScreenshotService.shared.syncWithPreferences()
                }
                .padding(.leading, settingsRowTextInset)
                if lastCaptureShortcutEnabled,
                   service.lastCaptureShortcutRegistrationFailed {
                    Text(l10n.s.shortcutUnavailable)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, settingsRowTextInset)
                }
                SettingsRow(symbol: "doc.on.clipboard", title: strings.editClipboardImage) {
                    Toggle(strings.editClipboardImage, isOn: $clipboardShortcutEnabled)
                        .labelsHidden()
                        .toggleStyle(VorssaintCompactSwitchStyle())
                        .onChange(of: clipboardShortcutEnabled) { _, _ in
                            ScreenshotService.shared.syncWithPreferences()
                        }
                }
                ShortcutPreferenceRow(role: .screenshotClipboard,
                                      isEnabled: clipboardShortcutEnabled) {
                    ScreenshotService.shared.syncWithPreferences()
                }
                .padding(.leading, settingsRowTextInset)
                if clipboardShortcutEnabled, service.clipboardShortcutRegistrationFailed {
                    Text(l10n.s.shortcutUnavailable)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, settingsRowTextInset)
                }
                if !permissions.screenRecording {
                    Divider()
                    PermissionRow(kind: .screenRecording)
                }
            }
            .settingsSectionAnchor(.screenshot, cornerRadius: 16)

            SettingsCard {
                SettingsRow(symbol: "snowflake", title: strings.freezeToggle,
                            caption: strings.freezeCaption) {
                    Toggle(strings.freezeToggle, isOn: $freeze)
                        .labelsHidden()
                        .toggleStyle(VorssaintCompactSwitchStyle())
                }
                SettingsRow(symbol: "eye.slash", title: strings.hideVorssaintWindowsToggle) {
                    Toggle(strings.hideVorssaintWindowsToggle, isOn: $hideVorssaintWindows)
                        .labelsHidden()
                        .toggleStyle(VorssaintCompactSwitchStyle())
                }
                SettingsRow(symbol: "desktopcomputer",
                            title: OverhaulStrings.wave2(l10n.language).hideDesktopIconsLabel) {
                    Toggle(OverhaulStrings.wave2(l10n.language).hideDesktopIconsLabel,
                           isOn: $hideDesktopIcons)
                        .labelsHidden()
                        .toggleStyle(VorssaintCompactSwitchStyle())
                }
                Divider()
                SettingsChoiceRow(symbol: "timer", title: strings.delayLabel, selection: $delay) {
                    ForEach(ScreenshotSupport.allowedDelays, id: \.self) { seconds in
                        if seconds == 0 {
                            Text(strings.delayOff).tag(0)
                        } else {
                            Text(String(format: strings.delaySecondsFormat, seconds)).tag(seconds)
                        }
                    }
                }
                Divider()
                SettingsRow(symbol: "cursorarrow", title: strings.pointerToggle) {
                    Toggle(strings.pointerToggle, isOn: $includePointer)
                        .labelsHidden()
                        .toggleStyle(VorssaintCompactSwitchStyle())
                }
                SettingsRow(symbol: "rectangle.dashed", title: strings.lastRegionToggle) {
                    Toggle(strings.lastRegionToggle, isOn: $showLastRegion)
                        .labelsHidden()
                        .toggleStyle(VorssaintCompactSwitchStyle())
                }
                SettingsRow(symbol: "macwindow", title: strings.highlightWindowsToggle,
                            caption: strings.highlightWindowsCaption) {
                    Toggle(strings.highlightWindowsToggle, isOn: $highlightWindows)
                        .labelsHidden()
                        .toggleStyle(VorssaintCompactSwitchStyle())
                }
                Divider()
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsRow(symbol: "magnifyingglass", title: strings.loupeStartsOnToggle) {
                            Toggle(strings.loupeStartsOnToggle, isOn: $loupeStartsOn)
                                .labelsHidden()
                                .toggleStyle(VorssaintCompactSwitchStyle())
                        }
                        SettingsRow(symbol: "plus.magnifyingglass", title: strings.loupeRememberZoomToggle) {
                            Toggle(strings.loupeRememberZoomToggle, isOn: $rememberLoupeZoom)
                                .labelsHidden()
                                .toggleStyle(VorssaintCompactSwitchStyle())
                        }
                        if !rememberLoupeZoom {
                            SettingsMenuRow(symbol: "viewfinder", title: strings.loupeDefaultZoomLabel,
                                            selection: $loupeDefaultZoom) {
                                ForEach(ScreenshotSupport.captureLoupeDefaultZooms, id: \.self) { zoom in
                                    Text(zoom.formatted(
                                        .number.precision(.fractionLength(0...1))) + "×")
                                        .tag(zoom)
                                }
                            }
                        }
                        SettingsChoiceRow(symbol: "plus.magnifyingglass", title: strings.loupeWheelZoomLabel,
                                          selection: $steppedLoupeZoomByDefault) {
                            Text(strings.loupeZoomFast).tag(false)
                            Text(strings.loupeZoomStepped).tag(true)
                        }
                        Text(strings.loupeZoomOptionCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, settingsRowTextInset)
                        previewPositionRow
                        previewFocusRow
                        defaultActionRow
                    }
                    .padding(.top, 8)
                } label: {
                    Text(FeatureStrings.recorder(l10n.language).moreOptions)
                        .font(.subheadline.weight(.medium))
                }
            }

            SettingsCard {
                SettingsRow(symbol: "doc.on.clipboard", title: strings.autoCopyToggle,
                            caption: strings.autoCopyCaption) {
                    Toggle(strings.autoCopyToggle, isOn: autoCopyBinding)
                        .labelsHidden()
                        .toggleStyle(VorssaintCompactSwitchStyle())
                }
                SettingsRow(symbol: "photo", title: strings.copyImageOnlyToggle,
                            caption: strings.copyImageOnlyCaption) {
                    Toggle(strings.copyImageOnlyToggle, isOn: $copyImageOnly)
                        .labelsHidden()
                        .toggleStyle(VorssaintCompactSwitchStyle())
                }
                SettingsRow(symbol: "tray.and.arrow.down", title: strings.addToShelfToggle,
                            caption: strings.addToShelfCaption) {
                    Toggle(strings.addToShelfToggle, isOn: addToShelfBinding)
                        .labelsHidden()
                        .toggleStyle(VorssaintCompactSwitchStyle())
                        .disabled(!shelfIsOn)
                }
                Divider()
                folderRow
                subfolderRow
                fileNameRow
                Divider()
                SettingsRow(symbol: "arrow.down.right.and.arrow.up.left", title: strings.downscaleToggle,
                            caption: strings.downscaleCaption) {
                    Toggle(strings.downscaleToggle, isOn: $downscale)
                        .labelsHidden()
                        .toggleStyle(VorssaintCompactSwitchStyle())
                }
            }

            SettingsCard(title: strings.toolShortcutsTitle) {
                ScreenshotToolOrderControls(orderRaw: $toolOrderRaw,
                                            shortcutsEnabled: $toolShortcutsEnabled,
                                            showsTitle: false)
            }

            SettingsCard(title: strings.shareSectionTitle) {
                SettingsRow(symbol: "square.and.arrow.up", title: strings.shareEnabledToggle,
                            caption: sharingEnabled ? strings.shareCaption : nil) {
                    Toggle(strings.shareEnabledToggle, isOn: $sharingEnabled)
                        .labelsHidden()
                        .toggleStyle(VorssaintCompactSwitchStyle())
                        .onChange(of: sharingEnabled) { _, _ in service.syncWithPreferences() }
                }
                if sharingEnabled {
                    Divider()
                    SettingsRow(symbol: "keyboard", title: strings.uploadLastCapture) {
                        Toggle(strings.uploadLastCapture, isOn: $uploadShortcutEnabled)
                            .labelsHidden()
                            .toggleStyle(VorssaintCompactSwitchStyle())
                            .onChange(of: uploadShortcutEnabled) { _, _ in service.syncWithPreferences() }
                    }
                    ShortcutPreferenceRow(role: .screenshotUpload,
                                          isEnabled: uploadShortcutEnabled) {
                        service.syncWithPreferences()
                    }
                    .padding(.leading, settingsRowTextInset)
                    if uploadShortcutEnabled, service.uploadShortcutRegistrationFailed {
                        Text(l10n.s.shortcutUnavailable)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, settingsRowTextInset)
                    }
                    SettingsMenuRow(symbol: "clock", title: strings.uploadExpiry, selection: $uploadDuration) {
                        ForEach(ScreenshotShareDuration.allCases) { duration in
                            Text(duration.title(strings)).tag(duration.rawValue)
                        }
                    }
                }
                Divider()
                Button {
                    showingSharePrivacy = true
                } label: {
                    SettingsRow(symbol: "hand.raised", title: strings.sharePrivacyButton) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if !sharing.records.isEmpty {
                    Button {
                        showingSharedLinks = true
                    } label: {
                        SettingsRow(symbol: "link", title: strings.sharedLinksTitle) {
                            HStack(spacing: 6) {
                                Text("\(sharing.records.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            cloudUploadCard
        }
        .onAppear {
            sharing.refresh()
            cloudUpload.refreshSecretStatus()
            if cloudUpload.config.provider != .disabled || !cloudUpload.recentUploads.isEmpty {
                cloudExpanded = true
            }
        }
        .onDisappear {
            commitCloudSecretIfEdited()
        }
        .sheet(isPresented: $showingSharedLinks) {
            ScreenshotSharedLinksView()
        }
        .sheet(isPresented: $showingSharePrivacy) {
            ScreenshotSharePrivacyView()
        }
    }

    private var cloudUploadCard: some View {
        SettingsDisclosureCard(
            title: v2Strings.cloudUploadTitle,
            symbol: "icloud.and.arrow.up",
            badge: cloudUpload.isConfigured ? cloudUpload.config.provider.shortBadge : nil,
            isExpanded: $cloudExpanded
        ) {
            SettingsChoiceRow(
                symbol: "icloud.and.arrow.up",
                title: v2Strings.cloudUploadTitle,
                selection: $cloudUpload.config.provider
            ) {
                Text(strings.delayOff).tag(ScreenshotCloudProvider.disabled)
                Text("S3 / R2").tag(ScreenshotCloudProvider.s3Compatible)
                Text("Webhook").tag(ScreenshotCloudProvider.customWebhook)
            }
            .onChange(of: cloudUpload.config.provider) { _, _ in
                cloudSecretInput = ""
                cloudUpload.refreshSecretStatus()
            }

            if cloudUpload.config.provider != .disabled {
                Divider()
                SettingsRow(symbol: "link", title: v2Strings.cloudEndpointLabel) {
                    TextField(
                        cloudUpload.config.provider == .s3Compatible
                            ? "https://account.r2.cloudflarestorage.com"
                            : "https://uploads.example.com/hook",
                        text: $cloudUpload.config.endpointURLString
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                }
            }

            if cloudUpload.config.provider == .s3Compatible {
                SettingsRow(symbol: "externaldrive", title: v2Strings.cloudBucketLabel) {
                    TextField("screenshots", text: $cloudUpload.config.bucket)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
                SettingsRow(symbol: "globe", title: v2Strings.cloudRegionLabel) {
                    TextField("auto", text: $cloudUpload.config.region)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                }
                SettingsRow(symbol: "folder", title: "Key prefix") {
                    TextField("captures/", text: $cloudUpload.config.keyPrefix)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
                SettingsRow(symbol: "arrow.up.forward.app", title: "Public base URL") {
                    TextField("https://cdn.example.com", text: $cloudUpload.config.publicBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }
                SettingsRow(symbol: "key", title: v2Strings.cloudAccessKeyLabel) {
                    TextField("AKIA...", text: $cloudUpload.config.accessKeyID)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }
                cloudSecretRow(placeholder: "Secret Access Key")
            } else if cloudUpload.config.provider == .customWebhook {
                SettingsRow(symbol: "key", title: "Auth header") {
                    TextField("Authorization", text: $cloudUpload.config.webhookHeaderName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
                cloudSecretRow(placeholder: "Bearer / API token")
                SettingsRow(symbol: "doc.text", title: "Response URL JSON keypath") {
                    TextField("data.url", text: $cloudUpload.config.webhookResponseURLKeyPath)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
            }

            if !cloudUpload.recentUploads.isEmpty {
                Divider()
                cloudUploadHistorySection
            }
        }
    }

    private var cloudUploadHistorySection: some View {
        VStack(alignment: .leading, spacing: DesignSpace.sm) {
            HStack(spacing: DesignSpace.sm) {
                Label(v3(\OverhaulV3Strings.screenshotCloudHistoryTitle), systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(cloudUpload.recentUploads.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.top, DesignSpace.xs)

            if cloudUpload.recentUploads.count > 4 {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DesignSpace.xs) {
                        ForEach(cloudUpload.recentUploads) { entry in
                            cloudUploadHistoryRow(entry)
                        }
                    }
                }
                .frame(maxHeight: 220)
            } else {
                ForEach(cloudUpload.recentUploads) { entry in
                    cloudUploadHistoryRow(entry)
                }
            }

            if let cloudDeleteError {
                Text(cloudDeleteError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func cloudUploadHistoryRow(_ entry: CloudUploadHistoryEntry) -> some View {
        HStack(spacing: DesignSpace.sm) {
            VStack(alignment: .leading, spacing: DesignSpace.xxs) {
                Text(entry.filename)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .strikethrough(entry.isDeletedRemotely)
                    .foregroundStyle(entry.isDeletedRemotely ? .secondary : .primary)
                HStack(spacing: DesignSpace.xs) {
                    Text(entry.publicURL)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("·")
                    Text(entry.uploadedAt, style: .relative)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: DesignSpace.sm)
            if !entry.isDeletedRemotely {
                VorssaintActionChip(title: strings.copyLink, symbol: "doc.on.doc", tone: .tools) {
                    copyCloudURL(entry.publicURL)
                }
                if cloudUpload.config.provider == .s3Compatible {
                    VorssaintActionChip(
                        title: v3(\OverhaulV3Strings.screenshotCloudDeleteAction),
                        symbol: "trash",
                        tone: .tools,
                        destructive: true
                    ) {
                        deleteCloudEntry(entry)
                    }
                    .disabled(deletingUploadID != nil)
                }
            } else {
                Text(strings.linkDeletedHUD)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, DesignSpace.xs)
        .padding(.horizontal, DesignSpace.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignRadius.pill, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func copyCloudURL(_ urlString: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareVorssaintSource()
        if pasteboard.setString(urlString, forType: .string) {
            VorssaintHaptics.alignment()
            QuickToolHUD.show(icon: "link", message: v2Strings.cloudCopiedBadge)
        } else {
            NSSound.beep()
        }
    }

    private func deleteCloudEntry(_ entry: CloudUploadHistoryEntry) {
        deletingUploadID = entry.id
        cloudDeleteError = nil
        Task {
            do {
                try await cloudUpload.deleteRemoteUpload(entry)
                VorssaintHaptics.alignment()
                QuickToolHUD.show(icon: "trash", message: strings.linkDeletedHUD)
            } catch {
                cloudDeleteError = error.localizedDescription
                NSSound.beep()
            }
            deletingUploadID = nil
        }
    }

    private func cloudSecretRow(placeholder: String) -> some View {
        let trimmed = cloudSecretInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return SettingsRow(
            symbol: "key.fill",
            title: v2Strings.cloudSecretKeyLabel,
            caption: cloudUpload.hasStoredSecret ? "Stored securely in macOS Keychain" : nil
        ) {
            HStack(spacing: 8) {
                SecureField(
                    cloudUpload.hasStoredSecret ? "•••••••• (Keychain)" : placeholder,
                    text: $cloudSecretInput
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .onSubmit {
                    commitCloudSecretIfEdited()
                }
                if !trimmed.isEmpty {
                    VorssaintActionChip(title: strings.saveButton, tone: .tools, prominent: true) {
                        commitCloudSecretIfEdited()
                    }
                } else if cloudUpload.hasStoredSecret {
                    VorssaintActionChip(title: strings.backdropDeletePreset, destructive: true) {
                        _ = cloudUpload.deleteSecret()
                    }
                }
            }
        }
    }

    private func commitCloudSecretIfEdited() {
        let trimmed = cloudSecretInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if cloudUpload.saveSecret(trimmed) {
            cloudSecretInput = ""
        }
    }

    /// The after-capture action can copy too, so the toggle reads on while
    /// either one copies. Turning it off clears both. Otherwise captures keep
    /// reaching the clipboard while the switch shows off.
    private var autoCopyBinding: Binding<Bool> {
        Binding {
            copyToClipboard || defaultAction.copiesToClipboard
        } set: { isOn in
            copyToClipboard = isOn
            if !isOn { defaultActionRaw = defaultAction.withoutCopy.rawValue }
        }
    }

    private var defaultAction: ScreenshotDefaultAction {
        ScreenshotDefaultAction(rawValue: defaultActionRaw) ?? .none
    }

    private var shelfIsOn: Bool {
        shelfEnabled && shelfAvailable
    }

    /// Reads off while the shelf is off, since no capture reaches it then.
    /// The choice itself is kept for when the shelf comes back.
    private var addToShelfBinding: Binding<Bool> {
        Binding {
            addToShelf && shelfIsOn
        } set: { isOn in
            addToShelf = isOn
        }
    }

    private var defaultActionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsMenuRow(symbol: "bolt", title: strings.defaultActionLabel, selection: $defaultActionRaw) {
                ScreenshotDefaultActionPicker.options(strings: strings)
            }
            if defaultActionRaw != ScreenshotDefaultAction.edit.rawValue {
                Text(strings.defaultActionCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, settingsRowTextInset)
            }
            if usesAutomaticConfirmationPreview {
                SettingsRow(symbol: "photo", title: strings.confirmationPreviewToggle) {
                    Toggle(strings.confirmationPreviewToggle, isOn: $previewEnabled)
                        .labelsHidden()
                        .toggleStyle(VorssaintCompactSwitchStyle())
                }
                if previewEnabled {
                    SettingsMenuRow(symbol: "timer", title: strings.confirmationPreviewDurationLabel,
                                    selection: $previewDuration) {
                        ForEach(ScreenshotSupport.confirmationPreviewDurations, id: \.self) { seconds in
                            if seconds == 0 {
                                Text(strings.confirmationPreviewUntilDismissed).tag(0)
                            } else {
                                Text(String(format: strings.delaySecondsFormat, seconds)).tag(seconds)
                            }
                        }
                    }
                    .padding(.leading, settingsRowTextInset)
                }
                Text(strings.confirmationPreviewCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, settingsRowTextInset)
            }
        }
    }

    private var usesAutomaticConfirmationPreview: Bool {
        guard let action = ScreenshotDefaultAction(rawValue: defaultActionRaw) else { return false }
        switch action {
        case .save, .saveAndCopy, .copy: return true
        case .none, .edit: return false
        }
    }

    private var previewFocusRow: some View {
        SettingsRow(symbol: "cursorarrow.click", title: strings.previewFocusToggle,
                    caption: strings.previewFocusCaption) {
            Toggle(strings.previewFocusToggle, isOn: $previewTakesFocus)
                .labelsHidden()
                .toggleStyle(VorssaintCompactSwitchStyle())
        }
    }

    private var previewPositionRow: some View {
        SettingsMenuRow(symbol: "macwindow", title: strings.previewPositionLabel,
                        selection: $previewPositionRaw) {
            Text(strings.previewPositionAutomatic)
                .tag(ScreenshotSupport.QuickPreviewPosition.automatic.rawValue)
            Text(strings.previewPositionTopLeft)
                .tag(ScreenshotSupport.QuickPreviewPosition.topLeft.rawValue)
            Text(strings.previewPositionTopRight)
                .tag(ScreenshotSupport.QuickPreviewPosition.topRight.rawValue)
            Text(strings.previewPositionBottomLeft)
                .tag(ScreenshotSupport.QuickPreviewPosition.bottomLeft.rawValue)
            Text(strings.previewPositionBottomRight)
                .tag(ScreenshotSupport.QuickPreviewPosition.bottomRight.rawValue)
        }
    }

    private var folderRow: some View {
        SettingsRow(symbol: "folder", title: strings.folderLabel) {
            HStack(spacing: 8) {
                Text(currentFolderName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !saveFolder.isEmpty {
                    Button {
                        saveFolder = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                    .screenshotSafeHelp(l10n.s.shortcutReset)
                }
                VorssaintActionChip(title: strings.folderChoose, tone: .tools) {
                    chooseFolder()
                }
            }
        }
    }

    private var subfolderRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            SettingsRow(symbol: "folder.fill", title: strings.subfolderLabel) {
                HStack(spacing: 8) {
                    if !saveSubfolder.isEmpty {
                        Text(ScreenshotSupport.expandSaveSubfolder(saveSubfolder, date: Date()))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    TextField("", text: $saveSubfolder)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }
            }
            Text(strings.subfolderCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, settingsRowTextInset)
        }
    }

    private var fileNameRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsRow(symbol: "doc.text", title: strings.fileNamePatternLabel) {
                HStack(spacing: 8) {
                    Text(fileNamePreview)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    TextField("", text: $fileNamePattern)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }
            }
            Text(strings.fileNamePatternCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, settingsRowTextInset)
            if ScreenshotSupport.fileNamePatternUsesNumber(fileNamePattern) {
                HStack(spacing: 8) {
                    Text(strings.fileNumberStartLabel)
                        .lineLimit(1)
                    TextField("", value: $numberStart, formatter: Self.numberFieldFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Stepper("", value: $numberStart, in: 0...999_999)
                        .labelsHidden()
                    VorssaintActionChip(title: strings.fileNumberResetButton, tone: .tools) {
                        nextNumber = numberStart
                    }
                    Spacer()
                    Text(String(format: strings.fileNumberNextFormat, nextNumber))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, settingsRowTextInset)
                .onChange(of: numberStart) { _, newValue in
                    nextNumber = newValue
                }
            }
        }
    }

    private static let numberFieldFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 0
        formatter.maximum = 999_999
        formatter.usesGroupingSeparator = false
        return formatter
    }()

    private var fileNamePreview: String {
        let trimmed = fileNamePattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ScreenshotSupport.fileName(prefix: strings.fileNamePrefix, date: Date())
        }
        return ScreenshotSupport.expandFileNamePattern(trimmed, date: Date(), number: nextNumber) + ".png"
    }

    private var currentFolderName: String {
        let manager = FileManager.default
        if !saveFolder.isEmpty {
            let expanded = (saveFolder as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if manager.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue {
                return manager.displayName(atPath: expanded)
            }
        }
        let desktop = manager.urls(for: .desktopDirectory, in: .userDomainMask).first
        return desktop.map { manager.displayName(atPath: $0.path) } ?? "Desktop"
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            saveFolder = url.path
        }
    }
}

struct ScreenshotSharePrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared
    let actionTitle: String?
    let onAction: (() -> Void)?

    init(actionTitle: String? = nil, onAction: (() -> Void)? = nil) {
        self.actionTitle = actionTitle
        self.onAction = onAction
    }

    private var strings: ScreenshotFeatureStrings {
        FeatureStrings.screenshot(l10n.language)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(strings.sharePrivacyTitle, systemImage: "hand.raised")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(actionTitle ?? strings.done) {
                    dismiss()
                    guard let onAction else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onAction()
                    }
                }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    privacyParagraph(symbol: "photo", text: strings.sharePrivacyData)
                    privacyParagraph(symbol: "externaldrive", text: strings.sharePrivacyStorage)
                    privacyParagraph(symbol: "person.2", text: strings.sharePrivacyAccess)
                }
                .padding(20)
            }
        }
        .frame(width: 560, height: 390)
    }

    private func privacyParagraph(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ScreenshotSharedLinksView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var sharing = ScreenshotShareService.shared
    @State private var deletingID: String?
    @State private var showingDeleteError = false

    private var strings: ScreenshotFeatureStrings {
        FeatureStrings.screenshot(l10n.language)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(strings.sharedLinksTitle)
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(strings.done) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(18)

            Divider()

            if sharing.records.isEmpty {
                ContentUnavailableView(strings.sharedLinksEmpty,
                                       systemImage: "link.badge.plus")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(sharing.records) { record in
                    linkRow(record)
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 560, height: 360)
        .onAppear { sharing.refresh() }
        .alert(strings.deleteFailedHUD, isPresented: $showingDeleteError) {
            Button(strings.done, role: .cancel) {}
        }
    }

    private func linkRow(_ record: ScreenshotShareRecord) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "link")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.url.absoluteString)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                HStack(spacing: 4) {
                    Text(strings.expiresLabel)
                    Text(record.expiresAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                copy(record.url)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .screenshotSafeHelp(strings.copyLink)
            Button {
                NSWorkspace.shared.open(record.url)
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .screenshotSafeHelp(strings.openLink)
            Button(role: .destructive) {
                delete(record)
            } label: {
                if deletingID == record.id {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "trash")
                }
            }
            .buttonStyle(.borderless)
            .disabled(deletingID != nil)
            .screenshotSafeHelp(strings.deleteLink)
        }
        .padding(.vertical, 5)
    }

    private func copy(_ url: URL) {
        sharing.copy(url)
    }

    private func delete(_ record: ScreenshotShareRecord) {
        deletingID = record.id
        Task {
            do {
                try await sharing.delete(record)
                QuickToolHUD.show(icon: "link", message: strings.linkDeletedHUD)
            } catch {
                showingDeleteError = true
            }
            deletingID = nil
        }
    }
}

struct ScreenshotDefaultActionPicker: View {
    let strings: ScreenshotFeatureStrings
    @Binding var selection: String

    var body: some View {
        Picker(strings.defaultActionLabel, selection: $selection) {
            Self.options(strings: strings)
        }
    }

    @ViewBuilder
    static func options(strings: ScreenshotFeatureStrings) -> some View {
        Text(strings.defaultActionNone).tag(ScreenshotDefaultAction.none.rawValue)
        Text(strings.saveButton).tag(ScreenshotDefaultAction.save.rawValue)
        Text(strings.defaultActionSaveAndCopy).tag(ScreenshotDefaultAction.saveAndCopy.rawValue)
        Text(strings.copyButton).tag(ScreenshotDefaultAction.copy.rawValue)
        Text(strings.editButton).tag(ScreenshotDefaultAction.edit.rawValue)
    }
}
