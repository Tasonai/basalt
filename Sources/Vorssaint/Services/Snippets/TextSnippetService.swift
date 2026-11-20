// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AudioToolbox
import Carbon.HIToolbox
import CoreGraphics

/// Text snippets: typing a trigger replaces it with its expansion, with
/// {{date}}, {{time}}, {{datetime}} and {{clipboard}} filled in. The key tap,
/// the observers and the snippet cache only exist while the feature is on;
/// off means nothing lives. Requires Accessibility (the tap).
final class TextSnippetService {
    static let shared = TextSnippetService()

    /// Marks our own synthetic events so the tap never re-processes them.
    private static let syntheticMarker = OwnKeyEvent.textSnippetMarker

    // The tap callback and its mutable text state live off the main thread so
    // demanding foreground apps cannot turn a main-thread stall into queued
    // keyboard input for the whole session.
    private let tapLifecycleLock = NSLock()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activationObserver: NSObjectProtocol?
    private var windowKeyObservers: [NSObjectProtocol] = []
    private let inputLock = NSLock()
    private var buffer = ""
    private var libraryVisible = false
    private var commandBarVisible = false
    private var fillInVisible = false
    private var ownKeyWindowActive = false
    /// Registered once when the preferences change, so no expansion pays
    /// for the file read. nil means no sound plays.
    private var expansionSound: AlertSound?
    /// Split by expansion mode at load time; the tap callback only scans.
    private var immediateSnippets: [TextSnippet] = []
    private var delimiterSnippets: [TextSnippet] = []
    private var snippetsByTrigger: [String: String] = [:]

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
    }

    var isRunning: Bool { tapLifecycleLock.withLock { tap != nil } }

    func syncWithPreferences() {
        let enabled = AppFeature.textSnippets.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.textSnippetsEnabled)
        reloadSnippets()
        let hasWork = inputLock.withLock {
            !(immediateSnippets.isEmpty && delimiterSnippets.isEmpty)
        }
        syncExpansionSound(featureEnabled: enabled)
        if SessionActivitySupport.tapShouldRun(featureWanted: enabled && hasWork,
                                               accessibilityGranted: AXIsProcessTrusted(),
                                               sessionIsActive: SessionActivity.shared.isActive) {
            let libraryIsVisible = SnippetLibraryService.shared.isVisible
            let commandBarIsVisible = AppFeature.commandBar.isAvailable
                && CommandBarService.shared.isVisible
            let ownKeyActive = Thread.isMainThread
                ? MainActor.assumeIsolated { NSApp?.keyWindow != nil }
                : false
            inputLock.withLock {
                libraryVisible = libraryIsVisible
                commandBarVisible = commandBarIsVisible
                ownKeyWindowActive = ownKeyActive
            }
            start()
        } else {
            stop()
        }
    }

    /// Plays the sound an expansion would play, for the picker's preview.
    /// Plays the retained one, so the preview cannot demonstrate a sound
    /// other than the one that will fire; it resolves for itself only
    /// when nothing is retained, which is when the feature is off.
    func previewExpansionSound() {
        let retained = inputLock.withLock { expansionSound }
        (retained ?? Self.preferredExpansionSound())?.play()
    }

    /// The sound the stored preference resolves to. Both the preview and
    /// the armed sound come through here, so they cannot disagree about
    /// which name wins when the stored one is not available.
    private static func preferredExpansionSound() -> AlertSound? {
        TextSnippetSupport.resolvedSoundName(
            stored: UserDefaults.standard.string(forKey: DefaultsKey.snippetSoundName))
            .flatMap { AlertSound(name: $0) }
    }

    /// Picks up a change to the sound preferences on their own. The picker
    /// fires on every arrow-key move through the list, and going through
    /// syncWithPreferences would reload every snippet and tear down and
    /// rebuild the event tap each time.
    ///
    /// `featureEnabled` is whether text snippets are on at all. Passed in
    /// by syncWithPreferences, which has already worked it out, so the two
    /// cannot answer that question differently.
    func syncExpansionSound(featureEnabled: Bool? = nil) {
        let featureOn = featureEnabled ?? (AppFeature.textSnippets.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.textSnippetsEnabled))
        let soundEnabled = featureOn
            && UserDefaults.standard.bool(forKey: DefaultsKey.snippetSoundEnabled)
        let sound = soundEnabled ? Self.preferredExpansionSound() : nil
        inputLock.withLock { expansionSound = sound }
    }

    func suspend() { stop() }

    func setLibraryVisible(_ visible: Bool) {
        inputLock.withLock {
            libraryVisible = visible
            if visible { buffer = "" }
        }
    }

    func setCommandBarVisible(_ visible: Bool) {
        inputLock.withLock {
            commandBarVisible = visible
            if visible { buffer = "" }
        }
    }

    /// Reloads the stored snippets; called by the settings page after edits.
    private func reloadSnippets() {
        let all = TextSnippetSupport.decode(
            UserDefaults.standard.data(forKey: DefaultsKey.textSnippets))
        var byTrigger: [String: String] = [:]
        for snippet in all where snippet.enabled && !snippet.trigger.isEmpty {
            byTrigger[snippet.trigger] = snippet.replacement
        }
        inputLock.withLock {
            immediateSnippets = all.filter { $0.enabled && $0.expansion == .immediate }
            delimiterSnippets = all.filter { $0.enabled && $0.expansion == .afterDelimiter }
            snippetsByTrigger = byTrigger
        }
    }

    private func start() {
        guard tapLifecycleLock.withLock({ tap == nil }) else { return }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<TextSnippetService>.fromOpaque(userInfo)
                    .takeUnretainedValue()
                return service.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        tapLifecycleLock.withLock {
            self.tap = tap
            self.runLoopSource = source
        }
        if let source {
            KeyboardTapRunLoop.add(source)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        if Thread.isMainThread {
            tapDidStart(tap)
        } else {
            DispatchQueue.main.async { [weak self] in self?.tapDidStart(tap) }
        }
    }

    private func stop() {
        let (port, source) = tapLifecycleLock.withLock { () -> (CFMachPort?, CFRunLoopSource?) in
            let current = (tap, runLoopSource)
            tap = nil
            runLoopSource = nil
            return current
        }
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let source {
            KeyboardTapRunLoop.remove(source, invalidating: port)
        } else if let port {
            CFMachPortInvalidate(port)
        }
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        for observer in windowKeyObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowKeyObservers.removeAll()
        resetBuffer()
    }

    private func tapDidStart(_ startedTap: CFMachPort) {
        let active = tapLifecycleLock.withLock {
            tap === startedTap
        }
        guard active, activationObserver == nil else { return }
        // Switching apps invalidates whatever was half-typed there.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            // Not when the Accessibility Keyboard itself comes forward: pressing
            // one of its keys is typing into the app you were already in, so the
            // buffer has to survive it. Otherwise this clears what the mouse-down
            // branch above just took care to keep.
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier == AssistiveKeyboard.bundleID {
                return
            }
            self?.resetBuffer()
        }
        if windowKeyObservers.isEmpty {
            let syncOwnKeyWindow: (Notification) -> Void = { [weak self] _ in
                let activeKey = MainActor.assumeIsolated { NSApp?.keyWindow != nil }
                self?.inputLock.withLock { self?.ownKeyWindowActive = activeKey }
            }
            windowKeyObservers = [
                NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification,
                                                       object: nil, queue: .main, using: syncOwnKeyWindow),
                NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                       object: nil, queue: .main, using: syncOwnKeyWindow),
            ]
        }
    }

    private func resetBuffer() {
        inputLock.withLock { buffer = "" }
    }

    // MARK: - Tap

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // stop() switches the tap off itself, and that is reported here
            // like a disable by the system. A stop under way has nothing to
            // recover: syncing would start the tap again under a suspend().
            let currentTap = tapLifecycleLock.withLock { tap }
            if SessionActivity.shared.isActive, AXIsProcessTrusted(), let currentTap {
                CGEvent.tapEnable(tap: currentTap, enable: true)
            } else if currentTap != nil {
                DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
            }
            return Unmanaged.passUnretained(event)
        }
        // Clicks move the caret somewhere unknown; the half-typed trigger is
        // no longer where the deletes would land. A click on the Accessibility
        // Keyboard is the exception: there the mouse is how a key is pressed,
        // so the click types a character and leaves the caret alone. Window
        // enumeration is skipped when the keyboard is not running.
        if type == .leftMouseDown || type == .rightMouseDown {
            if !AssistiveKeyboard.ownsPoint(event.location) { resetBuffer() }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        // Never react to our own synthetic typing.
        guard event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker else {
            return Unmanaged.passUnretained(event)
        }
        // Password fields: the system enables secure input; typing there must
        // stay exactly as typed, and the buffer must not remember any of it.
        guard !IsSecureEventInputEnabled() else {
            resetBuffer()
            return Unmanaged.passUnretained(event)
        }
        // Visibility is mirrored behind the same lock as the buffer, so this
        // callback never has to ask AppKit or wait for the main thread.
        guard !inputLock.withLock({ libraryVisible || commandBarVisible || fillInVisible }) else {
            resetBuffer()
            return Unmanaged.passUnretained(event)
        }
        // Shortcuts are commands, not text.
        if !event.flags.intersection([.maskCommand, .maskControl]).isEmpty {
            resetBuffer()
            return Unmanaged.passUnretained(event)
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        switch keyCode {
        case kVK_Delete:
            inputLock.withLock {
                if !buffer.isEmpty { buffer.removeLast() }
            }
            return Unmanaged.passUnretained(event)
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Escape,
             kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete:
            resetBuffer()
            return Unmanaged.passUnretained(event)
        default:
            break
        }

        var length = 0
        var characters = [UniChar](repeating: 0, count: 20)
        event.keyboardGetUnicodeString(maxStringLength: characters.count, actualStringLength: &length, unicodeString: &characters)
        let count = min(max(0, length), characters.count)
        guard count > 0 else { return Unmanaged.passUnretained(event) }
        let typed = String(utf16CodeUnits: characters, count: count)

        if let first = typed.first, TextSnippetSupport.delimiters.contains(first) {
            // A delimiter can complete an afterDelimiter trigger. The typed
            // delimiter is swallowed and kept after the replacement, either
            // in the same paste or as the original key after typed injection.
            let matched = inputLock.withLock { () -> (snippet: TextSnippet, deleteCount: Int, typedTrigger: String)? in
                let match = TextSnippetSupport.expansionMatch(buffer: buffer,
                                                              expansion: .afterDelimiter,
                                                              snippets: delimiterSnippets,
                                                              swallowed: "")
                buffer = ""
                return match
            }
            if let matched {
                return expand(matched.snippet,
                              deleteCount: matched.deleteCount,
                              typedTrigger: matched.typedTrigger,
                              trailingKeyCode: CGKeyCode(keyCode),
                              trailingFlags: event.flags,
                              trailingText: typed,
                              failureKeyCode: CGKeyCode(keyCode))
                    ? nil
                    : Unmanaged.passUnretained(event)
            }
            return Unmanaged.passUnretained(event)
        }

        let matched = inputLock.withLock { () -> (snippet: TextSnippet, deleteCount: Int, typedTrigger: String)? in
            buffer = TextSnippetSupport.bufferAppending(buffer, typed: typed)
            let match = TextSnippetSupport.expansionMatch(buffer: buffer,
                                                          expansion: .immediate,
                                                          snippets: immediateSnippets,
                                                          swallowed: typed)
            if match != nil { buffer = "" }
            return match
        }
        if let matched {
            // Suppress the final trigger event once the replacement path has
            // accepted it. A busy transient paste fails open to normal typing.
            return expand(matched.snippet,
                          deleteCount: matched.deleteCount,
                          typedTrigger: matched.typedTrigger,
                          trailingKeyCode: nil,
                          trailingFlags: [],
                          trailingText: "",
                          failureKeyCode: CGKeyCode(keyCode),
                          failureFlags: event.flags)
                ? nil
                : Unmanaged.passUnretained(event)
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: - Expansion

    @discardableResult
    private func expand(_ snippet: TextSnippet,
                        deleteCount: Int,
                        typedTrigger: String,
                        trailingKeyCode: CGKeyCode?,
                        trailingFlags: CGEventFlags,
                        trailingText: String,
                        failureKeyCode: CGKeyCode?,
                        failureFlags: CGEventFlags = []) -> Bool {
        let didExpand = expansionSoundCue()
        let replaySwallowedKey = {
            guard let failureKeyCode else { return }
            let source = CGEventSource(stateID: .hidSystemState)
            source?.userData = Self.syntheticMarker
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: failureKeyCode, keyDown: down)
                event?.flags = failureFlags
                event?.post(tap: .cghidEventTap)
            }
        }
        let lookupMap = inputLock.withLock { snippetsByTrigger }
        let snippetLookup: (String) -> String? = { trigger in lookupMap[trigger] }
        var visited = Set<String>()
        let nestedTemplate = TextSnippetProEngine.resolveNestedSnippets(
            snippet.replacement,
            lookup: snippetLookup,
            visited: &visited,
            depth: 0
        )
        let argFields = TextSnippetProEngine.extractArgumentSpecs(from: nestedTemplate)
        let needsClip = TextSnippetSupport.needsClipboard(nestedTemplate)
        let remoteType = NSPasteboard.PasteboardType("com.apple.is-remote-clipboard")

        func deliver(_ result: TextSnippetExpansionResult) {
            if let attributed = result.markdownRTFAttributed {
                let posted = Self.postRichExpansion(
                    deleteCount: deleteCount,
                    typedTrigger: typedTrigger,
                    attributed: attributed,
                    trailingKeyCode: trailingKeyCode,
                    trailingFlags: trailingFlags,
                    trailingText: trailingText,
                    failureKeyCode: failureKeyCode,
                    failureFlags: failureFlags,
                    cursorMoveBackSteps: result.cursorMoveBackCharacters,
                    didExpand: didExpand
                )
                if !posted { replaySwallowedKey() }
                return
            }
            let posted = Self.postExpansion(
                deleteCount: deleteCount,
                typedTrigger: typedTrigger,
                text: result.text,
                trailingKeyCode: trailingKeyCode,
                trailingFlags: trailingFlags,
                trailingText: trailingText,
                failureKeyCode: failureKeyCode,
                failureFlags: failureFlags,
                cursorMoveBackSteps: result.cursorMoveBackCharacters,
                didExpand: didExpand
            )
            if !posted { replaySwallowedKey() }
        }

        if !argFields.isEmpty {
            inputLock.withLock {
                fillInVisible = true
                buffer = ""
            }
            let promptTitle = snippet.name.isEmpty ? snippet.trigger : snippet.name
            let showPopover: (String?) -> Void = { [weak self] clipboard in
                DispatchQueue.main.async {
                    SnippetFillInPopoverController.shared.show(
                        snippetTitle: promptTitle,
                        fields: argFields
                    ) { values in
                        self?.inputLock.withLock { self?.fillInVisible = false }
                        guard let values else {
                            replaySwallowedKey()
                            return
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            let expanded = TextSnippetProEngine.expandAdvanced(
                                nestedTemplate,
                                date: Date(),
                                clipboard: clipboard,
                                arguments: values,
                                snippetLookup: snippetLookup
                            )
                            deliver(expanded)
                        }
                    }
                }
            }
            if needsClip {
                GeneralPasteboardAccess.shared.async({
                    NSPasteboard.general.string(forType: .string)
                }, then: showPopover)
            } else {
                showPopover(nil)
            }
            return true
        }

        if !Thread.isMainThread, needsClip, (NSPasteboard.general.types ?? []).contains(remoteType) {
            // Remote Universal Clipboard payloads can stall for seconds over
            // Continuity; resolve on the pasteboard lane off the tap thread.
            GeneralPasteboardAccess.shared.async({
                NSPasteboard.general.string(forType: .string)
            }, then: { clipboard in
                let expanded = TextSnippetProEngine.expandAdvanced(
                    nestedTemplate,
                    date: Date(),
                    clipboard: clipboard,
                    snippetLookup: snippetLookup
                )
                deliver(expanded)
            })
            return true
        }

        let clipboard = needsClip ? NSPasteboard.general.string(forType: .string) : nil
        let expanded = TextSnippetProEngine.expandAdvanced(
            nestedTemplate,
            date: Date(),
            clipboard: clipboard,
            snippetLookup: snippetLookup
        )
        let needsMainThreadPaste = expanded.markdownRTFAttributed != nil
            || TextSnippetSupport.requiresPaste(expanded.text)
        if !Thread.isMainThread, needsMainThreadPaste {
            // TransientPaste runs on main and dispatches to the pasteboard lane;
            // queue asynchronously so the event tap never blocks on main.sync.
            DispatchQueue.main.async {
                deliver(expanded)
            }
            return true
        }
        if let attributed = expanded.markdownRTFAttributed {
            return Self.postRichExpansion(
                deleteCount: deleteCount,
                typedTrigger: typedTrigger,
                attributed: attributed,
                trailingKeyCode: trailingKeyCode,
                trailingFlags: trailingFlags,
                trailingText: trailingText,
                failureKeyCode: failureKeyCode,
                failureFlags: failureFlags,
                cursorMoveBackSteps: expanded.cursorMoveBackCharacters,
                didExpand: didExpand
            )
        }
        return Self.postExpansion(deleteCount: deleteCount,
                                  typedTrigger: typedTrigger,
                                  text: expanded.text,
                                  trailingKeyCode: trailingKeyCode,
                                  trailingFlags: trailingFlags,
                                  trailingText: trailingText,
                                  failureKeyCode: failureKeyCode,
                                  failureFlags: failureFlags,
                                  cursorMoveBackSteps: expanded.cursorMoveBackCharacters,
                                  didExpand: didExpand)
    }

    private static func postRichExpansion(deleteCount: Int,
                                          typedTrigger: String,
                                          attributed: NSAttributedString,
                                          trailingKeyCode: CGKeyCode?,
                                          trailingFlags: CGEventFlags,
                                          trailingText: String,
                                          failureKeyCode: CGKeyCode?,
                                          failureFlags: CGEventFlags,
                                          cursorMoveBackSteps: Int,
                                          didExpand: (() -> Void)?) -> Bool {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                _ = postRichExpansion(deleteCount: deleteCount,
                                      typedTrigger: typedTrigger,
                                      attributed: attributed,
                                      trailingKeyCode: trailingKeyCode,
                                      trailingFlags: trailingFlags,
                                      trailingText: trailingText,
                                      failureKeyCode: failureKeyCode,
                                      failureFlags: failureFlags,
                                      cursorMoveBackSteps: cursorMoveBackSteps,
                                      didExpand: didExpand)
            }
            return true
        }

        let fullAttributed = NSMutableAttributedString(attributedString: attributed)
        if !trailingText.isEmpty {
            let normalizedTrailing = trailingText.replacingOccurrences(of: "\r", with: "\n")
            fullAttributed.append(NSAttributedString(string: normalizedTrailing,
                                                     attributes: [.font: NSFont.systemFont(ofSize: 13)]))
        }
        let plainPayload = fullAttributed.string
        guard let rtfData = try? fullAttributed.data(
            from: NSRange(location: 0, length: fullAttributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) else {
            return postExpansion(deleteCount: deleteCount,
                                 typedTrigger: typedTrigger,
                                 text: attributed.string,
                                 trailingKeyCode: trailingKeyCode,
                                 trailingFlags: trailingFlags,
                                 trailingText: trailingText,
                                 failureKeyCode: failureKeyCode,
                                 failureFlags: failureFlags,
                                 cursorMoveBackSteps: cursorMoveBackSteps,
                                 didExpand: didExpand)
        }

        let trailingMoveBack = trailingText.isEmpty ? (trailingKeyCode == nil ? 0 : 1) : trailingText.count
        let totalCursorRewind = cursorMoveBackSteps > 0 ? cursorMoveBackSteps + trailingMoveBack : 0

        let source = CGEventSource(stateID: .hidSystemState)
        source?.userData = syntheticMarker
        func postSyntheticKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
                event?.flags = flags
                event?.post(tap: .cghidEventTap)
            }
        }
        func postTriggerDeletes() {
            guard deleteCount > 0 else { return }
            let app = ownWindowIsKey ? nil : NSWorkspace.shared.frontmostApplication
            let selection = app.flatMap {
                SelectedTextReader.focusedTextSelection(processID: $0.processIdentifier, timeout: 0.12)
            }
            let count = TextSnippetSupport.triggerDeleteCount(
                deleteCount, typed: typedTrigger,
                focusedSelection: selection.map { (range: $0.range, textLength: $0.textLength) }
            ) { selection?.text(in: $0) }
            for _ in 0..<count { postSyntheticKey(CGKeyCode(kVK_Delete)) }
        }
        func snapshotPasteboard(_ pasteboard: NSPasteboard) -> [NSPasteboardItem]? {
            guard let items = pasteboard.pasteboardItems else {
                return pasteboard.types?.isEmpty == false ? nil : []
            }
            var copies: [NSPasteboardItem] = []
            for item in items {
                let copy = NSPasteboardItem()
                for type in item.types {
                    guard let data = item.data(forType: type) else { return nil }
                    copy.setData(data, forType: type)
                }
                copies.append(copy)
            }
            return copies
        }
        func restoreSnapshot(_ snapshot: [NSPasteboardItem], expectedChangeCount: Int) {
            GeneralPasteboardAccess.shared.async {
                let pasteboard = NSPasteboard.general
                guard pasteboard.changeCount == expectedChangeCount else { return }
                pasteboard.clearContents()
                if !snapshot.isEmpty { pasteboard.writeObjects(snapshot) }
                let restoredCount = pasteboard.changeCount
                DispatchQueue.main.async {
                    ClipboardHistoryService.shared.ignoreNextChange(upTo: restoredCount)
                }
            }
        }

        GeneralPasteboardAccess.shared.async {
            let pasteboard = NSPasteboard.general
            let originalChangeCount = pasteboard.changeCount
            guard let snapshot = snapshotPasteboard(pasteboard),
                  pasteboard.changeCount == originalChangeCount else {
                DispatchQueue.main.async {
                    if let failureKeyCode { postSyntheticKey(failureKeyCode, flags: failureFlags) }
                }
                return
            }

            pasteboard.clearContents()
            let rtfOK = pasteboard.setData(rtfData, forType: .rtf)
            let stringOK = pasteboard.setString(plainPayload, forType: .string)
            guard rtfOK, stringOK else {
                if !snapshot.isEmpty { pasteboard.writeObjects(snapshot) }
                DispatchQueue.main.async {
                    if let failureKeyCode { postSyntheticKey(failureKeyCode, flags: failureFlags) }
                }
                return
            }
            let writtenChangeCount = pasteboard.changeCount
            DispatchQueue.main.async {
                ClipboardHistoryService.shared.ignoreNextChange(upTo: writtenChangeCount)
                let started = TransientPaste.shared.pasteCurrentContents(
                    willPostShortcut: {
                        postTriggerDeletes()
                    },
                    didPostShortcut: {
                        if totalCursorRewind > 0 {
                            for _ in 0..<totalCursorRewind {
                                postSyntheticKey(CGKeyCode(kVK_LeftArrow))
                            }
                        }
                        didExpand?()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            restoreSnapshot(snapshot, expectedChangeCount: writtenChangeCount)
                        }
                    },
                    didFail: {
                        restoreSnapshot(snapshot, expectedChangeCount: writtenChangeCount)
                        if let failureKeyCode { postSyntheticKey(failureKeyCode, flags: failureFlags) }
                    }
                )
                if !started {
                    restoreSnapshot(snapshot, expectedChangeCount: writtenChangeCount)
                    if let failureKeyCode { postSyntheticKey(failureKeyCode, flags: failureFlags) }
                }
            }
        }
        return true
    }

    /// Hung off the replacement going out rather than off `postExpansion`'s
    /// return value: a transient paste reports success as soon as it reaches
    /// the pasteboard lane, so its return cannot tell a paste that went out
    /// from one that failed open to typing. It also keeps the sound behind
    /// the paste instead of ahead of it, since the shortcut waits for the
    /// modifiers to come up.
    ///
    /// Nil when no sound is retained, which is when the feature is off.
    private func expansionSoundCue() -> (() -> Void)? {
        guard let sound = inputLock.withLock({ expansionSound }) else { return nil }
        return {
            // Async because the typed path calls this while the tap callback
            // may still be blocked on the main queue, and asking the sound
            // server to play is a round trip that must not sit inside the
            // window macOS disables the tap for.
            DispatchQueue.main.async { sound.play() }
        }
    }

    /// Whether one of this app's windows takes the keys. A panel that never
    /// activates the app, like the island's scratchpad, is key while the app
    /// behind it stays frontmost, and that app's field is not where the
    /// backspaces land. AppKit is read on the main thread, where both
    /// expansion paths post their backspaces; anywhere else counts as ours,
    /// so no other app is asked.
    private static var ownWindowIsKey: Bool {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { NSApp?.keyWindow != nil }
        }
        return shared.inputLock.withLock { shared.ownKeyWindowActive }
    }

    /// Also the snippet library's insertion path (deleteCount 0): one typing
    /// routine, one synthetic marker, one set of quirks. `typedTrigger` is
    /// the text the `deleteCount` backspaces clear.
    @discardableResult
    static func postExpansion(deleteCount: Int,
                              typedTrigger: String,
                              text: String,
                              trailingKeyCode: CGKeyCode?,
                              trailingFlags: CGEventFlags,
                              trailingText: String = "",
                              failureKeyCode: CGKeyCode? = nil,
                              failureFlags: CGEventFlags = [],
                              cursorMoveBackSteps: Int = 0,
                              didExpand: (() -> Void)? = nil) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.userData = syntheticMarker

        func post(_ event: CGEvent?) {
            event?.post(tap: .cghidEventTap)
        }
        func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
                event?.flags = flags
                post(event)
            }
        }
        let trailingMoveBack = trailingText.isEmpty ? (trailingKeyCode == nil ? 0 : 1) : trailingText.count
        let totalCursorRewind = cursorMoveBackSteps > 0 ? cursorMoveBackSteps + trailingMoveBack : 0
        func postCursorRewind() {
            guard totalCursorRewind > 0 else { return }
            for _ in 0..<totalCursorRewind {
                postKey(CGKeyCode(kVK_LeftArrow))
            }
        }
        // Asked right before the backspaces go out, so the count covers a
        // completion the field shows by then. Typing waits while the field
        // answers, so every question, up to five for a selection that looks
        // like a completion, shares one short time limit. Runs on the main
        // thread on the typed and the pasted path alike.
        func postDeletes() {
            guard deleteCount > 0 else { return }
            let app = ownWindowIsKey ? nil : NSWorkspace.shared.frontmostApplication
            let selection = app.flatMap {
                SelectedTextReader.focusedTextSelection(processID: $0.processIdentifier, timeout: 0.12)
            }
            let count = TextSnippetSupport.triggerDeleteCount(
                deleteCount, typed: typedTrigger,
                focusedSelection: selection.map { (range: $0.range, textLength: $0.textLength) }
            ) { selection?.text(in: $0) }
            for _ in 0..<count { postKey(CGKeyCode(kVK_Delete)) }
        }

        if TextSnippetSupport.requiresPaste(text) {
            let payload = TextSnippetSupport.pastePayload(text: text, trailingText: trailingText)
            return TransientPaste.shared.paste(
                payload,
                willPostShortcut: { postDeletes() },
                didPostShortcut: {
                    postCursorRewind()
                    didExpand?()
                },
                didFail: {
                    if let failureKeyCode { postKey(failureKeyCode, flags: failureFlags) }
                }
            )
        }

        postDeletes()

        // Typed injection instead of pasting: the clipboard stays untouched.
        // Keystroke events carry at most ~20 UTF-16 units reliably.
        let units = Array(text.utf16)
        var index = 0
        while index < units.count {
            var end = min(index + 20, units.count)
            // Never split a surrogate pair across chunks: two lone halves in
            // separate events render as replacement characters in some apps.
            if end < units.count, UTF16.isLeadSurrogate(units[end - 1]) {
                end -= 1
            }
            let chunk = Array(units[index..<end])
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                post(event)
            }
            index = end
        }

        if let trailingKeyCode {
            postKey(trailingKeyCode, flags: trailingFlags)
        }
        postCursorRewind()
        didExpand?()
        return true
    }
}

/// One alert sound file registered with the system sound server, so it
/// plays the way the Mac's own alert sounds do: through the sound effects
/// output device, at the alert volume, with the screen flash Accessibility
/// can ask for in place of a sound. NSSound would play it on the default
/// output device at the main volume, ignoring all three.
private final class AlertSound {
    private let soundID: SystemSoundID

    init?(name: String) {
        var soundID: SystemSoundID = 0
        let url = TextSnippetSupport.soundFileURL(for: name) as CFURL
        guard AudioServicesCreateSystemSoundID(url, &soundID) == noErr else { return nil }
        self.soundID = soundID
    }

    deinit {
        AudioServicesDisposeSystemSoundID(soundID)
    }

    func play() {
        // The completion holds this instance until playback ends, so a
        // preview that resolved its own sound is not disposed mid-note.
        AudioServicesPlayAlertSoundWithCompletion(soundID) { withExtendedLifetime(self) {} }
    }
}
