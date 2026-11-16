// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Synchronized collapsible multi-track NLE timeline below the editor stage.
/// Keeps ruler, zoom blocks, keystrokes, captions, click SFX markers, audio
/// waveforms, and filmstrip trim/cuts aligned on one shared recording clock.
struct RecorderMultiTrackTimelineView: View {
    @ObservedObject var model: RecorderEditorModel
    @ObservedObject private var l10n = L10n.shared
    @AppStorage("recorderTimelineExpanded") private var isExpanded = true

    private let labelWidth: CGFloat = 88

    private var strings: RecorderFeatureStrings {
        FeatureStrings.recorder(l10n.language)
    }

    private var wave2: OverhaulWave2Strings {
        OverhaulStrings.wave2(l10n.language)
    }

    private var v2: OverhaulV2Strings {
        OverhaulV2Strings.localized(l10n.language)
    }

    private var v3: OverhaulV3Strings {
        OverhaulV3Strings.localized(l10n.language)
    }

    private var clickStyle: RecorderClickSFXStyle {
        RecorderClickSFXStyle.sanitized(model.document.clickSFXStyle)
    }

    private var showsSceneKeyframesLane: Bool {
        model.document.cameraBubble.isEnabled || !model.document.sceneKeyframes.isEmpty
    }

    private var showsKaraokeWordsLane: Bool {
        model.document.captionsEnabled && !model.document.whisperWords.isEmpty
    }

    private var showsKeystrokesLane: Bool {
        model.document.keystrokesEnabled && !model.document.keystrokes.isEmpty
    }

    private var showsCaptionsLane: Bool {
        !model.document.captions.isEmpty
    }

    private var showsClickSFXLane: Bool {
        clickStyle != .off
    }

