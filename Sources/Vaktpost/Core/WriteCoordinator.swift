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
    case startFirmwareUpdate(current: String, target: String)
    case startPackageUpdate(identifier: String, displayName: String,
                            installed: String, target: String)
    case quickBlock(interface: String, address: String, description: String)
    case flushStates(interface: String)
    case deleteRule(tracker: String, displayName: String)
    case saveRule(rule: JSONDict, displayName: String)
    case deleteNatRule(tracker: String, displayName: String)
    case saveNatRule(rule: JSONDict, displayName: String)
    case reorderFilterRules(interface: String, items: [FirewallClient.ReorderItem], displayName: String)
    case reorderNatRules(items: [FirewallClient.NatReorderItem], displayName: String)
    case saveFilterSeparator(separator: JSONDict, displayName: String)
    case deleteFilterSeparator(interface: String, key: String, displayName: String)
    case saveNatSeparator(separator: JSONDict, displayName: String)
    case deleteNatSeparator(key: String, displayName: String)
    case saveAlias(alias: JSONDict, displayName: String)
    case deleteAlias(name: String, displayName: String)

    var action: AuditAction {
        switch self {
        case .reloadFirewall: return .reloadFirewall
        case .restartService: return .restartService
        case .startFirmwareUpdate: return .updateFirmware
        case .startPackageUpdate: return .updatePackage
        case .quickBlock: return .quickBlock
        case .flushStates: return .flushStates
        case .deleteRule: return .deleteRule
        case .saveRule(let rule, _):
            if Self.isCreate(rule) { return .addRule }
            return Self.movesRule(rule) ? .reorderRules : .editRule
        case .deleteNatRule: return .deletePortForward
        case .saveNatRule(let rule, _): return Self.isCreate(rule) ? .addPortForward : .editPortForward
        case .reorderFilterRules, .reorderNatRules: return .reorderRules
        case .saveFilterSeparator(let separator, _):
            return separator.bool("create") == true ? .addSeparator : .editSeparator
        case .saveNatSeparator(let separator, _):
            return separator.bool("create") == true ? .addSeparator : .editSeparator
        case .deleteFilterSeparator, .deleteNatSeparator: return .deleteSeparator
        case .saveAlias(let alias, _): return Self.isCreate(alias) ? .addAlias : .editAlias
        case .deleteAlias: return .deleteAlias
        }
    }

    var analyticsName: String { action.rawValue }

    var target: String? {
        switch self {
        case .reloadFirewall: return nil
        case .restartService(let name, _): return name
        case .startFirmwareUpdate: return "pfSense base system"
        case .startPackageUpdate(_, let displayName, _, _): return displayName
        case .quickBlock(let interface, _, _): return interface
        case .flushStates(let interface): return interface.isEmpty ? "all interfaces" : interface
        case .deleteRule(_, let displayName), .saveRule(_, let displayName),
             .deleteNatRule(_, let displayName), .saveNatRule(_, let displayName):
            return displayName
        case .reorderFilterRules(_, _, let displayName),
             .reorderNatRules(_, let displayName):
            return displayName
        case .saveFilterSeparator(_, let displayName),
             .deleteFilterSeparator(_, _, let displayName),
             .saveNatSeparator(_, let displayName),
             .deleteNatSeparator(_, let displayName):
            return displayName
        case .saveAlias(_, let displayName), .deleteAlias(_, let displayName):
            return displayName
        }
    }

    var summary: String {
        switch self {
        case .reloadFirewall:
            return "Apply pending firewall changes"
        case .restartService(_, let displayName):
            return "Restart service \(displayName)"
        case .startFirmwareUpdate(let current, let target):
            return "Update pfSense from \(current) to \(target)"
        case .startPackageUpdate(_, let displayName, let installed, let target):
            return "Update package \(displayName) from \(installed) to \(target)"
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
        case .reorderFilterRules(_, let items, let displayName):
            let separators = items.filter { if case .separator = $0 { return true }; return false }.count
            return "Reorder rules on \(displayName)"
                + (separators > 0 ? " (\(separators) separator\(separators == 1 ? "" : "s"))" : "")
        case .reorderNatRules(let items, _):
            let forwardCount = items.filter { $0.kind == .rule }.count
            let separatorCount = items.count - forwardCount
            return "Reorder \(forwardCount) NAT port forward\(forwardCount == 1 ? "" : "s")"
                + (separatorCount > 0
                   ? " and \(separatorCount) separator\(separatorCount == 1 ? "" : "s")" : "")
        case .saveFilterSeparator(let separator, let displayName):
            return "\(separator.bool("create") == true ? "Add" : "Edit") separator \(displayName)"
        case .deleteFilterSeparator(_, _, let displayName):
            return "Delete separator \(displayName)"
        case .saveNatSeparator(let separator, let displayName):
            return "\(separator.bool("create") == true ? "Add" : "Edit") NAT separator \(displayName)"
        case .deleteNatSeparator(_, let displayName):
            return "Delete NAT separator \(displayName)"
        case .saveAlias(let alias, let displayName):
            return "\(Self.isCreate(alias) ? "Add" : "Edit") alias \(displayName)"
        case .deleteAlias(_, let displayName):
            return "Delete alias \(displayName)"
        }
    }

    /// Finished text shown before confirmation. It names the firewall at the
    /// call site and the exact target here, rather than relying on a generic
    /// destructive-action warning.
    var preview: String {
        switch self {
        case .reloadFirewall:
            return "Apply every pending filter, NAT, and alias change currently saved on this firewall, "
                + "including changes made in the web UI or by another administrator. Existing connections may be briefly interrupted."
        case .restartService(_, let displayName):
            return "Restart \(displayName). The service will be temporarily unavailable."
        case .startFirmwareUpdate(let current, let target):
            return "Start the pfSense base-system update from \(current) to \(target) on the configured release branch. "
                + "pfSense will create a restore point, run the update in the background, and may reboot. "
                + "Traffic and management access can be interrupted for several minutes."
        case .startPackageUpdate(_, let displayName, let installed, let target):
            return "Start the update of package “\(displayName)” from \(installed) to \(target). "
                + "pfSense will create a restore point and run the package update in the background. "
                + "Services provided by this package may restart or be temporarily unavailable."
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
        case .reorderFilterRules(let interface, let items, _):
            let ruleCount = items.filter { if case .rule = $0 { return true }; return false }.count
            let sepCount = items.count - ruleCount
            var text = "Rearrange \(interface) to the new order — \(ruleCount) rule\(ruleCount == 1 ? "" : "s")"
            if sepCount > 0 { text += " and \(sepCount) separator\(sepCount == 1 ? "" : "s")" }
            return text + ". Every other interface's rules are left exactly where they are."
        case .reorderNatRules(let items, _):
            let forwardCount = items.filter { $0.kind == .rule }.count
            let separatorCount = items.count - forwardCount
            return "Rearrange the complete NAT table to the new order — \(forwardCount) port forward\(forwardCount == 1 ? "" : "s") "
                + "and \(separatorCount) separator\(separatorCount == 1 ? "" : "s")."
        case .saveFilterSeparator(let separator, let displayName):
            let verb = separator.bool("create") == true ? "Add" : "Update"
            return "\(verb) separator “\(displayName)” on \(separator.string("interface") ?? "unknown interface"), "
                + "after \(separator.int("position") ?? 0) rules."
        case .deleteFilterSeparator(let interface, _, let displayName):
            return "Delete separator “\(displayName)” from \(interface)."
        case .saveNatSeparator(let separator, let displayName):
            let verb = separator.bool("create") == true ? "Add" : "Update"
            return "\(verb) NAT separator “\(displayName)”, after \(separator.int("position") ?? 0) port forwards."
        case .deleteNatSeparator(_, let displayName):
            return "Delete NAT separator “\(displayName)”."
        case .saveAlias(let alias, let displayName):
            let verb = Self.isCreate(alias) ? "Add" : "Update"
            let members = alias.list("members").count
            return "\(verb) \(alias.string("type") ?? "firewall") alias “\(displayName)” with \(members) member\(members == 1 ? "" : "s"). "
                + "The change will remain inactive until Apply Changes."
        case .deleteAlias(_, let displayName):
            return "Delete unused firewall alias “\(displayName)”. The change will remain inactive until Apply Changes."
        }
    }

    private static func ruleDescription(_ rule: JSONDict) -> String {
        let source = addressDescription(rule.value("source"), fallback: "any")
        let destination = addressDescription(rule.value("destination"), fallback: "any")
        let port = rule.string("destination_port").map { ":\($0)" } ?? ""
        return "\((rule.string("type") ?? "pass").uppercased()) \(source) → \(destination)\(port) on \(rule.string("interface") ?? "unknown interface")"
    }

    private static func natDescription(_ rule: JSONDict) -> String {
        let destination = addressDescription(rule.value("destination"),
                                             fallback: "interface address")
        let destinationPort = rule.string("destination_port").map { ":\($0)" } ?? ""
        let target = rule.string("target") ?? "unknown target"
        let localPort = rule.string("local_port").map { ":\($0)" } ?? ""
        return "\(destination)\(destinationPort) → \(target)\(localPort) on \(rule.string("interface") ?? "unknown interface")"
    }

    private static func addressDescription(_ value: JSONValue?, fallback: String) -> String {
        guard value != nil else { return fallback }
        let side = FilterAddress(value)
        switch side.storageKind {
        case .any:
            return "any"
        case .network:
            return "\(side.address) (system selector)"
        case .address:
            return side.address
        }
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
    /// Stable identity returned by pfSense for the saved object. This matters
    /// for a trackerless NAT rule: its first Vaktpost edit assigns a tracker,
    /// so the list identity changes even though it is still the same rule.
    let objectID: String?
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
            return "The firewall action was verified, but its completed audit result could not be saved. "
                + "Inspect the firewall before doing anything else. \(detail)"
        case .outcomeUnknown(let detail):
            return "The firewall may have accepted the action, but its outcome could not be confirmed. "
                + "Do not repeat it until you inspect the firewall. \(detail)"
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
    let client: FirewallClient
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
            detail: readBack.detail,
            objectID: receipt.tracker
        )
    }

    // MARK: Validation and execution

    private func validate(_ operation: AdministrativeWrite) throws {
        switch operation {
        case .restartService(let name, _):
            try Self.validateRestartService(name: name)
        case .startFirmwareUpdate(let current, let target):
            try Self.validateFirmwareUpdate(current: current, target: target)
        case .startPackageUpdate(let identifier, _, let installed, let target):
            try Self.validatePackageUpdate(identifier: identifier, installed: installed, target: target)
        case .quickBlock(let interface, let address, _):
            try Self.validateQuickBlock(interface: interface, address: address)
        case .deleteRule(let tracker, _), .deleteNatRule(let tracker, _):
            try Self.validateTrackerRequired(tracker)
        case .saveRule(let rule, _):
            try Self.validateSaveRule(rule)
        case .saveNatRule(let rule, _):
            try Self.validateSaveNatRule(rule)
        case .reloadFirewall, .flushStates:
            break
        case .saveFilterSeparator(let separator, _):
            try Self.validateSaveFilterSeparator(separator)
        case .deleteFilterSeparator(let interface, let key, _):
            try Self.validateDeleteFilterSeparator(interface: interface, key: key)
        case .saveNatSeparator(let separator, _):
            try Self.validateSaveNatSeparator(separator)
        case .deleteNatSeparator(let key, _):
            try Self.validateDeleteNatSeparator(key: key)
        case .saveAlias(let alias, _):
            try Self.validateSaveAlias(alias)
        case .deleteAlias(let name, _):
            try Self.validateDeleteAlias(name: name)
        case .reorderFilterRules(let interface, let items, _):
            try Self.validateReorderFilterRules(interface: interface, items: items)
        case .reorderNatRules(let items, _):
            try Self.validateReorderNatRules(items: items)
        }
    }

    struct Receipt {
        let status: String
        let tracker: String?
        let updatePhase: String?

        init(status: String, tracker: String?, updatePhase: String? = nil) {
            self.status = status
            self.tracker = tracker
            self.updatePhase = updatePhase
        }
    }

    private func perform(_ operation: AdministrativeWrite) async throws -> Receipt {
        switch operation {
        case .reloadFirewall:
            return Receipt(status: try await client.reloadFirewall(), tracker: nil)
        case .restartService(let name, _):
            return Receipt(status: try await client.restartService(named: name), tracker: nil)
        case .startFirmwareUpdate:
            let result = try await client.startFirmwareUpdate()
            return Receipt(status: result.string("status") ?? "ok", tracker: "firmware",
                           updatePhase: result.string("phase"))
        case .startPackageUpdate(let identifier, _, _, _):
            let result = try await client.startPackageUpdate(identifier: identifier)
            return Receipt(status: result.string("status") ?? "ok", tracker: identifier,
                           updatePhase: result.string("phase"))
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
        case .reorderFilterRules(let interface, let items, _):
            let result = try await client.reorderFilterRules(interface: interface, items: items)
            return Receipt(status: result.string("status") ?? "ok", tracker: nil)
        case .reorderNatRules(let items, _):
            let result = try await client.reorderNatRules(items: items)
            return Receipt(status: result.string("status") ?? "ok", tracker: nil)
        case .saveFilterSeparator(let separator, _):
            let result = try await client.saveFilterSeparator(separator: separator)
            return Receipt(status: result.string("status") ?? "ok", tracker: result.string("key"))
        case .deleteFilterSeparator(let interface, let key, _):
            let result = try await client.deleteFilterSeparator(interface: interface, key: key)
            return Receipt(status: result.string("status") ?? "ok", tracker: key)
        case .saveNatSeparator(let separator, _):
            let result = try await client.saveNatSeparator(separator: separator)
            return Receipt(status: result.string("status") ?? "ok", tracker: result.string("key"))
        case .deleteNatSeparator(let key, _):
            let result = try await client.deleteNatSeparator(key: key)
            return Receipt(status: result.string("status") ?? "ok", tracker: key)
        case .saveAlias(let alias, _):
            let result = try await client.saveAlias(alias: alias)
            return Receipt(status: result.string("status") ?? "ok", tracker: result.string("name"))
        case .deleteAlias(let name, _):
            let result = try await client.deleteAlias(name: name)
            return Receipt(status: result.string("status") ?? "ok", tracker: name)
        }
    }

    private static func isAmbiguous(_ error: Error) -> Bool {
        guard let rpc = error as? RPCError else { return false }
        switch rpc {
        case .transport, .offline, .tls, .cancelled: return true
        default: return false
        }
    }

    /// The current order of one interface's rules and separators, as tokens,
    /// in the same reading order the app displays them in.
    ///
    /// This is the one place the ordering logic could drift from what the
    /// Rules screen shows, so it is built the same way that screen builds
    /// it: this interface's own rules in on-disk order, with each separator
    /// inserted at its recorded `precedingRuleCount` — matched by exact
    /// interface equality, which is what already excludes a floating rule's
    /// comma-joined interface list without a special case for it.
    ///
    /// A separator whose position could not be read, or one that names more
    /// preceding rules than exist, is placed last rather than dropped —
    /// the same fallback the display already uses, so a snapshot always
    /// accounts for every separator it was given.
}

extension AdministrativeWrite {
    var tracker: String? {
        switch self {
        case .deleteRule(let tracker, _), .deleteNatRule(let tracker, _): return tracker
        case .saveRule(let rule, _), .saveNatRule(let rule, _): return rule.string("tracker")
        default: return nil
        }
    }
}
