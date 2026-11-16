// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Spawns extra independent, ephemeral floating Drop Shelf windows (`OverlayPanel`)
/// with cascade offsets, always-on-top pinning, drag-in/drag-out, and cloud upload.
final class ShelfAdditionalInstanceController {
    static let shared = ShelfAdditionalInstanceController()

    private var windows: [ShelfAdditionalInstanceWindow] = []
    private var nextInstanceNumber = 1

    private init() {}

    func openNewShelf(seededWith items: [ShelfItem] = []) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.openNewShelf(seededWith: items)
            }
            return
        }

        let store = ShelfAdditionalInstanceStore(instanceNumber: nextInstanceNumber, initialItems: items)
        nextInstanceNumber += 1

        let window = ShelfAdditionalInstanceWindow(store: store) { [weak self] closedWindow in
            self?.remove(closedWindow)
        }

        let visible = NSScreen.pointerVisibleFrame
        let cascadeIndex = windows.count % 6
        let step: CGFloat = 28
        let baseX = visible.midX - 152 + CGFloat(cascadeIndex) * step
        let baseY = visible.midY - 140 - CGFloat(cascadeIndex) * step
        let frame = window.frame
        let clampedX = min(max(visible.minX + 8, baseX), max(visible.minX + 8, visible.maxX - frame.width - 8))
        let clampedY = min(max(visible.minY + 8, baseY), max(visible.minY + 8, visible.maxY - frame.height - 8))
        window.setFrameOrigin(CGPoint(x: clampedX.rounded(), y: clampedY.rounded()))

        windows.append(window)
        window.orderFrontRegardless()
        VorssaintHaptics.generic()
    }

    func closeAll() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
    }

    private func remove(_ window: ShelfAdditionalInstanceWindow) {
        window.orderOut(nil)
        windows.removeAll { $0 === window }
    }
}

final class ShelfAdditionalInstanceWindow: OverlayPanel, NSDraggingDestination {
    private let store: ShelfAdditionalInstanceStore
    private let onClose: (ShelfAdditionalInstanceWindow) -> Void
    private var pinCancellable: AnyCancellable?

    fileprivate init(store: ShelfAdditionalInstanceStore,
         onClose: @escaping (ShelfAdditionalInstanceWindow) -> Void) {
        self.store = store
        self.onClose = onClose
        super.init(contentRect: CGRect(x: 0, y: 0, width: 304, height: 260),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        level = store.isPinned ? .floating : .normal
        isOpaque = false
        backgroundColor = .clear
        becomesKeyOnlyIfNeeded = true
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        registerForDraggedTypes(ShelfService.tileDropTypes)

        let rootView = ShelfAdditionalInstanceView(store: store) { [weak self] in
            guard let self else { return }
            self.onClose(self)
        }
        let host = NSHostingController(rootView: rootView)
        host.sizingOptions = .preferredContentSize
        contentViewController = host
        host.view.layoutSubtreeIfNeeded()
        setContentSize(host.view.fittingSize)

        pinCancellable = store.$isPinned.sink { [weak self] pinned in
            self?.level = pinned ? .floating : .normal
        }
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        if !store.selection.isEmpty {
            store.clearSelection()
        } else {
            onClose(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if Int(event.keyCode) == kVK_Escape {
            cancelOperation(nil)
        } else if Int(event.keyCode) == kVK_ANSI_V && flags.contains(.command) {
            store.pasteFromClipboard()
        } else if Int(event.keyCode) == kVK_ANSI_A && flags.contains(.command) {
            store.selectAll()
        } else {
            super.keyDown(with: event)
        }
    }

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let accepts = store.canAccept(pasteboard: sender.draggingPasteboard)
        store.isDropTargeted = accepts
        return accepts ? .copy : []
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        store.isDropTargeted = false
    }

    func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        draggingEntered(sender) != []
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { store.isDropTargeted = false }
        return store.accept(pasteboard: sender.draggingPasteboard)
    }

    func concludeDragOperation(_ sender: NSDraggingInfo?) {
        store.isDropTargeted = false
    }
}

private final class ShelfAdditionalInstanceStore: ObservableObject {
    let instanceNumber: Int

    @Published var items: [ShelfItem]
    @Published var selection: Set<UUID> = []
    @Published var isPinned: Bool = true
    @Published var isDropTargeted: Bool = false

    private let ephemeralDir: URL

    init(instanceNumber: Int, initialItems: [ShelfItem]) {
        self.instanceNumber = instanceNumber
        self.items = initialItems
        self.ephemeralDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VorssaintFloatingShelf-\(UUID().uuidString)", isDirectory: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: ephemeralDir)
    }

