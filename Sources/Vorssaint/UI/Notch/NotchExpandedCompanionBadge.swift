// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Keeps the existing Mascot alive and interactive inside the expanded Dynamic Island
/// header without changing its visual rig, reacting to music playback, Keep Awake,
/// Mic Mute, Recording, active timers, and drag/pointer cues.
struct NotchExpandedCompanionBadge: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var awake = KeepAwakeManager.shared
    @ObservedObject private var mic = MicMuteService.shared
    @ObservedObject private var timer = NotchTimerService.shared
    @ObservedObject private var recorder = ScreenRecorderService.shared
    @ObservedObject private var commandBar = CommandBarService.shared

    @AppStorage(DefaultsKey.notchMascotEnabled) private var mascotEnabled = true
    @AppStorage(DefaultsKey.notchMascotStyle) private var mascotStyleRaw = NotchMascotStyle.minimal.rawValue
    @AppStorage(DefaultsKey.notchMascotShape) private var mascotShapeRaw = NotchMascotShape.ball.rawValue
    @AppStorage(DefaultsKey.notchMascotPalette) private var mascotPaletteRaw = NotchMascotPalette.pearl.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var cue: NotchMascotCue?
    @State private var cueID = 0

    private var look: NotchMascotLook {
        let style = NotchMascotStyle(rawValue: mascotStyleRaw) ?? .minimal
        let shape = NotchMascotShape(rawValue: mascotShapeRaw) ?? .ball
        let palette = NotchMascotPalette(rawValue: mascotPaletteRaw) ?? .pearl
        return NotchMascotLook(style: style, shape: shape, palette: palette)
    }

    private var resolvedMood: NotchMascotMood {
        if recorder.isRecording || mic.isMuted { return .alert }
        if commandBar.awaitsAnswers { return .thinking }
        if music.playback?.isPlaying == true { return .happy }
        if awake.isActive { return .alert }
        if timer.session.isRunning { return .determined }
        return .idle
    }

    private var musicAccent: Color {
        music.artworkTint?.color ?? SemanticCategoryTone.sound.badgeColor
    }

    private var badgeAccent: Color {
        if recorder.isRecording || mic.isMuted { return .red }
        if music.playback?.isPlaying == true { return musicAccent }
        if awake.isActive { return SemanticCategoryTone.energyDisplay.badgeColor }
        if timer.session.isRunning { return .cyan }
        return SemanticCategoryTone.dynamicIsland.badgeColor
    }

    private var isPlayingMusic: Bool { music.playback?.isPlaying == true }

    var body: some View {
        if AppFeature.notchMascot.isAvailable && mascotEnabled {
            HStack(spacing: 5) {
                NotchMascotView(
                    look: look,
                    mood: resolvedMood,
                    size: 21,
                    idles: true,
                    cue: cue,
                    cueID: cueID,
                    followsDrag: true,
                    followsPointer: true,
                    interactive: true
                )
                .frame(width: 22, height: 22)

                if isPlayingMusic {
                    NotchLiveEqualizerBars(
                        isPlaying: true,
                        bars: 3,
                        barWidth: 1.8,
                        height: 11,
                        tint: musicAccent
                    )
                    .padding(.trailing, 2)
                } else if recorder.isRecording || mic.isMuted {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                        .padding(.trailing, 2)
                } else if awake.isActive || timer.session.isRunning {
                    Circle()
                        .fill(badgeAccent)
                        .frame(width: 6, height: 6)
                        .padding(.trailing, 2)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 28)
            .background(
                Capsule(style: .continuous)
                    .fill(badgeAccent.opacity(0.14))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(badgeAccent.opacity(0.28), lineWidth: 0.6)
                    )
            )
            .contentShape(Capsule())
            .help("Companion")
            .onChange(of: music.playback?.track.title) { oldTitle, newTitle in
                guard newTitle != nil, newTitle != oldTitle else { return }
                fireCue(.celebrate)
            }
            .onChange(of: awake.isActive) { _, isActive in
                guard isActive else { return }
                fireCue(.celebrate)
            }
            .onChange(of: timer.session.isRunning) { _, isRunning in
                guard isRunning else { return }
                fireCue(.celebrate)
            }
            .onChange(of: service.selected) { _, _ in
                fireCue(.glance)
            }
            .onChange(of: service.notice?.event) { _, incoming in
                guard let incoming else { return }
                if incoming == .volume || incoming == .brightness {
                    fireCue(.glance)
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: isPlayingMusic)
        }
    }

    private func fireCue(_ next: NotchMascotCue) {
        guard !reduceMotion else { return }
        cue = next
        cueID &+= 1
    }
}
