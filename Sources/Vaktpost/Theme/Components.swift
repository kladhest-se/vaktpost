import SwiftUI

// MARK: - Health

enum Health {
    case ok, warn, bad, idle, info

    /// A stable name, for anything that needs to persist a severity — alert
    /// acknowledgements survive relaunches, so they cannot key on a case's
    /// memory representation.
    var name: String {
        switch self {
        case .ok: return "ok"
        case .warn: return "warn"
        case .bad: return "bad"
        case .idle: return "idle"
        case .info: return "info"
        }
    }

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
                                .scaledFont(11, weight: .semibold, design: .rounded)
                                .tracking(1.1)
                                .foregroundStyle(theme.labelFaint)
                        }
                        Spacer(minLength: 8)
                        if let trailing {
                            Text(trailing)
                                .scaledFont(11, weight: .medium, design: .monospaced)
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
            .scaledFont(10, weight: .bold, design: .rounded)
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
                    .scaledFont(13, weight: .medium)
                    .foregroundStyle(theme.labelMuted)
                Spacer()
                Text(readout)
                    .scaledFont(13, weight: .semibold, design: .monospaced)
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
                .scaledFont(13)
                .foregroundStyle(theme.labelMuted)
            Spacer(minLength: 8)
            Text(value)
                .scaledFont(13, weight: .medium, design: mono ? .monospaced : .default)
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
                .scaledFont(12, weight: .heavy, design: .rounded)
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
                .scaledFont(30, weight: .light)
                .foregroundStyle(health.color(theme))
            Text(title)
                .scaledFont(15, weight: .semibold)
                .foregroundStyle(theme.label)
            if let detail {
                Text(detail)
                    .scaledFont(13)
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

    static func date(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: d)
    }

    static func bytesPerSec(_ bps: Double) -> String {
        let units = ["B/s", "KiB/s", "MiB/s", "GiB/s"]
        var v = bps
        var i = 0
        while v >= 1024, i < units.count - 1 { v /= 1024; i += 1 }
        return String(format: i == 0 ? "%.0f %@" : "%.1f %@", v, units[i])
    }
}

// MARK: - Sparkline

/// A two-series sparkline with time axis, gridlines, and tap tooltips.
struct Sparkline: View {
    @EnvironmentObject private var theme: ThemeManager

    let inSeries: [Double]
    let outSeries: [Double]
    var height: CGFloat = 44

    private var peak: Double {
        max(inSeries.max() ?? 0, outSeries.max() ?? 0, 1)
    }

    @State private var showTooltip = false
    @State private var tooltipX: CGFloat?
    @State private var tooltipValue: (in: Double?, out: Double?)?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            yAxisLabels
            
