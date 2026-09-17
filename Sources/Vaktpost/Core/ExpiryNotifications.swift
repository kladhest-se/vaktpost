import Foundation
import Observation
import UserNotifications

enum ExpiryNotificationReconcilePolicy {
    /// An empty successful result is meaningful: it removes notifications for
    /// certificates that no longer exist. Only a failed fetch lacks enough
    /// information to change the existing schedule safely.
    static func shouldReconcile(_ certificates: [CertificateInfo], fetchError: String?) -> Bool {
        fetchError == nil
    }
}

/// One notification the app intends to have delivered.
///
/// Kept as a value type so the decision of *what* to schedule can be made and
/// tested without touching `UNUserNotificationCenter`, which needs a real
/// bundle, a real authorisation state and a device to say anything useful.
struct ExpiryNotification: Equatable, Identifiable {
    let id: String
    let fireAt: Date
    let title: String
    let body: String
}

/// What to schedule for a set of certificates, and when.
///
/// This is the whole reason certificate expiry works as a notification when
/// most of what this app knows does not: an expiry date is known in advance.
/// Everything else on the Alerts screen — a gateway down, a disk filling — is
/// only knowable by asking the firewall, and an app that is not running cannot
/// ask. A certificate says months ahead exactly when it will become a problem,
/// so the notification can be scheduled then and delivered whether or not this
/// app is ever opened again.
///
/// That is also the constraint. These fire on a date, not on a condition. A
/// certificate renewed the day after one is scheduled would still announce
/// itself unless the schedule is reconciled, which is why the caller removes
/// and rebuilds rather than only adding.
enum ExpirySchedule {

    /// Days before expiry at which to say something.
    ///
    /// Spaced so that the first is early enough to renew unhurriedly and the
    /// last is late enough to be alarming. A daily reminder for a month would
    /// be trained away long before it mattered.
    static let thresholds = [30, 14, 7, 3, 1]

    /// When on the day to deliver.
    ///
    /// Nine in the morning, local time. A certificate expiry is a working
    /// problem and a notification at three in the morning is a worse version
    /// of the same information.
    static let hour = 9

    /// Everything worth scheduling for one firewall's certificates.
    ///
    /// Identifiers are namespaced by server so several firewalls can hold
    /// pending notifications at once and reconciling one never cancels
    /// another's. They are stable for a given certificate and threshold, so
    /// rescheduling replaces rather than duplicates.
    ///
    /// Only future dates are returned. A threshold already passed cannot be
    /// scheduled, and delivering it immediately would mean every already-known
    /// expiry arriving at once the first time this is switched on.
    static func requests(for certificates: [CertificateInfo],
                         serverID: String,
                         serverName: String,
                         now: Date = Date(),
                         calendar: Calendar = .current) -> [ExpiryNotification] {
        var out: [ExpiryNotification] = []

        for certificate in certificates {
            guard let expiry = certificate.validUntil else { continue }
            // Already expired. The Alerts screen says so every time the app is
            // opened; a notification about it would be a reminder of something
            // that can no longer be prevented.
            guard expiry > now else { continue }

            let kind = certificate.isCA ? "CA certificate" : "Certificate"

            for days in thresholds {
                guard let fireDay = calendar.date(byAdding: .day, value: -days, to: expiry),
                      let fireAt = calendar.date(bySettingHour: hour, minute: 0, second: 0,
                                                 of: fireDay),
                      fireAt > now
                else { continue }

                out.append(ExpiryNotification(
                    id: "cert.\(serverID).\(certificate.id).\(days)",
                    fireAt: fireAt,
                    title: days == 1
                        ? "\(certificate.descr) expires tomorrow"
                        : "\(certificate.descr) expires in \(days) days",
                    // The firewall is named because somebody watching three of
                    // them needs to know which one to log into, and a
                    // notification is read away from the app that could say.
                    body: "\(kind) on \(serverName)."
                ))
            }
        }

        return out.sorted { $0.fireAt < $1.fireAt }
    }

    /// The prefix every identifier for one server shares.
    static func prefix(forServer serverID: String) -> String { "cert.\(serverID)." }
}

/// A notification iOS is holding, as it can be read back.
///
/// Read back rather than remembered. What this app intended to schedule and
/// what iOS is actually holding are two different things — a request can be
/// dropped for exceeding the 64-notification limit, and one scheduled by an
/// older build can outlive the code that made it. A screen built from the
/// app's own intentions would agree with itself and tell you nothing.
struct ScheduledNotification: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    /// When iOS will deliver it, or nil if the trigger cannot be read back as
    /// a date.
    let fireAt: Date?
    /// Parsed out of the identifier, so a notification can be attributed to a
    /// firewall even after that firewall stops being the active one.
    let serverID: String?
    let daysBefore: Int?

    /// `cert.<serverID>.<certificate>.<days>`.
    ///
    /// Parsed defensively from both ends: a certificate reference is opaque
    /// and this app does not get to assume it contains no dots.
    init(id: String, title: String, body: String, fireAt: Date?) {
        self.id = id
        self.title = title
        self.body = body
        self.fireAt = fireAt

        let parts = id.split(separator: ".").map(String.init)
        if parts.count >= 4, parts[0] == "cert" {
            serverID = parts[1]
            daysBefore = Int(parts[parts.count - 1])
        } else {
            serverID = nil
            daysBefore = nil
        }
    }
}

