// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Foundation
import QuartzCore

/// Records formatted keystroke and modifier shortcut events while recording.
/// Strictly gated on macOS Secure Event Input so passwords and secure prompts
/// are never observed, formatted, or persisted.
final class RecorderKeystrokeSampler {
    private let pauseClock: RecorderPauseClock
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let lock = NSLock()
    private var events: [RecorderKeystrokeEvent] = []
    private var pendingModifierPeak: [String] = []
    private var pendingModifierTime: Double?
    private var pendingModifierConsumed = false

    init(pauseClock: RecorderPauseClock) {
        self.pauseClock = pauseClock
    }

    func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown, .flagsChanged]
        ) { [weak self] event in
            self?.record(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged]
        ) { [weak self] event in
            self?.record(event)
            return event
        }
    }

    func stop() -> [RecorderKeystrokeEvent] {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        return lock.withLock {
            let collected = events
            events.removeAll()
            pendingModifierPeak.removeAll()
            pendingModifierTime = nil
            pendingModifierConsumed = false
            return collected
        }
    }

    private func record(_ event: NSEvent) {
        // Security gate MUST run on every event before reading, formatting, or buffering.
        guard RecorderKeystrokeCaptureGate.canRecordKeystrokes(
            secureInputActive: IsSecureEventInputEnabled()
        ) else { return }

        if event.type == .keyDown, event.isARepeat { return }

        let now = CACurrentMediaTime()
        guard let time = pauseClock.eventTime(now) else { return }

        if event.type == .flagsChanged {
            let mods = Self.modifierGlyphs(from: event.modifierFlags)
            lock.withLock {
                if mods.isEmpty {
                    if !pendingModifierPeak.isEmpty, !pendingModifierConsumed {
                        events.append(RecorderKeystrokeEvent(
                            timestamp: pendingModifierTime ?? time,
                            label: "",
                            modifiers: pendingModifierPeak
                        ))
                    }
                    pendingModifierPeak.removeAll()
                    pendingModifierTime = nil
                    pendingModifierConsumed = false
                } else {
                    if pendingModifierTime == nil {
                        pendingModifierTime = time
                        pendingModifierConsumed = false
                    }
                    if mods.count >= pendingModifierPeak.count {
                        pendingModifierPeak = mods
                    }
                }
            }
            return
        }

        guard event.type == .keyDown,
              let formatted = Self.formattedEvent(
                keyCode: event.keyCode,
                modifierFlags: event.modifierFlags,
                characters: event.characters,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                isFlagsChanged: false,
                at: time,
                secureInputActive: IsSecureEventInputEnabled()
              )
        else { return }

        lock.withLock {
            pendingModifierConsumed = true
            events.append(formatted)
        }
    }

    deinit {
        let g = globalMonitor
        let l = localMonitor
        globalMonitor = nil
        localMonitor = nil
        if g != nil || l != nil {
            if Thread.isMainThread {
                if let g { NSEvent.removeMonitor(g) }
                if let l { NSEvent.removeMonitor(l) }
            } else {
                DispatchQueue.main.async {
                    if let g { NSEvent.removeMonitor(g) }
                    if let l { NSEvent.removeMonitor(l) }
                }
            }
        }
    }

    // MARK: - Formatting & Persistence

    static func formattedEvent(keyCode: UInt16,
                               modifierFlags: NSEvent.ModifierFlags,
                               characters: String?,
                               charactersIgnoringModifiers: String?,
                               isFlagsChanged: Bool,
                               at timestamp: Double,
                               secureInputActive: Bool = IsSecureEventInputEnabled()) -> RecorderKeystrokeEvent? {
        guard RecorderKeystrokeCaptureGate.canRecordKeystrokes(secureInputActive: secureInputActive) else {
            return nil
        }

        let modifiers = modifierGlyphs(from: modifierFlags)
        if isFlagsChanged {
            guard !modifiers.isEmpty else { return nil }
            return RecorderKeystrokeEvent(timestamp: timestamp, label: "", modifiers: modifiers)
        }

        let label = keyGlyph(
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            modifiers: modifiers,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers
        )
        guard let label, !label.isEmpty || !modifiers.isEmpty else { return nil }
        let event = RecorderKeystrokeEvent(timestamp: timestamp, label: label, modifiers: modifiers)
        return event.formattedCapString.isEmpty ? nil : event
    }

    static func modifierGlyphs(from flags: NSEvent.ModifierFlags) -> [String] {
        var result: [String] = []
        if flags.contains(.command) { result.append("⌘") }
        if flags.contains(.control) { result.append("⌃") }
        if flags.contains(.option) { result.append("⌥") }
        if flags.contains(.shift) { result.append("⇧") }
        return result
    }

    private static func keyGlyph(keyCode: UInt16,
                                 modifierFlags: NSEvent.ModifierFlags,
                                 modifiers: [String],
                                 characters: String?,
                                 charactersIgnoringModifiers: String?) -> String? {
        switch Int(keyCode) {
        case kVK_Space:
            return modifiers.isEmpty ? "␣" : "Space"
        case kVK_Return:
            return "⏎"
        case kVK_ANSI_KeypadEnter:
            return "⌤"
        case kVK_Tab:
            return "⇥"
        case kVK_Escape:
            return "⎋"
        case kVK_Delete:
            return "⌫"
        case kVK_ForwardDelete:
            return "⌦"
        case kVK_LeftArrow:
            return "←"
        case kVK_RightArrow:
            return "→"
        case kVK_UpArrow:
            return "↑"
        case kVK_DownArrow:
            return "↓"
        case kVK_Home:
            return "↖"
        case kVK_End:
            return "↘"
        case kVK_PageUp:
            return "⇞"
        case kVK_PageDown:
            return "⇟"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"
        default:
            break
        }

        let hasPrimaryModifier = modifierFlags.contains(.command)
            || modifierFlags.contains(.control)
            || modifierFlags.contains(.option)

        if hasPrimaryModifier, Thread.isMainThread,
           let layout = GlobalShortcut.layoutKeyLabel(for: Int64(keyCode),
                                                    usesCommand: modifierFlags.contains(.command)) {
            return layout
        }

        let raw = hasPrimaryModifier
            ? (charactersIgnoringModifiers ?? characters)
            : (characters ?? charactersIgnoringModifiers)
        guard let raw else { return nil }

        let printable = String(raw.unicodeScalars.filter { scalar in
            scalar.value >= 0x20 && scalar.value != 0x7F && !CharacterSet.controlCharacters.contains(scalar)
        }).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !printable.isEmpty else { return nil }
        return printable.count == 1 ? printable.uppercased() : printable
    }

    static func encoded(_ events: [RecorderKeystrokeEvent]) -> Data? {
        try? JSONEncoder().encode(events)
    }

    static func decoded(_ data: Data?) -> [RecorderKeystrokeEvent] {
        guard let data else { return [] }
        if let direct = try? JSONDecoder().decode([RecorderKeystrokeEvent].self, from: data) {
            return direct
        }
        struct Wrapper: Codable { var events: [RecorderKeystrokeEvent] }
        if let wrapped = try? JSONDecoder().decode(Wrapper.self, from: data) {
            return wrapped.events
        }
        return []
    }
}
