import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Focus and lock-in countdowns on the Lock Screen, and in the Dynamic
/// Island on phones that have one. The clock ticks on its own, so the app
/// doesn't need to be running for it to stay right.
struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionAttributes.self) { context in
            SessionBanner(state: context.state, stale: context.isStale)
                .padding(16)
                .activityBackgroundTint(Palette.bg)
                .activitySystemActionForegroundColor(Palette.ink)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SessionIcon(state: s).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: s, stale: context.isStale)
                        .font(.system(size: 22, weight: .semibold).monospacedDigit())
                        .frame(maxWidth: 110, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(s.focusTitle ?? "Your Mac stays awake")
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        StopButton(kind: s.hasFocus ? .focus : .lockin)
                    }
                }
            } compactLeading: {
                SessionIcon(state: s, size: 14)
            } compactTrailing: {
                Countdown(state: s, stale: context.isStale)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .frame(maxWidth: 52)
            } minimal: {
                SessionIcon(state: s, size: 14)
            }
            .keylineTint(s.hasFocus ? Palette.blue : Palette.green)
        }
    }
}

struct SessionBanner: View {
    let state: SessionAttributes.ContentState
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                SessionIcon(state: state, size: 18)
                    .frame(width: 36, height: 36)
                    .background(Palette.surface2, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.hasFocus ? "FOCUS" : "LOCKED IN")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(state.hasFocus ? Palette.blue : Palette.green)
                    Text(state.focusTitle ?? "Your Mac stays awake")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if state.hasFocus, let start = state.lockStart, let end = state.lockEnd, !stale {
                        // Both running: the lock-in rides along underneath.
                        HStack(spacing: 4) {
                            Text("Locked in ·")
                            Text(timerInterval: min(start, end)...end, countsDown: true)
                                .monospacedDigit()
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                    }
                }

                Spacer(minLength: 4)

                Countdown(state: state, stale: stale)
                    .font(.system(size: 26, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120, alignment: .trailing)

                StopButton(kind: state.hasFocus ? .focus : .lockin)
            }

            if let (start, end) = primarySpan(state), !stale {
                ProgressView(timerInterval: min(start, end)...end, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(state.hasFocus ? Palette.blue : Palette.green)
            }
        }
    }
}

/// The span the big clock counts: focus if there is one, otherwise lock-in.
private func primarySpan(_ s: SessionAttributes.ContentState) -> (Date, Date)? {
    if let start = s.focusStart, let end = s.focusEnd { return (start, end) }
    if let start = s.lockStart, let end = s.lockEnd { return (start, end) }
    return nil
}

struct Countdown: View {
    let state: SessionAttributes.ContentState
    let stale: Bool

    var body: some View {
        if stale || primarySpan(state) == nil {
            Text("Done")
        } else if let (start, end) = primarySpan(state) {
            Text(timerInterval: min(start, end)...end, countsDown: true)
        }
    }
}

struct SessionIcon: View {
    let state: SessionAttributes.ContentState
    var size: CGFloat = 16

    var body: some View {
        Image(systemName: state.hasFocus ? "scope" : "lock.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(state.hasFocus ? Palette.blue : Palette.green)
    }
}

struct StopButton: View {
    let kind: SessionKind

    var body: some View {
        Button(intent: StopSessionIntent(kind: kind)) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Palette.ink)
                .frame(width: 30, height: 30)
                .background(Palette.chip, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind == .focus ? "Stop focus" : "Stop lock-in")
    }
}

// MARK: - Control Center

/// Control Center, the Lock Screen's corner buttons and the Action button.
struct NewTaskControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "rw.azultech.mitasks.new-task") {
            ControlWidgetButton(action: OpenComposerIntent(mode: .add)) {
                Label("New task", systemImage: "plus.circle.fill")
            }
        }
        .displayName("New task")
        .description("Open miTasks with the composer ready.")
    }
}

struct SpeakTaskControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "rw.azultech.mitasks.speak-task") {
            ControlWidgetButton(action: OpenComposerIntent(mode: .voice)) {
                Label("Speak a task", systemImage: "mic.fill")
            }
        }
        .displayName("Speak a task")
        .description("Open miTasks already listening.")
    }
}