    var itemCount: Int {
        items.reduce(0) { $0 + $1.leafCount }
    }

    var hasFilesForActions: Bool {
        (selection.isEmpty ? items : selectedItems()).contains(where: \.holdsFile)
    }

    func selectedItems() -> [ShelfItem] {
        items.filter { selection.contains($0.id) }
    }

    func fileURLsForActions() -> [URL] {
        let candidates = selection.isEmpty ? items : selectedItems()
        return flattenFileURLs(in: candidates)
    }

    func fileURLsForActions(startingAt item: ShelfItem) -> [URL] {
        let candidates = selection.contains(item.id) ? selectedItems() : [item]
        return flattenFileURLs(in: candidates)
    }

    private func flattenFileURLs(in items: [ShelfItem]) -> [URL] {
        var urls: [URL] = []
        for item in items {
            switch item.payload {
            case .file(let url):
                if FileManager.default.fileExists(atPath: url.path) {
                    urls.append(url)
                }
            case .batch(let children):
                urls.append(contentsOf: flattenFileURLs(in: children))
            case .text, .link:
                continue
            }
        }
        return urls
    }

    func togglePin() {
        isPinned.toggle()
        VorssaintHaptics.generic()
    }

    func toggleSelection(_ id: UUID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    func selectAll() {
        selection = Set(items.map(\.id))
    }

    func clearSelection() {
        selection.removeAll()
    }

    func removeItem(_ id: UUID) {
        items.removeAll { $0.id == id }
        selection.remove(id)
    }

    func clear() {
        items.removeAll()
        selection.removeAll()
    }

    func canAccept(pasteboard: NSPasteboard) -> Bool {
        if !ShelfService.shared.fileURLs(from: pasteboard).isEmpty {
            return true
        }
        if NSImage(pasteboard: pasteboard) != nil {
            return true
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL],
           urls.contains(where: { !($0 as URL).isFileURL }) {
            return true
        }
        if let string = pasteboard.string(forType: .string),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return false
    }

    @discardableResult
    func pasteFromClipboard() -> Bool {
        let accepted = accept(pasteboard: .general)
        if accepted {
            VorssaintHaptics.generic()
        }
        return accepted
    }

    @discardableResult
    func accept(pasteboard: NSPasteboard) -> Bool {
        var added: [ShelfItem] = []

        let fileURLs = ShelfService.shared.fileURLs(from: pasteboard)
        if !fileURLs.isEmpty {
            for url in fileURLs {
                let isImage = UTType(filenameExtension: url.pathExtension.lowercased())?.conforms(to: .image) == true
                let fallbackIcon = NSWorkspace.shared.icon(forFile: url.path)
                let inlineThumbnail = isImage ? ImageThumbnailer.thumbnail(for: url, pointSize: 64) : nil
                let icon = inlineThumbnail
                    ?? ImageThumbnailer.thumbnail(for: fallbackIcon)
                    ?? fallbackIcon
                added.append(ShelfItem(payload: .file(url),
                                       title: url.lastPathComponent,
                                       icon: icon,
                                       isImage: isImage,
                                       hasContentThumbnail: inlineThumbnail != nil))
            }
        } else if let image = NSImage(pasteboard: pasteboard),
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let pngData = rep.representation(using: .png, properties: [:]) {
            PrivateFileStore.createDirectory(at: ephemeralDir)
            let target = ephemeralDir.appendingPathComponent("\(UUID().uuidString).png")
            if PrivateFileStore.write(pngData, to: target) {
                let icon = ImageThumbnailer.thumbnail(for: image, pointSize: 64) ?? image
                added.append(ShelfItem(payload: .file(target),
                                       title: L10n.shared.s.shelfItemImage,
                                       icon: icon,
                                       isImage: true,
                                       hasContentThumbnail: true))
            }
        } else if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL],
                  let url = urls.map({ $0 as URL }).first(where: { !$0.isFileURL }) {
            let icon = NSImage(systemSymbolName: "link", accessibilityDescription: nil) ?? NSImage()
            added.append(ShelfItem(payload: .link(url),
                                   title: url.host ?? url.absoluteString,
                                   icon: icon,
                                   isImage: false))
        } else if let text = pasteboard.string(forType: .string),
                  let bounded = ShelfPersistenceSupport.boundedLiveText(text) {
            let trimmed = bounded.trimmingCharacters(in: .whitespacesAndNewlines)
            let firstLine = trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? trimmed
            let icon = NSImage(systemSymbolName: "doc.plaintext", accessibilityDescription: nil) ?? NSImage()
            added.append(ShelfItem(payload: .text(bounded),
                                   title: String(firstLine.prefix(48)),
                                   icon: icon,
                                   isImage: false))
        }

        guard !added.isEmpty else { return false }
        items.append(contentsOf: added)
        VorssaintHaptics.generic()
        return true
    }

