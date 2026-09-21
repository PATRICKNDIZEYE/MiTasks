import Foundation

/// Mirrors the JSON shape the widget's sync server publishes. Everything
/// optional decodes leniently — the Mac is the source of truth and may add
/// fields ahead of the app.

struct TaskItem: Codable, Identifiable, Hashable {
    var id: String
    var text: String
    var label: String?
    var done: Bool
    var createdAt: Double?
    var doneAt: Double?
    var notes: String?
    var priority: String?
    var due: String?
    var startAt: String?
    var repeatRule: String?
    var focusedMs: Double?

    enum CodingKeys: String, CodingKey {
        case id, text, label, done, createdAt, doneAt, notes, priority, due, startAt, focusedMs
        case repeatRule = "repeat"
    }

    var createdDate: Date? { createdAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
    var doneDate: Date? { doneAt.map { Date(timeIntervalSince1970: $0 / 1000) } }

    var ageDays: Int {
        guard let created = createdDate else { return 0 }
        return Calendar.current.dateComponents([.day], from: created, to: Date()).day ?? 0
    }

    /// Aging only counts when nothing louder already flags the task — an
    /// overdue date beats "it has been sitting here" as a signal.
    var isAging: Bool {
        !done && due == nil && startAt == nil && ageDays >= 3
    }

    var dueDate: Date? { due.flatMap(DateParse.day) }
    var startDate: Date? { startAt.flatMap(DateParse.local) }
}

struct LabelItem: Codable, Identifiable, Hashable {
    var name: String
    var color: String?
    var id: String { name }
}

struct NoteItem: Codable, Identifiable, Hashable {
    var id: String
    var label: String?
    var title: String?
    var body: String?
    var createdAt: Double?
    var updatedAt: Double?

    var updatedDate: Date? { updatedAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
}

struct CalEvent: Codable, Identifiable, Hashable {
    var id: String
    var title: String?
    var start: String?
    var end: String?
    var allDay: Bool?
    var location: String?
    var attendees: [String]?
    var color: String?
    var calendar: String?

    var startDate: Date? { start.flatMap(DateParse.iso) }
    var endDate: Date? { end.flatMap(DateParse.iso) }

    var isNow: Bool {
        guard let s = startDate, let e = endDate else { return false }
        let now = Date()
        return s <= now && e > now
    }
}

struct FocusSession: Codable, Hashable {
    var taskId: String?
    var startedAt: Double?
    var endAt: Double?
    var minutes: Int?

    var endDate: Date? { endAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
    var remaining: TimeInterval { max(0, (endDate ?? Date()).timeIntervalSinceNow) }
}

struct LockinStatus: Codable, Hashable {
    var active: Bool
    var startedAt: Double?
    var endAt: Double?
    var minutes: Int?

    var endDate: Date? { endAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
    var remaining: TimeInterval { max(0, (endDate ?? Date()).timeIntervalSinceNow) }

    static let off = LockinStatus(active: false)
}

struct FocusLogEntry: Codable, Hashable {
    var date: String?
    var taskId: String?
    var label: String?
    var ms: Double?
}

struct AppState: Codable {
    var tasks: [TaskItem] = []
    var labels: [LabelItem] = []
    var notes: [NoteItem] = []
    var focus: FocusSession?
    var events: [CalEvent] = []
    var lockin: LockinStatus = .off
    var focusMinutes: Int = 25
    var focusLog: [FocusLogEntry] = []

    static let empty = AppState()

    func label(named name: String?) -> LabelItem? {
        guard let name else { return nil }
        return labels.first { $0.name == name }
    }
}

/// The three date shapes the server speaks: ISO8601 for calendar events,
/// "yyyy-MM-dd" for due dates, and a local "yyyy-MM-dd'T'HH:mm" for start times.
enum DateParse {
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let localFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func iso(_ s: String) -> Date? {
        isoFractional.date(from: s) ?? isoPlain.date(from: s)
    }

    static func day(_ s: String) -> Date? { dayFmt.date(from: s) }
    static func local(_ s: String) -> Date? { localFmt.date(from: s) }

    static func dayString(_ d: Date) -> String { dayFmt.string(from: d) }
    static func localString(_ d: Date) -> String { localFmt.string(from: d) }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
    var endOfDay: Date {
        Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay) ?? self
    }

    /// "3:40pm", matching the widget's compact clock labels.
    var clockLabel: String {
        let f = DateFormatter()
        f.dateFormat = "h:mma"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f.string(from: self)
    }
}

func formatCountdown(_ interval: TimeInterval) -> String {
    let total = max(0, Int(interval.rounded()))
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0
        ? String(format: "%d:%02d:%02d", h, m, s)
        : String(format: "%d:%02d", m, s)
}
