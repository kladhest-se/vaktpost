import SwiftUI

struct SettingsView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore

    var body: some View {
        ScrollView {
            PageHeader(title: "Settings", subtitle: nil)
            VStack(alignment: .leading, spacing: 14) {
                GroupHeading(text: "Appearance")
                themeSlab
                accentSlab

                // An iPad app on a Mac keeps the icon it was installed with;
                // `supportsAlternateIcons` is false there, so the picker could
                // only ever report failure.
                if !Platform.isMac {
                    GroupHeading(text: "App icon")
                    AppIconPicker()
                }

                GroupHeading(text: "Alerts")
                alertsSlab

                if BiometricAuth.canUseBiometrics() {
                    GroupHeading(text: "Lock screen")
                    lockScreenSlab
                }

                GroupHeading(text: "Diagnostics")
                NavigationLink { DiagnosticsView() } label: {
                    Slab(rail: store.errors.isEmpty ? .idle : .warn) {
                        HStack(spacing: 10) {
                            Image(systemName: store.errors.isEmpty
                                  ? "stethoscope" : "stethoscope.circle.fill")
                                .scaledFont(15)
                                .foregroundStyle(store.errors.isEmpty
                                                 ? theme.labelMuted : theme.warn)
                                .scaledFrame(width: 22)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Diagnostics")
                                    .scaledFont(14, weight: .medium)
                                    .foregroundStyle(theme.label)
                                // The count here rather than on a toolbar
                                // icon: this is a screen somebody visits when
                                // something looks wrong, not a thing to watch.
                                Text(store.errors.isEmpty
                                     ? "Everything is answering"
                                     : "\(store.errors.count) section\(store.errors.count == 1 ? "" : "s") failing")
                                    .scaledFont(11)
                                    .foregroundStyle(store.errors.isEmpty
                                                     ? theme.labelFaint : theme.warn)
                            }

                            Spacer()
                            Image(systemName: "chevron.right")
                                .scaledFont(11, weight: .semibold)
                                .foregroundStyle(theme.labelFaint)
                        }
                    }
                }
                .buttonStyle(.plain)

                GroupHeading(text: "About")
                aboutSlab
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(theme.bg.ignoresSafeArea())
    }

    /// Which conditions are worth being told about.
    ///
    /// Alerts are derived on the device, so silencing changes what is shown
    /// rather than what is measured — everything stays visible on the Alerts
    /// screen, it just stops driving the badge and the Overview banner.
    /// Certificate expiry warnings follow the Certificates alert.
    ///
    /// Everything else on the Alerts screen is derived from status the app has
    /// to ask the firewall for, and an app that is not running cannot ask. A
    /// certificate is different: it says months in advance exactly when it
    /// will become a problem, so the warning can be scheduled — 30, 14, 7, 3
    /// and 1 days ahead, at 9am — and arrives whether or not this app is ever
    /// opened again. That is the same thing the alert itself is for, so it is
    /// the same switch rather than a second one to find.
    ///
    /// Permission is asked for here, the first time somebody turns the alert
    /// on, rather than at launch: a prompt on first run, before the app has
    /// shown what it would use it for, is the reliable way to be refused
    /// permanently.
    private func setExpiryNotifications(_ enabled: Bool) {
        store.expiryNotifier.isEnabled = enabled
        Task {
            if enabled {
                await store.expiryNotifier.requestPermission()
                store.scheduleExpiryNotifications()
            } else {
                await store.expiryNotifier.refreshPermission()
            }
        }
    }

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
                    get: { !store.alertManager.alertsSilenced },
                    set: { store.alertManager.alertsSilenced = !$0 }
                )) {
                    Text("Show alerts")
                        .scaledFont(14)
                        .foregroundStyle(theme.label)
                }
                .tint(theme.accentColor)

                if !store.alertManager.alertsSilenced {
                    Hairline()
                    Text("Kinds of alerts")
                        .scaledFont(12)
                        .foregroundStyle(theme.labelMuted)

                    // Sensors is one of these now, with no special treatment.
                    //
                    // It had its own heading and a slider, which made a
                    // temperature threshold look like a different class of
                    // setting from the switches under it. The threshold has not
                    // gone: it is a long press on the row, which is where iOS
                    // puts a secondary choice and costs nothing to leave there.
                    ForEach(VaktpostAlert.Category.allCases, id: \.rawValue) { category in
                        Toggle(isOn: Binding(
                            get: { !store.alertManager.mutedAlertCategories.contains(category.rawValue) },
                            set: { shown in
                                if shown { store.alertManager.mutedAlertCategories.remove(category.rawValue) }
                                else { store.alertManager.mutedAlertCategories.insert(category.rawValue) }
                                if category == .certificate { setExpiryNotifications(shown) }
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
                        .contextMenu {
                            if category == .sensor { temperatureMenu }
                            if category == .capacity { capacityMenus }
                        }

                        // The only alert that can arrive while the app is not
                        // running, and the only one that needs iOS to agree.
                        // Said once, and only when iOS has refused, because a
                        // switch that is on and delivers nothing is worse
                        // than one that is off.
                        if category == .certificate,
                           !store.alertManager.mutedAlertCategories.contains(category.rawValue),
                           store.expiryNotifier.permission == .denied {
                            Text("Notifications are turned off for Vaktpost in iOS Settings, "
                                 + "so expiry warnings will not be delivered until they are turned back on there.")
                                .scaledFont(11)
                                .foregroundStyle(theme.warn)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        // The Certificates alert is on by default, so a fresh install would
        // otherwise never reach the code that turns scheduling on. Asked here,
        // where the person is looking at alert settings, and only once: iOS
        // prompts for notification permission a single time.
        .task {
            await store.expiryNotifier.refreshPermission()
            let wanted = !store.alertManager.mutedAlertCategories.contains(
                VaktpostAlert.Category.certificate.rawValue)
            guard wanted != store.expiryNotifier.isEnabled else { return }
            setExpiryNotifications(wanted)
        }
    }

    /// Six nested submenus under the Capacity row's long press: CPU, Memory,
    /// Disk, Swap, mbuf, and the state table. One shared row, because
    /// `.capacity` is one alert category covering five different alerts —
    /// CPU makes six, despite having no alert of its own to attach to,
    /// since it is the same kind of number as the other five and the meter
    /// on Overview reads the same override.
    @ViewBuilder
    private var capacityMenus: some View {
        thresholdMenu("CPU usage", current: store.alertManager.cpuWarnOverride, options: [50, 60, 70, 80, 90]) {
            store.alertManager.cpuWarnOverride = $0
        }
        thresholdMenu("Memory", current: store.alertManager.memWarnOverride, options: [60, 70, 80, 90]) {
            store.alertManager.memWarnOverride = $0
        }
        thresholdMenu("Disk", current: store.alertManager.diskWarnOverride, options: [60, 70, 80, 90]) {
            store.alertManager.diskWarnOverride = $0
        }
        thresholdMenu("Swap", current: store.alertManager.swapWarnOverride, options: [10, 25, 40, 60]) {
            store.alertManager.swapWarnOverride = $0
        }
        thresholdMenu("mbuf", current: store.alertManager.mbufWarnOverride, options: [50, 60, 75, 85]) {
            store.alertManager.mbufWarnOverride = $0
        }
        // Stored as a fraction (0–1), matching HealthThresholds.stateWarn and
        // the state table's own `fraction` — only this one needs the ×100/÷100
        // conversion at the boundary, since it's the only overridable
        // threshold not already stored the same way it's displayed.
        thresholdMenu("State table", current: store.alertManager.stateWarnOverride.map { $0 * 100 },
                      options: [50, 65, 75, 85]) {
            store.alertManager.stateWarnOverride = $0.map { $0 / 100 }
        }
    }

    /// One row's worth of "Automatic" plus a handful of round percentage
    /// steps, as a submenu — the same fixed-steps-not-a-slider shape
    /// `temperatureMenu` already uses, generalized so the other six
    /// thresholds don't each need their own copy of it.
    @ViewBuilder
    private func thresholdMenu(_ title: String, current: Double?, options: [Int],
                               set: @escaping (Double?) -> Void) -> some View {
        Menu(title) {
            Button {
                set(nil)
            } label: {
                if current == nil {
                    Label("Automatic", systemImage: "checkmark")
                } else {
                    Text("Automatic")
                }
            }
            ForEach(options, id: \.self) { percent in
                Button {
                    set(Double(percent))
                } label: {
                    if Int(current ?? -1) == percent {
                        Label("Warn at \(percent)%", systemImage: "checkmark")
                    } else {
                        Text("Warn at \(percent)%")
                    }
                }
            }
        }
    }

    /// Where the temperature alert fires, as a menu on the Sensors row.
    ///
    /// Fixed steps rather than a slider: the useful answers are "follow the
    /// sensor" and a handful of round numbers, and a slider asked somebody to
    /// aim for one of them.
    @ViewBuilder
    private var temperatureMenu: some View {
        Button {
            store.alertManager.temperatureWarnOverride = nil
        } label: {
            Label("Automatic", systemImage: store.alertManager.temperatureWarnOverride == nil
                  ? "checkmark" : "thermometer.medium")
        }
        ForEach([70, 75, 80, 85, 90, 95], id: \.self) { degrees in
            Button {
                store.alertManager.temperatureWarnOverride = Double(degrees)
            } label: {
                if Int(store.alertManager.temperatureWarnOverride ?? -1) == degrees {
                    Label("Warn at \(degrees) °C", systemImage: "checkmark")
                } else {
                    Text("Warn at \(degrees) °C")
                }
            }
        }
    }

    private var lockScreenSlab: some View {
        Slab(rail: .info) {
            Toggle(isOn: Binding(
                get: { BiometricAuth.isEnabled },
                set: { BiometricAuth.isEnabled = $0 }
            )) {
                Text("Require Face ID / Touch ID")
                    .scaledFont(14)
                    .foregroundStyle(theme.label)
            }
            .tint(theme.accentColor)
        }
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

    /// "1.0.0 (12)", from the bundle rather than a constant, so it cannot
    /// describe a build other than the one running.
    private static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    private var aboutSlab: some View {
        Slab(rail: .info, title: "Vaktpost") {
            VStack(alignment: .leading, spacing: 8) {
                Text("A monitoring and administration app for pfSense CE and Plus, talking to the firewall's built-in XML-RPC service. Nothing to install.")
                    .scaledFont(13)
                    .foregroundStyle(theme.labelMuted)
                Hairline()
                // The build number belongs next to the version: it is what a
                // bug report needs in order to name one particular build, and
                // the only place it is otherwise visible is App Store Connect.
                FieldRow(key: "Version", value: Self.versionLine, mono: false)
                FieldRow(key: "Made by", value: "Tommy Frössman", mono: false)
                FieldRow(key: "Website", value: "vaktpost.kladhest.se", mono: false)
                FieldRow(key: "Licence", value: "GPL-3.0-or-later", mono: false)
                Hairline()
                FieldRow(key: "Transport", value: "xmlrpc.php", mono: false)
                FieldRow(key: "Auth", value: "webConfigurator login", mono: false)
                FieldRow(key: "Privilege", value: "System - HA node sync", mono: false)
                FieldRow(key: "Active mode", value: store.canAdminister ? "administration enabled" : "monitor only", mono: false)
                FieldRow(key: "Writes", value: "confirmed admin actions", mono: false)
                FieldRow(key: "Firewalls", value: "\(store.registry.servers.count)", mono: false)
                Hairline()
                Link(destination: URL(string: "https://vaktpost.kladhest.se")!) {
                    HStack(spacing: 6) {
                        Text("Project website and source")
                            .scaledFont(12, weight: .semibold)
                        Image(systemName: "arrow.up.right")
                            .scaledFont(10, weight: .semibold)
                    }
                    .foregroundStyle(theme.accentColor)
                }
                .accessibilityLabel("Open the project website")
                Text("Free software under the GNU General Public License, version 3 or later. "
                     + "Not affiliated with Netgate or the Catppuccin project. pfSense is a "
                     + "trademark of Netgate.")
                    .scaledFont(11)
                    .foregroundStyle(theme.labelFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One card in the theme grid. Auto renders in whichever theme is currently
/// resolved, so the card previews what you would actually get.
struct ThemeSwatch: View {
    @Environment(\.themeManager) private var theme: ThemeManager
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
