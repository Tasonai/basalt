// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct ShelfSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var shelf = ShelfService.shared
    @AppStorage(DefaultsKey.shelfEnabled) private var enabled = false
    @AppStorage(DefaultsKey.shelfShortcutEnabled) private var shortcutEnabled = true
    @AppStorage(DefaultsKey.shelfShortcutAddsFinderSelection) private var shortcutAddsFinderSelection = false
    @AppStorage(DefaultsKey.shelfShakeToOpen) private var shake = true
    @AppStorage(DefaultsKey.shelfDropZoneEnabled) private var dropZone = true
    @AppStorage(DefaultsKey.shelfDockPlacement) private var dockPlacement = ShelfDockPlacement.menuBar.rawValue
    @AppStorage(DefaultsKey.notchEnabled) private var islandEnabled = false
    @AppStorage(DefaultsKey.shelfEdgeDragEnabled) private var edgeDrag = false
    @AppStorage(DefaultsKey.shelfCloseAfterDrop) private var closeAfterDrop = false
    @AppStorage(DefaultsKey.shelfRemoveAfterDrop) private var removeAfterDrop = true
    @AppStorage(DefaultsKey.shelfClearOnClose) private var clearOnClose = false
    @AppStorage(DefaultsKey.shelfCatchSystemScreenshots) private var catchSystemScreenshots = true
    @AppStorage(DefaultsKey.notchShelf) private var opensInIsland = true
    @State private var showingAppPicker = false
    @State private var islandShowsFiles = NotchSupport.showsFiles()

    var body: some View {
        SettingsPageContainer(title: l10n.s.shelfTitle) {
            SettingsCard {
                SettingsRow(symbol: "tray.full", title: l10n.s.shelfEnable,
                            caption: l10n.s.shelfEnableCaption) {
                    Toggle(l10n.s.shelfEnable, isOn: $enabled)
                        .labelsHidden()
                        .toggleStyle(VorssaintCompactSwitchStyle())
                        .onChange(of: enabled) { _, _ in
                            ShelfService.shared.syncWithPreferences()
                        }
                }
                // Adding the Finder selection asks to control Finder, so the
                // promise only holds while that option is off.
                if !(shortcutEnabled && shortcutAddsFinderSelection) {
                    Label(l10n.s.shelfNoPermission, systemImage: "checkmark.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, settingsRowTextInset)
                }
            }

            SettingsCard(title: l10n.s.shelfHowTitle) {
                bullet("1", l10n.s.shelfStep1)
                bullet("2", l10n.s.shelfStep2)
                bullet("3", l10n.s.shelfStep3)
            }

            if enabled {
                // Mirrors the island page's Files choice, which only matters while the island shows Files.
                if islandShowsFiles {
                    SettingsCard {
                        SettingsChoiceRow(symbol: "macbook",
                                          title: FeatureStrings.notchEditor(l10n.language).destinations,
                                          selection: $opensInIsland) {
                            Text(FeatureStrings.notch(l10n.language).title).tag(true)
                            Text(FeatureStrings.notchEditor(l10n.language).separate).tag(false)
                        }
                    }
                }

                SettingsCard {
                    SettingsRow(symbol: "keyboard", title: l10n.s.shelfShortcutToggle) {
                        Toggle(l10n.s.shelfShortcutToggle, isOn: $shortcutEnabled)
                            .labelsHidden()
                            .toggleStyle(VorssaintCompactSwitchStyle())
                            .onChange(of: shortcutEnabled) { _, _ in
                                ShelfService.shared.syncHotkey()
                            }
                    }
                    ShortcutPreferenceRow(role: .shelf, isEnabled: shortcutEnabled) {
                        ShelfService.shared.syncHotkey()
                    }
                    .padding(.leading, settingsRowTextInset)
                    if shortcutEnabled, shelf.hotkeyRegistrationFailed {
                        Text(l10n.s.shortcutUnavailable)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, settingsRowTextInset)
                    }
                    if shortcutEnabled {
                        SettingsRow(symbol: "doc.on.doc", title: l10n.s.shelfShortcutFinderSelection,
                                    caption: l10n.s.shelfShortcutFinderSelectionCaption) {
                            Toggle(l10n.s.shelfShortcutFinderSelection, isOn: $shortcutAddsFinderSelection)
                                .labelsHidden()
                                .toggleStyle(VorssaintCompactSwitchStyle())
                        }
                        .padding(.leading, settingsRowTextInset)
                        if shortcutAddsFinderSelection {
                            Text(l10n.s.cutPasteAutomationNote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, settingsRowTextInset * 2)
                        }
                    }
                    Divider()
                    SettingsRow(symbol: "hand.draw", title: l10n.s.shelfShakeToggle,
                                caption: l10n.s.shelfShakeCaption) {
                        Toggle(l10n.s.shelfShakeToggle, isOn: $shake)
                            .labelsHidden()
                            .toggleStyle(VorssaintCompactSwitchStyle())
                            .onChange(of: shake) { _, _ in
                                ShelfService.shared.syncDragMonitor()
                            }
                    }
                    SettingsRow(symbol: "tray.and.arrow.down", title: l10n.s.shelfDropZoneToggle,
                                caption: dockPlacement == ShelfDockPlacement.topCenter.rawValue && !islandOn
                                    ? l10n.s.shelfDropZoneCaptionTopCenter : l10n.s.shelfDropZoneCaption) {
                        Toggle(l10n.s.shelfDropZoneToggle, isOn: $dropZone)
                            .labelsHidden()
                            .toggleStyle(VorssaintCompactSwitchStyle())
                            .onChange(of: dropZone) { _, _ in
                                ShelfService.shared.syncDragMonitor()
                            }
                    }
                    if dropZone {
                        SettingsMenuRow(symbol: "menubar.rectangle", title: l10n.s.shelfDockPlacement,
                                        selection: $dockPlacement) {
                            Text(l10n.s.shelfDockMenuBar).tag(ShelfDockPlacement.menuBar.rawValue)
                            Text(l10n.s.shelfDockTopCenter).tag(ShelfDockPlacement.topCenter.rawValue)
                        }
                        .disabled(islandOn)
                        .onChange(of: dockPlacement) { _, _ in
                            ShelfService.shared.syncDockedShelf()
                        }
                        .padding(.leading, settingsRowTextInset)
                        if islandOn {
                            Text(l10n.s.shelfDockIslandNote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, settingsRowTextInset)
                        }
                    }
                    SettingsRow(symbol: "arrow.right.to.line", title: l10n.s.shelfEdgeToggle,
                                caption: l10n.s.shelfEdgeCaption) {
                        Toggle(l10n.s.shelfEdgeToggle, isOn: $edgeDrag)
                            .labelsHidden()
                            .toggleStyle(VorssaintCompactSwitchStyle())
                            .onChange(of: edgeDrag) { _, _ in
                                ShelfService.shared.syncDragMonitor()
                            }
                    }
                    Divider()
                    HStack {
                        VorssaintActionChip(title: l10n.s.shelfOpenNow, symbol: "tray.and.arrow.down",
                                            tone: .clipboardFiles, prominent: true) {
                            ShelfService.shared.summon()
                        }
                        Spacer()
                    }
                }

                SettingsCard(title: l10n.s.shelfBehaviorTitle) {
                    SettingsRow(symbol: "xmark.rectangle", title: l10n.s.shelfCloseAfterDrop,
                                caption: l10n.s.shelfCloseAfterDropCaption) {
                        Toggle(l10n.s.shelfCloseAfterDrop, isOn: $closeAfterDrop)
                            .labelsHidden()
                            .toggleStyle(VorssaintCompactSwitchStyle())
                    }
                    SettingsRow(symbol: "trash", title: l10n.s.shelfRemoveAfterDrop,
                                caption: l10n.s.shelfRemoveAfterDropCaption) {
                        Toggle(l10n.s.shelfRemoveAfterDrop, isOn: $removeAfterDrop)
                            .labelsHidden()
                            .toggleStyle(VorssaintCompactSwitchStyle())
                    }
                    SettingsRow(symbol: "sparkles", title: l10n.s.shelfClearOnClose,
                                caption: l10n.s.shelfClearOnCloseCaption) {
                        Toggle(l10n.s.shelfClearOnClose, isOn: $clearOnClose)
                            .labelsHidden()
                            .toggleStyle(VorssaintCompactSwitchStyle())
                    }
                    SettingsRow(symbol: "camera.viewfinder",
                                title: l10n.language == .ru ? "Перехватывать системные скриншоты" : "Catch system screenshots",
                                caption: l10n.language == .ru
                                    ? "Снимки экрана через ⌘⇧3 и ⌘⇧4 сразу появляются на полке."
                                    : "Screenshots taken via ⌘⇧3 and ⌘⇧4 automatically appear on the shelf.") {
                        Toggle(l10n.language == .ru ? "Перехватывать системные скриншоты" : "Catch system screenshots",
                               isOn: $catchSystemScreenshots)
                            .labelsHidden()
                            .toggleStyle(VorssaintCompactSwitchStyle())
                            .onChange(of: catchSystemScreenshots) { _, _ in
                                ShelfService.shared.syncDragMonitor()
                            }
                    }
                }

                SettingsCard(title: l10n.s.shelfExclusionsTitle) {
                    if sortedExclusions.isEmpty {
                        Text(l10n.s.shelfExclusionsEmpty)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedExclusions, id: \.self) { bundleID in
                            HStack(spacing: 9) {
                                Image(nsImage: InstalledApps.icon(for: bundleID))
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                Text(InstalledApps.name(for: bundleID))
                                Spacer()
                                ListRemoveButton(label: l10n.s.actionRemove) {
                                    shelf.removeAutomaticExclusion(bundleID)
                                }
                            }
                        }
                    }
                    HStack {
                        VorssaintActionChip(title: l10n.s.autoQuitAddApp, symbol: "plus", tone: .clipboardFiles) {
                            showingAppPicker = true
                        }
                        Spacer()
                    }
                    Text(l10n.s.shelfExclusionsCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // The island can be switched on or its modules changed elsewhere while this page is open.
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)) { _ in
            islandShowsFiles = NotchSupport.showsFiles()
        }
        .sheet(isPresented: $showingAppPicker) {
            appPickerSheet
        }
    }

    private var islandOn: Bool {
        islandEnabled && NotchSupport.isEnabled()
    }

    private var sortedExclusions: [String] {
        shelf.automaticExclusions.sorted {
            InstalledApps.name(for: $0)
                .localizedCaseInsensitiveCompare(InstalledApps.name(for: $1)) == .orderedAscending
        }
    }

    private var appPickerSheet: some View {
        let excluded = Set(shelf.automaticExclusions)
        return AppPickerView {
            showingAppPicker = false
        } onSelect: { url in
            showingAppPicker = false
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
            shelf.addAutomaticExclusion(bundleID)
        } loadApps: {
            InstalledApps.installedBundleApplications(excluding: excluded)
        }
    }

    private func bullet(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
