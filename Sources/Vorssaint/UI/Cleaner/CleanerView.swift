// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UserNotifications

/// One Settings home for the installable Cleaner module. The system cleaner
/// and WhatsApp downloads keep separate controls and schedules, while sharing
/// the module's availability and permission portal entry.
struct CleanerSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var router = SettingsRouter.shared
    @AppStorage(DefaultsKey.whatsAppDownloadsEnabled) private var whatsAppEnabled = false
    @State private var tool = Tool.system

    private enum Tool: String {
        case system, whatsApp
    }

    /// A panel surface can ask for a specific tool; the hint is one-shot.
    private func consumeToolHint() {
        guard let hint = router.cleanerTool else { return }
        router.cleanerTool = nil
        guard whatsAppEnabled, let wanted = Tool(rawValue: hint) else { return }
        tool = wanted
    }

    var body: some View {
        VStack(spacing: 0) {
            if whatsAppEnabled {
                VorssaintSegmentedTabs(
                    selection: $tool,
                    options: [
                        .init(.system, title: l10n.s.cleanerName, symbol: "sparkles"),
                        .init(.whatsApp, title: FeatureStrings.whatsAppDownloads(l10n.language).title, symbol: "arrow.down.doc"),
                    ],
                    tone: .tools
                )
                .padding(.horizontal, 24)
                .padding(.vertical, 14)

                Divider()
            }

            if whatsAppEnabled, tool == .whatsApp {
                WhatsAppDownloadsSettings()
            } else {
                CleanerView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if !whatsAppEnabled { tool = .system }
            consumeToolHint()
        }
        .onChange(of: router.cleanerTool) { _, _ in consumeToolHint() }
        .onChange(of: whatsAppEnabled) { _, enabled in
            tool = enabled ? .whatsApp : .system
            WhatsAppDownloadScheduler.shared.syncWithPreferences()
            WhatsAppDownloadOrganizer.shared.syncWithPreferences()
            if !enabled {
                WhatsAppDownloadManager.shared.reset()
                WhatsAppDownloadOrganizer.shared.stop()
            }
        }
    }
}