    private var activeAuxiliaryLaneCount: Int {
        var count = 0
        if !model.document.texts.isEmpty { count += 1 }
        if !model.document.images.isEmpty { count += 1 }
        if !model.document.blurs.isEmpty { count += 1 }
        if showsSceneKeyframesLane { count += 1 }
        if showsKeystrokesLane { count += 1 }
        if showsCaptionsLane { count += 1 }
        if showsKaraokeWordsLane { count += 1 }
        if showsClickSFXLane { count += 1 }
        if model.hasAudio(.system) { count += 1 }
        if model.hasAudio(.microphone) { count += 1 }
        return count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            timelineHeader
            if isExpanded {
                expandedTracks
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                collapsedTracks
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.16), value: isExpanded)
    }

    // MARK: - Header

    private var timelineHeader: some View {
        HStack(spacing: 8) {
            Button {
                VorssaintHaptics.generic()
                isExpanded.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Image(systemName: "square.3.layers.3d")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.teal)
                    Text(v2.recorderTimelineTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            statusPills

            Spacer(minLength: 8)

            speedBadge
        }
        .frame(height: 20)
    }

    private var statusPills: some View {
        HStack(spacing: 5) {
            if model.document.cameraBubble.isEnabled {
                headerBadge(symbol: "video.circle",
                            text: model.hasCameraSidecar ? "PiP" : nil,
                            tint: .teal)
            }
            if !model.document.sceneKeyframes.isEmpty {
                headerBadge(symbol: "diamond.fill",
                            text: "\(model.document.sceneKeyframes.count)",
                            tint: .cyan)
            }
            if model.document.resolvedOutputAspect != .native {
                headerBadge(symbol: "aspectratio",
                            text: aspectBadgeText(model.document.resolvedOutputAspect),
                            tint: .mint)
            }
            if model.document.perspectiveTiltEnabled || model.document.perspectiveTilt3DEnabled {
                headerBadge(symbol: "view.3d",
                            text: nil,
                            tint: .indigo)
            }
            if model.document.ambientGlowEnabled {
                headerBadge(symbol: "sparkles",
                            text: nil,
                            tint: .orange)
            }
            if model.document.micAutoDuckingEnabled {
                headerBadge(symbol: "waveform",
                            text: "Duck",
                            tint: .blue)
            }
            if model.document.exportsProRes4444 {
                headerBadge(symbol: "film",
                            text: "4444",
                            tint: .purple)
            }
            if !isExpanded {
                collapsedSummaryBadges
            }
        }
    }

    private func aspectBadgeText(_ aspect: StudioOutputAspect) -> String {
        switch aspect {
        case .native: return "Native"
        case .vertical9x16: return "9:16"
        case .square1x1: return "1:1"
        case .cinema16x9: return "16:9"
        }
    }

    private var collapsedSummaryBadges: some View {
        HStack(spacing: 4) {
            if !model.document.zoomSegments.isEmpty {
                headerBadge(symbol: "plus.magnifyingglass",
                            text: "\(model.document.zoomSegments.count)",
                            tint: .teal)
            }
            if showsKeystrokesLane {
                headerBadge(symbol: "keyboard",
                            text: "\(model.document.keystrokes.count)",
                            tint: .blue)
            }
            if showsCaptionsLane {
                headerBadge(symbol: "captions.bubble",
                            text: "\(model.document.captions.filter { !$0.isCut }.count)",
                            tint: .accentColor)
            }
            if showsKaraokeWordsLane {
                headerBadge(symbol: "text.word.spacing",
                            text: "\(model.document.whisperWords.count)",
                            tint: .cyan)
            }
            if showsClickSFXLane {
                headerBadge(symbol: "cursorarrow.click.2",
                            text: clickStyle.shortDisplayName,
                            tint: .mint)
            }
            if model.hasAudio(.system) || model.hasAudio(.microphone) {
                headerBadge(symbol: "waveform",
                            text: nil,
                            tint: .blue)
            }
        }
    }

    private var speedBadge: some View {
        let speedText = String(format: "%.2g×",
                               locale: Locale(identifier: "en_US_POSIX"),
                               model.document.exportTiming.speed)
        return HStack(spacing: 4) {
            Image(systemName: "speedometer")
                .font(.system(size: 10, weight: .semibold))
            Text(v2.recorderSpeedTrackLabel)
                .font(.system(size: 10, weight: .medium))
            Text(speedText)
                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
        }
        .foregroundStyle(model.document.exportTiming.speed == 1 ? Color.secondary : Color.teal)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color.white.opacity(0.09), lineWidth: 0.75)
        }
    }

    private func headerBadge(symbol: String, text: String?, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .semibold))
            if let text {
                Text(text)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded).monospacedDigit())
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tint.opacity(0.14), in: Capsule())
    }

    // MARK: - Tracks

    private var expandedTracks: some View {
        VStack(spacing: 5) {
            timelineRow(strings.zoomSectionLabel, symbol: "plus.magnifyingglass") {
                VStack(spacing: 3) {
                    ClickRuler(model: model).frame(height: 12)
                    RecorderZoomLane(model: model,
                                     kind: .zoom,
                                     emptyHint: strings.zoomLaneEmptyHint)
                        .frame(height: 28)
                    if !model.document.zoomSegments.isEmpty {
                        zoomSegmentBadgeStrip
                    }
                }
            }

            if activeAuxiliaryLaneCount > 4 {
                ScrollView(.vertical, showsIndicators: true) {
                    auxiliaryLanes
                }
                .frame(maxHeight: 132)
            } else if activeAuxiliaryLaneCount > 0 {
                auxiliaryLanes
            }

            timelineRow(strings.editorTitle, symbol: "film") {
                Filmstrip(model: model).frame(height: 52)
            }
        }
    }

    private var collapsedTracks: some View {
        VStack(spacing: 4) {
            timelineRow(strings.editorTitle, symbol: "film") {
                VStack(spacing: 2) {
                    ClickRuler(model: model).frame(height: 10)
                    Filmstrip(model: model).frame(height: 40)
                }
            }
        }
    }

    @ViewBuilder
    private var auxiliaryLanes: some View {
        VStack(spacing: 5) {
            if !model.document.texts.isEmpty {
                timelineRow(strings.textContentLabel, symbol: "textformat") {
                    RecorderZoomLane(model: model,
                                     kind: .text,
                                     emptyHint: strings.textLaneEmptyHint)
                        .frame(height: 26)
                }
            }
            if !model.document.images.isEmpty {
                timelineRow(strings.imageLaneLabel, symbol: "photo") {
                    RecorderZoomLane(model: model,
                                     kind: .image,
                                     emptyHint: strings.imageLaneEmptyHint)
                        .frame(height: 26)
                }
            }
            if !model.document.blurs.isEmpty {
                timelineRow(strings.blurLaneLabel, symbol: "aqi.medium") {
                    RecorderZoomLane(model: model,
                                     kind: .blur,
                                     emptyHint: strings.blurLaneEmptyHint)
                        .frame(height: 26)
                }
            }
            if showsSceneKeyframesLane {
                timelineRow(v3.recorderCameraShapeTitle, symbol: "diamond") {
                    SceneKeyframeTimelineLane(model: model)
                        .frame(height: 24)
                }
            }
            if showsKeystrokesLane {
                timelineRow(wave2.keystrokeHUDTitle, symbol: "keyboard") {
                    KeystrokeTimelineLane(model: model)
                        .frame(height: 24)
                }
            }
            if showsCaptionsLane {
                timelineRow(wave2.captionsTrackTitle, symbol: "captions.bubble") {
                    CaptionTimelineLane(model: model)
                        .frame(height: 24)
                }
            }
            if showsKaraokeWordsLane {
                timelineRow("Karaoke", symbol: "text.word.spacing") {
                    KaraokeWordTimelineLane(model: model)
                        .frame(height: 24)
                }
            }
            if showsClickSFXLane {
                timelineRow(wave2.clickSFXTitle, symbol: "cursorarrow.click.2") {
                    ClickSFXTimelineLane(model: model, style: clickStyle)
                        .frame(height: 22)
                }
            }
            if model.hasAudio(.system) {
                timelineRow(strings.systemAudioTrackLabel, symbol: "speaker.wave.2") {
                    RecorderAudioLane(model: model, source: .system)
                        .frame(height: 28)
                }
            }
            if model.hasAudio(.microphone) {
                timelineRow(strings.microphoneTrackLabel, symbol: "mic") {
                    RecorderAudioLane(model: model, source: .microphone)
                        .frame(height: 28)
                }
            }
        }
    }

    private var zoomSegmentBadgeStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(model.document.zoomSegments) { segment in
                    let isSelected = model.selectedZoomID == segment.id
                    let factor = String(format: "%.1f×",
                                        locale: Locale(identifier: "en_US_POSIX"),
                                        segment.amount)
                    Button {
                        VorssaintHaptics.alignment()
                        model.selectZoomAndSeek(isSelected ? nil : segment.id)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: segment.followsPointer ? "cursorarrow.rays" : "scope")
                                .font(.system(size: 8.5, weight: .semibold))
                            Text(factor)
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded).monospacedDigit())
                        }
                        .foregroundStyle(isSelected ? .black : .white.opacity(0.86))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            isSelected ? Color.teal : Color.teal.opacity(0.22),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule().strokeBorder(Color.teal.opacity(isSelected ? 0 : 0.45), lineWidth: 0.75)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 18)
    }

    private func timelineRow<Content: View>(
        _ title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                Image(systemName: symbol)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.85))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(width: labelWidth, alignment: .trailing)

            content()
        }
    }
}

