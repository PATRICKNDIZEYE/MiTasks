import SwiftUI

struct AgendaView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let events = store.todaysEvents
        let gaps = store.freeGaps
        let freeHours = gaps.reduce(0.0) { $0 + $1.1.timeIntervalSince($1.0) } / 3600
        let upcoming = events.filter { ($0.endDate ?? .distantPast) > Date() }.count

        Screen(
            title: "Agenda",
            subtitle: events.isEmpty
                ? Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
                : "\(upcoming) left · \(String(format: "%.1f", freeHours))h free"
        ) {
            if events.isEmpty {
                EmptyNote(big: "No meetings today.", small: "The whole day is yours.")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(rows.indices, id: \.self) { i in
                        switch rows[i] {
                        case .event(let ev): EventRow(event: ev)
                        case .gap(let a, let b): GapRow(from: a, to: b)
                        }
                    }
                }
                .padding(.top, 16)
            }
        }
    }

    private enum Row {
        case event(CalEvent)
        case gap(Date, Date)
    }

    /// Interleaves free stretches between the meetings they sit before.
    private var rows: [Row] {
        var out: [Row] = []
        var gaps = store.freeGaps
        for ev in store.todaysEvents {
            while let g = gaps.first, g.1 <= (ev.startDate ?? .distantFuture) {
                out.append(.gap(g.0, g.1))
                gaps.removeFirst()
            }
            out.append(.event(ev))
        }
        out.append(contentsOf: gaps.map { Row.gap($0.0, $0.1) })
        return out
    }
}

private struct EventRow: View {
    let event: CalEvent

    var body: some View {
        let now = event.isNow
        HStack(alignment: .top, spacing: 11) {
            RoundedRectangle(cornerRadius: 2)
                .fill(now ? Theme.amber : (Color(cssHex: event.color) ?? Theme.ink3))
                .frame(width: 2.5)

            VStack(alignment: .leading, spacing: 3) {
                Text(timeLabel)
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(now ? Theme.amber : Theme.ink3)
                Text(event.title ?? "Untitled")
                    .font(.system(size: 14.5, weight: now ? .semibold : .regular))
                    .fixedSize(horizontal: false, vertical: true)
                if !meta.isEmpty {
                    Text(meta)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hair).frame(height: 1) }
    }

    private var timeLabel: String {
        if event.allDay == true { return "ALL DAY" }
        guard let s = event.startDate, let e = event.endDate else { return "" }
        return "\(s.clockLabel) – \(e.clockLabel)" + (event.isNow ? "  · NOW" : "")
    }

    private var meta: String {
        var bits: [String] = []
        if let l = event.location, !l.isEmpty { bits.append(l) }
        if let a = event.attendees, !a.isEmpty { bits.append("\(a.count) people") }
        return bits.joined(separator: " · ")
    }
}

private struct GapRow: View {
    let from: Date
    let to: Date

    var body: some View {
        HStack(spacing: 9) {
            Rectangle().fill(Theme.sage.opacity(0.45)).frame(width: 16, height: 1)
            Text("\(lengthLabel) open · \(from.clockLabel)")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.sage)
            Spacer(minLength: 0)
        }
        .padding(.leading, 14)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hair).frame(height: 1) }
    }

    private var lengthLabel: String {
        let mins = Int(to.timeIntervalSince(from) / 60)
        return mins >= 60 ? String(format: "%.1fh", Double(mins) / 60) : "\(mins)m"
    }
}

struct NotesView: View {
    @EnvironmentObject var store: Store
    @State private var editing: NoteItem?

    var body: some View {
        let notes = store.state.notes.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }

        Screen(
            title: "Notes",
            subtitle: "\(notes.count) note\(notes.count == 1 ? "" : "s")",
            trailing: AnyView(addButton)
        ) {
            if notes.isEmpty {
                EmptyNote(big: "No notes yet.", small: "Tap + to start one.")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(notes) { note in
                        Button { editing = note } label: { row(note) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.top, 16)
            }
        }
        .sheet(item: $editing) { NoteEditor(note: $0) }
    }

    private var addButton: some View {
        Button {
            Task {
                if let created = await store.createNote(label: nil) { editing = created }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17))
                .frame(width: 36, height: 36)
                .foregroundStyle(Theme.ink3)
        }
    }

    private func row(_ note: NoteItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.title?.isEmpty == false ? note.title! : "Untitled")
                .font(.system(size: 14.5, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            if let body = note.body, !body.isEmpty {
                Text(body)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            HStack(spacing: 6) {
                if let l = store.state.label(named: note.label) {
                    Chip(text: l.name, dot: Color(cssHex: l.color))
                }
                if let d = note.updatedDate {
                    Chip(text: d.formatted(.dateTime.month(.abbreviated).day()))
                }
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hair).frame(height: 1) }
    }
}

