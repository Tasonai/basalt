// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import EventKit

struct NotchCalendarView: View {
    let size: CGSize
    @Environment(\.notchSettingsPreview) private var preview
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var calendar = NotchCalendarService.shared
    @ObservedObject private var reminders = NotchRemindersService.shared
    @ObservedObject private var notch = NotchService.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.notchCalendarCountdown) private var countdownForEvery = false
    @AppStorage(DefaultsKey.notchPlannerSplitRatio) private var splitRatioRaw = NotchPlannerSplitRatio.balanced.rawValue
    @AppStorage(DefaultsKey.notchPlannerSwapped) private var plannerSwapped = false
    @Environment(\.notchBand) private var band
    /// The day the month grid or the week strip is built around.
    @State private var focus = Date()
    @State private var selectedDay: Date?
    /// The strip's month grid, in place of the strip and the cards.
    @State private var showingMonth = false
    @State private var showingQuickCapture = false
    @State private var hoveringTodayDrop = false
    @State private var hoveringDayDrop: Date?
    @State private var hoveringEventDropID: String?
    private var text: NotchCalendarStrings { FeatureStrings.notchCalendar(l10n.language) }
    private var plannerCopy: NotchPlannerStrings { NotchPlannerStrings.localized(l10n.language) }
    private var splitRatio: NotchPlannerSplitRatio { NotchPlannerSplitRatio.sanitized(splitRatioRaw) }
    private var canSplitHorizontally: Bool { size.width >= NotchRemindersSupport.minimumSplitWidth }
    private var effectiveRatio: NotchPlannerSplitRatio {
        if canSplitHorizontally { return splitRatio }
        return splitRatio == .remindersOnly ? .remindersOnly : .calendarOnly
    }
    /// A month grid needs six rows beside an agenda; anything shorter shows
    /// the week as a strip above a vertical agenda.
    private var showsMonth: Bool {
        !effectiveRatio.showsReminders && size.height >= 300 && size.width >= 420
    }

    private var quickCaptureDefaultKind: NotchPlannerQuickCreateKind {
        if effectiveRatio == .calendarOnly && permissions.calendarAccess == .fullAccess {
            return .event
        }
        if permissions.remindersAccess == .fullAccess {
            return .reminder
        }
        return permissions.calendarAccess == .fullAccess ? .event : .reminder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showingQuickCapture {
                NotchPlannerQuickCaptureBar(
                    copy: plannerCopy,
                    defaultKind: quickCaptureDefaultKind,
                    onSubmit: { kind, title, preset, done in
                        reminders.quickCreate(kind: kind, rawTitle: title, preset: preset) { ok in
                            done(ok)
                            if ok {
                                withAnimation(.snappy(duration: 0.18)) { showingQuickCapture = false }
                            }
                        }
                    },
                    onCancel: {
                        withAnimation(.snappy(duration: 0.18)) { showingQuickCapture = false }
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            TimelineView(.everyMinute) { context in
                plannerBody(now: context.date)
                    .onChange(of: Calendar.current.startOfDay(for: context.date)) { _, _ in
                        if selectedDay == nil { focus = context.date }
                    }
            }
        }
        .overlay(alignment: .bottom) {
            if let banner = reminders.statusBanner {
                HStack(spacing: 7) {
                    Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(banner.isError ? .orange : .mint)
                    Text(banner.message)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(1)
                    if let undoItem = banner.undoReminder {
                        Button(l10n.s.uninstallerCancel) {
                            reminders.undoCompletion(undoItem)
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.mint)
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.84), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.75))
                .padding(.bottom, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // The month's name and planner controls head the page from the island's top row.
        .notchBand { monthTitle } trailing: { navigation }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Day and month names follow the app's language; the order of the
        // date and the 12/24-hour clock follow the user's region.
        .environment(\.locale, l10n.language.formattingLocale())
        .onAppear {
            if ownsMonth { calendar.showMonth(focus) }
            if !preview { reminders.syncWithPreferences() }
        }
        .onChange(of: focus) { previous, date in
            // A month read already covers every week of that month, so
            // moving the strip within it keeps the loaded events.
            if !Calendar.current.isDate(previous, equalTo: date, toGranularity: .month) { calendar.showMonth(date) }
        }
        .onChange(of: notch.calendarQuickCreateSerial) { _, _ in
            guard !preview else { return }
            withAnimation(.snappy(duration: 0.18)) { showingQuickCapture.toggle() }
        }
        .onChange(of: showingQuickCapture) { _, active in
            guard !preview else { return }
            NotchService.shared.setCalendarQuickCaptureActive(active)
        }
        // Escape closes Quick Capture or the month grid before closing the island.
        .onChange(of: showingQuickCapture || (showingMonth && !showsMonth)) { _, hasLayer in
            guard !preview else { return }
            if hasLayer {
                NotchService.shared.setPageLayer(.calendar) {
                    withAnimation(.snappy(duration: 0.18)) {
                        if showingQuickCapture {
                            showingQuickCapture = false
                        } else if showingMonth {
                            showingMonth = false
                        }
                    }
                }
            } else {
                NotchService.shared.setPageLayer(.calendar, close: nil)
            }
        }
        .onDisappear {
            showingQuickCapture = false
            if ownsMonth { calendar.showMonth(nil) }
            if !preview {
                NotchService.shared.setCalendarQuickCaptureActive(false)
                NotchService.shared.setPageLayer(.calendar, close: nil)
                calendar.revealing = nil
            }
        }
    }

    @ViewBuilder
    private func plannerBody(now: Date) -> some View {
        let ratio = effectiveRatio
        if ratio.isSplit {
            let spacing: CGFloat = 12
            let dividerWidth: CGFloat = 1
            let widths = NotchRemindersSupport.columnWidths(
                totalWidth: Double(max(0, size.width - dividerWidth)),
                spacing: Double(spacing),
                ratio: ratio
            )
            HStack(alignment: .top, spacing: spacing / 2) {
                if plannerSwapped {
                    remindersColumn(now: now)
                        .frame(width: CGFloat(widths.reminders))
                    Rectangle().fill(.white.opacity(0.12)).frame(width: dividerWidth)
                        .accessibilityHidden(true)
                    calendarColumn(now: now, compact: true)
                        .frame(width: CGFloat(widths.calendar))
                } else {
                    calendarColumn(now: now, compact: true)
                        .frame(width: CGFloat(widths.calendar))
                    Rectangle().fill(.white.opacity(0.12)).frame(width: dividerWidth)
                        .accessibilityHidden(true)
                    remindersColumn(now: now)
                        .frame(width: CGFloat(widths.reminders))
                }
            }
        } else if ratio == .remindersOnly {
            remindersColumn(now: now)
        } else {
            calendarColumn(now: now, compact: false)
        }
    }

    @ViewBuilder
    private func calendarColumn(now: Date, compact: Bool) -> some View {
        if permissions.calendarAccess == .fullAccess {
            let summary = NotchRemindersSupport.nowAndTomorrow(events: calendar.events, now: now)
            VStack(alignment: .leading, spacing: 8) {
                if let active = summary.activeEvent,
                   let progress = summary.activeProgress,
                   let remaining = summary.remainingMinutes {
                    NotchPlannerNowBannerView(
                        event: active,
                        progress: progress,
                        remainingMinutes: remaining,
                        copy: plannerCopy
                    ) {
                        openCalendar(showing: active)
                    }
                }

                if effectiveRatio.showsReminders {
                    todayDropZone(now: now)
                }

                if !compact && showsMonth {
                    HStack(alignment: .top, spacing: 16) {
                        ScrollView { monthView(now: now) }
                            .scrollIndicators(.automatic)
                            .frame(width: 196)
                        Rectangle().fill(.white.opacity(0.12)).frame(width: 1)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 12) {
                            agendaHeader
                            agenda(now: now, tomorrowEvents: summary.tomorrowEvents)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                } else if showingMonth {
                    monthGrid(now: now)
                } else {
                    VStack(alignment: .leading, spacing: compact ? 6 : NotchLayout.rowSpacing) {
                        if compact {
                            compactAgendaHeader
                        } else {
                            weekStrip(now: now)
                        }
                        agenda(now: now, tomorrowEvents: summary.tomorrowEvents)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            permissionCard
        }
    }

    private var compactAgendaHeader: some View {
        HStack(spacing: 6) {
            Group {
                if let selectedDay {
                    Text(selectedDay, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                } else {
                    Text(text.week)
                }
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
            .lineLimit(1)
            Spacer(minLength: 4)
            if selectedDay != nil {
                Button {
                    selectedDay = nil
                    focus = Date()
                } label: {
                    Text(text.week)
                        .font(.system(size: 9.5, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.1), in: Capsule())
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func remindersColumn(now: Date) -> some View {
        NotchRemindersPaneView(
            now: now,
            onQuickCreate: {
                withAnimation(.snappy(duration: 0.18)) { showingQuickCapture = true }
            },
            onRescheduleToday: { reminderID in
                reminders.reschedule(reminderID: reminderID, toDay: now)
            },
            onTimeBlockToday: { reminderID in
                reminders.timeBlock(reminderID: reminderID, after: nil, on: selectedDay ?? now)
            }
        )
    }

    /// Dedicated Monolith-style drop target to drag any reminder onto Today (or the currently selected day).
    private func todayDropZone(now: Date) -> some View {
        let targetDay = selectedDay ?? now
        let isTargetToday = Calendar.current.isDate(targetDay, inSameDayAs: now)
        return HStack(spacing: 6) {
            Image(systemName: hoveringTodayDrop ? "sun.max.fill" : "arrow.down.to.line.compact")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(hoveringTodayDrop ? .mint : .white.opacity(0.45))
            if isTargetToday {
                Text(plannerCopy.dropForTodayHint)
                    .font(.system(size: 10, weight: hoveringTodayDrop ? .semibold : .medium))
                    .foregroundStyle(hoveringTodayDrop ? .white : .white.opacity(0.45))
                    .lineLimit(1)
            } else {
                HStack(spacing: 3) {
                    Text("→")
                    Text(targetDay, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                }
                .font(.system(size: 10, weight: hoveringTodayDrop ? .semibold : .medium))
                .foregroundStyle(hoveringTodayDrop ? .white : .white.opacity(0.55))
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hoveringTodayDrop ? Color.mint.opacity(0.18) : .white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    hoveringTodayDrop ? Color.mint.opacity(0.65) : .white.opacity(0.08),
                    style: StrokeStyle(lineWidth: 1, dash: hoveringTodayDrop ? [] : [4, 3])
                )
        )
        .dropDestination(for: String.self) { payloads, _ in
            guard let id = payloads.compactMap(NotchRemindersSupport.decodeDragPayload).first else { return false }
            reminders.reschedule(reminderID: id, toDay: targetDay)
            return true
        } isTargeted: { targeted in
            withAnimation(.snappy(duration: 0.14)) { hoveringTodayDrop = targeted }
        }
    }

    /// The month the service reads belongs to the island's own page; a preview
    /// in Settings borrows it only while the island shows another page.
    private var ownsMonth: Bool {
        !preview || !(NotchService.shared.expanded && NotchService.shared.selected == .calendar)
    }

    private func monthView(now: Date) -> some View {
        NotchCalendarMonthView(month: focus, selectedDay: selectedDay, now: now,
                               events: calendar.events, text: text, select: select)
    }

    private func weekStrip(now: Date) -> some View {
        NotchCalendarWeekStrip(focus: focus, selectedDay: selectedDay, now: now,
                               events: calendar.events, text: text, select: select) {
            selectedDay = nil
            focus = now
        }
    }

    /// Picking a day lands back on the strip with that day.
    private func monthGrid(now: Date) -> some View {
        NotchCalendarMonthGrid(month: focus, selectedDay: selectedDay, now: now, height: size.height,
                               events: calendar.events, text: text) { date in
            select(date)
            showingMonth = false
        }
    }

    /// The month the page shows, named in the language's own words: in full
    /// where the row has room, abbreviated where the camera leaves less. Over
    /// the week strip it opens the month grid, and over that grid it closes it.
    private var monthTitle: some View {
        let title = ViewThatFits(in: .horizontal) {
            Text(focus, format: .dateTime.month(.wide).year())
            Text(focus, format: .dateTime.month(.abbreviated).year())
        }
        .font(.system(size: 13, weight: .semibold))
        .lineLimit(1)
        // The row is drawn by the island, outside this page's own locale.
        .environment(\.locale, l10n.language.formattingLocale())
        return Group {
            if showsMonth {
                title.accessibilityAddTraits(.isHeader)
            } else {
                Button { showingMonth.toggle() } label: {
                    title
                        .padding(.horizontal, 7)
                        .frame(height: 28)
                        .background(.white.opacity(showingMonth ? 0.12 : 0),
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(NotchButtonStyle(cornerRadius: 9))
                .help(text.month)
                .accessibilityHint(text.month)
                .accessibilityAddTraits(showingMonth ? .isSelected : [])
            }
        }
    }

    /// Accounts for `+`, split capsule, and date arrows so trailing controls never crowd the camera cutout.
    private var rowShowsNavArrows: Bool {
        !band.besideCamera || band.side >= 166
    }

    private var rowOpensCalendar: Bool {
        !band.besideCamera ? size.width >= 480 : band.side >= 198
    }

    /// The arrows step by week over the strip and by month over a grid,
    /// around the way back to today, alongside Quick Capture (⌘N) and Split-View layout controls.
    private var navigation: some View {
        let byWeek = !showsMonth && !showingMonth
        return HStack(spacing: 4) {
            NotchIconButton(symbol: showingQuickCapture ? "xmark" : "plus",
                            title: plannerCopy.quickAddTooltip) {
                withAnimation(.snappy(duration: 0.18)) { showingQuickCapture.toggle() }
            }

            if canSplitHorizontally {
                Menu {
                    ForEach(NotchPlannerSplitRatio.allCases, id: \.self) { ratio in
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { splitRatioRaw = ratio.rawValue }
                        } label: {
                            HStack {
                                Text(ratioMenuTitle(ratio))
                                if ratio == splitRatio { Image(systemName: "checkmark") }
                            }
                        }
                    }
                    if splitRatio.isSplit {
                        Divider()
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { plannerSwapped.toggle() }
                        } label: {
                            Label(plannerCopy.swapSidesTooltip, systemImage: "arrow.left.arrow.right")
                        }
                    }
                    if !rowOpensCalendar {
                        Divider()
                        Button { openCalendar() } label: {
                            Label(text.openCalendar, systemImage: "arrow.up.forward.app")
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(splitRatio.shortLabel)
                            .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .foregroundStyle(.white.opacity(0.86))
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .background(.white.opacity(0.1), in: Capsule())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(plannerCopy.splitLayoutTooltip)
            } else {
                NotchIconButton(symbol: splitRatio == .remindersOnly ? "calendar" : "checklist",
                                title: splitRatio == .remindersOnly ? plannerCopy.calendarTitle : plannerCopy.remindersTitle) {
                    withAnimation(.snappy(duration: 0.18)) {
                        splitRatioRaw = (splitRatio == .remindersOnly
                                         ? NotchPlannerSplitRatio.calendarOnly
                                         : NotchPlannerSplitRatio.remindersOnly).rawValue
                    }
                }
            }

            if effectiveRatio.showsCalendar && rowShowsNavArrows {
                HStack(spacing: 0) {
                    NotchIconButton(symbol: "chevron.left", title: byWeek ? text.previousWeek : text.previousMonth) {
                        byWeek ? moveWeek(-1) : moveMonth(-1)
                    }
                    NotchIconButton(symbol: "circle.circle", title: text.today) {
                        today(now: Date())
                        showingMonth = false
                    }
                    NotchIconButton(symbol: "chevron.right", title: byWeek ? text.nextWeek : text.nextMonth) {
                        byWeek ? moveWeek(1) : moveMonth(1)
                    }
                }
                if rowOpensCalendar {
                    NotchIconButton(symbol: "arrow.up.forward.app", title: text.openCalendar) { openCalendar() }
                }
            }
        }
    }

    private func ratioMenuTitle(_ ratio: NotchPlannerSplitRatio) -> String {
        switch ratio {
        case .calendarOnly: return "\(plannerCopy.calendarTitle) 100%"
        case .calendarFocus: return "\(plannerCopy.calendarTitle) 70 / 30"
        case .balanced: return "50 / 50"
        case .remindersFocus: return "\(plannerCopy.remindersTitle) 70 / 30"
        case .remindersOnly: return "\(plannerCopy.remindersTitle) 100%"
        }
    }

    private func moveWeek(_ offset: Int) {
        guard let date = Calendar.current.date(byAdding: .day, value: offset * 7, to: focus) else { return }
        selectedDay = Calendar.current.startOfDay(for: date)
        focus = date
    }

    private func moveMonth(_ offset: Int) {
        guard let start = Calendar.current.dateInterval(of: .month, for: focus)?.start,
              let date = Calendar.current.date(byAdding: .month, value: offset, to: start) else { return }
        selectedDay = date
        focus = date
    }

    private func select(_ date: Date) {
        selectedDay = date
        focus = date
    }

    private func today(now: Date) {
        selectedDay = Calendar.current.startOfDay(for: now)
        focus = now
    }

    private var agendaHeader: some View {
        HStack(spacing: 6) {
            Group {
                if let selectedDay {
                    Text(selectedDay, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                } else {
                    Text(text.week)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            if selectedDay != nil {
                NotchIconButton(symbol: "calendar.badge.clock", title: text.week) {
                    selectedDay = nil
                    focus = Date()
                }
            }
        }
        .frame(minHeight: 32)
    }

    private struct DayGroup {
        let day: Date
        let events: [NotchCalendarEvent]
    }

    private func groups(now: Date) -> [DayGroup] {
        let days = selectedDay.map { [$0] } ?? (0..<7).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: Calendar.current.startOfDay(for: now))
        }
        let events = selectedDay == nil ? NotchCalendarSupport.upcoming(calendar.events, now: now) : calendar.events
        return days.map { DayGroup(day: $0, events: NotchCalendarSupport.events(events, on: $0)) }
            .filter { !$0.events.isEmpty }
    }

    /// Scrolls once to the countdown's event opened from the closed island,
    /// after the reload that opening the page starts has finished.
    private func agenda(now: Date, tomorrowEvents: [NotchCalendarEvent]) -> some View {
        ScrollViewReader { proxy in
            ScrollView { appointmentList(now: now, tomorrowEvents: tomorrowEvents) }
                .scrollIndicators(.automatic)
                .notchScrollEdgeFade()
                .id(selectedDay)
                .onChange(of: calendar.loading ? nil : calendar.revealing, initial: true) { _, target in
                    guard !preview, let target else { return }
                    DispatchQueue.main.async {
                        guard !calendar.loading, calendar.revealing == target else { return }
                        calendar.revealing = nil
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
        }
    }

    @ViewBuilder private func appointmentList(now: Date, tomorrowEvents: [NotchCalendarEvent]) -> some View {
        let groups = groups(now: now)
        let next = NotchCalendarSupport.next(calendar.events, now: now)
        let showingTomorrowPreview = selectedDay.map { Calendar.current.isDate($0, inSameDayAs: now) } ?? false
        if calendar.loading {
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 72)
        } else if groups.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                emptyAgenda.frame(maxWidth: .infinity, minHeight: 72)
                if showingTomorrowPreview && !tomorrowEvents.isEmpty {
                    tomorrowStrip(now: now, tomorrowEvents: tomorrowEvents)
                }
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(groups, id: \.day) { group in
                    let dayTargeted = hoveringDayDrop.map { Calendar.current.isDate($0, inSameDayAs: group.day) } ?? false
                    VStack(alignment: .leading, spacing: 5) {
                        if selectedDay == nil {
                            dayLabel(group.day, now: now)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(dayTargeted ? Color.mint.opacity(0.2) : .clear)
                                )
                                .dropDestination(for: String.self) { payloads, _ in
                                    guard let id = payloads.compactMap(NotchRemindersSupport.decodeDragPayload).first else {
                                        return false
                                    }
                                    reminders.reschedule(reminderID: id, toDay: group.day)
                                    return true
                                } isTargeted: { targeted in
                                    hoveringDayDrop = targeted ? group.day : (dayTargeted ? nil : hoveringDayDrop)
                                }
                        }
                        ForEach(group.events) { event in
                            let eventTargeted = hoveringEventDropID == event.id
                            NotchCalendarEventRow(event: event, day: group.day, now: now,
                                                  isNext: event.id == next?.id, text: text,
                                                  countdown: countdownChoice(event, now: now),
                                                  choose: { calendar.setCountdown($0, for: event) }) {
                                openCalendar(showing: event)
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(Color.mint.opacity(eventTargeted ? 0.85 : 0), lineWidth: 1.5)
                            )
                            .dropDestination(for: String.self) { payloads, _ in
                                guard let id = payloads.compactMap(NotchRemindersSupport.decodeDragPayload).first else {
                                    return false
                                }
                                reminders.timeBlock(reminderID: id, after: event, on: group.day)
                                return true
                            } isTargeted: { targeted in
                                hoveringEventDropID = targeted ? event.id : (eventTargeted ? nil : hoveringEventDropID)
                            }
                            .id(event.id)
                        }
                    }
                }
                if showingTomorrowPreview {
                    tomorrowStrip(now: now, tomorrowEvents: tomorrowEvents)
                }
            }
            .padding(.bottom, 2)
        }
    }

    private func tomorrowStrip(now: Date, tomorrowEvents: [NotchCalendarEvent]) -> some View {
        NotchPlannerTomorrowStripView(events: tomorrowEvents, copy: plannerCopy) {
            if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) {
                select(tomorrow)
            }
        }
    }

    /// Whether a timed event yet to start counts down on its own, or nil when
    /// its menu has nothing to offer: the countdown for every event covers it.
    private func countdownChoice(_ event: NotchCalendarEvent, now: Date) -> Bool? {
        guard !countdownForEvery, !event.allDay, event.start > now, !event.countdownKey.isEmpty else { return nil }
        return calendar.isChosen(event)
    }

    private func dayLabel(_ day: Date, now: Date) -> some View {
        NotchCalendarDayLabel(day: day, now: now, text: text)
    }

    private var emptyAgenda: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white.opacity(0.45))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(selectedDay == nil ? text.empty : text.emptyDay)
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                // With no card to open it from and no room for it in the row.
                if !rowOpensCalendar {
                    NotchPillButton(title: text.openCalendar) { openCalendar() }
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private var permissionCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock").font(.system(size: 28))
            Text(permissions.calendarAccess == .denied || permissions.calendarAccess == .restricted
                 ? text.denied : text.permission)
                .font(.callout).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if permissions.calendarAccess == .denied || permissions.calendarAccess == .restricted {
                    Button(text.settings) { permissions.openCalendarSettings() }
                } else {
                    Button(text.allow) {
                        NotchService.shared.open(.calendar)
                        permissions.requestCalendar()
                    }
                    .disabled(permissions.requestingCalendar)
                }
                if permissions.requestingCalendar { ProgressView().controlSize(.small) }
            }
            if permissions.calendarRequestFailed {
                Text(text.requestFailed).font(.caption).foregroundStyle(.orange)
            }
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
    }

    /// Calendar itself gets the link: another app claiming the `ical` scheme
    /// would not know EventKit's identifiers.
    private func openCalendar(showing event: NotchCalendarEvent? = nil) {
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        if let url = event.flatMap({ NotchCalendarSupport.eventURL($0) }) {
            NSWorkspace.shared.open([url], withApplicationAt: application, configuration: configuration)
        } else {
            NSWorkspace.shared.openApplication(at: application, configuration: configuration)
        }
    }
}

private struct NotchCalendarDayLabel: View {
    let day: Date
    let now: Date
    let text: NotchCalendarStrings

    var body: some View {
        HStack(spacing: 5) {
            if Calendar.current.isDate(day, inSameDayAs: now) {
                Text(text.today).foregroundStyle(.white)
            } else {
                Text(day, format: .dateTime.weekday(.abbreviated))
            }
            Text(day, format: .dateTime.day().month(.abbreviated))
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white.opacity(0.5))
        .lineLimit(1)
    }
}

private struct NotchCalendarEventRow: View {
    let event: NotchCalendarEvent
    let day: Date
    let now: Date
    let isNext: Bool
    let text: NotchCalendarStrings
    /// Whether the event counts down on its own; nil when it cannot.
    let countdown: Bool?
    let choose: (Bool) -> Void
    let open: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    private var ongoing: Bool { !event.allDay && event.start <= now && event.end > now }
    private var ended: Bool { event.end <= now }

    var body: some View {
        Button(action: open) { card }
            .buttonStyle(NotchButtonStyle(cornerRadius: 11, lifts: false))
            .help(text.openCalendar)
            .accessibilityHint(text.openCalendar)
            .modifier(NotchCountdownChoice(chosen: countdown, text: text, choose: choose))
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 4) {
            if ongoing || isNext {
                Text(ongoing ? text.ongoing : text.next)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ongoing ? .mint : .white.opacity(0.7))
                    .lineLimit(1)
            }
            Text(event.title.isEmpty ? text.untitled : event.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(ended ? 0.65 : 1))
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Group {
                    if event.allDay {
                        Text(text.allDay)
                    } else if Calendar.current.isDate(event.start, inSameDayAs: day)
                                && Calendar.current.isDate(event.end.addingTimeInterval(-1), inSameDayAs: day) {
                        Text(event.start, format: .dateTime.hour().minute())
                            + Text(" · ") + Text(event.end, format: .dateTime.hour().minute())
                    } else {
                        Text(event.start, format: .dateTime.day().month(.abbreviated).hour().minute())
                            + Text(" → ") + Text(event.end, format: .dateTime.day().month(.abbreviated).hour().minute())
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                // The mark of an event chosen to count down on its own.
                if countdown == true {
                    Image(systemName: "timer")
                        .accessibilityLabel(text.countdown)
                }
            }
            .font(.system(size: 11)).monospacedDigit()
            .foregroundStyle(.white.opacity(0.75))
            HStack(spacing: 5) {
                Text(event.calendar)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                if !event.location.isEmpty {
                    Text("·")
                        .foregroundStyle(.white.opacity(0.35))
                        .accessibilityHidden(true)
                    Label(event.location, systemImage: "mappin")
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .font(.system(size: 10))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(event.color.color)
                .frame(width: 3)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(event.color.color.opacity(ongoing ? 0.2 : 0.1),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(.white.opacity(contrast == .increased ? 0.5 : ongoing ? 0.16 : 0.05), lineWidth: 0.75)
        }
        .clipped()
    }
}

/// A timed event yet to start offers its own countdown from its menu, and
/// to VoiceOver as an action, while the countdown for every event is off.
private struct NotchCountdownChoice: ViewModifier {
    let chosen: Bool?
    let text: NotchCalendarStrings
    let choose: (Bool) -> Void

    @ViewBuilder func body(content: Content) -> some View {
        if let chosen {
            let title = chosen ? text.removeCountdown : text.addCountdown
            content
                .contextMenu { Button(title) { choose(!chosen) } }
                .accessibilityAction(named: Text(title)) { choose(!chosen) }
        } else {
            content
        }
    }
}

extension NotchCalendarColor {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
}
