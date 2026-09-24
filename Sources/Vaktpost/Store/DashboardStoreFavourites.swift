import Foundation

/// Which interfaces and gateways the Overview shows.
///
/// Separate from the refresh state next door, and from `DashboardStore.swift`,
/// which is at the length the linter allows.
extension DashboardStore {
    // MARK: Favourite interfaces

    func toggleFavourite(_ iface: InterfaceStat) {
        if favouriteInterfaces.contains(iface.seriesKey) {
            favouriteInterfaces.remove(iface.seriesKey)
        } else {
            favouriteInterfaces.insert(iface.seriesKey)
        }
    }

    func isFavourite(_ iface: InterfaceStat) -> Bool {
        favouriteInterfaces.contains(iface.seriesKey)
    }

    // MARK: Favourite gateways

    func toggleFavourite(_ gateway: GatewayStatus) {
        // The first star is also the moment the choice stops being the app's.
        defaults.set(true, forKey: UDKey.gatewayFavouritesSeeded.rawValue)
        if favouriteGateways.contains(gateway.name) {
            favouriteGateways.remove(gateway.name)
        } else {
            favouriteGateways.insert(gateway.name)
        }
    }

    func isFavourite(_ gateway: GatewayStatus) -> Bool {
        favouriteGateways.contains(gateway.name)
    }

    /// The gateways the Overview shows.
    ///
    /// Every gateway until somebody chooses, which is what the Overview did
    /// before this existed. Once anything is starred the choice is theirs,
    /// including starring none — an empty gateway card says so rather than
    /// quietly showing all of them again.
    var overviewGateways: [GatewayStatus] {
        guard defaults.bool(forKey: UDKey.gatewayFavouritesSeeded.rawValue) else {
            return gatewayManager.gateways
        }
        return gatewayManager.gateways.filter { favouriteGateways.contains($0.name) }
    }

    /// What the Overview shows.
    ///
    /// Favourites if any are set, otherwise the WAN — the previous behaviour,
    /// kept as the default so the dashboard is useful before anybody has
    /// chosen anything.
    var overviewInterfaces: [InterfaceStat] {
        interfaces.filter { favouriteInterfaces.contains($0.seriesKey) }
    }

    /// Picks sensible defaults the first time interfaces are seen.
    ///
    /// WAN and LAN, because on almost every firewall those are the two worth a
    /// glance. Chosen once and recorded, so removing one sticks — a default
    /// that reasserts itself on every launch is not a default, it is a
    /// setting the person does not have.
    /// Not private: called from `DashboardStore.swift`, which is a different
    /// file, and `private` in Swift stops at the file.
    func seedFavouritesIfNeeded() {
        guard !interfaces.isEmpty else { return }
        guard !UserDefaults.standard.bool(forKey: UDKey.favouritesSeeded.rawValue) else { return }
        UserDefaults.standard.set(true, forKey: UDKey.favouritesSeeded.rawValue)

        let wanted = interfaces.filter { iface in
            let name = iface.name.lowercased()
            let internalName = (iface.internalName ?? "").lowercased()
            return internalName == "wan" || internalName == "lan"
                || name.hasPrefix("wan") || name.hasPrefix("lan")
        }
        favouriteInterfaces.formUnion(wanted.map(\.seriesKey))
    }
}
