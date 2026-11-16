// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreGraphics
import Foundation

/// Lightweight snapshot of another app's menu bar status item window captured via CGWindowList.
struct MenuBarOverflowItem: Identifiable, Equatable, Sendable {
    let id: String
    let windowID: CGWindowID
    let ownerName: String
    let title: String
    let ownerPID: pid_t
    let bounds: CGRect

    var displayName: String {
        if !title.isEmpty, title != ownerName {
            return "\(ownerName) · \(title)"
        }
        return ownerName
    }
}

/// Manages a non-destructive collapsible `NSStatusItem` divider (`com.vorssaint.menubar.divider`)
/// that hides status icons to its left when collapsed (`length = 10_000`) and reveals them
/// (`length = 18`) along with an optional floating glass overflow bar on Notch Macs.
@MainActor
final class MenuBarIconManagerService: ObservableObject {
    static let shared = MenuBarIconManagerService()

    static let dividerAutosaveName = "com.vorssaint.menubar.divider"
    static let enabledDefaultsKey = "vorssaintMenuBarManagerEnabled"
    static let autoHideDefaultsKey = "vorssaintMenuBarAutoHideSeconds"
    static let collapsedLength: CGFloat = 10_000
    static let expandedLength: CGFloat = 18
    static let autoHideRange: ClosedRange<Double> = 2...30