            GeometryReader { geo in
                ZStack {
                    gridlines(in: geo.size)
                    area(outSeries, in: geo.size, color: theme.info)
                    area(inSeries, in: geo.size, color: theme.ok)
                    if showTooltip, let x = tooltipX, let vals = tooltipValue {
                        tooltipLine(at: x, in: geo.size)
                        tooltipMarker(at: x, in: geo.size, color: theme.ok, value: vals.in)
                        tooltipMarker(at: x, in: geo.size, color: theme.info, value: vals.out)
                        
                        if let inVal = vals.in {
                            tooltipLabel(text: "\(Fmt.bytesPerSec(inVal)) IN", at: x, in: geo.size, color: theme.ok, value: inVal)
                        }
                        if let outVal = vals.out {
                            tooltipLabel(text: "\(Fmt.bytesPerSec(outVal)) OUT", at: x, in: geo.size, color: theme.info, value: outVal)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showTooltip.toggle()
                        if showTooltip {
                            let chartX = max(0, min(location.x, geo.size.width))
                            tooltipX = chartX
                            tooltipValue = valueAt(x: chartX, in: geo.size)
                        } else {
                            tooltipValue = nil
                        }
                    }
                }
            }
            .frame(height: height)
            .background(theme.hairline.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Throughput sparkline showing network traffic rates")
    }

    private var yAxisLabels: some View {
        HStack(spacing: 0) {
            Text(Fmt.bytesPerSec(peak))
                .scaledFont(8, design: .monospaced)
                .foregroundStyle(theme.labelFaint.opacity(0.6))
                .lineLimit(1)
            Spacer()
        }
    }

    private func gridlines(in size: CGSize) -> some View {
        ZStack {
            ForEach(0..<4) { i in
                let y = size.height * CGFloat(i) / 3
                Rectangle()
                    .fill(theme.hairline.opacity(0.08))
                    .frame(height: 1)
                    .offset(y: y - 0.5)
            }
        }
    }

    private func yAxisLabels(in size: CGSize) -> some View {
        VStack(spacing: 0) {
            Text(Fmt.bytesPerSec(peak))
                .scaledFont(8, design: .monospaced)
                .foregroundStyle(theme.labelFaint.opacity(0.6))
                .padding(.leading, 2)
            Spacer()
            Text("0")
                .scaledFont(8, design: .monospaced)
                .foregroundStyle(theme.labelFaint.opacity(0.6))
                .padding(.leading, 2)
        }
    }

    private func tooltipLine(at x: CGFloat, in size: CGSize) -> some View {
        Path { p in
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: size.height))
        }
        .stroke(theme.label.opacity(0.3), style: StrokeStyle(lineWidth: 1))
    }

    private func tooltipMarker(at x: CGFloat, in size: CGSize, color: Color, value: Double?) -> some View {
        Group {
            if let value {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .offset(x: x, y: size.height - (CGFloat(value / peak) * size.height * 0.92) - 2 - 3)
                    .shadow(color: color.opacity(0.4), radius: 2)
            }
        }
    }

    private func tooltipLabel(text: String, at x: CGFloat, in size: CGSize, color: Color, value: Double) -> some View {
        let y = size.height - (CGFloat(value / peak) * size.height * 0.92) - 2 - 3
        return Text(text)
            .scaledFont(9, design: .monospaced)
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(color.opacity(0.8), in: Capsule())
            .offset(x: x, y: y - 12)
    }

    private func valueAt(x: CGFloat, in size: CGSize) -> (in: Double?, out: Double?) {
        guard inSeries.count > 1, outSeries.count > 1 else { return (nil, nil) }
        let step = size.width / CGFloat(max(inSeries.count, outSeries.count) - 1)
        let idx = Int(x / step)
        let clampedIdx = idx.clamped(to: 0...inSeries.count)
        return (inSeries[clampedIdx], outSeries[clampedIdx])
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

/// Extension to clamp an integer to a range.
private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}

/// Legend + current values shown under a sparkline.
struct RateLegend: View {
    @EnvironmentObject private var theme: ThemeManager
    let inBps: Double?
    let outBps: Double?

    var body: some View {
        HStack(spacing: 12) {
            item("IN", inBps, theme.ok)
            item("OUT", outBps, theme.info)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Inbound \(inBps.map(Rate.bits) ?? "no data") per second, outbound \(outBps.map(Rate.bits) ?? "no data") per second")
    }

    private func item(_ label: String, _ value: Double?, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label)
                .scaledFont(9, weight: .medium)
                .foregroundStyle(theme.labelFaint)
            Text(value.map(Rate.bits) ?? "—")
                .scaledFont(10, weight: .semibold, design: .monospaced)
                .foregroundStyle(theme.label)
        }
    }
}

// MARK: - Throughput chart

/// Renders a throughput sparkline for a single interface device.
///
/// Wraps the common pattern of fetching points from `ThroughputTracker`,
/// building a `Sparkline`, and showing a `RateLegend`. The `showExplanatoryText`
/// parameter controls the "Derived from counter deltas …" caption shown in
/// Overview but omitted from NetworkView.
struct ThroughputChart: View {
    @EnvironmentObject private var theme: ThemeManager

    /// Observed, not held.
    ///
    /// This was `let store: DashboardStore`, and a plain `let` on a reference
    /// type is why the chart never drew: SwiftUI compares a view's stored
    /// properties to decide whether to re-render, the reference never changes,
    /// so the body ran once and kept whatever it saw. A card created before
    /// the first sample said "none yet" for the rest of the session while the
    /// tracker filled up behind it — which is exactly what the diagnostics
    /// screen showed, three points recorded against a card reporting none.
    ///
    /// Observing the tracker rather than the store also narrows the
    /// invalidation to the thing being drawn.
    @ObservedObject var tracker: ThroughputTracker
    /// Observed for the same reason: the caption reads whether the firewall
    /// reports counters at all, and a stale answer there is the difference
    /// between "waiting" and "will never arrive".
    @ObservedObject var store: DashboardStore
    let device: String
    let height: CGFloat
    var showExplanatoryText: Bool = false

