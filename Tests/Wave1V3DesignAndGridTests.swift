// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum Wave1V3DesignAndGridContract {
    static func run(_ suite: TestSuite) {
        testDesignSpaceAndConcentricRadii(suite)
        testOverhaulV3LocalizationRules(suite)
        testZeroRawSwitchesOrGroupedForms(suite)
        testMenuPanelCalmChromeAndGeneratedSources(suite)
    }

    private static func testDesignSpaceAndConcentricRadii(_ suite: TestSuite) {
        suite.expect(DesignSpace.xs == 4
                     && DesignSpace.sm == 8
                     && DesignSpace.md == 12
                     && DesignSpace.lg == 16
                     && DesignSpace.xl == 20
                     && DesignSpace.xxl == 24
                     && DesignSpace.section == 32,
                     "DesignSpace defines the complete 4pt/8pt rhythm scale")
        suite.expect(DesignSpace.concentricInner(outer: DesignRadius.window, inset: DesignSpace.sm) == 12
                     && DesignSpace.concentricInner(outer: 8, inset: 8) == 4,
                     "concentricInner preserves concentric corner geometry with a 4pt floor")
        suite.expect(PanelDensityMode.allCases == [.calm, .pro],
                     "PanelDensityMode supports calm and pro progressive disclosure modes")
    }

    private static func testOverhaulV3LocalizationRules(_ suite: TestSuite) {
        let stringsSource = (try? String(contentsOfFile: "Sources/Vorssaint/Core/OverhaulV3Strings.swift", encoding: .utf8)) ?? ""
        suite.expect(!stringsSource.isEmpty
                     && !stringsSource.contains("'")
                     && !stringsSource.contains("\u{2014}"),
                     "OverhaulV3Strings contains zero ASCII apostrophes or em-dashes")

        for lang in AppLanguage.allCases {
            let localized = OverhaulV3Strings.localized(lang)
            suite.expect(!localized.panelDensityCalm.isEmpty
                         && !localized.audioChainTitle.isEmpty
                         && !localized.hidpiMirrorTitle.isEmpty
                         && !localized.menuBarManagerToggle.isEmpty
                         && !localized.clipboardFTSBadgeFormat.isEmpty
                         && !localized.spaceLensSunburstMode.isEmpty,
                         "OverhaulV3Strings populates every key for \(lang.rawValue)")
            let formatted = String(format: localized.clipboardFTSBadgeFormat, locale: Locale(identifier: "en_US_POSIX"), 500)
            suite.expect(formatted.contains("500"),
                         "clipboardFTSBadgeFormat formats count cleanly in \(lang.rawValue)")
        }

        let fr = OverhaulV3Strings.localized(.fr)
        suite.expect(fr.hidpiMirrorConfirmBanner.contains("\u{00A0}?"),
                     "French strings in OverhaulV3Strings place NBSP before question marks")
    }

    private static func testZeroRawSwitchesOrGroupedForms(_ suite: TestSuite) {
        let uiRoot = URL(fileURLWithPath: "Sources/Vorssaint/UI", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: uiRoot, includingPropertiesForKeys: nil) else {
            suite.expect(false, "UI directory is enumerable")
            return
        }
        var rawToggles: [String] = []
        var groupedForms: [String] = []
        var uiFiles = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            uiFiles += 1
            let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") { continue }
                if url.lastPathComponent == "SettingsCard.swift" && trimmed.contains(".toggleStyle(.switch)") {
                    continue
                }
                if trimmed.contains(".toggleStyle(.switch)") || trimmed.contains(".toggleStyle(.checkbox)") {
                    rawToggles.append(url.lastPathComponent)
                }
                if trimmed.contains(".formStyle(.grouped)") {
                    groupedForms.append(url.lastPathComponent)
                }
            }
        }
        suite.expect(uiFiles > 35 && rawToggles.isEmpty && groupedForms.isEmpty,
                     "Zero raw .toggleStyle(.switch/.checkbox) or .formStyle(.grouped) remain in \(uiFiles) UI files (toggles: \(rawToggles), forms: \(groupedForms))")
    }

    private static func testMenuPanelCalmChromeAndGeneratedSources(_ suite: TestSuite) {
        let menuPanel = (try? String(contentsOfFile: "Sources/Vorssaint/UI/MenuPanel/MenuPanelView.swift", encoding: .utf8)) ?? ""
        suite.expect(menuPanel.contains("menuPanelDensity")
                     && menuPanel.contains("PanelDensityMode"),
                     "MenuPanelView propagates Calm/Pro progressive disclosure density mode")

        let gridLint = (try? String(contentsOfFile: "Tools/grid-lint.sh", encoding: .utf8)) ?? ""
        suite.expect(gridLint.contains("DesignSpace") && gridLint.contains("VorssaintCompactSwitchStyle"),
                     "Tools/grid-lint.sh validates grid tokens and DesignKit controls")
    }
}
