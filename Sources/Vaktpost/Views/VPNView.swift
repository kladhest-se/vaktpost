import SwiftUI

/// VPN, split by technology.
///
/// One scroll containing OpenVPN servers, OpenVPN clients, IPsec and WireGuard
/// meant four unrelated things stacked vertically, and on a firewall running
/// two of them you scrolled past the one you wanted. A picker puts each on its
/// own page and shows only the technologies this firewall actually runs — a
/// tab for something you do not use is a tab you learn to skip.
struct VPNView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore

    @State private var pane: Pane?

    enum Pane: String, CaseIterable, Identifiable {
        case openvpn = "OpenVPN", wireguard = "WireGuard", ipsec = "IPsec"
        var id: String { rawValue }
    }

    /// Only what is configured. A firewall with no IPsec should not have an
    /// IPsec tab that is permanently empty.
    private var available: [Pane] {
        var out: [Pane] = []
        if !store.openvpnServers.isEmpty || !store.openvpnClients.isEmpty { out.append(.openvpn) }
        if !store.wireguardTunnels.isEmpty { out.append(.wireguard) }
        if !store.ipsecSAs.isEmpty { out.append(.ipsec) }
        return out
    }

    private var selection: Pane { pane ?? available.first ?? .openvpn }

    var body: some View {
        VStack(spacing: 0) {
            if available.count > 1 {
                Picker("", selection: Binding(
                    get: { selection },
                    set: { pane = $0 }
                )) {
                    ForEach(available) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    FreshnessView(sections: [.openvpn, .openvpnClients, .ipsec, .wireguard], showNames: true)
                    if available.isEmpty {
                        Notice(
                            symbol: "lock.open",
                            title: "No VPN configured",
                            detail: "No OpenVPN instances, WireGuard tunnels or IPsec associations were reported."
                        )
                    } else {
                        switch selection {
                        case .openvpn: openvpnPane
                        case .wireguard: wireguardPane
                        case .ipsec: ipsecPane
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, available.count > 1 ? 0 : 12)
                .padding(.bottom, 28)
            .readableWidth()
            }
            .refreshable { await store.refreshManually() }
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("VPN")
    }

    @ViewBuilder
    private var openvpnPane: some View {
        ForEach(store.openvpnServers) { srv in
            OpenVPNCard(server: srv, vpnThroughput: store.vpnThroughput)
        }
        if !store.openvpnClients.isEmpty {
            GroupHeading(text: "Client instances")
            ForEach(store.openvpnClients) { srv in
                OpenVPNCard(server: srv, vpnThroughput: store.vpnThroughput)
            }
        }
    }

    private var wireguardPane: some View {
        ForEach(store.wireguardTunnels) { tunnel in
            WireGuardCard(
                tunnel: tunnel,
                peers: store.wireguardPeers.filter { $0.tunnel == tunnel.name },
                vpnThroughput: store.vpnThroughput
            )
        }
    }

    private var ipsecPane: some View {
        ForEach(store.ipsecSAs) { IPsecCard(sa: $0) }
    }
}

/// One OpenVPN instance, as a row.
///
/// The peer list moved to its own screen. Four servers each listing their
/// connections made the VPN tab a wall of addresses and byte counts, and the
/// question it is usually opened to answer — is everything up, how many are on
/// — was buried inside it. The count is the summary; the detail is a tap away.
struct OpenVPNCard: View {
    @EnvironmentObject private var theme: ThemeManager
    let server: OpenVPNServerStatus
    @ObservedObject var vpnThroughput: ThroughputTracker

    var body: some View {
        NavigationLink {
            OpenVPNDetailView(server: server, vpnThroughput: vpnThroughput)
        } label: {
            Slab(rail: server.health, trailing: server.modeLabel) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(server.name)
                            .scaledFont(15, weight: .semibold)
                            .foregroundStyle(theme.label)
                        Spacer(minLength: 8)
                        StatusPill(text: server.statusLabel, health: server.health)
                    }
                    if !server.connections.isEmpty {
                        HStack {
                            Text(server.connections.count == 1
                                 ? "1 client connected"
                                 : "\(server.connections.count) clients connected")
                                .scaledFont(12)
                                .foregroundStyle(theme.labelMuted)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .scaledFont(11, weight: .semibold)
                                .foregroundStyle(theme.labelFaint)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// The peers of one OpenVPN instance.
struct OpenVPNDetailView: View {
    @EnvironmentObject private var theme: ThemeManager
    let server: OpenVPNServerStatus
    @ObservedObject var vpnThroughput: ThroughputTracker

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Slab(rail: server.health, trailing: server.modeLabel) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(server.name)
                                .scaledFont(15, weight: .semibold)
                                .foregroundStyle(theme.label)
                            Spacer()
                            StatusPill(text: server.statusLabel, health: server.health)
                        }
                        if let port = server.port, !port.isEmpty {
                            FieldRow(key: "Port", value: port)
                        }
                    }
                }

                if server.connections.isEmpty {
                    Notice(symbol: "person.slash", title: "No clients connected")
                } else {
                    GroupHeading(text: "Connected clients")
                    ForEach(server.connections) { conn in
                        Slab(rail: .ok) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(conn.commonName)
                                        .scaledFont(14, weight: .semibold)
                                        .foregroundStyle(theme.label)
                                    Spacer()
                                    Text(conn.virtualAddress ?? "")
                                        .scaledFont(12, design: .monospaced)
                                        .foregroundStyle(theme.labelMuted)
                                }
                                Text(conn.remoteHost)
                                    .scaledFont(11, design: .monospaced)
                                    .foregroundStyle(theme.labelFaint)
                                    .textSelection(.enabled)
                                if let rx = conn.bytesReceived, let tx = conn.bytesSent {
                                    Text("↓\(Fmt.bytes(rx))  ↑\(Fmt.bytes(tx))")
                                        .scaledFont(11, design: .monospaced)
                                        .foregroundStyle(theme.labelFaint)
                                }
                                if let seen = server.lastSeen(for: conn.commonName), !seen.isEmpty {
                                    Text("route since \(seen)")
                                        .scaledFont(10, design: .monospaced)
                                        .foregroundStyle(theme.labelFaint)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle(server.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct IPsecCard: View {
    @EnvironmentObject private var theme: ThemeManager
    let sa: IPsecSA

    var body: some View {
        Slab(rail: sa.health, trailing: sa.version) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(sa.connectionName)
                        .scaledFont(15, weight: .semibold)
                        .foregroundStyle(theme.label)
                    Spacer()
                    StatusPill(text: sa.state, health: sa.health)
                }
                if let l = sa.localHost, let r = sa.remoteHost {
                    FieldRow(key: "Peers", value: "\(l) → \(r)")
                }
                if let id = sa.remoteID, !id.isEmpty {
                    FieldRow(key: "Remote ID", value: id)
                }
                FieldRow(key: "Child SAs", value: "\(sa.childCount)")
            }
        }
    }
}

/// One WireGuard tunnel, as a row. Peers are on the detail screen.
struct WireGuardCard: View {
    @EnvironmentObject private var theme: ThemeManager
    let tunnel: WireGuardTunnel
    let peers: [WireGuardPeer]
    @ObservedObject var vpnThroughput: ThroughputTracker

    private var connected: Int {
        peers.filter { $0.health == .ok }.count
    }

    var body: some View {
        NavigationLink {
            WireGuardDetailView(tunnel: tunnel, peers: peers)
        } label: {
            Slab(rail: tunnel.health, trailing: tunnel.listenPort.map { "port \($0)" }) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(tunnel.descr.flatMap { $0.isEmpty ? nil : $0 } ?? tunnel.name)
                            .scaledFont(15, weight: .semibold)
                            .foregroundStyle(theme.label)
                        Spacer()
                        StatusPill(text: tunnel.statusLabel, health: tunnel.health)
                    }
                    Text(tunnel.name)
                        .scaledFont(11, design: .monospaced)
                        .foregroundStyle(theme.labelFaint)

                    HStack {
                        // Connected, not merely configured: a tunnel with three
                        // peers and none connected is a different situation
                        // from one with three peers all up, and a bare count
                        // cannot tell them apart.
                        Text(peerSummary)
                            .scaledFont(12)
                            .foregroundStyle(theme.labelMuted)
                        Spacer()
                        if !peers.isEmpty {
                            Image(systemName: "chevron.right")
                                .scaledFont(11, weight: .semibold)
                                .foregroundStyle(theme.labelFaint)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(peers.isEmpty)
    }

    private var peerSummary: String {
        if peers.isEmpty { return "No peers configured" }
        if connected == 0 { return "\(peers.count) peers, none connected" }
        return "\(connected) of \(peers.count) connected"
    }
}

/// The peers of one WireGuard tunnel.
struct WireGuardDetailView: View {
    @EnvironmentObject private var theme: ThemeManager
    let tunnel: WireGuardTunnel
    let peers: [WireGuardPeer]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Slab(rail: tunnel.health, trailing: tunnel.listenPort.map { "port \($0)" }) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(tunnel.name)
                                .scaledFont(14, weight: .semibold, design: .monospaced)
                                .foregroundStyle(theme.label)
                            Spacer()
                            StatusPill(text: tunnel.statusLabel, health: tunnel.health)
                        }
                        if let rx = tunnel.bytesReceived, let tx = tunnel.bytesSent {
                            FieldRow(key: "Transfer", value: "↓\(Fmt.bytes(rx))  ↑\(Fmt.bytes(tx))")
                        }
                    }
                }

                if peers.isEmpty {
                    Notice(symbol: "person.slash", title: "No peers configured")
                } else {
                    GroupHeading(text: "Peers")
                    ForEach(peers) { peer in
                        Slab(rail: peer.health) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(peer.descr ?? peer.shortKey)
                                        .scaledFont(14, weight: .semibold)
                                        .foregroundStyle(theme.label)
                                    Spacer()
                                    StatusPill(text: peer.statusLabel, health: peer.health)
                                }
                                if let endpoint = peer.endpoint, !endpoint.isEmpty {
                                    Text(endpoint)
                                        .scaledFont(11, design: .monospaced)
                                        .foregroundStyle(theme.labelFaint)
                                        .textSelection(.enabled)
                                }
                                ForEach(peer.allowedIPs, id: \.self) { allowed in
                                    Text(allowed)
                                        .scaledFont(11, design: .monospaced)
                                        .foregroundStyle(theme.labelFaint)
                                }
                                HStack {
                                    if let rx = peer.bytesReceived, let tx = peer.bytesSent {
                                        Text("↓\(Fmt.bytes(rx))  ↑\(Fmt.bytes(tx))")
                                            .scaledFont(11, design: .monospaced)
                                            .foregroundStyle(theme.labelFaint)
                                    }
                                    Spacer()
                                    Text(peer.handshakeDescription)
                                        .scaledFont(11, design: .monospaced)
                                        .foregroundStyle(theme.labelFaint)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle(tunnel.descr ?? tunnel.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
