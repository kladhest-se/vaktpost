import Foundation

/// Central configuration for all health threshold values. Both the alert
/// builder and the overview meter read from this so the UI and alerts never
/// disagree about when a condition becomes a warning or a critical alert.
enum HealthThresholds {
    // CPU
    static let cpuWarn: Double = 70
    static let cpuBad: Double = 90

    // Memory
    static let memWarn: Double = 80
    static let memBad: Double = 92

    // Disk
    static let diskWarn: Double = 80
    static let diskBad: Double = 92

    // Swap
    static let swapWarn: Double = 25
    static let swapBad: Double = 60

    // mbuf
    static let mbufWarn: Double = 75
    static let mbufBad: Double = 90

    // Temperature
    static let tempWarn: Double = 70
    static let tempBad: Double = 85

    // State table (fraction 0–1)
    static let stateWarn: Double = 0.75
    static let stateBad: Double = 0.90
}

/// A derived condition worth surfacing. Nothing here comes from an alerts
/// endpoint — pfSense has none. Each item is computed from state the dashboard
/// already fetched, which means the rules live in one readable place rather
/// than being scattered as red text across cards.
struct VaktpostAlert: Identifiable {
    enum Category: String, CaseIterable {
        // Sensors is its own kind rather than part of capacity.
        //
        // A temperature reading is not a resource filling up, and folding it
        // into capacity meant somebody who wanted to stop hearing about a warm
        // chipset had to silence disk and memory warnings with it.
        case gateway, service, system, certificate, update, capacity, sensor, ha, vpn, connection

        var displayName: String {
            switch self {
            case .sensor: return "Sensors"
            case .gateway: return "Gateways"
            case .service: return "Services"
            case .system: return "System notices"
            case .certificate: return "Certificates"
            case .update: return "Updates"
            case .capacity: return "Capacity"
            case .ha: return "High availability"
            case .vpn: return "VPN"
            case .connection: return "Connection"
            }
        }

        var symbol: String {
            switch self {
            case .gateway: return "arrow.triangle.branch"
            case .service: return "gearshape.2"
            case .system: return "cpu"
            case .certificate: return "lock.doc"
            case .update: return "arrow.down.circle"
            case .capacity: return "gauge.with.dots.needle.67percent"
            case .sensor: return "thermometer.medium"
            case .ha: return "arrow.left.arrow.right"
            case .vpn: return "lock.shield"
            case .connection: return "antenna.radiowaves.left.and.right.slash"
            }
        }
    }

    let id = UUID()

    var severity: Health
    var category: Category
    var title: String
    var detail: String

    /// What distinguishes this alert from others of its kind, when the title
    /// alone cannot.
    ///
    /// Needed where the identifier is a bare number: "CARP VHID 1 backup" and
    /// "CARP VHID 2 backup" differ only by a digit that the signature drops as
    /// a measurement. Two different virtual IPs, one acknowledgement.
    var key: String? = nil

    /// A stable identity for acknowledgement, ignoring the numbers.
    ///
    /// "Chipset at 81 °C" and "Chipset at 83 °C" are the same condition told
    /// twice. Acknowledging by exact title would mean re-acknowledging on
    /// every degree, which is worse than not offering it — so digits are
    /// stripped and the category kept, giving `capacity:Chipset at  °C`.
    ///
    /// Severity is part of it deliberately: acknowledging a warning should not
    /// silence the same condition when it becomes critical. Something you
    /// decided to live with at 81° is not something you decided to live with
    /// at 105°.
    var signature: String {
        // Only whole numeric words are dropped, not every digit.
        //
        // Stripping all digits turned "WAN_DHCP is down" and "WAN2_DHCP is
        // down" into the same string, so acknowledging one gateway silenced
        // the other — which is the opposite of what acknowledging is for. A
        // digit inside an identifier is part of its name; a word that is only
        // a number is a measurement.
        let normalised = title
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { word -> Substring in
                word.first?.isNumber == true ? "" : word
            }
            .joined(separator: " ")
        return "\(category.rawValue):\(severity.name):\(key ?? ""):\(normalised)"
    }

