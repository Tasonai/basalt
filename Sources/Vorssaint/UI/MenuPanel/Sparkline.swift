// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// A small history graph: a filled area under a smooth polyline. Hand-drawn with
/// `Path` so the app needs no charting framework (and stays clear of the SwiftUI
/// macro plugins the Command Line Tools cannot load).
///
/// `maxValue` fixes the vertical scale (CPU/memory use 1.0 for an absolute 0–100%
/// reading); when nil the graph auto-scales to its own peak (network, power).
struct Sparkline: View {
    var values: [Double]
    var color: Color
    var maxValue: Double? = nil
    var fillOpacity: Double = 0.16
    var lineWidth: CGFloat = 1.5
    var showsZeroBaseline = false
    var hoveredNormalizedX: Double? = nil
    var onHoverNormalizedX: ((Double?) -> Void)? = nil

    var body: some View {
        GeometryReader { geometry in
            let baselineY = max(0.5, geometry.size.height - 0.5)
            let topY: CGFloat = 0.5
            let points = points(in: geometry.size, baselineY: baselineY, topY: topY)
            if points.count >= 2 {
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: baselineY))
                        path.addLine(to: points[0])
                        addCatmullRomCurves(to: &path, points: points, minY: topY, maxY: baselineY)
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: baselineY))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(colors: [color.opacity(fillOpacity), color.opacity(0.02), color.opacity(0)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    if showsZeroBaseline {
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: baselineY))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: baselineY))
                        }
                        .stroke(Color.secondary.opacity(0.28), lineWidth: 1)
                    }
                    Path { path in
                        path.move(to: points[0])
                        addCatmullRomCurves(to: &path, points: points, minY: topY, maxY: baselineY)
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

                    if let hoveredX = hoveredNormalizedX, geometry.size.width > 1 {
                        let clamped = min(max(hoveredX, 0), 1)
                        let cursorX = geometry.size.width * CGFloat(clamped)
                        let sampleIndex = min(points.count - 1, max(0, Int((clamped * Double(points.count - 1)).rounded())))
                        let samplePoint = points[sampleIndex]

                        Path { path in
                            path.move(to: CGPoint(x: cursorX, y: 0))
                            path.addLine(to: CGPoint(x: cursorX, y: geometry.size.height))
                        }
                        .stroke(color.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))

                        Circle()
                            .fill(color)
                            .frame(width: 6, height: 6)
                            .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                            .position(x: samplePoint.x, y: samplePoint.y)
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    guard let onHoverNormalizedX else { return }
                    switch phase {
                    case .active(let location):
                        guard geometry.size.width > 0 else {
                            onHoverNormalizedX(nil)
                            return
                        }
                        let normalized = min(max(Double(location.x / geometry.size.width), 0), 1)
                        onHoverNormalizedX(normalized)
                    case .ended:
                        onHoverNormalizedX(nil)
                    }
                }
            }
        }
    }

    private func addCatmullRomCurves(to path: inout Path,
                                      points: [CGPoint],
                                      minY: CGFloat,
                                      maxY: CGFloat) {
        guard points.count >= 2 else { return }
        if points.count == 2 {
            path.addLine(to: points[1])
            return
        }
        let tension: CGFloat = 1.0 / 6.0
        for index in 0 ..< (points.count - 1) {
            let p0 = index > 0 ? points[index - 1] : points[index]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = (index + 2 < points.count) ? points[index + 2] : points[index + 1]

            let cp1x = p1.x + (p2.x - p0.x) * tension
            let cp1y = min(max(p1.y + (p2.y - p0.y) * tension, minY), maxY)
            let cp2x = p2.x - (p3.x - p1.x) * tension
            let cp2y = min(max(p2.y - (p3.y - p1.y) * tension, minY), maxY)
            path.addCurve(to: p2, control1: CGPoint(x: cp1x, y: cp1y), control2: CGPoint(x: cp2x, y: cp2y))
        }
    }

    private func points(in size: CGSize, baselineY: CGFloat, topY: CGFloat) -> [CGPoint] {
        guard values.count >= 2 else { return [] }
        let peak = max(maxValue ?? (values.max() ?? 1), 0.0001)
        let plotHeight = max(1, baselineY - topY)
        let lastIndex = values.count - 1
        return values.enumerated().map { index, value in
            let x = size.width * CGFloat(index) / CGFloat(lastIndex)
            let normalized = min(1, max(0, value / peak))
            let y = baselineY - plotHeight * CGFloat(normalized)
            return CGPoint(x: x, y: y)
        }
    }
}

extension View {
    /// Marks the top of a graph with a dashed rule and names its value on that
    /// rule, so the number reads as the scale and not as a sample.
    func graphCeilingLabel(_ text: String) -> some View {
        modifier(GraphCeilingLabel(text: text))
    }
}

private struct GraphCeilingLabel: ViewModifier {
    @AppStorage(DefaultsKey.monitorGraphScale) private var visible = true
    let text: String

    func body(content: Content) -> some View {
        if visible {
            content
                .overlay {
                    GeometryReader { geometry in
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: 0.5))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: 0.5))
                        }
                        .stroke(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    }
                    .allowsHitTesting(false)
                }
                // Over the oldest samples, so the newest stay clear.
                .overlay(alignment: .topLeading) {
                    Text(text)
                        .font(.system(size: 9))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 3)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 3))
                        .alignmentGuide(.top) { $0[VerticalAlignment.center] }
                        .allowsHitTesting(false)
                }
        } else {
            content
        }
    }
}
