import Foundation

/// Why the firewall would not let this app in, in words somebody can act on.
///
/// A wrong password, a missing privilege and a missing Keychain entry each
/// need a different fix, and none of them is "check your network". Before
/// this, all three reached the screen as one line of error text among the
/// connection hints, and pfSense's own wording — "Authentication failed",
/// arriving as a numbered fault — did not even say which of the first two it
/// was.
///
/// Built only from errors that are about identity (`isAuthenticationFailure`);
/// everything else keeps the existing unreachable and per-card handling.
struct AuthenticationProblem: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// The firewall rejected the username or password.
        case wrongCredentials
        /// The sign-in worked, but the account may not use XML-RPC.
        case missingPrivilege
        /// There is no password on this device to send.
        case noPassword
    }

    let kind: Kind
    /// The account that was refused, for naming it back to the person.
    let username: String

    init?(_ error: Error, username: String) {
        guard let rpc = error as? RPCError else { return nil }
        switch rpc {
        case .unauthorized: kind = .wrongCredentials
        case .forbidden: kind = .missingPrivilege
        case .noCredentials: kind = .noPassword
        default: return nil
        }
        self.username = username
    }

    private var account: String {
        username.isEmpty ? "this account" : "“\(username)”"
    }

    var symbol: String {
        switch kind {
        case .wrongCredentials: return "person.crop.circle.badge.xmark"
        case .missingPrivilege: return "lock.shield"
        case .noPassword: return "key.slash"
        }
    }

    var title: String {
        switch kind {
        case .wrongCredentials: return "Wrong username or password"
        case .missingPrivilege: return "Signed in, but access denied"
        case .noPassword: return "No password saved"
        }
    }

    var summary: String {
        switch kind {
        case .wrongCredentials:
            return "The firewall rejected the sign-in for \(account). Nothing was loaded."
        case .missingPrivilege:
            return "The username and password are correct, but \(account) is not allowed to use "
                + "pfSense's XML-RPC service, which Vaktpost needs."
        case .noPassword:
            return "There is no password for this firewall on this device, so Vaktpost could not sign in."
        }
    }

    /// What to do, in the order that fixes it fastest.
    var steps: [String] {
        switch kind {
        case .wrongCredentials:
            return [
                "Check the username. pfSense usernames are case-sensitive.",
                "Enter the password again in this firewall's settings, and tap Save.",
                "Sign in to the pfSense web interface with the same account to confirm it works there.",
            ]
        case .missingPrivilege:
            return [
                "In pfSense, open System → User Manager and edit \(account), or a group it belongs to.",
                "Add the “System - HA node sync” privilege and save.",
                "Come back and tap Try again.",
            ]
        case .noPassword:
            return [
                "Open this firewall's settings, enter the password, and tap Save.",
            ]
        }
    }

    /// Said once, under the steps, where it applies.
    var note: String? {
        switch kind {
        case .wrongCredentials:
            return "Vaktpost has stopped refreshing this firewall until you change the settings or tap Try again. "
                + "pfSense blocks an address after repeated failed sign-ins; if it has, wait a few minutes "
                + "or remove the block under Diagnostics → Tables."
        case .missingPrivilege:
            return "That privilege is administrator-equivalent. Use a dedicated account for Vaktpost."
        case .noPassword:
            return nil
        }
    }

    /// Whether the fix is in the credentials the person typed, so those
    /// fields can be marked.
    var pointsAtCredentials: Bool {
        kind == .wrongCredentials || kind == .noPassword
    }
}
