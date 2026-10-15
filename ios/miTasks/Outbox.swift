import Foundation

/// A write the Mac hasn't confirmed yet. The phone keeps these on disk and
/// replays them in order whenever the Mac is reachable, so nothing typed on a
/// plane or with the Mac asleep is lost.
///
/// Every change is safe to send twice — creates carry their own id and ticks
/// say "done" rather than "flip" — because a request can land on the Mac and
/// still lose its response on the way back.
struct PendingOp: Codable, Identifiable {
    var id = UUID()
    var change: Change
}

/// The fields a task edit sends. nil means "clear it", matching the server.
struct TaskEdit: Codable, Hashable {
    var text: String?
    var notes: String?
    var priority: String?
    var label: String?
    var due: String?
    var startAt: String?
    var repeatRule: String?
}

enum Change: Codable, Hashable {
    case addTask(TaskItem)
    case setDone(id: String, done: Bool, at: Double)
    case editTask(id: String, edit: TaskEdit)
    case deleteTask(id: String)
    case clearDone
    case addNote(NoteItem)
    case editNote(id: String, title: String, body: String, at: Double)
    case deleteNote(id: String)

    /// The task or note this change is about, so repeated edits can collapse.
    var subject: String? {
        switch self {
        case .editTask(let id, _), .editNote(let id, _, _, _): return id
        default: return nil
        }
    }

    var request: (path: String, method: String, body: [String: Any]?) {
        func orNull(_ v: String?) -> Any { v ?? NSNull() }
        switch self {
        case .addTask(let t):
            var body: [String: Any] = ["id": t.id, "text": t.text, "createdAt": t.createdAt ?? 0]
            if let v = t.label { body["label"] = v }
            if let v = t.priority { body["priority"] = v }
            if let v = t.due { body["due"] = v }
            if let v = t.startAt { body["startAt"] = v }
            if let v = t.repeatRule { body["repeat"] = v }
            return ("/api/tasks", "POST", body)
        case .setDone(let id, let done, let at):
            return ("/api/tasks/\(id)/toggle", "POST", ["done": done, "at": at])
        case .editTask(let id, let e):
            return ("/api/tasks/\(id)", "PATCH", [
                "text": orNull(e.text), "notes": orNull(e.notes), "priority": orNull(e.priority),
                "label": orNull(e.label), "due": orNull(e.due), "startAt": orNull(e.startAt),
                "repeat": orNull(e.repeatRule),
            ])
        case .deleteTask(let id):
            return ("/api/tasks/\(id)", "DELETE", nil)
        case .clearDone:
            return ("/api/clear-done", "POST", nil)
        case .addNote(let n):
            var body: [String: Any] = [
                "id": n.id, "title": n.title ?? "", "body": n.body ?? "", "createdAt": n.createdAt ?? 0,
            ]
            if let v = n.label { body["label"] = v }
            return ("/api/notes", "POST", body)
        case .editNote(let id, let title, let body, _):
            return ("/api/notes/\(id)", "PATCH", ["title": title, "body": body])
        case .deleteNote(let id):
            return ("/api/notes/\(id)", "DELETE", nil)
        }
    }

    /// Replays the change on a copy of the Mac's state. Idempotent, because a
    /// broadcast can arrive with the change already in it before the request
    /// that caused it has answered.
    func apply(to s: inout AppState) {
        switch self {
        case .addTask(let t):
            if !s.tasks.contains(where: { $0.id == t.id }) { s.tasks.insert(t, at: 0) }
        case .setDone(let id, let done, let at):
            if let i = s.tasks.firstIndex(where: { $0.id == id }), s.tasks[i].done != done {
                s.tasks[i].done = done
                s.tasks[i].doneAt = done ? at : nil
            }
        case .editTask(let id, let e):
            guard let i = s.tasks.firstIndex(where: { $0.id == id }) else { return }
            if let text = e.text, !text.trimmingCharacters(in: .whitespaces).isEmpty { s.tasks[i].text = text }
            s.tasks[i].notes = e.notes ?? ""
            s.tasks[i].priority = e.priority
            s.tasks[i].label = e.label
            s.tasks[i].due = e.due
            s.tasks[i].startAt = e.startAt
            s.tasks[i].repeatRule = e.repeatRule
        case .deleteTask(let id):
            s.tasks.removeAll { $0.id == id }
        case .clearDone:
            s.tasks.removeAll { $0.done }
        case .addNote(let n):
            if !s.notes.contains(where: { $0.id == n.id }) { s.notes.append(n) }
        case .editNote(let id, let title, let body, let at):
            if let i = s.notes.firstIndex(where: { $0.id == id }) {
                s.notes[i].title = title
                s.notes[i].body = body
                s.notes[i].updatedAt = at
            }
        case .deleteNote(let id):
            s.notes.removeAll { $0.id == id }
        }
    }
}

/// Same shape as the widget's ids (base-36 time plus noise), so the server's
/// routes accept them unchanged.
func makeId() -> String {
    let time = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
    let noise = (0..<5).map { _ in String(Int.random(in: 0..<36), radix: 36) }.joined()
    return time + noise
}

var nowMs: Double { Date().timeIntervalSince1970 * 1000 }
