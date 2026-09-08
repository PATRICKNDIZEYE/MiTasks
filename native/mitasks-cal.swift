// mitasks-cal — a thin EventKit bridge for miTasks.
//
// Reads and writes the calendars macOS Calendar.app already has configured, so
// no account ever needs re-linking. Every subcommand prints one JSON object (or
// array) on stdout; failures print {"error": "..."} and exit non-zero.
//
//   mitasks-cal auth                          current permission, never prompts
//   mitasks-cal request                       triggers the system prompt
//   mitasks-cal calendars                     every calendar, grouped by account
//   mitasks-cal events --from ISO --to ISO [--cal id,id]
//   mitasks-cal create  <<< '{"title":…}'     reads the event body from stdin
//   mitasks-cal update  --id ID <<< '{…}'
//   mitasks-cal delete  --id ID

import EventKit
import Foundation

let store = EKEventStore()

// MARK: - Output

func emit(_ value: Any) -> Never {
  let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
  FileHandle.standardOutput.write(data)
  FileHandle.standardOutput.write("\n".data(using: .utf8)!)
  exit(0)
}

func fail(_ message: String) -> Never {
  let data = try! JSONSerialization.data(withJSONObject: ["error": message])
  FileHandle.standardOutput.write(data)
  FileHandle.standardOutput.write("\n".data(using: .utf8)!)
  exit(1)
}

// MARK: - Dates

let iso: ISO8601DateFormatter = {
  let f = ISO8601DateFormatter()
  f.formatOptions = [.withInternetDateTime]
  return f
}()

// Accepts both "2026-09-07T14:30:00+02:00" and a bare "2026-09-07T14:30".
func parseDate(_ raw: String) -> Date? {
  if let d = iso.date(from: raw) { return d }
  let loose = DateFormatter()
  loose.locale = Locale(identifier: "en_US_POSIX")
  loose.timeZone = TimeZone.current
  for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
    loose.dateFormat = format
    if let d = loose.date(from: raw) { return d }
  }
  return nil
}

func str(_ date: Date) -> String { iso.string(from: date) }

// MARK: - Permission

func statusName(_ s: EKAuthorizationStatus) -> String {
  switch s {
  case .notDetermined: return "notDetermined"
  case .restricted:    return "restricted"
  case .denied:        return "denied"
  case .fullAccess:    return "fullAccess"
  case .writeOnly:     return "writeOnly"
  @unknown default:    return "unknown"
  }
}

func currentStatus() -> EKAuthorizationStatus {
  EKEventStore.authorizationStatus(for: .event)
}

/// Waits for the user to answer the system prompt.
///
/// This has to pump the run loop rather than block on a semaphore. TCC delivers
/// both the prompt and its reply over XPC on the main queue, so parking the main
/// thread means the dialog never appears and the completion never fires — the
/// call just sits there until it times out.
func requestAccess() -> (Bool, String?) {
  var granted = false
  var failure: String?
  var finished = false

  store.requestFullAccessToEvents { ok, error in
    granted = ok
    failure = error?.localizedDescription
    finished = true
  }

  let deadline = Date().addingTimeInterval(90)
  while !finished && Date() < deadline {
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
  }

  if !finished { return (false, "timed out waiting for the permission prompt") }
  return (granted, failure)
}

/// Every read/write path needs full access; bail out with a stable shape so the
/// app can tell "not allowed yet" apart from "something broke".
func requireAccess() {
  let s = currentStatus()
  guard s == .fullAccess else {
    let payload: [String: Any] = ["error": "not authorized", "status": statusName(s)]
    let data = try! JSONSerialization.data(withJSONObject: payload)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    exit(2)
  }
}

// MARK: - Serialization

