// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import CoreGraphics

/// Swish-style titlebar scroll/swipe event tap.
///
/// Opt-in and gated by Accessibility permission and `"titlebarScrollGesturesEnabled"`.
/// Watches scroll wheel events over the top 30pt titlebar band of any standard
/// window under the pointer and maps vertical and horizontal swipes to minimize,
/// maximize, or half-screen snaps with cooldown debouncing.
final class TitlebarScrollTap: ObservableObject {
    static let shared = TitlebarScrollTap()
    static let preferenceKey = "titlebarScrollGesturesEnabled"
    static let titlebarHeight: CGFloat = 30

    @Published private(set) var isRunning = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var accumulatedX: Double = 0
    private var accumulatedY: Double = 0
    private var triggeredCurrentGesture = false
    private var lastTriggerUptime: TimeInterval = -.infinity

    private let cooldownInterval: TimeInterval = 0.45
    private let continuousSwipeThreshold: Double = 14.0
    private static let ownProcessID = Int64(getpid())

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in
            self?.syncWithPreferences()
        }
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
    }

    func syncWithPreferences() {
        let wanted = AppFeature.windowLayout.isAvailable
            && UserDefaults.standard.bool(forKey: Self.preferenceKey)
        if SessionActivitySupport.tapShouldRun(featureWanted: wanted,
                                               accessibilityGranted: AXIsProcessTrusted(),
                                               sessionIsActive: SessionActivity.shared.isActive) {
            start()
        } else {
            stop()
        }
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        tap = nil
        resetGestureTracking()
        isRunning = false
    }

    private func start() {
        guard tap == nil else {
            isRunning = true
            return
        }
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let createdTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<TitlebarScrollTap>.fromOpaque(userInfo).takeUnretainedValue()
                return monitor.handleEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            isRunning = false
            return
        }

        tap = createdTap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, createdTap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: createdTap, enable: true)
        isRunning = true
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if SessionActivity.shared.isActive,
               AXIsProcessTrusted(),
               UserDefaults.standard.bool(forKey: Self.preferenceKey),
               let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            } else {
                DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
            }
            resetGestureTracking()
            return Unmanaged.passUnretained(event)
        }

        guard type == .scrollWheel,
              AXIsProcessTrusted(),
              SessionActivity.shared.isActive,
              !ShortcutCapture.isCapturing,
              UserDefaults.standard.bool(forKey: Self.preferenceKey),
              event.getIntegerValueField(.eventSourceUnixProcessID) != Self.ownProcessID,
              event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty,
              event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0 else {
            return Unmanaged.passUnretained(event)
        }

        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let scrollPhase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        if isContinuous {
            if scrollPhase == 1 || scrollPhase == 32 { // began or mayBegin
                resetGestureTracking()
            } else if scrollPhase == 4 || scrollPhase == 8 { // ended or cancelled
                resetGestureTracking()
                return Unmanaged.passUnretained(event)
            }
        }

        let wheel = ScrollInverter.directionApplied(to: event)
        let deltaY = wheel.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let fixedDeltaY = wheel.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let scrollY = deltaY != 0 ? deltaY : Double(fixedDeltaY)

        let deltaX = wheel.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        let fixedDeltaX = wheel.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let scrollX = deltaX != 0 ? deltaX : Double(fixedDeltaX)

        let vecX: Double
        let vecY: Double
        if isContinuous {
            if triggeredCurrentGesture {
                return Unmanaged.passUnretained(event)
            }
            accumulatedX += scrollX
            accumulatedY += scrollY
            guard max(abs(accumulatedX), abs(accumulatedY)) >= continuousSwipeThreshold else {
                return Unmanaged.passUnretained(event)
            }
            vecX = accumulatedX
            vecY = accumulatedY
            triggeredCurrentGesture = true
        } else {
            guard abs(scrollY) >= 0.5 || abs(scrollX) >= 0.5 else {
                return Unmanaged.passUnretained(event)
            }
            vecX = scrollX
            vecY = scrollY
        }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTriggerUptime >= cooldownInterval else {
            return Unmanaged.passUnretained(event)
        }

        let quartzPoint = event.location
        DispatchQueue.main.async { [weak self] in
            self?.handleTitlebarSwipe(atQuartzPoint: quartzPoint, deltaX: vecX, deltaY: vecY)
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleTitlebarSwipe(atQuartzPoint quartzPoint: CGPoint,
                                     deltaX: Double,
                                     deltaY: Double) {
        guard AXIsProcessTrusted(),
              SessionActivity.shared.isActive,
              UserDefaults.standard.bool(forKey: Self.preferenceKey) else {
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTriggerUptime >= cooldownInterval else { return }

        let ownPID = pid_t(Self.ownProcessID)
        let windows = WindowServerSupport.onScreenWindowInfo()
        guard let candidate = WindowServerSupport.windowCandidate(
            in: windows,
            at: quartzPoint,
            ownProcessID: ownPID,
            pidIsEligible: { pid in
                guard let app = NSRunningApplication(processIdentifier: pid),
                      !app.isTerminated,
                      app.activationPolicy == .regular else {
                    return false
                }
                return !WindowLayoutIgnoredApps.shared.contains(
                    bundleID: app.bundleIdentifier,
                    executablePath: app.executableURL?.path
                )
            }
        ) else {
            return
        }

        let menuBarTopY = (NSScreen.screens.first {
            abs($0.frame.minX) < 0.5 && abs($0.frame.minY) < 0.5
        } ?? NSScreen.main ?? NSScreen.screens.first)?.frame.maxY ?? 0

        let cocoaPoint = CGPoint(x: quartzPoint.x, y: menuBarTopY - quartzPoint.y)
        let cocoaFrame = CGRect(x: candidate.frame.minX,
                                y: menuBarTopY - candidate.frame.maxY,
                                width: candidate.frame.width,
                                height: candidate.frame.height)

        if abs(deltaY) >= abs(deltaX) {
            let kind: TitlebarGestureService.GestureEventKind = deltaY < 0 ? .scrollDown : .scrollUp
            guard TitlebarGestureService.classify(point: cocoaPoint,
                                                  inWindowFrame: cocoaFrame,
                                                  titlebarHeight: Self.titlebarHeight,
                                                  eventKind: kind) != nil else {
                return
            }
            lastTriggerUptime = now
            if deltaY < 0 {
                if WindowLayoutService.shared.minimizeWindow(windowID: candidate.windowID,
                                                             processID: candidate.pid) {
                    VorssaintHaptics.alignment()
                }
            } else {
                if case .success = WindowLayoutService.shared.apply(.maximize,
                                                                     toWindowID: candidate.windowID,
                                                                     processID: candidate.pid) {
                    VorssaintHaptics.alignment()
                }
            }
        } else {
            guard TitlebarGestureService.classify(point: cocoaPoint,
                                                  inWindowFrame: cocoaFrame,
                                                  titlebarHeight: Self.titlebarHeight,
                                                  eventKind: .scrollUp) != nil else {
                return
            }
            lastTriggerUptime = now
            let action: WindowLayoutAction = deltaX > 0 ? .leftHalf : .rightHalf
            if case .success = WindowLayoutService.shared.apply(action,
                                                                 toWindowID: candidate.windowID,
                                                                 processID: candidate.pid) {
                VorssaintHaptics.alignment()
            }
        }
    }

    private func resetGestureTracking() {
        accumulatedX = 0
        accumulatedY = 0
        triggeredCurrentGesture = false
    }
}