    func itemProvider(for item: ShelfItem) -> NSItemProvider {
        switch item.payload {
        case .file(let url):
            return NSItemProvider(object: url as NSURL)
        case .link(let url):
            return NSItemProvider(object: url as NSURL)
        case .text(let text):
            return NSItemProvider(object: text as NSString)
        case .batch(let children):
            if let first = children.first {
                return itemProvider(for: first)
            }
            return NSItemProvider(object: item.title as NSString)
        }
    }

    func uploadToCloud(url: URL) {
        Task {
            let payloadData = await Task.detached(priority: .userInitiated) {
                ShelfView.readCloudPayloadData(from: url)
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

private struct ShelfAdditionalInstanceView: View {
    @ObservedObject var store: ShelfAdditionalInstanceStore
    var onClose: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var cloudUpload = ScreenshotCloudUploadService.shared
    @State private var shareAnchor = ShelfSharePickerAnchor.Anchor()
    @State private var pasteHovered = false
    @State private var pinHovered = false
    @State private var clearHovered = false
    @State private var shareHovered = false
    @State private var actionsHovered = false

    private let gridColumns = [
        GridItem(.fixed(78), spacing: 10),
        GridItem(.fixed(78), spacing: 10),
        GridItem(.fixed(78), spacing: 10),
    ]

    private var v2Strings: OverhaulV2Strings {
        OverhaulV2Strings.localized(l10n.language)
    }

    private var shelfActionsStrings: ShelfActionStrings {
        OverhaulStrings.shelfActions(l10n.language)
    }

    private var menuText: ShelfMenuStrings {
        ShelfMenuStrings.localized(l10n.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header
            contentArea
            if !store.items.isEmpty {
                bottomBar
            }
        }
        .padding(14)
        .frame(width: 304)
        .background(HUDBackdrop(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(store.isDropTargeted ? Color.accentColor : Color.primary.opacity(0.14),
                              lineWidth: store.isDropTargeted ? 2 : 1)
        )
        .animation(.easeOut(duration: 0.15), value: store.isDropTargeted)
        .animation(.easeOut(duration: 0.18), value: store.items)
    }

    private var header: some View {
        HStack(spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: "tray.full")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("\(l10n.s.shelfTitle) #\(store.instanceNumber)")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !store.items.isEmpty {
                    Text("\(store.itemCount)")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.18)))
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .background(AdditionalShelfMoveHandle())

            Button {
                store.pasteFromClipboard()
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.primary.opacity(pasteHovered ? 0.14 : 0.08)))
                    .overlay(Circle().strokeBorder(Color.primary.opacity(pasteHovered ? 0.42 : 0.18), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .onHover { pasteHovered = $0 }
            .help(menuText.pasteFromClipboardShortcut)
            .accessibilityLabel(menuText.pasteFromClipboard)

            Button {
                store.togglePin()
            } label: {
                Image(systemName: store.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(
                        Circle().fill(store.isPinned
                                      ? Color.accentColor.opacity(pinHovered ? 0.30 : 0.20)
                                      : Color.primary.opacity(pinHovered ? 0.14 : 0.08))
                    )
                    .overlay(
                        Circle().strokeBorder(store.isPinned
                                              ? Color.accentColor.opacity(0.65)
                                              : Color.primary.opacity(pinHovered ? 0.42 : 0.18),
                                              lineWidth: 1)
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(store.isPinned ? Color.accentColor : Color.secondary)
            .onHover { pinHovered = $0 }
            .help(v2Strings.shelfAlwaysOnTop)
            .accessibilityLabel(v2Strings.shelfAlwaysOnTop)

            PanelCloseButton(label: l10n.s.menuClose, action: onClose)
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        if store.items.isEmpty {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(.secondary.opacity(0.4))
                .frame(height: 188)
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 21))
                            .foregroundStyle(.secondary)
                        Text(v2Strings.shelfEmptyDrop)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 12)
                    }
                )
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 10) {
                    ForEach(store.items) { item in
                        tileView(for: item)
                    }
                }
                .padding(4)
            }
            .frame(height: 188)
        }
    }

