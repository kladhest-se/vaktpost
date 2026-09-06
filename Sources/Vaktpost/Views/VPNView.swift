import SwiftUI

struct VPNView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !store.hasVPN {
                    Notice(
                        symbol: "lock.open",
                        title: "No VPN reported",
                        detail: "None of the OpenVPN, IPsec or WireGuard status endpoints returned tunnels. WireGuard needs its package installed for those endpoints to exist."
                    )
                }

                if !store.openvpnServers.isEmpty {
                    GroupHeading(text: "OpenVPN servers")
                    ForEach(store.openvpnServers) { OpenVPNCard(server: $0, isServer: true) }
                }

                if !store.openvpnClients.isEmpty {
                    GroupHeading(text: "OpenVPN clients")
                    ForEach(store.openvpnClients) { OpenVPNCard(server: $0, isServer: false) }
                }

                if !store.ipsecSAs.isEmpty {
                    GroupHeading(text: "IPsec")
                    ForEach(store.ipsecSAs) { IPsecCard(sa: $0) }
                }

                if !store.wireguardTunnels.isEmpty {
                    GroupHeading(text: "WireGuard")
                    ForEach(store.wireguardTunnels) { tunnel in
                        WireGuardCard(
                            tunnel: tunnel,
                            peers: store.wireguardPeers.filter {
                                $0.tunnel == tunnel.name || $0.tunnel.isEmpty
                            }
                        )
                    }
                }

                ForEach(unavailable, id: \.self) { note in
                    Slab(rail: .idle) {
                        Text(note)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.labelFaint)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .refreshable { await store.refresh() }
        .navigationTitle("VPN")
    }

    private var unavailable: [String] {
        var out: [String] = []
        if let e = store.errors[.openvpn] { out.append("OpenVPN: \(e)") }
        if let e = store.errors[.ipsec] { out.append("IPsec: \(e)") }
        if let e = store.errors[.wireguard] { out.append("WireGuard: \(e)") }
        return out
    }
}

struct OpenVPNCard: View {
    @EnvironmentObject private var theme: ThemeManager
    let server: OpenVPNServerStatus
    let isServer: Bool

    var body: some View {
        Slab(rail: server.health, trailing: server.mode) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(server.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.label)
                    Spacer()
                    StatusPill(text: server.status, health: server.health)
                }
                if isServer {
                    FieldRow(key: "Connections", value: "\(server.connections.count)")
                }
                if !server.connections.isEmpty {
                    Hairline()
                    ForEach(server.connections) { conn in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(conn.commonName)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(theme.label)
                                Spacer()
                                Text(conn.virtualAddress ?? "")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(theme.labelMuted)
                            }
                            HStack(spacing: 10) {
                                Text(conn.remoteHost)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(theme.labelFaint)
                                Spacer()
                                if let rx = conn.bytesReceived, let tx = conn.bytesSent {
                                    Text("↓\(Fmt.bytes(rx))  ↑\(Fmt.bytes(tx))")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(theme.labelFaint)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
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
                        .font(.system(size: 15, weight: .semibold))
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

struct WireGuardCard: View {
    @EnvironmentObject private var theme: ThemeManager
    let tunnel: WireGuardTunnel
    let peers: [WireGuardPeer]

    var body: some View {
        Slab(rail: tunnel.health, trailing: tunnel.listenPort.map { "port \($0)" }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(tunnel.descr?.isEmpty == false ? tunnel.descr! : tunnel.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.label)
                    Spacer()
                    StatusPill(text: (tunnel.enabled ?? true) ? "enabled" : "disabled",
                               health: tunnel.health)
                }
                Text(tunnel.name)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.labelFaint)

                if peers.isEmpty {
                    FieldRow(key: "Peers", value: "\(tunnel.peerCount)")
                } else {
                    Hairline()
                    ForEach(peers) { peer in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(peer.descr?.isEmpty == false ? peer.descr! : peer.shortKey)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(theme.label)
                                Spacer()
                                StatusPill(
                                    text: peer.health == .ok ? "handshaked" : "no handshake",
                                    health: peer.health
                                )
                            }
                            if let ep = peer.endpoint, !ep.isEmpty {
                                Text(ep)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(theme.labelFaint)
                            }
                            if !peer.allowedIPs.isEmpty {
                                Text(peer.allowedIPs.joined(separator: ", "))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(theme.labelMuted)
                            }
                            if let rx = peer.bytesReceived, let tx = peer.bytesSent {
                                Text("↓\(Fmt.bytes(rx))  ↑\(Fmt.bytes(tx))")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(theme.labelFaint)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }
}
