import SwiftUI
import WidgetKit

/// The next seven days at a glance: what's due each day next to the meetings
/// already in it, so a crowded Thursday is obvious before Thursday.
struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Week", intent: FilterIntent.self, provider: TasksProvider()) { entry in
            WeekView(entry: entry)
                .containerBackground(Palette.bg, for: .widget)
        }
        .configurationDisplayName("This Week")
        .description("Tasks due each day alongside your meetings.")
        .supportedFamilies([.systemLarge])
    }
}

private struct DayPlan: Identifiable {
    let date: Date
    let tasks: [TaskItem]
    let meetings: [CalEvent]
    let late: Int
    var id: Date { date }
}

struct WeekView: View {
    let entry: TasksEntry

    private var days: [DayPlan] {
        let open = entry.ranked
        let cal = Calendar.current
        return (0..<7).compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: Date().startOfDay) else { return nil }
            let key = DateParse.dayString(day)
            // A task belongs to the day it's due, or failing that, the day it starts.
            let tasks = open.filter { ($0.due ?? $0.startAt.map { String($0.prefix(10)) }) == key }
            let meetings = entry.state.events
                .filter { ev in
                    guard ev.allDay != true, let s = ev.startDate else { return false }
                    return cal.isDate(s, inSameDayAs: day) && (ev.endDate ?? s) > Date()
                }
                .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
            return DayPlan(date: day, tasks: tasks, meetings: meetings,
                           late: offset == 0 ? open.filter(\.isOverdue).count : 0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Header(title: entry.label ?? "This week", dot: Color(css: entry.color) ?? Palette.brand) {
                let due = days.reduce(0) { $0 + $1.tasks.count }
                Count(n: due, word: "due", color: Palette.muted)
            }
            .padding(.bottom, 4)

            if !entry.paired {
                Empty(big: "Not paired", small: "Open miTasks to connect your Mac.")
            } else {
                ForEach(Array(days.enumerated()), id: \.element.id) { i, day in
                    if i > 0 { Rectangle().fill(Palette.line).frame(height: 1) }
                    DayRow(day: day, isToday: i == 0, labels: entry.state)
                        .frame(maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct DayRow: View {
    let day: DayPlan
    let isToday: Bool
    let labels: AppState

    private enum Item: Identifiable {
        case meeting(CalEvent), task(TaskItem)
        var id: String {
            switch self {
            case .meeting(let e): return "m" + e.id
            case .task(let t): return "t" + t.id
            }
        }
    }

    var body: some View {
        // Two lines per day: the most important tasks first, then meetings.
        let items: [Item] = day.tasks.map(Item.task) + day.meetings.map(Item.meeting)
        let shown = items.prefix(2)

        HStack(alignment: .center, spacing: 10) {
            VStack(spacing: 0) {
                Text(day.date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isToday ? Palette.brand : Palette.faint)
                Text(day.date.formatted(.dateTime.day()))
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(isToday ? Palette.ink : Palette.muted)
            }
            .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                if shown.isEmpty {
                    Text(day.late > 0 ? "" : "Nothing due")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.faint)
                }
                ForEach(Array(shown)) { item in
                    switch item {
                    case .task(let t):
                        Link(destination: AppRoute.task(t.id).url) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(t.priority == nil ? Palette.faint : Palette.priority(t.priority))
                                    .frame(width: 6, height: 6)
                                Text(t.text)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                            }
                        }
                    case .meeting(let e):
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color(css: e.color) ?? Palette.muted)
                                .frame(width: 2, height: 10)
                            Text(e.startDate?.clockLabel ?? "")
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                            Text(e.title ?? "Meeting")
                                .font(.system(size: 11))
                                .lineLimit(1)
                        }
                        .foregroundStyle(Palette.muted)
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                if day.late > 0 { Count(n: day.late, word: "late", color: Palette.red) }
                if items.count > 2 {
                    Text("+\(items.count - 2)")
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(Palette.muted)
                }
            }
        }
    }
}
