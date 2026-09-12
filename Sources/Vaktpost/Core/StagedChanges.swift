import Foundation
import Observation

/// Manages staged write operations for the staged-apply pattern.
///
/// Changes are accumulated in memory and persisted to disk so they survive
/// app restarts. At apply time all changes are sent to the firewall in a
/// single batch, reducing the number of round trips and ensuring atomicity.
@MainActor
@Observable
final class StagedChanges {

    /// Represents a single staged change.
    struct Change: Identifiable, Codable {
        let id: UUID
        let action: String
        let target: String?
        let description: String
        let timestamp: Date

        /// Human-readable label for the change.
        var summary: String {
            if let target {
                return "\(action): \(target)"
            }
            return action
        }
    }

    private var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("vaktpost/staged-changes.json")
    }

    private(set) var changes: [Change] = [] {
        didSet { save() }
    }

    /// Whether there are pending changes.
    var hasPendingChanges: Bool { !changes.isEmpty }

    /// Total number of pending changes.
    var count: Int { changes.count }

    init() {
        // Ensure the directory exists
        let directory = storageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Load persisted changes
        load()
    }

    /// Stages a new change.
    ///
    /// - Parameters:
    ///   - action: Category of the change (e.g. "add_rule", "delete_alias").
    ///   - target: What is being changed (e.g. rule number, alias name).
    ///   - description: Human-readable description.
    func stage(action: String, target: String? = nil, description: String) {
        let change = Change(
            id: UUID(),
            action: action,
            target: target,
            description: description,
            timestamp: Date()
        )
        changes.append(change)
    }

    /// Removes a specific change from the staging area.
    func discard(_ change: Change) {
        changes.removeAll { $0.id == change.id }
    }

    /// Discards all pending changes.
    func discardAll() {
        changes.removeAll()
    }

    /// Returns a summary of all pending changes.
    var summary: String {
        let grouped = Dictionary(grouping: changes) { $0.action }
        return grouped.map { "\($1.count) \($0)" }.joined(separator: "\n")
    }

    /// Clears the stage.
    func clear() {
        changes.removeAll()
    }

    /// Persists changes to disk.
    private func save() {
        do {
            let data = try JSONEncoder().encode(changes)
            try data.write(to: storageURL, options: .completeFileProtection)
        } catch {
            // Silently fail - changes will be recovered from memory on restart
        }
    }

    /// Loads changes from disk.
    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }

        do {
            let data = try Data(contentsOf: storageURL)
            let decoded = try JSONDecoder().decode([Change].self, from: data)
            changes = decoded
        } catch {
            // Silently fail - start with empty changes
            changes = []
        }
    }
}
