import SwiftUI

@main
struct VaktpostApp: App {
    @StateObject private var theme = ThemeManager()
    @StateObject private var registry: ServerRegistry
    @StateObject private var store: DashboardStore

    init() {
        let reg = ServerRegistry()
        _registry = StateObject(wrappedValue: reg)
        _store = StateObject(wrappedValue: DashboardStore(registry: reg))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(theme)
                .environmentObject(registry)
                .environmentObject(store)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if store.isConfigured {
                TabView {
                    NavigationStack { OverviewView() }
                        .tabItem { Label("Overview", systemImage: "square.grid.2x2") }

                    NavigationStack { ClientsView() }
                        .tabItem { Label("Clients", systemImage: "person.2") }

                    NavigationStack { NetworkView() }
                        .tabItem { Label("Network", systemImage: "network") }

                    NavigationStack { LogsView() }
                        .tabItem { Label("Logs", systemImage: "text.alignleft") }

                    NavigationStack { MoreView() }
                        .tabItem { Label("More", systemImage: "ellipsis.circle") }
                        .badge(store.criticalAlertCount)
                }
            } else {
                OnboardingView()
            }
        }
        .tint(theme.accentColor)
        .preferredColorScheme(theme.mode == .fixed ? theme.fixedFlavor.colorScheme : nil)
        .onAppear {
            theme.systemScheme = systemScheme
            guard store.isConfigured else { return }
            Task {
                await store.refresh()
                store.startAutoRefresh()
            }
        }
        .onChange(of: systemScheme) { _, newValue in
            theme.systemScheme = newValue
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                guard store.isConfigured else { return }
                Task {
                    await store.refresh()
                    store.startAutoRefresh()
                }
            case .background, .inactive:
                store.stopAutoRefresh()
            @unknown default:
                break
            }
        }
    }
}
