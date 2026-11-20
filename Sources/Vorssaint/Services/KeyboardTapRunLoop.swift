// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Shared user-interactive run loop that serves keyboard event taps off the
/// main thread.
///
/// Active keyboard taps hold each keystroke until their callback returns, so
/// running them on the main run loop would make system-wide typing wait behind
/// UI layout, Accessibility queries, or disk work. Consolidating independent
/// keyboard taps onto a single dedicated run loop preserves that isolation
/// while eliminating per-feature permanent NSThread / CFRunLoop stacks.
enum KeyboardTapRunLoop {
    /// Serves `source` on the shared keyboard tap thread. The tap callback runs
    /// there, so everything it touches must be safe away from the main thread.
    static func add(_ source: CFRunLoopSource) {
        CFRunLoopAddSource(runLoop, source, .commonModes)
    }

    /// Removes `source` and invalidates its port on the keyboard thread once any
    /// in-flight callback has returned. Never blocks the calling thread.
    static func remove(_ source: CFRunLoopSource, invalidating port: CFMachPort?) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            if let port {
                CFMachPortInvalidate(port)
            }
        }
        CFRunLoopWakeUp(runLoop)
    }

    /// Runs `work` asynchronously on the shared keyboard tap thread.
    static func perform(_ work: @escaping () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, work)
        CFRunLoopWakeUp(runLoop)
    }

    /// Underlying `CFRunLoop` for callers that need direct `CFRunLoopPerformBlock` scheduling.
    static var cfRunLoop: CFRunLoop { runLoop }

    /// Built on first use: if no keyboard tap ever activates, the thread never starts.
    private static let runLoop: CFRunLoop = {
        var started: CFRunLoop?
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            started = CFRunLoopGetCurrent()
            // Keep the run loop alive even while all keyboard taps are temporarily removed.
            RunLoop.current.add(NSMachPort(), forMode: .common)
            ready.signal()
            while true {
                CFRunLoopRunInMode(.defaultMode, .greatestFiniteMagnitude, false)
            }
        }
        thread.name = "Basalt Keyboard Input"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        return started!
    }()
}
