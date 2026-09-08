import SwiftUI

struct ServerMenu: View {
    @EnvironmentObject private var registry: ServerRegistry
    @EnvironmentObject private var store: DashboardStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmLogout = false

    var body: some View {
        Menu {
            ForEach(registry.servers) { server in
                Button(server.displayName) {
                    Task { await store.switchTo(server) }
                }
            }
            if !registry.servers.isEmpty {
                Divider()
            }
            Button("Log out", role: .destructive) {
                confirmLogout = true
            }
        } label: {
            Image(systemName: "server.rack")
                .scaledFont(16)
        }
        .confirmationDialog("Log out?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Log out", role: .destructive) {
                Task { await store.logout() }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All metrics, logs, and cached data will be cleared.")
        }
    }
}

struct AlertButton: View {
    @EnvironmentObject private var store: DashboardStore
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        NavigationLink { AlertsView() } label: {
            Image(systemName: store.criticalAlertCount > 0 ? "bell.badge.fill" : "bell")
                .foregroundStyle(store.criticalAlertCount > 0 ? theme.warn : theme.labelMuted)
        }
    }
}

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
                        NavigationStack {
                            OverviewView()
                                .toolbar {
                                    ToolbarItem(placement: .topBarLeading) { ServerMenu() }
                                    ToolbarItem(placement: .topBarTrailing) { AlertButton() }
                                    ToolbarItem(placement: .confirmationAction) { DoneButton() }
                                }
                        }
                        .tabItem { Label("Overview", systemImage: "square.grid.2x2") }

                        // Wrapped like every other tab. MasterDetail no
                        // longer creates a stack of its own — it cannot, since
                        // the same container is used by Firewall, which is
                        // pushed from More and must not nest one.
                        NavigationStack {
                            ClientsView()
                                .toolbar {
                                    ToolbarItem(placement: .topBarLeading) { ServerMenu() }
                                    ToolbarItem(placement: .topBarTrailing) { AlertButton() }
                                }
                        }
                        .tabItem { Label("Clients", systemImage: "person.2") }

                        NavigationStack {
                            NetworkView()
                                .toolbar {
                                    ToolbarItem(placement: .topBarLeading) { ServerMenu() }
                                    ToolbarItem(placement: .topBarTrailing) { AlertButton() }
                                }
                        }
                        .tabItem { Label("Network", systemImage: "network") }

                        NavigationStack {
                            LogsView()
                                .toolbar {
                                    ToolbarItem(placement: .topBarLeading) { ServerMenu() }
                                    ToolbarItem(placement: .topBarTrailing) { AlertButton() }
                                }
                        }
                        .tabItem { Label("Logs", systemImage: "text.alignleft") }

                        NavigationStack {
                            MoreView()
                                .toolbar {
                                    ToolbarItem(placement: .topBarLeading) { ServerMenu() }
                                    ToolbarItem(placement: .topBarTrailing) { AlertButton() }
                                }
                        }
                        .tabItem { Label("More", systemImage: "ellipsis.circle") }
                        .badge(store.criticalAlertCount)
                    }

                    // No refresh indicator here at all.
                    //
                    // Every screen is inside a `refreshable` scroll view, which
                    // draws its own spinner when a refresh is running. A second
                    // one floating above the tab content was both redundant and
                    // in the way — it sat over the title while scrolling.
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

private struct DoneButton: View {
    @EnvironmentObject private var store: DashboardStore
    @EnvironmentObject private var theme: ThemeManager
    
    var body: some View {
        if store.isOverviewEditing {
            Button("Done") {
                store.toggleOverviewEditing()
            }
            .bold()
            .foregroundStyle(theme.accentColor)
        }
    }
}
