// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Pure math & detent snapping logic for VorssaintDesignKit, testable without AppKit UI.
enum VorssaintDesignKitMath {
    /// Applies a magnetic detent zone around `detent` so sliders click onto
    /// canonical reference points (such as 100% or 0 dB) cleanly.
    static func snappedDetentValue(rawValue: Double,
                                   range: ClosedRange<Double>,
                                   detent: Double?,
                                   snapWindowFraction: Double = 0.025) -> Double {
        let clamped = min(max(rawValue, range.lowerBound), range.upperBound)
        guard let detent, range.contains(detent) else { return clamped }
        let span = max(0.0001, range.upperBound - range.lowerBound)
        let threshold = span * snapWindowFraction
        return abs(clamped - detent) <= threshold ? detent : clamped
    }

    static func didCrossDetent(previous: Double, next: Double, detent: Double?, epsilon: Double = 0.0005) -> Bool {
        guard let detent else { return false }
        let wasAtDetent = abs(previous - detent) <= epsilon
        let isAtDetent = abs(next - detent) <= epsilon
        return (!wasAtDetent && isAtDetent) || ((previous - detent) * (next - detent) < 0)
    }
}

/// Main-thread safe haptic feedback helper matching Apple HIG multimodal touchstone.
enum VorssaintHaptics {
    static func alignment() {
        perform(.alignment)
    }

    static func levelChange() {
        perform(.levelChange)
    }

    static func generic() {
        perform(.generic)
    }

    private static func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        let send = {
            NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
        }
        if Thread.isMainThread {
            send()
        } else {
            DispatchQueue.main.async(execute: send)
        }
    }
}

/// Tactile micro-scale button style (`emil-design-eng`: scale 0.97 under 140ms).
struct VorssaintScalePressButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = DesignRadius.pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : (appearsActive ? 1.0 : 0.92))
            .animation(
                reduceMotion ? nil : .timingCurve(0.23, 1.0, 0.32, 1.0, duration: 0.14),
                value: configuration.isPressed
            )
    }
}

/// Tactile compact pill toggle replacement for raw `.toggleStyle(.checkbox)` in panels and popovers.
struct VorssaintPillToggleStyle: ToggleStyle {
    var tone: SemanticCategoryTone = .brand
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let tint = tone.color(scheme: colorScheme, highContrast: colorSchemeContrast == .increased)
        Button {
            VorssaintHaptics.generic()
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                configuration.label
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isEnabled ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule(style: .continuous)
                        .fill(configuration.isOn ? tint : Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.12))
                        .frame(width: 30, height: 17)
                    Circle()
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.22), radius: 1.5, x: 0, y: 0.5)
                        .frame(width: 13, height: 13)
                        .padding(2)
                }
                .opacity(appearsActive ? 1.0 : 0.85)
                .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.85), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1.0 : 0.45)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

/// Compact 30x17 trailing pill toggle for `SettingsRow` and table accessories without forcing `maxWidth: .infinity`.
struct VorssaintCompactSwitchStyle: ToggleStyle {
    var tone: SemanticCategoryTone = .brand
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let highContrast = colorSchemeContrast == .increased
        let tint = tone.color(scheme: colorScheme, highContrast: highContrast)
        let offTrack = Color.primary.opacity(colorScheme == .dark ? (highContrast ? 0.28 : 0.18) : (highContrast ? 0.24 : 0.13))
        Button {
            VorssaintHaptics.generic()
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(configuration.isOn ? tint : offTrack)
                    .frame(width: 30, height: 17)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.primary.opacity(highContrast ? 0.35 : 0.08), lineWidth: 0.5)
                    )
                Circle()
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.24), radius: 1.5, x: 0, y: 0.5)
                    .frame(width: 13, height: 13)
                    .padding(2)
            }
            .scaleEffect(isEnabled ? 1.0 : 0.98)
            .opacity(appearsActive ? 1.0 : 0.86)
            .animation(reduceMotion ? nil : DesignMotion.emilPress, value: configuration.isOn)
            .contentShape(Capsule())
        }
        .buttonStyle(VorssaintScalePressButtonStyle(cornerRadius: 9))
        .opacity(isEnabled ? 1.0 : 0.45)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) {
                configuration.label
            }
        }
    }
}

