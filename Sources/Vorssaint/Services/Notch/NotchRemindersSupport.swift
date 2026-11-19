// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Immutable display value for an Apple Reminder shown inside Basalt's Dynamic Island.
struct NotchReminderItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let listID: String
    let listTitle: String
    let dueDate: Date?
    let hasDueTime: Bool
    let isCompleted: Bool
    /// EventKit priority: 0 = none, 1...4 = high, 5 = medium, 6...9 = low.
    let priority: Int
    let color: NotchCalendarColor
    let notes: String
}

/// Immutable descriptor for an Apple Reminders list.
struct NotchReminderList: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let color: NotchCalendarColor
}

/// Time-oriented buckets mirroring focused daily-HUD planners.
enum NotchReminderBucket: Int, CaseIterable, Equatable, Hashable, Sendable {
    case overdue = 0
    case today = 1
    case upcoming = 2
    case anytime = 3
}

/// Quick filter pills for the Reminders pane.
enum NotchReminderFilter: String, CaseIterable, Equatable, Sendable {
    case all
    case today
    case overdue
}

/// Split-view proportion between Calendar and Reminders inside Dynamic Island.
enum NotchPlannerSplitRatio: String, CaseIterable, Equatable, Sendable {
    case calendarOnly
    case calendarFocus   // 70 / 30
    case balanced        // 50 / 50
    case remindersFocus  // 30 / 70
    case remindersOnly

    var calendarFraction: Double {
        switch self {
        case .calendarOnly: return 1.0
        case .calendarFocus: return 0.70
        case .balanced: return 0.50
        case .remindersFocus: return 0.30
        case .remindersOnly: return 0.0
        }
    }

    var remindersFraction: Double { 1.0 - calendarFraction }

    var showsCalendar: Bool { self != .remindersOnly }
    var showsReminders: Bool { self != .calendarOnly }
    var isSplit: Bool { showsCalendar && showsReminders }

    var shortLabel: String {
        switch self {
        case .calendarOnly: return "100/0"
        case .calendarFocus: return "70/30"
        case .balanced: return "50/50"
        case .remindersFocus: return "30/70"
        case .remindersOnly: return "0/100"
        }
    }

    func next() -> NotchPlannerSplitRatio {
        let all = Self.allCases
        guard let idx = all.firstIndex(of: self) else { return .balanced }
        return all[(idx + 1) % all.count]
    }

    static func sanitized(_ raw: String?) -> NotchPlannerSplitRatio {
        raw.flatMap(Self.init(rawValue:)) ?? .balanced
    }
}

/// Kind of item created by the inline ⌘N Quick Capture composer.
enum NotchPlannerQuickCreateKind: String, CaseIterable, Equatable, Sendable {
    case reminder
    case event
}

/// Fast date/time presets in the ⌘N Quick Capture composer.
enum NotchPlannerQuickDatePreset: String, CaseIterable, Equatable, Sendable {
    case today
    case tomorrow
    case inOneHour
    case anytime
}

/// Snapshot of what is happening RIGHT NOW plus a compact Tomorrow preview.
struct NotchPlannerNowAndTomorrow: Equatable, Sendable {
    let activeEvent: NotchCalendarEvent?
    /// Progress `0...1` through `activeEvent`, nil when no timed event is active.
    let activeProgress: Double?
    let remainingMinutes: Int?
    let tomorrowEvents: [NotchCalendarEvent]
}

/// Pure, testable planning logic for Basalt's Monolith-class Dynamic Island HUD.
enum NotchRemindersSupport {
    static let dragPayloadPrefix = "basalt-reminder:"
    static let minimumSplitWidth: Double = 360
    static let defaultTimeBlockMinutes = 30

    /// Encodes a reminder identifier for drag-and-drop rescheduling / time-blocking.
    static func encodeDragPayload(reminderID: String) -> String {
        dragPayloadPrefix + reminderID
    }

