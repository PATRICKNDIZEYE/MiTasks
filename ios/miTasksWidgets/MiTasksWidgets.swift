import AppIntents
import SwiftUI
import WidgetKit

@main
struct MiTasksWidgets: WidgetBundle {
    var body: some Widget {
        UpNextWidget()
        PrioritiesWidget()
        WeekWidget()
        GlanceWidget()
        SessionLiveActivity()
        NewTaskControl()
        SpeakTaskControl()
    }
}

/// The app's Crew dark tokens, the handful a widget needs (see Theme.swift).
enum Palette {
    static let bg = Color(hex: 0x111110)
    static let surface2 = Color(hex: 0x1C1C1A)
    static let ink = Color(hex: 0xEDECE9)
    static let muted = Color(hex: 0x8F8D88)
    static let faint = Color(hex: 0x64625E)
    static let line = Color(hex: 0x262624)
    static let chip = Color(hex: 0x3B3B3C)
    static let brand = Color(hex: 0xF2A93B)
    static let amber = Color(hex: 0xE4A53A)
    static let red = Color(hex: 0xEC6A5A)
    static let green = Color(hex: 0x52C48F)
    static let blue = Color(hex: 0x79A3FF)

    static func tone(_ t: Tone) -> Color {
        switch t {
        case .none: return muted
        case .amber: return amber
        case .red: return red
        }
    }

    static func priority(_ p: String?) -> Color {
        switch p {
        case "high": return red
        case "med": return amber
        default: return line
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    init?(css: String?) {
        guard var s = css else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }
}

// MARK: - Up Next (small)

struct UpNextWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "UpNext", intent: FilterIntent.self, provider: TasksProvider()) { entry in
            UpNextView(entry: entry)
                .containerBackground(Palette.bg, for: .widget)
        }
        .configurationDisplayName("Up Next")
        .description("Your single most important open task, one tap from done.")
        .supportedFamilies([.systemSmall])
    }
}

struct UpNextView: View {
    let entry: TasksEntry

