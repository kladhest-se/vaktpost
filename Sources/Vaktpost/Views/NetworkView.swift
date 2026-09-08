import SwiftUI

struct NetworkView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore

    @State private var query = ""

    var body: some View {
        ScrollView {
            PageHeader(title: "Network", subtitle: store.interfaces.count > 0 ? "\(store.interfaces.count) interfaces" : nil)
            VStack(alignment: .leading, spacing: 12) {
                interfacesPane
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .refreshable { await store.refreshManually() }
        .searchable(text: $query, prompt: "Filter interfaces")
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
            VStack(spacing: 12) {
                HStack {
                    Text("\(store.interfacesUp) of \(store.interfaces.count) up")
                        .scaledFont(12, design: .monospaced)
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
    }

/// One interface, as a card.
///
/// Rebuilt after a regex meant to remove the ARP pane matched to the wrong
/// closing brace and took this and `ARPRow` with it. The ARP row is gone on
/// purpose — Clients covers that table — but this was collateral.
struct InterfaceCard: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore
    let iface: InterfaceStat

    var body: some View {
        Slab(rail: iface.health, trailing: iface.device) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    // Filled when pinned to the Overview. Tapping the star
                    // toggles it without opening the interface, so the two
                    // actions on this card stay distinct.
                    Button {
                        store.toggleFavourite(iface)
                    } label: {
                        Image(systemName: store.isFavourite(iface) ? "star.fill" : "star")
                            .scaledFont(12)
                            .foregroundStyle(store.isFavourite(iface)
                                             ? theme.accentColor : theme.labelFaint)
                    }
                    .buttonStyle(.plain)

                    Text(iface.name)
                        .scaledFont(16, weight: .semibold)
                        .foregroundStyle(theme.label)

                    Spacer(minLength: 8)
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
                        .lineLimit(2)
                }

                HStack(spacing: 0) {
                    traffic("IN", iface.inBytes, theme.ok)
                    traffic("OUT", iface.outBytes, theme.info)
                }

                // The same chart the Overview draws. Lifetime counters say how
                // much has gone through an interface since boot; they say
                // nothing about whether anything is going through it now,
                // which is what somebody scanning this list wants.
                ThroughputChart(
                    tracker: store.throughput,
                    store: store,
                    device: iface.seriesKey,
                    height: 44
                )
            }
        }
    }

    private func traffic(_ label: String, _ bytes: Double?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .scaledFont(10, weight: .bold, design: .rounded)
                .tracking(0.8)
                .foregroundStyle(theme.labelFaint)
            Text(bytes.map(Fmt.bytes) ?? "—")
                .scaledFont(15, weight: .semibold, design: .monospaced)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
}
