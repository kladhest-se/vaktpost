import Foundation

/// Renders a v2 filter address, which may be a plain string or an object with
/// `any` / `network` / `address` / `port` members depending on the rule.
/// One side of a rule: where it comes from or goes to, and on what port.
///
/// Address and port are kept apart rather than joined into `host:port`.
/// Joining them meant every consumer had to split on ":" to get either back,
/// and an IPv6 address is full of colons — `fe80::1:443` cannot be taken apart
/// again correctly, and the attempt produced nonsense on any rule with a v6
/// address in it.
struct FilterAddress {
    /// The key pfSense used in `config.xml` for this value. It is not cosmetic:
    /// `any`, a special network such as `wanip`, and a literal/alias are three
    /// different rule representations.
    enum StorageKind: String, Hashable {
        case any
        case network
        case address
    }

    var address: String
    var port: String?
    var storageKind: StorageKind

    init(_ value: JSONValue?, port explicitPort: JSONValue? = nil) {
        var base = "any"
        var found: String?
        var storage: StorageKind = .any

        if let value {
            if let s = value.stringValue, !s.isEmpty {
                base = s
                storage = s.lowercased() == "any" ? .any : .address
            } else if let d = JSONDict(value) {
                if d.bool("any") == true {
                    base = "any"
                    storage = .any
                } else if let n = d.string("network") {
                    base = n
                    storage = .network
                } else if let a = d.string("address") {
                    base = a
                    storage = a.lowercased() == "any" ? .any : .address
                }
                if let p = d.string("port"), !p.isEmpty { found = p }
            }
        }
        if found == nil, let p = explicitPort?.stringValue, !p.isEmpty { found = p }

        address = base
        port = found
        storageKind = storage
    }

    /// Encode the value without erasing the rule type pfSense supplied.
    static func encoded(_ address: String, as kind: StorageKind) -> JSONValue {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .any:
            return .object(["any": .bool(true)])
        case .network:
            return .object(["network": .string(value)])
        case .address:
            return .object(["address": .string(value)])
        }
    }

    /// What sort of thing this side is.
    ///
    /// pfSense distinguishes these in its own editor and the distinction
    /// matters when reading a rule: `any` is a wildcard, a network covers a
    /// range, an interface name resolves to whatever that interface currently
    /// holds, and an alias is a list you have to look up. Four rules that look
    /// alike in a list are doing very different things.
    enum Kind: String {
        case any = "any"
        case network = "network"
        case host = "host"
        case interface = "interface"
        case alias = "alias"
    }

    /// Worked out from the address, since pfSense does not label it.
    func kind(knownAliases: Set<String>) -> Kind {
        if address == "any" { return .any }
        if knownAliases.contains(address) { return .alias }
        if address.contains("/") { return .network }
        // `wanip`, `lan`, `opt3` — an interface, or its address.
        if address.hasSuffix("ip") || !address.contains(".") && !address.contains(":") {
            return .interface
        }
        return .host
    }

    /// The joined form, for anywhere a single string is wanted.
    var text: String {
        guard let port, !port.isEmpty else { return address }
        return "\(address):\(port)"
    }
}

struct FirewallRule: Identifiable {
    var id: String { tracker.isEmpty ? "\(interfaceName)-\(descr)-\(source)-\(destination)" : tracker }
    var tracker: String
    var interfaceName: String
    var type: String            // pass / block / reject
    var ipProtocol: String?     // inet / inet6
    var proto: String?
    var sourceSide: FilterAddress
    var destinationSide: FilterAddress
    var descr: String
    var disabled: Bool
    var logged: Bool

    var source: String { sourceSide.text }
    var destination: String { destinationSide.text }

    init(_ d: JSONDict) {
        tracker = d.string("tracker") ?? ""
        let ifaces = d.list("interface").compactMap { $0.stringValue }
        interfaceName = ifaces.isEmpty ? (d.string("interface") ?? "—") : ifaces.joined(separator: ",")
        type = (d.string("type") ?? "").lowercased()
        ipProtocol = d.string("ipprotocol")
        proto = d.string("protocol")
        sourceSide = FilterAddress(d.value("source"), port: d.value("source_port"))
        destinationSide = FilterAddress(d.value("destination"), port: d.value("destination_port"))
        descr = d.string("descr", "description") ?? ""
        disabled = d.bool("disabled") ?? false
        logged = d.bool("log") ?? false
    }

