import SwiftUI

struct TaskEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    let task: TaskItem

    @State private var text = ""
    @State private var notes = ""
    @State private var priority: String?
    @State private var label: String?
    @State private var repeatRule: String?
    @State private var hasDue = false
    @State private var due = Date()
    @State private var hasStart = false
    @State private var start = Date()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.surface.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        field("Task") {
                            TextField("", text: $text, axis: .vertical)
                                .font(Theme.text(Theme.Size.body))
                                .crewInput()
                        }

                        field("Label") {
                            FlowRow(spacing: Theme.Space.xs) {
                                OptionChip(title: "None", on: label == nil) { label = nil }
                                ForEach(store.state.labels) { l in
                                    OptionChip(title: l.name, dot: Color(cssHex: l.color), on: label == l.name) {
                                        label = l.name
                                    }
                                }
                            }
                        }

                        field("Priority") {
                            Segmented(
                                options: [(nil, "None"), ("med", "Medium"), ("high", "High")],
                                selection: $priority,
                                tints: ["med": Theme.amber, "high": Theme.red]
                            )
                        }

                        if !task.done {
                            field("Focus") {
                                let focused = store.state.focus?.taskId == task.id
                                Button(focused ? "Stop session" : "Focus · \(store.state.focusMinutes) min") {
                                    focused ? store.stopFocus() : store.startFocus(task)
                                    dismiss()
                                }
                                .buttonStyle(.crew(focused ? .destructive : .chip, height: 26))
                            }
                        }

                        field("Due date") {
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle("Has a due date", isOn: $hasDue)
                                    .font(Theme.text(Theme.Size.body))
                                    .tint(Theme.statusRunning)
                                if hasDue {
                                    DatePicker("", selection: $due, displayedComponents: .date)
                                        .datePickerStyle(.compact)
                                        .labelsHidden()
                                }
                            }
                        }

                        field("Start time") {
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle("Has a start time", isOn: $hasStart)
                                    .font(Theme.text(Theme.Size.body))
                                    .tint(Theme.statusRunning)
                                if hasStart {
                                    DatePicker("", selection: $start)
                                        .datePickerStyle(.compact)
                                        .labelsHidden()
                                }
                            }
                        }

                        field("Repeat") {
                            Segmented(
                                options: [
                                    (nil, "Off"), ("daily", "Daily"),
                                    ("weekly", "Weekly"), ("monthly", "Monthly"),
                                ],
                                selection: $repeatRule
                            )
                        }

                        field("Notes") {
                            TextField("", text: $notes, axis: .vertical)
                                .font(Theme.text(Theme.Size.body))
                                .lineLimit(5...)
                                .crewInput()
                        }

                        Button(role: .destructive) {
                            store.delete(task)
                            dismiss()
                        } label: {
                            Text("Delete task")
                        }
                        .buttonStyle(.crew(.destructive, height: Theme.Height.regular))
                        .padding(.top, Theme.Space.s)
                    }
                    .padding(Theme.Space.xl)
                }
            }
            .foregroundStyle(Theme.ink)
            .navigationTitle("Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold)
                }
            }
        }
        .onAppear(perform: load)
        .crewSheet()
    }

    private func load() {
        text = task.text
        notes = task.notes ?? ""
        priority = task.priority
        label = task.label
        repeatRule = task.repeatRule
        if let d = task.dueDate { hasDue = true; due = d }
        if let s = task.startDate { hasStart = true; start = s }
    }

    private func save() {
        var changes: [String: Any] = ["text": text, "notes": notes]
        changes["priority"] = priority
        changes["label"] = label
        changes["repeat"] = repeatRule
        changes["due"] = hasDue ? DateParse.dayString(due) : nil
        changes["startAt"] = hasStart ? DateParse.localString(start) : nil
        store.update(task, changes: changes)
        dismiss()
    }

    @ViewBuilder
    private func field<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Eyebrow(text: title)
            content()
        }
    }
}

