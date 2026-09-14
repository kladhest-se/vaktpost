import Foundation

/// The audit path — `snapshotBefore(_:)`, `verify(_:receipt:)`, and every
/// case and shared snapshot/matching helper either uses — split out of
/// `WriteCoordinator.swift` on size alone. Nothing here changed behaviour;
/// declarations `execute` still calls directly (`snapshotBefore`, `verify`,
/// `Receipt`, `Verification`) are now `internal` rather than `private` so
/// the other file can still reach them. Everything used only within this
/// file stays `private` to it.
extension WriteCoordinator {
    // MARK: Precondition snapshots and read-back

    func snapshotBefore(_ operation: AdministrativeWrite) async throws -> String? {
        switch operation {
        case .reloadFirewall:
            return try await snapshotReloadFirewall()
        case .quickBlock(let interface, _, _):
            return try await snapshotQuickBlock(interface: interface)
        case .restartService(let name, _):
            return try await snapshotRestartService(name: name)
        case .startFirmwareUpdate(let current, let target):
            return try await snapshotFirmwareUpdate(current: current, target: target)
        case .startPackageUpdate(let identifier, _, let installed, let target):
            return try await snapshotPackageUpdate(
                identifier: identifier, installed: installed, target: target)
        case .flushStates:
            return try await snapshotFlushStates()
        case .deleteRule:
            return try await snapshotDeleteRule(operation)
        case .saveRule(let expected, _):
            return try await snapshotSaveRule(expected)
        case .saveNatRule(let rule, _) where rule.bool("create") == true:
            return try await snapshotSaveNatRuleCreate()
        case .deleteNatRule:
            return try await snapshotDeleteNatRule(operation)
        case .saveNatRule(let rule, _):
            return try await snapshotSaveNatRule(rule)
        case .saveFilterSeparator(let expected, _):
            return try await snapshotSaveFilterSeparator(expected)
        case .deleteFilterSeparator(let interface, let key, _):
            return try await snapshotDeleteFilterSeparator(interface: interface, key: key)
        case .saveNatSeparator(let expected, _):
            return try await snapshotSaveNatSeparator(expected)
        case .deleteNatSeparator(let key, _):
            return try await snapshotDeleteNatSeparator(key: key)
        case .saveAlias(let expected, _):
            return try await snapshotSaveAlias(expected)
        case .deleteAlias(let name, _):
            return try await snapshotDeleteAlias(name: name)
        case .reorderFilterRules(let interface, let items, _):
            return try await snapshotReorderFilterRules(interface: interface, items: items)
        case .reorderNatRules(let items, _):
            return try await snapshotReorderNatRules(items: items)
        }
    }

    private func snapshotReloadFirewall() async throws -> String? {
        "rules=\((try await client.firewallRules()).count)"
    }

    private func snapshotQuickBlock(interface: String) async throws -> String? {
        let interfaces = try await client.interfaces()
        guard interfaces.contains(where: { $0.internalName == interface }) else {
            throw WriteCoordinatorError.invalidOperation(
                "the selected interface is no longer configured"
            )
        }
        return "rules=\((try await client.firewallRules()).count);interface=\(interface)"
    }

    private func snapshotRestartService(name: String) async throws -> String? {
        guard let service = try await client.services().first(where: { $0.name == name }) else {
            throw WriteCoordinatorError.invalidOperation("the service is no longer present")
        }
        return Self.serviceSnapshot(service)
    }

    private func snapshotFirmwareUpdate(current: String, target: String) async throws -> String? {
        try await requireNoUpdateInProgress()
        let version = try await client.systemVersion()
        guard version.updateAvailable == true,
              version.current == current,
              version.latest == target else {
            throw WriteCoordinatorError.invalidOperation(
                "the available pfSense update changed; check for updates again")
        }
        return "firmware=\(current);target=\(target);updater=idle"
    }

    private func snapshotPackageUpdate(identifier: String, installed: String,
                                       target: String) async throws -> String? {
        try await requireNoUpdateInProgress()
        guard let packages = try await client.packageUpdates(),
              let package = packages.first(where: { $0.updateIdentifier == identifier }),
              package.updateAvailable,
              package.installedVersion == installed,
              package.latestVersion == target else {
            throw WriteCoordinatorError.invalidOperation(
                "the available package update changed; check the repository again")
        }
        return "package=\(identifier);installed=\(installed);target=\(target);updater=idle"
    }

