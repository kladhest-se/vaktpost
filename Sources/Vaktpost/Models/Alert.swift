import Foundation

/// A derived condition worth surfacing. Nothing here comes from an alerts
/// endpoint — pfSense has none. Each item is computed from state the dashboard
/// already fetched, which means the rules live in one readable place rather
/// than being scattered as red text across cards.
struct VaktpostAlert: Identifiable {
    enum Category: String {
        case gateway, service, system, certificate, update, capacity, ha, vpn, connection

        var symbol: String {
            switch self {
            case .gateway: return "arrow.triangle.branch"
            case .service: return "gearshape.2"
            case .system: return "cpu"
            case .certificate: return "lock.doc"
            case .update: return "arrow.down.circle"
            case .capacity: return "gauge.with.dots.needle.67percent"
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
            if let disk = sys.diskUsage, disk >= 85 {
                out.append(.init(severity: disk >= 92 ? .bad : .warn, category: .capacity,
                                 title: "Disk at \(Fmt.pct(disk))",
                                 detail: "Log rotation or a large package cache is the usual cause."))
            }
            if let mem = sys.memUsage, mem >= 90 {
                out.append(.init(severity: .warn, category: .capacity,
                                 title: "Memory at \(Fmt.pct(mem))", detail: "Sustained pressure may push the box into swap."))
            }
            if let swap = sys.swapUsage, swap >= 25 {
                out.append(.init(severity: .warn, category: .capacity,
                                 title: "Swap in use (\(Fmt.pct(swap)))",
                                 detail: "A firewall that swaps is usually one that will drop packets under load."))
            }
            if let mbuf = sys.mbufUsage, mbuf >= 80 {
                out.append(.init(severity: mbuf >= 90 ? .bad : .warn, category: .capacity,
                                 title: "mbuf at \(Fmt.pct(mbuf))",
                                 detail: "Raise kern.ipc.nmbclusters if this stays high."))
            }
        }

        if let st = store.states, let frac = st.fraction, frac >= 0.75 {
            out.append(.init(severity: frac >= 0.9 ? .bad : .warn, category: .capacity,
                             title: "State table \(Fmt.pct(frac * 100)) full",
                             detail: "\(st.current ?? 0) of \(st.maximum ?? 0) states."))
        }

        if store.version?.updateAvailable == true {
            let latest = store.version?.latest ?? "a newer release"
            out.append(.init(severity: .warn, category: .update,
                             title: "Update available",
                             detail: "Running \(store.version?.current ?? "?"), \(latest) is available."))
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
                                 detail: "On \(vip.interfaceName)."))
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
