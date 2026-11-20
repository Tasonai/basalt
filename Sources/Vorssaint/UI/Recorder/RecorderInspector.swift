// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The panel down the side of the editor: three looks to start from, then the
/// handful of things worth changing. Everything here changes the picture the
/// preview is already showing, so nothing has to be imagined.
struct RecorderInspector: View {
    @ObservedObject var model: RecorderEditorModel
    @ObservedObject private var l10n = L10n.shared
    @State private var showsBackdropPopover = false
    @State private var tab: Tab = .look
    @State private var hoveredLook: RecorderEditDocument.Look?
    /// Typing is one edit, landed when the field is let go. Without this the
    /// caption would only reach the preview on a Return, and this field takes
    /// several lines, so Return is a new line and not a commit.
    @FocusState private var textFieldFocused: Bool

    private var strings: RecorderFeatureStrings {
        FeatureStrings.recorder(l10n.language)
    }

    private var screenshotStrings: ScreenshotFeatureStrings {
        FeatureStrings.screenshot(l10n.language)
    }

    private var wave2: OverhaulWave2Strings {
        OverhaulStrings.wave2(l10n.language)
    }

    private var v2: OverhaulV2Strings {
        OverhaulV2Strings.localized(l10n.language)
    }

    private enum Tab: String, CaseIterable {
        case look, pointer, zoom, studio
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Selecting a zoom swaps the whole panel to that zoom. The
                // swap is what teaches the selection model, without a word.
                if let text = model.selectedText {
                    selectedTextSection(text)
                } else if let image = model.selectedImage {
                    selectedImageSection(image)
                } else if model.selectedBlur != nil {
                    selectedBlurSection
                } else if let selected = model.selectedZoom {
                    selectedZoomSection(selected)
                } else {
                    tabPicker
                    switch tab {
                    case .look:
                        lookSection
                        Divider().opacity(0.35)
                        backgroundSection
                    case .pointer:
                        if model.hasPointerTrack {
                            pointerSection
                        } else {
                            Text(strings.noPointerNote)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    case .zoom:
                        zoomSection
                    case .studio:
                        studioSection
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .scrollIndicators(.never)
        .frame(width: 272)
        .background(.ultraThinMaterial)
    }

    private var tabPicker: some View {
        VorssaintSegmentedTabs(
            selection: $tab,
            options: [
                .init(.look, title: strings.lookLabel),
                .init(.pointer, title: strings.pointerSectionLabel),
                .init(.zoom, title: strings.zoomSectionLabel),
                .init(.studio, title: wave2.studioTabTitle),
            ],
            tone: .tools
        )
    }

    // MARK: - Look

    private var lookSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(strings.lookLabel)
            HStack(spacing: 7) {
                lookCard(.raw, title: strings.lookRaw, icon: "rectangle")
                lookCard(.clean, title: strings.lookClean,
                         icon: "cursorarrow.motionlines")
                lookCard(.studio, title: strings.lookStudio, icon: "sparkles")
            }
        }
    }

