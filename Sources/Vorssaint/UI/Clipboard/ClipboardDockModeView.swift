// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Paste-inspired horizontal bottom dock carousel showing color-coded source app strips,
/// rich content/OCR/thumbnail previews, `⌘1`–`⌘9` badges, and tactile hover glows.
struct ClipboardDockModeView: View {
    let entries: [ClipboardHistoryEntry]
    let tokens: [String]
    let selectedEntryID: UUID?
    let selectionIsVisible: Bool
    let batchEntryIDs: Set<UUID>
    let showSourceAppIcons: Bool
    let canReorderEntries: Bool
    let presentationID: UUID
    let language: AppLanguage
    let pinboards: [ClipboardPinboard]

    let onSelectHover: (UUID) -> Void
    let onActivate: (ClipboardHistoryEntry) -> Void
    let onCopyOnly: (ClipboardHistoryEntry) -> Void
    let onToggleBatch: (ClipboardHistoryEntry) -> Void
    let onTogglePin: (ClipboardHistoryEntry) -> Void
    let onMove: (ClipboardHistoryEntry, ClipboardHistoryMoveDirection) -> Void
    let canMove: (ClipboardHistoryEntry, ClipboardHistoryMoveDirection) -> Bool
    let onAssignPinboard: (ClipboardHistoryEntry, UUID) -> Void
    let onRemoveFromPinboard: (ClipboardHistoryEntry, UUID) -> Void
    let onEnqueuePasteStack: (ClipboardHistoryEntry) -> Void
    let onEditImage: (ClipboardHistoryEntry) -> Void
    let onDelete: (ClipboardHistoryEntry) -> Void

