import SwiftUI

/// The hosts using one interface, updating continuously.
///
/// This screen is unlike every other one in the app, and the differences are
/// worth stating rather than leaving to be discovered:
///
///   - **It measures rather than reads.** There is no per-host counter on
///     pfSense. The firewall runs a one-second packet capture to answer this.
///   - **The refresh interval is a control, not a constant.** The right number
///     depends on what is being watched for and on what else the firewall is
///     doing, so it is a stored preference shared with the per-client trace.
///     The floor is not a preference: `rate` needs a full second of wall clock
///     to produce one report, and each poll is an `exec_php` that pfSense
///     serialises against its own webConfigurator, so anything under about a
///     second and a half queues requests faster than they complete. The
///     shortest option offered is two seconds, which on a busy firewall is
///     effectively continuous polling rather than a two-second interval.
///   - **It is one interface at a time**, because the capture is per
///     interface.
///   - **It shows at most ten hosts.** That bound is inside pfSense; the
///     webConfigurator table has the same one.
///   - **The sort decides which hosts survive that truncation**, not merely
///     their order, because pfSense truncates after sorting. Switching between
///     inbound and outbound can return a different set of devices entirely,
///     which is why it is a control rather than a local re-ordering.
///   - **Local and remote are separate measurements**, not two filters over
///     one result. pfSense hands the capture a different subnet for each.
struct HostTrafficPanel: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore

    /// pfSense's internal handle for the interface to open on — "lan", "opt3".
    /// Supplied when this panel is pushed from an interface, nil otherwise.
    var preselect: String?

    @State private var slot: Int = 0
    @State private var filter: PHPSnippet.HostFilter = .local
    @State private var sort: PHPSnippet.HostSort = .inbound
    @State private var sample: HostTrafficSample?
    @State private var error: String?
    @State private var hasPreselected = false
    @State private var sampledAt: Date?

    /// The interface whose suggested filter has already been applied.
    ///
    /// Tracked so the suggestion is a default rather than an override: it is
    /// applied when the interface changes, and a filter chosen by hand after
    /// that survives until the interface changes again.
    @State private var filterSuggestedFor: Int?

    /// Narrows what is shown, never what is measured.
    ///
    /// Ten rows do not need searching for their own sake. What this is for is
    /// the question the list cannot answer by being read: whether one
    /// particular device is in the ten right now. Typing its name and watching
    /// the row appear and disappear across captures says that, and scanning
    /// ten changing rows for it does not.
    @State private var query = ""

    /// A short trace per address, so a row says which way it is heading.
    ///
    /// A single instantaneous number cannot tell a device that is winding down
    /// from one that is ramping up, and at a fifteen-second interval two
    /// consecutive glances are a long way apart. Keyed by normalised address
    /// rather than by the string the capture printed, for the same reason
    /// everything else here is: two spellings of one IPv6 address would
    /// otherwise be two traces, each half empty.
    @State private var history: [String: [ThroughputTracker.Point]] = [:]

    /// Points kept per row. Twenty is five minutes at the default interval and
    /// about forty seconds at the shortest — enough to read a direction from,
    /// and narrow enough to draw in a row without crowding the numbers.
    private let traceLength = 20

    /// How often a capture starts, measured start to start.
    ///
    /// A period rather than a pause between captures, so the interval is one
    /// somebody can reason about: a capture takes about a second and the round
    /// trip is variable, so a fixed gap would give a refresh rate that drifted
    /// with how busy the firewall was. The loop sleeps whatever is left; if a
    /// capture overruns, the next starts immediately rather than falling
    /// further behind.
    private var period: TimeInterval { store.hostTrafficInterval }

    /// Written through to the store so the choice outlives the screen and the
    /// per-client trace uses the same one.
    private var intervalBinding: Binding<TimeInterval> {
        Binding(get: { store.hostTrafficInterval },
                set: { store.hostTrafficInterval = $0 })
    }

    private var interfaces: [InterfaceStat] { store.interfaces }

    private var selected: InterfaceStat? {
        interfaces.indices.contains(slot) ? interfaces[slot] : nil
    }

    /// What identifies one continuous run of captures.
    ///
    /// Changing any part of it cancels the loop mid-capture and starts a new
    /// one, so a picker never leaves a result from the previous question on
    /// screen while the next one is still being measured.
    private var runKey: String {
        "\(store.bindingID)-\(slot)-\(filter.rawValue)-\(sort.rawValue)-\(Int(period))"
    }

    /// Hosts with a name attached where the firewall knows one, ordered by the
    /// column being sorted on.
    ///
    /// pfSense returns them in that order already. Sorting again locally costs
    /// nothing and means the list cannot disagree with the control above it —
    /// including on the tie-break, where pfSense's order is whatever `rate`
    /// happened to emit and a stable one stops rows swapping places between
    /// captures for no reason.
    /// Every host the last capture returned, named and ordered.
    ///
    /// Deduplicated by identity first. `ForEach` over duplicate ids is
    /// undefined behaviour, and the identity here comes from an address the
    /// firewall chose — this app does not get to assume it is unique.
    private var allRows: [HostTraffic] {
        var seen = Set<String>()
        return (sample?.hosts ?? [])
            .filter { seen.insert($0.id).inserted }
            .map { host in
                var named = host
                named.hostname = store.nameForAddress(host.ip)
                return named
            }
            .sorted { lhs, rhs in
                let left = sort == .inbound ? lhs.bandwidthIn : lhs.bandwidthOut
                let right = sort == .inbound ? rhs.bandwidthIn : rhs.bandwidthOut
                if left != right { return left > right }
                if lhs.total != rhs.total { return lhs.total > rhs.total }
                return lhs.ip < rhs.ip
            }
    }

    /// What the search leaves.
    ///
    /// Matched against the address and against every name the firewall knows
    /// the device by, not only the one that won the title — a device shown as
    /// its DNS override is still findable by the description on its static
    /// mapping, which is how the Clients list next door behaves.
    private var rows: [HostTraffic] {
        guard !query.isEmpty else { return allRows }
        let needle = query.lowercased()
        return allRows.filter { host in
            host.ip.lowercased().contains(needle)
                || (host.hostname ?? "").lowercased().contains(needle)
                || (store.client(matching: host.ip)?.name ?? "").lowercased().contains(needle)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            controls
            search
            results
            note
        }
        .padding(.horizontal, 16)
        .onAppear(perform: applyPreselection)
        .onChange(of: slot) { _, _ in applySuggestedFilter() }
        // The interface list can arrive after this screen opens, and the
        // suggestion cannot be made until it does.
        .onChange(of: interfaces.count) { _, _ in applySuggestedFilter() }
        .task(id: runKey) { await run() }
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        if interfaces.isEmpty {
            Notice(symbol: "questionmark.circle",
                   title: "No interfaces yet",
                   detail: "Refresh the dashboard first — this screen samples one of the interfaces it finds.")
        } else {
            Slab(rail: .info, title: "Measuring", trailing: selected?.device) {
                VStack(alignment: .leading, spacing: 12) {
                    // Grouped, because fifteen entries in pfSense's config
                    // order interleaves two uplinks, five tunnels and eight
                    // VLANs into a list you have to read all of. The tag stays
                    // the original index either way — grouping changes what is
                    // shown, never what is sent.
                    Picker("Interface", selection: $slot) {
                        ForEach(InterfaceStat.grouped(interfaces)) { group in
                            Section(group.title) {
                                ForEach(group.entries) { entry in
                                    Text(entry.interface.name).tag(entry.id)
                                }
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(theme.accentColor)

                    Picker("Hosts", selection: $filter) {
                        ForEach(PHPSnippet.HostFilter.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    // Only where the default is not the obvious one. On a VLAN
                    // there is nothing to explain and a line saying so is
                    // noise on the screen every time.
                    if let rationale = selected?.hostFilterRationale {
                        Text(rationale)
                            .scaledFont(11)
                            .foregroundStyle(theme.labelFaint)
                    }

                    // The busiest by which direction. Not a re-ordering of one
                    // result — pfSense sorts inside the capture and keeps only
                    // the top ten, so this changes which devices come back.
                    Picker("Busiest by", selection: $sort) {
                        ForEach(PHPSnippet.HostSort.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    // Restarting the run on a change costs one capture and
                    // means the new interval takes effect now rather than
                    // after the old one has finished waiting — which, going
                    // from a minute to five seconds, is a long time to sit
                    // watching nothing happen.
                    Picker("Refresh", selection: intervalBinding) {
                        ForEach(DashboardStore.hostTrafficIntervals, id: \.self) { seconds in
                            Text("\(Int(seconds))s").tag(seconds)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 10) {
                        liveIndicator
                        Spacer(minLength: 8)
                        NavigationLink {
                            TopTalkersView()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.arrow.circlepath")
                                Text("History")
                            }
                            .scaledFont(12, weight: .medium)
                            .foregroundStyle(theme.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var liveIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(error == nil ? theme.ok : theme.warn)
                .frame(width: 6, height: 6)
            if let sampledAt {
                Text("Live — last capture \(sampledAt.formatted(date: .omitted, time: .standard))")
                    .scaledFont(11, design: .monospaced)
                    .foregroundStyle(theme.labelFaint)
            } else {
                Text("Capturing…")
                    .scaledFont(11, design: .monospaced)
                    .foregroundStyle(theme.labelFaint)
            }
        }
    }

    @ViewBuilder
    private var search: some View {
        // Only once there is something to search. An empty field above an
        // empty list is furniture.
        if !allRows.isEmpty || !query.isEmpty {
            InlineSearchField(text: $query, prompt: "Name or address")
        }
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        // The error sits above whatever was last measured rather than
        // replacing it. A monitor that blanks itself on one failed request
        // throws away the reading that might explain the failure.
        if let error {
            Notice(symbol: "exclamationmark.triangle",
                   title: "The last capture failed",
                   detail: error,
                   health: .warn)
        }

        if !rows.isEmpty {
            VStack(spacing: 8) {
                ForEach(rows) { host in
                    hostRow(host)
                }
            }
        } else if !allRows.isEmpty {
            // Searched, and nothing matched. Worth its own sentence rather
            // than falling through to "nothing measured", which would be
            // false: something was measured, it just was not this.
            //
            // And the absence is the same ambiguity the list always has. A
            // device missing from the ten is usually idle and is sometimes
            // crowded out by ten busier ones, and a search that found nothing
            // cannot tell which.
            Notice(symbol: "magnifyingglass",
                   title: "Not in the last capture",
                   detail: "No address matching that is among the ten busiest on \(selected?.name ?? "this interface") right now. "
                       + "That usually means it is idle, but a quiet device behind ten busy ones looks the same from here.")
        } else if let sample {
            Notice(symbol: "chart.bar",
                   title: sample.available ? "Nothing measured" : "Not available on this firewall",
                   detail: sample.reason ?? "The capture ran and saw no host matching this filter on the interface.",
                   health: sample.available ? .idle : .warn)
        } else if !interfaces.isEmpty && error == nil {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for the first capture…")
                    .scaledFont(12)
                    .foregroundStyle(theme.labelFaint)
            }
            .frame(height: 60)
        }
    }

    /// One host, and a way through to it when the firewall knows what it is.
    ///
    /// Both of these screens live in the Clients tab and describe the same
    /// devices, so "172.16.1.10 is pulling 5.63M" and that device's leases,
    /// names and filter log should be one tap apart. A capture also returns
    /// addresses the client list has never heard of — everything on the far
    /// side of a WAN — so the link appears only where there is somewhere to
    /// go, and the chevron is what says which rows those are.
    @ViewBuilder
    private func hostRow(_ host: HostTraffic) -> some View {
        if let client = store.client(matching: host.ip) {
            NavigationLink {
                // Re-identified rather than captured, the same way the client
                // list does it: the detail follows the data instead of showing
                // the device as it was when the row was tapped.
                ClientDetailView(client: client).id(store.bindingID)
            } label: {
                hostRowBody(host, linked: true)
            }
            .buttonStyle(.plain)
        } else {
            hostRowBody(host, linked: false)
        }
    }

    private func hostRowBody(_ host: HostTraffic, linked: Bool) -> some View {
        // No proportion bar.
        //
        // There was one, scaled against the busiest row in the capture. It
        // looked like information and was not: pfSense returns whichever ten
        // hosts happened to be busiest, so the bar's full width meant a
        // different rate every refresh and a row could shrink while its own
        // throughput rose. The numbers are the measurement.
        Slab(rail: .info) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top) {
                    identity(host, linked: linked)

                    Spacer(minLength: 8)

                    rateColumn("IN", rateText(host.bandwidthIn, host.inText), theme.ok,
                               emphasised: sort == .inbound)
                    rateColumn("OUT", rateText(host.bandwidthOut, host.outText), theme.info,
                               emphasised: sort == .outbound)
                }

                // Scaled to this row's own peak, not the list's. The question
                // a row-sized trace answers is "which way is this one
                // heading", and against a shared scale every row but the
                // busiest would be a flat line along the bottom.
                if let series = history[traceKey(host.ip)], series.count > 1 {
                    RowTrace(inSeries: series.map(\.inBps), outSeries: series.map(\.outBps))
                }
            }
        }
        // Kept after the bar went: `contentTransition(.numericText())` on the
        // rate labels needs an animation to drive it, and without one the
        // figures snap between captures rather than counting across.
        .animation(.easeOut(duration: 0.3), value: host.total)
    }

    /// The name and address, selectable only where the row does not navigate.
    ///
    /// Written as two branches rather than one modifier taking a ternary.
    /// `.enabled` and `.disabled` are two different types conforming to
    /// `TextSelectability`, not two cases of one, so a ternary between them
    /// does not type-check — the choice has to be which modifier is applied,
    /// not which argument it gets.
    @ViewBuilder
    private func identity(_ host: HostTraffic, linked: Bool) -> some View {
        if linked {
            // Selectable text swallows the tap that would follow the link, so
            // rows that go somewhere do not offer it.
            identityLabel(host, linked: true)
        } else {
            identityLabel(host, linked: false).textSelection(.enabled)
        }
    }

    private func identityLabel(_ host: HostTraffic, linked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(host.hostname ?? host.ip)
                    .scaledFont(13, weight: .semibold)
                    .foregroundStyle(theme.label)
                if linked {
                    Image(systemName: "chevron.right")
                        .scaledFont(9, weight: .semibold)
                        .foregroundStyle(theme.labelFaint)
                }
            }
            if host.hostname != nil {
                Text(host.ip)
                    .scaledFont(10, design: .monospaced)
                    .foregroundStyle(theme.labelFaint)
            }
        }
    }

    private func rateColumn(_ label: String, _ value: String, _ colour: Color,
                            emphasised: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .scaledFont(12, weight: emphasised ? .semibold : .regular, design: .monospaced)
                .foregroundStyle(emphasised ? colour : colour.opacity(0.65))
                .contentTransition(.numericText())
            Text(label)
                .scaledFont(8, weight: .medium)
                .foregroundStyle(theme.labelFaint)
        }
    }

    /// The firewall's own text wins when the parser could not read it.
    ///
    /// A parse failure rendered as "0 bit/s" would be a lie about a
    /// measurement, and reporting measurements is the whole point of this
    /// screen. A zero the firewall actually wrote as "0" is not a failure and
    /// formats normally.
    private func rateText(_ value: Double, _ raw: String) -> String {
        if value == 0 && raw.trimmingCharacters(in: .whitespaces) != "0" {
            return raw
        }
        return Rate.bits(value)
    }

    /// Whatever pfSense wrote when it wrote no rows.
    ///
    /// What used to be here was four paragraphs explaining the capture
    /// interval, the ten-host cap, what the row traces mean and what Local
    /// means on a WAN. All true, and all of it read once and then sat under a
    /// live screen forever. The constraints are in `PHPSnippets.hostTraffic`
    /// and in this file's own documentation, where they are of use to somebody
    /// changing the code rather than to somebody watching a graph.
    ///
    /// This line stays because it only appears when the list is empty, and
    /// when the list is empty it is the only thing on screen that says why.
    @ViewBuilder
    private var note: some View {
        // `allRows`, not `rows`: a search that happens to match nothing is not
        // the firewall reporting nothing, and showing its raw output
        // underneath would read as though it were.
        if let raw = sample?.raw, !raw.isEmpty, allRows.isEmpty {
            Text(raw)
                .scaledFont(11, design: .monospaced)
                .foregroundStyle(theme.labelFaint)
                .textSelection(.enabled)
                .padding(.horizontal, 2)
        }
    }

    // MARK: The loop

    private func traceKey(_ ip: String) -> String { ClientAddress.key(ip) ?? ip }

    private func recordHistory(_ result: HostTrafficSample) {
        let now = Date()
        var seen = Set<String>()

        for host in result.hosts {
            let key = traceKey(host.ip)
            seen.insert(key)
            var series = history[key] ?? []
            series.append(ThroughputTracker.Point(at: now,
                                                  inBps: host.bandwidthIn,
                                                  outBps: host.bandwidthOut))
            history[key] = Array(series.suffix(traceLength))
        }

        // A row that fell out of the top ten carries a zero rather than a gap,
        // so the trace keeps a time axis and a device winding down is drawn
        // winding down rather than simply vanishing. It is the same ambiguity
        // the list itself has — out of the ten is not proof of silence — and
        // the note under the list says so.
        //
        // Once its whole window is zeros it is forgotten. Otherwise a firewall
        // left on this screen accumulates a trace for every address that has
        // ever been busy on that interface.
        for (key, series) in history where !seen.contains(key) {
            let next = Array((series + [ThroughputTracker.Point(at: now, inBps: 0, outBps: 0)])
                .suffix(traceLength))
            if next.allSatisfy({ $0.inBps == 0 && $0.outBps == 0 }) {
                history.removeValue(forKey: key)
            } else {
                history[key] = next
            }
        }
    }

    private func applyPreselection() {
        if !hasPreselected {
            hasPreselected = true
            if let preselect,
               let index = interfaces.firstIndex(where: { $0.internalName == preselect }) {
                slot = index
            }
        }
        applySuggestedFilter()
    }

    /// Start each interface on the filter that will actually return something.
    ///
    /// Opening a WAN or a tunnel and being shown an empty list reads as a
    /// broken screen, and on both of those an empty list is exactly what Local
    /// correctly returns — a tunnel has no local subnet, and a WAN's local
    /// subnet is the ISP's side of the link.
    ///
    /// Applied once per interface. Choosing a filter by hand afterwards is a
    /// deliberate act and is not undone until the interface changes.
    private func applySuggestedFilter() {
        guard let selected, filterSuggestedFor != slot else { return }
        filterSuggestedFor = slot
        filter = selected.suggestedHostFilter
    }

    private func run() async {
        // Reset rather than carry over: the previous run answered a different
        // question, and its rows sitting under a changed picker would be
        // read as the new answer.
        sample = nil
        sampledAt = nil
        error = nil
        // The previous run measured a different interface, filter or sort.
        // Its traces describe a different question and would be read as
        // history for this one.
        history = [:]

        var consecutiveFailures = 0

        while !Task.isCancelled {
            guard let selected else {
                // The dashboard may not have loaded interfaces yet.
                try? await Task.sleep(for: .seconds(2))
                continue
            }

            let startedAt = Date()
            do {
                let result = try await store.client.hostTraffic(slot: slot, filter: filter, sort: sort)

                // The interface list and the sampler both walk
                // get_configured_interface_with_descr(), so position n is the
                // same interface in both. Checked anyway: a silent mismatch
                // would label one interface's traffic with another's name,
                // which is a worse failure than an error message. Retrying
                // would ask the identical question, so this run stops.
                if let expected = selected.internalName, !expected.isEmpty,
                   !result.interface.isEmpty, result.interface != expected {
                    error = "The firewall sampled \(result.interface) when \(expected) was asked for. Refresh the dashboard, then pick the interface again."
                    sample = nil
                    return
                }

                sample = result
                sampledAt = Date()
                error = nil
                consecutiveFailures = 0
                recordHistory(result)

                // Folded into the hourly record as well as the row traces.
                // The traces are two minutes and belong to this screen; the
                // record outlives it, which is the only reason there is
                // anything to look back at.
                store.topTalkers.record(
                    result.hosts,
                    serverID: store.profile.id.uuidString,
                    interface: result.interface,
                    interfaceName: selected.name
                ) { store.nameForAddress($0) }
            } catch {
                if error is CancellationError || (error as? RPCError) == .cancelled { return }
                self.error = error.localizedDescription
                consecutiveFailures += 1
            }

            // A failed capture backs off; a good one goes straight round
            // again. A monitor should not give up on one bad request, and it
            // should not hammer a firewall that is struggling either.
            let wait: TimeInterval = consecutiveFailures == 0
                ? max(0, period - Date().timeIntervalSince(startedAt))
                : Double(min(2 << min(consecutiveFailures, 3), 15))
            do {
                try await Task.sleep(for: .seconds(wait))
            } catch {
                return
            }
        }
    }
}

/// A row-sized trace. Twenty points, two directions, no furniture.
///
/// `Sparkline` already exists and is the wrong tool here: it carries axis
/// labels, gridlines and a tap-to-inspect tooltip, all of which are right for
/// a card and wrong for a strip under two numbers — and its tap gesture would
/// fight the link the row now is.
///
/// Deliberately not interactive and deliberately unlabelled. The numbers above
/// it are the measurement; this only has to answer "rising or falling", and
/// anything more would be competing with the row it belongs to.
struct RowTrace: View {
    @Environment(\.themeManager) private var theme: ThemeManager

    let inSeries: [Double]
    let outSeries: [Double]
    var height: CGFloat = 20

    /// Both directions share one scale so they stay comparable. Scaling each
    /// independently would draw a device downloading at 5 Mbit and uploading
    /// at 3 kbit as two lines of similar size.
    private var peak: Double {
        max(inSeries.max() ?? 0, outSeries.max() ?? 0, 1)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                area(outSeries, in: geo.size, colour: theme.info)
                area(inSeries, in: geo.size, colour: theme.ok)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func area(_ values: [Double], in size: CGSize, colour: Color) -> some View {
        let step = values.count > 1 ? size.width / CGFloat(values.count - 1) : size.width
        let points = values.enumerated().map { index, value in
            CGPoint(x: CGFloat(index) * step,
                    y: size.height - (CGFloat(value / peak) * size.height * 0.9) - 1)
        }
        return ZStack {
            Path { path in
                guard let first = points.first else { return }
                path.move(to: CGPoint(x: first.x, y: size.height))
                path.addLine(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
                path.addLine(to: CGPoint(x: points.last?.x ?? 0, y: size.height))
                path.closeSubpath()
            }
            .fill(colour.opacity(0.18))

            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
            }
            .stroke(colour.opacity(0.85), style: StrokeStyle(lineWidth: 1.2,
                                                             lineCap: .round,
                                                             lineJoin: .round))
        }
    }
}

/// The panel as a screen of its own.
///
/// It lives in the Clients tab now, next to the device list, because "which
/// device is using the bandwidth" and "which devices are there" are the same
/// question asked twice. This wrapper is what an interface's detail screen
/// pushes, so that route still arrives somewhere with a title and a back
/// button rather than dropping the person into a tab.
struct TrafficView: View {
    @Environment(\.themeManager) private var theme: ThemeManager

    var preselect: String?

    var body: some View {
        ScrollView {
            HostTrafficPanel(preselect: preselect)
                .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("Host traffic")
        .navigationBarTitleDisplayMode(.inline)
    }
}
