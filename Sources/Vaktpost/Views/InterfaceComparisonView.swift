import SwiftUI

/// Compare throughput across multiple interfaces.
///
/// Select interfaces with checkboxes, then see all of them overlaid on a
/// shared graph — one graph for inbound traffic and another for outbound.
/// This makes it easy to spot which links are busy, whether traffic is
/// pinned to a single path, or whether failover actually switches flows.

struct InterfaceComparisonView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore

    @State private var selectedKeys: Set<String> = []
    @State private var refreshInterval: TimeInterval = 5
    @State private var pollingTask: Task<Void, Never>?

    private let refreshOptions: [(String, TimeInterval)] = [
        ("0.2s", 0.2),
        ("5s", 5),
        ("10s", 10),
        ("30s", 30),
    ]

    private static let selectedInterfacesKey = "InterfaceComparison.selectedInterfaces"
    private static let refreshIntervalKey = "InterfaceComparison.refreshInterval"

    private var interfaceColors: [String: Color] {
        let palette = [theme.ok, theme.info, theme.warn, theme.teal, theme.mauve, theme.lavender, theme.peach, theme.maroon, theme.bad, theme.blue]
        return Array(selectedKeys).enumerated().reduce(into: [:]) { dict, pair in
            let (index, key) = pair
            dict[key] = palette[index % palette.count]
        }
    }

    private var selectedInterfaces: [InterfaceStat] {
        store.interfaces
            .filter { selectedKeys.contains($0.seriesKey) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                interfaceList
                if !selectedInterfaces.isEmpty {
                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Refresh rate")
                                .scaledFont(10, weight: .semibold)
                                .foregroundStyle(theme.labelFaint)
                            Picker("Refresh", selection: $refreshInterval) {
                                ForEach(refreshOptions, id: \.1) { label, interval in
                                    Text(label).tag(interval)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        inboundChart
                        outboundChart
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let saved = UserDefaults.standard.stringArray(forKey: InterfaceComparisonView.selectedInterfacesKey) {
                selectedKeys = Set(saved)
            }
            if let savedInterval = UserDefaults.standard.object(forKey: InterfaceComparisonView.refreshIntervalKey) as? TimeInterval {
                refreshInterval = savedInterval
            }
        }
        .onChange(of: selectedKeys) { _, newValue in
            UserDefaults.standard.set(Array(newValue), forKey: InterfaceComparisonView.selectedInterfacesKey)
        }
        .onChange(of: refreshInterval) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: InterfaceComparisonView.refreshIntervalKey)
        }
        .task(id: selectedKeys) {
            startPolling()
        }
        .task(id: refreshInterval) {
            restartPolling()
        }
    }

    // MARK: Polling

    private func startPolling() {
        pollingTask?.cancel()
        guard !selectedKeys.isEmpty else { return }
        pollingTask = Task {
            while !Task.isCancelled {
                do {
                    let counters = try await store.fetchInterfaceCounters()
                    if !Task.isCancelled {
                        store.throughput.ingest(counters, at: Date())
                    }
                } catch {
                    // Polling errors are silent — the chart shows whatever
                    // samples are already collected.
                }
                do {
                    try await Task.sleep(for: .seconds(refreshInterval))
                } catch {
                    break
                }
            }
        }
    }

    private func restartPolling() {
        startPolling()
    }

    // MARK: Interface list

    private var interfaceList: some View {
        Slab(rail: .idle) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Interfaces")
                        .scaledFont(12, weight: .semibold)
                    Spacer()
                    if !selectedKeys.isEmpty {
                        Text("\(selectedKeys.count) selected")
                            .scaledFont(10, weight: .medium)
                            .foregroundStyle(theme.labelFaint)
                    }
                }

                // iface.name directly, not store.interfaceLabel(for:) — this
                // screen already has InterfaceStat, whose .name is the
                // resolved friendly name, so it needs no lookup. Passing it
                // through the lookup anyway once made this screen show one
                // interface's name for a different one: pfSense's internal
                // "lan" role can be renamed to display as anything, and a
                // separate interface can then be given that literal name.
                // interfaceLabel(for:) is built for raw pfSense identifiers
                // (a rule's, lease's, or ARP entry's own interface field) —
                // exactly the case where an internal handle needs resolving
                // to what the administrator actually calls it — not for a
                // name that's already resolved.
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(splitInterfaces.left, id: \.seriesKey) { iface in
                                InterfaceCheckRow(
                                    label: iface.name,
                                    health: iface.health,
                                    isSelected: selectedKeys.contains(iface.seriesKey)
                                ) {
                                    toggleSelection(for: iface.seriesKey)
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(splitInterfaces.right, id: \.seriesKey) { iface in
                                InterfaceCheckRow(
                                    label: iface.name,
                                    health: iface.health,
                                    isSelected: selectedKeys.contains(iface.seriesKey)
                                ) {
                                    toggleSelection(for: iface.seriesKey)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var splitInterfaces: (left: [InterfaceStat], right: [InterfaceStat]) {
        let mid = (store.interfaces.count + 1) / 2
        return (Array(store.interfaces.prefix(mid)), Array(store.interfaces.suffix(store.interfaces.count - mid)))
    }

    private func toggleSelection(for key: String) {
        if selectedKeys.contains(key) {
            selectedKeys.remove(key)
        } else {
            selectedKeys.insert(key)
        }
    }

    // MARK: Charts

    private var inboundChart: some View {
        MultiSeriesChart(
            title: "Inbound",
            series: selectedInterfaces.map { iface -> (label: String, values: [Double], color: Color) in
                let points = store.throughput.points(for: iface.seriesKey)
                let label = iface.name
                return (label, points.map(\.inBps), interfaceColors[iface.seriesKey] ?? theme.ok)
            },
            color: theme.ok
        )
    }

    private var outboundChart: some View {
        MultiSeriesChart(
            title: "Outbound",
            series: selectedInterfaces.map { iface -> (label: String, values: [Double], color: Color) in
                let points = store.throughput.points(for: iface.seriesKey)
                let label = iface.name
                return (label, points.map(\.outBps), interfaceColors[iface.seriesKey] ?? theme.info)
            },
            color: theme.info
        )
    }
}

// MARK: - Interface check row

private struct InterfaceCheckRow: View {
    let label: String
    let health: Health
    let isSelected: Bool
    let action: () -> Void

    private var statusDescription: String { health.spokenDescription }

    private var statusColor: Color {
        switch health {
        case .ok: return theme.ok
        case .info: return theme.info
        case .warn: return .yellow
        case .bad: return .red
        case .idle: return theme.labelFaint
        }
    }

    @Environment(\.themeManager) private var theme: ThemeManager

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.square" : "square")
                    .foregroundStyle(isSelected ? theme.accentColor : theme.labelFaint)
                    .symbolRenderingMode(.multicolor)

                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)

                Text(label)
                    .scaledFont(13)

                Spacer()
            }
        }
        .buttonStyle(.plain)
        // One control, read as one thing: the name, whether it is charted,
        // and the health the coloured dot shows to everybody else.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(isSelected ? "Shown, \(statusDescription)" : "Hidden, \(statusDescription)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Multi-series chart

private struct MultiSeriesChart: View {
    @Environment(\.themeManager) private var theme: ThemeManager

    let title: String
    let series: [(label: String, values: [Double], color: Color)]
    var color: Color

    @State private var showTooltip = false
    @State private var tooltipX: CGFloat?
    @State private var tooltipValues: [(label: String, value: Double, color: Color)]?

    private var peak: Double {
        series.flatMap(\.values).max() ?? 1
    }

    var body: some View {
        Slab(rail: .idle, title: title) {
            VStack(alignment: .leading, spacing: 0) {
                chart
                    .frame(minHeight: 160)
                    // The legend below carries the series names for everyone
                    // else; this says the same without the shapes.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(title)
                    .accessibilityValue(series.isEmpty
                                        ? "Nothing to compare"
                                        : series.map { "\($0.label) peak \(Int(($0.values.max() ?? 0).rounded()))" }
                                            .joined(separator: ", "))
                legend
            }
        }
    }

    private var chart: some View {
        GeometryReader { geo in
            ZStack {
                let chartHeight = max(160, geo.size.height - 80)
                gridlines(width: geo.size.width, height: chartHeight)
                ForEach(validSeries, id: \.label) { s in
                    chartPath(s.values, width: geo.size.width, height: chartHeight, color: s.color, isArea: true)
                    chartPath(s.values, width: geo.size.width, height: chartHeight, color: s.color, isArea: false)
                }
                if showTooltip, let x = tooltipX, let vals = tooltipValues {
                    tooltipLine(at: x, width: geo.size.width, height: chartHeight)
                    ForEach(Array(vals.enumerated()), id: \.offset) { _, v in
                        tooltipMarker(at: x, width: geo.size.width, height: chartHeight, color: v.color, value: v.value)
                        tooltipLabel(text: v.label, value: v.value, at: x, width: geo.size.width, height: chartHeight, color: v.color)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                withAnimation(Motion.animation(.easeInOut(duration: 0.15))) {
                    showTooltip.toggle()
                    if showTooltip {
                        let chartX = max(0, min(location.x, geo.size.width))
                        if let sample = sampleAt(x: chartX, width: geo.size.width, height: max(160, geo.size.height - 80)) {
                            tooltipX = sample.x
                            tooltipValues = sample.values
                        } else {
                            showTooltip = false
                            tooltipValues = nil
                        }
                    } else {
                        tooltipValues = nil
                    }
                }
            }
        }
        .background(theme.hairline.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var legend: some View {
        WrapFlowLegend(series: series)
            .padding(.vertical, 4)
    }

    private var validSeries: [(label: String, values: [Double], color: Color)] {
        series.filter { $0.values.count > 1 }
    }

    private var estimatedLegendRows: Int {
        max(1, (series.count + 1) / 2)
    }

    private func gridlines(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            ForEach(0..<4) { i in
                let y = height * CGFloat(i) / 3
                Rectangle()
                    .fill(theme.hairline.opacity(0.08))
                    .frame(height: 1)
                    .offset(y: y - 0.5)
            }
        }
    }

    private func tooltipLine(at x: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        Path { p in
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: height))
        }
        .stroke(theme.label.opacity(0.3), style: StrokeStyle(lineWidth: 1))
    }

    private func tooltipMarker(at x: CGFloat, width: CGFloat, height: CGFloat, color: Color, value: Double) -> some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .position(x: x, y: height - (CGFloat(value / peak) * height * 0.92) - 2)
            .shadow(color: color.opacity(0.4), radius: 2)
    }

    private func tooltipLabel(text: String, value: Double, at x: CGFloat, width: CGFloat, height: CGFloat, color: Color) -> some View {
        let y = height - (CGFloat(value / peak) * height * 0.92) - 2
        let halfWidth: CGFloat = 40
        let clampedX = min(max(x, halfWidth), max(halfWidth, width - halfWidth))
        // Bits, like the legend three lines below and like every other rate
        // on this screen. These series come from `store.throughput`, which is
        // the interface tracker, and this was the second place labelling its
        // bits as bytes.
        return Text("\(Rate.bits(value))")
            .scaledFont(9, design: .monospaced)
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(color.opacity(0.8), in: Capsule())
            .position(x: clampedX, y: max(8, y - 12))
    }

    private func sampleAt(x: CGFloat, width: CGFloat, height: CGFloat) -> (x: CGFloat, values: [(label: String, value: Double, color: Color)])? {
        let count = validSeries.first?.values.count ?? 0
        guard count > 1 else { return nil }

        let values = validSeries.compactMap { series -> (label: String, value: Double, color: Color)? in
            guard series.values.count > 1 else { return nil }
            let step = width / CGFloat(series.values.count - 1)
            let index = Int((x / step).rounded()).clamped(to: 0...(series.values.count - 1))
            return (label: series.label, value: series.values[index], color: series.color)
        }
        
        guard !values.isEmpty else { return nil }
        let firstSeries = validSeries.first { $0.values.count > 1 }!
        let step = width / CGFloat(firstSeries.values.count - 1)
        let index = Int((x / step).rounded()).clamped(to: 0...(firstSeries.values.count - 1))
        let snappedX = CGFloat(index) * step
        
        return (snappedX, values)
    }

    @ViewBuilder
    private func chartPath(_ values: [Double], width: CGFloat, height: CGFloat, color: Color, isArea: Bool) -> some View {
        let pts = points(values, width: width, height: height)
        if pts.count > 1 {
            if isArea {
                Path { p in
                    p.move(to: CGPoint(x: pts[0].x, y: height))
                    pts.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: height))
                    p.closeSubpath()
                }
                .fill(color.opacity(0.12))
            }
            Path { p in
                p.move(to: pts[0])
                pts.dropFirst().forEach { p.addLine(to: $0) }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
    }

    private func points(_ values: [Double], width: CGFloat, height: CGFloat) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let step = width / CGFloat(values.count - 1)
        return values.enumerated().map { idx, v in
            CGPoint(
                x: CGFloat(idx) * step,
                y: height - (CGFloat(v / peak) * height * 0.92) - 2
            )
        }
    }
}

// MARK: - Wrap flow legend

private struct WrapFlowLegend: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    let series: [(label: String, values: [Double], color: Color)]

    var body: some View {
        VStack(spacing: 4) {
            let columns = 2
            let rowCount = (series.count + columns - 1) / columns
            
            ForEach(0..<rowCount, id: \.self) { row in
                HStack {
                    ForEach(0..<columns, id: \.self) { col in
                        let idx = row * columns + col
                        if idx < series.count {
                            legendItem(series[idx])
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func legendItem(_ s: (label: String, values: [Double], color: Color)) -> some View {
        HStack(spacing: 4) {
            Circle().fill(s.color).frame(width: 6, height: 6)
            Text(s.label)
                .scaledFont(10, weight: .medium)
                .foregroundStyle(theme.label)
            if !s.values.isEmpty {
                Text(Rate.bits(s.values.max() ?? 0))
                    .scaledFont(9, design: .monospaced)
                    .foregroundStyle(theme.labelFaint)
            }
        }
    }
}

// Extension to clamp an integer to a range.
private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}
