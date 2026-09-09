import Foundation
import Observation

/// Each selection owns its result and loading state. An obsolete request may
/// finish even after cancellation, but cannot replace the selected range.
@MainActor
final class HistoryLoader<Key: Hashable, Value>: Observable {
    struct Entry {
        let value: Value
        let fetchedAt: Date
    }
    var key: Key?
    var value: Value?
    var fetchedAt: Date?
    var isLoading = false
    var error: String?
    private(set) var cache: [Key: Entry] = [:]
    private var failedKeys: Set<Key> = []
    private var requestID = UUID()
    private let lifetime: TimeInterval
    private let now: () -> Date

    init(lifetime: TimeInterval = 300, now: @escaping () -> Date = Date.init) {
        self.lifetime = lifetime
        self.now = now
    }

    func load(_ key: Key, force: Bool = false,
              fetch: @escaping @MainActor () async throws -> Value) async -> Bool {
        guard !Task.isCancelled else { return false }
        task?.cancel()
        let id = UUID()
        requestID = id
        self.key = key
        error = nil
        let cached = cache[key]
        value = cached?.value
        fetchedAt = cached?.fetchedAt
        if !force, !failedKeys.contains(key), let cached, now().timeIntervalSince(cached.fetchedAt) >= 0,
           now().timeIntervalSince(cached.fetchedAt) < lifetime {
            isLoading = false
            task = nil
            return true
        }
        isLoading = true
        let task = Task { try await fetch() }
        self.task = task
        defer {
            if requestID == id { isLoading = false; self.task = nil }
        }
        do {
            let result = try await withTaskCancellationHandler {
                let result = try await task.value
                try Task.checkCancellation()
                return result
            } onCancel: { task.cancel() }
            guard requestID == id else { return false }
            let date = now()
            failedKeys.remove(key)
            cache[key] = Entry(value: result, fetchedAt: date)
            value = result
            fetchedAt = date
            return true
        } catch {
            guard requestID == id, !Task.isCancelled else { return false }
            if error is CancellationError { return false }
            failedKeys.insert(key)
            self.error = error.localizedDescription
            return true
        }
    }

    func reset() {
        requestID = UUID()
        task?.cancel()
        task = nil
        cache.removeAll()
        failedKeys.removeAll()
        key = nil
        value = nil
        fetchedAt = nil
        isLoading = false
        error = nil
    }

    private var task: Task<Value, Error>?
}
