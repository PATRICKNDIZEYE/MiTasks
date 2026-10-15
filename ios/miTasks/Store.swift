import Foundation
import SwiftUI

@MainActor
final class Store: ObservableObject {
    /// What the screens show: the Mac's last word with queued edits on top.
    @Published private(set) var state = AppState.empty {
        didSet { LiveSessions.sync(state) }
    }
    /// A screen something outside the app asked for; the Today tab consumes it.
    @Published var route: AppRoute?
    @Published var connected = false
    @Published var config: ServerConfig?
    @Published var lastError: String?
    /// Edits made while the Mac was out of reach, oldest first.
    @Published private(set) var outbox: [PendingOp] = []

    /// Ticks once a second purely so the focus and lock-in countdowns move
    /// between server broadcasts.
    @Published var tick = Date()

    /// The last state the Mac actually sent.
    private var confirmed = AppState.empty
    private var streamTask: Task<Void, Never>?
    private var tickTimer: Timer?
    private var flushing = false
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
            confirmed = cached
        }
        if let data = defaults.data(forKey: "outbox"),
           let saved = try? JSONDecoder().decode([PendingOp].self, from: data) {
            outbox = saved
        }
        // Installs from before the widgets existed have never told them where the Mac is.
        if let config, WidgetBridge.loadConfig() == nil { WidgetBridge.saveConfig(config) }
        rebuild()
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
        // Queued edits belong to whichever Mac they were made against.
        if cfg.key != config?.key { setOutbox([]) }
        saveConfig(cfg)
        lastError = nil
        start()
        return true
    }

    func unpair() {
        streamTask?.cancel()
        streamTask = nil
        config = nil
        connected = false
        setOutbox([])
        defaults.removeObject(forKey: "serverConfig")
        WidgetBridge.saveConfig(nil)
    }

    private func saveConfig(_ cfg: ServerConfig) {
        config = cfg
        if let data = try? JSONEncoder().encode(cfg) {
            defaults.set(data, forKey: "serverConfig")
        }
        WidgetBridge.saveConfig(cfg)
    }

    // MARK: - Lifecycle

    func start() {
        guard config != nil else { return }
        absorbWidgetTicks()
        listen()
    }

    /// Coming back to the foreground: the stream is usually dead by now, so
    /// re-read and push anything that queued up meanwhile.
    func wake() async {
        absorbWidgetTicks()
        if await refresh() { await flush() }
    }

    /// Ticks made on a Home Screen widget while the Mac was out of reach join
    /// the queue like any other edit.
    private func absorbWidgetTicks() {
        for tick in WidgetBridge.takeTicks() {
            enqueue(.setDone(id: tick.id, done: true, at: tick.at))
        }
    }

    private func listen() {
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            // Reconnects for as long as the app is alive; the Mac sleeping is
            // an expected, recoverable state rather than an error.
            var backoff = 3.0
            while !Task.isCancelled {
                guard let self else { return }
                if await self.refresh() {
                    backoff = 3
                    await self.learnEndpoints()
                    await self.flush()
                    await self.streamOnce()
                } else {
                    backoff = min(backoff * 2, 30)
                }
                if Task.isCancelled { break }
                try? await Task.sleep(for: .seconds(backoff))
            }
        }
    }

    private func streamOnce() async {
        guard let url = config?.url("/api/events") else { return }
        var req = URLRequest(url: url)
        // The server pings every 25s, so a minute of silence means the link
        // is dead even if the socket hasn't noticed.
        req.timeoutInterval = 60
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

    /// Reads the full state from the first address that answers, and makes
    /// that address the one to use from now on.
    @discardableResult
    func refresh() async -> Bool {
        guard let cfg = config else { return false }
        for base in cfg.endpoints {
            guard let url = cfg.url("/api/state", base: base) else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 6
            guard let (data, response) = try? await URLSession.shared.data(for: req),
                  (response as? HTTPURLResponse)?.statusCode == 200
            else { continue }
            if base != config?.endpoints.first, var moved = config {
                moved.endpoints.removeAll { $0 == base }
                moved.endpoints.insert(base, at: 0)
                saveConfig(moved)
            }
            adopt(data)
            connected = true
            return true
        }
        connected = false
        return false
    }

    /// Asks the Mac for every address it has, so the phone can still find it
    /// after leaving home Wi-Fi without pairing again.
    private func learnEndpoints() async {
        guard let cfg = config, let url = cfg.url("/api/hosts"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hosts = json["hosts"] as? [String]
        else { return }
        var next = [cfg.endpoints[0]]
        for h in hosts where !next.contains(h) && URL(string: h) != nil { next.append(h) }
        if next != cfg.endpoints {
            var updated = cfg
            updated.endpoints = next
            saveConfig(updated)
        }
    }

    private func adopt(_ data: Data) {
        guard let next = try? JSONDecoder().decode(AppState.self, from: data) else { return }
        confirmed = next
        defaults.set(data, forKey: "cachedState")
        rebuild()
    }

    /// Recomputes what the screens show from the Mac's state plus the queue.
    private func rebuild() {
        var s = confirmed
        for op in outbox { op.change.apply(to: &s) }
        state = s
        WidgetBridge.publish(s, pending: outbox.count)
    }

    // MARK: - Outbox
    //
    // Task and note writes go through the queue: they show up instantly,
    // survive the app being killed, and reach the Mac whenever it's reachable.

    private func setOutbox(_ ops: [PendingOp]) {
        outbox = ops
        if let data = try? JSONEncoder().encode(ops) {
            defaults.set(data, forKey: "outbox")
        }
    }

    private func enqueue(_ change: Change) {
        var ops = outbox
        // Saving the same task or note twice only needs the last version. The
        // replacement gets a fresh id, so a copy already in flight is never
        // mistaken for it.
        if let subject = change.subject, let last = ops.last, last.change.subject == subject,
           sameKind(last.change, change) {
            ops[ops.count - 1] = PendingOp(change: change)
        } else {
            ops.append(PendingOp(change: change))
        }
        setOutbox(ops)
        rebuild()
        Task { await flush() }
    }

    private func sameKind(_ a: Change, _ b: Change) -> Bool {
        switch (a, b) {
        case (.editTask, .editTask), (.editNote, .editNote): return true
        default: return false
        }
    }

    private enum Delivery { case done, rejected, unreachable }

    /// Sends queued writes one at a time, in order, stopping at the first one
    /// the Mac can't be reached for.
    func flush() async {
        guard !flushing, config != nil, !outbox.isEmpty else { return }
        flushing = true
        defer { flushing = false }

        var sent = false
        while let op = outbox.first {
            let result = await deliver(op)
            if result == .unreachable { break }
            // Something newer may have replaced it while it was in flight.
            if outbox.first?.id == op.id { setOutbox(Array(outbox.dropFirst())) }
            if result == .rejected { rebuild() }
            sent = true
        }
        // Without a live stream nobody will tell us what the Mac made of it.
        if sent && !connected { await refresh() }
    }

    private func deliver(_ op: PendingOp) async -> Delivery {
        let (path, method, body) = op.change.request
        guard let url = config?.url(path) else { return .unreachable }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 10
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        guard let (_, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse
        else { return .unreachable }
        switch http.statusCode {
        case ..<400: return .done
        // A wrong key or a struggling server is worth retrying; a 404 means
        // the Mac deleted the thing first, and the Mac wins.
        case 403, 500...: return .unreachable
        default: return .rejected
        }
    }

    // MARK: - Writes

    func toggle(_ task: TaskItem) {
        let current = state.tasks.first { $0.id == task.id }?.done ?? task.done
        enqueue(.setDone(id: task.id, done: !current, at: nowMs))
    }

    func add(_ draft: QuickAdd) {
        enqueue(.addTask(TaskItem(
            id: makeId(), text: draft.text, label: draft.label,
            done: false, createdAt: nowMs, doneAt: nil,
            notes: "", priority: draft.priority, due: draft.due,
            startAt: draft.startAt, repeatRule: draft.repeatRule, focusedMs: 0
        )))
    }

    func update(_ task: TaskItem, changes: [String: Any]) {
        enqueue(.editTask(id: task.id, edit: TaskEdit(
            text: changes["text"] as? String,
            notes: changes["notes"] as? String,
            priority: changes["priority"] as? String,
            label: changes["label"] as? String,
            due: changes["due"] as? String,
            startAt: changes["startAt"] as? String,
            repeatRule: changes["repeat"] as? String
        )))
    }

    func delete(_ task: TaskItem) {
        enqueue(.deleteTask(id: task.id))
    }

    func clearDone() {
        enqueue(.clearDone)
    }

    func saveNote(_ note: NoteItem, title: String, body: String) {
        enqueue(.editNote(id: note.id, title: title, body: body, at: nowMs))
    }

    func deleteNote(_ note: NoteItem) {
        enqueue(.deleteNote(id: note.id))
    }

    /// The phone names the note itself, so the editor can open straight away
    /// even when the Mac is out of reach.
    func createNote(label: String?, title: String = "Untitled") -> NoteItem {
        let note = NoteItem(id: makeId(), label: label, title: title, body: "", createdAt: nowMs, updatedAt: nowMs)
        enqueue(.addNote(note))
        return note
    }

    // Focus and lock-in act on the Mac right now, so they aren't queued: a
    // lock-in replayed hours later would be wrong. If the Mac can't be
    // reached, the optimistic change is rolled back.

    private func sendLive(_ path: String, method: String, body: [String: Any]? = nil) {
        guard let url = config?.url(path) else { rebuild(); return }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 10
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        Task {
            let ok = (try? await URLSession.shared.data(for: req))
                .flatMap { ($0.1 as? HTTPURLResponse)?.statusCode }
                .map { $0 < 400 } ?? false
            if !ok {
                lastError = "Your Mac isn't reachable — focus and lock-in need it online."
                rebuild()
                await refresh()
            }
        }
    }

    func startFocus(_ task: TaskItem) {
        let minutes = state.focusMinutes
        state.focus = FocusSession(
            taskId: task.id,
            startedAt: nowMs,
            endAt: Date().addingTimeInterval(Double(minutes) * 60).timeIntervalSince1970 * 1000,
            minutes: minutes
        )
        sendLive("/api/focus", method: "POST", body: ["taskId": task.id])
    }

    func stopFocus() {
        state.focus = nil
        sendLive("/api/focus", method: "DELETE")
    }

    func startLockin(minutes: Int, extend: Bool = false) {
        let base = extend && state.lockin.active ? state.lockin.remaining : 0
        state.lockin = LockinStatus(
            active: true,
            startedAt: nowMs,
            endAt: Date().addingTimeInterval(base + Double(minutes) * 60).timeIntervalSince1970 * 1000,
            minutes: minutes
        )
        sendLive("/api/lockin", method: "POST", body: ["minutes": minutes, "extend": extend])
    }

    func stopLockin() {
        state.lockin = .off
        sendLive("/api/lockin", method: "DELETE")
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
        req.timeoutInterval = 20
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
    /// themselves are never lost — offline, or on a failed call, it simply
    /// becomes an unlabelled task.
    func saveSpoken(_ spoken: String, verdict: Verdict) {
        let parsed = QuickAdd.parse(spoken, labels: state.labels, activeLabel: nil)
        let text = parsed.text.isEmpty ? spoken : parsed.text

        if verdict.ok && verdict.kind == "note" {
            _ = createNote(label: verdict.label, title: String(text.prefix(120)))
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
