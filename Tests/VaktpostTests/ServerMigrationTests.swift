import XCTest
@testable import Vaktpost
import Security

/// Regression test for the migration from the legacy single-server layout
/// (where `ServerProfile` and its API key were stored under hardcoded keys)
/// to the multi-firewall layout backed by `servers.list`.
final class ServerMigrationTests: XCTestCase {

    private let listKey = "servers.list"
    private let activeKey = "servers.active"
    private let legacyProfileKey = "server.profile"
    private let service = "se.kladhest.vaktpost.apikey"

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: listKey)
        UserDefaults.standard.removeObject(forKey: activeKey)
        UserDefaults.standard.removeObject(forKey: legacyProfileKey)
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
    func testLegacyProfileIsMigratedToList() async {
        let legacyProfile = ServerProfile(
            baseURL: "https://firewall.example",
            label: "Test firewall",
            refreshSeconds: 30
        )
        let profileData = try! JSONEncoder().encode(legacyProfile)
        UserDefaults.standard.set(profileData, forKey: legacyProfileKey)

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
            _ = ServerRegistry()
        }

        // The old key should be gone.
        XCTAssertNil(UserDefaults.standard.data(forKey: legacyProfileKey))

        // The multi-firewall list should contain exactly one server.
        let listData = UserDefaults.standard.data(forKey: listKey)
        XCTAssertNotNil(listData)
        let servers = try! JSONDecoder().decode([ServerProfile].self, from: listData!)
        XCTAssertEqual(servers.count, 1)
        XCTAssertEqual(servers[0].baseURL, "https://firewall.example")
        XCTAssertEqual(servers[0].label, "Test firewall")

        // The keychain item should have been migrated.
        XCTAssertEqual(Keychain.apiKey(for: servers[0].id), "legacy-key-123")
        XCTAssertNil(Keychain.legacyAPIKey())

        // The registry should pick it up as active.
        await MainActor.run {
            let registry = ServerRegistry()
            XCTAssertEqual(registry.active?.id, servers[0].id)
        }
    }

    /// When no legacy profile exists but the list is present, the registry
    /// uses it as-is.
    func testExistingListIsUsedWithoutMigration() async {
        let profile = ServerProfile(baseURL: "https://new.example", label: "New")
        let list = [profile]
        let listData = try! JSONEncoder().encode(list)
        UserDefaults.standard.set(listData, forKey: listKey)

        await MainActor.run {
            let registry = ServerRegistry()
            XCTAssertEqual(registry.servers.count, 1)
            XCTAssertEqual(registry.active?.baseURL, "https://new.example")
        }
    }

    /// When neither legacy nor new data exists, the registry starts clean.
    func testEmptyStateProducesNoServers() async {
        await MainActor.run {
            let registry = ServerRegistry()
            XCTAssertTrue(registry.servers.isEmpty)
            XCTAssertNil(registry.active)
        }
    }

    /// A legacy profile with a malformed URL is not migrated.
    func testMalformedLegacyProfileIsSkipped() async {
        var badProfile = ServerProfile(baseURL: "not a url", label: "Bad")
        badProfile.normalize() // won't help — no host
        let profileData = try! JSONEncoder().encode(badProfile)
        UserDefaults.standard.set(profileData, forKey: legacyProfileKey)

        await MainActor.run {
            _ = ServerRegistry()
        }

        // The legacy key is still there (migration was skipped).
        XCTAssertNotNil(UserDefaults.standard.data(forKey: legacyProfileKey))
    }
}
