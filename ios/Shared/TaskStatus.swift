import Foundation

// MARK: - Status rules (ported from the widget's app.js)

/// How loudly a task's status line speaks. Each front-end picks the colour.
enum Tone {
    case none, amber, red
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
