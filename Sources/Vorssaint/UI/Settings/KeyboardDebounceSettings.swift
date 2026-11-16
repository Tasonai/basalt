// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct KeyboardDebounceSettings: View {
    private struct KeyWindowRow: Identifiable {
        let keyCode: Int64
        let window: Int
        var id: Int64 { keyCode }
    }

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var debounce = KeyboardDebounceService.shared
    @AppStorage(DefaultsKey.keyboardDebounceEnabled) private var enabled = false
    @AppStorage(DefaultsKey.keyboardDebounceWindowMs) private var globalWindow = Defaults.defaultKeyboardDebounceWindowMs
    @AppStorage(DefaultsKey.keyboardDebounceKeyWindows) private var keyWindowsRaw = ""
    @State private var selectedKeyCode: Int64?
    @State private var selectedWindow = Defaults.defaultKeyboardDebounceWindowMs

    var body: some View {
        SettingsPageContainer(title: l10n.s.keyDebounceName, subtitle: l10n.s.keyDebounceCaption) {
            SettingsCard {
                SettingsRow(symbol: "keyboard", title: l10n.s.keyDebounceEnable) {
                    Toggle(l10n.s.keyDebounceEnable, isOn: $enabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: enabled) { _, value in
                            KeyboardDebounceService.shared.syncWithPreferences()
                            guard value, !permissions.accessibility else { return }
                            permissions.requestAccessibility()
                            permissions.openAccessibilitySettings()
                        }
                }
                if enabled, debounce.isRunning {
                    Label(l10n.s.keyDebounceActiveNow, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.leading, settingsRowTextInset)
                }
                Divider()
                SettingsRow(symbol: "timer", title: l10n.s.keyDebounceGlobalWindow) {
                    HStack(spacing: 8) {
                        Text("\(globalWindow) ms")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Stepper("", value: globalWindowBinding,
                                in: Defaults.allowedKeyboardDebounceWindowRange,
                                step: Defaults.keyboardDebounceWindowStep)
                            .labelsHidden()
                    }
                }
                .disabled(!enabled)
            }

            SettingsCard(title: l10n.s.keyDebouncePerKeySection) {
                Text(l10n.s.keyDebouncePerKeyCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Picker(l10n.s.keyDebounceKeyLabel, selection: $selectedKeyCode) {
                        Text(l10n.s.keyDebounceKeyLabel).tag(Int64?.none)
                        ForEach(KeyboardDebounceKeyCatalog.common) { key in
                            Text(key.label).tag(Optional(key.code))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(minWidth: 160)
                    Stepper(value: $selectedWindow,
                            in: Defaults.allowedKeyboardDebounceWindowRange,
                            step: Defaults.keyboardDebounceWindowStep) {
                        Text("\(selectedWindow) ms")
                            .monospacedDigit()
                    }
                    Button(l10n.s.keyDebounceAddKey) {
                        if let selectedKeyCode {
                            setWindow(selectedWindow, for: selectedKeyCode)
                        }
                    }
                    .disabled(!enabled || selectedKeyCode == nil)
                }

                if keyWindows.isEmpty {
                    Text(l10n.s.keyDebounceNoOverrides)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Divider()
                    ForEach(keyWindows) { row in
                        if row.id != keyWindows.first?.id {
                            Divider()
                        }
                        HStack(spacing: 8) {
                            Text(KeyboardDebounceKeyCatalog.label(for: row.keyCode))
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 70, alignment: .leading)
                            Spacer()
                            Stepper(value: binding(for: row.keyCode),
                                    in: Defaults.allowedKeyboardDebounceWindowRange,
                                    step: Defaults.keyboardDebounceWindowStep) {
                                Text("\(row.window) ms")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Button {
                                removeWindow(for: row.keyCode)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help(l10n.s.keyDebounceRemoveKey)
                        }
                    }
                }
            }
            .disabled(!enabled)

            if enabled, !permissions.accessibility {
                SettingsCard(title: l10n.s.permissionRequired) {
                    PermissionRow(kind: .accessibility)
                }
            }
        }
        .onAppear {
            globalWindow = Defaults.sanitizedKeyboardDebounceWindow(globalWindow)
            selectedWindow = Defaults.sanitizedKeyboardDebounceWindow(selectedWindow)
        }
    }

    private var globalWindowBinding: Binding<Int> {
        Binding {
            Defaults.sanitizedKeyboardDebounceWindow(globalWindow)
        } set: { value in
            globalWindow = Defaults.sanitizedKeyboardDebounceWindow(value)
            KeyboardDebounceService.shared.syncWithPreferences()
        }
    }

    private var keyWindows: [KeyWindowRow] {
        KeyboardDebounceConfig.decodeKeyWindows(keyWindowsRaw)
            .map { KeyWindowRow(keyCode: $0.key, window: $0.value) }
            .sorted {
                KeyboardDebounceKeyCatalog.label(for: $0.keyCode) < KeyboardDebounceKeyCatalog.label(for: $1.keyCode)
            }
    }

    private func binding(for keyCode: Int64) -> Binding<Int> {
        Binding {
            KeyboardDebounceConfig.decodeKeyWindows(keyWindowsRaw)[keyCode]
                ?? Defaults.defaultKeyboardDebounceWindowMs
        } set: { value in
            setWindow(value, for: keyCode)
        }
    }

    private func setWindow(_ value: Int, for keyCode: Int64) {
        var windows = KeyboardDebounceConfig.decodeKeyWindows(keyWindowsRaw)
        windows[keyCode] = Defaults.sanitizedKeyboardDebounceWindow(value)
        keyWindowsRaw = KeyboardDebounceConfig.encodeKeyWindows(windows)
        KeyboardDebounceService.shared.syncWithPreferences()
    }

    private func removeWindow(for keyCode: Int64) {
        var windows = KeyboardDebounceConfig.decodeKeyWindows(keyWindowsRaw)
        windows.removeValue(forKey: keyCode)
        keyWindowsRaw = KeyboardDebounceConfig.encodeKeyWindows(windows)
        KeyboardDebounceService.shared.syncWithPreferences()
    }
}
