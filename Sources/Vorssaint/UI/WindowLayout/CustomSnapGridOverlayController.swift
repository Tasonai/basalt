// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

/// Interactive translucent overlay centered on the pointer's screen allowing
/// click-drag selection across `CustomSnapGridSpec` cells to snap the active window.
final class CustomSnapGridOverlayController {
    static let shared = CustomSnapGridOverlayController()

    private var window: CustomSnapGridOverlayWindow?
    private let model = CustomSnapGridOverlayModel()

    private init() {}

    func show() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.show() }
            return
        }

        let visibleFrame = NSScreen.pointerVisibleFrame
        model.reloadFromDefaults(targetVisibleFrame: visibleFrame)

        let overlayWindow: CustomSnapGridOverlayWindow
        if let existing = window {
            overlayWindow = existing
        } else {
            let content = CustomSnapGridOverlayView(
                model: model,
                onCommit: { [weak self] frame in
                    self?.commitSelection(frame)
                },
                onClose: { [weak self] in
                    self?.close()
                }
            )
            let host = NSHostingController(rootView: content)
            host.sizingOptions = .preferredContentSize

            let created = CustomSnapGridOverlayWindow(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            created.level = .statusBar
            created.isOpaque = false
            created.backgroundColor = .clear
            created.hasShadow = true
            created.hidesOnDeactivate = false
            created.isReleasedWhenClosed = false
            created.isMovableByWindowBackground = false
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
            created.contentViewController = host
            created.onCancel = { [weak self] in
                self?.close()
            }
            window = created
            overlayWindow = created
        }

        let aspect = visibleFrame.height / max(1, visibleFrame.width)
        let panelWidth = min(560, max(380, visibleFrame.width * 0.46))
        let gridHeight = min(320, max(180, (panelWidth - 32) * aspect))
        let panelHeight = gridHeight + 76
        let origin = CGPoint(
            x: (visibleFrame.midX - panelWidth / 2).rounded(),
            y: (visibleFrame.midY - panelHeight / 2).rounded()
        )
        overlayWindow.setFrame(CGRect(origin: origin, size: CGSize(width: panelWidth, height: panelHeight)),
                               display: true)
        overlayWindow.alphaValue = 0
        overlayWindow.orderFrontRegardless()
        overlayWindow.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            overlayWindow.animator().alphaValue = 1
        }
    }

    func close() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.close() }
            return
        }
        model.clearDrag()
        window?.orderOut(nil)
    }

    private func commitSelection(_ frame: CGRect) {
        WindowLayoutService.shared.applyCustomSnapGridFrame(frame)
        VorssaintHaptics.alignment()
        close()
    }
}

final class CustomSnapGridOverlayWindow: OverlayPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}

private final class CustomSnapGridOverlayModel: ObservableObject {
    struct CellCoord: Equatable {
        let col: Int
        let visualRow: Int
    }

    @Published var columns: Int = 3
    @Published var rows: Int = 2
    @Published var anchorCell: CellCoord?
    @Published var currentCell: CellCoord?
    @Published var targetVisibleFrame: CGRect = NSScreen.pointerVisibleFrame

    func reloadFromDefaults(targetVisibleFrame: CGRect) {
        let savedCols = UserDefaults.standard.integer(forKey: DefaultsKey.windowCustomGridColumns)
        let savedRows = UserDefaults.standard.integer(forKey: DefaultsKey.windowCustomGridRows)
        columns = savedCols > 0 ? max(2, min(savedCols, 6)) : 3
        rows = savedRows > 0 ? max(1, min(savedRows, 4)) : 2
        self.targetVisibleFrame = targetVisibleFrame
        clearDrag()
    }

    func applyPreset(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
        UserDefaults.standard.set(columns, forKey: DefaultsKey.windowCustomGridColumns)
        UserDefaults.standard.set(rows, forKey: DefaultsKey.windowCustomGridRows)
        clearDrag()
        VorssaintHaptics.generic()
    }

    func clearDrag() {
        anchorCell = nil
        currentCell = nil
    }

    var selectedColRange: ClosedRange<Int>? {
        guard let anchor = anchorCell, let current = currentCell else { return nil }
        return min(anchor.col, current.col)...max(anchor.col, current.col)
    }

    var selectedVisualRowRange: ClosedRange<Int>? {
        guard let anchor = anchorCell, let current = currentCell else { return nil }
        return min(anchor.visualRow, current.visualRow)...max(anchor.visualRow, current.visualRow)
    }

    /// Converts top-down SwiftUI visual rows into bottom-up AppKit rows for `CustomSnapGridSpec`.
    var selectedAppKitRowRange: ClosedRange<Int>? {
        guard let visual = selectedVisualRowRange else { return nil }
        let lower = max(0, (rows - 1) - visual.upperBound)
        let upper = min(rows - 1, (rows - 1) - visual.lowerBound)
        return min(lower, upper)...max(lower, upper)
    }
}

