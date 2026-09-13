import Foundation
import Observation

/// The complete set of mutations Vaktpost permits.
///
/// Views may describe one of these operations, but only `WriteCoordinator`
/// executes it. Keeping the payload, preview, audit classification and target
/// together prevents a new screen from silently omitting a safety step.
enum AdministrativeWrite: Sendable {
    case reloadFirewall
    case restartService(name: String, displayName: String)
    case quickBlock(interface: String, address: String, description: String)
    case flushStates(interface: String)
    case deleteRule(tracker: String, displayName: String)
    case saveRule(rule: JSONDict, displayName: String)
    case deleteNatRule(tracker: String, displayName: String)
    case saveNatRule(rule: JSONDict, displayName: String)

    var action: AuditAction {
        switch self {
        case .reloadFirewall: return .reloadFirewall
        case .restartService: return .restartService
        case .quickBlock: return .quickBlock
        case .flushStates: return .flushStates
        case .deleteRule: return .deleteRule
        case .saveRule(let rule, _):
            if Self.isCreate(rule) { return .addRule }
            return Self.movesRule(rule) ? .reorderRules : .editRule
        case .deleteNatRule: return .deletePortForward
        case .saveNatRule(let rule, _): return Self.isCreate(rule) ? .addPortForward : .editPortForward
        }
    }

    var analyticsName: String { action.rawValue }

    var target: String? {
        switch self {
        case .reloadFirewall: return nil
        case .restartService(let name, _): return name
        case .quickBlock(let interface, _, _): return interface
        case .flushStates(let interface): return interface.isEmpty ? "all interfaces" : interface
        case .deleteRule(_, let displayName), .saveRule(_, let displayName),
             .deleteNatRule(_, let displayName), .saveNatRule(_, let displayName):
            return displayName
        }
    }

    var summary: String {
        switch self {
        case .reloadFirewall:
            return "Reload firewall ruleset"
        case .restartService(_, let displayName):
            return "Restart service \(displayName)"
        case .quickBlock(let interface, let address, _):
            return "Block \(address) on \(interface)"
        case .flushStates(let interface):
            return interface.isEmpty ? "Flush all firewall states" : "Flush states on \(interface)"
        case .deleteRule(let tracker, let displayName):
            return "Delete rule \(displayName.isEmpty ? tracker : displayName)"
        case .saveRule(let rule, let displayName):
            if Self.isCreate(rule) { return "Add rule \(displayName)" }
            return "\(Self.movesRule(rule) ? "Edit and move" : "Edit") rule \(displayName)"
        case .deleteNatRule(let tracker, let displayName):
            return "Delete port forward \(displayName.isEmpty ? tracker : displayName)"
        case .saveNatRule(let rule, let displayName):
            return "\(Self.isCreate(rule) ? "Add" : "Edit") port forward \(displayName)"
        }
    }

    /// Finished text shown before confirmation. It names the firewall at the
    /// call site and the exact target here, rather than relying on a generic
    /// destructive-action warning.
    var preview: String {
        switch self {
        case .reloadFirewall:
            return "Reload the active pf ruleset. Existing connections may be briefly interrupted."
        case .restartService(_, let displayName):
            return "Restart \(displayName). The service will be temporarily unavailable."
        case .quickBlock(let interface, let address, let description):
            return "Add a block rule on \(interface) for \(address), described as “\(description)”."
        case .flushStates(let interface):
            return interface.isEmpty
                ? "Delete every active firewall state. All active connections will be dropped."
                : "Delete active firewall states on \(interface). Connections using it will be dropped."
        case .deleteRule(let tracker, let displayName):
            return "Permanently delete rule “\(displayName.isEmpty ? tracker : displayName)” (tracker \(tracker))."
        case .saveRule(let rule, let displayName):
            let verb = Self.isCreate(rule) ? "Add" : "Update"
            return "\(verb) rule “\(displayName)” as \(Self.ruleDescription(rule))"
                + Self.rulePlacementDescription(rule) + "."
        case .deleteNatRule(let tracker, let displayName):
            return "Permanently delete port forward “\(displayName.isEmpty ? tracker : displayName)” (tracker \(tracker))."
        case .saveNatRule(let rule, let displayName):
            let verb = Self.isCreate(rule) ? "Add" : "Update"
            return "\(verb) port forward “\(displayName)” as \(Self.natDescription(rule))."
        }
    }

    private static func ruleDescription(_ rule: JSONDict) -> String {
        let source = rule.dict("source")?.string("address") ?? "any"
        let destination = rule.dict("destination")?.string("address") ?? "any"
        let port = rule.string("destination_port").map { ":\($0)" } ?? ""
        return "\((rule.string("type") ?? "pass").uppercased()) \(source) → \(destination)\(port) on \(rule.string("interface") ?? "unknown interface")"
    }

