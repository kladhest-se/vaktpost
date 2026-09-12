import Foundation

/// Performs an async operation with retry logic.
///
/// Retries transient failures up to a configurable number of times with
/// exponential backoff. Non-retryable errors are thrown immediately.
@MainActor
struct Retrier {

    /// Maximum number of attempts (including the first).
    private let maxAttempts: Int

    /// Base delay in seconds between retries.
    private let baseDelay: TimeInterval

    /// Creates a retrier with the given configuration.
    ///
    /// - Parameters:
    ///   - maxAttempts: Maximum number of attempts. Defaults to 2.
    ///   - baseDelay: Base delay in seconds. Defaults to 1.0.
    init(maxAttempts: Int = 2, baseDelay: TimeInterval = 1.0) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
    }

    /// Executes an async operation with retry logic.
    ///
    /// - Parameters:
    ///   - operation: The async operation to execute.
    /// - Returns: The result of the operation.
    /// - Throws: The error if all attempts fail.
    func retry<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                let result = try await operation()
                return result
            } catch {
                lastError = error

                let rpcError = error as? RPCError
                guard rpcError?.isRetryable == true else {
                    throw error
                }

                if attempt < maxAttempts {
                    let delay = baseDelay * TimeInterval(attempt - 1)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        throw lastError ?? RPCError.transport("All attempts failed")
    }
}
