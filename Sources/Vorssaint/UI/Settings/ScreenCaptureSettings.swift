// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// One Settings destination for every tool that starts from the screen. The
/// tool picker at the top changes the feature-specific options shown
/// below it, and the top section also carries the selected tool's own
/// shortcut where the old shared shortcut lived.
struct ScreenCaptureSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var router = SettingsRouter.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @State private var selectedTool = ScreenCaptureTool.screenshot

    private var strings: ScreenshotFeatureStrings {
        FeatureStrings.screenshot(l10n.language)
    }

    private var availableTools: [ScreenCaptureTool] {
        ScreenCaptureTool.available()
    }

    private var currentTool: ScreenCaptureTool {
        availableTools.contains(selectedTool) ? selectedTool : availableTools.first ?? .screenshot
    }

    var body: some View {
        SettingsPageContainer(title: strings.screenCaptureTitle) {
            if !availableTools.isEmpty {
                SettingsCard {
                    if availableTools.count > 1 {
                        ScreenCaptureToolPicker(tools: availableTools,
                                                strings: l10n.s,
                                                language: l10n.language,
                                                selection: toolSelection)
                        Divider()
                    }
                    ToolShortcutRows(tool: currentTool, keys: currentTool.dedicatedShortcut)
                        .id(currentTool)
                    if AppFeature.screenshot.isAvailable || AppFeature.screenRecorder.isAvailable {
                        Divider()
                        RecentCapturesShortcutRows()
                    }
                }
            }

            selectedSettings
        }
        .onAppear { reconcileSelection(withDestination: true) }
        .onChange(of: features.revision) { _, _ in
            reconcileSelection(withDestination: false)
        }
        .onChange(of: router.requestID) { _, _ in
            reconcileSelection(withDestination: true)
        }
    }

    private var toolSelection: Binding<ScreenCaptureTool> {
        Binding(get: { currentTool }, set: { tool in
            guard availableTools.contains(tool), tool != currentTool else { return }
            selectedTool = tool
            router.request(tool.feature.settingsDestination, sidebarFeature: tool.feature)
        })
    }

    @ViewBuilder
    private var selectedSettings: some View {
        if availableTools.isEmpty {
            EmptyView()
        } else {
            switch currentTool {
            case .screenshot:
                ScreenshotCaptureSettings()
            case .recording:
                ScreenRecordingCaptureSettings()
            case .text:
                ScreenTextCaptureSettings()
            case .color:
                ColorCaptureSettings()
            }
        }
    }

    private func reconcileSelection(withDestination: Bool) {
        if withDestination {
            if let anchor = router.destination.sectionAnchor,
               let requestedTool = anchor.screenCaptureTool,
               availableTools.contains(requestedTool) {
                selectedTool = requestedTool
            } else if router.destination.sectionAnchor == nil,
                      let first = availableTools.first {
                selectedTool = first
            }
            return
        }
        if !availableTools.contains(selectedTool), let first = availableTools.first {
            selectedTool = first
        }
    }
}

