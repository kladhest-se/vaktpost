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
            .refreshable { await store.refreshManually() }
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
            ForEach(filteredInterfaces) { iface in
                // Tappable: the card is a summary, the detail screen watches
                // the same interface at two-second resolution.
                NavigationLink {
                    InterfaceDetailView(iface: iface)
                } label: {
                    InterfaceCard(iface: iface)
                }
                .buttonStyle(.plain)
                // `swipeActions` would do nothing here — it only works inside a
                // List, and this is a LazyVStack. A long press works, and the
                // card carries a visible star as well, since a gesture with no
                // affordance is a feature nobody finds.
                .contextMenu {
                    Button {
                        store.toggleFavourite(iface)
                    } label: {
                        Label(store.isFavourite(iface) ? "Remove from Overview" : "Show on Overview",
                              systemImage: store.isFavourite(iface) ? "star.slash" : "star")
                    }
                }
            }
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
                            // Named the same way the Clients tab does: the ARP
                            // table writes a literal "?" when reverse DNS
                            // fails, and a firewall alias or host override is
                            // a better label than either.
                            Text(store.nameForAddress(entry.ip) ?? entry.ip)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.label)
                            Spacer()
                            if let iface = entry.interfaceName, !iface.isEmpty {
                                // An interface name is an identifier, not a
                                // label — uppercasing turns "ix0" into "IX0",
                                // which reads as the letter O.
                                Text(store.interfaceLabel(for: iface) ?? iface)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(theme.info)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(theme.info.opacity(0.16))
                                    .clipShape(Capsule())
                            }
                        }
                        FieldRow(key: "IP", value: entry.ip)
                        FieldRow(key: "MAC", value: entry.mac)
                        if let expiry = entry.expiryDescription {
                            FieldRow(key: "Expires", value: expiry)
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
                    // Filled when pinned to the Overview. Tapping the star
                    // toggles it without opening the interface, so the two
                    // actions on this card stay distinct.
                    Button {
                        store.toggleFavourite(iface)
                    } label: {
                        Image(systemName: store.isFavourite(iface) ? "star.fill" : "star")
                            .font(.system(size: 12))
                            .foregroundStyle(store.isFavourite(iface)
                                             ? theme.accentColor : theme.labelFaint)
                    }
                    .buttonStyle(.plain)

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

                ThroughputChart(
                    store: store,
                    device: iface.seriesKey,
                    height: 38
                )

                Hairline()

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
