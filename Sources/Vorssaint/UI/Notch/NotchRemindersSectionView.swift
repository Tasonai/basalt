// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import EventKit
import SwiftUI

/// Interactive Apple Reminders pane inside Basalt's Dynamic Island Daily Planner.
struct NotchRemindersPaneView: View {
    let now: Date
    let onQuickCreate: () -> Void
    let onRescheduleToday: (String) -> Void
    let onTimeBlockToday: (String) -> Void

    @Environment(\.notchSettingsPreview) private var preview
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var reminders = NotchRemindersService.shared
    @ObservedObject private var permissions = Permissions.shared
    @State private var filter: NotchReminderFilter = .all

    private var copy: NotchPlannerStrings { NotchPlannerStrings.localized(l10n.language) }
    private var calendarText: NotchCalendarStrings { FeatureStrings.notchCalendar(l10n.language) }

    private var overdueCount: Int {
        reminders.items.filter { !$0.isCompleted && NotchRemindersSupport.bucket(for: $0, now: now) == .overdue }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerSection
            if permissions.remindersAccess == .fullAccess {
                if reminders.loading {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    remindersList
                }
            } else {
                permissionCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if !preview { reminders.syncWithPreferences() }
        }
    }

    /// Two-tier compact header so long Russian/German filter pills never wrap or crush the title in narrow split columns.
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(copy.remindersTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if permissions.remindersAccess == .fullAccess {
                    Text("\(reminders.items.count)")
                        .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer(minLength: 4)
            }
            if permissions.remindersAccess == .fullAccess {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        filterChip(.all, label: copy.filterAll, badge: nil)
                        filterChip(.today, label: copy.filterToday, badge: nil)
                        filterChip(.overdue, label: copy.filterOverdue, badge: overdueCount > 0 ? overdueCount : nil)
                    }
                }
            }
        }
    }

    private func filterChip(_ target: NotchReminderFilter, label: String, badge: Int?) -> some View {
        let active = filter == target
        return Button {
            withAnimation(.snappy(duration: 0.18)) { filter = target }
        } label: {
            HStack(spacing: 3) {
                Text(label)
                    .font(.system(size: 9.5, weight: active ? .semibold : .medium))
                    .lineLimit(1)
                if let badge {
                    Text("\(badge)")
                        .font(.system(size: 8.5, weight: .bold).monospacedDigit())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 0.5)
                        .background(Color.red.opacity(0.85), in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.white.opacity(active ? 0.18 : 0.06), in: Capsule())
            .foregroundStyle(.white.opacity(active ? 1 : 0.68))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var remindersList: some View {
        let groups = NotchRemindersSupport.grouped(reminders.items, filter: filter, now: now)
        if groups.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.mint.opacity(0.75))
                Text(copy.emptyReminders)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.62))
                Button {
                    onQuickCreate()
                } label: {
                    Label(copy.addAction, systemImage: "plus")
                        .font(.system(size: 10.5, weight: .medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.1), in: Capsule())
                        .foregroundStyle(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(groups, id: \.bucket) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            bucketHeader(group.bucket, count: group.items.count)
                            ForEach(group.items) { item in
                                NotchReminderRow(
                                    item: item,
                                    bucket: group.bucket,
                                    copy: copy,
                                    onToggle: { reminders.toggleCompleted(item) },
                                    onMoveToday: { onRescheduleToday(item.id) },
                                    onTimeBlock: { onTimeBlockToday(item.id) },
                                    onOpenApp: openRemindersApp
                                )
                            }
                        }
                    }
                }
                .padding(.bottom, 2)
            }
            .scrollIndicators(.automatic)
            .notchScrollEdgeFade()
        }
    }

    private func bucketHeader(_ bucket: NotchReminderBucket, count: Int) -> some View {
        let title: String
        let accent: Color
        switch bucket {
        case .overdue: title = copy.bucketOverdue; accent = .red.opacity(0.95)
        case .today: title = copy.bucketToday; accent = .mint
        case .upcoming: title = copy.bucketUpcoming; accent = .white.opacity(0.6)
        case .anytime: title = copy.bucketAnytime; accent = .white.opacity(0.45)
        }
        return HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accent)
            Text("\(count)")
                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var permissionCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.75))
            Text(permissions.remindersAccess == .denied || permissions.remindersAccess == .restricted
                 ? copy.remindersDeniedPrompt
                 : copy.remindersPermissionPrompt)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if permissions.remindersAccess == .denied || permissions.remindersAccess == .restricted {
                    Button(copy.openRemindersSettings) { permissions.openRemindersSettings() }
                } else {
                    Button(copy.allowReminders) {
                        if !preview { NotchService.shared.open(.calendar) }
                        permissions.requestReminders()
                    }
                    .disabled(permissions.requestingReminders)
                }
                if permissions.requestingReminders { ProgressView().controlSize(.small) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            if permissions.remindersRequestFailed {
                Text(calendarText.requestFailed)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openRemindersApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Single draggable Apple Reminder row with hover checkmark preview and non-jittering trailing overlay action.
private struct NotchReminderRow: View {
    let item: NotchReminderItem
    let bucket: NotchReminderBucket
    let copy: NotchPlannerStrings
    let onToggle: () -> Void
    let onMoveToday: () -> Void
    let onTimeBlock: () -> Void
    let onOpenApp: () -> Void

    @State private var hovered = false
    @State private var hoveredCheck = false

    private var priorityMark: String? {
        switch item.priority {
        case 1...4: return "!!!"
        case 5: return "!!"
        case 6...9: return "!"
        default: return nil
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .fill(hoveredCheck ? item.color.color.opacity(0.28) : .clear)
                        .frame(width: 15, height: 15)
                    Circle()
                        .strokeBorder(item.color.color.opacity(0.95), lineWidth: 1.5)
                        .frame(width: 15, height: 15)
                    if hoveredCheck {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 24, height: 24)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { hoveredCheck = $0 }
            .accessibilityLabel("\(item.title), \(copy.kindReminder)")
            .accessibilityAddTraits(.isButton)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if let priorityMark {
                        Text(priorityMark)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.orange)
                    }
                    Text(item.title.isEmpty ? "—" : item.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 5) {
                    if let due = item.dueDate {
                        Group {
                            if item.hasDueTime {
                                Text(due, format: .dateTime.day().month(.abbreviated).hour().minute())
                            } else {
                                Text(due, format: .dateTime.day().month(.abbreviated))
                            }
                        }
                        .font(.system(size: 9.5).monospacedDigit())
                        .foregroundStyle(bucket == .overdue ? .red.opacity(0.95) : .white.opacity(0.6))
                    }
                    Text(item.listTitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(hovered ? 0.095 : 0.055))
        )
        .overlay(alignment: .trailing) {
            if hovered && bucket != .today {
                Button(action: onMoveToday) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.mint)
                        .frame(width: 24, height: 24)
                        .background(Color.black.opacity(0.72), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.75))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
                .help(copy.moveToTodayAction)
                .transition(.opacity)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(bucket == .overdue ? Color.red.opacity(0.24) : .white.opacity(0.06), lineWidth: 0.75)
        )
        .onHover { hovered = $0 }
        .draggable(NotchRemindersSupport.encodeDragPayload(reminderID: item.id))
        .contextMenu {
            Button(copy.moveToTodayAction, action: onMoveToday)
            Button(copy.timeBlockTodayAction, action: onTimeBlock)
            Divider()
            Button(copy.openRemindersApp, action: onOpenApp)
        }
    }
}

/// Live "NOW" HUD strip showing the ongoing meeting on two clean rows so titles never crush in narrow split columns.
struct NotchPlannerNowBannerView: View {
    let event: NotchCalendarEvent
    let progress: Double
    let remainingMinutes: Int
    let copy: NotchPlannerStrings
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.mint)
                            .frame(width: 6, height: 6)
                        Text(copy.nowBadge)
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                            .lineLimit(1)
                    }
                    .fixedSize()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.mint.opacity(0.18), in: Capsule())
                    .foregroundStyle(.mint)

                    Spacer(minLength: 4)

                    Text(String(format: copy.remainingMinutesFormat, remainingMinutes))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.mint.opacity(0.95))
                        .lineLimit(1)
                        .fixedSize()
                }

                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.12))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [event.color.color, .mint],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(4, geo.size.width * CGFloat(progress)))
                    }
                }
                .frame(height: 3)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(event.color.color.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.mint.opacity(0.32), lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Compact "Tomorrow" preview card shown at the bottom of Today's agenda.
struct NotchPlannerTomorrowStripView: View {
    let events: [NotchCalendarEvent]
    let copy: NotchPlannerStrings
    let onSelectTomorrow: () -> Void

    var body: some View {
        Button(action: onSelectTomorrow) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(copy.tomorrowTitle)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                    Spacer(minLength: 4)
                    Text("\(events.count)")
                        .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.38))
                }
                if events.isEmpty {
                    Text(copy.tomorrowEmpty)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.42))
                } else {
                    ForEach(events.prefix(2)) { ev in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(ev.color.color)
                                .frame(width: 5, height: 5)
                            if !ev.allDay {
                                Text(ev.start, format: .dateTime.hour().minute())
                                    .font(.system(size: 10).monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                            Text(ev.title)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.07), lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Inline ⌘N Quick Capture composer: full-width TextField on row 1, kind toggle & date presets on row 2.
struct NotchPlannerQuickCaptureBar: View {
    let copy: NotchPlannerStrings
    let defaultKind: NotchPlannerQuickCreateKind
    let onSubmit: (NotchPlannerQuickCreateKind, String, NotchPlannerQuickDatePreset, @escaping (Bool) -> Void) -> Void
    let onCancel: () -> Void

    @ObservedObject private var permissions = Permissions.shared
    @State private var kind: NotchPlannerQuickCreateKind
    @State private var title = ""
    @State private var preset: NotchPlannerQuickDatePreset = .today
    @State private var isSubmitting = false
    @FocusState private var titleFocused: Bool

    init(copy: NotchPlannerStrings,
         defaultKind: NotchPlannerQuickCreateKind,
         onSubmit: @escaping (NotchPlannerQuickCreateKind, String, NotchPlannerQuickDatePreset, @escaping (Bool) -> Void) -> Void,
         onCancel: @escaping () -> Void) {
        self.copy = copy
        self.defaultKind = defaultKind
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        _kind = State(initialValue: defaultKind)
    }

    private var presets: [NotchPlannerQuickDatePreset] {
        kind == .reminder ? [.today, .tomorrow, .inOneHour, .anytime] : [.today, .inOneHour, .tomorrow]
    }

    private var hasPermissionForSelectedKind: Bool {
        kind == .reminder
            ? permissions.remindersAccess == .fullAccess
            : permissions.calendarAccess == .fullAccess
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: kind == .reminder ? "checkmark.circle" : "calendar.badge.plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                TextField(
                    kind == .reminder ? copy.quickAddPlaceholderReminder : copy.quickAddPlaceholderEvent,
                    text: $title
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(.white)
                .focused($titleFocused)
                .disabled(isSubmitting)
                .onSubmit(submit)

                if hasPermissionForSelectedKind {
                    Button(action: submit) {
                        if isSubmitting {
                            ProgressView().controlSize(.mini)
                                .frame(width: 44, height: 18)
                        } else {
                            Text(copy.addAction)
                                .font(.system(size: 10.5, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize()
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                        }
                    }
                    .background(
                        NotchRemindersSupport.sanitizedTitle(title) != nil && !isSubmitting
                            ? Color.accentColor
                            : Color.white.opacity(0.12),
                        in: Capsule()
                    )
                    .foregroundStyle(.white)
                    .buttonStyle(.plain)
                    .disabled(NotchRemindersSupport.sanitizedTitle(title) == nil || isSubmitting)
                } else {
                    Button {
                        if kind == .reminder {
                            permissions.remindersAccess == .denied ? permissions.openRemindersSettings() : permissions.requestReminders()
                        } else {
                            permissions.calendarAccess == .denied ? permissions.openCalendarSettings() : permissions.requestCalendar()
                        }
                    } label: {
                        Text(kind == .reminder ? copy.allowReminders : copy.openRemindersSettings)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.28), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(width: 22, height: 22)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .help(copy.cancelAction)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    HStack(spacing: 2) {
                        kindPill(.reminder, label: copy.kindReminder, icon: "checkmark.circle")
                        kindPill(.event, label: copy.kindEvent, icon: "calendar")
                    }
                    .padding(2)
                    .background(.white.opacity(0.08), in: Capsule())

                    Rectangle()
                        .fill(.white.opacity(0.14))
                        .frame(width: 1, height: 14)

                    ForEach(presets, id: \.self) { option in
                        let active = preset == option
                        Button {
                            preset = option
                        } label: {
                            Text(presetLabel(option))
                                .font(.system(size: 9.5, weight: active ? .semibold : .medium))
                                .lineLimit(1)
                                .fixedSize()
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.white.opacity(active ? 0.18 : 0.06), in: Capsule())
                                .foregroundStyle(.white.opacity(active ? 1 : 0.65))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.white.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
        )
        .onAppear {
            DispatchQueue.main.async { titleFocused = true }
        }
        .onChange(of: kind) { _, newKind in
            if newKind == .event && preset == .anytime {
                preset = .today
            }
        }
    }

    private func kindPill(_ target: NotchPlannerQuickCreateKind, label: String, icon: String) -> some View {
        let active = kind == target
        return Button {
            withAnimation(.snappy(duration: 0.16)) { kind = target }
        } label: {
            Label(label, systemImage: icon)
                .font(.system(size: 10, weight: active ? .semibold : .medium))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.white.opacity(active ? 0.18 : 0), in: Capsule())
                .foregroundStyle(.white.opacity(active ? 1 : 0.65))
        }
        .buttonStyle(.plain)
    }

    private func presetLabel(_ option: NotchPlannerQuickDatePreset) -> String {
        switch option {
        case .today: return copy.presetToday
        case .tomorrow: return copy.presetTomorrow
        case .inOneHour: return copy.presetInOneHour
        case .anytime: return copy.presetAnytime
        }
    }

    private func submit() {
        guard !isSubmitting, hasPermissionForSelectedKind,
              let clean = NotchRemindersSupport.sanitizedTitle(title) else { return }
        isSubmitting = true
        onSubmit(kind, clean, preset) { ok in
            isSubmitting = false
            if ok { title = "" }
        }
    }
}
