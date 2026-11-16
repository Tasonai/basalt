// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Side-by-side Light & Dark storybook gallery (`VORSSAINT_KIT_GALLERY=1`) to
/// visually verify every shared VorssaintDesignKit control, SettingsCard,
/// telemetry graph, and Mascot badge in both appearances at once.
struct VorssaintKitGalleryView: View {
    @ObservedObject private var l10n = L10n.shared

    private var strings: OverhaulV2Strings {
        OverhaulV2Strings.localized(l10n.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(strings.galleryTitle).font(.title2.bold())
                    Text(strings.gallerySubtitle).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            HStack(spacing: 16) {
                GalleryColumn(title: strings.galleryLightLabel, strings: strings)
                    .environment(\.colorScheme, .light)
                    .background(DesignSurfaceTier.canvas.fillColor(for: .light))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.10), lineWidth: 1)
                    )

                GalleryColumn(title: strings.galleryDarkLabel, strings: strings)
                    .environment(\.colorScheme, .dark)
                    .background(DesignSurfaceTier.canvas.fillColor(for: .dark))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 1120, height: 780)
    }
}

private struct GalleryColumn: View {
    let title: String
    let strings: OverhaulV2Strings

    @State private var toggleA = true
    @State private var toggleB = false
    @State private var selectedTab = 0
    @State private var sliderValue = 0.72
    @State private var eqGainValue = 0.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    NotchMascotView(look: NotchMascotSupport.look(), mood: .happy, size: 32)
                        .frame(width: 32, height: 32)
                }

                SettingsCard(title: "SettingsCard & Rows") {
                    SettingsRow(symbol: "sparkles", title: "Dynamic Island 2.5",
                                caption: "Ambient album art glow & haptics.") {
                        Toggle("", isOn: $toggleA).labelsHidden().toggleStyle(VorssaintCompactSwitchStyle())
                    }
                    Divider()
                    SettingsRow(symbol: "slider.horizontal.3", title: "Tactile Pill Toggle",
                                caption: "Custom pill style outside legacy Forms.") {
                        Toggle("", isOn: $toggleB).labelsHidden().toggleStyle(VorssaintPillToggleStyle(tone: .sound))
                    }
                }

                SettingsCard(title: "Segmented Tabs & Detent Sliders") {
                    VorssaintSegmentedTabs(
                        selection: $selectedTab,
                        options: [
                            .init(0, title: "Master", symbol: "speaker.wave.2.fill"),
                            .init(1, title: "Per-App", symbol: "app.badge"),
                            .init(2, title: "AUv3", symbol: "waveform")
                        ],
                        tone: .sound
                    )
                    VorssaintDetentSlider(
                        value: $sliderValue,
                        range: 0...1.5,
                        detent: 1.0,
                        tone: .energyDisplay,
                        icon: "sun.max.fill",
                        title: "Brightness & Boost",
                        formattedValue: String(format: "%d%%", locale: Locale(identifier: "en_US_POSIX"), Int((sliderValue * 100).rounded()))
                    )
                    VorssaintDetentSlider(
                        value: $eqGainValue,
                        range: -12...12,
                        detent: 0.0,
                        tone: .sound,
                        icon: "dial.medium.fill",
                        title: "Band Gain (0 dB detent)",
                        formattedValue: String(format: "%+.1f dB", locale: Locale(identifier: "en_US_POSIX"), eqGainValue)
                    )
                    HStack(spacing: 8) {
                        VorssaintActionChip(title: strings.savePresetButton, symbol: "checkmark", tone: .tools, prominent: true) {}
                        VorssaintActionChip(title: strings.resetFlatButton, symbol: "arrow.counterclockwise", tone: .brand) {}
                        VorssaintActionChip(title: "Remove", symbol: "trash", destructive: true) {}
                    }
                }

                SettingsCard(title: "Palette & Rhythm (4pt/8pt)") {
                    HStack(spacing: 8) {
                        ForEach(SemanticCategoryTone.allCases.prefix(6), id: \.rawValue) { tone in
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(tone.color(scheme: .dark))
                                .frame(height: 24)
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}

@MainActor
final class VorssaintKitGalleryWindowController {
    static let shared = VorssaintKitGalleryWindowController()
    private var window: NSWindow?

    func presentIfRequested() -> Bool {
        let env = ProcessInfo.processInfo.environment
        guard env["VORSSAINT_KIT_GALLERY"] == "1" else { return false }

        let hosting = NSHostingView(rootView: VorssaintKitGalleryView())
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 780),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = OverhaulV2Strings.localized(L10n.shared.language).galleryTitle
        win.contentView = hosting
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win

        if let snapDir = env["VORSSAINT_SNAPSHOT_DIR"], !snapDir.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                Self.writeBitmapSnapshot(window: win, directory: snapDir)
                NSApp.terminate(nil)
            }
        }
        return true
    }

    private static func writeBitmapSnapshot(window: NSWindow, directory: String) {
        guard let contentView = window.contentView else { return }
        contentView.layoutSubtreeIfNeeded()
        let bounds = contentView.bounds
        guard let rep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        contentView.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try? png.write(to: url.appendingPathComponent("designkit-gallery.png"), options: .atomic)
    }
}
