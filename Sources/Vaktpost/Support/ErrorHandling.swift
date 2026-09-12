import Foundation

/// Provides user-friendly error messages for write operations.
///
/// Translates low-level RPC errors into actionable messages that explain
/// what went wrong and what the user can do about it.
enum WriteErrorFormatter {

    /// Returns a human-readable error message for a write operation.
    ///
    /// - Parameters:
    ///   - error: The error that occurred.
    ///   - operation: The type of operation being attempted.
    /// - Returns: A user-friendly error message.
    static func message(for error: Error, operation: WriteOperation) -> String {
        let rpcError = error as? RPCError

        switch (rpcError, operation) {
        case (.administrationDisabled, _):
            return "This firewall is in monitor-only mode. No change was sent."
        case (.unauthorized, _):
            return "Authentication failed. Check your credentials and that the account has the 'System - HA node sync' privilege."
        case (.forbidden, _):
            return "Access denied. The account needs the 'System - HA node sync' privilege to perform write operations."
        case (.offline(let detail), _):
            return "Cannot reach the firewall: \(detail)"
        case (.transport, _):
            return "Network error while communicating with the firewall. Check your connection and try again."
        case (.tls, _):
            return "Secure connection failed. The firewall's certificate could not be verified."
        case (.fault(_, let message), .quickBlock):
            return "Firewall rejected the block rule: \(message)"
        case (.fault(_, let message), .restartService):
            return "Firewall rejected the service restart: \(message)"
        case (.fault(_, let message), .reloadFirewall):
            return "Firewall rejected the ruleset reload: \(message)"
        case (.fault(_, let message), .flushStates):
            return "Firewall rejected the state flush: \(message)"
        case (.malformed(let detail), _):
            if let detail, !detail.isEmpty {
                return "The firewall returned an unexpected response: \(detail)"
            }
            return "The firewall returned an unexpected response. Check the firewall logs for details."
        case (_, .quickBlock):
            return "Failed to add block rule. \(error.localizedDescription)"
        case (_, .restartService):
            return "Failed to restart service. \(error.localizedDescription)"
        case (_, .reloadFirewall):
            return "Failed to reload firewall rules. \(error.localizedDescription)"
        case (_, .flushStates):
            return "Failed to flush states. \(error.localizedDescription)"
        default:
            return error.localizedDescription
        }
    }

    /// Returns a recovery suggestion for an error.
    ///
    /// - Parameter error: The error that occurred.
    /// - Returns: A suggested action, or nil if no suggestion is available.
    static func suggestion(for error: Error) -> String? {
        guard let rpcError = error as? RPCError else { return nil }

        switch rpcError {
        case .administrationDisabled:
            return "Open Firewalls, edit this firewall, and authenticate to enable administrative actions."
        case .unauthorized, .forbidden:
            return "Contact your firewall administrator to verify the account has the required privileges."
        case .offline:
            return "Check that the firewall is powered on and reachable on the network."
        case .transport:
            return "Check your network connection and try again. If the problem persists, verify firewall connectivity."
        case .tls:
            return "Verify the firewall's certificate is valid, or enable untrusted TLS in Settings if in a lab environment."
        case .fault:
            return "Check the firewall system logs for details about the rejected operation."
        case .malformed:
            return "The firewall may be experiencing issues. Try refreshing the page and retrying the operation."
        case .notConfigured, .badURL, .noCredentials, .cancelled:
            return nil
        }
    }
}

/// Types of write operations, used for error formatting.
enum WriteOperation {
    case quickBlock
    case restartService
    case reloadFirewall
    case flushStates
    case other
}
