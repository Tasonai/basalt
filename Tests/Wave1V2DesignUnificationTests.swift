// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum Wave1V2DesignUnificationContract {
    static func run(_ suite: TestSuite) {
        testDesignKitDetentMath(suite)
        testOverhaulV2LocalizationCoverage(suite)
        testZeroGroupedFormsRemainInUI(suite)
    }

    private static func testDesignKitDetentMath(_ suite: TestSuite) {
        let snappedToOne = VorssaintDesignKitMath.snappedDetentValue(
            rawValue: 1.02, range: 0...1.5, detent: 1.0
        )
        suite.expectClose(snappedToOne, 1.0, "VorssaintDetentSlider snaps cleanly inside detent window")

        let outsideDetent = VorssaintDesignKitMath.snappedDetentValue(
            rawValue: 1.25, range: 0...1.5, detent: 1.0
        )
        suite.expectClose(outsideDetent, 1.25, "VorssaintDetentSlider preserves raw value outside detent window")

        let zeroDB = VorssaintDesignKitMath.snappedDetentValue(
            rawValue: -0.3, range: -12...12, detent: 0.0
        )
        suite.expectClose(zeroDB, 0.0, "0 dB EQ detent snaps symmetrically around zero")

        suite.expect(VorssaintDesignKitMath.didCrossDetent(previous: 0.94, next: 1.00, detent: 1.0),
                     "Entering detent fires alignment feedback")
        suite.expect(VorssaintDesignKitMath.didCrossDetent(previous: -0.2, next: 0.2, detent: 0.0),
                     "Crossing through detent fires alignment feedback")
        suite.expect(!VorssaintDesignKitMath.didCrossDetent(previous: 0.2, next: 0.4, detent: 1.0),
                     "Movement away from detent stays silent")
    }

    private static func testOverhaulV2LocalizationCoverage(_ suite: TestSuite) {
        for lang in AppLanguage.allCases {
            let localized = OverhaulV2Strings.localized(lang)
            suite.expect(!localized.galleryTitle.isEmpty && !localized.bentoQuickTitle.isEmpty
                         && !localized.clopSavedBadgeFormat.isEmpty,
                         "OverhaulV2Strings populates core labels for \(lang.rawValue)")
            let renderedBadge = String(format: localized.clopSavedBadgeFormat, locale: Locale(identifier: "en_US_POSIX"), 42, "1.8 MB")
            suite.expect(!renderedBadge.isEmpty && renderedBadge.contains("42") && renderedBadge.contains("1.8 MB"),
                         "clopSavedBadgeFormat formats positional args in \(lang.rawValue)")
        }
    }

    private static func testZeroGroupedFormsRemainInUI(_ suite: TestSuite) {
        let uiRoot = URL(fileURLWithPath: "Sources/Vorssaint/UI", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: uiRoot, includingPropertiesForKeys: nil) else {
            suite.expect(false, "UI directory is enumerable")
            return
        }
        var groupedFiles: [String] = []
        var scannedCount = 0
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            scannedCount += 1
            let content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            if content.contains(".formStyle(.grouped)") {
                groupedFiles.append(fileURL.lastPathComponent)
            }
        }
        suite.expect(scannedCount > 30 && groupedFiles.isEmpty,
                     "Zero .formStyle(.grouped) views remain across \(scannedCount) UI files (found: \(groupedFiles))")
    }
}