    @Published var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledDefaultsKey)
            syncWithPreferences()
        }
    }

    @Published private(set) var isExpanded: Bool = false

    @Published var autoHideSeconds: Double {
        didSet {
            let clamped = Self.clampedAutoHideSeconds(autoHideSeconds)
            if clamped != autoHideSeconds {
                autoHideSeconds = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: Self.autoHideDefaultsKey)
            if isEnabled && isExpanded {
                rescheduleAutoHideTimer()
            }
        }
    }

    @Published private(set) var overflowItems: [MenuBarOverflowItem] = []
    @Published var overflowBarVisible: Bool = false
    @Published var isOverflowBarPinned: Bool = false

    var menuBarHasNotch: Bool {
        NotchSupport.hasNotchedDisplay
    }

    private var dividerStatusItem: NSStatusItem?
    private weak var collapsedTrailingIconView: NSImageView?
    private var autoHideTimer: Timer?
    private var refreshWorkItem: DispatchWorkItem?

    private init() {
        let defaults = UserDefaults.standard
        self.isEnabled = defaults.bool(forKey: Self.enabledDefaultsKey)
        if let storedNumber = defaults.object(forKey: Self.autoHideDefaultsKey) as? NSNumber {
            self.autoHideSeconds = Self.clampedAutoHideSeconds(storedNumber.doubleValue)
        } else {
            self.autoHideSeconds = 6
        }
    }

    func syncWithPreferences() {
        guard isEnabled else {
            stop()
            return
        }

        if dividerStatusItem == nil {
            let item = NSStatusBar.system.statusItem(
                withLength: isExpanded ? Self.expandedLength : Self.collapsedLength
            )
            item.autosaveName = Self.dividerAutosaveName
            item.behavior = []
            item.isVisible = true
            if let button = item.button {
                button.target = self
                button.action = #selector(handleDividerClick(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                button.toolTip = OverhaulV3Strings.localized(L10n.shared.language).menuBarManagerToggle
                installTrailingIconIfNeeded(in: button)
            }
            dividerStatusItem = item
        }

        applyDividerAppearance()
        refreshOverflowItems()
    }

    func toggleExpanded() {
        setExpanded(!isExpanded)
    }

    func setExpanded(_ expanded: Bool) {
        invalidateAutoHideTimer()
        refreshWorkItem?.cancel()
        refreshWorkItem = nil

        guard isEnabled else {
            isExpanded = false
            isOverflowBarPinned = false
            overflowBarVisible = false
            MenuBarOverflowBarController.shared.hide()
            return
        }

        if dividerStatusItem == nil {
            syncWithPreferences()
        }

        isExpanded = expanded
        applyDividerAppearance()

        if expanded {
            refreshOverflowItems()
            scheduleDelayedOverflowRefresh()
            if menuBarHasNotch || overflowBarVisible {
                overflowBarVisible = true
                MenuBarOverflowBarController.shared.show(items: overflowItems)
            }
            rescheduleAutoHideTimer()
        } else {
            isOverflowBarPinned = false
            overflowBarVisible = false
            MenuBarOverflowBarController.shared.hide()
        }
    }

    func toggleOverflowBar() {
        guard isEnabled else { return }
        if overflowBarVisible {
            hideOverflowBar()
        } else {
            if !isExpanded {
                overflowBarVisible = true
                setExpanded(true)
            } else {
                refreshOverflowItems()
                overflowBarVisible = true
                MenuBarOverflowBarController.shared.show(items: overflowItems)
                rescheduleAutoHideTimer()
            }
        }
    }

    func hideOverflowBar() {
        overflowBarVisible = false
        isOverflowBarPinned = false
        MenuBarOverflowBarController.shared.hide()
        if isEnabled && isExpanded {
            rescheduleAutoHideTimer()
        }
    }

    func setOverflowBarPinned(_ pinned: Bool) {
        isOverflowBarPinned = pinned
        if pinned {
            invalidateAutoHideTimer()
        } else if isEnabled && isExpanded {
            rescheduleAutoHideTimer()
        }
    }

    func refreshOverflowItems() {
        let items = Self.captureStatusBarItems()
        overflowItems = items
        if overflowBarVisible {
            MenuBarOverflowBarController.shared.update(items: items)
        }
    }

    func activateOverflowItem(_ item: MenuBarOverflowItem) {
        if let app = NSRunningApplication(processIdentifier: item.ownerPID), !app.isTerminated {
            app.activate()
        }
        if !isOverflowBarPinned {
            setExpanded(false)
        }
    }

    func containsDividerStatusItem(at screenPoint: NSPoint) -> Bool {
        guard let frame = dividerStatusItem?.button?.window?.frame else { return false }
        return frame.insetBy(dx: -4, dy: -8).contains(screenPoint)
    }

    func stop() {
        invalidateAutoHideTimer()
        refreshWorkItem?.cancel()
        refreshWorkItem = nil
        isExpanded = false
        isOverflowBarPinned = false
        overflowBarVisible = false
        MenuBarOverflowBarController.shared.hide()
        if let item = dividerStatusItem {
            NSStatusBar.system.removeStatusItem(item)
            dividerStatusItem = nil
            collapsedTrailingIconView = nil
        }
    }

    // MARK: - Private helpers

    @objc private func handleDividerClick(_ sender: NSStatusBarButton?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            toggleOverflowBar()
        } else {
            toggleExpanded()
        }
    }

    private func installTrailingIconIfNeeded(in button: NSStatusBarButton) {
        guard collapsedTrailingIconView == nil else { return }
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = .labelColor
        iconView.image = Self.chevronImage(symbolName: "chevron.left")
        button.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -2),
            iconView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
        ])
        collapsedTrailingIconView = iconView
    }

    private func applyDividerAppearance() {
        guard let item = dividerStatusItem else { return }
        item.length = isExpanded ? Self.expandedLength : Self.collapsedLength
        item.isVisible = true
        guard let button = item.button else { return }
        button.toolTip = OverhaulV3Strings.localized(L10n.shared.language).menuBarManagerToggle
        if isExpanded {
            collapsedTrailingIconView?.isHidden = true
            button.image = Self.chevronImage(symbolName: "chevron.right")
            button.imagePosition = .imageOnly
        } else {
            button.image = nil
            installTrailingIconIfNeeded(in: button)
            collapsedTrailingIconView?.image = Self.chevronImage(symbolName: "chevron.left")
            collapsedTrailingIconView?.isHidden = false
        }
    }

    private static func chevronImage(symbolName: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 10.5, weight: .semibold)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    private func invalidateAutoHideTimer() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
    }

    private func rescheduleAutoHideTimer() {
        invalidateAutoHideTimer()
        guard isEnabled, isExpanded, !isOverflowBarPinned, autoHideSeconds > 0 else { return }
        let interval = Self.clampedAutoHideSeconds(autoHideSeconds)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isEnabled, self.isExpanded, !self.isOverflowBarPinned else { return }
                self.setExpanded(false)
            }
        }
        timer.tolerance = min(0.5, interval * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        autoHideTimer = timer
    }

    private func scheduleDelayedOverflowRefresh() {
        refreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isEnabled, self.isExpanded else { return }
                self.refreshOverflowItems()
            }
        }
        refreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
    }

    static func clampedAutoHideSeconds(_ value: Double) -> Double {
        guard value.isFinite else { return 6 }
        return min(autoHideRange.upperBound, max(autoHideRange.lowerBound, value))
    }

    static func captureStatusBarItems() -> [MenuBarOverflowItem] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let statusLayer = Int(CGWindowLevelForKey(.statusWindow)) // 25
        var items: [MenuBarOverflowItem] = []
        var seen = Set<String>()

        for info in windowList {
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  layer == statusLayer,
                  let ownerPIDNumber = info[kCGWindowOwnerPID as String] as? NSNumber else {
                continue
            }
            let ownerPID = pid_t(ownerPIDNumber.int32Value)
            guard ownerPID != ownPID else { continue }
            guard (info[kCGWindowAlpha as String] as? Double ?? 1.0) > 0 else { continue }
            guard let rawOwner = info[kCGWindowOwnerName as String] as? String else { continue }
            let ownerName = rawOwner.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ownerName.isEmpty, ownerName != "Window Server" else { continue }

            let rawTitle = (info[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let windowID = CGWindowID((info[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
            let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            guard bounds.width > 0, bounds.width < 320, bounds.height > 0, bounds.height <= 48 else {
                continue
            }
            let dedupKey = "\(ownerPID)-\(windowID)"
            guard seen.insert(dedupKey).inserted else { continue }
            items.append(MenuBarOverflowItem(
                id: dedupKey,
                windowID: windowID,
                ownerName: ownerName,
                title: rawTitle,
                ownerPID: ownerPID,
                bounds: bounds
            ))
        }

        return items.sorted { $0.bounds.minX < $1.bounds.minX }
    }
}
