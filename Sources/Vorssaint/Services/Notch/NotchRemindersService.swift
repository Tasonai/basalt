// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import EventKit

/// Transient toast payload for planner mutations (supports error styling and 1-click Undo on completion).
struct NotchPlannerBanner: Equatable {
    let message: String
    let isError: Bool
    let undoReminder: NotchReminderItem?
}

/// Thread-safe holder for cancelling an in-flight `EKEventStore.fetchReminders` request on Task cancellation.
/// Guarantees that the Swift `CheckedContinuation` is resumed exactly once even when EventKit
/// drops the completion callback after `cancelFetchRequest(_:)`.
private final class RemindersFetchHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var token: Any?
    private var continuation: CheckedContinuation<[NotchReminderItem], Never>?
    private var cancelled = false
    private var resumed = false

    func install(continuation: CheckedContinuation<[NotchReminderItem], Never>) -> Bool {
        lock.lock()
        if cancelled || resumed {
            resumed = true
            lock.unlock()
            continuation.resume(returning: [])
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func store(_ token: Any?, cancel: (Any) -> Void) {
        lock.lock()
        let shouldCancel = cancelled
        if !shouldCancel { self.token = token }
        lock.unlock()
        if shouldCancel, let token { cancel(token) }
    }

    func resume(_ items: [NotchReminderItem]) {
        lock.lock()
        guard !resumed else {
            lock.unlock()
            return
        }
        resumed = true
        token = nil
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: items)
    }

    func cancel(_ cancelFn: (Any) -> Void) {
        lock.lock()
        cancelled = true
        let active = token
        token = nil
        let cont: CheckedContinuation<[NotchReminderItem], Never>?
        if !resumed {
            resumed = true
            cont = continuation
            continuation = nil
        } else {
            cont = nil
        }
        lock.unlock()
        if let active { cancelFn(active) }
        cont?.resume(returning: [])
    }
}

