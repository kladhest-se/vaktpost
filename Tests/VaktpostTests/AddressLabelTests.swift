import XCTest
@testable import Vaktpost

/// What a rule's source and destination read as.
///
/// pfSense stores a system selector by its internal key, so a rule read "from
/// lan to opt4" while the tab above it and its own Interface field both said
/// VLAN_100. Only the webConfigurator's name belongs on screen.
@MainActor
final class AddressLabelTests: XCTestCase {

    private func makeStore() -> (DashboardStore, UserDefaults, String) {
        let suite = "vaktpost.labels.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let store = DashboardStore(registry: ServerRegistry(defaults: defaults), defaults: defaults)
        store.interfaces = [
            InterfaceStat(JSONDict(["descr": .string("LAN"), "name": .string("lan"),
                                    "hwif": .string("igb1"), "status": .string("up")])),
            InterfaceStat(JSONDict(["descr": .string("VLAN_100"), "name": .string("opt4"),
                                    "hwif": .string("igb1.100"), "status": .string("up")])),
        ]
        return (store, defaults, suite)
    }

    private func network(_ value: String) -> FilterAddress {
        FilterAddress(.object(["network": .string(value)]))
    }

    private func address(_ value: String) -> FilterAddress {
        FilterAddress(.object(["address": .string(value)]))
    }

    func testAnInterfaceSelectorReadsAsItsName() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(store.addressLabel(for: network("lan")), "LAN subnets")
        XCTAssertEqual(store.addressLabel(for: network("opt4")), "VLAN_100 subnets")
        XCTAssertEqual(store.addressLabel(for: network("lanip")), "LAN address")
        XCTAssertEqual(store.addressLabel(for: network("opt4ip")), "VLAN_100 address")
    }

    func testTheFirewallsOwnSelectorsAreNamed() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(store.addressLabel(for: network("self")), "this firewall")
        XCTAssertEqual(store.addressLabel(for: network("pppoe")), "PPPoE clients")
        XCTAssertEqual(store.addressLabel(for: network("any")), "any")
    }

    func testAnAliasOrLiteralIsLeftAsTyped() {
        // An alias name is what somebody wrote, and renaming it on screen
        // would make it unfindable in the webConfigurator.
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(store.addressLabel(for: address("alias_host_nas003")), "alias_host_nas003")
        XCTAssertEqual(store.addressLabel(for: address("192.0.2.10")), "192.0.2.10")
        // `lan` typed as a literal address is not a selector either.
        XCTAssertEqual(store.addressLabel(for: address("lan")), "lan")
    }

    func testAnUnknownSelectorStillIdentifiesItself() {
        // An interface this build has not loaded yet, or one removed since:
        // the raw key beats a blank field.
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(store.addressLabel(for: network("opt99")), "opt99")
    }
}
