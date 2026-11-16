// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AudioToolbox
@preconcurrency import AVFoundation
import Combine
import CoreAudioKit
import Foundation

/// Descriptor for a discovered system AUv3 / Audio Unit effect component.
struct MixerAudioUnitComponentItem: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let manufacturerName: String
    let componentDescription: AudioComponentDescription

    init(component: AVAudioUnitComponent) {
        let desc = component.audioComponentDescription
        self.id = Self.identifier(for: desc)
        self.name = component.name
        self.manufacturerName = component.manufacturerName
        self.componentDescription = desc
    }

    init(name: String, manufacturerName: String, componentDescription: AudioComponentDescription) {
        self.id = Self.identifier(for: componentDescription)
        self.name = name
        self.manufacturerName = manufacturerName
        self.componentDescription = componentDescription
    }

    static func identifier(for desc: AudioComponentDescription) -> String {
        "\(desc.componentType):\(desc.componentSubType):\(desc.componentManufacturer)"
    }

    static func == (lhs: MixerAudioUnitComponentItem, rhs: MixerAudioUnitComponentItem) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.manufacturerName == rhs.manufacturerName
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Discovers, instantiates, bypasses, and hosts native Cocoa UI for installed AUv3 Audio Unit effects.
@MainActor
final class MixerAudioUnitHost: ObservableObject {
    static let shared = MixerAudioUnitHost()

    private static let selectedEffectDefaultsKey = "vorssaintSelectedAudioUnitEffectID"
    private static let bypassedDefaultsKey = "vorssaintAudioUnitEffectBypassed"

    @Published private(set) var availableEffects: [MixerAudioUnitComponentItem] = []
    @Published private(set) var selectedEffectID: String?
    @Published private(set) var activeEffect: MixerAudioUnitComponentItem?
    @Published private(set) var activeAudioUnit: AVAudioUnit?
    @Published var isBypassed: Bool {
        didSet {
            UserDefaults.standard.set(isBypassed, forKey: Self.bypassedDefaultsKey)
            activeAudioUnit?.auAudioUnit.shouldBypassEffect = isBypassed
        }
    }
    @Published private(set) var isLoading = false
    @Published private(set) var isEditorWindowVisible = false
    @Published private(set) var lastError: String?

    private var editorWindow: NSWindow?
    private var windowCloseObserver: NSObjectProtocol?
    private var loadGeneration = 0
    private var hasScannedEffects = false

    private init() {
        self.selectedEffectID = UserDefaults.standard.string(forKey: Self.selectedEffectDefaultsKey)
        self.isBypassed = UserDefaults.standard.bool(forKey: Self.bypassedDefaultsKey)
    }

    func refreshAvailableEffects() {
        let shouldRestoreSaved = !hasScannedEffects
        hasScannedEffects = true
        DispatchQueue.global(qos: .userInitiated).async {
            let desc = AudioComponentDescription(componentType: kAudioUnitType_Effect,
                                                 componentSubType: 0,
                                                 componentManufacturer: 0,
                                                 componentFlags: 0,
                                                 componentFlagsMask: 0)
            let components = AVAudioUnitComponentManager.shared().components(matching: desc)
            var seen = Set<String>()
            var items: [MixerAudioUnitComponentItem] = []
            items.reserveCapacity(components.count)
            for component in components {
                let item = MixerAudioUnitComponentItem(component: component)
                guard seen.insert(item.id).inserted else { continue }
                items.append(item)
            }
            items.sort {
                let nameCmp = $0.name.localizedCaseInsensitiveCompare($1.name)
                if nameCmp != .orderedSame { return nameCmp == .orderedAscending }
                return $0.manufacturerName.localizedCaseInsensitiveCompare($1.manufacturerName) == .orderedAscending
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.availableEffects != items {
                    self.availableEffects = items
                }
                if shouldRestoreSaved,
                   let savedID = self.selectedEffectID,
                   self.activeAudioUnit == nil,
                   items.contains(where: { $0.id == savedID }) {
                    self.selectEffect(id: savedID)
                }
            }
        }
    }

