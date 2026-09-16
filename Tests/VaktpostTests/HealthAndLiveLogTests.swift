import XCTest
@testable import Vaktpost

final class HealthAndLiveLogTests: XCTestCase {
    private let ipv4Line = LogLine(
        text: "Sep 16 20:00:00 fw filterlog[42]: 0,,,1000,igb0,match,block,in,4,0x0,,64,1,0,DF,6,tcp,60,192.0.2.10,198.51.100.20,51515,443,0,S",
        kind: .firewall
    )

    func testRawFilterCSVAndPrefixedCSVAreBothParsed() throws {
        let prefixed = try XCTUnwrap(ipv4Line.filterFields)
        XCTAssertEqual(prefixed.interfaceName, "igb0")
        XCTAssertEqual(ipv4Line.source, "192.0.2.10")
        XCTAssertEqual(ipv4Line.destination, "198.51.100.20")
        XCTAssertEqual(ipv4Line.proto, "tcp")

        let raw = LogLine(text: "0,,,1000,igb0,match,pass,in,4,0x0,,64,1,0,DF,17,udp,60,192.0.2.1,198.51.100.2,53,53000",
                          kind: .firewall)
        XCTAssertEqual(raw.filterFields?.action, "pass")
        XCTAssertEqual(raw.filterFields?.destinationPort, "53000")
    }

    func testStructuredFirewallFiltersComposeAndMalformedLinesRemainSafe() {
        let filter = FirewallLogFilter(query: "198.51", action: "block",
                                       interfaceName: "igb0", proto: "tcp",
                                       source: "192.0.2", destination: "100.20", port: "443")
        XCTAssertTrue(filter.matches(ipv4Line))
        var wrongPort = filter
        wrongPort.port = "22"
        XCTAssertFalse(wrongPort.matches(ipv4Line))
        XCTAssertFalse(filter.matches(LogLine(text: "partial,filter,line", kind: .firewall)))
    }

    func testRulePrefillIsDisabledStagedAndFamilyAware() throws {
        let form = try RuleEditForm.prefilled(from: ipv4Line, interface: "wan")
        XCTAssertTrue(form.isCreating)
        XCTAssertTrue(form.disabled)
        XCTAssertTrue(form.logged)
        XCTAssertEqual(form.type, "pass")
        XCTAssertEqual(form.interface, "wan")
        XCTAssertEqual(form.addressFamily, "inet")
        XCTAssertEqual(form.sourceAddress, "192.0.2.10")
        XCTAssertEqual(form.destinationAddress, "198.51.100.20")
        XCTAssertEqual(form.destinationPort, "443")
        XCTAssertEqual(form.placementTarget, .last)
    }

    func testRulePrefillRefusesOutboundAndUnknownInterfaces() {
        let outbound = LogLine(
            text: "0,,,1000,igb0,match,block,out,4,0x0,,64,1,0,DF,6,tcp,60,192.0.2.10,198.51.100.20,51515,443",
            kind: .firewall
        )
        XCTAssertThrowsError(try RuleEditForm.prefilled(from: outbound, interface: "wan")) {
            XCTAssertEqual($0 as? RuleEditForm.LogPrefillError, .outboundDirection)
        }
        XCTAssertThrowsError(try RuleEditForm.prefilled(from: ipv4Line, interface: nil)) {
            XCTAssertEqual($0 as? RuleEditForm.LogPrefillError, .missingInterface)
        }
    }

