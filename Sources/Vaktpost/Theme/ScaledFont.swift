import SwiftUI

/// A system font at a fixed size that scales with the person's text setting.
///
/// `Font.system(size:)` does not scale — it is the same points whether text is
/// set to xSmall or to the largest accessibility size. Every font in this app
/// was written that way, which meant somebody who needs larger text got a
/// dashboard they could not read.
///
/// `Font.custom(_:size:relativeTo:)` scales but needs a font name, and naming
/// the system font by string is fragile across releases. `@ScaledMetric` gives
/// the ratio the chosen text style is currently scaled by, which multiplies
/// cleanly and keeps the system font.
///
/// Relative to `.body` throughout: the sizes here were chosen against each
/// other, and scaling them by different curves would pull a card apart at
/// large sizes.
private struct ScaledFont: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight, design: design))
    }
}

extension View {
    /// A font that respects the person's text size.
    ///
    /// Drop-in for `.font(.system(size:weight:design:))` — same arguments, same
    /// appearance at the default text size.
    func scaledFont(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design))
    }
}

/// A frame width that grows with text.
///
/// For the columns an icon or a label sits in: a 22pt icon well clips a symbol
/// that has scaled to 30pt, and a fixed label column truncates its own label.
///
/// A `ViewModifier` rather than a value type, because `@ScaledMetric` only
/// reads the environment from inside a `View` — a struct holding one outside
/// the view hierarchy silently returns the unscaled number, which is worse
/// than not having it.
///
/// Decorative rules — the 2 and 3 point rails down the side of a card — are
/// deliberately left fixed. They are not text and do not need to grow.
private struct ScaledFrameWidth: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    let width: CGFloat
    let alignment: Alignment

    func body(content: Content) -> some View {
        content.frame(width: width * scale, alignment: alignment)
    }
}

extension View {
    func scaledFrame(width: CGFloat, alignment: Alignment = .center) -> some View {
        modifier(ScaledFrameWidth(width: width, alignment: alignment))
    }
}
