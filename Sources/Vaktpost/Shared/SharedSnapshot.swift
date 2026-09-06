import Foundation

/// The payload the app writes to the shared App Group container after each
/// refresh, and the widget reads on its timeline.
///
/// The widget deliberately does no networking: it would need the API key, which
/// would mean a shared keychain access group and a second copy of the TLS
/// pinning logic running outside the app's control. Writing a small snapshot
/// keeps the key in one place. The cost is that the widget only advances while
/// the app is opened or gets a background refresh slot from iOS.
struct SharedSnapshot: Codable {
    enum Level: String, Codable { case ok, warn, bad, idle }

    struct GatewayLine: Codable, Identifiable {
        var id: String { name }
        var name: String
        var status: String
        var delayMS: Double?
        var lossPercent: Double?
        var level: Level
    }

    var serverLabel: String = ""
    var capturedAt: Date = .distantPast
    var level: Level = .idle
    var headline: String = "Not connected"
    var interfacesUp: Int = 0
    var interfacesTotal: Int = 0
    var alertCount: Int = 0
    var gateways: [GatewayLine] = []
    var wanInBps: Double?
    var wanOutBps: Double?

    static let appGroup = "group.se.kladhest.vaktpost"
    static let filename = "snapshot.json"

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(filename)
    }

    static func write(_ snapshot: SharedSnapshot) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func read() -> SharedSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SharedSnapshot.self, from: data)
    }
}
