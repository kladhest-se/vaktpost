import Foundation

/// Transfers a callback out of the lock before invoking it. Competing terminal
/// events (a button and cancellation, for example) can resolve it only once.
final class Once<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: ((Value) -> Void)?

    init(_ callback: @escaping (Value) -> Void) { self.callback = callback }

    func resolve(_ value: Value) {
        lock.lock()
        let callback = self.callback
        self.callback = nil
        lock.unlock()
        callback?(value)
    }
}
