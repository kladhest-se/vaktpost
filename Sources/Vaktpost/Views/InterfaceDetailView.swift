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
        .task { await store.loadRRD() }
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
        Slab(rail: .idle, title: "Last 24 hours") {
            VStack(alignment: .leading, spacing: 8) {
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
                    RRDChart(series: historySeries)
                        .frame(height: 120)
                    Text("From pfSense's own records, five-minute averages.")
                        .scaledFont(10)
                        .foregroundStyle(theme.labelFaint)
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
        let candidates = [iface.internalName, iface.name.lowercased(), iface.device]
            .compactMap { $0 }
        for candidate in candidates {
            let found = history.series(forFile: candidate)
            if !found.isEmpty { return found }
        }
        return []
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

    private var peak: Double {
        max(series.flatMap(\.bitsPerSecond).max() ?? 1, 1)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(series.enumerated()), id: \.element.id) { index, one in
                    line(one.bitsPerSecond, in: geo.size,
                         colour: index == 0 ? theme.ok : theme.info)
                }
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