    private static let topAnchorID = "clipboard-dock-top"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    Color.clear
                        .frame(width: 4, height: 1)
                        .id(Self.topAnchorID)

                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        DockCarouselCard(
                            entry: entry,
                            tokens: tokens,
                            shortcutIndex: index < 9 ? index : nil,
                            isSelected: selectionIsVisible && selectedEntryID == entry.id,
                            isBatchSelected: batchEntryIDs.contains(entry.id),
                            showSourceAppIcons: showSourceAppIcons,
                            canReorderEntries: canReorderEntries,
                            presentationID: presentationID,
                            language: language,
                            pinboards: pinboards,
                            canMoveLeft: canMove(entry, .up),
                            canMoveRight: canMove(entry, .down),
                            onSelectHover: onSelectHover,
                            onActivate: onActivate,
                            onCopyOnly: onCopyOnly,
                            onToggleBatch: onToggleBatch,
                            onTogglePin: onTogglePin,
                            onMove: onMove,
                            onAssignPinboard: onAssignPinboard,
                            onRemoveFromPinboard: onRemoveFromPinboard,
                            onEnqueuePasteStack: onEnqueuePasteStack,
                            onEditImage: onEditImage,
                            onDelete: onDelete
                        )
                        .equatable()
                        .id(entry.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .onChange(of: selectedEntryID) { _, newID in
                guard selectionIsVisible, let newID else { return }
                proxy.scrollTo(newID)
            }
            .onChange(of: selectionIsVisible) { _, visible in
                guard visible, let selectedEntryID else { return }
                proxy.scrollTo(selectedEntryID)
            }
            .onChange(of: presentationID) { _, _ in
                proxy.scrollTo(Self.topAnchorID, anchor: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DockCarouselCard: View, Equatable {
    static let cardSize = CGSize(width: 224, height: 222)

    let entry: ClipboardHistoryEntry
    let tokens: [String]
    let shortcutIndex: Int?
    let isSelected: Bool
    let isBatchSelected: Bool
    let showSourceAppIcons: Bool
    let canReorderEntries: Bool
    let presentationID: UUID
    let language: AppLanguage
    let pinboards: [ClipboardPinboard]
    let canMoveLeft: Bool
    let canMoveRight: Bool

    let onSelectHover: (UUID) -> Void
    let onActivate: (ClipboardHistoryEntry) -> Void
    let onCopyOnly: (ClipboardHistoryEntry) -> Void
    let onToggleBatch: (ClipboardHistoryEntry) -> Void
    let onTogglePin: (ClipboardHistoryEntry) -> Void
    let onMove: (ClipboardHistoryEntry, ClipboardHistoryMoveDirection) -> Void
    let onAssignPinboard: (ClipboardHistoryEntry, UUID) -> Void
    let onRemoveFromPinboard: (ClipboardHistoryEntry, UUID) -> Void
    let onEnqueuePasteStack: (ClipboardHistoryEntry) -> Void
    let onEditImage: (ClipboardHistoryEntry) -> Void
    let onDelete: (ClipboardHistoryEntry) -> Void

    @State private var isHovered = false
    @State private var hoverTask: Task<Void, Never>?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var text: ClipboardFeatureStrings { FeatureStrings.clipboard(language) }
    private var l10nStrings: Strings { Strings.localized(language) }
    private var wave3Strings: OverhaulWave3Strings { OverhaulStrings.wave3(language) }
    private var v2Strings: OverhaulV2Strings { OverhaulV2Strings.localized(language) }

    static func == (lhs: DockCarouselCard, rhs: DockCarouselCard) -> Bool {
        lhs.entry == rhs.entry
            && lhs.tokens == rhs.tokens
            && lhs.shortcutIndex == rhs.shortcutIndex
            && lhs.isSelected == rhs.isSelected
            && lhs.isBatchSelected == rhs.isBatchSelected
            && lhs.showSourceAppIcons == rhs.showSourceAppIcons
            && lhs.canReorderEntries == rhs.canReorderEntries
            && lhs.presentationID == rhs.presentationID
            && lhs.language == rhs.language
            && lhs.pinboards == rhs.pinboards
            && lhs.canMoveLeft == rhs.canMoveLeft
            && lhs.canMoveRight == rhs.canMoveRight
    }

    var body: some View {
        let stripTint = headerAccentColor
        let highlightBorder = isBatchSelected || isSelected
        let borderColor: Color = highlightBorder
            ? Color.accentColor
            : (isHovered ? stripTint.opacity(0.85) : Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.10))

        VStack(alignment: .leading, spacing: 0) {
            cardHeaderStrip(tint: stripTint)
            cardBody
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            Divider()
            cardFooter
        }
        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
        .background(
            RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous)
                .fill(DesignSurfaceTier.elevated.fillColor(for: colorScheme))
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous)
                .strokeBorder(borderColor, lineWidth: highlightBorder ? 2.25 : (isHovered ? 1.5 : 0.75))
        )
        .shadow(
            color: (highlightBorder ? Color.accentColor : stripTint).opacity(isHovered || highlightBorder ? 0.26 : 0.06),
            radius: isHovered || highlightBorder ? 10 : 3,
            x: 0,
            y: isHovered ? 4 : 2
        )
        .scaleEffect(isHovered && !reduceMotion ? 1.015 : 1.0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovered)
        .contentShape(RoundedRectangle(cornerRadius: DesignRadius.card, style: .continuous))
        .onHover { hovering in
            if hovering, NSEvent.mouseLocation == ClipboardHistoryService.shared.keyboardSelectionPointer { return }
            isHovered = hovering
            hoverTask?.cancel()
            guard hovering else { return }
            let id = entry.id
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                onSelectHover(id)
            }
        }
        .onChange(of: presentationID) { _, _ in
            isHovered = false
            hoverTask?.cancel()
        }
        .onDisappear {
            isHovered = false
            hoverTask?.cancel()
        }
        .onTapGesture {
            VorssaintHaptics.generic()
            onActivate(entry)
        }
        .onDrag {
            NSItemProvider(object: entry.id.uuidString as NSString)
        }
        .contextMenu { cardContextMenu }
    }

