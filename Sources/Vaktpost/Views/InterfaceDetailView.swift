import SwiftUI

/// One interface, watched closely.
///
/// The dashboard samples every thirty seconds, which is right for a screen you
/// glance at and wrong for watching a transfer start. This polls every two
/// seconds while it is open and stops the moment it is dismissed — SwiftUI
/// cancels the `.task`, and the loop checks for it.
///
/// Two seconds rather than something faster is deliberate. Every poll is an
/// `exec_php` that pfSense serialises against the webConfigurator, so a tighter
/// loop would make the firewall's own web UI feel slow while this screen is
/// open. That trade is worth naming rather than hiding: this is the one place
/// in the app that deliberately costs the firewall something.
struct InterfaceDetailView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore

    let iface: InterfaceStat

    /// The live series, which starts empty each time the screen opens.
    private var points: [ThroughputTracker.Point] {
        store.liveThroughput.points(for: iface.seriesKey)
    }

    private var latest: ThroughputTracker.Point? { points.last }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                chart
                rates
                history
                counters
                note
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .task { await store.monitorInterface(iface.seriesKey) }
        // Widening on open only. A tap on "8 hours" is answered with 8 hours,
        // and the empty chart explains itself — silently showing a different
        // span than the one selected would be worse than showing nothing.
        .task { await store.loadRRD(widenIfEmpty: true) }
        .navigationTitle(iface.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Pieces

    private var header: some View {
        Slab(rail: iface.health, trailing: iface.device) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(iface.name)
                        .scaledFont(16, weight: .bold)
                        .foregroundStyle(theme.label)
                    Spacer()
                    StatusPill(text: iface.status, health: iface.health)
                }
                Text(iface.addressLine)
                    .scaledFont(12, design: .monospaced)
                    .foregroundStyle(theme.labelMuted)
                    .textSelection(.enabled)
                if let media = iface.media, !media.isEmpty {
                    Text(media)
                        .scaledFont(11)
                        .foregroundStyle(theme.labelFaint)
                }
            }
        }
    }

    @ViewBuilder
    private var chart: some View {
        Slab(rail: .info, title: "Throughput") {
            VStack(alignment: .leading, spacing: 8) {
                if let err = store.liveError {
                    Text(err)
                        .scaledFont(12)
                        .foregroundStyle(theme.warn)
                }

                if points.count > 1 {
                    LiveThroughputChart(points: points)
                        .frame(height: 180)
                } else {
                    // Two samples at two seconds apart, so this is brief and
                    // saying how brief is kinder than a bare spinner.
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(points.isEmpty
                             ? "Waiting for the first sample…"
                             : "One sample so far — a rate needs two.")
                            .scaledFont(12)
                            .foregroundStyle(theme.labelFaint)
                    }
                    .frame(height: 180)
                }
            }
        }
    }

    private var rates: some View {
        Slab(rail: .ok, title: "Now") {
            HStack(spacing: 0) {
                // `Rate.bits`, not a bytes formatter: the tracker stores
                // bits per second and every other screen shows kbit/s. The
                // same interface reading Mbit/s here and MiB/s on the Network
                // tab would look like two different measurements.
                rateColumn(
                    label: "IN",
                    value: latest.map { Rate.bits($0.inBps) } ?? "—",
                    peak: points.map(\.inBps).max().map(Rate.bits),
                    colour: theme.ok
                )
                Rectangle()
                    .fill(theme.hairline)
                    .frame(width: 1, height: 40)
                rateColumn(
                    label: "OUT",
                    value: latest.map { Rate.bits($0.outBps) } ?? "—",
                    peak: points.map(\.outBps).max().map(Rate.bits),
                    colour: theme.info
                )
            }
        }
    }

    private func rateColumn(label: String, value: String,
                            peak: String?, colour: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .scaledFont(10, weight: .semibold)
                .foregroundStyle(theme.labelFaint)
            Text(value)
                .scaledFont(20, weight: .semibold, design: .monospaced)
                .foregroundStyle(colour)
            if let peak {
                Text("peak \(peak)")
                    .scaledFont(10, design: .monospaced)
                    .foregroundStyle(theme.labelFaint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 4)
    }

    private var counters: some View {
        Slab(rail: .idle, title: "Since boot") {
            VStack(alignment: .leading, spacing: 4) {
                if let inBytes = iface.inBytes {
                    FieldRow(key: "Received", value: Fmt.bytes(inBytes))
                }
                if let outBytes = iface.outBytes {
                    FieldRow(key: "Sent", value: Fmt.bytes(outBytes))
                }
                if let inErr = iface.inErrors, let outErr = iface.outErrors {
                    FieldRow(key: "Errors", value: "in \(Int(inErr)) · out \(Int(outErr))")
                }
                if let mtu = iface.mtu { FieldRow(key: "MTU", value: mtu) }
                if let mac = iface.mac { FieldRow(key: "MAC", value: mac) }
            }
        }
    }

    /// A day of history, from the firewall's own records.
    ///
    /// Separate from the live chart above it rather than merged: one is a day
    /// at five-minute resolution and the other is two seconds, and drawing
    /// them on the same axis would make the live one a vertical line.
    @ViewBuilder
    private var history: some View {
        Slab(rail: .idle, title: "History") {
            VStack(alignment: .leading, spacing: 8) {
                // The span, chosen here rather than fixed.
                //
                // pfSense keeps years of this — its own page offers up to four
                // — and which span answers the question changes: an evening's
                // shape, a working week, a month's growth. Each is fetched
                // once and kept, so moving between them is instant after the
                // first look.
                if store.rrdWindow != .eightHours, store.widenedFromEmpty {
                    // Says that the span moved, and why. A picker that has
                    // quietly changed under somebody is worse than an empty
                    // chart, because it looks like they mis-tapped.
                    Text("Shorter spans are empty — showing \(store.rrdWindow.displayName.lowercased()).")
                        .scaledFont(10)
                        .foregroundStyle(theme.labelFaint)
                }

                Picker("", selection: Binding(
                    get: { store.rrdWindow },
                    set: { window in
                        // Chosen, not widened: the note goes.
                        store.widenedFromEmpty = false
                        Task { await store.loadRRD(window) }
                    }
                )) {
                    ForEach(PHPSnippet.RRDWindow.allCases) { window in
                        Text(window.displayName).tag(window)
                    }
                }
                .pickerStyle(.segmented)

                if store.isLoadingRRD {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading the firewall's records…")
                            .scaledFont(12)
                            .foregroundStyle(theme.labelFaint)
                    }
                } else if let err = store.errors[.rrd] {
                    Text(err)
                        .scaledFont(12)
                        .foregroundStyle(theme.warn)
                } else if let history = store.rrdHistory, !history.available {
                    // Said once, plainly. pfSense keeps months of this and
                    // reading it needs a shell, which this app will not use.
                    Text("This pfSense cannot read its own RRD files from PHP — that needs rrdtool, a shell binary. The chart above covers what the app has sampled since it opened.")
                        .scaledFont(11)
                        .foregroundStyle(theme.labelFaint)
                } else if !historySeries.isEmpty {
                    RRDChart(series: historySeries, explanation: spanExplanation)
                        .frame(height: 120)
                    // Says how recent it is, because "recent" is doing real
                    // work here: this firewall's traffic files stopped being
                    // written a day ago, so the newest sample is a day old and
                    // a chart that did not say so would be quietly misleading.
                    Text(historyCaption)
                        .scaledFont(10)
                        .foregroundStyle(historyIsStale ? theme.warn : theme.labelFaint)
                } else if store.rrdHistory == nil {
                    // Not the same as "no history": nothing has come back yet.
                    Text("Not read yet.")
                        .scaledFont(11)
                        .foregroundStyle(theme.labelFaint)
                } else if let names = unmatchedFileNames {
                    // The interface has no file under any name the app tried.
                    //
                    // Listing what did come back is the whole diagnosis: RRD
                    // files are named for pfSense's internal handle, and if
                    // that naming differs from what this app expects then the
                    // match is one string away from working. An empty chart
                    // alone would send us guessing again.
                    Text("No file for this interface. The firewall returned: \(names).")
                        .scaledFont(11)
                        .foregroundStyle(theme.labelFaint)
                        .textSelection(.enabled)
                } else {
                    Text("No recorded history for this interface.")
                        .scaledFont(11)
                        .foregroundStyle(theme.labelFaint)
                }
            }
        }
    }

    /// The series for this interface.
    ///
    /// RRD files are named for pfSense's internal handle — `wan`, `opt3` — not
    /// the label on screen, so the match goes through the same lookup
    /// everything else uses.
    private var historySeries: [RRDSeries] {
        guard let history = store.rrdHistory else { return [] }
        // pfSense names these for its internal handle — `wan-traffic.rrd`,
        // `opt3-traffic.rrd` — but a VLAN's file can carry the device name
        // instead, and the label is worth trying last.
        let candidates = [
            iface.internalName,
            iface.device,
            iface.name.lowercased(),
            iface.name,
        ].compactMap { $0 }
        for candidate in candidates {
            let found = history.series(forFile: candidate)
            if !found.isEmpty { return found }
        }
        return []
    }

    /// The files the firewall did return, when none matched this interface.
    ///
    /// Capped, since a firewall with fifteen interfaces returns thirty series
    /// and this is a sentence, not a list.
    private var unmatchedFileNames: String? {
        guard let history = store.rrdHistory, history.available else { return nil }
        let names = Array(Set(history.series.map(\.file))).sorted()
        guard !names.isEmpty else { return nil }
        return names.count > 8
            ? names.prefix(8).joined(separator: ", ") + " +\(names.count - 8)"
            : names.joined(separator: ", ")
    }

    /// What to say when the chosen span has nothing in it.
    ///
    /// A short span landing inside a gap is the common case here: the 8-hour
    /// and day windows come back empty while the week is full, because the
    /// recording stopped a day ago. Saying only "no samples" would leave
    /// somebody to work that out from the picker.
    private var spanExplanation: String {
        if let newest = store.newestRRDSample {
            let age = Date().timeIntervalSince(newest)
            if age > TimeInterval(store.rrdWindow.seconds) {
                let hours = Int(age / 3600)
                return "Nothing recorded in this span. The newest sample is \(hours) hours old, from \(Fmt.dateTime(newest)) — try a longer one."
            }
        }
        return "Nothing recorded in this span."
    }

    /// The newest sample across the drawn series.
    private var newestSample: Date? {
        historySeries.compactMap(\.newestSample).max()
    }

    private var historyIsStale: Bool {
        guard let newest = newestSample else { return false }
        return Date().timeIntervalSince(newest) > 7200
    }

    private var historyCaption: String {
        guard let newest = newestSample else {
            return "From pfSense's own records."
        }
        let age = Date().timeIntervalSince(newest)
        if age < 7200 {
            return "From pfSense's own records, up to the last few minutes."
        }
        let hours = Int(age / 3600)
        return "From pfSense's own records. Nothing recorded for \(hours) hours — the newest sample is from \(Fmt.dateTime(newest))."
    }

    private var note: some View {
        Text("Polling every 2 seconds while this screen is open. Each sample is a call the firewall answers one at a time, so this stops as soon as you go back.")
            .scaledFont(11)
            .foregroundStyle(theme.labelFaint)
            .padding(.horizontal, 4)
    }
}

