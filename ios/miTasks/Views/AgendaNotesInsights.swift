import SwiftUI

private var todayLine: String { Date().formatted(.dateTime.weekday(.wide).month(.wide).day()) }

// MARK: - Agenda

struct AgendaView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        TimelineView(.everyMinute) { _ in
            let events = store.todaysEvents
            let now = Date()
            let free = TaskStatus.formatMinutes(TaskStatus.freeTodayMs(events))
            let timed = events.filter { $0.allDay != true }
            let left = timed.filter { ($0.endDate ?? .distantPast) > now }.count
            let live = timed.filter(\.isNow).count

            Screen(title: "Agenda") {
                Text(todayLine)
                if !events.isEmpty {
                    Text("\(free) free").foregroundStyle(Theme.green)
                }
            } content: {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHead(
                        title: "Meetings",
                        countText: live > 0 ? "\(live) now" : left > 0 ? "\(left)" : nil,
                        countColor: live > 0 ? Theme.amber : Theme.muted,
                        hint: events.isEmpty ? "Nothing booked today" : (left > 0 ? "\(left) to go · " : "") + "\(free) free"
                    )
                    if events.isEmpty {
                        EmptyNote(big: "No meetings today", small: "The whole day is yours.")
                    } else {
                        ForEach(rows(events).indices, id: \.self) { i in
                            switch rows(events)[i] {
                            case .event(let ev): EventRow(event: ev, now: now)
                            case .gap(let ms): GapRow(ms: ms)
                            }
                        }
                    }
                }
                .padding(.horizontal, -Theme.Space.s)
                .padding(.top, Theme.Space.xs)
            }
        }
    }

    private enum Row {
        case event(CalEvent)
        case gap(Double)
    }

    /// Meetings in order, with an "open" line wherever there's 30 minutes or
    /// more between one ending and the next starting — the widget's rule.
    private func rows(_ events: [CalEvent]) -> [Row] {
        var out: [Row] = []
        var prevEnd: Date?
        for ev in events {
            if ev.allDay != true, let prev = prevEnd, let s = ev.startDate {
                let gap = s.timeIntervalSince(prev)
                if gap >= 1800 { out.append(.gap(gap * 1000)) }
            }
            out.append(.event(ev))
            if ev.allDay != true, let e = ev.endDate { prevEnd = max(prevEnd ?? e, e) }
        }
        return out
    }
}

private struct EventRow: View {
    let event: CalEvent
    let now: Date