    var body: some View {
        let next = entry.ranked.first
        VStack(alignment: .leading, spacing: 0) {
            Header(title: entry.label ?? "Up next", dot: Color(css: entry.color) ?? Palette.brand) {
                if entry.needsYou.count > 0 {
                    Text("\(entry.needsYou.count)")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Palette.amber)
                }
            }

            if !entry.paired {
                Empty(big: "Not paired", small: "Open miTasks to connect your Mac.")
            } else if let next {
                Text(next.text)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(3)
                    .padding(.top, 8)
                let status = TaskStatus.row(next)
                if !status.text.isEmpty {
                    Text(status.text)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tone(status.tone))
                        .lineLimit(1)
                        .padding(.top, 3)
                }
                Spacer(minLength: 6)
                Button(intent: CompleteTaskIntent(taskId: next.id)) {
                    Label("Done", systemImage: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(Palette.chip, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Empty(big: "All clear", small: "\(entry.state.doneToday) done today")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(next.map { AppRoute.task($0.id).url })
    }
}

// MARK: - Priorities (medium, large)

struct PrioritiesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Priorities", intent: FilterIntent.self, provider: TasksProvider()) { entry in
            PrioritiesView(entry: entry)
                .containerBackground(Palette.bg, for: .widget)
        }
        .configurationDisplayName("Priorities")
        .description("High, then medium, then by deadline. Tick them off without opening the app.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct PrioritiesView: View {
    let entry: TasksEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let ranked = entry.ranked
        let rows = family == .systemLarge ? 7 : 3
        let overdue = ranked.filter(\.isOverdue).count
        let today = ranked.filter(\.isDueToday).count

        VStack(alignment: .leading, spacing: 0) {
            Header(title: entry.label ?? "Priorities", dot: Color(css: entry.color) ?? Palette.brand) {
                HStack(spacing: 8) {
                    if overdue > 0 { Count(n: overdue, word: "late", color: Palette.red) }
                    if today > 0 { Count(n: today, word: "today", color: Palette.amber) }
                    if overdue == 0 && today == 0 { Count(n: ranked.count, word: "open", color: Palette.muted) }
                }
            }

            if family == .systemLarge, let meeting = entry.state.nextMeeting {
                MeetingLine(event: meeting).padding(.top, 8)
            }

            if !entry.paired {
                Empty(big: "Not paired", small: "Open miTasks to connect your Mac.")
            } else if ranked.isEmpty {
                Empty(big: "All clear", small: "\(entry.state.doneToday) done today — nothing waiting.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(ranked.prefix(rows).enumerated()), id: \.element.id) { i, task in
                        if i > 0 { Rectangle().fill(Palette.line).frame(height: 1) }
                        TaskRow(task: task, labelColor: entry.state.label(named: task.label)?.color,
                                showLabel: entry.label == nil)
                    }
                }
                .padding(.top, 6)
                Spacer(minLength: 0)
                Footer(more: ranked.count - rows, live: entry.live, doneToday: entry.state.doneToday)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct TaskRow: View {
    let task: TaskItem
    let labelColor: String?
    let showLabel: Bool

    var body: some View {
        let status = TaskStatus.row(task)
        HStack(spacing: 10) {
            Button(intent: CompleteTaskIntent(taskId: task.id)) {
                Circle()
                    .strokeBorder(Palette.priority(task.priority) == Palette.line ? Palette.faint : Palette.priority(task.priority),
                                  lineWidth: 1.5)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle().inset(by: -6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark \(task.text) as done")

            Link(destination: AppRoute.task(task.id).url) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(task.text)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        if !status.text.isEmpty {
                            Text(status.text)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Palette.tone(status.tone))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if showLabel, let c = Color(css: labelColor) {
                        Circle().fill(c).frame(width: 6, height: 6)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Lock Screen

struct GlanceWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Glance", intent: FilterIntent.self, provider: TasksProvider()) { entry in
            GlanceView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Glance")
        .description("What needs you now, on the Lock Screen.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct GlanceView: View {
    let entry: TasksEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let needs = entry.needsYou.count
        let done = entry.state.doneToday
        switch family {
        case .accessoryCircular:
            // Today's progress: what's done against what still needs you.
            Gauge(value: Double(done), in: 0...Double(max(done + needs, 1))) {
                Image(systemName: "checkmark")
            } currentValueLabel: {
                Text("\(needs)").font(.system(size: 18, weight: .semibold).monospacedDigit())
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()

        case .accessoryInline:
            if let next = entry.ranked.first {
                Text("\(needs > 0 ? "\(needs) now · " : "")\(next.text)")
            } else {
                Text("All clear · \(done) done")
            }

        default:
            VStack(alignment: .leading, spacing: 1) {
                Text(needs > 0 ? "NEEDS YOU · \(needs)" : "UP NEXT")
                    .font(.system(size: 11, weight: .semibold))
                    .widgetAccentable()
                if let next = entry.ranked.first {
                    Text(next.text)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                    let status = TaskStatus.row(next).text
                    if !status.isEmpty {
                        Text(status).font(.system(size: 12)).lineLimit(1).opacity(0.7)
                    }
                } else {
                    Text("All clear").font(.system(size: 15, weight: .semibold))
                    Text("\(done) done today").font(.system(size: 12)).opacity(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(entry.ranked.first.map { AppRoute.task($0.id).url })
        }
    }
}

// MARK: - Pieces

struct Header<Trailing: View>: View {
    let title: String
    let dot: Color
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
            Spacer(minLength: 4)
            trailing
        }
    }
}

struct Count: View {
    let n: Int
    let word: String
    let color: Color

    var body: some View {
        Text("\(n) \(word)")
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(color)
    }
}

struct MeetingLine: View {
    let event: CalEvent

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar").font(.system(size: 10, weight: .semibold))
            Text(event.isNow ? "Now" : (event.startDate?.clockLabel ?? ""))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
            Text(event.title ?? "Meeting").font(.system(size: 11)).lineLimit(1)
        }
        .foregroundStyle(event.isNow ? Palette.green : Palette.muted)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct Footer: View {
    let more: Int
    let live: Bool
    let doneToday: Int

    var body: some View {
        HStack(spacing: 6) {
            if more > 0 { Text("+\(more) more") }
            if doneToday > 0 { Text("\(doneToday) done today").foregroundStyle(Palette.green) }
            Spacer(minLength: 0)
            if !live { Text("offline copy").foregroundStyle(Palette.faint) }
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(Palette.muted)
    }
}

struct Empty: View {
    let big: String
    let small: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Spacer(minLength: 0)
            Text(big).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
            Text(small).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview(as: .systemMedium) {
    PrioritiesWidget()
} timeline: {
    TasksEntry.preview
}
