// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

/// Floating pinned screenshots keep a capture visible while working.
/// Drag anywhere to move, resize from the edges keeping proportions, scroll
/// to adjust opacity, Option-double-click or hover button to collapse into a
/// compact pill, double click or Esc closes, right click offers copy, save,
/// opacity, collapse and click-through. A monitor exists only while a
/// click-through pin needs its Option-click escape hatch.
final class ScreenshotPinController {
    static let shared = ScreenshotPinController()

    private var pins: [ScreenshotPinWindow] = []
    private var escapeMonitor: Any?

    private init() {}

    var protectedWindowIDs: Set<CGWindowID> {
        Set(pins.compactMap { $0.isVisible && $0.windowNumber > 0 ? CGWindowID($0.windowNumber) : nil })
    }

    func pin(image: CGImage, scale: CGFloat) {
        let window = ScreenshotPinWindow(image: image, scale: scale, controller: self)
        pins.append(window)
        // Cascade so consecutive pins never stack invisibly.
        let offset = CGFloat((pins.count - 1) % 5) * 26
        var origin = window.frame.origin
        origin.x += offset
        origin.y -= offset
        window.setFrameOrigin(origin)
        window.orderFrontRegardless()
    }

    func closeAll() {
        for pin in pins {
            pin.orderOut(nil)
        }
        pins.removeAll()
        refreshEscapeMonitor()
    }

    fileprivate func remove(_ pin: ScreenshotPinWindow) {
        pins.removeAll { $0 === pin }
        refreshEscapeMonitor()
    }

    /// While any pin ignores clicks, a global monitor watches for
    /// Option-click inside it and restores interaction; without this a
    /// click-through pin could never be caught again.
    fileprivate func refreshEscapeMonitor() {
        let needed = pins.contains { $0.ignoresMouseEvents }
        if needed, escapeMonitor == nil {
            escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, event.modifierFlags.contains(.option) else { return }
                let location = NSEvent.mouseLocation
                for pin in self.pins where pin.ignoresMouseEvents && pin.frame.contains(location) {
                    pin.setClickThrough(false)
                }
                self.refreshEscapeMonitor()
            }
        } else if !needed, let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }
}

/// One pinned capture.
final class ScreenshotPinWindow: OverlayPanel {
    static let opacityRange: ClosedRange<CGFloat> = 0.20...1.0
    static let collapsedPillSize = CGSize(width: 156, height: 30)