    var body: some View {
        let live = event.allDay != true && event.isNow
        let past = event.allDay != true && (event.endDate ?? .distantFuture) <= now
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Text(timeLabel)
                .font(Theme.mono(Theme.Size.s))
                .monospacedDigit()
                .foregroundStyle(live ? Theme.amber : Theme.muted)
                .lineLimit(1)
                .frame(width: 66, height: 20, alignment: .leading)

            RoundedRectangle(cornerRadius: 1)
                .fill(live ? Theme.amber : (Color(cssHex: event.color) ?? Theme.lineStrong))
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 0) {
                Text(event.title ?? "Untitled")
                    .font(Theme.text(Theme.Size.m, live ? .semibold : .regular))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .frame(minHeight: 20)
                if !sub(live: live).isEmpty {
                    Text(sub(live: live))
                        .font(Theme.text(Theme.Size.s))
                        .foregroundStyle(live ? Theme.amber : Theme.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, Theme.Space.s6)
        .background(live ? Theme.select : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .opacity(past ? 0.45 : 1)
    }

    private var timeLabel: String {
        if event.allDay == true { return "All day" }
        return event.startDate?.formatted(date: .omitted, time: .shortened) ?? ""
    }

    /// One line of context, in order of how much it tells you.
    private func sub(live: Bool) -> String {
        var bits: [String] = []
        if live { bits.append("Now") }
        if let l = event.location, !l.isEmpty { bits.append(l) }
        else if let a = event.attendees, !a.isEmpty { bits.append("\(a.count) people") }
        else if let c = event.calendar, !c.isEmpty { bits.append(c) }
        return bits.joined(separator: " · ")
    }
}

private struct GapRow: View {
    let ms: Double

    var body: some View {
        Text("\(TaskStatus.formatMinutes(ms)) open")
            .font(Theme.text(Theme.Size.s))
            .foregroundStyle(Theme.green)
            .padding(.leading, Theme.Space.s + 66 + Theme.Space.m + 2 + Theme.Space.m)
            .padding(.vertical, Theme.Space.xxs)
    }
}

// MARK: - Notes

struct NotesView: View {
    @EnvironmentObject var store: Store
    @State private var editing: NoteItem?
    @State private var filter: String?

    var body: some View {
        let notes = store.state.notes
            .filter { filter == nil || $0.label == filter }
            .sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }

        Screen(title: "Notes") {
            Text(todayLine)
            Text("\(store.state.notes.count) note\(store.state.notes.count == 1 ? "" : "s")")
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                SectionHead(title: "Notes", count: notes.count) {
                    Button("New note") {
                        Task {
                            if let created = await store.createNote(label: filter) { editing = created }
                        }
                    }
                    .buttonStyle(.crew(.chip, height: 26))
                }

                if !store.state.labels.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Space.xs) {
                            OptionChip(title: "All", on: filter == nil) { filter = nil }
                            ForEach(store.state.labels) { l in
                                OptionChip(title: l.name, dot: Color(cssHex: l.color), on: filter == l.name) {
                                    filter = filter == l.name ? nil : l.name
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Space.s)
                        .padding(.vertical, 1)
                    }
                    .padding(.bottom, Theme.Space.s)
                }

                if notes.isEmpty {
                    EmptyNote(big: "No notes yet", small: "Tap New note to start one.")
                } else {
                    ForEach(notes) { note in
                        Button { editing = note } label: { row(note) }
                            .buttonStyle(RowPressStyle())
                    }
                }
            }
            .padding(.horizontal, -Theme.Space.s)
            .padding(.top, Theme.Space.xs)
        }
        .sheet(item: $editing) { NoteEditor(note: $0) }
    }

    private func row(_ note: NoteItem) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(note.title?.isEmpty == false ? note.title! : "Untitled")
                .font(Theme.text(Theme.Size.m, .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let body = note.body?
                .split(whereSeparator: \.isNewline)
                .map({ $0.trimmingCharacters(in: .whitespaces) })
                .filter({ !$0.isEmpty })
                .joined(separator: "\n"),
                !body.isEmpty {
                Text(body)
                    .font(Theme.text(Theme.Size.s))
                    .foregroundStyle(Theme.muted)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            HStack(spacing: Theme.Space.s6) {
                if let l = store.state.label(named: note.label) {
                    Circle().fill(Color(cssHex: l.color) ?? Theme.faint).frame(width: 6, height: 6)
                    Text(l.name)
                }
                if let d = note.updatedDate {
                    if store.state.label(named: note.label) != nil { Text("·") }
                    Text(relativeDay(d))
                }
            }
            .font(Theme.text(Theme.Size.s))
            .foregroundStyle(Theme.faint)
            .padding(.top, Theme.Space.xxs)
        }
        .padding(Theme.Space.s)
        .contentShape(Rectangle())
    }

    private func relativeDay(_ d: Date) -> String {
        let diff = TaskStatus.dayDiff(d)
        if diff >= 0 { return "Today" }
        if diff == -1 { return "Yesterday" }
        return TaskStatus.short(d)
    }
}

/// Crew's option chip: outlined capsule, selected one filled with `select`.
struct OptionChip: View {
    let title: String
    var dot: Color? = nil
    let on: Bool
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            HStack(spacing: Theme.Space.s6) {
                if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
                Text(title).font(Theme.text(Theme.Size.s))
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .foregroundStyle(on ? Theme.ink : Theme.ink2)
            .background(on ? Theme.select : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(on ? Theme.ink2 : Theme.lineStrong, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A quiet row that washes on press, like a Crew row on hover.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? Theme.hover : .clear,
                in: RoundedRectangle(cornerRadius: Theme.Radius.card)
            )
    }
}

// MARK: - Insights

struct InsightsView: View {
    @EnvironmentObject var store: Store
    @State private var editing: TaskItem?
    @State private var showSettings = false

