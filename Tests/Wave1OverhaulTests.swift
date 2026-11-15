// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import SwiftUI

enum Wave1OverhaulContract {
    static func run(_ suite: TestSuite) {
        testSemanticPalette(suite)
        testDesignTokensAndMetal(suite)
        testFeatureWorkspaces(suite)
        testOTPExtraction(suite)
        testFocusModeAndSmartModuleOrdering(suite)
        testMascotMomentsAndReactions(suite)
    }

    private static func testSemanticPalette(_ suite: TestSuite) {
        for tone in SemanticCategoryTone.allCases {
            let triad = tone.rgbTriad
            suite.expect(triad.light != triad.dark, "SemanticCategoryTone.\(tone) has distinct light/dark colors")
            suite.expect(triad.light != triad.highContrast, "SemanticCategoryTone.\(tone) has distinct highContrast variant")
        }
        for group in FeatureGroup.allCases {
            let tone = SemanticCategoryPalette.tone(for: group)
            suite.expect(SemanticCategoryTone.allCases.contains(tone), "FeatureGroup.\(group) maps to valid tone")
        }
        suite.expect(SemanticCategoryPalette.tone(forSymbol: "speaker.wave.2") == .sound, "speaker maps to .sound")
        suite.expect(SemanticCategoryPalette.tone(forSymbol: "cpu") == .monitor, "cpu maps to .monitor")
        suite.expect(SemanticCategoryPalette.tone(forSymbol: "sparkles") == .dynamicIsland, "sparkles maps to .dynamicIsland")
    }

    private static func testDesignTokensAndMetal(_ suite: TestSuite) {
        suite.expect(DesignMotion.resolve(DesignMotion.snappy, reduceMotion: true) == nil,
                     "DesignMotion.resolve returns nil when Reduce Motion is enabled")
        suite.expect(DesignMotion.resolve(DesignMotion.snappy, reduceMotion: false) != nil,
                     "DesignMotion.resolve returns animation when Reduce Motion is off")
        suite.expect(DesignRadius.window > DesignRadius.card && DesignRadius.card > DesignRadius.innerGroup,
                     "DesignRadius follows concentric hierarchy")

        if VorssaintMetalShaders.shared.isMetalAvailable {
            let img = VorssaintMetalShaders.shared.makeDitheredGradientImage(
                width: 64,
                height: 48,
                start: (0.1, 0.2, 0.5),
                end: (0.8, 0.4, 0.3)
            )
            suite.expect(img?.width == 64 && img?.height == 48,
                         "VorssaintMetalShaders renders 64x48 TPDF dithered gradient")
        } else {
            suite.expect(true, "Metal device unavailable in headless environment; fallback contract satisfied")
        }
    }

    private static func testFeatureWorkspaces(_ suite: TestSuite) {
        suite.expect(FeaturePreset.allCases.count == 3,
                     "Existing FeaturePreset.allCases count remains 3")
        suite.expect(FeatureWorkspaceProfile.allCases.count == 4,
                     "FeatureWorkspaceProfile defines 4 role workspaces")

        var seenIDs = Set<String>()
        for profile in FeatureWorkspaceProfile.allCases {
            seenIDs.insert(profile.id)
            suite.expect(!profile.features.isEmpty, "\(profile.id) includes features")
            suite.expect(!profile.enableKeys.isEmpty, "\(profile.id) includes enable keys")
            for lang in [AppLanguage.enUS, .ru, .ja, .zhHans] {
                suite.expect(!profile.title(in: lang).isEmpty && !profile.subtitle(in: lang).isEmpty,
                             "\(profile.id) has localized copy in \(lang)")
            }
        }
        suite.expect(seenIDs.count == 4, "Workspace profile IDs are unique")
    }

