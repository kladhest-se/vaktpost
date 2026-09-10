import Foundation
import UIKit

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

// MARK: - Haptic Feedback

enum HapticFeedback {
    static let notification = UINotificationFeedbackGenerator()
    static let impact = UIImpactFeedbackGenerator(style: .medium)
    static let selection = UISelectionFeedbackGenerator()

    static func alertDismiss() {
        notification.notificationOccurred(.success)
    }

    static func warning() {
        notification.notificationOccurred(.warning)
    }

    static func error() {
        notification.notificationOccurred(.error)
    }

    static func sectionReorder() {
        impact.impactOccurred()
    }

    static func selectionHaptic() {
        selection.selectionChanged()
    }

    static func prepare() {
        notification.prepare()
        impact.prepare()
        selection.prepare()
    }
}
