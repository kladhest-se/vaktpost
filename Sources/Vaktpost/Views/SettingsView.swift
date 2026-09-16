import SwiftUI

struct SettingsView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore

    /// How many expiry notifications are pending, or nil while counting.
    @State private var pending: Int?

    var body: some View {
        ScrollView {
            PageHeader(title: "Settings", subtitle: nil)
            VStack(alignment: .leading, spacing: 14) {
                GroupHeading(text: "Appearance")
                themeSlab
                accentSlab

                GroupHeading(text: "App icon")
                AppIconPicker()

                GroupHeading(text: "Alerts")
                alertsSlab

                GroupHeading(text: "Notifications")
                notificationsSlab

                if BiometricAuth.canUseBiometrics() {
                    GroupHeading(text: "Lock screen")
                    lockScreenSlab
                }

                GroupHeading(text: "Configured firewalls")
                NavigationLink { ServersView() } label: {
                    Slab(rail: store.registry.persistenceError == nil ? .info : .bad) {
                        HStack(spacing: 10) {
                            Image(systemName: "server.rack")
                                .foregroundStyle(store.registry.persistenceError == nil
                                                 ? theme.info : theme.bad)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Firewall instances")
                                    .scaledFont(14, weight: .medium)
                                    .foregroundStyle(theme.label)
                                Text(store.registry.persistenceError
                                     ?? "Connection, certificate, refresh, and administration settings for each firewall")
                                    .scaledFont(11)
                                    .foregroundStyle(store.registry.persistenceError == nil
                                                     ? theme.labelFaint : theme.bad)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .scaledFont(11, weight: .semibold)
                                .foregroundStyle(theme.labelFaint)
                        }
                    }
                }
                .buttonStyle(.plain)

                GroupHeading(text: "Administration")
                Slab(rail: store.auditTrail.persistenceError == nil ? .info : .bad) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.shield")
                            .scaledFont(15)
                            .foregroundStyle(store.auditTrail.persistenceError == nil
                                             ? theme.info : theme.bad)
                            .scaledFrame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Administrative history")
                                .scaledFont(14, weight: .medium)
                                .foregroundStyle(theme.label)
                            Text(store.auditTrail.persistenceError == nil
                                 ? "\(store.auditTrail.entries.count) protected record\(store.auditTrail.entries.count == 1 ? "" : "s") for this firewall"
                                 : "Protected history is unavailable")
                                .scaledFont(11)
                                .foregroundStyle(store.auditTrail.persistenceError == nil
                                                 ? theme.labelFaint : theme.bad)
                        }
                        Spacer()
                        ShareLink(
                            item: store.auditTrail.redactedExport(),
                            preview: SharePreview("Redacted Vaktpost administrative history")
                        ) {
                            Image(systemName: "square.and.arrow.up")
                                .scaledFont(15)
                                .foregroundStyle(theme.accentColor)
                        }
                        .disabled(store.auditTrail.entries.isEmpty)
                    }
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
    /// The one alert this app can deliver while it is not running.
    ///
    /// Everything else on the Alerts screen is derived from status the app has
    /// to ask the firewall for, and an app that is not running cannot ask. A
    /// certificate is different: it says months in advance exactly when it
    /// will become a problem, so the notification can be scheduled for that
    /// date and arrives whether or not this app is ever opened again.
    private var notificationsSlab: some View {
        Slab(rail: .info) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: Binding(
                    get: { store.expiryNotifier.isEnabled },
                    set: { on in
                        store.expiryNotifier.isEnabled = on
                        guard on else { return }
                        Task {
                            // Asked here rather than at launch. A permission
                            // prompt on first run, before the app has shown
                            // what it would use it for, is the reliable way to
                            // be refused permanently.
                            await store.expiryNotifier.requestPermission()
                            store.scheduleExpiryNotifications()
                        }
                    }
                )) {
                    Text("Certificate expiry")
                        .scaledFont(14)
                        .foregroundStyle(theme.label)
                }
                .tint(theme.accentColor)

                Text("Scheduled 30, 14, 7, 3 and 1 days before a certificate expires, at 9am. Each notification names the firewall.")
                    .scaledFont(12)
                    .foregroundStyle(theme.labelMuted)

                if store.expiryNotifier.isEnabled, store.expiryNotifier.permission == .denied {
                    // A toggle that is on and does nothing is worse than one
                    // that is off. The app cannot re-ask once refused; only
                    // iOS Settings can grant it back.
                    Text("Notifications are turned off for Vaktpost in iOS Settings, so nothing will be delivered until they are turned back on there.")
                        .scaledFont(12)
                        .foregroundStyle(theme.warn)
                }

                if store.expiryNotifier.isEnabled, store.expiryNotifier.permission == .granted {
                    Hairline()
                    // A count says something is scheduled and nothing about
                    // whether it is still true. The list behind this is the
                    // only way to see what reconciling actually did.
                    NavigationLink {
                        ScheduledNotificationsView()
                    } label: {
                        HStack(spacing: 8) {
                            Text(pendingDescription)
                                .scaledFont(11, design: .monospaced)
                                .foregroundStyle(theme.labelFaint)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .scaledFont(10, weight: .semibold)
                                .foregroundStyle(theme.labelFaint)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task {
            await store.expiryNotifier.refreshPermission()
            pending = await store.expiryNotifier.pendingCount()
        }
    }

    private var pendingDescription: String {
        switch pending {
        case nil: return "Counting what is scheduled…"
        case 0: return "Nothing scheduled — no certificate on this firewall expires within 30 days."
        case 1: return "1 notification scheduled."
        default: return "\(pending ?? 0) notifications scheduled."
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
                    }
                }
            }
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

    private var aboutSlab: some View {
        Slab(rail: .info, title: "Vaktpost") {
            VStack(alignment: .leading, spacing: 8) {
                Text("A monitoring and administration app for pfSense CE and Plus, talking to the firewall's built-in XML-RPC service. Nothing to install.")
                    .scaledFont(13)
                    .foregroundStyle(theme.labelMuted)
                Hairline()
                FieldRow(key: "Transport", value: "xmlrpc.php", mono: false)
                FieldRow(key: "Auth", value: "webConfigurator login", mono: false)
                FieldRow(key: "Privilege", value: "System - HA node sync", mono: false)
                FieldRow(key: "Active mode", value: store.canAdminister ? "administration enabled" : "monitor only", mono: false)
                FieldRow(key: "Writes", value: "confirmed admin actions", mono: false)
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
