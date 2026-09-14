import Foundation

/// Every mutating operation `FirewallClient` exposes.
///
/// Split from `FirewallClient.swift` on size alone — the read operations and
/// the write operations were already two halves of the same actor, and this
/// is that split made real. Nothing here changed behaviour; `requireAdministration()`
/// and the three response validators moved with their callers since they are
/// private to this half of the actor and used by nothing else.
extension FirewallClient {
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

    /// Creates or updates an inline firewall alias. The change is deliberately
    /// staged: it does not alter the active ruleset until Apply Changes runs.
    func saveAlias(alias: JSONDict) async throws -> JSONDict {
        try requireAdministration()
        let isCreate = alias.bool("create") ?? false
        let name = alias.string("name") ?? ""
        let originalName = alias.string("original_name") ?? ""
        guard !name.isEmpty,
              (isCreate && originalName.isEmpty) || (!isCreate && originalName == name) else {
            throw RPCError.malformed(isCreate
                                     ? "Alias creation requires a new name."
                                     : "Alias editing requires its unchanged original name.")
        }
        let dict = try await rpc.runObjectOnce(PHPSnippet.saveAlias(alias: alias))
        let result = try Self.validatedPendingWriteResponse(dict, operation: "Alias save")
        guard result.string("name") == name,
              result.bool("created") == isCreate else {
            throw RPCError.fault(0, "Alias save returned an inconsistent result.")
        }
        return result
    }

    /// Deletes an unused firewall alias and leaves the change pending apply.
    func deleteAlias(name: String) async throws -> JSONDict {
        try requireAdministration()
        guard !name.isEmpty else { throw RPCError.malformed("Alias deletion requires a name.") }
        let dict = try await rpc.runObjectOnce(PHPSnippet.deleteAlias(name: name))
        let result = try Self.validatedPendingWriteResponse(dict, operation: "Alias deletion")
        guard result.string("name") == name else {
            throw RPCError.fault(0, "Alias deletion returned a different alias name.")
        }
        return result
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
        enum Kind: Sendable, Equatable {
            case rule
            case separator
        }

        let kind: Kind
        let originalIndex: Int
        let tracker: String
        let interfaceName: String
        let destinationKind: String
        let destinationAddress: String
        let destinationPort: String
        let target: String
        let localPort: String
        let separatorKey: String

        init(originalIndex: Int, forward: PortForward) {
            kind = .rule
            self.originalIndex = originalIndex
            tracker = forward.tracker
            interfaceName = forward.interfaceName
            destinationKind = forward.destinationSide.storageKind.rawValue
            destinationAddress = forward.destinationSide.address
            destinationPort = forward.destinationSide.port ?? ""
            target = forward.target
            localPort = forward.localPort ?? ""
            separatorKey = ""
        }

        init(separator: RuleSeparator) {
            kind = .separator
            originalIndex = -1
            tracker = ""
            interfaceName = ""
            destinationKind = ""
            destinationAddress = ""
            destinationPort = ""
            target = ""
            localPort = ""
            separatorKey = separator.key
        }

        var json: JSONValue {
            switch kind {
            case .rule:
                return .object([
                    "kind": .string("rule"),
                    "original_index": .number(Double(originalIndex)),
                    "tracker": .string(tracker),
                    "interface": .string(interfaceName),
                    "destination_kind": .string(destinationKind),
                    "destination_address": .string(destinationAddress),
                    "destination_port": .string(destinationPort),
                    "target": .string(target),
                    "local_port": .string(localPort)
                ])
            case .separator:
                return .object([
                    "kind": .string("separator"),
                    "id": .string(separatorKey)
                ])
            }
        }

        var identityToken: String {
            switch kind {
            case .rule:
                return "rule:" + [tracker, interfaceName, destinationKind, destinationAddress,
                                  destinationPort, target, localPort].joined(separator: "\u{1f}")
            case .separator:
                return "separator:\(separatorKey)"
            }
        }

        func matches(_ forward: PortForward, at index: Int) -> Bool {
            kind == .rule
                && originalIndex == index
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
}
