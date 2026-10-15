import ActivityKit
import Foundation

/// Keeps the Lock Screen's Live Activity in step with what's running on the
/// Mac. iOS only lets an app start one while it's on screen, so a session
/// started on the Mac shows up the next time the app is opened; updates and
/// endings work from the background too.
@MainActor
enum LiveSessions {
    private static var last: SessionAttributes.ContentState?

    static func sync(_ state: AppState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let desired = SessionAttributes.ContentState(state: state)
        let running = Activity<SessionAttributes>.activities
        // Every broadcast lands here; only touch ActivityKit when something moved.
        if desired == last && (desired == nil) == running.isEmpty { return }
        last = desired

        guard let desired else {
            for activity in running { Task { await activity.end(nil, dismissalPolicy: .immediate) } }
            return
        }
        let content = ActivityContent(state: desired, staleDate: desired.latestEnd)
        if let current = running.first {
            if current.content.state != desired { Task { await current.update(content) } }
            for extra in running.dropFirst() { Task { await extra.end(nil, dismissalPolicy: .immediate) } }
        } else {
            _ = try? Activity.request(attributes: SessionAttributes(), content: content)
        }
    }
}
