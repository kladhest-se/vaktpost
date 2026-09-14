import Foundation

/// Every `validate(_:)` case, split out of `WriteCoordinator.swift` on size
/// alone. Nothing here changed behaviour; each was `private static func` and
/// is now `static func` only so the dispatcher in the other file can still
/// call it.
extension WriteCoordinator {
    static func validateRestartService(name: String) throws {
        guard !name.isEmpty else { throw WriteCoordinatorError.invalidOperation("service name is empty") }
    }

    static func validateQuickBlock(interface: String, address: String) throws {
        guard !interface.isEmpty else {
            throw WriteCoordinatorError.invalidOperation("an internal interface is required")
        }
        if let problem = FieldValidator.quickBlockProblem(in: address) {
            throw WriteCoordinatorError.invalidOperation(problem.message)
        }
    }

    static func validateTrackerRequired(_ tracker: String) throws {
        guard !tracker.isEmpty else { throw WriteCoordinatorError.invalidOperation("a stable tracker ID is required") }
    }

    static func validateSaveRule(_ rule: JSONDict) throws {
        // A create has no tracker yet — the firewall assigns one, because
        // it is the only place that can see the whole ruleset at the
        // moment of writing. An edit without one would silently append a
        // second copy instead of changing the rule, so the requirement
        // stays everywhere else.
        let isCreate = rule.bool("create") ?? false
        guard isCreate || !(rule.string("tracker") ?? "").isEmpty else {
            throw WriteCoordinatorError.invalidOperation("a stable tracker ID is required for an edit")
        }
        let placement = rule.string("placement") ?? (isCreate ? "last" : "keep")
        guard ["keep", "last", "before"].contains(placement) else {
            throw WriteCoordinatorError.invalidOperation("the requested rule position is invalid")
        }
        if placement == "before" {
            let anchor = rule.string("before_tracker") ?? ""
            guard !anchor.isEmpty, anchor != rule.string("tracker") else {
                throw WriteCoordinatorError.invalidOperation("a different stable rule is required as the position anchor")
            }
        }
    }

    static func validateSaveNatRule(_ rule: JSONDict) throws {
        let isCreate = rule.bool("create") ?? false
        let hasTracker = !(rule.string("tracker") ?? "").isEmpty
        // Real pfSense NAT rules carry no tracker at all -- pfSense
        // assigns one to filter rules and never to NAT rules -- so an
        // edit of a forward nobody has saved through this app yet
        // legitimately has none. What it must have instead is the
        // forward's own identity as fetched, which the save snippet
        // matches on when no tracker is present. Requiring only that
        // they are non-empty here; whether they actually match a
        // forward still on the firewall is what `snapshotBefore` and
        // the write itself go on to check.
        let hasLegacyIdentity = !(rule.string("original_interface") ?? "").isEmpty
            && !(rule.string("original_target") ?? "").isEmpty
        guard isCreate || hasTracker || hasLegacyIdentity else {
            throw WriteCoordinatorError.invalidOperation(
                "a stable tracker ID or the forward's original identity is required for an edit")
        }
    }

    static func validateSaveFilterSeparator(_ separator: JSONDict) throws {
        let isCreate = separator.bool("create") ?? false
        let interface = separator.string("interface") ?? ""
        let key = separator.string("key") ?? ""
        let text = separator.string("text")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let color = separator.string("color") ?? ""
        let position = separator.int("position") ?? -1
        guard !interface.isEmpty else {
            throw WriteCoordinatorError.invalidOperation("a separator interface is required")
        }
        guard (isCreate && key.isEmpty) || (!isCreate && !key.isEmpty) else {
            throw WriteCoordinatorError.invalidOperation("the separator key does not match create/edit mode")
        }
        guard !text.isEmpty else {
            throw WriteCoordinatorError.invalidOperation("separator text is required")
        }
        guard ["info", "success", "warning", "danger"].contains(color) else {
            throw WriteCoordinatorError.invalidOperation("the separator color is invalid")
        }
        guard position >= 0 else {
            throw WriteCoordinatorError.invalidOperation("the separator position is invalid")
        }
    }

    static func validateDeleteFilterSeparator(interface: String, key: String) throws {
        guard !interface.isEmpty, !key.isEmpty else {
            throw WriteCoordinatorError.invalidOperation("a separator interface and key are required")
        }
    }

