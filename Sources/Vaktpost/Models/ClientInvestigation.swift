import Foundation

struct ClientInvestigation {
    let leases: [DHCPLease]
    let neighbors: [ARPEntry]
    let mappings: [StaticMapping]
    let addresses: [String]
    let names: [String]

    init(client: NetworkClient, leases: [DHCPLease], arp: [ARPEntry],
         mappings: [StaticMapping], overrides: [HostOverride], aliases: [FirewallAliasEntry]) {
        func belongs(_ mac: String, _ ip: String) -> Bool {
            ClientAddress.belongs(mac: mac, ip: ip, toMAC: client.mac, primaryIP: client.ip)
        }
        self.leases = leases.filter { belongs($0.mac, $0.ip) }
        neighbors = arp.filter { belongs($0.mac, $0.ip) }
        self.mappings = mappings.filter { belongs($0.mac, $0.ip) }
        var seen = Set<String>()
        addresses = ([client.ip] + neighbors.map(\.ip) + self.leases.map(\.ip) + self.mappings.map(\.ip))
            .filter { ip in
                guard let key = ClientAddress.key(ip) else { return false }
                return seen.insert(key).inserted
            }
        let keys = Set(addresses.compactMap(ClientAddress.key))
        var labels = client.knownNames.map { "\($0.source): \($0.value)" }
        labels += self.leases.compactMap { $0.hostname.map { "DHCP: \($0)" } }
        labels += neighbors.compactMap { $0.hostname.map { "ARP: \($0)" } }
        labels += self.mappings.compactMap { $0.hostname.map { "Static mapping: \($0)" } }
        labels += overrides.filter { ClientAddress.key($0.ip).map(keys.contains) == true }
            .map { "DNS override: \($0.fqdn)" }
        labels += aliases.filter { alias in
            alias.addresses.contains { address in
                let single = address.hasSuffix("/32") ? String(address.dropLast(3)) :
                    address.hasSuffix("/128") ? String(address.dropLast(4)) : address
                return ClientAddress.key(single).map(keys.contains) == true
            }
        }.map { "Firewall alias: \($0.name)" }
        names = Array(Set(labels)).sorted()
    }
}

extension LogLine {
    func involves(addresses: Set<String>) -> Bool {
        let fields = filterFields
        return [source, destination, fields?.source, fields?.destination]
            .compactMap { $0 }.compactMap(ClientAddress.key).contains(where: addresses.contains)
    }
}
