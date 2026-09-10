import Foundation
import Observation

/// Manages gateway state: the list of gateways and their delay/loss metrics.
///
/// Embedded as a property in ``DashboardStore``. The refresh cycle calls
/// ``ingest(_:delayMS:lossPercent:)`` after each fetch to maintain the
/// historical trend lines shown on the Gateways card.
@MainActor
@Observable
final class GatewayManager {

    /// Current gateway list from the firewall.
    var gateways: [GatewayStatus] = []

    /// Delay and loss history per gateway.
    let gatewayMetrics = GatewayMetricTracker()

    /// Ingest a new reading for a gateway after it has been fetched.
    ///
    /// Called during ``DashboardStore/refresh()`` once ``gateways`` has been
    /// populated from the latest batch.
    func ingest(key: String, delayMS: Double?, lossPercent: Double?) {
        gatewayMetrics.ingest(key: key, delayMS: delayMS, lossPercent: lossPercent)
    }

    /// Reset all gateway metrics (called on server switch).
    func reset() {
        gatewayMetrics.reset()
        gateways.removeAll()
    }
}
