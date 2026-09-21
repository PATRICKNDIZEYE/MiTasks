import SwiftUI

struct TodayView: View {
    @EnvironmentObject var store: Store
    @State private var draft = ""
    @State private var activeLabel: String?
    @State private var editing: TaskItem?
    @State private var showLockin = false

    private var parsed: QuickAdd? {
        let raw = draft.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }
        return QuickAdd.parse(raw, labels: store.state.labels, activeLabel: activeLabel)
    }

    private var visible: [TaskItem] {
        guard let activeLabel else { return store.state.tasks }
        return store.state.tasks.filter { $0.label == activeLabel }
    }

    private var pending: [TaskItem] {
        // Same ordering the widget uses: overdue and timed work first, then
        // priority, then newest.
        visible.filter { !$0.done }.sorted { a, b in
            let wa = weight(a), wb = weight(b)
            if wa != wb { return wa < wb }
            return (a.createdAt ?? 0) > (b.createdAt ?? 0)
        }
    }

    private var done: [TaskItem] {
        visible.filter(\.done).sorted { ($0.doneAt ?? 0) > ($1.doneAt ?? 0) }
    }

    private func weight(_ t: TaskItem) -> Int {
        var w = 0
        if let d = t.dueDate {
            let days = Calendar.current.dateComponents(
                [.day], from: Date().startOfDay, to: d.startOfDay
            ).day ?? 0
            if days < 0 { w -= 1000 } else if days == 0 { w -= 500 }
        }
        if t.startAt != nil { w -= 250 }
        if t.priority == "high" { w -= 100 } else if t.priority == "med" { w -= 50 }
        return w
    }

    var body: some View {
        Screen(
            title: "Today",
            subtitle: Date().formatted(.dateTime.weekday(.wide).month(.wide).day()),
            trailing: AnyView(lockinButton)
        ) {
            progress
            if store.state.lockin.active { LockinStrip() }
            if store.state.focus != nil { FocusStrip() }
            addBar
            chips

            LazyVStack(spacing: 0) {
                ForEach(pending) { task in
                    TaskRow(task: task) { editing = task }
                }
            }
            .padding(.top, 16)

            if pending.isEmpty {
                EmptyNote(big: "Nothing pending.", small: "Add something above.")
            }

            if !done.isEmpty {
                SectionRule(
                    title: "\(done.count) done",
                    trailing: AnyView(
                        Button("Clear") { store.clearDone() }
                            .font(Theme.label())
                            .foregroundStyle(Theme.ink3)
                    )
                )
                LazyVStack(spacing: 0) {
                    ForEach(done.prefix(40)) { task in
                        TaskRow(task: task) { editing = task }
                    }
                }
            }
        }
        .sheet(item: $editing) { TaskEditor(task: $0) }
        .sheet(isPresented: $showLockin) { LockinSheet() }
    }

    private var lockinButton: some View {
        Button { showLockin = true } label: {
            Image(systemName: "cup.and.saucer")
                .font(.system(size: 17))
                .frame(width: 36, height: 36)
                .foregroundStyle(store.state.lockin.active ? Theme.amber : Theme.ink3)
                .background(
                    store.state.lockin.active ? Theme.amberSoft : .clear,
                    in: RoundedRectangle(cornerRadius: 10)
                )
        }
    }

    private var progress: some View {
        let total = pending.count + done.count
        let pct = total > 0 ? Double(done.count) / Double(total) : 0
        return HStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.ink.opacity(0.1))
                    Capsule().fill(Theme.amber).frame(width: geo.size.width * pct)
                }
            }
            .frame(height: 3)
            Text(total > 0 ? "\(done.count)/\(total)" : "Nothing yet")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.ink2)
        }
        .padding(.top, 18)
    }

    private var addBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Add a task…", text: $draft)
                    .font(.system(size: 15))
                    .submitLabel(.done)
                    .onSubmit(commit)
                Button(action: commit) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 30, height: 30)
                        .foregroundStyle(Theme.amber)
                        .background(Theme.amberSoft, in: RoundedRectangle(cornerRadius: 9))
                }
            }
            .padding(.bottom, 9)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.hair).frame(height: 1)
            }

            Text(parsed?.summary ?? " ")
                .font(.system(size: 11))
                .foregroundStyle(Theme.amber)
                .frame(height: 14, alignment: .leading)
        }
        .padding(.top, 18)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                chip(title: "All", color: nil, on: activeLabel == nil) { activeLabel = nil }
                ForEach(store.state.labels) { l in
                    let open = store.state.tasks.filter { !$0.done && $0.label == l.name }.count
                    chip(
                        title: open > 0 ? "\(l.name) \(open)" : l.name,
                        color: Color(cssHex: l.color),
                        on: activeLabel == l.name
                    ) {
                        activeLabel = activeLabel == l.name ? nil : l.name
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .padding(.top, 14)
    }

    private func chip(title: String, color: Color?, on: Bool, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 5) {
                if let color { Circle().fill(color).frame(width: 6, height: 6) }
                Text(title).font(.system(size: 11.5, weight: .semibold))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .foregroundStyle(on ? Theme.bgLo : Theme.ink2)
            .background(on ? Theme.ink : .clear, in: Capsule())
            .overlay(Capsule().stroke(on ? .clear : Theme.hair, lineWidth: 1))
        }
    }

    private func commit() {
        guard let parsed, !parsed.text.isEmpty else { return }
        store.add(parsed)
        draft = ""
    }
}

