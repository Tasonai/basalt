// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Contents of the floating shelf panel: a header (a move handle plus actions)
/// and the item tiles. Dropping onto the card adds items; the tiles themselves
/// are AppKit, so they can drag several selected items out at once.
struct ShelfView: View {
    /// The top-right button. The floating shelf closes; the docked shelf
    /// collapses to its pill instead of vanishing.
    var dismissSystemImage: String = "xmark"
    var dismissHelp: String? = nil
    var onDismiss: (() -> Void)? = nil
    /// The docked shelf shows the brand mark as a quiet watermark, so it reads
    /// as the app's own tray rather than a plain floating card.
    var brandWatermark: Bool = false

    @EnvironmentObject private var shelf: ShelfService
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var cloudUpload = ScreenshotCloudUploadService.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var clearButtonHovered = false
    @State private var shareButtonHovered = false
    @State private var actionsButtonHovered = false
    /// The system share sheet points at a real view, which SwiftUI does not
    /// hand out; this invisible one sits behind the share button.
    @State private var shareAnchor = ShelfSharePickerAnchor.Anchor()
    @State private var newShelfButtonHovered = false
    @State private var pinButtonHovered = false
    @State private var pasteButtonHovered = false
    @State private var closeButtonHovered = false

    private static let panelWidth: CGFloat = 304
    private static let tileAreaHeight: CGFloat = 188

    private var v2Strings: OverhaulV2Strings {
        OverhaulV2Strings.localized(l10n.language)
    }

    private var shelfActionStrings: ShelfActionStrings {
        OverhaulStrings.shelfActions(l10n.language)
    }

    private var menuStrings: ShelfMenuStrings {
        ShelfMenuStrings.localized(l10n.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header
            tiles
            if !shelf.items.isEmpty {
                bottomBar
            }
        }
        .padding(14)
        .frame(width: Self.panelWidth)
        .background(
            ZStack {
                HUDBackdrop(cornerRadius: 18)
                if brandWatermark { brandWatermarkLayer }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isDropTargeted ? Color.accentColor : Color.primary.opacity(0.14),
                              lineWidth: isDropTargeted ? 2 : 1)
        )
        .overlay(alignment: .topLeading) {
            topMoveHandle
        }
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
        .animation(.easeOut(duration: 0.18), value: shelf.items)
        .onHover { inside in
            shelf.setPointerInsidePanel(inside)
        }

    }

    private var isDropTargeted: Bool {
        shelf.dropTargeted
    }

    /// The official mark, large and faint in the corner: unmistakably ours,
    /// never loud enough to fight the tiles.
    private var brandWatermarkLayer: some View {
        BrandMark(width: 128, tint: colorScheme == .light ? Color.black : Color.white)
            .opacity(colorScheme == .light ? 0.05 : 0.08)
            .rotationEffect(.degrees(-8))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .offset(x: 34, y: 26)
            .allowsHitTesting(false)
    }

