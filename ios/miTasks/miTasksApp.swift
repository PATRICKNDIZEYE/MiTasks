import SwiftUI

@main
struct miTasksApp: App {
    @StateObject private var store = Store()

    init() {
        Theme.applyChrome()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(Theme.primary)
                .preferredColorScheme(.dark)
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

/// Wraps a screen in the page background and gives it a Crew mission
/// header: a large title with a control on the right, then a 13 muted meta
/// line underneath.
struct Screen<Meta: View, Trailing: View, Content: View>: View {
    let title: String
    @ViewBuilder var meta: Meta
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    @EnvironmentObject private var store: Store

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: Theme.Space.s) {
                        Text(title)
                            .font(Theme.display())
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        trailing
                    }
                    .frame(minHeight: Theme.Height.large)

                    FlowRow(spacing: Theme.Space.l, lineSpacing: Theme.Space.xs) {
                        meta
                    }
                    .font(Theme.text(Theme.Size.m))
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)
                    .padding(.top, Theme.Space.xxs)

                    if !store.connected {
                        StatusStrip(
                            tint: Theme.red,
                            fill: Theme.redBg,
                            title: "Showing the last synced copy — your Mac isn't reachable.",
                            lines: 2
                        ) { EmptyView() }
                        .foregroundStyle(Theme.ink2)
                        .padding(.top, Theme.Space.m)
                    }

                    content
                }
                .padding(.horizontal, Theme.Space.xl)
                .padding(.top, Theme.Space.m)
                .padding(.bottom, Theme.Space.s32)
            }
        }
        .foregroundStyle(Theme.ink)
    }
}

extension Screen where Trailing == EmptyView {
    init(title: String, @ViewBuilder meta: () -> Meta, @ViewBuilder content: () -> Content) {
        self.init(title: title, meta: meta, trailing: { EmptyView() }, content: content)
    }
}

struct EmptyNote: View {
    let big: String
    let small: String

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            Text(big)
                .font(Theme.text(Theme.Size.body, .semibold))
                .foregroundStyle(Theme.ink)
            Text(small)
                .font(Theme.text(Theme.Size.m))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Space.xl)
        .padding(.top, Theme.Space.s40)
        .padding(.bottom, Theme.Space.xxl)
    }
}
