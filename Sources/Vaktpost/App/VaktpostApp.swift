import SwiftUI

/// Switching between firewalls, and managing them.
///
/// "Log out" was the only other thing this menu offered, which framed the app
/// as something you sign in and out of. It is not — it holds a list of
/// firewalls, and what somebody wants from this menu is to add one, correct an
/// address, or remove one they no longer run. Removing a firewall still clears
/// its credentials, so nothing is lost by dropping the word.
struct ServerMenu: View {
    @Environment(\.serverRegistry) private var registry: ServerRegistry
    @Environment(\.dashboardStore) private var store: DashboardStore

    @State private var managing = false
    @State private var showingAllFirewalls = false

    var body: some View {
        Menu {
            Button { showingAllFirewalls = true } label: {
                Label("All firewalls", systemImage: "square.grid.2x2")
            }
            Divider()
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
        .sheet(isPresented: $showingAllFirewalls) {
            NavigationStack { AllFirewallsView() }
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
    @Environment(\.themeManager) private var theme: ThemeManager

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
    @Environment(\.dashboardStore) private var store: DashboardStore
    @Environment(\.themeManager) private var theme: ThemeManager

    var body: some View {
        NavigationLink { AlertsView() } label: {
            Image(systemName: store.alertManager.criticalAlertCount > 0 ? "bell.badge.fill" : "bell")
                .foregroundStyle(store.alertManager.criticalAlertCount > 0 ? theme.warn : theme.labelMuted)
        }
    }
}

@main
struct VaktpostApp: App {
    @UIApplicationDelegateAdaptor(URLDelegate.self) private var urlDelegate
    private let theme = ThemeManager()
    private let registry = ServerRegistry()
    private let deepLinkRouter: DeepLinkRouter
    private let store: DashboardStore

    init() {
        self.deepLinkRouter = DeepLinkRouter()
        self.store = DashboardStore(registry: registry)
        self.urlDelegate.router = self.deepLinkRouter
        DashboardStore.shared = self.store
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.deepLinkRouter, deepLinkRouter)
                .environment(theme)
                .environment(registry)
                .environment(\.dashboardStore, store)
                .environment(\.store, store)
        }
    }
}

class URLDelegate: NSObject, UIApplicationDelegate {
    weak var router: DeepLinkRouter?
    
    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        router?.handle(url)
        return true
    }
}

struct RootView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.scenePhase) private var scenePhase
    /// Locked: the person has to authenticate before the dashboard is shown
    /// again. Set when the app genuinely goes to the background.
    @State private var isLocked = false

    /// Obscured: the dashboard is covered but nothing is being asked. Set
    /// while the app is merely inactive — a notification pulled down, the
    /// control centre opened, the app switcher invoked.
    ///
    /// Separate from `isLocked` for two reasons. It has to go up on
    /// `.inactive`, because that is when iOS takes the app-switcher snapshot
    /// and a lock screen that appears on `.active` has already let the
    /// dashboard be photographed. And it must not demand a face, because
    /// presenting a Face ID sheet *itself* makes the app inactive — treating
    /// that as a reason to authenticate is a loop that authenticates, goes
    /// inactive, and authenticates again.
    @State private var isObscured = false

    /// Whether this app should be hiding itself at all.
    ///
    /// Checked at every transition rather than once: the setting can be turned
    /// on while the app is running, and biometry can become unavailable
    /// underneath it.
    private var shouldLock: Bool {
        store.isConfigured && BiometricAuth.isEnabled && BiometricAuth.canUseBiometrics()
    }

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
                        .badge(store.alertManager.criticalAlertCount)
                    }

                    // No refresh indicator here at all.
                    //
                    // Every screen is inside a `refreshable` scroll view, which
                    // draws its own spinner when a refresh is running. A second
                    // one floating above the tab content was both redundant and
                    // in the way — it sat over the title while scrolling.
                    }
            } else {
                NavigationStack { OnboardingView().appToolbar() }
            }
        }
        .tint(theme.accentColor)
        .preferredColorScheme(theme.preferredColorScheme)
        .onAppear {
            theme.systemScheme = systemScheme
            store.themeName = theme.selection.storageValue
            guard store.isConfigured else { return }
            Task { await store.refresh() }
            store.startAutoRefresh()
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
                // Uncover, but do not unlock. `isLocked` is cleared only by a
                // successful authentication.
                isObscured = false
                guard store.isConfigured else { return }
                store.startAutoRefresh()

            case .inactive:
                // Cover the screen before iOS photographs it for the app
                // switcher, and ask for nothing. An interruption that turns
                // out to be a real backgrounding becomes a lock a moment
                // later, when `.background` arrives.
                if shouldLock { isObscured = true }

            case .background:
                store.stopAutoRefresh()
                if shouldLock { isLocked = true }

            @unknown default:
                break
            }
        }
        // One cover for both states. Presented while either flag is set, and
        // it only prompts when the lock is the reason.
        .fullScreenCover(isPresented: Binding(
            get: { isLocked || isObscured },
            set: { shown in if !shown { isLocked = false; isObscured = false } }
        )) {
            BiometricLockView(requiresAuthentication: isLocked) {
                isLocked = false
                isObscured = false
            }
        }
        .onAppear {
            if shouldLock { isLocked = true }
            guard store.isConfigured else { return }
            guard let last = store.lastRefresh,
                  Date().timeIntervalSince(last) > Double(store.profile.refreshSeconds) / 2
            else { store.startAutoRefresh(); return }
            Task {
                await store.refresh()
                store.startAutoRefresh()
            }
        }
    }
}

private struct DoneButton: View {
    @Environment(\.dashboardStore) private var store: DashboardStore
    @Environment(\.themeManager) private var theme: ThemeManager
    
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