/// A larger throughput chart with both directions and a filled area.
struct LiveThroughputChart: View {
    @EnvironmentObject private var theme: ThemeManager
    let points: [ThroughputTracker.Point]

    /// Scaled to the peak of either direction so the two are comparable — an
    /// independently scaled pair looks like symmetric traffic when it is not.
    private var peak: Double {
        max(points.map(\.inBps).max() ?? 1, points.map(\.outBps).max() ?? 1, 1)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                gridlines(in: geo.size)
                area(in: geo.size, values: points.map(\.inBps), colour: theme.ok)
                area(in: geo.size, values: points.map(\.outBps), colour: theme.info)
            }
        }
    }

    private func gridlines(in size: CGSize) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { _ in
                Rectangle()
                    .fill(theme.hairline.opacity(0.5))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private func area(in size: CGSize, values: [Double], colour: Color) -> some View {
        let step = values.count > 1 ? size.width / CGFloat(values.count - 1) : size.width
        let pts = values.enumerated().map { idx, v in
            CGPoint(x: CGFloat(idx) * step,
                    y: size.height - (CGFloat(v / peak) * size.height * 0.92) - 2)
        }
        return ZStack {
            Path { path in
                guard let first = pts.first else { return }
                path.move(to: CGPoint(x: first.x, y: size.height))
                path.addLine(to: first)
                for point in pts.dropFirst() { path.addLine(to: point) }
                path.addLine(to: CGPoint(x: pts.last?.x ?? 0, y: size.height))
                path.closeSubpath()
            }
            .fill(colour.opacity(0.16))

            Path { path in
                guard let first = pts.first else { return }
                path.move(to: first)
                for point in pts.dropFirst() { path.addLine(to: point) }
            }
            .stroke(colour, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
        }
    }
}

/// A day of recorded traffic.
///
/// Two lines on a shared scale, like the live chart, so in and out stay
/// comparable. Drawn from pfSense's own five-minute averages rather than the
/// app's samples, which is the only way to see beyond the current session.
struct RRDChart: View {
    @EnvironmentObject private var theme: ThemeManager
    let series: [RRDSeries]
    /// What to say when there is nothing to draw. Supplied, because the chart
    /// cannot know what other spans found.
    var explanation: String = "Nothing recorded in this window."

    /// Only what was passed, and only series that have samples.
    ///
    /// A traffic file holds eight data sources — pass and block, in and out,
    /// v4 and v6 — and drawing all eight puts six near-flat lines under the
    /// two worth reading. Empty ones are dropped so a chart with nothing to
    /// draw can say so rather than rendering blank.
    private var drawable: [RRDSeries] {
        let passing = series.filter { $0.isPassSeries && !$0.points.isEmpty }
        return passing.isEmpty ? series.filter { !$0.points.isEmpty } : passing
    }

    private var peak: Double {
        max(drawable.flatMap(\.bitsPerSecond).max() ?? 1, 1)
    }

    /// Why the chart is empty, when the answer is knowable.
    /// Why this span is empty.
    ///
    /// The chart is given the sentence rather than working it out: only the
    /// screen above knows what the other spans found, and "nothing in the last
    /// 8 hours" means something quite different when the week is full.
    private var emptyExplanation: String { explanation }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The scale, above the line.
            //
            // A line with no numbers on it says "there was traffic" and
            // nothing else — not how much, not when. The peak is the only
            // y-value worth printing at this size, and the span's ends are the
            // x-axis.
            if !drawable.isEmpty {
                HStack {
                    Text(Rate.bits(peak))
                        .scaledFont(9, design: .monospaced)
                        .foregroundStyle(theme.labelFaint)
                    Spacer()
                    legend
                }
            }

            GeometryReader { geo in
                ZStack {
                    if drawable.isEmpty {
                        Text(explanation)
                            .scaledFont(11)
                            .foregroundStyle(theme.labelFaint)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        gridlines(in: geo.size)
                        ForEach(drawable) { one in
                            line(one.bitsPerSecond, in: geo.size,
                                 colour: color(for: one))
                        }
                    }
                }
            }

            if !drawable.isEmpty, let span = timeSpan {
                HStack {
                    Text(span.start)
                    Spacer()
                    Text(span.end)
                }
                .scaledFont(9, design: .monospaced)
                .foregroundStyle(theme.labelFaint)
            }
        }
    }

    /// Which colour is which direction. Two words, and without them the two
    /// lines are just two lines.
    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(drawable) { one in
                HStack(spacing: 4) {
                    Circle()
                        .fill(color(for: one))
                        .frame(width: 6, height: 6)
                    Text(label(for: one))
                        .scaledFont(9)
                        .foregroundStyle(theme.labelFaint)
                }
            }
        }
    }

    private func label(for series: RRDSeries) -> String {
        let name = series.name.lowercased()
        let direction = series.isInbound ? "in" : "out"
        if name.contains("pass") && name.contains("block") {
            return "Mixed \(direction.capitalized)"
        } else if name.contains("pass") {
            if name.contains("6") {
                return "Passed \(direction.capitalized) (v6)"
            } else if name.contains("total") {
                return "Passed \(direction.capitalized) (total)"
            }
            return "Passed \(direction.capitalized)"
        } else if name.contains("block") {
            if name.contains("6") {
                return "Blocked \(direction.capitalized) (v6)"
            }
            return "Blocked \(direction.capitalized)"
        } else {
            return direction.capitalized
        }
    }

    private func color(for series: RRDSeries) -> Color {
        let name = series.name.lowercased()
        let direction = series.isInbound ? "in" : "out"
        if name.contains("pass") && name.contains("total") && direction == "in" {
            return theme.mauve
        } else if name.contains("pass") && name.contains("total") && direction == "out" {
            return theme.lavender
        } else if name.contains("pass") {
            if direction == "in" {
                return name.contains("6") ? theme.teal : theme.ok
            }
            return name.contains("6") ? theme.blue : theme.info
        } else if name.contains("block") {
            if direction == "in" {
                return name.contains("6") ? theme.maroon : theme.warn
            }
            return name.contains("6") ? theme.peach : theme.bad
        } else {
            return direction == "in" ? theme.ok : theme.info
        }
    }

    /// The ends of the drawn span, formatted for their length: a day wants the
    /// hour, a year wants the month.
    private var timeSpan: (start: String, end: String)? {
        let stamps = drawable.flatMap(\.points).map(\.at)
        guard let first = stamps.min(), let last = stamps.max() else { return nil }

        let formatter = DateFormatter()
        let length = last.timeIntervalSince(first)
        if length <= 172_800 {
            formatter.dateFormat = "HH:mm"
        } else if length <= 5_184_000 {
            formatter.dateFormat = "d MMM"
        } else {
            formatter.dateFormat = "MMM yyyy"
        }
        return (formatter.string(from: first), formatter.string(from: last))
    }

    /// Faint horizontal rules, so a peak can be read against something.
    private func gridlines(in size: CGSize) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                Rectangle()
                    .fill(theme.hairline.opacity(0.5))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private func line(_ values: [Double], in size: CGSize, colour: Color) -> some View {
        let step = values.count > 1 ? size.width / CGFloat(values.count - 1) : size.width
        let points = values.enumerated().map { index, value in
            CGPoint(x: CGFloat(index) * step,
                    y: size.height - (CGFloat(value / peak) * size.height * 0.92) - 2)
        }
        return Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
        .stroke(colour, style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
    }
}
