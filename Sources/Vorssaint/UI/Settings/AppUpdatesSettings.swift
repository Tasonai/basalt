// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct AppUpdatesSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var updates = AppUpdatesService.shared
    @AppStorage(DefaultsKey.appUpdatesCheckFrequency)
    private var frequencyRaw = AppUpdatesSupport.CheckFrequency.off.rawValue
    @AppStorage(DefaultsKey.appUpdatesNotify) private var notify = true
    @AppStorage(DefaultsKey.appUpdatesIncludeHomebrewApps) private var includeHomebrewApps = true
    @AppStorage(DefaultsKey.appUpdatesIncludeAppStore) private var includeAppStore = true
    @AppStorage(DefaultsKey.appUpdatesIncludeOnlineCatalog)
    private var includeOnlineCatalog = true
    @AppStorage(DefaultsKey.panelUtilityAppUpdates) private var showInPanel = true

    private var text: AppUpdateStrings { FeatureStrings.appUpdates(l10n.language) }

    var body: some View {
        SettingsPageContainer(title: text.pageTitle, subtitle: text.caption) {
            SettingsCard {
                AppUpdatesListView()
            }

            SettingsCard(title: text.frequencyLabel) {
                VorssaintSegmentedTabs(
                    selection: frequencyBinding,
                    options: [
                        .init(.off, title: text.frequencyOff),
                        .init(.daily, title: text.frequencyDaily),
                        .init(.weekly, title: text.frequencyWeekly),
                    ],
                    tone: .brand
                )
                if let next = updates.nextCheck {
                    Text(String(format: text.nextCheckFormat, nextCheckText(next)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                SettingsRow(symbol: "bell.badge", title: text.notifyToggle) {
                    Toggle(text.notifyToggle, isOn: $notify)
                        .labelsHidden()
                        .toggleStyle(VorssaintCompactSwitchStyle())
                        .disabled(AppUpdatesSupport.CheckFrequency.sanitized(frequencyRaw) == .off)
                        .onChange(of: notify) { _, value in
                            guard value else { return }
                            Notifier.requestPermission()
                        }
                }
            }

            SettingsCard(title: text.sourcesTitle) {
                SettingsRow(symbol: "shippingbox", title: text.includeHomebrewToggle) {
                    Toggle(text.includeHomebrewToggle, isOn: $includeHomebrewApps)
                        .labelsHidden()
                        .toggleStyle(VorssaintCompactSwitchStyle())
                        .disabled(includeHomebrewApps && enabledSourceCount == 1)
                        .onChange(of: includeHomebrewApps) { _, _ in
                            updates.sourceSelectionDidChange()
                        }
                }
                Divider()
                SettingsRow(symbol: "bag", title: text.includeStoreToggle,
                            caption: text.includeStoreCaption) {
                    Toggle(text.includeStoreToggle, isOn: $includeAppStore)
                        .labelsHidden()
                        .toggleStyle(VorssaintCompactSwitchStyle())
                        .disabled(includeAppStore && enabledSourceCount == 1)
                        .onChange(of: includeAppStore) { _, _ in
                            updates.sourceSelectionDidChange()
                        }
                }
                Divider()
                SettingsRow(symbol: "globe", title: text.includeOnlineToggle,
                            caption: text.includeOnlineCaption) {
                    Toggle(text.includeOnlineToggle, isOn: $includeOnlineCatalog)
                        .labelsHidden()
                        .toggleStyle(VorssaintCompactSwitchStyle())
                        .disabled(includeOnlineCatalog && enabledSourceCount == 1)
                        .onChange(of: includeOnlineCatalog) { _, _ in
                            updates.sourceSelectionDidChange()
                        }
                }
            }

            SettingsCard {
                SettingsRow(symbol: "menubar.rectangle", title: text.showInPanel) {
                    Toggle(text.showInPanel, isOn: $showInPanel)
                        .labelsHidden()
                        .toggleStyle(VorssaintCompactSwitchStyle())
                }
            }
        }
        .onAppear { updates.checkIfNeeded() }
    }

    private var frequencyBinding: Binding<AppUpdatesSupport.CheckFrequency> {
        Binding {
            AppUpdatesSupport.CheckFrequency.sanitized(frequencyRaw)
        } set: { frequency in
            frequencyRaw = frequency.rawValue
            AppUpdatesService.shared.syncWithPreferences()
            if frequency != .off, notify { Notifier.requestPermission() }
        }
    }

    private var enabledSourceCount: Int {
        [includeHomebrewApps, includeAppStore, includeOnlineCatalog].filter { $0 }.count
    }

    private func nextCheckText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = .current
        return formatter.string(from: date)
    }
}
