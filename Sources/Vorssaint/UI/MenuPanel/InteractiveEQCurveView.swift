// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Compact segmented studio VU meter bar driven at 30Hz by `MixerMeterPublisher`.
struct LiveVUMeterBar: View {
    let appID: String
    let isPlaying: Bool
    @ObservedObject var meterFeed: MixerMeterPublisher
    var axis: Axis = .horizontal
    var barLength: CGFloat = 26
    var barThickness: CGFloat = 5
    var showIdlePlayingIndicator: Bool = true

    var body: some View {
        RealtimeLevelMeterBar(level: meterFeed.level(for: appID),
                              isActive: isPlaying,
                              axis: axis,
                              barLength: barLength,
                              barThickness: barThickness,
                              showIdleIndicator: showIdlePlayingIndicator)
    }
}

/// Reusable segmented studio VU meter bar for any normalized `0...1` audio level.
struct RealtimeLevelMeterBar: View {
    let level: Float
    var isActive: Bool = true
    var axis: Axis = .horizontal
    var barLength: CGFloat = 26
    var barThickness: CGFloat = 5
    var showIdleIndicator: Bool = true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let segmentCount = 6

    private var clampedLevel: CGFloat {
        guard level.isFinite else { return 0 }
        return CGFloat(min(max(level, 0), 1))
    }

    var body: some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: 1.5))
            : AnyLayout(VStackLayout(spacing: 1.5))
        let activeCount = Int((clampedLevel * CGFloat(Self.segmentCount)).rounded(.up))
        layout {
            ForEach(0..<Self.segmentCount, id: \.self) { rawIndex in
                let index = axis == .horizontal ? rawIndex : (Self.segmentCount - 1 - rawIndex)
                let lit = index < activeCount || (showIdleIndicator && isActive && activeCount == 0 && index == 0)
                let color = segmentColor(at: index, lit: lit, isIdlePulse: isActive && activeCount == 0 && index == 0)
                RoundedRectangle(cornerRadius: 1.25, style: .continuous)
                    .fill(color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: axis == .horizontal ? barLength : barThickness,
               height: axis == .horizontal ? barThickness : barLength)
        .animation(reduceMotion ? nil : .linear(duration: 0.06), value: activeCount)
        .accessibilityHidden(true)
    }

    private func segmentColor(at index: Int, lit: Bool, isIdlePulse: Bool) -> Color {
        guard lit else {
            return Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.10)
        }
        if isIdlePulse {
            return PanelMetricColor.green(for: colorScheme).opacity(0.7)
        }
        if index == Self.segmentCount - 1 {
            return PanelMetricColor.red(for: colorScheme)
        }
        if index == Self.segmentCount - 2 {
            return PanelMetricColor.orange(for: colorScheme)
        }
        return PanelMetricColor.green(for: colorScheme)
    }
}

/// Interactive 10-band parametric EQ spline editor (31Hz–16kHz, -12...+12 dB)
/// with gradient underfill, 0 dB magnetic detent haptics, double-click reset,
/// and inline preset save/rename/delete via `CustomEQPresetStore`.
struct InteractiveEQCurveView: View {
    let title: String
    /// `nil` edits Master EQ; non-nil edits that specific app's persistent/session EQ key.
    let appKey: String?
    var compact: Bool = false
    var curveHeight: CGFloat = 116

    @ObservedObject private var mixer = AppVolumeMixer.shared
    @ObservedObject private var presetStore = CustomEQPresetStore.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var activeBand: Int?
    @State private var hoveredBand: Int?
    @State private var isSavingPreset = false
    @State private var isRenamingPreset = false
    @State private var presetNameDraft = ""

    private static let bandLabels = ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    private static let minDB: Double = -12
    private static let maxDB: Double = 12

    private var gains: [Float] {
        let raw = appKey.map { mixer.eqGains(for: $0) } ?? mixer.masterEQGains()
        return Self.normalizedDisplayGains(raw)
    }

    private var isFlat: Bool {
        gains.allSatisfy { abs($0) < 0.05 }
    }

    private var activePresetID: String? {
        mixer.activeEQPresetID(for: appKey)
    }

    private var activePreset: MixerEQPreset? {
        guard let id = activePresetID else { return nil }
        return presetStore.preset(id: id)
    }

    private var isCustomPresetActive: Bool {
        guard let id = activePresetID else { return false }
        return presetStore.isCustomPreset(id: id)
    }

    private var toneColor: Color {
        SemanticCategoryTone.sound.color(scheme: colorScheme,
                                         highContrast: colorSchemeContrast == .increased)
    }