/// Crew's segmented control: a sunken `surface-3` track with the chosen
/// segment lifted onto `chip-bg`. `tints` colours a chosen segment by meaning.
struct Segmented: View {
    let options: [(String?, String)]
    @Binding var selection: String?
    var tints: [String: Color] = [:]

    var body: some View {
        HStack(spacing: Theme.Space.xxs) {
            ForEach(options.indices, id: \.self) { i in
                let (value, title) = options[i]
                let on = selection == value
                Button { selection = value } label: {
                    Text(title)
                        .font(Theme.text(Theme.Size.s, on ? .medium : .regular))
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .foregroundStyle(on ? (value.flatMap { tints[$0] } ?? Theme.ink) : Theme.ink2)
                        .background(on ? Theme.chipBg : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(Theme.Space.xxs)
        .background(Theme.surface3, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

struct LockinSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var custom = ""

    private let presets = [25, 45, 60, 90, 120, 180]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.surface.ignoresSafeArea()
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    Text("Keeps your Mac awake — no sleep, no lock screen — until the timer runs out.")
                        .font(Theme.text(Theme.Size.m))
                        .foregroundStyle(Theme.ink2)
                        .lineSpacing(Theme.Space.xxs)

                    Eyebrow(text: store.state.lockin.active ? "Replace with" : "Keep this Mac awake for")

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Space.s), count: 3), spacing: Theme.Space.s) {
                        ForEach(presets, id: \.self) { m in
                            Button {
                                store.startLockin(minutes: m)
                                dismiss()
                            } label: {
                                Text(labelFor(m))
                                    .font(Theme.mono(Theme.Size.m, .medium))
                            }
                            .buttonStyle(.crew(.chip, height: Theme.Height.regular, fullWidth: true))
                        }
                    }

                    HStack(spacing: Theme.Space.s) {
                        TextField("Minutes", text: $custom)
                            .keyboardType(.numberPad)
                            .font(Theme.mono(Theme.Size.body))
                            .crewInput()
                        Button("Start") {
                            if let m = Int(custom), m > 0 {
                                store.startLockin(minutes: m)
                                dismiss()
                            }
                        }
                        .buttonStyle(.crew(.primary, height: Theme.Height.large))
                    }

                    if store.state.lockin.active {
                        Button("Stop lock-in") {
                            store.stopLockin()
                            dismiss()
                        }
                        .buttonStyle(.crew(.destructive, height: Theme.Height.regular))
                    }

                    Spacer()
                }
                .padding(Theme.Space.xl)
            }
            .foregroundStyle(Theme.ink)
            .navigationTitle(store.state.lockin.active ? "Locked in" : "Lock in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .crewSheet()
    }

    private func labelFor(_ m: Int) -> String {
        if m < 60 { return "\(m)m" }
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)½h"
    }
}

struct NoteEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    let note: NoteItem
    @State private var title = ""
    @State private var body_ = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.surface.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        TextField(
                            "",
                            text: $title,
                            prompt: Text("Title").foregroundStyle(Theme.faint)
                        )
                        .font(Theme.text(Theme.Size.xl, .semibold))
                        .padding(.bottom, Theme.Space.s)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Theme.line).frame(height: 1)
                        }

                        TextField(
                            "",
                            text: $body_,
                            prompt: Text("Write it down…").foregroundStyle(Theme.faint),
                            axis: .vertical
                        )
                        .font(Theme.text(Theme.Size.body))
                        .lineSpacing(5)
                        .lineLimit(12...)
                        .padding(.top, Theme.Space.m)

                        Button(role: .destructive) {
                            store.deleteNote(note)
                            dismiss()
                        } label: {
                            Text("Delete note")
                        }
                        .buttonStyle(.crew(.destructive, height: Theme.Height.regular))
                        .padding(.top, Theme.Space.xxl)
                    }
                    .padding(Theme.Space.xl)
                }
            }
            .foregroundStyle(Theme.ink)
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.saveNote(note, title: title, body: body_)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            title = note.title ?? ""
            body_ = note.body ?? ""
        }
        .crewSheet()
    }
}