    private func lookCard(_ look: RecorderEditDocument.Look,
                          title: String,
                          icon: String) -> some View {
        let selected = model.document.matches(look)
        let hovered = hoveredLook == look
        return Button {
            withAnimation(.easeOut(duration: 0.16)) {
                model.applyLook(look)
            }
        } label: {
            VStack(spacing: 6) {
                lookPreview(look, icon: icon)
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 5)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.1)
                                   : Color.white.opacity(hovered ? 0.07 : 0.035))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.72)
                                           : Color.white.opacity(hovered ? 0.14 : 0.07),
                                  lineWidth: selected ? 1.25 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.28))
                    .padding(6)
            }
        }
        .buttonStyle(.plain)
        .onHover { isInside in hoveredLook = isInside ? look : nil }
    }

    private func lookPreview(_ look: RecorderEditDocument.Look, icon: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(look == .studio
                      ? AnyShapeStyle(LinearGradient(colors: [Color.indigo.opacity(0.9),
                                                               Color.purple.opacity(0.55)],
                                                     startPoint: .topLeading,
                                                     endPoint: .bottomTrailing))
                      : AnyShapeStyle(Color.black.opacity(look == .raw ? 0.82 : 0.62)))
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(white: look == .raw ? 0.55 : 0.78).opacity(0.82))
                .frame(width: 31, height: 20)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                }
                .shadow(color: .black.opacity(0.24), radius: 3, y: 2)
        }
        .frame(width: 48, height: 36)
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
    }

    // MARK: - Background

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(strings.backgroundSectionLabel)
            Button {
                showsBackdropPopover = true
            } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(LinearGradient(
                            colors: BackdropPickerAssets.previewColors(for: model.backdropStyle),
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 26, height: 20)
                        .overlay {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                        }
                    Text(model.showsBackdrop
                         ? strings.backgroundSectionLabel
                         : FeatureStrings.screenshot(l10n.language).backdropNone)
                        .font(.system(size: 12))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .popover(isPresented: $showsBackdropPopover, arrowEdge: .trailing) {
                ScreenshotBackdropPopover(model: model, showsAdjustments: false)
            }

            Picker(strings.shapeLabel, selection: aspectBinding) {
                Text(strings.shapeOriginal).tag(RecorderSupport.Aspect.original.rawValue)
                Text(strings.shapeWide).tag(RecorderSupport.Aspect.wide.rawValue)
                Text(strings.shapeSquare).tag(RecorderSupport.Aspect.square.rawValue)
                Text(strings.shapeVertical).tag(RecorderSupport.Aspect.vertical.rawValue)
            }
            .pickerStyle(.menu)

            if model.showsBackdrop {
                VStack(spacing: 7) {
                    backgroundSlider(title: screenshotStrings.backdropPaddingLabel,
                                     value: model.backdropStyle.padding,
                                     onChange: { updateBackdrop(\.padding, to: $0) },
                                     onReset: { updateBackdrop(\.padding, to: 0.5) })
                    backgroundSlider(title: screenshotStrings.backdropCornersLabel,
                                     value: model.backdropStyle.cornerRadius,
                                     onChange: { updateBackdrop(\.cornerRadius, to: $0) },
                                     onReset: { updateBackdrop(\.cornerRadius, to: 0) })
                    backgroundSlider(title: screenshotStrings.backdropBlurLabel,
                                     value: model.backdropStyle.blur,
                                     onChange: { updateBackdrop(\.blur, to: $0) },
                                     onReset: { updateBackdrop(\.blur, to: 0) })
                }
                .padding(9)
                .background(Color.white.opacity(0.04),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func updateBackdrop(
        _ keyPath: WritableKeyPath<ScreenshotSupport.BackdropStyle, Double>,
        to value: Double
    ) {
        var style = model.backdropStyle
        style[keyPath: keyPath] = value
        model.backdropStyle = style
    }

    private func backgroundSlider(title: String,
                                  value: Double,
                                  onChange: @escaping (Double) -> Void,
                                  onReset: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(Color(white: 0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(width: 64, alignment: .leading)
            VorssaintDetentSlider(
                value: Binding(get: { value }, set: onChange),
                in: 0...1,
                tone: .tools
            )
            .onTapGesture(count: 2) { onReset() }
            Text(String(format: "%.0f%%", locale: MetricFormat.locale, value * 100))
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color(white: 0.86))
                .frame(width: 34, alignment: .trailing)
        }
    }

    // MARK: - One zoom

    /// Exactly four rows, and four is the ceiling. A zoom has more knobs than
    /// this in theory; showing them turns a timeline into a control panel.
    private func selectedZoomSection(_ segment: RecorderTimeline.ZoomSegment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // The way back has to be a labelled thing, not a bare glyph:
            // otherwise selecting a zoom feels like a door that locks.
            Button {
                model.selectZoom(nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                    Text(strings.backToOptions)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)
            .keyboardShortcut(.escape, modifiers: [])
            sectionTitle(strings.thisZoomLabel)
            valueSlider(title: strings.zoomAmountLabel,
                        value: segment.amount,
                        range: RecorderSupport.zoomAmountRange,
                        format: "%.1f×",
                        onChange: { model.setSelectedZoomAmount($0) },
                        onCommit: { model.commitZoomEdit() },
                        onReset: {
                            model.setSelectedZoomAmount(1.8)
                            model.commitZoomEdit()
                        })
            VStack(alignment: .leading, spacing: 5) {
                Text(strings.zoomWhereLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.72))
                VorssaintSegmentedTabs(
                    selection: Binding(
                        get: { segment.followsPointer },
                        set: { follows in
                            if follows {
                                model.setSelectedZoomFocus(nil)
                            } else {
                                model.beginAiming()
                            }
                        }
                    ),
                    options: [
                        .init(true, title: strings.zoomFollowsPointer),
                        .init(false, title: strings.zoomPickSpot),
                    ],
                    tone: .tools
                )
                if !segment.followsPointer {
                    Button(strings.zoomPickSpotHint) { model.beginAiming() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.accentColor)
                }
            }
            Button(strings.removeZoom) { model.removeSelectedZoom() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - One text

    private func selectedTextSection(_ overlay: RecorderTextOverlay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                model.selectLaneItem(.text, id: nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                    Text(strings.backToOptions)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)
            .keyboardShortcut(.escape, modifiers: [])
            sectionTitle(strings.thisTextLabel)

            TextField(strings.textPlaceholder, text: Binding(
                get: { overlay.text },
                set: { value in model.updateSelectedText { $0.text = value } }),
                      axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .focused($textFieldFocused)
                .onSubmit { model.commitZoomEdit() }
                .onChange(of: textFieldFocused) { _, focused in
                    if !focused { model.commitZoomEdit() }
                }
                .onDisappear { model.commitZoomEdit() }

            valueSlider(title: strings.textSizeLabel,
                        value: overlay.size,
                        range: RecorderTextOverlay.sizeRange,
                        format: "%.0f%%",
                        scale: 100,
                        onChange: { value in model.updateSelectedText { $0.size = value } },
                        onCommit: { model.commitZoomEdit() },
                        onReset: {
                            model.updateSelectedText { $0.size = 0.06 }
                            model.commitZoomEdit()
                        })

            VStack(alignment: .leading, spacing: 5) {
                Text(strings.textPositionLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.72))
                anchorGrid(selected: overlay.anchor) { anchor in
                    model.updateSelectedText { $0.anchor = anchor }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(strings.textColorLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.72))
                HStack(spacing: 6) {
                    ForEach(Array(RecorderTextOverlay.Palette.allCases.enumerated()), id: \.element.rawValue) { index, palette in
                        let parts = palette.components
                        let isSelected = overlay.palette == palette
                        Button {
                            model.updateSelectedText { $0.palette = palette }
                            model.commitZoomEdit()
                        } label: {
                            Circle()
                                .fill(Color(.sRGB, red: parts.red, green: parts.green,
                                            blue: parts.blue, opacity: 1))
                                .frame(width: 20, height: 20)
                                .overlay {
                                    Circle().strokeBorder(
                                        isSelected
                                            ? Color.accentColor : Color.white.opacity(0.18),
                                        lineWidth: isSelected ? 2.5 : 1)
                                }
                                .frame(minWidth: 22, minHeight: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(strings.textColorLabel) \(index + 1)")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }

            Button(strings.removeText) { model.removeSelectedText() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - One picture

    /// The picture itself was chosen when the block was made, so what is left
    /// here is how big it is, how solid it is and where it sits.
    private func selectedImageSection(_ overlay: RecorderImageOverlay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                model.selectLaneItem(.image, id: nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                    Text(strings.backToOptions)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)
            .keyboardShortcut(.escape, modifiers: [])
            sectionTitle(strings.thisImageLabel)

            Text(URL(fileURLWithPath: overlay.path).lastPathComponent)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            valueSlider(title: strings.imageSizeLabel,
                        value: overlay.size,
                        range: RecorderImageOverlay.sizeRange,
                        format: "%.0f%%",
                        scale: 100,
                        onChange: { value in model.updateSelectedImage { $0.size = value } },
                        onCommit: { model.commitZoomEdit() },
                        onReset: {
                            model.updateSelectedImage { $0.size = RecorderImageOverlay.defaultSize }
                            model.commitZoomEdit()
                        })

            valueSlider(title: strings.imageOpacityLabel,
                        value: overlay.opacity,
                        range: RecorderImageOverlay.opacityRange,
                        format: "%.0f%%",
                        scale: 100,
                        onChange: { value in model.updateSelectedImage { $0.opacity = value } },
                        onCommit: { model.commitZoomEdit() },
                        onReset: {
                            model.updateSelectedImage { $0.opacity = 1 }
                            model.commitZoomEdit()
                        })

            VStack(alignment: .leading, spacing: 5) {
                Text(strings.imagePositionLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.72))
                anchorGrid(selected: overlay.anchor) { anchor in
                    model.updateSelectedImage { $0.anchor = anchor }
                }
            }

            Button(strings.removeText) { model.removeSelectedImage() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - One blur

    /// The area is the whole thing, and it is drawn on the picture rather than
    /// typed here: a blur that misses by a few pixels is not a blur.
    private var selectedBlurSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                model.selectLaneItem(.blur, id: nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                    Text(strings.backToOptions)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)
            .keyboardShortcut(.escape, modifiers: [])
            sectionTitle(strings.thisBlurLabel)

            Button {
                model.beginPickingBlurArea()
            } label: {
                Label(strings.blurPickArea, systemImage: "aqi.medium")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(model.isPickingBlurArea)
            Text(model.isPickingBlurArea ? strings.blurPickAreaHint : strings.blurCaption)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let blur = model.selectedBlur {
                let levels = ScreenshotSupport.BlurStrength.levels
                valueSlider(title: screenshotStrings.blurStrengthLabel,
                            value: Double(blur.strength),
                            range: Double(levels.lowerBound)...Double(levels.upperBound),
                            format: "%.0f",
                            step: 1,
                            onChange: { model.setSelectedBlurStrength(Int($0.rounded())) },
                            onCommit: { model.commitZoomEdit() },
                            onReset: {
                                model.setSelectedBlurStrength(ScreenshotSupport.BlurStrength.defaultLevel)
                                model.commitZoomEdit()
                            })
            }

            Button(strings.removeZoom) { model.removeSelectedBlur() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        }
    }

    private func anchorLabel(_ anchor: RecorderTextOverlay.Anchor) -> String {
        let layout = FeatureStrings.windowLayout(l10n.language)
        switch anchor {
        case .topLeading: return layout.topLeft
        case .top: return layout.topHalf
        case .topTrailing: return layout.topRight
        case .leading: return layout.leftHalf
        case .center: return layout.center
        case .trailing: return layout.rightHalf
        case .bottomLeading: return layout.bottomLeft
        case .bottom: return layout.bottomHalf
        case .bottomTrailing: return layout.bottomRight
        }
    }

    /// Nine places instead of a drag: it reads at a glance, needs no gesture
    /// on the picture, and covers what people actually do with a caption or a
    /// mark of their own.
    private func anchorGrid(selected: RecorderTextOverlay.Anchor,
                            onSelect: @escaping (RecorderTextOverlay.Anchor) -> Void)
        -> some View {
        let rows: [[RecorderTextOverlay.Anchor]] = [
            [.topLeading, .top, .topTrailing],
            [.leading, .center, .trailing],
            [.bottomLeading, .bottom, .bottomTrailing],
        ]
        return VStack(spacing: 4) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(rows[row], id: \.rawValue) { anchor in
                        let isSelected = selected == anchor
                        Button {
                            onSelect(anchor)
                            model.commitZoomEdit()
                        } label: {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(isSelected
                                      ? Color.accentColor.opacity(0.85)
                                      : Color.white.opacity(0.08))
                                .frame(minWidth: 22, minHeight: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(anchorLabel(anchor))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
        }
    }

    /// A slider that says what it is set to and goes back to its default on a
    /// double click. A bare track with no number is the difference between a
    /// control and a guess.
    private func valueSlider(title: String,
                             value: Double,
                             range: ClosedRange<Double>,
                             format: String,
                             scale: Double = 1,
                             step: Double? = nil,
                             onChange: @escaping (Double) -> Void,
                             onCommit: @escaping () -> Void = {},
                             onReset: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.72))
                Spacer()
                Text(String(format: format, locale: .autoupdatingCurrent, value * scale))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color(white: 0.86))
            }
            VorssaintDetentSlider(
                value: Binding(get: { value }, set: onChange),
                in: range,
                step: step,
                tone: .tools,
                onEditingChanged: { editing in if !editing { onCommit() } }
            )
            .onTapGesture(count: 2) { onReset() }
        }
    }

    // MARK: - Pointer

    private var pointerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(strings.pointerSectionLabel)
            Toggle(strings.pointerShowToggle, isOn: boolBinding(\.showsPointer))
                .toggleStyle(VorssaintCompactSwitchStyle())
                .controlSize(.mini)
            if model.document.showsPointer {
                Picker(strings.pointerSmoothingLabel, selection: smoothingBinding) {
                    Text(strings.pointerSmoothingOff)
                        .tag(RecorderMotion.Smoothing.off.rawValue)
                    Text(strings.pointerSmoothingLight)
                        .tag(RecorderMotion.Smoothing.light.rawValue)
                    Text(strings.pointerSmoothingSmooth)
                        .tag(RecorderMotion.Smoothing.smooth.rawValue)
                    Text(strings.pointerSmoothingCinematic)
                        .tag(RecorderMotion.Smoothing.cinematic.rawValue)
                }
                .pickerStyle(.menu)
                valueSlider(title: strings.pointerSizeLabel,
                            value: model.document.pointerSize,
                            range: RecorderSupport.pointerSizeRange,
                            format: "%.2f×",
                            onChange: { doubleBinding(\.pointerSize).wrappedValue = $0 },
                            onReset: { doubleBinding(\.pointerSize).wrappedValue = 1 })
                Toggle(strings.clickRingToggle, isOn: boolBinding(\.showsClickRing))
                    .toggleStyle(VorssaintCompactSwitchStyle())
                    .controlSize(.mini)
            }
        }
    }

    // MARK: - Zoom

    private var zoomSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(strings.zoomSectionLabel)
            if model.hasPointerTrack {
                Toggle(strings.zoomToggle, isOn: Binding(
                    get: { model.document.zoomEnabled },
                    set: model.setAutomaticZoomEnabled))
                    .toggleStyle(VorssaintCompactSwitchStyle())
                    .controlSize(.mini)
            }
            if model.document.zoomEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(strings.typingZoomToggle, isOn: Binding(
                        get: { model.document.zoomsOnTyping },
                        set: model.setTypingZoomEnabled))
                        .toggleStyle(VorssaintCompactSwitchStyle())
                        .controlSize(.mini)
                    Text(strings.typingZoomCaption)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.document.zoomSegments.isEmpty {
                    zoomEmptyState
                } else {
                    VStack(alignment: .leading, spacing: 9) {
                        valueSlider(title: strings.zoomAmountLabel,
                                    value: model.document.zoomAmount,
                                    range: RecorderSupport.zoomAmountRange,
                                    format: "%.1f×",
                                    onChange: { doubleBinding(\.zoomAmount).wrappedValue = $0 },
                                    onReset: { doubleBinding(\.zoomAmount).wrappedValue = 1.8 })
                        if model.hasPointerTrack {
                            Button(strings.regenerateZooms) { model.regenerateZooms() }
                                .buttonStyle(.borderless)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(11)
                    .background(Color.white.opacity(0.035),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
            }
        }
    }

    private var zoomEmptyState: some View {
        VStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            VStack(spacing: 3) {
                Text(strings.zoomEmptyTitle)
                    .font(.system(size: 12, weight: .semibold))
                Text(strings.zoomEmptyCaption)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(model.canCreateAutomaticZooms
                   ? strings.createAutomaticZooms : strings.addZoomButton) {
                if model.canCreateAutomaticZooms {
                    model.regenerateZooms()
                } else {
                    model.addZoom(at: model.sourceTime)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        }
    }

    // MARK: - Pieces

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(white: 0.62))
            .textCase(.uppercase)
            .kerning(0.4)
    }

    private func boolBinding(_ path: WritableKeyPath<RecorderEditDocument, Bool>) -> Binding<Bool> {
        Binding(get: { model.document[keyPath: path] },
                set: { newValue in
                    var next = model.document
                    next[keyPath: path] = newValue
                    model.document = next
                })
    }

    private func doubleBinding(
        _ path: WritableKeyPath<RecorderEditDocument, Double>
    ) -> Binding<Double> {
        Binding(get: { model.document[keyPath: path] },
                set: { newValue in
                    var next = model.document
                    next[keyPath: path] = newValue
                    model.document = next
                })
    }

    private var smoothingBinding: Binding<String> {
        Binding(get: { model.document.pointerSmoothing },
                set: { newValue in
                    var next = model.document
                    next.pointerSmoothing = newValue
                    model.document = next
                })
    }

    private var aspectBinding: Binding<String> {
        Binding(get: { model.document.resolvedAspect.rawValue },
                set: { newValue in
                    var next = model.document
                    next.aspect = newValue
                    next.outputAspect = StudioOutputAspect(legacyAspect: RecorderSupport.sanitizedAspect(newValue))
                    model.document = next
                })
    }

    // MARK: - Studio

    private var studioSection: some View {
        VStack(alignment: .leading, spacing: DesignSpace.sm) {
            sectionTitle(wave2.studioTabTitle)

            HStack(spacing: DesignSpace.xs) {
                Text(OverhaulV3Strings.recorderAspectTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: DesignSpace.xs)
                Menu {
                    ForEach(StudioOutputAspect.allCases) { option in
                        Button {
                            VorssaintHaptics.generic()
                            var next = model.document
                            next.outputAspect = option
                            next.aspect = option.legacyAspect.rawValue
                            model.document = next
                        } label: {
                            Label(aspectOptionLabel(option), systemImage: aspectSymbol(option))
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(aspectOptionLabel(model.document.resolvedOutputAspect))
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8.5, weight: .semibold))
                    }
                    .padding(.horizontal, DesignSpace.xs)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            compactSwitchRow(title: wave2.motionBlurTitle, isOn: boolBinding(\.motionBlurEnabled))
            if model.document.motionBlurEnabled {
                backgroundSlider(
                    title: wave2.motionBlurTitle,
                    value: model.document.motionBlurStrength,
                    onChange: { value in
                        var next = model.document
                        next.motionBlurStrength = value
                        model.document = next
                    },
                    onReset: {
                        var next = model.document
                        next.motionBlurStrength = 0.5
                        model.document = next
                    }
                )
            }

            compactSwitchRow(
                title: OverhaulV3Strings.recorderTilt3DToggle,
                isOn: Binding(
                    get: { model.document.perspectiveTilt3DEnabled || model.document.perspectiveTiltEnabled },
                    set: { enabled in
                        var next = model.document
                        next.perspectiveTilt3DEnabled = enabled
                        next.perspectiveTiltEnabled = enabled
                        model.document = next
                    }
                )
            )

            compactSwitchRow(title: v2.recorderGlowLabel, isOn: boolBinding(\.ambientGlowEnabled))
            compactSwitchRow(title: v2.recorderProResAlphaLabel, isOn: boolBinding(\.exportsProRes4444))
            compactSwitchRow(title: OverhaulV3Strings.recorderMicDuckingToggle,
                             isOn: boolBinding(\.micAutoDuckingEnabled))

            let actionCopy = OverhaulV3ActionCopy.localized(l10n.language)
            Picker(wave2.clickSFXTitle, selection: Binding(
                get: { model.document.clickSFXStyle },
                set: { newValue in
                    VorssaintHaptics.generic()
                    var next = model.document
                    next.clickSFXStyle = newValue
                    model.document = next
                }
            )) {
                Text(actionCopy.clickSFXOff).tag(RecorderClickSFXStyle.off.rawValue)
                Text(actionCopy.clickSFXSoft).tag(RecorderClickSFXStyle.softTap.rawValue)
                Text(actionCopy.clickSFXMechanical).tag(RecorderClickSFXStyle.mechanical.rawValue)
                Text(actionCopy.clickSFXCrisp).tag(RecorderClickSFXStyle.crispPop.rawValue)
            }
            .pickerStyle(.menu)

            compactSwitchRow(title: wave2.keystrokeHUDTitle, isOn: boolBinding(\.keystrokesEnabled))

            Divider().opacity(0.35)
            sectionTitle(wave2.cameraBubbleTitle)
            compactSwitchRow(
                title: wave2.cameraBubbleTitle,
                isOn: Binding(
                    get: { model.document.cameraBubble.isEnabled },
                    set: { enabled in
                        UserDefaults.standard.set(enabled,
                                                  forKey: RecorderCameraCapture.defaultPreferenceKey)
                        var next = model.document
                        next.cameraBubble.isEnabled = enabled
                        model.document = next
                    }
                )
            )

            if model.document.cameraBubble.isEnabled {
                Text(v2.recorderCameraLiveNote)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: DesignSpace.xs) {
                    Text(OverhaulV3Strings.recorderCameraShapeTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: DesignSpace.xs)
                    Menu {
                        ForEach(CameraBubbleShape.allCases) { shape in
                            Button {
                                VorssaintHaptics.generic()
                                var next = model.document
                                next.cameraShape = shape
                                next.cameraBubble.shape = shape
                                model.document = next
                            } label: {
                                Label(cameraShapeLabel(shape), systemImage: cameraShapeSymbol(shape))
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: cameraShapeSymbol(model.document.cameraShape))
                                .font(.system(size: 10, weight: .semibold))
                            Text(cameraShapeLabel(model.document.cameraShape))
                                .font(.system(size: 11, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8.5, weight: .semibold))
                        }
                        .padding(.horizontal, DesignSpace.xs)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                compactSwitchRow(
                    title: OverhaulV3Strings.recorderPersonBlurToggle,
                    isOn: Binding(
                        get: { model.document.personSegmentationBlurEnabled },
                        set: { enabled in
                            var next = model.document
                            next.personSegmentationBlurEnabled = enabled
                            next.cameraBubble.personSegmentationBlurEnabled = enabled
                            model.document = next
                        }
                    )
                )

                compactSwitchRow(
                    title: wave2.cameraAutoShrinkLabel,
                    isOn: Binding(
                        get: { model.document.cameraBubble.autoShrinkOnPointerNear },
                        set: { shrink in
                            var next = model.document
                            next.cameraBubble.autoShrinkOnPointerNear = shrink
                            model.document = next
                        }
                    )
                )

                sceneKeyframesControls
            }

            Divider().opacity(0.35)
            sectionTitle(wave2.captionsTrackTitle)
            compactSwitchRow(title: wave2.captionsTrackTitle, isOn: boolBinding(\.captionsEnabled))
            HStack(spacing: DesignSpace.xs) {
                if model.isTranscribingCaptions {
                    ProgressView().controlSize(.small)
                } else {
                    VorssaintActionChip(title: wave2.transcribeAudioButton,
                                        symbol: "waveform",
                                        tone: .tools,
                                        prominent: true) {
                        Task { @MainActor in
                            await model.transcribeCaptions()
                        }
                    }
                }

                if !model.document.captions.isEmpty {
                    VorssaintActionChip(title: wave2.exportSRTButton,
                                        symbol: "square.and.arrow.up",
                                        tone: .tools) {
                        saveSRTPanel()
                    }
                }
            }

            if model.document.captions.isEmpty {
                Text(wave2.captionsEmptyHint)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.document.captions) { segment in
                        HStack(spacing: 6) {
                            Button {
                                model.toggleCaptionCut(segment.id)
                            } label: {
                                Image(systemName: segment.isCut ? "scissors.circle.fill" : "scissors")
                                    .foregroundStyle(segment.isCut ? Color.orange : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            Text(segment.text)
                                .font(.system(size: 10.5))
                                .strikethrough(segment.isCut)
                                .foregroundStyle(segment.isCut ? .secondary : .primary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 3)
                    }
                }
                .padding(DesignSpace.xs)
                .background(Color.white.opacity(0.035),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var sceneKeyframesControls: some View {
        VStack(alignment: .leading, spacing: DesignSpace.xs) {
            HStack(spacing: DesignSpace.xs) {
                VorssaintActionChip(title: "Keyframe",
                                    symbol: "plus",
                                    tone: .tools) {
                    model.addOrUpdateSceneKeyframe()
                }
                Spacer(minLength: 0)
                if let kfID = model.selectedSceneKeyframeID {
                    VorssaintActionChip(title: strings.removeZoom,
                                        symbol: "trash",
                                        tone: .tools,
                                        destructive: true) {
                        model.removeSceneKeyframe(kfID)
                    }
                }
            }

            if !model.document.sceneKeyframes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.document.sceneKeyframes) { keyframe in
                        let selected = model.selectedSceneKeyframeID == keyframe.id
                        HStack(spacing: 6) {
                            Button {
                                VorssaintHaptics.alignment()
                                model.selectSceneKeyframeAndSeek(keyframe.id)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: selected ? "diamond.fill" : "diamond")
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundStyle(selected ? Color.teal : Color.secondary)
                                    Text(String(format: "%.1fs", locale: .autoupdatingCurrent, keyframe.timeSeconds))
                                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                                    Text(cameraShapeLabel(keyframe.shape))
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Spacer(minLength: 4)
                            Button {
                                model.removeSceneKeyframe(keyframe.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(selected ? Color.teal.opacity(0.16) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
                .padding(6)
                .background(Color.white.opacity(0.035),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func compactSwitchRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: DesignSpace.xs) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: DesignSpace.xs)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(VorssaintCompactSwitchStyle(tone: .tools))
        }
    }

    private func cameraShapeLabel(_ shape: CameraBubbleShape) -> String {
        switch shape {
        case .circle: return "Circle"
        case .squircle: return "Squircle"
        case .verticalPortrait: return "9:16"
        case .hidden: return "Hidden"
        }
    }

    private func cameraShapeSymbol(_ shape: CameraBubbleShape) -> String {
        switch shape {
        case .circle: return "circle"
        case .squircle: return "square"
        case .verticalPortrait: return "rectangle.portrait"
        case .hidden: return "eye.slash"
        }
    }

    private func aspectOptionLabel(_ aspect: StudioOutputAspect) -> String {
        switch aspect {
        case .native: return strings.shapeOriginal
        case .vertical9x16: return "9:16"
        case .square1x1: return "1:1"
        case .cinema16x9: return "16:9"
        }
    }

    private func aspectSymbol(_ aspect: StudioOutputAspect) -> String {
        switch aspect {
        case .native: return "aspectratio"
        case .vertical9x16: return "rectangle.portrait"
        case .square1x1: return "square"
        case .cinema16x9: return "aspectratio"
        }
    }

    private func saveSRTPanel() {
        let srt = model.exportCaptionsSRT()
        guard !srt.isEmpty else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "captions.srt"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? srt.write(to: url, atomically: true, encoding: .utf8)
        }
    }

}

private extension OverhaulV3Strings {
    static var recorderCameraShapeTitle: String { localized(L10n.shared.language).recorderCameraShapeTitle }
    static var recorderPersonBlurToggle: String { localized(L10n.shared.language).recorderPersonBlurToggle }
    static var recorderTilt3DToggle: String { localized(L10n.shared.language).recorderTilt3DToggle }
    static var recorderAspectTitle: String { localized(L10n.shared.language).recorderAspectTitle }
    static var recorderMicDuckingToggle: String { localized(L10n.shared.language).recorderMicDuckingToggle }
}
