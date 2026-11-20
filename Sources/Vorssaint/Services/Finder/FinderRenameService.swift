// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Turns one chosen key combination into Finder's native Rename command.
/// Unrelated keys stay on the tap thread's fast path, and the tap only lives
/// while the feature is on and Accessibility is available.
final class FinderRenameService {
    static let shared = FinderRenameService()

    private static let finderBundleID = "com.apple.finder"

    private let routeLock = NSLock()
    private var routeShortcut = GlobalShortcut.finderRenameDefault

    private let lifecycleLock = NSLock()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
    }

    func syncWithPreferences() {
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.finderRenameShortcut,
                                            fallback: .finderRenameDefault)
        routeLock.withLock { routeShortcut = shortcut }
        let enabled = AppFeature.finderRename.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.finderRenameEnabled)
        if SessionActivitySupport.tapShouldRun(featureWanted: enabled,
                                               accessibilityGranted: AXIsProcessTrusted(),
                                               sessionIsActive: SessionActivity.shared.isActive) {
            // This tap is tail-append, so the WindowServer answers a symbolic
            // hotkey long before the key reaches it: on a taken-over key the
            // claim is what makes the key arrive at all.
            SystemShortcutTakeover.claim(DefaultsKey.finderRenameShortcut, shortcut: shortcut)
            installTap()
        } else {
            removeTap()
        }
    }

    func suspend() {
        removeTap()
    }

    private func installTap() {
        guard lifecycleLock.withLock({ tap == nil }) else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            // The Super Key decorates shortcuts before this tap sees them.
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<FinderRenameService>
                    .fromOpaque(userInfo).takeUnretainedValue()
                return service.route(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            // Without a tap nobody answers a taken-over key, so give it
            // back rather than leaving the shortcut dead.
            SystemShortcutTakeover.release(DefaultsKey.finderRenameShortcut)
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        lifecycleLock.withLock {
            self.tap = tap
            runLoopSource = source
        }
        if let source {
            KeyboardTapRunLoop.add(source)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeTap() {
        // The claim goes with the tap, so a key held for a rename that is no
        // longer listening — switched off, or suspended for an uninstall —
        // goes back to macOS.
        SystemShortcutTakeover.release(DefaultsKey.finderRenameShortcut)
        let (port, source) = lifecycleLock.withLock { () -> (CFMachPort?, CFRunLoopSource?) in
            let current = (tap, runLoopSource)
            tap = nil
            runLoopSource = nil
            return current
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        if let source {
            KeyboardTapRunLoop.remove(source, invalidating: port)
        } else if let port {
            CFMachPortInvalidate(port)
        }
    }

    /// Runs on the tap thread. Every unrelated key returns after an in-memory
    /// comparison; Finder and Accessibility are consulted only for the chosen
    /// combination.
    private func route(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // removeTap() switches the tap off itself, and that is reported
            // here like a disable by the system. A stop under way has nothing
            // to recover: syncing would start the tap again under a suspend().
            let currentTap = lifecycleLock.withLock { tap }
            if SessionActivity.shared.isActive, AXIsProcessTrusted(), let currentTap {
                CGEvent.tapEnable(tap: currentTap, enable: true)
            } else if currentTap != nil {
                DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let shortcut = routeLock.withLock { routeShortcut }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let modifiers = GlobalShortcutModifiers(cgFlags: event.flags)
        guard shortcut.matches(keyCode: keyCode, modifiers: modifiers),
              AXIsProcessTrusted(),
              let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier == Self.finderBundleID,
              FinderRenameSupport.acceptsFocusedRole(focusedRole(for: front.processIdentifier)),
              let replacement = event.copy()
        else { return Unmanaged.passUnretained(event) }

        replacement.setIntegerValueField(.keyboardEventKeycode, value: Int64(kVK_Return))
        replacement.flags = []
        return Unmanaged.passRetained(replacement)
    }

    private func focusedRole(for pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.12)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString,
                                            &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.12)
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString,
                                            &role) == .success,
              let role, CFGetTypeID(role) == CFStringGetTypeID()
        else { return nil }
        return role as? String
    }
}