    private func tileView(for item: ShelfItem) -> some View {
        let selected = store.selection.contains(item.id)
        return VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 64, height: 50)
                    .overlay(
                        Image(nsImage: item.icon)
                            .resizable()
                            .scaledToFit()
                            .padding(item.hasContentThumbnail ? 4 : 10)
                    )
                Button {
                    store.removeItem(item.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .help(l10n.s.actionRemove)
            }
            Text(item.title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 72, height: 24, alignment: .top)
        }
        .frame(width: 78, height: 88)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.16) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if case .file(let url) = item.payload {
                NSWorkspace.shared.open(url)
            } else if case .link(let url) = item.payload {
                NSWorkspace.shared.open(url)
            }
        }
        .onTapGesture {
            store.toggleSelection(item.id)
        }
        .onDrag {
            store.itemProvider(for: item)
        }
        .contextMenu {
            let urls = store.fileURLsForActions(startingAt: item)
            if let first = urls.first {
                Button(l10n.s.shelfActionOpen) {
                    urls.forEach { NSWorkspace.shared.open($0) }
                }
                Button(menuText.quickLook) {
                    ShelfQuickLookCoordinator.shared.toggle(urls: urls)
                }
                Button(v2Strings.shelfRevealOriginal) {
                    NSWorkspace.shared.activateFileViewerSelecting(urls)
                }
                Button(v2Strings.shelfCopyURL) {
                    ShelfActionsEngine.copyFilePaths(urls: urls)
                }
                if cloudUpload.isConfigured {
                    Button(v2Strings.shelfUploadCloud) {
                        store.uploadToCloud(url: first)
                    }
                }
                Divider()
            }
            Button(l10n.s.actionRemove, role: .destructive) {
                store.removeItem(item.id)
            }
        }
    }

    private var bottomBar: some View {
        let enabled = store.hasFilesForActions
        let urls = store.fileURLsForActions()
        return HStack(spacing: 6) {
            Text(l10n.s.shelfHint)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 6)

            Menu {
                if cloudUpload.isConfigured, let uploadTarget = urls.first {
                    Button {
                        store.uploadToCloud(url: uploadTarget)
                    } label: {
                        Label(v2Strings.shelfUploadCloud, systemImage: "icloud.and.arrow.up")
                    }
                }
                Button {
                    ShelfActionsEngine.compressToZip(urls: urls, addToShelf: false)
                } label: {
                    Label(menuText.compressToZip, systemImage: "archivebox")
                }
                if urls.count > 1 || urls.contains(where: { $0.pathExtension.lowercased() == "pdf" }) {
                    Button {
                        ShelfActionsEngine.mergeToPDF(urls: urls, addToShelf: false)
                    } label: {
                        Label(shelfActionsStrings.mergePDF, systemImage: "doc.on.doc.fill")
                    }
                }
                Button {
                    ShelfActionsEngine.copyFilePaths(urls: urls)
                } label: {
                    Label(v2Strings.shelfCopyURL, systemImage: "doc.on.doc")
                }
                Divider()
                Button {
                    ShelfQuickLookCoordinator.shared.toggle(urls: urls)
                } label: {
                    Label(menuText.quickLookSpace, systemImage: "eye")
                }
            } label: {
                footerFace(systemImage: "wand.and.stars", tint: .purple, hovered: actionsHovered && enabled)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(actionsHovered ? Color.purple : Color.secondary)
            .opacity(enabled ? 1 : 0.4)
            .onHover { actionsHovered = $0 }
            .disabled(!enabled)
            .help(menuText.quickActions)

            Button {
                guard !urls.isEmpty else { return }
                shareAnchor.present(urls)
            } label: {
                footerFace(systemImage: "square.and.arrow.up", tint: .accentColor, hovered: shareHovered && enabled)
                    .background(ShelfSharePickerAnchor(anchor: shareAnchor))
            }
            .buttonStyle(.plain)
            .foregroundStyle(shareHovered && enabled ? Color.accentColor : Color.secondary)
            .opacity(enabled ? 1 : 0.4)
            .onHover { shareHovered = $0 }
            .disabled(!enabled)
            .help(l10n.s.shelfActionShare)

            Button {
                if store.selection.isEmpty {
                    store.clear()
                } else {
                    for id in store.selection { store.removeItem(id) }
                }
            } label: {
                footerFace(systemImage: store.selection.isEmpty ? "trash" : "trash.fill",
                           tint: .red,
                           hovered: clearHovered)
            }
            .buttonStyle(.plain)
            .foregroundStyle(clearHovered ? Color.red.opacity(0.82) : Color.secondary)
            .onHover { clearHovered = $0 }
            .help(store.selection.isEmpty ? v2Strings.shelfClearAll : l10n.s.shelfRemoveSelected)
        }
        .frame(minHeight: 30)
    }

    private func footerFace(systemImage: String, tint: Color, hovered: Bool) -> some View {
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
}

private struct AdditionalShelfMoveHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> MoveHandleView { MoveHandleView() }
    func updateNSView(_ nsView: MoveHandleView, context: Context) {}

    final class MoveHandleView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
