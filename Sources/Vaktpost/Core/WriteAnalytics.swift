import Foundation
import Observation

/// Tracks analytics for write operations on the firewall.
///
/// Records success and failure counts per operation type and calculates
/// success rates. Data is persisted to disk for aggregate statistics.
@MainActor
@Observable
final class WriteAnalytics {

    /// A single analytics event.
    private struct Event: Codable {
        let operation: String
        let success: Bool
        let timestamp: Date
    }

    private var events: [Event] = []

    /// Storage URL for analytics data.
    private var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("vaktpost/write-analytics.json")
    }

    /// Maximum number of events to keep before evicting oldest.
    private static let maxEvents = 1000

    init() {
        let directory = storageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    /// Records the result of a write operation.
    ///
    /// - Parameters:
    ///   - operation: The operation type (e.g. "quick_block", "restart_service").
    ///   - success: Whether the operation succeeded.
    func record(operation: String, success: Bool) {
        let event = Event(operation: operation, success: success, timestamp: Date())
        events.append(event)
        if events.count > Self.maxEvents {
            events.removeFirst(events.count - Self.maxEvents)
        }
        save()
    }

    /// Returns the success rate for a specific operation type.
    ///
    /// - Parameter operation: The operation type to query.
    /// - Returns: Success rate as a decimal (0.0 to 1.0), or nil if no events found.
    func successRate(for operation: String) -> Double? {
        let ops = events.filter { $0.operation == operation }
        guard !ops.isEmpty else { return nil }
        let successes = ops.filter { $0.success }.count
        return Double(successes) / Double(ops.count)
    }

    /// Returns the success rate for all operations.
    var overallSuccessRate: Double? {
        guard !events.isEmpty else { return nil }
        let successes = events.filter { $0.success }.count
        return Double(successes) / Double(events.count)
    }

    /// Returns the total number of operations.
    var totalOperations: Int {
        events.count
    }

    /// Returns the number of successful operations.
    var successfulOperations: Int {
        events.filter { $0.success }.count
    }

    /// Returns the number of failed operations.
    var failedOperations: Int {
        events.filter { !$0.success }.count
    }

    /// Returns statistics grouped by operation type.
    var statisticsByOperation: [String: OperationStats] {
        let grouped = Dictionary(grouping: events) { $0.operation }
        return grouped.mapValues { group in
            let successes = group.filter { $0.success }.count
            return OperationStats(
                count: group.count,
                successes: successes,
                failures: group.count - successes,
                successRate: Double(successes) / Double(group.count)
            )
        }
    }

    /// Clears all analytics data.
    func clear() {
        events.removeAll()
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(events)
            try data.write(to: storageURL, options: .completeFileProtection)
        } catch {
            // Silently fail
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            events = try JSONDecoder().decode([Event].self, from: data)
        } catch {
            events = []
        }
    }

    /// Statistics for a single operation type.
    struct OperationStats {
        let count: Int
        let successes: Int
        let failures: Int
        let successRate: Double
    }
}
