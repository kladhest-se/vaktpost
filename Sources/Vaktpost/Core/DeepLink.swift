import Foundation

/// Deep link types supported by Vaktpost.
///
/// Allows opening the app directly to a specific section, investigation query,
/// or other actionable context.
enum DeepLink: Equatable, Hashable {
    case overview
    case clients
    case network
    case logs
    case investigate(query: String)
    case section(OverviewSection)
    case performance
    case ruleSimulation
    case settings
    
    var tabIdentifier: String? {
        switch self {
        case .overview, .section: return "overview"
        case .clients: return "clients"
        case .network: return "network"
        case .logs: return "logs"
        case .investigate: return "clients"
        case .performance: return nil
        case .ruleSimulation: return nil
        case .settings: return nil
        }
    }
    
    var query: String? {
        switch self {
        case .investigate(let q): return q
        default: return nil
        }
    }
    
    var overviewSection: OverviewSection? {
        switch self {
        case .section(let s): return s
        default: return nil
        }
    }
}

/// Parses deep link URLs.
enum DeepLinkParser {
    static let scheme = "vaktpost"
    static let host = "investigate"
    static let hostSection = "section"
    static let hostOverview = "overview"
    static let hostClients = "clients"
    static let hostNetwork = "network"
    static let hostLogs = "logs"
    static let hostPerformance = "performance"
    static let hostRuleSimulation = "simulator"
    static let hostSettings = "settings"
    
    static func parse(_ url: URL) -> DeepLink? {
        guard url.scheme == scheme else { return nil }
        
        switch url.host {
        case hostOverview, nil:
            return .overview
        case hostClients:
            return .clients
        case hostNetwork:
            return .network
        case hostLogs:
            return .logs
        case hostSection:
            let sectionName = url.path().trimmingCharacters(in: .forwardSlashes)
            if let section = OverviewSection.init(rawValue: sectionName) {
                return .section(section)
            }
            return .overview
        case host, "investigate":
            if let query = url.query?.split(separator: "&").compactMap({ pair in
                let components = String(pair).split(separator: "=")
                return components.count == 2 ? (String(components[0]), String(components[1])) : nil
            }).first(where: { $0.0 == "q" })?.1.removingPercentEncoding {
                return .investigate(query: query)
            }
            let path = url.path().trimmingCharacters(in: .forwardSlashes)
            if !path.isEmpty {
                return .investigate(query: path)
            }
            return nil
        case hostPerformance:
            return .performance
        case hostRuleSimulation:
            return .ruleSimulation
        case hostSettings:
            return .settings
        default:
            return nil
        }
    }
    
    static func buildInvestigationURL(_ query: String) -> URL? {
        URL(string: "\(scheme)://\(host)?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
    }
    
    static func buildSectionURL(_ section: OverviewSection) -> URL? {
        URL(string: "\(scheme)://\(hostSection)/\(section.rawValue)")
    }
}

extension CharacterSet {
    static var forwardSlashes: CharacterSet {
        CharacterSet(charactersIn: "/")
    }
}