    private var points: [ThroughputTracker.Point] {
        tracker.points(for: device)
    }

    /// Says which of the two situations this is.
    ///
    /// "Collecting samples" for an interface the firewall reports no counters
    /// for is a promise the app cannot keep, and it kept it on screen for a
    /// whole session while the real problem went unnoticed.
    private var caption: String {
        let iface = store.interfaces.first { $0.seriesKey == device }
        if iface?.countersPresent == false {
            return "\(shortDevice) reports no byte counters, so there is nothing to chart."
        }
        return points.isEmpty
            ? "Collecting samples for \(shortDevice) — none yet."
            : "Collecting samples for \(shortDevice) — 1 so far."
    }

    /// The series key carries the interface and its device; only the first is
    /// worth showing a person.
    private var shortDevice: String {
        device.split(separator: "|").first.map(String.init) ?? device
    }

    var body: some View {
        if points.count > 1 {
            VStack(alignment: .leading, spacing: 6) {
                Sparkline(
                    inSeries: points.map(\.inBps),
                    outSeries: points.map(\.outBps),
                    height: height
                )
                RateLegend(inBps: points.last?.inBps, outBps: points.last?.outBps)
                if showExplanatoryText {
                    Text("Derived from counter deltas over the last \(points.count) samples.")
                        .scaledFont(10)
                        .foregroundStyle(theme.labelFaint)
                }
            }
        } else if showExplanatoryText {
            // Only on the Network tab, where the chart is the point of the
            // card. Elsewhere an empty frame with a caption is noise — the
            // totals beside it already say more than a chart with no line.
            //
            // The count and the interface are both named: "collecting samples"
            // on its own cannot distinguish "this started a moment ago" from
            // "no sample will ever arrive", which is exactly the ambiguity
            // that made the throughput bug hard to see.
            Text(caption)
                .scaledFont(12)
                .foregroundStyle(theme.labelFaint)
        }
    }
}

// MARK: - ServerSwitcher

