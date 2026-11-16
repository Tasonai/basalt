// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AppIntents
import Foundation

/// Parsed automation action from a `vorssaint://` URL or Shortcuts `AppIntent`.
enum VorssaintAutomationCommand: Equatable, Sendable {
    case clean
    case clipboardSearch(query: String)
    case recordStart
    case recordStop
    case screenshotArea
    case workspaceApply(name: String)
    case mixerPreset(name: String)
    case displayBrightness(percent: Int)
}

/// Central dispatcher for `vorssaint://` URL schemes and Shortcuts / AppIntents automation.
@MainActor
final class VorssaintAutomationRouter {
    static let shared = VorssaintAutomationRouter()

    private init() {}

    nonisolated static func parseCommand(from url: URL) -> VorssaintAutomationCommand? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "vorssaint" else {
            return nil
        }

        let host = (components.host ?? "").lowercased()
        let path = components.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        let route = host.isEmpty ? path : (path.isEmpty ? host : "\(host)/\(path)")

        func queryValue(_ name: String) -> String? {
            components.queryItems?.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.value
        }

        switch route {
        case "clean":
            return .clean
        case "clipboard/search":
            return .clipboardSearch(query: queryValue("q") ?? "")
        case "record/start":
            return .recordStart
        case "record/stop":
            return .recordStop
        case "screenshot/area":
            return .screenshotArea
        case "workspace/apply":
            guard let rawName = queryValue("name")?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawName.isEmpty else {
                return nil
            }
            return .workspaceApply(name: rawName)
        case "mixer/preset":
            guard let rawName = queryValue("name")?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawName.isEmpty else {
                return nil
            }
            return .mixerPreset(name: rawName)
        case "display/brightness":
            guard let rawValue = queryValue("value") ?? queryValue("percent"),
                  let parsed = Int(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return nil
            }
            return .displayBrightness(percent: min(100, max(0, parsed)))
        default:
            return nil
        }
    }

    @discardableResult
    func handle(url: URL) -> Bool {
        guard let command = Self.parseCommand(from: url) else {
            return false
        }
        execute(command)
        return true
    }

    func execute(_ command: VorssaintAutomationCommand) {
        switch command {
        case .clean:
            SettingsRouter.shared.request(FeatureSettingsDestination(.cleaner))
            JunkCleaner.shared.scan(attended: true)

        case .clipboardSearch(let query):
            ClipboardHistoryService.shared.showHistoryWindow(preferNotch: false)
            if !query.isEmpty {
                ClipboardHistoryService.shared.quickQuery = query
            }

        case .recordStart:
            if !ScreenRecorderService.shared.hasActiveCapture {
                ScreenCaptureService.shared.capture(initial: .recording)
            }

        case .recordStop:
            _ = ScreenRecorderService.shared.stopOrCancelActiveCapture()

        case .screenshotArea:
            ScreenshotService.shared.capture()

        case .workspaceApply(let name):
            let presets = WindowWorkspaceStore.shared.presets
            if let preset = presets.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
                ?? presets.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) {
                WindowLayoutService.shared.applyWorkspacePreset(preset)
            }

        case .mixerPreset(let name):
            let presets = CustomEQPresetStore.shared.allPresets
            if let preset = presets.first(where: {
                $0.id.caseInsensitiveCompare(name) == .orderedSame
                    || $0.name.caseInsensitiveCompare(name) == .orderedSame
            }) {
                AppVolumeMixer.shared.applyEQPreset(preset, for: nil)
            }

        case .displayBrightness(let percent):
            let level = min(1.0, max(0.0, Double(percent) / 100.0))
            let displays = BrightnessService.shared.displays.filter(\.isActive)
            for display in displays {
                BrightnessService.shared.setBrightness(level, for: display.id, showOSD: true)
            }
        }
    }
}

@available(macOS 14.0, *)
struct CleanSystemCachesIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan System Caches"
    static let description = IntentDescription("Scans macOS system caches and junk categories with Vorssaint Cleaner.")

    @MainActor
    func perform() async throws -> some IntentResult {
        VorssaintAutomationRouter.shared.execute(.clean)
        return .result()
    }
}

@available(macOS 14.0, *)
struct CaptureAreaScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Area Screenshot"
    static let description = IntentDescription("Starts an interactive area screenshot capture in Vorssaint.")

    @MainActor
    func perform() async throws -> some IntentResult {
        VorssaintAutomationRouter.shared.execute(.screenshotArea)
        return .result()
    }
}

@available(macOS 14.0, *)
struct ApplyWorkspaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Apply Window Workspace"
    static let description = IntentDescription("Restores a saved multi-window workspace layout by name.")

    @Parameter(title: "Workspace Name")
    var name: String

    @MainActor
    func perform() async throws -> some IntentResult {
        VorssaintAutomationRouter.shared.execute(.workspaceApply(name: name))
        return .result()
    }
}

@available(macOS 14.0, *)
struct SetDisplayBrightnessIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Display Brightness"
    static let description = IntentDescription("Sets active display brightness to a target percentage.")

    @Parameter(title: "Brightness Percent")
    var percent: Int

    @MainActor
    func perform() async throws -> some IntentResult {
        VorssaintAutomationRouter.shared.execute(.displayBrightness(percent: min(100, max(0, percent))))
        return .result()
    }
}

@available(macOS 14.0, *)
struct VorssaintShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CleanSystemCachesIntent(),
            phrases: [
                "Scan system caches with \(.applicationName)",
                "Clean caches in \(.applicationName)"
            ],
            shortTitle: "Scan Caches",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: CaptureAreaScreenshotIntent(),
            phrases: [
                "Capture area screenshot with \(.applicationName)",
                "Take screenshot in \(.applicationName)"
            ],
            shortTitle: "Capture Area",
            systemImageName: "camera.viewfinder"
        )
        AppShortcut(
            intent: ApplyWorkspaceIntent(),
            phrases: [
                "Apply workspace with \(.applicationName)"
            ],
            shortTitle: "Apply Workspace",
            systemImageName: "macwindow.on.rectangle"
        )
        AppShortcut(
            intent: SetDisplayBrightnessIntent(),
            phrases: [
                "Set display brightness with \(.applicationName)"
            ],
            shortTitle: "Display Brightness",
            systemImageName: "sun.max"
        )
    }
}
