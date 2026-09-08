import Foundation

/// A new binding invalidates every loader and trust decision from the old one.
@MainActor
final class BindingGeneration {
    private(set) var id = UUID()
    func advance() { id = UUID() }
}