    @MainActor
    static func build(from store: DashboardStore) -> [VaktpostAlert] {
        var out: [VaktpostAlert] = []

        if let msg = store.connectionError {
            out.append(.init(severity: .bad, category: .connection,
                             title: "Cannot reach firewall", detail: msg))
        }

        for gw in store.gateways where gw.health != .ok && gw.health != .idle {
            out.append(.init(
                severity: gw.health,
                category: .gateway,
                title: "Gateway \(gw.name) \(gw.status)",
                detail: gw.readout
            ))
        }

        for svc in store.servicesDown {
            out.append(.init(severity: .bad, category: .service,
                             title: "\(svc.descr ?? svc.name) not running",
                             detail: "Service is enabled but reported as \(svc.status.isEmpty ? "stopped" : svc.status)."))
        }

        if let sys = store.system {
            if let disk = sys.diskUsage, disk >= HealthThresholds.diskWarn {
                out.append(.init(severity: disk >= HealthThresholds.diskBad ? .bad : .warn, category: .capacity,
                                 title: "Disk at \(Fmt.pct(disk))",
                                 detail: "Log rotation or a large package cache is the usual cause."))
            }
            if let mem = sys.memUsage, mem >= HealthThresholds.memWarn {
                out.append(.init(severity: .warn, category: .capacity,
                                 title: "Memory at \(Fmt.pct(mem))", detail: "Sustained pressure may push the box into swap."))
            }
            if let swap = sys.swapUsage, swap >= HealthThresholds.swapWarn {
                out.append(.init(severity: .warn, category: .capacity,
                                 title: "Swap in use (\(Fmt.pct(swap)))",
                                 detail: "A firewall that swaps is usually one that will drop packets under load."))
            }
            // Thresholds follow the sensor, not a single pair of numbers.
            //
            // A chipset sits in the eighties under normal load; a CPU die at
            // the same temperature is worth looking at. One pair for both made
            // a healthy PCH raise a permanent warning nobody could act on,
            // which is how an alert list stops being read.
            // An explicit setting wins over the sensor-derived guess. The
            // critical point moves with it, staying ten degrees above, so a
            // person lowering the warning does not silently lose the
            // distinction between warm and serious.
            var tempLimits = sys.temperatureThresholds
            if let warn = store.temperatureWarnOverride {
                tempLimits = (warn: warn, bad: max(warn + 10, tempLimits.bad))
            }
            if let temp = sys.temperature, temp >= tempLimits.warn {
                out.append(.init(
                    severity: temp >= tempLimits.bad ? .bad : .warn,
                    category: .sensor,
                    title: String(format: "%@ at %.0f °C", sys.temperatureLabel, temp),
                    detail: temp >= tempLimits.bad
                        ? "Thermal throttling territory. Check airflow and fan health."
                        : "Warm for this sensor. Worth watching if it climbs."
                ))
            }
            if let mbuf = sys.mbufUsage, mbuf >= HealthThresholds.mbufWarn {
                out.append(.init(severity: mbuf >= HealthThresholds.mbufBad ? .bad : .warn, category: .capacity,
                                 title: "mbuf at \(Fmt.pct(mbuf))",
                                 detail: "Raise kern.ipc.nmbclusters if this stays high."))
            }
        }

        if let st = store.states, let frac = st.fraction, frac >= HealthThresholds.stateWarn {
            out.append(.init(severity: frac >= HealthThresholds.stateBad ? .bad : .warn, category: .capacity,
                             title: "State table \(Fmt.pct(frac * 100)) full",
                             detail: "\(st.current ?? 0) of \(st.maximum ?? 0) states."))
        }

        if store.version?.updateAvailable == true {
            let latest = store.version?.latest ?? "a newer release"
            out.append(.init(severity: .warn, category: .update,
                             title: "Update available",
                             detail: "Running \(store.version?.current ?? "?"), \(latest) is available."))
        }

        // The firewall's own notices, one alert each.
        for notice in store.criticalNotices where !notice.isFromThisApp {
            out.append(.init(
                severity: notice.health,
                category: .system,
                title: notice.summary.isEmpty ? "System notice" : notice.summary,
                detail: notice.displayTime
            ))
        }

        // The app's own failures, collapsed into one.
        //
        // A failing snippet writes a notice on every refresh, so within an hour
        // the badge read 50 and every entry was the same PHP error. That buries
        // the gateway or certificate alert somebody actually needs to see, and
        // an app that floods its own alert list with its own bugs is worse than
        // one that stays quiet about them.
        // Only recent ones, and only as one alert.
        //
        // Notices persist on the firewall until somebody clears them, so a bug
        // fixed twenty minutes ago still has eighty entries sitting in the log.
        // Reporting those as "a snippet is failing" is false: nothing is
        // failing now. The whole history stays visible under System → Notices,
        // where it belongs; only something that failed in the last quarter of
        // an hour is worth an alert.
        let ours = store.criticalNotices.filter(\.isFromThisApp)
        let recent = ours.filter { notice in
            guard let when = notice.date else { return true }   // undated: assume current
            return Date().timeIntervalSince(when) < 900
        }
        if let latest = recent.first {
            let historical = ours.count - recent.count
            out.append(.init(
                severity: .warn,
                category: .system,
                title: recent.count == 1
                    ? "A Vaktpost snippet is failing"
                    : "A Vaktpost snippet is failing (\(recent.count) times recently)",
                detail: historical > 0
                    ? "\(latest.summary) — plus \(historical) older notices from failures already fixed. Clear them from the bell icon in the webConfigurator."
                    : "\(latest.summary) — these accumulate on the firewall. Clear them from the bell icon once fixed."
            ))
        } else if ours.count >= 10 {
            // Nothing failing now, but the log is full of what used to.
            out.append(.init(
                severity: .info,
                category: .system,
                title: "\(ours.count) old Vaktpost notices on the firewall",
                detail: "Nothing has failed in the last 15 minutes. Clear these from the bell icon in the webConfigurator."
            ))
        }

        for fs in store.fullFilesystems {
            out.append(.init(
                severity: fs.health,
                category: .capacity,
                title: "\(fs.mountpoint) at \(Fmt.pct(fs.percentUsed ?? 0))",
                detail: "A full filesystem stops logging long before it stops routing."
            ))
        }

        for entry in store.staleDyndns {
            out.append(.init(
                severity: .warn,
                category: .system,
                title: "\(entry.displayName) may be stale",
                detail: "Last pushed \(entry.cachedAddress ?? "?") on \(entry.updatedDescription); the interface has a different address now."
            ))
        }

        let stale = store.packagesNeedingUpdate
        if !stale.isEmpty {
            out.append(.init(
                severity: .warn,
                category: .update,
                title: stale.count == 1
                    ? "\(stale[0].shortName) has an update"
                    : "\(stale.count) packages have updates",
                detail: stale.map(\.shortName).sorted().joined(separator: ", ")
            ))
        }

        for cert in store.certificates where cert.health == .bad || cert.health == .warn {
            let days = cert.daysRemaining ?? 0
            out.append(.init(
                severity: cert.health,
                category: .certificate,
                title: days < 0 ? "\(cert.descr) expired" : "\(cert.descr) expires in \(days)d",
                detail: cert.isCA ? "Certificate authority" : "Certificate"
            ))
        }

        if let carp = store.carp, carp.isConfigured {
            if carp.maintenanceMode == true {
                out.append(.init(severity: .warn, category: .ha,
                                 title: "CARP in maintenance mode",
                                 detail: "This node is deliberately demoted. Clear it when the work is done."))
            }
            for vip in carp.interfaces where vip.health == .bad {
                out.append(.init(severity: .bad, category: .ha,
                                 title: "CARP VHID \(vip.vhid) \(vip.status)",
                                 detail: "On \(vip.interfaceName).",
                                 key: "vhid-\(vip.vhid)"))
            }
        }

        for sa in store.ipsecSAs where sa.health == .bad {
            out.append(.init(severity: .bad, category: .vpn,
                             title: "IPsec \(sa.connectionName) down",
                             detail: "State: \(sa.state)"))
        }

        let order: [Health] = [.bad, .warn, .info, .ok, .idle]
        return out.sorted {
            (order.firstIndex(of: $0.severity) ?? 9) < (order.firstIndex(of: $1.severity) ?? 9)
        }
    }
}
