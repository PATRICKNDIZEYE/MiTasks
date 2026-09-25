import SwiftUI

/// Today, laid out like a Crew mission — the same structure as the Mac
/// widget's `render()`: a header with the Lock-in pill, the composer, then
/// sidebar-style sections (In focus, Needs you, Up next) and a folded Done.
struct TodayView: View {
    @EnvironmentObject var store: Store
    @State private var draft = ""
    @State private var activeLabel: String?
    @State private var editing: TaskItem?
    @State private var showLockin = false
    @State private var doneOpen = false
    @StateObject private var dictation = Dictation()
    @State private var voiceNote: String?
    @FocusState private var composerFocused: Bool

    private var parsed: QuickAdd? {
        let raw = draft.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }
        return QuickAdd.parse(raw, labels: store.state.labels, activeLabel: activeLabel)
    }

    private var visible: [TaskItem] {
        guard let activeLabel else { return store.state.tasks }
        return store.state.tasks.filter { $0.label == activeLabel }
    }

    /// The task in focus, if it's still open.
    private var focusTask: TaskItem? {
        guard let id = store.state.focus?.taskId else { return nil }
        return store.state.tasks.first { $0.id == id && !$0.done }
    }

    /// Open work minus whatever is in focus: priority, then deadline, then newest.
    private var pending: [TaskItem] {
        let focusId = focusTask?.id
        return visible.filter { !$0.done && $0.id != focusId }.sorted { a, b in
            let pa = TaskStatus.priorityRank(a), pb = TaskStatus.priorityRank(b)
            if pa != pb { return pa < pb }
            let da = TaskStatus.dueValue(a), db = TaskStatus.dueValue(b)
            if da != db { return da < db }
            return (a.createdAt ?? 0) > (b.createdAt ?? 0)
        }
    }

    private var done: [TaskItem] {
        visible.filter(\.done).sorted { ($0.doneAt ?? 0) > ($1.doneAt ?? 0) }
    }

    var body: some View {
        let pending = pending
        let done = done
        let focus = focusTask
        // Needs you: oldest deadline first, then priority.
        let needs = pending.filter(TaskStatus.needsYou).sorted { a, b in
            let da = TaskStatus.dueValue(a), db = TaskStatus.dueValue(b)
            if da != db { return da < db }
            return TaskStatus.priorityRank(a) < TaskStatus.priorityRank(b)
        }
        let next = pending.filter { !TaskStatus.needsYou($0) }

        Screen(title: "Today") {
            meta(total: visible.count, doneCount: done.count)
        } trailing: {
            lockin
        } content: {
            voiceStrip
            composer

            VStack(alignment: .leading, spacing: 0) {
                if let focus {
                    SectionHead(title: "In focus", count: 1, countColor: Theme.statusRunning, hint: "what you're on")
                    FocusRow(task: focus) { editing = focus }
                }

                if !needs.isEmpty {
                    SectionHead(title: "Needs you", count: needs.count, countColor: Theme.amber, hint: "most urgent first")
                    ForEach(needs) { task in
                        NeedRow(task: task, badge: activeLabel == nil) { editing = task }
                    }
                }

                if !next.isEmpty {
                    upNext(next, title: needs.isEmpty && focus == nil ? "To do" : "Up next")
                }

                if pending.isEmpty && done.isEmpty && focus == nil {
                    EmptyNote(
                        big: "Nothing on your plate",
                        small: "Add the next thing above — try “call Jev tomorrow 3pm !high”."
                    )
                }

                if !done.isEmpty {
                    doneBlock(done)
                }
            }
            .padding(.horizontal, -Theme.Space.s)
            .padding(.top, Theme.Space.xs)
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(item: $editing) { TaskEditor(task: $0) }
        .sheet(isPresented: $showLockin) { LockinSheet() }
    }

    // MARK: Header

    @ViewBuilder
    private func meta(total: Int, doneCount: Int) -> some View {
        Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
        if total > 0 {
            Text("\(Text("\(doneCount)").foregroundStyle(Theme.ink).fontWeight(.semibold)) of \(total) done")
        }
        if !store.state.events.isEmpty {
            Text("\(TaskStatus.formatMinutes(TaskStatus.freeTodayMs(store.todaysEvents))) free")
                .foregroundStyle(Theme.green)
        }
    }

    /// Lock-in as Crew's Auto-approve pill. Tapping opens the minutes sheet,
    /// which also stops it.
    private var lockin: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let status = store.state.lockin
            let active = status.active && status.remaining > 0
            HStack(spacing: Theme.Space.xs) {
                if active {
                    Button("+15") { store.startLockin(minutes: 15, extend: true) }
                        .buttonStyle(.crew(.quiet, height: Theme.Height.small))
                        .accessibilityLabel("Add 15 minutes")
                }
                Button { showLockin = true } label: {
                    PillSwitch(
                        on: active,
                        title: active ? "Locked in" : "Lock in",
                        time: active ? formatCountdown(status.remaining) : nil
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(active ? "Locked in, \(formatCountdown(status.remaining)) left" : "Lock in")
            }
        }
    }

    // MARK: Composer

    /// Crew's composer: the box you type into, with its controls underneath.
    private var composer: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s6) {
            TextField(
                "",
                text: $draft,
                prompt: Text(activeLabel.map { "Add to \($0)" } ?? "Add a task").foregroundStyle(Theme.faint)
            )
            .font(Theme.text(Theme.Size.body))
            .foregroundStyle(Theme.ink)
            .focused($composerFocused)
            .submitLabel(.done)
            .onSubmit(commit)
            .frame(minHeight: 24)

            if let summary = parsed?.summary, !summary.isEmpty {
                Text(summary)
                    .font(Theme.text(Theme.Size.s))
                    .foregroundStyle(Theme.muted)
            }

            HStack(spacing: Theme.Space.xs) {
                scope
                Spacer(minLength: 0)
                Button(action: handleVoice) {
                    IconButtonLabel(
                        systemName: dictation.isListening ? "mic.fill" : "mic",
                        size: Theme.Height.small,
                        tint: dictation.isListening ? Theme.red : Theme.muted,
                        fill: dictation.isListening ? Theme.redBg : .clear
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(dictation.isListening ? "Stop dictation" : "Dictate a task")

                Button(action: commit) {
                    HStack(spacing: Theme.Space.s6) {
                        Image(systemName: "arrow.up").font(.system(size: 12, weight: .semibold))
                        Text("Add")
                    }
                }
                .buttonStyle(.crew(.chip, height: 26))
                .accessibilityLabel("Add task")
            }
        }
        .padding(.leading, Theme.Space.m)
        .padding(.trailing, Theme.Space.s6)
        .padding(.top, Theme.Space.s)
        .padding(.bottom, Theme.Space.s6)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.panel)
                .strokeBorder(composerFocused ? Theme.muted : Theme.lineStrong, lineWidth: 1)
        )
        .shadow(color: Theme.shadowSm, radius: 1, y: 1)
        .contentShape(Rectangle())
        .onTapGesture { composerFocused = true }
        .animation(.easeOut(duration: 0.1), value: composerFocused)
        .padding(.top, Theme.Space.m)
    }

    /// The label scope: a quiet dropdown, like Crew's "by repo". It filters the
    /// list and labels new tasks.
    private var scope: some View {
        Menu {
            Button { activeLabel = nil } label: {
                if activeLabel == nil { Label("All labels", systemImage: "checkmark") } else { Text("All labels") }
            }
            Divider()
            ForEach(store.state.labels) { l in
                let open = store.state.tasks.filter { !$0.done && $0.label == l.name }.count
                let title = open > 0 ? "\(l.name)  \(open)" : l.name
                Button { activeLabel = l.name } label: {
                    if activeLabel == l.name { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
        } label: {
            HStack(spacing: Theme.Space.s6) {
                if let l = store.state.label(named: activeLabel) {
                    Circle().fill(Color(cssHex: l.color) ?? Theme.faint).frame(width: 7, height: 7)
                }
                Text(activeLabel ?? "All labels")
                    .font(Theme.text(Theme.Size.s))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(activeLabel == nil ? Theme.muted : Theme.ink2)
            .padding(.horizontal, Theme.Space.s6)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .padding(.leading, -Theme.Space.s6)
        .accessibilityLabel("Label filter")
    }

    // MARK: Sections

    @ViewBuilder
    private func upNext(_ next: [TaskItem], title: String) -> some View {
        if let activeLabel {
            SectionHead(title: title, count: next.count, hint: activeLabel)
            ForEach(next) { task in LineRow(task: task) { editing = task } }
        } else {
            SectionHead(title: title, count: next.count, hint: "by label")
            // Grouped by label in the order the labels were made; unlabelled last.
            let known = Set(store.state.labels.map(\.name))
            ForEach(store.state.labels) { l in
                let rows = next.filter { $0.label == l.name }
                if !rows.isEmpty {
                    GroupHead(name: l.name, color: Color(cssHex: l.color), count: rows.count)
                    ForEach(rows) { task in LineRow(task: task) { editing = task } }
                }
            }
            let loose = next.filter { $0.label.map { !known.contains($0) } ?? true }
            if !loose.isEmpty {
                GroupHead(name: "No label", color: nil, count: loose.count)
                ForEach(loose) { task in LineRow(task: task) { editing = task } }
            }
        }
    }

    @ViewBuilder
    private func doneBlock(_ done: [TaskItem]) -> some View {
        HStack(spacing: Theme.Space.s6) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { doneOpen.toggle() }
            } label: {
                HStack(spacing: Theme.Space.s6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(doneOpen ? 90 : 0))
                    Text("Done").font(Theme.text(Theme.Size.m))
                    Text("\(done.count)")
                        .font(Theme.text(Theme.Size.m))
                        .monospacedDigit()
                        .foregroundStyle(Theme.muted)
                }
                .foregroundStyle(Theme.ink2)
                .frame(height: Theme.Height.small)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(doneOpen ? "Hide done" : "Show \(done.count) done")
            Spacer(minLength: 0)
            if doneOpen {
                Button("Clear") { store.clearDone() }
                    .buttonStyle(.crew(.quiet, height: 24))
            }
        }
        .padding(.horizontal, Theme.Space.s)
        .padding(.top, Theme.Space.m)

        if doneOpen {
            ForEach(done.prefix(40)) { task in LineRow(task: task) { editing = task } }
        }
    }

    // MARK: Voice

    @ViewBuilder
    private var voiceStrip: some View {
        let message: String? = {
            switch dictation.phase {
            case .idle: return voiceNote
            case .listening: return dictation.transcript.isEmpty ? "Listening…" : dictation.transcript
            case .working(let m): return m
            case .denied(let m): return m
            }
        }()

        if let message {
            StatusStrip(
                tint: dictation.isListening ? Theme.red : Theme.faint,
                fill: dictation.isListening ? Theme.redBg : Theme.surface3,
                title: message,
                lines: 2
            ) {
                if dictation.isListening {
                    Button("Cancel") {
                        dictation.cancel()
                        voiceNote = nil
                    }
                    .buttonStyle(.crew(.quiet, height: Theme.Height.small))
                }
            }
            .padding(.top, Theme.Space.m)
        }
    }

    private func handleVoice() {
        Task {
            if dictation.isListening {
                let spoken = await dictation.stop()
                guard !spoken.isEmpty else {
                    dictation.phase = .idle
                    flash("Didn't catch that")
                    return
                }
                dictation.phase = .working("Sorting it out…")
                let verdict = await store.classify(spoken)
                store.saveSpoken(spoken, verdict: verdict)
                dictation.phase = .idle
                flash(verdict.ok ? "Added" : "Added — " + (verdict.error ?? "not classified"))
            } else {
                voiceNote = nil
                await dictation.start()
            }
        }
    }

    private func flash(_ message: String) {
        voiceNote = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if voiceNote == message { voiceNote = nil }
        }
    }

    private func commit() {
        guard let parsed, !parsed.text.isEmpty else { return }
        store.add(parsed)
        draft = ""
    }
}

// MARK: - Rows

/// Crew's "Needs you" row: a checkbox with the label as a status dot, a bold
/// title, a coloured status line and a grey "Focus" chip.
struct NeedRow: View {
    @EnvironmentObject var store: Store
    let task: TaskItem
    var badge = true
    let onOpen: () -> Void

    var body: some View {
        let status = TaskStatus.row(task)
        HStack(spacing: 10) {
            CheckToggle(task: task, size: 18, badge: badge ? labelColor : nil)

            VStack(alignment: .leading, spacing: 1) {
                Text(task.text)
                    .font(Theme.text(Theme.Size.m, .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if !status.text.isEmpty {
                    Text(status.text)
                        .font(Theme.text(Theme.Size.s))
                        .foregroundStyle(status.tone.color)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)

            Button("Focus") { store.startFocus(task) }
                .buttonStyle(.crew(.chip, height: 26))
                .accessibilityLabel("Focus on \(task.text)")
        }
        .padding(.leading, Theme.Space.s)
        .padding(.trailing, Theme.Space.s6)
        .padding(.vertical, Theme.Space.s6)
    }

    private var labelColor: Color? {
        store.state.label(named: task.label).flatMap { Color(cssHex: $0.color) }
    }
}

/// Crew's mission-list row: a small checkbox, the title and a muted word.
struct LineRow: View {
    let task: TaskItem
    let onOpen: () -> Void

    var body: some View {
        let status = TaskStatus.row(task)
        HStack(spacing: 9) {
            CheckToggle(task: task, size: 15)

            HStack(spacing: Theme.Space.s) {
                Text(task.text)
                    .font(Theme.text(Theme.Size.m))
                    .foregroundStyle(task.done ? Theme.muted : Theme.ink)
                    .strikethrough(task.done, color: Theme.faint)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !task.done && !status.text.isEmpty {
                    Text(status.text)
                        .font(Theme.text(Theme.Size.s))
                        .foregroundStyle(status.tone == .none ? Theme.muted : status.tone.color)
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
        }
        .padding(.leading, Theme.Space.m)
        .padding(.trailing, Theme.Space.s)
        .padding(.vertical, 7)
    }
}

/// In focus: Crew's active-thread row, with a mono countdown and a Stop chip.
struct FocusRow: View {
    @EnvironmentObject var store: Store
    let task: TaskItem
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            CheckCircle(done: false, ring: Theme.statusRunning)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Theme.Space.s6) {
                    Text(task.text)
                        .font(Theme.text(Theme.Size.m, .semibold))
                        .lineLimit(1)
                    Text("focus")
                        .font(Theme.mono(Theme.Size.xs, .medium))
                        .foregroundStyle(Theme.statusRunning)
                        .padding(.horizontal, 5)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.chip)
                                .strokeBorder(Theme.statusRunning.opacity(0.45), lineWidth: 1)
                        )
                        .fixedSize()
                }
                Text(sub)
                    .font(Theme.text(Theme.Size.s))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(formatCountdown(store.state.focus?.remaining ?? 0))
                    .font(Theme.mono(Theme.Size.s))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink2)
            }
            Button("Stop") { store.stopFocus() }
                .buttonStyle(.crew(.chip, height: 26))
                .accessibilityLabel("Stop the session")
        }
        .padding(.leading, Theme.Space.s)
        .padding(.trailing, Theme.Space.s6)
        .padding(.vertical, Theme.Space.s)
        .background(Theme.select, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private var sub: String {
        var bits: [String] = []
        if let p = task.priority { bits.append(p == "high" ? "High" : "Medium") }
        if let l = task.label { bits.append(l) }
        if let ms = task.focusedMs, ms > 0 {
            bits.append("\(TaskStatus.formatMinutes(ms)) before this")
        } else {
            bits.append("First session")
        }
        return bits.joined(separator: " · ")
    }
}

/// The checkbox as a button that completes the task.
struct CheckToggle: View {
    @EnvironmentObject var store: Store
    let task: TaskItem
    var size: CGFloat = 18
    var badge: Color? = nil

    var body: some View {
        Button { store.toggle(task) } label: {
            CheckCircle(done: task.done, size: size, badge: badge)
                .frame(width: Theme.Height.small, height: Theme.Height.small)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -(Theme.Height.small - size) / 2)
        .padding(.vertical, -(Theme.Height.small - size) / 2)
        .accessibilityLabel(task.done ? "Mark as not done" : "Mark as done")
        .animation(.easeOut(duration: 0.14), value: task.done)
    }
}

// MARK: - Status rules (ported from the widget's app.js)

enum Tone {
    case none, amber, red

    var color: Color {
        switch self {
        case .none: return Theme.muted
        case .amber: return Theme.amber
        case .red: return Theme.red
        }
    }
}

enum TaskStatus {
    private static let dayMs: Double = 86_400_000

    static func priorityRank(_ t: TaskItem) -> Int {
        switch t.priority {
        case "high": return 0
        case "med": return 1
        default: return 2
        }
    }

    /// Epoch ms of the deadline's midnight, or far future.
    static func dueValue(_ t: TaskItem) -> Double {
        guard let d = t.dueDate else { return .greatestFiniteMagnitude }
        return d.timeIntervalSince1970 * 1000
    }

    /// Crew's "Needs you": anything high, due today or earlier, or starting
    /// today or earlier.
    static func needsYou(_ t: TaskItem) -> Bool {
        if t.priority == "high" { return true }
        if t.dueDate != nil, dueValue(t) < (Date().startOfDay.timeIntervalSince1970 * 1000 + dayMs) {
            return true
        }
        if let s = t.startDate, s <= Date().endOfDay { return true }
        return false
    }

    /// The line under a task's title, and how loudly it speaks: red is late or
    /// high, amber is today, everything else stays quiet.
    static func row(_ task: TaskItem) -> (text: String, tone: Tone) {
        var bits: [String] = []
        var tone = Tone.none
        func raise(_ t: Tone) { if t == .red || tone == .none { tone = t } }

        let start = task.startDate
        let sameDay = start != nil && task.due != nil && task.startAt?.prefix(10) == task.due?.prefix(10)

        if let due = task.dueDate {
            let diff = dayDiff(due)
            if diff < 0 {
                bits.append("Overdue · \(short(due))")
                raise(.red)
            } else if diff == 0 {
                bits.append("Due today")
                raise(.amber)
            } else if diff == 1 {
                bits.append("Due tomorrow")
            } else {
                bits.append("Due \(short(due))")
            }
        }
        if let start {
            let time = start.formatted(date: .omitted, time: .shortened)
            let diff = dayDiff(start)
            let started = start <= Date()
            if started {
                bits.append("Started · \(time)")
                raise(.amber)
            } else if sameDay || diff == 0 {
                bits.append(time)
            } else if diff == 1 {
                bits.append("Tomorrow · \(time)")
            } else {
                bits.append("\(short(start)) · \(time)")
            }
        }
        if task.priority == "high" { bits.append("High"); raise(.red) }
        else if task.priority == "med" { bits.append("Medium"); raise(.amber) }
        if let r = task.repeatRule { bits.append(r.prefix(1).uppercased() + r.dropFirst()) }
        if task.isAging {
            let days = task.ageDays
            bits.append("\(days)d old")
            if days >= 14 { raise(.red) } else if days >= 7 { raise(.amber) }
        }
        if let ms = task.focusedMs, ms > 0 { bits.append("\(formatMinutes(ms)) focused") }
        return (bits.joined(separator: " · "), tone)
    }

    static func formatMinutes(_ ms: Double) -> String {
        let mins = Int((ms / 60000).rounded())
        if mins < 60 { return "\(mins)m" }
        return "\(mins / 60)h \(mins % 60)m"
    }

    /// What's left of today minus the meetings in it, overlaps merged.
    static func freeTodayMs(_ events: [CalEvent]) -> Double {
        let now = Date(), end = Date().endOfDay
        let spans = events
            .filter { $0.allDay != true }
            .compactMap { ev -> (Date, Date)? in
                guard let s = ev.startDate, let e = ev.endDate else { return nil }
                let a = max(s, now), b = min(e, end)
                return b > a ? (a, b) : nil
            }
            .sorted { $0.0 < $1.0 }
        var busy: TimeInterval = 0
        var cur: (Date, Date)?
        for span in spans {
            if let c = cur, span.0 <= c.1 {
                cur = (c.0, max(c.1, span.1))
            } else {
                if let c = cur { busy += c.1.timeIntervalSince(c.0) }
                cur = span
            }
        }
        if let c = cur { busy += c.1.timeIntervalSince(c.0) }
        return max(0, end.timeIntervalSince(now) - busy) * 1000
    }

    static func dayDiff(_ d: Date) -> Int {
        Calendar.current.dateComponents([.day], from: Date().startOfDay, to: d.startOfDay).day ?? 0
    }

    static func short(_ d: Date) -> String {
        d.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// Chips wrap onto as many lines as they need.
struct FlowRow: Layout {
    var spacing: CGFloat = 6
    /// Space between wrapped lines; defaults to `spacing`.
    var lineSpacing: CGFloat? = nil

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + (lineSpacing ?? spacing)
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + (lineSpacing ?? spacing)
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
