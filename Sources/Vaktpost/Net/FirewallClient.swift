import Foundation

/// The typed surface the rest of the app talks to.
///
/// Deliberately the same method names the REST client had, so the store, the
/// models and the views did not change when the transport did. What changed is
/// underneath: each call runs a snippet from `PHPSnippet` rather than hitting
/// an endpoint.
actor FirewallClient {

    private let rpc: XMLRPCClient
    private let administrationEnabled: Bool

    init(profile: ServerProfile, allowsTrustPrompt: Bool = true, onPin: @escaping TrustEvaluator.PinHandler) {
        self.administrationEnabled = profile.isAdministrationEnabled
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

    /// pfBlockerNG, or nil when the package is not installed.
    ///
    /// Installed is decided on the filesystem rather than on the presence of
    /// settings: a removed package leaves its configuration behind, and a
    /// screen that read that as installed would show zeros indefinitely.
    func pfBlocker() async throws -> PFBlockerStatus? {
        let payload = try await rpc.runObject(.pfBlocker)
        guard payload.bool("installed") == true else { return nil }
        return PFBlockerStatus(payload)
    }

    /// DNSBL block statistics, counted from the tail of pfBlockerNG's log.
    func dnsblStats() async throws -> DNSBLStats {
        DNSBLStats(try await rpc.runObject(.dnsblStats))
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

    /// Filter-rule and NAT separators plus pfSense's pending-apply marker,
    /// together, since the same lightweight call reads all three.
    func ruleSeparators() async throws -> (filter: [RuleSeparator], nat: [RuleSeparator], applyPending: Bool) {
        let payload = try await rpc.runObject(.ruleSeparators)
        let filter = payload.list("filter").compactMap(JSONDict.init).map(RuleSeparator.init)
        let nat = payload.list("nat").compactMap(JSONDict.init).map(RuleSeparator.init)
        return (filter, nat, payload.bool("apply_pending") ?? false)
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

    // MARK: Write operations

    private func requireAdministration() throws {
        guard administrationEnabled else { throw RPCError.administrationDisabled }
    }

    /// pfSense snippets report domain failures in their payload even when the
    /// XML-RPC request itself succeeded. Treat only an explicit `ok` as a
    /// successful mutation so callers cannot log or display a false success.
    @discardableResult
    static func validatedWriteResponse(_ dict: JSONDict, operation: String) throws -> JSONDict {
        guard let status = dict.string("status"), status == "ok" else {
            let status = dict.string("status") ?? "missing status"
            let detail = dict.string("error").flatMap { $0.isEmpty ? nil : $0 }
            let message = detail.map { "\(operation) failed (\(status)): \($0)" }
                ?? "\(operation) failed (\(status))."
            throw RPCError.fault(0, message)
        }
        return dict
    }

    /// Configuration writes are saves, not applies. Require the snippet to
    /// confirm that pfSense was left dirty so a missing marker cannot be
    /// presented as a successful WebUI-style staged change.
    static func validatedPendingWriteResponse(_ dict: JSONDict,
                                              operation: String) throws -> JSONDict {
        let result = try validatedWriteResponse(dict, operation: operation)
        guard result.bool("apply_pending") == true else {
            throw RPCError.fault(0, "\(operation) did not leave changes pending for Apply Changes.")
        }
        return result
    }

    /// A save is not complete until pfSense confirms whether it created or
    /// edited the object and returns the stable identity used for read-back.
    static func validatedSaveResponse(_ dict: JSONDict,
                                      operation: String,
                                      requestedTracker: String,
                                      isCreate: Bool) throws -> JSONDict {
        let result = try validatedPendingWriteResponse(dict, operation: operation)
        guard result.bool("created") == isCreate else {
            throw RPCError.fault(0, "\(operation) returned an inconsistent create/edit result.")
        }
        guard let tracker = result.string("tracker"), !tracker.isEmpty else {
            throw RPCError.malformed("\(operation) did not return a tracker ID.")
        }
        // Skipped when nothing was requested. An empty `requestedTracker` on
        // an edit means a legacy save healing an untracked NAT rule — there
        // was no tracker to differ *from*, so a freshly assigned one is the
        // correct result, not a mismatch. A filter-rule edit never reaches
        // this with an empty tracker at all; `WriteCoordinator.validate()`
        // requires one before the request is ever sent, so this relaxation
        // changes nothing for that path.
        if !isCreate, !requestedTracker.isEmpty, tracker != requestedTracker {
            throw RPCError.fault(0, "\(operation) returned a different tracker ID.")
        }
        return result
    }

    /// Reloads the firewall ruleset.
    func reloadFirewall() async throws -> String {
        try requireAdministration()
        let dict = try await rpc.runObjectOnce(.reloadFirewall)
        _ = try Self.validatedWriteResponse(dict, operation: "Firewall reload")
        return "ok"
    }

    /// Restarts a pfSense service by name.
    func restartService(named serviceName: String) async throws -> String {
        try requireAdministration()
        let snippet = PHPSnippet.restartService(serviceName: serviceName)
        let dict = try await rpc.runObjectOnce(snippet)
        _ = try Self.validatedWriteResponse(dict, operation: "Service restart")
        return "ok"
    }

    /// Adds a quick-block rule to block an IP address.
    ///
    /// - Parameters:
    ///   - interface: The interface to block on.
    ///   - address: The IP address or subnet to block.
    ///   - description: A description for the rule.
    func quickBlock(interface: String, address: String, description: String) async throws -> JSONDict {
        try requireAdministration()
        let snippet = PHPSnippet.quickBlock(interface: interface, address: address, description: description)
        let dict = try await rpc.runObjectOnce(snippet)
        return try Self.validatedPendingWriteResponse(dict, operation: "Quick block")
    }

    /// Flushes the firewall state table.
    ///
    /// - Parameter interface: Optional interface to flush states for. Empty means all.
    func flushStates(interface: String = "") async throws -> String {
        try requireAdministration()
        let snippet = PHPSnippet.flushStates(interface: interface)
        let dict = try await rpc.runObjectOnce(snippet)
        _ = try Self.validatedWriteResponse(dict, operation: "State flush")
        return "ok"
    }

    /// Deletes a firewall rule by tracker ID.
    func deleteRule(tracker: String) async throws -> String {
        try requireAdministration()
        let snippet = PHPSnippet.deleteRule(tracker: tracker)
        let dict = try await rpc.runObjectOnce(snippet)
        _ = try Self.validatedPendingWriteResponse(dict, operation: "Rule deletion")
        return "ok"
    }

    /// Deletes a NAT/port forward rule by tracker ID.
    func deleteNatRule(tracker: String) async throws -> String {
        try requireAdministration()
        guard !tracker.isEmpty else {
            throw RPCError.malformed("Port-forward deletion requires a tracker ID.")
        }
        let snippet = PHPSnippet.deleteNatRule(tracker: tracker)
        let dict = try await rpc.runObjectOnce(snippet)
        _ = try Self.validatedPendingWriteResponse(dict, operation: "Port-forward deletion")
        return "ok"
    }

    /// Saves (creates or updates) a firewall rule.
    func saveRule(rule: JSONDict) async throws -> JSONDict {
        try requireAdministration()
        let tracker = rule.string("tracker") ?? ""
        let isCreate = rule.bool("create") ?? false
        guard (isCreate && tracker.isEmpty) || (!isCreate && !tracker.isEmpty) else {
            throw RPCError.malformed(isCreate
                                     ? "Rule creation must not supply a tracker ID."
                                     : "Rule editing requires a tracker ID.")
        }
        let snippet = PHPSnippet.saveRule(rule: rule)
        let dict = try await rpc.runObjectOnce(snippet)
        let result = try Self.validatedSaveResponse(
            dict, operation: "Rule save", requestedTracker: tracker, isCreate: isCreate
        )
        let placement = rule.string("placement") ?? (isCreate ? "last" : "keep")
        guard result.string("placement") == placement else {
            throw RPCError.fault(0, "Rule save returned a different placement result.")
        }
        if placement == "before",
           result.string("before_tracker") != rule.string("before_tracker") {
            throw RPCError.fault(0, "Rule save returned a different position anchor.")
        }
        return result
    }

    /// Saves (creates or updates) a NAT/port forward rule.
    func saveNatRule(rule: JSONDict) async throws -> JSONDict {
        try requireAdministration()
        let tracker = rule.string("tracker") ?? ""
        let isCreate = rule.bool("create") ?? false
        // pfSense assigns no tracker to a NAT rule at all through its own web
        // GUI — confirmed against `firewall_nat_edit.php`, which identifies a
        // forward purely by array position. So an edit of a forward nobody
        // has saved through this app yet legitimately arrives with no
        // tracker, and the snippet already has a complete fallback for that:
        // it matches on the forward's original interface, destination, port
        // and target instead, and heals it with a fresh tracker on save.
        //
        // This guard used to reject that case outright, before the payload —
        // which already carried those original fields — ever left the
        // phone. `WriteCoordinator.validate()` already knew about the
        // fallback; this method had not been told.
        let hasLegacyIdentity = !(rule.string("original_interface") ?? "").isEmpty
            && !(rule.string("original_target") ?? "").isEmpty
        guard (isCreate && tracker.isEmpty)
                || (!isCreate && (!tracker.isEmpty || hasLegacyIdentity)) else {
            throw RPCError.malformed(isCreate
                                     ? "Port-forward creation must not supply a tracker ID."
                                     : "Port-forward editing requires a tracker ID or the forward's original identity.")
        }
        let snippet = PHPSnippet.saveNatRule(rule: rule)
        let dict = try await rpc.runObjectOnce(snippet)
        return try Self.validatedSaveResponse(
            dict, operation: "Port-forward save", requestedTracker: tracker, isCreate: isCreate
        )
    }

    /// Creates or updates one separator in an interface's filter rules.
    func saveFilterSeparator(separator: JSONDict) async throws -> JSONDict {
        try requireAdministration()
        let isCreate = separator.bool("create") ?? false
        let key = separator.string("key") ?? ""
        guard (isCreate && key.isEmpty) || (!isCreate && !key.isEmpty) else {
            throw RPCError.malformed(isCreate
                                     ? "Separator creation must not supply a key."
                                     : "Separator editing requires its pfSense key.")
        }
        let dict = try await rpc.runObjectOnce(PHPSnippet.saveFilterSeparator(separator: separator))
        let result = try Self.validatedPendingWriteResponse(dict, operation: "Separator save")
        guard !(result.string("key") ?? "").isEmpty else {
            throw RPCError.fault(0, "Separator save did not return its pfSense key.")
        }
        return result
    }

    /// Deletes one separator from an interface's filter rules.
    func deleteFilterSeparator(interface: String, key: String) async throws -> JSONDict {
        try requireAdministration()
        guard !interface.isEmpty, !key.isEmpty else {
            throw RPCError.malformed("Separator deletion requires an interface and key.")
        }
        let dict = try await rpc.runObjectOnce(
            PHPSnippet.deleteFilterSeparator(interface: interface, key: key)
        )
        return try Self.validatedPendingWriteResponse(dict, operation: "Separator deletion")
    }

    /// Creates or updates one separator in the flat NAT port-forward table.
    func saveNatSeparator(separator: JSONDict) async throws -> JSONDict {
        try requireAdministration()
        let isCreate = separator.bool("create") ?? false
        let key = separator.string("key") ?? ""
        guard (isCreate && key.isEmpty) || (!isCreate && !key.isEmpty) else {
            throw RPCError.malformed(isCreate
                                     ? "NAT separator creation must not supply a key."
                                     : "NAT separator editing requires its pfSense key.")
        }
        let dict = try await rpc.runObjectOnce(PHPSnippet.saveNatSeparator(separator: separator))
        let result = try Self.validatedPendingWriteResponse(dict, operation: "NAT separator save")
        guard !(result.string("key") ?? "").isEmpty else {
            throw RPCError.fault(0, "NAT separator save did not return its pfSense key.")
        }
        return result
    }

    /// Deletes one separator from the flat NAT port-forward table.
    func deleteNatSeparator(key: String) async throws -> JSONDict {
        try requireAdministration()
        guard !key.isEmpty else {
            throw RPCError.malformed("NAT separator deletion requires its pfSense key.")
        }
        let dict = try await rpc.runObjectOnce(PHPSnippet.deleteNatSeparator(key: key))
        return try Self.validatedPendingWriteResponse(dict, operation: "NAT separator deletion")
    }

    /// One item in a drag-produced order: a rule by tracker, or a separator
    /// by its pfSense key.
    enum ReorderItem {
        case rule(tracker: String)
        case separator(key: String)

        var json: JSONValue {
            switch self {
            case .rule(let tracker):
                return .object(["kind": .string("rule"), "id": .string(tracker)])
            case .separator(let key):
                return .object(["kind": .string("separator"), "id": .string(key)])
            }
        }

        /// A single comparable string, for building and comparing whole
        /// orders without repeatedly pattern-matching the case.
        var token: String {
            switch self {
            case .rule(let tracker): return "rule:\(tracker)"
            case .separator(let key): return "separator:\(key)"
            }
        }
    }

    /// One port forward in a drag-produced NAT order.
    ///
    /// pfSense does not assign trackers to WebUI-created NAT rules, so a NAT
    /// reorder cannot safely use the filter-rule identity scheme above. The
    /// original array position is paired with the fields that identify the
    /// forward. The PHP write validates that pair against the current config
    /// before moving the complete, untouched rule dictionary.
    struct NatReorderItem: Sendable {
        let originalIndex: Int
        let tracker: String
        let interfaceName: String
        let destinationKind: String
        let destinationAddress: String
        let destinationPort: String
        let target: String
        let localPort: String

        init(originalIndex: Int, forward: PortForward) {
            self.originalIndex = originalIndex
            tracker = forward.tracker
            interfaceName = forward.interfaceName
            destinationKind = forward.destinationSide.storageKind.rawValue
            destinationAddress = forward.destinationSide.address
            destinationPort = forward.destinationSide.port ?? ""
            target = forward.target
            localPort = forward.localPort ?? ""
        }

        var json: JSONValue {
            .object([
                "original_index": .number(Double(originalIndex)),
                "tracker": .string(tracker),
                "interface": .string(interfaceName),
                "destination_kind": .string(destinationKind),
                "destination_address": .string(destinationAddress),
                "destination_port": .string(destinationPort),
                "target": .string(target),
                "local_port": .string(localPort)
            ])
        }

        var identityToken: String {
            [tracker, interfaceName, destinationKind, destinationAddress,
             destinationPort, target, localPort].joined(separator: "\u{1f}")
        }

        func matches(_ forward: PortForward, at index: Int) -> Bool {
            originalIndex == index
                && tracker == forward.tracker
                && interfaceName == forward.interfaceName
                && destinationKind == forward.destinationSide.storageKind.rawValue
                && destinationAddress == forward.destinationSide.address
                && destinationPort == (forward.destinationSide.port ?? "")
                && target == forward.target
                && localPort == (forward.localPort ?? "")
        }
    }

    /// Reorders one interface's filter rules and separators, from a complete
    /// drag-produced arrangement.
    func reorderFilterRules(interface: String, items: [ReorderItem]) async throws -> JSONDict {
        try requireAdministration()
        guard !interface.isEmpty else {
            throw RPCError.malformed("Reordering rules requires an interface.")
        }
        guard !items.isEmpty else {
            throw RPCError.malformed("Reordering rules requires a non-empty order.")
        }
        let snippet = PHPSnippet.reorderFilterRules(interface: interface, items: items.map(\.json))
        let dict = try await rpc.runObjectOnce(snippet)
        return try Self.validatedPendingWriteResponse(dict, operation: "Rule reorder")
    }

    /// Reorders the complete flat NAT rule table.
    func reorderNatRules(items: [NatReorderItem]) async throws -> JSONDict {
        try requireAdministration()
        guard !items.isEmpty else {
            throw RPCError.malformed("Reordering port forwards requires a non-empty order.")
        }
        let snippet = PHPSnippet.reorderNatRules(items: items.map(\.json))
        let dict = try await rpc.runObjectOnce(snippet)
        return try Self.validatedPendingWriteResponse(dict, operation: "Port-forward reorder")
    }


    // MARK: - Staged operations

    /// Represents a staged write operation ready for batch apply.
}
