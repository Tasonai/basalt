// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The command bar's face: one field, one list. Reads top to bottom with no
/// chrome to learn; every row is icon, name in plain words, where it lives,
/// and its shortcut so the bar teaches the faster way while being used.
struct CommandBarView: View {
    /// Short enough to sit on one line, chosen to show three different things
    /// the bar can do that a list of commands would never reveal.
    ///
    /// The battery one is the localized word, because that is the word the
    /// answer is titled with. As a fixed English "battery" the chip matched
    /// nothing in the other twelve languages and led to an empty list, which
    /// teaches the opposite of what an example is for. The other three hold
    /// everywhere: the maths is language-free, the conversion parser already
    /// takes each language's own word for "to", and the emoji names come from
    /// Unicode, which spells them in English on purpose.
    static func examples(_ text: CommandBarFeatureStrings) -> [String] {
        var examples = ["100 km to mi", "2+2*3"]
        if PowerSampler.hasInternalBattery {
            examples.append(text.answerBatteryLabel.lowercased())
        }
        examples.append("fire")
        return examples
    }
    /// As tall as the list is ever allowed to be, so the panel never grows
    /// past what a laptop screen can show above the fold.
    static let listCeiling: CGFloat = 452
    static let width: CGFloat = 560
    /// The field alone, as the compact bar shows it.
    static let fieldHeight: CGFloat = 50
    private static let homeChipID = "category.all"

    /// Where this copy is drawn: the island's own, or the bar's window, which
    /// follows how the bar was presented.
    var presentation: CommandBarPresentation? = nil

    @ObservedObject private var service = CommandBarService.shared
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var uninstaller = AppUninstaller.shared
    @ObservedObject private var homebrew = HomebrewManager.shared
    @ObservedObject private var quickAI = CommandBarQuickAIService.shared
    @AppStorage(DefaultsKey.commandBarLayoutMode) private var layoutModeRaw = CommandBarLayoutMode.list.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var searchFocused: Bool
    @State private var showHomebrewDetails = false
    @State private var showQuickAICard = false
    @State private var attachedContextTokens: Set<QuickAIContextToken> = []
    @State private var quickAICopied = false
    @State private var quickAIPromptDraft = ""
    @State private var showActionPanelOverlay = false
    @State private var actionPanelIndex = 0
    @State private var actionPanelTransformOutput: String?
    @State private var scriptArgInputs: [String] = ["", "", ""]
    @State private var scriptArgLinkID: UUID?
    @State private var detectedCLITools: [QuickAIProvider] = []
    @FocusState private var actionPanelFocused: Bool

    private var wave3Strings: OverhaulWave3Strings { OverhaulStrings.wave3(l10n.language) }
    private var v2Strings: OverhaulV2Strings { OverhaulV2Strings.localized(l10n.language) }

    private var layoutMode: CommandBarLayoutMode {
        CommandBarLayoutMode(rawValue: layoutModeRaw) ?? .list
    }

    private var effectiveWidth: CGFloat {
        if shownAs == .island { return Self.width }
        return layoutMode == .splitDetail ? 680 : Self.width
    }

    /// The mark, made a handle. Dragging rides on AppKit's own window
    /// dragging — the same machinery a title bar uses — rather than a
    /// SwiftUI gesture, whose translation is read in a coordinate space
    /// that moves with the window and jitters under its own feet.
    private struct DragHandle: NSViewRepresentable {
        func makeNSView(context: Context) -> HandleView { HandleView() }
        func updateNSView(_ view: HandleView, context: Context) {}

        final class HandleView: NSView {
            private var moveObserver: NSObjectProtocol?
            private var saveTask: DispatchWorkItem?

            deinit {
                saveTask?.cancel()
                if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
            }

            override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

            override func resetCursorRects() {
                // Cursor rects, not a pushed NSCursor: the system hands the
                // arrow back on its own the moment the pointer leaves, even
                // if the bar hides mid-hover.
                addCursorRect(bounds, cursor: .openHand)
            }

            override func mouseDown(with event: NSEvent) {
                if event.clickCount == 2 {
                    CommandBarService.shared.resetPanelPosition()
                    return
                }
                guard let window else { return }
                NSCursor.closedHand.set()
                observeMovement(of: window)
                window.performDrag(with: event)
                scheduleSave()
                NSCursor.openHand.set()
            }

            private func observeMovement(of window: NSWindow) {
                saveTask?.cancel()
                if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
                moveObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didMoveNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.scheduleSave()
                }
            }

