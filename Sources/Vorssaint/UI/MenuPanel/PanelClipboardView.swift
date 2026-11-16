// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct PanelClipboardView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var history = ClipboardHistoryService.shared
    @AppStorage(DefaultsKey.clipboardHistoryEnabled) private var enabled = false
    @AppStorage(DefaultsKey.clipboardHistoryShortcutEnabled) private var shortcutEnabled = true
    @State private var query = ""
    @State private var copiedID: UUID?
    @State private var hoveredEntryID: UUID?
    /// Counts copies, so the list also follows an entry copied again while
    /// it still carries the tick.
    @State private var copyCount = 0
    @State private var clearingIDs: [UUID: Date]?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.notchPresentation) private var inNotch

    var onClose: () -> Void

    private var text: ClipboardFeatureStrings {
        FeatureStrings.clipboard(l10n.language)
    }

    /// The alert would hang from the island as a sheet; there it asks on its own.
    private func confirmClearAboveIsland(_ ids: [UUID: Date]) {
        let text = text
        DispatchQueue.main.async {
            guard NSAlert.confirmAboveIsland(String(format: text.clearRecentConfirmFormat, ids.count),
                                             message: text.clearRecentConfirmMessage,
                                             action: text.clearRecent, destructive: true,
                                             cancel: text.cancel) else { return }
            history.clearRecent(ids)
            copiedID = nil
        }
    }

    private var filteredEntries: [ClipboardHistoryEntry] {
        history.filteredEntries(matching: query)
    }

    private var canReorderEntries: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchTokens: [String] {
        ClipboardHistorySearch.searchTokens(for: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            controls
            entriesList
        }
        .onAppear { PanelInteractionState.shared.viewKeepsPopoverOpen = true }
        .onDisappear { PanelInteractionState.shared.viewKeepsPopoverOpen = false }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(text.title, systemImage: "doc.on.clipboard")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            PanelCloseButton(action: onClose)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle(isOn: $enabled) {
                HStack(spacing: 6) {
                    Text(text.enable)
                        .font(.system(size: 11.5, weight: .medium))
                    if enabled, shortcutEnabled {
                        Text(shortcut.displayString)
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                            .help(text.shortcut)
                    }
                }
            }
            .toggleStyle(VorssaintPillToggleStyle(tone: .clipboardFiles))
            .accessibilityLabel(text.enable)
            .onChange(of: enabled) { _, _ in
                ClipboardHistoryService.shared.syncWithPreferences()
            }
            if !enabled {
                Text(text.disabled)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                TextField(text.search, text: $query)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .disabled(history.entries.isEmpty)
                ClipboardCapsuleIconButton(
                    systemImage: "trash",
                    destructive: true,
                    iconSize: 11,
                    size: CGSize(width: 28, height: 24),
                    helpText: text.clearRecent
                ) {
                    let ids = history.recentEntriesSnapshot
                    if inNotch { confirmClearAboveIsland(ids) } else { clearingIDs = ids }
                }
                .disabled(history.recentEntries.isEmpty)
                .modifier(ClipboardClearRecentConfirmation(entryIDs: $clearingIDs))
                ClipboardCapsuleIconButton(
                    systemImage: "arrow.up.forward.app",
                    iconSize: 11,
                    size: CGSize(width: 28, height: 24),
                    helpText: text.shortcut
                ) {
                    history.showHistoryWindow()
                }
            }
        }
        .panelCard()
    }

    @ViewBuilder
    private var entriesList: some View {
        if history.entries.isEmpty {
            emptyState(text.empty)
        } else if filteredEntries.isEmpty {
            emptyState(text.noResults)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    // Lazy: a large history would otherwise build every row, and
                    // decode every image thumbnail, each time the panel opens.
                    LazyVStack(alignment: .leading, spacing: 7) {
                        ForEach(filteredEntries) { entry in
                            entryRow(entry)
                                .id(entry.id)
                        }
                    }
                }
                .frame(maxHeight: 260)
                // A copied recent entry moves to the top, so the list follows
                // it and the tick stays in view.
                .onChange(of: copyCount) { _, _ in
                    guard let id = copiedID else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { proxy.scrollTo(id) }
                }
            }
        }
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .panelCard()
    }

    private var shortcut: GlobalShortcut {
        GlobalShortcut.saved(for: DefaultsKey.clipboardHistoryShortcut,
                             fallback: .clipboardDefault)
    }

    @ViewBuilder
    private func entryPreview(_ entry: ClipboardHistoryEntry) -> some View {
        switch entry.kind {
        case .text:
            // Deliberately not selectable: clicking a selectable Text swaps in
            // the selection renderer, which lays the whole preview out and
            // ignores the line limit, so a long entry paints over the rows
            // below it. The history window shows the full, selectable text.
            HStack(alignment: .center, spacing: 7) {
                if let color = entry.color {
                    ColorSwatch(color: color, size: 12)
                }
                SearchHighlightText.text(entry.preview, tokens: searchTokens, fontSize: 10.5)
                    .font(.system(size: 10.5))
                    .lineLimit(3)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .image:
            HStack(alignment: .center, spacing: 7) {
                if let name = entry.imageFile {
                    ClipboardThumbnailImage(source: .stored(name: name),
                                            aspectRatio: entry.imageAspectRatio)
                        .frame(maxWidth: 110, maxHeight: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                SearchHighlightText.text("\(text.imageEntryLabel) · \(entry.imageDimensionsLabel)",
                                         tokens: searchTokens, fontSize: 10)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        case .files:
            if entry.filePaths.count == 1,
               let path = entry.filePaths.first,
               ClipboardImageStore.isImageFile(atPath: path) {
                HStack(alignment: .center, spacing: 7) {
                    ClipboardThumbnailImage(source: .file(path: path),
                                            aspectRatio: ClipboardImageStore.imageAspectRatio(atPath: path))
                        .frame(maxWidth: 110, maxHeight: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    SearchHighlightText.text(entry.fileNames.first ?? entry.preview, tokens: searchTokens, fontSize: 10.5)
                        .font(.system(size: 10.5))
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .help(path)
            } else {
                HStack(alignment: .center, spacing: 7) {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    // A count of several files is no text the search reads.
                    SearchHighlightText.text(entry.filePaths.count == 1
                                                ? (entry.fileNames.first ?? entry.preview)
                                                : String(format: text.fileCountFormat, entry.filePaths.count),
                                             tokens: entry.filePaths.count == 1 ? searchTokens : [],
                                             fontSize: 10.5)
                        .font(.system(size: 10.5))
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .help(entry.filePaths.joined(separator: "\n"))
            }
        }
    }

    private func copyEntry(_ entry: ClipboardHistoryEntry) {
        // A copied recent entry moves to the top, so the second
        // click of a double click would copy whichever entry took
        // its place.
        if let event = NSApp.currentEvent, [.leftMouseDown, .leftMouseUp].contains(event.type),
           event.clickCount > 1 { return }
        // The tick means "it is on the clipboard", so it waits for
        // the write instead of announcing one still queued behind
        // a stalled pasteboard provider.
        history.copy(entry) { copied in
            if copied {
                copiedID = entry.id
                copyCount += 1
            } else {
                NSSound.beep()
            }
        }
    }

    private func entryRow(_ entry: ClipboardHistoryEntry) -> some View {
        let isHovered = hoveredEntryID == entry.id || copiedID == entry.id
        let isCopied = copiedID == entry.id
        let highContrast = colorSchemeContrast == .increased
        let clipboardTint = SemanticCategoryTone.clipboardFiles.color(scheme: colorScheme, highContrast: highContrast)
        let copiedTint = SemanticCategoryTone.tools.color(scheme: colorScheme, highContrast: highContrast)

        return VStack(alignment: .leading, spacing: 6) {
            Button {
                copyEntry(entry)
            } label: {
                entryPreview(entry)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(text.copy)

            HStack(spacing: 5) {
                if entry.isPinned {
                    Label(text.pinned, systemImage: "pin.fill")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(clipboardTint)
                }
                Text(entry.copiedAt, style: .time)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 4)
                if isHovered {
                    if canReorderEntries && (history.canMove(entry, .up) || history.canMove(entry, .down)) {
                        ClipboardCapsuleIconButton(
                            systemImage: "arrow.up",
                            iconSize: 9.5,
                            size: CGSize(width: 22, height: 20),
                            helpText: text.moveUp
                        ) {
                            history.move(entry, .up)
                        }
                        .disabled(!history.canMove(entry, .up))
                        ClipboardCapsuleIconButton(
                            systemImage: "arrow.down",
                            iconSize: 9.5,
                            size: CGSize(width: 22, height: 20),
                            helpText: text.moveDown
                        ) {
                            history.move(entry, .down)
                        }
                        .disabled(!history.canMove(entry, .down))
                    }
                    ClipboardCapsuleIconButton(
                        systemImage: entry.isPinned ? "pin.slash" : "pin",
                        active: entry.isPinned,
                        iconSize: 9.5,
                        size: CGSize(width: 24, height: 20),
                        helpText: entry.isPinned ? text.unpin : text.pin
                    ) {
                        history.togglePin(entry)
                    }
                    if entry.kind == .image, AppFeature.screenshot.isAvailable {
                        ClipboardCapsuleIconButton(
                            systemImage: "pencil",
                            iconSize: 9.5,
                            size: CGSize(width: 24, height: 20),
                            helpText: text.edit
                        ) {
                            history.editImage(entry)
                        }
                    }
                    Button {
                        VorssaintHaptics.generic()
                        copyEntry(entry)
                    } label: {
                        Label(isCopied ? text.copied : text.copy,
                              systemImage: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .frame(height: 20)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isCopied ? copiedTint : clipboardTint)
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(VorssaintScalePressButtonStyle())
                    ClipboardCapsuleIconButton(
                        systemImage: "trash",
                        destructive: true,
                        iconSize: 9.5,
                        size: CGSize(width: 24, height: 20),
                        helpText: text.delete
                    ) {
                        history.remove(entry)
                    }
                }
            }
            .frame(minHeight: 22)
        }
        .panelCard()
        .onHover { hovering in
            hoveredEntryID = hovering ? entry.id : (hoveredEntryID == entry.id ? nil : hoveredEntryID)
        }
    }
}

private struct ClipboardCapsuleIconButton: View {
    let systemImage: String
    var tone: SemanticCategoryTone = .clipboardFiles
    var active: Bool = false
    var destructive: Bool = false
    var iconSize: CGFloat = 10.5
    var size: CGSize = CGSize(width: 26, height: 22)
    let helpText: String
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let accent = destructive
            ? Color.red
            : tone.color(scheme: colorScheme, highContrast: colorSchemeContrast == .increased)
        let foreground: Color = {
            if destructive { return isHovered ? .red : .secondary }
            if active { return accent }
            return isHovered ? .primary : .secondary
        }()
        let fill: Color = {
            if destructive && isHovered { return Color.red.opacity(colorScheme == .dark ? 0.18 : 0.11) }
            if active { return accent.opacity(colorScheme == .dark ? 0.22 : 0.14) }
            return Color.primary.opacity(isHovered ? 0.11 : 0.06)
        }()
        let border: Color = {
            if destructive && isHovered { return Color.red.opacity(0.32) }
            if active { return accent.opacity(0.42) }
            return Color.primary.opacity(isHovered ? 0.16 : 0.09)
        }()

        Button {
            VorssaintHaptics.generic()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: size.width, height: size.height)
                .background(Capsule(style: .continuous).fill(fill))
                .overlay(Capsule(style: .continuous).strokeBorder(border, lineWidth: 0.75))
                .contentShape(Capsule())
        }
        .buttonStyle(VorssaintScalePressButtonStyle())
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { isHovered = $0 }
        .help(helpText)
        .accessibilityLabel(helpText)
    }
}
