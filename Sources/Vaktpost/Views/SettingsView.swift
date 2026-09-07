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

                GroupHeading(text: "App icon")
                AppIconPicker()

                GroupHeading(text: "Alerts")
                alertsSlab

                GroupHeading(text: "Temperature")
                temperatureSlab

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





    /// Which conditions are worth being told about.
    ///
    /// Alerts are derived on the device, so silencing changes what is shown
    /// rather than what is measured — everything stays visible on the Alerts
    /// screen, it just stops driving the badge and the Overview banner.
    private var alertsSlab: some View {
        Slab(rail: .info) {
            VStack(alignment: .leading, spacing: 10) {
                // Phrased as "show", not "silence".
                //
                // A row of switches under "silence individual kinds" is on when
                // the thing is silenced, which means a default of everything
                // enabled looks like a screen full of off switches — and a
                // screen full of off switches reads as "nothing is working".
                // Turning something on to receive it is the direction people
                // expect, and it makes the default state look like the default.
                Toggle(isOn: Binding(
                    get: { !store.alertsSilenced },
                    set: { store.alertsSilenced = !$0 }
                )) {
                    Text("Show alerts")
                        .scaledFont(14)
                        .foregroundStyle(theme.label)
                }
                .tint(theme.accentColor)

                if !store.alertsSilenced {
                    Hairline()
                    Text("Kinds to show")
                        .scaledFont(12)
                        .foregroundStyle(theme.labelMuted)

                    ForEach(VaktpostAlert.Category.allCases, id: \.rawValue) { category in
                        Toggle(isOn: Binding(
                            get: { !store.mutedAlertCategories.contains(category.rawValue) },
                            set: { shown in
                                if shown { store.mutedAlertCategories.remove(category.rawValue) }
                                else { store.mutedAlertCategories.insert(category.rawValue) }
                            }
                        )) {
                            HStack(spacing: 8) {
                                Image(systemName: category.symbol)
                                    .scaledFont(12)
                                    .foregroundStyle(theme.labelMuted)
                                    .scaledFrame(width: 18)
                                Text(category.displayName)
                                    .scaledFont(13)
                                    .foregroundStyle(theme.label)
                            }
                        }
                        .tint(theme.accentColor)
                    }
                }
            }
        }
    }

    /// Where the temperature alert fires.
    ///
    /// The default follows the sensor — a chipset runs far hotter than a CPU
    /// die — but those numbers are a guess about hardware the app cannot see.
    private var temperatureSlab: some View {
        Slab(rail: .info) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Warn above")
                        .scaledFont(14)
                        .foregroundStyle(theme.label)
                    Spacer()
                    Text(store.temperatureWarnOverride
                            .map { String(format: "%.0f °C", $0) } ?? "automatic")
                        .scaledFont(14, design: .monospaced)
                        .foregroundStyle(theme.labelMuted)
                }

                Slider(
                    value: Binding(
                        get: { store.temperatureWarnOverride ?? 0 },
                        set: { store.temperatureWarnOverride = $0 < 50 ? nil : $0 }
                    ),
                    in: 40...110,
                    step: 1
                )
                .tint(theme.accentColor)

                Text(store.temperatureWarnOverride == nil
                     ? "Following the sensor: \(sensorDescription). Slide up to set your own."
                     : "Critical at \(Int((store.temperatureWarnOverride ?? 0) + 10)) °C. Slide below 50 to go back to automatic.")
                    .scaledFont(11)
                    .foregroundStyle(theme.labelFaint)
            }
        }
    }

    private var sensorDescription: String {
        guard let sys = store.system else { return "no reading yet" }
        let limits = sys.temperatureThresholds
        return "\(sys.temperatureLabel.lowercased()), warn at \(Int(limits.warn)) °C"
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
                     : "\(theme.current.displayName), whatever iOS is set to.")
                    .scaledFont(12)
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
                Text("A read-only dashboard for pfSense CE and Plus, talking to the firewall's built-in XML-RPC service. Nothing to install.")
                    .scaledFont(13)
                    .foregroundStyle(theme.labelMuted)
                Hairline()
                FieldRow(key: "Transport", value: "xmlrpc.php", mono: false)
                FieldRow(key: "Auth", value: "webConfigurator login", mono: false)
                FieldRow(key: "Privilege", value: "System - HA node sync", mono: false)
                FieldRow(key: "Writes", value: "none", mono: false)
                FieldRow(key: "Firewalls", value: "\(store.registry.servers.count)", mono: false)
                Text("Not affiliated with Netgate or the Catppuccin project. pfSense is a trademark of Netgate.")
                    .scaledFont(11)
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
                        .scaledFont(11)
                        .foregroundStyle(p.subtext0)
                }
                Text(selection.displayName)
                    .scaledFont(13, weight: .semibold)
                    .foregroundStyle(p.text)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .scaledFont(13)
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