/// The junk cleaner, built for one glance: a safe section that is fully
/// selected and ready for a single click, and an optional section that
/// starts unchecked and collapsed for whoever wants to dig. Every group has
/// a plain language explanation; the file by file detail lives one chevron
/// away instead of in your face. Hosted by the menu bar panel and the quick
/// panel.
struct CleanerView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var cleaner = JunkCleaner.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.cleanerScheduleFrequency) private var scheduleFrequencyRaw = "off"
    @AppStorage(DefaultsKey.cleanerScheduleHour) private var scheduleHour = 9
    @AppStorage(DefaultsKey.cleanerScheduleMinute) private var scheduleMinute = 0
    @AppStorage(DefaultsKey.cleanerScheduleWeekday) private var scheduleWeekday = 2
    @AppStorage(DefaultsKey.cleanerLastAutoRun) private var lastAutoRun = 0.0
    @AppStorage(DefaultsKey.cleanerLastAutoFreed) private var lastAutoFreed = 0
    @AppStorage(DefaultsKey.cleanerLastAutoFailed) private var lastAutoFailed = 0
    @AppStorage(DefaultsKey.cleanerScheduleNotify) private var scheduleNotify = true
    @AppStorage(DefaultsKey.cleanerScreenshotAgeDays)
    private var screenshotAgeDays = CleanerPolicy.defaultScreenshotAgeDays
    @ObservedObject private var scheduler = CleanerScheduler.shared
    @ObservedObject private var whatsAppScheduler = WhatsAppDownloadScheduler.shared
    @AppStorage(DefaultsKey.whatsAppDownloadsEnabled) private var whatsAppEnabled = false
    @AppStorage(DefaultsKey.whatsAppDownloadsAutomaticEnabled) private var whatsAppAutomatic = false
    @AppStorage(DefaultsKey.whatsAppDownloadsLastCleanup) private var whatsAppLastCleanup = 0.0
    @AppStorage(DefaultsKey.whatsAppDownloadsLastCleanupCount) private var whatsAppLastCount = 0
    @AppStorage(DefaultsKey.whatsAppDownloadsLastCleanupBytes) private var whatsAppLastBytes = 0
    @AppStorage(DefaultsKey.whatsAppDownloadsLastCleanupFailed) private var whatsAppLastFailed = 0
    @State private var notificationsDenied = false
    /// The panel hosted card starts folded; the Settings page shows it open.
    @State private var scheduleExpanded = false
    @State private var whatsAppExpanded = false
    @State private var scheduleHovered = false
    @State private var whatsAppHovered = false
    @State private var showSpaceLens = false
    @State private var spaceLensMode: SpaceLensRenderMode = .sunburst
    @State private var spaceLensBreadcrumbs: [(title: String, url: URL?)] = []
    @State private var spaceLensGroupFilter: DisplayGroup? = nil
    @State private var spaceLensRootNode: SpaceLensNode? = nil
    @State private var drilledDirectoryNodes: [SpaceLensNode] = []
    @State private var selectedSpaceTileID: String? = nil
    @State private var hoveredSunburstArc: SpaceLensSunburstArc? = nil
    @State private var selectedSunburstArc: SpaceLensSunburstArc? = nil
    @State private var spaceLensScanning = false
    @State private var spaceLensScanTask: Task<Void, Never>? = nil
    @State private var collectBasket = SpaceLensCollectBasket()

    @State private var startupAgentsExpanded = false
    @State private var startupAgentsHovered = false
    @State private var startupAgents: [StartupAgentEntry] = []
    @State private var startupAgentsLoaded = false
    @State private var startupAgentsScanning = false
    @State private var startupAgentsBusyID: String? = nil

    @State private var duplicatesExpanded = false
    @State private var duplicatesHovered = false
    @State private var duplicatesRootURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads", isDirectory: true)
    @State private var duplicateGroups: [DuplicateFileGroup] = []
    @State private var duplicatesScanning = false
    @State private var duplicatesHasScanned = false
    @State private var duplicatesScanTask: Task<Void, Never>? = nil

    @ObservedObject private var trashWatcher = TrashWatcherService.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Tightens paddings for the panel and launcher.
    var compact = false

    private enum SpaceLensRenderMode: String, CaseIterable {
        case sunburst
        case treemap
    }

    private func v3(_ keyPath: KeyPath<OverhaulV3Strings, String>) -> String {
        OverhaulV3Strings.localized(l10n.language)[keyPath: keyPath]
    }

    var body: some View {
        VStack(spacing: 0) {
            trashWatcherBanner
            content
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch cleaner.phase {
        case .idle:
            if showSpaceLens, !spaceLensBreadcrumbs.isEmpty {
                let lensBody = VStack(alignment: .leading, spacing: DesignSpace.sm) {
                    spaceLensToggleBar
                    spaceLensMapView
                }
                if compact {
                    lensBody
                } else {
                    settingsScrolling(lensBody)
                }
            } else {
                settingsScrolling(idleState)
            }
        case .scanning: settingsScrolling(busyState(l10n.s.cleanerScanning, detail: scanningDetail))
        case .results:
            VStack(alignment: .leading, spacing: DesignSpace.sm) {
                spaceLensToggleBar
                if showSpaceLens {
                    if compact {
                        spaceLensMapView
                    } else {
                        settingsScrolling(spaceLensMapView)
                    }
                } else {
                    resultsState
                }
            }
        case .cleaning: settingsScrolling(busyState(l10n.s.cleanerCleaning, detail: nil))
        case let .done(freed, failed): settingsScrolling(doneState(freed: freed, failed: failed))
        }
    }

    @ViewBuilder
    private var trashWatcherBanner: some View {
        if let trashed = trashWatcher.detectedAppName {
            let leftovers = trashWatcher.detectedLeftovers
            HStack(spacing: 10) {
                MascotCameoBadge(
                    mood: .determined,
                    reaction: .sweep,
                    tone: .tools,
                    size: 26
                )
                VStack(alignment: .leading, spacing: 2) {
                    if leftovers.isEmpty {
                        Text(trashed)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    } else {
                        Text(String(format: OverhaulStrings.wave4(l10n.language).trashLeftoversFoundFormat,
                                    leftovers.count, trashed))
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        Text(prettyPath(leftovers[0]))
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 4)
                if !leftovers.isEmpty {
                    Button(OverhaulStrings.wave4(l10n.language).cleanLeftoversButton) {
                        trashWatcher.removeDetectedLeftovers()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
                Button("Dismiss") {
                    trashWatcher.clear()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.orange.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.orange.opacity(0.28), lineWidth: 1)
                    )
            )
            .padding(.horizontal, compact ? 10 : 18)
            .padding(.top, 8)
        }
    }

    private var spaceLensToggleBar: some View {
        HStack(spacing: DesignSpace.sm) {
            if let trashed = trashWatcher.detectedAppName, !trashWatcher.detectedLeftovers.isEmpty {
                Label(String(format: OverhaulStrings.wave4(l10n.language).trashLeftoversFoundFormat,
                             trashWatcher.detectedLeftovers.count, trashed),
                      systemImage: "sparkles")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            Spacer(minLength: DesignSpace.xs)
            VorssaintActionChip(
                title: OverhaulV2Strings.localized(l10n.language).spaceLensRootLabel,
                symbol: "folder.badge.gearshape",
                tone: .tools
            ) {
                chooseSpaceLensFolder()
            }

            VorssaintActionChip(
                title: OverhaulStrings.wave4(l10n.language).spaceLensTitle,
                symbol: showSpaceLens ? "list.bullet" : "sun.max.fill",
                tone: .tools,
                prominent: showSpaceLens
            ) {
                withAnimation(DesignMotion.resolve(DesignMotion.snappy, reduceMotion: reduceMotion)) {
                    showSpaceLens.toggle()
                }
            }
        }
        .padding(.horizontal, compact ? DesignSpace.md - 2 : DesignSpace.lg + 2)
        .padding(.top, DesignSpace.xs + 2)
    }

    private var currentSpaceLensRootNode: SpaceLensNode {
        if !spaceLensBreadcrumbs.isEmpty, let root = spaceLensRootNode {
            return root
        }
        if let group = spaceLensGroupFilter {
            let groupChildren = items(for: group).enumerated().map { idx, item in
                var isDirObj: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: item.url.path, isDirectory: &isDirObj)
                return SpaceLensNode(
                    id: item.url.path,
                    title: item.name,
                    bytes: item.size,
                    categoryIndex: idx,
                    url: item.url,
                    isDirectory: exists && isDirObj.boolValue
                )
            }
            let total = groupChildren.reduce(Int64(0)) { $0 + $1.bytes }
            return SpaceLensNode(
                id: "group-\(group.rawValue)",
                name: title(for: group),
                path: "",
                bytes: total,
                isDirectory: true,
                children: groupChildren,
                categoryIndex: group.rawValue
            )
        }
        let groupNodes = DisplayGroup.allCases.enumerated().compactMap { idx, grp -> SpaceLensNode? in
            let grpChildren = items(for: grp).enumerated().map { _, item in
                var isDirObj: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: item.url.path, isDirectory: &isDirObj)
                return SpaceLensNode(
                    id: item.url.path,
                    title: item.name,
                    bytes: item.size,
                    categoryIndex: idx,
                    url: item.url,
                    isDirectory: exists && isDirObj.boolValue
                )
            }
            let total = grpChildren.reduce(Int64(0)) { $0 + $1.bytes }
            guard total > 0 else { return nil }
            return SpaceLensNode(
                id: "group-\(grp.rawValue)",
                name: title(for: grp),
                path: "",
                bytes: total,
                isDirectory: true,
                children: grpChildren,
                categoryIndex: idx
            )
        }
        let total = groupNodes.reduce(Int64(0)) { $0 + $1.bytes }
        return SpaceLensNode(
            id: "cleaner-results-root",
            name: l10n.s.cleanerName,
            path: "",
            bytes: total,
            isDirectory: true,
            children: groupNodes
        )
    }

    private var currentSpaceLensNodes: [SpaceLensNode] {
        if !spaceLensBreadcrumbs.isEmpty {
            return drilledDirectoryNodes
        }
        return currentSpaceLensRootNode.children
    }

    private var selectedSpaceTileURL: URL? {
        if let arc = selectedSunburstArc, !arc.isOtherGroup, !arc.path.isEmpty {
            return URL(fileURLWithPath: arc.path)
        }
        guard let selectedSpaceTileID else { return nil }
        return currentSpaceLensNodes.first(where: { $0.id == selectedSpaceTileID })?.url
    }

    private var selectedSpaceNode: SpaceLensNode? {
        if let arc = selectedSunburstArc, !arc.isOtherGroup {
            return SpaceLensNode(
                id: arc.nodeID,
                name: arc.name,
                path: arc.path,
                bytes: arc.bytes,
                isDirectory: isDirectoryPath(arc.path)
            )
        }
        guard let selectedSpaceTileID else { return nil }
        return currentSpaceLensNodes.first(where: { $0.id == selectedSpaceTileID })
    }

    private func isDirectoryPath(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        var isDirObj: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirObj)
        return exists && isDirObj.boolValue
    }

    private var spaceLensMapView: some View {
        let rootNode = currentSpaceLensRootNode
        let nodes = currentSpaceLensNodes
        return VStack(alignment: .leading, spacing: DesignSpace.sm) {
            spaceLensNavigationHeader
            spaceLensModeStrip(rootNode: rootNode)

            if spaceLensScanning {
                VStack(spacing: DesignSpace.sm) {
                    ProgressView()
                        .controlSize(.small)
                    Text(l10n.s.cleanerScanning)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    VorssaintActionChip(title: l10n.s.uninstallerCancel, symbol: "xmark", tone: .tools) {
                        spaceLensScanTask?.cancel()
                        spaceLensScanning = false
                    }
                }
                .frame(maxWidth: .infinity, minHeight: compact ? 180 : 250)
            } else if nodes.allSatisfy({ $0.bytes <= 0 }) {
                VStack(spacing: DesignSpace.xs + 2) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 20))
                        .foregroundStyle(.tertiary)
                    Text(OverhaulStrings.wave4(l10n.language).spaceLensTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: compact ? 180 : 250)
            } else if spaceLensMode == .sunburst {
                spaceLensSunburstView(rootNode: rootNode)
            } else {
                GeometryReader { proxy in
                    let rect = CGRect(origin: .zero, size: CGSize(width: max(120, proxy.size.width),
                                                                  height: max(140, proxy.size.height)))
                    let tiles = SpaceLensTreemap.layout(nodes: nodes, in: rect)
                    ZStack(alignment: .topLeading) {
                        ForEach(tiles) { tile in
                            spaceLensTileView(tile)
                        }
                    }
                }
                .frame(height: compact ? 200 : 270)
            }

            if let selected = selectedSpaceNode, !selected.path.isEmpty || selected.id.hasPrefix("group-") {
                spaceLensSelectedBar(selected)
            }

            spaceLensCollectTray
        }
        .padding(.horizontal, compact ? DesignSpace.md - 2 : DesignSpace.lg + 2)
        .padding(.bottom, DesignSpace.md)
        .focusable()
        .onKeyPress(.space) {
            guard let url = selectedSpaceTileURL else { return .ignored }
            ShelfQuickLookCoordinator.shared.toggle(urls: [url])
            return .handled
        }
    }

    private func spaceLensModeStrip(rootNode: SpaceLensNode) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignSpace.sm) {
                spaceLensModeTabs
                Spacer(minLength: DesignSpace.xs)
                spaceLensRootQuickActions(rootNode: rootNode)
            }
            VStack(alignment: .leading, spacing: DesignSpace.xs + 2) {
                spaceLensModeTabs
                HStack(spacing: DesignSpace.xs + 2) {
                    spaceLensRootQuickActions(rootNode: rootNode)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var spaceLensModeTabs: some View {
        VorssaintSegmentedTabs(
            selection: $spaceLensMode,
            options: [
                .init(.sunburst, title: v3(\OverhaulV3Strings.spaceLensSunburstMode), symbol: "sun.max.fill"),
                .init(.treemap, title: v3(\OverhaulV3Strings.spaceLensTreemapMode), symbol: "square.grid.2x2"),
            ],
            tone: .tools
        )
    }

    @ViewBuilder
    private func spaceLensRootQuickActions(rootNode: SpaceLensNode) -> some View {
        if let currentURL = spaceLensBreadcrumbs.last?.url {
            VorssaintActionChip(
                title: v3(\OverhaulV3Strings.spaceLensCollectTitle),
                symbol: "plus.circle",
                tone: .tools
            ) {
                collectBasket.add(path: currentURL.path, sizeBytes: rootNode.bytes, name: rootNode.name)
            }
            VorssaintActionChip(title: "↻", symbol: "arrow.clockwise", tone: .clipboardFiles) {
                SpaceLensDeepScanner.shared.invalidateCache(for: currentURL)
                loadDirectoryNodes(at: currentURL, forceRescan: true)
            }
            .help(l10n.s.cleanerScan)
        } else {
            VorssaintActionChip(
                title: "~",
                symbol: "house",
                tone: .clipboardFiles
            ) {
                let home = FileManager.default.homeDirectoryForCurrentUser
                openSpaceLensDirectory(home)
            }
        }
    }

    private struct SunburstArcShape: Shape {
        let startAngle: Double
        let endAngle: Double
        let innerRadius: CGFloat
        let outerRadius: CGFloat

        func path(in rect: CGRect) -> Path {
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let gap = min(0.008, max(0.0, (endAngle - startAngle) * 0.08))
            let startRad = startAngle + gap * 0.5 - (.pi / 2)
            let endRad = endAngle - gap * 0.5 - (.pi / 2)
            var path = Path()
            guard outerRadius > innerRadius, endRad > startRad else { return path }
            let start = Angle(radians: startRad)
            let end = Angle(radians: endRad)
            path.addArc(center: center, radius: outerRadius, startAngle: start, endAngle: end, clockwise: false)
            path.addArc(center: center, radius: innerRadius, startAngle: end, endAngle: start, clockwise: true)
            path.closeSubpath()
            return path
        }
    }

    private func sunburstColor(for arc: SpaceLensSunburstArc) -> Color {
        if arc.isOtherGroup {
            return Color.secondary.opacity(0.65)
        }
        let groups = FeatureGroup.allCases
        let hashValue = abs(arc.nodeID.hashValue)
        let group = groups[hashValue % max(1, groups.count)]
        return SemanticCategoryPalette.color(for: group, scheme: colorScheme)
    }

    private func spaceLensSunburstView(rootNode: SpaceLensNode) -> some View {
        let arcs = SpaceLensSunburst.buildArcs(root: rootNode, maxDepth: 5)
        let maxRing = max(1, arcs.map(\.ringDepth).max() ?? 1)
        return GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let outerLimit = max(56, side * 0.47)
            let hubRadius = max(24, outerLimit * 0.30)
            let ringCount = CGFloat(max(3, min(5, maxRing)))
            let ringThickness = max(8, (outerLimit - hubRadius) / ringCount)
            let activeArc = hoveredSunburstArc ?? selectedSunburstArc

            ZStack {
                ForEach(arcs) { arc in
                    let depthOffset = CGFloat(arc.ringDepth - 1)
                    let innerR = hubRadius + depthOffset * ringThickness + 1.5
                    let outerR = innerR + ringThickness - 2.0
                    let shape = SunburstArcShape(
                        startAngle: arc.startAngle,
                        endAngle: arc.endAngle,
                        innerRadius: innerR,
                        outerRadius: outerR
                    )
                    let baseColor = sunburstColor(for: arc)
                    let isHighlighted = activeArc?.id == arc.id
                    let ringOpacity = max(0.30, 0.78 - Double(arc.ringDepth - 1) * 0.10)

                    shape
                        .fill(baseColor.opacity(isHighlighted ? 0.92 : ringOpacity))
                        .overlay(
                            shape.stroke(
                                isHighlighted ? Color.primary.opacity(0.85) : Color.primary.opacity(0.18),
                                lineWidth: isHighlighted ? 1.5 : 0.65
                            )
                        )
                        .contentShape(shape)
                        .onHover { hovering in
                            if hovering {
                                hoveredSunburstArc = arc
                            } else if hoveredSunburstArc?.id == arc.id {
                                hoveredSunburstArc = nil
                            }
                        }
                        .onTapGesture(count: 2) {
                            handleSunburstArcDoubleTap(arc)
                        }
                        .onTapGesture {
                            handleSunburstArcTap(arc)
                        }
                        .contextMenu {
                            sunburstContextMenu(for: arc)
                        }
                        .accessibilityLabel("\(arc.name), \(Self.byteString(arc.bytes))")
                }

                sunburstCenterHub(rootNode: rootNode, activeArc: activeArc, hubRadius: hubRadius)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: compact ? 220 : 290)
    }

    private func sunburstCenterHub(rootNode: SpaceLensNode,
                                   activeArc: SpaceLensSunburstArc?,
                                   hubRadius: CGFloat) -> some View {
        let canStepUp = !spaceLensBreadcrumbs.isEmpty || spaceLensGroupFilter != nil
        let sharePct = activeArc.map { arc in
            rootNode.bytes > 0 ? (Double(arc.bytes) / Double(rootNode.bytes)) * 100.0 : 0.0
        }
        return VStack(spacing: DesignSpace.xxs) {
            if let activeArc, let sharePct {
                Text(activeArc.name)
                    .font(.system(size: compact ? 9.5 : 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(Self.byteString(activeArc.bytes))
                    .font(.system(size: compact ? 9.5 : 11, weight: .bold).monospacedDigit())
                Text(String(format: "%.1f%%", locale: .autoupdatingCurrent, sharePct))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text(rootNode.name)
                    .font(.system(size: compact ? 9.5 : 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(Self.byteString(rootNode.bytes))
                    .font(.system(size: compact ? 10 : 11.5, weight: .bold).monospacedDigit())
                if canStepUp {
                    Text(OverhaulV2Strings.localized(l10n.language).spaceLensUpButton)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(DesignSpace.xs)
        .frame(width: max(44, hubRadius * 1.78), height: max(44, hubRadius * 1.78))
        .background(Circle().fill(DesignSurfaceTier.elevated.fillColor(for: colorScheme)))
        .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 0.75))
        .contentShape(Circle())
        .onTapGesture {
            if canStepUp {
                stepUpSpaceLensLevel()
            }
        }
    }

    @ViewBuilder
    private func sunburstContextMenu(for arc: SpaceLensSunburstArc) -> some View {
        if !arc.isOtherGroup {
            if isDirectoryPath(arc.path) {
                Button(OverhaulStrings.wave4(l10n.language).spaceLensTitle) {
                    drillIntoDirectory(URL(fileURLWithPath: arc.path), title: arc.name)
                }
            }
            if !arc.path.isEmpty {
                Button(v3(\OverhaulV3Strings.spaceLensCollectTitle)) {
                    collectBasket.add(path: arc.path, sizeBytes: arc.bytes, name: arc.name)
                }
                Button("Quick Look") {
                    ShelfQuickLookCoordinator.shared.toggle(urls: [URL(fileURLWithPath: arc.path)])
                }
                Button(l10n.s.cleanerRevealInFinder) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: arc.path)])
                }
            }
        }
    }

    private func handleSunburstArcTap(_ arc: SpaceLensSunburstArc) {
        if arc.isOtherGroup {
            selectedSunburstArc = arc
            selectedSpaceTileID = nil
            return
        }
        if spaceLensBreadcrumbs.isEmpty, spaceLensGroupFilter == nil,
           arc.nodeID.hasPrefix("group-"),
           let raw = Int(arc.nodeID.replacingOccurrences(of: "group-", with: "")),
           let group = DisplayGroup(rawValue: raw) {
            spaceLensGroupFilter = group
            selectedSpaceTileID = nil
            selectedSunburstArc = nil
            return
        }
        selectedSunburstArc = arc
        selectedSpaceTileID = arc.nodeID
    }

    private func handleSunburstArcDoubleTap(_ arc: SpaceLensSunburstArc) {
        guard !arc.isOtherGroup else { return }
        if spaceLensBreadcrumbs.isEmpty, spaceLensGroupFilter == nil,
           arc.nodeID.hasPrefix("group-"),
           let raw = Int(arc.nodeID.replacingOccurrences(of: "group-", with: "")),
           let group = DisplayGroup(rawValue: raw) {
            spaceLensGroupFilter = group
            selectedSpaceTileID = nil
            selectedSunburstArc = nil
            return
        }
        guard !arc.path.isEmpty else { return }
        let url = URL(fileURLWithPath: arc.path)
        if isDirectoryPath(arc.path) {
            drillIntoDirectory(url, title: arc.name)
        } else {
            ShelfQuickLookCoordinator.shared.toggle(urls: [url])
        }
    }

    private func spaceLensSelectedBar(_ node: SpaceLensNode) -> some View {
        HStack(spacing: DesignSpace.sm) {
            Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !node.path.isEmpty {
                    Text(prettyPath(URL(fileURLWithPath: node.path)) + "/" + node.name)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: DesignSpace.xs)
            Text(Self.byteString(node.bytes))
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
            if node.isDirectory, !node.path.isEmpty {
                VorssaintActionChip(title: "→", symbol: "arrow.down.right.circle", tone: .tools) {
                    drillIntoDirectory(URL(fileURLWithPath: node.path), title: node.name)
                }
                .help(OverhaulStrings.wave4(l10n.language).spaceLensTitle)
            }
            if !node.path.isEmpty {
                VorssaintActionChip(title: "+", symbol: "tray.and.arrow.down", tone: .tools) {
                    collectBasket.add(path: node.path, sizeBytes: node.bytes, name: node.name)
                }
                .help(v3(\OverhaulV3Strings.spaceLensCollectTitle))
            }
        }
        .padding(.horizontal, DesignSpace.sm + 2)
        .padding(.vertical, DesignSpace.xs + 2)
        .background(
            RoundedRectangle(cornerRadius: DesignRadius.innerGroup, style: .continuous)
                .fill(DesignSurfaceTier.card.fillColor(for: colorScheme))
        )
        .hairlineSpecularBorder(cornerRadius: DesignRadius.innerGroup, opacity: 0.14)
    }

    private var spaceLensCollectTray: some View {
        VStack(alignment: .leading, spacing: DesignSpace.xs + 2) {
            HStack(spacing: DesignSpace.sm) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(SemanticCategoryTone.tools.color(scheme: colorScheme))
                Text(v3(\OverhaulV3Strings.spaceLensCollectTitle))
                    .font(.system(size: 11.5, weight: .semibold))
                if !collectBasket.items.isEmpty {
                    Text("\(collectBasket.items.count) · \(Self.byteString(collectBasket.totalBytes))")
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: DesignSpace.xs)
                if !collectBasket.items.isEmpty {
                    VorssaintActionChip(title: l10n.s.uninstallerCancel, symbol: "xmark", tone: .tools) {
                        collectBasket.clear()
                    }
                    VorssaintActionChip(
                        title: v3(\OverhaulV3Strings.spaceLensCollectTrashAll),
                        symbol: "trash",
                        tone: .tools,
                        prominent: true,
                        destructive: true
                    ) {
                        trashCollectedItems()
                    }
                }
            }

            if !collectBasket.items.isEmpty {
                VStack(alignment: .leading, spacing: DesignSpace.xs) {
                    ForEach(collectBasket.items) { item in
                        HStack(spacing: DesignSpace.sm) {
                            Text(item.name)
                                .font(.system(size: 10.5, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: DesignSpace.xs)
                            Text(Self.byteString(item.sizeBytes))
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(.secondary)
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
                            } label: {
                                Image(systemName: "folder")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                            .help(l10n.s.cleanerRevealInFinder)
                            Button {
                                collectBasket.remove(id: item.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(DesignSpace.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: DesignRadius.innerGroup, style: .continuous)
                .fill(DesignSurfaceTier.card.fillColor(for: colorScheme))
        )
        .hairlineSpecularBorder(cornerRadius: DesignRadius.innerGroup, opacity: 0.16)
    }

    private func trashCollectedItems() {
        let trashed = collectBasket.trashAll()
        if trashed > 0 {
            if let currentURL = spaceLensBreadcrumbs.last?.url {
                SpaceLensDeepScanner.shared.invalidateCache(for: currentURL)
                loadDirectoryNodes(at: currentURL, forceRescan: true)
            } else {
                SpaceLensDeepScanner.shared.invalidateCache()
            }
        }
    }

    private var spaceLensNavigationHeader: some View {
        HStack(spacing: DesignSpace.xs + 2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignSpace.xs) {
                    VorssaintActionChip(title: OverhaulStrings.wave4(l10n.language).spaceLensTitle, tone: .tools) {
                        resetSpaceLensRoot()
                    }

                    if let group = spaceLensGroupFilter {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        VorssaintActionChip(title: title(for: group), tone: .tools) {
                            spaceLensBreadcrumbs = []
                            drilledDirectoryNodes = []
                            spaceLensRootNode = nil
                            selectedSpaceTileID = nil
                            selectedSunburstArc = nil
                        }
                    }

                    ForEach(Array(spaceLensBreadcrumbs.enumerated()), id: \.offset) { index, crumb in
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        VorssaintActionChip(title: crumb.title, tone: .tools) {
                            popSpaceLensBreadcrumb(to: index)
                        }
                    }
                }
            }

            Spacer(minLength: DesignSpace.xs)

            if let selectedURL = selectedSpaceTileURL {
                VorssaintActionChip(title: "", symbol: "eye", tone: .clipboardFiles) {
                    ShelfQuickLookCoordinator.shared.toggle(urls: [selectedURL])
                }
                .help("Quick Look")

                VorssaintActionChip(title: "", symbol: "folder", tone: .clipboardFiles) {
                    NSWorkspace.shared.activateFileViewerSelecting([selectedURL])
                }
                .help(l10n.s.cleanerRevealInFinder)
            }

            if !spaceLensBreadcrumbs.isEmpty || spaceLensGroupFilter != nil {
                VorssaintActionChip(title: OverhaulV2Strings.localized(l10n.language).spaceLensUpButton, symbol: "arrow.up", tone: .tools) {
                    stepUpSpaceLensLevel()
                }
            }
        }
    }

    @ViewBuilder
    private func spaceLensTileView(_ tile: SpaceLensTile) -> some View {
        let groups = FeatureGroup.allCases
        let color = SemanticCategoryPalette.color(for: groups[tile.categoryIndex % max(1, groups.count)])
        let isSelected = selectedSpaceTileID == tile.id
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(color.opacity(isSelected ? 0.36 : 0.24))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : color.opacity(0.55), lineWidth: isSelected ? 1.8 : 1)
            )
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 3) {
                        if tile.isDirectory || tile.id.hasPrefix("group-") {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        Text(tile.title)
                            .font(.system(size: 10.5, weight: .semibold))
                            .lineLimit(1)
                    }
                    Text(Self.byteString(tile.bytes))
                        .font(.system(size: 9.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(6)
            }
            .frame(width: max(4, tile.rect.width - 4), height: max(4, tile.rect.height - 4))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                if let url = tile.url {
                    if tile.isDirectory {
                        drillIntoDirectory(url, title: tile.title)
                    } else {
                        ShelfQuickLookCoordinator.shared.toggle(urls: [url])
                    }
                }
            }
            .onTapGesture {
                handleSpaceLensTileTap(tile)
            }
            .contextMenu {
                if let url = tile.url {
                    if tile.isDirectory {
                        Button(OverhaulStrings.wave4(l10n.language).spaceLensTitle) {
                            drillIntoDirectory(url, title: tile.title)
                        }
                    }
                    Button(v3(\OverhaulV3Strings.spaceLensCollectTitle)) {
                        collectBasket.add(path: url.path, sizeBytes: tile.bytes, name: tile.title)
                    }
                    Button("Quick Look") {
                        ShelfQuickLookCoordinator.shared.toggle(urls: [url])
                    }
                    Button(l10n.s.cleanerRevealInFinder) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
            .offset(x: tile.rect.minX + 2, y: tile.rect.minY + 2)
    }

    private func handleSpaceLensTileTap(_ tile: SpaceLensTile) {
        selectedSpaceTileID = tile.id
        selectedSunburstArc = nil
        if spaceLensBreadcrumbs.isEmpty, spaceLensGroupFilter == nil,
           tile.id.hasPrefix("group-"),
           let raw = Int(tile.id.replacingOccurrences(of: "group-", with: "")),
           let group = DisplayGroup(rawValue: raw) {
            spaceLensGroupFilter = group
            selectedSpaceTileID = nil
            return
        }
        if tile.isDirectory, let url = tile.url {
            drillIntoDirectory(url, title: tile.title)
        }
    }

    private func resetSpaceLensRoot() {
        spaceLensScanTask?.cancel()
        spaceLensGroupFilter = nil
        spaceLensBreadcrumbs = []
        spaceLensRootNode = nil
        drilledDirectoryNodes = []
        selectedSpaceTileID = nil
        selectedSunburstArc = nil
        hoveredSunburstArc = nil
        spaceLensScanning = false
        if case .idle = cleaner.phase {
            showSpaceLens = false
        }
    }

    private func stepUpSpaceLensLevel() {
        selectedSpaceTileID = nil
        selectedSunburstArc = nil
        hoveredSunburstArc = nil
        if spaceLensBreadcrumbs.count > 1 {
            popSpaceLensBreadcrumb(to: spaceLensBreadcrumbs.count - 2)
        } else if !spaceLensBreadcrumbs.isEmpty {
            spaceLensScanTask?.cancel()
            spaceLensBreadcrumbs = []
            spaceLensRootNode = nil
            drilledDirectoryNodes = []
            if case .idle = cleaner.phase {
                showSpaceLens = false
            }
        } else {
            spaceLensGroupFilter = nil
        }
    }

    private func popSpaceLensBreadcrumb(to index: Int) {
        guard index >= 0, index < spaceLensBreadcrumbs.count else { return }
        spaceLensBreadcrumbs = Array(spaceLensBreadcrumbs.prefix(index + 1))
        selectedSpaceTileID = nil
        selectedSunburstArc = nil
        hoveredSunburstArc = nil
        if let url = spaceLensBreadcrumbs.last?.url {
            loadDirectoryNodes(at: url)
        }
    }

    private func drillIntoDirectory(_ url: URL, title: String) {
        spaceLensBreadcrumbs.append((title: title, url: url))
        selectedSpaceTileID = nil
        selectedSunburstArc = nil
        hoveredSunburstArc = nil
        loadDirectoryNodes(at: url)
    }

    private func loadDirectoryNodes(at url: URL, forceRescan: Bool = false) {
        spaceLensScanTask?.cancel()
        if !forceRescan, let cached = SpaceLensDeepScanner.shared.cachedTree(for: url) {
            spaceLensRootNode = cached
            drilledDirectoryNodes = cached.children
            spaceLensScanning = false
            return
        }
        spaceLensScanning = true
        spaceLensScanTask = Task {
            let tree = await SpaceLensDeepScanner.shared.scanTree(at: url, includeHidden: true, useCache: !forceRescan)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                spaceLensRootNode = tree
                drilledDirectoryNodes = tree.children
                spaceLensScanning = false
            }
        }
    }

    private func openSpaceLensDirectory(_ url: URL) {
        showSpaceLens = true
        spaceLensGroupFilter = nil
        let name = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        spaceLensBreadcrumbs = [(title: name, url: url)]
        selectedSpaceTileID = nil
        selectedSunburstArc = nil
        hoveredSunburstArc = nil
        loadDirectoryNodes(at: url)
    }

    private func chooseSpaceLensFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            openSpaceLensDirectory(url)
        }
    }

    /// On the Settings page every detail must host a scroll container: the
    /// split view's sidebar loses its title bar safe area otherwise (macOS 27
    /// beta) and its rows draw under the toolbar or vanish. Every other page
    /// is a Form and gets this for free; the cleaner's List state scrolls on
    /// its own, and these centered states scroll here — the minHeight keeps
    /// them vertically centered exactly as before. The panel keeps the plain
    /// layout: it never sits inside the split view.
    @ViewBuilder
    private func settingsScrolling(_ view: some View) -> some View {
        if compact {
            view
        } else {
            GeometryReader { proxy in
                ScrollView {
                    view.frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
            }
        }
    }

    /// The cleaner's waiting face: the sparkles glyph twinkling layer by
    /// layer through the system symbol effect. Simple, native, and still
    /// while nothing is happening.
    private struct SparkleGlyph: View {
        var animating = false
        var size: CGFloat = 44

        var body: some View {
            Image(systemName: "sparkles")
                .font(.system(size: size, weight: .light))
                .foregroundStyle(.secondary)
                .symbolEffect(.variableColor.iterative.reversing,
                              options: .repeating, isActive: animating)
        }
    }

    private var scanningDetail: String? {
        cleaner.scanningCategory.flatMap { category in
            DisplayGroup.allCases.first { $0.categories.contains(category) }
        }.map(title(for:))
    }

    // MARK: Display groups

    /// How the raw finds are presented: safe groups first, fully selected;
    /// judgment calls under optional, unchecked and collapsed.
    private enum DisplayGroup: Int, CaseIterable, Identifiable {
        case loginItems, safeCaches, logs, developer
        case leftovers, otherCaches, deviceBackups, screenshots, trash

        var id: Int { rawValue }

        var isSafe: Bool {
            switch self {
            case .loginItems, .safeCaches, .logs, .developer: return true
            case .leftovers, .otherCaches, .deviceBackups, .screenshots, .trash: return false
            }
        }

        var categories: [CleanerSupport.Category] {
            switch self {
            case .loginItems: return [.loginItems]
            case .safeCaches, .otherCaches: return [.caches]
            case .logs: return [.logs]
            case .developer: return [.developer]
            case .leftovers: return [.leftovers]
            case .deviceBackups: return [.deviceBackups]
            case .screenshots: return [.screenshots]
            case .trash: return [.trash]
            }
        }

        var icon: String {
            switch self {
            case .loginItems: return "power"
            case .safeCaches: return "archivebox"
            case .logs: return "doc.text"
            case .developer: return "hammer"
            case .leftovers: return "puzzlepiece"
            case .otherCaches: return "internaldrive"
            case .deviceBackups: return "iphone"
            case .screenshots: return "camera.viewfinder"
            case .trash: return "trash"
            }
        }
    }

    private func items(for group: DisplayGroup) -> [JunkCleaner.Item] {
        switch group {
        case .safeCaches: return cleaner.items.filter { $0.category == .caches && $0.recommended }
        case .otherCaches: return cleaner.items.filter { $0.category == .caches && !$0.recommended }
        default: return cleaner.items.filter { group.categories.contains($0.category) }
        }
    }

    private func title(for group: DisplayGroup) -> String {
        switch group {
        case .loginItems: return l10n.s.cleanerCatLoginItems
        case .safeCaches: return l10n.s.cleanerCatCaches
        case .logs: return l10n.s.cleanerCatLogs
        case .developer: return l10n.s.cleanerCatDeveloper
        case .leftovers: return l10n.s.cleanerCatLeftovers
        case .otherCaches: return l10n.s.cleanerCatOtherCaches
        case .deviceBackups: return l10n.s.cleanerCatDeviceBackups
        case .screenshots: return l10n.s.cleanerCatScreenshots
        case .trash: return l10n.s.cleanerCatTrash
        }
    }

    private func caption(for group: DisplayGroup) -> String {
        switch group {
        case .loginItems: return l10n.s.cleanerLoginItemsCaption
        case .safeCaches: return l10n.s.cleanerCachesCaption
        case .logs: return l10n.s.cleanerLogsCaption
        case .developer: return l10n.s.cleanerDeveloperCaption
        case .leftovers: return l10n.s.cleanerLeftoversCaption
        case .otherCaches: return l10n.s.cleanerOtherCachesCaption
        case .deviceBackups: return l10n.s.cleanerDeviceBackupsCaption
        case .screenshots:
            return String(format: l10n.s.cleanerScreenshotsCaptionFormat,
                          CleanerPolicy.sanitizedScreenshotAgeDays(screenshotAgeDays))
        case .trash: return l10n.s.cleanerTrashNote
        }
    }

    // MARK: Idle

    private var idleState: some View {
        VStack(spacing: compact ? 12 : 18) {
            if !compact { Spacer() }
            MascotCameoBadge(mood: .idle, tone: .tools, size: compact ? 34 : 46)
            Text(l10n.s.cleanerIntroTitle)
                .font(.system(size: compact ? 15 : 17, weight: .semibold))
            Text(l10n.s.cleanerIntroCaption)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
            HStack(spacing: DesignSpace.sm + 2) {
                Button(l10n.s.cleanerScan) { cleaner.scan(attended: true) }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                Button {
                    chooseSpaceLensFolder()
                } label: {
                    Label(OverhaulV2Strings.localized(l10n.language).spaceLensRootLabel, systemImage: "sun.max.fill")
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
            }
            scheduleCard
            screenshotsCard
            startupAgentsCard
            duplicatesFinderCard
            if !compact, !whatsAppEnabled { whatsAppOptInCard }
            // The Settings page has its own full tool for these downloads;
            // the panel gets this one-line home so the feature is findable
            // without opening Settings.
            if compact, whatsAppEnabled { whatsAppCard }
            if !permissions.fullDiskAccess {
                FullDiskAccessNote(compact: compact).frame(maxWidth: 380)
            }
            if !compact { Spacer() }
        }
        .padding(compact ? 14 : 28)
        .frame(maxWidth: .infinity)
    }

    // MARK: Forgotten screenshots

    /// Off plus the offered ages, and the stored value when it came from
    /// elsewhere (a restored backup) and is not one of them.
    private var screenshotAgeChoices: [Int] {
        var choices = CleanerPolicy.screenshotAgeChoices
        let current = CleanerPolicy.sanitizedScreenshotAgeDays(screenshotAgeDays)
        if current > 0, !choices.contains(current) {
            choices.append(current)
            choices.sort()
        }
        return [0] + choices
    }

    /// How old an untouched screenshot must be to be listed, or off. The
    /// Settings page explains it; the panel keeps it to one line.
    private var screenshotsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "camera.viewfinder").foregroundStyle(.secondary)
                Text(l10n.s.cleanerCatScreenshots)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Picker("", selection: $screenshotAgeDays) {
                    ForEach(screenshotAgeChoices, id: \.self) { days in
                        Text(days == 0
                             ? l10n.s.cleanerScheduleOff
                             : String(format: l10n.s.cleanerScreenshotsAfterFormat, days))
                            .tag(days)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            if !compact {
                Text(l10n.s.cleanerScreenshotsSettingCaption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(11)
        .frame(maxWidth: 380)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    // MARK: Startup Agents & Daemons

    private var startupAgentsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(DesignMotion.resolve(DesignMotion.gentle, reduceMotion: reduceMotion)) {
                    startupAgentsExpanded.toggle()
                }
                if startupAgentsExpanded, !startupAgentsLoaded {
                    refreshStartupAgents()
                }
            } label: {
                HStack(spacing: DesignSpace.sm) {
                    Image(systemName: startupAgentsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 9)
                    Image(systemName: "bolt.badge.clock")
                        .foregroundStyle(SemanticCategoryTone.tools.color(scheme: colorScheme))
                    Text(v3(\OverhaulV3Strings.startupAgentsTitle))
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    if startupAgentsLoaded {
                        Text("\(startupAgents.count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DesignSpace.md - 1)
                .background(
                    RoundedRectangle(cornerRadius: DesignRadius.pill, style: .continuous)
                        .fill(Color.primary.opacity(startupAgentsHovered ? 0.05 : 0))
                        .padding(DesignSpace.xxs)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { startupAgentsHovered = $0 }

            if startupAgentsExpanded {
                VStack(alignment: .leading, spacing: DesignSpace.sm) {
                    HStack(spacing: DesignSpace.sm) {
                        if startupAgentsScanning {
                            ProgressView()
                                .controlSize(.mini)
                            Text(l10n.s.cleanerScanning)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(startupAgents.filter(\.isEnabled).count) / \(startupAgents.count)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VorssaintActionChip(title: "↻", symbol: "arrow.clockwise", tone: .tools) {
                            refreshStartupAgents()
                        }
                    }

                    if !startupAgentsScanning && startupAgents.isEmpty {
                        Text(l10n.s.cleanerNothingFound)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if compact {
                        VStack(alignment: .leading, spacing: DesignSpace.xs + 2) {
                            ForEach(startupAgents.prefix(16)) { entry in
                                startupAgentRow(entry)
                            }
                        }
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: DesignSpace.xs + 2) {
                                ForEach(startupAgents) { entry in
                                    startupAgentRow(entry)
                                }
                            }
                        }
                        .frame(maxHeight: 220)
                    }
                }
                .padding(.horizontal, DesignSpace.md - 1)
                .padding(.top, DesignSpace.xs)
                .padding(.bottom, DesignSpace.md - 1)
            }
        }
        .frame(maxWidth: compact ? 380 : 500)
        .background(
            RoundedRectangle(cornerRadius: DesignRadius.innerGroup, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func startupAgentRow(_ entry: StartupAgentEntry) -> some View {
        HStack(spacing: DesignSpace.sm) {
            VStack(alignment: .leading, spacing: DesignSpace.xxs) {
                HStack(spacing: DesignSpace.xs) {
                    Text(entry.label)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(startupDomainBadge(entry.domain))
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, DesignSpace.xs + 1)
                        .padding(.vertical, 1)
                        .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.08)))
                    if entry.runAtLoad {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    if entry.keepAlive {
                        Image(systemName: "repeat.circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                }
                if !entry.program.isEmpty {
                    Text(entry.program)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: DesignSpace.xs)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([entry.plistURL])
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(l10n.s.cleanerRevealInFinder)

            if entry.domain == .userAgent {
                Toggle("", isOn: Binding(
                    get: { entry.isEnabled },
                    set: { newValue in toggleUserStartupAgent(entry, enabled: newValue) }
                ))
                .labelsHidden()
                .toggleStyle(VorssaintCompactSwitchStyle(tone: .tools))
                .disabled(startupAgentsBusyID == entry.id)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .help(entry.plistURL.path)
            }
        }
        .padding(.vertical, DesignSpace.xxs)
    }

    private func startupDomainBadge(_ domain: StartupAgentDomain) -> String {
        switch domain {
        case .userAgent: return "User"
        case .globalAgent: return "Global"
        case .systemDaemon: return "Daemon"
        }
    }

    private func refreshStartupAgents() {
        startupAgentsScanning = true
        Task.detached(priority: .utility) {
            let scanned = StartupAgentInspector.scanSystemAgents()
            await MainActor.run {
                startupAgents = scanned
                startupAgentsLoaded = true
                startupAgentsScanning = false
            }
        }
    }

    private func toggleUserStartupAgent(_ entry: StartupAgentEntry, enabled: Bool) {
        startupAgentsBusyID = entry.id
        Task.detached(priority: .userInitiated) {
            let ok = StartupAgentInspector.setUserAgentEnabled(entry, enabled: enabled)
            let updated = StartupAgentInspector.scanSystemAgents()
            await MainActor.run {
                if ok {
                    startupAgents = updated
                } else if let idx = startupAgents.firstIndex(where: { $0.id == entry.id }) {
                    startupAgents[idx].isEnabled = entry.isEnabled
                }
                startupAgentsBusyID = nil
            }
        }
    }

    // MARK: Fast Duplicates Finder

    private var duplicateTotalWaste: Int64 {
        duplicateGroups.reduce(0) { $0 + $1.byteSize * Int64(max(0, $1.urls.count - 1)) }
    }

    private var duplicatesFinderCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(DesignMotion.resolve(DesignMotion.gentle, reduceMotion: reduceMotion)) {
                    duplicatesExpanded.toggle()
                }
            } label: {
                HStack(spacing: DesignSpace.sm) {
                    Image(systemName: duplicatesExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 9)
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(SemanticCategoryTone.clipboardFiles.color(scheme: colorScheme))
                    Text(v3(\OverhaulV3Strings.duplicatesFinderTitle))
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    if !duplicateGroups.isEmpty {
                        Text("\(duplicateGroups.count) · \(Self.byteString(duplicateTotalWaste))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DesignSpace.md - 1)
                .background(
                    RoundedRectangle(cornerRadius: DesignRadius.pill, style: .continuous)
                        .fill(Color.primary.opacity(duplicatesHovered ? 0.05 : 0))
                        .padding(DesignSpace.xxs)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { duplicatesHovered = $0 }

            if duplicatesExpanded {
                VStack(alignment: .leading, spacing: DesignSpace.sm) {
                    HStack(spacing: DesignSpace.xs + 2) {
                        Text(duplicatesRootURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: DesignSpace.xs)
                        VorssaintActionChip(
                            title: OverhaulV2Strings.localized(l10n.language).chooseFolderButton,
                            symbol: "folder",
                            tone: .clipboardFiles
                        ) {
                            chooseDuplicatesFolder()
                        }
                        VorssaintActionChip(
                            title: duplicatesScanning ? l10n.s.uninstallerCancel : l10n.s.cleanerScan,
                            symbol: duplicatesScanning ? "xmark" : "magnifyingglass",
                            tone: .tools,
                            prominent: true
                        ) {
                            if duplicatesScanning {
                                duplicatesScanTask?.cancel()
                                duplicatesScanning = false
                            } else {
                                startDuplicatesScan()
                            }
                        }
                    }

                    if duplicatesScanning {
                        HStack(spacing: DesignSpace.sm) {
                            ProgressView().controlSize(.mini)
                            Text(l10n.s.cleanerScanning)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else if duplicatesHasScanned && duplicateGroups.isEmpty {
                        Text(l10n.s.cleanerNothingFound)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if !duplicateGroups.isEmpty {
                        if compact {
                            VStack(alignment: .leading, spacing: DesignSpace.sm) {
                                ForEach(duplicateGroups.prefix(12)) { group in
                                    duplicateGroupRow(group)
                                }
                            }
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: DesignSpace.sm) {
                                    ForEach(duplicateGroups.prefix(40)) { group in
                                        duplicateGroupRow(group)
                                    }
                                }
                            }
                            .frame(maxHeight: 240)
                        }
                    }
                }
                .padding(.horizontal, DesignSpace.md - 1)
                .padding(.top, DesignSpace.xs)
                .padding(.bottom, DesignSpace.md - 1)
            }
        }
        .frame(maxWidth: compact ? 380 : 500)
        .background(
            RoundedRectangle(cornerRadius: DesignRadius.innerGroup, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func duplicateGroupRow(_ group: DuplicateFileGroup) -> some View {
        VStack(alignment: .leading, spacing: DesignSpace.xs) {
            HStack(spacing: DesignSpace.xs + 2) {
                Text(group.urls.first?.lastPathComponent ?? "")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("×\(group.urls.count)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.orange)
                Text(Self.byteString(group.byteSize))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: DesignSpace.xs)
                if group.urls.count > 1 {
                    VorssaintActionChip(
                        title: v3(\OverhaulV3Strings.spaceLensCollectTrashAll),
                        symbol: "trash",
                        tone: .tools,
                        destructive: true
                    ) {
                        trashDuplicateCopies(in: group)
                    }
                }
            }
            ForEach(Array(group.urls.enumerated()), id: \.offset) { idx, url in
                HStack(spacing: DesignSpace.xs + 2) {
                    Image(systemName: idx == 0 ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 9.5))
                        .foregroundStyle(idx == 0 ? Color.green : Color.secondary)
                    Text(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: 9.5))
                        .foregroundStyle(idx == 0 ? .secondary : .tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer(minLength: DesignSpace.xs)
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(l10n.s.cleanerRevealInFinder)
                }
            }
        }
        .padding(DesignSpace.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignRadius.pill, style: .continuous)
                .fill(DesignSurfaceTier.card.fillColor(for: colorScheme))
        )
    }

    private func chooseDuplicatesFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            duplicatesRootURL = url
            startDuplicatesScan()
        }
    }

    private func startDuplicatesScan() {
        duplicatesScanTask?.cancel()
        duplicatesScanning = true
        let root = duplicatesRootURL
        duplicatesScanTask = Task {
            let found = await FastDuplicateScanner.scan(directoryURL: root, minBytes: 1024)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                duplicateGroups = found
                duplicatesHasScanned = true
                duplicatesScanning = false
            }
        }
    }

    private func trashDuplicateCopies(in group: DuplicateFileGroup) {
        guard group.urls.count > 1 else { return }
        let kept = group.urls[0]
        var remaining: [URL] = [kept]
        for duplicateURL in group.urls.dropFirst() {
            if (try? FileManager.default.trashItem(at: duplicateURL, resultingItemURL: nil)) == nil,
               FileManager.default.fileExists(atPath: duplicateURL.path) {
                remaining.append(duplicateURL)
            }
        }
        if let index = duplicateGroups.firstIndex(where: { $0.id == group.id }) {
            if remaining.count >= 2 {
                duplicateGroups[index] = DuplicateFileGroup(
                    id: group.id,
                    sha256Hex: group.sha256Hex,
                    byteSize: group.byteSize,
                    urls: remaining
                )
            } else {
                duplicateGroups.remove(at: index)
            }
        }
        SpaceLensDeepScanner.shared.invalidateCache(for: duplicatesRootURL)
    }

    // MARK: WhatsApp downloads (panel surface)

    private var whatsAppStrings: WhatsAppDownloadStrings {
        FeatureStrings.whatsAppDownloads(l10n.language)
    }

    private var whatsAppOptInCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(whatsAppStrings.title, isOn: $whatsAppEnabled)
                .font(.system(size: 12, weight: .medium))
            Text(whatsAppStrings.hubDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: 380, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    /// Collapsed summary: Off until the automation is armed, then the next
    /// pass, so the row answers "is it working?" without being opened.
    private var whatsAppSummary: String {
        guard whatsAppAutomatic else { return l10n.s.cleanerScheduleOff }
        if let next = whatsAppScheduler.nextFire {
            return Self.nextRunFormatter.string(from: next)
        }
        return whatsAppStrings.automatic
    }

    /// The cleanup's one-line home in the panel: state at a glance, the last
    /// and next pass when expanded, and a jump straight into its settings.
    private var whatsAppCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    whatsAppExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: whatsAppExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 9)
                    Image(systemName: "arrow.down.doc").foregroundStyle(.secondary)
                    Text(whatsAppStrings.title)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(whatsAppSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(11)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(whatsAppHovered ? 0.05 : 0))
                        .padding(2)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { whatsAppHovered = $0 }

            if whatsAppExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if whatsAppLastCleanup > 0 {
                        Text(String(format: whatsAppStrings.lastRunFormat,
                                    Self.nextRunFormatter.string(
                                        from: Date(timeIntervalSince1970: whatsAppLastCleanup)),
                                    whatsAppLastCount,
                                    Self.byteString(Int64(whatsAppLastBytes)),
                                    whatsAppLastFailed))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(whatsAppStrings.neverRun)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if whatsAppAutomatic, let next = whatsAppScheduler.nextFire {
                        Text(String(format: whatsAppStrings.nextRunFormat,
                                    Self.nextRunFormatter.string(from: next)))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Button(whatsAppStrings.manageButton) {
                        SettingsRouter.shared.cleanerTool = "whatsApp"
                        SettingsRouter.shared.request(FeatureSettingsDestination(.cleaner))
                        appDelegate()?.openSettingsWindow()
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 11)
                .padding(.top, 5)
                .padding(.bottom, 11)
            }
        }
        .frame(maxWidth: 380)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    // MARK: Automatic cleanup

    private var scheduleFrequency: CleanerSchedule.Frequency {
        CleanerSchedule.Frequency.sanitized(scheduleFrequencyRaw)
    }

    /// Whether the user's clock runs on twelve hours (6 PM) or twenty four
    /// (18:00); the pickers follow whatever the Mac is set to.
    private static let uses12HourClock: Bool = {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0,
                                              locale: Locale.current) ?? ""
        return format.contains("a")
    }()

    private static let dayPeriodSymbols: (am: String, pm: String) = {
        let formatter = DateFormatter()
        return (formatter.amSymbol ?? "AM", formatter.pmSymbol ?? "PM")
    }()

    /// The stored hour split for the twelve hour pickers: hour, then
    /// minutes, then AM or PM.
    private var scheduleHour12Binding: Binding<Int> {
        Binding(
            get: { CleanerSchedule.hour12Components(fromHour24: scheduleHour).hour12 },
            set: { newValue in
                let isPM = CleanerSchedule.hour12Components(fromHour24: scheduleHour).isPM
                scheduleHour = CleanerSchedule.hour24(hour12: newValue, isPM: isPM)
            }
        )
    }

    private var schedulePMBinding: Binding<Bool> {
        Binding(
            get: { CleanerSchedule.hour12Components(fromHour24: scheduleHour).isPM },
            set: { isPM in
                let hour12 = CleanerSchedule.hour12Components(fromHour24: scheduleHour).hour12
                scheduleHour = CleanerSchedule.hour24(hour12: hour12, isPM: isPM)
            }
        )
    }

    /// Five minute steps, plus the stored value when it falls off the grid.
    private var minuteChoices: [Int] {
        var minutes = Array(stride(from: 0, through: 55, by: 5))
        if !minutes.contains(scheduleMinute), (0...59).contains(scheduleMinute) {
            minutes.append(scheduleMinute)
            minutes.sort()
        }
        return minutes
    }

    private static let nextRunFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    private var scheduleSummary: String {
        switch scheduleFrequency {
        case .off: return l10n.s.cleanerScheduleOff
        case .daily: return l10n.s.cleanerScheduleDaily
        case .weekly: return l10n.s.cleanerScheduleWeekly
        }
    }

    private var frequencyPicker: some View {
        Picker("", selection: $scheduleFrequencyRaw) {
            Text(l10n.s.cleanerScheduleOff).tag(CleanerSchedule.Frequency.off.rawValue)
            Text(l10n.s.cleanerScheduleDaily).tag(CleanerSchedule.Frequency.daily.rawValue)
            Text(l10n.s.cleanerScheduleWeekly).tag(CleanerSchedule.Frequency.weekly.rawValue)
        }
        .labelsHidden()
        .fixedSize()
    }

    /// The schedule in one small card: a frequency and, once it is on, the
    /// weekday and time as plain menus, a live "next cleanup" line proving
    /// the schedule armed, and the notification choice with its permission
    /// state in the open. Hosted in the panels the card folds to one quiet
    /// line with the current state; the Settings page shows it whole.
    @ViewBuilder
    private var scheduleCard: some View {
        if compact {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        scheduleExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: scheduleExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 9)
                        Image(systemName: "clock").foregroundStyle(.secondary)
                        Text(l10n.s.cleanerScheduleTitle)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(scheduleSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(11)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(scheduleHovered ? 0.05 : 0))
                            .padding(2)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { scheduleHovered = $0 }

                if scheduleExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { frequencyPicker; Spacer() }
                        scheduleDetails
                        Text(l10n.s.cleanerScheduleCaption)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 11)
                    .padding(.top, 5)
                    .padding(.bottom, 11)
                }
            }
            .frame(maxWidth: 380)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
            .modifier(ScheduleChangeSync(notify: $scheduleNotify,
                                         frequency: $scheduleFrequencyRaw,
                                         hour: $scheduleHour,
                                         minute: $scheduleMinute,
                                         weekday: $scheduleWeekday,
                                         refresh: refreshNotificationStatus))
        } else {
            fullScheduleCard
        }
    }

    private var fullScheduleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "clock").foregroundStyle(.secondary)
                Text(l10n.s.cleanerScheduleTitle)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                frequencyPicker
            }
            scheduleDetails
            Text(l10n.s.cleanerScheduleCaption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: 380)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
        .modifier(ScheduleChangeSync(notify: $scheduleNotify,
                                     frequency: $scheduleFrequencyRaw,
                                     hour: $scheduleHour,
                                     minute: $scheduleMinute,
                                     weekday: $scheduleWeekday,
                                     refresh: refreshNotificationStatus))
    }

    @ViewBuilder
    private var scheduleDetails: some View {
        if scheduleFrequency != .off {
                // The menu panel is too narrow for the weekday beside the time
                // in most languages, and a row wider than the panel shifts all
                // of its content past the left edge, so the weekday then takes
                // its own row.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        weekdayPicker
                        timePickers
                        Spacer()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        weekdayPicker
                        HStack(spacing: 6) {
                            timePickers
                            Spacer()
                        }
                    }
                }
                Toggle(l10n.s.cleanerScheduleNotifyToggle, isOn: $scheduleNotify)
                    .toggleStyle(VorssaintCheckPillStyle())
                    .font(.system(size: 11.5))
                if scheduleNotify, notificationsDenied {
                    Text(l10n.s.cleanerNotifDenied)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(l10n.s.cleanerNotifOpenSettings) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
                if let next = scheduler.nextFire {
                    Text(String(format: l10n.s.cleanerScheduleNextFormat,
                                Self.nextRunFormatter.string(from: next)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if lastAutoRun > 0 {
                    Text(lastRunLine)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
        }
    }

    @ViewBuilder
    private var weekdayPicker: some View {
        if scheduleFrequency == .weekly {
            Picker("", selection: $scheduleWeekday) {
                ForEach(1...7, id: \.self) { day in
                    Text(Calendar.current.standaloneWeekdaySymbols[day - 1].capitalized)
                        .tag(day)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    /// The hour, the minutes and, on a twelve hour clock, AM or PM.
    @ViewBuilder
    private var timePickers: some View {
        if Self.uses12HourClock {
            Picker("", selection: scheduleHour12Binding) {
                ForEach(1...12, id: \.self) { hour in
                    Text(String(hour)).tag(hour)
                }
            }
            .labelsHidden()
            .fixedSize()
        } else {
            Picker("", selection: $scheduleHour) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(String(hour)).tag(hour)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
        Picker("", selection: $scheduleMinute) {
            ForEach(minuteChoices, id: \.self) { minute in
                Text(String(format: ":%02d", minute)).tag(minute)
            }
        }
        .labelsHidden()
        .fixedSize()
        if Self.uses12HourClock {
            Picker("", selection: schedulePMBinding) {
                Text(Self.dayPeriodSymbols.am).tag(false)
                Text(Self.dayPeriodSymbols.pm).tag(true)
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    /// The schedule card's reactions, shared by the folded and full forms:
    /// keep the scheduler armed with the latest picks, ask for notification
    /// permission on opt in, and re-read the permission whenever the app
    /// becomes active again (coming back from System Settings included).
    private struct ScheduleChangeSync: ViewModifier {
        @Binding var notify: Bool
        @Binding var frequency: String
        @Binding var hour: Int
        @Binding var minute: Int
        @Binding var weekday: Int
        let refresh: () -> Void

        func body(content: Content) -> some View {
            content
                .onAppear { refresh() }
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification)) { _ in
                    refresh()
                }
                .onChange(of: frequency) { _, _ in CleanerScheduler.shared.syncWithPreferences() }
                .onChange(of: hour) { _, _ in CleanerScheduler.shared.syncWithPreferences() }
                .onChange(of: minute) { _, _ in CleanerScheduler.shared.syncWithPreferences() }
                .onChange(of: weekday) { _, _ in CleanerScheduler.shared.syncWithPreferences() }
                .onChange(of: notify) { _, wanted in
                    if wanted { Notifier.requestPermission() }
                    refresh()
                }
        }
    }

    private var lastRunLine: String {
        let ranAt = Self.nextRunFormatter.string(from: Date(timeIntervalSince1970: lastAutoRun))
        let line = lastAutoFreed > 0
            ? String(format: l10n.s.cleanerScheduleLastFormat, Self.byteString(Int64(lastAutoFreed)))
            : String(format: l10n.s.cleanerScheduleRanFormat, ranAt)
        // A pass that moved nothing still reads as a normal run unless what it left is said.
        return lastAutoFailed > 0 ? line + " " + l10n.s.uninstallerSomeFailed : line
    }

    /// Checked slightly delayed so a just fired authorization prompt has a
    /// chance to be answered before the warning appears. The notification
    /// center only exists for real app bundles (bare test binaries have
    /// none and would throw).
    private func refreshNotificationStatus() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                DispatchQueue.main.async {
                    notificationsDenied = settings.authorizationStatus == .denied
                }
            }
        }
    }

    // MARK: Busy

    private func busyState(_ message: String, detail: String?) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: compact ? 24 : 0)
            SparkleGlyph(animating: true, size: compact ? 40 : 54)
            Text(message).foregroundStyle(.secondary)
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.tertiary)
            }
            if cleaner.phase == .scanning {
                Button(l10n.s.uninstallerCancel) { cleaner.reset() }
                    .controlSize(compact ? .small : .large)
            }
            Spacer(minLength: compact ? 24 : 0)
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 0 : 320)
    }

    // MARK: Results

    private var resultsState: some View {
        VStack(spacing: 0) {
            resultsHeader
            Divider()
            if cleaner.items.isEmpty {
                VStack(spacing: 10) {
                    Spacer(minLength: 24)
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.green)
                    Text(l10n.s.cleanerNothingFound)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 24)
                }
                .frame(maxWidth: .infinity)
            } else {
                if compact {
                    // The island, menu panel and launcher already scroll.
                    // Keep the rows and Clean button in that same scroll area.
                    VStack(alignment: .leading, spacing: 16) {
                        resultsGroups
                    }
                    .padding(12)
                } else {
                    List { resultsGroups }
                        .listStyle(.inset)
                }
                Divider()
                resultsFooter
            }
        }
    }

    @ViewBuilder
    private var resultsGroups: some View {
        section(l10n.s.cleanerSafeSection, groups: DisplayGroup.allCases.filter(\.isSafe))
        section(l10n.s.cleanerOptionalSection, groups: DisplayGroup.allCases.filter { !$0.isSafe })
    }

    private var resultsHeader: some View {
        HStack(spacing: 12) {
            SparkleGlyph(size: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.s.cleanerName).font(.system(size: 15, weight: .semibold))
                Text("\(Self.byteString(cleaner.totalSize)) \(l10n.s.uninstallerFoundTitle)")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            Spacer()
            PanelCloseButton(label: l10n.s.uninstallerCancel) { cleaner.reset() }
        }
        .padding(compact ? 12 : 16)
    }

    @ViewBuilder
    private func section(_ header: String, groups: [DisplayGroup]) -> some View {
        let visible = groups.filter { !items(for: $0).isEmpty }
        if !visible.isEmpty {
            if compact {
                VStack(alignment: .leading, spacing: 8) {
                    Text(header).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ForEach(visible) { group in
                        groupRow(group)
                        Divider()
                    }
                }
            } else {
                Section(header) {
                    ForEach(visible) { group in groupRow(group) }
                }
            }
        }
    }

    private func groupRow(_ group: DisplayGroup) -> some View {
        let group_items = items(for: group)
        return DisclosureGroup {
            if group == .leftovers {
                Text(l10n.s.cleanerLeftoversNote)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if group == .loginItems {
                Text(l10n.s.cleanerLoginItemsNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(group_items) { item in itemRow(item) }
        } label: {
            HStack(spacing: 10) {
                Toggle("", isOn: groupBinding(group)).labelsHidden().toggleStyle(VorssaintCheckPillStyle())
                Image(systemName: group.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title(for: group)).font(.system(size: 13, weight: .medium))
                    Text(caption(for: group))
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text(Self.byteString(group_items.reduce(0) { $0 + $1.size }))
                    .font(.system(size: 11.5)).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.vertical, 3)
        }
    }

    private func itemRow(_ item: JunkCleaner.Item) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: includeBinding(item)).labelsHidden().toggleStyle(VorssaintCheckPillStyle())
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                Text(prettyPath(item.url))
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer()
            Text(Self.byteString(item.size))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.leading, 8)
        .padding(.vertical, 1)
        .contextMenu {
            Button(l10n.s.cleanerRevealInFinder) {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        }
    }

    private var resultsFooter: some View {
        HStack {
            Text(String(format: l10n.s.uninstallerSelectedFormat,
                        cleaner.selectedCount, cleaner.items.count))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer()
            Button(l10n.s.uninstallerCancel) { cleaner.reset() }
            Button(String(format: l10n.s.cleanerCleanSizeFormat,
                          Self.byteString(cleaner.selectedSize))) {
                cleaner.cleanSelected(escalate: true)
            }
            .monospacedDigit()
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(cleaner.selectedCount == 0)
        }
        .padding(compact ? 12 : 16)
    }

    // MARK: Done

    private func doneState(freed: Int64, failed: Int) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: compact ? 20 : 0)
            MascotCameoBadge(
                mood: failed == 0 ? .happy : .determined,
                reaction: failed == 0 ? .celebrate : nil,
                tone: .tools,
                size: compact ? 38 : 50
            )
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: failed == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: compact ? 14 : 18, weight: .semibold))
                    .foregroundStyle(failed == 0 ? .green : .orange)
                    .background(Circle().fill(.background))
                    .offset(x: 2, y: 2)
            }
            Text(l10n.s.uninstallerDoneTitle).font(.system(size: compact ? 17 : 20, weight: .bold))
            Text(String(format: l10n.s.uninstallerFreedFormat, Self.byteString(freed)))
                .font(.system(size: 13)).monospacedDigit().foregroundStyle(.secondary)
            Text(l10n.s.cleanerDoneNote)
                .font(.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            if failed > 0 {
                Text(l10n.s.uninstallerSomeFailed)
                    .font(.caption).foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Button(l10n.s.cleanerAgain) { cleaner.reset() }
                .controlSize(.large)
                .padding(.top, 6)
            Spacer(minLength: compact ? 20 : 0)
        }
        .padding(compact ? 14 : 28)
        .frame(maxWidth: .infinity, minHeight: compact ? 0 : 320)
    }

    // MARK: Helpers

    private func includeBinding(_ item: JunkCleaner.Item) -> Binding<Bool> {
        Binding(
            get: { cleaner.items.first(where: { $0.id == item.id })?.include ?? false },
            set: { cleaner.setInclude($0, for: item.id) }
        )
    }

    private func groupBinding(_ group: DisplayGroup) -> Binding<Bool> {
        Binding(
            get: {
                let group_items = items(for: group)
                return !group_items.isEmpty && group_items.allSatisfy(\.include)
            },
            set: { include in
                for item in items(for: group) {
                    cleaner.setInclude(include, for: item.id)
                }
            }
        )
    }

    private func prettyPath(_ url: URL) -> String {
        url.deletingLastPathComponent().path
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private static func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// The cleaner hosted inside the menu panel or the quick panel, with the
/// shared header and close affordance of the other hosted utilities.
struct PanelCleanerView: View {
    @ObservedObject private var l10n = L10n.shared
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .font(.system(size: 13, weight: .semibold))
                Text(l10n.s.cleanerName)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                PanelCloseButton(label: l10n.s.menuClose) {
                    // Closing means cancel: a scan left running would come
                    // back on the next open. Cleaning in progress is left alone.
                    let cleaner = JunkCleaner.shared
                    if cleaner.phase == .scanning { cleaner.reset() }
                    onClose()
                }
            }
            CleanerView(compact: true)
        }
        .padding(2)
        .onAppear { PanelInteractionState.shared.viewKeepsPopoverOpen = true }
        .onDisappear { PanelInteractionState.shared.viewKeepsPopoverOpen = false }
    }
}