/// A horizontal scrollable row of pill buttons for switching between firewalls.
struct ServerSwitcher: View {
    @EnvironmentObject private var theme: ThemeManager
    let servers: [ServerProfile]
    let activeID: UUID?
    let onSwitch: (ServerProfile) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(servers) { server in
                    Button {
                        onSwitch(server)
                    } label: {
                        Text(server.displayName)
                            .scaledFont(12, weight: .medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(activeID == server.id ? theme.accentColor : theme.card)
                            .foregroundStyle(activeID == server.id
                                             ? theme.palette.crust : theme.labelMuted)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - State trend line

struct StateTrendLine: View {
    @EnvironmentObject private var theme: ThemeManager
    let values: [Int]
    let max: Int

    private var latest: Int { values.last ?? 0 }

    /// Scaled to the data rather than to zero — see SingleMetricSparkline.
    /// A state table steady at 10,856 out of 1,621,000 is otherwise a flat
    /// line pinned to the bottom of an empty box.
    private var bounds: (low: Double, high: Double) {
        let doubles = values.map(Double.init)
        guard let low = doubles.min(), let high = doubles.max() else { return (0, 1) }
        if high - low < 0.001 { return (low - Swift.max(high * 0.15, 1), high + Swift.max(high * 0.15, 1)) }
        let padding = (high - low) * 0.1
        return (low - padding, high + padding)
    }
    private var trend: String {
        guard values.count >= 2 else { return "" }
        let recent = Array(values.suffix(3))
        guard recent.count >= 2 else { return "" }
        let last = Double(recent[recent.count - 1])
        let prev = Double(recent[recent.count - 2])
        if last > prev * 1.2 { return " ↑" }
        if last < prev * 0.8 { return " ↓" }
        return " →"
    }

    var body: some View {
        // Same rule as every other chart here: nothing until there is a line.
        // The Path guarded on it, the frame and the overlay did not — so a
        // single sample drew an empty grey box with "10 256 →" floating in it,
        // under a meter that had already said the same thing.
        if values.count > 1 { chart }
    }

    private var chart: some View {
        GeometryReader { geo in
            Path { path in
                guard values.count > 1 else { return }
                let step = geo.size.width / CGFloat(values.count - 1)
                let span = Swift.max(bounds.high - bounds.low, 0.001)
                let pts = values.enumerated().map { idx, v in
                    CGPoint(
                        x: CGFloat(idx) * step,
                        y: geo.size.height
                            - (CGFloat((Double(v) - bounds.low) / span) * geo.size.height * 0.9) - 1
                    )
                }
                path.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                pts.forEach { path.addLine(to: $0) }
                path.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: geo.size.height))
                path.closeSubpath()
            }
            .fill(theme.warn.opacity(0.15))
        }
        .frame(height: 24)
        .background(theme.hairline.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay(alignment: .trailing) {
            Text("\(latest)\(trend)")
                .scaledFont(10, design: .monospaced)
                .foregroundStyle(theme.labelMuted)
                .padding(.trailing, 6)
        }
    }
}

// MARK: - Single-metric sparkline

struct SingleMetricSparkline: View {
    @EnvironmentObject private var theme: ThemeManager
    let values: [Double]
    let label: String
    var height: CGFloat = 32

    private var latest: Double { values.last ?? 0 }

    /// Where the y-axis starts and ends.
    ///
    /// Scaled to the data, not to zero. Memory sitting at a steady 8% drawn
    /// against a zero baseline is a filled area covering nine tenths of the
    /// frame — which renders as a solid grey block and looks like a broken
    /// chart rather than a flat line.
    ///
    /// A completely flat series gets an artificial span so the line lands in
    /// the middle instead of against an edge.
    private var bounds: (low: Double, high: Double) {
        guard let low = values.min(), let high = values.max() else { return (0, 1) }
        if high - low < 0.001 {
            let padding = Swift.max(high * 0.15, 1)
            return (low - padding, high + padding)
        }
        // A tenth of the span as headroom, so the extremes are not on the edge.
        let padding = (high - low) * 0.1
        return (low - padding, high + padding)
    }

    /// The span the history covers, which is what a chart adds over a meter.
    private var range: String {
        guard let low = values.min(), let high = values.max() else { return "" }
        return low.rounded() == high.rounded()
            ? "steady at \(Fmt.pct(high))"
            : "\(Fmt.pct(low))–\(Fmt.pct(high))"
    }

    @State private var showTooltip = false
    @State private var tooltipValue: Double?
    @State private var tooltipX: CGFloat?

    var body: some View {
        // Nothing at all until there is a line to draw.
        //
        // The Path already guarded on this, but the frame and the footer did
        // not — so a metric with no history rendered an empty box under a
        // caption reading "Memory 0%", directly beneath the live meter saying
        // 8%. Two readings, one of them invented. On first launch every metric
        // is in that state, so the Overview showed each one twice.
        if values.count > 1 {
            chart
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 2) {
            GeometryReader { geo in
                ZStack {
                    gridlines(in: geo.size)
                    Path { path in
                        guard values.count > 1 else { return }
                        let step = geo.size.width / CGFloat(values.count - 1)
                        let span = Swift.max(bounds.high - bounds.low, 0.001)
                        let points = values.enumerated().map { idx, v in
                            CGPoint(
                                x: CGFloat(idx) * step,
                                y: geo.size.height
                                    - (CGFloat((v - bounds.low) / span) * geo.size.height * 0.9)
                                    - 1
                            )
                        }
                        path.move(to: CGPoint(x: points[0].x, y: geo.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(theme.accentColor.opacity(0.2))

                    if showTooltip, let x = tooltipX, let val = tooltipValue {
                        Path { p in
                            p.move(to: CGPoint(x: x, y: 0))
                            p.addLine(to: CGPoint(x: x, y: geo.size.height))
                        }
                        .stroke(theme.label.opacity(0.3), style: StrokeStyle(lineWidth: 1))
                        let span = Swift.max(bounds.high - bounds.low, 0.001)
                        let y = geo.size.height
                            - (CGFloat((val - bounds.low) / span) * geo.size.height * 0.9) - 1
                        Circle()
                            .fill(theme.accentColor)
                            .frame(width: 5, height: 5)
                            .offset(x: x, y: y)
                        
                        Text("\(Int(val)) \(label)")
                            .scaledFont(9, design: .monospaced)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(theme.accentColor.opacity(0.8), in: Capsule())
                            .offset(x: x, y: y - 12)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showTooltip.toggle()
                        if showTooltip {
                            tooltipX = location.x
                            tooltipValue = valueAt(x: location.x, in: geo.size)
                        } else {
                            tooltipValue = nil
                        }
                    }
                }
            }
            .frame(height: height)
            .background(theme.hairline.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            // The range, not the current value.
            //
            // The meter immediately above already gives the label and the
            // latest reading, so repeating both here printed "Memory 8%"
            // directly under a bar that said "Memory 8%". What the history
            // adds is where the value has been.
            HStack {
                Text(range)
                    .scaledFont(10, design: .monospaced)
                    .foregroundStyle(theme.labelFaint)
                Spacer()
                Text("\(values.count) samples")
                    .scaledFont(10)
                    .foregroundStyle(theme.labelFaint)
            }
        }
    }

    private func gridlines(in size: CGSize) -> some View {
        ZStack {
            ForEach(0..<3) { i in
                let y = size.height * CGFloat(i) / 2
                Rectangle()
                    .fill(theme.hairline.opacity(0.06))
                    .frame(height: 1)
                    .offset(y: y - 0.5)
            }
        }
    }

    private func valueAt(x: CGFloat, in size: CGSize) -> Double? {
        guard values.count > 1 else { return nil }
        let step = size.width / CGFloat(values.count - 1)
        let idx = Int(x / step).clamped(to: 0...values.count)
        return values[idx]
    }
}

// MARK: - Gateway trend

struct GatewayTrend: View {
    @EnvironmentObject private var theme: ThemeManager
    let delayPoints: [Double]
    let lossPoints: [Double]
    let latestDelay: Double?
    let latestLoss: Double?

    private var trend: String {
        guard delayPoints.count >= 2 else { return "" }
        let recent = Array(delayPoints.suffix(3))
        guard recent.count >= 2 else { return "" }
        let last = recent[recent.count - 1]
        let prev = recent[recent.count - 2]
        if last > prev * 1.3 { return "↑" }
        if last < prev * 0.7 { return "↓" }
        return "→"
    }

    var body: some View {
        // The gateway card already prints delay and loss above this. With one
        // sample there is no trend and no line either, so this rendered as a
        // stray "0ms →" repeating what was directly above it.
        if delayPoints.count > 1 { chart }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if let delay = latestDelay {
                    Text("\(Int(delay))ms")
                        .scaledFont(10, design: .monospaced)
                }
                Text(trend)
                    .scaledFont(9)
                    .foregroundStyle(trend == "↑" ? theme.bad : trend == "↓" ? theme.ok : theme.labelMuted)
                if let loss = latestLoss, loss > 0 {
                    Text("\(Int(loss))%")
                        .scaledFont(10, design: .monospaced)
                        .foregroundStyle(loss > 5 ? theme.bad : theme.warn)
                }
            }
            if !delayPoints.isEmpty {
                miniSparkline(points: delayPoints, color: theme.warn, label: "ms")
                    .frame(height: 18)
            }
        }
    }

    private func miniSparkline(points: [Double], color: Color, label: String) -> some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<3) { i in
                    let y = geo.size.height * CGFloat(i) / 2
                    Rectangle()
                        .fill(theme.hairline.opacity(0.06))
                        .frame(height: 1)
                        .offset(y: y - 0.5)
                }
                Path { path in
                    guard points.count > 1 else { return }
                    let step = geo.size.width / CGFloat(points.count - 1)
                    let peak = points.max() ?? 1
                    let pts = points.enumerated().map { idx, v in
                        CGPoint(
                            x: CGFloat(idx) * step,
                            y: geo.size.height - (CGFloat(v) / Swift.max(peak, 1) * geo.size.height * 0.85) - 1
                        )
                    }
                    path.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                    pts.forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(color.opacity(0.15))
            }
        }
    }
}

// MARK: - VPN sparkline row

struct VPNSparklineRow: View {
    @EnvironmentObject private var theme: ThemeManager
    let name: String
    let inPoints: [ThroughputTrackerV2.Point]
    let outPoints: [ThroughputTrackerV2.Point]
    let latestIn: Double?
    let latestOut: Double?

    private var inPeak: Double { inPoints.map(\.inBps).max() ?? 1 }
    private var outPeak: Double { outPoints.map(\.outBps).max() ?? 1 }
    private var peak: Double { max(inPeak, outPeak) }

    /// Nothing at all until there is a line to draw.
    ///
    /// An empty frame with "↓ — ↑ —" under it is not a chart waiting to fill,
    /// it is a rectangle of noise: it takes vertical space, draws attention,
    /// and says less than the transfer totals already shown above it.
    var body: some View {
        if inPoints.count > 1 || outPoints.count > 1 { chart }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    Path { path in
                        guard outPoints.count > 1 else { return }
                        let step = geo.size.width / CGFloat(outPoints.count - 1)
                        let pts = outPoints.enumerated().map { idx, v in
                            CGPoint(x: CGFloat(idx) * step,
                                    y: geo.size.height - (CGFloat(v.outBps / max(outPeak, 1)) * geo.size.height * 0.85) - 1)
                        }
                        path.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        pts.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(theme.info.opacity(0.15))

                    Path { path in
                        guard inPoints.count > 1 else { return }
                        let step = geo.size.width / CGFloat(inPoints.count - 1)
                        let pts = inPoints.enumerated().map { idx, v in
                            CGPoint(x: CGFloat(idx) * step,
                                    y: geo.size.height - (CGFloat(v.inBps / max(inPeak, 1)) * geo.size.height * 0.85) - 1)
                        }
                        path.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        pts.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(theme.ok.opacity(0.15))

                    Path { path in
                        guard inPoints.count > 1 else { return }
                        let step = geo.size.width / CGFloat(inPoints.count - 1)
                        let pts = inPoints.enumerated().map { idx, v in
                            CGPoint(x: CGFloat(idx) * step,
                                    y: geo.size.height - (CGFloat(v.inBps / max(inPeak, 1)) * geo.size.height * 0.85) - 1)
                        }
                        path.move(to: pts[0])
                        pts.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(theme.ok, style: StrokeStyle(lineWidth: 1.2))

                    Path { path in
                        guard outPoints.count > 1 else { return }
                        let step = geo.size.width / CGFloat(outPoints.count - 1)
                        let pts = outPoints.enumerated().map { idx, v in
                            CGPoint(x: CGFloat(idx) * step,
                                    y: geo.size.height - (CGFloat(v.outBps / max(outPeak, 1)) * geo.size.height * 0.85) - 1)
                        }
                        path.move(to: pts[0])
                        pts.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(theme.info, style: StrokeStyle(lineWidth: 1.2))
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 28)
            .background(theme.hairline.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            HStack(spacing: 8) {
                // The closing paren belongs to `map`, not to the interpolation
                // — written the other way it printed "↓ -)/s", and appended a
                // second unit onto a value that already carries one.
                Text("↓ \(latestIn.map(Fmt.bytesPerSec) ?? "—")")
                    .scaledFont(10, design: .monospaced)
                    .foregroundStyle(theme.ok)
                Text("↑ \(latestOut.map(Fmt.bytesPerSec) ?? "—")")
                    .scaledFont(10, design: .monospaced)
                    .foregroundStyle(theme.info)
            }
        }
    }
}

/// A system notice, which may be one line or an entire stack trace.
///
/// Collapsed by default: shown whole, a PHP backtrace fills the screen and
/// buries everything below it. Tapping expands.
struct NoticeText: View {
    @EnvironmentObject private var theme: ThemeManager
    let notice: SystemNotice
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if notice.isFromThisApp {
                // Owning it. A snippet that throws is recorded by pfSense as a
                // notice, which this app then reads back and shows — so its own
                // bug arrives looking like a firewall fault.
                StatusPill(text: "raised by Vaktpost", health: .warn)
            }

            Text(expanded ? notice.notice : notice.summary)
                .scaledFont(13, design: notice.isMultiline ? .monospaced : .default)
                .foregroundStyle(theme.label)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if notice.isMultiline {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    Text(expanded ? "Show less" : "Show full notice")
                        .scaledFont(12, weight: .medium)
                        .foregroundStyle(theme.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Page Header

struct PageHeader: View {
    @EnvironmentObject private var theme: ThemeManager
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(title)
                .scaledFont(22, weight: .semibold)
                .foregroundStyle(theme.label)
            if let subtitle {
                Text(subtitle)
                    .scaledFont(13)
                    .foregroundStyle(theme.labelMuted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}
