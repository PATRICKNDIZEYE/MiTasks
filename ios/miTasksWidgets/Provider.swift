import AppIntents
import WidgetKit

// MARK: - Configuration

/// A project the widget can be narrowed to. Labels are the user's own, read
/// from the list the app last shared.
struct LabelEntity: AppEntity {
    var id: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Project"
    static var defaultQuery = LabelQuery()

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }
}

struct LabelQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [LabelEntity] {
        identifiers.map(LabelEntity.init)
    }

    func suggestedEntities() async throws -> [LabelEntity] {
        (WidgetBridge.loadState()?.labels ?? []).map { LabelEntity(id: $0.name) }
    }
}

struct FilterIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose tasks"
    static var description = IntentDescription("Show every open task, or just one project's.")

    @Parameter(title: "Project")
    var label: LabelEntity?
}

// MARK: - Timeline

struct TasksEntry: TimelineEntry {
    let date: Date
    let state: AppState
    let label: String?
    let paired: Bool
    /// False when the Mac couldn't be reached and this is the phone's copy.
    let live: Bool

    var color: String? { label.flatMap { state.label(named: $0)?.color } }
    var ranked: [TaskItem] { state.ranked(label: label) }
    var needsYou: [TaskItem] { ranked.filter(TaskStatus.needsYou) }

    static let preview = TasksEntry(date: .now, state: .sample, label: nil, paired: true, live: true)
}

struct TasksProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TasksEntry { .preview }

    func snapshot(for configuration: FilterIntent, in context: Context) async -> TasksEntry {
        if context.isPreview && WidgetBridge.loadState() == nil { return .preview }
        return await entry(for: configuration)
    }

    func timeline(for configuration: FilterIntent, in context: Context) async -> Timeline<TasksEntry> {
        let entry = await entry(for: configuration)
        // Redraw at least every 20 minutes, and right after midnight, when
        // "due today" turns into "overdue".
        let soon = Date().addingTimeInterval(20 * 60)
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Date().startOfDay) ?? soon
        return Timeline(entries: [entry], policy: .after(min(soon, midnight.addingTimeInterval(60))))
    }

    private func entry(for configuration: FilterIntent) async -> TasksEntry {
        let config = WidgetBridge.loadConfig()
        var state = WidgetBridge.loadState() ?? .empty
        var live = false

        // The Mac is the truth whenever the app has nothing of its own still
        // waiting to go up; otherwise the app's copy is the newer one.
        if let config, WidgetBridge.pendingCount == 0, let fresh = await MacClient(config: config).state() {
            state = fresh
            live = true
        }
        let ticked = Set(WidgetBridge.ticks.map(\.id))
        for i in state.tasks.indices where ticked.contains(state.tasks[i].id) {
            state.tasks[i].done = true
        }
        return TasksEntry(date: .now, state: state, label: configuration.label?.id, paired: config != nil, live: live)
    }
}

// MARK: - Ticking from the Home Screen

struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete task"
    static var isDiscoverable = false

    @Parameter(title: "Task")
    var taskId: String

    init() {}
    init(taskId: String) { self.taskId = taskId }

    func perform() async throws -> some IntentResult {
        let at = Date().timeIntervalSince1970 * 1000

        // Tick it in the shared copy first, so the widget redraws at once.
        if var state = WidgetBridge.loadState(),
           let i = state.tasks.firstIndex(where: { $0.id == taskId }) {
            state.tasks[i].done = true
            state.tasks[i].doneAt = at
            WidgetBridge.publish(state, pending: WidgetBridge.pendingCount)
        }

        // Straight to the Mac if it's there; otherwise the app sends it later.
        var sent = false
        if let config = WidgetBridge.loadConfig() {
            sent = await MacClient(config: config).complete(taskId, at: at)
        }
        if !sent { WidgetBridge.addTick(.init(id: taskId, at: at)) }
        return .result()
    }
}

// MARK: - Sample data for the gallery

extension AppState {
    static var sample: AppState {
        let today = DateParse.dayString(.now)
        let yesterday = DateParse.dayString(Date().addingTimeInterval(-86_400))
        var s = AppState()
        s.labels = [LabelItem(name: "Crew", color: "#7d9bb8"), LabelItem(name: "Home", color: "#8fa876")]
        s.tasks = [
            TaskItem(id: "s1", text: "Ship the pairing fix", label: "Crew", done: false, priority: "high", due: yesterday),
            TaskItem(id: "s2", text: "Review Jev classifier prompts", label: "Crew", done: false, priority: "high", due: today),
            TaskItem(id: "s3", text: "Call the landlord", label: "Home", done: false, priority: "med", due: today),
            TaskItem(id: "s4", text: "Draft the weekly update", label: "Crew", done: false, priority: "med"),
            TaskItem(id: "s5", text: "Book flights for December", label: "Home", done: false),
            TaskItem(id: "s6", text: "Tidy the Notes tab", label: nil, done: false),
        ]
        return s
    }
}
