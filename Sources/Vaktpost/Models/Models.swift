import Foundation

// MARK: - System

struct SystemStatus {
    var cpuUsage: Double?        // 0...100
    var memUsage: Double?        // 0...100
    var swapUsage: Double?       // 0...100
    var diskUsage: Double?       // 0...100
    var temperature: Double?     // °C
    var uptimeSeconds: Int?
    var load: [Double]           // 1/5/15 min
    var mbufUsage: Double?       // 0...100

    init(_ d: JSONDict) {
        cpuUsage = d.double("cpu_usage", "cpu", "cpu_load")
        memUsage = d.double("mem_usage", "memory_usage", "mem")
        swapUsage = d.double("swap_usage", "swap")
        diskUsage = d.double("disk_usage", "disk")
        temperature = d.double("temp_c", "temperature", "temp")
        uptimeSeconds = d.int("uptime_sec", "uptime_seconds", "uptime")
        mbufUsage = d.double("mbuf_usage", "mbuf")

        // `load_avg` may be a list of numbers or a list of strings.
        let raw = d.list("load_avg", "load_average", "loadavg")
        load = raw.compactMap { $0.doubleValue }
    }

    var loadDescription: String {
        guard !load.isEmpty else { return "—" }
        return load.map { String(format: "%.2f", $0) }.joined(separator: "  ")
    }
}

struct SystemVersion {
    var current: String?
    var latest: String?
    var updateAvailable: Bool?
    var releaseType: String?

    init(_ d: JSONDict) {
        current = d.string("version", "current_version", "installed_version")
        latest = d.string("latest_version", "available_version")
        updateAvailable = d.bool("update_available", "upgrade_available")
        releaseType = d.string("release_type", "base_version")
    }
}

struct StateTableSize {
    var current: Int?
    var maximum: Int?
    var defaultMaximum: Int?

    init(_ d: JSONDict) {
        current = d.int("current_states", "current", "states")
        maximum = d.int("maximum_states", "maximum", "max")
        defaultMaximum = d.int("default_maximum_states")
    }

    var fraction: Double? {
        guard let c = current, let m = maximum, m > 0 else { return nil }
        return Double(c) / Double(m)
    }
}

// MARK: - Interfaces

struct InterfaceStat: Identifiable {
    var id: String { "\(device)-\(name)" }
    var name: String            // friendly name, e.g. "WAN"
    var device: String          // e.g. "igb0"
    var status: String          // up / down / no carrier
    var enabled: Bool?
    var ipv4: String?
    var subnetv4: String?
    var ipv6: String?
    var mac: String?
    var media: String?
    var inBytes: Double?
    var outBytes: Double?
    var inPackets: Double?
    var outPackets: Double?
    var inErrors: Double?
    var outErrors: Double?
    var collisions: Double?

    init(_ d: JSONDict) {
        name = d.string("name", "descr", "description") ?? d.string("hwif", "if") ?? "—"
        device = d.string("hwif", "if", "device", "interface") ?? "—"
        status = (d.string("status", "linkstate") ?? "unknown").lowercased()
        enabled = d.bool("enable", "enabled")
        ipv4 = d.string("ipaddr", "ip_address", "ipv4")
        subnetv4 = d.string("subnet", "subnetbits", "subnet_bits")
        ipv6 = d.string("ipaddrv6", "ipv6")
        mac = d.string("macaddr", "mac", "mac_address")
        media = d.string("media", "mediaopt")
        inBytes = d.double("inbytes", "in_bytes", "bytes_in")
        outBytes = d.double("outbytes", "out_bytes", "bytes_out")
        inPackets = d.double("inpkts", "in_packets", "packets_in")
        outPackets = d.double("outpkts", "out_packets", "packets_out")
        inErrors = d.double("inerrs", "in_errors")
        outErrors = d.double("outerrs", "out_errors")
        collisions = d.double("collisions")
    }

    var isUp: Bool { status.contains("up") || status == "active" }

    var health: Health {
        if enabled == false { return .idle }
        if isUp { return .ok }
        if status.contains("no carrier") { return .warn }
        return .bad
    }

    var addressLine: String {
        var parts: [String] = []
        if let ipv4, !ipv4.isEmpty {
            parts.append(subnetv4.map { "\(ipv4)/\($0)" } ?? ipv4)
        }
        if let ipv6, !ipv6.isEmpty { parts.append(ipv6) }
        return parts.isEmpty ? "no address" : parts.joined(separator: "  ")
    }
}

// MARK: - Gateways

struct GatewayStatus: Identifiable {
    var id: String { name }
    var name: String
    var monitorIP: String?
    var sourceIP: String?
    var status: String      // online / down / pending
    var substatus: String?  // none / highloss / highdelay
    var delayMS: Double?
    var stddevMS: Double?
    var lossPercent: Double?

