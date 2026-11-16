// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import SwiftUI

/// Concave ear and convex corner geometry for a Dynamic Island silhouette attached
/// to the display's top bezel.
struct NotchConcaveEarGeometry: Equatable, Sendable {
    /// Cubic Bezier anchor and control points describing the attached notch corners
    /// in clockwise order starting from the top-right bezel junction.
    struct ControlPoints: Equatable, Sendable {
        let topEarRadius: CGFloat
        let bottomCornerRadius: CGFloat

        let topRightStart: CGPoint
        let topRightControl1: CGPoint
        let topRightControl2: CGPoint
        let topRightEnd: CGPoint

        let bottomRightStart: CGPoint
        let bottomRightControl1: CGPoint
        let bottomRightControl2: CGPoint
        let bottomRightEnd: CGPoint

        let bottomLeftStart: CGPoint
        let bottomLeftControl1: CGPoint
        let bottomLeftControl2: CGPoint
        let bottomLeftEnd: CGPoint

        let topLeftStart: CGPoint
        let topLeftControl1: CGPoint
        let topLeftControl2: CGPoint
        let topLeftEnd: CGPoint

        /// Builds the closed clockwise outline for the attached notch silhouette.
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: topRightStart)
            path.addCurve(to: topRightEnd, control1: topRightControl1, control2: topRightControl2)
            path.addLine(to: bottomRightStart)
            path.addCurve(to: bottomRightEnd, control1: bottomRightControl1, control2: bottomRightControl2)
            path.addLine(to: bottomLeftStart)
            path.addCurve(to: bottomLeftEnd, control1: bottomLeftControl1, control2: bottomLeftControl2)
            path.addLine(to: topLeftStart)
            path.addCurve(to: topLeftEnd, control1: topLeftControl1, control2: topLeftControl2)
            path.closeSubpath()
            return path
        }
    }

    /// Circular-arc cubic Bezier handle ratio: 4 * (sqrt(2) - 1) / 3.
    static let opticalTangent: CGFloat = 0.55228475

    let topEarRadius: CGFloat
    let bottomCornerRadius: CGFloat

    /// Clamps concave top ear and convex bottom corner radii smoothly to the bounds of `size`
    /// so opposing shoulders and bottom corners never invert or self-intersect.
    static func resolvedRadii(for size: CGSize, shoulder: CGFloat, requestedBottom: CGFloat) -> NotchConcaveEarGeometry {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            return NotchConcaveEarGeometry(topEarRadius: 0, bottomCornerRadius: 0)
        }
        let safeShoulder = shoulder.isFinite ? shoulder : 4
        let safeBottom = requestedBottom.isFinite ? requestedBottom : 2
        let topEar = min(max(4, safeShoulder), size.width * 0.22, size.height * 0.45)
        let bottomCorner = min(max(2, safeBottom), size.height * 0.48, max(2, (size.width - topEar * 2) * 0.5))
        return NotchConcaveEarGeometry(topEarRadius: topEar, bottomCornerRadius: bottomCorner)
    }

    /// Computes cubic Bezier tangent and anchor points for seamless bezel fusion
    /// when the island is attached to the display notch.
    static func concaveShoulderControlPoints(rect: CGRect, shoulder: CGFloat, bottom: CGFloat) -> ControlPoints {
        guard rect.width.isFinite, rect.height.isFinite,
              rect.minX.isFinite, rect.minY.isFinite,
              rect.width > 0, rect.height > 0 else {
            let origin = CGPoint(x: rect.minX.isFinite ? rect.minX : 0, y: rect.minY.isFinite ? rect.minY : 0)
            return ControlPoints(
                topEarRadius: 0,
                bottomCornerRadius: 0,
                topRightStart: origin,
                topRightControl1: origin,
                topRightControl2: origin,
                topRightEnd: origin,
                bottomRightStart: origin,
                bottomRightControl1: origin,
                bottomRightControl2: origin,
                bottomRightEnd: origin,
                bottomLeftStart: origin,
                bottomLeftControl1: origin,
                bottomLeftControl2: origin,
                bottomLeftEnd: origin,
                topLeftStart: origin,
                topLeftControl1: origin,
                topLeftControl2: origin,
                topLeftEnd: origin
            )
        }

        let radii = resolvedRadii(for: rect.size, shoulder: shoulder, requestedBottom: bottom)
        let s = radii.topEarRadius
        let b = min(radii.bottomCornerRadius, max(0, (rect.width - s * 2) * 0.5))
        let topSpan = s * opticalTangent
        let earInset = s * (1 - opticalTangent)
        let bottomSpan = b * (1 - opticalTangent)

        return ControlPoints(
            topEarRadius: s,
            bottomCornerRadius: b,
            topRightStart: CGPoint(x: rect.maxX, y: rect.minY),
            topRightControl1: CGPoint(x: rect.maxX - topSpan, y: rect.minY),
            topRightControl2: CGPoint(x: rect.maxX - s, y: rect.minY + earInset),
            topRightEnd: CGPoint(x: rect.maxX - s, y: rect.minY + s),
            bottomRightStart: CGPoint(x: rect.maxX - s, y: rect.maxY - b),
            bottomRightControl1: CGPoint(x: rect.maxX - s, y: rect.maxY - bottomSpan),
            bottomRightControl2: CGPoint(x: rect.maxX - s - bottomSpan, y: rect.maxY),
            bottomRightEnd: CGPoint(x: rect.maxX - s - b, y: rect.maxY),
            bottomLeftStart: CGPoint(x: rect.minX + s + b, y: rect.maxY),
            bottomLeftControl1: CGPoint(x: rect.minX + s + bottomSpan, y: rect.maxY),
            bottomLeftControl2: CGPoint(x: rect.minX + s, y: rect.maxY - bottomSpan),
            bottomLeftEnd: CGPoint(x: rect.minX + s, y: rect.maxY - b),
            topLeftStart: CGPoint(x: rect.minX + s, y: rect.minY + s),
            topLeftControl1: CGPoint(x: rect.minX + s, y: rect.minY + earInset),
            topLeftControl2: CGPoint(x: rect.minX + topSpan, y: rect.minY),
            topLeftEnd: CGPoint(x: rect.minX, y: rect.minY)
        )
    }
}