    private static func natDescription(_ rule: JSONDict) -> String {
        let destination = rule.dict("destination")?.string("address") ?? "interface address"
        let destinationPort = rule.string("destination_port").map { ":\($0)" } ?? ""
        let target = rule.string("target") ?? "unknown target"
        let localPort = rule.string("local_port").map { ":\($0)" } ?? ""
        return "\(destination)\(destinationPort) → \(target)\(localPort) on \(rule.string("interface") ?? "unknown interface")"
    }

    private static func isCreate(_ rule: JSONDict) -> Bool {
        rule.bool("create") ?? false
    }

    private static func movesRule(_ rule: JSONDict) -> Bool {
        !isCreate(rule) && rule.string("placement").map { $0 != "keep" } == true
    }

    private static func rulePlacementDescription(_ rule: JSONDict) -> String {
        switch rule.string("placement") {
        case "last":
            return ", placed last on its interface"
        case "before":
            return ", placed before tracker \(rule.string("before_tracker") ?? "unknown")"
        default:
            return ""
        }
    }
}

struct AdministrativeWriteOutcome: Sendable {
    let operationID: UUID
    let verification: AuditVerification
    let detail: String
}

enum WriteCoordinatorError: LocalizedError {
    case busy
    case staleFirewall
    case rateLimited
    case invalidOperation(String)
    case auditUnavailable(String)
    case auditCompletionFailed(String)
    case outcomeUnknown(String)
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .busy:
            return "Another administrative action is still running."
        case .staleFirewall:
            return "The selected firewall changed before this action could start. Nothing was sent."
        case .rateLimited:
            return "Please wait a few seconds between administrative actions."
        case .invalidOperation(let detail):
            return "The action was refused before sending: \(detail)"
        case .auditUnavailable(let detail):
            return "The protected audit trail is unavailable, so the action was not allowed. \(detail)"
        case .auditCompletionFailed(let detail):
            return "The firewall action was verified, but its completed audit result could not be saved. Inspect the firewall before doing anything else. \(detail)"
        case .outcomeUnknown(let detail):
            return "The firewall may have accepted the action, but its outcome could not be confirmed. Do not repeat it until you inspect the firewall. \(detail)"
        case .verificationFailed(let detail):
            return "The firewall accepted the action, but read-back verification did not confirm the intended result. \(detail)"
        }
    }
}

/// Serializes the entire administrative transaction for one firewall binding.
@MainActor
@Observable
final class WriteCoordinator {
    private let firewallID: UUID
    private let firewallName: String
    private let client: FirewallClient
    private let auditTrail: AuditTrail
    private let rateLimiter: WriteRateLimiter
    private let analytics: WriteAnalytics
    private let isBindingCurrent: () -> Bool
    private let administrationEnabled: Bool

    private(set) var isExecuting = false

    init(profile: ServerProfile,
         client: FirewallClient,
         auditTrail: AuditTrail,
         rateLimiter: WriteRateLimiter,
         analytics: WriteAnalytics,
         isBindingCurrent: @escaping () -> Bool) {
        firewallID = profile.id
        firewallName = profile.displayName
        administrationEnabled = profile.isAdministrationEnabled
        self.client = client
        self.auditTrail = auditTrail
        self.rateLimiter = rateLimiter
        self.analytics = analytics
        self.isBindingCurrent = isBindingCurrent
    }

    func preview(for operation: AdministrativeWrite) -> String {
        "Firewall: \(firewallName)\n\n\(operation.preview)\n\nThe result will be read back and recorded in the protected audit trail."
    }

