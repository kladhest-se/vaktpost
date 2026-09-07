import SwiftUI

/// HAProxy frontends and backends.
///
/// The question this screen answers is the one you asked: **is backend
/// monitoring set up?** A backend with no health check will keep sending
/// traffic to a server after it dies, because HAProxy only knows a server is
/// down if something told it to look. That is a configuration fact, readable
/// from `$config`, and it is arguably more useful than live status — live
/// status tells you a server is down now, this tells you that you would never
/// find out.
///
/// Live per-server health is not here. It lives in HAProxy's admin socket, and
/// reading it means writing `show stat` to a socket that also accepts
/// `disable server`. Nothing checking this app's source could tell those apart,
/// so the read-only guarantee would become a promise instead of a property.
/// See SECURITY.md.
struct HAProxyView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore

    @State private var query = ""
    @State private var pane: Pane = .backends

    enum Pane: String, CaseIterable, Identifiable {
        case backends = "Backends", frontends = "Frontends"
        var id: String { rawValue }
    }

    private var backends: [HAProxyBackend] {
        guard !query.isEmpty else { return store.haproxyBackends }
        let q = query.lowercased()
        return store.haproxyBackends.filter {
            $0.name.lowercased().contains(q)
                || ($0.descr ?? "").lowercased().contains(q)
                || $0.servers.contains { s in
                    s.name.lowercased().contains(q) || s.address.contains(q)
                }
        }
    }

    private var frontends: [HAProxyFrontend] {
        guard !query.isEmpty else { return store.haproxyFrontends }
        let q = query.lowercased()
        return store.haproxyFrontends.filter {
            $0.name.lowercased().contains(q) || ($0.descr ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $pane) {
                ForEach(Pane.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if let err = store.errors[.haproxy] {
                        Notice(symbol: "exclamationmark.triangle",
                               title: "HAProxy unavailable", detail: err, health: .warn)
                    } else if !store.haproxyInstalled {
                        Notice(symbol: "square.stack.3d.up.slash",
                               title: "HAProxy is not installed on this firewall")
                    } else {
                        switch pane {
                        case .backends: backendsPane
                        case .frontends: frontendsPane
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .refreshable { await store.refreshManually() }
        }
        .background(theme.bg.ignoresSafeArea())
        .task { await store.loadHAProxy() }
        .searchable(text: $query, prompt: "Backend, server or address")
        .navigationTitle("HAProxy")
    }

    @ViewBuilder
    private var backendsPane: some View {
        if store.haproxyBackends.isEmpty {
            Notice(symbol: "server.rack", title: "No backends configured")
        } else {
            monitoringSummary
            ForEach(backends) { BackendCard(backend: $0) }
            if backends.isEmpty { Notice(symbol: "magnifyingglass", title: "No matches") }
            liveStatusNote
        }
    }

    /// The headline: how many backends would notice a dead server.
    private var monitoringSummary: some View {
        let unmonitored = store.haproxyBackends.filter { !$0.isMonitored }
        return Slab(rail: unmonitored.isEmpty ? .ok : .warn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(unmonitored.isEmpty
                     ? "All \(store.haproxyBackends.count) backends have health checks"
                     : "\(unmonitored.count) of \(store.haproxyBackends.count) have no health check")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.label)
                Text(unmonitored.isEmpty
                     ? "HAProxy will stop sending traffic to a server that fails its check."
                     : "HAProxy keeps sending traffic to servers in these backends whether they answer or not.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.labelFaint)
            }
        }
    }

    /// Honest about what this screen does not show.
    private var liveStatusNote: some View {
        Slab(rail: .idle) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Configuration, not live status")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.labelMuted)
                Text(store.haproxyStatsAccessors.isEmpty
                     ? "Whether each server is up right now lives in HAProxy's admin socket, which this app will not open — the same socket accepts commands that disable servers."
                     : "This pfSense exposes \(store.haproxyStatsAccessors.joined(separator: ", ")), so live status could be added.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.labelFaint)
            }
        }
    }

    @ViewBuilder
    private var frontendsPane: some View {
        if store.haproxyFrontends.isEmpty {
            Notice(symbol: "arrow.down.left.and.arrow.up.right", title: "No frontends configured")
        } else {
            ForEach(frontends) { frontend in
                Slab(rail: frontend.health, trailing: frontend.type) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(frontend.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.label)
                            Spacer()
                            if !frontend.enabled { StatusPill(text: "disabled", health: .idle) }
                        }
                        if let descr = frontend.descr, !descr.isEmpty {
                            Text(descr)
                                .font(.system(size: 11))
                                .foregroundStyle(theme.labelFaint)
                        }
                        FieldRow(key: "Binds", value: frontend.bindDescription)
                        if let routing = frontend.routingDescription {
                            FieldRow(key: "Routes to", value: routing, mono: false)
                        }
                    }
                }
            }
            if frontends.isEmpty { Notice(symbol: "magnifyingglass", title: "No matches") }
        }
    }
}

struct BackendCard: View {
    @EnvironmentObject private var theme: ThemeManager
    let backend: HAProxyBackend

    var body: some View {
        Slab(rail: backend.health, trailing: backend.balance) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(backend.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.label)
                    Spacer(minLength: 8)
                    StatusPill(
                        text: backend.isMonitored ? "checked" : "unchecked",
                        health: backend.isMonitored ? .ok : .warn
                    )
                }

                if let descr = backend.descr, !descr.isEmpty {
                    Text(descr)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.labelFaint)
                }

                Text(backend.checkDescription)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(backend.isMonitored ? theme.labelMuted : theme.warn)

                if !backend.servers.isEmpty {
                    Hairline()
                    ForEach(backend.servers) { server in
                        HStack {
                            Text(server.name)
                                .font(.system(size: 12))
                                .foregroundStyle(server.enabled ? theme.label : theme.labelFaint)
                            if server.ssl {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(theme.labelFaint)
                            }
                            Spacer()
                            Text(server.endpoint)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(theme.labelFaint)
                            if !server.enabled {
                                Text("off")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(theme.idle)
                            }
                        }
                    }
                }
            }
        }
    }
}