    private func requireNoUpdateInProgress() async throws {
        let status = try await client.updateProcessStatus()
        guard status.bool("running") != true else {
            throw WriteCoordinatorError.invalidOperation(
                "another pfSense firmware or package update is already running")
        }
    }

    private func snapshotFlushStates() async throws -> String? {
        Self.stateSnapshot(try await client.stateTableSize())
    }

    private func snapshotDeleteRule(_ operation: AdministrativeWrite) async throws -> String? {
        guard let tracker = operation.tracker else {
            throw WriteCoordinatorError.invalidOperation("a stable rule tracker is required")
        }
        guard let rule = try await client.firewallRules().first(where: { $0.tracker == tracker }) else {
            throw WriteCoordinatorError.invalidOperation("the rule is no longer present")
        }
        return Self.ruleSnapshot(rule)
    }

    private func snapshotSaveRule(_ expected: JSONDict) async throws -> String? {
        let rules = try await client.firewallRules()
        try Self.requirePlacementAnchor(expected, in: rules)
        if expected.bool("create") == true {
            return "rules=\(rules.count);new_tracker=unassigned;"
                + Self.requestedPlacementSnapshot(expected)
        }
        guard let tracker = expected.string("tracker"),
              let rule = rules.first(where: { $0.tracker == tracker }) else {
            throw WriteCoordinatorError.invalidOperation("the rule is no longer present")
        }
        let placement = expected.string("placement") ?? "keep"
        if placement == "keep", rule.interfaceName != expected.string("interface") {
            throw WriteCoordinatorError.invalidOperation(
                "a position on the new interface must be selected"
            )
        }
        let position = Self.interfacePosition(of: tracker, interface: rule.interfaceName, in: rules) ?? -1
        return Self.ruleSnapshot(rule) + ";position=\(position);"
            + Self.requestedPlacementSnapshot(expected)
    }

    private func snapshotSaveNatRuleCreate() async throws -> String? {
        "port_forwards=\((try await client.portForwards()).count);new_tracker=unassigned"
    }

    private func snapshotDeleteNatRule(_ operation: AdministrativeWrite) async throws -> String? {
        // Unchanged, and still narrower than it should be: deleting a
        // legacy forward -- one with no tracker, saved by the web GUI or
        // by a build of this app before it wrote trackers onto NAT rules
        // -- fails here exactly as saving one used to, for the same
        // reason. Editing a legacy forward heals it going forward (see
        // `saveNatRule` below), so the practical way through this today
        // is to open the forward, save it once with no other change to
        // adopt a tracker, then delete it. Fixing this properly needs the
        // same before/after identity split `saveNatRule` now has, and
        // that is real, separate work rather than a one-line fix here.
        guard let tracker = operation.tracker else {
            throw WriteCoordinatorError.invalidOperation("a stable port-forward tracker is required")
        }
        guard let forward = try await client.portForwards().first(where: { $0.tracker == tracker }) else {
            throw WriteCoordinatorError.invalidOperation("the port forward is no longer present")
        }
        return Self.natSnapshot(forward)
    }

    private func snapshotSaveNatRule(_ rule: JSONDict) async throws -> String? {
        if let tracker = rule.string("tracker"), !tracker.isEmpty {
            guard let forward = try await client.portForwards().first(where: { $0.tracker == tracker }) else {
                throw WriteCoordinatorError.invalidOperation("the port forward is no longer present")
            }
            return Self.natSnapshot(forward)
        }
        // No tracker: this is a legacy forward, identified by the
        // original fields `save(changes:)` captured before any edits in
        // this payload -- the same ones the save snippet's fallback
        // matches on. Checked here too, ahead of the write, so a
        // vanished or already-edited-elsewhere forward is rejected with
        // "no longer present" rather than reaching the firewall to find
        // out.
        guard let forward = Self.legacyNatMatch(rule, in: try await client.portForwards()) else {
            throw WriteCoordinatorError.invalidOperation(
                "the port forward is no longer present, or has changed since it was fetched")
        }
        return Self.natSnapshot(forward)
    }