/// Tactile rounded-square checkbox replacement matching VorssaintDesignKit surfaces and focus semantics.
struct VorssaintCheckPillStyle: ToggleStyle {
    var tone: SemanticCategoryTone = .brand
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let highContrast = colorSchemeContrast == .increased
        let tint = tone.color(scheme: colorScheme, highContrast: highContrast)
        Button {
            VorssaintHaptics.generic()
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: DesignSpace.xs + 3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(configuration.isOn ? tint : Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06))
                        .frame(width: 16, height: 16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(configuration.isOn ? tint : Color.primary.opacity(highContrast ? 0.42 : 0.22),
                                              lineWidth: 1)
                        )
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.white)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? nil : DesignMotion.emilPress, value: configuration.isOn)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(VorssaintScalePressButtonStyle(cornerRadius: 6))
        .opacity(isEnabled ? (appearsActive ? 1.0 : 0.88) : 0.45)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) {
                configuration.label
            }
        }
    }
}

/// Sliding-capsule segmented tabs using `matchedGeometryEffect`, matching the Dynamic Island aesthetic.
struct VorssaintSegmentedTabs<SelectionValue: Hashable>: View {
    struct Option: Identifiable {
        let value: SelectionValue
        let title: String
        let symbol: String?
        var id: SelectionValue { value }

        init(_ value: SelectionValue, title: String, symbol: String? = nil) {
            self.value = value
            self.title = title
            self.symbol = symbol
        }
    }

    @Binding var selection: SelectionValue
    let options: [Option]
    var tone: SemanticCategoryTone = .brand