    private func cardHeaderStrip(tint: Color) -> some View {
        HStack(spacing: 7) {
            Button {
                onToggleBatch(entry)
            } label: {
                if isBatchSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                } else if let app = sourceApp {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    Image(systemName: kindSymbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                }
            }
            .buttonStyle(.plain)
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 0) {
                Text(headerTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(entry.copiedAt, style: .time)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
            }

            Spacer(minLength: 4)

            if isHovered {
                HStack(spacing: 4) {
                    if entry.kind == .image, AppFeature.screenshot.isAvailable {
                        Button { onEditImage(entry) } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                    Button { onCopyOnly(entry) } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    Menu {
                        cardContextMenu
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            } else if entry.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(
            LinearGradient(
                colors: [tint.opacity(0.94), tint.opacity(0.76)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    @ViewBuilder
    private var cardBody: some View {
        switch entry.kind {
        case .text:
            if let color = entry.color {
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(red: color.red, green: color.green, blue: color.blue, opacity: color.alpha))
                        .frame(height: 54)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
                        )
                    SearchHighlightText.text(entry.cardPreview, tokens: tokens, fontSize: 12)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(3)
                }
            } else if let linkURL = ClipboardLinkMetadataFetcher.eligibleURL(from: entry.text) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "link")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        Text(linkURL.host ?? linkURL.absoluteString)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())

                    if let cached = ClipboardLinkMetadataFetcher.sharedCache.metadata(for: linkURL),
                       let title = cached.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(2)
                    }
                    SearchHighlightText.text(entry.cardPreview, tokens: tokens, fontSize: 11)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            } else {
                let lang = ClipboardSyntaxHighlighter.detectLanguage(for: entry.text)
                SearchHighlightText.text(entry.cardPreview, tokens: tokens, fontSize: 12)
                    .font(lang == .plain ? .system(size: 12) : .system(size: 11.5, design: .monospaced))
                    .lineSpacing(1.5)
                    .lineLimit(7)
                    .truncationMode(.tail)
            }
        case .image:
            VStack(alignment: .leading, spacing: 6) {
                if let name = entry.imageFile {
                    ClipboardThumbnailImage(source: .stored(name: name),
                                            aspectRatio: entry.imageAspectRatio)
                        .frame(maxWidth: .infinity, maxHeight: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                if let ocr = entry.ocrText, !ocr.isEmpty {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.top, 1)
                        SearchHighlightText.text(ocr, tokens: tokens, fontSize: 10.5)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        case .files:
            if entry.filePaths.count == 1,
               let path = entry.filePaths.first,
               ClipboardImageStore.isImageFile(atPath: path) {
                VStack(alignment: .leading, spacing: 6) {
                    ClipboardThumbnailImage(source: .file(path: path),
                                            aspectRatio: ClipboardImageStore.imageAspectRatio(atPath: path))
                        .frame(maxWidth: .infinity, maxHeight: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    SearchHighlightText.text(entry.fileNames.first ?? entry.preview, tokens: tokens, fontSize: 11.5)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let ocr = entry.ocrText, !ocr.isEmpty {
                        SearchHighlightText.text(ocr, tokens: tokens, fontSize: 10)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        if let icon = firstFileIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 28, height: 28)
                        } else {
                            Image(systemName: "folder")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        SearchHighlightText.text(fileTitle, tokens: entry.filePaths.count == 1 ? tokens : [], fontSize: 12)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    if entry.filePaths.count > 1 {
                        SearchHighlightText.text(entry.preview, tokens: tokens, fontSize: 10.5)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                }
            }
        }
    }

    private var cardFooter: some View {
        HStack(spacing: 6) {
            Text(footerDetail)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if entry.ocrText?.isEmpty == false {
                Text(v2Strings.clipboardOCRIndexedBadge)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            Spacer(minLength: 4)
            if let shortcutIndex {
                Text("⌘\(shortcutIndex + 1)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.07), in: Capsule())
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
    }

    @ViewBuilder
    private var cardContextMenu: some View {
        Button(l10nStrings.menuPaste) { onActivate(entry) }
        Button(text.copy) { onCopyOnly(entry) }
        Button(wave3Strings.pasteStackTitle) { onEnqueuePasteStack(entry) }
        Divider()
        if !pinboards.isEmpty {
            Menu("Pinboard") {
                ForEach(pinboards) { board in
                    let assigned = board.entryIDs.contains(entry.id)
                    Button {
                        if assigned {
                            onRemoveFromPinboard(entry, board.id)
                        } else {
                            onAssignPinboard(entry, board.id)
                        }
                    } label: {
                        HStack {
                            Text(board.name)
                            if assigned { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
            Divider()
        }
        Button(entry.isPinned ? text.unpin : text.pin) { onTogglePin(entry) }
        Button(text.moveUp) { onMove(entry, .up) }
            .disabled(!canReorderEntries || !canMoveLeft)
        Button(text.moveDown) { onMove(entry, .down) }
            .disabled(!canReorderEntries || !canMoveRight)
        Divider()
        Button(text.delete, role: .destructive) { onDelete(entry) }
    }

    private var headerAccentColor: Color {
        if let color = entry.color {
            return Color(red: color.red, green: color.green, blue: color.blue, opacity: 1)
        }
        let highContrast = colorSchemeContrast == .increased
        if let bundleID = entry.sourceBundleID, !bundleID.isEmpty {
            let tones: [SemanticCategoryTone] = [
                .windowsDock, .clipboardFiles, .dynamicIsland, .tools, .mouseKeyboard, .energyDisplay, .monitor
            ]
            let hash = bundleID.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
            let tone = tones[abs(hash) % tones.count]
            return tone.color(scheme: colorScheme, highContrast: highContrast)
        }
        switch entry.kind {
        case .text:
            return SemanticCategoryTone.clipboardFiles.color(scheme: colorScheme, highContrast: highContrast)
        case .image:
            return SemanticCategoryTone.dynamicIsland.color(scheme: colorScheme, highContrast: highContrast)
        case .files:
            return SemanticCategoryTone.windowsDock.color(scheme: colorScheme, highContrast: highContrast)
        }
    }

    private var headerTitle: String {
        if let app = sourceApp { return app.name }
        switch entry.kind {
        case .text:
            if entry.color != nil { return "Color" }
            if ClipboardLinkMetadataFetcher.eligibleURL(from: entry.text) != nil { return "Link" }
            let lang = ClipboardSyntaxHighlighter.detectLanguage(for: entry.text)
            return lang == .plain ? "Text" : lang.badgeTitle
        case .image:
            return text.imageEntryLabel
        case .files:
            return fileTitle
        }
    }

    private var footerDetail: String {
        switch entry.kind {
        case .text:
            let lang = ClipboardSyntaxHighlighter.detectLanguage(for: entry.text)
            let count = entry.text.count
            return lang == .plain ? "\(count) chars" : "\(lang.badgeTitle) · \(count) chars"
        case .image:
            return entry.imageDimensionsLabel.isEmpty ? text.imageEntryLabel : entry.imageDimensionsLabel
        case .files:
            return fileTitle
        }
    }

    private var fileTitle: String {
        if entry.filePaths.count == 1 {
            return entry.fileNames.first ?? entry.preview
        }
        return String(format: text.fileCountFormat, locale: language.formattingLocale(), entry.filePaths.count)
    }

    private var kindSymbol: String {
        switch entry.kind {
        case .text:
            if entry.color != nil { return "paintpalette" }
            if ClipboardLinkMetadataFetcher.eligibleURL(from: entry.text) != nil { return "link" }
            return "doc.text"
        case .image: return "photo"
        case .files: return "folder"
        }
    }

    private var firstFileIcon: NSImage? {
        guard entry.kind == .files,
              let path = entry.filePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return nil
        }
        return ClipboardImageStore.fileIcon(atPath: path)
    }

    private var sourceApp: (name: String, icon: NSImage)? {
        guard showSourceAppIcons || entry.sourceBundleID != nil,
              let bundleID = entry.sourceBundleID,
              let url = InstalledApps.url(for: bundleID) else {
            return nil
        }
        let rawIcon = InstalledApps.cachedFileIcon(atPath: url.path)
        let icon = ImageThumbnailer.thumbnail(for: rawIcon, pointSize: 20) ?? rawIcon
        let name = InstalledApps.cachedName(for: bundleID)
        return (name, icon)
    }
}