func colorHex(_ calendar: EKCalendar) -> String? {
  guard let cg = calendar.cgColor,
        let converted = cg.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     intent: .defaultIntent, options: nil),
        let parts = converted.components, parts.count >= 3 else { return nil }
  let byte = { (v: CGFloat) in Int((max(0, min(1, v)) * 255).rounded()) }
  return String(format: "#%02x%02x%02x", byte(parts[0]), byte(parts[1]), byte(parts[2]))
}

func encode(_ calendar: EKCalendar) -> [String: Any] {
  var out: [String: Any] = [
    "id": calendar.calendarIdentifier,
    "title": calendar.title,
    "allowsModify": calendar.allowsContentModifications,
    "immutable": calendar.isImmutable,
    "subscribed": calendar.isSubscribed,
  ]
  out["account"] = calendar.source?.title ?? "Local"
  out["accountType"] = calendar.source.map { "\($0.sourceType.rawValue)" } ?? ""
  if let hex = colorHex(calendar) { out["color"] = hex }
  return out
}

func encode(_ event: EKEvent) -> [String: Any] {
  var out: [String: Any] = [
    "id": event.eventIdentifier ?? "",
    "title": event.title ?? "(no title)",
    "allDay": event.isAllDay,
    "calendarId": event.calendar?.calendarIdentifier ?? "",
    "calendar": event.calendar?.title ?? "",
    "recurring": event.hasRecurrenceRules,
  ]
  if let start = event.startDate { out["start"] = str(start) }
  if let end = event.endDate { out["end"] = str(end) }
  if let location = event.location, !location.isEmpty { out["location"] = location }
  if let notes = event.notes, !notes.isEmpty { out["notes"] = notes }
  if let url = event.url { out["url"] = url.absoluteString }
  if let hex = event.calendar.flatMap(colorHex) { out["color"] = hex }
  if let organizer = event.organizer?.name { out["organizer"] = organizer }

  switch event.status {
  case .confirmed: out["status"] = "confirmed"
  case .tentative: out["status"] = "tentative"
  case .canceled:  out["status"] = "canceled"
  default:         out["status"] = "none"
  }

  // Only the participant names — the app never needs addresses.
  if let attendees = event.attendees, !attendees.isEmpty {
    out["attendees"] = attendees.compactMap { $0.name }
    out["attendeeCount"] = attendees.count
  }
  return out
}

// MARK: - Arguments

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
  fail("usage: mitasks-cal <auth|request|calendars|events|create|update|delete>")
}
args = Array(args.dropFirst())

func flag(_ name: String) -> String? {
  guard let i = args.firstIndex(of: "--\(name)"), i + 1 < args.count else { return nil }
  return args[i + 1]
}

func stdinJson() -> [String: Any] {
  let data = FileHandle.standardInput.readDataToEndOfFile()
  guard !data.isEmpty,
        let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    fail("expected a JSON object on stdin")
  }
  return parsed
}

/// Applies a JSON body onto an event. Shared by create and update so the two
/// paths can never drift apart.
func apply(_ body: [String: Any], to event: EKEvent) {
  if let title = body["title"] as? String { event.title = title }
  if let notes = body["notes"] as? String { event.notes = notes }
  if let location = body["location"] as? String { event.location = location }
  if let allDay = body["allDay"] as? Bool { event.isAllDay = allDay }
  if let raw = body["url"] as? String, let url = URL(string: raw) { event.url = url }

  if let raw = body["start"] as? String {
    guard let d = parseDate(raw) else { fail("bad start date: \(raw)") }
    event.startDate = d
  }
  if let raw = body["end"] as? String {
    guard let d = parseDate(raw) else { fail("bad end date: \(raw)") }
    event.endDate = d
  }
  // A duration is friendlier than an end date when the caller only knows length.
  if event.endDate == nil, let minutes = body["minutes"] as? Int, let start = event.startDate {
    event.endDate = start.addingTimeInterval(TimeInterval(minutes * 60))
  }

  if let minutesBefore = body["alarmMinutesBefore"] as? Int {
    event.alarms = [EKAlarm(relativeOffset: TimeInterval(-minutesBefore * 60))]
  }
}

