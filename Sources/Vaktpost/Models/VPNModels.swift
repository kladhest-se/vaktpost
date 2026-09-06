import Foundation

// MARK: - OpenVPN

struct OpenVPNServerStatus: Identifiable {
    var id: String { "\(name)-\(vpnID)" }
    var name: String
    var vpnID: String
    var mode: String?
    var port: String?
    /// Absent from `status/openvpn/servers` on 26.07 — a running server simply
    /// appears in the list. Kept optional because the clients endpoint does
    /// report one, and older versions may.
    var status: String?
    var connections: [OpenVPNConnection]
    var routes: [OpenVPNRoute]

    init(_ d: JSONDict) {
        name = d.string("name", "description", "descr") ?? "OpenVPN"
        vpnID = d.string("vpnid", "id") ?? ""
        mode = d.string("mode")
        port = d.string("port")
        status = d.string("status")
        connections = d.list("conns", "connections").compactMap { JSONDict($0) }.map(OpenVPNConnection.init)
        routes = d.list("routes").compactMap { JSONDict($0) }.map(OpenVPNRoute.init)
    }

    /// Derived from what the endpoint actually returns.
    ///
    /// There is no status field, so the app used to render a permanent
    /// "UNKNOWN" pill — a placeholder dressed up as a reading. A server with
    /// clients on it is working; one with none is idle, which is a normal
    /// state for a remote-access server and not a fault.
    var health: Health {
        if let status, !status.isEmpty {
            let s = status.lowercased()
            if s.contains("up") || s.contains("running") || s.contains("connected") { return .ok }
            if s.contains("down") || s.contains("stopped") { return .bad }
            return .idle
        }
        return connections.isEmpty ? .idle : .ok
    }

    var statusLabel: String {
        if let status, !status.isEmpty { return status }
        switch connections.count {
        case 0: return "no clients"
        case 1: return "1 connected"
        default: return "\(connections.count) connected"
        }
    }

    /// The name already carries the protocol and port ("openvpn1 UDP4:1194"),
    /// so the trailing slot shows the mode instead of repeating it.
    var modeLabel: String? {
        guard let mode, !mode.isEmpty else { return nil }
        return mode.replacingOccurrences(of: "_", with: " ")
    }

    func lastSeen(for commonName: String) -> String? {
        routes.first { $0.commonName == commonName }?.lastTime
    }
}

/// A route the server holds for a connected client. Carries `last_time`, which
/// is the closest thing available to "when did we last hear from this peer".
struct OpenVPNRoute: Identifiable {
    var id: String { "\(commonName)-\(virtualAddress ?? "")" }
    var commonName: String
    var remoteHost: String?
    var virtualAddress: String?
    var lastTime: String?

    init(_ d: JSONDict) {
        commonName = d.string("common_name", "user_name", "name") ?? ""
        remoteHost = d.string("remote_host")
        virtualAddress = d.string("virtual_addr", "virtual_address")
        lastTime = d.string("last_time")
    }
}

struct OpenVPNConnection: Identifiable {
    var id: String { "\(commonName)-\(remoteHost)" }
    var commonName: String
    var remoteHost: String
    var virtualAddress: String?
    var bytesReceived: Double?
    var bytesSent: Double?
    var connectedSince: String?

    init(_ d: JSONDict) {
        commonName = d.string("common_name", "user_name", "name") ?? "peer"
        remoteHost = d.string("remote_host", "remote", "real_address") ?? ""
        virtualAddress = d.string("virtual_addr", "virtual_address", "tunnel_addr")
        bytesReceived = d.double("bytes_recv", "bytes_received")
        bytesSent = d.double("bytes_sent")
        connectedSince = d.string("connect_time", "connected_since", "connect_time_unix")
    }
}

// MARK: - IPsec

struct IPsecSA: Identifiable {
    var id: String { "\(connectionName)-\(uniqueID)" }
    var connectionName: String
    var uniqueID: String
    var state: String
    var localHost: String?
    var remoteHost: String?
    var localID: String?
    var remoteID: String?
    var version: String?
    var childCount: Int

    init(_ d: JSONDict) {
        connectionName = d.string("con_id", "name", "connection") ?? "IPsec"
        uniqueID = d.string("uniqueid", "id") ?? ""
        state = (d.string("state") ?? "unknown").lowercased()
        localHost = d.string("local_host", "local-host")
        remoteHost = d.string("remote_host", "remote-host")
        localID = d.string("local_id", "local-id")
        remoteID = d.string("remote_id", "remote-id")
        version = d.string("version", "ike_version")
        childCount = d.list("child_sas", "child-sas").count
    }

    var health: Health {
        if state.contains("established") || state.contains("installed") { return .ok }
        if state.contains("connecting") { return .warn }
        return .bad
    }
}

// MARK: - WireGuard

struct WireGuardTunnel: Identifiable {
    var id: String { name }
    var name: String
    var descr: String?
    var publicKey: String?
    var listenPort: String?
    var enabled: Bool?
    var peerCount: Int

    init(_ d: JSONDict) {
        name = d.string("name", "tun") ?? "wg"
        descr = d.string("descr", "description")
        publicKey = d.string("public_key", "publickey")
        listenPort = d.string("listen_port", "listenport")
        enabled = d.bool("enabled", "enable")
        peerCount = d.int("peer_count") ?? d.list("peers").count
    }

    var health: Health { (enabled ?? true) ? .ok : .idle }
}

struct WireGuardPeer: Identifiable {
    var id: String { "\(tunnel)-\(publicKey)" }
    var tunnel: String
    var publicKey: String
    var descr: String?
    var endpoint: String?
    var latestHandshake: String?
    var bytesReceived: Double?
    var bytesSent: Double?
    var allowedIPs: [String]

    init(_ d: JSONDict) {
        tunnel = d.string("tun", "tunnel", "parent_id") ?? ""
        publicKey = d.string("public_key", "publickey") ?? ""
        descr = d.string("descr", "description")
        endpoint = d.string("endpoint", "endpoint_address")
        latestHandshake = d.string("latest_handshake", "handshake")
        bytesReceived = d.double("transfer_rx", "bytes_received", "rx")
        bytesSent = d.double("transfer_tx", "bytes_sent", "tx")
        allowedIPs = d.list("allowed_ips", "allowedips").compactMap { $0.stringValue }
    }

    var shortKey: String {
        publicKey.count > 14 ? String(publicKey.prefix(10)) + "…" : publicKey
    }

    var health: Health {
        guard let hs = latestHandshake, !hs.isEmpty, hs != "0" else { return .idle }
        return .ok
    }
}
