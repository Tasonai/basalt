// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

/// Floating non-activating pill HUD anchored near bottom-center while `ClipboardPasteStack`
/// is recording or holds queued items (`⌘⌃V` FIFO sequential paste).
final class ClipboardPasteStackHUDController: OverlayPanel {
    static let shared = ClipboardPasteStackHUDController()

    private var hostingController: NSHostingController<ClipboardPasteStackHUDView>?
    private var cancellables: Set<AnyCancellable> = []

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        observeChanges()
    }

    private func observeChanges() {
        let stack = ClipboardPasteStack.shared
        Publishers.Merge3(
            stack.$queue.map { _ in () },
            stack.$isRecording.map { _ in () },
            L10n.shared.$language.map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in
            // `@Published` emits in `willSet`; schedule on next main tick so `queue`/`isRecording` reflect new state.
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
        .store(in: &cancellables)
    }

    func refresh() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.refresh() }
            return
        }
        let stack = ClipboardPasteStack.shared
        guard stack.isActive else {
            orderOut(nil)
            return
        }

        let rootView = ClipboardPasteStackHUDView()
        if let hostingController {
            hostingController.rootView = rootView
        } else {
            let controller = NSHostingController(rootView: rootView)
            contentViewController = controller
            hostingController = controller
        }

        hostingController?.view.layoutSubtreeIfNeeded()
        let fitting = hostingController?.view.fittingSize ?? NSSize(width: 360, height: 46)
        let size = NSSize(width: min(max(fitting.width, 280), 560), height: max(fitting.height, 44))
        let screen = NSScreen.pointerVisibleFrame
        let x = max(screen.minX + 16, min(screen.midX - size.width / 2, screen.maxX - size.width - 16))
        let y = screen.minY + 26
        setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        orderFrontRegardless()
    }
}

private struct ClipboardPasteStackHUDView: View {
    @ObservedObject private var stack = ClipboardPasteStack.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var wave3Strings: OverhaulWave3Strings {
        OverhaulStrings.wave3(l10n.language)
    }

    private var v2Strings: OverhaulV2Strings {
        OverhaulV2Strings.localized(l10n.language)
    }

    private var nextSnippet: String {
        guard let next = stack.peekNext() else {
            return stack.isRecording ? "Recording…" : wave3Strings.pasteStackTitle
        }
        let collapsed = next.preview
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.isEmpty {
            return next.kind == .image
                ? FeatureStrings.clipboard(l10n.language).imageEntryLabel
                : wave3Strings.pasteStackTitle
        }
        return collapsed.count > 44 ? String(collapsed.prefix(44)) + "…" : collapsed
    }

    var body: some View {
        let tint = SemanticCategoryTone.clipboardFiles.color(
            scheme: colorScheme,
            highContrast: colorSchemeContrast == .increased
        )
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: stack.isRecording ? "record.circle" : "square.stack.3d.up.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(stack.isRecording ? Color.red : tint)
                Text("\(stack.count)")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule(style: .continuous).fill(tint))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(nextSnippet)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 230, alignment: .leading)
                if stack.isRecording {
                    Text(wave3Strings.pasteStackTitle)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                VorssaintHaptics.alignment()
                ClipboardHistoryService.shared.pasteNextFromStack()
            } label: {
                HStack(spacing: 4) {
                    Text(l10n.s.menuPaste)
                    Text("⌘⌃V")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .opacity(0.85)
                }
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: DesignRadius.pill, style: .continuous).fill(tint))
            }
            .buttonStyle(VorssaintScalePressButtonStyle())
            .disabled(stack.queue.isEmpty)
            .opacity(stack.queue.isEmpty ? 0.45 : 1)
            .accessibilityLabel(
                String(format: v2Strings.clipboardPasteStackHUDFormat,
                       locale: l10n.language.formattingLocale(),
                       stack.count,
                       nextSnippet)
            )

            Button {
                VorssaintHaptics.generic()
                stack.clear()
                stack.isRecording = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.08), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(l10n.s.actionClear)
            .accessibilityLabel(l10n.s.actionClear)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignRadius.panel, style: .continuous))
        .hairlineSpecularBorder(cornerRadius: DesignRadius.panel, opacity: 0.24)
    }
}
