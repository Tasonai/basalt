// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Panel section with one brightness slider per adjustable display. Values
/// refresh whenever the section appears, so changes made with the keyboard,
/// in System Settings or on the monitor itself are picked up.
struct BrightnessSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = BrightnessService.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var ambientSync = AmbientLightSyncService.shared
    @ObservedObject private var xdrUpscale = XDRUpscaleOverlayController.shared
    @ObservedObject private var virtualDisplays = VirtualDisplayManager.shared
    @AppStorage(DefaultsKey.brightnessOSDEnabled) private var brightnessOSDEnabled = false
    @AppStorage(DefaultsKey.brightnessKeysEnabled) private var brightnessKeysEnabled = false
    @AppStorage(DefaultsKey.displayAmbientSyncEnabled) private var ambientSyncEnabled = false
    @State private var optionsExpanded = false
    var collapsible = true

    private var strings: BrightnessFeatureStrings { FeatureStrings.brightness(l10n.language) }
    private var wave4Strings: OverhaulWave4Strings { OverhaulStrings.wave4(l10n.language) }
    private var v2Strings: OverhaulV2Strings { OverhaulV2Strings.localized(l10n.language) }
    private var ddcDisplays: [BrightnessDisplay] { service.displays.filter { $0.isActive && $0.method == .ddc } }

    var body: some View {
        PanelSection(.brightness, title: strings.pageTitle, collapsible: collapsible) {
            VStack(alignment: .leading, spacing: 10) {
                if service.displays.isEmpty {
                    Text(strings.noDisplays)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(service.displays) { display in
                        row(display)
                    }
                }
                if let failure = service.displayControlFailure {
                    Text(displayControlFailureText(failure, strings: strings))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                }
                if service.keyboardLightEnabled != nil {
                    Divider()
                    keyboardLightRow
                }
                if service.brightnessOSDSupported {
                    Divider()
                    Toggle(strings.osdToggle, isOn: $brightnessOSDEnabled)
                        .font(.system(size: 10.5, weight: .medium))
                        .toggleStyle(VorssaintCompactSwitchStyle())
                        .controlSize(.mini)
                        .help(strings.osdCaption)
                        .onChange(of: brightnessOSDEnabled) { _, isOn in
                            if isOn { permissions.requestAccessibility() }
                            service.syncWithPreferences()
                        }
                }
                if AppFeature.extraBrightness.isAvailable {
                    Divider()
                    ExtraBrightnessPanelToggle()
                }
                Divider()
                optionsDisclosure
            }
            .panelCard()
            .onAppear {
                service.refresh()
                service.refreshKeyboardLight()
                if ambientSync.isEnabled != ambientSyncEnabled {
                    ambientSync.isEnabled = ambientSyncEnabled
                }
            }
        }
    }

    private var optionsDisclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    optionsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                        .rotationEffect(.degrees(optionsExpanded ? 90 : 0))
                    Text(l10n.s.keepAwakeOptions)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if optionsExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(strings.keysToggle, isOn: $brightnessKeysEnabled)
                        .onChange(of: brightnessKeysEnabled) { _, isOn in
                            if isOn { permissions.requestAccessibility() }
                            service.syncWithPreferences()
                        }
                    Text(strings.keysCaption)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if brightnessKeysEnabled, !permissions.accessibility {
                        Button {
                            permissions.openAccessibilitySettings()
                        } label: {
                            Label(l10n.s.permissionOpenSettings, systemImage: "hand.raised")
                        }
                        .buttonStyle(.link)
                    }
                    DisplayBrightnessShortcutControls()
                    Divider()
                    Toggle(wave4Strings.ambientSyncLabel, isOn: $ambientSyncEnabled)
                        .onChange(of: ambientSyncEnabled) { _, on in
                            AmbientLightSyncService.shared.isEnabled = on
                            service.syncWithPreferences()
                        }
                    if ambientSyncEnabled {
                        HStack(spacing: 6) {
                            Image(systemName: ambientSync.hasAmbientSensor ? "sun.max.circle.fill" : "sun.min")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(v2Strings.alsPollingActive)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 4)
                            Text("\(Int(ambientSync.lastLux.rounded())) lx")
                                .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        VorssaintDetentSlider(
                            value: ambientBiasBinding,
                            range: -0.35...0.35,
                            detent: 0,
                            tone: .energyDisplay,
                            icon: "sun.and.horizon",
                            formattedValue: String(format: "%+.0f%%", locale: Locale.current, ambientSync.userBias * 100)
                        )
                    }
                    Divider()
                    Toggle(v2Strings.xdrBoostLabel, isOn: $xdrUpscale.isEnabled)
                        .disabled(!xdrUpscale.isXDRCapable && !xdrUpscale.isEnabled)
                        .help(v2Strings.xdrBoostCaption)
                    Text(v2Strings.xdrBoostCaption)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if xdrUpscale.isEnabled {
                        VorssaintDetentSlider(
                            value: $xdrUpscale.boostAmount,
                            range: XDRUpscaleOverlayController.minBoostAmount...XDRUpscaleOverlayController.maxBoostAmount,
                            detent: 1.5,
                            tone: .energyDisplay,
                            icon: "sun.max.fill",
                            title: l10n.s.extraBrightnessLevelLabel,
                            formattedValue: String(format: "%.2fx", locale: Locale.current, xdrUpscale.boostAmount)
                        )
                    }
                    if !ddcDisplays.isEmpty {
                        Divider()
                        ForEach(ddcDisplays) { display in
                            ddcControlsRow(for: display)
                        }
                    }
                    Divider()
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.badge.plus")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(wave4Strings.virtualHiDPILabel)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        if !virtualDisplays.activePresetIDs.isEmpty {
                            VorssaintActionChip(
                                title: v2Strings.virtualDisplayDestroy,
                                symbol: "xmark.circle",
                                tone: .energyDisplay,
                                destructive: true
                            ) {
                                virtualDisplays.deactivateAll()
                            }
                        }
                    }
                    ForEach(VirtualDisplayManager.presets) { preset in
                        Toggle(isOn: virtualPresetBinding(preset)) {
                            HStack(spacing: 6) {
                                Text(preset.title)
                                    .font(.system(size: 11, weight: .medium))
                                if let displayID = virtualDisplays.virtualDisplayIDs[preset.id] {
                                    Text("#\(displayID)")
                                        .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .help(virtualDisplays.activePresetIDs.contains(preset.id)
                              ? v2Strings.virtualDisplayDestroy
                              : v2Strings.virtualDisplayCreate)
                    }
                }
                .font(.system(size: 11.5, weight: .medium))
                .toggleStyle(VorssaintPillToggleStyle(tone: .energyDisplay))
                .controlSize(.small)
                .padding(.leading, 19)
            }
        }
    }

    private func row(_ display: BrightnessDisplay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(display.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if display.isActive, display.method != nil {
                    Text("\(Int((display.brightness * 100).rounded()))%")
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if !display.isActive {
                    Text(strings.displayOff)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                DisplayPowerButton(display: display, compact: true)
            }
            if display.isActive, display.method != nil {
                VorssaintDetentSlider(value: brightnessBinding(display), in: 0...1, tone: .energyDisplay)
                    .disabled(service.isDisplayPending(display.id))
                    .accessibilityLabel(display.name)
            }
            SoftwareDimmingButton(display: display, compact: true)
        }
    }

    /// Sits with the display sliders because it is the same control. The
    /// Quick toggles switch stays the place to flip it off and back on, and
    /// the slider reaches 0, so the row carries no switch of its own.
    private var keyboardLightRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "keyboard")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(strings.keyboardLight)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(Int(((service.keyboardLightLevel ?? 0) * 100).rounded()))%")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            VorssaintDetentSlider(value: keyboardLightBinding,
                                  in: 0...1,
                                  tone: .energyDisplay,
                                  onEditingChanged: service.keyboardLightDragChanged)
                .accessibilityLabel(strings.keyboardLight)
        }
    }

    private var keyboardLightBinding: Binding<Double> {
        Binding(get: { Double(service.keyboardLightLevel ?? 0) },
                set: { service.setKeyboardLightLevel(Float($0)) })
    }

    private func brightnessBinding(_ display: BrightnessDisplay) -> Binding<Double> {
        Binding(get: { display.brightness },
                set: { service.setBrightness($0, for: display.id,
                                             showOSD: brightnessOSDEnabled) })
    }

    @ViewBuilder
    private func ddcControlsRow(for display: BrightnessDisplay) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if ddcDisplays.count > 1 {
                HStack(spacing: 5) {
                    Image(systemName: "display")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(display.name)
                        .font(.system(size: 10.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            VorssaintDetentSlider(
                value: ddcContrastBinding(display.id),
                range: 0...100,
                detent: 75,
                tone: .energyDisplay,
                icon: "circle.lefthalf.filled",
                title: wave4Strings.hardwareContrastLabel,
                formattedValue: "\(Int(service.ddcContrast(for: display.id).rounded()))%"
            )
            HStack(alignment: .bottom, spacing: 8) {
                VorssaintDetentSlider(
                    value: ddcVolumeBinding(display.id),
                    range: 0...100,
                    detent: 50,
                    tone: .energyDisplay,
                    icon: service.isDDCAudioMuted(for: display.id) ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    title: wave4Strings.hardwareVolumeLabel,
                    formattedValue: "\(Int(service.ddcVolume(for: display.id).rounded()))%"
                )
                .disabled(service.isDDCAudioMuted(for: display.id))
                Button {
                    VorssaintHaptics.generic()
                    service.setDisplayAudioMuted(!service.isDDCAudioMuted(for: display.id), for: display.id)
                } label: {
                    Image(systemName: service.isDDCAudioMuted(for: display.id) ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(service.isDDCAudioMuted(for: display.id) ? .red : .secondary)
                        .frame(width: 24, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(display.name): \(wave4Strings.hardwareVolumeLabel)")
            }
            HStack(spacing: 8) {
                Text(wave4Strings.inputSourceLabel)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: ddcInputBinding(display.id)) {
                    ForEach(DisplayInputSourcePreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.mini)
                .fixedSize()
            }
        }
    }

    private var ambientBiasBinding: Binding<Double> {
        Binding(
            get: { ambientSync.userBias },
            set: { newBias in
                ambientSync.userBias = newBias
                ambientSync.update(lux: ambientSync.lastLux)
            }
        )
    }

    private func ddcContrastBinding(_ id: CGDirectDisplayID) -> Binding<Double> {
        Binding(
            get: { service.ddcContrast(for: id) },
            set: { service.setDisplayContrast($0, for: id) }
        )
    }

    private func ddcVolumeBinding(_ id: CGDirectDisplayID) -> Binding<Double> {
        Binding(
            get: { service.ddcVolume(for: id) },
            set: { service.setDisplayAudioVolume($0, for: id) }
        )
    }

    private func ddcInputBinding(_ id: CGDirectDisplayID) -> Binding<DisplayInputSourcePreset> {
        Binding(
            get: { service.ddcInputSource(for: id) },
            set: { service.setDisplayInputSource($0, for: id) }
        )
    }

    private func virtualPresetBinding(_ preset: VirtualDisplayManager.ScaledPreset) -> Binding<Bool> {
        Binding(
            get: { virtualDisplays.activePresetIDs.contains(preset.id) },
            set: { enabled in
                if enabled {
                    virtualDisplays.activatePreset(preset)
                } else {
                    virtualDisplays.deactivatePreset(preset)
                }
            }
        )
    }
}

private struct ExtraBrightnessPanelToggle: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = ExtraBrightnessService.shared
    @AppStorage(DefaultsKey.extraBrightnessEnabled) private var enabled = false

    var body: some View {
        Toggle(l10n.s.extraBrightnessName, isOn: $enabled)
            .font(.system(size: 10.5, weight: .medium))
            .toggleStyle(VorssaintCompactSwitchStyle())
            .controlSize(.mini)
            .disabled(!service.supported && !enabled)
            .help(service.supported ? l10n.s.extraBrightnessCaption : l10n.s.extraBrightnessUnsupported)
            .onChange(of: enabled) { _, _ in service.syncWithPreferences() }
            .onAppear { service.syncWithPreferences() }
    }
}

/// Shared routing choice, on every surface that shows the display rows: the
/// slider is just as dead on the Energy page as in the panel, so the way out
/// has to be there too.
///
/// On readable DDC displays, the choice extends the slider below the panel's
/// hardware minimum and is offered in Settings. On write-only DDC paths, it
/// keeps the existing fallback to software control on both surfaces (issue
/// #1589). Either choice stays visible until cleared.
struct SoftwareDimmingButton: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = BrightnessService.shared
    let display: BrightnessDisplay
    var compact = false

    private var strings: BrightnessFeatureStrings { FeatureStrings.brightness(l10n.language) }
    private var extendedChosen: Bool { service.extendedDimmingPreferred.contains(display.id) }
    private var softwareChosen: Bool { service.softwareDimmingPreferred.contains(display.id) }
    private var chosen: Bool { extendedChosen || softwareChosen }
    private var usesExtendedDimming: Bool {
        !softwareChosen && (extendedChosen || (display.method == .ddc && display.readable))
    }

    private var offered: Bool {
        guard display.isActive, !display.isBuiltIn, display.canChooseDimming else { return false }
        if chosen { return true }
        guard display.method == .ddc else { return false }
        // The panel keeps only the write-only way out; extra dimming is
        // offered in Settings and joins the panel once it is on.
        return !(compact && display.readable)
    }

    var body: some View {
        if offered {
            Button {
                if usesExtendedDimming {
                    service.setExtendedDimmingPreferred(!extendedChosen, for: display.id)
                } else {
                    service.setSoftwareDimmingPreferred(!softwareChosen, for: display.id)
                }
            } label: {
                HStack(spacing: compact ? 4 : 5) {
                    Image(systemName: chosen ? "checkmark.circle.fill" : "circle.lefthalf.filled")
                        .font(.system(size: compact ? 9.5 : 11, weight: .semibold))
                    Text(usesExtendedDimming ? strings.extendedDimming : strings.softwareDimming)
                        .font(.system(size: compact ? 10 : 12, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(chosen ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(service.isDisplayPending(display.id))
            .accessibilityLabel("\(display.name): \(usesExtendedDimming ? strings.extendedDimming : strings.softwareDimming)")
        }
    }
}

/// Shared power affordance used by Settings and the menu bar panel. It stays
/// icon-only in the row, with a localized tooltip and accessibility label.
struct DisplayPowerButton: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = BrightnessService.shared
    let display: BrightnessDisplay
    var compact = false

    private var strings: BrightnessFeatureStrings { FeatureStrings.brightness(l10n.language) }
    private var pending: Bool { service.isDisplayPending(display.id) }
    private var enabled: Bool { service.canToggleDisplay(display) }

    private var label: String {
        if !service.displaySwitchingAvailable { return strings.switchUnavailable }
        if display.isActive, !enabled { return strings.lastDisplayCaption }
        return display.isActive ? strings.turnOffDisplay : strings.turnOnDisplay
    }

    var body: some View {
        Group {
            if pending {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: compact ? 16 : 20, height: 18)
                    .accessibilityLabel(label)
            } else {
                Button {
                    service.toggleDisplay(display)
                } label: {
                    Image(systemName: display.isActive ? "power" : "power.circle.fill")
                        .font(.system(size: compact ? 10.5 : 12, weight: .semibold))
                        .foregroundStyle(display.isActive ? AnyShapeStyle(.secondary)
                                                         : AnyShapeStyle(.green))
                        .frame(width: compact ? 16 : 20, height: 18)
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
                .help(label)
                .accessibilityLabel(label)
            }
        }
    }
}

func displayControlFailureText(_ failure: BrightnessService.DisplayControlFailure,
                               strings: BrightnessFeatureStrings) -> String {
    switch failure {
    case .unavailable: return strings.switchUnavailable
    case .lastActive: return strings.lastDisplayCaption
    case .failed: return strings.switchFailed
    case .closedLid: return strings.openLidToEnable
    }
}