// MARK: - Studio Sub-Lanes

private struct KeystrokeTimelineLane: View {
    @ObservedObject var model: RecorderEditorModel

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            let height = proxy.size.height
            let duration = max(0.001, model.duration)
            let visible = visibleKeystrokes(width: width, duration: duration)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.blue.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.blue.opacity(0.24), lineWidth: 0.75)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let ratio = Double(min(1, max(0, location.x / width)))
                        model.seek(to: ratio * duration)
                    }

                ForEach(visible) { event in
                    let rawX = CGFloat(min(1, max(0, event.timestamp / duration))) * width
                    let clampedX = min(max(12, rawX), max(12, width - 22))
                    Button {
                        VorssaintHaptics.alignment()
                        model.seek(to: event.timestamp)
                    } label: {
                        Text(event.formattedCapString)
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.45),
                                        in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.6)
                            }
                    }
                    .buttonStyle(.plain)
                    .position(x: clampedX, y: height / 2)
                }

                playheadNeedle(width: width, height: height, duration: duration)
            }
        }
    }

    private func visibleKeystrokes(width: CGFloat, duration: Double) -> [RecorderKeystrokeEvent] {
        var accepted: [RecorderKeystrokeEvent] = []
        var lastX: CGFloat = -.greatestFiniteMagnitude
        let minSpacing: CGFloat = 26
        for event in model.document.keystrokes {
            let x = CGFloat(min(1, max(0, event.timestamp / duration))) * width
            if x - lastX >= minSpacing {
                accepted.append(event)
                lastX = x
                if accepted.count >= 40 { break }
            }
        }
        return accepted
    }

    private func playheadNeedle(width: CGFloat, height: CGFloat, duration: Double) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.85))
            .frame(width: 1.5, height: height)
            .offset(x: CGFloat(min(1, max(0, model.sourceTime / duration))) * width - 0.75)
            .allowsHitTesting(false)
    }
}

