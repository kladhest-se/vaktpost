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
    var platform: String?
    /// Cumulative CPU ticks. A percentage cannot be read from a single sample;
    /// `DashboardStore` differences consecutive ones to get `cpuUsage`.
    var cpuTicksTotal: Int?
    var cpuTicksIdle: Int?
    var hostname: String?
    var temperatureSource: String?
    var cpuModel: String?
    var cpuCount: Int?
    var serial: String?
    var biosVersion: String?

    init(_ d: JSONDict) {
        // Present under the REST transport, absent under XML-RPC where only
        // raw ticks are available. Left nil rather than zero so the meter is
        // hidden until two samples exist, instead of claiming an idle CPU.
        cpuUsage = d.double("cpu_usage", "cpu", "cpu_load")
        cpuTicksTotal = d.int("cpu_ticks_total")
        cpuTicksIdle = d.int("cpu_ticks_idle")
        hostname = d.string("hostname")
        temperatureSource = d.string("temp_source")
        memUsage = d.double("mem_usage", "memory_usage", "mem")
        swapUsage = d.double("swap_usage", "swap")
        // No single disk figure under XML-RPC — only per-filesystem rows. The
        // worst mount is the honest summary and a more useful one than an
        // average: a full /var stops logging while the pool looks empty.
        if let aggregate = d.double("disk_usage", "disk") {
            diskUsage = aggregate
        } else {
            diskUsage = d.list("filesystems")
                .compactMap { JSONDict($0)?.double("percent_used", "percent") }
                .max()
        }
        // Both fields are reported. Celsius is preferred; Fahrenheit is
        // converted rather than ignored, since which one is populated varies
        // with the sensor driver.
        if let celsius = d.double("temp_c", "temperature", "temp") {
            temperature = celsius
        } else if let fahrenheit = d.double("temp_f") {
            temperature = (fahrenheit - 32) * 5 / 9
        } else {
            temperature = nil
        }
        mbufUsage = d.double("mbuf_usage", "mbuf")
        uptimeSeconds = Self.uptime(d.value("uptime_sec", "uptime_seconds", "uptime"))

        // An object of name/descr on some versions, a plain string on others.
        platform = d.string("platform") ?? d.dict("platform")?.string("descr", "name")
        cpuModel = d.string("cpu_model")
        cpuCount = d.int("cpu_count")
        serial = d.string("serial")
        biosVersion = d.string("bios_version")

        // A list under both transports, but hass-pfsense's telemetry shape
        // returns an object keyed by interval, so both are accepted.
        let rawLoad = d.list("cpu_load_avg", "load_avg", "load_average", "loadavg")
        if rawLoad.isEmpty, let object = d.dict("cpu_load_avg", "load_average") {
            load = ["one_minute", "five_minute", "fifteen_minute"]
                .compactMap { object.double($0) }
        } else {
            load = rawLoad.compactMap { $0.doubleValue }
        }
    }

    /// Uptime, from either a count of seconds or pfSense's English phrasing.
    ///
    /// `status/system` returns "5 Days 01 Hour 37 Minutes 40 Seconds", not a
    /// number. Reading that with a plain integer conversion takes the leading
    /// 5 and stops, so the dashboard showed "up 0m" on a box that had been up
    /// for most of a week — wrong in the least suspicious way possible, since
    /// a freshly rebooted firewall looks exactly like that.
    ///
    /// Both shapes are accepted because the field is a plain number on some
    /// versions.
    static func uptime(_ value: JSONValue?) -> Int? {
        guard let value else { return nil }
        if case .number(let n) = value { return Int(n) }
        guard let text = value.stringValue else { return nil }
        if let plain = Int(text) { return plain }

        var total = 0
        var pending: Double?
        var matchedAUnit = false

        for token in text.split(whereSeparator: { $0 == " " || $0 == "," }) {
            if let number = Double(token) { pending = number; continue }
            guard let number = pending else { continue }
            pending = nil

            let unit = token.lowercased()
            let seconds: Int
            if unit.hasPrefix("day") { seconds = 86_400 }
            else if unit.hasPrefix("hour") || unit.hasPrefix("hr") { seconds = 3_600 }
            else if unit.hasPrefix("min") { seconds = 60 }
            else if unit.hasPrefix("sec") { seconds = 1 }
            else { continue }

            total += Int(number) * seconds
            matchedAUnit = true
        }
        return matchedAUnit ? total : nil
    }

    var loadDescription: String {
        guard !load.isEmpty else { return "—" }
        return load.map { String(format: "%.2f", $0) }.joined(separator: "  ")
    }

    /// Whether the firewall is reporting a temperature at all.
    ///
    /// Null on most hardware until a thermal sensor module is loaded under
    /// System → Advanced → Miscellaneous. Distinguishing "no sensor" from
    /// "cold" matters: 0 °C would be alarming and wrong.
    var hasTemperature: Bool { temperature != nil }

    /// What the reading is of.
    ///
    /// "CPU at 82 °C" is alarming; "Chipset at 82 °C" is a Tuesday. The number
    /// is the same and the sensor is what makes the difference, so the label
    /// follows the sysctl that answered rather than assuming a CPU die.
    var temperatureLabel: String {
        guard let source = temperatureSource, !source.isEmpty else { return "Temperature" }
        if source.contains("pchtherm") { return "Chipset" }
        if source.contains("cpu") { return "CPU" }
        if source.contains("acpi") { return "System" }
        return "Temperature"
    }

    /// Thresholds that suit the sensor.
    ///
    /// A PCH sits in the eighties under normal load and throttles above about
    /// 105; a CPU die at 82 is worth a look and at 95 is a problem. Using one
    /// pair of numbers for both meant a healthy chipset raised a permanent
    /// warning nobody could act on — which is how an alert list stops being
    /// read at all.
    var temperatureThresholds: (warn: Double, bad: Double) {
        // An unidentified sensor gets the cautious pair rather than the strict
        // one. Warning at 80 on a reading that might be a chipset produces an
        // alert nobody can act on, and an alert list with one of those in it
        // stops being read.
        guard let source = temperatureSource, !source.isEmpty else { return (90, 100) }
        if source.contains("pchtherm") { return (95, 105) }
        if source.contains("acpi") { return (85, 100) }
        return (80, 95)
    }

    var hardwareDescription: String? {
        var parts: [String] = []
        if let platform, !platform.isEmpty { parts.append(platform) }
        if let cpuCount { parts.append("\(cpuCount) cores") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
        // No underscores in the v2 field names — `currentstates`, not
        // `current_states`. With only the underscored spellings listed, every
        // value read as nil and the card showed "Current states 0" on a
        // firewall holding eleven thousand of them.
        current = d.int("currentstates", "current_states", "current", "states")
        maximum = d.int("maximumstates", "maximum_states", "maximum", "max")
        defaultMaximum = d.int("defaultmaximumstates", "default_maximum_states")
    }

    /// `maximumstates` is null unless somebody has overridden the limit, so the
    /// number actually being enforced is the default. Using only the explicit
    /// maximum meant no denominator and therefore no meter on a stock box —
    /// which is every box.
    var effectiveMaximum: Int? { maximum ?? defaultMaximum }

    var isDefaultLimit: Bool { maximum == nil && defaultMaximum != nil }

    var fraction: Double? {
        guard let c = current, let m = effectiveMaximum, m > 0 else { return nil }
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
    var mtu: String?
    var gateway: String?
    var internalName: String?
    var inBytes: Double?
    var outBytes: Double?
    var inPackets: Double?
    var outPackets: Double?
    var inErrors: Double?
    var outErrors: Double?
    var collisions: Double?

    init(_ d: JSONDict) {
        // `descr` is what the administrator called it ("WAN_1"); `name` is
        // pfSense's internal handle ("wan"). The description is the one worth
        // showing, and the one that matches the webConfigurator.
        name = d.string("descr", "description") ?? d.string("name") ?? d.string("hwif", "if") ?? "—"
        // pfSense's internal handle — "lan", "opt7". Rules reference this,
        // where clients and ARP reference the device.
        internalName = d.string("name")
        device = d.string("hwif", "if", "device", "interface") ?? "—"
        status = (d.string("status", "linkstate") ?? "unknown").lowercased()
        enabled = d.bool("enable", "enabled")
        ipv4 = d.string("ipaddr", "ip_address", "ipv4")
        subnetv4 = Self.prefixLength(d.string("subnet", "subnetbits", "subnet_bits"))
        ipv6 = d.string("ipaddrv6", "ipv6")
        mac = d.string("macaddr", "mac", "mac_address")
        media = d.string("media", "mediaopt")?.trimmingCharacters(in: .whitespaces)
        mtu = d.string("mtu")
        gateway = d.string("gateway")
        inBytes = d.double("inbytes", "in_bytes", "bytes_in")
        outBytes = d.double("outbytes", "out_bytes", "bytes_out")
        inPackets = d.double("inpkts", "in_packets", "packets_in")
        outPackets = d.double("outpkts", "out_packets", "packets_out")
        inErrors = d.double("inerrs", "in_errors")
        outErrors = d.double("outerrs", "out_errors")
        collisions = d.double("collisions")
    }

    /// Renders a subnet as a prefix length whichever way it arrives.
    ///
    /// `status/interfaces` returns a dotted netmask ("255.255.255.224") where
    /// the configuration endpoints return prefix bits ("27"). Concatenating
    /// blindly produced "203.0.113.9/255.255.255.224", which is not a
    /// notation anybody uses.
    static func prefixLength(_ subnet: String?) -> String? {
        guard let subnet, !subnet.isEmpty else { return nil }
        guard subnet.contains(".") else { return subnet }
        let octets = subnet.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return subnet }
        return String(octets.reduce(0) { $0 + $1.nonzeroBitCount })
    }

    /// A stable identity for throughput history.
    ///
    /// `device` alone is not unique: VLANs share their parent's `hwif`.
    var seriesKey: String { "\(name)|\(device)" }

    var isUp: Bool { status.contains("up") || status == "active" }

    /// Link state decides this, not the `enable` flag.
    ///
    /// A live WAN carrying traffic reports `"enable": false` — that field
    /// tracks something other than administrative state, and treating it as
    /// authoritative greyed out a working uplink.
    var health: Health {
        if isUp { return .ok }
        if status.contains("no carrier") { return .warn }
        if enabled == false { return .idle }
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
        // `system_get_dhcpleases` reports this as the string "online" or
        // "offline" rather than a boolean.
        if let raw = d.string("online") {
            online = raw.lowercased() == "online"
        } else {
            online = d.bool("online")
        }
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

    /// Seconds until the entry ages out, rendered as a duration.
    ///
    /// The raw value is a count of seconds — "1181" tells nobody anything,
    /// where "19m" is immediately legible.
    var expiryDescription: String? {
        guard let expires, !expires.isEmpty else { return nil }
        guard let seconds = Int(expires) else { return expires }
        if seconds <= 0 { return "expired" }
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        return "\(seconds / 3_600)h \((seconds % 3_600) / 60)m"
    }

    init(_ d: JSONDict) {
        // `system_get_arp_table` spells these with hyphens; the REST endpoint
        // used underscores. Both are listed so a fixture from either transport
        // decodes.
        ip = d.string("ip-address", "ip", "ip_address") ?? "—"
        mac = (d.string("mac-address", "mac", "mac_address") ?? "—").lowercased()
        hostname = d.string("hostname", "dnsresolve")
        interfaceName = d.string("interface", "if")
        expires = d.string("expires")
        type = d.string("type")
    }
}

// MARK: - Logs

struct LogLine: Identifiable {
    enum Kind { case firewall, system, auth, dhcp, openvpn }

    let id = UUID()
    var kind: Kind
    var text: String
    var timestamp: String?
    var action: String?     // pass / block / reject
    var interfaceName: String?
    var source: String?
    var destination: String?
    var proto: String?

    /// A raw log line.
    ///
    /// Under XML-RPC the logs are read straight off disk, so a line is a
    /// string rather than a parsed structure. The filter log's action is
    /// recovered from the text so the pass/block filter and the coloured rail
    /// keep working.
    init(text: String, kind: Kind) {
        self.kind = kind
        self.text = text
        timestamp = nil
        interfaceName = nil
        source = nil
        destination = nil
        proto = nil

        let lower = text.lowercased()
        if kind == .firewall {
            if lower.contains(",block,") || lower.contains(" block ") { action = "block" }
            else if lower.contains(",reject,") { action = "reject" }
            else if lower.contains(",pass,") || lower.contains(" pass ") { action = "pass" }
            else { action = nil }
        } else {
            action = nil
        }
    }

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
