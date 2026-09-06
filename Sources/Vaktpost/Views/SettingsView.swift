import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupHeading(text: "Appearance")
                themeSlab
                accentSlab

                GroupHeading(text: "About")
                aboutSlab
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("Settings")
    }





    private var themeSlab: some View {
        Slab(rail: .info, title: "Theme") {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(ThemeManager.Selection.all) { option in
                        ThemeSwatch(
                            selection: option,
                            resolved: theme.current,
                            isSelected: theme.selection == option
                        )
                        .onTapGesture { theme.selection = option }
                    }
                }
                Text(theme.selection == .auto
                     ? "Auto follows iOS: Latte in light, Mocha in dark. Currently \(theme.current.displayName)."
                     : "\(theme.current.displayName) whatever iOS is set to.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.labelFaint)
            }
        }
    }

    private var accentSlab: some View {
        Slab(rail: .info, title: "Accent") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 7), spacing: 12) {
                ForEach(Accent.allCases) { accent in
                    Circle()
                        .fill(accent.color(in: theme.palette))
                        .frame(height: 30)
                        .overlay(
                            Circle()
                                .strokeBorder(theme.label, lineWidth: theme.accent == accent ? 2.5 : 0)
                                .padding(-3)
                        )
                        .onTapGesture { theme.accent = accent }
                        .accessibilityLabel(accent.displayName)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var aboutSlab: some View {
        Slab(rail: .info, title: "Vaktpost") {
            VStack(alignment: .leading, spacing: 8) {
                Text("A read-only dashboard for pfSense CE and Plus, talking to the community REST API package over /api/v2.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.labelMuted)
                Hairline()
                FieldRow(key: "Requires", value: "pfSense-pkg-RESTAPI", mono: false)
                FieldRow(key: "Auth", value: "X-API-Key", mono: false)
                FieldRow(key: "Writes", value: "none", mono: false)
                FieldRow(key: "Firewalls", value: "\(store.registry.servers.count)", mono: false)
                Text("Not affiliated with Netgate or the Catppuccin project. pfSense is a trademark of Netgate.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.labelFaint)
            }
        }
    }
}

/// One card in the theme grid. Auto renders in whichever theme is currently
/// resolved, so the card previews what you would actually get.
struct ThemeSwatch: View {
    @EnvironmentObject private var theme: ThemeManager
    let selection: ThemeManager.Selection
    let resolved: Theme
    let isSelected: Bool

    private var previewed: Theme {
        if case .fixed(let t) = selection { return t }
        return resolved
    }

    var body: some View {
        let p = previewed.palette
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                if case .auto = selection {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 11))
                        .foregroundStyle(p.subtext0)
                }
                Text(selection.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(p.text)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(p.green)
                }
            }
            HStack(spacing: 4) {
                ForEach([p.red, p.peach, p.yellow, p.green, p.sapphire, p.mauve], id: \.self) { c in
                    Capsule().fill(c).frame(height: 8)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.base)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? theme.accentColor : p.surface1,
                              lineWidth: isSelected ? 2 : 1)
        )
    }
}
