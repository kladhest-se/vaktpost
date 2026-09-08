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
    var address: String
    var port: String?

    init(_ value: JSONValue?, port explicitPort: JSONValue? = nil) {
        var base = "any"
        var found: String?

        if let value {
            if let s = value.stringValue, !s.isEmpty {
                base = s
            } else if let d = JSONDict(value) {
                if d.bool("any") == true {
                    base = "any"
                } else if let n = d.string("network") {
                    base = n
                } else if let a = d.string("address") {
                    base = a
                }
                if let p = d.string("port"), !p.isEmpty { found = p }
            }
        }
        if found == nil, let p = explicitPort?.stringValue, !p.isEmpty { found = p }

        address = base
        port = found
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
        interfaceName.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.count > 1
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
    var id: String { "\(interfaceName)-\(destination)-\(target)" }
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

    var destination: String { destinationSide.text }
    var descr: String
    var disabled: Bool

    init(_ d: JSONDict) {
        interfaceName = d.string("interface") ?? "—"
        proto = d.string("protocol")
        sourceSide = FilterAddress(d.value("source"), port: d.value("source_port"))
        destinationSide = FilterAddress(d.value("destination"), port: d.value("destination_port"))
        target = d.string("target") ?? FilterAddress(d.value("target")).text
        localPort = d.string("local_port")
        descr = d.string("descr", "description") ?? ""
        disabled = d.bool("disabled") ?? false
    }

    var targetLabel: String {
        guard let p = localPort, !p.isEmpty else { return target }
        return "\(target):\(p)"
    }

    var health: Health { disabled ? .idle : .info }
}