    func selectEffect(id: String?) {
        guard let id, !id.isEmpty else {
            removeEffect()
            return
        }
        guard let item = availableEffects.first(where: { $0.id == id }) else {
            lastError = L10n.shared.language == .ru
                ? "Выбранный Audio Unit не найден"
                : "Selected Audio Unit is unavailable"
            return
        }
        if activeEffect?.id == item.id && activeAudioUnit != nil {
            return
        }

        loadGeneration &+= 1
        let generation = loadGeneration
        selectedEffectID = item.id
        UserDefaults.standard.set(item.id, forKey: Self.selectedEffectDefaultsKey)
        isLoading = true
        lastError = nil

        AVAudioUnit.instantiate(with: item.componentDescription, options: []) { [weak self] audioUnit, error in
            DispatchQueue.main.async {
                guard let self, self.loadGeneration == generation else { return }
                self.isLoading = false
                if let error {
                    self.activeAudioUnit = nil
                    self.activeEffect = nil
                    self.lastError = error.localizedDescription
                    return
                }
                guard let audioUnit else {
                    self.activeAudioUnit = nil
                    self.activeEffect = nil
                    self.lastError = L10n.shared.language == .ru
                        ? "Не удалось создать экземпляр Audio Unit"
                        : "Failed to instantiate Audio Unit"
                    return
                }
                audioUnit.auAudioUnit.shouldBypassEffect = self.isBypassed
                self.activeAudioUnit = audioUnit
                self.activeEffect = item
                self.lastError = nil
                if self.editorWindow?.isVisible == true {
                    self.attachViewController(for: audioUnit, title: item.name)
                }
            }
        }
    }

    func setBypassed(_ bypassed: Bool) {
        if isBypassed != bypassed {
            isBypassed = bypassed
        } else {
            activeAudioUnit?.auAudioUnit.shouldBypassEffect = bypassed
        }
    }

    func openEffectUI() {
        guard let audioUnit = activeAudioUnit else { return }
        let title = activeEffect?.name ?? audioUnit.name
        if let window = editorWindow, window.isVisible {
            window.title = title
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        attachViewController(for: audioUnit, title: title)
    }

    func closeEffectUI() {
        editorWindow?.orderOut(nil)
        editorWindow?.contentViewController = nil
        isEditorWindowVisible = false
    }

    func removeEffect() {
        loadGeneration &+= 1
        closeEffectUI()
        activeAudioUnit?.auAudioUnit.shouldBypassEffect = true
        activeAudioUnit = nil
        activeEffect = nil
        selectedEffectID = nil
        isLoading = false
        lastError = nil
        UserDefaults.standard.removeObject(forKey: Self.selectedEffectDefaultsKey)
    }

    private func attachViewController(for audioUnit: AVAudioUnit, title: String) {
        let targetUnitID = activeEffect?.id
        audioUnit.auAudioUnit.requestViewController { [weak self] viewController in
            DispatchQueue.main.async {
                guard let self, self.activeEffect?.id == targetUnitID else { return }
                let resolvedController: NSViewController
                if let viewController {
                    resolvedController = viewController
                } else {
                    let generic = AUGenericViewController()
                    generic.auAudioUnit = audioUnit.auAudioUnit
                    resolvedController = generic
                }
                self.presentEditorWindow(with: resolvedController, title: title)
            }
        }
    }

    private func presentEditorWindow(with viewController: NSViewController, title: String) {
        let window: NSWindow
        if let existing = editorWindow {
            window = existing
        } else {
            let created = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 340),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow],
                backing: .buffered,
                defer: false
            )
            created.level = .floating
            created.isReleasedWhenClosed = false
            created.collectionBehavior = [.moveToActiveSpace, .transient]
            editorWindow = created
            windowCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: created,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isEditorWindowVisible = false
                }
            }
            window = created
        }

        window.title = title
        window.contentViewController = viewController
        let preferredSize = viewController.preferredContentSize
        if preferredSize.width >= 180 && preferredSize.height >= 120 {
            window.setContentSize(NSSize(width: min(max(preferredSize.width, 320), 960),
                                         height: min(max(preferredSize.height, 200), 720)))
        }
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isEditorWindowVisible = true
    }
}