    static func validateSaveNatSeparator(_ separator: JSONDict) throws {
        let isCreate = separator.bool("create") ?? false
        let key = separator.string("key") ?? ""
        let text = separator.string("text")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let color = separator.string("color") ?? ""
        let position = separator.int("position") ?? -1
        guard (isCreate && key.isEmpty) || (!isCreate && !key.isEmpty) else {
            throw WriteCoordinatorError.invalidOperation(
                "the NAT separator key does not match create/edit mode")
        }
        guard !text.isEmpty else {
            throw WriteCoordinatorError.invalidOperation("NAT separator text is required")
        }
        guard ["info", "success", "warning", "danger"].contains(color), position >= 0 else {
            throw WriteCoordinatorError.invalidOperation(
                "the NAT separator color or position is invalid")
        }
    }

    static func validateDeleteNatSeparator(key: String) throws {
        guard !key.isEmpty else {
            throw WriteCoordinatorError.invalidOperation("a NAT separator key is required")
        }
    }

    static func validateSaveAlias(_ alias: JSONDict) throws {
        let isCreate = alias.bool("create") ?? false
        let name = alias.string("name") ?? ""
        let originalName = alias.string("original_name") ?? ""
        let type = alias.string("type") ?? ""
        let members = alias.list("members").compactMap(\.stringValue)
        let details = alias.list("details")
        guard FieldValidator.isAliasName(name) else {
            throw WriteCoordinatorError.invalidOperation("the alias name is invalid")
        }
        guard (isCreate && originalName.isEmpty) || (!isCreate && originalName == name) else {
            throw WriteCoordinatorError.invalidOperation(
                "existing alias names must remain unchanged so rule references stay valid")
        }
        guard ["host", "network", "port"].contains(type) else {
            throw WriteCoordinatorError.invalidOperation(
                "only host, network, and port aliases can be edited")
        }
        guard !members.isEmpty, members.count == alias.list("members").count,
              members.count == details.count,
              members.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw WriteCoordinatorError.invalidOperation(
                "at least one non-empty member and one matching description slot are required")
        }
        guard !members.contains(name) else {
            throw WriteCoordinatorError.invalidOperation("an alias cannot include itself")
        }
    }

    static func validateDeleteAlias(name: String) throws {
        guard FieldValidator.isAliasName(name) else {
            throw WriteCoordinatorError.invalidOperation("the alias name is invalid")
        }
    }

    static func validateReorderFilterRules(interface: String, items: [FirewallClient.ReorderItem]) throws {
        guard !interface.isEmpty else {
            throw WriteCoordinatorError.invalidOperation("an interface is required")
        }
        guard !items.isEmpty else {
            throw WriteCoordinatorError.invalidOperation("a non-empty order is required")
        }
        // Every id present once. The snippet re-validates this itself
        // against the firewall's own current state — this is the same
        // check done early, against what the app already has, so an
        // obviously malformed drag is refused before a round trip rather
        // than after one.
        var seen = Set<String>()
        for item in items {
            let id: String
            switch item {
            case .rule(let tracker): id = "rule:\(tracker)"
            case .separator(let key): id = "separator:\(key)"
            }
            guard seen.insert(id).inserted else {
                throw WriteCoordinatorError.invalidOperation("the order contains a duplicate")
            }
        }
    }

    static func validateReorderNatRules(items: [FirewallClient.NatReorderItem]) throws {
        guard !items.isEmpty else {
            throw WriteCoordinatorError.invalidOperation("a non-empty NAT order is required")
        }
        let rules = items.filter { $0.kind == .rule }
        let separators = items.filter { $0.kind == .separator }
        let positions = Set(rules.map(\.originalIndex))
        let separatorKeys = Set(separators.map(\.separatorKey))
        guard positions.count == rules.count,
              positions.allSatisfy({ $0 >= 0 }) else {
            throw WriteCoordinatorError.invalidOperation(
                "the NAT order contains a duplicate or invalid original position")
        }
        guard separatorKeys.count == separators.count,
              separatorKeys.allSatisfy({ !$0.isEmpty }) else {
            throw WriteCoordinatorError.invalidOperation(
                "the NAT order contains a duplicate or invalid separator")
        }
    }
}