    func testCertificateExpiryAndPinStatesUseAStableClock() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func observation(days: Int) -> CertificateObservation {
            CertificateObservation(fingerprint: String(repeating: "ab", count: 32),
                                   subject: "fw.example", issuer: "CN=Local CA",
                                   validFrom: now.addingTimeInterval(-86_400),
                                   validUntil: now.addingTimeInterval(Double(days) * 86_400),
                                   systemTrusted: false, observedAt: now)
        }
        XCTAssertEqual(observation(days: 90).expiryState(now: now), .valid(daysRemaining: 90))
        XCTAssertEqual(observation(days: 20).expiryState(now: now), .expiringSoon(daysRemaining: 20))
        XCTAssertEqual(observation(days: 5).expiryState(now: now), .critical(daysRemaining: 5))
        XCTAssertTrue(observation(days: 90).matches(pin: String(repeating: "AB:", count: 31) + "AB"))
    }

    func testFleetHealthAggregationDoesNotInventUnavailableValues() {
        let unknown = FleetReading()
        XCTAssertFalse(unknown.needsAttention)
        XCTAssertEqual(unknown.stateUsage, 0)

        let pressure = FleetReading(firewallStatesCurrent: 9_100, firewallStatesMaximum: 10_000)
        XCTAssertTrue(pressure.needsAttention)
        XCTAssertEqual(pressure.stateUsage, 0.91, accuracy: 0.001)
        XCTAssertTrue(FleetReading(firmwareUpdateAvailable: true).needsAttention)
    }

    func testLiveLogPollingIsBounded() {
        XCTAssertEqual(FirewallLogPollPolicy.interval(profileRefreshSeconds: 1), 10)
        XCTAssertEqual(FirewallLogPollPolicy.interval(profileRefreshSeconds: 20), 20)
        XCTAssertEqual(FirewallLogPollPolicy.interval(profileRefreshSeconds: 300), 30)
        XCTAssertEqual(FirewallLogPollPolicy.interval(profileRefreshSeconds: 10, consecutiveFailures: 2), 20)
        XCTAssertEqual(FirewallLogPollPolicy.interval(profileRefreshSeconds: 30, consecutiveFailures: 8), 300)
    }

    func testRepeatedLogSnapshotsKeepIdentityAndCountOnlyNewOccurrences() {
        let duplicateA = LogLine(text: "same", kind: .firewall)
        let duplicateB = LogLine(text: "same", kind: .firewall)
        let old = LogLine(text: "old", kind: .firewall)
        let incoming = [
            LogLine(text: "new", kind: .firewall),
            LogLine(text: "same", kind: .firewall),
            LogLine(text: "same", kind: .firewall),
            LogLine(text: "old", kind: .firewall)
        ]

        let result = LogSnapshotMerge.merge(previous: [duplicateA, duplicateB, old], incoming: incoming)

        XCTAssertEqual(result.newCount, 1)
        XCTAssertEqual(result.lines.dropFirst().map(\.id), [duplicateA.id, duplicateB.id, old.id])
    }

    func testRedactedLogExportRemovesAddressesAndPortsWithoutChangingFullExport() {
        let full = LogExport.text(for: [ipv4Line], redacted: false)
        let redacted = LogExport.text(for: [ipv4Line], redacted: true)

        XCTAssertTrue(full.contains("192.0.2.10"))
        XCTAssertTrue(full.contains("51515"))
        XCTAssertFalse(redacted.contains("192.0.2.10"))
        XCTAssertFalse(redacted.contains("198.51.100.20"))
        XCTAssertFalse(redacted.contains("51515"))
        XCTAssertFalse(redacted.contains(",443,"))
        XCTAssertTrue(redacted.contains("<address>"))
        XCTAssertTrue(redacted.contains("<port>"))
    }

    func testTLSRecoveryNeverSuggestsBypassingTrust() throws {
        let suggestion = try XCTUnwrap(WriteErrorFormatter.suggestion(for: RPCError.tls))
        XCTAssertTrue(suggestion.contains("SHA-256"))
        XCTAssertTrue(suggestion.contains("separate trusted path"))
        XCTAssertFalse(suggestion.localizedCaseInsensitiveContains("untrusted TLS"))
    }

    func testHTTPSValidationRejectsCredentialAndPathSmuggling() {
        XCTAssertTrue(ServerProfile(baseURL: "https://fw.example:8443").isConfigured)
        XCTAssertFalse(ServerProfile(baseURL: "http://fw.example").isConfigured)
        XCTAssertFalse(ServerProfile(baseURL: "https://user:pass@fw.example").isConfigured)
        XCTAssertFalse(ServerProfile(baseURL: "https://fw.example/admin").isConfigured)
        XCTAssertFalse(ServerProfile(baseURL: "https://fw.example?next=http://evil").isConfigured)
    }

    @MainActor
    func testLegacyUntrustedTLSPreferenceIsNeutralizedOnLoad() throws {
        let suite = "vaktpost.tls-migration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var legacy = ServerProfile(baseURL: "https://fw.example/")
        legacy.allowUntrustedTLS = true
        defaults.set(try JSONEncoder().encode([legacy]), forKey: "servers.list")

        let registry = ServerRegistry(defaults: defaults)

        XCTAssertFalse(try XCTUnwrap(registry.servers.first).allowUntrustedTLS)
        XCTAssertEqual(registry.servers.first?.baseURL, "https://fw.example")
    }

    @MainActor
    func testCertificateObservationsStayIsolatedPerFirewall() {
        let suite = "vaktpost.cert-isolation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = ServerProfile(baseURL: "https://first.example")
        let second = ServerProfile(baseURL: "https://second.example")
        let registry = ServerRegistry(defaults: defaults)
        registry.upsert(first)
        registry.upsert(second)
        let observation = CertificateObservation(
            fingerprint: String(repeating: "01", count: 32), subject: "first.example",
            issuer: nil, validFrom: nil, validUntil: nil,
            systemTrusted: true, observedAt: Date()
        )
        registry.observeCertificate(observation, for: first)
        XCTAssertEqual(registry.servers.first { $0.id == first.id }?.certificateObservation,
                       observation)
        XCTAssertNil(registry.servers.first { $0.id == second.id }?.certificateObservation)
    }

    @MainActor
    func testFleetRequiresTwoTransientHealthSamplesButShowsUpdatesImmediately() async {
        let profile = ServerProfile(baseURL: "https://fw.example")
        let store = FleetStore { _ in FleetReading(memoryUsage: 95) }

        await store.refresh([profile])
        XCTAssertFalse(try XCTUnwrap(store.snapshots[profile.id]).needsAttention)
        XCTAssertTrue(try XCTUnwrap(store.snapshots[profile.id]).isConfirmingIssue)

        await store.refresh([profile])
        XCTAssertTrue(try XCTUnwrap(store.snapshots[profile.id]).needsAttention)

        let updates = FleetStore { _ in FleetReading(packageUpdates: 1) }
        await updates.refresh([profile])
        XCTAssertTrue(try XCTUnwrap(updates.snapshots[profile.id]).needsAttention)
    }

    @MainActor
    func testFleetConfirmsOutageAndAutomaticBackoffCanBeBypassedManually() async throws {
        enum Failure: Error { case offline }
        let profile = ServerProfile(baseURL: "https://fw.example")
        let clock = Date(timeIntervalSince1970: 2_000)
        let store = FleetStore(now: { clock }) { _ in throw Failure.offline }

        await store.refresh([profile])
        let first = try XCTUnwrap(store.snapshots[profile.id])
        XCTAssertNil(first.failure)
        XCTAssertEqual(first.consecutiveFailures, 1)
        XCTAssertEqual(first.nextAutomaticAttempt, clock.addingTimeInterval(10))

        await store.refresh([profile], automatic: true)
        XCTAssertEqual(store.snapshots[profile.id]?.consecutiveFailures, 1)

        await store.refresh([profile])
        let confirmed = try XCTUnwrap(store.snapshots[profile.id])
        XCTAssertNotNil(confirmed.failure)
        XCTAssertEqual(confirmed.consecutiveFailures, 2)
        XCTAssertEqual(confirmed.nextAutomaticAttempt, clock.addingTimeInterval(20))
    }
}