/// Pure fluid kinematics for Dynamic Island momentum projection, elastic rubber-banding,
/// boundary HUD overshoot, and decomposed X/Y morph scaling.
enum NotchFluidKinematics {
    private static let maximumHUDOvershoot: CGFloat = 0.055
    private static let maximumMorphScale: CGFloat = 1.15
    private static let minimumMorphScale: CGFloat = 0.85

    /// Apple Fluid Interfaces exponential momentum projection distance after release.
    static func project(velocity: Double, decelerationRate: Double = 0.998) -> Double {
        guard velocity.isFinite, decelerationRate.isFinite,
              decelerationRate > 0, decelerationRate < 1 else {
            return 0
        }
        return (velocity / 1000.0) * decelerationRate / (1.0 - decelerationRate)
    }

    /// Progressive edge resistance preserving the sign of `overshoot` when `dimension > 0`.
    static func rubberBand(overshoot: CGFloat, dimension: CGFloat, constant: CGFloat = 0.55) -> CGFloat {
        guard overshoot.isFinite, dimension.isFinite, constant.isFinite,
              dimension > 0, constant > 0, overshoot != 0 else {
            return 0
        }
        let magnitude = abs(overshoot)
        let damped = (magnitude * dimension * constant) / (dimension + constant * magnitude)
        return overshoot >= 0 ? damped : -damped
    }

    /// Subtle horizontal stretch (`1.0...1.055`) when pushing past `0.0` downward or `1.0` upward
    /// on boundary HUD updates; returns `1.0` inside `0.01...0.99`.
    static func hudOvershootScale(normalizedLevel: Double, delta: Double) -> CGFloat {
        guard normalizedLevel.isFinite, delta.isFinite else { return 1.0 }
        if (0.01...0.99).contains(normalizedLevel) {
            return 1.0
        }

        let push: Double
        if normalizedLevel < 0.01 {
            let beyondLower = max(0.0, -normalizedLevel)
            if delta < 0 {
                push = beyondLower + abs(delta)
            } else if normalizedLevel < 0.0 && delta == 0 {
                push = beyondLower
            } else {
                push = 0
            }
        } else {
            let beyondUpper = max(0.0, normalizedLevel - 1.0)
            if delta > 0 {
                push = beyondUpper + delta
            } else if normalizedLevel > 1.0 && delta == 0 {
                push = beyondUpper
            } else {
                push = 0
            }
        }

        guard push > 0 else { return 1.0 }
        let stretch = rubberBand(overshoot: CGFloat(push), dimension: maximumHUDOvershoot)
        return min(1.0 + maximumHUDOvershoot, max(1.0, 1.0 + stretch))
    }

    /// Normalized X/Y scale ratio from `oldSize` to `newSize`, clamped to `0.85...1.15`
    /// for independent fluid spring morphs.
    static func decomposedSpringScale(from oldSize: CGSize, to newSize: CGSize) -> CGSize {
        func axisRatio(from oldValue: CGFloat, to newValue: CGFloat) -> CGFloat {
            guard oldValue.isFinite, newValue.isFinite, oldValue > 0, newValue > 0 else {
                return 1.0
            }
            return min(maximumMorphScale, max(minimumMorphScale, newValue / oldValue))
        }

        return CGSize(
            width: axisRatio(from: oldSize.width, to: newSize.width),
            height: axisRatio(from: oldSize.height, to: newSize.height)
        )
    }
}
