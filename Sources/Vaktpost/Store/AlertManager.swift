import Foundation
import Observation
import SwiftUI

/// Manages alert state: storage, silencing, acknowledgement, and filtering.
///
/// Embedded as a property in ``DashboardStore`` so the alert lifecycle
/// (build → prune → filter → acknowledge) stays local while the rest of the
/// store keeps its raw data.
@MainActor
@Observable
final class AlertManager {

    // MARK: UserDefaults keys

    private enum UDKey: String {
        case temperatureWarn = "alerts.tempWarn"
        case mutedAlerts = "alerts.hidden.v2"
        case alertsSilenced = "alerts.silenced"
        case acknowledgedAlerts = "alerts.acknowledged"
    }

    // MARK: Properties

    /// Raw alerts derived from current firewall state.
    ///
    /// Everything on screen uses `visibleAlerts`; this stays unfiltered so the
    /// Alerts screen can report what is hidden.
    var alerts: [VaktpostAlert] = []

    /// Categories the person has chosen not to be told about.
    ///
    /// Alerts are derived on the device from status already fetched, so this
    /// filters what is shown rather than what is measured — a silenced
    /// category still appears on its own screen, it just stops driving the
    /// badge and the Overview banner.
    var mutedAlertCategories: Set<String> = [] {
        didSet {
            // A new key, deliberately.
            //
            // `alerts.muted` was written by a build where the switches meant
            // the opposite thing, so anyone who touched that screen has a
            // stored set that now reads inverted — every kind silenced when
            // they had silenced nothing. Changing what a stored value means
            // without changing where it is stored is a migration, and this is
            // the cheapest correct one: start again from the default.
            UserDefaults.standard.set(Array(mutedAlertCategories), forKey: UDKey.mutedAlerts.rawValue)
        }
    }

    /// Whether the person has silenced all alerts.
    var alertsSilenced: Bool = false {
        didSet { UserDefaults.standard.set(alertsSilenced, forKey: UDKey.alertsSilenced.rawValue) }
    }

    /// Individual alerts the person has acknowledged.
    ///
    /// Keyed by signature rather than by identity, so the same condition
    /// reported a degree hotter stays acknowledged. Persisted, because an
    /// acknowledgement that expires when the app is backgrounded is not one.
    ///
    /// This is separate from silencing a whole category: silencing says "never
    /// tell me about certificates", acknowledging says "I have seen this one".
    /// Most things people want to stop seeing are the second kind.
    var acknowledgedAlerts: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(acknowledgedAlerts), forKey: UDKey.acknowledgedAlerts.rawValue)
        }
    }

    /// Where the temperature alert fires, in °C, or nil to follow the sensor.
    ///
    /// The built-in thresholds are a guess about hardware the app cannot see:
    /// 95 for a chipset, 80 for a CPU die. Those are reasonable defaults and
    /// wrong for somebody who knows their board runs at 80 and wants to hear
    /// about 82. Whoever owns the firewall knows what normal looks like on it,
    /// so they get to say.
    var temperatureWarnOverride: Double? {
        didSet {
            UserDefaults.standard.set(temperatureWarnOverride ?? 0,
                                      forKey: UDKey.temperatureWarn.rawValue)
        }
    }

    // MARK: Initialization

    init(defaults: UserDefaults = .standard) {
        mutedAlertCategories = Set(defaults.stringArray(forKey: "alerts.hidden.v2") ?? [])
        defaults.removeObject(forKey: "alerts.muted")   // superseded; see above
        alertsSilenced = defaults.bool(forKey: "alerts.silenced")
        acknowledgedAlerts = Set(defaults.stringArray(forKey: "alerts.acknowledged") ?? [])
        let tempWarn = defaults.double(forKey: "alerts.tempWarn")
        temperatureWarnOverride = tempWarn > 0 ? tempWarn : nil
    }

    // MARK: Actions

    /// Marks `alert` as seen by the user.
    func acknowledge(_ alert: VaktpostAlert) {
        acknowledgedAlerts.insert(alert.signature)
    }

    /// Clears every acknowledgement at once.
    func unacknowledgeAll() {
        acknowledgedAlerts.removeAll()
    }

    /// Forgets acknowledgements for conditions that are no longer true.
    ///
    /// Called after each refresh. Without it, acknowledging a gateway that was
    /// down would silence that gateway going down again next month — the
    /// acknowledgement would outlive the thing it was about.
    func pruneAcknowledgements() {
        let present = Set(alerts.map(\.signature))
        let stale = acknowledgedAlerts.subtracting(present)
        if !stale.isEmpty { acknowledgedAlerts.subtract(stale) }
    }

    // MARK: Derived properties

    /// Acknowledged conditions that are still true.
    var acknowledgedButPresent: [VaktpostAlert] {
        alerts.filter { acknowledgedAlerts.contains($0.signature) }
    }

    /// Alerts after silencing. Everything on screen uses this; `alerts` stays
    /// the unfiltered truth so the Alerts screen can say what is hidden.
    var visibleAlerts: [VaktpostAlert] {
        if alertsSilenced { return [] }
        return alerts.filter {
            !mutedAlertCategories.contains($0.category.rawValue)
                && !acknowledgedAlerts.contains($0.signature)
        }
    }

    /// Hidden by silencing, not by acknowledgement.
    ///
    /// Subtracting one count from the other would include acknowledged alerts,
    /// which are reported separately — the screen would say the same alert was
    /// hidden twice for two different reasons.
    var silencedAlertCount: Int {
        if alertsSilenced { return alerts.count }
        return alerts.filter { mutedAlertCategories.contains($0.category.rawValue) }.count
    }

    /// The tab badge. Silenced categories do not contribute — a badge that
    /// counts things the person has asked not to see is just a red dot they
    /// learn to ignore.
    var criticalAlertCount: Int {
        visibleAlerts.filter { $0.severity == .bad || $0.severity == .warn }.count
    }
}