    var body: some View {
        let tasks = store.state.tasks
        let today = Date().startOfDay
        let weekAgo = Date().addingTimeInterval(-7 * 86400)
        let done = tasks.filter(\.done)
        let overdue = tasks.filter { !$0.done && ($0.dueDate.map { $0 < today } ?? false) }
        let stalled = tasks.filter { t in
            !t.done && (t.startDate.map { $0 <= Date() } ?? false) && !(t.dueDate.map { $0 < today } ?? false)
        }
        let attention = overdue.map { ($0, "Overdue") } + stalled.map { ($0, "Started") }
        let aging = tasks.filter(\.isAging).sorted { ($0.createdAt ?? 0) < ($1.createdAt ?? 0) }.prefix(8)

        Screen(title: "Insights") {
            Text(todayLine)
            if store.streakDays > 0 {
                Text("\(store.streakDays)-day streak").foregroundStyle(Theme.green)
            }
        } trailing: {
            Button { showSettings = true } label: {
                IconButtonLabel(systemName: "gearshape", size: Theme.Height.regular)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        } content: {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Space.s), count: 3),
                spacing: Theme.Space.s
            ) {
                MetricCard(label: "Done today", value: "\(done.filter { ($0.doneDate ?? .distantPast) >= today }.count)")
                MetricCard(label: "Past 7 days", value: "\(done.filter { ($0.doneDate ?? .distantPast) >= weekAgo }.count)")
                MetricCard(label: "Pending", value: "\(tasks.filter { !$0.done }.count)")
                MetricCard(label: "Overdue", value: "\(overdue.count)", warn: !overdue.isEmpty)
                MetricCard(label: "Focused today", value: "\(store.focusedTodayMinutes)m")
                MetricCard(label: "Focused 7 days", value: TaskStatus.formatMinutes(focusedWeekMs))
            }
            .padding(.top, Theme.Space.l)