    var health: Health {
        if disabled { return .idle }
        switch type {
        case "pass": return .ok
        case "block": return .bad
        case "reject": return .warn
        default: return .info
        }
    }

    var protoLabel: String { (proto ?? "any").uppercased() }

    var isFloating: Bool {
        interfaceName.components(separatedBy: ",").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count > 1
    }

    /// A configured block whose source is a literal host or CIDR. Quick Block
    /// always creates this shape. Keeping it separate from dynamic pf tables
    /// lets the System screen show what Vaktpost just added even on pfSense
    /// Plus, where the live table accessor is not exposed to PHP.
    var isConfiguredHostBlock: Bool {
        type == "block"
            && !disabled
            && sourceSide.storageKind == .address
            && !sourceSide.address.isEmpty
            && sourceSide.address.lowercased() != "any"
    }
}

struct FirewallAliasEntry: Identifiable {
    var id: String { name }
    var name: String
    var type: String
    var descr: String?
    var addresses: [String]
    var details: [String]

    init(_ d: JSONDict) {
        name = d.string("name") ?? "—"
        type = d.string("type") ?? ""
        descr = d.string("descr", "description")
        addresses = Self.addressList(d.value("address"))
        details = Self.detailList(d.value("detail"))
    }

    /// pfSense's port-bearing alias types are named `port`, `url_ports` or
    /// `urltable_ports`. Everything else is an address-side alias, including
    /// host, network, URL table and GeoIP aliases. Keeping the distinction in
    /// one place prevents a port alias being offered in an address field where
    /// the firewall will reject it.
    var isPortAlias: Bool { type.lowercased().contains("port") }
    var isAddressAlias: Bool { !isPortAlias }

    func matches(search raw: String) -> Bool {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        return name.lowercased().contains(query)
            || type.lowercased().contains(query)
            || (descr ?? "").lowercased().contains(query)
            || addresses.contains { $0.lowercased().contains(query) }
            || details.contains { $0.lowercased().contains(query) }
    }

    /// The members of an alias, however this transport spells them.
    ///
    /// In `config.xml` an alias stores its members as one space-separated
    /// string — "172.16.1.50 172.16.1.51 172.16.1.52". The REST API returned a
    /// list instead, so reading it as a list gave nothing at all under
    /// XML-RPC: every alias looked empty, the Firewall tab showed member
    /// counts of zero, and no client got a name from one.
    static func addressList(_ value: JSONValue?) -> [String] {
        guard let value else { return [] }
        if let array = value.arrayValue { return array.compactMap { $0.stringValue } }
        guard let text = value.stringValue else { return [] }
        return text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Per-member descriptions, which `config.xml` separates with "||".
    static func detailList(_ value: JSONValue?) -> [String] {
        guard let value else { return [] }
        if let array = value.arrayValue { return array.compactMap { $0.stringValue } }
        guard let text = value.stringValue else { return [] }
        return text.components(separatedBy: "||").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }
}

struct PortForward: Identifiable {
    var id: String { tracker.isEmpty ? "\(interfaceName)-\(destination)-\(target)" : tracker }
    /// Stable pfSense identity used for updates and deletes.
    var tracker: String
    var interfaceName: String
    var proto: String?
    /// Where the traffic comes from.
    ///
    /// Usually `any` on a port forward, which is why it went unnoticed — but
    /// pfSense does return it, and a forward restricted to one source is
    /// exactly the kind of rule you would want to see restricted.
    var sourceSide: FilterAddress
    var destinationSide: FilterAddress
    var target: String
    var localPort: String?
    /// inet / inet6, as pfSense stores it.
    ///
    /// Not read before, which left the editor deriving it from `protocol` —
    /// comparing tcp or udp against the string "inet6", so it was always IPv4
    /// and saving an IPv6 forward converted it. A field the app intends to
    /// write back has to be a field it reads.
    var ipProtocol: String?

