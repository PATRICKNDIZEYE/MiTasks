import Foundation
import WidgetKit

/// What the app and its widgets share through the App Group: the list the
/// app is showing (Mac state plus queued edits), where the Mac is, and any
/// ticks made on a widget that haven't reached the Mac yet.
enum WidgetBridge {
    static let group = "group.rw.azultech.mitasks"
    static let kind = "rw.azultech.mitasks"

    private enum Key {
        static let state = "w.state"
        static let config = "w.config"
        static let pending = "w.pending"
        static let ticks = "w.ticks"
        static let route = "w.route"
    }

    private static var defaults: UserDefaults? { UserDefaults(suiteName: group) }

    // MARK: State

    static func loadState() -> AppState? {
        guard let data = defaults?.data(forKey: Key.state) else { return nil }
        return try? JSONDecoder().decode(AppState.self, from: data)
    }

    /// Stores what the app is showing and, only when it actually changed,
    /// asks WidgetKit to redraw — reloads come out of a daily budget.
    static func publish(_ state: AppState, pending: Int) {
        guard let d = defaults, let data = try? JSONEncoder().encode(state) else { return }
        let changed = d.data(forKey: Key.state) != data || d.integer(forKey: Key.pending) != pending
        guard changed else { return }
        d.set(data, forKey: Key.state)
        d.set(pending, forKey: Key.pending)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Edits the app is still holding for the Mac. While there are any, the
    /// app's copy is newer than the Mac's.
    static var pendingCount: Int { defaults?.integer(forKey: Key.pending) ?? 0 }

    // MARK: Config

    static func loadConfig() -> ServerConfig? {
        guard let data = defaults?.data(forKey: Key.config) else { return nil }
        return try? JSONDecoder().decode(ServerConfig.self, from: data)
    }

    static func saveConfig(_ config: ServerConfig?) {
        guard let d = defaults else { return }
        if let config, let data = try? JSONEncoder().encode(config) {
            d.set(data, forKey: Key.config)
        } else {
            d.removeObject(forKey: Key.config)
            d.removeObject(forKey: Key.state)
            d.removeObject(forKey: Key.ticks)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Widget ticks

    /// A task ticked on the Home Screen while the Mac was out of reach. The
    /// app folds these into its own queue the next time it runs.
    struct Tick: Codable, Hashable {
        var id: String
        var at: Double
    }

    static var ticks: [Tick] {
        guard let data = defaults?.data(forKey: Key.ticks) else { return [] }
        return (try? JSONDecoder().decode([Tick].self, from: data)) ?? []
    }

    static func addTick(_ tick: Tick) {
        var all = ticks.filter { $0.id != tick.id }
        all.append(tick)
        if let data = try? JSONEncoder().encode(all) { defaults?.set(data, forKey: Key.ticks) }
    }

    static func takeTicks() -> [Tick] {
        let all = ticks
        defaults?.removeObject(forKey: Key.ticks)
        return all
    }
}

// MARK: - Opening the app somewhere

extension WidgetBridge {
    /// A screen a control asked the app to open, picked up once it's running.
    static func setRoute(_ route: AppRoute) {
        defaults?.set(route.url.absoluteString, forKey: Key.route)
        NotificationCenter.default.post(name: .miTasksRoute, object: nil)
    }

    static func takeRoute() -> AppRoute? {
        guard let raw = defaults?.string(forKey: Key.route), let url = URL(string: raw) else { return nil }
        defaults?.removeObject(forKey: Key.route)
        return AppRoute(url: url)
    }
}

extension Notification.Name {
    static let miTasksRoute = Notification.Name("miTasksRoute")
}

// MARK: - What the widgets ask of the state

extension AppState {
    /// Open work in the app's own order: priority, then deadline, then newest.
    func ranked(label: String? = nil) -> [TaskItem] {
        tasks
            .filter { !$0.done && (label == nil || $0.label == label) }
            .sorted { a, b in
                let pa = TaskStatus.priorityRank(a), pb = TaskStatus.priorityRank(b)
                if pa != pb { return pa < pb }
                let da = TaskStatus.dueValue(a), db = TaskStatus.dueValue(b)
                if da != db { return da < db }
                return (a.createdAt ?? 0) > (b.createdAt ?? 0)
            }
    }

    var doneToday: Int {
        let start = Date().startOfDay
        return tasks.filter { $0.done && ($0.doneDate.map { $0 >= start } ?? false) }.count
    }

    /// Next meeting that hasn't finished, today only.
    var nextMeeting: CalEvent? {
        let now = Date(), end = now.endOfDay
        return events
            .filter { $0.allDay != true && ($0.endDate ?? .distantPast) > now && ($0.startDate ?? .distantFuture) < end }
            .min { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }
}

extension TaskItem {
    var isOverdue: Bool { !done && (dueDate.map { TaskStatus.dayDiff($0) < 0 } ?? false) }
    var isDueToday: Bool { !done && (dueDate.map { TaskStatus.dayDiff($0) == 0 } ?? false) }
}
