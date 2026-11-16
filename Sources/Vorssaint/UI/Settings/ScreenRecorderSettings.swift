// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Settings for the screen recorder: how a recording starts, what it captures
/// and where the file lands. Everything a person rarely touches sits behind
/// one disclosure, so the page reads at a glance.
struct ScreenRecordingCaptureSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = ScreenRecorderService.shared
    @ObservedObject private var sharing = RecordingShareService.shared
    @AppStorage(DefaultsKey.recorderCountdown) private var countdown = 3
    @AppStorage(DefaultsKey.recorderQuality) private var qualityRaw =
        RecorderSupport.Quality.balanced.rawValue
    @AppStorage(DefaultsKey.recorderFrameRate) private var frameRate = 60
    @AppStorage(DefaultsKey.recorderSystemAudio) private var systemAudio = true
    @AppStorage(DefaultsKey.recorderMicrophone) private var microphone = false
    @AppStorage(DefaultsKey.recorderSaveFolder) private var saveFolder = ""
    @AppStorage(DefaultsKey.recorderOpenEditor) private var opensEditor = true
    @AppStorage(DefaultsKey.recorderAutomaticZoom) private var automaticZoom = true
    @AppStorage(DefaultsKey.recorderGIFSize) private var gifSizeRaw =
        RecorderSupport.GIFSize.medium.rawValue
    @AppStorage(DefaultsKey.recorderGIFFrameRate) private var gifFrameRate = 12
    @AppStorage(DefaultsKey.recorderSharingEnabled) private var sharingEnabled = true
    @State private var showsMoreOptions = false
    @State private var showingSharedLinks = false
    @State private var showingSharePrivacy = false

    private var strings: RecorderFeatureStrings {
        FeatureStrings.recorder(l10n.language)
    }

    private var shareStrings: RecorderShareStrings {
        FeatureStrings.recorderShare(l10n.language)
    }

    private var screenshotStrings: ScreenshotFeatureStrings {
        FeatureStrings.screenshot(l10n.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: strings.pageTitle) {
                HStack {
                    VorssaintActionChip(
                        title: service.isRecording ? strings.stopButton : strings.startButton,
                        symbol: service.isRecording ? "stop.circle" : "record.circle",
                        tone: .tools,
                        prominent: !service.isRecording,
                        destructive: service.isRecording
                    ) {
                        ScreenRecorderService.shared.toggle()
                    }
                    Spacer()
                }
                Text(service.isRecording
                     ? RecorderSupport.elapsedLabel(seconds: service.elapsedSeconds)
                     : strings.panelCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                if !permissions.screenRecording || !permissions.accessibility {
                    Divider()
                }
                if !permissions.screenRecording {
                    PermissionRow(kind: .screenRecording)
                }
                if !permissions.accessibility {
                    PermissionRow(kind: .accessibility)
                }
            }
            .settingsSectionAnchor(.screenRecorder, cornerRadius: 16)

            SettingsCard {
                SettingsChoiceRow(symbol: "timer", title: strings.countdownLabel, selection: $countdown) {
                    ForEach(ScreenshotSupport.allowedDelays, id: \.self) { seconds in
                        if seconds == 0 {
                            Text(strings.countdownOff).tag(0)
                        } else {
                            Text(String(format: strings.countdownSecondsFormat, seconds)).tag(seconds)
                        }
                    }
                }
                Divider()
                SettingsRow(symbol: "speaker.wave.2", title: strings.systemAudioToggle,
                            caption: strings.systemAudioCaption) {
                    Toggle(strings.systemAudioToggle, isOn: $systemAudio)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsRow(symbol: "mic", title: strings.microphoneToggle,
                            caption: strings.microphoneCaption) {
                    Toggle(strings.microphoneToggle, isOn: $microphone)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: microphone) { _, enabled in
                            if enabled, permissions.microphone == .undetermined {
                                permissions.requestMicrophone()
                            }
                        }
                }
                if microphone, permissions.microphone != .granted {
                    PermissionRow(kind: .microphone)
                        .padding(.leading, settingsRowTextInset)
                }
                Divider()
                SettingsRow(symbol: "film", title: strings.openEditorToggle,
                            caption: strings.openEditorCaption) {
                    Toggle(strings.openEditorToggle, isOn: $opensEditor)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsRow(symbol: "video", title: strings.automaticZoomToggle,
                            caption: strings.automaticZoomCaption) {
                    Toggle(strings.automaticZoomToggle, isOn: $automaticZoom)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            SettingsCard {
                folderRow
                Divider()
                DisclosureHeaderRow(isExpanded: $showsMoreOptions) {
                    Text(strings.moreOptions)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }
                if showsMoreOptions {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsMenuRow(symbol: "slider.horizontal.3", title: strings.qualityLabel,
                                        selection: $qualityRaw) {
                            Text(strings.qualitySmall).tag(RecorderSupport.Quality.small.rawValue)
                            Text(strings.qualityBalanced).tag(RecorderSupport.Quality.balanced.rawValue)
                            Text(strings.qualityHigh).tag(RecorderSupport.Quality.high.rawValue)
                        }
                        Text(strings.qualityCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, settingsRowTextInset)
                        SettingsChoiceRow(symbol: "gauge", title: strings.frameRateLabel, selection: $frameRate) {
                            ForEach(RecorderSupport.frameRates, id: \.self) { rate in
                                Text(String(format: strings.frameRateFormat, rate)).tag(rate)
                            }
                        }
                        SettingsChoiceRow(symbol: "photo", title: strings.gifSizeLabel, selection: $gifSizeRaw) {
                            Text(strings.gifSizeSmall).tag(RecorderSupport.GIFSize.small.rawValue)
                            Text(strings.gifSizeMedium).tag(RecorderSupport.GIFSize.medium.rawValue)
                            Text(strings.gifSizeLarge).tag(RecorderSupport.GIFSize.large.rawValue)
                        }
                        SettingsChoiceRow(symbol: "timer", title: strings.gifFrameRateLabel,
                                          selection: $gifFrameRate) {
                            ForEach(RecorderSupport.gifFrameRates, id: \.self) { rate in
                                Text(String(format: strings.frameRateFormat, rate)).tag(rate)
                            }
                        }
                    }
                    .disclosureIndent()
                }
            }

            SettingsCard(title: screenshotStrings.shareSectionTitle) {
                SettingsRow(symbol: "square.and.arrow.up", title: screenshotStrings.shareEnabledToggle,
                            caption: sharingEnabled ? shareStrings.caption : nil) {
                    Toggle(screenshotStrings.shareEnabledToggle, isOn: $sharingEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                Divider()
                Button {
                    showingSharePrivacy = true
                } label: {
                    SettingsRow(symbol: "hand.raised", title: screenshotStrings.sharePrivacyButton) {
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
                        SettingsRow(symbol: "link", title: screenshotStrings.sharedLinksTitle) {
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
        }
        .onAppear { sharing.refresh() }
        .sheet(isPresented: $showingSharedLinks) {
            RecorderSharedLinksView()
        }
        .sheet(isPresented: $showingSharePrivacy) {
            RecorderSharePrivacyView()
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

private struct RecorderSharePrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    private var strings: ScreenshotFeatureStrings {
        FeatureStrings.screenshot(l10n.language)
    }

    private var shareStrings: RecorderShareStrings {
        FeatureStrings.recorderShare(l10n.language)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(strings.sharePrivacyTitle, systemImage: "hand.raised")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(strings.done) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    privacyParagraph(symbol: "video", text: shareStrings.privacyData)
                    privacyParagraph(symbol: "externaldrive", text: shareStrings.privacyStorage)
                    privacyParagraph(symbol: "person.2", text: shareStrings.privacyAccess)
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

private struct RecorderSharedLinksView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var sharing = RecordingShareService.shared
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

    private func linkRow(_ record: RecordingShareRecord) -> some View {
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
                sharing.copy(record.url)
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

    private func delete(_ record: RecordingShareRecord) {
        deletingID = record.id
        Task { @MainActor in
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