    init(_ d: JSONDict) {
        name = d.string("name", "gateway_name") ?? "—"
        monitorIP = d.string("monitor_ip", "monitorip", "monitor")
        sourceIP = d.string("source_ip", "srcip")
        status = (d.string("status") ?? "unknown").lowercased()
        substatus = d.string("substatus")?.lowercased()
        delayMS = d.double("delay")
        stddevMS = d.double("stddev")
        lossPercent = d.double("loss")
    }

    var health: Health {
        if status.contains("online") {
            if let sub = substatus, sub != "none", !sub.isEmpty { return .warn }
            if let loss = lossPercent, loss >= 5 { return .warn }
            return .ok
        }
        if status.contains("pending") || status.contains("unknown") { return .idle }
        return .bad
    }

    var readout: String {
        var parts: [String] = []
        if let delayMS { parts.append(String(format: "%.1f ms", delayMS)) }
        if let lossPercent { parts.append(String(format: "%.0f%% loss", lossPercent)) }
        return parts.isEmpty ? "no monitor data" : parts.joined(separator: "  ·  ")
    }
}

// MARK: - Services

struct ServiceStatus: Identifiable {
    var id: String { name }
    var name: String
    var descr: String?
    var status: String
    var enabled: Bool?

    init(_ d: JSONDict) {
        name = d.string("name") ?? "—"
        descr = d.string("description", "descr")
        status = (d.string("status") ?? "").lowercased()
        enabled = d.bool("enabled", "enable")
    }

    var running: Bool { status.contains("running") || status == "up" || status == "true" }

    var health: Health {
        if enabled == false { return .idle }
        return running ? .ok : .bad
    }
}

// MARK: - DHCP

struct DHCPLease: Identifiable {
    var id: String { "\(ip)-\(mac)" }
    var ip: String
    var mac: String
    var hostname: String?
    var interfaceName: String?
    var state: String       // active / expired / static / …
    var starts: String?
    var ends: String?
    var isStatic: Bool
    var online: Bool?

    init(_ d: JSONDict) {
        ip = d.string("ip", "ip_address", "address") ?? "—"
        mac = (d.string("mac", "mac_address", "hardware") ?? "—").lowercased()
        hostname = d.string("hostname", "client_hostname", "descr")
        interfaceName = d.string("if", "interface")
        state = (d.string("state", "status", "act") ?? "").lowercased()
        starts = d.string("starts", "start")
        ends = d.string("ends", "end")
        isStatic = (d.bool("static") ?? false) || state.contains("static")
        online = d.bool("online")
    }

    var health: Health {
        if isStatic { return .info }
        if online == true || state.contains("active") { return .ok }
        if state.contains("expired") { return .idle }
        return .warn
    }

    var label: String {
        if let h = hostname, !h.isEmpty, h != "—" { return h }
        return ip
    }
}

// MARK: - ARP

struct ARPEntry: Identifiable {
    var id: String { "\(ip)-\(mac)" }
    var ip: String
    var mac: String
    var hostname: String?
    var interfaceName: String?
    var expires: String?
    var type: String?

    init(_ d: JSONDict) {
        ip = d.string("ip", "ip_address") ?? "—"
        mac = (d.string("mac", "mac_address") ?? "—").lowercased()
        hostname = d.string("hostname", "dnsresolve")
        interfaceName = d.string("interface", "if")
        expires = d.string("expires")
        type = d.string("type")
    }
}

// MARK: - Logs

struct LogLine: Identifiable {
    enum Kind { case firewall, system }

    let id = UUID()
    var kind: Kind
    var text: String
    var timestamp: String?
    var action: String?     // pass / block / reject
    var interfaceName: String?
    var source: String?
    var destination: String?
    var proto: String?

    init(_ d: JSONDict, kind: Kind) {
        self.kind = kind
        text = d.string("text", "line", "message", "log") ?? ""
        timestamp = d.string("time", "timestamp", "date")
        action = d.string("action")?.lowercased()
        interfaceName = d.string("interface", "if")
        source = d.string("source_address", "src", "source")
        destination = d.string("destination_address", "dest", "destination")
        proto = d.string("protocol", "proto")

        if text.isEmpty {
            // Some builds return structured fields only.
            let bits = [timestamp, action?.uppercased(), interfaceName, source, "→", destination, proto]
            text = bits.compactMap { $0 }.joined(separator: " ")
        }
    }

    var health: Health {
        switch action {
        case "block", "reject": return .bad
        case "pass": return .ok
        default: return .idle
        }
    }

    var portsAndPeers: String? {
        guard source != nil || destination != nil else { return nil }
        return "\(source ?? "?") → \(destination ?? "?")"
    }
}
