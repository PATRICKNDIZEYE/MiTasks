import AppIntents
import Foundation

/// Places outside the app can send you: a widget row, a Control Center
/// button, Siri. Spelled as mitasks:// links so widgets can use them directly.
enum AppRoute: Equatable {
    case task(String)
    case add
    case voice

    var url: URL {
        switch self {
        case .task(let id): return URL(string: "mitasks://task/\(id)")!
        case .add: return URL(string: "mitasks://add")!
        case .voice: return URL(string: "mitasks://voice")!
        }
    }

    init?(url: URL) {
        guard url.scheme == "mitasks" else { return nil }
        switch url.host {
        case "task":
            let id = url.pathComponents.dropFirst().first ?? ""
            guard !id.isEmpty else { return nil }
            self = .task(id)
        case "add": self = .add
        case "voice": self = .voice
        default: return nil
        }
    }
}

enum ComposerMode: String, AppEnum {
    case add, voice

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Capture"
    static var caseDisplayRepresentations: [ComposerMode: DisplayRepresentation] = [
        .add: "Type a task",
        .voice: "Speak a task",
    ]
}

/// Opens the app ready to capture: the composer focused, or the mic already
/// listening. Backs the Control Center buttons and the Siri shortcuts.
struct OpenComposerIntent: AppIntent {
    static var title: LocalizedStringResource = "New task"
    static var description = IntentDescription("Open miTasks ready to type or speak a task.")
    static var openAppWhenRun = true

    @Parameter(title: "Capture", default: .add)
    var mode: ComposerMode

    init() {}
    init(mode: ComposerMode) { self.mode = mode }

    @MainActor
    func perform() async throws -> some IntentResult {
        WidgetBridge.setRoute(mode == .voice ? .voice : .add)
        return .result()
    }
}
