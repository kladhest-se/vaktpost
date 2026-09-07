import SwiftUI

/// UPnP and NAT-PMP mappings.
///
/// These are holes in the firewall that nobody wrote a rule for. A console or
/// a torrent client asks miniupnpd for a port and gets it, and the only record
/// is a lease file — so this is the one place where "what is open" and "what is
/// in the rules" can differ, which makes it worth a screen of its own.
struct UPnPView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore

    @State private var query = ""

    private var mappings: [UPnPMapping] {
        guard !query.isEmpty else { return store.upnpMappings }
        let q = query.lowercased()
        return store.upnpMappings.filter {
            $0.internalAddress.contains(q)
                || $0.externalPort.contains(q)
                || ($0.descr ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if let err = store.errors[.upnp] {
                    Notice(symbol: "exclamationmark.triangle",
                           title: "UPnP unavailable", detail: err, health: .warn)
                } else if !store.upnpInstalled {
                    Notice(symbol: "square.stack.3d.up.slash",
                           title: "The UPnP service is not installed")
                } else if let status = store.upnpStatus {
                    summary(status)

                    if status.mappingsReadable {
                        if store.upnpMappings.isEmpty {
                            Notice(symbol: "checkmark.shield",
                                   title: "No ports currently open")
                        } else {
                            ForEach(mappings) { mapping in
                                mappingRow(mapping)
                            }
                            if mappings.isEmpty {
                                Notice(symbol: "magnifyingglass", title: "No matches")
                            }
                        }
                    } else {
                        // Not an empty list.
                        //
                        // "No ports open" and "this app cannot see which ports
                        // are open" look the same on screen and mean opposite
                        // things, and the first is far more comforting than it
                        // deserves to be.
                        Slab(rail: .idle, title: "Which ports are open") {
                            Text("miniupnpd keeps its port maps in a pf anchor, and reading that needs a shell — which this app will not use. The webConfigurator shows them under Status → UPnP IGD & PCP.")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.labelMuted)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .refreshable { await store.refreshManually() }
        .background(theme.bg.ignoresSafeArea())
        .task { await store.loadUPnP() }
        .searchable(text: $query, prompt: "Address, port or description")
        .navigationTitle("UPnP")
    }

    @ViewBuilder
    private func mappingRow(_ mapping: UPnPMapping) -> some View {
        Slab(rail: .info, trailing: mapping.proto) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(mapping.descr ?? "(no description)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(mapping.descr == nil ? theme.labelFaint : theme.label)
                    Spacer(minLength: 8)
                    if let iface = mapping.interfaceName, !iface.isEmpty {
                        Text(store.interfaceLabel(for: iface) ?? iface)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(theme.labelFaint)
                    }
                }
                Text(mapping.route)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.labelMuted)
                    .textSelection(.enabled)
                if let name = store.nameForAddress(mapping.internalAddress),
                   name != mapping.internalAddress {
                    Text(name)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.labelFaint)
                }
            }
        }
    }

    /// What is actually knowable: whether the service is on and running.
    ///
    /// A running UPnP daemon is a standing offer to open ports on request,
    /// which is worth colouring even when the resulting ports cannot be listed.
    private func summary(_ status: UPnPStatus) -> some View {
        Slab(rail: status.health) {
            VStack(alignment: .leading, spacing: 4) {
                Text(headline(status))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.label)
                if let iface = status.externalInterface, !iface.isEmpty {
                    FieldRow(key: "External", value: store.interfaceLabel(for: iface) ?? iface)
                }
                Text(status.enabled
                     ? "Devices on the network can ask the firewall to open ports, and it will."
                     : "Nothing can open a port without a rule.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.labelFaint)
            }
        }
    }

    private func headline(_ status: UPnPStatus) -> String {
        if !status.enabled { return "UPnP is turned off" }
        return status.running ? "UPnP is on and running" : "UPnP is enabled but not running"
    }
}
