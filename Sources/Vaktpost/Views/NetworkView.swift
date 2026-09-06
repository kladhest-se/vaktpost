import SwiftUI

struct NetworkView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore

    enum Pane: String, CaseIterable, Identifiable {
        case interfaces = "Interfaces"
        case arp = "ARP"
        var id: String { rawValue }
    }

    @State private var pane: Pane = .interfaces
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $pane) {
                ForEach(Pane.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch pane {
                    case .interfaces: interfacesPane
                    case .arp: arpPane
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .refreshable { await store.refresh() }
        }
        .background(theme.bg.ignoresSafeArea())
        .searchable(text: $query, prompt: pane == .interfaces ? "Filter interfaces" : "Filter by IP, MAC or host")
        .navigationTitle("Network")
    }

    // MARK: Interfaces

    private var filteredInterfaces: [InterfaceStat] {
        guard !query.isEmpty else { return store.interfaces }
        let q = query.lowercased()
        return store.interfaces.filter {
            $0.name.lowercased().contains(q)
                || $0.device.lowercased().contains(q)
                || ($0.ipv4 ?? "").contains(q)
        }
    }

    @ViewBuilder
    private var interfacesPane: some View {
        if let err = store.errors[.interfaces] {
            Notice(symbol: "exclamationmark.triangle", title: "Interfaces unavailable",
                   detail: err, health: .warn)
        } else if filteredInterfaces.isEmpty {
            Notice(symbol: "point.3.connected.trianglepath.dotted",
                   title: query.isEmpty ? "No interfaces reported" : "No matches")
        } else {
            HStack {
                Text("\(store.interfacesUp) of \(store.interfaces.count) up")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.labelFaint)
                Spacer()
            }
            ForEach(filteredInterfaces) { InterfaceCard(iface: $0) }
        }
    }

    // MARK: ARP

    private var filteredARP: [ARPEntry] {
        guard !query.isEmpty else { return store.arp }
        let q = query.lowercased()
        return store.arp.filter {
            $0.ip.contains(q) || $0.mac.contains(q) || ($0.hostname ?? "").lowercased().contains(q)
        }
    }

    @ViewBuilder
    private var arpPane: some View {
        if let err = store.errors[.arp] {
            Notice(symbol: "exclamationmark.triangle", title: "ARP table unavailable",
                   detail: err, health: .warn)
        } else if filteredARP.isEmpty {
            Notice(symbol: "tablecells", title: query.isEmpty ? "ARP table empty" : "No matches")
        } else {
            HStack {
                Text("\(filteredARP.count) entries")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.labelFaint)
                Spacer()
            }
            ForEach(filteredARP) { entry in
                Slab(rail: .info) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.hostname?.isEmpty == false ? entry.hostname! : entry.ip)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.label)
                            Spacer()
                            if let iface = entry.interfaceName {
                                StatusPill(text: iface, health: .info)
                            }
                        }
                        FieldRow(key: "IP", value: entry.ip)
                        FieldRow(key: "MAC", value: entry.mac)
                        if let e = entry.expires, !e.isEmpty {
                            FieldRow(key: "Expires", value: e)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Interface card

struct InterfaceCard: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore
    let iface: InterfaceStat

    var body: some View {
        Slab(rail: iface.health) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(iface.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.label)
                    Text(iface.device)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.labelFaint)
                    Spacer()
                    StatusPill(text: iface.status, health: iface.health)
                }

                Text(iface.addressLine)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.labelMuted)

                Hairline()

                let points = store.throughput.points(for: iface.device)
                if points.count > 1 {
                    Sparkline(
                        inSeries: points.map(\.inBps),
                        outSeries: points.map(\.outBps),
                        height: 38
                    )
                    RateLegend(inBps: points.last?.inBps, outBps: points.last?.outBps)
                    Hairline()
                }

                HStack(spacing: 0) {
                    traffic("TOTAL IN", iface.inBytes, theme.ok)
                    Divider().frame(height: 26).overlay(theme.hairline)
                    traffic("TOTAL OUT", iface.outBytes, theme.info)
                }

                if let mac = iface.mac, !mac.isEmpty {
                    FieldRow(key: "MAC", value: mac)
                }
                if let media = iface.media, !media.isEmpty {
                    FieldRow(key: "Media", value: media, mono: false)
                }
                if let e = iface.inErrors, let o = iface.outErrors, e + o > 0 {
                    FieldRow(key: "Errors", value: "in \(Int(e)) · out \(Int(o))")
                }
            }
        }
    }

    private func traffic(_ label: String, _ bytes: Double?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(theme.labelFaint)
            Text(bytes.map(Fmt.bytes) ?? "—")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
