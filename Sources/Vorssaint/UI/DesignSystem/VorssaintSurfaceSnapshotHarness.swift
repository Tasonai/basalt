// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Darwin
import QuartzCore
import SwiftUI

/// Headless offscreen Retina snapshot harness (`VORSSAINT_SURFACE_SNAPSHOT_DIR`)
/// that renders five core Vorssaint surfaces into `@2x` PNG files using
/// offscreen `NSHostingView` + `NSBitmapImageRep` without allocating windows.
@MainActor
enum VorssaintSurfaceSnapshotHarness {
    static let environmentKey = "VORSSAINT_SURFACE_SNAPSHOT_DIR"

    private struct SnapshotSpec {
        let fileName: String
        let size: CGSize
        let appearanceName: NSAppearance.Name
        let makeView: () -> AnyView
    }

    static func captureAllAndExit(toDirectoryPath rawPath: String) {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            NSApp.terminate(nil)
            return
        }

        let directoryURL = URL(fileURLWithPath: trimmed, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let specs: [SnapshotSpec] = [
                SnapshotSpec(
                    fileName: "menupanel-light.png",
                    size: CGSize(width: 756, height: 600),
                    appearanceName: .aqua,
                    makeView: { AnyView(MenuPanelSnapshotSurface(scheme: .light)) }
                ),
                SnapshotSpec(
                    fileName: "menupanel-dark.png",
                    size: CGSize(width: 756, height: 600),
                    appearanceName: .darkAqua,
                    makeView: { AnyView(MenuPanelSnapshotSurface(scheme: .dark)) }
                ),
                SnapshotSpec(
                    fileName: "island-expanded-dark.png",
                    size: CGSize(width: 680, height: 340),
                    appearanceName: .darkAqua,
                    makeView: { AnyView(ExpandedIslandSnapshotSurface()) }
                ),
                SnapshotSpec(
                    fileName: "onboarding-stage-dark.png",
                    size: CGSize(width: 640, height: 340),
                    appearanceName: .darkAqua,
                    makeView: { AnyView(OnboardingStageSnapshotSurface()) }
                ),
                SnapshotSpec(
                    fileName: "spacelens-sunburst-dark.png",
                    size: CGSize(width: 780, height: 420),
                    appearanceName: .darkAqua,
                    makeView: { AnyView(SpaceLensSunburstSnapshotSurface()) }
                ),
            ]

            for spec in specs {
                let appearance = NSAppearance(named: spec.appearanceName) ?? NSAppearance(named: .darkAqua)!
                try renderRetinaPNG(
                    view: spec.makeView(),
                    size: spec.size,
                    appearance: appearance,
                    to: directoryURL.appendingPathComponent(spec.fileName)
                )
            }

            print("VORSSAINT_SNAPSHOTS_OK: 5 files -> \(directoryURL.path)")
            fflush(stdout)
            NSApp.terminate(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                exit(0)
            }
        } catch {
            fputs("VORSSAINT_SNAPSHOTS_ERROR: \(error.localizedDescription)\n", stderr)
            fflush(stderr)
            exit(1)
        }
    }

    private static func renderRetinaPNG(
        view: AnyView,
        size: CGSize,
        appearance: NSAppearance,
        to fileURL: URL
    ) throws {
        let scale = 2
        let scheme: ColorScheme = appearance.name == .aqua ? .light : .dark
        let rootView = view
            .environment(\.colorScheme, scheme)
            .frame(width: size.width, height: size.height)

        let hosting = NSHostingView(rootView: rootView)
        hosting.appearance = appearance
        hosting.wantsLayer = true
        hosting.frame = NSRect(origin: .zero, size: size)

        for _ in 0..<2 {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        hosting.layoutSubtreeIfNeeded()
        CATransaction.flush()

        let pixelsWide = max(2, Int((size.width * CGFloat(scale)).rounded()))
        let pixelsHigh = max(2, Int((size.height * CGFloat(scale)).rounded()))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try pngData.write(to: fileURL, options: .atomic)
    }
}

// MARK: - 1 & 2. MenuPanel + Bento & DesignKit Surface (Light & Dark)

private struct MenuPanelSnapshotSurface: View {
    let scheme: ColorScheme
    @ObservedObject private var l10n = L10n.shared
    @State private var toggleA = true
    @State private var toggleB = false
    @State private var selectedTab = 0
    @State private var boostValue = 1.0
    @State private var eqGain = 2.5