/// EventKit objects stay strictly inside one actor; only immutable value snapshots reach SwiftUI.
private actor NotchRemindersStore {
    private var store = EKEventStore()

    func resetStore() {
        store = EKEventStore()
    }

    func readIncomplete() async -> (items: [NotchReminderItem], lists: [NotchReminderList]) {
        guard !Task.isCancelled, EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            return ([], [])
        }
        let calendars = store.calendars(for: .reminder)
        let lists = calendars.map { cal in
            NotchReminderList(id: cal.calendarIdentifier, title: cal.title, color: Self.tint(cal))
        }
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: calendars
        )
        let handle = RemindersFetchHandle()
        let storeRef = store
        let items: [NotchReminderItem] = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard handle.install(continuation: continuation) else { return }
                let token = storeRef.fetchReminders(matching: predicate) { reminders in
                    let cal = Calendar.current
                    let mapped = (reminders ?? []).map { reminder -> NotchReminderItem in
                        let dueComponents = reminder.dueDateComponents
                        let hasTime = dueComponents?.hour != nil
                        let dueDate = dueComponents.flatMap { cal.date(from: $0) }
                        return NotchReminderItem(
                            id: reminder.calendarItemIdentifier,
                            title: reminder.title ?? "",
                            listID: reminder.calendar.calendarIdentifier,
                            listTitle: reminder.calendar.title,
                            dueDate: dueDate,
                            hasDueTime: hasTime,
                            isCompleted: reminder.isCompleted,
                            priority: reminder.priority,
                            color: Self.tint(reminder.calendar),
                            notes: reminder.notes ?? ""
                        )
                    }
                    handle.resume(mapped)
                }
                handle.store(token) { storeRef.cancelFetchRequest($0) }
            }
        } onCancel: {
            handle.cancel { storeRef.cancelFetchRequest($0) }
        }
        guard !Task.isCancelled else { return ([], lists) }
        return (NotchRemindersSupport.ordered(items), lists)
    }

    func setCompleted(_ completed: Bool, identifier: String) -> Bool {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess,
              let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            return false
        }
        reminder.isCompleted = completed
        reminder.completionDate = completed ? Date() : nil
        do {
            try store.save(reminder, commit: true)
            return true
        } catch {
            return false
        }
    }

    func reschedule(identifier: String, toDay day: Date) -> Bool {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess,
              let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            return false
        }
        let cal = Calendar.current
        let existingComps = reminder.dueDateComponents
        let hasTime = existingComps?.hour != nil
        let existingDate = existingComps.flatMap { cal.date(from: $0) }
        var updated = NotchRemindersSupport.rescheduleComponents(
            for: day,
            preserving: existingDate,
            hasDueTime: hasTime,
            calendar: cal
        )
        updated.calendar = cal
        updated.timeZone = hasTime ? cal.timeZone : nil
        reminder.dueDateComponents = updated
        if reminder.startDateComponents != nil {
            reminder.startDateComponents = updated
        }
        // Keep timed reminder alarms synchronized so Apple Reminders still fires notifications.
        if hasTime, let newDueDate = cal.date(from: updated) {
            if let alarms = reminder.alarms, !alarms.isEmpty {
                for alarm in alarms { reminder.removeAlarm(alarm) }
                reminder.addAlarm(EKAlarm(absoluteDate: newDueDate))
            }
        }
        do {
            try store.save(reminder, commit: true)
            return true
        } catch {
            return false
        }
    }

    func createReminder(title: String, dueDate: Date?, hasTime: Bool, listID: String?) -> Bool {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return false }
        let writableLists = store.calendars(for: .reminder).filter(\.allowsContentModifications)
        let targetList: EKCalendar?
        if let listID {
            targetList = writableLists.first { $0.calendarIdentifier == listID }
                ?? store.defaultCalendarForNewReminders()
                ?? writableLists.first
        } else {
            let def = store.defaultCalendarForNewReminders()
            targetList = (def?.allowsContentModifications == true ? def : nil) ?? writableLists.first
        }
        guard let calendar = targetList else { return false }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        reminder.title = title
        if let dueDate {
            let cal = Calendar.current
            var comps: DateComponents = hasTime
                ? cal.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
                : cal.dateComponents([.year, .month, .day], from: dueDate)
            comps.calendar = cal
            comps.timeZone = hasTime ? cal.timeZone : nil
            reminder.dueDateComponents = comps
            if hasTime {
                reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
            }
        }
        do {
            try store.save(reminder, commit: true)
            return true
        } catch {
            return false
        }
    }

    func createEvent(title: String, start: Date, end: Date, excludedCalendars: Set<String>) -> Bool {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return false }
        let writable = store.calendars(for: .event).filter(\.allowsContentModifications)
        let preferred: EKCalendar?
        if let def = store.defaultCalendarForNewEvents,
           def.allowsContentModifications,
           !excludedCalendars.contains(def.calendarIdentifier) {
            preferred = def
        } else {
            preferred = writable.first { !excludedCalendars.contains($0.calendarIdentifier) }
                ?? store.defaultCalendarForNewEvents
                ?? writable.first
        }
        guard let calendar = preferred else { return false }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.startDate = start
        event.endDate = max(end, start.addingTimeInterval(15 * 60))
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return true
        } catch {
            return false
        }
    }

    private static func tint(_ calendar: EKCalendar) -> NotchCalendarColor {
        let color = calendar.cgColor.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) }
        return color.map {
            NotchCalendarColor(red: $0.redComponent, green: $0.greenComponent, blue: $0.blueComponent)
        } ?? .fallback
    }
}

/// Manages Apple Reminders and quick creation/time-blocking for Basalt's Dynamic Island planner.
final class NotchRemindersService: NSObject, ObservableObject {
    static let shared = NotchRemindersService()

    @Published private(set) var items: [NotchReminderItem] = []
    @Published private(set) var lists: [NotchReminderList] = []
    @Published private(set) var loading = false
    @Published private(set) var statusBanner: NotchPlannerBanner?

    private var started = false
    private var storeActor: NotchRemindersStore?
    private var readTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var permissionSubscriptions: Set<AnyCancellable> = []
    private var generation = UUID()
    private var bannerClearWork: DispatchWorkItem?

    private override init() { super.init() }