    var destination: String { destinationSide.text }
    var descr: String
    var disabled: Bool

    init(_ d: JSONDict) {
        tracker = d.string("tracker") ?? ""
        interfaceName = d.string("interface") ?? "—"
        proto = d.string("protocol")
        sourceSide = FilterAddress(d.value("source"), port: d.value("source_port"))
        destinationSide = FilterAddress(d.value("destination"), port: d.value("destination_port"))
        target = d.string("target") ?? FilterAddress(d.value("target")).text
        localPort = d.string("local_port")
        ipProtocol = d.string("ipprotocol", "ip_protocol")
        descr = d.string("descr", "description") ?? ""
        disabled = d.bool("disabled") ?? false
    }

    var targetLabel: String {
        guard let p = localPort, !p.isEmpty else { return target }
        return "\(target):\(p)"
    }

    var health: Health { disabled ? .idle : .info }
}

// MARK: - pfBlockerNG

/// One alias pfBlockerNG maintains, and what pf currently holds for it.
struct PFBlockerFeed: Identifiable {
    var id: String { name }
    var name: String
    var descr: String?
    var type: String?

    /// Addresses this list holds, or nil where nothing could answer.
    ///
    /// Nil rather than zero, and the distinction matters: a list configured
    /// but never downloaded and a feed that legitimately matched nothing both
    /// look like zero, and only one of them is working.
    var entries: Int?

    /// Where the count came from.
    ///
    /// `pf` is the running firewall and the strongest answer. `file` is
    /// /var/db/aliastables, which is what pf loads from — a list written but
    /// not applied still counts. `config` is an inline alias, which is the
    /// only count a port alias has ever had.
    enum Source: String {
        case pf, file, config, none

        var description: String {
            switch self {
            case .pf: return "from pf"
            case .file: return "from the table file"
            case .config: return "from the configuration"
            case .none: return "unavailable"
            }
        }
    }

    var source: Source

    /// What pfBlockerNG calls the list, without its prefix.
    var shortName: String {
        name.hasPrefix("pfB_") ? String(name.dropFirst(4)) : name
    }

    init(_ d: JSONDict) {
        name = d.string("name") ?? "—"
        descr = d.string("descr").flatMap { $0.isEmpty ? nil : $0 }
        type = d.string("type").flatMap { $0.isEmpty ? nil : $0 }
        let count = d.int("entries") ?? -1
        entries = count < 0 ? nil : count
        source = Source(rawValue: d.string("source") ?? "") ?? .none
    }
}

/// One of pfBlockerNG's log files, described rather than read.
///
/// The size and the modification time answer the question a person actually
/// has — is this running — without pulling a log that on a busy firewall runs
/// to hundreds of megabytes across the wire to be counted.
struct PFBlockerLogFile: Identifiable {
    var id: String { name }
    var name: String
    var bytes: Double
    var updated: Date?

    init(_ d: JSONDict) {
        name = d.string("name") ?? "—"
        bytes = d.double("bytes") ?? 0
        updated = d.double("updated").flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
    }
}

/// pfBlockerNG as this app can see it.
struct PFBlockerStatus {
    var enabled: Bool
    var dnsblEnabled: Bool
    /// "unbound" or "dnsbl_python", when DNSBL is on.
    var dnsblMode: String?
    /// Which pf accessor was available, or nil where neither was.
    ///
    /// Nil on pfSense Plus, where neither function exists. That used to mean
    /// nothing could be counted; the counts now fall back to the table files
    /// pf loads from, and this only says whether the strongest source was
    /// available.
    var accessor: String?
    /// Which of the probed paths exist, for the diagnostics screen. The
    /// package and its development build keep things in different places and
    /// this app cannot tell which is installed without looking.
    var foundPaths: [String]
    var feeds: [PFBlockerFeed]
    var logs: [PFBlockerLogFile]

    /// Addresses currently loaded into pf across every feed.
    ///
    /// Feeds with no table are left out rather than counted as zero, so this
    /// is "what is blocked", not "what should be".
    var blockedAddresses: Int {
        feeds.compactMap(\.entries).reduce(0, +)
    }

