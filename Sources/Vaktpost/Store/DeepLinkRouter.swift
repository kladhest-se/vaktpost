import SwiftUI

/// Routes deep links to the appropriate view within the app.
///
/// Monitors for incoming URLs and updates navigation state accordingly.
@Observable
final class DeepLinkRouter {
    var activeLink: DeepLink?
    var investigationQuery: String?
    
    func handle(_ url: URL) {
        guard let link = DeepLinkParser.parse(url) else { return }
        activeLink = link
        investigationQuery = link.query
    }
    
    func clear() {
        activeLink = nil
        investigationQuery = nil
    }
}
