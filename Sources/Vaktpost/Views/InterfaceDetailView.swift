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
                counters
                note
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .task { await store.monitorInterface(iface.seriesKey) }
        .navigationTitle(iface.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Pieces

    private var header: some View {
        Slab(rail: iface.health, trailing: iface.device) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(iface.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(theme.label)
                    Spacer()
                    StatusPill(text: iface.status, health: iface.health)
                }
                Text(iface.addressLine)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.labelMuted)
                    .textSelection(.enabled)
                if let media = iface.media, !media.isEmpty {
                    Text(media)
                        .font(.system(size: 11))
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
                        .font(.system(size: 12))
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
                            .font(.system(size: 12))
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
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.labelFaint)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(colour)
            if let peak {
                Text("peak \(peak)")
                    .font(.system(size: 10, design: .monospaced))
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

    private var note: some View {
        Text("Polling every 2 seconds while this screen is open. Each sample is a call the firewall answers one at a time, so this stops as soon as you go back.")
            .font(.system(size: 11))
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
