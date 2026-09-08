import SwiftUI

/// Compare throughput between two interfaces.
///
/// Useful for WAN failover debugging: see whether the backup link actually
/// picks up traffic when the primary goes down, or whether traffic stays
/// pinned to one path. Shows the app's live samples (two-second resolution)
/// side by side so the shapes are directly comparable.

struct InterfaceComparisonView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore

    @State private var leftKey: String?
    @State private var rightKey: String?

    private var leftIface: InterfaceStat? {
        guard let key = leftKey else { return nil }
        return store.interfaces.first { $0.seriesKey == key }
    }

    private var rightIface: InterfaceStat? {
        guard let key = rightKey else { return nil }
        return store.interfaces.first { $0.seriesKey == key }
    }

    private var leftPoints: [ThroughputTracker.Point] {
        store.throughput.points(for: leftKey ?? "")
    }

    private var rightPoints: [ThroughputTracker.Point] {
        store.throughput.points(for: rightKey ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                picker
                charts
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if leftKey == nil, let first = store.interfaces.first {
                leftKey = first.seriesKey
            }
            if rightKey == nil, store.interfaces.count > 1 {
                let second = store.interfaces.dropFirst().first
                rightKey = second?.seriesKey
            }
        }
    }

    // MARK: Picker

    private var picker: some View {
        Slab(rail: .idle) {
            HStack(spacing: 12) {
                Picker("Left", selection: $leftKey) {
                    ForEach(store.interfaces, id: \.seriesKey) { iface in
                        Text(store.interfaceLabel(for: iface.name) ?? iface.name)
                            .tag(iface.seriesKey as String?)
                    }
                }
                .pickerStyle(.menu)

                Text("vs")
                    .scaledFont(12, weight: .medium)
                    .foregroundStyle(theme.labelFaint)

                Picker("Right", selection: $rightKey) {
                    ForEach(store.interfaces, id: \.seriesKey) { iface in
                        Text(store.interfaceLabel(for: iface.name) ?? iface.name)
                            .tag(iface.seriesKey as String?)
                    }
                }
                .pickerStyle(.menu)
            }
            .frame(minHeight: 40)
        }
    }

    // MARK: Charts

    private var charts: some View {
        Group {
            if let left = leftIface {
                comparisonSlab(side: "IN", left: leftPoints.map(\.inBps), right: rightPoints.map(\.inBps), label: store.interfaceLabel(for: left.name) ?? left.name, health: left.health)
            }
            if let left = leftIface {
                comparisonSlab(side: "OUT", left: leftPoints.map(\.outBps), right: rightPoints.map(\.outBps), label: store.interfaceLabel(for: left.name) ?? left.name, health: left.health)
            }
        }
        .transition(.opacity)
    }

    private func comparisonSlab(side: String, left: [Double], right: [Double], label: String, health: Health) -> some View {
        Slab(rail: health, title: "\(side) throughput") {
            VStack(alignment: .leading, spacing: 8) {
                sparklinePair(left, right, theme: theme)
                HStack {
                    Text(label)
                        .scaledFont(10, weight: .medium)
                        .foregroundStyle(theme.labelMuted)
                    Spacer()
                    if !left.isEmpty {
                        Text(Rate.bits(left.max() ?? 0))
                            .scaledFont(10, design: .monospaced)
                            .foregroundStyle(theme.labelFaint)
                    }
                    if !right.isEmpty {
                        Text(Rate.bits(right.max() ?? 0))
                            .scaledFont(10, design: .monospaced)
                            .foregroundStyle(theme.labelFaint)
                    }
                }
            }
        }
    }

    private func sparklinePair(_ left: [Double], _ right: [Double], theme: ThemeManager) -> some View {
        GeometryReader { geo in
            ZStack {
                // Left interface
                Path { path in
                    guard left.count > 1 else { return }
                    let step = geo.size.width / CGFloat(left.count - 1)
                    let peak = max(left.max() ?? 1, right.max() ?? 1, 1)
                    let pts = left.enumerated().map { idx, v in
                        CGPoint(x: CGFloat(idx) * step,
                                y: geo.size.height - (CGFloat(v / peak) * geo.size.height * 0.92) - 2)
                    }
                    path.move(to: CGPoint(x: pts.first?.x ?? 0, y: geo.size.height))
                    if let first = pts.first { path.addLine(to: first) }
                    for point in pts.dropFirst() { path.addLine(to: point) }
                    path.addLine(to: CGPoint(x: pts.last?.x ?? 0, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(theme.ok.opacity(0.2))
                .mask(alignment: .leading) {
                    Rectangle().frame(width: geo.size.width * 0.5)
                }

                Path { path in
                    guard left.count > 1 else { return }
                    let step = geo.size.width / CGFloat(left.count - 1)
                    let peak = max(left.max() ?? 1, right.max() ?? 1, 1)
                    let pts = left.enumerated().map { idx, v in
                        CGPoint(x: CGFloat(idx) * step,
                                y: geo.size.height - (CGFloat(v / peak) * geo.size.height * 0.92) - 2)
                    }
                    path.move(to: pts.first ?? .zero)
                    for point in pts.dropFirst() { path.addLine(to: point) }
                }
                .stroke(theme.ok, style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
                .mask(alignment: .leading) {
                    Rectangle().frame(width: geo.size.width * 0.5)
                }

                // Right interface
                Path { path in
                    guard right.count > 1 else { return }
                    let step = geo.size.width / CGFloat(right.count - 1)
                    let peak = max(left.max() ?? 1, right.max() ?? 1, 1)
                    let pts = right.enumerated().map { idx, v in
                        CGPoint(x: CGFloat(idx) * step + geo.size.width * 0.5,
                                y: geo.size.height - (CGFloat(v / peak) * geo.size.height * 0.92) - 2)
                    }
                    path.move(to: CGPoint(x: pts.first?.x ?? 0, y: geo.size.height))
                    if let first = pts.first { path.addLine(to: first) }
                    for point in pts.dropFirst() { path.addLine(to: point) }
                    path.addLine(to: CGPoint(x: pts.last?.x ?? 0, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(theme.info.opacity(0.2))
                .mask(alignment: .trailing) {
                    Rectangle().frame(width: geo.size.width * 0.5, alignment: .trailing)
                }

                Path { path in
                    guard right.count > 1 else { return }
                    let step = geo.size.width / CGFloat(right.count - 1)
                    let peak = max(left.max() ?? 1, right.max() ?? 1, 1)
                    let pts = right.enumerated().map { idx, v in
                        CGPoint(x: CGFloat(idx) * step + geo.size.width * 0.5,
                                y: geo.size.height - (CGFloat(v / peak) * geo.size.height * 0.92) - 2)
                    }
                    path.move(to: pts.first ?? .zero)
                    for point in pts.dropFirst() { path.addLine(to: point) }
                }
                .stroke(theme.info, style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
                .mask(alignment: .trailing) {
                    Rectangle().frame(width: geo.size.width * 0.5, alignment: .trailing)
                }

                // Divider
                Rectangle()
                    .fill(theme.hairline)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 100)
        .background(theme.hairline.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}
