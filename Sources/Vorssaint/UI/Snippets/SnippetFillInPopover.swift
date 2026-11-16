// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import SwiftUI

/// Floating non-activating fill-in panel for Snippets 2.0 `{{arg:name=default}}` tokens.
/// Subclasses `OverlayPanel` so tiling window managers skip it while allowing key focus
/// for text inputs without stealing activation from the target application.
final class SnippetFillInPopoverController: OverlayPanel {
    static let shared = SnippetFillInPopoverController()

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private final class FormModel: ObservableObject {
        @Published var snippetTitle: String = ""
        @Published var fields: [TextSnippetArgumentField] = []
        @Published var values: [String: String] = [:]
        @Published var sessionID = UUID()
    }

    private let model = FormModel()
    private var completion: (([String: String]?) -> Void)?
    private var keyMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    private convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 180),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
    }

    override init(contentRect: NSRect,
                  styleMask style: NSWindow.StyleMask,
                  backing backingStoreType: NSWindow.BackingStoreType,
                  defer flag: Bool) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: backingStoreType,
                   defer: flag)
        title = "Vorssaint"
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    var isShowingPopover: Bool { isVisible }

    func show(snippetTitle: String,
              fields: [TextSnippetArgumentField],
              completion: @escaping ([String: String]?) -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.show(snippetTitle: snippetTitle, fields: fields, completion: completion)
            }
            return
        }
        dismiss(deliverCancel: true)

        model.snippetTitle = snippetTitle
        model.fields = fields
        var initialValues: [String: String] = [:]
        for field in fields {
            initialValues[field.name] = field.defaultValue
        }
        model.values = initialValues
        model.sessionID = UUID()
        self.completion = completion

        let content = SnippetFillInPopoverView(
            model: model,
            onConfirm: { [weak self] in self?.confirm() },
            onCancel: { [weak self] in self?.cancel() }
        )
        let host = NSHostingController(rootView: content)
        host.sizingOptions = .preferredContentSize
        contentViewController = host
        host.view.layoutSubtreeIfNeeded()

        let size = host.view.fittingSize
        let origin = preferredOrigin(for: size)
        setFrame(NSRect(origin: origin, size: size), display: false)

        installMonitors()
        alphaValue = 0
        orderFrontRegardless()
        makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 1
        }
        DispatchQueue.main.async { [weak self] in
            self?.focusFirstEditableField()
        }
    }

    func confirm() {
        var resolved: [String: String] = [:]
        for field in model.fields {
            resolved[field.name] = model.values[field.name] ?? field.defaultValue
        }
        let handler = completion
        completion = nil
        tearDown()
        handler?(resolved)
    }

    func cancel() {
        dismiss(deliverCancel: true)
    }

    private func dismiss(deliverCancel: Bool) {
        let handler = completion
        completion = nil
        tearDown()
        if deliverCancel {
            handler?(nil)
        }
    }

    private func tearDown() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        orderOut(nil)
    }

    private func installMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self else { return event }
            if let textView = self.firstResponder as? NSTextView, textView.hasMarkedText() {
                return event
            }
            switch Int(event.keyCode) {
            case kVK_Escape:
                self.cancel()
                return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                self.confirm()
                return nil
            default:
                return event
            }
        }
        let mouseMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseMask) { [weak self] event in
            guard let self, self.isVisible else { return event }
            if event.window !== self {
                self.cancel()
            }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseMask) { [weak self] _ in
            guard let self, self.isVisible else { return }
            self.cancel()
        }
    }

    private func focusFirstEditableField() {
        contentView?.layoutSubtreeIfNeeded()
        if let field = Self.firstEditableField(in: contentView) {
            makeFirstResponder(field)
        }
    }

    private static func firstEditableField(in view: NSView?) -> NSTextField? {
        guard let view, !view.isHidden else { return nil }
        if let field = view as? NSTextField, field.isEditable, field.isEnabled {
            return field
        }
        for subview in view.subviews {
            if let found = firstEditableField(in: subview) { return found }
        }
        return nil
    }

    private func preferredOrigin(for size: NSSize) -> NSPoint {
        let visible = NSScreen.pointerVisibleFrame
        let anchor = Self.activeCaretCocoaAnchor() ?? NSEvent.mouseLocation
        var x = anchor.x - 24
        var y = anchor.y - size.height - 14
        if y < visible.minY + 12 {
            y = anchor.y + 22
        }
        x = min(max(x, visible.minX + 12), max(visible.minX + 12, visible.maxX - size.width - 12))
        y = min(max(y, visible.minY + 12), max(visible.minY + 12, visible.maxY - size.height - 12))
        return NSPoint(x: x, y: y)
    }

    /// Reads the focused text caret's screen position via Accessibility without querying `kAXRoleAttribute`.
    private static func activeCaretCocoaAnchor() -> NSPoint? {
        guard AXIsProcessTrusted(),
              let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }
        let appElement = AXUIElementCreateApplication(front.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.15)
        var focusedRaw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRaw) == .success,
              let focusedRaw,
              CFGetTypeID(focusedRaw) == AXUIElementGetTypeID() else {
            return nil
        }
        let focused = focusedRaw as! AXUIElement
        AXUIElementSetMessagingTimeout(focused, 0.15)

        var rangeRaw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &rangeRaw) == .success,
              let rangeRaw,
              CFGetTypeID(rangeRaw) == AXValueGetTypeID() else {
            return nil
        }
        var boundsRaw: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            focused,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeRaw,
            &boundsRaw
        ) == .success,
              let boundsRaw,
              CFGetTypeID(boundsRaw) == AXValueGetTypeID() else {
            return nil
        }
        var quartzRect = CGRect.zero
        guard AXValueGetValue(boundsRaw as! AXValue, .cgRect, &quartzRect),
              quartzRect.width.isFinite, quartzRect.height.isFinite,
              quartzRect != .zero else {
            return nil
        }
        // Quartz origin is top-left of the primary screen; Cocoa origin is bottom-left.
        let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.screens.first?.frame.height
            ?? 900
        return NSPoint(x: quartzRect.minX, y: primaryHeight - quartzRect.maxY)
    }

    private struct SnippetFillInPopoverView: View {
        @ObservedObject var model: FormModel
        let onConfirm: () -> Void
        let onCancel: () -> Void

        @ObservedObject private var l10n = L10n.shared
        @FocusState private var focusedFieldID: String?

        private var v2Strings: OverhaulV2Strings {
            OverhaulV2Strings.localized(l10n.language)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "text.cursor")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.accentColor.opacity(0.14))
                        )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.snippetTitle.isEmpty ? v2Strings.snippetFillInTitle : model.snippetTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        if !model.snippetTitle.isEmpty {
                            Text(v2Strings.snippetFillInTitle)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Text("Esc")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.fields) { field in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(field.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            TextField(
                                field.defaultValue.isEmpty ? field.name : field.defaultValue,
                                text: binding(for: field)
                            )
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12.5))
                            .focused($focusedFieldID, equals: field.id)
                            .onSubmit { onConfirm() }
                        }
                    }
                }

                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    VorssaintActionChip(title: l10n.s.uninstallerCancel, tone: .mouseKeyboard) {
                        onCancel()
                    }
                    VorssaintActionChip(
                        title: v2Strings.snippetInsertButton,
                        symbol: "return",
                        tone: .mouseKeyboard,
                        prominent: true
                    ) {
                        onConfirm()
                    }
                }
            }
            .padding(16)
            .frame(width: 340)
            .background(HUDBackdrop(cornerRadius: DesignRadius.panel, contrast: .high))
            .clipShape(RoundedRectangle(cornerRadius: DesignRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignRadius.panel, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
            )
            .onAppear {
                focusedFieldID = model.fields.first?.id
            }
            .onChange(of: model.sessionID) { _, _ in
                focusedFieldID = model.fields.first?.id
            }
        }

        private func binding(for field: TextSnippetArgumentField) -> Binding<String> {
            Binding(
                get: { model.values[field.name] ?? field.defaultValue },
                set: { model.values[field.name] = $0 }
            )
        }
    }
}