    /// Feeds that are configured but hold nothing in pf.
    var unloadedFeeds: [PFBlockerFeed] {
        feeds.filter { $0.entries == nil }
    }

    init(_ d: JSONDict) {
        enabled = d.bool("enabled") ?? false
        dnsblEnabled = d.bool("dnsbl") ?? false
        dnsblMode = d.string("dnsbl_mode").flatMap { $0.isEmpty ? nil : $0 }
        accessor = d.string("accessor").flatMap { $0.isEmpty ? nil : $0 }
        foundPaths = (JSONDict(d.value("paths"))?.raw ?? [:])
            .filter { $0.value.boolValue == true }
            .keys.sorted()
        feeds = d.list("feeds").compactMap { JSONDict($0) }.map(PFBlockerFeed.init)
            .sorted { ($0.entries ?? -1) > ($1.entries ?? -1) }
        logs = d.list("logs").compactMap { JSONDict($0) }.map(PFBlockerLogFile.init)
    }
}

// MARK: - DNSBL statistics

/// One row of a "top N" count — a domain, a client, a feed, a group.
struct DNSBLCount: Identifiable {
    var id: String { name }
    var name: String
    var count: Int

    init(_ d: JSONDict) {
        name = d.string("name") ?? "—"
        count = d.int("count") ?? 0
    }
}

/// One hour of the log, labelled as pfBlockerNG labels it.
///
/// The label is text, not a date, and stays that way. pfBlockerNG writes its
/// timestamps with `date('M j H:i:s')` — no year — so anything that turned
/// "Sep 3 01" into a `Date` would be inventing one, and would invent the wrong
/// one for a log that spans a new year.
struct DNSBLHour: Identifiable {
    var id: String { label }
    var label: String
    var count: Int

    /// Just the hour, for an axis that already knows the day.
    var shortLabel: String {
        label.split(separator: " ").last.map(String.init) ?? label
    }

    init(_ d: JSONDict) {
        label = d.string("label") ?? "—"
        count = d.int("count") ?? 0
    }
}

/// What DNSBL has been blocking, from the tail of its log.
struct DNSBLStats {
    /// False when the log does not exist or is empty — DNSBL off, or on and
    /// never having blocked anything.
    var available: Bool
    var logBytes: Double
    var scannedBytes: Double
    /// The log is bigger than the window that was read, so these counts
    /// describe the recent tail rather than the whole log. Said out loud
    /// because a total that silently means "some of it" is worse than no
    /// total.
    var truncated: Bool
    var events: Int
    /// Lines that did not have the nine fields a complete record has — a line
    /// being written as it was read, or a format this app does not know.
    var unparsed: Int
    var first: String?
    var last: String?
    var domains: [DNSBLCount]
    var clients: [DNSBLCount]
    var groups: [DNSBLCount]
    var feeds: [DNSBLCount]
    var hours: [DNSBLHour]

    var busiestHour: DNSBLHour? { hours.max { $0.count < $1.count } }

    init(_ d: JSONDict) {
        available = d.bool("available") ?? false
        logBytes = d.double("bytes") ?? 0
        scannedBytes = d.double("scanned") ?? 0
        truncated = d.bool("truncated") ?? false
        events = d.int("events") ?? 0
        unparsed = d.int("unparsed") ?? 0
        first = d.string("first").flatMap { $0.isEmpty ? nil : $0 }
        last = d.string("last").flatMap { $0.isEmpty ? nil : $0 }
        domains = d.list("domains").compactMap { JSONDict($0) }.map(DNSBLCount.init)
        clients = d.list("clients").compactMap { JSONDict($0) }.map(DNSBLCount.init)
        groups = d.list("groups").compactMap { JSONDict($0) }.map(DNSBLCount.init)
        feeds = d.list("feeds").compactMap { JSONDict($0) }.map(DNSBLCount.init)
        hours = d.list("hours").compactMap { JSONDict($0) }.map(DNSBLHour.init)
    }
}