private struct CaptionTimelineLane: View {
    @ObservedObject var model: RecorderEditorModel

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            let height = proxy.size.height
            let duration = max(0.001, model.duration)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.07))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 0.75)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let ratio = Double(min(1, max(0, location.x / width)))
                        model.seek(to: ratio * duration)
                    }

                ForEach(model.document.captions) { segment in
                    let startX = CGFloat(min(1, max(0, segment.start / duration))) * width
                    let endX = CGFloat(min(1, max(0, segment.end / duration))) * width
                    let pillWidth = max(24, min(width - startX, max(endX - startX, 24)))
                    Button {
                        VorssaintHaptics.generic()
                        model.seek(to: segment.start)
                        model.toggleCaptionCut(segment.id)
                    } label: {
                        Text(segment.text)
                            .font(.system(size: 9.5, weight: .medium))
                            .strikethrough(segment.isCut)
                            .lineLimit(1)
                            .foregroundStyle(segment.isCut ? Color.orange.opacity(0.85) : .white)
                            .padding(.horizontal, 5)
                            .frame(width: pillWidth, height: height - 4, alignment: .leading)
                            .background(
                                (segment.isCut ? Color.orange.opacity(0.22) : Color.accentColor.opacity(0.3)),
                                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(
                                        (segment.isCut ? Color.orange.opacity(0.5) : Color.accentColor.opacity(0.55)),
                                        lineWidth: 0.75
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .offset(x: startX)
                }

                Rectangle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 1.5, height: height)
                    .offset(x: CGFloat(min(1, max(0, model.sourceTime / duration))) * width - 0.75)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct ClickSFXTimelineLane: View {
    @ObservedObject var model: RecorderEditorModel
    let style: RecorderClickSFXStyle

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            let height = proxy.size.height
            let duration = max(0.001, model.duration)
            let clicks = model.pointerTrack.clicks.filter(\.isDown)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.mint.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.mint.opacity(0.24), lineWidth: 0.75)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let target = Double(min(1, max(0, location.x / width))) * duration
                        VorssaintHaptics.alignment()
                        model.seek(to: target)
                    }

                ForEach(Array(clicks.enumerated()), id: \.offset) { _, click in
                    let x = CGFloat(min(1, max(0, click.time / duration))) * width
                    Capsule()
                        .fill(Color.mint.opacity(0.85))
                        .frame(width: 2.5, height: max(6, height - 8))
                        .offset(x: max(1, min(width - 3, x - 1.25)))
                        .allowsHitTesting(false)
                }

                HStack {
                    Spacer()
                    Text(style.shortDisplayName)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.mint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.45), in: Capsule())
                        .padding(.trailing, 5)
                }
                .allowsHitTesting(false)

                Rectangle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 1.5, height: height)
                    .offset(x: CGFloat(min(1, max(0, model.sourceTime / duration))) * width - 0.75)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct SceneKeyframeTimelineLane: View {
    @ObservedObject var model: RecorderEditorModel

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            let height = proxy.size.height
            let duration = max(0.001, model.duration)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.teal.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.teal.opacity(0.24), lineWidth: 0.75)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let ratio = Double(min(1, max(0, location.x / width)))
                        VorssaintHaptics.alignment()
                        model.seek(to: ratio * duration)
                    }

                ForEach(model.document.sceneKeyframes) { keyframe in
                    let rawX = CGFloat(min(1, max(0, keyframe.timeSeconds / duration))) * width
                    let clampedX = min(max(10, rawX), max(10, width - 26))
                    let isSelected = model.selectedSceneKeyframeID == keyframe.id
                    let tint = markerTint(for: keyframe.shape)

                    Button {
                        VorssaintHaptics.alignment()
                        model.selectSceneKeyframeAndSeek(isSelected ? nil : keyframe.id)
                    } label: {
                        Image(systemName: isSelected ? "diamond.fill" : "diamond")
                            .font(.system(size: isSelected ? 12 : 10.5, weight: .bold))
                            .foregroundStyle(isSelected ? Color.white : tint)
                            .padding(3)
                            .background(tint.opacity(isSelected ? 0.85 : 0.25), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .position(x: clampedX, y: height / 2)
                }

                HStack {
                    Spacer()
                    Button {
                        VorssaintHaptics.generic()
                        model.addOrUpdateSceneKeyframe()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.teal)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.45), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 4)
                }

                Rectangle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 1.5, height: height)
                    .offset(x: CGFloat(min(1, max(0, model.sourceTime / duration))) * width - 0.75)
                    .allowsHitTesting(false)
            }
        }
    }

    private func markerTint(for shape: CameraBubbleShape) -> Color {
        switch shape {
        case .circle: return .teal
        case .squircle: return .cyan
        case .verticalPortrait: return .purple
        case .hidden: return .orange
        }
    }
}

