import SwiftUI

// MARK: - Health

enum Health {
    case ok, warn, bad, idle, info

    /// `@MainActor` because `ThemeManager` is, and this reads its semantic
    /// roles. `Health` is a plain enum, so without the annotation this method
    /// is nonisolated and every `health.color(theme)` crosses an isolation
    /// boundary — a warning under older compilers and a hard error under the
    /// Swift 6 toolchain in Xcode 26.
    ///
    /// Nothing is lost by requiring the main actor: SwiftUI's `View` protocol
    /// is itself `@MainActor`, so every member of a conforming type is
    /// isolated to it, and every caller of this is a view.
    @MainActor
    func color(_ t: ThemeManager) -> Color {
        switch self {
        case .ok:   return t.ok
        case .warn: return t.warn
        case .bad:  return t.bad
        case .idle: return t.idle
        case .info: return t.info
        }
    }
}

// MARK: - Slab

/// Vaktpost's signature container: a flat slab with a coloured rail down its
/// leading edge. The rail carries the semantic state so colour is never the
/// only cue — the rail's presence and the label text both carry meaning.
struct Slab<Content: View>: View {
    @EnvironmentObject private var theme: ThemeManager

    var rail: Health = .info
    var title: String?
    var trailing: String?
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(rail.color(theme))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 10) {
                if title != nil || trailing != nil {
                    HStack(alignment: .firstTextBaseline) {
                        if let title {
                            Text(title.uppercased())
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .tracking(1.1)
                                .foregroundStyle(theme.labelFaint)
                        }
                        Spacer(minLength: 8)
                        if let trailing {
                            Text(trailing)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(theme.labelFaint)
                        }
                    }
                }
                content
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Status pill

struct StatusPill: View {
    @EnvironmentObject private var theme: ThemeManager
    let text: String
    var health: Health = .idle

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(health.color(theme))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(health.color(theme).opacity(0.16))
            .clipShape(Capsule())
    }
}

// MARK: - Meter

/// A thin capsule meter. `value` is 0...1.
struct Meter: View {
    @EnvironmentObject private var theme: ThemeManager
    let label: String
    let value: Double
    let readout: String
    var health: Health = .info

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.labelMuted)
                Spacer()
                Text(readout)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.label)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.hairline.opacity(0.55))
                    Capsule()
                        .fill(health.color(theme))
                        .frame(width: max(2, geo.size.width * min(max(value, 0), 1)))
                }
            }
            .frame(height: 5)
        }
    }
}

// MARK: - Rows

struct FieldRow: View {
    @EnvironmentObject private var theme: ThemeManager
    let key: String
    let value: String
    var mono: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(key)
                .font(.system(size: 13))
                .foregroundStyle(theme.labelMuted)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: mono ? .monospaced : .default))
                .foregroundStyle(theme.label)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct Hairline: View {
    @EnvironmentObject private var theme: ThemeManager
    var body: some View {
        Rectangle().fill(theme.hairline.opacity(0.5)).frame(height: 1)
    }
}

/// Section heading used above groups of slabs.
struct GroupHeading: View {
    @EnvironmentObject private var theme: ThemeManager
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Text(text.uppercased())
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(theme.labelMuted)
            Rectangle()
                .fill(theme.accentColor.opacity(0.45))
                .frame(height: 2)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Empty / error states

struct Notice: View {
    @EnvironmentObject private var theme: ThemeManager
    let symbol: String
    let title: String
    var detail: String?
    var health: Health = .idle

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(health.color(theme))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.label)
            if let detail {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.labelMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
    }
}

// MARK: - Formatting helpers

enum Fmt {
    static func bytes(_ v: Double) -> String {
        let units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"]
        var value = v
        var i = 0
        while value >= 1024, i < units.count - 1 { value /= 1024; i += 1 }
        return String(format: i == 0 ? "%.0f %@" : "%.1f %@", value, units[i])
    }

    static func uptime(_ seconds: Int) -> String {
        let d = seconds / 86_400
        let h = (seconds % 86_400) / 3_600
        let m = (seconds % 3_600) / 60
        if d > 0 { return "\(d)d \(h)h \(m)m" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    static func pct(_ v: Double) -> String { String(format: "%.0f%%", v) }
}

// MARK: - Sparkline

/// A two-series sparkline. Both series share a scale so in and out are directly
/// comparable, which is the whole point of putting them in one frame.
struct Sparkline: View {
    @EnvironmentObject private var theme: ThemeManager

    let inSeries: [Double]
    let outSeries: [Double]
    var height: CGFloat = 44

    private var peak: Double {
        max(inSeries.max() ?? 0, outSeries.max() ?? 0, 1)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                area(outSeries, in: geo.size, color: theme.info)
                area(inSeries, in: geo.size, color: theme.ok)
            }
        }
        .frame(height: height)
        .background(theme.hairline.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func points(_ values: [Double], in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { idx, v in
            CGPoint(
                x: CGFloat(idx) * step,
                y: size.height - (CGFloat(v / peak) * size.height * 0.92) - 2
            )
        }
    }

    @ViewBuilder
    private func area(_ values: [Double], in size: CGSize, color: Color) -> some View {
        let pts = points(values, in: size)
        if pts.count > 1 {
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: pts[0].x, y: size.height))
                    pts.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: size.height))
                    p.closeSubpath()
                }
                .fill(color.opacity(0.18))

                Path { p in
                    p.move(to: pts[0])
                    pts.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
    }
}

/// Legend + current values shown under a sparkline.
struct RateLegend: View {
    @EnvironmentObject private var theme: ThemeManager
    let inBps: Double?
    let outBps: Double?

    var body: some View {
        HStack(spacing: 14) {
            item("IN", inBps, theme.ok)
            item("OUT", outBps, theme.info)
            Spacer()
        }
    }

    private func item(_ label: String, _ value: Double?, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(theme.labelFaint)
            Text(value.map(Rate.bits) ?? "—")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.label)
        }
    }
}
