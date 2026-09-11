import XCTest
@testable import Vaktpost

/// The dashboard layout is persisted as raw strings, which makes renaming or
/// splitting a section a migration rather than an edit. An unknown stored name
/// is silently dropped, so getting this wrong does not fail loudly — it just
/// removes a section from somebody's dashboard.
@MainActor
final class OverviewSectionTests: XCTestCase {

    // MARK: The layout end to end, through the registry
    //
    // The pure migration tests below prove the names come out right. These
    // prove the thing actually asked for: that one section can be hidden
    // without taking another with it, all the way through storage.

    private func registry(_ stored: [String]) -> (ServerRegistry, ServerProfile) {
        let suite = "vaktpost.sections.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }

        let registry = ServerRegistry(defaults: defaults)
        var profile = ServerProfile()
        profile.label = "test"
        profile.baseURL = "https://192.0.2.1"
        profile.overviewVisibleSections = stored
        registry.upsert(profile)
        return (registry, profile)
    }

    private func stored(_ registry: ServerRegistry, _ profile: ServerProfile) -> [String] {
        registry.servers.first { $0.id == profile.id }?.overviewVisibleSections ?? []
    }

    func testHidingOneVPNSectionLeavesTheOther() {
        let (registry, profile) = registry(["status", "vpnServers", "vpnClients"])
        registry.setOverviewSectionVisibility(profile, .vpnServers, visible: false)
        XCTAssertEqual(stored(registry, profile), ["status", "vpnClients"])
    }

    func testHidingOneAndAddingAnotherDoesNotBringItBack() {
        // The reported symptom: unhiding Status also unhid both VPN sections.
        let (registry, profile) = registry(["vpnServers", "vpnClients"])
        registry.setOverviewSectionVisibility(profile, .vpnServers, visible: false)
        registry.setOverviewSectionVisibility(profile, .status, visible: true)

        let names = stored(registry, profile)
        XCTAssertFalse(names.contains("vpnServers"), "hidden stays hidden")
        XCTAssertTrue(names.contains("vpnClients"))
        XCTAssertTrue(names.contains("status"))
    }

    func testALegacyLayoutMigratesOnceAndThenBehavesIndependently() {
        // A profile stored by the build that had one combined VPN section.
        // After the rewrite, the two behave like any other pair.
        let (registry, profile) = registry(["status", "vpn"])

        let migrated = OverviewSection.migrate(storedNames: stored(registry, profile))!
        registry.setOverviewSectionNames(profile, migrated)
        XCTAssertEqual(stored(registry, profile), ["status", "vpnServers", "vpnClients"])

        registry.setOverviewSectionVisibility(profile, .vpnClients, visible: false)
        XCTAssertEqual(stored(registry, profile), ["status", "vpnServers"])

        // And nothing reintroduces the old name, so nothing expands again.
        XCTAssertNil(OverviewSection.migrate(storedNames: stored(registry, profile)))
    }

    func testHidingEverythingThenAddingOneAddsOnlyThatOne() {
        let (registry, profile) = registry(["status", "vpnServers", "vpnClients", "clients"])
        for section in OverviewSection.allCases {
            registry.setOverviewSectionVisibility(profile, section, visible: false)
        }
        XCTAssertTrue(stored(registry, profile).isEmpty)

        registry.setOverviewSectionVisibility(profile, .status, visible: true)
        XCTAssertEqual(stored(registry, profile), ["status"])
    }


    func testTheOldVPNSectionBecomesBothOfItsReplacements() {
        // Dropping it would have taken VPN off the dashboard of everybody who
        // had it, and put the two new sections in the hidden list where they
        // would have to be found and re-added by hand.
        XCTAssertEqual(OverviewSection.replacing("vpn"), [.vpnServers, .vpnClients])
    }

    func testASectionThatStillExistsIsNotReplaced() {
        // Only names that no longer exist get mapped. A live one must go
        // through the ordinary initialiser or it would be duplicated.
        for section in OverviewSection.allCases {
            XCTAssertNil(OverviewSection.replacing(section.rawValue),
                         "\(section.rawValue) is a current section and needs no replacement")
        }
    }

