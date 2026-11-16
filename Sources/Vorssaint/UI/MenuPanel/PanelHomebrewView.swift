// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct PanelHomebrewView: View {
    private static let packageListTopID = "panel-homebrew-package-list-top"

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var homebrew = HomebrewManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.notchPresentation) private var inNotch
    @State private var query = ""
    @State private var searchKind: HomebrewPackageKind = .cask
    @State private var mode: PanelHomebrewMode = .search
    @State private var filter: PanelHomebrewFilter = .all
    @State private var pendingAction: HomebrewPendingAction?
    @State private var showOperationDetails = false

    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if homebrew.brewPath == nil {
                missingState
            } else {
                modePicker
                shellSetupCard
                if mode == .search {
                    searchControls
                    packageList(homebrew.searchResults,
                                emptyText: searchEmptyText,
                                isLoading: homebrew.isSearching
                                    || (!homebrew.searchResults.isEmpty && homebrew.isLoadingPopularity))
                } else {
                    installedControls
                    packageList(filteredInstalled,
                                emptyText: l10n.s.homebrewNoPackages,
                                isLoading: homebrew.isLoadingInstalled)
                }
                errorBanner
                detailCard
                operationCard
            }
        }
        .onAppear {
            if homebrew.installed.isEmpty {
                homebrew.refreshInstalled()
            }
        }
        .onChange(of: query) { _, _ in resetContextSelection() }
        .onChange(of: mode) { _, _ in resetContextSelection() }
        .onChange(of: filter) { _, _ in resetContextSelection() }
        .onChange(of: searchKind) { _, _ in resetContextSelection() }
        .onChange(of: homebrew.operationStatus?.targetID) { _, _ in
            showOperationDetails = false
        }
        .onDisappear {
            PanelInteractionState.shared.isPresentingPopoverModal = false
        }
        .confirmationDialog(confirmationTitle,
                            isPresented: confirmationPresented,
                            titleVisibility: .visible) {
            if let pendingAction {
                Button(actionTitle(for: pendingAction), role: pendingAction.action == .uninstall ? .destructive : nil) {
                    run(pendingAction)
                }
            }
            Button(l10n.s.uninstallerCancel, role: .cancel) {
                dismissConfirmation()
            }
        } message: {
            if let pendingAction {
                Text(confirmationBody(for: pendingAction))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(l10n.s.homebrewName, systemImage: "shippingbox")
                .font(.system(size: 12, weight: .semibold))
            if !homebrew.installed.isEmpty {
                Text(String(homebrew.installed.count))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Color.primary.opacity(0.07), in: Capsule())
            }
            Spacer()
            PanelCloseButton(action: onClose)
        }
    }

    private var missingState: some View {
        VStack(spacing: 10) {
            Image(systemName: "shippingbox")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text(l10n.s.homebrewMissingTitle)
                .font(.system(size: 13, weight: .semibold))
            Text(l10n.s.homebrewMissingBody)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VorssaintActionChip(title: l10n.s.homebrewInstallHomebrew,
                                symbol: "terminal",
                                tone: .clipboardFiles,
                                prominent: true) {
                homebrew.openHomebrewInstaller()
            }
            Text(homebrew.didOpenInstaller ? l10n.s.homebrewInstallHomebrewOpened : l10n.s.homebrewInstallHomebrewCaption)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let error = homebrew.errorMessage, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.orange)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VorssaintActionChip(title: l10n.s.homebrewRefresh,
                                symbol: "arrow.clockwise",
                                tone: .clipboardFiles) {
                homebrew.refreshInstalled()
            }
        }
        .frame(maxWidth: .infinity)
        .panelCard()
    }

    private var clipboardToneColor: Color {
        SemanticCategoryTone.clipboardFiles.color(
            scheme: colorScheme,
            highContrast: colorSchemeContrast == .increased
        )
    }

    private var modePicker: some View {
        VorssaintSegmentedTabs(
            selection: $mode,
            options: [
                .init(.search, title: l10n.s.homebrewSearchButton, symbol: "magnifyingglass"),
                .init(.installed, title: "\(l10n.s.homebrewInstalled) \(homebrew.installed.count)", symbol: "shippingbox"),
            ],
            tone: .clipboardFiles
        )
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var shellSetupCard: some View {
        if !homebrew.isShellConfigured {
            VStack(alignment: .leading, spacing: 7) {
                Label(l10n.s.homebrewShellSetupTitle, systemImage: "terminal")
                    .font(.system(size: 10.5, weight: .semibold))
                Text(homebrew.didOpenShellConfig ? l10n.s.homebrewShellSetupOpened : l10n.s.homebrewShellSetupBody)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 7) {
                    VorssaintActionChip(title: l10n.s.homebrewShellSetupButton,
                                        symbol: "wrench.and.screwdriver",
                                        tone: .clipboardFiles,
                                        prominent: true) {
                        homebrew.openShellConfiguration()
                    }
                    VorssaintActionChip(title: l10n.s.homebrewRefresh,
                                        symbol: "arrow.clockwise",
                                        tone: .clipboardFiles) {
                        homebrew.refreshShellConfigurationStatus()
                    }
                }
            }
            .panelCard()
        }
    }

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                PanelHomebrewSearchField(text: $query,
                                         placeholder: l10n.s.homebrewSearchPlaceholder,
                                         onSubmit: search)
                    .frame(height: 24)
                let searchDisabled = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || homebrew.isBusy
                Button {
                    VorssaintHaptics.generic()
                    search()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: DesignRadius.pill, style: .continuous)
                                .fill(clipboardToneColor)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: DesignRadius.pill, style: .continuous))
                }
                .buttonStyle(VorssaintScalePressButtonStyle(cornerRadius: DesignRadius.pill))
                .opacity(searchDisabled ? 0.45 : 1)
                .disabled(searchDisabled)
                .help(l10n.s.homebrewSearchButton)
                .accessibilityLabel(l10n.s.homebrewSearchButton)
            }
            VorssaintSegmentedTabs(
                selection: $searchKind,
                options: [
                    .init(.cask, title: l10n.s.homebrewCasks, symbol: "app"),
                    .init(.formula, title: l10n.s.homebrewFormulas, symbol: "terminal"),
                ],
                tone: .clipboardFiles
            )
        }
        .panelCard()
    }

    private var installedControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            VorssaintSegmentedTabs(
                selection: $filter,
                options: [
                    .init(.all, title: "\(l10n.s.homebrewAll) \(homebrew.installed.count)"),
                    .init(.cask, title: "\(l10n.s.homebrewCasks) \(installedCaskCount)"),
                    .init(.formula, title: "\(l10n.s.homebrewFormulas) \(installedFormulaCount)"),
                ],
                tone: .clipboardFiles
            )

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 7) {
                    installedActionChips
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 6) {
                    installedActionChips
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            outdatedSummary
        }
        .panelCard()
    }

    @ViewBuilder
    private var installedActionChips: some View {
        VorssaintActionChip(title: l10n.s.homebrewCheckPackages,
                            symbol: "arrow.clockwise",
                            tone: .clipboardFiles) {
            homebrew.refreshInstalled()
        }
        .help(l10n.s.homebrewCheckPackages)
        .disabled(homebrew.isBusy)

        VorssaintActionChip(title: l10n.s.homebrewUpdateHomebrew,
                            symbol: "arrow.triangle.2.circlepath",
                            tone: .clipboardFiles) {
            presentConfirmation(HomebrewPendingAction(action: .updateHomebrew))
        }
        .help(l10n.s.homebrewUpdateHomebrew)
        .disabled(homebrew.isBusy)
    }

    @ViewBuilder
    private var outdatedSummary: some View {
        if homebrew.isLoadingOutdated {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text(l10n.s.homebrewUpdates)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        } else if homebrew.outdatedCount > 0 {
            HStack(spacing: 7) {
                Label("\(l10n.s.homebrewUpdates) \(homebrew.outdatedCount)",
                      systemImage: "arrow.up.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
                Spacer(minLength: 0)
                VorssaintActionChip(title: l10n.s.homebrewUpgradeAll,
                                    symbol: "arrow.up.circle",
                                    tone: .energyDisplay,
                                    prominent: true) {
                    presentConfirmation(HomebrewPendingAction(action: .upgradeAll))
                }
                .help(l10n.s.homebrewUpgradeAll)
                .disabled(homebrew.isBusy)
            }
        } else {
            Label("\(l10n.s.homebrewUpdates) 0", systemImage: "checkmark.circle.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func packageList(_ packages: [HomebrewPackage],
                             emptyText: String,
                             isLoading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(mode == .search ? l10n.s.homebrewSearchResults : l10n.s.homebrewInstalled)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                if !isLoading {
                    countBadge(packages.count)
                }
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            if packages.isEmpty {
                Text(isLoading ? l10n.s.homebrewLoading : emptyText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 64)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 5) {
                            Color.clear
                                .frame(height: 0)
                                .id(Self.packageListTopID)
                            ForEach(packages) { package in
                                row(package)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: homebrew.operationStatus?.result) { _, result in
                        guard result == .succeeded,
                              homebrew.operationStatus?.action.clearsSelectionOnSuccess == true else { return }
                        proxy.scrollTo(Self.packageListTopID, anchor: .top)
                    }
                }
                .frame(height: 162)
            }
        }
        .panelCard()
    }

    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
    }

    private func row(_ package: HomebrewPackage) -> some View {
        HStack(spacing: 8) {
            Button {
                homebrew.select(package)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: package.kind == .formula ? "terminal" : "app")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 15)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(package.displayName)
                            .font(.system(size: 11.5, weight: selected(package) ? .semibold : .regular))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(package.versionText ?? package.name)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 0)
                    if let popularity = package.popularity {
                        popularityBadge(popularity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .buttonStyle(.plain)
            if activeStatus(for: package) != nil {
                ProgressView()
                    .controlSize(.mini)
            } else if let update = package.update {
                updateButton(package, update: update)
            } else if package.isInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
            } else {
                Button {
                    VorssaintHaptics.generic()
                    presentConfirmation(HomebrewPendingAction(action: .install, package: package))
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(clipboardToneColor)
                        .frame(width: 22, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(VorssaintScalePressButtonStyle(cornerRadius: 6))
                .disabled(homebrew.isBusy)
                .help(l10n.s.homebrewInstall)
                .accessibilityLabel(l10n.s.homebrewInstall)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected(package) ? clipboardToneColor.opacity(0.15) : Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(selected(package) ? clipboardToneColor.opacity(0.32) : Color.clear, lineWidth: 0.75)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contextMenu {
            packageContextMenu(package)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func updateButton(_ package: HomebrewPackage, update: HomebrewPackageUpdate) -> some View {
        Button {
            VorssaintHaptics.generic()
            presentConfirmation(HomebrewPendingAction(action: .upgrade, package: package))
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(VorssaintScalePressButtonStyle(cornerRadius: 6))
        .disabled(homebrew.isBusy)
        .help("\(l10n.s.homebrewUpgrade): \(update.versionSummary)")
        .accessibilityLabel(l10n.s.homebrewUpgrade)
    }

    @ViewBuilder
    private func packageContextMenu(_ package: HomebrewPackage) -> some View {
        let isBusy = homebrew.isBusy || activeStatus(for: package) != nil
        Button {
            homebrew.select(package)
        } label: {
            Label(l10n.s.homebrewDetailsTitle, systemImage: "info.circle")
        }
        if package.update != nil {
            Button {
                presentConfirmation(HomebrewPendingAction(action: .upgrade, package: package))
            } label: {
                Label(l10n.s.homebrewUpgrade, systemImage: "arrow.up.circle")
            }
            .disabled(isBusy)
        }
        if package.isInstalled {
            Button(role: .destructive) {
                presentConfirmation(HomebrewPendingAction(action: .uninstall, package: package))
            } label: {
                Label(l10n.s.homebrewUninstall, systemImage: "trash")
            }
            .disabled(isBusy)
        } else {
            Button {
                presentConfirmation(HomebrewPendingAction(action: .install, package: package))
            } label: {
                Label(l10n.s.homebrewInstall, systemImage: "arrow.down.circle")
            }
            .disabled(isBusy)
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let tap = homebrew.untrustedTap {
            HomebrewTrustCard(tap: tap, compact: true)
        }
        if let error = homebrew.errorMessage, !error.isEmpty {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .panelCard()
        }
    }

    @ViewBuilder
    private var detailCard: some View {
        if let package = homebrew.selectedPackage {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(package.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    statusBadge(package)
                    Spacer(minLength: 0)
                }
                if let desc = package.desc, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Text(package.name)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    if let version = package.versionText {
                        Text(version)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if let popularity = package.popularity {
                    Label(popularityDescription(popularity), systemImage: "chart.bar.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let update = package.update {
                    Label(update.versionSummary, systemImage: "arrow.up.circle.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .help(updateHelp(update))
                }
                if let homepage = package.homepage, let url = URL(string: homepage) {
                    Link(l10n.s.homebrewHomepage, destination: url)
                        .font(.system(size: 10.5))
                        .lineLimit(1)
                }
                HStack(spacing: 7) {
                    Spacer(minLength: 0)
                    detailActions(for: package)
                }
                .disabled(homebrew.isBusy)
            }
            .panelCard()
        } else {
            Text(l10n.s.homebrewNoSelection)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .panelCard()
        }
    }

    @ViewBuilder
    private var operationCard: some View {
        if let status = homebrew.operationStatus {
            HomebrewOperationStatusView(status: status,
                                        log: homebrew.log,
                                        terminalFallbackCommand: homebrew.terminalFallbackCommand,
                                        compact: true,
                                        showDetails: $showOperationDetails,
                                        onCancel: homebrew.cancelOperation,
                                        onClear: homebrew.clearLog,
                                        onOpenTerminal: homebrew.openTerminalFallback)
            .panelCard()
        }
    }

    @ViewBuilder
    private func detailActions(for package: HomebrewPackage) -> some View {
        if let status = activeStatus(for: package) {
            Label(activeActionTitle(for: status), systemImage: "hourglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        } else if package.isInstalled {
            if package.update != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 7) {
                        upgradeChip(for: package)
                        uninstallChip(for: package)
                    }
                    VStack(alignment: .trailing, spacing: 6) {
                        upgradeChip(for: package)
                        uninstallChip(for: package)
                    }
                }
            } else {
                uninstallChip(for: package)
            }
        } else {
            VorssaintActionChip(title: l10n.s.homebrewInstall,
                                symbol: "arrow.down.circle",
                                tone: .clipboardFiles,
                                prominent: true) {
                presentConfirmation(HomebrewPendingAction(action: .install, package: package))
            }
        }
    }

    private func upgradeChip(for package: HomebrewPackage) -> some View {
        VorssaintActionChip(title: l10n.s.homebrewUpgrade,
                            symbol: "arrow.up.circle",
                            tone: .energyDisplay,
                            prominent: true) {
            presentConfirmation(HomebrewPendingAction(action: .upgrade, package: package))
        }
    }

    private func uninstallChip(for package: HomebrewPackage) -> some View {
        VorssaintActionChip(title: l10n.s.homebrewUninstall,
                            symbol: "trash",
                            destructive: true) {
            presentConfirmation(HomebrewPendingAction(action: .uninstall, package: package))
        }
    }

    private func statusBadge(_ package: HomebrewPackage) -> some View {
        let active = activeStatus(for: package)
        let title = active.map { activeActionTitle(for: $0) }
            ?? (package.update != nil
                ? l10n.s.homebrewUpdateAvailableBadge
                : (package.isInstalled ? l10n.s.homebrewInstalledBadge : l10n.s.homebrewNotInstalledBadge))
        let color: Color = active != nil ? clipboardToneColor : (package.update != nil ? .orange : (package.isInstalled ? .green : .secondary))
        return Text(title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(color.opacity(0.12))
            )
    }

    private func popularityBadge(_ popularity: HomebrewPopularity) -> some View {
        Text(popularity.compactCount)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(clipboardToneColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(clipboardToneColor.opacity(0.12)))
            .help(popularityDescription(popularity))
    }

    private func updateHelp(_ update: HomebrewPackageUpdate) -> String {
        "\(l10n.s.homebrewUpdateAvailableBadge): \(update.versionSummary)"
    }

    private func popularityDescription(_ popularity: HomebrewPopularity) -> String {
        String(format: l10n.s.homebrewPopularityFormat,
               popularity.decimalCount,
               "\(popularity.days)")
    }

    private var searchEmptyText: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? l10n.s.homebrewNoSelection
            : l10n.s.homebrewSearchEmpty
    }

    private var filteredInstalled: [HomebrewPackage] {
        let packages: [HomebrewPackage]
        switch filter {
        case .all:
            packages = homebrew.installed
        case .formula:
            packages = homebrew.installed.filter { $0.kind == .formula }
        case .cask:
            packages = homebrew.installed.filter { $0.kind == .cask }
        }
        return HomebrewPackageOrdering.updatesFirst(packages)
    }

    private var installedCaskCount: Int {
        homebrew.installed.filter { $0.kind == .cask }.count
    }

    private var installedFormulaCount: Int {
        homebrew.installed.filter { $0.kind == .formula }.count
    }

    private var confirmationPresented: Binding<Bool> {
        Binding {
            pendingAction != nil
        } set: { isPresented in
            if !isPresented { dismissConfirmation() }
        }
    }

    private var confirmationTitle: String {
        guard let pendingAction else { return "" }
        return dialogTitle(for: pendingAction)
    }

    private func dialogTitle(for action: HomebrewPendingAction) -> String {
        switch action.action {
        case .install:
            return l10n.s.homebrewConfirmInstallTitle
        case .uninstall:
            return l10n.s.homebrewConfirmUninstallTitle
        case .upgrade:
            return l10n.s.homebrewConfirmUpgradeTitle
        case .upgradeAll:
            return l10n.s.homebrewConfirmUpgradeAllTitle
        case .updateHomebrew:
            return l10n.s.homebrewConfirmUpdateHomebrewTitle
        }
    }

    private func confirmationBody(for action: HomebrewPendingAction) -> String {
        if action.action == .updateHomebrew {
            return l10n.s.homebrewConfirmUpdateHomebrewBody
        }
        if action.action == .upgradeAll {
            return l10n.s.homebrewConfirmUpgradeAllBody
        }
        guard let package = action.package else { return "" }
        let format: String
        switch action.action {
        case .install:
            format = l10n.s.homebrewConfirmInstallBodyFormat
        case .uninstall:
            format = l10n.s.homebrewConfirmUninstallBodyFormat
        case .upgrade:
            format = l10n.s.homebrewConfirmUpgradeBodyFormat
        case .upgradeAll:
            return l10n.s.homebrewConfirmUpgradeAllBody
        case .updateHomebrew:
            return l10n.s.homebrewConfirmUpdateHomebrewBody
        }
        return String(format: format, package.displayName)
    }

    private func actionTitle(for action: HomebrewPendingAction) -> String {
        switch action.action {
        case .install: return l10n.s.homebrewInstall
        case .uninstall: return l10n.s.homebrewUninstall
        case .upgrade: return l10n.s.homebrewUpgrade
        case .upgradeAll: return l10n.s.homebrewUpgradeAll
        case .updateHomebrew: return l10n.s.homebrewUpdateHomebrew
        }
    }

    private func run(_ action: HomebrewPendingAction) {
        switch action.action {
        case .install:
            if let package = action.package { homebrew.install(package) }
        case .uninstall:
            if let package = action.package { homebrew.uninstall(package) }
        case .upgrade:
            if let package = action.package { homebrew.upgrade(package) }
        case .upgradeAll:
            homebrew.upgradeAll()
        case .updateHomebrew:
            homebrew.updateHomebrew()
        }
        dismissConfirmation()
    }

    private func search() {
        resetContextSelection()
        mode = .search
        homebrew.search(query: query, kind: searchKind)
    }

    private func selected(_ package: HomebrewPackage) -> Bool {
        homebrew.selectedPackage?.id == package.id
    }

    private func activeStatus(for package: HomebrewPackage) -> HomebrewOperationStatus? {
        guard let status = homebrew.operationStatus,
              status.isActive,
              status.package?.id == package.id else { return nil }
        return status
    }

    private func activeActionTitle(for status: HomebrewOperationStatus) -> String {
        switch status.action {
        case .install: return l10n.s.homebrewOperationInstalling
        case .uninstall: return l10n.s.homebrewOperationUninstalling
        case .upgrade: return l10n.s.homebrewOperationUpgrading
        case .upgradeAll: return l10n.s.homebrewOperationUpgrading
        case .updateHomebrew: return l10n.s.homebrewOperationRefreshing
        }
    }

    private func presentConfirmation(_ action: HomebrewPendingAction) {
        // The dialog would hang from the island as a sheet; there it asks on its own.
        guard !inNotch else {
            DispatchQueue.main.async {
                guard NSAlert.confirmAboveIsland(dialogTitle(for: action), message: confirmationBody(for: action),
                                                 action: actionTitle(for: action), destructive: action.action == .uninstall,
                                                 cancel: l10n.s.uninstallerCancel) else { return }
                run(action)
            }
            return
        }
        PanelInteractionState.shared.isPresentingPopoverModal = true
        pendingAction = action
    }

    private func dismissConfirmation() {
        pendingAction = nil
        PanelInteractionState.shared.isPresentingPopoverModal = false
    }

    private func resetContextSelection() {
        dismissConfirmation()
        showOperationDetails = false
        homebrew.clearSelection()
    }
}

private enum PanelHomebrewMode: String, CaseIterable, Identifiable {
    case search
    case installed

    var id: String { rawValue }
}

private enum PanelHomebrewFilter: String, CaseIterable, Identifiable {
    case all
    case cask
    case formula

    var id: String { rawValue }
}

private struct PanelHomebrewSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submitFromSearchField(_:))
        field.font = .systemFont(ofSize: 11)
        field.controlSize = .small
        field.placeholderString = placeholder
        field.sendsSearchStringImmediately = false
        field.sendsWholeSearchString = true
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        field.placeholderString = placeholder
        field.target = context.coordinator
        field.action = #selector(Coordinator.submitFromSearchField(_:))
        if field.stringValue != text {
            field.stringValue = text
        }
        context.coordinator.onSubmit = onSubmit
        context.coordinator.focusIfNeeded(field)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        @Binding var text: String
        var onSubmit: () -> Void
        private var didFocus = false

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text = field.stringValue
        }

        func control(_ control: NSControl,
                     textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                text = (control as? NSSearchField)?.stringValue ?? text
                submit()
                return true
            }
            return false
        }

        @objc func submitFromSearchField(_ sender: NSSearchField) {
            text = sender.stringValue
            submit()
        }

        private func submit() {
            onSubmit()
        }

        func focusIfNeeded(_ field: NSSearchField) {
            guard !didFocus else { return }
            DispatchQueue.main.async { [weak self, weak field] in
                guard let self, let field, let window = field.window else { return }
                window.makeFirstResponder(field)
                self.didFocus = true
            }
        }
    }
}