    static func clampedOpacity(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 1.0 }
        return min(max(value, opacityRange.lowerBound), opacityRange.upperBound)
    }

    private let image: CGImage
    private let scale: CGFloat
    private unowned let controller: ScreenshotPinController
    private var pinContentView: PinContentView?
    private(set) var isCollapsedPill = false
    private var expandedFrame: CGRect?
    private var expandedMinSize = CGSize(width: 90, height: 60)
    private var expandedAspectRatio = CGSize.zero

    private var strings: ScreenshotFeatureStrings {
        FeatureStrings.screenshot(L10n.shared.language)
    }

    private var overhaulStrings: OverhaulV2Strings {
        OverhaulV2Strings.localized(L10n.shared.language)
    }

    init(image: CGImage, scale: CGFloat, controller: ScreenshotPinController) {
        self.image = image
        self.scale = scale
        self.controller = controller

        let screen = NSScreen.pointerVisibleFrame
        var size = CGSize(width: CGFloat(image.width) / scale,
                          height: CGFloat(image.height) / scale)
        let cap = min(screen.width, screen.height) * 0.55
        let ratio = min(1, min(cap / max(size.width, 1), cap / max(size.height, 1)))
        size = CGSize(width: max(90, size.width * ratio), height: max(60, size.height * ratio))
        let rect = CGRect(x: screen.midX - size.width / 2,
                          y: screen.midY - size.height / 2,
                          width: size.width,
                          height: size.height)

        super.init(contentRect: rect,
                   styleMask: [.borderless, .nonactivatingPanel, .resizable],
                   backing: .buffered,
                   defer: false)
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        expandedAspectRatio = CGSize(width: CGFloat(max(1, image.width)),
                                     height: CGFloat(max(1, image.height)))
        contentAspectRatio = expandedAspectRatio
        minSize = expandedMinSize

        let view = PinContentView(image: image, window: self)
        pinContentView = view
        contentView = view
    }

    override var canBecomeKey: Bool { true }

    // MARK: Actions

    func copyImage() {
        guard ScreenshotEditorController.copyImage(
            ScreenshotRenderer.Export(image: image, scale: scale),
            fileNamePrefix: strings.fileNamePrefix) else {
            NSSound.beep()
            return
        }
        QuickToolHUD.show(icon: "camera.viewfinder", message: strings.copiedHUD)
    }

    func saveImage() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = ScreenshotSupport.fileName(
            prefix: strings.fileNamePrefix, date: Date())
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url,
                  let data = ScreenshotRenderer.pngData(from: self.image, scale: self.scale)
            else { return }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                NSSound.beep()
            }
        }
    }

    func setOpacity(_ value: CGFloat, showBadge: Bool = true) {
        let clamped = Self.clampedOpacity(value)
        alphaValue = clamped
        if showBadge {
            pinContentView?.flashOpacityBadge(clamped)
        }
    }

    func adjustOpacity(by delta: CGFloat) {
        setOpacity(alphaValue + delta, showBadge: true)
    }

    func toggleCollapsedPill() {
        if !isCollapsedPill {
            let priorFrame = frame
            expandedFrame = priorFrame
            expandedMinSize = minSize
            if contentAspectRatio.width > 0 && contentAspectRatio.height > 0 {
                expandedAspectRatio = contentAspectRatio
            }
            isCollapsedPill = true
            contentAspectRatio = .zero
            resizeIncrements = NSSize(width: 1, height: 1)
            minSize = Self.collapsedPillSize
            maxSize = Self.collapsedPillSize
            let pillFrame = CGRect(x: priorFrame.minX,
                                   y: priorFrame.maxY - Self.collapsedPillSize.height,
                                   width: Self.collapsedPillSize.width,
                                   height: Self.collapsedPillSize.height)
            pinContentView?.setCollapsedPill(true)
            setFrame(pillFrame, display: true, animate: true)
        } else {
            isCollapsedPill = false
            let targetSize = expandedFrame?.size ?? CGSize(width: 240, height: 180)
            let restoredFrame = CGRect(x: frame.minX,
                                       y: frame.maxY - targetSize.height,
                                       width: targetSize.width,
                                       height: targetSize.height)
            minSize = expandedMinSize
            maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                             height: CGFloat.greatestFiniteMagnitude)
            if expandedAspectRatio.width > 0 && expandedAspectRatio.height > 0 {
                contentAspectRatio = expandedAspectRatio
            }
            pinContentView?.setCollapsedPill(false)
            setFrame(restoredFrame, display: true, animate: true)
            expandedFrame = nil
        }
    }

    func setClickThrough(_ enabled: Bool) {
        ignoresMouseEvents = enabled
        pinContentView?.updateClickThroughAppearance(enabled)
        controller.refreshEscapeMonitor()
        if enabled {
            QuickToolHUD.show(
                icon: "eye.slash",
                message: "\(overhaulStrings.pinGhostClickThrough) (Option-Click)"
            )
        }
    }

    func closePin() {
        orderOut(nil)
        controller.remove(self)
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let step: CGFloat = flags.contains(.shift) ? 12 : 1
        switch Int(event.keyCode) {
        case kVK_Escape:
            closePin()
        case kVK_ANSI_W where flags.contains(.command):
            closePin()
        case kVK_ANSI_C where flags.contains(.command):
            copyImage()
        case kVK_LeftArrow:
            setFrameOrigin(CGPoint(x: frame.origin.x - step, y: frame.origin.y))
        case kVK_RightArrow:
            setFrameOrigin(CGPoint(x: frame.origin.x + step, y: frame.origin.y))
        case kVK_UpArrow:
            setFrameOrigin(CGPoint(x: frame.origin.x, y: frame.origin.y + step))
        case kVK_DownArrow:
            setFrameOrigin(CGPoint(x: frame.origin.x, y: frame.origin.y - step))
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: Content

    private final class PinContentView: NSView {
        /// Weak for the same reason the capture surface is: closing a pin
        /// releases its window from inside this view's own event handling,
        /// so a menu item or a second click can arrive with the window gone.
        private weak var pinWindow: ScreenshotPinWindow?
        private let imageLayer = CALayer()
        private let opacityBadge = NSVisualEffectView()
        private let opacityLabel = NSTextField(labelWithString: "100%")
        private var opacityBadgeDismissWork: DispatchWorkItem?
        private let collapseButton = NSButton()
        private let pillContainer = NSVisualEffectView()
        private let pillTitleLabel = NSTextField(labelWithString: "")
        private let pillExpandButton = NSButton()
        private var trackingArea: NSTrackingArea?
        private var isHovered = false
        private var isCollapsed = false

        init(image: CGImage, window: ScreenshotPinWindow) {
            pinWindow = window
            super.init(frame: .zero)
            wantsLayer = true
            layer?.cornerRadius = 7
            layer?.masksToBounds = true
            layer?.borderWidth = 1
            layer?.borderColor = CGColor(gray: 0.5, alpha: 0.4)

            imageLayer.contents = image
            imageLayer.contentsGravity = .resizeAspect
            imageLayer.frame = bounds
            imageLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            layer?.addSublayer(imageLayer)

            configureOpacityBadge()
            configureHoverCollapseButton()
            configureCollapsedPill(image: image)
            updateAccessibilityState(clickThrough: false, collapsed: false)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        private var strings: ScreenshotFeatureStrings {
            FeatureStrings.screenshot(L10n.shared.language)
        }

        private var overhaulStrings: OverhaulV2Strings {
            OverhaulV2Strings.localized(L10n.shared.language)
        }

        private func configureOpacityBadge() {
            opacityBadge.material = .hudWindow
            opacityBadge.blendingMode = .withinWindow
            opacityBadge.state = .active
            opacityBadge.wantsLayer = true
            opacityBadge.layer?.cornerRadius = 9
            opacityBadge.layer?.masksToBounds = true
            opacityBadge.layer?.borderWidth = 0.5
            opacityBadge.layer?.borderColor = CGColor(gray: 1, alpha: 0.16)
            opacityBadge.alphaValue = 0
            opacityBadge.isHidden = true
            opacityBadge.translatesAutoresizingMaskIntoConstraints = false

            opacityLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
            opacityLabel.textColor = .white
            opacityLabel.alignment = .center
            opacityLabel.translatesAutoresizingMaskIntoConstraints = false
            opacityBadge.addSubview(opacityLabel)
            addSubview(opacityBadge)

            NSLayoutConstraint.activate([
                opacityBadge.topAnchor.constraint(equalTo: topAnchor, constant: 8),
                opacityBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                opacityBadge.heightAnchor.constraint(equalToConstant: 20),
                opacityLabel.leadingAnchor.constraint(equalTo: opacityBadge.leadingAnchor, constant: 7),
                opacityLabel.trailingAnchor.constraint(equalTo: opacityBadge.trailingAnchor, constant: -7),
                opacityLabel.centerYAnchor.constraint(equalTo: opacityBadge.centerYAnchor),
            ])
        }

        private func configureHoverCollapseButton() {
            collapseButton.bezelStyle = .regularSquare
            collapseButton.isBordered = false
            collapseButton.wantsLayer = true
            collapseButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.58).cgColor
            collapseButton.layer?.cornerRadius = 10
            collapseButton.layer?.borderWidth = 0.5
            collapseButton.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
            collapseButton.image = NSImage(systemSymbolName: "arrow.down.right.and.arrow.up.left",
                                           accessibilityDescription: strings.pinButton)
            collapseButton.contentTintColor = .white
            collapseButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9.5, weight: .semibold)
            collapseButton.target = self
            collapseButton.action = #selector(actionToggleCollapse)
            collapseButton.alphaValue = 0
            collapseButton.isHidden = true
            collapseButton.translatesAutoresizingMaskIntoConstraints = false
            addSubview(collapseButton)

            NSLayoutConstraint.activate([
                collapseButton.topAnchor.constraint(equalTo: topAnchor, constant: 7),
                collapseButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
                collapseButton.widthAnchor.constraint(equalToConstant: 24),
                collapseButton.heightAnchor.constraint(equalToConstant: 20),
            ])
        }

        private func configureCollapsedPill(image: CGImage) {
            pillContainer.material = .hudWindow
            pillContainer.blendingMode = .withinWindow
            pillContainer.state = .active
            pillContainer.wantsLayer = true
            pillContainer.layer?.cornerRadius = 15
            pillContainer.layer?.masksToBounds = true
            pillContainer.layer?.borderWidth = 0.75
            pillContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
            pillContainer.isHidden = true
            pillContainer.translatesAutoresizingMaskIntoConstraints = false

            let thumb = NSImageView()
            thumb.wantsLayer = true
            thumb.layer?.cornerRadius = 4
            thumb.layer?.masksToBounds = true
            thumb.imageScaling = .scaleProportionallyUpOrDown
            thumb.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            thumb.translatesAutoresizingMaskIntoConstraints = false

            pillTitleLabel.stringValue = strings.pinButton
            pillTitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            pillTitleLabel.textColor = .labelColor
            pillTitleLabel.lineBreakMode = .byTruncatingTail
            pillTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            pillTitleLabel.translatesAutoresizingMaskIntoConstraints = false

            pillExpandButton.bezelStyle = .regularSquare
            pillExpandButton.isBordered = false
            pillExpandButton.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right",
                                             accessibilityDescription: strings.pinButton)
            pillExpandButton.contentTintColor = .secondaryLabelColor
            pillExpandButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            pillExpandButton.target = self
            pillExpandButton.action = #selector(actionToggleCollapse)
            pillExpandButton.translatesAutoresizingMaskIntoConstraints = false

            pillContainer.addSubview(thumb)
            pillContainer.addSubview(pillTitleLabel)
            pillContainer.addSubview(pillExpandButton)
            addSubview(pillContainer)

            NSLayoutConstraint.activate([
                pillContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
                pillContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
                pillContainer.topAnchor.constraint(equalTo: topAnchor),
                pillContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

                thumb.leadingAnchor.constraint(equalTo: pillContainer.leadingAnchor, constant: 6),
                thumb.centerYAnchor.constraint(equalTo: pillContainer.centerYAnchor),
                thumb.widthAnchor.constraint(equalToConstant: 20),
                thumb.heightAnchor.constraint(equalToConstant: 20),

                pillTitleLabel.leadingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: 6),
                pillTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: pillExpandButton.leadingAnchor, constant: -4),
                pillTitleLabel.centerYAnchor.constraint(equalTo: pillContainer.centerYAnchor),

                pillExpandButton.trailingAnchor.constraint(equalTo: pillContainer.trailingAnchor, constant: -6),
                pillExpandButton.centerYAnchor.constraint(equalTo: pillContainer.centerYAnchor),
                pillExpandButton.widthAnchor.constraint(equalToConstant: 20),
                pillExpandButton.heightAnchor.constraint(equalToConstant: 20),
            ])
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            imageLayer.frame = bounds
            CATransaction.commit()
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea { removeTrackingArea(trackingArea) }
            let area = NSTrackingArea(rect: bounds,
                                      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                      owner: self,
                                      userInfo: nil)
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            isHovered = true
            refreshHoverButtonVisibility()
        }

        override func mouseExited(with event: NSEvent) {
            isHovered = false
            refreshHoverButtonVisibility()
        }

        private func refreshHoverButtonVisibility() {
            let shouldShow = isHovered && !isCollapsed
            if shouldShow {
                collapseButton.isHidden = false
            }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.14
                collapseButton.animator().alphaValue = shouldShow ? 1 : 0
            }, completionHandler: { [weak self] in
                guard let self, !self.isHovered || self.isCollapsed else { return }
                self.collapseButton.isHidden = true
            })
        }

        func setCollapsedPill(_ collapsed: Bool) {
            isCollapsed = collapsed
            imageLayer.isHidden = collapsed
            pillContainer.isHidden = !collapsed
            pillTitleLabel.stringValue = strings.pinButton
            layer?.cornerRadius = collapsed ? 15 : 7
            if collapsed {
                collapseButton.isHidden = true
                collapseButton.alphaValue = 0
                opacityBadgeDismissWork?.cancel()
                opacityBadge.isHidden = true
                opacityBadge.alphaValue = 0
            } else {
                refreshHoverButtonVisibility()
            }
            updateAccessibilityState(clickThrough: pinWindow?.ignoresMouseEvents ?? false,
                                     collapsed: collapsed)
        }

        func updateClickThroughAppearance(_ enabled: Bool) {
            layer?.borderWidth = enabled ? 1.5 : 1
            layer?.borderColor = enabled
                ? NSColor.systemCyan.withAlphaComponent(0.55).cgColor
                : CGColor(gray: 0.5, alpha: 0.4)
            pillContainer.layer?.borderColor = enabled
                ? NSColor.systemCyan.withAlphaComponent(0.55).cgColor
                : NSColor.white.withAlphaComponent(0.20).cgColor
            updateAccessibilityState(clickThrough: enabled, collapsed: isCollapsed)
        }

        private func updateAccessibilityState(clickThrough: Bool, collapsed: Bool) {
            var notes: [String] = []
            if collapsed { notes.append("Collapsed") }
            if clickThrough { notes.append(overhaulStrings.pinGhostClickThrough) }
            setAccessibilityLabel(strings.pinButton)
            setAccessibilityValue(notes.isEmpty ? nil : notes.joined(separator: ", "))
        }

        func flashOpacityBadge(_ opacity: CGFloat) {
            guard !isCollapsed else { return }
            let percent = Int((opacity * 100).rounded())
            opacityLabel.stringValue = "\(percent)%"
            opacityBadgeDismissWork?.cancel()
            opacityBadge.isHidden = false
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.10
                opacityBadge.animator().alphaValue = 1
            }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.22
                    self.opacityBadge.animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    guard let self, self.opacityBadge.alphaValue <= 0.01 else { return }
                    self.opacityBadge.isHidden = true
                })
            }
            opacityBadgeDismissWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85, execute: work)
        }

        override func scrollWheel(with event: NSEvent) {
            guard event.momentumPhase.isEmpty else { return }
            let raw = event.scrollingDeltaY
            guard raw.isFinite, raw != 0 else { return }
            let step = event.hasPreciseScrollingDeltas
                ? raw * 0.004
                : max(-3, min(3, raw)) * 0.05
            pinWindow?.adjustOpacity(by: step)
        }

        override func mouseDown(with event: NSEvent) {
            guard let pinWindow else { return }
            if pinWindow.isCollapsedPill {
                pinWindow.makeKey()
                let startMouse = NSEvent.mouseLocation
                let startOrigin = pinWindow.frame.origin
                var dragged = false
                while let next = pinWindow.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
                    if next.type == .leftMouseDragged {
                        let now = NSEvent.mouseLocation
                        let dx = now.x - startMouse.x
                        let dy = now.y - startMouse.y
                        if !dragged, hypot(dx, dy) >= 3 { dragged = true }
                        if dragged {
                            pinWindow.setFrameOrigin(CGPoint(x: startOrigin.x + dx,
                                                             y: startOrigin.y + dy))
                        }
                    } else {
                        break
                    }
                }
                if !dragged {
                    pinWindow.toggleCollapsedPill()
                }
                return
            }
            if event.clickCount == 2 {
                if event.modifierFlags.contains(.option) {
                    pinWindow.toggleCollapsedPill()
                } else {
                    pinWindow.closePin()
                }
                return
            }
            pinWindow.makeKey()
            super.mouseDown(with: event)
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            guard let pinWindow else { return nil }
            let menu = NSMenu()
            menu.addItem(withTitle: strings.copyButton,
                         action: #selector(menuCopy), keyEquivalent: "").target = self
            menu.addItem(withTitle: strings.saveAsButton,
                         action: #selector(menuSave), keyEquivalent: "").target = self
            menu.addItem(.separator())

            let collapseItem = NSMenuItem(
                title: pinWindow.isCollapsedPill ? "Expand Pin" : "Collapse to Pill",
                action: #selector(actionToggleCollapse),
                keyEquivalent: ""
            )
            collapseItem.target = self
            collapseItem.state = pinWindow.isCollapsedPill ? .on : .off
            menu.addItem(collapseItem)

            let opacityItem = NSMenuItem(title: strings.pinOpacity, action: nil, keyEquivalent: "")
            let opacityMenu = NSMenu()
            for percent in [100, 85, 70, 50] {
                let item = NSMenuItem(title: "\(percent)%",
                                      action: #selector(menuOpacity(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = percent
                item.state = Int((pinWindow.alphaValue * 100).rounded()) == percent ? .on : .off
                opacityMenu.addItem(item)
            }
            opacityItem.submenu = opacityMenu
            menu.addItem(opacityItem)

            let clickThrough = NSMenuItem(title: strings.pinClickThrough,
                                          action: #selector(menuClickThrough),
                                          keyEquivalent: "")
            clickThrough.target = self
            clickThrough.state = pinWindow.ignoresMouseEvents ? .on : .off
            menu.addItem(clickThrough)
            menu.addItem(.separator())

            menu.addItem(withTitle: L10n.shared.s.menuClose,
                         action: #selector(menuClose), keyEquivalent: "").target = self
            menu.addItem(withTitle: strings.pinCloseAll,
                         action: #selector(menuCloseAll), keyEquivalent: "").target = self
            return menu
        }

        @objc private func menuCopy() { pinWindow?.copyImage() }
        @objc private func menuSave() { pinWindow?.saveImage() }
        @objc private func menuClose() { pinWindow?.closePin() }
        @objc private func menuCloseAll() { ScreenshotPinController.shared.closeAll() }
        @objc private func actionToggleCollapse() { pinWindow?.toggleCollapsedPill() }

        @objc private func menuOpacity(_ sender: NSMenuItem) {
            guard let pinWindow, let percent = sender.representedObject as? Int else { return }
            pinWindow.setOpacity(CGFloat(percent) / 100)
        }

        @objc private func menuClickThrough() {
            guard let pinWindow else { return }
            pinWindow.setClickThrough(!pinWindow.ignoresMouseEvents)
        }
    }
}
