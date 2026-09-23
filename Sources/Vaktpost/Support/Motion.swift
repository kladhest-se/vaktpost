import SwiftUI
import UIKit

/// Animation, subject to the person's Reduce Motion setting.
///
/// Every animation in this app goes through here. Passing `nil` to
/// `withAnimation` or `.animation(_:value:)` performs the same change with no
/// animation at all, which is exactly what Reduce Motion asks for: the app
/// still updates, it just stops moving to get there.
///
/// Read at the moment the animation is about to run rather than held in a
/// view's environment, so a change made in Settings applies to the next
/// animation without the app having to be relaunched.
enum Motion {
    /// The animation to use, or `nil` when the person has asked for less
    /// motion.
    ///
    /// `assumeIsolated` rather than `@MainActor`: the callers are SwiftUI
    /// view bodies, gesture handlers and drop delegates, which all run on the
    /// main actor but are not all statically isolated to it, and an
    /// `await` in the middle of a drag gesture would be worse than this
    /// assertion. Reading an accessibility setting off the main thread is a
    /// bug either way; this makes it a loud one.
    nonisolated static func animation(_ animation: Animation) -> Animation? {
        isReduced ? nil : animation
    }

    /// Whether motion should be avoided right now.
    ///
    /// For the cases a `nil` animation cannot cover: a repeating pulse that
    /// exists only to draw the eye, which should not be drawn at all rather
    /// than drawn instantly.
    nonisolated static var isReduced: Bool {
        MainActor.assumeIsolated { UIAccessibility.isReduceMotionEnabled }
    }
}