    func syncWithPreferences() {
        guard NotchCalendarSupport.isEnabled() else { stop(); return }
        guard !started else { return }
        started = true
        if storeActor == nil { storeActor = NotchRemindersStore() }
        for name in [Notification.Name.EKEventStoreChanged, NSApplication.didBecomeActiveNotification,
                     .NSSystemClockDidChange, .NSSystemTimeZoneDidChange, .NSCalendarDayChanged] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in self?.refresh()
            })
        }
        Permissions.shared.$remindersAccess.removeDuplicates().dropFirst()
            .sink { [weak self] status in
                guard let self else { return }
                if status == .fullAccess {
                    // Fresh EKEventStore after TCC grant avoids stale empty-cache responses.
                    self.storeActor = NotchRemindersStore()
                }
                self.refresh()
            }
            .store(in: &permissionSubscriptions)
        Permissions.shared.$calendarAccess.removeDuplicates().dropFirst()
            .sink { [weak self] status in
                guard let self, status == .fullAccess else { return }
                self.storeActor = NotchRemindersStore()
            }
            .store(in: &permissionSubscriptions)
        refresh()
    }

    private func ensureActiveActor() -> NotchRemindersStore {
        if !started && NotchCalendarSupport.isEnabled() {
            syncWithPreferences()
        }
        if let existing = storeActor { return existing }
        let created = NotchRemindersStore()
        storeActor = created
        return created
    }

    func refresh() {
        readTask?.cancel()
        generation = UUID()
        guard NotchCalendarSupport.isEnabled() else { stop(); return }
        guard let storeActor else { return }
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            items = []
            lists = []
            loading = false
            return
        }
        let requested = generation
        loading = items.isEmpty
        readTask = Task { @MainActor [weak self] in
            let snapshot = await storeActor.readIncomplete()
            guard !Task.isCancelled, let self, self.generation == requested,
                  NotchCalendarSupport.isEnabled() else { return }
            guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
                self.items = []
                self.lists = []
                self.loading = false
                self.readTask = nil
                return
            }
            self.items = snapshot.items
            self.lists = snapshot.lists
            self.loading = false
            self.readTask = nil
        }
    }

    /// Optimistically marks a reminder complete/incomplete in Apple Reminders with 1-click Undo and safe single-item rollback.
    func toggleCompleted(_ item: NotchReminderItem) {
        let nextState = !item.isCompleted
        if nextState {
            items.removeAll { $0.id == item.id }
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        let actor = ensureActiveActor()
        Task { @MainActor [weak self] in
            let ok = await actor.setCompleted(nextState, identifier: item.id)
            guard let self, self.started, self.storeActor === actor else { return }
            if ok {
                if nextState {
                    self.showTransientBanner(
                        NotchPlannerBanner(
                            message: item.title.isEmpty ? "✓" : item.title,
                            isError: false,
                            undoReminder: item
                        ),
                        duration: 3.5
                    )
                }
            } else {
                // Re-insert only the single failed item instead of clobbering concurrent toggles.
                if nextState && !self.items.contains(where: { $0.id == item.id }) {
                    self.items = NotchRemindersSupport.ordered(self.items + [item])
                }
                self.showTransientBanner(
                    NotchPlannerBanner(
                        message: NotchPlannerStrings.localized(L10n.shared.language).saveFailed,
                        isError: true,
                        undoReminder: nil
                    )
                )
            }
        }
    }

    /// Undoes a recent 1-click completion directly from the toast pill.
    func undoCompletion(_ item: NotchReminderItem) {
        bannerClearWork?.cancel()
        statusBanner = nil
        let actor = ensureActiveActor()
        if !items.contains(where: { $0.id == item.id }) {
            items = NotchRemindersSupport.ordered(items + [item])
        }
        Task { @MainActor [weak self] in
            let ok = await actor.setCompleted(false, identifier: item.id)
            guard let self, self.started, self.storeActor === actor else { return }
            if !ok {
                self.refresh()
                self.showTransientBanner(
                    NotchPlannerBanner(
                        message: NotchPlannerStrings.localized(L10n.shared.language).saveFailed,
                        isError: true,
                        undoReminder: nil
                    )
                )
            }
        }
    }

    /// Reschedules a reminder onto `day` (e.g., dropped on "Today" or another calendar day).
    func reschedule(reminderID: String, toDay day: Date) {
        let actor = ensureActiveActor()
        Task { @MainActor [weak self] in
            let ok = await actor.reschedule(identifier: reminderID, toDay: day)
            guard let self, self.started else { return }
            if ok {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                self.showTransientBanner(
                    NotchPlannerBanner(
                        message: NotchPlannerStrings.localized(L10n.shared.language).rescheduledToast,
                        isError: false,
                        undoReminder: nil
                    )
                )
                self.refresh()
            } else {
                self.showTransientBanner(
                    NotchPlannerBanner(
                        message: NotchPlannerStrings.localized(L10n.shared.language).saveFailed,
                        isError: true,
                        undoReminder: nil
                    )
                )
            }
        }
    }

    /// Time-blocks a dropped reminder onto Apple Calendar (creating a calendar event + syncing its due day).
    func timeBlock(reminderID: String,
                   after event: NotchCalendarEvent?,
                   on targetDay: Date,
                   durationMinutes: Int = NotchRemindersSupport.defaultTimeBlockMinutes) {
        guard let item = items.first(where: { $0.id == reminderID }) else { return }
        let slot = NotchRemindersSupport.timeBlockInterval(
            after: event,
            on: targetDay,
            now: Date(),
            durationMinutes: durationMinutes
        )
        let excluded = NotchCalendarSupport.excludedCalendars()
        let actor = ensureActiveActor()
        Task { @MainActor [weak self] in
            let title = item.title.isEmpty
                ? FeatureStrings.notchCalendar(L10n.shared.language).untitled
                : item.title
            let eventCreated = await actor.createEvent(
                title: title,
                start: slot.start,
                end: slot.end,
                excludedCalendars: excluded
            )
            // Keep reminder due day aligned with the actual scheduled slot day (even across midnight).
            let reminderMoved = await actor.reschedule(identifier: reminderID, toDay: slot.start)
            guard let self, self.started else { return }
            if eventCreated {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                self.showTransientBanner(
                    NotchPlannerBanner(
                        message: NotchPlannerStrings.localized(L10n.shared.language).timeBlockedToast,
                        isError: false,
                        undoReminder: nil
                    )
                )
                self.refresh()
                NotchCalendarService.shared.refresh()
            } else if reminderMoved {
                self.showTransientBanner(
                    NotchPlannerBanner(
                        message: NotchPlannerStrings.localized(L10n.shared.language).saveFailed,
                        isError: true,
                        undoReminder: nil
                    )
                )
                self.refresh()
            } else {
                self.showTransientBanner(
                    NotchPlannerBanner(
                        message: NotchPlannerStrings.localized(L10n.shared.language).saveFailed,
                        isError: true,
                        undoReminder: nil
                    )
                )
            }
        }
    }

    /// Creates a new Apple Reminder or Calendar Event from the inline ⌘N Quick Capture composer.
    func quickCreate(kind: NotchPlannerQuickCreateKind,
                     rawTitle: String,
                     preset: NotchPlannerQuickDatePreset,
                     listID: String? = nil,
                     completion: @escaping (Bool) -> Void) {
        guard let title = NotchRemindersSupport.sanitizedTitle(rawTitle) else {
            completion(false)
            return
        }
        let resolved = NotchRemindersSupport.quickCreateDate(preset: preset, kind: kind, now: Date())
        let excluded = NotchCalendarSupport.excludedCalendars()
        let actor = ensureActiveActor()
        Task { @MainActor [weak self] in
            let ok: Bool
            switch kind {
            case .reminder:
                ok = await actor.createReminder(
                    title: title,
                    dueDate: resolved.date,
                    hasTime: resolved.hasTime,
                    listID: listID
                )
            case .event:
                let start = resolved.date ?? Date()
                let end = start.addingTimeInterval(TimeInterval(NotchRemindersSupport.defaultTimeBlockMinutes * 60))
                ok = await actor.createEvent(
                    title: title,
                    start: start,
                    end: end,
                    excludedCalendars: excluded
                )
            }
            guard let self else {
                completion(ok)
                return
            }
            if ok {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                self.showTransientBanner(
                    NotchPlannerBanner(
                        message: kind == .reminder
                            ? NotchPlannerStrings.localized(L10n.shared.language).reminderCreatedToast
                            : NotchPlannerStrings.localized(L10n.shared.language).eventCreatedToast,
                        isError: false,
                        undoReminder: nil
                    )
                )
                self.refresh()
                NotchCalendarService.shared.refresh()
            } else {
                self.showTransientBanner(
                    NotchPlannerBanner(
                        message: NotchPlannerStrings.localized(L10n.shared.language).saveFailed,
                        isError: true,
                        undoReminder: nil
                    )
                )
            }
            completion(ok)
        }
    }

    private func showTransientBanner(_ banner: NotchPlannerBanner, duration: TimeInterval = 2.4) {
        bannerClearWork?.cancel()
        statusBanner = banner
        let work = DispatchWorkItem { [weak self] in
            self?.statusBanner = nil
        }
        bannerClearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func stop() {
        started = false
        generation = UUID()
        readTask?.cancel()
        readTask = nil
        bannerClearWork?.cancel()
        bannerClearWork = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        permissionSubscriptions.removeAll()
        storeActor = nil
        items = []
        lists = []
        loading = false
        statusBanner = nil
    }
}
