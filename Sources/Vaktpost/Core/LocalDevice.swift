import Foundation

/// This device's own addresses on the local network.
///
/// Used to mark the phone you are holding in the client list. Being able to
/// pick your own device out of two hundred rows is worth a small icon: it
/// tells you which lease is yours before you go looking for a MAC you would
/// have to check in Settings.
///
/// **Not by MAC.** iOS has refused to hand an app the Wi-Fi MAC since iOS 7 —
/// `en0` reports `02:00:00:00:00:00` to everyone — so matching the firewall's
/// ARP table by hardware address cannot work at all. Private Wi-Fi Address
/// makes it worse again: the MAC the firewall sees is generated per network
/// and is not the one the device would report even if it could.
///
/// So this matches on the IPv4 address of the Wi-Fi interface, which the
/// system does provide. That is right for exactly as long as the lease lasts,
/// which is the same window in which the client list is worth looking at.
enum LocalDevice {

    /// Every IPv4 address this device currently holds, by interface.
    ///
    /// `en0` is Wi-Fi and the one that matters; the rest are returned because
    /// a device on a VPN or a personal hotspot has several, and guessing which
    /// is "the" address would be wrong more often than listing them.
    static func addresses() -> [String: String] {
        var found: [String: String] = [:]

        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return found }
        defer { freeifaddrs(head) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee

            // Up, running, and not the loopback: 127.0.0.1 is nobody's client.
            let flags = Int32(interface.ifa_flags)
            guard flags & IFF_UP == IFF_UP,
                  flags & IFF_LOOPBACK == 0,
                  let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET)
            else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &host, socklen_t(host.count),
                nil, 0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }

            let name = String(cString: interface.ifa_name)
            let addressText = String(
                bytes: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
                encoding: .utf8
            ) ?? ""
            found[name] = addressText
        }

        return found
    }

    /// The Wi-Fi address, if there is one.
    static var wifiAddress: String? { addresses()["en0"] }

    /// Whether an address belongs to this device.
    static func isThisDevice(_ address: String) -> Bool {
        guard !address.isEmpty else { return false }
        return addresses().values.contains(address)
    }
}