    /// Decodes a dropped string payload back into a reminder identifier, rejecting foreign strings.
    static func decodeDragPayload(_ payload: String) -> String? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(dragPayloadPrefix) else { return nil }
        let id = String(trimmed.dropFirst(dragPayloadPrefix.count))
        return id.isEmpty ? nil : id
    }

    /// Categorizes an incomplete reminder relative to `now`.
    static func bucket(for item: NotchReminderItem,
                       now: Date,
                       calendar: Calendar = .current) -> NotchReminderBucket {
        guard let due = item.dueDate else { return .anytime }
        let startOfToday = calendar.startOfDay(for: now)
        if item.hasDueTime {
            if due < now { return .overdue }
            if calendar.isDate(due, inSameDayAs: now) { return .today }
            return .upcoming
        } else {
            let dueDay = calendar.startOfDay(for: due)
            if dueDay < startOfToday { return .overdue }
            if dueDay == startOfToday { return .today }
            return .upcoming
        }
    }

    /// Sorts reminders cleanly: earlier due date first, then higher priority (1 before 5 before 9 before 0), then title.
    static func ordered(_ items: [NotchReminderItem]) -> [NotchReminderItem] {
        items.sorted { lhs, rhs in
            switch (lhs.dueDate, rhs.dueDate) {
            case let (l?, r?) where l != r:
                return l < r
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                let lp = normalizedPriorityRank(lhs.priority)
                let rp = normalizedPriorityRank(rhs.priority)
                if lp != rp { return lp < rp }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        }
    }

    /// Maps EventKit's 0=none, 1..9=high..low into a sortable rank where high=1, med=2, low=3, none=4.
    static func normalizedPriorityRank(_ priority: Int) -> Int {
        switch priority {
        case 1...4: return 1
        case 5: return 2
        case 6...9: return 3
        default: return 4
        }
    }

    /// Groups incomplete reminders into ordered buckets respecting the active filter pill.
    static func grouped(_ items: [NotchReminderItem],
                        filter: NotchReminderFilter = .all,
                        now: Date,
                        calendar: Calendar = .current) -> [(bucket: NotchReminderBucket, items: [NotchReminderItem])] {
        let incomplete = items.filter { !$0.isCompleted }
        var map: [NotchReminderBucket: [NotchReminderItem]] = [:]
        for item in incomplete {
            let b = bucket(for: item, now: now, calendar: calendar)
            switch filter {
            case .all:
                map[b, default: []].append(item)
            case .today:
                if b == .overdue || b == .today {
                    map[b, default: []].append(item)
                }
            case .overdue:
                if b == .overdue {
                    map[b, default: []].append(item)
                }
            }
        }
        return NotchReminderBucket.allCases.compactMap { b in
            guard let list = map[b], !list.isEmpty else { return nil }
            return (bucket: b, items: ordered(list))
        }
    }

    /// Computes exact column widths for split-view planner layouts, guaranteeing neither visible column collapses.
    static func columnWidths(totalWidth: Double,
                             spacing: Double,
                             ratio: NotchPlannerSplitRatio) -> (calendar: Double, reminders: Double) {
        let usable = max(0, totalWidth)
        guard ratio.isSplit else {
            return ratio == .calendarOnly ? (usable, 0) : (0, usable)
        }
        let available = max(0, usable - spacing)
        let minCol = min(140, available * 0.32)
        let rawCal = available * ratio.calendarFraction
        let cal = min(max(rawCal, minCol), max(minCol, available - minCol))
        let rem = max(0, available - cal)
        return (cal, rem)
    }

    /// Computes the "NOW" active event + progress + remaining minutes and Tomorrow's upcoming events.
    static func nowAndTomorrow(events: [NotchCalendarEvent],
                               now: Date,
                               calendar: Calendar = .current) -> NotchPlannerNowAndTomorrow {
        let active = events
            .filter { !$0.allDay && $0.start <= now && $0.end > now }
            .sorted { $0.end < $1.end }
            .first

        let progress: Double?
        let remainingMinutes: Int?
        if let active {
            let total = active.end.timeIntervalSince(active.start)
            let elapsed = now.timeIntervalSince(active.start)
            progress = total > 0 ? min(max(elapsed / total, 0), 1) : 0
            remainingMinutes = max(1, Int(ceil(active.end.timeIntervalSince(now) / 60)))
        } else {
            progress = nil
            remainingMinutes = nil
        }

        let startOfToday = calendar.startOfDay(for: now)
        let tomorrowDay = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        let tomorrowEvents = NotchCalendarSupport.events(events, on: tomorrowDay, calendar: calendar)

        return NotchPlannerNowAndTomorrow(
            activeEvent: active,
            activeProgress: progress,
            remainingMinutes: remainingMinutes,
            tomorrowEvents: tomorrowEvents
        )
    }

    /// Computes updated `DateComponents` when a reminder is dragged onto `targetDay` (preserving time if it had one).
    static func rescheduleComponents(for targetDay: Date,
                                     preserving existingDueDate: Date?,
                                     hasDueTime: Bool,
                                     calendar: Calendar = .current) -> DateComponents {
        var comps = calendar.dateComponents([.year, .month, .day], from: targetDay)
        if hasDueTime, let existingDueDate {
            let time = calendar.dateComponents([.hour, .minute], from: existingDueDate)
            comps.hour = time.hour
            comps.minute = time.minute
        }
        return comps
    }

    /// Computes a clean time-block interval when a reminder is dropped onto a calendar event or a calendar day.
    static func timeBlockInterval(after event: NotchCalendarEvent?,
                                  on targetDay: Date,
                                  now: Date,
                                  durationMinutes: Int = defaultTimeBlockMinutes,
                                  calendar: Calendar = .current) -> DateInterval {
        let duration = TimeInterval(max(15, durationMinutes) * 60)
        if let event, !event.allDay, event.end > now {
            return DateInterval(start: event.end, duration: duration)
        }
        if calendar.isDate(targetDay, inSameDayAs: now) {
            // Next clean 15-minute slot from now.
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
            let minute = comps.minute ?? 0
            let nextQuarter = ((minute / 15) + 1) * 15
            let base = calendar.date(from: comps) ?? now
            let start = calendar.date(byAdding: .minute, value: nextQuarter - minute, to: base) ?? now
            return DateInterval(start: start, duration: duration)
        } else {
            // 10:00 AM on the target day.
            var comps = calendar.dateComponents([.year, .month, .day], from: targetDay)
            comps.hour = 10
            comps.minute = 0
            let start = calendar.date(from: comps) ?? targetDay
            return DateInterval(start: start, duration: duration)
        }
    }

    /// Resolves a date for the ⌘N Quick Capture composer preset.
    static func quickCreateDate(preset: NotchPlannerQuickDatePreset,
                                kind: NotchPlannerQuickCreateKind,
                                now: Date,
                                calendar: Calendar = .current) -> (date: Date?, hasTime: Bool) {
        switch preset {
        case .today:
            if kind == .event {
                let slot = timeBlockInterval(after: nil, on: now, now: now, calendar: calendar)
                return (slot.start, true)
            }
            return (calendar.startOfDay(for: now), false)
        case .tomorrow:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            if kind == .event {
                var comps = calendar.dateComponents([.year, .month, .day], from: tomorrow)
                comps.hour = 10
                comps.minute = 0
                return (calendar.date(from: comps) ?? tomorrow, true)
            }
            return (tomorrow, false)
        case .inOneHour:
            let target = now.addingTimeInterval(3600)
            return (target, true)
        case .anytime:
            if kind == .event {
                let slot = timeBlockInterval(after: nil, on: now, now: now, calendar: calendar)
                return (slot.start, true)
            }
            return (nil, false)
        }
    }

    /// Trims user-entered quick-capture titles and rejects empty/whitespace-only strings.
    static func sanitizedTitle(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(240))
    }

    static func splitRatio(in defaults: UserDefaults = .standard) -> NotchPlannerSplitRatio {
        NotchPlannerSplitRatio.sanitized(defaults.string(forKey: DefaultsKey.notchPlannerSplitRatio))
    }

    static func isSwapped(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.notchPlannerSwapped)
    }
}