/// Schedules the notifications `ExpirySchedule` decides on.
///
/// Off until switched on, and authorisation is requested at that moment rather
/// than at launch. A permission prompt on first run, before the app has shown
/// what it would use it for, is the reliable way to be refused permanently.
@MainActor
@Observable
final class ExpiryNotifier {

    enum Permission {
        case unknown
        case granted
        /// Refused, or turned off later in iOS Settings. The app cannot
        /// re-ask; only Settings can grant it back, and saying so is more use
        /// than a toggle that silently does nothing.
        case denied
    }

    private enum UDKey: String {
        case enabled = "notifications.certificateExpiry"
    }

    private let defaults: UserDefaults
    private let center: UNUserNotificationCenter?

    var permission: Permission = .unknown

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: UDKey.enabled.rawValue)
            if !isEnabled { Task { await cancelEverything() } }
        }
    }

    /// `center` is optional so tests can construct this without a notification
    /// centre, which needs a real bundle to exist at all.
    init(defaults: UserDefaults = .standard, center: UNUserNotificationCenter? = .current()) {
        self.defaults = defaults
        self.center = center
        self.isEnabled = defaults.bool(forKey: UDKey.enabled.rawValue)
    }

    /// Ask for permission, and report what was decided.
    ///
    /// Called from the toggle, not from launch.
    func requestPermission() async {
        guard let center else { return }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            permission = granted ? .granted : .denied
            if !granted { isEnabled = false }
        } catch {
            permission = .denied
            isEnabled = false
        }
    }

    /// Read the current state without prompting.
    func refreshPermission() async {
        guard let center else { return }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: permission = .granted
        case .denied: permission = .denied
        case .notDetermined: permission = .unknown
        @unknown default: permission = .unknown
        }
    }

    /// Bring the pending notifications in line with what these certificates
    /// now say.
    ///
    /// Remove-then-add rather than add-only, and scoped to this server's
    /// prefix. A renewed certificate has a new expiry and its old schedule is
    /// now a lie; a deleted one should stop announcing itself. Without the
    /// removal, renewing a certificate would leave its "expires in 7 days"
    /// pending and it would arrive on time, for a certificate that was
    /// replaced a month earlier.
    func reconcile(certificates: [CertificateInfo],
                   serverID: String,
                   serverName: String,
                   now: Date = Date()) async {
        guard let center, isEnabled, permission == .granted else { return }

        let wanted = ExpirySchedule.requests(for: certificates,
                                             serverID: serverID,
                                             serverName: serverName,
                                             now: now)

        let prefix = ExpirySchedule.prefix(forServer: serverID)
        let wantedIDs = Set(wanted.map(\.id))
        let pending = await center.pendingNotificationRequests()
        // A set rather than a nested `contains`: this runs once per refresh
        // over every pending request on the device, and the nested form also
        // put a `$0` inside a closure that had its own explicit argument,
        // which does not compile.
        let stale = pending.map(\.identifier)
            .filter { $0.hasPrefix(prefix) && !wantedIDs.contains($0) }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }

        for notification in wanted {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = .default

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: notification.fireAt)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

            // Adding with an identifier that is already pending replaces it,
            // which is what makes this safe to run on every refresh.
            try? await center.add(UNNotificationRequest(identifier: notification.id,
                                                        content: content,
                                                        trigger: trigger))
        }
    }

    /// Everything this app scheduled, for every firewall.
    ///
    /// Used when the feature is switched off. Scoped to the certificate prefix
    /// so it cannot remove something another part of the app scheduled later.
    func cancelEverything() async {
        guard let center else { return }
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix("cert.") }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }

    /// Everything this app has pending, soonest first.
    ///
    /// The screen showing these is the only way to tell whether reconciling is
    /// behaving. A count says something is scheduled; it cannot say whether
    /// what is scheduled is still true — a renewed certificate leaving a stale
    /// "expires in 7 days" behind looks identical to a correct one until you
    /// read the date on it.
    func pending() async -> [ScheduledNotification] {
        guard let center else { return [] }
        return await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix("cert.") }
            .map { request in
                ScheduledNotification(
                    id: request.identifier,
                    title: request.content.title,
                    body: request.content.body,
                    fireAt: (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
                )
            }
            .sorted { lhs, rhs in
                switch (lhs.fireAt, rhs.fireAt) {
                case let (l?, r?): return l < r
                // A trigger that will not resolve to a date sorts last. It is
                // the one worth looking at, and burying it at the top of a
                // list of ordinary ones would be worse.
                case (nil, _?): return false
                case (_?, nil): return true
                case (nil, nil): return lhs.id < rhs.id
                }
            }
    }

    /// What is currently scheduled, for the Settings screen to report.
    func pendingCount() async -> Int {
        await pending().count
    }
}
