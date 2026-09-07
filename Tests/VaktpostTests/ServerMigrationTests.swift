import XCTest
@testable import Vaktpost
import Security

/// Regression test for the migration from the legacy single-server layout
/// (where `ServerProfile` and its API key were stored under hardcoded keys)
/// to the multi-firewall layout backed by `servers.list`.
///
/// The profile still migrates. The credential deliberately does not: a REST
/// API key is not a webConfigurator password, and carrying it across would
/// produce a 401 that looks like a wrong password rather than a prompt for the
/// thing now required.
final class ServerMigrationTests: XCTestCase {

    private let listKey = "servers.list"
    private let activeKey = "servers.active"
    private let legacyProfileKey = "server.profile"
    private let service = "se.kladhest.vaktpost.apikey"

    /// An isolated store, one per test.
    ///
    /// These tests used `UserDefaults.standard`, which in a host-app test
    /// bundle is the app's own defaults on that simulator. "The registry starts
    /// clean when nothing is stored" then passed on a fresh simulator and
    /// failed on one where a firewall had been configured — the test was
    /// reading the real profile. A test whose result depends on the state of
    /// the machine running it is worse than no test.
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "vaktpost.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        super.tearDown()
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        Keychain.deleteLegacy()
        deleteKeychainItem(account: "default")
    }

    private func deleteKeychainItem(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// When a single-server profile exists under the old key, `ServerRegistry`
    /// migrates it into the multi-firewall list and moves the keychain item.
    func testLegacyProfileIsMigratedToList() async throws {
        let legacyProfile = ServerProfile(
            baseURL: "https://firewall.example",
            label: "Test firewall",
            refreshSeconds: 30
        )
        let profileData = try! JSONEncoder().encode(legacyProfile)
        defaults.set(profileData, forKey: legacyProfileKey)

        // Store a legacy keychain item under the "default" account used by old versions.
        guard let data = "legacy-key-123".data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "default",
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)

        await MainActor.run {
            _ = ServerRegistry(defaults: defaults)
        }

        // The old key should be gone.
        XCTAssertNil(defaults.data(forKey: legacyProfileKey))

        // The multi-firewall list should contain exactly one server.
        //
        // `XCTUnwrap` rather than a force unwrap: when this was `listData!`
        // the test did not fail, it crashed — taking the whole run with it and
        // producing a macOS crash report instead of a test result. A failing
        // assertion tells you which expectation was wrong; a crash tells you
        // nothing and hides every test that would have run after it.
        let listData = try XCTUnwrap(defaults.data(forKey: listKey))
        let servers = try JSONDecoder().decode([ServerProfile].self, from: listData)
        XCTAssertEqual(servers.count, 1)
        XCTAssertEqual(servers[0].baseURL, "https://firewall.example")
        XCTAssertEqual(servers[0].label, "Test firewall")

        // The keychain item should have been migrated.
        XCTAssertEqual(Keychain.password(for: servers[0].id), nil)
        XCTAssertNil(Keychain.legacyAPIKey())

        // The registry should pick it up as active.
        await MainActor.run {
            let registry = ServerRegistry(defaults: defaults)
            XCTAssertEqual(registry.active?.id, servers[0].id)
        }
    }

    /// When no legacy profile exists but the list is present, the registry
    /// uses it as-is.
    func testExistingListIsUsedWithoutMigration() async {
        let profile = ServerProfile(baseURL: "https://new.example", label: "New")
        let list = [profile]
        let listData = try! JSONEncoder().encode(list)
        defaults.set(listData, forKey: listKey)

        await MainActor.run {
            let registry = ServerRegistry(defaults: defaults)
            XCTAssertEqual(registry.servers.count, 1)
            XCTAssertEqual(registry.active?.baseURL, "https://new.example")
        }
    }

    /// When neither legacy nor new data exists, the registry starts clean.
    func testEmptyStateProducesNoServers() async {
        await MainActor.run {
            let registry = ServerRegistry(defaults: defaults)
            XCTAssertTrue(registry.servers.isEmpty)
            XCTAssertNil(registry.active)
        }
    }

    /// A legacy profile with a malformed URL is not migrated.
    func testMalformedLegacyProfileIsSkipped() async {
        var badProfile = ServerProfile(baseURL: "not a url", label: "Bad")
        badProfile.normalize() // won't help — no host
        let profileData = try! JSONEncoder().encode(badProfile)
        defaults.set(profileData, forKey: legacyProfileKey)

        await MainActor.run {
            _ = ServerRegistry(defaults: defaults)
        }

        // The legacy key is still there (migration was skipped).
        XCTAssertNotNil(defaults.data(forKey: legacyProfileKey))
    }
}
