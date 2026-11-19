// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct WindowLayoutSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var service = WindowLayoutService.shared
    @ObservedObject private var maximizer = WindowMaximizer.shared
    @AppStorage(DefaultsKey.windowMaximizeEnabled) private var maximizeEnabled = false
    @ObservedObject private var pointerDisplay = PointerDisplayService.shared
    @AppStorage(DefaultsKey.pointerDisplayEnabled) private var pointerDisplayEnabled = false
    @AppStorage(DefaultsKey.panelUtilityWindowLayout) private var showInPanel = true
    @AppStorage(DefaultsKey.windowLayoutShortcutsEnabled) private var shortcutsEnabled = true
    @AppStorage(DefaultsKey.windowDirectionalEnabled) private var directionalEnabled = false
    @AppStorage(DefaultsKey.windowDirectionalShortcut) private var directionalShortcutRaw = GlobalShortcut.windowDirectionalDefault.storageValue
    @AppStorage(DefaultsKey.windowEdgeSnapEnabled) private var edgeSnapEnabled = false
    @AppStorage(DefaultsKey.windowEdgeSnapDisabledZones) private var edgeSnapDisabledZones = ""
    @AppStorage(DefaultsKey.windowEdgeSnapZoneActions) private var edgeSnapZoneActions = ""
    @AppStorage(DefaultsKey.windowGestureEnabled) private var gestureEnabled = false
    @AppStorage(DefaultsKey.windowGestureModifiers) private var gestureModifiers = WindowGestureSupport.defaultModifierStorageValue
    @AppStorage(DefaultsKey.windowGestureRaiseWindow) private var gestureRaiseWindow = false
    @AppStorage(DefaultsKey.windowLayoutWindowGap) private var windowGap = 0
    @AppStorage(DefaultsKey.windowLayoutScreenGap) private var screenGap = 0
    @AppStorage(DefaultsKey.windowReserveStageManagerSpace) private var reserveStageManagerSpace = false
    @AppStorage(DefaultsKey.windowLayoutMarginPercent) private var marginPercent = WindowLayoutMargin.defaultPercent
    @AppStorage(DefaultsKey.windowLayoutSideRepeatCyclesThirds) private var sideRepeatCyclesThirds = false
    @AppStorage(DefaultsKey.windowCustomGridColumns) private var customGridColumns = 3
    @AppStorage(DefaultsKey.windowCustomGridRows) private var customGridRows = 2
    @AppStorage(TitlebarScrollTap.preferenceKey) private var titlebarScrollGesturesEnabled = false
    @ObservedObject private var workspaceStore = WindowWorkspaceStore.shared
    @State private var newWorkspaceName = ""
    @State private var directionalError: String?
    @State private var systemTilingEnabled = WindowEdgeSnapSupport.isSystemTilingEnabled
    // Same preference the Switcher page exposes next to Dock Preview; it is
    // mirrored here because it is a window-juggling behavior people look for
    // on this page too.
    @AppStorage(DefaultsKey.dockClickCycleWindows) private var dockClickCycleWindows = false

    private var text: WindowLayoutFeatureStrings {
        FeatureStrings.windowLayout(l10n.language)
    }

    private var v2Strings: OverhaulV2Strings {
        OverhaulV2Strings.localized(l10n.language)
    }

    var body: some View {
        SettingsPageContainer(title: text.title, subtitle: text.caption) {
            if AppFeature.windowLayout.isAvailable {
                SettingsCard {
                    SettingsRow(symbol: "rectangle.3.group", title: text.showInPanel) {
                        Toggle(text.showInPanel, isOn: $showInPanel)
                            .labelsHidden()
                            .toggleStyle(VorssaintCompactSwitchStyle())
                    }
                    Label(text.permissionCaption, systemImage: "hand.raised")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, settingsRowTextInset)
                }
            }

            if !permissions.accessibility {
                SettingsCard(title: l10n.s.permissionRequired) {
                    PermissionRow(kind: .accessibility)
                }
            }

            // The green button override has no page of its own; it lives here
            // with the other window behaviors and keeps this page reachable
            // when it is the only one of the two still switched on in the hub.
            if AppFeature.windowMaximizer.isAvailable {
                windowMaximizerSection
            }

            if AppFeature.windowLayout.isAvailable || AppFeature.windowMaximizer.isAvailable {
                SettingsCard {
                    SettingsRow(symbol: "squares.leading.rectangle",
                                title: WindowStageManagerStrings.localized(l10n.language).title,
                                caption: WindowStageManagerStrings.localized(l10n.language).caption) {
                        Toggle(WindowStageManagerStrings.localized(l10n.language).title,
                               isOn: $reserveStageManagerSpace)
                            .labelsHidden()
                            .toggleStyle(VorssaintCompactSwitchStyle())
                    }
                }
            }

            if AppFeature.windowLayout.isAvailable {
                SettingsCard(title: text.gestureSection) {
                    SettingsRow(symbol: "rectangle.inset.filled.and.cursorarrow",
                                title: text.edgeSnapEnable,
                                caption: text.edgeSnapCaption) {
                        Toggle(text.edgeSnapEnable, isOn: $edgeSnapEnabled)
                            .labelsHidden()
                            .toggleStyle(VorssaintCompactSwitchStyle())
                            .onChange(of: edgeSnapEnabled) { _, _ in
                                WindowLayoutService.shared.syncWithPreferences()
                            }
                    }
                    WindowEdgeSnapZonePicker(disabledZonesStorage: $edgeSnapDisabledZones,
                                             zoneActionsStorage: $edgeSnapZoneActions,
                                             text: text,
                                             resetTitle: l10n.s.shortcutReset)
                        .disabled(!edgeSnapEnabled)
                        .opacity(edgeSnapEnabled ? 1 : 0.45)
                        .onChange(of: edgeSnapDisabledZones) { _, _ in
                            WindowLayoutService.shared.syncWithPreferences()
                        }
                    if systemTilingEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(text.edgeSnapSystemConflict, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                            if edgeSnapEnabled {
                                Text(text.edgeSnapWaitingForSystem)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Button(text.edgeSnapOpenSystemSettings) {
                                NSWorkspace.shared.open(WindowEdgeSnapSupport.desktopAndDockSettingsURL)
                            }
                            .controlSize(.small)
                        }
                    }
                    Divider()
                    SettingsRow(symbol: "cursorarrow.and.square.on.square.dashed",
                                title: text.gestureEnable,
                                caption: text.gestureCaption) {
                        Toggle(text.gestureEnable, isOn: $gestureEnabled)
                            .labelsHidden()
                            .toggleStyle(VorssaintCompactSwitchStyle())
                            .onChange(of: gestureEnabled) { _, _ in
                                WindowLayoutService.shared.syncWithPreferences()
                            }
                    }
                    if gestureEnabled {
                        VStack(alignment: .leading, spacing: 10) {
                            WindowGestureModifierPicker(storageValue: $gestureModifiers,
                                                        title: text.gestureModifiers)
                                .onChange(of: gestureModifiers) { _, _ in
                                    WindowLayoutService.shared.syncWithPreferences()
                                }
                            WindowGestureHints(modifierStorage: gestureModifiers,
                                               moveText: text.gestureMove,
                                               resizeText: text.gestureResize)
                            Text(text.gestureResizeHint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Toggle(text.gestureRaiseWindow, isOn: $gestureRaiseWindow)
                        }
                        .padding(.leading, settingsRowTextInset)
                    }
                    Divider()
                    SettingsRow(symbol: "hand.draw",
                                title: v2Strings.titlebarGesturesEnable,
                                caption: titlebarGestureHelpCaption) {
                        Toggle(v2Strings.titlebarGesturesEnable, isOn: $titlebarScrollGesturesEnabled)
                            .labelsHidden()
                            .toggleStyle(VorssaintCompactSwitchStyle())
                            .onChange(of: titlebarScrollGesturesEnabled) { _, _ in
                                TitlebarScrollTap.shared.syncWithPreferences()
                            }
                    }
                }

                SettingsCard(title: FeatureStrings.windowLayoutIgnoredApps(l10n.language).sectionTitle) {
                    WindowLayoutIgnoredAppsList()
                }

                SettingsCard(title: text.gapsSection) {
                    gapPicker(text.windowGap, selection: $windowGap)
                    Divider()
                    gapPicker(text.screenGap, selection: $screenGap)
                    Text(text.gapsCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsCard(title: text.shortcuts) {
                    SettingsRow(symbol: "keyboard", title: text.shortcuts, caption: text.shortcutsCaption) {
                        Toggle(text.shortcuts, isOn: $shortcutsEnabled)
                            .labelsHidden()
                            .toggleStyle(VorssaintCompactSwitchStyle())
                            .onChange(of: shortcutsEnabled) { _, _ in
                                WindowLayoutService.shared.syncWithPreferences()
                            }
                    }
                    if !service.failedShortcutActions.isEmpty {
                        Text(l10n.s.shortcutUnavailable)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.leading, settingsRowTextInset)
                    }
                    Divider()
                    SettingsRow(symbol: "arrow.up.and.down.and.arrow.left.and.right",
                                title: WindowDirectionalStrings.localized(l10n.language).title,
                                caption: WindowDirectionalStrings.localized(l10n.language).caption) {
                        Toggle(WindowDirectionalStrings.localized(l10n.language).title,
                               isOn: $directionalEnabled)
                            .labelsHidden()
                            .toggleStyle(VorssaintCompactSwitchStyle())
                            .onChange(of: directionalEnabled) { _, _ in service.syncWithPreferences() }
                    }
                    if directionalEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            ShortcutRecorderButton(shortcut: directionalKeyShortcut,
                                                   isEnabled: permissions.accessibility,
                                                   waitingTitle: l10n.s.shortcutPressKeys,
                                                   emptyTitle: directionalTrigger.displayString,
                                                   notCapturedAction: { directionalError = l10n.s.shortcutNotCaptured },
                                                   recordingChanged: { if $0 { directionalError = nil } },
                                                   captureModifiersAction: { saveDirectionalTrigger(.modifiers($0)) },
                                                   invalidAction: { directionalError = l10n.s.shortcutInvalid },
                                                   captureAction: saveDirectionalShortcut)
                                .frame(width: 108)
                            if let directionalError {
                                Text(directionalError)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            if service.directionalShortcutRegistrationFailed {
                                Text(l10n.s.shortcutUnavailable)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.leading, settingsRowTextInset)
                    }
                }

                // The pointer moves without Accessibility, so this sits outside
                // the window shortcuts toggle and works before that grant.
                SettingsCard {
                    SettingsRow(symbol: "display.2",
                                title: PointerDisplayStrings.localized(l10n.language).title,
                                caption: PointerDisplayStrings.localized(l10n.language).caption) {
                        Toggle(PointerDisplayStrings.localized(l10n.language).title,
                               isOn: $pointerDisplayEnabled)
                            .labelsHidden()
                            .toggleStyle(VorssaintCompactSwitchStyle())
                            .onChange(of: pointerDisplayEnabled) { _, _ in
                                // Also syncs the pointer key, and starts or stops
                                // watching app switches for Ignore apps.
                                service.syncWithPreferences()
                            }
                    }
                    ShortcutPreferenceRow(role: .pointerNextDisplay,
                                          isEnabled: pointerDisplayEnabled,
                                          additionalConflict: {
                                              service.shortcutConflictTitle($0)
                                          }) {
                        pointerDisplay.syncWithPreferences()
                    }
                    .padding(.leading, settingsRowTextInset)
                    if pointerDisplayEnabled, pointerDisplay.shortcutRegistrationFailed {
                        Text(l10n.s.shortcutUnavailable)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.leading, settingsRowTextInset)
                    }
                }

                SettingsCard {
                    SettingsRow(symbol: "arrow.triangle.2.circlepath",
                                title: l10n.s.dockClickCycleWindows,
                                caption: l10n.s.dockClickCycleWindowsCaption) {
                        Toggle(l10n.s.dockClickCycleWindows, isOn: $dockClickCycleWindows)
                            .labelsHidden()
                            .toggleStyle(VorssaintCompactSwitchStyle())
                            .onChange(of: dockClickCycleWindows) { _, _ in
                                DockClickService.shared.syncWithPreferences()
                            }
                    }
                }

                placementSections

                SettingsCard(title: text.other) {
                    actionRow(.maximize)
                    Divider()
                    actionRow(.marginMaximize)
                    marginSlider
                    Divider()
                    actionRow(.fullScreen)
                    Divider()
                    actionRow(.center)
                    Divider()
                    actionRow(.previousDisplay)
                    Divider()
                    actionRow(.nextDisplay)
                    Divider()
                    actionRow(.restore)
                    if let message = resultMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(resultColor)
                    }
                }
            }
            if AppFeature.windowLayout.isAvailable {
                workspacesAndGridSection
            }
        }
        .onAppear { refreshSystemTilingState() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshSystemTilingState()
        }
    }

    private var windowMaximizerSection: some View {
        SettingsCard {
            SettingsRow(symbol: AppFeature.windowMaximizer.symbolName,
                        title: l10n.s.windowMaximizeName,
                        caption: l10n.s.windowMaximizeCaption) {
                Toggle(l10n.s.windowMaximizeName, isOn: $maximizeEnabled)
                    .labelsHidden()
                    .toggleStyle(VorssaintCompactSwitchStyle())
                    .onChange(of: maximizeEnabled) { _, _ in
                        WindowMaximizer.shared.syncWithPreferences()
                    }
            }
            if maximizeEnabled, maximizer.isRunning {
                Label(l10n.s.windowMaximizeActiveNow, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.leading, settingsRowTextInset)
            }
            Divider()
            WindowMaximizerExclusionsList()
        }
        .settingsSectionAnchor(.windowMaximizer, cornerRadius: 16)
    }

    private var wave4Strings: OverhaulWave4Strings {
        OverhaulStrings.wave4(l10n.language)
    }

    private var titlebarGestureHelpCaption: String {
        switch l10n.language {
        case .enUS:
            return "Scroll or swipe inside a window\u{2019}s top 30pt titlebar to minimize (down), maximize (up), or snap left/right."
        case .ru:
            return "Проведите или прокрутите на верхней 30pt-шапке окна: вниз (свернуть), вверх (развернуть), влево/вправо (половина экрана)."
        case .ptBR:
            return "Role ou deslize na barra de título (30pt): para baixo minimiza, para cima maximiza e esquerda/direita encaixa na metade."
        case .tr:
            return "Pencerenin üst 30pt başlık çubuğunda kaydırın: aşağı simge durumuna küçültür, yukarı büyütür, sol/sağ yarıya yaslar."
        case .es:
            return "Desliza o haz scroll en la barra de título (30pt): abajo minimiza, arriba maximiza e izquierda/derecha ajusta a la mitad."
        case .sk:
            return "Posuňte alebo otočte kolieskom v hornom 30pt záhlaví okna: nadol minimalizuje, nahor maximalizuje, vľavo/vpravo prichytí na polovicu."
        case .de:
            return "In der oberen 30pt-Titelleiste scrollen oder wischen: nach unten minimiert, nach oben maximiert, links/rechts rastet halb ein."
        case .fr:
            return "Faites défiler sur la barre de titre (30pt)\u{00A0}: vers le bas réduit, vers le haut agrandit, gauche/droite place à moitié."
        case .it:
            return "Scorri sulla barra del titolo (30pt): giù riduce a icona, su massimizza, sinistra/destra aggancia a metà."
        case .ja:
            return "ウィンドウ上端 30pt のタイトルバー上でスクロール／スワイプして最小化（下）、最大化（上）、左右半分にスナップします。"
        case .ko:
            return "창 상단 30pt 제목 표시줄에서 스크롤/스와이프하여 최소화(아래), 최대화(위), 좌/우 절반 스냅을 실행합니다."
        case .uk:
            return "Прокрутіть або змахніть у верхній 30pt-смужці заголовка: вниз згортає, вгору розгортає, вліво/вправо прикріплює на половину."
        case .zhHans:
            return "在窗口顶部 30pt 标题栏区域滚动或滑动：向下最小化，向上最大化，向左/右半屏贴靠。"
        case .zhTW:
            return "在視窗頂部 30pt 標題列區域捲動或滑動：向下最小化，向上最大化，向左/右半螢幕貼齊。"
        case .zhHK:
            return "喺視窗頂部 30pt 標題列區域捲動或滑動：向下縮到最小，向上放到最大，向左/右半螢幕貼齊。"
        }
    }

    private var customSnapGridTabs: some View {
        VorssaintSegmentedTabs(
            selection: $customGridColumns,
            options: [
                .init(2, title: "2x2"),
                .init(3, title: "3x2"),
                .init(4, title: "4x2"),
                .init(6, title: "6x2"),
            ],
            tone: .windowsDock
        )
        .fixedSize()
    }

    private var customSnapOverlayTrigger: some View {
        Button {
            CustomSnapGridOverlayController.shared.show()
        } label: {
            Label(v2Strings.customSnapOverlayButton, systemImage: "square.grid.3x2")
                .lineLimit(1)
        }
        .fixedSize()
        .controlSize(.small)
        .disabled(!permissions.accessibility)
    }

    private var workspacesAndGridSection: some View {
        SettingsCard(title: wave4Strings.workspacesTitle) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    Text(wave4Strings.customSnapGridLabel)
                        .lineLimit(1)
                        .fixedSize()
                    Spacer(minLength: 8)
                    customSnapGridTabs
                    customSnapOverlayTrigger
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(wave4Strings.customSnapGridLabel)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        customSnapGridTabs
                        Spacer(minLength: 8)
                        customSnapOverlayTrigger
                    }
                }
            }
            Divider()
            HStack(spacing: 8) {
                TextField(wave4Strings.workspacesTitle, text: $newWorkspaceName)
                    .textFieldStyle(.roundedBorder)
                Button(wave4Strings.saveWorkspaceButton) {
                    let captured = WindowLayoutService.shared.captureCurrentWorkspaceSlots()
                    let slots: [WindowWorkspaceSlot]
                    if !captured.isEmpty {
                        slots = captured
                    } else {
                        let grid = CustomSnapGridSpec(columns: customGridColumns, rows: customGridRows)
                        let rect = grid.cellFrame(in: CGRect(x: 0, y: 0, width: 1, height: 1),
                                                  colRange: 0...0, rowRange: 0...0)
                        let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "com.apple.Finder"
                        slots = [WindowWorkspaceSlot(bundleID: bundle,
                                                     normalizedX: rect.minX,
                                                     normalizedY: rect.minY,
                                                     normalizedWidth: rect.width,
                                                     normalizedHeight: rect.height)]
                    }
                    workspaceStore.savePreset(name: newWorkspaceName, slots: slots)
                    newWorkspaceName = ""
                    VorssaintHaptics.alignment()
                }
            }
            ForEach(workspaceStore.presets) { preset in
                Divider()
                HStack(spacing: 8) {
                    Text(preset.name)
                    Text("\(preset.slots.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.14)))
                    Spacer()
                    Button {
                        WindowLayoutService.shared.applyWorkspacePreset(preset)
                    } label: {
                        Label(v2Strings.workspaceRestoreAction, systemImage: "play.fill")
                    }
                    .controlSize(.small)
                    .disabled(!permissions.accessibility)
                    Button(role: .destructive) {
                        workspaceStore.deletePreset(id: preset.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help(l10n.s.actionRemove)
                    .accessibilityLabel(l10n.s.actionRemove)
                }
            }
        }
    }

    private var directionalTrigger: WindowDirectionalTrigger {
        WindowDirectionalTrigger(storageValue: directionalShortcutRaw) ?? .key(.windowDirectionalDefault)
    }

    private var directionalKeyShortcut: GlobalShortcut {
        if case .key(let shortcut) = directionalTrigger { return shortcut }
        return .windowDirectionalDefault
    }

    private func saveDirectionalShortcut(_ shortcut: GlobalShortcut) {
        if let conflict = service.directionalShortcutConflictTitle(shortcut) {
            directionalError = String(format: l10n.s.shortcutConflictFormat, conflict)
            return
        }
        saveDirectionalTrigger(.key(shortcut))
    }

    private func saveDirectionalTrigger(_ trigger: WindowDirectionalTrigger) {
        directionalError = nil
        directionalShortcutRaw = trigger.storageValue
        service.syncWithPreferences()
    }

    /// The gaps take effect on the next placement — the engine reads them
    /// per apply — so the pickers need no service sync.
    private func gapPicker(_ title: String, selection: Binding<Int>) -> some View {
        SettingsMenuRow(symbol: "square.split.2x2", title: title, selection: selection) {
            ForEach(WindowLayoutGaps.presets, id: \.self) { value in
                Text(gapPresetTitle(value)).tag(value)
            }
        }
    }

    private func gapPresetTitle(_ value: Int) -> String {
        let name: String
        switch value {
        case 0: return text.gapNone
        case 8: name = text.gapTiny
        case 16: name = text.gapSmall
        case 32: name = text.gapMedium
        case 64: name = text.gapLarge
        case 128: name = text.gapExtraLarge
        default: return "\(value) px"
        }
        return "\(name) (\(value) px)"
    }

    private var marginSlider: some View {
        HStack(spacing: 12) {
            Text(text.marginPerEdge)
                .foregroundStyle(.secondary)
            VorssaintDetentSlider(value: Binding(
                get: { WindowLayoutMargin.sanitizedPercent(marginPercent) },
                set: { marginPercent = WindowLayoutMargin.sanitizedPercent($0) }
            ), in: WindowLayoutMargin.percentRange, step: 1, detent: 0, tone: .windowsDock)
            Text(WindowLayoutMargin.sanitizedPercent(marginPercent) / 100,
                 format: .percent.precision(.fractionLength(0)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    private func refreshSystemTilingState() {
        systemTilingEnabled = WindowEdgeSnapSupport.isSystemTilingEnabled
        WindowLayoutService.shared.syncWithPreferences()
    }

    private static let halfActions: [WindowLayoutAction] = [
        .leftHalf, .rightHalf, .topHalf, .bottomHalf, .centerHalf,
    ]
    private static let thirdActions: [WindowLayoutAction] = [
        .leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds, .centerTwoThirds,
        .topThird, .middleThird, .bottomThird, .topTwoThirds, .bottomTwoThirds,
    ]
    private static let quarterRowActions: [WindowLayoutAction] = [
        .topQuarter, .upperMiddleQuarter, .lowerMiddleQuarter, .bottomQuarter,
    ]
    private static let quarterColumnActions: [WindowLayoutAction] = [
        .leftQuarter, .leftMiddleQuarter, .rightMiddleQuarter, .rightQuarter,
    ]
    private static let sixthActions: [WindowLayoutAction] = [
        .topLeftSixth, .topCenterSixth, .topRightSixth,
        .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth,
    ]
    private static let cornerActions: [WindowLayoutAction] = [
        .topLeft, .topRight, .bottomLeft, .bottomRight,
    ]

    /// The placement families, grouped so the page body stays within the
    /// ten-view ViewBuilder limit.
    @ViewBuilder
    private var placementSections: some View {
        SettingsCard {
            WindowSnapZonePreview(
                screenGap: max(0, screenGap),
                edgeSnapEnabled: edgeSnapEnabled,
                strings: OverhaulStrings.localized(l10n.language)
            )
        }
        SettingsCard(title: text.halves) {
            ForEach(Self.halfActions) { action in
                if action != Self.halfActions.first {
                    Divider()
                }
                actionRow(action)
            }
            Divider()
            SettingsRow(symbol: "arrow.triangle.2.circlepath",
                        title: text.sideRepeatCycle,
                        caption: text.sideRepeatCycleCaption) {
                Toggle(text.sideRepeatCycle, isOn: $sideRepeatCyclesThirds)
                    .labelsHidden()
                    .toggleStyle(VorssaintCompactSwitchStyle())
            }
        }
        actionSection(text.thirds, Self.thirdActions)
        actionSection(text.quarterRows, Self.quarterRowActions)
        actionSection(text.quarterColumns, Self.quarterColumnActions)
        actionSection(text.sixths, Self.sixthActions)
        actionSection(text.corners, Self.cornerActions)
    }

    /// One card per placement family. Building the rows from an array keeps
    /// each card clear of the ten-view ViewBuilder limit and keeps the page
    /// body small enough for the type checker.
    private func actionSection(_ title: String, _ actions: [WindowLayoutAction]) -> some View {
        SettingsCard(title: title) {
            ForEach(actions) { action in
                if action != actions.first {
                    Divider()
                }
                actionRow(action)
            }
        }
    }

    /// One row per action: try-it button on the left, the action's global
    /// shortcut recorder inline on the right — every action is adjustable
    /// right where it lives, no separate shortcut list to hunt for.
    private func actionRow(_ action: WindowLayoutAction) -> some View {
        WindowLayoutActionRow(action: action,
                              title: title(for: action),
                              symbol: symbol(for: action),
                              applyEnabled: permissions.accessibility,
                              shortcutEnabled: shortcutsEnabled && permissions.accessibility)
    }

    private func title(for action: WindowLayoutAction) -> String {
        action.title(text)
    }

    private func symbol(for action: WindowLayoutAction) -> String {
        action.symbolName
    }

    private var resultMessage: String? {
        switch service.lastResult {
        case .success(let restored): return restored ? text.restored : text.done
        case .failure(.missingAccessibility): return text.missingPermission
        case .failure(.noWindow): return text.noWindow
        case .failure(.noRestore): return text.noRestore
        case .failure(.failed): return text.failed
        case nil: return nil
        }
    }

    private var resultColor: Color {
        switch service.lastResult {
        case .success: return .green
        case .failure: return .orange
        case nil: return .secondary
        }
    }
}

private struct WindowLayoutActionRow: View {
    @ObservedObject private var l10n = L10n.shared
    let action: WindowLayoutAction
    let title: String
    let symbol: String
    let applyEnabled: Bool
    let shortcutEnabled: Bool
    @AppStorage private var rawValue: String
    @State private var errorText: String?
    @State private var isRecording = false
    @State private var pendingTakeOver: GlobalShortcut?

    init(action: WindowLayoutAction,
         title: String,
         symbol: String,
         applyEnabled: Bool,
         shortcutEnabled: Bool) {
        self.action = action
        self.title = title
        self.symbol = symbol
        self.applyEnabled = applyEnabled
        self.shortcutEnabled = shortcutEnabled
        _rawValue = AppStorage(
            wrappedValue: action.defaultShortcut?.storageValue
                ?? WindowLayoutAction.clearedShortcutStorageValue,
            action.shortcutKey
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button {
                    WindowLayoutService.shared.apply(action)
                } label: {
                    Label(title, systemImage: symbol)
                }
                .disabled(!applyEnabled)
                Spacer()
                ShortcutRecorderButton(shortcut: pendingTakeOver
                                           ?? shortcut
                                           ?? action.defaultShortcut
                                           ?? .windowLayoutLeftDefault,
                                       isEnabled: shortcutEnabled,
                                       waitingTitle: l10n.s.shortcutPressKeys,
                                       emptyTitle: pendingTakeOver == nil && shortcut == nil ? l10n.s.shortcutNone : nil,
                                       clearAction: clear,
                                       notCapturedAction: { errorText = l10n.s.shortcutNotCaptured },
                                       recordingChanged: { recording in
                                           isRecording = recording
                                           if recording {
                                               errorText = nil
                                               pendingTakeOver = nil
                                           }
                                       },
                                       invalidAction: { errorText = l10n.s.shortcutInvalid },
                                       captureAction: save)
                    .frame(width: 108)
                    .disabled(!shortcutEnabled)
                ClearIconButton(label: l10n.s.shortcutClear, disabled: !shortcutEnabled || shortcut == nil) {
                    clear()
                }
                Button(l10n.s.shortcutReset) {
                    rawValue = action.defaultShortcut?.storageValue
                        ?? WindowLayoutAction.clearedShortcutStorageValue
                    errorText = nil
                    pendingTakeOver = nil
                    SystemShortcutTakeover.setTakeOver(action.shortcutKey, false)
                    WindowLayoutService.shared.syncWithPreferences()
                }
                .disabled(!shortcutEnabled || shortcut == action.defaultShortcut)
            }
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if isRecording {
                Text(ShortcutRecordingCaption.text(l10n.s, canClear: true))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let pendingTakeOver {
                SystemShortcutTakeOverOffer(
                    shortcut: pendingTakeOver,
                    onAccept: {
                        rawValue = pendingTakeOver.storageValue
                        SystemShortcutTakeover.setTakeOver(action.shortcutKey, true)
                        self.pendingTakeOver = nil
                        WindowLayoutService.shared.syncWithPreferences()
                    },
                    onDismiss: {
                        self.pendingTakeOver = nil
                        errorText = String(format: l10n.s.shortcutConflictFormat, "macOS")
                    }
                )
            }
        }
        .onChange(of: l10n.language) { _, _ in errorText = nil }
    }

    private var shortcut: GlobalShortcut? {
        WindowLayoutAction.resolvedShortcut(storedValue: rawValue,
                                            defaultShortcut: action.defaultShortcut)
    }

    private func clear() {
        rawValue = WindowLayoutAction.clearedShortcutStorageValue
        errorText = nil
        pendingTakeOver = nil
        SystemShortcutTakeover.setTakeOver(action.shortcutKey, false)
        WindowLayoutService.shared.syncWithPreferences()
    }

    private func save(_ shortcut: GlobalShortcut) {
        if let conflict = GlobalShortcutRole.conflict(for: shortcut, excluding: nil) {
            errorText = String(format: l10n.s.shortcutConflictFormat, conflict.title(l10n.s))
            return
        }
        if let conflict = WindowLayoutService.shared.shortcutConflictTitle(shortcut, excluding: action) {
            errorText = String(format: l10n.s.shortcutConflictFormat, conflict)
            return
        }
        // The offer is the last word on a combination: every other check has
        // already passed, so accepting it writes exactly what a save writes.
        switch SystemShortcutTakeoverSupport.recorderDecision(
            shortcut: shortcut,
            conflictsWithMacOS: SystemShortcutTakeover.conflictsWithMacOS(shortcut),
            takenOver: SystemShortcutTakeover.isTakenOver(action.shortcutKey),
            current: GlobalShortcut(storageValue: rawValue)) {
        case .offer:
            pendingTakeOver = shortcut
            errorText = nil
            return
        case .save(let clearTakeOver):
            rawValue = shortcut.storageValue
            errorText = nil
            if clearTakeOver { SystemShortcutTakeover.setTakeOver(action.shortcutKey, false) }
        }
        WindowLayoutService.shared.syncWithPreferences()
    }
}
