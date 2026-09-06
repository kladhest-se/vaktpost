import Foundation

/// Renders a v2 filter address, which may be a plain string or an object with
/// `any` / `network` / `address` / `port` members depending on the rule.
struct FilterAddress {
    var text: String

    init(_ value: JSONValue?, port: JSONValue? = nil) {
        var base = "any"
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
                if let p = d.string("port"), !p.isEmpty { base += ":" + p }
            }
        }
        if let p = port?.stringValue, !p.isEmpty, !base.contains(":") {
            base += ":" + p
        }
        text = base
    }
}

struct FirewallRule: Identifiable {
    var id: String { tracker.isEmpty ? "\(interfaceName)-\(descr)-\(source)-\(destination)" : tracker }
    var tracker: String
    var interfaceName: String
    var type: String            // pass / block / reject
    var ipProtocol: String?     // inet / inet6
    var proto: String?
    var source: String
    var destination: String
    var descr: String
    var disabled: Bool
    var logged: Bool

    init(_ d: JSONDict) {
        tracker = d.string("tracker") ?? ""
        let ifaces = d.list("interface").compactMap { $0.stringValue }
        interfaceName = ifaces.isEmpty ? (d.string("interface") ?? "—") : ifaces.joined(separator: ",")
        type = (d.string("type") ?? "").lowercased()
        ipProtocol = d.string("ipprotocol")
        proto = d.string("protocol")
        source = FilterAddress(d.value("source"), port: d.value("source_port")).text
        destination = FilterAddress(d.value("destination"), port: d.value("destination_port")).text
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
        addresses = d.list("address").compactMap { $0.stringValue }
        details = d.list("detail").compactMap { $0.stringValue }
    }
}

struct PortForward: Identifiable {
    var id: String { "\(interfaceName)-\(destination)-\(target)" }
    var interfaceName: String
    var proto: String?
    var destination: String
    var target: String
    var localPort: String?
    var descr: String
    var disabled: Bool

    init(_ d: JSONDict) {
        interfaceName = d.string("interface") ?? "—"
        proto = d.string("protocol")
        destination = FilterAddress(d.value("destination"), port: d.value("destination_port")).text
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
