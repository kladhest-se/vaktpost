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
    private var rows: [HostTraffic] {
        (sample?.hosts ?? [])
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            controls
            results
            note
        }
        .padding(.horizontal, 16)
        .onAppear(perform: applyPreselection)
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
                    Picker("Interface", selection: $slot) {
                        ForEach(Array(interfaces.enumerated()), id: \.offset) { index, iface in
                            Text(iface.name).tag(index)
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

                    liveIndicator
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

    private func hostRow(_ host: HostTraffic) -> some View {
        // No proportion bar.
        //
        // There was one, scaled against the busiest row in the capture. It
        // looked like information and was not: pfSense returns whichever ten
        // hosts happened to be busiest, so the bar's full width meant a
        // different rate every three seconds and a row could shrink while its
        // own throughput rose. The numbers are the measurement; a bar drawn
        // against a moving denominator only obscures them.
        Slab(rail: .info) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(host.hostname ?? host.ip)
                        .scaledFont(13, weight: .semibold)
                        .foregroundStyle(theme.label)
                    if host.hostname != nil {
                        Text(host.ip)
                            .scaledFont(10, design: .monospaced)
                            .foregroundStyle(theme.labelFaint)
                    }
                }
                .textSelection(.enabled)

                Spacer(minLength: 8)

                rateColumn("IN", rateText(host.bandwidthIn, host.inText), theme.ok,
                           emphasised: sort == .inbound)
                rateColumn("OUT", rateText(host.bandwidthOut, host.outText), theme.info,
                           emphasised: sort == .outbound)
            }
        }
        // Kept after the bar went: `contentTransition(.numericText())` on the
        // rate labels needs an animation to drive it, and without one the
        // figures snap between captures rather than counting across.
        .animation(.easeOut(duration: 0.3), value: host.total)
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

    @ViewBuilder
    private var note: some View {
        if sample != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("Refreshed every \(Int(period)) seconds for as long as this screen is open, each one a one-second packet capture on this interface. pfSense returns at most ten hosts and picks them by \(sort.displayName.lowercased()), so switching the sort can return a different set of devices rather than the same ones reordered.")

                // Local means the interface's own subnet, which on a LAN is
                // the clients and on a WAN is whatever the ISP has on the
                // other side of the link. Same filter, opposite meaning, and
                // the word does not say so.
                Text("Local means the interface's own subnet. On a VLAN that is your clients; on a WAN it is the addresses the ISP has on the far side of the link, so Remote is usually the one worth asking for there.")

                if let raw = sample?.raw, !raw.isEmpty, rows.isEmpty {
                    Text(raw)
                        .scaledFont(11, design: .monospaced)
                        .foregroundStyle(theme.labelFaint)
                        .textSelection(.enabled)
                }
            }
            .scaledFont(12)
            .foregroundStyle(theme.labelMuted)
            .padding(.horizontal, 2)
        }
    }

    // MARK: The loop

    private func applyPreselection() {
        guard !hasPreselected else { return }
        hasPreselected = true
        if let preselect,
           let index = interfaces.firstIndex(where: { $0.internalName == preselect }) {
            slot = index
        }
    }

    private func run() async {
        // Reset rather than carry over: the previous run answered a different
        // question, and its rows sitting under a changed picker would be
        // read as the new answer.
        sample = nil
        sampledAt = nil
        error = nil

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
