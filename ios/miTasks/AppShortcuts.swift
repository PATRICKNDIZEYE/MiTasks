import AppIntents

/// Siri, Spotlight and the Action button.
struct MiTasksShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenComposerIntent(mode: .voice),
            phrases: ["Speak a task in \(.applicationName)", "Tell \(.applicationName) something"],
            shortTitle: "Speak a task",
            systemImageName: "mic"
        )
        AppShortcut(
            intent: OpenComposerIntent(mode: .add),
            phrases: ["New task in \(.applicationName)", "Add a task to \(.applicationName)"],
            shortTitle: "New task",
            systemImageName: "plus"
        )
    }
}