    private var isRussian: Bool {
        l10n.language == .ru
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            headerRow
            splineCanvas
            frequencyAxisLabels
            toolbarRow
            if isSavingPreset || isRenamingPreset {
                inlinePresetEditorRow
            }
        }
        .padding(compact ? 8 : 10)
        .background(
            RoundedRectangle(cornerRadius: DesignRadius.innerGroup, style: .continuous)
                .fill(DesignSurfaceTier.card.fillColor(for: colorScheme))
        )
        .hairlineSpecularBorder(cornerRadius: DesignRadius.innerGroup, opacity: 0.16)
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Label {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: "slider.vertical.3")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(isFlat ? AnyShapeStyle(.secondary) : AnyShapeStyle(toneColor))
            }

            Spacer(minLength: 4)

            if let focusedBand = activeBand ?? hoveredBand, gains.indices.contains(focusedBand) {
                Text(bandBadgeText(band: focusedBand, gain: gains[focusedBand]))
                    .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(toneColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule(style: .continuous).fill(toneColor.opacity(0.14)))
            }

            presetMenu
        }
    }

    private var presetMenu: some View {
        Menu {
            ForEach(MixerEQPreset.builtInPresets) { preset in
                Button {
                    VorssaintHaptics.generic()
                    mixer.applyEQPreset(preset, for: appKey)
                } label: {
                    HStack {
                        Text(preset.name)
                        if activePresetID == preset.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            if !presetStore.customPresets.isEmpty {
                Divider()
                ForEach(presetStore.customPresets) { preset in
                    Button {
                        VorssaintHaptics.generic()
                        mixer.applyEQPreset(preset, for: appKey)
                    } label: {
                        HStack {
                            Text(preset.name)
                            if activePresetID == preset.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(activePreset?.name ?? (isFlat ? "Flat" : (isRussian ? "Свой" : "Custom")))
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .frame(maxWidth: 128, alignment: .trailing)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var splineCanvas: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let plotRect = Self.plotRect(for: size)
            let points = Self.nodePoints(for: gains, in: plotRect)
            ZStack {
                Canvas { context, _ in
                    drawGrid(in: &context, rect: plotRect)
                    drawSpline(in: &context, points: points, rect: plotRect)
                }

                ForEach(0..<MixerParametricEQ.bandCount, id: \.self) { band in
                    let point = points[band]
                    let isFocused = activeBand == band || hoveredBand == band
                    let isZero = abs(gains[band]) < 0.05
                    ZStack {
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 22, height: 22)
                        Circle()
                            .fill(isZero ? Color.secondary.opacity(0.65) : toneColor)
                            .frame(width: isFocused ? 11 : 8, height: isFocused ? 11 : 8)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.85 : 0.95),
                                                  lineWidth: isFocused ? 1.5 : 1.0)
                            )
                            .shadow(color: (isZero ? Color.black : toneColor).opacity(isFocused ? 0.35 : 0.16),
                                    radius: isFocused ? 3 : 1.5)
                    }
                    .contentShape(Rectangle())
                    .position(point)
                    .onHover { inside in
                        if inside {
                            hoveredBand = band
                        } else if hoveredBand == band {
                            hoveredBand = nil
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                activeBand = band
                                updateBand(band, atY: gesture.location.y, in: plotRect)
                            }
                            .onEnded { _ in
                                activeBand = nil
                            }
                    )
                    .onTapGesture(count: 2) {
                        resetBand(band)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.045 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: activeBand)
        }
        .frame(height: curveHeight)
    }

    private var frequencyAxisLabels: some View {
        HStack(spacing: 0) {
            ForEach(0..<Self.bandLabels.count, id: \.self) { index in
                Text(Self.bandLabels[index])
                    .font(.system(size: 8.5, weight: .medium).monospacedDigit())
                    .foregroundStyle((activeBand == index || hoveredBand == index) ? toneColor : .secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
    }

    private var toolbarRow: some View {
        HStack(spacing: 6) {
            VorssaintActionChip(title: isRussian ? "Сброс 0 дБ" : "Reset 0 dB",
                                symbol: "arrow.counterclockwise",
                                tone: .sound) {
                mixer.resetEQ(for: appKey)
            }
            .disabled(isFlat)

            VorssaintActionChip(title: isRussian ? "Сохранить" : "Save Preset",
                                symbol: "plus",
                                tone: .sound) {
                isRenamingPreset = false
                presetNameDraft = ""
                withAnimation(DesignMotion.resolve(DesignMotion.snappy, reduceMotion: reduceMotion)) {
                    isSavingPreset.toggle()
                }
            }

            if isCustomPresetActive, let current = activePreset {
                Button {
                    isSavingPreset = false
                    presetNameDraft = current.name
                    withAnimation(DesignMotion.resolve(DesignMotion.snappy, reduceMotion: reduceMotion)) {
                        isRenamingPreset.toggle()
                    }
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: DesignRadius.pill, style: .continuous)
                                .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
                        )
                }
                .buttonStyle(VorssaintScalePressButtonStyle())
                .help(isRussian ? "Переименовать пресет" : "Rename Preset")

                Button {
                    VorssaintHaptics.generic()
                    presetStore.deletePreset(id: current.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(PanelMetricColor.red(for: colorScheme))
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: DesignRadius.pill, style: .continuous)
                                .fill(PanelMetricColor.red(for: colorScheme).opacity(0.10))
                        )
                }
                .buttonStyle(VorssaintScalePressButtonStyle())
                .help(isRussian ? "Удалить пресет" : "Delete Preset")
            }

            Spacer(minLength: 0)
        }
    }

    private var inlinePresetEditorRow: some View {
        HStack(spacing: 6) {
            TextField(isRenamingPreset
                      ? (isRussian ? "Новое имя..." : "New name...")
                      : (isRussian ? "Название пресета..." : "Preset name..."),
                      text: $presetNameDraft)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .font(.system(size: 11))
                .onSubmit { commitInlinePresetEdit() }

            Button {
                commitInlinePresetEdit()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(toneColor))
            }
            .buttonStyle(VorssaintScalePressButtonStyle())
            .disabled(presetNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                withAnimation(DesignMotion.resolve(DesignMotion.snappy, reduceMotion: reduceMotion)) {
                    isSavingPreset = false
                    isRenamingPreset = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
        }
    }

    private func commitInlinePresetEdit() {
        let trimmed = presetNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        VorssaintHaptics.generic()
        if isRenamingPreset, let current = activePreset, presetStore.isCustomPreset(id: current.id) {
            presetStore.renamePreset(id: current.id, to: trimmed)
        } else {
            let preamp = mixer.eqPreampDB(for: appKey)
            let saved = presetStore.savePreset(name: trimmed, gainsDB: gains, preampDB: preamp)
            mixer.applyEQPreset(saved, for: appKey)
        }
        withAnimation(DesignMotion.resolve(DesignMotion.snappy, reduceMotion: reduceMotion)) {
            isSavingPreset = false
            isRenamingPreset = false
            presetNameDraft = ""
        }
    }

    private func updateBand(_ band: Int, atY locationY: CGFloat, in plotRect: CGRect) {
        var nextGains = gains
        guard nextGains.indices.contains(band) else { return }
        let normalizedY = min(max((locationY - plotRect.minY) / max(1, plotRect.height), 0), 1)
        let rawDB = Self.maxDB - Double(normalizedY) * (Self.maxDB - Self.minDB)
        let snappedDB = VorssaintDesignKitMath.snappedDetentValue(
            rawValue: rawDB,
            range: Self.minDB...Self.maxDB,
            detent: 0,
            snapWindowFraction: 0.04
        )
        let quantized = (snappedDB * 2).rounded() / 2
        if VorssaintDesignKitMath.didCrossDetent(previous: Double(nextGains[band]),
                                                 next: quantized,
                                                 detent: 0) {
            VorssaintHaptics.alignment()
        }
        nextGains[band] = Float(quantized)
        if let appKey {
            mixer.setEQGains(nextGains, for: appKey)
        } else {
            mixer.setMasterEQGains(nextGains)
        }
    }

    private func resetBand(_ band: Int) {
        var nextGains = gains
        guard nextGains.indices.contains(band) else { return }
        VorssaintHaptics.alignment()
        nextGains[band] = 0
        if let appKey {
            mixer.setEQGains(nextGains, for: appKey)
        } else {
            mixer.setMasterEQGains(nextGains)
        }
    }

    private func bandBadgeText(band: Int, gain: Float) -> String {
        let freq = Self.bandLabels[band]
        let sign = gain > 0.04 ? "+" : ""
        let formatted = String(format: "%.1f", locale: l10n.language.formattingLocale(), Double(gain))
        return "\(freq)Hz \(sign)\(formatted) dB"
    }

    private func drawGrid(in context: inout GraphicsContext, rect: CGRect) {
        let zeroY = Self.yPosition(forGain: 0, in: rect)
        let guideLevels: [Float] = [12, 6, 0, -6, -12]
        for level in guideLevels {
            let y = Self.yPosition(forGain: level, in: rect)
            var line = Path()
            line.move(to: CGPoint(x: rect.minX - 4, y: y))
            line.addLine(to: CGPoint(x: rect.maxX + 4, y: y))
            let isZero = level == 0
            context.stroke(
                line,
                with: .color(Color.primary.opacity(isZero ? 0.24 : 0.08)),
                style: StrokeStyle(lineWidth: isZero ? 1.0 : 0.5, dash: isZero ? [] : [2, 3])
            )
        }
        for band in 0..<MixerParametricEQ.bandCount {
            let x = Self.xPosition(forBand: band, in: rect)
            var vLine = Path()
            vLine.move(to: CGPoint(x: x, y: rect.minY))
            vLine.addLine(to: CGPoint(x: x, y: rect.maxY))
            context.stroke(
                vLine,
                with: .color(Color.primary.opacity(band == activeBand || band == hoveredBand ? 0.16 : 0.05)),
                lineWidth: 0.5
            )
        }
        _ = zeroY
    }

    private func drawSpline(in context: inout GraphicsContext, points: [CGPoint], rect: CGRect) {
        guard points.count >= 2 else { return }
        let splinePath = Self.catmullRomSpline(through: points, clampedTo: rect)

        var fillPath = splinePath
        fillPath.addLine(to: CGPoint(x: points.last!.x, y: rect.maxY + 4))
        fillPath.addLine(to: CGPoint(x: points.first!.x, y: rect.maxY + 4))
        fillPath.closeSubpath()

        context.fill(
            fillPath,
            with: .linearGradient(
                Gradient(colors: [
                    toneColor.opacity(colorScheme == .dark ? 0.34 : 0.24),
                    toneColor.opacity(0.02)
                ]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY),
                endPoint: CGPoint(x: rect.midX, y: rect.maxY + 4)
            )
        )

        context.stroke(
            splinePath,
            with: .color(toneColor),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )
    }

    private static func normalizedDisplayGains(_ raw: [Float]) -> [Float] {
        var result = Array(raw.prefix(MixerParametricEQ.bandCount)).map {
            $0.isFinite ? min(max($0, Float(minDB)), Float(maxDB)) : Float(0)
        }
        while result.count < MixerParametricEQ.bandCount {
            result.append(0)
        }
        return result
    }

    private static func plotRect(for size: CGSize) -> CGRect {
        let padX: CGFloat = 12
        let padY: CGFloat = 10
        return CGRect(x: padX,
                      y: padY,
                      width: max(10, size.width - padX * 2),
                      height: max(10, size.height - padY * 2))
    }

    private static func xPosition(forBand band: Int, in rect: CGRect) -> CGFloat {
        let fraction = CGFloat(band) / CGFloat(max(1, MixerParametricEQ.bandCount - 1))
        return rect.minX + fraction * rect.width
    }

    private static func yPosition(forGain gain: Float, in rect: CGRect) -> CGFloat {
        let clamped = min(max(Double(gain), minDB), maxDB)
        let fraction = 1.0 - (clamped - minDB) / (maxDB - minDB)
        return rect.minY + CGFloat(fraction) * rect.height
    }

    private static func nodePoints(for gains: [Float], in rect: CGRect) -> [CGPoint] {
        (0..<MixerParametricEQ.bandCount).map { band in
            let gain = band < gains.count ? gains[band] : 0
            return CGPoint(x: xPosition(forBand: band, in: rect),
                           y: yPosition(forGain: gain, in: rect))
        }
    }

    private static func catmullRomSpline(through points: [CGPoint], clampedTo rect: CGRect) -> Path {
        var path = Path()
        guard points.count >= 2 else { return path }
        path.move(to: points[0])

        let tension: CGFloat = 1.0 / 6.0
        func clampY(_ y: CGFloat) -> CGFloat {
            min(max(y, rect.minY - 2), rect.maxY + 2)
        }

        for index in 0..<(points.count - 1) {
            let p0 = index > 0
                ? points[index - 1]
                : CGPoint(x: points[0].x - (points[1].x - points[0].x), y: points[0].y)
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = index + 2 < points.count
                ? points[index + 2]
                : CGPoint(x: points[points.count - 1].x + (points[points.count - 1].x - points[points.count - 2].x),
                          y: points[points.count - 1].y)

            let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) * tension,
                              y: clampY(p1.y + (p2.y - p0.y) * tension))
            let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) * tension,
                              y: clampY(p2.y - (p3.y - p1.y) * tension))
            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }
        return path
    }
}
