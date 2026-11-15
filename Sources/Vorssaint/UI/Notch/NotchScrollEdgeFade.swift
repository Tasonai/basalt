// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// A scrolling page fades where more of it lies beyond an edge, so a card is
/// never sliced by a hard line. At rest at the start there is nothing to fade,
/// and the last row at the end stays clear. Earlier systems keep the hard edge.
struct NotchScrollEdgeFade: ViewModifier {
    var axis: Axis = .vertical
    var length: CGFloat = 16
    @State private var beyondStart = false
    @State private var beyondEnd = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content
                .onScrollGeometryChange(for: Edges.self) { geometry in
                    let offset = axis == .vertical ? geometry.contentOffset.y : geometry.contentOffset.x
                    let visible = axis == .vertical ? geometry.containerSize.height : geometry.containerSize.width
                    let total = axis == .vertical ? geometry.contentSize.height : geometry.contentSize.width
                    return Edges(start: offset > 1, end: offset + visible < total - 1)
                } action: { _, edges in
                    guard beyondStart != edges.start || beyondEnd != edges.end else { return }
                    DispatchQueue.main.async {
                        if beyondStart != edges.start { beyondStart = edges.start }
                        if beyondEnd != edges.end { beyondEnd = edges.end }
                    }
                }
                .mask { fadeMask }
        } else {
            content
        }
    }

    private struct Edges: Equatable { var start: Bool; var end: Bool }

    private var fadeMask: some View {
        let vertical = axis == .vertical
        return Rectangle().fill(.black)
            .overlay(alignment: vertical ? .top : .leading) {
                fade(toStart: true).opacity(beyondStart ? 1 : 0)
            }
            .overlay(alignment: vertical ? .bottom : .trailing) {
                fade(toStart: false).opacity(beyondEnd ? 1 : 0)
            }
            .compositingGroup()
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: beyondStart)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: beyondEnd)
    }

    /// Erases the mask toward the edge it sits on with a progressive multi-stop
    /// ease-out curve so scrolling items dissolve cleanly with zero abrupt banding.
    private func fade(toStart: Bool) -> some View {
        let vertical = axis == .vertical
        let from: UnitPoint = vertical ? (toStart ? .top : .bottom) : (toStart ? .leading : .trailing)
        let to: UnitPoint = vertical ? (toStart ? .bottom : .top) : (toStart ? .trailing : .leading)
        return LinearGradient(
            stops: [
                .init(color: .black, location: 0.0),
                .init(color: .black.opacity(0.84), location: 0.25),
                .init(color: .black.opacity(0.45), location: 0.58),
                .init(color: .black.opacity(0.12), location: 0.85),
                .init(color: .clear, location: 1.0),
            ],
            startPoint: from,
            endPoint: to
        )
        .frame(width: vertical ? nil : length, height: vertical ? length : nil)
        .blendMode(.destinationOut)
    }
}

struct OverlayScrollEdgeFade: ViewModifier {
    let contentHeight: CGFloat
    let viewportHeight: CGFloat
    let length: CGFloat

    private var active: Bool {
        contentHeight > viewportHeight + 2 && viewportHeight > length * 2
    }

    func body(content: Content) -> some View {
        if active {
            content.mask(
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .black.opacity(0.65), location: 0.45),
                            .init(color: .black, location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: length * 0.55)
                    Rectangle().fill(.black)
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .black.opacity(0.65), location: 0.55),
                            .init(color: .clear, location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: length)
                }
            )
        } else {
            content
        }
    }
}

extension View {
    func notchScrollEdgeFade(_ axis: Axis = .vertical, length: CGFloat = 16) -> some View {
        modifier(NotchScrollEdgeFade(axis: axis, length: length))
    }

    func notchScrollEdgeFade(axis: Axis, length: CGFloat = 16) -> some View {
        modifier(NotchScrollEdgeFade(axis: axis, length: length))
    }

    func overlayScrollEdgeFade(contentHeight: CGFloat, viewportHeight: CGFloat, length: CGFloat = 14) -> some View {
        modifier(OverlayScrollEdgeFade(contentHeight: contentHeight, viewportHeight: viewportHeight, length: length))
    }
}
