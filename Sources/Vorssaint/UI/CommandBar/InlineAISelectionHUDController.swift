// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import SwiftUI

/// Non-activating floating panel for inline AI actions over selected text.
/// Subclasses `OverlayPanel` so tiling window managers ignore it while preserving accessibility.
final class InlineAISelectionHUDPanel: OverlayPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Manages the floating Inline AI Selection HUD (Wave 7 Command Bar 3.0).
/// Reads selected text via Accessibility (`kAXSelectedTextAttribute` / text marker fallback)
/// or passive clipboard fallback without mutating the pasteboard, streams rewrites via
/// `CommandBarQuickAIService`, and replaces or copies the result cleanly.
@MainActor
final class InlineAISelectionHUDController: ObservableObject {
    static let shared = InlineAISelectionHUDController()

    @Published private(set) var isVisible = false
    @Published private(set) var selectedText = ""
    @Published private(set) var activeAction: InlineAIRewriteAction?
    @Published private(set) var resultText = ""
    @Published private(set) var isStreaming = false
    @Published private(set) var errorText: String?
    @Published private(set) var didCopy = false
    @Published var selectedProvider: QuickAIProvider = .ollama {
        didSet {
            aiService.selectedProvider = selectedProvider
        }
    }
    @Published var customPrompt = ""

    private let aiService = CommandBarQuickAIService(defaults: .standard)
    private var panel: InlineAISelectionHUDPanel?
    private var hostingController: NSHostingController<InlineAISelectionHUDView>?
    private var cancellables: Set<AnyCancellable> = []
    private var keyMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var captureGeneration = 0

    private init() {
        selectedProvider = CommandBarQuickAIService.shared.selectedProvider
        bindService()
    }

    private func bindService() {
        aiService.$isStreaming
            .receive(on: DispatchQueue.main)
            .sink { [weak self] streaming in
                self?.isStreaming = streaming
                self?.resizePanelIfVisible()
            }
            .store(in: &cancellables)

        aiService.$responseText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.resultText = text
                self?.resizePanelIfVisible()
            }
            .store(in: &cancellables)