/// Capture history belongs to screenshots and recordings together, so its
/// shortcut stays visible whichever of those tools is selected.
private struct RecentCapturesShortcutRows: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = RecentCaptureService.shared
    @AppStorage(DefaultsKey.recentCapturesShortcutEnabled) private var enabled = false

    var body: some View {
        let role = GlobalShortcutRole.recentCaptures
        VStack(alignment: .leading, spacing: 10) {
            Toggle(role.title(l10n.s), isOn: $enabled)
                .onChange(of: enabled) { _, _ in
                    service.syncWithPreferences()
                }
            ShortcutPreferenceRow(role: role, isEnabled: enabled) {
                service.syncWithPreferences()
            }
            if enabled, service.shortcutRegistrationFailed {
                Text(l10n.s.shortcutUnavailable)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private extension SettingsSectionAnchor {
    var screenCaptureTool: ScreenCaptureTool? {
        switch self {
        case .screenshot: return .screenshot
        case .screenRecorder: return .recording
        case .screenOCR: return .text
        case .colorPicker: return .color
        default: return nil
        }
    }
}

/// The shortcut that opens the chooser straight on one tool, shown in the
/// page's top section under the tool's own name while that tool is selected.
private struct ToolShortcutRows: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = ScreenCaptureService.shared
    @AppStorage private var enabled: Bool
    @AppStorage private var showsCaptureMenu: Bool

    private let tool: ScreenCaptureTool
    private let keys: ScreenCaptureTool.DedicatedShortcut

    init(tool: ScreenCaptureTool, keys: ScreenCaptureTool.DedicatedShortcut) {
        self.tool = tool
        self.keys = keys
        _enabled = AppStorage(wrappedValue: false, keys.enabledKey)
        _showsCaptureMenu = AppStorage(wrappedValue: true, tool.showCaptureMenuOnShortcutKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(keys.role.title(l10n.s), isOn: $enabled)
                .onChange(of: enabled) { _, _ in
                    service.syncWithPreferences()
                }
            ShortcutPreferenceRow(role: keys.role, isEnabled: enabled) {
                service.syncWithPreferences()
            }
            Toggle(FeatureStrings.screenshot(l10n.language).showCaptureMenuOnShortcut,
                   isOn: $showsCaptureMenu)
                .disabled(!enabled)
            if enabled, service.toolShortcutRegistrationFailures.contains(tool) {
                Text(l10n.s.shortcutUnavailable)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ScreenTextCaptureSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.screenOCRRemoveLineBreaks) private var removesLineBreaks = false
    @AppStorage(DefaultsKey.screenOCRDetectQRCodes) private var detectsQRCodes = true

    var body: some View {
        SettingsCard(title: l10n.s.ocrName) {
            HStack {
                VorssaintActionChip(title: l10n.s.ocrName, symbol: "text.viewfinder",
                                    tone: .tools, prominent: true) {
                    ScreenTextService.shared.capture()
                }
                Spacer()
            }
            Text(l10n.s.ocrCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            SettingsRow(symbol: "text.alignleft", title: l10n.s.ocrRemoveLineBreaksToggle,
                        caption: l10n.s.ocrRemoveLineBreaksCaption) {
                Toggle(l10n.s.ocrRemoveLineBreaksToggle, isOn: $removesLineBreaks)
                    .labelsHidden()
                    .toggleStyle(VorssaintCompactSwitchStyle())
            }
            SettingsRow(symbol: "qrcode", title: l10n.s.ocrQRToggle,
                        caption: l10n.s.ocrQRCaption) {
                Toggle(l10n.s.ocrQRToggle, isOn: $detectsQRCodes)
                    .labelsHidden()
                    .toggleStyle(VorssaintCompactSwitchStyle())
            }
            if !permissions.screenRecording {
                Divider()
                PermissionRow(kind: .screenRecording)
            }
        }
        .settingsSectionAnchor(.screenOCR, cornerRadius: 16)
    }
}

private struct ColorCaptureSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.colorPickerFormat) private var format = "hex"
    @AppStorage(DefaultsKey.colorPickerBareHex) private var usesBareHex = false

    var body: some View {
        SettingsCard(title: l10n.s.colorPickerName) {
            SettingsRow(symbol: "eyedropper", title: l10n.s.colorPickerName,
                        caption: l10n.s.colorPickerCaption) {
                VorssaintActionChip(title: l10n.s.colorPickerPickNow, symbol: "eyedropper",
                                    tone: .tools, prominent: true) {
                    ColorSamplerService.shared.pick()
                }
            }
            Divider()
            SettingsChoiceRow(symbol: "paintpalette", title: l10n.s.colorPickerFormatLabel,
                              selection: $format) {
                ForEach(ColorCopyFormat.allCases) { format in
                    Text(format.label).tag(format.rawValue)
                }
            }
            if format == ColorCopyFormat.hex.rawValue {
                SettingsRow(symbol: "number", title: l10n.s.colorPickerBareHexToggle) {
                    Toggle(l10n.s.colorPickerBareHexToggle, isOn: $usesBareHex)
                        .labelsHidden()
                        .toggleStyle(VorssaintCompactSwitchStyle())
                }
            }
        }
        .settingsSectionAnchor(.colorPicker, cornerRadius: 16)
    }
}
