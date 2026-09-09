import Foundation

enum IncidentSource: String, CaseIterable, Identifiable {
    case firewall = "Firewall"
    case system = "System"
    case authentication = "Authentication"
    case dhcp = "DHCP"
    case vpn = "VPN"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .firewall: return "shield"
        case .system: return "server.rack"
        case .authentication: return "person.badge.key"
        case .dhcp: return "network"
        case .vpn: return "lock.shield"
        }
    }
}

struct IncidentEvent: Identifiable {
    let source: IncidentSource
    let severity: IncidentSeverity
    let line: LogLine
    let date: Date?
    let position: Int

    var id: String { "\(source.rawValue)-\(line.id.uuidString)" }
    var timestampText: String? { line.timestamp ?? line.syslogFields?.timestamp }
}

enum IncidentTimeline {
    static func build(_ sources: [(IncidentSource, [LogLine])], now: Date = Date()) -> [IncidentEvent] {
        var position = 0
        var result: [IncidentEvent] = []
        for (source, lines) in sources {
            for line in lines {
                let rawTimestamp = line.timestamp ?? line.syslogFields?.timestamp
                result.append(IncidentEvent(
                    source: source,
                    severity: IncidentAnalysis.severity(
                        action: line.action ?? line.filterFields?.action,
                        text: line.text
                    ),
                    line: line,
                    date: IncidentAnalysis.date(from: rawTimestamp, now: now),
                    position: position
                ))
                position += 1
            }
        }
        return result.sorted {
            switch ($0.date, $1.date) {
            case let (left?, right?) where left != right: return left > right
            case (_?, nil): return true
            case (nil, _?): return false
            default: return $0.position < $1.position
            }
        }
    }
}
