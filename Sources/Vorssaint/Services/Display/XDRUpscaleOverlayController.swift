// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation
import Metal
import QuartzCore

/// Per-screen EDR Metal multiply overlay that unlocks sustained 1000-1600 nit
/// peak headroom on XDR-capable displays.
final class XDRUpscaleOverlayController: ObservableObject, @unchecked Sendable {
    static let shared = XDRUpscaleOverlayController()

    static let minBoostAmount: Double = 1.0
    static let maxBoostAmount: Double = 2.0
    static let defaultBoostAmount: Double = 1.45

    private static let enabledDefaultsKey = "xdrUpscaleOverlayEnabled"
    private static let boostAmountDefaultsKey = "xdrUpscaleBoostAmount"
    private static let autoBoostBundleIDsDefaultsKey = "xdrAutoBoostBundleIDs"

    private struct ScreenSpec: Equatable {
        let displayID: CGDirectDisplayID
        let frame: CGRect
    }

    private struct OverlayEntry {
        let screenSpec: ScreenSpec
        let window: NSWindow
        let layer: CAMetalLayer
        let triggerWindow: NSWindow
        let triggerLayer: CAMetalLayer
    }

    @Published var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledDefaultsKey)
            syncWorkspaceActivationObserver()
            syncOverlays()
        }
    }

    @Published var boostAmount: Double {
        didSet {
            let clamped = Self.clampBoost(boostAmount)
            if clamped != boostAmount {
                boostAmount = clamped
                return
            }
            guard oldValue != boostAmount else { return }
            UserDefaults.standard.set(boostAmount, forKey: Self.boostAmountDefaultsKey)
            if isEffectiveBoostActive {
                runOnMainActor { [weak self] in
                    self?.renderOverlays(waitUntilScheduled: false)
                }
            }
        }
    }

    @Published var xdrAutoBoostBundleIDs: Set<String> {
        didSet {
            let sanitized = Set(
                xdrAutoBoostBundleIDs
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
            if sanitized != xdrAutoBoostBundleIDs {
                xdrAutoBoostBundleIDs = sanitized
                return
            }
            guard oldValue != xdrAutoBoostBundleIDs else { return }
            UserDefaults.standard.set(xdrAutoBoostBundleIDs.sorted(), forKey: Self.autoBoostBundleIDsDefaultsKey)
            syncWorkspaceActivationObserver()
            if !xdrAutoBoostBundleIDs.isEmpty, frontmostBundleID == nil {
                evaluateFrontmostBundleID(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
            } else {
                evaluateFrontmostBundleID(frontmostBundleID)
            }
        }
    }

    @Published private(set) var frontmostBundleID: String?
    @Published private(set) var isAutoBoostTriggeredByFrontmostApp: Bool = false
    @Published private(set) var isXDRCapable: Bool = false

    private var isEffectiveBoostActive: Bool {
        isEnabled || isAutoBoostTriggeredByFrontmostApp
    }

    private var entries: [OverlayEntry] = []
    private var metalDevice: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var heartbeatTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var workspaceActivationObserver: NSObjectProtocol?
    private var screensAsleep = false

    init() {
        let defaults = UserDefaults.standard
        let storedEnabled = defaults.bool(forKey: Self.enabledDefaultsKey)
        let rawBoost = defaults.object(forKey: Self.boostAmountDefaultsKey) as? Double ?? Self.defaultBoostAmount
        let storedBundleIDs = Set(
            (defaults.stringArray(forKey: Self.autoBoostBundleIDsDefaultsKey) ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        self.isEnabled = storedEnabled
        self.boostAmount = Self.clampBoost(rawBoost)
        self.xdrAutoBoostBundleIDs = storedBundleIDs
        runOnMainActor { [self] in
            self.isXDRCapable = Self.hasXDRCapableScreen()
            self.installObservers()
            self.syncWorkspaceActivationObserver()
            if !storedBundleIDs.isEmpty {
                self.evaluateFrontmostBundleID(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
            } else {
                self.syncOverlaysOnMainActor()
            }
        }
    }

    private func runOnMainActor(_ operation: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(operation)
        } else {
            Task { @MainActor in
                operation()
            }
        }
    }

    func setAutoBoost(bundleID: String, enabled: Bool) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if enabled {
            xdrAutoBoostBundleIDs.insert(trimmed)
        } else {
            xdrAutoBoostBundleIDs.remove(trimmed)
        }
    }

    func toggleAutoBoost(bundleID: String) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        setAutoBoost(bundleID: trimmed, enabled: !xdrAutoBoostBundleIDs.contains(trimmed))
    }

    func evaluateFrontmostBundleID(_ bundleID: String?) {
        let trimmed = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = (trimmed?.isEmpty == false) ? trimmed : nil
        if frontmostBundleID != normalized {
            frontmostBundleID = normalized
        }
        let shouldAutoBoost = normalized.map { xdrAutoBoostBundleIDs.contains($0) } ?? false
        if isAutoBoostTriggeredByFrontmostApp != shouldAutoBoost {
            isAutoBoostTriggeredByFrontmostApp = shouldAutoBoost
        }
        syncOverlays()
    }

    @MainActor
    static func hasXDRCapableScreen() -> Bool {
        NSScreen.screens.contains { $0.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0 }
    }

    private static func clampBoost(_ value: Double) -> Double {
        guard value.isFinite else { return defaultBoostAmount }
        return min(max(value, minBoostAmount), maxBoostAmount)
    }

    @MainActor
    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    @MainActor
    private static func xdrScreens() -> [(screen: NSScreen, spec: ScreenSpec)] {
        NSScreen.screens.compactMap { screen in
            guard screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0,
                  let id = displayID(of: screen) else {
                return nil
            }
            return (screen, ScreenSpec(displayID: id, frame: screen.frame))
        }
    }

    func syncOverlays() {
        runOnMainActor { [weak self] in
            self?.syncOverlaysOnMainActor()
        }
    }

    func tearDown() {
        runOnMainActor { [weak self] in
            self?.tearDownOnMainActor()
        }
    }

    @MainActor
    private func syncOverlaysOnMainActor() {
        isXDRCapable = Self.hasXDRCapableScreen()
        guard isEffectiveBoostActive, isXDRCapable else {
            tearDownOnMainActor()
            return
        }

        let targetScreens = Self.xdrScreens()
        let targetSpecs = targetScreens.map(\.spec)
        guard !targetScreens.isEmpty else {
            tearDownOnMainActor()
            return
        }

        if entries.map(\.screenSpec) == targetSpecs, heartbeatTimer != nil {
            renderOverlays(waitUntilScheduled: false)
            return
        }

        tearDownOnMainActor()
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            return
        }
        metalDevice = device
        commandQueue = queue

        for (screen, spec) in targetScreens {
            guard let entry = makeOverlayEntry(for: screen, spec: spec, device: device) else {
                continue
            }
            entries.append(entry)
        }

        guard !entries.isEmpty else {
            tearDownOnMainActor()
            return
        }

        renderOverlays(waitUntilScheduled: true)
        for entry in entries {
            entry.window.orderFrontRegardless()
            entry.triggerWindow.orderFrontRegardless()
        }
        startHeartbeat()
    }

    @MainActor
    private func tearDownOnMainActor() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil

        for entry in entries {
            entry.window.orderOut(nil)
            entry.window.close()
            entry.triggerWindow.orderOut(nil)
            entry.triggerWindow.close()
        }
        entries.removeAll()
        commandQueue = nil
        metalDevice = nil
    }

    @MainActor
    private func makeOverlayEntry(
        for screen: NSScreen,
        spec: ScreenSpec,
        device: MTLDevice
    ) -> OverlayEntry? {
        let frame = screen.frame
        guard frame.width > 0, frame.height > 0 else { return nil }

        let window = makeOverlayWindow(contentRect: frame)
        let layer = makeEDRMetalLayer(device: device, frameSize: frame.size, drawableSize: CGSize(width: 2, height: 2), multiply: true)
        let contentView = NSView(frame: NSRect(origin: .zero, size: frame.size))
        contentView.wantsLayer = true
        contentView.layer = layer
        window.contentView = contentView

        let triggerFrame = NSRect(x: frame.maxX - 1, y: frame.minY, width: 1, height: 1)
        let triggerWindow = makeOverlayWindow(contentRect: triggerFrame)
        let triggerLayer = makeEDRMetalLayer(device: device, frameSize: CGSize(width: 1, height: 1), drawableSize: CGSize(width: 1, height: 1), multiply: false)
        let triggerView = NSView(frame: NSRect(origin: .zero, size: triggerFrame.size))
        triggerView.wantsLayer = true
        triggerView.layer = triggerLayer
        triggerWindow.contentView = triggerView

        return OverlayEntry(
            screenSpec: spec,
            window: window,
            layer: layer,
            triggerWindow: triggerWindow,
            triggerLayer: triggerLayer
        )
    }

    @MainActor
    private func makeOverlayWindow(contentRect: NSRect) -> NSWindow {
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.sharingType = .readOnly
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        return window
    }

    private func makeEDRMetalLayer(
        device: MTLDevice,
        frameSize: CGSize,
        drawableSize: CGSize,
        multiply: Bool
    ) -> CAMetalLayer {
        let layer = CAMetalLayer()
        layer.device = device
        layer.wantsExtendedDynamicRangeContent = true
        layer.pixelFormat = .rgba16Float
        layer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        layer.isOpaque = false
        layer.drawableSize = drawableSize
        layer.frame = CGRect(origin: .zero, size: frameSize)
        if multiply {
            layer.compositingFilter = "multiply"
        }
        return layer
    }

    @MainActor
    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.renderOverlays(waitUntilScheduled: false)
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    @MainActor
    private func renderOverlays(waitUntilScheduled: Bool) {
        guard isEffectiveBoostActive, !screensAsleep, !entries.isEmpty, let queue = commandQueue else { return }
        let screensByID: [CGDirectDisplayID: NSScreen] = Dictionary(
            uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
                Self.displayID(of: screen).map { ($0, screen) }
            }
        )

        guard let commands = queue.makeCommandBuffer() else { return }
        var presentedAny = false

        for entry in entries {
            let screen = screensByID[entry.screenSpec.displayID]
            let currentEDR = Double(screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1.0)
            let potentialEDR = Double(screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1.0)

            let factor: Double
            if potentialEDR <= 1.0 {
                factor = 1.0
            } else if currentEDR <= 1.05 {
                factor = min(boostAmount, 1.15)
            } else {
                factor = min(boostAmount, max(1.0, currentEDR))
            }

            if let drawable = entry.layer.nextDrawable() {
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = drawable.texture
                pass.colorAttachments[0].loadAction = .clear
                pass.colorAttachments[0].storeAction = .store
                pass.colorAttachments[0].clearColor = MTLClearColor(
                    red: factor,
                    green: factor,
                    blue: factor,
                    alpha: 1.0
                )
                if let encoder = commands.makeRenderCommandEncoder(descriptor: pass) {
                    encoder.endEncoding()
                    commands.present(drawable)
                    presentedAny = true
                }
            }

            if let triggerDrawable = entry.triggerLayer.nextDrawable() {
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = triggerDrawable.texture
                pass.colorAttachments[0].loadAction = .clear
                pass.colorAttachments[0].storeAction = .store
                pass.colorAttachments[0].clearColor = MTLClearColor(red: 1.8, green: 1.8, blue: 1.8, alpha: 1.0)
                if let encoder = commands.makeRenderCommandEncoder(descriptor: pass) {
                    encoder.endEncoding()
                    commands.present(triggerDrawable)
                    presentedAny = true
                }
            }
        }

        guard presentedAny else { return }
        commands.commit()
        if waitUntilScheduled {
            commands.waitUntilScheduled()
        }
    }

    @MainActor
    private func installObservers() {
        let center = NotificationCenter.default
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        observers.append(
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleScreenParametersChanged()
                }
            }
        )
        observers.append(
            center.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.tearDownOnMainActor()
                    self?.removeWorkspaceActivationObserver()
                }
            }
        )
        observers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.screensDidSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.screensAsleep = true
                }
            }
        )
        observers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.screensDidWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.screensAsleep = false
                    self?.syncOverlaysOnMainActor()
                }
            }
        )
    }

    private func syncWorkspaceActivationObserver() {
        let shouldObserve = isEnabled || !xdrAutoBoostBundleIDs.isEmpty
        if shouldObserve {
            guard workspaceActivationObserver == nil else { return }
            workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let bundleID = app?.bundleIdentifier ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                if Thread.isMainThread {
                    self?.evaluateFrontmostBundleID(bundleID)
                } else {
                    DispatchQueue.main.async {
                        self?.evaluateFrontmostBundleID(bundleID)
                    }
                }
            }
        } else {
            removeWorkspaceActivationObserver()
        }
    }

    private func removeWorkspaceActivationObserver() {
        if let token = workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            workspaceActivationObserver = nil
        }
    }

    @MainActor
    private func handleScreenParametersChanged() {
        let nextCapability = Self.hasXDRCapableScreen()
        isXDRCapable = nextCapability
        guard isEffectiveBoostActive, nextCapability else {
            tearDownOnMainActor()
            return
        }
        let nextSpecs = Self.xdrScreens().map(\.spec)
        if entries.map(\.screenSpec) != nextSpecs {
            tearDownOnMainActor()
            syncOverlaysOnMainActor()
        } else {
            renderOverlays(waitUntilScheduled: false)
        }
    }
}
