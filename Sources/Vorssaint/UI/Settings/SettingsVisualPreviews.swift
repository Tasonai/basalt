// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Interactive miniature previews inside dense Settings panels so tuning spatial,
/// motion, and switcher options reads visually instead of as raw sliders alone.
struct WindowSnapZonePreview: View {
    enum Zone: String, CaseIterable {
        case topLeft, topHalf, topRight
        case leftHalf, center, rightHalf
        case bottomLeft, bottomHalf, bottomRight

        func rect(in size: CGSize, margin: CGFloat) -> CGRect {
            let m = max(2, margin)
            let w = size.width - m * 2
            let h = size.height - m * 2
            switch self {
            case .leftHalf:
                return CGRect(x: m, y: m, width: (w - m) / 2, height: h)
            case .rightHalf:
                return CGRect(x: m + (w + m) / 2, y: m, width: (w - m) / 2, height: h)
            case .topHalf:
                return CGRect(x: m, y: m, width: w, height: (h - m) / 2)
            case .bottomHalf:
                return CGRect(x: m, y: m + (h + m) / 2, width: w, height: (h - m) / 2)
            case .topLeft:
                return CGRect(x: m, y: m, width: (w - m) / 2, height: (h - m) / 2)
            case .topRight:
                return CGRect(x: m + (w + m) / 2, y: m, width: (w - m) / 2, height: (h - m) / 2)
            case .bottomLeft:
                return CGRect(x: m, y: m + (h + m) / 2, width: (w - m) / 2, height: (h - m) / 2)
            case .bottomRight:
                return CGRect(x: m + (w + m) / 2, y: m + (h + m) / 2, width: (w - m) / 2, height: (h - m) / 2)
            case .center:
                return CGRect(x: m + w * 0.14, y: m + h * 0.14, width: w * 0.72, height: h * 0.72)
            }
        }
    }

    let screenGap: Int
    let edgeSnapEnabled: Bool
    let strings: OverhaulStrings

    @State private var selectedZone: Zone = .leftHalf
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color {
        SemanticCategoryPalette.color(for: .windowsDock, scheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(strings.snapPreviewTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(strings.previewInteractiveHint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            GeometryReader { proxy in
                let size = proxy.size
                let scaledGap = min(14, max(3, CGFloat(screenGap) * 0.35))
                let previewRect = selectedZone.rect(in: size, margin: scaledGap)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.18), accent.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                        }

                    // Snap target preview window
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(accent.opacity(edgeSnapEnabled ? 0.85 : 0.4), lineWidth: 1.5)
                        }
                        .shadow(color: accent.opacity(0.22), radius: 6, y: 2)
                        .frame(width: max(12, previewRect.width), height: max(12, previewRect.height))
                        .offset(x: previewRect.minX, y: previewRect.minY)
                        .animation(DesignMotion.resolve(DesignMotion.snappy, reduceMotion: reduceMotion),
                                   value: selectedZone)
                        .animation(DesignMotion.resolve(DesignMotion.snappy, reduceMotion: reduceMotion),
                                   value: screenGap)

                    // Clickable 3x3 snap zone overlay
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            zoneHit(.topLeft); zoneHit(.topHalf); zoneHit(.topRight)
                        }
                        HStack(spacing: 0) {
                            zoneHit(.leftHalf); zoneHit(.center); zoneHit(.rightHalf)
                        }
                        HStack(spacing: 0) {
                            zoneHit(.bottomLeft); zoneHit(.bottomHalf); zoneHit(.bottomRight)
                        }
                    }
                }
            }
            .frame(height: 92)
        }
        .padding(.vertical, 4)
    }

    private func zoneHit(_ zone: Zone) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { selectedZone = zone }
    }
}

/// Interactive response curve preview visualizing step size, responsiveness, and coast.
struct MouseScrollCurvePreview: View {
    let step: Int
    let response: Int
    let coast: Int
    let strings: OverhaulStrings

    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color {
        SemanticCategoryPalette.color(for: .mouseKeyboard, scheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(strings.scrollPreviewCurveLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(step)pt · \(response)% · \(coast)%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Canvas { context, size in
                let w = size.width
                let h = size.height
                // Reference baseline grid
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: h * 0.5))
                grid.addLine(to: CGPoint(x: w, y: h * 0.5))
                context.stroke(grid, with: .color(.primary.opacity(0.08)), lineWidth: 0.75)

                // Smooth scroll impulse curve: rise driven by response, tail driven by coast
                let riseFactor = max(0.15, Double(response) / 100.0)
                let coastTail = max(0.1, Double(coast) / 100.0)
                let amp = min(0.85, max(0.32, Double(step) / 120.0))

                var curve = Path()
                var area = Path()
                let samples = 48
                for i in 0...samples {
                    let t = Double(i) / Double(samples)
                    let attack = 1 - exp(-t * (4.0 + riseFactor * 12.0))
                    let decay = exp(-t * (4.2 - coastTail * 2.8))
                    let yNorm = min(1.0, max(0.0, attack * decay * amp * 2.4))
                    let x = t * w
                    let y = h - 6 - CGFloat(yNorm) * (h - 14)
                    if i == 0 {
                        curve.move(to: CGPoint(x: x, y: y))
                        area.move(to: CGPoint(x: x, y: h - 4))
                        area.addLine(to: CGPoint(x: x, y: y))
                    } else {
                        curve.addLine(to: CGPoint(x: x, y: y))
                        area.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                area.addLine(to: CGPoint(x: w, y: h - 4))
                area.closeSubpath()

                context.fill(area, with: .linearGradient(
                    Gradient(colors: [accent.opacity(0.28), accent.opacity(0.02)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: h)
                ))
                context.stroke(curve, with: .color(accent), lineWidth: 2)
            }
            .frame(height: 54)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Live compact desktop mockup preview reflecting switcher layout, shortcut hints, and columns.
struct SwitcherLayoutLivePreview: View {
    let isSimple: Bool
    let isIcons: Bool
    let showShortcutHints: Bool
    let strings: OverhaulStrings

    @Environment(\.colorScheme) private var colorScheme
    private var accent: Color {
        SemanticCategoryPalette.color(for: .windowsDock, scheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(strings.switcherPreviewLayoutLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.22), Color.primary.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                if isSimple {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(0..<3, id: \.self) { row in
                            HStack(spacing: 6) {
                                Circle().fill(row == 0 ? accent : Color.secondary.opacity(0.45))
                                    .frame(width: 7, height: 7)
                                RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(row == 0 ? 0.55 : 0.22))
                                    .frame(width: row == 0 ? 78 : 62, height: 6)
                                Spacer()
                                if showShortcutHints {
                                    Text("⌘\(row + 1)")
                                        .font(.system(size: 8, weight: .semibold, design: .rounded).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(row == 0 ? accent.opacity(0.18) : .clear,
                                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                    }
                    .padding(8)
                    .frame(width: 170)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                } else {
                    HStack(spacing: 8) {
                        ForEach(0..<4, id: \.self) { idx in
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(idx == 1 ? accent.opacity(0.32) : Color.primary.opacity(0.10))
                                    .frame(width: isIcons ? 24 : 38, height: isIcons ? 24 : 28)
                                    .overlay {
                                        if idx == 1 {
                                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                .strokeBorder(accent, lineWidth: 1.5)
                                        }
                                    }
                                if showShortcutHints {
                                    Text("\(idx + 1)")
                                        .font(.system(size: 8, weight: .bold, design: .rounded).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .frame(height: 82)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.75)
            }
        }
        .padding(.vertical, 2)
    }
}
