import SwiftUI
import Foundation

/// Custom environment keys for @Observable stores.
///
/// Replaces .environmentObject() with .environment() so that @Observable
/// (not just ObservableObject) types can be injected into the view hierarchy.

// MARK: - Environment key wrappers

private struct DashboardStoreEnvironmentKey: EnvironmentKey {
    @MainActor
    static var defaultValue: DashboardStore { _defaultDashboardStore }
}

private struct ServerRegistryEnvironmentKey: EnvironmentKey {
    @MainActor
    static var defaultValue: ServerRegistry { _defaultServerRegistry }
}

private struct ThemeManagerEnvironmentKey: EnvironmentKey {
    @MainActor
    static var defaultValue: ThemeManager { _defaultThemeManager }
}

private struct DeepLinkRouterEnvironmentKey: EnvironmentKey {
    @MainActor
    static var defaultValue: DeepLinkRouter { DeepLinkRouter() }
}

// MARK: - Default instances

@MainActor
private let _defaultDashboardStore = DashboardStore(registry: ServerRegistry())

@MainActor
private let _defaultServerRegistry = ServerRegistry()

@MainActor
private let _defaultThemeManager = ThemeManager()

extension EnvironmentValues {
    var dashboardStore: DashboardStore {
        get { self[DashboardStoreEnvironmentKey.self] }
        set { self[DashboardStoreEnvironmentKey.self] = newValue }
    }
    var serverRegistry: ServerRegistry {
        get { self[ServerRegistryEnvironmentKey.self] }
        set { self[ServerRegistryEnvironmentKey.self] = newValue }
    }
    var themeManager: ThemeManager {
        get { self[ThemeManagerEnvironmentKey.self] }
        set { self[ThemeManagerEnvironmentKey.self] = newValue }
    }
    var deepLinkRouter: DeepLinkRouter {
        get { self[DeepLinkRouterEnvironmentKey.self] }
        set { self[DeepLinkRouterEnvironmentKey.self] = newValue }
    }
    
    /// Allow @Environment(\.themeManager) private var theme: ThemeManager
    var theme: ThemeManager {
        get { self[ThemeManagerEnvironmentKey.self] }
        set { self[ThemeManagerEnvironmentKey.self] = newValue }
    }
    
    /// Allow @Environment(\.dashboardStore) private var store: DashboardStore
    var store: DashboardStore {
        get { self[DashboardStoreEnvironmentKey.self] }
        set { self[DashboardStoreEnvironmentKey.self] = newValue }
    }
    
    /// Allow @Environment(\.serverRegistry) private var registry: ServerRegistry
    var registry: ServerRegistry {
        get { self[ServerRegistryEnvironmentKey.self] }
        set { self[ServerRegistryEnvironmentKey.self] = newValue }
    }
}

// MARK: - Convenience modifiers

extension View {
    func environment(_ store: DashboardStore) -> some View {
        environment(\.dashboardStore, store)
            .environment(\.store, store)
    }
    func environment(_ registry: ServerRegistry) -> some View {
        environment(\.serverRegistry, registry)
            .environment(\.registry, registry)
    }
    func environment(_ theme: ThemeManager) -> some View {
        environment(\.themeManager, theme)
            .environment(\.theme, theme)
    }
}
