import XCTest
@testable import Vaktpost

/// Scheduling, not delivery.
///
/// `UNUserNotificationCenter` needs a real bundle, a real authorisation state
/// and a device before it says anything useful, so the decision of *what* to
/// schedule is a pure function over certificates and a date, and that is what
/// these cover. What they are guarding is a class of mistake that is invisible
/// until a notification arrives weeks later saying something untrue.
final class ExpiryNotificationTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    private func now() -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))!
    }

    private func certificate(_ descr: String, expiresInDays days: Int,
                             isCA: Bool = false, refID: String? = nil) -> CertificateInfo {
        let expiry = calendar.date(byAdding: .day, value: days, to: now())!
        let raw: [String: Any] = [
            "refid": refID ?? descr.lowercased(),
            "descr": descr,
            "valid_until": expiry.timeIntervalSince1970,
            "is_ca": isCA,
        ]
        let data = try! JSONSerialization.data(withJSONObject: raw)
        let value = try! JSONDecoder().decode(JSONValue.self, from: data)
        return CertificateInfo(JSONDict(value)!, isCA: isCA)
    }

    private func requests(_ certificates: [CertificateInfo],
                          server: String = "FW1") -> [ExpiryNotification] {
        ExpirySchedule.requests(for: certificates, serverID: server, serverName: "firewall",
                                now: now(), calendar: calendar)
    }

    func testSuccessfulEmptyCertificateRefreshStillReconciles() {
        XCTAssertTrue(ExpiryNotificationReconcilePolicy.shouldReconcile([], fetchError: nil))
    }

    func testFailedCertificateRefreshPreservesExistingSchedule() {
        XCTAssertFalse(ExpiryNotificationReconcilePolicy.shouldReconcile([], fetchError: "offline"))
    }

    // MARK: What gets scheduled

    func testAllFiveThresholdsAreScheduledForADistantExpiry() {
        let out = requests([certificate("web", expiresInDays: 90)])
        XCTAssertEqual(out.count, ExpirySchedule.thresholds.count)
    }

    func testOnlyThresholdsStillInTheFutureAreScheduled() {
        // A certificate ten days out has already passed its 30 and 14 day
        // marks. Scheduling them anyway would deliver both immediately the
        // first time this is switched on — every known expiry arriving at once
        // is how a person learns to swipe these away without reading.
        let out = requests([certificate("web", expiresInDays: 10)])
        XCTAssertEqual(out.map(\.id).sorted(),
                       ["cert.FW1.web.1", "cert.FW1.web.3", "cert.FW1.web.7"])
    }

    func testAnExpiredCertificateSchedulesNothing() {
        // The Alerts screen says so on every launch. A notification about it
        // would be a reminder of something that can no longer be prevented.
        XCTAssertTrue(requests([certificate("old", expiresInDays: -5)]).isEmpty)
    }

    func testACertificateWithNoExpiryDateSchedulesNothing() {
        let raw: [String: Any] = ["refid": "weird", "descr": "no dates"]
        let data = try! JSONSerialization.data(withJSONObject: raw)
        let value = try! JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertTrue(requests([CertificateInfo(JSONDict(value)!, isCA: false)]).isEmpty)
    }

    // MARK: Identity

    func testIdentifiersAreStableSoReschedulingReplaces() {
        // Adding a request with an identifier that is already pending replaces
        // it. That is what makes reconciling on every refresh safe, and it
        // only holds if the identifier does not change between refreshes.
        let first = requests([certificate("web", expiresInDays: 90)]).map(\.id)
        let second = requests([certificate("web", expiresInDays: 90)]).map(\.id)
        XCTAssertEqual(first, second)
    }

    func testIdentifiersAreNamespacedPerFirewall() {
        // Reconciling one firewall must not cancel another's pending
        // notifications. Somebody watching three firewalls has three sets, and
        // only one of them is the active profile at any moment.
        let a = requests([certificate("web", expiresInDays: 90)], server: "FW1")
        let b = requests([certificate("web", expiresInDays: 90)], server: "FW2")
        XCTAssertTrue(Set(a.map(\.id)).isDisjoint(with: Set(b.map(\.id))))
        XCTAssertTrue(a.allSatisfy { $0.id.hasPrefix(ExpirySchedule.prefix(forServer: "FW1")) })
        XCTAssertFalse(b.contains { $0.id.hasPrefix(ExpirySchedule.prefix(forServer: "FW1")) })
    }

    func testTwoCertificatesWithTheSameNameDoNotShareASchedule() {
        // The identity is the reference ID, not the description. pfSense does
        // not stop somebody calling two certificates the same thing, and one
        // silently replacing the other's notifications would mean the second
        // expiring unannounced.
        let out = requests([
            certificate("web", expiresInDays: 90, refID: "aaa"),
            certificate("web", expiresInDays: 40, refID: "bbb"),
        ])
        XCTAssertEqual(Set(out.map(\.id)).count, out.count)
    }

    // MARK: Reading a pending notification back

    func testAnIdentifierIsAttributedToItsFirewallAndThreshold() {
        // Parsed from the identifier rather than remembered, so a notification
        // can still be attributed after its firewall stops being the active
        // one — or after it is removed altogether.
        let parsed = ScheduledNotification(
            id: "cert.5F3A1C2D-0000-0000-0000-000000000001.abcdef.7",
            title: "web expires in 7 days", body: "Certificate on firewall.", fireAt: nil)
        XCTAssertEqual(parsed.serverID, "5F3A1C2D-0000-0000-0000-000000000001")
        XCTAssertEqual(parsed.daysBefore, 7)
    }

    func testACertificateReferenceContainingDotsStillParses() {
        // A pfSense reference is opaque and this app does not get to assume it
        // contains no dots. Both ends are read from the ends.
        let parsed = ScheduledNotification(
            id: "cert.FW1.some.ref.with.dots.30",
            title: "t", body: "b", fireAt: nil)
        XCTAssertEqual(parsed.serverID, "FW1")
        XCTAssertEqual(parsed.daysBefore, 30)
    }

    func testSomethingElseEntirelyIsNotAttributedToAnything() {
        // A notification scheduled by a future build, or something that is not
        // ours at all, should read as unattributed rather than as a firewall.
        let parsed = ScheduledNotification(id: "whatever", title: "t", body: "b", fireAt: nil)
        XCTAssertNil(parsed.serverID)
        XCTAssertNil(parsed.daysBefore)
    }

    func testEveryScheduledRequestParsesBackToItsFirewallAndThreshold() {
        // The round trip that matters: what the schedule produces has to be
        // readable by the screen that lists it.
        for notification in requests([certificate("web", expiresInDays: 90)]) {
            let parsed = ScheduledNotification(id: notification.id, title: notification.title,
                                               body: notification.body, fireAt: notification.fireAt)
            XCTAssertEqual(parsed.serverID, "FW1")
            XCTAssertTrue(ExpirySchedule.thresholds.contains(parsed.daysBefore ?? -1))
        }
    }

    // MARK: When and what it says

    func testNotificationsFireAtNineInTheMorning() {
        // A certificate expiry is a working problem. The same information at
        // three in the morning is a worse version of it.
        for notification in requests([certificate("web", expiresInDays: 90)]) {
            XCTAssertEqual(calendar.component(.hour, from: notification.fireAt),
                           ExpirySchedule.hour)
        }
    }

    func testEachNotificationLandsTheRightNumberOfDaysBefore() {
        let expiry = calendar.date(byAdding: .day, value: 90, to: now())!
        for notification in requests([certificate("web", expiresInDays: 90)]) {
            let days = Int(notification.id.split(separator: ".").last!)!
            let gap = calendar.dateComponents([.day],
                                              from: calendar.startOfDay(for: notification.fireAt),
                                              to: calendar.startOfDay(for: expiry)).day
            XCTAssertEqual(gap, days)
        }
    }

    func testTheFirewallIsNamedInTheBody() {
        // A notification is read away from the app that could have said which
        // firewall it was about.
        let out = requests([certificate("web", expiresInDays: 90)])
        XCTAssertTrue(out.allSatisfy { $0.body.contains("firewall") })
    }

    func testACertificateAuthoritySaysSo() {
        let ca = requests([certificate("internal-ca", expiresInDays: 90, isCA: true)])
        XCTAssertTrue(ca.allSatisfy { $0.body.hasPrefix("CA certificate") })
        let leaf = requests([certificate("web", expiresInDays: 90)])
        XCTAssertTrue(leaf.allSatisfy { $0.body.hasPrefix("Certificate") })
    }

    func testTheLastWarningReadsAsTomorrowRatherThanOneDays() {
        let out = requests([certificate("web", expiresInDays: 90)])
        let final = out.first { $0.id.hasSuffix(".1") }
        XCTAssertEqual(final?.title, "web expires tomorrow")
    }

    func testTheScheduleIsOrderedByWhenItFires() {
        let out = requests([
            certificate("a", expiresInDays: 90, refID: "a"),
            certificate("b", expiresInDays: 20, refID: "b"),
        ])
        XCTAssertEqual(out.map(\.fireAt), out.map(\.fireAt).sorted())
    }
}
