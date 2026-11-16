// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum Wave2V3FluidIslandAndOnboardingContract {
    static func run(_ suite: TestSuite) {
        testConcaveEarGeometryAndControlPoints(suite)
        testFluidKinematicsPhysics(suite)
        testOnboardingInteractiveStageContracts(suite)
    }

    private static func testConcaveEarGeometryAndControlPoints(_ suite: TestSuite) {
        let radii = NotchConcaveEarGeometry.resolvedRadii(
            for: CGSize(width: 240, height: 40),
            shoulder: 14,
            requestedBottom: 16
        )
        suite.expect(radii.topEarRadius == 14 && radii.bottomCornerRadius == 16,
                     "NotchConcaveEarGeometry preserves valid shoulder and bottom radii")

        let compactRadii = NotchConcaveEarGeometry.resolvedRadii(
            for: CGSize(width: 32, height: 18),
            shoulder: 20,
            requestedBottom: 20
        )
        suite.expect(compactRadii.topEarRadius <= 32 * 0.22 + 0.001
                     && compactRadii.bottomCornerRadius <= 18 * 0.48 + 0.001,
                     "NotchConcaveEarGeometry clamps radii safely inside tight dimensions")

        let zeroRadii = NotchConcaveEarGeometry.resolvedRadii(
            for: .zero,
            shoulder: 10,
            requestedBottom: 10
        )
        suite.expect(zeroRadii.topEarRadius == 0 && zeroRadii.bottomCornerRadius == 0,
                     "NotchConcaveEarGeometry returns zero radii for empty sizes")

        let rect = CGRect(x: 0, y: 0, width: 220, height: 48)
        let points = NotchConcaveEarGeometry.concaveShoulderControlPoints(
            rect: rect,
            shoulder: 14,
            bottom: 16
        )
        let pathRect = points.path(in: rect).boundingRect
        suite.expect(abs(pathRect.width - rect.width) <= 0.5 && abs(pathRect.height - rect.height) <= 0.5,
                     "NotchConcaveEarGeometry path bounds match notch surface rect cleanly")
    }

    private static func testFluidKinematicsPhysics(_ suite: TestSuite) {
        let projected = NotchFluidKinematics.project(velocity: 1000, decelerationRate: 0.998)
        suite.expect(abs(projected - 499.0) < 0.1,
                     "NotchFluidKinematics project computes Apple exponential momentum distance")

        let rb1 = NotchFluidKinematics.rubberBand(overshoot: 20, dimension: 200)
        let rb2 = NotchFluidKinematics.rubberBand(overshoot: 200, dimension: 200)
        let rbNeg = NotchFluidKinematics.rubberBand(overshoot: -20, dimension: 200)
        suite.expect(rb1 > 0 && rb1 < 20 && rb2 > rb1 && rb2 < 200 && abs(rbNeg + rb1) < 0.001,
                     "NotchFluidKinematics rubberBand produces smooth symmetric sublinear resistance")
        suite.expect(NotchFluidKinematics.rubberBand(overshoot: 20, dimension: 0) == 0,
                     "NotchFluidKinematics rubberBand guards zero dimension")

        let midScale = NotchFluidKinematics.hudOvershootScale(normalizedLevel: 0.5, delta: 0.1)
        let minStretch = NotchFluidKinematics.hudOvershootScale(normalizedLevel: 0.0, delta: -0.25)
        let maxStretch = NotchFluidKinematics.hudOvershootScale(normalizedLevel: 1.0, delta: 0.25)
        suite.expect(abs(midScale - 1.0) < 0.0001
                     && minStretch > 1.0 && minStretch <= 1.055
                     && maxStretch > 1.0 && maxStretch <= 1.055,
                     "NotchFluidKinematics stretches subtly only at 0%/100% boundaries")

        let scale = NotchFluidKinematics.decomposedSpringScale(
            from: CGSize(width: 100, height: 40),
            to: CGSize(width: 400, height: 20)
        )
        suite.expect(abs(scale.width - 1.15) < 0.0001 && abs(scale.height - 0.85) < 0.0001,
                     "decomposedSpringScale clamps X/Y spring scale ratios inside 0.85...1.15")
    }

    private static func testOnboardingInteractiveStageContracts(_ suite: TestSuite) {
        let stage = (try? String(contentsOfFile: "Sources/Vorssaint/UI/Onboarding/OnboardingInteractiveStageView.swift", encoding: .utf8)) ?? ""
        let onboarding = (try? String(contentsOfFile: "Sources/Vorssaint/UI/Onboarding/OnboardingView.swift", encoding: .utf8)) ?? ""
        let notchView = (try? String(contentsOfFile: "Sources/Vorssaint/UI/Notch/NotchView.swift", encoding: .utf8)) ?? ""

        suite.expect(stage.contains("NotchMascotView")
                     && stage.contains("enum OnboardingRoleProfile")
                     && stage.contains("onboardingTryIsland")
                     && stage.contains("onboardingTryCommandBar")
                     && stage.contains("onboardingTryShelf"),
                     "OnboardingInteractiveStageView hosts live Mascot stage, 3 sandboxes, and role profiles")

        suite.expect(onboarding.contains("OnboardingInteractiveStageView")
                     && onboarding.contains("VorssaintCheckPillStyle")
                     && !onboarding.contains(".toggleStyle(.checkbox)")
                     && !onboarding.contains(".toggleStyle(.switch)"),
                     "OnboardingView wires interactive stage and VorssaintDesignKit controls cleanly")

        suite.expect(notchView.contains("NotchFluidKinematics")
                     && notchView.contains("DesignMotion.fluidX")
                     && notchView.contains("NotchMascotView"),
                     "NotchView integrates NotchFluidKinematics springs and preserves Mascot")
    }
}
