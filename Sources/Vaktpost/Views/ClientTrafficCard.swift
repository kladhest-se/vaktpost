import SwiftUI

/// What one device is pulling through the firewall, live.
///
/// There is no per-host counter on pfSense and no way to ask about a single
/// host. The only measurement available is the one the Host traffic screen
/// takes: a one-second packet capture of an interface, returning its ten
/// busiest addresses. So this samples the interface the device is on, looks
/// for the device in the result, and plots what it finds.
///
/// **The refresh interval is the one chosen on the Traffic screen**, shared so
/// a firewall is not being polled on two different schedules at once. The
/// floor is set by the measurement rather than by preference: `rate` needs a
/// full second of wall clock to produce one report — that is the capture
/// window, and no flag shortens it — and each poll is an `exec_php` that
/// pfSense serialises against its own webConfigurator.
///
/// **A zero is a measured zero, with one caveat that the card states.** When
/// the device is not in the returned list the graph plots zero, because for a
/// live trace that is the honest shape — but "not in the list" means "not
/// among the ten busiest", which is usually idleness and is occasionally ten
/// busier neighbours. The card marks those points rather than leaving the
/// distinction to be guessed at.
///
/// The sort matters more than it looks. pfSense truncates *after* sorting, so
/// a device that only uploads can be absent from an inbound-sorted capture
/// entirely. When a sample comes back without the device, the next one is
/// sorted the other way; once a sample finds it, that sort is kept. Either way
/// it is one capture per point — the row carries both directions.
struct ClientTrafficCard: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore

    let client: NetworkClient
    /// Every address this device is known by, so a sample that reports it
    /// under a second address still counts as a match.
    let addresses: [String]

    @State private var points: [ThroughputTracker.Point] = []
    @State private var latest: HostTraffic?
    @State private var isPresent = false
    @State private var sort: PHPSnippet.HostSort = .inbound
    @State private var status: Status = .starting

    enum Status {
        case starting
        case live
        /// No table records which interface this device is on.
        case unknownInterface
        /// The firewall cannot measure here at all — no device behind the
        /// interface, no include. Carries the reason the snippet established.
        case unavailable(String)
        case failed(String)
    }

    /// How often a capture starts, measured start to start.
    ///
    /// A period rather than a pause between captures: a capture takes about a
    /// second and the round trip is variable, so a fixed gap would give a
    /// trace whose time axis stretched and squeezed with how busy the firewall
    /// was. Sleeping whatever is left keeps the points evenly spaced, which is
    /// what makes the trace's width mean anything.
    private var period: TimeInterval { store.hostTrafficInterval }

    /// Points kept. Twenty minutes at the default interval, and still a
    /// couple of minutes at the shortest one.
    private let capacity = 80

    private var hint: String? {
        // The client's own interface first, then whatever the ARP and lease
        // records say. A device that has moved between VLANs has more than one
        // answer here and the most recently observed one is the client's.
        if let name = client.interfaceName, !name.isEmpty { return name }
        return store.arp.first(where: { $0.mac == client.mac })?.interfaceName
            ?? store.leases.first(where: { $0.mac == client.mac })?.interfaceName
    }

    private var slot: Int? { store.interfaceSlot(for: hint) }

    private var selected: InterfaceStat? {
        slot.flatMap { store.interfaces.indices.contains($0) ? store.interfaces[$0] : nil }
    }

    /// Which hosts to ask for on this device's interface.
    ///
    /// Hardcoded to Local until now, which was right for a device on a VLAN
    /// and wrong everywhere else: a device reached over a tunnel would never
    /// appear, because a tunnel has no local subnet for the capture to scope
    /// to, and the card would report it idle forever.
    private var filter: PHPSnippet.HostFilter {
        selected?.suggestedHostFilter ?? .local
    }

    private var interfaceName: String {
        slot.flatMap { store.interfaces.indices.contains($0) ? store.interfaces[$0].name : nil }
            ?? store.interfaceLabel(for: hint)
            ?? "an unknown interface"
    }

    var body: some View {
        Slab(rail: .info, title: "Traffic now",
             trailing: slot == nil ? nil : interfaceName) {
            VStack(alignment: .leading, spacing: 10) {
                rates
                chart
                footnote
            }
        }
        .task(id: client.id) { await run() }
    }

    // MARK: Pieces

    private var rates: some View {
        HStack(spacing: 0) {
            rateColumn("IN", latest.map { text($0.bandwidthIn, $0.inText) } ?? "0 bit/s", theme.ok)
            Rectangle().fill(theme.hairline).frame(width: 1, height: 36)
            rateColumn("OUT", latest.map { text($0.bandwidthOut, $0.outText) } ?? "0 bit/s", theme.info)
        }
    }

    @ViewBuilder
    private var chart: some View {
        switch status {
        case .starting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Capturing on \(interfaceName)…")
                    .scaledFont(12)
                    .foregroundStyle(theme.labelFaint)
            }
            .frame(height: 90)

        case .live:
            if points.count > 1 {
                LiveThroughputChart(points: points)
                    .frame(height: 90)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("One sample so far — a trace needs two.")
                        .scaledFont(12)
                        .foregroundStyle(theme.labelFaint)
                }
                .frame(height: 90)
            }

        case .unknownInterface:
            Text("Which interface this device is on is not recorded in the ARP table, its lease, or the client list, and traffic can only be measured one interface at a time. Open Host traffic and pick the interface yourself.")
                .scaledFont(12)
                .foregroundStyle(theme.labelMuted)

        case let .unavailable(reason):
            Text(reason)
                .scaledFont(12)
                .foregroundStyle(theme.warn)

        case let .failed(message):
            Text(message)
                .scaledFont(12)
                .foregroundStyle(theme.bad)
        }
    }

    @ViewBuilder
    private var footnote: some View {
        switch status {
        case .live:
            if isPresent {
                Text("Measured on \(interfaceName), sorted by \(sort.displayName.lowercased()). Refreshed every \(Int(period)) seconds, each one a one-second capture.")
                    .scaledFont(11)
                    .foregroundStyle(theme.labelFaint)
            } else {
                // The one place a plotted zero needs a sentence. pfSense
                // returns ten addresses, so absence is not proof of silence.
                Text("Not among the ten busiest addresses on \(interfaceName) in the last capture, so this reads zero. That is usually idleness, but a quiet device behind ten busy ones looks the same from here.")
                    .scaledFont(11)
                    .foregroundStyle(theme.labelFaint)
            }
        case .starting, .unknownInterface, .unavailable, .failed:
            EmptyView()
        }
    }

    private func rateColumn(_ label: String, _ value: String, _ colour: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .scaledFont(10, weight: .semibold)
                .foregroundStyle(theme.labelFaint)
            Text(value)
                .scaledFont(16, weight: .semibold, design: .monospaced)
                .foregroundStyle(colour)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The firewall's own text wins when the parser could not read it, so a
    /// shape this app does not understand is never rendered as a zero.
    private func text(_ value: Double, _ raw: String) -> String {
        if value == 0 && raw.trimmingCharacters(in: .whitespaces) != "0" { return raw }
        return Rate.bits(value)
    }

    // MARK: The loop

    private func run() async {
        while !Task.isCancelled {
            // Recomputed each pass rather than captured once: the interface
            // list may not have arrived when this screen opened, and a card
            // that gave up at that moment would stay blank until the person
            // navigated away and back.
            guard let slot else {
                status = .unknownInterface
                try? await Task.sleep(for: .seconds(2))
                continue
            }

            let startedAt = Date()
            do {
                let result = try await store.client.hostTraffic(slot: slot, filter: filter, sort: sort)

                if !result.available {
                    status = .unavailable(result.reason
                        ?? "This firewall cannot measure per-host traffic on \(interfaceName).")
                    return
                }

                status = .live
                record(result)

                // The same capture the traffic screen would have recorded. It
                // returns the interface's whole top ten, not just this device,
                // so there is no reason to throw the rest away.
                if let selected {
                    store.topTalkers.record(
                        result.hosts,
                        serverID: store.profile.id.uuidString,
                        interface: result.interface,
                        interfaceName: selected.name,
                        names: { store.nameForAddress($0) }
                    )
                }
            } catch {
                if error is CancellationError || (error as? RPCError) == .cancelled { return }
                status = .failed(error.localizedDescription)
                return
            }

            // Whatever is left of the period. If a capture overran it, the
            // next starts immediately rather than falling further behind.
            do {
                try await Task.sleep(for: .seconds(max(0, period - Date().timeIntervalSince(startedAt))))
            } catch {
                return
            }
        }
    }

    private func record(_ result: HostTrafficSample) {
        // Compared on the normalised key, not the string: the ARP table and
        // the capture can spell the same IPv6 address differently, and a
        // device found under one spelling and missed under the other would
        // plot as a gap in the trace.
        let keys = Set(addresses.compactMap(ClientAddress.key))
        let match = result.hosts.first { ClientAddress.key($0.ip).map(keys.contains) == true }

        latest = match
        isPresent = match != nil
        append(inBps: match?.bandwidthIn ?? 0, outBps: match?.bandwidthOut ?? 0)

        if match == nil {
            // pfSense truncates after sorting, so an upload-only device is
            // absent from an inbound-sorted capture however busy it is.
            // Alternating while absent costs nothing extra — it is the same
            // one capture, asked a different way.
            sort = sort == .inbound ? .outbound : .inbound
        }
    }

    private func append(inBps: Double, outBps: Double) {
        points.append(ThroughputTracker.Point(at: Date(), inBps: inBps, outBps: outBps))
        if points.count > capacity {
            points.removeFirst(points.count - capacity)
        }
    }
}
