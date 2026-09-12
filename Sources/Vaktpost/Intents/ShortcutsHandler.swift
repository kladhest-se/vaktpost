import Foundation
import AppIntents

// MARK: - Stubbed App Intents for iOS 26 compatibility
// The original App Intents implementation has been temporarily disabled
// due to breaking API changes in iOS 26 SDK.

// enum VaktpostShortcuts: AppEntity { /* disabled */ }
// struct VaktpostShortcutsQuery: EntityQuery<VaktpostShortcuts> { /* disabled */ }
// struct GetFirewallStatus: AppIntent { /* disabled */ }
// struct GetVPNStatus: AppIntent { /* disabled */ }
// struct GetInvestigationResults: AppIntent { /* disabled */ }
// struct GetActiveAlerts: AppIntent { /* disabled */ }

enum VaktpostShortcutError: Error, LocalizedError {
    case noFirewallConfigured
    
    var errorDescription: String? {
        switch self {
        case .noFirewallConfigured:
            return "Shortcuts integration is temporarily unavailable."
        }
    }
}