            VStack(alignment: .leading, spacing: 0) {
                if !attention.isEmpty {
                    SectionHead(title: "Needs attention")
                    ForEach(Array(attention.prefix(8)), id: \.0.id) { task, why in
                        listRow(task.text, why: why, tone: why == "Overdue" ? Theme.red : Theme.amber) { editing = task }
                    }
                }

                if !aging.isEmpty {
                    SectionHead(title: "Aging", hint: "nothing scheduled")
                    ForEach(Array(aging)) { task in
                        let d = task.ageDays
                        listRow(task.text, why: "\(d)d", tone: d >= 14 ? Theme.red : Theme.amber) { editing = task }
                    }
                }

                if !clients.isEmpty {
                    SectionHead(title: "By label", hint: "done of total")
                    ForEach(clients, id: \.name) { clientRow($0) }
                }

                if !focusByLabel.isEmpty {
                    SectionHead(title: "Focus by label", hint: "7 days")
                    ForEach(focusByLabel.prefix(6), id: \.0) { name, ms in
                        HStack(spacing: Theme.Space.s) {
                            labelName(name)
                            Spacer(minLength: 0)
                            Text(TaskStatus.formatMinutes(ms))
                                .font(Theme.text(Theme.Size.s))
                                .monospacedDigit()
                                .foregroundStyle(Theme.muted)
                        }
                        .frame(minHeight: Theme.Height.small)
                        .padding(.horizontal, Theme.Space.s)
                    }
                }
            }
            .padding(.horizontal, -Theme.Space.s)
            .padding(.top, Theme.Space.xs)
        }
        .sheet(item: $editing) { TaskEditor(task: $0) }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private func listRow(_ text: String, why: String, tone: Color, open: @escaping () -> Void) -> some View {
        Button(action: open) {
            HStack(spacing: Theme.Space.s) {
                Text(text)
                    .font(Theme.text(Theme.Size.m))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(why)
                    .font(Theme.text(Theme.Size.s))
                    .foregroundStyle(tone)
            }
            .frame(minHeight: Theme.Height.regular)
            .padding(.horizontal, Theme.Space.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    @ViewBuilder
    private func labelName(_ name: String?) -> some View {
        HStack(spacing: 7) {
            if let l = store.state.label(named: name) {
                Circle().fill(Color(cssHex: l.color) ?? Theme.faint).frame(width: 7, height: 7)
            }
            Text(name ?? "No label")
                .font(Theme.text(Theme.Size.m))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
        }
    }

    private var focusedWeekMs: Double {
        let cut = DateParse.dayString(Date().addingTimeInterval(-8 * 86400))
        return store.state.focusLog.filter { ($0.date ?? "") >= cut }.reduce(0) { $0 + ($1.ms ?? 0) }
    }

    private var focusByLabel: [(String, Double)] {
        let cut = DateParse.dayString(Date().addingTimeInterval(-8 * 86400))
        var out: [String: Double] = [:]
        for entry in store.state.focusLog where (entry.date ?? "") >= cut {
            let label = entry.label ?? store.state.tasks.first { $0.id == entry.taskId }?.label
            out[label ?? "No label", default: 0] += entry.ms ?? 0
        }
        return out.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    private struct ClientRow {
        let name: String?
        let open: Int
        let done: Int
        let total: Int
        let last: Double
    }

    /// Labels with open work first, oldest activity at the top — the point is
    /// spotting the client that has gone quiet.
    private var clients: [ClientRow] {
        let buckets = Dictionary(grouping: store.state.tasks) { $0.label }
        return buckets.map { name, tasks in
            let done = tasks.filter(\.done).count
            return ClientRow(
                name: name,
                open: tasks.count - done,
                done: done,
                total: tasks.count,
                last: tasks.map { $0.doneAt ?? $0.createdAt ?? 0 }.max() ?? 0
            )
        }
        .sorted { a, b in
            if (a.open > 0) != (b.open > 0) { return a.open > 0 }
            return a.last < b.last
        }
    }

    private func clientRow(_ r: ClientRow) -> some View {
        let quiet = r.last > 0 ? Int((Date().timeIntervalSince1970 * 1000 - r.last) / 86_400_000) : 0
        let color = store.state.label(named: r.name).flatMap { Color(cssHex: $0.color) } ?? Theme.faint
        return HStack(spacing: Theme.Space.m) {
            labelName(r.name)
                .frame(width: 118, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surface3)
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * (r.total > 0 ? Double(r.done) / Double(r.total) : 0))
                }
            }
            .frame(height: 4)
            Text(r.open > 0 ? (quiet >= 7 ? "\(r.open) open · \(quiet)d" : "\(r.open) open") : "\(r.done)/\(r.total)")
                .font(Theme.text(Theme.Size.s))
                .monospacedDigit()
                .foregroundStyle(r.open > 0 && quiet >= 7 ? Theme.red : Theme.muted)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(minHeight: Theme.Height.regular)
        .padding(.horizontal, Theme.Space.s)
    }
}

/// Crew's metric card: an 11 muted label on top, the number underneath.
struct MetricCard: View {
    let label: String
    let value: String
    var warn = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(label)
                .font(Theme.text(Theme.Size.xs))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(Theme.text(Theme.Size.xl, .semibold))
                .monospacedDigit()
                .foregroundStyle(warn ? Theme.red : Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.m)
        .padding(.top, Theme.Space.s)
        .padding(.bottom, 10)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.line, lineWidth: 1))
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.surface.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 0) {
                    SectionHead(title: "Connected to")
                        .padding(.horizontal, -Theme.Space.s)
                    Text(store.config?.host ?? "—")
                        .font(Theme.mono(Theme.Size.m, .medium))
                        .foregroundStyle(Theme.ink)
                    HStack(spacing: Theme.Space.s6) {
                        Circle()
                            .fill(store.connected ? Theme.green : Theme.red)
                            .frame(width: 6, height: 6)
                        Text(store.connected ? "Live" : "Not reachable right now")
                            .font(Theme.text(Theme.Size.s))
                            .foregroundStyle(store.connected ? Theme.green : Theme.red)
                    }
                    .padding(.top, Theme.Space.s6)

                    Text("Your Mac's address can change when it reconnects to Wi-Fi. If the app stops syncing, disconnect and scan the widget's code again.")
                        .font(Theme.text(Theme.Size.s))
                        .foregroundStyle(Theme.muted)
                        .lineSpacing(Theme.Space.xxs)
                        .padding(.top, Theme.Space.l)

                    Button("Disconnect this Mac") { store.unpair(); dismiss() }
                        .buttonStyle(.crew(.destructive, height: Theme.Height.regular))
                        .padding(.top, Theme.Space.l)

                    Spacer()
                }
                .padding(.horizontal, Theme.Space.xl)
            }
            .foregroundStyle(Theme.ink)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .crewSheet()
    }
}