struct InsightsView: View {
    @EnvironmentObject var store: Store
    @State private var editing: TaskItem?
    @State private var showSettings = false

    var body: some View {
        Screen(
            title: "Insights",
            subtitle: Date().formatted(.dateTime.weekday(.wide).month(.wide).day()),
            trailing: AnyView(settingsLink)
        ) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                stat("\(doneToday)", "Done today")
                stat("\(store.state.tasks.filter { !$0.done }.count)", "Still open")
                stat("\(store.focusedTodayMinutes)m", "Focused today")
                stat("\(store.streakDays)d", "Streak")
            }
            .padding(.top, 16)

            let aging = store.state.tasks.filter(\.isAging).sorted { $0.ageDays > $1.ageDays }.prefix(8)
            if !aging.isEmpty {
                SectionRule(title: "Sitting too long")
                LazyVStack(spacing: 0) {
                    ForEach(Array(aging)) { task in
                        TaskRow(task: task) { editing = task }
                    }
                }
            }

            if !clients.isEmpty {
                SectionRule(title: "By client")
                ForEach(clients, id: \.label.name) { row in
                    clientRow(row)
                }
            }
        }
        .sheet(item: $editing) { TaskEditor(task: $0) }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private var settingsLink: some View {
        Button { showSettings = true } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 16))
                .frame(width: 36, height: 36)
                .foregroundStyle(Theme.ink3)
        }
    }

    private var doneToday: Int {
        let today = DateParse.dayString(Date())
        return store.state.tasks.filter { $0.doneDate.map(DateParse.dayString) == today }.count
    }

    private func stat(_ n: String, _ k: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(n).font(Theme.display(26))
            Eyebrow(text: k)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.ink.opacity(0.03), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.hair, lineWidth: 1))
    }

    private struct ClientRow {
        let label: LabelItem
        let open: Int
        let done: Int
        let total: Int
        let quietDays: Int?
    }

    private var clients: [ClientRow] {
        store.state.labels.compactMap { l -> ClientRow? in
            let all = store.state.tasks.filter { $0.label == l.name }
            guard !all.isEmpty else { return nil }
            let last = all.compactMap { $0.doneAt ?? $0.createdAt }.max()
            let quiet = last.map {
                Int(Date().timeIntervalSince(Date(timeIntervalSince1970: $0 / 1000)) / 86400)
            }
            return ClientRow(
                label: l,
                open: all.filter { !$0.done }.count,
                done: all.filter(\.done).count,
                total: all.count,
                quietDays: quiet
            )
        }
        .sorted { a, b in
            if a.open != b.open { return a.open > b.open }
            return (a.quietDays ?? 0) > (b.quietDays ?? 0)
        }
    }

    private func clientRow(_ r: ClientRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(Color(cssHex: r.label.color) ?? Theme.ink3).frame(width: 7, height: 7)
                Text(r.label.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(r.done)/\(r.total)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.ink3)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.ink.opacity(0.08))
                    Capsule()
                        .fill(Color(cssHex: r.label.color) ?? Theme.amber)
                        .frame(width: geo.size.width * (r.total > 0 ? Double(r.done) / Double(r.total) : 0))
                }
            }
            .frame(height: 3)

            if let q = r.quietDays, q >= 7, r.open > 0 {
                Text("Quiet \(q) days — \(r.open) still open")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.clay)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hair).frame(height: 1) }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 7) {
                        Eyebrow(text: "Connected to")
                        Text(store.config?.host ?? "—")
                            .font(.system(size: 15, weight: .semibold))
                        Text(store.connected ? "Live" : "Not reachable right now")
                            .font(.system(size: 12))
                            .foregroundStyle(store.connected ? Theme.sage : Theme.clay)
                    }

                    Button("Disconnect this Mac") { store.unpair(); dismiss() }
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundStyle(Theme.clay)
                        .background(RoundedRectangle(cornerRadius: 11).stroke(Theme.clay.opacity(0.4), lineWidth: 1))

                    Text("Your Mac's address can change when it reconnects to Wi-Fi. If the app stops syncing, disconnect and scan the widget's code again.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.ink3)
                        .lineSpacing(2)

                    Spacer()
                }
                .padding(20)
            }
            .foregroundStyle(Theme.ink)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}