        aiService.$errorText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.errorText = error
                self?.resizePanelIfVisible()
            }
            .store(in: &cancellables)
    }

    /// Reads the current selection from the frontmost app (or optional pre-captured text)
    /// and presents the floating glass HUD anchored near the text caret or pointer.
    func show(preselectedText: String? = nil) {
        captureGeneration &+= 1
        let generation = captureGeneration
        let frontPID: pid_t? = {
            guard let front = NSWorkspace.shared.frontmostApplication,
                  front.bundleIdentifier != Bundle.main.bundleIdentifier else {
                return nil
            }
            return front.processIdentifier
        }()

        selectedProvider = CommandBarQuickAIService.shared.selectedProvider
        activeAction = nil
        didCopy = false
        customPrompt = ""
        aiService.reset()
        resultText = ""
        errorText = nil

        if let preselectedText, !preselectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmed = String(preselectedText.prefix(CommandBarSelectionReader.maximumLength))
            presentHUD(with: trimmed, anchor: Self.caretCocoaAnchor(for: frontPID) ?? NSEvent.mouseLocation)
            return
        }

        Task { @MainActor [weak self] in
            let axText = await Task.detached(priority: .userInitiated) {
                frontPID.flatMap { SelectedTextReader.read(processID: $0)?.text }?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }.value
            guard let self, self.captureGeneration == generation else { return }
            let anchor = Self.caretCocoaAnchor(for: frontPID) ?? NSEvent.mouseLocation
            let resolvedText: String
            if let axText, !axText.isEmpty {
                resolvedText = String(axText.prefix(CommandBarSelectionReader.maximumLength))
            } else {
                let clip = NSPasteboard.general.string(forType: .string)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                resolvedText = String(clip.prefix(CommandBarSelectionReader.maximumLength))
            }
            self.presentHUD(with: resolvedText, anchor: anchor)
        }
    }

    func run(_ action: InlineAIRewriteAction) {
        let source = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        activeAction = action
        didCopy = false
        aiService.selectedProvider = selectedProvider
        aiService.sendPrompt(action.prompt(for: source))
    }

    func runCustomPrompt() {
        let instruction = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty, !source.isEmpty else { return }
        activeAction = nil
        didCopy = false
        aiService.selectedProvider = selectedProvider
        aiService.sendPrompt("\(instruction)\n\n\(source)")
    }

    func stopStreaming() {
        aiService.reset()
    }

    func copyResult() {
        let text = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareVorssaintSource()
        pasteboard.setString(text, forType: .string)
        didCopy = true
        VorssaintHaptics.generic()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            self?.didCopy = false
        }
    }

    func replaceSelection() {
        let replacement = resultText
        guard !replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            _ = TransientPaste.shared.paste(replacement)
            VorssaintHaptics.alignment()
        }
    }

    func dismiss() {
        captureGeneration &+= 1
        aiService.reset()
        removeMonitors()
        panel?.orderOut(nil)
        isVisible = false
    }

    private func presentHUD(with text: String, anchor: NSPoint) {
        selectedText = text
        let panel = ensurePanel()
        let rootView = InlineAISelectionHUDView(controller: self)
        if let hostingController {
            hostingController.rootView = rootView
        } else {
            let host = NSHostingController(rootView: rootView)
            host.sizingOptions = .preferredContentSize
            panel.contentViewController = host
            hostingController = host
        }
        hostingController?.view.layoutSubtreeIfNeeded()
        let size = hostingController?.view.fittingSize ?? NSSize(width: 400, height: 220)
        let origin = preferredOrigin(for: size, anchor: anchor)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)

        installMonitors(for: panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        isVisible = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }
    }

    private func resizePanelIfVisible() {
        guard let panel, panel.isVisible, let hostingController else { return }
        DispatchQueue.main.async { [weak panel, weak hostingController] in
            guard let panel, panel.isVisible, let hostingController else { return }
            hostingController.view.layoutSubtreeIfNeeded()
            let newSize = hostingController.view.fittingSize
            guard newSize.width > 0, newSize.height > 0 else { return }
            let visible = panel.screen?.visibleFrame ?? NSScreen.pointerVisibleFrame
            let top = panel.frame.maxY
            let x = min(max(panel.frame.origin.x, visible.minX + 12), max(visible.minX + 12, visible.maxX - newSize.width - 12))
            let y = min(max(top - newSize.height, visible.minY + 12), max(visible.minY + 12, visible.maxY - newSize.height - 12))
            panel.setFrame(NSRect(x: x, y: y, width: newSize.width, height: newSize.height), display: true)
        }
    }

    private func ensurePanel() -> InlineAISelectionHUDPanel {
        if let panel { return panel }
        let created = InlineAISelectionHUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        created.title = AppInfo.name
        created.isReleasedWhenClosed = false
        created.isOpaque = false
        created.backgroundColor = .clear
        created.hasShadow = true
        created.hidesOnDeactivate = false
        created.isMovableByWindowBackground = true
        created.level = .floating
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel = created
        return created
    }

    private func preferredOrigin(for size: NSSize, anchor: NSPoint) -> NSPoint {
        let visible = NSScreen.pointerVisibleFrame
        let x = min(max(anchor.x - 24, visible.minX + 12), max(visible.minX + 12, visible.maxX - size.width - 12))
        var y = anchor.y - size.height - 14
        if y < visible.minY + 12 {
            y = anchor.y + 22
        }
        y = min(max(y, visible.minY + 12), max(visible.minY + 12, visible.maxY - size.height - 12))
        return NSPoint(x: x, y: y)
    }

    private func installMonitors(for panel: InlineAISelectionHUDPanel) {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel else { return event }
            if Int(event.keyCode) == kVK_Escape {
                self.dismiss()
                return nil
            }
            return event
        }
        let mouseMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseMask) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible else { return event }
            if event.window !== panel {
                self.dismiss()
            }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseMask) { [weak self, weak panel] _ in
            guard let self, let panel, panel.isVisible else { return }
            self.dismiss()
        }
    }

    private func removeMonitors() {
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
    }

    private static func caretCocoaAnchor(for processID: pid_t?) -> NSPoint? {
        guard AXIsProcessTrusted(), let processID else { return nil }
        let appElement = AXUIElementCreateApplication(processID)
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
        let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.screens.first?.frame.height
            ?? 900
        return NSPoint(x: quartzRect.minX, y: primaryHeight - quartzRect.maxY)
    }
}