    var body: some View {
        let v2 = OverhaulV2Strings.localized(l10n.language)
        ZStack(alignment: .top) {
            DesignSurfaceTier.canvas.fillColor(for: scheme)

            HStack(alignment: .top, spacing: DesignSpace.lg) {
                MenuPanelView()
                    .frame(width: 332)
                    .background(
                        RoundedRectangle(cornerRadius: DesignRadius.panel, style: .continuous)
                            .fill(DesignSurfaceTier.elevated.fillColor(for: scheme))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DesignRadius.panel, style: .continuous))
                    .hairlineSpecularBorder(cornerRadius: DesignRadius.panel, opacity: 0.22)
                    .shadow(color: Color.black.opacity(scheme == .dark ? 0.42 : 0.12), radius: 14, x: 0, y: 6)

                VStack(alignment: .leading, spacing: DesignSpace.sm + 2) {
                    HStack(spacing: DesignSpace.sm) {
                        BrandBadge(size: 32)
                        VStack(alignment: .leading, spacing: DesignSpace.xxs) {
                            Text(v2.galleryTitle)
                                .font(.system(size: 13.5, weight: .bold))
                                .lineLimit(1)
                            Text(scheme == .light ? v2.galleryLightLabel : v2.galleryDarkLabel)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        MascotCameoBadge(mood: .happy, tone: .brand, size: 28, interactiveCue: false)
                    }

                    SettingsCard(title: v2.bentoQuickTitle) {
                        HStack(spacing: DesignSpace.sm) {
                            SnapshotBentoMiniCard(
                                title: v2.bentoKeepAwakeTile,
                                value: "Active",
                                symbol: "cup.and.saucer.fill",
                                tone: .energyDisplay
                            )
                            SnapshotBentoMiniCard(
                                title: v2.bentoMicMuteTile,
                                value: "Live",
                                symbol: "mic.slash.fill",
                                tone: .sound
                            )
                        }
                        Divider()
                        SettingsRow(
                            symbol: "sparkles",
                            title: "Dynamic Island 3.0",
                            caption: "Concave ears & ambient bloom."
                        ) {
                            Toggle("", isOn: $toggleA)
                                .labelsHidden()
                                .toggleStyle(VorssaintCompactSwitchStyle(tone: .dynamicIsland))
                        }
                        Divider()
                        SettingsRow(
                            symbol: "slider.horizontal.3",
                            title: "Loudness Contour",
                            caption: "Fletcher-Munson curve."
                        ) {
                            Toggle("", isOn: $toggleB)
                                .labelsHidden()
                                .toggleStyle(VorssaintPillToggleStyle(tone: .sound))
                                .fixedSize()
                        }
                    }

                    SettingsCard(title: "DesignKit Controls") {
                        VorssaintSegmentedTabs(
                            selection: $selectedTab,
                            options: [
                                .init(0, title: "Master", symbol: "speaker.wave.2.fill"),
                                .init(1, title: "Per-App", symbol: "app.badge"),
                                .init(2, title: "AUv3", symbol: "waveform"),
                            ],
                            tone: .sound
                        )

                        VorssaintDetentSlider(
                            value: $boostValue,
                            range: 0...1.5,
                            detent: 1.0,
                            tone: .energyDisplay,
                            icon: "sun.max.fill",
                            title: "XDR Headroom",
                            formattedValue: "\(Int((boostValue * 100).rounded()))%"
                        )

                        VorssaintDetentSlider(
                            value: $eqGain,
                            range: -12...12,
                            detent: 0.0,
                            tone: .sound,
                            icon: "dial.medium.fill",
                            title: "Parametric Band",
                            formattedValue: String(format: "%+.1f dB", locale: .autoupdatingCurrent, eqGain)
                        )

                        HStack(spacing: DesignSpace.sm) {
                            VorssaintActionChip(title: v2.savePresetButton, symbol: "checkmark", tone: .tools, prominent: true) {}
                            VorssaintActionChip(title: v2.resetFlatButton, symbol: "arrow.counterclockwise", tone: .brand) {}
                        }
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .padding(DesignSpace.lg)
        }
    }
}

private struct SnapshotBentoMiniCard: View {
    let title: String
    let value: String
    let symbol: String
    let tone: SemanticCategoryTone
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let accent = tone.color(scheme: colorScheme)
        HStack(spacing: DesignSpace.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignRadius.iconTile, style: .continuous)
                    .fill(accent.opacity(colorScheme == .dark ? 0.24 : 0.14))
                    .frame(width: 24, height: 24)
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(accent)
            }
            Spacer(minLength: 0)
        }
        .padding(DesignSpace.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignRadius.innerGroup, style: .continuous)
                .fill(accent.opacity(colorScheme == .dark ? 0.12 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignRadius.innerGroup, style: .continuous)
                .strokeBorder(accent.opacity(0.28), lineWidth: 0.75)
        )
    }
}

