import SwiftUI

/// Custom environment keys for @Observable stores.
///
/// Replaces .environmentObject() with .environment() so that @Observable
/// (not just ObservableObject) types can be injected into the view hierarchy.

// MARK: - Environment key wrappers

private struct DashboardStoreEnvironmentKey: EnvironmentKey {
    static var defaultValue: DashboardStore? = nil
}

private struct ServerRegistryEnvironmentKey: EnvironmentKey {
    static var defaultValue: ServerRegistry? = nil
}

private struct ThemeManagerEnvironmentKey: EnvironmentKey {
    static var defaultValue: ThemeManager? = nil
}

extension EnvironmentValues {
    var dashboardStore: DashboardStore {
        get { self[DashboardStoreEnvironmentKey.self]! }
        set { self[DashboardStoreEnvironmentKey.self] = newValue }
    }
    var serverRegistry: ServerRegistry {
        get { self[ServerRegistryEnvironmentKey.self]! }
        set { self[ServerRegistryEnvironmentKey.self] = newValue }
    }
    var themeManager: ThemeManager {
        get { self[ThemeManagerEnvironmentKey.self]! }
        set { self[ThemeManagerEnvironmentKey.self] = newValue }
    }
    
    /// Allow @Environment(\.themeManager) private var theme: ThemeManager
    var theme: ThemeManager {
        get { self[ThemeManagerEnvironmentKey.self]! }
        set { self[ThemeManagerEnvironmentKey.self] = newValue }
    }
    
    /// Allow @Environment(\.dashboardStore) private var store: DashboardStore
    var store: DashboardStore {
        get { self[DashboardStoreEnvironmentKey.self]! }
        set { self[DashboardStoreEnvironmentKey.self] = newValue }
    }
    
    /// Allow @Environment(\.serverRegistry) private var registry: ServerRegistry
    var registry: ServerRegistry {
        get { self[ServerRegistryEnvironmentKey.self]! }
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