    func testAnUnrecognisedNameMapsToNothing() {
        XCTAssertNil(OverviewSection.replacing("somethingelse"))
    }

    // MARK: Writing the migration back

    func testTheStoredLayoutIsRewrittenWhenItHoldsAnOldName() {
        // The bug: expanding `vpn` at read time and leaving it in storage.
        // Hiding VPN servers removed `vpnServers`, which was never stored;
        // `vpn` stayed, and the next load expanded it again — so both VPN
        // sections came back the moment anything else was added.
        XCTAssertEqual(OverviewSection.migrate(storedNames: ["status", "vpn", "clients"]),
                       ["status", "vpnServers", "vpnClients", "clients"])
    }

    func testALayoutWithNothingToMigrateIsLeftAlone() {
        // Returning a value here would write on every appearance, for nothing.
        XCTAssertNil(OverviewSection.migrate(storedNames: ["status", "vpnServers", "clients"]))
        XCTAssertNil(OverviewSection.migrate(storedNames: []))
    }

    func testAnOldNameBesideItsReplacementDoesNotDuplicateIt() {
        XCTAssertEqual(OverviewSection.migrate(storedNames: ["vpn", "vpnServers"]),
                       ["vpnServers", "vpnClients"])
    }

    func testDuplicatesAreCollapsedAndCountAsAChange() {
        XCTAssertEqual(OverviewSection.migrate(storedNames: ["status", "status"]), ["status"])
    }

    func testANameThisBuildDoesNotKnowIsKeptRatherThanDeleted() {
        // It cannot be displayed, but it belongs to whoever stored it. A build
        // that knows about it should still find it after this one has run.
        XCTAssertEqual(OverviewSection.migrate(storedNames: ["vpn", "somethingfuture"]),
                       ["vpnServers", "vpnClients", "somethingfuture"])
    }

    func testMigrationIsIdempotent() {
        // It runs on every appearance. A second pass must find nothing, or the
        // layout is rewritten forever.
        let once = OverviewSection.migrate(storedNames: ["status", "vpn"])
        XCTAssertNotNil(once)
        XCTAssertNil(OverviewSection.migrate(storedNames: once!))
    }

    func testMigratingAStoredLayoutKeepsItsOrderAndDoesNotDuplicate() {
        // The same walk the view does: replacements expand in place, current
        // names pass through, and nothing appears twice — a layout that
        // already contained one of the replacements alongside the old name
        // would otherwise render it twice.
        let stored = ["status", "vpn", "vpnServers", "interfaces", "nonsense"]
        let migrated = OverviewSection.migrate(storedNames: stored) ?? stored

        // What the view renders: the migrated names, minus the one it cannot
        // map, in stored order and without repeats.
        var seen = Set<OverviewSection>()
        let resolved = migrated
            .compactMap(OverviewSection.init(rawValue:))
            .filter { seen.insert($0).inserted }

        XCTAssertEqual(resolved, [.status, .vpnServers, .vpnClients, .interfaces])
        XCTAssertTrue(migrated.contains("nonsense"), "kept in storage, just not shown")
    }

    func testEverySectionHasANameAndASymbol() {
        // Both are exhaustive switches, so a case added without them does not
        // compile — but an empty string would, and reads as a gap on screen.
        for section in OverviewSection.allCases {
            XCTAssertFalse(section.displayName.isEmpty, "\(section.rawValue) has no name")
            XCTAssertFalse(section.symbol.isEmpty, "\(section.rawValue) has no symbol")
        }
    }

    func testTheTwoVPNSectionsAreDistinct() {
        XCTAssertNotEqual(OverviewSection.vpnServers.displayName,
                          OverviewSection.vpnClients.displayName)
        XCTAssertNotEqual(OverviewSection.vpnServers.symbol,
                          OverviewSection.vpnClients.symbol)
    }
}
