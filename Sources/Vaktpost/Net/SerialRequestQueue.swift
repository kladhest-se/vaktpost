import Foundation

/// Reserve each place in the queue before suspending. Cancellation skips the
/// cancelled operation, but its successor still waits for earlier work.
actor SerialRequestQueue {
    private var tail: Task<Void, Never>?
    private var tailID: UUID?
    private var cancellations: [UUID: () -> Void] = [:]
    private var invalidated = false

    func run<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        guard !invalidated else { throw CancellationError() }
        let id = UUID()
        let previous = tail
        let task = Task {
            await previous?.value
            try Task.checkCancellation()
            return try await operation()
        }
        tail = Task { _ = try? await task.value }
        tailID = id
        cancellations[id] = { task.cancel() }
        defer {
            cancellations[id] = nil
            if tailID == id {
                tail = nil
                tailID = nil
            }
        }
        return try await withTaskCancellationHandler {
            let value = try await task.value
            try Task.checkCancellation()
            return value
        } onCancel: {
            task.cancel()
        }
    }

    func invalidate() {
        invalidated = true
        for cancel in cancellations.values { cancel() }
    }
}