struct TaskRow: View {
    @EnvironmentObject var store: Store
    let task: TaskItem
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Button { store.toggle(task) } label: {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(task.done ? Theme.amber : Theme.ink3, lineWidth: 1.5)
                    .background(
                        task.done
                            ? RoundedRectangle(cornerRadius: 7).fill(Theme.amber)
                            : RoundedRectangle(cornerRadius: 7).fill(.clear)
                    )
                    .frame(width: 21, height: 21)
                    .overlay {
                        if task.done {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(Theme.bgLo)
                        }
                    }
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                Text(task.text)
                    .font(.system(size: 14.5))
                    .foregroundStyle(task.done ? Theme.ink3 : Theme.ink)
                    .strikethrough(task.done)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !tags.isEmpty {
                    FlowRow(spacing: 6) { ForEach(tags.indices, id: \.self) { tags[$0] } }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)

            if !task.done {
                Button {
                    isFocused ? store.stopFocus() : store.startFocus(task)
                } label: {
                    Image(systemName: isFocused ? "pause.fill" : "play.fill")
                        .font(.system(size: 13))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(isFocused ? Theme.amber : Theme.ink3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hair).frame(height: 1) }
    }

    private var isFocused: Bool { store.state.focus?.taskId == task.id }

    private var tags: [Chip] {
        var out: [Chip] = []
        if let l = store.state.label(named: task.label) {
            out.append(Chip(text: l.name, dot: Color(cssHex: l.color)))
        }
        if let p = task.priority {
            out.append(Chip(
                text: p == "high" ? "HIGH" : "MED",
                tint: p == "high" ? Theme.clay : Theme.amber,
                fill: (p == "high" ? Theme.clay : Theme.amber).opacity(0.16)
            ))
        }
        if let s = task.startDate {
            let overdue = s < Date()
            out.append(Chip(
                text: s.clockLabel,
                tint: overdue ? Theme.clay : Theme.ink2,
                fill: overdue ? Theme.clay.opacity(0.16) : Theme.ink.opacity(0.07)
            ))
        } else if let d = task.dueDate {
            let days = Calendar.current.dateComponents(
                [.day], from: Date().startOfDay, to: d.startOfDay
            ).day ?? 0
            let tint = days < 0 ? Theme.clay : days == 0 ? Theme.amber : Theme.ink2
            out.append(Chip(
                text: QuickAdd.dueWord(d),
                tint: tint,
                fill: days <= 0 ? tint.opacity(0.16) : Theme.ink.opacity(0.07)
            ))
        }
        if let r = task.repeatRule { out.append(Chip(text: r)) }
        if task.isAging {
            let d = task.ageDays
            let tint = d >= 14 ? Theme.clay : Theme.amber
            out.append(Chip(text: "\(d)d old", tint: tint, fill: tint.opacity(0.16)))
        }
        return out
    }
}

/// Chips wrap onto as many lines as they need — SwiftUI has no built-in
/// flow layout before iOS 16's Layout protocol, so this is the small version.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
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
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct FocusStrip: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let task = store.state.tasks.first { $0.id == store.state.focus?.taskId }
        HStack(spacing: 10) {
            Circle().fill(Theme.amber).frame(width: 7, height: 7)
            Text(task?.text ?? "Focus")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(formatCountdown(store.state.focus?.remaining ?? 0))
                .font(Theme.display(16))
                .foregroundStyle(Theme.amber)
                .monospacedDigit()
            Button("Stop") { store.stopFocus() }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.ink2)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Theme.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Theme.amberSoft, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.amber.opacity(0.45), lineWidth: 1))
        .padding(.top, 14)
        .id(store.tick)
    }
}

struct LockinStrip: View {
    @EnvironmentObject var store: Store

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Theme.sage).frame(width: 7, height: 7)
            Text("Locked in").font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 0)
            Text(formatCountdown(store.state.lockin.remaining))
                .font(Theme.display(16))
                .foregroundStyle(Theme.sage)
                .monospacedDigit()
            Button("+15") { store.startLockin(minutes: 15, extend: true) }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.ink2)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Theme.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            Button("Stop") { store.stopLockin() }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.ink2)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Theme.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Theme.sage.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.sage.opacity(0.4), lineWidth: 1))
        .padding(.top, 14)
        .id(store.tick)
    }
}