private struct CustomSnapGridOverlayView: View {
    @ObservedObject var model: CustomSnapGridOverlayModel
    var onCommit: (CGRect) -> Void
    var onClose: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private let presets: [(cols: Int, rows: Int)] = [(2, 2), (3, 2), (4, 2)]

    private var accent: Color {
        SemanticCategoryPalette.color(
            for: .windowsDock,
            scheme: colorScheme,
            highContrast: colorSchemeContrast == .increased
        )
    }

    private var v2Strings: OverhaulV2Strings {
        OverhaulV2Strings.localized(l10n.language)
    }

    private var wave4Strings: OverhaulWave4Strings {
        OverhaulStrings.wave4(l10n.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            gridCanvas
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HUDBackdrop(cornerRadius: 18, contrast: .high))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(wave4Strings.customSnapGridLabel, systemImage: "square.grid.3x2")
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)

            if let colRange = model.selectedColRange, let rowRange = model.selectedVisualRowRange {
                Text("\(colRange.count)×\(rowRange.count)")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(accent.opacity(0.16)))
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                ForEach(presets, id: \.cols) { preset in
                    let active = model.columns == preset.cols && model.rows == preset.rows
                    Button {
                        model.applyPreset(columns: preset.cols, rows: preset.rows)
                    } label: {
                        Text("\(preset.cols)×\(preset.rows)")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(active ? accent.opacity(0.24) : Color.primary.opacity(0.08))
                            )
                            .overlay(
                                Capsule().strokeBorder(active ? accent.opacity(0.70) : Color.primary.opacity(0.12),
                                                       lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(active ? accent : .secondary)
                }
            }

            PanelCloseButton(label: l10n.s.menuClose, action: onClose)
        }
    }

    private var gridCanvas: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let gap: CGFloat = 8
            let spec = CustomSnapGridSpec(columns: model.columns, rows: model.rows, gap: gap)
            let totalHGap = gap * CGFloat(model.columns + 1)
            let totalVGap = gap * CGFloat(model.rows + 1)
            let cellW = max(12, (size.width - totalHGap) / CGFloat(model.columns))
            let cellH = max(12, (size.height - totalVGap) / CGFloat(model.rows))

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                    )

                ForEach(0..<model.rows, id: \.self) { row in
                    ForEach(0..<model.columns, id: \.self) { col in
                        let selected = isCellSelected(col: col, visualRow: row)
                        let x = gap * CGFloat(col + 1) + cellW * CGFloat(col)
                        let y = gap * CGFloat(row + 1) + cellH * CGFloat(row)
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selected ? accent.opacity(0.28) : Color.primary.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(selected ? accent.opacity(0.85) : Color.primary.opacity(0.12),
                                                  lineWidth: selected ? 1.5 : 1)
                            )
                            .frame(width: cellW, height: cellH)
                            .offset(x: x, y: y)
                    }
                }

                if let colRange = model.selectedColRange, let rowRange = model.selectedVisualRowRange {
                    let preview = spec.cellFrame(in: CGRect(origin: .zero, size: size),
                                                 colRange: colRange,
                                                 rowRange: rowRange)
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(accent.opacity(0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(accent, lineWidth: 2)
                        )
                        .frame(width: preview.width, height: preview.height)
                        .offset(x: preview.minX, y: preview.minY)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let start = cell(at: value.startLocation, in: size)
                        let current = cell(at: value.location, in: size)
                        if model.anchorCell != start {
                            model.anchorCell = start
                        }
                        if model.currentCell != current {
                            model.currentCell = current
                            VorssaintHaptics.generic()
                        }
                    }
                    .onEnded { value in
                        let start = cell(at: value.startLocation, in: size)
                        let end = cell(at: value.location, in: size)
                        model.anchorCell = start
                        model.currentCell = end
                        guard let colRange = model.selectedColRange,
                              let rowRange = model.selectedAppKitRowRange else {
                            model.clearDrag()
                            return
                        }
                        let screenSpec = CustomSnapGridSpec(columns: model.columns, rows: model.rows)
                        let targetFrame = screenSpec.cellFrame(in: model.targetVisibleFrame,
                                                               colRange: colRange,
                                                               rowRange: rowRange)
                        onCommit(targetFrame)
                    }
            )
        }
        .accessibilityLabel(v2Strings.customSnapOverlayButton)
    }

    private func cell(at point: CGPoint, in size: CGSize) -> CustomSnapGridOverlayModel.CellCoord {
        let clampedX = min(max(0, point.x), max(1, size.width - 1))
        let clampedY = min(max(0, point.y), max(1, size.height - 1))
        let col = min(model.columns - 1, max(0, Int(clampedX / max(1, size.width) * CGFloat(model.columns))))
        let row = min(model.rows - 1, max(0, Int(clampedY / max(1, size.height) * CGFloat(model.rows))))
        return CustomSnapGridOverlayModel.CellCoord(col: col, visualRow: row)
    }

    private func isCellSelected(col: Int, visualRow: Int) -> Bool {
        guard let colRange = model.selectedColRange,
              let rowRange = model.selectedVisualRowRange else {
            return false
        }
        return colRange.contains(col) && rowRange.contains(visualRow)
    }
}
