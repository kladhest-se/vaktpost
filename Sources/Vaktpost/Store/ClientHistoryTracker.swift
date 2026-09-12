import Foundation
import Observation

/// Tracks client IP/MAC address changes over time.
///
/// Builds a timeline of client appearances in DHCP leases, ARP tables, and
/// static mappings across refresh cycles.
@MainActor
@Observable
final class ClientHistoryTracker {
    
    struct ClientEvent: Identifiable {
        let id = UUID()
        let timestamp: Date
        let event: EventType
        let ipAddress: String
        let macAddress: String?
        let hostname: String?
        let source: String
        
        enum EventType: String {
            case dhcpLease = "dhcp_lease"
            case arpEntry = "arp_entry"
            case staticMapping = "static_mapping"
            case hostOverride = "host_override"
        }
    }
    
    struct ClientHistory: Identifiable {
        let id: UUID
        let ipAddress: String
        let macAddress: String?
        let hostname: String?
        let events: [ClientEvent]
        let lastSeen: Date
        let firstSeen: Date
        let eventCount: Int
        
        init(id: UUID, ipAddress: String, macAddress: String?, hostname: String?, events: [ClientEvent]) {
            self.id = id
            self.ipAddress = ipAddress
            self.macAddress = macAddress
            self.hostname = hostname
            self.events = events.sorted { $0.timestamp < $1.timestamp }
            self.lastSeen = events.map(\.timestamp).max() ?? Date()
            self.firstSeen = events.map(\.timestamp).min() ?? Date()
            self.eventCount = events.count
        }
    }
    
    private let maxEventsPerClient: Int
    private(set) var clientHistories: [String: ClientHistory] = [:]
    
    init(maxEventsPerClient: Int = 50) {
        self.maxEventsPerClient = maxEventsPerClient
    }
    
    func update(leases: [DHCPLease], arp: [ARPEntry], statics: [StaticMapping], hostOverrides: [HostOverride]) {
        var newHistories: [String: [ClientEvent]] = [:]
        
        // Process DHCP leases
        for lease in leases {
            let key = lease.ip
            let event = ClientEvent(
                timestamp: Date(),
                event: .dhcpLease,
                ipAddress: lease.ip,
                macAddress: lease.mac,
                hostname: lease.hostname,
                source: "DHCP"
            )
            newHistories[key, default: []].append(event)
        }
        
        // Process ARP entries
        for arpEntry in arp {
            let key = arpEntry.ip
            let event = ClientEvent(
                timestamp: Date(),
                event: .arpEntry,
                ipAddress: arpEntry.ip,
                macAddress: arpEntry.mac,
                hostname: nil,
                source: "ARP"
            )
            newHistories[key, default: []].append(event)
        }
        
        // Process static mappings
        for mapping in statics {
            let key = mapping.ip
            let event = ClientEvent(
                timestamp: Date(),
                event: .staticMapping,
                ipAddress: mapping.ip,
                macAddress: mapping.mac,
                hostname: mapping.hostname,
                source: "Static"
            )
            newHistories[key, default: []].append(event)
        }
        
        // Process host overrides
        for override in hostOverrides {
            let key = override.ip
            let event = ClientEvent(
                timestamp: Date(),
                event: .hostOverride,
                ipAddress: override.ip,
                macAddress: nil,
                hostname: override.host,
                source: "DNS Override"
            )
            newHistories[key, default: []].append(event)
        }
        
        // Merge with existing histories
        for (key, events) in newHistories {
            var existingEvents = clientHistories[key]?.events ?? []
            existingEvents.append(contentsOf: events)
            
            // Limit events
            if existingEvents.count > maxEventsPerClient {
                existingEvents = Array(existingEvents.suffix(maxEventsPerClient))
            }
            
            // Get unique MAC and hostname from latest events
            let macAddress = events.first(where: { $0.macAddress != nil })?.macAddress
            let hostname = events.first(where: { $0.hostname != nil })?.hostname
            
            clientHistories[key] = ClientHistory(
                id: UUID(),
                ipAddress: key,
                macAddress: macAddress,
                hostname: hostname,
                events: existingEvents
            )
        }
    }
    
    func history(for ip: String) -> ClientHistory? {
        clientHistories[ip]
    }
    
    func allClients() -> [ClientHistory] {
        Array(clientHistories.values).sorted { $0.lastSeen > $1.lastSeen }
    }
    
    func reset() {
        clientHistories.removeAll()
    }
}