// MARK: - 3. Expanded Dynamic Island (Dark Mode)

private struct ExpandedIslandSnapshotSurface: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let v2 = OverhaulV2Strings.localized(l10n.language)
        let islandSize = CGSize(width: 604, height: 284)
        let islandShape = NotchShape(
            attached: true,
            radius: 26,
            floatingGap: nil,
            shoulderFit: 6,
            radiusFit: 0
        )
        let bloomColor = SemanticCategoryTone.dynamicIsland.badgeColor
        let earGeometry = NotchConcaveEarGeometry.resolvedRadii(
            for: islandSize,
            shoulder: NotchLayout.shoulder(height: islandSize.height) + 6,
            requestedBottom: 26
        )

        ZStack(alignment: .top) {
            Theme.spaceGradient

            RadialGradient(
                colors: [bloomColor.opacity(0.22), SemanticCategoryTone.sound.badgeColor.opacity(0.08), .clear],
                center: UnitPoint(x: 0.5, y: 0.28),
                startRadius: 20,
                endRadius: 340
            )

            // Simulated top menu bar behind the hardware notch.
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 30)

            ZStack(alignment: .top) {
                islandShape
                    .fill(Color.black)
                    .overlay(
                        RadialGradient(
                            colors: [bloomColor.opacity(0.16), .clear],
                            center: .top,
                            startRadius: 16,
                            endRadius: 300
                        )
                        .clipShape(islandShape)
                    )
                    .overlay(
                        islandShape
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.22),
                                        Color.white.opacity(0.10),
                                        Color.white.opacity(0.04),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1.0
                            )
                    )
                    .shadow(color: bloomColor.opacity(0.26), radius: 18, x: 0, y: 8)

                VStack(spacing: DesignSpace.md) {
                    // Concave top camera header bar.
                    HStack(spacing: DesignSpace.sm) {
                        HStack(spacing: DesignSpace.xs + 1) {
                            NotchMascotView(
                                look: NotchMascotLook(style: .minimal, shape: .pill, palette: .lilac),
                                mood: .happy,
                                size: 21,
                                idles: false,
                                followsPointer: true,
                                interactive: true
                            )
                            .frame(width: 22, height: 22)

                            SnapshotStaticEqualizer(tint: SemanticCategoryTone.sound.badgeColor)
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(
                            Capsule(style: .continuous)
                                .fill(SemanticCategoryTone.sound.badgeColor.opacity(0.14))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(SemanticCategoryTone.sound.badgeColor.opacity(0.28), lineWidth: 0.6)
                                )
                        )

                        Text(FeatureStrings.notch(l10n.language).title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white)

                        Spacer(minLength: 0)

                        // Physical MacBook camera lens housing.
                        ZStack {
                            Capsule(style: .continuous)
                                .fill(Color(white: 0.08))
                                .frame(width: 96, height: 22)
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
                                )
                            Circle()
                                .fill(Color(white: 0.16))
                                .frame(width: 8, height: 8)
                                .overlay(
                                    Circle()
                                        .fill(Color.cyan.opacity(0.45))
                                        .frame(width: 3, height: 3)
                                        .offset(x: -1, y: -1)
                                )
                        }

                        Spacer(minLength: 0)

                        HStack(spacing: DesignSpace.xs + 2) {
                            islandHeaderPill(symbol: "square.grid.2x2")
                            islandHeaderPill(symbol: "pin.fill", active: true)
                            islandHeaderPill(symbol: "gearshape")
                        }
                    }
                    .padding(.top, DesignSpace.sm)
                    .padding(.horizontal, max(DesignSpace.lg, earGeometry.topEarRadius + DesignSpace.md))

                    // Live Island Cards (Music + System Pulse + Quick Controls).
                    HStack(alignment: .top, spacing: DesignSpace.md) {
                        // Now Playing live card.
                        VStack(alignment: .leading, spacing: DesignSpace.sm) {
                            HStack(spacing: DesignSpace.sm) {
                                RoundedRectangle(cornerRadius: DesignRadius.innerGroup, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [bloomColor, SemanticCategoryTone.sound.badgeColor],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Image(systemName: "music.note")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(.white)
                                    )

                                VStack(alignment: .leading, spacing: DesignSpace.xxs) {
                                    Text("Midnight Glass")
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Text("Spatial Audio · 48 kHz")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.white.opacity(0.65))
                                }
                                Spacer(minLength: 0)
                            }

                            NotchMeter(value: 0.64, height: 5, tint: SemanticCategoryTone.sound.badgeColor)

                            HStack(spacing: DesignSpace.lg) {
                                Spacer(minLength: 0)
                                Image(systemName: "backward.fill")
                                Image(systemName: "play.fill")
                                    .font(.system(size: 14, weight: .bold))
                                Image(systemName: "forward.fill")
                                Spacer(minLength: 0)
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                        }
                        .padding(DesignSpace.md)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
                                )
                        )

                        // System Pulse live card.
                        VStack(alignment: .leading, spacing: DesignSpace.sm) {
                            Text(v2.bentoTelemetryTitle)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.75))

                            islandMetricRow(
                                label: l10n.s.cpuLabel,
                                value: "34%",
                                level: 0.34,
                                symbol: "cpu",
                                tint: SemanticCategoryTone.monitor.badgeColor
                            )
                            islandMetricRow(
                                label: l10n.s.memorySection,
                                value: "11.4 GB",
                                level: 0.48,
                                symbol: "memorychip",
                                tint: SemanticCategoryTone.clipboardFiles.badgeColor
                            )
                            islandMetricRow(
                                label: l10n.s.powerSection,
                                value: "8.2 W",
                                level: 0.28,
                                symbol: "bolt.fill",
                                tint: SemanticCategoryTone.energyDisplay.badgeColor
                            )
                        }
                        .padding(DesignSpace.md)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
                                )
                        )
                    }
                    .frame(height: 126)
                    .padding(.horizontal, max(DesignSpace.lg, earGeometry.topEarRadius + DesignSpace.md))

                    // Bottom quick action rail inside expanded island.
                    HStack(spacing: DesignSpace.sm) {
                        islandQuickTile(title: v2.bentoKeepAwakeTile, symbol: "cup.and.saucer.fill", tone: .energyDisplay, active: true)
                        islandQuickTile(title: v2.bentoMicMuteTile, symbol: "mic.slash.fill", tone: .sound, active: false)
                        islandQuickTile(title: "Shelf", symbol: "tray.full.fill", tone: .clipboardFiles, active: true)
                        islandQuickTile(title: "Quick AI", symbol: "sparkles", tone: .dynamicIsland, active: false)
                    }
                    .padding(.horizontal, max(DesignSpace.lg, earGeometry.topEarRadius + DesignSpace.md))
                    .padding(.bottom, DesignSpace.md)
                }
            }
            .frame(width: islandSize.width, height: islandSize.height)
            .clipShape(islandShape)
        }
    }

    private func islandHeaderPill(symbol: String, active: Bool = false) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(active ? .white : .white.opacity(0.75))
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: DesignRadius.pill, style: .continuous)
                    .fill(Color.white.opacity(active ? 0.18 : 0.08))
            )
    }

    private func islandMetricRow(label: String, value: String, level: Double, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer(minLength: 4)
                Text(value)
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            NotchMeter(value: level, height: 4, tint: tint)
        }
    }

    private func islandQuickTile(title: String, symbol: String, tone: SemanticCategoryTone, active: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? tone.badgeColor : .white.opacity(0.75))
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, DesignSpace.md)
        .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
        .background(
            RoundedRectangle(cornerRadius: DesignRadius.innerGroup, style: .continuous)
                .fill(active ? tone.badgeColor.opacity(0.22) : Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignRadius.innerGroup, style: .continuous)
                        .strokeBorder(active ? tone.badgeColor.opacity(0.50) : Color.white.opacity(0.12), lineWidth: 0.75)
                )
        )
    }
}