private struct KaraokeWordTimelineLane: View {
    @ObservedObject var model: RecorderEditorModel

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            let height = proxy.size.height
            let duration = max(0.001, model.duration)
            let tokens = model.document.whisperWords
            let activeIdx = WhisperCLITranscriptParser.activeWordIndex(at: model.sourceTime, tokens: tokens)
            let visible = visibleWordIndices(tokens: tokens, activeIdx: activeIdx, width: width, duration: duration)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.cyan.opacity(0.07))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.cyan.opacity(0.22), lineWidth: 0.75)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let ratio = Double(min(1, max(0, location.x / width)))
                        model.seek(to: ratio * duration)
                    }

                ForEach(visible, id: \.self) { idx in
                    let token = tokens[idx]
                    let isActive = activeIdx == idx
                    let rawX = CGFloat(min(1, max(0, token.startSeconds / duration))) * width
                    let clampedX = min(max(16, rawX), max(16, width - 24))
                    Button {
                        VorssaintHaptics.alignment()
                        model.seek(to: token.startSeconds)
                    } label: {
                        Text(token.word)
                            .font(.system(size: 9, weight: isActive ? .bold : .medium))
                            .foregroundStyle(isActive ? Color.black : Color.white.opacity(0.88))
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                isActive ? Color.teal : Color.cyan.opacity(0.26),
                                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .position(x: clampedX, y: height / 2)
                }

                Rectangle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 1.5, height: height)
                    .offset(x: CGFloat(min(1, max(0, model.sourceTime / duration))) * width - 0.75)
                    .allowsHitTesting(false)
            }
        }
    }

    private func visibleWordIndices(tokens: [WhisperWordToken],
                                    activeIdx: Int?,
                                    width: CGFloat,
                                    duration: Double) -> [Int] {
        var accepted: [Int] = []
        var lastX: CGFloat = -.greatestFiniteMagnitude
        let minSpacing: CGFloat = 28
        for (idx, token) in tokens.enumerated() {
            let x = CGFloat(min(1, max(0, token.startSeconds / duration))) * width
            if idx == activeIdx || x - lastX >= minSpacing {
                accepted.append(idx)
                lastX = x
                if accepted.count >= 48 { break }
            }
        }
        return accepted
    }
}

extension RecorderClickSFXStyle {
    var shortDisplayName: String {
        switch self {
        case .off: return "Off"
        case .softTap: return "Soft"
        case .mechanical: return "Mechanical"
        case .crispPop: return "Crisp"
        }
    }
}
