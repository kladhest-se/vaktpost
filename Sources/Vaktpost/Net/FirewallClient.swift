import Foundation

/// The typed surface the rest of the app talks to.
///
/// Deliberately the same method names the REST client had, so the store, the
/// models and the views did not change when the transport did. What changed is
/// underneath: each call runs a snippet from `PHPSnippet` rather than hitting
/// an endpoint.
actor FirewallClient {

    private let rpc: XMLRPCClient

    init(profile: ServerProfile, allowsTrustPrompt: Bool = true, onPin: @escaping TrustEvaluator.PinHandler) {
        self.rpc = XMLRPCClient(profile: profile, allowsTrustPrompt: allowsTrustPrompt, onPin: onPin)
    }

    func invalidate() async {
        await rpc.invalidate()
    }

    var lastSeenFingerprint: String? {
        get async { await rpc.lastSeenFingerprint }
    }

    // MARK: System

    func systemStatus() async throws -> SystemStatus {
        SystemStatus(try await rpc.runObject(.telemetry))
    }

    /// The state table comes back inside the telemetry snippet rather than
    /// from a call of its own — one `exec_php` round trip is expensive enough
    /// that splitting it would cost more than the tidiness is worth.
    func stateTableSize(from status: JSONDict) -> StateTableSize {
        StateTableSize(status)
    }

    func stateTableSize() async throws -> StateTableSize {
        StateTableSize(try await rpc.runObject(.telemetry))
    }

    func systemVersion() async throws -> SystemVersion {
        SystemVersion(try await rpc.runObject(.firmware))
    }

    func filesystems() async throws -> [Filesystem] {
        let dict = try await rpc.runObject(.telemetry)
        return dict.list("filesystems").compactMap { JSONDict($0) }.map(Filesystem.init)
    }

    func packages() async throws -> [PackageInfo] {
        try await rpc.runList(.packages).map(PackageInfo.init)
    }

    /// Package versions checked against the repository.
    ///
    /// Returns nil when this pfSense has no `get_pkg_info`. Two minutes of
    /// timeout because the call reaches the repository over the network.
    func packageUpdates() async throws -> [PackageInfo]? {
        let payload = try await rpc.runObject(.packageUpdates, timeout: 120)
        guard payload.bool("available") == true else { return nil }
        return payload.list("data").compactMap { JSONDict($0) }.map(PackageInfo.init)
    }

    func notices() async throws -> [SystemNotice] {
        try await rpc.runList(.notices).map(SystemNotice.init)
    }

    // MARK: Network

    func interfaces() async throws -> [InterfaceStat] {
        try await rpc.runList(.interfaces).map(InterfaceStat.init)
    }

    /// Counters only, for the interface screen's faster poll.
    func interfaceCounters() async throws -> [InterfaceStat] {
        try await rpc.runList(.interfaceCounters).map(InterfaceStat.init)
    }

    /// Per-host rates for one interface, sampled now.
    ///
    /// Unlike every other call here this one costs the firewall a one-second
    /// packet capture — see `PHPSnippet.hostTraffic`. It is never on the
    /// refresh timer; something has to ask for it.
    ///
    /// The timeout allows for that second plus the webConfigurator lock the
    /// call queues behind, which on a busy firewall is the larger of the two.
    func hostTraffic(slot: Int,
                     filter: PHPSnippet.HostFilter,
                     sort: PHPSnippet.HostSort) async throws -> HostTrafficSample {
        HostTrafficSample(try await rpc.runObject(
            PHPSnippet.hostTraffic(slot: slot, filter: filter, sort: sort), timeout: 60))
    }

    func gateways() async throws -> [GatewayStatus] {
        try await rpc.runList(.gateways).map(GatewayStatus.init)
    }

    func arpTable() async throws -> [ARPEntry] {
        try await rpc.runList(.arpTable).map(ARPEntry.init)
    }

    func leases() async throws -> [DHCPLease] {
        try await rpc.runList(.dhcpLeases).map(DHCPLease.init)
    }

    func hostOverrides() async throws -> [HostOverride] {
        try await rpc.runList(.hostOverrides).map(HostOverride.init)
    }

    func staticMappings() async throws -> [StaticMapping] {
        try await rpc.runList(.staticMappings).map(StaticMapping.init)
    }

    // MARK: Services and VPN

    func services() async throws -> [ServiceStatus] {
        try await rpc.runList(.services).map(ServiceStatus.init)
    }

    func openvpnServers() async throws -> [OpenVPNServerStatus] {
        try await rpc.runList(.openvpnServers).map(OpenVPNServerStatus.init)
    }

    func openvpnClients() async throws -> [OpenVPNServerStatus] {
        try await rpc.runList(.openvpnClients).map(OpenVPNServerStatus.init)
    }

    func ipsecSAs() async throws -> [IPsecSA] {
        try await rpc.runList(.ipsecSAs).map(IPsecSA.init)
    }

    /// Tunnels and peers together — one call, since `wg_get_status()` returns
    /// both and a second round trip would cost another firewall-side lock.
    func wireguard() async throws -> (tunnels: [WireGuardTunnel], peers: [WireGuardPeer]) {
        let payload = try await rpc.runObject(.wireguard)
        return (
            payload.list("tunnels").compactMap { JSONDict($0) }.map(WireGuardTunnel.init),
            payload.list("peers").compactMap { JSONDict($0) }.map(WireGuardPeer.init)
        )
    }

    /// pf tables, when this pfSense exposes an accessor for them.
    ///
    /// Returns nil when it does not, which is different from returning none —
    /// "no accessor" and "nothing blocked" should not look the same.
    func pfTables() async throws -> [FirewallTable]? {
        let payload = try await rpc.runObject(.pfTables)
        guard payload.bool("available") == true else { return nil }
        return payload.list("data").compactMap { JSONDict($0) }.map(FirewallTable.init)
    }

    /// HAProxy configuration, and which live-stats accessors this version has.
    ///
    /// Returns nil when the package is not installed, which is different from
    /// installed-with-nothing-configured.
    func haproxy() async throws -> (frontends: [HAProxyFrontend],
                                    backends: [HAProxyBackend],
                                    statsAccessors: [String])? {
        let payload = try await rpc.runObject(.haproxy)
        guard payload.bool("installed") == true else { return nil }
        return (
            payload.list("frontends").compactMap { JSONDict($0) }.map(HAProxyFrontend.init),
            payload.list("backends").compactMap { JSONDict($0) }.map(HAProxyBackend.init),
            payload.list("stats_accessors").compactMap { $0.stringValue }
        )
    }

    /// ACME configuration, or nil when the package is not installed.
    func acme() async throws -> (certificates: [ACMECertificate], accounts: [ACMEAccount])? {
        let payload = try await rpc.runObject(.acme)
        guard payload.bool("installed") == true else { return nil }
        return (
            payload.list("certificates").compactMap { JSONDict($0) }.map(ACMECertificate.init),
            payload.list("accounts").compactMap { JSONDict($0) }.map(ACMEAccount.init)
        )
    }

    /// A day of recorded traffic, if this pfSense can read its own RRD files.
    func rrdTraffic(_ window: PHPSnippet.RRDWindow) async throws -> RRDHistory {
        RRDHistory(try await rpc.runObject(PHPSnippet.rrdTraffic(window), timeout: 90))
    }

    // MARK: Batches

    /// One call's worth of sections, keyed by the name the individual snippet
    /// used. Sections decode from these exactly as they did from their own
    /// responses, so nothing downstream had to change shape.
    struct Batch {
        private let sections: JSONDict?

        init(_ payload: JSONDict) {
            sections = JSONDict(payload.value("sections"))
        }

        func require(_ names: [String]) throws {
            for name in names {
                guard let value = sections?.value(name) else {
                    throw RPCError.malformed("Missing section: \(name)")
                }
                if case .null = value { throw RPCError.malformed("Empty section: \(name)") }
                if let error = JSONDict(value)?.string("__error") { throw RPCError.fault(0, error) }
            }
        }

        /// A section that returns an object rather than rows.
        func object(_ name: String) -> JSONDict {
            JSONDict(sections?.value(name)) ?? JSONDict(.object([:]))!
        }

        /// A section's rows, unwrapped exactly as `runList` unwraps a response
        /// of its own — same envelope handling, same keyed-object folding.
        func rows(_ name: String) -> [JSONDict] {
            XMLRPCClient.rows(from: sections?.value(name))
        }
    }

    func batchCore() async throws -> Batch {
        let batch = Batch(try await rpc.runObject(.batchCore))
        try batch.require(["telemetry", "firmware", "interfaces", "gateways", "services"])
        return batch
    }

    func batchClients() async throws -> Batch {
        let batch = Batch(try await rpc.runObject(.batchClients))
        try batch.require(["dhcp_leases", "arp_table", "static_mappings", "host_overrides", "firewall_aliases"])
        return batch
    }

    func batchVPN() async throws -> Batch {
        let batch = Batch(try await rpc.runObject(.batchVpn))
        try batch.require(["openvpn_servers", "openvpn_clients", "ipsec_sas", "wireguard"])
        return batch
    }

    func batchSystem() async throws -> Batch {
        let batch = Batch(try await rpc.runObject(.batchSystem))
        try batch.require(["carp", "certificates", "packages", "notices", "dyndns"])
        return batch
    }

    // MARK: Firewall objects

    func firewallRules() async throws -> [FirewallRule] {
        try await rpc.runList(.firewallRules).map(FirewallRule.init)
    }

    func firewallAliases() async throws -> [FirewallAliasEntry] {
        try await rpc.runList(.firewallAliases).map(FirewallAliasEntry.init)
    }

    func portForwards() async throws -> [PortForward] {
        try await rpc.runList(.portForwards).map(PortForward.init)
    }

    // MARK: High availability

    func carp() async throws -> CARPStatus {
        CARPStatus(try await rpc.runObject(.carp))
    }

    func certificates() async throws -> [CertificateInfo] {
        try await rpc.runList(.certificates).map { dict in
            CertificateInfo(dict, isCA: dict.bool("is_ca") ?? false)
        }
    }

    // MARK: Dynamic DNS

    func dyndns() async throws -> [DyndnsEntry] {
        try await rpc.runList(.dyndns).map(DyndnsEntry.init)
    }

    // MARK: Logs

    func log(_ source: PHPSnippet.LogSource, limit: Int, kind: LogLine.Kind) async throws -> [LogLine] {
        let value = try await rpc.run(.log(source, limit: limit))
        let rows = JSONDict(value)?.list("data") ?? value.arrayValue ?? []
        // Log lines arrive as plain strings, newest last. Reversed so the most
        // recent is at the top, which is the order a person reads a log in.
        // Blank lines are dropped.
        //
        // A log file ends with a newline, so splitting it yields an empty
        // final element — which, reversed, became the first row: an empty card
        // sitting above every log on every tab.
        return rows.compactMap { $0.stringValue }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reversed()
            .map { LogLine(text: $0, kind: kind) }
    }

    func firewallLog(limit: Int) async throws -> [LogLine] {
        try await log(.filter, limit: limit, kind: .firewall)
    }
    func systemLog(limit: Int) async throws -> [LogLine] {
        try await log(.system, limit: limit, kind: .system)
    }
    func authLog(limit: Int) async throws -> [LogLine] {
        try await log(.auth, limit: limit, kind: .auth)
    }
    func dhcpLog(limit: Int) async throws -> [LogLine] {
        try await log(.dhcpd, limit: limit, kind: .dhcp)
    }
    func openvpnLog(limit: Int) async throws -> [LogLine] {
        try await log(.openvpn, limit: limit, kind: .openvpn)
    }

    // MARK: Onboarding

    /// Validates credentials and returns the firmware version.
    func ping() async throws -> String {
        let dict = try await rpc.runObject(.ping)
        return dict.string("version") ?? "connected"
    }
}