    func execute(_ operation: AdministrativeWrite) async throws -> AdministrativeWriteOutcome {
        guard !isExecuting else { throw WriteCoordinatorError.busy }
        guard administrationEnabled else { throw RPCError.administrationDisabled }
        guard isBindingCurrent() else { throw WriteCoordinatorError.staleFirewall }
        try validate(operation)
        guard rateLimiter.allowWrite() else { throw WriteCoordinatorError.rateLimited }

        isExecuting = true
        defer { isExecuting = false }

        let before = try await snapshotBefore(operation)
        guard isBindingCurrent() else { throw WriteCoordinatorError.staleFirewall }

        let operationID = UUID()
        do {
            try auditTrail.begin(
                id: operationID,
                firewallID: firewallID,
                action: operation.action,
                summary: operation.summary,
                target: operation.target,
                preview: operation.preview,
                beforeHash: AuditTrail.hash(before)
            )
        } catch {
            throw WriteCoordinatorError.auditUnavailable(error.localizedDescription)
        }

        let receipt: Receipt
        do {
            receipt = try await perform(operation)
        } catch {
            analytics.record(operation: operation.analyticsName, success: false)
            let ambiguous = Self.isAmbiguous(error)
            let failureVerification: AuditVerification = ambiguous ? .outcomeUnknown : .unavailable
            try? auditTrail.finish(
                id: operationID,
                firewallID: firewallID,
                responseStatus: failureVerification == .outcomeUnknown ? "transport_unknown" : "rejected",
                verification: failureVerification,
                detail: error.localizedDescription,
                afterHash: nil
            )
            if ambiguous {
                throw WriteCoordinatorError.outcomeUnknown(error.localizedDescription)
            }
            throw error
        }

        guard isBindingCurrent() else {
            try? auditTrail.finish(
                id: operationID,
                firewallID: firewallID,
                responseStatus: receipt.status,
                verification: .outcomeUnknown,
                detail: "The active firewall changed before verification.",
                afterHash: nil
            )
            analytics.record(operation: operation.analyticsName, success: false)
            throw WriteCoordinatorError.outcomeUnknown("The active firewall changed before verification.")
        }

        let readBack: Verification
        do {
            readBack = try await verify(operation, receipt: receipt)
        } catch {
            let detail = error.localizedDescription
            try? auditTrail.finish(
                id: operationID,
                firewallID: firewallID,
                responseStatus: receipt.status,
                verification: .unavailable,
                detail: detail,
                afterHash: nil
            )
            analytics.record(operation: operation.analyticsName, success: false)
            throw WriteCoordinatorError.outcomeUnknown("Read-back failed: \(detail)")
        }

        do {
            try auditTrail.finish(
                id: operationID,
                firewallID: firewallID,
                responseStatus: receipt.status,
                verification: readBack.state,
                detail: readBack.detail,
                afterHash: AuditTrail.hash(readBack.snapshot)
            )
        } catch {
            analytics.record(operation: operation.analyticsName, success: false)
            throw WriteCoordinatorError.auditCompletionFailed(error.localizedDescription)
        }

        guard readBack.state == .verified || readBack.state == .readBack else {
            analytics.record(operation: operation.analyticsName, success: false)
            throw WriteCoordinatorError.verificationFailed(readBack.detail)
        }

        analytics.record(operation: operation.analyticsName, success: true)
        return AdministrativeWriteOutcome(
            operationID: operationID,
            verification: readBack.state,
            detail: readBack.detail
        )
    }

    // MARK: Validation and execution

    private func validate(_ operation: AdministrativeWrite) throws {
        switch operation {
        case .restartService(let name, _):
            guard !name.isEmpty else { throw WriteCoordinatorError.invalidOperation("service name is empty") }
        case .quickBlock(let interface, let address, _):
            guard !interface.isEmpty, !address.isEmpty else {
                throw WriteCoordinatorError.invalidOperation("interface and address are required")
            }
        case .deleteRule(let tracker, _), .deleteNatRule(let tracker, _):
            guard !tracker.isEmpty else { throw WriteCoordinatorError.invalidOperation("a stable tracker ID is required") }
        case .saveRule(let rule, _):
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
        case .saveNatRule(let rule, _):
            let isCreate = rule.bool("create") ?? false
            guard isCreate || !(rule.string("tracker") ?? "").isEmpty else {
                throw WriteCoordinatorError.invalidOperation("a stable tracker ID is required for an edit")
            }
        case .reloadFirewall, .flushStates:
            break
        }
    }

    private struct Receipt {
        let status: String
        let tracker: String?
    }

    private func perform(_ operation: AdministrativeWrite) async throws -> Receipt {
        switch operation {
        case .reloadFirewall:
            return Receipt(status: try await client.reloadFirewall(), tracker: nil)
        case .restartService(let name, _):
            return Receipt(status: try await client.restartService(named: name), tracker: nil)
        case .quickBlock(let interface, let address, let description):
            let result = try await client.quickBlock(
                interface: interface,
                address: address,
                description: description
            )
            return Receipt(
                status: result.string("status") ?? "ok",
                tracker: result.dict("rule")?.string("tracker") ?? result.string("tracker")
            )
        case .flushStates(let interface):
            return Receipt(status: try await client.flushStates(interface: interface), tracker: nil)
        case .deleteRule(let tracker, _):
            return Receipt(status: try await client.deleteRule(tracker: tracker), tracker: tracker)
        case .saveRule(let rule, _):
            let result = try await client.saveRule(rule: rule)
            return Receipt(status: result.string("status") ?? "ok", tracker: result.string("tracker"))
        case .deleteNatRule(let tracker, _):
            return Receipt(status: try await client.deleteNatRule(tracker: tracker), tracker: tracker)
        case .saveNatRule(let rule, _):
            let result = try await client.saveNatRule(rule: rule)
            return Receipt(status: result.string("status") ?? "ok", tracker: result.string("tracker"))
        }
    }

