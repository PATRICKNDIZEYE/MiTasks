import Foundation
import SwiftUI

/// Where the widget lives on the network, plus the shared secret from its
/// pairing URL.
struct ServerConfig: Codable, Equatable {
    var host: String   // e.g. "10.110.0.127:43917"
    var key: String

    var baseURL: URL? { URL(string: "http://\(host)") }

    func url(_ path: String, query: [String: String] = [:]) -> URL? {
        guard var comps = URLComponents(string: "http://\(host)\(path)") else { return nil }
        var items = [URLQueryItem(name: "key", value: key)]
        items += query.map { URLQueryItem(name: $0.key, value: $0.value) }
        comps.queryItems = items
        return comps.url
    }

    /// Accepts the pairing URL straight from the widget or the QR code,
    /// e.g. http://10.110.0.127:43917/?key=abc123
    static func parse(_ raw: String) -> ServerConfig? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let comps = URLComponents(string: withScheme),
              let host = comps.host,
              let key = comps.queryItems?.first(where: { $0.name == "key" })?.value,
              !key.isEmpty
        else { return nil }
        let port = comps.port ?? 43917
        return ServerConfig(host: "\(host):\(port)", key: key)
    }
}

@MainActor
final class Store: ObservableObject {
    @Published var state = AppState.empty
    @Published var connected = false
    @Published var config: ServerConfig?
    @Published var lastError: String?

    /// Ticks once a second purely so the focus and lock-in countdowns move
    /// between server broadcasts.
    @Published var tick = Date()

    private var streamTask: Task<Void, Never>?
    private var tickTimer: Timer?
    private let defaults = UserDefaults.standard

