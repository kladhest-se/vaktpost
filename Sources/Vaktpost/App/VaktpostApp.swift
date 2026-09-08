import SwiftUI

/// Switching between firewalls, and managing them.
///
/// "Log out" was the only other thing this menu offered, which framed the app
/// as something you sign in and out of. It is not — it holds a list of
/// firewalls, and what somebody wants from this menu is to add one, correct an
/// address, or remove one they no longer run. Removing a firewall still clears
/// its credentials, so nothing is lost by dropping the word.
struct ServerMenu: View {
    @EnvironmentObject private var registry: ServerRegistry
    @EnvironmentObject private var store: DashboardStore

    @State private var managing = false

    var body: some View {
        Menu {
            ForEach(registry.servers) { server in
                Button {
                    Task { await store.switchTo(server) }
                } label: {
                    // A tick beside the one in use: with three firewalls the
                    // menu otherwise gives no clue which you are looking at.
                    if server.id == registry.active?.id {
                        Label(server.displayName, systemImage: "checkmark")
                    } else {
                        Text(server.displayName)
                    }
                }
            }

            if !registry.servers.isEmpty {
                Divider()
            }

            Button {
                managing = true
            } label: {
                Label("Manage firewalls", systemImage: "slider.horizontal.3")
            }
        } label: {
            Image(systemName: "server.rack")
                .scaledFont(16)
        }
        .sheet(isPresented: $managing) {
            NavigationStack {
                ServersView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { managing = false }
                        }
                    }
            }
        }
    }
}

/// Settings.
struct SettingsButton: View {
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        NavigationLink { SettingsView() } label: {
            Image(systemName: "gearshape")
                .foregroundStyle(theme.labelMuted)
                .scaledFont(16)
        }
        .accessibilityLabel("Settings")
    }
}

/// The toolbar every tab carries.
///
/// It was written out five times, once per tab, which is five places to edit
/// and five chances to leave one behind — the Overview already had a button
/// the others did not.
struct AppToolbar: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarLeading) { ServerMenu() }
            ToolbarItemGroup(placement: .topBarTrailing) {
                AlertButton()
                SettingsButton()
            }
        }
    }
}

extension View {
    func appToolbar() -> some View { modifier(AppToolbar()) }
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
            if store.isConfigured && store.isUnreachable {
                // Tabs hidden while the firewall cannot be reached.
                //
                // Five tabs of empty cards is a worse answer than one sentence
                // saying the firewall is not answering: each of those screens
                // would explain its own emptiness separately, and none would
                // say the thing they have in common.
                //
                // The toolbar stays. Switching to another firewall or fixing
                // this one's address is exactly what somebody wants from here,
                // and both live up there.
                NavigationStack {
                    UnreachableView()
                        .appToolbar()
                }
            } else if store.isConfigured {
                ZStack(alignment: .top) {
                    TabView {
                        NavigationStack {
                            OverviewView()
                                .appToolbar()
                                .toolbar { ToolbarItem(placement: .confirmationAction) { DoneButton() } }
                        }
                        .tabItem { Label("Overview", systemImage: "square.grid.2x2") }

                        // Wrapped like every other tab. MasterDetail no
                        // longer creates a stack of its own — it cannot, since
                        // the same container is used by Firewall, which is
                        // pushed from More and must not nest one.
                        NavigationStack {
                            ClientsView()
                                .appToolbar()
                        }
                        .tabItem { Label("Clients", systemImage: "person.2") }

                        NavigationStack {
                            NetworkView()
                                .appToolbar()
                        }
                        .tabItem { Label("Network", systemImage: "network") }

                        NavigationStack {
                            LogsView()
                                .appToolbar()
                        }
                        .tabItem { Label("Logs", systemImage: "text.alignleft") }

                        NavigationStack {
                            MoreView()
                                .appToolbar()
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
