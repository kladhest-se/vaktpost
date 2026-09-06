import SwiftUI

/// Owns the active flavour and accent, persisted to UserDefaults.
///
/// Note: `@AppStorage` is deliberately not used here. It is a `DynamicProperty`
/// intended for views; inside an `ObservableObject` it does not fire
/// `objectWillChange`, so the tab tree would not repaint when the flavour
/// changed. Plain `@Published` properties with a `didSet` write-through do.
@MainActor
final class ThemeManager: ObservableObject {

    enum Mode: String, CaseIterable, Identifiable, Codable {
        case fixed          // always use `fixedFlavor`
        case followSystem   // pick `lightFlavor` / `darkFlavor` from system appearance

        var id: String { rawValue }
        var displayName: String { self == .fixed ? "Fixed" : "Follow system" }
    }

    private enum Key {
        static let mode = "theme.mode"
        static let fixed = "theme.fixed"
        static let light = "theme.light"
        static let dark = "theme.dark"
        static let accent = "theme.accent"
    }

    @Published var mode: Mode { didSet { store(mode.rawValue, Key.mode) } }
    @Published var fixedFlavor: Flavor { didSet { store(fixedFlavor.rawValue, Key.fixed) } }
    @Published var lightFlavor: Flavor { didSet { store(lightFlavor.rawValue, Key.light) } }
    @Published var darkFlavor: Flavor { didSet { store(darkFlavor.rawValue, Key.dark) } }
    @Published var accent: Accent { didSet { store(accent.rawValue, Key.accent) } }

    /// Pushed in by the root view so `followSystem` can resolve.
    @Published var systemScheme: ColorScheme = .dark

    init() {
        let d = UserDefaults.standard
        mode = Mode(rawValue: d.string(forKey: Key.mode) ?? "") ?? .followSystem
        fixedFlavor = Flavor(rawValue: d.string(forKey: Key.fixed) ?? "") ?? .mocha
        lightFlavor = Flavor(rawValue: d.string(forKey: Key.light) ?? "") ?? .latte
        darkFlavor = Flavor(rawValue: d.string(forKey: Key.dark) ?? "") ?? .macchiato
        accent = Accent(rawValue: d.string(forKey: Key.accent) ?? "") ?? .sapphire
    }

    private func store(_ value: String, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    // MARK: Resolved theme

    var flavor: Flavor {
        switch mode {
        case .fixed: return fixedFlavor
        case .followSystem: return systemScheme == .light ? lightFlavor : darkFlavor
        }
    }

    var palette: Palette { flavor.palette }
    var accentColor: Color { accent.color(in: palette) }

    // MARK: Semantic roles — views never reach for a raw colour name

    var bg: Color { palette.base }
    var bgSunken: Color { palette.mantle }
    var card: Color { palette.surface0 }
    var cardRaised: Color { palette.surface1 }
    var hairline: Color { palette.surface2 }
    var label: Color { palette.text }
    var labelMuted: Color { palette.subtext0 }
    var labelFaint: Color { palette.overlay1 }

    var ok: Color { palette.green }
    var warn: Color { palette.yellow }
    var bad: Color { palette.red }
    var info: Color { palette.sky }
    var idle: Color { palette.overlay0 }
}