    @Namespace private var pillNamespace
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        let activeTint = tone.color(scheme: colorScheme, highContrast: colorSchemeContrast == .increased)
        HStack(spacing: 3) {
            ForEach(options) { option in
                let isSelected = option.value == selection
                Button {
                    guard selection != option.value else { return }
                    VorssaintHaptics.generic()
                    if reduceMotion {
                        selection = option.value
                    } else {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                            selection = option.value
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        if let symbol = option.symbol {
                            Image(systemName: symbol)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(option.title)
                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background {
                        if isSelected {
                            Capsule(style: .continuous)
                                .fill(appearsActive ? activeTint : Color.secondary.opacity(0.65))
                                .matchedGeometryEffect(id: "VorssaintSegmentedPill", in: pillNamespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.06))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
}

/// Precision full-track slider styled after `NotchLevelSlider`, with magnetic
/// detent snap (e.g. 100% or 0 dB) and trackpad haptic tick.
struct VorssaintDetentSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var step: Double? = nil
    var detent: Double? = nil
    var tone: SemanticCategoryTone = .brand
    var icon: String? = nil
    var title: String? = nil
    var formattedValue: String? = nil
    var onEditingChanged: ((Bool) -> Void)? = nil

    init(value: Binding<Double>,
         range: ClosedRange<Double> = 0...1,
         step: Double? = nil,
         detent: Double? = nil,
         tone: SemanticCategoryTone = .brand,
         icon: String? = nil,
         title: String? = nil,
         formattedValue: String? = nil,
         onEditingChanged: ((Bool) -> Void)? = nil) {
        self._value = value
        self.range = range
        self.step = step
        self.detent = detent
        self.tone = tone
        self.icon = icon
        self.title = title
        self.formattedValue = formattedValue
        self.onEditingChanged = onEditingChanged
    }

    init<V: BinaryFloatingPoint>(value: Binding<V>,
                                 in bounds: ClosedRange<V>,
                                 step: V? = nil,
                                 detent: V? = nil,
                                 tone: SemanticCategoryTone = .brand,
                                 icon: String? = nil,
                                 title: String? = nil,
                                 formattedValue: String? = nil,
                                 onEditingChanged: ((Bool) -> Void)? = nil) {
        self._value = Binding(
            get: { Double(value.wrappedValue) },
            set: { value.wrappedValue = V($0) }
        )
        self.range = Double(bounds.lowerBound)...Double(bounds.upperBound)
        self.step = step.map { Double($0) }
        self.detent = detent.map { Double($0) }
        self.tone = tone
        self.icon = icon
        self.title = title
        self.formattedValue = formattedValue
        self.onEditingChanged = onEditingChanged
    }

    @State private var isDragging = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.isEnabled) private var isEnabled

    private var normalized: Double {
        let span = max(0.0001, range.upperBound - range.lowerBound)
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    private var detentNormalized: Double? {
        guard let detent, range.contains(detent) else { return nil }
        let span = max(0.0001, range.upperBound - range.lowerBound)
        return min(max((detent - range.lowerBound) / span, 0), 1)
    }

    var body: some View {
        let fillTint = tone.color(scheme: colorScheme, highContrast: colorSchemeContrast == .increased)
        VStack(alignment: .leading, spacing: 5) {
            if title != nil || formattedValue != nil {
                HStack(spacing: 6) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(fillTint)
                    }
                    if let title {
                        Text(title)
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if let formattedValue {
                        Text(formattedValue)
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            GeometryReader { geo in
                let width = max(1, geo.size.width)
                let height: CGFloat = 18
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.10))
                        .frame(height: 8)

                    if let dn = detentNormalized {
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.32))
                            .frame(width: 2, height: 12)
                            .offset(x: max(0, min(width - 2, CGFloat(dn) * width - 1)))
                    }

                    Capsule(style: .continuous)
                        .fill(fillTint.opacity(isEnabled ? 1 : 0.4))
                        .frame(width: max(8, CGFloat(normalized) * width), height: 8)

                    Circle()
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.28), radius: isDragging ? 3 : 1.5, x: 0, y: 1)
                        .frame(width: isDragging ? 16 : 14, height: isDragging ? 16 : 14)
                        .overlay(
                            Circle()
                                .strokeBorder(fillTint.opacity(0.45), lineWidth: 1)
                        )
                        .offset(x: max(0, min(width - (isDragging ? 16 : 14),
                                             CGFloat(normalized) * (width - (isDragging ? 16 : 14)))))
                }
                .frame(height: height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            guard isEnabled else { return }
                            if !isDragging {
                                isDragging = true
                                onEditingChanged?(true)
                            }
                            let frac = min(max(Double(drag.location.x / width), 0), 1)
                            let raw = range.lowerBound + frac * (range.upperBound - range.lowerBound)
                            let stepped = step.map { s in
                                s > 0 ? min(range.upperBound, max(range.lowerBound, (raw / s).rounded() * s)) : raw
                            } ?? raw
                            let snapped = VorssaintDesignKitMath.snappedDetentValue(
                                rawValue: stepped, range: range, detent: detent
                            )
                            if VorssaintDesignKitMath.didCrossDetent(previous: value, next: snapped, detent: detent) {
                                VorssaintHaptics.alignment()
                            }
                            value = snapped
                        }
                        .onEnded { _ in
                            isDragging = false
                            onEditingChanged?(false)
                        }
                )
                .onTapGesture(count: 2) {
                    guard isEnabled, let detent else { return }
                    VorssaintHaptics.alignment()
                    onEditingChanged?(true)
                    value = detent
                    onEditingChanged?(false)
                }
            }
            .frame(height: 18)
        }
        .opacity(isEnabled ? 1 : 0.5)
    }
}

/// Compact 26pt tactile action chip replacing `.buttonStyle(.bordered).controlSize(.mini)`.
struct VorssaintActionChip: View {
    let title: String
    var symbol: String? = nil
    var tone: SemanticCategoryTone = .brand
    var prominent: Bool = false
    var destructive: Bool = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let baseColor: Color = destructive
            ? .red
            : tone.color(scheme: colorScheme, highContrast: colorSchemeContrast == .increased)
        Button(action: {
            VorssaintHaptics.generic()
            action()
        }) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(prominent ? .white : (destructive ? .red : .primary))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: DesignRadius.pill, style: .continuous)
                    .fill(prominent
                          ? baseColor
                          : baseColor.opacity(colorScheme == .dark ? 0.14 : 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignRadius.pill, style: .continuous)
                    .strokeBorder(prominent ? Color.clear : baseColor.opacity(0.24), lineWidth: 0.75)
            )
        }
        .buttonStyle(VorssaintScalePressButtonStyle())
        .opacity(isEnabled ? 1 : 0.45)
    }
}

