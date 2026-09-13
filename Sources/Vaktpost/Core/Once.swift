import Foundation
import UIKit
import os

/// Transfers a callback out of the lock before invoking it. Competing terminal
/// events (a button and cancellation, for example) can resolve it only once.
final class Once<Value: Sendable>: Sendable {
    typealias Callback = @Sendable (Value) -> Void
    private let callback: OSAllocatedUnfairLock<Callback?>

    init(_ callback: @escaping Callback) {
        self.callback = OSAllocatedUnfairLock(initialState: callback)
    }

    func resolve(_ value: Value) {
        let callback = callback.withLock { stored -> Callback? in
            defer { stored = nil }
            return stored
        }
        callback?(value)
    }
}

// MARK: - Haptic Feedback

@MainActor
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
