import Foundation
import Observation

/// Throttles write operations to prevent overwhelming the firewall.
///
/// Enforces a minimum interval between consecutive writes. If a write is
/// attempted too soon, the caller receives `false` and should retry later
/// or queue the operation.
@MainActor
@Observable
final class WriteRateLimiter {

    /// How many seconds must elapse between writes.
    private let minimumInterval: TimeInterval

    private var lastWriteTime: Date?

    /// Creates a rate limiter with the given minimum interval.
    ///
    /// - Parameter minimumInterval: Minimum seconds between writes. Defaults to 2.
    init(minimumInterval: TimeInterval = 2) {
        self.minimumInterval = minimumInterval
    }

    /// Returns whether a write is allowed right now.
    ///
    /// If the caller is allowed to write, this records the timestamp so the
    /// next call cannot proceed until `minimumInterval` has elapsed.
    func allowWrite() -> Bool {
        let now = Date()
        guard let last = lastWriteTime else {
            lastWriteTime = now
            return true
        }
        let elapsed = now.timeIntervalSince(last)
        if elapsed >= minimumInterval {
            lastWriteTime = now
            return true
        }
        return false
    }

    /// Forces the rate limiter to allow the next write immediately.
    ///
    /// Use this after a successful apply or when the user explicitly
    /// requests to bypass the throttle (e.g. via a "force apply" option).
    func bypass() {
        lastWriteTime = nil
    }
}