private struct InlineAISelectionHUDView: View {
    @ObservedObject var controller: InlineAISelectionHUDController
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private func v3(_ keyPath: KeyPath<OverhaulV3Strings, String>) -> String {
        OverhaulV3Strings.localized(l10n.language)[keyPath: keyPath]
    }

    var body: some View {
        let tone = SemanticCategoryTone.dynamicIsland
        let accent = tone.color(scheme: colorScheme, highContrast: colorSchemeContrast == .increased)

        VStack(alignment: .leading, spacing: DesignSpace.sm + 2) {
            HStack(spacing: DesignSpace.sm) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: DesignRadius.iconTile, style: .continuous)
                            .fill(accent.opacity(0.15))
                    )
                Text(v3(\OverhaulV3Strings.inlineAITitle))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: DesignSpace.xs)

                Menu {
                    ForEach(QuickAIProvider.allCases) { provider in
                        Button {
                            controller.selectedProvider = provider
                        } label: {
                            HStack {
                                Text(provider.displayName)
                                if controller.selectedProvider == provider {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(controller.selectedProvider.displayName)
                            .font(.system(size: 10.5, weight: .medium))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8.5, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button {
                    controller.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if !controller.selectedText.isEmpty {
                Text(controller.selectedText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DesignSpace.sm)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: DesignRadius.pill, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
            } else {
                Text(FeatureStrings.commandBar(l10n.language).noResultsTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 114), spacing: 6)], spacing: 6) {
                let copy = OverhaulV3ActionCopy.localized(l10n.language)
                ForEach(InlineAIRewriteAction.allCases) { action in
                    VorssaintActionChip(
                        title: copy.title(for: action),
                        symbol: action.symbolName,
                        tone: .dynamicIsland,
                        prominent: controller.activeAction == action
                    ) {
                        controller.run(action)
                    }
                    .disabled(controller.selectedText.isEmpty)
                }
            }

            HStack(spacing: 6) {
                TextField(OverhaulStrings.wave3(l10n.language).quickAIPlaceholder, text: $controller.customPrompt)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5))
                    .onSubmit {
                        controller.runCustomPrompt()
                    }
                    .disabled(controller.selectedText.isEmpty)
                Button {
                    controller.runCustomPrompt()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(
                            controller.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.secondary.opacity(0.4)
                                : accent
                        )
                }
                .buttonStyle(.plain)
                .disabled(
                    controller.selectedText.isEmpty
                        || controller.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }

            if controller.isStreaming {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(OverhaulStrings.wave3(l10n.language).quickAIThinking)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    VorssaintActionChip(title: l10n.s.uninstallerCancel, symbol: "stop.fill", tone: .energyDisplay) {
                        controller.stopStreaming()
                    }
                }
            }

            if let error = controller.errorText, !error.isEmpty {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !controller.resultText.isEmpty {
                ScrollView {
                    Text(controller.resultText)
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
                .padding(DesignSpace.sm)
                .background(
                    RoundedRectangle(cornerRadius: DesignRadius.innerGroup, style: .continuous)
                        .fill(accent.opacity(0.08))
                )

                if !controller.isStreaming {
                    let copy = OverhaulV3ActionCopy.localized(l10n.language)
                    HStack(spacing: DesignSpace.sm) {
                        Spacer(minLength: 0)
                        VorssaintActionChip(
                            title: controller.didCopy ? l10n.s.urlCleanerCopied : l10n.s.menuCopy,
                            symbol: controller.didCopy ? "checkmark" : "doc.on.doc",
                            tone: .clipboardFiles
                        ) {
                            controller.copyResult()
                        }
                        VorssaintActionChip(
                            title: copy.replace,
                            symbol: "arrow.uturn.down.circle.fill",
                            tone: .dynamicIsland,
                            prominent: true
                        ) {
                            controller.replaceSelection()
                        }
                    }
                }
            }
        }
        .padding(DesignSpace.md + 2)
        .frame(width: 400)
        .background(HUDBackdrop(cornerRadius: DesignRadius.panel, contrast: .high))
        .clipShape(RoundedRectangle(cornerRadius: DesignRadius.panel, style: .continuous))
        .hairlineSpecularBorder(cornerRadius: DesignRadius.panel)
    }
}