private struct SnapshotStaticEqualizer: View {
    let tint: Color
    private let heights: [CGFloat] = [6, 12, 9, 14]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<heights.count, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: 2.5, height: heights[index])
            }
        }
        .frame(height: 14, alignment: .center)
    }
}

// MARK: - 4. Interactive Onboarding Stage (Dark Mode)

private struct OnboardingStageSnapshotSurface: View {
    var body: some View {
        ZStack {
            DesignSurfaceTier.canvas.fillColor(for: .dark)

            OnboardingInteractiveStageView(showsBrandHeader: true, showsSandboxCards: true)
                .padding(DesignSpace.lg)
                .background(
                    RoundedRectangle(cornerRadius: DesignRadius.window, style: .continuous)
                        .fill(DesignSurfaceTier.elevated.fillColor(for: .dark))
                )
                .hairlineSpecularBorder(cornerRadius: DesignRadius.window, opacity: 0.22)
                .padding(DesignSpace.md)
        }
    }
}

// MARK: - 5. Space Lens Sunburst + Collect Drawer (Dark Mode)

private struct SpaceLensSunburstSnapshotSurface: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var chartMode = 0

    private static let ringPalette: [SemanticCategoryTone] = [
        .tools, .windowsDock, .energyDisplay, .clipboardFiles, .dynamicIsland,
    ]

    private var rootNodes: [SpaceLensNode] {
        [
            SpaceLensNode(
                id: "derived",
                name: "DerivedData",
                path: "/Users/Developer/Library/Developer/Xcode/DerivedData",
                bytes: 28_400_000_000,
                isDirectory: true,
                children: [
                    SpaceLensNode(id: "derived-idx", name: "Index.noindex", path: "/tmp/idx", bytes: 17_600_000_000, isDirectory: true, children: [
                        SpaceLensNode(id: "derived-idx-swift", name: "SwiftModules", path: "/tmp/idx/swift", bytes: 11_200_000_000, isDirectory: true),
                        SpaceLensNode(id: "derived-idx-db", name: "DataStore", path: "/tmp/idx/db", bytes: 6_400_000_000, isDirectory: true),
                    ]),
                    SpaceLensNode(id: "derived-build", name: "Build", path: "/tmp/build", bytes: 10_800_000_000, isDirectory: true),
                ],
                categoryIndex: 0
            ),
            SpaceLensNode(
                id: "docker",
                name: "Docker & VMs",
                path: "/Users/Developer/Library/Containers/com.docker.docker",
                bytes: 18_600_000_000,
                isDirectory: true,
                children: [
                    SpaceLensNode(id: "docker-raw", name: "Docker.raw", path: "/tmp/docker.raw", bytes: 12_400_000_000, isDirectory: false),
                    SpaceLensNode(id: "docker-vm", name: "LinuxKit", path: "/tmp/vm", bytes: 6_200_000_000, isDirectory: true),
                ],
                categoryIndex: 1
            ),
            SpaceLensNode(
                id: "caches",
                name: "Caches",
                path: "/Users/Developer/Library/Caches",
                bytes: 14_200_000_000,
                isDirectory: true,
                children: [
                    SpaceLensNode(id: "caches-brew", name: "Homebrew", path: "/tmp/brew", bytes: 8_800_000_000, isDirectory: true),
                    SpaceLensNode(id: "caches-clang", name: "Clang", path: "/tmp/clang", bytes: 5_400_000_000, isDirectory: true),
                ],
                categoryIndex: 2
            ),
            SpaceLensNode(
                id: "downloads",
                name: "Downloads",
                path: "/Users/Developer/Downloads",
                bytes: 9_800_000_000,
                isDirectory: true,
                children: [
                    SpaceLensNode(id: "dl-dmg", name: "Installers", path: "/tmp/dmg", bytes: 6_200_000_000, isDirectory: true),
                    SpaceLensNode(id: "dl-iso", name: "Archives", path: "/tmp/iso", bytes: 3_600_000_000, isDirectory: true),
                ],
                categoryIndex: 3
            ),
            SpaceLensNode(
                id: "media",
                name: "ScreenCaptures",
                path: "/Users/Developer/Desktop/Captures",
                bytes: 7_400_000_000,
                isDirectory: true,
                children: [
                    SpaceLensNode(id: "media-mov", name: "Recordings", path: "/tmp/mov", bytes: 4_800_000_000, isDirectory: true),
                    SpaceLensNode(id: "media-png", name: "Shots", path: "/tmp/png", bytes: 2_600_000_000, isDirectory: true),
                ],
                categoryIndex: 4
            ),
        ]
    }

    private var rootTree: SpaceLensNode {
        let total = rootNodes.reduce(Int64(0)) { $0 + $1.bytes }
        return SpaceLensNode(
            id: "root",
            name: "Library",
            path: "/Users/Developer/Library",
            bytes: total,
            isDirectory: true,
            children: rootNodes
        )
    }

    private var arcs: [SpaceLensSunburstArc] {
        SpaceLensSunburst.buildArcs(root: rootTree, maxDepth: 4)
    }

    private func tone(for arc: SpaceLensSunburstArc) -> SemanticCategoryTone {
        let ring1 = arcs.filter { $0.ringDepth == 1 }
        if let idx = ring1.firstIndex(where: { arc.startAngle >= $0.startAngle - 1e-6 && arc.endAngle <= $0.endAngle + 1e-6 }) {
            return Self.ringPalette[idx % Self.ringPalette.count]
        }
        return .tools
    }

    private var stagedBasket: SpaceLensCollectBasket {
        var basket = SpaceLensCollectBasket()
        basket.add(path: "~/Library/Developer/Xcode/DerivedData", sizeBytes: 16_200_000_000, name: "Xcode/DerivedData")
        basket.add(path: "~/Library/Developer/Xcode/iOS DeviceSupport", sizeBytes: 5_400_000_000, name: "iOS DeviceSupport")
        basket.add(path: "~/Downloads/Archive/Old.dmg", sizeBytes: 3_200_000_000, name: "Old DMG Installers")
        return basket
    }

    var body: some View {
        let v3 = OverhaulV3Strings.localized(l10n.language)
        let formatter: (Int64) -> String = { bytes in
            ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
        let basket = stagedBasket

        ZStack {
            DesignSurfaceTier.canvas.fillColor(for: .dark)

            VStack(alignment: .leading, spacing: DesignSpace.md) {
                // Header toolbar.
                HStack(spacing: DesignSpace.sm) {
                    MascotCameoBadge(mood: .determined, reaction: .sweep, tone: .tools, size: 28, interactiveCue: false)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(OverhaulStrings.wave4(l10n.language).spaceLensTitle)
                            .font(.system(size: 14, weight: .bold))
                        HStack(spacing: DesignSpace.xs) {
                            Label("Macintosh HD", systemImage: "internaldrive")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8.5, weight: .semibold))
                            Text("Users/Developer/Library")
                        }
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: DesignSpace.sm)
                    VorssaintSegmentedTabs(
                        selection: $chartMode,
                        options: [
                            .init(0, title: v3.spaceLensSunburstMode, symbol: "chart.pie.fill"),
                            .init(1, title: v3.spaceLensTreemapMode, symbol: "square.grid.2x2"),
                        ],
                        tone: .tools
                    )
                }

                // Sunburst + Collect Basket split.
                HStack(spacing: DesignSpace.lg) {
                    sunburstStage(formatter: formatter)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous)
                                .fill(DesignSurfaceTier.elevated.fillColor(for: .dark))
                        )
                        .hairlineSpecularBorder(cornerRadius: DesignRadius.card, opacity: 0.18)

                    collectBasketDrawer(basket: basket, v3: v3, formatter: formatter)
                        .frame(width: 286)
                        .background(
                            RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous)
                                .fill(DesignSurfaceTier.elevated.fillColor(for: .dark))
                        )
                        .hairlineSpecularBorder(cornerRadius: DesignRadius.card, opacity: 0.22)
                }
            }
            .padding(DesignSpace.lg)
        }
    }

    private func sunburstStage(formatter: @escaping (Int64) -> String) -> some View {
        let computedArcs = arcs
        return HStack(spacing: DesignSpace.lg) {
            ZStack {
                ForEach(computedArcs) { arc in
                    let arcColor = tone(for: arc).badgeColor
                    SunburstRingSegment(
                        startAngle: .radians(arc.startAngle - .pi / 2.0),
                        endAngle: .radians(arc.endAngle - .pi / 2.0),
                        innerRadiusRatio: ringInnerRatio(arc.ringDepth),
                        outerRadiusRatio: ringOuterRatio(arc.ringDepth)
                    )
                    .fill(arcColor.opacity(ringOpacity(arc.ringDepth)))
                    .overlay(
                        SunburstRingSegment(
                            startAngle: .radians(arc.startAngle - .pi / 2.0),
                            endAngle: .radians(arc.endAngle - .pi / 2.0),
                            innerRadiusRatio: ringInnerRatio(arc.ringDepth),
                            outerRadiusRatio: ringOuterRatio(arc.ringDepth)
                        )
                        .stroke(Color(white: 0.12), lineWidth: 1.5)
                    )
                }

                Circle()
                    .fill(DesignSurfaceTier.canvas.fillColor(for: .dark))
                    .frame(width: 88, height: 88)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
                VStack(spacing: 2) {
                    Text(formatter(rootTree.bytes))
                        .font(.system(size: 13.5, weight: .bold).monospacedDigit())
                    Text("\(rootNodes.count) folders")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 204, height: 204)

            VStack(alignment: .leading, spacing: DesignSpace.sm + 2) {
                ForEach(Array(rootNodes.enumerated()), id: \.element.id) { idx, node in
                    let color = Self.ringPalette[idx % Self.ringPalette.count].badgeColor
                    HStack(spacing: DesignSpace.xs + 2) {
                        Circle()
                            .fill(color)
                            .frame(width: 8, height: 8)
                        Text(node.title)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: DesignSpace.xs)
                        Text(formatter(node.bytes))
                            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DesignSpace.md)
    }

    private func collectBasketDrawer(
        basket: SpaceLensCollectBasket,
        v3: OverhaulV3Strings,
        formatter: @escaping (Int64) -> String
    ) -> some View {
        let toolsTone = SemanticCategoryTone.tools.color(scheme: .dark)
        return VStack(alignment: .leading, spacing: DesignSpace.md) {
            HStack(spacing: DesignSpace.sm) {
                Image(systemName: "basket.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(toolsTone)
                Text(v3.spaceLensCollectTitle)
                    .font(.system(size: 12.5, weight: .bold))
                Spacer(minLength: 0)
                Text(formatter(basket.totalBytes))
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(toolsTone)
                    .padding(.horizontal, DesignSpace.sm)
                    .padding(.vertical, 2)
                    .background(Capsule(style: .continuous).fill(toolsTone.opacity(0.16)))
            }

            Divider()

            VStack(spacing: DesignSpace.sm) {
                ForEach(Array(basket.items.enumerated()), id: \.element.id) { idx, item in
                    let tone = Self.ringPalette[idx % Self.ringPalette.count]
                    HStack(spacing: DesignSpace.sm) {
                        ZStack {
                            RoundedRectangle(cornerRadius: DesignRadius.iconTile, style: .continuous)
                                .fill(tone.badgeColor.opacity(0.18))
                                .frame(width: 24, height: 24)
                            Image(systemName: idx < 2 ? "folder.fill" : "doc.fill")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(tone.badgeColor)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            Text(item.path)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer(minLength: DesignSpace.xs)

                        Text(formatter(item.sizeBytes))
                            .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(DesignSpace.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DesignRadius.innerGroup, style: .continuous)
                            .fill(DesignSurfaceTier.card.fillColor(for: .dark))
                    )
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: DesignSpace.sm) {
                Text("\(basket.items.count) items staged")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                VorssaintActionChip(title: v3.spaceLensCollectTrashAll, symbol: "trash", destructive: true) {}
            }
        }
        .padding(DesignSpace.md)
    }

    private func ringInnerRatio(_ ring: Int) -> CGFloat {
        switch ring {
        case 1: return 0.44
        case 2: return 0.64
        default: return 0.82
        }
    }

    private func ringOuterRatio(_ ring: Int) -> CGFloat {
        switch ring {
        case 1: return 0.62
        case 2: return 0.80
        default: return 0.96
        }
    }

    private func ringOpacity(_ ring: Int) -> Double {
        switch ring {
        case 1: return 0.92
        case 2: return 0.72
        default: return 0.52
        }
    }
}

private struct SunburstRingSegment: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let innerRadiusRatio: CGFloat
    let outerRadiusRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let maxRadius = min(rect.width, rect.height) * 0.5
        let innerR = maxRadius * innerRadiusRatio
        let outerR = maxRadius * outerRadiusRatio

        var path = Path()
        path.addArc(center: center, radius: outerR, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.addArc(center: center, radius: innerR, startAngle: endAngle, endAngle: startAngle, clockwise: true)
        path.closeSubpath()
        return path
    }
}