    private var header: some View {
        HStack(spacing: 7) {
            // Drag this region to move the panel; the tiles below stay free to
            // start item drags.
            HStack(spacing: 7) {
                Image(systemName: "tray.full")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !shelf.items.isEmpty {
                    Text("\(shelf.itemCount)")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.18)))
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .overlay(WindowMoveHandle())

            pasteButton
            newShelfButton
            if !brandWatermark { pinButton }
            closeButton
        }
    }

    private var topMoveHandle: some View {
        WindowMoveHandle(acceptsDrops: true)
            .frame(width: Self.panelWidth - (brandWatermark ? 129 : 167), height: 55)
    }

    private var newShelfButton: some View {
        Button {
            let seeded = shelf.selection.isEmpty ? [] : shelf.selectedItems()
            ShelfAdditionalInstanceController.shared.openNewShelf(seededWith: seeded)
        } label: {
            Image(systemName: "plus.rectangle.on.rectangle")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(Color.primary.opacity(newShelfButtonHovered ? 0.14 : 0.08))
                )
                .overlay(
                    Circle().strokeBorder(Color.primary.opacity(newShelfButtonHovered ? 0.42 : 0.18), lineWidth: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.secondary)
        .onHover { newShelfButtonHovered = $0 }
        .help(v2Strings.shelfNewButton)
        .accessibilityLabel(v2Strings.shelfNewButton)
    }

    private var pasteButton: some View {
        Button { shelf.pasteFromClipboard() } label: {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(Color.primary.opacity(pasteButtonHovered ? 0.14 : 0.08))
                )
                .overlay(
                    Circle().strokeBorder(Color.primary.opacity(pasteButtonHovered ? 0.42 : 0.18), lineWidth: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.secondary)
        .onHover { pasteButtonHovered = $0 }
        .help(menuStrings.pasteFromClipboardShortcut)
        .accessibilityLabel(menuStrings.pasteFromClipboard)
    }

    private var pinButton: some View {
        Button { shelf.togglePin() } label: {
            Image(systemName: shelf.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(shelf.isPinned
                                  ? Color.accentColor.opacity(pinButtonHovered ? 0.30 : 0.20)
                                  : Color.primary.opacity(pinButtonHovered ? 0.14 : 0.08))
                )
                .overlay(
                    Circle().strokeBorder(shelf.isPinned
                                          ? Color.accentColor.opacity(0.65)
                                          : Color.primary.opacity(pinButtonHovered ? 0.42 : 0.18),
                                          lineWidth: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(shelf.isPinned ? Color.accentColor : Color.secondary)
        .onHover { pinButtonHovered = $0 }
        .help(shelf.isPinned ? l10n.s.shelfUnpin : l10n.s.shelfPin)
        .accessibilityLabel(shelf.isPinned ? l10n.s.shelfUnpin : l10n.s.shelfPin)
    }

    private var closeButton: some View {
        Button { (onDismiss ?? { shelf.close() })() } label: {
            Image(systemName: dismissSystemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(closeButtonHovered ? 0.14 : 0.08))
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(closeButtonHovered ? 0.42 : 0.18), lineWidth: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { closeButtonHovered = $0 }
        .help(dismissHelp ?? l10n.s.menuClose)
    }

    private var bottomBar: some View {
        HStack(spacing: 6) {
            Text(l10n.s.shelfHint)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 6)
            actionsMenuButton
            shareButton
            clearButton
        }
        .frame(minHeight: 30)
    }

    private var actionsMenuButton: some View {
        let enabled = shelf.hasFilesForActions
        let urls = shelf.fileURLsForActions()
        return Menu {
            if cloudUpload.isConfigured, let uploadTarget = urls.first {
                Button {
                    uploadFileToCloud(uploadTarget)
                } label: {
                    Label(v2Strings.shelfUploadCloud, systemImage: "icloud.and.arrow.up")
                }
            }

            Button {
                ShelfActionsEngine.compressToZip(urls: shelf.fileURLsForActions())
            } label: {
                Label(menuStrings.compressToZip, systemImage: "archivebox")
            }

            let hasImages = urls.contains { ShelfInteractionSupport.editableImage(in: [$0]) != nil }
            if hasImages {
                Menu {
                    Button("PNG") {
                        if let img = urls.first(where: { ShelfInteractionSupport.editableImage(in: [$0]) != nil }) {
                            ShelfActionsEngine.convertImage(url: img, to: .png)
                        }
                    }
                    Button("JPEG") {
                        if let img = urls.first(where: { ShelfInteractionSupport.editableImage(in: [$0]) != nil }) {
                            ShelfActionsEngine.convertImage(url: img, to: .jpeg)
                        }
                    }
                    Button(shelfActionStrings.convertWebP) {
                        if let img = urls.first(where: { ShelfInteractionSupport.editableImage(in: [$0]) != nil }) {
                            _ = try? ShelfProActions.convertAndResizeImage(at: img, to: .webp)
                        }
                    }
                    Button(shelfActionStrings.convertHEIC) {
                        if let img = urls.first(where: { ShelfInteractionSupport.editableImage(in: [$0]) != nil }) {
                            _ = try? ShelfProActions.convertAndResizeImage(at: img, to: .heic)
                        }
                    }
                } label: {
                    Label(menuStrings.convertImage, systemImage: "photo.on.rectangle")
                }

                Button {
                    for img in urls where ShelfInteractionSupport.editableImage(in: [img]) != nil {
                        ShelfActionsEngine.stripMetadata(url: img)
                    }
                } label: {
                    Label(menuStrings.stripExif, systemImage: "shield.lefthalf.filled")
                }

                Button {
                    if let img = urls.first(where: { ShelfInteractionSupport.editableImage(in: [$0]) != nil }) {
                        ShelfActionsEngine.extractTextOCR(from: img)
                    }
                } label: {
                    Label(menuStrings.recognizeOCR, systemImage: "text.viewfinder")
                }
            }

            let imageURLs = urls.filter { ShelfInteractionSupport.editableImage(in: [$0]) != nil }
            if imageURLs.count >= 2 {
                Menu {
                    Button(menuStrings.vertically) {
                        ShelfActionsEngine.stitchImages(urls: imageURLs, direction: .vertical)
                    }
                    Button(menuStrings.horizontally) {
                        ShelfActionsEngine.stitchImages(urls: imageURLs, direction: .horizontal)
                    }
                } label: {
                    Label(menuStrings.stitchImages, systemImage: "rectangle.split.2x1")
                }
            }

            if urls.count > 1 || urls.contains(where: { $0.pathExtension.lowercased() == "pdf" }) {
                Button {
                    ShelfActionsEngine.mergeToPDF(urls: shelf.fileURLsForActions())
                } label: {
                    Label(shelfActionStrings.mergePDF, systemImage: "doc.on.doc.fill")
                }
            }

            if urls.count > 1 {
                Menu {
                    Button(menuStrings.renameNumber) {
                        ShelfActionsEngine.batchRename(urls: shelf.fileURLsForActions(), pattern: .sequential(prefix: "File"))
                    }
                    Button(menuStrings.renameSnakeCase) {
                        ShelfActionsEngine.batchRename(urls: shelf.fileURLsForActions(), pattern: .slugify)
                    }
                } label: {
                    Label(shelfActionStrings.batchRename, systemImage: "pencil.line")
                }
            }

            Button {
                ShelfActionsEngine.copyFilePaths(urls: shelf.fileURLsForActions())
            } label: {
                Label(v2Strings.shelfCopyURL, systemImage: "doc.on.doc")
            }

            Menu {
                let tags: [(String, String)] = [
                    (menuStrings.tagRed, "Red"),
                    (menuStrings.tagOrange, "Orange"),
                    (menuStrings.tagYellow, "Yellow"),
                    (menuStrings.tagGreen, "Green"),
                    (menuStrings.tagBlue, "Blue"),
                    (menuStrings.tagPurple, "Purple"),
                    (menuStrings.tagGray, "Gray"),
                ]
                ForEach(tags, id: \.1) { name, val in
                    Button(name) {
                        ShelfActionsEngine.setFinderTag(urls: shelf.fileURLsForActions(), tag: val)
                    }
                }
                Divider()
                Button(menuStrings.clearTags) {
                    ShelfActionsEngine.setFinderTag(urls: shelf.fileURLsForActions(), tag: nil)
                }
            } label: {
                Label(menuStrings.finderTag, systemImage: "tag")
            }

            Button {
                let urls = shelf.fileURLsForActions()
                if let airdrop = NSSharingService(named: .sendViaAirDrop), airdrop.canPerform(withItems: urls) {
                    airdrop.perform(withItems: urls)
                }
            } label: {
                Label("AirDrop", systemImage: "antenna.radiowaves.left.and.right")
            }

            Divider()

            Button {
                ShelfQuickLookCoordinator.shared.toggle(urls: shelf.fileURLsForActions())
            } label: {
                Label(menuStrings.quickLookSpace, systemImage: "eye")
            }
        } label: {
            footerButtonFace(systemImage: "wand.and.stars", tint: .purple, hovered: actionsButtonHovered && enabled)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(actionsButtonHovered ? Color.purple : Color.secondary)
        .opacity(enabled ? 1 : 0.4)
        .onHover { actionsButtonHovered = $0 }
        .disabled(!enabled)
        .help(menuStrings.quickActions)
    }

    private var shareButton: some View {
        // Nothing to send means a button that has to read as unavailable,
        // hover included, instead of looking exactly like the live one.
        let enabled = shelf.hasFilesForActions
        let hovered = shareButtonHovered && enabled
        return Button(action: shareAction) {
            footerButtonFace(systemImage: "square.and.arrow.up", tint: .accentColor, hovered: hovered)
                .background(ShelfSharePickerAnchor(anchor: shareAnchor))
        }
        .buttonStyle(.plain)
        .foregroundStyle(hovered ? Color.accentColor : Color.secondary)
        .opacity(enabled ? 1 : 0.4)
        .onHover { shareButtonHovered = $0 }
        .disabled(!enabled)
        .help(l10n.s.shelfActionShare)
        .accessibilityLabel(l10n.s.shelfActionShare)
    }

    private var clearButton: some View {
        Button(action: trashAction) {
            footerButtonFace(systemImage: shelf.selection.isEmpty ? "trash" : "trash.fill",
                             tint: .red,
                             hovered: clearButtonHovered)
        }
        .buttonStyle(.plain)
        .foregroundStyle(clearButtonHovered ? Color.red.opacity(0.82) : Color.secondary)
        .onHover { clearButtonHovered = $0 }
        .help(shelf.selection.isEmpty ? l10n.s.shelfClearAll : l10n.s.shelfRemoveSelected)
    }

    /// The shared face of the footer's buttons.
    private func footerButtonFace(systemImage: String, tint: Color, hovered: Bool) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 36, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.opacity(hovered ? 0.20 : 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(tint.opacity(hovered ? 0.34 : 0.12), lineWidth: 0.8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var title: String {
        shelf.selection.isEmpty
            ? l10n.s.shelfTitle
            : String(format: l10n.s.shelfSelectedFormat, shelf.selection.count)
    }

    @ViewBuilder
    private var tiles: some View {
        if shelf.items.isEmpty {
            emptyState
        } else {
            ShelfTilesView(items: shelf.visibleItems,
                           contentRevision: shelf.contentRevision,
                           selection: shelf.selection,
                           expandedBatches: shelf.expandedBatches,
                           pinnedIDs: shelf.pinnedIDs,
                           revealID: shelf.revealTargetID,
                           revealSerial: shelf.addSerial)
                .frame(height: Self.tileAreaHeight)
        }
    }

    private var emptyState: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .foregroundStyle(.secondary.opacity(0.4))
            .frame(height: Self.tileAreaHeight)
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 21))
                        .foregroundStyle(.secondary)
                    Text(l10n.s.shelfEmpty)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            )
            .overlay(WindowMoveHandle(acceptsDrops: true))
    }

    private func shareAction() {
        let urls = shelf.fileURLsForActions()
        guard !urls.isEmpty else { return }
        shareAnchor.present(urls)
    }

    private func trashAction() {
        if shelf.selection.isEmpty {
            shelf.clear()
        } else {
            shelf.removeItems(Array(shelf.selection))
        }
    }

    nonisolated static func readCloudPayloadData(from url: URL) -> Data? {
        guard ShelfInteractionSupport.editableImage(in: [url]) != nil,
              url.pathExtension.lowercased() != "png" else {
            return try? Data(contentsOf: url)
        }
        guard let image = NSImage(contentsOf: url),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
    }

    private func uploadFileToCloud(_ url: URL) {
        Task {
            let payloadData = await Task.detached(priority: .userInitiated) {
                Self.readCloudPayloadData(from: url)
            }.value
            guard let payloadData, !payloadData.isEmpty else {
                QuickToolHUD.show(icon: "icloud.and.arrow.up",
                                  message: ScreenshotCloudUploadError.invalidImage.localizedDescription)
                NSSound.beep()
                return
            }
            let fileName = (ShelfInteractionSupport.editableImage(in: [url]) != nil
                            && url.pathExtension.lowercased() != "png")
                ? url.deletingPathExtension().lastPathComponent + ".png"
                : url.lastPathComponent
            do {
                _ = try await ScreenshotCloudUploadService.shared.upload(
                    pngData: payloadData,
                    fileName: fileName
                )
            } catch {
                QuickToolHUD.show(icon: "icloud.and.arrow.up", message: error.localizedDescription)
                NSSound.beep()
            }
        }
    }
}

/// 15-language Shelf action & context-menu strings complementing `OverhaulV2Strings`
/// and `OverhaulStrings.shelfActions`.
struct ShelfMenuStrings {
    let pasteFromClipboard: String
    let pasteFromClipboardShortcut: String
    let compressToZip: String
    let convertImage: String
    let stripExif: String
    let recognizeOCR: String
    let stitchImages: String
    let vertically: String
    let horizontally: String
    let renameNumber: String
    let renameSnakeCase: String
    let finderTag: String
    let clearTags: String
    let tagRed: String
    let tagOrange: String
    let tagYellow: String
    let tagGreen: String
    let tagBlue: String
    let tagPurple: String
    let tagGray: String
    let quickLook: String
    let quickLookSpace: String
    let quickActions: String

    static func localized(_ language: AppLanguage) -> ShelfMenuStrings {
        switch language {
        case .enUS:
            return ShelfMenuStrings(
                pasteFromClipboard: "Paste from clipboard",
                pasteFromClipboardShortcut: "Paste from clipboard (⌘V)",
                compressToZip: "Compress to ZIP",
                convertImage: "Convert Image",
                stripExif: "Strip EXIF Metadata",
                recognizeOCR: "Recognize Text (OCR)",
                stitchImages: "Stitch Images",
                vertically: "Vertically",
                horizontally: "Horizontally",
                renameNumber: "Number (File_1, File_2…)",
                renameSnakeCase: "Web safe (snake_case)",
                finderTag: "Finder Tag",
                clearTags: "Clear Tags",
                tagRed: "Red",
                tagOrange: "Orange",
                tagYellow: "Yellow",
                tagGreen: "Green",
                tagBlue: "Blue",
                tagPurple: "Purple",
                tagGray: "Gray",
                quickLook: "Quick Look",
                quickLookSpace: "Quick Look (Space)",
                quickActions: "Quick Actions"
            )
        case .ru:
            return ShelfMenuStrings(
                pasteFromClipboard: "Вставить из буфера обмена",
                pasteFromClipboardShortcut: "Вставить из буфера обмена (⌘V)",
                compressToZip: "Сжать в ZIP",
                convertImage: "Конвертировать изображение",
                stripExif: "Очистить метаданные (EXIF)",
                recognizeOCR: "Распознать текст (OCR)",
                stitchImages: "Склеить изображения",
                vertically: "По вертикали",
                horizontally: "По горизонтали",
                renameNumber: "Пронумеровать (File_1, File_2…)",
                renameSnakeCase: "Веб-формат (snake_case)",
                finderTag: "Метка Finder",
                clearTags: "Снять метки",
                tagRed: "Красный",
                tagOrange: "Оранжевый",
                tagYellow: "Жёлтый",
                tagGreen: "Зелёный",
                tagBlue: "Синий",
                tagPurple: "Фиолетовый",
                tagGray: "Серый",
                quickLook: "Быстрый просмотр",
                quickLookSpace: "Быстрый просмотр (Пробел)",
                quickActions: "Быстрые действия с файлами"
            )
        case .ptBR:
            return ShelfMenuStrings(
                pasteFromClipboard: "Colar da área de transferência",
                pasteFromClipboardShortcut: "Colar da área de transferência (⌘V)",
                compressToZip: "Compactar em ZIP",
                convertImage: "Converter imagem",
                stripExif: "Remover metadados (EXIF)",
                recognizeOCR: "Reconhecer texto (OCR)",
                stitchImages: "Unir imagens",
                vertically: "Verticalmente",
                horizontally: "Horizontalmente",
                renameNumber: "Numerar (File_1, File_2…)",
                renameSnakeCase: "Formato web (snake_case)",
                finderTag: "Etiqueta do Finder",
                clearTags: "Limpar etiquetas",
                tagRed: "Vermelho",
                tagOrange: "Laranja",
                tagYellow: "Amarelo",
                tagGreen: "Verde",
                tagBlue: "Azul",
                tagPurple: "Roxo",
                tagGray: "Cinza",
                quickLook: "Visualização Rápida",
                quickLookSpace: "Visualização Rápida (Espaço)",
                quickActions: "Ações Rápidas"
            )
        case .tr:
            return ShelfMenuStrings(
                pasteFromClipboard: "Panodan yapıştır",
                pasteFromClipboardShortcut: "Panodan yapıştır (⌘V)",
                compressToZip: "ZIP Olarak Sıkıştır",
                convertImage: "Görseli Dönüştür",
                stripExif: "EXIF Verilerini Temizle",
                recognizeOCR: "Metni Tanı (OCR)",
                stitchImages: "Görselleri Birleştir",
                vertically: "Dikey",
                horizontally: "Yatay",
                renameNumber: "Numaralandır (File_1, File_2…)",
                renameSnakeCase: "Web uyumlu (snake_case)",
                finderTag: "Finder Etiketi",
                clearTags: "Etiketleri Temizle",
                tagRed: "Kırmızı",
                tagOrange: "Turuncu",
                tagYellow: "Sarı",
                tagGreen: "Yeşil",
                tagBlue: "Mavi",
                tagPurple: "Mor",
                tagGray: "Gri",
                quickLook: "Göz At",
                quickLookSpace: "Göz At (Boşluk)",
                quickActions: "Hızlı Eylemler"
            )
        case .es:
            return ShelfMenuStrings(
                pasteFromClipboard: "Pegar del portapapeles",
                pasteFromClipboardShortcut: "Pegar del portapapeles (⌘V)",
                compressToZip: "Comprimir en ZIP",
                convertImage: "Convertir imagen",
                stripExif: "Eliminar metadatos (EXIF)",
                recognizeOCR: "Reconocer texto (OCR)",
                stitchImages: "Unir imágenes",
                vertically: "Verticalmente",
                horizontally: "Horizontalmente",
                renameNumber: "Numerar (File_1, File_2…)",
                renameSnakeCase: "Formato web (snake_case)",
                finderTag: "Etiqueta del Finder",
                clearTags: "Borrar etiquetas",
                tagRed: "Rojo",
                tagOrange: "Naranja",
                tagYellow: "Amarillo",
                tagGreen: "Verde",
                tagBlue: "Azul",
                tagPurple: "Morado",
                tagGray: "Gris",
                quickLook: "Vista Rápida",
                quickLookSpace: "Vista Rápida (Espacio)",
                quickActions: "Acciones rápidas"
            )
        case .sk:
            return ShelfMenuStrings(
                pasteFromClipboard: "Prilepiť zo schránky",
                pasteFromClipboardShortcut: "Prilepiť zo schránky (⌘V)",
                compressToZip: "Komprimovať do ZIP",
                convertImage: "Previesť obrázok",
                stripExif: "Odstrániť metadáta (EXIF)",
                recognizeOCR: "Rozpoznať text (OCR)",
                stitchImages: "Spojiť obrázky",
                vertically: "Zvislo",
                horizontally: "Vodorovne",
                renameNumber: "Očíslovať (File_1, File_2…)",
                renameSnakeCase: "Webový formát (snake_case)",
                finderTag: "Značka Findera",
                clearTags: "Odstrániť značky",
                tagRed: "Červená",
                tagOrange: "Oranžová",
                tagYellow: "Žltá",
                tagGreen: "Zelená",
                tagBlue: "Modrá",
                tagPurple: "Fialová",
                tagGray: "Sivá",
                quickLook: "Rýchly náhľad",
                quickLookSpace: "Rýchly náhľad (Medzerník)",
                quickActions: "Rýchle akcie"
            )
        case .de:
            return ShelfMenuStrings(
                pasteFromClipboard: "Aus Zwischenablage einsetzen",
                pasteFromClipboardShortcut: "Aus Zwischenablage einsetzen (⌘V)",
                compressToZip: "Als ZIP komprimieren",
                convertImage: "Bild konvertieren",
                stripExif: "EXIF-Metadaten entfernen",
                recognizeOCR: "Text erkennen (OCR)",
                stitchImages: "Bilder zusammenfügen",
                vertically: "Vertikal",
                horizontally: "Horizontal",
                renameNumber: "Nummerieren (File_1, File_2…)",
                renameSnakeCase: "Web-Format (snake_case)",
                finderTag: "Finder-Tag",
                clearTags: "Tags entfernen",
                tagRed: "Rot",
                tagOrange: "Orange",
                tagYellow: "Gelb",
                tagGreen: "Grün",
                tagBlue: "Blau",
                tagPurple: "Violett",
                tagGray: "Grau",
                quickLook: "Übersicht",
                quickLookSpace: "Übersicht (Leertaste)",
                quickActions: "Schnellaktionen"
            )
        case .fr:
            return ShelfMenuStrings(
                pasteFromClipboard: "Coller depuis le presse-papiers",
                pasteFromClipboardShortcut: "Coller depuis le presse-papiers (⌘V)",
                compressToZip: "Compresser en ZIP",
                convertImage: "Convertir l\u{2019}image",
                stripExif: "Supprimer les métadonnées (EXIF)",
                recognizeOCR: "Reconnaître le texte (OCR)",
                stitchImages: "Assembler les images",
                vertically: "Verticalement",
                horizontally: "Horizontalement",
                renameNumber: "Numéroter (File_1, File_2…)",
                renameSnakeCase: "Format web (snake_case)",
                finderTag: "Tag Finder",
                clearTags: "Effacer les tags",
                tagRed: "Rouge",
                tagOrange: "Orange",
                tagYellow: "Jaune",
                tagGreen: "Vert",
                tagBlue: "Bleu",
                tagPurple: "Violet",
                tagGray: "Gris",
                quickLook: "Coup d\u{2019}œil",
                quickLookSpace: "Coup d\u{2019}œil (Espace)",
                quickActions: "Actions rapides"
            )
        case .it:
            return ShelfMenuStrings(
                pasteFromClipboard: "Incolla dagli appunti",
                pasteFromClipboardShortcut: "Incolla dagli appunti (⌘V)",
                compressToZip: "Comprimi in ZIP",
                convertImage: "Converti immagine",
                stripExif: "Rimuovi metadati (EXIF)",
                recognizeOCR: "Riconosci testo (OCR)",
                stitchImages: "Unisci immagini",
                vertically: "Verticalmente",
                horizontally: "Orizzontalmente",
                renameNumber: "Numera (File_1, File_2…)",
                renameSnakeCase: "Formato web (snake_case)",
                finderTag: "Tag del Finder",
                clearTags: "Rimuovi tag",
                tagRed: "Rosso",
                tagOrange: "Arancione",
                tagYellow: "Giallo",
                tagGreen: "Verde",
                tagBlue: "Blu",
                tagPurple: "Viola",
                tagGray: "Grigio",
                quickLook: "Visualizzazione rapida",
                quickLookSpace: "Visualizzazione rapida (Spazio)",
                quickActions: "Azioni rapide"
            )
        case .ja:
            return ShelfMenuStrings(
                pasteFromClipboard: "クリップボードからペースト",
                pasteFromClipboardShortcut: "クリップボードからペースト (⌘V)",
                compressToZip: "ZIP に圧縮",
                convertImage: "画像を変換",
                stripExif: "EXIF メタデータを削除",
                recognizeOCR: "テキストを認識 (OCR)",
                stitchImages: "画像を結合",
                vertically: "縦方向に結合",
                horizontally: "横方向に結合",
                renameNumber: "連番を付ける (File_1, File_2…)",
                renameSnakeCase: "Web 形式 (snake_case)",
                finderTag: "Finder タグ",
                clearTags: "タグを消去",
                tagRed: "レッド",
                tagOrange: "オレンジ",
                tagYellow: "イエロー",
                tagGreen: "グリーン",
                tagBlue: "ブルー",
                tagPurple: "パープル",
                tagGray: "グレイ",
                quickLook: "クイックルック",
                quickLookSpace: "クイックルック (スペース)",
                quickActions: "クイックアクション"
            )
        case .ko:
            return ShelfMenuStrings(
                pasteFromClipboard: "클립보드에서 붙여넣기",
                pasteFromClipboardShortcut: "클립보드에서 붙여넣기 (⌘V)",
                compressToZip: "ZIP으로 압축",
                convertImage: "이미지 변환",
                stripExif: "EXIF 메타데이터 제거",
                recognizeOCR: "텍스트 인식 (OCR)",
                stitchImages: "이미지 이어 붙이기",
                vertically: "세로로",
                horizontally: "가로로",
                renameNumber: "번호 매기기 (File_1, File_2…)",
                renameSnakeCase: "웹 안전 (snake_case)",
                finderTag: "Finder 태그",
                clearTags: "태그 지우기",
                tagRed: "빨강",
                tagOrange: "주황",
                tagYellow: "노랑",
                tagGreen: "초록",
                tagBlue: "파랑",
                tagPurple: "보라",
                tagGray: "회색",
                quickLook: "훑어보기",
                quickLookSpace: "훑어보기 (Space)",
                quickActions: "빠른 동작"
            )
        case .uk:
            return ShelfMenuStrings(
                pasteFromClipboard: "Вставити з буфера обміну",
                pasteFromClipboardShortcut: "Вставити з буфера обміну (⌘V)",
                compressToZip: "Стиснути в ZIP",
                convertImage: "Конвертувати зображення",
                stripExif: "Очистити метадані (EXIF)",
                recognizeOCR: "Розпізнати текст (OCR)",
                stitchImages: "З\u{2019}єднати зображення",
                vertically: "Вертикально",
                horizontally: "Горизонтально",
                renameNumber: "Пронумерувати (File_1, File_2…)",
                renameSnakeCase: "Веб-формат (snake_case)",
                finderTag: "Тег Finder",
                clearTags: "Очистити теги",
                tagRed: "Червоний",
                tagOrange: "Помаранчевий",
                tagYellow: "Жовтий",
                tagGreen: "Зелений",
                tagBlue: "Синій",
                tagPurple: "Фіолетовий",
                tagGray: "Сірий",
                quickLook: "Швидкий перегляд",
                quickLookSpace: "Швидкий перегляд (Пробіл)",
                quickActions: "Швидкі дії"
            )
        case .zhHans:
            return ShelfMenuStrings(
                pasteFromClipboard: "从剪贴板粘贴",
                pasteFromClipboardShortcut: "从剪贴板粘贴 (⌘V)",
                compressToZip: "压缩为 ZIP",
                convertImage: "转换图像",
                stripExif: "清除 EXIF 元数据",
                recognizeOCR: "识别文本 (OCR)",
                stitchImages: "拼接图像",
                vertically: "纵向拼接",
                horizontally: "横向拼接",
                renameNumber: "按序号命名 (File_1, File_2…)",
                renameSnakeCase: "网页命名 (snake_case)",
                finderTag: "访达标签",
                clearTags: "清除标签",
                tagRed: "红色",
                tagOrange: "橙色",
                tagYellow: "黄色",
                tagGreen: "绿色",
                tagBlue: "蓝色",
                tagPurple: "紫色",
                tagGray: "灰色",
                quickLook: "快速查看",
                quickLookSpace: "快速查看 (空格键)",
                quickActions: "快速操作"
            )
        case .zhTW:
            return ShelfMenuStrings(
                pasteFromClipboard: "從剪貼簿貼上",
                pasteFromClipboardShortcut: "從剪貼簿貼上 (⌘V)",
                compressToZip: "壓縮為 ZIP",
                convertImage: "轉換影像",
                stripExif: "清除 EXIF 中繼資料",
                recognizeOCR: "辨識文字 (OCR)",
                stitchImages: "拼接影像",
                vertically: "垂直拼接",
                horizontally: "水平拼接",
                renameNumber: "依序編號 (File_1, File_2…)",
                renameSnakeCase: "網頁命名 (snake_case)",
                finderTag: "Finder 標籤",
                clearTags: "清除標籤",
                tagRed: "紅色",
                tagOrange: "橙色",
                tagYellow: "黃色",
                tagGreen: "綠色",
                tagBlue: "藍色",
                tagPurple: "紫色",
                tagGray: "灰色",
                quickLook: "快速查看",
                quickLookSpace: "快速查看 (空白鍵)",
                quickActions: "快速動作"
            )
        case .zhHK:
            return ShelfMenuStrings(
                pasteFromClipboard: "從剪貼簿貼上",
                pasteFromClipboardShortcut: "從剪貼簿貼上 (⌘V)",
                compressToZip: "壓縮為 ZIP",
                convertImage: "轉換影像",
                stripExif: "清除 EXIF 中繼資料",
                recognizeOCR: "辨識文字 (OCR)",
                stitchImages: "拼接影像",
                vertically: "垂直拼接",
                horizontally: "水平拼接",
                renameNumber: "順序編號 (File_1, File_2…)",
                renameSnakeCase: "網頁命名 (snake_case)",
                finderTag: "Finder 標籤",
                clearTags: "清除標籤",
                tagRed: "紅色",
                tagOrange: "橙色",
                tagYellow: "黃色",
                tagGreen: "綠色",
                tagBlue: "藍色",
                tagPurple: "紫色",
                tagGray: "灰色",
                quickLook: "快速查看",
                quickLookSpace: "快速查看 (空白鍵)",
                quickActions: "快速動作"
            )
        }
    }
}

/// Hosts the invisible view the system share sheet is anchored to. SwiftUI
/// creates and owns that view, so the button reaches whichever one is on
/// screen right now through the box below.
struct ShelfSharePickerAnchor: NSViewRepresentable {
    final class Anchor {
        fileprivate weak var view: NSView?
        private let presenter = ShelfSharePresenter()

        @discardableResult
        func present(_ urls: [URL], completion: ((Bool) -> Void)? = nil) -> Bool {
            guard let view else { return false }
            return presenter.present(for: urls, from: view, completion: completion)
        }
    }

    let anchor: Anchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}
