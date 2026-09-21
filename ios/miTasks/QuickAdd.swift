import Foundation

/// The widget's quick-add grammar, ported so muscle memory carries over:
///
///   !high / !med            priority
///   @azul                   label (prefix match)
///   today / tomorrow / in 3 days / friday
///   at 3pm / at 15:30 / 3pm
///   every day / every week / every month
struct QuickAdd {
    var text: String
    var priority: String?
    var label: String?
    var due: String?
    var startAt: String?
    var repeatRule: String?

    var summary: String {
        var bits: [String] = []
        if let label { bits.append(label) }
        if let priority { bits.append(priority == "high" ? "high priority" : "medium") }
        if let startAt, let d = DateParse.local(startAt) {
            bits.append(d.clockLabel)
        } else if let due, let d = DateParse.day(due) {
            bits.append(Self.dueWord(d))
        }
        if let repeatRule { bits.append(repeatRule) }
        return bits.joined(separator: " · ")
    }

    static func dueWord(_ date: Date) -> String {
        let days = Calendar.current.dateComponents(
            [.day], from: Date().startOfDay, to: date.startOfDay
        ).day ?? 0
        switch days {
        case ..<(-1): return "\(-days)d late"
        case -1: return "yesterday"
        case 0: return "today"
        case 1: return "tomorrow"
        case 2..<7: return "\(days)d"
        default:
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return f.string(from: date)
        }
    }

    private static let weekdays = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"
    ]

    static func parse(_ raw: String, labels: [LabelItem], activeLabel: String?) -> QuickAdd {
        var text = " \(raw) "
        var out = QuickAdd(text: "", label: activeLabel)

        func match(_ pattern: String) -> [String]? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
            else { return nil }
            var groups: [String] = []
            for i in 0..<m.numberOfRanges {
                if let r = Range(m.range(at: i), in: text) {
                    groups.append(String(text[r]))
                } else {
                    groups.append("")
                }
            }
            text = text.replacingCharacters(
                in: Range(m.range, in: text)!, with: " "
            )
            return groups
        }

        if match(#"\s!(high|h)(?=\s)"#) != nil {
            out.priority = "high"
        } else if match(#"\s!(med|medium|m)(?=\s)"#) != nil {
            out.priority = "med"
        }

        if let g = match(#"\s@([\w-]+)"#) {
            let q = g[1].lowercased()
            if let found = labels.first(where: {
                $0.name.lowercased().replacingOccurrences(of: " ", with: "").hasPrefix(q)
            }) {
                out.label = found.name
            }
        }

        if let g = match(#"\severy\s?(day|week|month|monday|tuesday|wednesday|thursday|friday|saturday|sunday)(?=\s)"#) {
            let w = g[1].lowercased()
            out.repeatRule = w == "day" ? "daily" : w == "month" ? "monthly" : "weekly"
        }

        var base: Date?
        if match(#"\s(today|tonight)(?=\s)"#) != nil {
            base = Date()
        } else if match(#"\s(tomorrow|tmrw|tmr)(?=\s)"#) != nil {
            base = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        } else if let g = match(#"\sin (\d{1,2}) days?(?=\s)"#) {
            base = Calendar.current.date(byAdding: .day, value: Int(g[1]) ?? 1, to: Date())
        } else if let g = match(#"\s(?:on |next )?(monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|wed|thu|fri|sat|sun)(?=\s)"#) {
            let q = g[1].lowercased()
            if let idx = weekdays.firstIndex(where: { $0 == q || $0.prefix(3) == q }) {
                // Calendar.weekday is Sunday-first; the widget's list is Monday-first.
                let todayIdx = (Calendar.current.component(.weekday, from: Date()) + 5) % 7
                var delta = (idx - todayIdx + 7) % 7
                if delta == 0 { delta = 7 }
                base = Calendar.current.date(byAdding: .day, value: delta, to: Date())
            }
        }

        var hour: Int?
        var minute = 0
        if let g = match(#"\s(?:at\s)?(\d{1,2})(?::(\d{2}))?\s?(am|pm)(?=\s)"#) {
            var h = (Int(g[1]) ?? 0) % 12
            if g[3].lowercased() == "pm" { h += 12 }
            hour = h
            minute = Int(g[2]) ?? 0
        } else if let g = match(#"\sat\s(\d{1,2}):(\d{2})(?=\s)"#) {
            hour = Int(g[1])
            minute = Int(g[2]) ?? 0
        }

        if let hour {
            var day = base ?? Date()
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: day)
            comps.hour = hour
            comps.minute = minute
            if let built = Calendar.current.date(from: comps) {
                day = built
                // A bare time that already passed means tomorrow, not this morning.
                if base == nil && built < Date() {
                    day = Calendar.current.date(byAdding: .day, value: 1, to: built) ?? built
                }
                out.startAt = DateParse.localString(day)
                out.due = DateParse.dayString(day)
            }
        } else if let base {
            out.due = DateParse.dayString(base)
        }

        out.text = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return out
    }
}
