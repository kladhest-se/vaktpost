import SwiftUI

/// The active theme and accent, persisted to UserDefaults.
///
/// Five choices, one list: Auto plus the four themes. There is no separate
/// light/dark pairing to configure — Auto is Latte in light and Mocha in dark,
/// and anything else is that theme regardless of what iOS is doing.
///
/// The previous design let you pick a theme for each appearance independently.
/// It was three controls deep for a decision most people make once, and the two
/// grids were visually identical so half of every tap landed on the appearance
/// you weren't currently in.
///
/// Note: `@AppStorage` is deliberately not used. It is a `DynamicProperty`
/// intended for views; inside an `ObservableObject` it does not fire
/// `objectWillChange`, so the tab tree would not repaint when the theme
/// changed. `@Published` with a `didSet` write-through does.
@MainActor
final class ThemeManager: ObservableObject {

    /// Auto, or one theme pinned.
    enum Selection: Equatable, Hashable, Identifiable {
        case auto
        case fixed(Theme)

        var id: String { storageValue }

        var storageValue: String {
            switch self {
            case .auto: return "auto"
            case .fixed(let theme): return theme.rawValue
            }
        }

        init(storageValue: String) {
            if let theme = Theme(rawValue: storageValue) { self = .fixed(theme) }
            else { self = .auto }
        }

        var displayName: String {
            switch self {
            case .auto: return "Auto"
            case .fixed(let theme): return theme.displayName
            }
        }

        static var all: [Selection] { [.auto] + Theme.allCases.map(Selection.fixed) }
    }

    private enum Key {
        static let selection = "theme.selection"
        static let accent = "theme.accent"
        // Read once, to carry over a choice made under the old three-control
        // design rather than silently resetting it.
        static let legacyMode = "theme.mode"
        static let legacyFixed = "theme.fixed"
    }

    @Published var selection: Selection {
        didSet { UserDefaults.standard.set(selection.storageValue, forKey: Key.selection) }
    }
    @Published var accent: Accent {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: Key.accent) }
    }

    /// Pushed in by the root view so Auto can resolve.
    @Published var systemScheme: ColorScheme = .dark

    init() {
        let defaults = UserDefaults.standard
        accent = Accent(rawValue: defaults.string(forKey: Key.accent) ?? "") ?? .sapphire

        if let stored = defaults.string(forKey: Key.selection) {
            selection = Selection(storageValue: stored)
        } else if defaults.string(forKey: Key.legacyMode) == "fixed",
                  let old = defaults.string(forKey: Key.legacyFixed),
                  let theme = Theme(rawValue: old) {
            selection = .fixed(theme)
        } else {
            selection = .auto
        }
    }

    // MARK: Resolved theme

    /// The theme in effect right now.
    var current: Theme {
        switch selection {
        case .auto: return systemScheme == .light ? .latte : .mocha
        case .fixed(let theme): return theme
        }
    }

    /// nil under Auto, so SwiftUI keeps following the system.
    var preferredColorScheme: ColorScheme? {
        if case .fixed(let theme) = selection { return theme.colorScheme }
        return nil
    }

    var palette: Palette { current.palette }
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
    var teal: Color { palette.teal }
    var blue: Color { palette.blue }
    var mauve: Color { palette.mauve }
    var lavender: Color { palette.lavender }
    var maroon: Color { palette.maroon }
    var peach: Color { palette.peach }
}
