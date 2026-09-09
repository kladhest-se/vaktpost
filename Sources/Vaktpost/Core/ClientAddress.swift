import Foundation
import Darwin

/// Numeric address comparison: never confuse an address with a substring or hostname.
enum ClientAddress {
    static func key(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var v4 = in_addr()
        if inet_pton(AF_INET, text, &v4) == 1 {
            return withUnsafeBytes(of: &v4) { "4:" + $0.map { String(format: "%02x", $0) }.joined() }
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, text, &v6) == 1 {
            return withUnsafeBytes(of: &v6) { "6:" + $0.map { String(format: "%02x", $0) }.joined() }
        }
        return nil
    }

    static func macKey(_ value: String) -> String? {
        let compact = value.lowercased().filter { $0 != ":" && $0 != "-" }
        guard compact.count == 12, compact.allSatisfy({ $0.isASCII && $0.isHexDigit }),
              compact != "000000000000", compact != "ffffffffffff" else { return nil }
        return compact
    }

    static func belongs(mac: String, ip: String, toMAC: String, primaryIP: String) -> Bool {
        if let owner = macKey(toMAC) { return macKey(mac) == owner }
        guard let address = key(primaryIP) else { return false }
        return key(ip) == address
    }
}