    private func snapshotSaveFilterSeparator(_ expected: JSONDict) async throws -> String? {
        let interface = expected.string("interface") ?? ""
        let position = expected.int("position") ?? -1
        let rules = try await client.firewallRules()
        let ruleCount = rules.filter { $0.interfaceName == interface }.count
        guard position <= ruleCount else {
            throw WriteCoordinatorError.invalidOperation(
                "the selected separator position is no longer available")
        }
        let separatorPayload = try await client.ruleSeparators()
        let separators = separatorPayload.filter
        if expected.bool("create") == true {
            return "separators=\(separators.filter { $0.interfaceName == interface }.count);new_key=unassigned"
        }
        let key = expected.string("key") ?? ""
        guard let separator = separators.first(where: {
            $0.interfaceName == interface && $0.key == key
        }) else {
            throw WriteCoordinatorError.invalidOperation("the separator is no longer present")
        }
        return Self.separatorSnapshot(separator)
    }

    private func snapshotDeleteFilterSeparator(interface: String, key: String) async throws -> String? {
        let separatorPayload = try await client.ruleSeparators()
        let separators = separatorPayload.filter
        guard let separator = separators.first(where: {
            $0.interfaceName == interface && $0.key == key
        }) else {
            throw WriteCoordinatorError.invalidOperation("the separator is no longer present")
        }
        return Self.separatorSnapshot(separator)
    }

    private func snapshotSaveNatSeparator(_ expected: JSONDict) async throws -> String? {
        let position = expected.int("position") ?? -1
        let forwards = try await client.portForwards()
        guard position <= forwards.count else {
            throw WriteCoordinatorError.invalidOperation(
                "the selected NAT separator position is no longer available")
        }
        let separatorPayload = try await client.ruleSeparators()
        let separators = separatorPayload.nat
        if expected.bool("create") == true {
            return "nat_separators=\(separators.count);new_key=unassigned"
        }
        let key = expected.string("key") ?? ""
        guard let separator = separators.first(where: { $0.key == key }) else {
            throw WriteCoordinatorError.invalidOperation("the NAT separator is no longer present")
        }
        return Self.separatorSnapshot(separator)
    }

    private func snapshotDeleteNatSeparator(key: String) async throws -> String? {
        let separatorPayload = try await client.ruleSeparators()
        let separators = separatorPayload.nat
        guard let separator = separators.first(where: { $0.key == key }) else {
            throw WriteCoordinatorError.invalidOperation("the NAT separator is no longer present")
        }
        return Self.separatorSnapshot(separator)
    }

