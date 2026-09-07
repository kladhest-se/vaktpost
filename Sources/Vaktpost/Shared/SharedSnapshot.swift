import Foundation
import os.log

private let snapshotLog = OSLog(subsystem: "se.kladhest.vaktpost", category: "Snapshot")

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
    /// User-configured refresh interval in seconds, used by the widget to
    /// size its timeline.
    var refreshSeconds: Int = 30

    /// The name of the theme the user has chosen, used by the widget so it
    /// can match the app's colours instead of blindly following the system.
    var themeName: String = ""

    static let appGroup = "group.se.kladhest.vaktpost"
    static let filename = "snapshot.json"

    enum ContainerStatus {
        case available
        case missingEntitlement
        case notWritable
    }

    static var containerStatus: ContainerStatus {
        guard let url = fileURL else { return .missingEntitlement }
        do {
            let testFile = url.appendingPathComponent(".write-test")
            try "test".write(to: testFile, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: testFile)
            return .available
        } catch {
            os_log(.error, log: snapshotLog, "App Group container not writable: %{public}@", error.localizedDescription)
            return .notWritable
        }
    }

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(filename)
    }

    static func write(_ snapshot: SharedSnapshot) {
        guard let url = fileURL else {
            os_log(.error, log: snapshotLog, "SharedSnapshot: no App Group container URL")
            return
        }
        guard let data = try? JSONEncoder().encode(snapshot) else {
            os_log(.error, log: snapshotLog, "SharedSnapshot: failed to encode snapshot")
            return
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            os_log(.error, log: snapshotLog, "SharedSnapshot: failed to write: %{public}@", error.localizedDescription)
        }
    }

    static func read() -> SharedSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SharedSnapshot.self, from: data)
    }
}