// MARK: - Commands

switch command {

case "auth":
  emit(["status": statusName(currentStatus())])

case "request":
  // Already answered? Report without re-prompting.
  let existing = currentStatus()
  if existing == .fullAccess { emit(["status": "fullAccess", "granted": true]) }
  let (granted, error) = requestAccess()
  var payload: [String: Any] = ["granted": granted, "status": statusName(currentStatus())]
  if let error { payload["error"] = error }
  emit(payload)

case "calendars":
  requireAccess()
  let calendars = store.calendars(for: .event)
    .sorted { ($0.source?.title ?? "", $0.title) < ($1.source?.title ?? "", $1.title) }
  emit(calendars.map(encode))

case "events":
  requireAccess()
  guard let fromRaw = flag("from"), let from = parseDate(fromRaw) else { fail("--from is required (ISO8601)") }
  guard let toRaw = flag("to"), let to = parseDate(toRaw) else { fail("--to is required (ISO8601)") }

  // No --cal means every calendar; an explicit list narrows it.
  var calendars: [EKCalendar]? = nil
  if let raw = flag("cal"), !raw.isEmpty {
    let wanted = Set(raw.split(separator: ",").map(String.init))
    calendars = store.calendars(for: .event).filter { wanted.contains($0.calendarIdentifier) }
    if calendars?.isEmpty == true { emit([]) }
  }

  let predicate = store.predicateForEvents(withStart: from, end: to, calendars: calendars)
  let events = store.events(matching: predicate)
    .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
  emit(events.map(encode))

case "create":
  requireAccess()
  let body = stdinJson()
  let event = EKEvent(eventStore: store)

  // Pick the requested calendar, else the user's default, and refuse read-only ones.
  if let wanted = body["calendarId"] as? String, !wanted.isEmpty {
    guard let match = store.calendars(for: .event).first(where: { $0.calendarIdentifier == wanted })
    else { fail("no calendar with id \(wanted)") }
    event.calendar = match
  } else {
    guard let fallback = store.defaultCalendarForNewEvents else { fail("no default calendar available") }
    event.calendar = fallback
  }
  guard event.calendar?.allowsContentModifications == true else {
    fail("calendar \"\(event.calendar?.title ?? "?")\" is read-only")
  }

  apply(body, to: event)
  guard event.title?.isEmpty == false else { fail("title is required") }
  guard event.startDate != nil else { fail("start is required") }
  if event.endDate == nil { event.endDate = event.startDate!.addingTimeInterval(3600) }

  do {
    try store.save(event, span: .thisEvent, commit: true)
    emit(encode(event))
  } catch {
    fail("could not save: \(error.localizedDescription)")
  }

case "update":
  requireAccess()
  guard let id = flag("id") else { fail("--id is required") }
  guard let event = store.event(withIdentifier: id) else { fail("no event with id \(id)") }
  guard event.calendar?.allowsContentModifications == true else {
    fail("calendar \"\(event.calendar?.title ?? "?")\" is read-only")
  }
  apply(stdinJson(), to: event)
  do {
    // .futureEvents would rewrite the whole series; miTasks only ever edits one.
    try store.save(event, span: .thisEvent, commit: true)
    emit(encode(event))
  } catch {
    fail("could not save: \(error.localizedDescription)")
  }

case "delete":
  requireAccess()
  guard let id = flag("id") else { fail("--id is required") }
  guard let event = store.event(withIdentifier: id) else { fail("no event with id \(id)") }
  guard event.calendar?.allowsContentModifications == true else {
    fail("calendar \"\(event.calendar?.title ?? "?")\" is read-only")
  }
  do {
    try store.remove(event, span: .thisEvent, commit: true)
    emit(["ok": true, "id": id])
  } catch {
    fail("could not delete: \(error.localizedDescription)")
  }

default:
  fail("unknown command \"\(command)\"")
}
