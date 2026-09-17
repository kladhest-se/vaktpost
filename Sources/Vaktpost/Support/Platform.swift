import Foundation

/// Where this build is actually running.
///
/// Vaktpost ships one iOS binary. On Apple Silicon Macs the App Store offers
/// that same binary as a "Designed for iPad" app, where it runs unmodified
/// but under macOS window and lifecycle rules. `#if os(macOS)` and
/// `targetEnvironment(macCatalyst)` are both false there, so the only honest
/// test is the runtime one.
///
/// Kept to the few behaviours that are genuinely wrong on a Mac rather than
/// merely different; everything else is left to UIKit's own translation.
enum Platform {
    /// True when the iPad binary is running on an Apple Silicon Mac.
    static var isMac: Bool {
        ProcessInfo.processInfo.isiOSAppOnMac
    }
}
