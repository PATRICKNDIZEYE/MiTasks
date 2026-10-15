import ActivityKit
import AppIntents
import Foundation

enum SessionKind: String, Codable, Hashable {
    case focus, lockin
}

/// The Live Activity for whatever is running on the Mac: a focus session, a
/// lock-in, or both. One activity carries both so they never stack up.
struct SessionAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var focusTitle: String?
        var focusStart: Date?
        var focusEnd: Date?
        var lockStart: Date?
        var lockEnd: Date?

        var hasFocus: Bool { focusEnd != nil }
        var hasLock: Bool { lockEnd != nil }
        /// When the last thing running is due to stop; past it, it's stale.
        var latestEnd: Date? { [focusEnd, lockEnd].compactMap { $0 }.max() }

        mutating func clear(_ kind: SessionKind) {
            switch kind {
            case .focus: focusTitle = nil; focusStart = nil; focusEnd = nil
            case .lockin: lockStart = nil; lockEnd = nil
            }
        }
    }
}

extension SessionAttributes.ContentState {
    /// What should be on the Lock Screen for this state, or nil for nothing.
    init?(state: AppState) {
        let now = Date()
        if let focus = state.focus, let end = focus.endDate, end > now {
            focusTitle = state.tasks.first { $0.id == focus.taskId }?.text ?? "Focus"
            focusStart = focus.startedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? now
            focusEnd = end
        }
        if state.lockin.active, let end = state.lockin.endDate, end > now {
            lockStart = state.lockin.startedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? now
            lockEnd = end
        }
        if focusEnd == nil && lockEnd == nil { return nil }
    }
}

/// The stop button on the Live Activity. It runs in the app's process, tells
/// the Mac, and takes that half off the Lock Screen.
struct StopSessionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop session"
    static var isDiscoverable = false

    @Parameter(title: "Session")
    var kind: String

    init() {}
    init(kind: SessionKind) { self.kind = kind.rawValue }

    func perform() async throws -> some IntentResult {
        let session = SessionKind(rawValue: kind) ?? .focus
        if let config = WidgetBridge.loadConfig() {
            _ = await MacClient(config: config).stop(session)
        }
        for activity in Activity<SessionAttributes>.activities {
            var next = activity.content.state
            next.clear(session)
            if next.latestEnd == nil {
                await activity.end(nil, dismissalPolicy: .immediate)
            } else {
                await activity.update(ActivityContent(state: next, staleDate: next.latestEnd))
            }
        }
        return .result()
    }
}
