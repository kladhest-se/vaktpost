import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// A DNS lookup run by this device's own resolver rather than the firewall's.
///
/// Answers a different question than `PHPSnippet.dnsLookup` does: that one
/// asks what the firewall's resolver — usually Unbound, forwarding through
/// whatever upstream or split-DNS rules are configured there — believes.
/// This asks what the phone's own resolver believes, over whatever network
/// path it currently has (cellular, a different Wi-Fi network, a VPN). The
/// two disagreeing is itself the diagnosis for a surprising number of
/// "this site works on the firewall's own admin page but not on my phone"
/// reports, so both are worth having rather than picking one.
///
/// Limited to A and AAAA records. This previously used `res_query()` to
/// query any record type over the device's own resolver and parse the raw
/// DNS wire format by hand — until a newer SDK stopped exporting it from
/// `Darwin` to Swift at all, exactly the kind of legacy BSD resolver symbol
/// Apple has been progressively pulling from view in favour of
/// Network.framework, with no notice beyond the build breaking.
///
/// `getaddrinfo()`/`getnameinfo()` are the replacement, not a workaround:
/// they are what `URLSession` itself resolves through, declared in the same
/// `<netdb.h>` this file already reaches for other reasons, thread-safe by
/// design, and address-only by design too — which is also this lookup's
/// actual job. Answering "what does this host's MX or TXT record say, from
/// this device's own resolver specifically" is a rarer question than "can
/// this phone reach this host at all", and the firewall-side lookup
/// (`PHPSnippet.dnsLookup`) still answers every record type this app has
/// ever supported, unchanged — a device-side CNAME/MX/NS/TXT/SOA request
/// gets a clear "not supported this way" rather than a silent wrong answer.
enum DeviceDNSLookup {

    private static let addressTypes: Set<String> = ["A", "AAAA"]

    static func lookup(host: String, recordType: String) async -> DNSLookupResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = lookupSync(host: host, recordType: recordType)
                continuation.resume(returning: result)
            }
        }
    }

    private static func lookupSync(host: String, recordType: String) -> DNSLookupResult {
        let type = recordType.uppercased()
        guard addressTypes.contains(type) else {
            return DNSLookupResult(JSONDict([
                "host": .string(host),
                "error": .string("\(type) is not available from this device's own resolver — "
                    + "only A and AAAA are. Switch to the firewall's resolver for other record types.")
            ]))
        }

        let start = Date()
        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM  // one result per address, not one per socket type
        hints.ai_family = type == "AAAA" ? AF_INET6 : AF_INET

        var head: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &head)
        let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
        defer { if let head { freeaddrinfo(head) } }

        guard status == 0, let head else {
            let message = String(cString: gai_strerror(status))
            return DNSLookupResult(JSONDict([
                "host": .string(host), "queryTime": .number(Double(elapsedMs)),
                "error": .string("No answer — \(message)"),
                "serverTimings": .array([.object(["server": .string("This device"),
                                                  "time": .string("\(elapsedMs) msec")])])
            ]))
        }

        var addresses: [String] = []
        var current: UnsafeMutablePointer<addrinfo>? = head
        while let entry = current {
            if let address = numericAddress(entry.pointee) {
                addresses.append(address)
            }
            current = entry.pointee.ai_next
        }

        guard !addresses.isEmpty else {
            return DNSLookupResult(JSONDict([
                "host": .string(host), "queryTime": .number(Double(elapsedMs)),
                "error": .string("No \(type) records found."),
                "serverTimings": .array([.object(["server": .string("This device"),
                                                  "time": .string("\(elapsedMs) msec")])])
            ]))
        }

        return DNSLookupResult(JSONDict([
            "host": .string(host), "queryTime": .number(Double(elapsedMs)),
            "records": .array(addresses.map { address in
                .object(["name": .string(host), "class": .string("IN"),
                         "type": .string(type), "value": .string(address)])
            }),
            "answers": .array(addresses.map { address in
                .object(["name": .string(host), "address": .string(address)])
            }),
            "serverTimings": .array([.object(["server": .string("This device"),
                                              "time": .string("\(elapsedMs) msec")])])
        ]))
    }

    /// The numeric text form of one `getaddrinfo()` result — "192.0.2.1" or
    /// "2001:db8::1" — via `getnameinfo(NI_NUMERICHOST)` rather than
    /// reaching into the `sockaddr` by hand for each address family.
    private static func numericAddress(_ info: addrinfo) -> String? {
        var text = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = getnameinfo(
            info.ai_addr, info.ai_addrlen,
            &text, socklen_t(text.count),
            nil, 0, NI_NUMERICHOST
        )
        guard status == 0 else { return nil }
        let bytes = text.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(bytes: bytes, encoding: .utf8)
    }
}
