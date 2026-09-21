import SwiftUI

@main
struct miTasksApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.amber)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var phase
    @State private var tab = Tab.initial

    enum Tab: Hashable {
        case today, agenda, notes, insights

        /// `simctl launch … -startTab agenda` lands straight on a screen.
        /// UserDefaults picks up `-key value` launch arguments for free.
        static var initial: Tab {
            #if DEBUG
            switch UserDefaults.standard.string(forKey: "startTab") {
            case "agenda": return .agenda
            case "notes": return .notes
            case "insights": return .insights
            default: return .today
            }
            #else
            return .today
            #endif
        }
    }

    var body: some View {
        Group {
            if store.config == nil {
                PairingView()
            } else {
                tabs
            }
        }
        .task { store.start() }
        .onChange(of: phase) { _, new in
            // Coming back from the background, the SSE stream is usually dead;
            // a plain re-read is the cheapest way to resync.
            if new == .active { Task { await store.refresh() } }
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "checkmark.square") }
                .tag(Tab.today)
            AgendaView()
                .tabItem { Label("Agenda", systemImage: "calendar") }
                .tag(Tab.agenda)
            NotesView()
                .tabItem { Label("Notes", systemImage: "doc.text") }
                .tag(Tab.notes)
            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.bar") }
                .tag(Tab.insights)
        }
    }
}

/// Wraps a screen in the widget's gradient and gives it the standard header.
struct Screen<Content: View>: View {
    let title: String
    var subtitle: String
    var trailing: AnyView? = nil
    @ViewBuilder var content: Content

    @EnvironmentObject private var store: Store

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(title).font(Theme.display(27))
                            Eyebrow(text: subtitle)
                        }
                        Spacer(minLength: 0)
                        if let trailing { trailing }
                        Circle()
                            .fill(store.connected ? Theme.sage : Theme.clay)
                            .frame(width: 8, height: 8)
                            .padding(.top, 15)
                    }

                    if !store.connected {
                        Text("Showing the last synced copy — your Mac isn't reachable.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.ink2)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.clay.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
                            .overlay(
                                RoundedRectangle(cornerRadius: 11)
                                    .stroke(Theme.clay.opacity(0.4), lineWidth: 1)
                            )
                            .padding(.top, 14)
                    }

                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
        }
        .foregroundStyle(Theme.ink)
    }
}

struct EmptyNote: View {
    let big: String
    let small: String

    var body: some View {
        VStack(spacing: 7) {
            Text(big).font(.system(size: 17, design: .serif)).italic()
            Text(small).font(.system(size: 12))
        }
        .foregroundStyle(Theme.ink3)
        .frame(maxWidth: .infinity)
        .padding(.top, 52)
    }
}