    init() {
        if let data = defaults.data(forKey: "serverConfig"),
           let cfg = try? JSONDecoder().decode(ServerConfig.self, from: data) {
            config = cfg
        }
        // Last good snapshot, so a cold launch paints instantly and an
        // unreachable Mac still shows this morning's list.
        if let data = defaults.data(forKey: "cachedState"),
           let cached = try? JSONDecoder().decode(AppState.self, from: data) {
            state = cached
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick = Date() }
        }
    }

    // MARK: - Pairing

    func pair(with raw: String) -> Bool {
        guard let cfg = ServerConfig.parse(raw) else {
            lastError = "That doesn't look like a miTasks link."
            return false
        }
        config = cfg
        if let data = try? JSONEncoder().encode(cfg) {
            defaults.set(data, forKey: "serverConfig")
        }
        lastError = nil
        start()
        return true
    }

    func unpair() {
        streamTask?.cancel()
        streamTask = nil
        config = nil
        connected = false
        defaults.removeObject(forKey: "serverConfig")
    }

    // MARK: - Lifecycle

    func start() {
        guard config != nil else { return }
        Task { await refresh() }
        listen()
    }

    private func listen() {
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            // Reconnects for as long as the view is alive; the Mac sleeping is
            // an expected, recoverable state rather than an error.
            while !Task.isCancelled {
                await self?.streamOnce()
                if Task.isCancelled { break }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func streamOnce() async {
        guard let url = config?.url("/api/events") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = .infinity
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                connected = false
                return
            }
            connected = true
            for try await line in bytes.lines {
                guard line.hasPrefix("data: ") else { continue }
                let payload = String(line.dropFirst(6))
                if let data = payload.data(using: .utf8) { adopt(data) }
            }
            connected = false
        } catch {
            connected = false
        }
    }

    func refresh() async {
        guard let url = config?.url("/api/state") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                connected = false
                return
            }
            adopt(data)
            connected = true
        } catch {
            connected = false
        }
    }

    private func adopt(_ data: Data) {
        guard let next = try? JSONDecoder().decode(AppState.self, from: data) else { return }
        state = next
        defaults.set(data, forKey: "cachedState")
    }

    // MARK: - Writes
    //
    // Every write is optimistic: mutate locally so the tap lands instantly,
    // then let the server's broadcast reconcile. A failure re-reads state.

    private func send(_ path: String, method: String, body: [String: Any]? = nil) {
        guard let url = config?.url(path) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: req)
                if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                    await refresh()
                }
            } catch {
                await refresh()
            }
        }
    }

    func toggle(_ task: TaskItem) {
        if let i = state.tasks.firstIndex(where: { $0.id == task.id }) {
            state.tasks[i].done.toggle()
            state.tasks[i].doneAt = state.tasks[i].done ? Date().timeIntervalSince1970 * 1000 : nil
        }
        send("/api/tasks/\(task.id)/toggle", method: "POST")
    }

    func add(_ draft: QuickAdd) {
        var body: [String: Any] = ["text": draft.text]
        if let v = draft.label { body["label"] = v }
        if let v = draft.priority { body["priority"] = v }
        if let v = draft.due { body["due"] = v }
        if let v = draft.startAt { body["startAt"] = v }
        if let v = draft.repeatRule { body["repeat"] = v }

        let optimistic = TaskItem(
            id: "tmp-\(UUID().uuidString)", text: draft.text, label: draft.label,
            done: false, createdAt: Date().timeIntervalSince1970 * 1000, doneAt: nil,
            notes: "", priority: draft.priority, due: draft.due,
            startAt: draft.startAt, repeatRule: draft.repeatRule, focusedMs: 0
        )
        state.tasks.insert(optimistic, at: 0)
        send("/api/tasks", method: "POST", body: body)
    }

    func update(_ task: TaskItem, changes: [String: Any]) {
        if let i = state.tasks.firstIndex(where: { $0.id == task.id }) {
            var t = state.tasks[i]
            if let v = changes["text"] as? String { t.text = v }
            if let v = changes["notes"] as? String { t.notes = v }
            t.priority = changes["priority"] as? String
            t.label = changes["label"] as? String
            t.due = changes["due"] as? String
            t.startAt = changes["startAt"] as? String
            t.repeatRule = changes["repeat"] as? String
            state.tasks[i] = t
        }
        // NSNull marks "clear this field" — JSONSerialization turns it into null,
        // which the server reads as an explicit reset rather than "unchanged".
        var body: [String: Any] = [:]
        for key in ["text", "notes", "priority", "label", "due", "startAt", "repeat"] {
            body[key] = changes[key] ?? NSNull()
        }
        send("/api/tasks/\(task.id)", method: "PATCH", body: body)
    }

    func delete(_ task: TaskItem) {
        state.tasks.removeAll { $0.id == task.id }
        send("/api/tasks/\(task.id)", method: "DELETE")
    }

    func clearDone() {
        state.tasks.removeAll { $0.done }
        send("/api/clear-done", method: "POST")
    }

    func startFocus(_ task: TaskItem) {
        let minutes = state.focusMinutes
        state.focus = FocusSession(
            taskId: task.id,
            startedAt: Date().timeIntervalSince1970 * 1000,
            endAt: Date().addingTimeInterval(Double(minutes) * 60).timeIntervalSince1970 * 1000,
            minutes: minutes
        )
        send("/api/focus", method: "POST", body: ["taskId": task.id])
    }

    func stopFocus() {
        state.focus = nil
        send("/api/focus", method: "DELETE")
    }

    func startLockin(minutes: Int, extend: Bool = false) {
        let base = extend && state.lockin.active ? state.lockin.remaining : 0
        state.lockin = LockinStatus(
            active: true,
            startedAt: Date().timeIntervalSince1970 * 1000,
            endAt: Date().addingTimeInterval(base + Double(minutes) * 60).timeIntervalSince1970 * 1000,
            minutes: minutes
        )
        send("/api/lockin", method: "POST", body: ["minutes": minutes, "extend": extend])
    }

    func stopLockin() {
        state.lockin = .off
        send("/api/lockin", method: "DELETE")
    }

    func saveNote(_ note: NoteItem, title: String, body: String) {
        if let i = state.notes.firstIndex(where: { $0.id == note.id }) {
            state.notes[i].title = title
            state.notes[i].body = body
            state.notes[i].updatedAt = Date().timeIntervalSince1970 * 1000
        }
        send("/api/notes/\(note.id)", method: "PATCH", body: ["title": title, "body": body])
    }

    func deleteNote(_ note: NoteItem) {
        state.notes.removeAll { $0.id == note.id }
        send("/api/notes/\(note.id)", method: "DELETE")
    }

    /// Creating a note needs the server's id back before the editor can open,
    /// so this one write is not optimistic.
    func createNote(label: String?) async -> NoteItem? {
        guard let url = config?.url("/api/notes") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["title": "Untitled"]
        if let label { body["label"] = label }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String
        else { return nil }

        await refresh()
        return state.notes.first { $0.id == id }
    }

    // MARK: - Voice

    struct Verdict {
        var ok = false
        var kind = "task"
        var label: String?
        var priority: String?
        var error: String?
    }

    /// Asks the Mac to classify a transcript. The Jev key lives only on the
    /// Mac, so the phone never holds it.
    func classify(_ transcript: String) async -> Verdict {
        guard let url = config?.url("/api/classify") else {
            return Verdict(error: "not paired")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["transcript": transcript])

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return Verdict(error: "your Mac didn't answer") }

        guard json["ok"] as? Bool == true else {
            return Verdict(error: json["error"] as? String ?? "not classified")
        }
        return Verdict(
            ok: true,
            kind: json["kind"] as? String ?? "task",
            label: json["label"] as? String,
            priority: json["priority"] as? String
        )
    }

    /// Saves a spoken sentence. Whatever the classifier says, the words
    /// themselves are never lost — a failed call just means an unlabelled task.
    func saveSpoken(_ spoken: String, verdict: Verdict) {
        let parsed = QuickAdd.parse(spoken, labels: state.labels, activeLabel: nil)
        let text = parsed.text.isEmpty ? spoken : parsed.text

        if verdict.ok && verdict.kind == "note" {
            Task {
                if let note = await createNote(label: verdict.label) {
                    saveNote(note, title: String(text.prefix(120)), body: "")
                }
            }
            return
        }

        var draft = parsed
        draft.text = text
        if verdict.ok {
            if let l = verdict.label { draft.label = l }
            if let p = verdict.priority { draft.priority = p }
        }
        add(draft)
    }

    // MARK: - Derived

    var todaysEvents: [CalEvent] {
        let start = Date().startOfDay, end = Date().endOfDay
        return state.events
            .filter { ev in
                guard let s = ev.startDate, let e = ev.endDate else { return false }
                return e > start && s < end
            }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }

    /// Merges overlapping meetings before measuring, so a double-booked hour
    /// counts once rather than twice.
    var freeGaps: [(Date, Date)] {
        let events = todaysEvents
        guard !events.isEmpty else { return [] }

        let now = Date(), end = Date().endOfDay
        let busy = events
            .filter { $0.allDay != true }
            .compactMap { ev -> (Date, Date)? in
                guard let s = ev.startDate, let e = ev.endDate, e > now else { return nil }
                return (max(s, now), e)
            }
            .sorted { $0.0 < $1.0 }

        var merged: [(Date, Date)] = []
        for iv in busy {
            if let last = merged.last, iv.0 <= last.1 {
                merged[merged.count - 1].1 = max(last.1, iv.1)
            } else {
                merged.append(iv)
            }
        }

        var gaps: [(Date, Date)] = []
        var cursor = now
        for (s, e) in merged {
            if s.timeIntervalSince(cursor) >= 1800 { gaps.append((cursor, s)) }
            cursor = max(cursor, e)
        }
        if end.timeIntervalSince(cursor) >= 1800 { gaps.append((cursor, end)) }
        return gaps
    }

    var streakDays: Int {
        let days = Set(state.tasks.compactMap { $0.doneDate.map(DateParse.dayString) })
        var cursor = Date()
        // An empty today shouldn't read as a broken streak until the day is over.
        if !days.contains(DateParse.dayString(cursor)) {
            cursor = Calendar.current.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        var n = 0
        while days.contains(DateParse.dayString(cursor)) {
            n += 1
            cursor = Calendar.current.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return n
    }

    var focusedTodayMinutes: Int {
        let today = DateParse.dayString(Date())
        let ms = state.focusLog.filter { $0.date == today }.reduce(0.0) { $0 + ($1.ms ?? 0) }
        return Int(ms / 60000)
    }
}