    // MARK: Precondition snapshots and read-back

    private func snapshotBefore(_ operation: AdministrativeWrite) async throws -> String? {
        switch operation {
        case .reloadFirewall, .quickBlock:
            return "rules=\((try await client.firewallRules()).count)"
        case .restartService(let name, _):
            guard let service = try await client.services().first(where: { $0.name == name }) else {
                throw WriteCoordinatorError.invalidOperation("the service is no longer present")
            }
            return Self.serviceSnapshot(service)
        case .flushStates:
            return Self.stateSnapshot(try await client.stateTableSize())
        case .deleteRule:
            guard let tracker = operation.tracker else {
                throw WriteCoordinatorError.invalidOperation("a stable rule tracker is required")
            }
            guard let rule = try await client.firewallRules().first(where: { $0.tracker == tracker }) else {
                throw WriteCoordinatorError.invalidOperation("the rule is no longer present")
            }
            return Self.ruleSnapshot(rule)
        case .saveRule(let expected, _):
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
        case .saveNatRule(let rule, _) where rule.bool("create") == true:
            return "port_forwards=\((try await client.portForwards()).count);new_tracker=unassigned"
        case .deleteNatRule, .saveNatRule:
            guard let tracker = operation.tracker else {
                throw WriteCoordinatorError.invalidOperation("a stable port-forward tracker is required")
            }
            guard let forward = try await client.portForwards().first(where: { $0.tracker == tracker }) else {
                throw WriteCoordinatorError.invalidOperation("the port forward is no longer present")
            }
            return Self.natSnapshot(forward)
        }
    }

    private struct Verification {
        let state: AuditVerification
        let detail: String
        let snapshot: String?
    }

    private func verify(_ operation: AdministrativeWrite, receipt: Receipt) async throws -> Verification {
        switch operation {
        case .reloadFirewall:
            let rules = try await client.firewallRules()
            return Verification(state: .readBack,
                                detail: "Ruleset is readable after reload (\(rules.count) rules).",
                                snapshot: "rules=\(rules.count)")
        case .restartService(let name, _):
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
        case .quickBlock(let interface, let address, let description):
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
        case .flushStates:
            let state = try await client.stateTableSize()
            return Verification(state: .readBack,
                                detail: "State table is readable after the flush (\(state.current ?? 0) active states).",
                                snapshot: Self.stateSnapshot(state))
        case .deleteRule(let tracker, _):
            let exists = try await client.firewallRules().contains { $0.tracker == tracker }
            return Verification(state: exists ? .mismatch : .verified,
                                detail: exists ? "The deleted rule is still present." : "The rule is absent during read-back.",
                                snapshot: exists ? "tracker=\(tracker);present=true" : "tracker=\(tracker);present=false")
        case .saveRule(let expected, _):
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
        case .deleteNatRule(let tracker, _):
            let exists = try await client.portForwards().contains { $0.tracker == tracker }
            return Verification(state: exists ? .mismatch : .verified,
                                detail: exists ? "The deleted port forward is still present." : "The port forward is absent during read-back.",
                                snapshot: exists ? "tracker=\(tracker);present=true" : "tracker=\(tracker);present=false")
        case .saveNatRule(let expected, _):
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
    }

    private static func isAmbiguous(_ error: Error) -> Bool {
        guard let rpc = error as? RPCError else { return false }
        switch rpc {
        case .transport, .offline, .tls, .cancelled: return true
        default: return false
        }
    }

    private static func ruleSnapshot(_ rule: FirewallRule) -> String {
        [rule.tracker, rule.interfaceName, rule.type, rule.ipProtocol ?? "", rule.proto ?? "",
         rule.source, rule.destination, rule.descr, String(rule.disabled), String(rule.logged)]
            .joined(separator: "|")
    }

    private static func natSnapshot(_ forward: PortForward) -> String {
        [forward.tracker, forward.interfaceName, forward.ipProtocol ?? "", forward.proto ?? "",
         forward.sourceSide.text, forward.destinationSide.text, forward.target,
         forward.localPort ?? "", forward.descr, String(forward.disabled)]
            .joined(separator: "|")
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

private extension AdministrativeWrite {
    var tracker: String? {
        switch self {
        case .deleteRule(let tracker, _), .deleteNatRule(let tracker, _): return tracker
        case .saveRule(let rule, _), .saveNatRule(let rule, _): return rule.string("tracker")
        default: return nil
        }
    }
}
