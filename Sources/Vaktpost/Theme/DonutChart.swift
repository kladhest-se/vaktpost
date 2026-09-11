import SwiftUI

/// A donut, for a breakdown where the parts are meant to be read against the
/// whole.
///
/// Deliberately a donut rather than a pie. The hole is where the total goes,
/// and a total is the thing that makes the slices mean anything — 33% of nine
/// requests and 33% of nine thousand are the same wedge and not the same fact.
///
/// Hand-drawn with `Path`, like `Sparkline` and `RowTrace`, rather than pulling
/// in Swift Charts for one shape. The app draws its own small visuals and they
/// look like each other because of it.
struct DonutChart: View {
    @Environment(\.themeManager) private var theme: ThemeManager

    struct Slice: Identifiable {
        let id: String
        let label: String
        let value: Int
        let color: Color
    }

    let slices: [Slice]
    /// What goes in the hole. Usually the total the slices add up to.
    var centerValue: String?
    var centerCaption: String?
    var thickness: CGFloat = 16

    private var total: Double {
        max(1, slices.reduce(0.0) { $0 + Double(max(0, $1.value)) })
    }

    /// Where each slice starts, as a running total of the ones before it.
    private func start(before index: Int) -> Double {
        slices.prefix(index).reduce(0.0) { $0 + Double(max(0, $1.value)) }
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = side / 2
            ZStack {
                ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                    // A hairline gap between slices, in degrees, so adjacent
                    // colours of similar weight stay countable. Skipped when a
                    // slice is too small to survive it — better a thin wedge
                    // than a missing one.
                    let sweep = 360 * Double(max(0, slice.value)) / total
                    let gap = sweep > 4 ? 1.0 : 0.0
                    let from = 360 * start(before: index) / total
                    Path { path in
                        path.addArc(center: CGPoint(x: radius, y: radius),
                                    radius: radius - thickness / 2,
                                    startAngle: .degrees(from - 90 + gap / 2),
                                    endAngle: .degrees(from + sweep - 90 - gap / 2),
                                    clockwise: false)
                    }
                    .stroke(slice.color,
                            style: StrokeStyle(lineWidth: thickness, lineCap: .butt))
                }

                if centerValue != nil || centerCaption != nil {
                    VStack(spacing: 1) {
                        if let centerValue {
                            Text(centerValue)
                                .scaledFont(17, weight: .bold, design: .rounded)
                                .foregroundStyle(theme.label)
                        }
                        if let centerCaption {
                            Text(centerCaption)
                                .scaledFont(8)
                                .foregroundStyle(theme.labelFaint)
                        }
                    }
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// Spoken as proportions, because that is what the shape is for. A
    /// screen reader gets the reading, not a description of a circle.
    private var accessibilityText: String {
        let parts = slices.prefix(5).map { slice in
            "\(slice.label), \(Int((Double(slice.value) / total * 100).rounded())) percent"
        }
        return parts.joined(separator: ". ")
    }
}

extension DonutChart {
    /// Colours for a breakdown, in an order that stays legible next to itself.
    ///
    /// Picked from the flavour's own accents rather than generated, so a donut
    /// looks like the rest of the app in all four themes. Ordered to keep
    /// neighbouring hues apart — adjacent slices are the ones hardest to tell
    /// from each other.
    static func colors(_ theme: ThemeManager) -> [Color] {
        let p = theme.palette
        return [p.blue, p.peach, p.green, p.mauve, p.yellow, p.teal,
                p.pink, p.sapphire, p.maroon, p.lavender]
    }

    /// Build slices from counted rows, folding everything past `limit` into a
    /// single remainder.
    ///
    /// `total` is passed separately rather than summed from `rows`, because
    /// the rows are a top-N and the total is every event. Summing them would
    /// make the percentages describe the top ten rather than the whole, which
    /// is the ordinary way a chart like this ends up lying.
    static func slices(_ rows: [DNSBLCount], total: Int, limit: Int,
                       theme: ThemeManager) -> [Slice] {
        let palette = colors(theme)
        var out = rows.prefix(limit).enumerated().map { index, row in
            Slice(id: row.name, label: row.name, value: row.count,
                  color: palette[index % palette.count])
        }
        let counted = out.reduce(0) { $0 + $1.value }
        if total > counted {
            out.append(Slice(id: "__other", label: "Other", value: total - counted,
                             color: theme.palette.overlay0))
        }
        return out
    }
}

/// The names and shares beside a donut.
struct DonutLegend: View {
    @Environment(\.themeManager) private var theme: ThemeManager

    let slices: [DonutChart.Slice]

    private var total: Double {
        max(1, slices.reduce(0.0) { $0 + Double(max(0, $1.value)) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(slices) { slice in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(slice.color)
                        .frame(width: 8, height: 8)
                    Text(slice.label)
                        .scaledFont(11)
                        .foregroundStyle(theme.label)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text("\(Int((Double(slice.value) / total * 100).rounded()))%")
                        .scaledFont(11, weight: .semibold, design: .monospaced)
                        .foregroundStyle(theme.labelMuted)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
