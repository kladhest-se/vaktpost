import Foundation

// MARK: - OpenVPN

struct OpenVPNServerStatus: Identifiable {
    var id: String { "\(name)-\(vpnID)" }
    var name: String
    var vpnID: String
    var mode: String?
    var status: String
    var connections: [OpenVPNConnection]

    init(_ d: JSONDict) {
        name = d.string("name", "description", "descr") ?? "OpenVPN"
        vpnID = d.string("vpnid", "id") ?? ""
        mode = d.string("mode")
        status = (d.string("status") ?? "unknown").lowercased()
        connections = d.list("conns", "connections").compactMap { JSONDict($0) }.map(OpenVPNConnection.init)
    }

    var health: Health {
        if status.contains("up") || status.contains("server_running") || status.contains("running") { return .ok }
        if status.contains("connected") { return .ok }
        if status.contains("down") || status.contains("stopped") { return .bad }
        return .idle
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