    private func snapshotSaveAlias(_ expected: JSONDict) async throws -> String? {
        let aliases = try await client.firewallAliases()
        let name = expected.string("name") ?? ""
        if expected.bool("create") == true {
            guard !aliases.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw WriteCoordinatorError.invalidOperation("an alias with this name already exists")
            }
            return "aliases=\(aliases.count);new_name=\(name)"
        }
        guard let alias = aliases.first(where: { $0.name == name }) else {
            throw WriteCoordinatorError.invalidOperation("the alias is no longer present")
        }
        guard alias.type.lowercased() == expected.string("type")?.lowercased() else {
            throw WriteCoordinatorError.invalidOperation(
                "an existing alias type must remain unchanged so rule references stay valid")
        }
        return Self.aliasSnapshot(alias)
    }

    private func snapshotDeleteAlias(name: String) async throws -> String? {
        guard let alias = try await client.firewallAliases().first(where: { $0.name == name }) else {
            throw WriteCoordinatorError.invalidOperation("the alias is no longer present")
        }
        return Self.aliasSnapshot(alias)
    }

    private func snapshotReorderFilterRules(interface: String, items: [FirewallClient.ReorderItem]) async throws -> String? {
        // Validated early, against a fresh read, so a drag made against
        // data that has since changed on the firewall is refused with a
        // clear reason rather than reaching the write and failing there.
        let rules = try await client.firewallRules()
        let separators = try await client.ruleSeparators()
        let currentTokens = Self.reorderTokens(for: interface, in: rules,
                                               separators: separators.filter)
        let requestedTokens = items.map(\.token)
        guard Set(currentTokens) == Set(requestedTokens), currentTokens.count == requestedTokens.count else {
            throw WriteCoordinatorError.invalidOperation(
                "the rules or separators on this interface changed since they were fetched")
        }
        return "order=" + currentTokens.joined(separator: ",")
    }

    private func snapshotReorderNatRules(items: [FirewallClient.NatReorderItem]) async throws -> String? {
        // The original array index is safe only when it still identifies
        // the same forward. Check every submitted item against a fresh
        // read before the PHP snippet repeats the same validation against
        // the configuration it is about to write.
        let forwards = try await client.portForwards()
        let separatorPayload = try await client.ruleSeparators()
        let currentItems = Self.natReorderItems(
            forwards: forwards, separators: separatorPayload.nat)
        let submittedRules = items.filter { $0.kind == .rule }
        guard submittedRules.count == forwards.count,
              submittedRules.allSatisfy({ item in
                  forwards.indices.contains(item.originalIndex)
                    && item.matches(forwards[item.originalIndex], at: item.originalIndex)
              }),
              Set(currentItems.map(\.identityToken)) == Set(items.map(\.identityToken)),
              currentItems.count == items.count else {
            throw WriteCoordinatorError.invalidOperation(
                "the NAT rules or separators changed since they were fetched")
        }
        return "order=" + currentItems.map(\.identityToken).joined(separator: ",")
    }

    struct Verification {
        let state: AuditVerification
        let detail: String
        let snapshot: String?
    }

    func verify(_ operation: AdministrativeWrite, receipt: Receipt) async throws -> Verification {
        switch operation {
        case .reloadFirewall:
            return try await verifyReloadFirewall()
        case .restartService(let name, _):
            return try await verifyRestartService(name: name)
        case .startFirmwareUpdate:
            return verifyUpdateAccepted(receipt: receipt)
        case .startPackageUpdate(let identifier, _, _, _):
            return verifyUpdateAccepted(receipt: receipt, identifier: identifier)
        case .quickBlock(let interface, let address, let description):
            return try await verifyQuickBlock(interface: interface, address: address,
                                              description: description, receipt: receipt)
        case .flushStates:
            return try await verifyFlushStates()
        case .deleteRule(let tracker, _):
            return try await verifyDeleteRule(tracker: tracker)
        case .reorderFilterRules(let interface, let items, _):
            return try await verifyReorderFilterRules(interface: interface, items: items)
        case .reorderNatRules(let items, _):
            return try await verifyReorderNatRules(items: items)
        case .saveRule(let expected, _):
            return try await verifySaveRule(expected, receipt: receipt)
        case .deleteNatRule(let tracker, _):
            return try await verifyDeleteNatRule(tracker: tracker)
        case .saveNatRule(let expected, _):
            return try await verifySaveNatRule(expected, receipt: receipt)
        case .saveFilterSeparator(let expected, _):
            return try await verifySaveFilterSeparator(expected, receipt: receipt)
        case .deleteFilterSeparator(let interface, let key, _):
            return try await verifyDeleteFilterSeparator(interface: interface, key: key)
        case .saveNatSeparator(let expected, _):
            return try await verifySaveNatSeparator(expected, receipt: receipt)
        case .deleteNatSeparator(let key, _):
            return try await verifyDeleteNatSeparator(key: key)
        case .saveAlias(let expected, _):
            return try await verifySaveAlias(expected, receipt: receipt)
        case .deleteAlias(let name, _):
            return try await verifyDeleteAlias(name: name)
        }
    }

    private func verifyReloadFirewall() async throws -> Verification {
        let rules = try await client.firewallRules()
        return Verification(state: .readBack,
                            detail: "Ruleset is readable after reload (\(rules.count) rules).",
                            snapshot: "rules=\(rules.count)")
    }

    private func verifyRestartService(name: String) async throws -> Verification {
        guard let service = try await client.services().first(where: { $0.name == name }) else {
            return Verification(state: .mismatch,
                                detail: "The service disappeared during read-back.", snapshot: nil)
        }
        let snapshot = Self.serviceSnapshot(service)
        return Verification(
            state: service.running ? .verified : .mismatch,
            detail: service.running ? "Service reports running after restart." : "Service does not report running after restart.",
            snapshot: snapshot
        )
    }

    private func verifyUpdateAccepted(receipt: Receipt,
                                      identifier: String? = nil) -> Verification {
        let phase = receipt.updatePhase ?? "accepted"
        let target = identifier ?? "pfSense base system"
        let detail: String
        let state: AuditVerification
        switch phase {
        case "completed":
            detail = "The pfSense updater completed successfully for \(target)."
            state = .verified
        case "running":
            detail = "The pfSense updater is running for \(target)."
            state = .verified
        default:
            detail = "pfSense accepted the updater process for \(target); refresh to verify completion."
            state = .readBack
        }
        return Verification(
            state: state,
            detail: detail,
            snapshot: "phase=\(phase);target=\(target)"
        )
    }

    private func verifyQuickBlock(interface: String, address: String, description: String,
                                  receipt: Receipt) async throws -> Verification {
        let rules = try await client.firewallRules()
        let found = rules.first { rule in
            if let tracker = receipt.tracker, !tracker.isEmpty { return rule.tracker == tracker }
            return rule.interfaceName == interface && rule.sourceSide.address == address
                && rule.type == "block" && rule.descr == description
        }
        guard let found else {
            return Verification(state: .mismatch,
                                detail: "The new block rule was not found during read-back.", snapshot: nil)
        }
        return Verification(state: .verified,
                            detail: "The block rule was found during read-back.",
                            snapshot: Self.ruleSnapshot(found))
    }

    private func verifyFlushStates() async throws -> Verification {
        let state = try await client.stateTableSize()
        return Verification(state: .readBack,
                            detail: "State table is readable after the flush (\(state.current ?? 0) active states).",
                            snapshot: Self.stateSnapshot(state))
    }

    private func verifyDeleteRule(tracker: String) async throws -> Verification {
        let exists = try await client.firewallRules().contains { $0.tracker == tracker }
        return Verification(state: exists ? .mismatch : .verified,
                            detail: exists ? "The deleted rule is still present." : "The rule is absent during read-back.",
                            snapshot: exists ? "tracker=\(tracker);present=true" : "tracker=\(tracker);present=false")
    }

    private func verifyReorderFilterRules(interface: String, items: [FirewallClient.ReorderItem]) async throws -> Verification {
        let rules = try await client.firewallRules()
        let separators = try await client.ruleSeparators()
        let actualTokens = Self.reorderTokens(for: interface, in: rules,
                                              separators: separators.filter)
        let requestedTokens = items.map(\.token)
        let matches = actualTokens == requestedTokens
        return Verification(
            state: matches ? .verified : .mismatch,
            detail: matches
                ? "The interface now reads back in the requested order."
                : "The interface's order after saving does not match what was requested.",
            snapshot: "order=" + actualTokens.joined(separator: ",")
        )
    }

    private func verifyReorderNatRules(items: [FirewallClient.NatReorderItem]) async throws -> Verification {
        let forwards = try await client.portForwards()
        let separatorPayload = try await client.ruleSeparators()
        let actualTokens = Self.natReorderItems(
            forwards: forwards, separators: separatorPayload.nat
        ).map(\.identityToken)
        let requestedTokens = items.map(\.identityToken)
        let matches = actualTokens == requestedTokens
        return Verification(
            state: matches ? .verified : .mismatch,
            detail: matches
                ? "The NAT rules and separators now read back in the requested order."
                : "The NAT rule or separator order after saving does not match what was requested.",
            snapshot: "order=" + actualTokens.joined(separator: ",")
        )
    }

    private func verifySaveRule(_ expected: JSONDict, receipt: Receipt) async throws -> Verification {
        let isCreate = expected.bool("create") ?? false
        let rules = try await client.firewallRules()
        guard let tracker = receipt.tracker, !tracker.isEmpty,
              let actual = rules.first(where: { $0.tracker == tracker }) else {
            return Verification(state: .mismatch,
                                detail: "The \(isCreate ? "new" : "edited") rule was not found during read-back.", snapshot: nil)
        }
        let valuesMatch = Self.rule(actual, matches: expected)
        let placementMatches = Self.rulePlacement(tracker: tracker, matches: expected, in: rules)
        let matches = valuesMatch && placementMatches
        let detail = matches
            ? "The \(isCreate ? "new" : "edited") rule matches the requested values."
            : (valuesMatch
               ? "The rule values match, but its position is different after saving."
               : "The rule returned different values after saving.")
        return Verification(state: matches ? .verified : .mismatch,
                            detail: detail,
                            snapshot: Self.ruleSnapshot(actual))
    }

    private func verifyDeleteNatRule(tracker: String) async throws -> Verification {
        let exists = try await client.portForwards().contains { $0.tracker == tracker }
        return Verification(state: exists ? .mismatch : .verified,
                            detail: exists ? "The deleted port forward is still present." : "The port forward is absent during read-back.",
                            snapshot: exists ? "tracker=\(tracker);present=true" : "tracker=\(tracker);present=false")
    }

    private func verifySaveNatRule(_ expected: JSONDict, receipt: Receipt) async throws -> Verification {
        let isCreate = expected.bool("create") ?? false
        guard let tracker = receipt.tracker, !tracker.isEmpty,
              let actual = try await client.portForwards().first(where: { $0.tracker == tracker }) else {
            return Verification(state: .mismatch,
                                detail: "The \(isCreate ? "new" : "edited") port forward was not found during read-back.", snapshot: nil)
        }
        let matches = Self.nat(actual, matches: expected)
        let detail = matches
            ? "The \(isCreate ? "new" : "edited") port forward matches the requested values."
            : "The port forward returned different values after saving."
        return Verification(state: matches ? .verified : .mismatch,
                            detail: detail,
                            snapshot: Self.natSnapshot(actual))
    }

    private func verifySaveFilterSeparator(_ expected: JSONDict, receipt: Receipt) async throws -> Verification {
        let interface = expected.string("interface") ?? ""
        let key = receipt.tracker ?? expected.string("key") ?? ""
        let separators = try await client.ruleSeparators()
        let actual = separators.filter.first {
            $0.interfaceName == interface && $0.key == key
        }
        guard let actual else {
            return Verification(state: .mismatch,
                                detail: "The separator was not found during read-back.",
                                snapshot: nil)
        }
        let matches = actual.text == (expected.string("text") ?? "")
            && actual.colorName == (expected.string("color") ?? "")
            && actual.precedingRuleCount == expected.int("position")
        return Verification(
            state: matches ? .verified : .mismatch,
            detail: matches
                ? "The separator matches the requested text, color, and position."
                : "The separator returned different values after saving.",
            snapshot: Self.separatorSnapshot(actual)
        )
    }

    private func verifyDeleteFilterSeparator(interface: String, key: String) async throws -> Verification {
        let separators = try await client.ruleSeparators()
        let exists = separators.filter.contains {
            $0.interfaceName == interface && $0.key == key
        }
        return Verification(
            state: exists ? .mismatch : .verified,
            detail: exists ? "The deleted separator is still present." : "The separator is absent during read-back.",
            snapshot: exists ? "interface=\(interface);key=\(key);present=true" : "interface=\(interface);key=\(key);present=false"
        )
    }

    private func verifySaveNatSeparator(_ expected: JSONDict, receipt: Receipt) async throws -> Verification {
        let key = receipt.tracker ?? expected.string("key") ?? ""
        let separators = try await client.ruleSeparators()
        let actual = separators.nat.first { $0.key == key }
        guard let actual else {
            return Verification(state: .mismatch,
                                detail: "The NAT separator was not found during read-back.",
                                snapshot: nil)
        }
        let matches = actual.text == (expected.string("text") ?? "")
            && actual.colorName == (expected.string("color") ?? "")
            && actual.precedingRuleCount == expected.int("position")
        return Verification(
            state: matches ? .verified : .mismatch,
            detail: matches
                ? "The NAT separator matches the requested text, color, and position."
                : "The NAT separator returned different values after saving.",
            snapshot: Self.separatorSnapshot(actual)
        )
    }

    private func verifyDeleteNatSeparator(key: String) async throws -> Verification {
        let separators = try await client.ruleSeparators()
        let exists = separators.nat.contains { $0.key == key }
        return Verification(
            state: exists ? .mismatch : .verified,
            detail: exists
                ? "The deleted NAT separator is still present."
                : "The NAT separator is absent during read-back.",
            snapshot: "key=\(key);present=\(exists)"
        )
    }

    private func verifySaveAlias(_ expected: JSONDict, receipt: Receipt) async throws -> Verification {
        let isCreate = expected.bool("create") ?? false
        let name = receipt.tracker ?? expected.string("name") ?? ""
        guard let actual = try await client.firewallAliases().first(where: { $0.name == name }) else {
            return Verification(
                state: .mismatch,
                detail: "The \(isCreate ? "new" : "edited") alias was not found during read-back.",
                snapshot: nil
            )
        }
        let expectedMembers = expected.list("members").compactMap(\.stringValue)
        let expectedDetails = expected.list("details").compactMap(\.stringValue)
        let matches = actual.name == name
            && actual.type == expected.string("type")
            && (actual.descr ?? "") == (expected.string("descr") ?? "")
            && actual.addresses == expectedMembers
            && actual.details == expectedDetails
        return Verification(
            state: matches ? .verified : .mismatch,
            detail: matches
                ? "The \(isCreate ? "new" : "edited") alias matches the requested values."
                : "The alias returned different values after saving.",
            snapshot: Self.aliasSnapshot(actual)
        )
    }

    private func verifyDeleteAlias(name: String) async throws -> Verification {
        let exists = try await client.firewallAliases().contains { $0.name == name }
        return Verification(
            state: exists ? .mismatch : .verified,
            detail: exists ? "The deleted alias is still present." : "The alias is absent during read-back.",
            snapshot: "name=\(name);present=\(exists)"
        )
    }

    private static func reorderTokens(for interface: String,
                                      in rules: [FirewallRule],
                                      separators: [RuleSeparator]) -> [String] {
        let ownRules = rules.filter { $0.interfaceName == interface }
        let ownSeparators = separators.filter { $0.interfaceName == interface }

        var tokens: [String] = []
        for (index, rule) in ownRules.enumerated() {
            for separator in ownSeparators where separator.precedingRuleCount == index {
                tokens.append("separator:\(separator.key)")
            }
            tokens.append("rule:\(rule.tracker)")
        }
        for separator in ownSeparators
        where (separator.precedingRuleCount ?? Int.max) >= ownRules.count {
            tokens.append("separator:\(separator.key)")
        }
        return tokens
    }

    /// The complete mixed NAT order using the same preceding-forward count
    /// semantics as pfSense and `mergedNatList` in the view.
    private static func natReorderItems(
        forwards: [PortForward], separators: [RuleSeparator]
    ) -> [FirewallClient.NatReorderItem] {
        var items: [FirewallClient.NatReorderItem] = []
        for (index, forward) in forwards.enumerated() {
            for separator in separators where separator.precedingRuleCount == index {
                items.append(FirewallClient.NatReorderItem(separator: separator))
            }
            items.append(FirewallClient.NatReorderItem(originalIndex: index, forward: forward))
        }
        for separator in separators
        where (separator.precedingRuleCount ?? Int.max) >= forwards.count {
            items.append(FirewallClient.NatReorderItem(separator: separator))
        }
        return items
    }

    private static func ruleSnapshot(_ rule: FirewallRule) -> String {
        [rule.tracker, rule.interfaceName, rule.type, rule.ipProtocol ?? "", rule.proto ?? "",
         rule.sourceSide.storageKind.rawValue, rule.source,
         rule.destinationSide.storageKind.rawValue, rule.destination,
         rule.descr, String(rule.disabled), String(rule.logged)]
            .joined(separator: "|")
    }

    private static func natSnapshot(_ forward: PortForward) -> String {
        [forward.tracker, forward.interfaceName, forward.ipProtocol ?? "", forward.proto ?? "",
         forward.sourceSide.storageKind.rawValue, forward.sourceSide.text,
         forward.destinationSide.storageKind.rawValue, forward.destinationSide.text, forward.target,
         forward.localPort ?? "", forward.descr, String(forward.disabled)]
            .joined(separator: "|")
    }

    private static func separatorSnapshot(_ separator: RuleSeparator) -> String {
        [separator.interfaceName ?? "", separator.key, separator.text,
         separator.colorName, String(separator.precedingRuleCount ?? -1)]
            .joined(separator: "|")
    }

    private static func aliasSnapshot(_ alias: FirewallAliasEntry) -> String {
        [alias.name, alias.type, alias.descr ?? "",
         alias.addresses.joined(separator: " "),
         alias.details.joined(separator: "||")]
            .joined(separator: "|")
    }

    /// Finds the forward a legacy (trackerless) payload is editing, by the
    /// identity `save(changes:)` captured before its edits were applied.
    ///
    /// Only ever matches a forward that itself has no tracker. Two things
    /// this guards against: mistaking an already-adopted forward for one that
    /// still needs adopting, and matching a forward that coincidentally now
    /// shares the old identity of the one being edited -- both of which stay
    /// impossible as long as a tracker, once assigned, is never reused.
    private static func legacyNatMatch(_ rule: JSONDict, in forwards: [PortForward]) -> PortForward? {
        guard let interface = rule.string("original_interface"), !interface.isEmpty else { return nil }
        let destination = FilterAddress(rule.value("original_destination"))
        let port = rule.string("original_destination_port") ?? ""
        let target = rule.string("original_target") ?? ""
        return forwards.first {
            $0.tracker.isEmpty
                && $0.interfaceName == interface
                && $0.destinationSide.storageKind == destination.storageKind
                && $0.destinationSide.address == destination.address
                && ($0.destinationSide.port ?? "") == port
                && $0.target == target
        }
    }

    private static func serviceSnapshot(_ service: ServiceStatus) -> String {
        [service.name, service.status, String(service.enabled ?? false)].joined(separator: "|")
    }

    private static func stateSnapshot(_ state: StateTableSize) -> String {
        "current=\(state.current ?? -1);maximum=\(state.effectiveMaximum ?? -1)"
    }

    private static func rule(_ actual: FirewallRule, matches expected: JSONDict) -> Bool {
        let source = FilterAddress(expected.value("source"), port: expected.value("source_port"))
        let destination = FilterAddress(expected.value("destination"),
                                        port: expected.value("destination_port"))
        return actual.interfaceName == expected.string("interface")
            && actual.type == (expected.string("type") ?? "").lowercased()
            && (actual.ipProtocol ?? "inet") == (expected.string("ipprotocol") ?? "inet")
            && (actual.proto ?? "any") == (expected.string("protocol") ?? "any")
            && actual.sourceSide.address == source.address
            && actual.sourceSide.storageKind == source.storageKind
            && (actual.sourceSide.port ?? "") == (source.port ?? "")
            && actual.destinationSide.address == destination.address
            && actual.destinationSide.storageKind == destination.storageKind
            && (actual.destinationSide.port ?? "") == (destination.port ?? "")
            && actual.descr == (expected.string("descr") ?? "")
            && actual.disabled == (expected.bool("disabled") ?? false)
            && actual.logged == (expected.bool("log") ?? false)
    }

    private static func nat(_ actual: PortForward, matches expected: JSONDict) -> Bool {
        let source = FilterAddress(expected.value("source"), port: expected.value("source_port"))
        let destination = FilterAddress(expected.value("destination"),
                                        port: expected.value("destination_port"))
        return actual.interfaceName == expected.string("interface")
            && (actual.ipProtocol ?? "inet") == (expected.string("ipprotocol") ?? "inet")
            && (actual.proto ?? "any") == (expected.string("protocol") ?? "any")
            && actual.sourceSide.address == source.address
            && actual.sourceSide.storageKind == source.storageKind
            && actual.destinationSide.address == destination.address
            && actual.destinationSide.storageKind == destination.storageKind
            && (actual.destinationSide.port ?? "") == (destination.port ?? "")
            && actual.target == (expected.string("target") ?? "")
            && (actual.localPort ?? "") == (expected.string("local_port") ?? "")
            && actual.descr == (expected.string("descr") ?? "")
            && actual.disabled == (expected.bool("disabled") ?? false)
    }

    private static func requirePlacementAnchor(_ expected: JSONDict,
                                               in rules: [FirewallRule]) throws {
        guard expected.string("placement") == "before" else { return }
        let anchor = expected.string("before_tracker") ?? ""
        let interface = expected.string("interface") ?? ""
        guard rules.contains(where: { $0.tracker == anchor && $0.interfaceName == interface }) else {
            throw WriteCoordinatorError.invalidOperation(
                "the selected position anchor is no longer present on this interface"
            )
        }
    }

    private static func requestedPlacementSnapshot(_ expected: JSONDict) -> String {
        let placement = expected.string("placement") ?? "keep"
        let anchor = expected.string("before_tracker") ?? ""
        return "placement=\(placement);before_tracker=\(anchor)"
    }

    private static func interfacePosition(of tracker: String,
                                          interface: String,
                                          in rules: [FirewallRule]) -> Int? {
        rules.filter { $0.interfaceName == interface }
            .firstIndex { $0.tracker == tracker }
            .map { $0 + 1 }
    }

    private static func rulePlacement(tracker: String,
                                      matches expected: JSONDict,
                                      in rules: [FirewallRule]) -> Bool {
        let interfaceRules = rules.filter { $0.interfaceName == expected.string("interface") }
        guard let index = interfaceRules.firstIndex(where: { $0.tracker == tracker }) else {
            return false
        }
        switch expected.string("placement") {
        case "before":
            guard let anchor = expected.string("before_tracker"),
                  let anchorIndex = interfaceRules.firstIndex(where: { $0.tracker == anchor }) else {
                return false
            }
            return index + 1 == anchorIndex
        case "last":
            return index == interfaceRules.count - 1
        default:
            return true
        }
    }
}
