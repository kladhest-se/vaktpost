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
                ZStack(alignment: .top) {
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

                    if store.isRefreshing {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Refreshing…")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(theme.hairline.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: theme.label.opacity(0.1), radius: 4, y: 2)
                    }
                }
            } else {
                OnboardingView()
            }
        }
        .tint(theme.accentColor)
        .preferredColorScheme(theme.preferredColorScheme)
        .onAppear {
            theme.systemScheme = systemScheme
            store.themeName = theme.selection.storageValue
            guard store.isConfigured else { return }
            Task {
                await store.refresh()
                store.startAutoRefresh()
            }
        }
        .onChange(of: systemScheme) { _, newValue in
            theme.systemScheme = newValue
        }
        .onChange(of: theme.selection) { _, _ in
            store.themeName = theme.selection.storageValue
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                guard store.isConfigured else { return }
                guard let last = store.lastRefresh,
                      Date().timeIntervalSince(last) > Double(store.profile.refreshSeconds) / 2
                else { store.startAutoRefresh(); return }
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
