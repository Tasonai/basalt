// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Non-activating floating glass panel hosting overflow menu bar icons below the Notch / menu bar.
/// Subclasses `OverlayPanel` so tiling window managers skip it while preserving assistive accessibility.
final class MenuBarOverflowBarPanel: OverlayPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 84),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        title = "Vorssaint"
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
    }
}

/// Manages presentation, Notch-aware positioning, and click-outside dismissal of `MenuBarOverflowBarPanel`.
@MainActor
final class MenuBarOverflowBarController {
    static let shared = MenuBarOverflowBarController()

    private var panel: MenuBarOverflowBarPanel?
    private var hostingController: NSHostingController<MenuBarOverflowBarView>?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var localKeyMonitor: Any?

    var isVisible: Bool {
        panel?.isVisible == true
    }

    private init() {}

    func show(items: [MenuBarOverflowItem]) {
        let activePanel: MenuBarOverflowBarPanel
        if let existing = panel {
            activePanel = existing
        } else {
            let created = MenuBarOverflowBarPanel()
            panel = created
            activePanel = created
        }

        let rootView = MenuBarOverflowBarView()
        if let hostingController {
            hostingController.rootView = rootView
        } else {
            let controller = NSHostingController(rootView: rootView)
            controller.sizingOptions = .preferredContentSize
            activePanel.contentViewController = controller
            hostingController = controller
        }

        positionAndSize(panel: activePanel, itemCount: items.count)
        installDismissMonitors()
        activePanel.alphaValue = 0
        activePanel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            activePanel.animator().alphaValue = 1
        }
    }

    func update(items: [MenuBarOverflowItem]) {
        guard let activePanel = panel, activePanel.isVisible else { return }
        hostingController?.rootView = MenuBarOverflowBarView()
        positionAndSize(panel: activePanel, itemCount: items.count)
    }

    func hide() {
        removeDismissMonitors()
        panel?.orderOut(nil)
    }

    private func positionAndSize(panel: MenuBarOverflowBarPanel, itemCount: Int) {
        hostingController?.view.layoutSubtreeIfNeeded()
        let screen = NSScreen.main ?? NSScreen.withMenuBar ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSScreen.pointerVisibleFrame
        let maxPanelWidth = max(360, visibleFrame.width - DesignSpace.xxl)
        let fitting = hostingController?.view.fittingSize ?? NSSize(width: 460, height: 82)
        let preferredWidth = max(itemCount > 0 ? 380 : 320, fitting.width)
        let width = min(preferredWidth, min(720, maxPanelWidth))
        let height = max(72, min(140, fitting.height))

        let x = max(
            visibleFrame.minX + DesignSpace.md,
            min(visibleFrame.midX - width / 2, visibleFrame.maxX - width - DesignSpace.md)
        )
        let y = visibleFrame.maxY - height - DesignSpace.sm
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func installDismissMonitors() {
        removeDismissMonitors()

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismissIfClickedOutside(screenPoint: NSEvent.mouseLocation)
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, let activePanel = self.panel, activePanel.isVisible else {
                return event
            }
            if event.window !== activePanel {
                self.dismissIfClickedOutside(screenPoint: NSEvent.mouseLocation)
            }
            return event
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let activePanel = self.panel, activePanel.isVisible else {
                return event
            }
            if event.keyCode == 53 { // Escape
                MenuBarIconManagerService.shared.hideOverflowBar()
                return nil
            }
            return event
        }
    }

    private func dismissIfClickedOutside(screenPoint: NSPoint) {
        guard let activePanel = panel, activePanel.isVisible else { return }
        guard !MenuBarIconManagerService.shared.isOverflowBarPinned else { return }
        guard !MenuBarIconManagerService.shared.containsDividerStatusItem(at: screenPoint) else { return }
        if !activePanel.frame.insetBy(dx: -4, dy: -4).contains(screenPoint) {
            MenuBarIconManagerService.shared.setExpanded(false)
        }
    }

    private func removeDismissMonitors() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }
}

private struct MenuBarOverflowBarView: View {
    @ObservedObject private var manager = MenuBarIconManagerService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme

    private func v3(_ keyPath: KeyPath<OverhaulV3Strings, String>) -> String {
        OverhaulV3Strings.localized(l10n.language)[keyPath: keyPath]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpace.sm) {
            HStack(spacing: DesignSpace.sm) {
                MascotCameoBadge(
                    mood: manager.isExpanded ? .happy : .idle,
                    tone: .brand,
                    size: 22,
                    interactiveCue: true
                )
                Text(v3(\OverhaulV3Strings.menuBarOverflowTitle))
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)

                Text("\(manager.overflowItems.count)")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, DesignSpace.xs + 2)
                    .padding(.vertical, DesignSpace.xxs)
                    .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.08)))

                Spacer(minLength: DesignSpace.sm)

                VorssaintActionChip(
                    title: manager.isOverflowBarPinned ? l10n.s.dockPreviewPinned : l10n.s.dockPreviewPinPanel,
                    symbol: manager.isOverflowBarPinned ? "pin.fill" : "pin",
                    tone: .brand,
                    prominent: manager.isOverflowBarPinned
                ) {
                    manager.setOverflowBarPinned(!manager.isOverflowBarPinned)
                }

                VorssaintActionChip(
                    title: l10n.s.shelfCollapse,
                    symbol: "chevron.up",
                    tone: .brand
                ) {
                    manager.setExpanded(false)
                }
            }

            if manager.overflowItems.isEmpty {
                HStack(spacing: DesignSpace.xs + 2) {
                    Image(systemName: "menubar.rectangle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(l10n.s.disclosureCollapsed)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, DesignSpace.xs)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DesignSpace.xs + 2) {
                        ForEach(manager.overflowItems) { item in
                            Button {
                                manager.activateOverflowItem(item)
                            } label: {
                                overflowItemChip(item)
                            }
                            .buttonStyle(VorssaintScalePressButtonStyle(cornerRadius: DesignRadius.pill))
                        }
                    }
                    .padding(.vertical, DesignSpace.xxs)
                }
            }
        }
        .padding(.horizontal, DesignSpace.md)
        .padding(.vertical, DesignSpace.sm + 2)
        .background(
            HUDBackdrop(cornerRadius: DesignRadius.panel, contrast: .high)
        )
        .hairlineSpecularBorder(cornerRadius: DesignRadius.panel)
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.36 : 0.16),
            radius: 14,
            x: 0,
            y: 6
        )
    }

    private func overflowItemChip(_ item: MenuBarOverflowItem) -> some View {
        let appIcon = NSRunningApplication(processIdentifier: item.ownerPID)?.icon
        return HStack(spacing: DesignSpace.xs + 2) {
            if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 14, height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
            } else {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
            }
            Text(item.displayName)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, DesignSpace.sm)
        .padding(.vertical, DesignSpace.xs + 1)
        .background(
            RoundedRectangle(cornerRadius: DesignRadius.pill, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
        )
        .hairlineSpecularBorder(cornerRadius: DesignRadius.pill, opacity: 0.14)
    }
}
