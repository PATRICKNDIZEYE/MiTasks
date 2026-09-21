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
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        field("Task") {
                            TextField("", text: $text, axis: .vertical)
                                .font(.system(size: 14.5))
                                .padding(12)
                                .background(Theme.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                        }

                        field("Priority") {
                            Segmented(
                                options: [(nil, "None"), ("med", "Medium"), ("high", "High")],
                                selection: $priority
                            )
                        }

                        field("Label") {
                            Segmented(
                                options: [(nil, "None")] + store.state.labels.map { ($0.name, $0.name) },
                                selection: $label
                            )
                        }

                        field("Due date") {
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle("Has a due date", isOn: $hasDue)
                                    .font(.system(size: 13))
                                    .tint(Theme.amber)
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
                                    .font(.system(size: 13))
                                    .tint(Theme.amber)
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
                                    (nil, "Never"), ("daily", "Daily"),
                                    ("weekly", "Weekly"), ("monthly", "Monthly"),
                                ],
                                selection: $repeatRule
                            )
                        }

                        field("Notes") {
                            TextField("", text: $notes, axis: .vertical)
                                .font(.system(size: 14.5))
                                .lineLimit(5...)
                                .padding(12)
                                .background(Theme.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                        }

                        Button(role: .destructive) {
                            store.delete(task)
                            dismiss()
                        } label: {
                            Text("Delete task")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .foregroundStyle(Theme.clay)
                                .background(RoundedRectangle(cornerRadius: 11).stroke(Theme.clay.opacity(0.4), lineWidth: 1))
                        }
                        .padding(.top, 6)
                    }
                    .padding(20)
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
                    Button("Save", action: save).fontWeight(.bold)
                }
            }
        }
        .onAppear(perform: load)
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
        VStack(alignment: .leading, spacing: 7) {
            Eyebrow(text: title)
            content()
        }
    }
}

/// A wrapping row of mutually exclusive buttons — Picker's segmented style
/// can't hold a dozen client names without shrinking them to nothing.
struct Segmented: View {
    let options: [(String?, String)]
    @Binding var selection: String?

    var body: some View {
        FlowRow(spacing: 7) {
            ForEach(options.indices, id: \.self) { i in
                let (value, title) = options[i]
                Button { selection = value } label: {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .foregroundStyle(selection == value ? Theme.bgLo : Theme.ink2)
                        .background(selection == value ? Theme.ink : .clear, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(selection == value ? .clear : Theme.hair, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
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
                Theme.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    Text("Keeps your Mac awake — no sleep, no lock screen — until the timer runs out.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink2)
                        .lineSpacing(2)

                    Eyebrow(text: store.state.lockin.active ? "Replace with" : "Keep awake for")

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(presets, id: \.self) { m in
                            Button {
                                store.startLockin(minutes: m)
                                dismiss()
                            } label: {
                                Text(labelFor(m))
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.hair, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("Minutes", text: $custom)
                            .keyboardType(.numberPad)
                            .font(.system(size: 14))
                            .padding(12)
                            .background(Theme.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                        Button("Start") {
                            if let m = Int(custom), m > 0 {
                                store.startLockin(minutes: m)
                                dismiss()
                            }
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.amber)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(Theme.amberSoft, in: RoundedRectangle(cornerRadius: 10))
                    }

                    if store.state.lockin.active {
                        Button("Stop lock-in") {
                            store.stopLockin()
                            dismiss()
                        }
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundStyle(Theme.ink2)
                        .background(RoundedRectangle(cornerRadius: 11).stroke(Theme.hair, lineWidth: 1))
                    }

                    Spacer()
                }
                .padding(20)
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
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        Eyebrow(text: "Title")
                        TextField("", text: $title)
                            .font(.system(size: 15, weight: .semibold))
                            .padding(12)
                            .background(Theme.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))

                        Eyebrow(text: "Body")
                        TextField("", text: $body_, axis: .vertical)
                            .font(.system(size: 14.5))
                            .lineLimit(10...)
                            .padding(12)
                            .background(Theme.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))

                        Button(role: .destructive) {
                            store.deleteNote(note)
                            dismiss()
                        } label: {
                            Text("Delete note")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .foregroundStyle(Theme.clay)
                                .background(RoundedRectangle(cornerRadius: 11).stroke(Theme.clay.opacity(0.4), lineWidth: 1))
                        }
                        .padding(.top, 6)
                    }
                    .padding(20)
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
                    .fontWeight(.bold)
                }
            }
        }
        .onAppear {
            title = note.title ?? ""
            body_ = note.body ?? ""
        }
    }
}
