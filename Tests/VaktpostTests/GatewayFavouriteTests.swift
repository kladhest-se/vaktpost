import XCTest
@testable import Vaktpost

/// Which gateways the Overview shows.
///
/// The rule is "all of them until somebody chooses", because that is what the
/// Overview did before starring existed and a dashboard that empties itself on
/// upgrade is worse than one that shows too much.
@MainActor
final class GatewayFavouriteTests: XCTestCase {

    private func makeStore(_ suite: String = "vaktpost.gateways.\(UUID())")
    -> (DashboardStore, UserDefaults, String) {
        let defaults = UserDefaults(suiteName: suite)!
        let store = DashboardStore(registry: ServerRegistry(defaults: defaults), defaults: defaults)
        return (store, defaults, suite)
    }

    private func gateway(_ name: String) -> GatewayStatus {
        GatewayStatus(JSONDict(["name": .string(name), "status": .string("online")]))
    }

    func testEveryGatewayIsShownUntilOneIsStarred() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.gatewayManager.gateways = [gateway("WAN_DHCP"), gateway("VPN_GW")]

        XCTAssertEqual(store.overviewGateways.map(\.name), ["WAN_DHCP", "VPN_GW"])

        store.toggleFavourite(gateway("VPN_GW"))
        XCTAssertEqual(store.overviewGateways.map(\.name), ["VPN_GW"])
    }

    func testStarringNoneShowsNoneRatherThanReverting() {
        // Starring and then unstarring is a choice, not a reset: reverting to
        // "show everything" here would make the star look broken.
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.gatewayManager.gateways = [gateway("WAN_DHCP")]

        store.toggleFavourite(gateway("WAN_DHCP"))
        XCTAssertTrue(store.isFavourite(gateway("WAN_DHCP")))
        store.toggleFavourite(gateway("WAN_DHCP"))

        XCTAssertFalse(store.isFavourite(gateway("WAN_DHCP")))
        XCTAssertTrue(store.overviewGateways.isEmpty)
    }

    func testTheChoiceSurvivesARelaunch() {
        let suite = "vaktpost.gateways.\(UUID())"
        let (store, defaults, _) = makeStore(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        store.gatewayManager.gateways = [gateway("WAN_DHCP"), gateway("VPN_GW")]
        store.toggleFavourite(gateway("WAN_DHCP"))

        let reopened = DashboardStore(registry: ServerRegistry(defaults: defaults), defaults: defaults)
        reopened.gatewayManager.gateways = [gateway("WAN_DHCP"), gateway("VPN_GW")]
        XCTAssertEqual(reopened.overviewGateways.map(\.name), ["WAN_DHCP"])
    }

    func testAGatewayThatIsGoneIsNotShown() {
        // A starred gateway that no longer exists — renamed, or its interface
        // removed — must not resurrect itself as an empty row.
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.gatewayManager.gateways = [gateway("WAN_DHCP")]
        store.toggleFavourite(gateway("WAN_DHCP"))

        store.gatewayManager.gateways = [gateway("WAN2_DHCP")]
        XCTAssertTrue(store.overviewGateways.isEmpty)
    }
}