            private func scheduleSave() {
                saveTask?.cancel()
                let task = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
                    moveObserver = nil
                    saveTask = nil
                    CommandBarService.shared.finishPanelDrag()
                }
                saveTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: task)
            }
        }
    }

    private var markTint: Color {
        colorScheme == .light ? Color(white: 0.03) : .white
    }

    private var text: CommandBarFeatureStrings { FeatureStrings.commandBar(l10n.language) }

    private var shownAs: CommandBarPresentation { presentation ?? service.presentation }

    /// Out of the island the bar is the island's: black, or the open island's
    /// own surface, and dark like it.
    @ViewBuilder private var backdrop: some View {
        switch shownAs {
        case .window: HUDBackdrop(cornerRadius: 22, contrast: .high)
        case .droplet: RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black)
        case .island: Color.clear
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if let warning = service.uninstallWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 17)
                    .padding(.bottom, 12)
            }
            switch service.mode {
            case .search:
                if showsCategoryChips {
                    Divider()
                    categoryChipsRow
                }
                if service.rows.isEmpty {
                    // A category with nothing in it needs the same way out a
                    // fruitless search gets, or the panel is a room with no
                    // door in it.
                    if !trimmedQuery.isEmpty || service.activeCategory != nil {
                        Divider()
                        emptyState
                    }
                } else {
                    if !showsCategoryChips { Divider() }
                    if showActionPanelOverlay, let selected = service.selectedEntry {
                        commandBarActionPanelCard(for: selected)
                    } else {
                        switch layoutMode {
                        case .list:
                            resultsList
                        case .splitDetail:
                            splitDetailResultsView
                        case .grid:
                            gridResultsView
                        }
                    }
                }
            case .argument(let entryID):
                Divider()
                argumentCard(entryID: entryID)
            case .confirm(let entryID):
                Divider()
                confirmCard(entryID: entryID)
            case .uninstallReview:
                Divider()
                uninstallReviewCard
            case .uninstallHomebrewConfirm:
                Divider()
                uninstallHomebrewConfirmCard
            case .actions:
                Divider()
                actionsList
            case .naming(let entryID):
                Divider()
                namingCard(entryID: entryID)
            case .capturingShortcut(let entryID):
                Divider()
                shortcutCard(entryID: entryID)
            }
            if showQuickAICard || quickAI.isStreaming || !quickAI.responseText.isEmpty || quickAI.errorText != nil {
                Divider()
                quickAICard
            }
            // A footer under a bare field reads as a second row of chrome on
            // something meant to be one strip.
            if !service.isCompactHome {
                Divider()
                footer
            }
        }
        .frame(width: effectiveWidth)
        .environment(\.colorScheme, shownAs == .window ? colorScheme : .dark)
        .background(backdrop)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            if shownAs == .window {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
        }
        .onAppear {
            focusSearch()
            service.barDidAppear()
            detectedCLITools = CommandBarQuickAIService.installedCLITools()
        }
        .onChange(of: service.presentationID) { _, _ in
            showActionPanelOverlay = false
            actionPanelTransformOutput = nil
            quickAICopied = false
            detectedCLIsRefresh()
            focusSearch()
        }
        .onChange(of: service.mode) { _, _ in
            showActionPanelOverlay = false
            focusSearch()
        }
        .onChange(of: layoutModeRaw) { _, _ in
            service.refreshPanelLayout()
        }
        .onChange(of: service.selectedEntry?.id) { _, _ in
            actionPanelTransformOutput = nil
            syncScriptArgInputsForSelection()
        }
        // Typing as the drop still falls hurries it, so the bar shows what
        // is being typed right away.
        .onChange(of: service.query) { _, query in
            if !query.isEmpty, service.presentation == .droplet { CommandBarDroplet.shared.hurry() }
        }
    }

    /// Only the copy on screen asks for the keyboard: a hidden copy taking it
    /// would hand its own empty text back to the search.
    private var isShown: Bool {
        presentation == .island ? service.presentation == .island : service.presentation != .island
    }

    private func focusSearch() {
        DispatchQueue.main.async { if isShown { searchFocused = true } }
    }

    // MARK: - Field

    private var searchBar: some View {
        HStack(spacing: 10) {
            // The mark leads the field, the same face the quick panel and the
            // radial menu wear; modes speak through the chip and the cards.
            // Both axes are pinned: the panel re-fits on every keystroke and
            // a mark left to follow the proposed height shrinks or vanishes
            // mid-layout. It is also the handle that carries the bar to
            // wherever the hand wants it; a double-click brings it home.
            if shownAs == .window {
                BrandMark(width: 22, tint: markTint)
                    .opacity(0.85)
                    .frame(width: 22, height: 22)
                    .allowsHitTesting(false)
                    .overlay(
                        DragHandle()
                            .help(text.dragHint)
                    )
            } else {
                // Out of the island, the companion is the bar's face, and the
                // bar stays where the island put it.
                CommandBarMascot(service: service)
                    .frame(width: 22, height: 22)
            }
            if case .naming(let entryID) = service.mode,
               let entry = service.entry(withID: entryID) {
                Text(entry.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
            }
            if case .argument(let entryID) = service.mode,
               let entry = service.entry(withID: entryID) {
                Text(entry.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
            }
            TextField(fieldPlaceholder, text: $service.query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($searchFocused)
                .disableAutocorrection(true)
                .accessibilityLabel(text.pageTitle)
            if service.isCompactHome { compactHints }
            Button {
                let prompt = service.query.trimmingCharacters(in: .whitespacesAndNewlines)
                if prompt.isEmpty {
                    showQuickAICard.toggle()
                    if showQuickAICard { detectedCLIsRefresh() }
                } else {
                    showQuickAICard = true
                    detectedCLIsRefresh()
                    sendQuickAIPrompt(prompt)
                }
            } label: {
                Image(systemName: quickAI.isStreaming ? "ellipsis.bubble.fill" : "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(showQuickAICard || quickAI.isStreaming ? Color.accentColor : Color.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(wave3Strings.quickAITitle)
            Menu {
                ForEach(CommandBarLayoutMode.allCases, id: \.self) { mode in
                    Button {
                        layoutModeRaw = mode.rawValue
                    } label: {
                        HStack {
                            Text(layoutModeTitle(mode))
                            if layoutMode == mode { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                Image(systemName: layoutMode == .grid ? "square.grid.2x2" : (layoutMode == .splitDetail ? "sidebar.right" : "list.bullet"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            if !service.query.isEmpty {
                CommandBarClearButton {
                    service.query = ""
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    /// The collapsed bar has no footer, so the keys that still work (↓ to
    /// peek, Esc to close) say so inline instead, in the footer's own glyphs.
    private var compactHints: some View {
        HStack(spacing: 4) {
            Text("↓")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
            Text(text.suggestionsLabel)
                .font(.system(size: 10))
            Text("Esc")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.leading, 4)
        }
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
    }

    /// Everything that can be done to the selected row, in the same list
    /// shape as the results so there is nothing new to learn.
    private var actionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(text.actionsTitle.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("↑↓ ⏎ Esc")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)

            if case .actions(let entryID) = service.mode,
               let entry = service.entry(withID: entryID) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(actionPanelItems(for: entry)) { item in
                            Button {
                                executeActionPanelItem(item, for: entry)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: item.symbolName)
                                        .font(.system(size: 10, weight: .semibold))
                                    Text(item.title)
                                        .font(.system(size: 10.5, weight: .medium))
                                        .lineLimit(1)
                                    Text(item.shortcutDisplay)
                                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                                .foregroundStyle(item.isDestructive ? Color.red : Color.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(item.isDestructive
                                              ? Color.red.opacity(0.10)
                                              : Color.primary.opacity(0.07))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 6)
                if let transformed = actionPanelTransformOutput {
                    transformOutputBanner(transformed)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }
            }

            VStack(spacing: 1) {
                ForEach(Array(service.actionRows.enumerated()), id: \.element.id) { index, action in
                    Button {
                        service.runAction(action)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: action.symbolName)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(action.isDestructive
                                                 ? Color.red : Color.primary.opacity(0.85))
                                .frame(width: 30, height: 30)
                            Text(action.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(action.isDestructive ? Color.red : Color.primary)
                            Spacer(minLength: 12)
                            if let shortcutHint = actionShortcutDisplay(for: action.id) {
                                Text(shortcutHint)
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .fill(Color.primary.opacity(0.06))
                                    )
                            }
                            Image(systemName: "return")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .opacity(index == service.actionIndex ? 1 : 0)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(index == service.actionIndex
                                      ? (action.isDestructive
                                         ? Color.red.opacity(0.12)
                                         : Color.accentColor.opacity(0.14))
                                      : .clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }

    /// Naming a row: the field becomes the name, and says so when the name is
    /// already taken instead of quietly stealing it.
    private func namingCard(entryID: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let entry = service.entry(withID: entryID) {
                HStack(spacing: 10) {
                    iconView(entry)
                    Text(entry.title)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 17)
                .padding(.top, 12)
            }
            Text(service.aliasWarning ?? text.argumentHint)
                .font(.system(size: 10.5))
                .foregroundStyle(service.aliasWarning == nil
                                 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.orange))
                .padding(.horizontal, 17)
                .padding(.bottom, 12)
        }
    }

    /// Listening for the combination one row should answer to. The card says
    /// so plainly, because a field that silently swallows every key is the
    /// most confusing thing a panel can do.
    private func shortcutCard(entryID: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let entry = service.entry(withID: entryID) {
                HStack(spacing: 10) {
                    iconView(entry)
                    Text(entry.title)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    if let existing = service.rowShortcut(for: entry) {
                        Text(existing.displayString)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                    }
                }
                .padding(.horizontal, 17)
                .padding(.top, 12)
            }
            Text(service.aliasWarning ?? text.shortcutCaptureHint)
                .font(.system(size: 10.5))
                .foregroundStyle(service.aliasWarning == nil
                                 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.orange))
                .padding(.horizontal, 17)
                .padding(.bottom, 12)
        }
    }

    private var fieldPlaceholder: String {
        if case .argument(let entryID) = service.mode,
           let range = service.entry(withID: entryID)?.numericRange {
            return String(format: text.argumentRangeFormat, range.lowerBound, range.upperBound)
        }
        if case .naming = service.mode { return text.aliasPlaceholder }
        return text.searchPlaceholder
    }

    // MARK: - Results

    private var trimmedQuery: String {
        service.query.trimmingCharacters(in: .whitespaces)
    }

    /// The chips stay up while a category is on, typing or not: a filter the
    /// person cannot see is a filter they will blame the bar for.
    private var showsCategoryChips: Bool {
        !service.categoryChips.isEmpty
            && (service.isShowingSuggestions || service.activeCategory != nil)
    }

    /// The categories, one tap deep: the same drill-in the launchers people
    /// know. "All" is home; Esc always walks back to it.
    private var categoryChipsRow: some View {
        ScrollViewReader { chips in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    categoryChip(nil, label: text.categoryAll)
                        .id(Self.homeChipID)
                    ForEach(service.categoryChips, id: \.self) { source in
                        categoryChip(source, label: service.categoryTitle(source))
                            .id(source.rawValue)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
            }
            .onChange(of: service.activeCategory) { _, category in
                // The arrow keys can walk past the edge of the row.
                withAnimation(.easeOut(duration: 0.12)) {
                    chips.scrollTo(category?.rawValue ?? Self.homeChipID)
                }
            }
        }
    }

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if service.isShowingSuggestions, service.activeCategory == nil {
                // A list of commands never says the bar can add up, convert or
                // reach into another app's menus. Examples do, and clicking
                // one fills the field so it can be tried on the spot.
                HStack(spacing: 5) {
                    Text(text.tryTheseLabel)
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.tertiary)
                    ForEach(CommandBarView.examples(text), id: \.self) { example in
                        Button {
                            service.query = example
                        } label: {
                            Text(example)
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            ScrollViewReader { proxy in
                // The bar shows more than fits when nothing is typed, and a
                // list with no scrollbar looks like a list that ends there.
                ScrollView(showsIndicators: service.rows.count > 14) {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(service.rows.enumerated()), id: \.element.id) { index, entry in
                            // Every heading lives in the list, directly above
                            // the rows it names.
                            if let heading = service.sectionTitles[index] {
                                sectionHeader(heading)
                            }
                            row(entry, index: index)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                // A short list makes the panel exactly as tall as it needs to
                // be. A long one is pinned to its ceiling instead: asking the
                // layout for the ideal height of a hundred rows would measure
                // every one of them and throw the laziness away.
                .frame(maxHeight: Self.listCeiling)
                .fixedSize(horizontal: false, vertical: service.rows.count <= 14)
                .frame(minHeight: service.rows.count > 14 ? Self.listCeiling : nil)
                .notchScrollEdgeFade(axis: .vertical, length: 14)
                .onChange(of: service.selectedIndex) { _, index in
                    guard service.rows.indices.contains(index) else { return }
                    proxy.scrollTo(service.rows[index].id)
                }
            }
        }
    }

    private func categoryChip(_ source: CommandBarSource?, label: String) -> some View {
        CommandBarCategoryChip(source: source,
                               label: label,
                               isActive: service.activeCategory == source) {
            service.setCategory(source)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 3)
    }

    private func row(_ entry: CommandBarEntry, index: Int) -> some View {
        let isSelected = index == service.selectedIndex
        return Button {
            // By identity, not by position: a background load can rebuild the
            // list between the click and this call.
            service.run(entry, fromClick: true)
        } label: {
            HStack(spacing: 10) {
                iconView(entry)
                VStack(alignment: .leading, spacing: 1.5) {
                    titleView(entry)
                    subtitleView(entry)
                }
                Spacer(minLength: 12)
                if service.commandIsHeld, index < 9 {
                    // Holding Command turns the list into nine numbered rows.
                    Text("⌘\(index + 1)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                        )
                } else if let value = entry.answerValue {
                    Text(value)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                        .monospacedDigit()
                } else if let shortcut = service.rowShortcut(for: entry)?.displayString
                            ?? entry.shortcut?.displayString ?? entry.menuShortcut {
                    Text(shortcut)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                }
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    // Always laid out, only drawn on the selected row: without
                    // the reserved width every row shifted as the selection
                    // moved.
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, entry.isAnswer ? 9 : 7)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { service.selectFromHover(index) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(entry))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Everything the eye gets from a row, said in words: the name, where it
    /// lives, its value or shortcut, and the states that are only a colour.
    private func accessibilityLabel(_ entry: CommandBarEntry) -> String {
        var parts = [entry.title, entry.subtitle]
        if let value = entry.answerValue { parts.append(value) }
        if let shortcut = service.rowShortcut(for: entry)?.displayString
            ?? entry.shortcut?.displayString ?? entry.menuShortcut { parts.append(shortcut) }
        if entry.isActive { parts.append(text.stateOn) }
        if service.isPinned(entry) { parts.append(text.pinnedTitle) }
        switch entry.trouble {
        case .needsSetup(let feature, _): parts.append(String(format: text.needsSetupFormat, feature))
        case .needsPermission: parts.append(text.needsPermissionHint)
        case nil: break
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// The title with the letters that actually matched in accent, so the row
    /// shows why it is here. The calculator's result gets the loud treatment.
    @ViewBuilder
    private func titleView(_ entry: CommandBarEntry) -> some View {
        if entry.isAnswer {
            let font = Font.system(size: 17, weight: .semibold, design: .rounded)
            Text(entry.title)
                // Tabular digits keep a sum steady while typing; in a color
                // value they leave gaps between letters and digits.
                .font(entry.isColor ? font : font.monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            let offsets = service.highlightOffsets(for: entry)
            if offsets.isEmpty {
                Text(entry.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(entry.title)
            } else {
                Text(highlighted(entry.title, offsets: offsets))
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private func highlighted(_ title: String, offsets: Set<Int>) -> AttributedString {
        var result = AttributedString()
        for (index, character) in title.enumerated() {
            var piece = AttributedString(String(character))
            if offsets.contains(index) {
                piece.foregroundColor = Color.accentColor
                piece.font = .system(size: 13, weight: .bold)
            } else {
                piece.foregroundColor = .primary
            }
            result.append(piece)
        }
        return result
    }

    @ViewBuilder
    private func subtitleView(_ entry: CommandBarEntry) -> some View {
        switch entry.trouble {
        case .needsSetup(let featureTitle, _):
            Text(String(format: text.needsSetupFormat, featureTitle))
                .font(.system(size: 10.5))
                .foregroundStyle(.orange)
                .lineLimit(1)
        case .needsPermission:
            Text(text.needsPermissionHint)
                .font(.system(size: 10.5))
                .foregroundStyle(.orange)
                .lineLimit(1)
        case nil:
            // A row under a heading that already names its area carries no
            // caption at all, which makes the browse list read as one column
            // of names instead of a wall of repetition.
            if !entry.subtitle.isEmpty {
                Text(entry.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func iconView(_ entry: CommandBarEntry) -> some View {
        ZStack(alignment: .topTrailing) {
            // An app or file icon already has its own shape and padding, so a
            // plate behind it reads as a second frame; only glyphs get one.
            if entry.usesPlateIcon {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(entry.isActive ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06))
                    .frame(width: 30, height: 30)
                    .overlay(iconContent(entry))
            } else {
                iconContent(entry)
                    .frame(width: 30, height: 30)
            }
            if entry.isActive {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                    // A ring keeps the dot legible on top of a colorful icon.
                    .overlay(
                        Circle().strokeBorder(
                            (shownAs != .window || colorScheme == .dark)
                                ? Color.black.opacity(0.88)
                                : Color.white.opacity(0.92),
                            lineWidth: 1.2
                        )
                    )
                    .offset(x: 2.5, y: -2.5)
            }
        }
    }

    @ViewBuilder
    private func iconContent(_ entry: CommandBarEntry) -> some View {
        switch entry.icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(entry.isActive ? Color.accentColor : Color.primary.opacity(0.85))
        case .appIcon(let path):
            Image(nsImage: CommandBarIconCache.icon(forPath: path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
        case .clipboardImage(let name):
            ClipboardThumbnailImage(source: .stored(name: name), contentMode: .fill)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        case .filePath(let path):
            Image(nsImage: CommandBarIconCache.icon(forPath: path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
        case .color(let color):
            ColorSwatch(color: color, size: 22)
        }
    }

    // MARK: - Empty, argument and confirm states

    private var emptyState: some View {
        VStack(spacing: 9) {
            BrandMark(width: 26, tint: markTint)
                .opacity(0.3)
                .frame(width: 26, height: 26)
                .padding(.bottom, 2)
            Text(text.noResultsTitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button {
                    service.goHome()
                } label: {
                    Text(text.noResultsAction)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                }
                .buttonStyle(.plain)

                if !trimmedQuery.isEmpty {
                    Button {
                        showQuickAICard = true
                        detectedCLIsRefresh()
                        sendQuickAIPrompt(trimmedQuery)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10, weight: .semibold))
                            Text(wave3Strings.quickAITitle)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(SemanticCategoryTone.dynamicIsland.badgeColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(SemanticCategoryTone.dynamicIsland.badgeColor.opacity(0.16)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func argumentCard(entryID: String) -> some View {
        VStack(spacing: 4) {
            if let entry = service.entry(withID: entryID) {
                HStack(spacing: 10) {
                    iconView(entry)
                    Text(entry.title)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 17)
                .padding(.top, 12)
            }
            Text(text.argumentHint)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 17)
                .padding(.bottom, 12)
        }
    }

    private func confirmCard(entryID: String) -> some View {
        VStack(spacing: 6) {
            if let entry = service.entry(withID: entryID) {
                HStack(spacing: 10) {
                    iconView(entry)
                    VStack(alignment: .leading, spacing: 1.5) {
                        Text(entry.confirmationPrompt ?? entry.title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(text.confirmHint)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    // Someone who opened the bar with the mouse has to be able
                    // to finish with the mouse.
                    Button(l10n.s.uninstallerCancel) { service.stepBack() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button(text.confirmButton) {
                        service.runSelected()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.red.opacity(0.09))
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Uninstall review

    /// The full leftover-files checklist, in place for `.uninstallReview` -
    /// the same categories, sizes and per-item toggles `UninstallerView`
    /// shows in Settings, just inline in the bar. Homebrew-managed apps are
    /// handled here too, not handed off to Settings: `.uninstallHomebrewConfirm`
    /// guards the extra confirmation `brew uninstall` needs, and
    /// `HomebrewOperationStatusView` renders its live progress inline.
    @ViewBuilder
    private var uninstallReviewCard: some View {
        switch uninstaller.phase {
        case .empty:
            VStack(spacing: 12) {
                Text(l10n.s.uninstallerSelectionUnavailable)
                    .foregroundStyle(.secondary)
                Button(l10n.s.uninstallerCancel) { service.stepBack() }
            }
            .padding(20)
        case .scanning:
            uninstallReviewBusy(l10n.s.uninstallerScanning)
        case .results:
            uninstallReviewChecklist
        case .removing:
            uninstallReviewBusy(l10n.s.uninstallerRemoving)
        case let .done(freed, failed):
            uninstallReviewDone(freed: freed, failed: failed)
        }
    }

    private func uninstallReviewBusy(_ message: String) -> some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let target = uninstaller.target {
                HStack(spacing: 7) {
                    Image(nsImage: target.icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text(target.name)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private var uninstallReviewChecklist: some View {
        VStack(alignment: .leading, spacing: 8) {
            uninstallReviewHeader
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(AppUninstaller.Category.allCases, id: \.self) { category in
                        let group = uninstaller.items.filter { $0.category == category }
                        if !group.isEmpty {
                            uninstallCategoryGroup(group, category: category)
                        }
                    }
                }
                .padding(.horizontal, 17)
            }
            .frame(maxHeight: Self.listCeiling - 90)
            .notchScrollEdgeFade(axis: .vertical, length: 12)
            Divider().padding(.horizontal, 17)
            uninstallHomebrewStatus
            uninstallReviewFooter
        }
        .padding(.vertical, 12)
    }

    /// Live progress for a Homebrew-managed app's removal, shown inline once
    /// confirmed - the same view the menu panel already shows in its own
    /// small floating window, so nothing here is rebuilt from scratch.
    @ViewBuilder
    private var uninstallHomebrewStatus: some View {
        if uninstaller.homebrewCheckFailed {
            UninstallerHomebrewFailureNote(onRetry: uninstaller.retryHomebrewCheck)
                .padding(.horizontal, 17)
        } else if let package = uninstaller.selectedHomebrewPackage {
            if let status = homebrew.operationStatus,
               status.action == .uninstall,
               status.package?.id == package.id {
                HomebrewOperationStatusView(status: status,
                                            log: homebrew.log,
                                            terminalFallbackCommand: homebrew.terminalFallbackCommand,
                                            compact: true,
                                            showDetails: $showHomebrewDetails,
                                            onCancel: homebrew.cancelOperation,
                                            onClear: homebrew.clearLog,
                                            onOpenTerminal: homebrew.openTerminalFallback)
                    .padding(.horizontal, 17)
                if let tap = homebrew.untrustedTap {
                    HomebrewTrustCard(tap: tap, compact: true)
                        .padding(.horizontal, 17)
                }
                if let error = homebrew.errorMessage, !error.isEmpty {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 17)
                }
            } else {
                Label(String(format: l10n.s.uninstallerHomebrewPackageFormat, package.displayName),
                      systemImage: "shippingbox")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 17)
            }
            Divider().padding(.horizontal, 17)
        }
    }

    private var uninstallReviewHeader: some View {
        HStack(spacing: 9) {
            if let target = uninstaller.target {
                Image(nsImage: target.icon)
                    .resizable()
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(target.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Text(target.bundleID ?? target.url.path)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 1) {
                Text(Self.uninstallByteString(uninstaller.totalSize))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(l10n.s.uninstallerFoundTitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 17)
    }

    private func uninstallCategoryGroup(_ group: [AppUninstaller.Leftover],
                                        category: AppUninstaller.Category) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(uninstallCategoryLabel(category).uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            ForEach(group) { item in
                uninstallReviewRow(item)
            }
        }
    }

    private func uninstallReviewRow(_ item: AppUninstaller.Leftover) -> some View {
        HStack(spacing: 7) {
            Toggle(item.name, isOn: uninstallIncludeBinding(item))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .focusable(interactions: .edit)
                .onKeyPress(.space) {
                    let included = uninstaller.items.first(where: { $0.id == item.id })?.include ?? false
                    uninstaller.setInclude(!included, for: item.id)
                    return .handled
                }
                .disabled(uninstaller.isRemoving)
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 5) {
                    if item.confidence == .related {
                        Label(l10n.s.cleanerOptionalSection, systemImage: "questionmark.circle")
                            .foregroundStyle(.orange)
                    }
                    Text(item.url.deletingLastPathComponent().path
                            .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .font(.system(size: 9.5))
            }
            Spacer(minLength: 0)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
            .help(l10n.s.cleanerRevealInFinder)
            .accessibilityLabel(l10n.s.cleanerRevealInFinder)
            Text(Self.uninstallByteString(item.size))
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 22)
    }

    private var uninstallReviewFooter: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(String(format: l10n.s.uninstallerSelectedFormat,
                            uninstaller.items.filter(\.include).count, uninstaller.items.count))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                Text(Self.uninstallByteString(uninstaller.selectedSize))
                    .font(.system(size: 9.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(l10n.s.uninstallerCancel) { service.stepBack() }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button {
                service.runSelected()
            } label: {
                Label(uninstaller.selectedHomebrewPackage == nil
                      ? l10n.s.uninstallerRemove : l10n.s.homebrewUninstall,
                      systemImage: "trash")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.red)
            .disabled(!uninstaller.canRemoveSelected
                      || (uninstaller.selectedHomebrewPackage != nil && homebrew.isBusy))
        }
        .padding(.horizontal, 17)
    }

    private func uninstallReviewDone(freed: Int64, failed: [AppUninstaller.Leftover]) -> some View {
        VStack(spacing: 9) {
            Image(systemName: UninstallerSupport.doneSymbol(hasLeftovers: !failed.isEmpty))
                .font(.system(size: 28))
                .foregroundStyle(failed.isEmpty ? .green : .orange)
            Text(l10n.s.uninstallerDoneTitle)
                .font(.system(size: 13, weight: .bold))
            Text(String(format: l10n.s.uninstallerFreedFormat, Self.uninstallByteString(freed)))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if !failed.isEmpty {
                UninstallFailureNote(items: failed, compact: true)
                    .padding(.horizontal, 17)
            }
            Button(l10n.s.uninstallerAnother) { service.runSelected() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private func uninstallIncludeBinding(_ item: AppUninstaller.Leftover) -> Binding<Bool> {
        Binding(
            get: { uninstaller.items.first(where: { $0.id == item.id })?.include ?? false },
            set: { uninstaller.setInclude($0, for: item.id) }
        )
    }

    private func uninstallCategoryLabel(_ category: AppUninstaller.Category) -> String {
        switch category {
        case .app: return l10n.s.uninstallerCatApp
        case .support: return l10n.s.uninstallerCatSupport
        case .caches: return l10n.s.uninstallerCatCaches
        case .preferences: return l10n.s.uninstallerCatPreferences
        case .containers: return l10n.s.uninstallerCatContainers
        case .logs: return l10n.s.uninstallerCatLogs
        case .state: return l10n.s.uninstallerCatState
        case .other: return l10n.s.uninstallerCatOther
        }
    }

    private static func uninstallByteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Guards a Homebrew-managed app's removal, the same extra step the
    /// Settings page and menu panel already ask for before running `brew
    /// uninstall` - styled like `confirmCard` since it is the same kind of
    /// destructive guard, just reached from the checklist instead of a row.
    private var uninstallHomebrewConfirmCard: some View {
        VStack(spacing: 6) {
            if let target = uninstaller.target, let package = uninstaller.selectedHomebrewPackage {
                HStack(spacing: 10) {
                    Image(nsImage: target.icon)
                        .resizable()
                        .frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 1.5) {
                        Text(l10n.s.homebrewConfirmUninstallTitle)
                            .font(.system(size: 13, weight: .semibold))
                        Text(String(format: l10n.s.homebrewConfirmUninstallBodyFormat, package.displayName))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(l10n.s.uninstallerCancel) { service.stepBack() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button(l10n.s.homebrewUninstall) { service.runSelected() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.red)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.red.opacity(0.09))
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: "keyboard")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(GlobalShortcut.saved(for: DefaultsKey.commandBarShortcut,
                                      fallback: .commandBarDefault).displayString)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
            if service.selectedEntry != nil || service.canOpenActions {
                Button {
                    toggleActionPanel()
                } label: {
                    HStack(spacing: 3) {
                        Text("⌘K")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                        Text(text.actionsHint)
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(showActionPanelOverlay || isActionsMode ? Color.accentColor : Color.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(showActionPanelOverlay || isActionsMode ? Color.accentColor.opacity(0.14) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
            }
            Text(service.isShowingSuggestions && !service.categoryChips.isEmpty ? "⌃P ⌃N ↑↓ ←→" : "⌃P ⌃N ↑↓")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            if service.selectedEntry?.id == "math.result" {
                Text("⇥")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(text.reuseHint)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "return")
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
            Text("Esc")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func layoutModeTitle(_ mode: CommandBarLayoutMode) -> String {
        switch mode {
        case .list: return wave3Strings.layoutListLabel
        case .splitDetail: return wave3Strings.layoutSplitLabel
        case .grid: return wave3Strings.layoutGridLabel
        }
    }

    // MARK: - Split Detail & Grid Views (Command Bar 2.0)

    private var splitDetailResultsView: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: service.rows.count > 10) {
                        LazyVStack(spacing: 1) {
                            ForEach(Array(service.rows.enumerated()), id: \.element.id) { index, entry in
                                if let heading = service.sectionTitles[index] {
                                    sectionHeader(heading)
                                }
                                row(entry, index: index)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                    }
                    .frame(height: Self.listCeiling)
                    .notchScrollEdgeFade(axis: .vertical, length: 14)
                    .onChange(of: service.selectedIndex) { _, index in
                        guard service.rows.indices.contains(index) else { return }
                        proxy.scrollTo(service.rows[index].id)
                    }
                }
            }
            .frame(width: shownAs == .island ? 236 : 272)

            Divider()

            splitDetailInspector
                .frame(maxWidth: .infinity, maxHeight: Self.listCeiling, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var splitDetailInspector: some View {
        if let entry = service.selectedEntry ?? service.rows.first {
            let source = CommandBarPreferences.source(ofRowID: entry.id)
            let tone = categoryTone(for: source)
            let accent = tone.color(scheme: shownAs == .window ? colorScheme : .dark, highContrast: false)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        iconView(entry)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            if !entry.subtitle.isEmpty {
                                Text(entry.subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 4)
                        Text(service.categoryTitle(source))
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(accent.opacity(0.15)))
                    }

                    // Metadata badges
                    HStack(spacing: 6) {
                        if entry.isActive {
                            inspectorPill(title: text.stateOn, symbol: "circle.fill", tint: .green)
                        }
                        if service.isPinned(entry) {
                            inspectorPill(title: text.pinnedTitle, symbol: "pin.fill", tint: accent)
                        }
                        if let alias = service.alias(for: entry) {
                            inspectorPill(title: alias, symbol: "character.cursor.ibeam", tint: .secondary)
                        }
                        if let shortcut = service.rowShortcut(for: entry)?.displayString
                            ?? entry.shortcut?.displayString ?? entry.menuShortcut {
                            inspectorPill(title: shortcut, symbol: "command", tint: .secondary)
                        }
                    }

                    // Live preview body
                    inspectorPreviewBody(for: entry, accent: accent)

                    // Quick Actions from CommandBarActionPanelModel
                    VStack(alignment: .leading, spacing: 5) {
                        Text(text.actionsTitle.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(.tertiary)
                        ForEach(actionPanelItems(for: entry)) { item in
                            Button {
                                executeActionPanelItem(item, for: entry)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: item.symbolName)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(item.isDestructive ? Color.red : accent)
                                        .frame(width: 16)
                                    Text(item.title)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(item.isDestructive ? Color.red : Color.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(item.shortcutDisplay)
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Color.primary.opacity(0.05))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let transformed = actionPanelTransformOutput {
                        transformOutputBanner(transformed)
                    }
                }
                .padding(14)
            }
            .notchScrollEdgeFade(axis: .vertical, length: 12)
        } else {
            VStack {
                Text(text.noResultsTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func inspectorPreviewBody(for entry: CommandBarEntry, accent: Color) -> some View {
        if let value = entry.answerValue ?? (entry.isAnswer ? entry.title : nil) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(value)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        copyTextToPasteboard(value)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(accent.opacity(0.10)))
        } else if let link = scriptLink(for: entry) {
            scriptInspectorSection(link: link, accent: accent)
        } else if let path = entry.revealPath {
            VStack(alignment: .leading, spacing: 4) {
                Text(path)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
        } else if case .needsSetup(let featureTitle, _) = entry.trouble {
            Label(String(format: text.needsSetupFormat, featureTitle), systemImage: "gearshape")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
        } else if case .needsPermission = entry.trouble {
            Label(text.needsPermissionHint, systemImage: "hand.raised")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
        }

        if quickAI.isStreaming || !quickAI.responseText.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(wave3Strings.quickAITitle)
                        .font(.system(size: 10.5, weight: .semibold))
                    Spacer()
                    if quickAI.isStreaming {
                        Text(wave3Strings.quickAIThinking)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(quickAI.responseText.isEmpty ? wave3Strings.quickAIPlaceholder : quickAI.responseText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.accentColor.opacity(0.09)))
        }
    }

    @ViewBuilder
    private func scriptInspectorSection(link: CommandBarLink, accent: Color) -> some View {
        let meta = service.scriptRunner.metadata(for: link)
        let typed = service.query.trimmingCharacters(in: .whitespaces)
        let typedArg = CommandBarLinks.trailingArgument(query: typed, name: link.name) ?? ""
        let explicitArg = scriptArgInputs.prefix(max(1, meta?.arguments.count ?? 1))
            .map { value -> String in
                value.contains(where: \.isWhitespace) ? "\"\(value)\"" : value
            }
            .joined(separator: " ")
        let activeResult = service.scriptRunner.cachedResult(linkID: link.id, argument: typedArg)
            ?? service.scriptRunner.cachedResult(linkID: link.id, argument: explicitArg)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let mode = meta?.mode {
                    inspectorPill(title: mode.rawValue, symbol: "terminal", tint: accent)
                }
                if let refresh = meta?.refreshTime, !refresh.isEmpty {
                    inspectorPill(title: refresh, symbol: "clock", tint: .secondary)
                }
                if let pkg = meta?.packageName, !pkg.isEmpty {
                    inspectorPill(title: pkg, symbol: "shippingbox", tint: .secondary)
                }
            }
            if let desc = meta?.description, !desc.isEmpty {
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let argSpecs = meta?.arguments, !argSpecs.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(argSpecs.enumerated()), id: \.element.index) { idx, spec in
                        if idx < 3 {
                            HStack(spacing: 6) {
                                if spec.secure {
                                    SecureField(spec.placeholder.isEmpty ? "Arg \(spec.index)" : spec.placeholder,
                                                text: $scriptArgInputs[idx])
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 11))
                                } else {
                                    TextField(spec.placeholder.isEmpty ? "Arg \(spec.index)" : spec.placeholder,
                                              text: $scriptArgInputs[idx])
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 11))
                                }
                            }
                        }
                    }
                    Button {
                        let args = (0..<min(argSpecs.count, 3)).map { scriptArgInputs[$0] }
                        service.scriptRunner.runWithArguments(link: link, arguments: args)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9.5))
                            Text("Run Script")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(accent))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let result = activeResult {
                if let payload = result.jsonPayload {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(payload.title)
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            if let badge = payload.badge, !badge.isEmpty {
                                Text(badge)
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(Color.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.green.opacity(0.15)))
                            }
                        }
                        if let sub = payload.subtitle, !sub.isEmpty {
                            Text(sub)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            Button {
                                copyTextToPasteboard(payload.copyText ?? payload.title)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .font(.system(size: 10.5, weight: .medium))
                            }
                            .buttonStyle(.plain)
                            if let openURL = payload.openURL, let url = URL(string: openURL) {
                                Button {
                                    NSWorkspace.shared.open(url)
                                } label: {
                                    Label("Open URL", systemImage: "arrow.up.right.square")
                                        .font(.system(size: 10.5, weight: .medium))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .foregroundStyle(accent)
                    }
                    .padding(9)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(accent.opacity(0.09)))
                } else {
                    Text(result.rawOutput)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(9)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
                }
            } else if service.scriptRunner.isAwaiting {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(wave3Strings.quickAIThinking)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func inspectorPill(title: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 3.5) {
            Image(systemName: symbol)
                .font(.system(size: 8.5, weight: .semibold))
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(tint.opacity(0.12)))
    }

    private var gridResultsView: some View {
        let columns = [GridItem(.adaptive(minimum: 122, maximum: 146), spacing: 8)]
        return VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: service.rows.count > 9) {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(Array(service.rows.enumerated()), id: \.element.id) { index, entry in
                            gridTile(entry, index: index)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .frame(maxHeight: Self.listCeiling)
                .fixedSize(horizontal: false, vertical: service.rows.count <= 9)
                .frame(minHeight: service.rows.count > 9 ? Self.listCeiling : nil)
                .notchScrollEdgeFade(axis: .vertical, length: 14)
                .onChange(of: service.selectedIndex) { _, index in
                    guard service.rows.indices.contains(index) else { return }
                    proxy.scrollTo(service.rows[index].id)
                }
            }
        }
    }

    private func gridTile(_ entry: CommandBarEntry, index: Int) -> some View {
        let isSelected = index == service.selectedIndex
        let source = CommandBarPreferences.source(ofRowID: entry.id)
        let accent = categoryTone(for: source).color(scheme: shownAs == .window ? colorScheme : .dark, highContrast: false)
        return Button {
            service.run(entry, fromClick: true)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top) {
                    iconView(entry)
                    Spacer(minLength: 4)
                    if service.commandIsHeld, index < 9 {
                        Text("⌘\(index + 1)")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.accentColor.opacity(0.14)))
                    } else {
                        Text(service.categoryTitle(source))
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(accent)
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(accent.opacity(0.14)))
                    }
                }
                Text(entry.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let value = entry.answerValue {
                    Text(value)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                } else if !entry.subtitle.isEmpty {
                    Text(entry.subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.16) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? accent.opacity(0.65) : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.2 : 0.6)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { service.selectFromHover(index) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(entry))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - ⌘K Action Panel Card

    private func commandBarActionPanelCard(for entry: CommandBarEntry) -> some View {
        let items = actionPanelItems(for: entry)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                iconView(entry)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Text(text.actionsTitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showActionPanelOverlay = false
                    focusSearch()
                } label: {
                    Text("Esc")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            VStack(spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let isSelected = index == actionPanelIndex
                    Button {
                        executeActionPanelItem(item, for: entry)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.symbolName)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(item.isDestructive ? Color.red : Color.primary.opacity(0.85))
                                .frame(width: 24, height: 24)
                            Text(item.title)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(item.isDestructive ? Color.red : Color.primary)
                            Spacer()
                            Text(item.shortcutDisplay)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.06)))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(isSelected
                                      ? (item.isDestructive ? Color.red.opacity(0.12) : Color.accentColor.opacity(0.16))
                                      : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering { actionPanelIndex = index }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)

            if let transformed = actionPanelTransformOutput {
                transformOutputBanner(transformed)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
        }
        .focusable()
        .focused($actionPanelFocused)
        .onAppear {
            actionPanelIndex = 0
            actionPanelFocused = true
        }
        .onKeyPress(.upArrow) {
            guard !items.isEmpty else { return .ignored }
            actionPanelIndex = (actionPanelIndex - 1 + items.count) % items.count
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !items.isEmpty else { return .ignored }
            actionPanelIndex = (actionPanelIndex + 1) % items.count
            return .handled
        }
        .onKeyPress(.return) {
            guard items.indices.contains(actionPanelIndex) else { return .ignored }
            executeActionPanelItem(items[actionPanelIndex], for: entry)
            return .handled
        }
        .onKeyPress(.escape) {
            showActionPanelOverlay = false
            focusSearch()
            return .handled
        }
    }

    private func transformOutputBanner(_ transformed: String) -> some View {
        HStack(spacing: 8) {
            Text(transformed)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer()
            Button {
                copyTextToPasteboard(transformed)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor.opacity(0.10)))
    }

    // MARK: - Quick AI (Command Bar 2.0)

    private var quickAICard: some View {
        let missingProvider = missingAPIKeyProvider
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label(wave3Strings.quickAITitle, systemImage: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                Menu {
                    ForEach(QuickAIProvider.allCases) { provider in
                        Button {
                            quickAI.selectedProvider = provider
                        } label: {
                            HStack {
                                Text(providerMenuLabel(provider))
                                if quickAI.selectedProvider == provider {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(quickAI.selectedProvider.displayName)
                            .font(.system(size: 10.5, weight: .medium))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8.5, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                if quickAI.isStreaming {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text(wave3Strings.quickAIThinking)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                } else if quickAI.dropletState == .celebrate && !quickAI.responseText.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.green)
                }

                Spacer()

                if !quickAI.responseText.isEmpty {
                    Button {
                        copyTextToPasteboard(quickAI.responseText)
                        quickAICopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            quickAICopied = false
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: quickAICopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 9.5, weight: .semibold))
                            if quickAICopied {
                                Text("Copied")
                                    .font(.system(size: 9.5, weight: .semibold))
                            }
                        }
                        .foregroundStyle(quickAICopied ? Color.green : Color.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }

                if quickAI.isStreaming {
                    Button {
                        quickAI.reset()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.orange)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    showQuickAICard = false
                    quickAI.reset()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Context injection chips: @clipboard, @selection, @frontApp, @browser
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(QuickAIContextToken.allCases) { token in
                        let isActive = attachedContextTokens.contains(token)
                            || service.query.lowercased().contains(token.token.lowercased())
                            || quickAIPromptDraft.lowercased().contains(token.token.lowercased())
                        Button {
                            if attachedContextTokens.contains(token) {
                                attachedContextTokens.remove(token)
                            } else {
                                attachedContextTokens.insert(token)
                            }
                        } label: {
                            HStack(spacing: 3.5) {
                                Image(systemName: token.symbolName)
                                    .font(.system(size: 8.5, weight: .semibold))
                                Text(token.token)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            }
                            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(isActive ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06))
                            )
                            .overlay(
                                Capsule().strokeBorder(isActive ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if trimmedQuery.isEmpty {
                HStack(spacing: 6) {
                    TextField(wave3Strings.quickAIPlaceholder, text: $quickAIPromptDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5))
                        .onSubmit {
                            let prompt = quickAIPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !prompt.isEmpty else { return }
                            sendQuickAIPrompt(prompt)
                        }
                    Button {
                        let prompt = quickAIPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !prompt.isEmpty else { return }
                        sendQuickAIPrompt(prompt)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(quickAIPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                             ? Color.secondary.opacity(0.4) : Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(quickAIPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                HStack {
                    Text(v2Strings.quickAIContextHint)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        sendQuickAIPrompt(trimmedQuery)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9.5, weight: .semibold))
                            Text("Ask")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3.5)
                        .background(Capsule().fill(Color.accentColor))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let missingProvider {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text(quickAI.errorText ?? "\(missingProvider.displayName) key missing in Keychain.")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button {
                        service.hide()
                        SettingsRouter.shared.page = .commandBar
                        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
                    } label: {
                        Label("Open Settings", systemImage: "gearshape")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.orange.opacity(0.10)))
            } else if let error = quickAI.errorText, !error.isEmpty {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !quickAI.responseText.isEmpty {
                ScrollView {
                    markdownOrPlainText(quickAI.responseText)
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
            } else {
                Text(wave3Strings.quickAIPlaceholder)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private var isActionsMode: Bool {
        if case .actions = service.mode { return true }
        return false
    }

    private var missingAPIKeyProvider: QuickAIProvider? {
        if let explicit = quickAI.missingKeyProvider { return explicit }
        let selected = quickAI.selectedProvider
        if (selected == .byokOpenAI || selected == .byokAnthropic),
           quickAI.apiKey(for: selected) == nil {
            return selected
        }
        return nil
    }

    private func detectedCLIsRefresh() {
        detectedCLITools = CommandBarQuickAIService.installedCLITools()
    }

    private func providerMenuLabel(_ provider: QuickAIProvider) -> String {
        switch provider {
        case .claudeCLI, .codexCLI:
            let ready = detectedCLITools.contains(provider)
            return ready ? "\(provider.displayName) ✓" : "\(provider.displayName) (not found)"
        case .byokOpenAI, .byokAnthropic:
            let hasKey = quickAI.apiKey(for: provider) != nil
            return hasKey ? "\(provider.displayName) ✓" : "\(provider.displayName) (no key)"
        case .ollama:
            return provider.displayName
        }
    }

    private func sendQuickAIPrompt(_ prompt: String) {
        quickAICopied = false
        quickAI.sendContextualPrompt(prompt, attachedTokens: attachedContextTokens)
    }

    private func markdownOrPlainText(_ content: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attributed = try? AttributedString(markdown: content, options: options) {
            return Text(attributed)
        }
        return Text(content)
    }

    private func toggleActionPanel() {
        if showActionPanelOverlay {
            showActionPanelOverlay = false
            focusSearch()
        } else if isActionsMode {
            service.stepBack()
        } else if service.canOpenActions {
            service.openActions()
        } else if service.selectedEntry != nil {
            showActionPanelOverlay = true
        }
    }

    private func actionPanelItems(for entry: CommandBarEntry) -> [CommandBarActionItem] {
        CommandBarActionPanelModel.actions(
            forTitle: entry.title,
            canRevealInFinder: entry.canRevealInFinder,
            canCopyValue: canCopyEntryValue(entry),
            canPin: CommandBarPreferences.acceptsPin(rowID: entry.id),
            canTransform: canTransformEntry(entry),
            isDestructiveSupported: true
        )
    }

    private func canCopyEntryValue(_ entry: CommandBarEntry) -> Bool {
        entry.answerValue != nil || entry.isAnswer || entry.revealPath != nil || !entry.title.isEmpty
    }

    private func canTransformEntry(_ entry: CommandBarEntry) -> Bool {
        let source = CommandBarPreferences.source(ofRowID: entry.id)
        return entry.isAnswer || entry.answerValue != nil || source == .clipboard || source == .selection
    }

    private func copyableValue(for entry: CommandBarEntry) -> String {
        if let link = scriptLink(for: entry) {
            let typed = service.query.trimmingCharacters(in: .whitespaces)
            let arg = CommandBarLinks.trailingArgument(query: typed, name: link.name) ?? ""
            if let res = service.scriptRunner.cachedResult(linkID: link.id, argument: arg) {
                return res.jsonPayload?.copyText ?? res.text
            }
        }
        return entry.answerValue ?? entry.revealPath ?? entry.title
    }

    private func executeActionPanelItem(_ item: CommandBarActionItem, for entry: CommandBarEntry) {
        switch item.id {
        case "open":
            showActionPanelOverlay = false
            service.run(entry, fromClick: true)
        case "reveal":
            showActionPanelOverlay = false
            service.revealInFinder(entry)
        case "copy":
            let value = copyableValue(for: entry)
            copyTextToPasteboard(value)
            showActionPanelOverlay = false
        case "pin":
            service.togglePin(entry)
        case "transform":
            let input = copyableValue(for: entry)
            let candidate = ClipboardTransformEngine.apply(.jsonPretty, to: input)
                ?? ClipboardTransformEngine.apply(.jwtDecode, to: input)
                ?? ClipboardTransformEngine.apply(.colorOKLCH, to: input)
                ?? ClipboardTransformEngine.apply(.base64Encode, to: input)
                ?? ClipboardTransformEngine.apply(.sha256, to: input)
            actionPanelTransformOutput = candidate
        case "delete":
            showActionPanelOverlay = false
            service.toggleHidden(entry)
        default:
            break
        }
    }

    private func actionShortcutDisplay(for actionID: String) -> String? {
        switch actionID {
        case "reveal": return "⌘⏎"
        case "pin": return "⌘P"
        case "hide": return "⌘⌫"
        default: return nil
        }
    }

    private func copyTextToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareVorssaintSource()
        let ok = pasteboard.setString(value, forType: .string)
        QuickToolHUD.show(
            icon: ok ? "doc.on.doc" : "exclamationmark.circle",
            message: ok ? value : text.copyFailed
        )
    }

    private func scriptLink(for entry: CommandBarEntry) -> CommandBarLink? {
        guard entry.id.hasPrefix("link."),
              let uuid = UUID(uuidString: String(entry.id.dropFirst("link.".count))) else { return nil }
        let links = CommandBarLinks.decode(UserDefaults.standard.data(forKey: DefaultsKey.commandBarLinks))
        return links.first(where: { $0.id == uuid && $0.kind == .script })
    }

    private func syncScriptArgInputsForSelection() {
        guard let entry = service.selectedEntry,
              let link = scriptLink(for: entry) else {
            scriptArgLinkID = nil
            return
        }
        guard scriptArgLinkID != link.id else { return }
        scriptArgLinkID = link.id
        scriptArgInputs = ["", "", ""]
    }

    private func categoryTone(for source: CommandBarSource) -> SemanticCategoryTone {
        switch source {
        case .actions, .settingsPages, .macSettings:
            return .brand
        case .apps, .windows, .menus, .quitApps, .uninstallApps:
            return .windowsDock
        case .snippets, .emoji, .selection:
            return .mouseKeyboard
        case .clipboard, .files, .folders, .links:
            return .clipboardFiles
        case .answers, .calculator:
            return .energyDisplay
        case .killProcess:
            return .tools
        }
    }
}

/// App and file icons resolved once and kept; NSWorkspace re-reads them from
/// disk on every call otherwise, once per row per render.
///
/// What it keeps is a small bitmap, not what the system hands over: a real
/// app icon carries every representation up to 1024 points, and a few hundred
/// of those held at full size would cost more memory than the rest of the app
/// put together. The rows draw at 28 points, so 64 pixels is already more
/// than any display needs.
enum CommandBarIconCache {
    private static let side: CGFloat = 64

    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 300
        // NSCache alone only sheds under system memory pressure, which is too
        // late; the cost ceiling keeps the whole set inside a few megabytes.
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    static func icon(forPath path: String) -> NSImage {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        let full = NSWorkspace.shared.icon(forFile: path)
        let small = downsampled(full)
        cache.setObject(small, forKey: path as NSString, cost: Int(side * side * 4))
        return small
    }

    private static func downsampled(_ image: NSImage) -> NSImage {
        let size = NSSize(width: side, height: side)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(side),
                                         pixelsHigh: Int(side),
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0)
        else { return image }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: .zero,
                   operation: .copy,
                   fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let result = NSImage(size: size)
        result.addRepresentation(rep)
        return result
    }
}

/// The companion as the bar's face: it glances about as you type, thinks
/// while answers load, hops when they arrive and looks lost when nothing
/// matches.
private struct CommandBarMascot: View {
    @ObservedObject var service: CommandBarService
    @ObservedObject private var quickAI = CommandBarQuickAIService.shared
    @State private var cue: NotchMascotCue?
    @State private var cueID = 0

    private var mood: NotchMascotMood {
        switch quickAI.dropletState {
        case .thinking: return .thinking
        case .celebrate: return .happy
        case .idle:
            return NotchMascotSupport.commandBarMood(query: service.query, hasResults: !service.rows.isEmpty,
                                                     searching: service.awaitsAnswers)
        }
    }

    var body: some View {
        NotchMascotView(look: NotchMascotSupport.look(), mood: mood, size: 22, cue: cue, cueID: cueID)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            // Its eyes go along what is typed, and come back once typing stops.
            .onChange(of: service.query) { _, query in
                cue = .look(NotchMascotSupport.readingGaze(for: query))
                cueID += 1
            }
            .onChange(of: quickAI.dropletState) { _, newState in
                guard newState == .celebrate else { return }
                cue = .celebrate
                cueID += 1
            }
            // After the look, so results arriving with a keystroke win.
            .onChange(of: mood) { old, new in
                guard NotchMascotSupport.celebrates(from: old, to: new, query: service.query,
                                                    hasResults: !service.rows.isEmpty) else { return }
                cue = .celebrate
                cueID += 1
            }
    }
}

private struct CommandBarClearButton: View {
    @ObservedObject private var l10n = L10n.shared
    let action: () -> Void

    var body: some View {
        ClearIconButton(label: l10n.s.actionClear, action: action)
    }
}

private struct CommandBarCategoryChip: View {
    let source: CommandBarSource?
    let label: String
    let isActive: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let source {
                    Image(systemName: source.symbolName)
                        .font(.system(size: 8.5, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .hidden()
                    .overlay {
                        Text(label)
                            .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                    }
            }
            .foregroundStyle(isActive ? Color.accentColor : (isHovered ? Color.primary : Color.secondary))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(
                    isActive
                        ? Color.accentColor.opacity(0.18)
                        : (isHovered ? Color.primary.opacity(0.10) : Color.primary.opacity(0.06))
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    isActive
                        ? Color.accentColor.opacity(0.45)
                        : (isHovered ? Color.primary.opacity(0.15) : Color.clear),
                    lineWidth: 1
                )
            )
            .animation(.easeOut(duration: 0.14), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