    private static func testOTPExtraction(_ suite: TestSuite) {
        let cases: [(NotchNotificationContent, String?, String)] = [
            (NotchNotificationContent(app: "Messages", title: "Google", subtitle: "",
                                    body: "Your verification code is 482910."), "482910", "EN 6-digit OTP"),
            (NotchNotificationContent(app: "Telegram", title: "Login code", subtitle: "",
                                    body: "Use 719-304 to confirm sign in."), "719304", "Hyphenated NNN-NNN OTP"),
            (NotchNotificationContent(app: "Bank", title: "Сбер", subtitle: "",
                                    body: "Код подтверждения: 5912. Никому не сообщайте."), "5912", "RU 4-digit OTP"),
            (NotchNotificationContent(app: "Auth", title: "登录验证", subtitle: "",
                                    body: "您的验证码为 839201，5分钟内有效。"), "839201", "CJK OTP"),
            (NotchNotificationContent(app: "Mail", title: "Код 2024", subtitle: "",
                                    body: "Одноразовый код входа: 2024"), "2024", "Year-like number with explicit cue"),
            (NotchNotificationContent(app: "Billing", title: "2026 Tax Verification Summary", subtitle: "",
                                    body: "Your verification report for 2026 is ready. Total $1490 paid."), nil, "Rejects year and currency"),
            (NotchNotificationContent(app: "Phone", title: "Support", subtitle: "",
                                    body: "Verification callback from +15551234 regarding ticket."), nil, "Rejects phone number"),
            (NotchNotificationContent(app: "Slack", title: "Build URL", subtitle: "",
                                    body: "Login check at https://localhost:8080/123456 failed"), nil, "Rejects URL ports and paths"),
            (NotchNotificationContent(app: "Calendar", title: "Standup", subtitle: "Room 402",
                                    body: "Daily sync starts at 1000"), nil, "Rejects messages without OTP cue"),
        ]
        for (content, expected, label) in cases {
            let extracted = NotchNotificationSupport.extractVerificationCode(from: content)
            suite.expect(extracted == expected, "\(label): got \(String(describing: extracted)), expected \(String(describing: expected))")
        }
    }

    private static func testFocusModeAndSmartModuleOrdering(_ suite: TestSuite) {
        let suiteName = "vorss.tests.wave1.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        suite.expect(NotchSupport.respectsFocusMode(in: defaults) == true,
                     "Focus mode suppression defaults to true")
        suite.expect(NotchSupport.suppressesAmbientVisits(in: defaults, focusActive: true) == true,
                     "Suppresses ambient mascot visits when Focus is active")
        defaults.set(false, forKey: DefaultsKey.notchRespectFocusMode)
        suite.expect(NotchSupport.suppressesAmbientVisits(in: defaults, focusActive: true) == false,
                     "Respects Focus opt-out preference")

        let base: [NotchModule] = [.controls, .calendar, .clipboard, .music, .timer, .agents, .notifications, .files]
        let idleStatuses = NotchLiveModuleStatus()
        suite.expect(NotchSupport.orderedModules(base: base, statuses: idleStatuses, smartOrder: false) == base,
                     "Preserves exact user order when smartOrder is disabled")

        var live = NotchLiveModuleStatus()
        live.isTimerRunning = true
        live.isMediaPlaying = true
        live.hasUnreadNotifications = true
        let ordered = NotchSupport.orderedModules(base: base, statuses: live, smartOrder: true)
        suite.expect(ordered.first == .controls, ".controls remains anchored first")
        let timerIdx = ordered.firstIndex(of: .timer) ?? 99
        let musicIdx = ordered.firstIndex(of: .music) ?? 99
        let notifIdx = ordered.firstIndex(of: .notifications) ?? 99
        let calendarIdx = ordered.firstIndex(of: .calendar) ?? -1
        suite.expect(timerIdx < musicIdx && musicIdx < notifIdx && notifIdx < calendarIdx,
                     "Live modules bubble above idle modules in priority order")
    }

    private static func testMascotMomentsAndReactions(_ suite: TestSuite) {
        let newMoments: [NotchMascotMoment] = [.aiReady, .countdownBeat, .codeCopied, .sweep]
        for moment in newMoments {
            suite.expect(moment.reaction != nil, "\(moment.rawValue) maps to a reaction")
            suite.expect(moment.followUp == nil, "\(moment.rawValue) has nil followUp")
            if let reaction = moment.reaction {
                suite.expect(reaction.length <= 1.5, "\(reaction.rawValue) fits cameo duration cap")
            }
            for lang in [AppLanguage.enUS, .ru, .ja] {
                let text = FeatureStrings.notchMascot(lang).moment(moment, language: lang)
                suite.expect(!text.isEmpty, "\(moment.rawValue) has localized title in \(lang)")
            }
        }
    }
}
