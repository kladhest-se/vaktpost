import Foundation

/// Minimal, bounds-checked DER reader for the certificate fields iOS does not
/// expose through Security.framework. It never participates in trust; trust is
/// still decided by SecTrust and the SHA-256 pin.
struct DERCertificateMetadata: Equatable {
    var issuer: String?
    var validFrom: Date?
    var validUntil: Date?

    static func parse(_ data: Data) -> DERCertificateMetadata? {
        var cursor = 0
        guard let certificate = node(in: data, cursor: &cursor), certificate.tag == 0x30,
              let tbs = children(of: certificate).first, tbs.tag == 0x30 else { return nil }
        let fields = children(of: tbs)
        let offset = fields.first?.tag == 0xa0 ? 1 : 0
        guard fields.count > offset + 3 else { return nil }
        let issuerNode = fields[offset + 2]
        let validityNode = fields[offset + 3]
        let validity = children(of: validityNode)
        return DERCertificateMetadata(
            issuer: distinguishedName(issuerNode),
            validFrom: validity.first.flatMap(time),
            validUntil: validity.dropFirst().first.flatMap(time)
        )
    }

    private struct Node {
        var tag: UInt8
        var value: Data
    }

    private static func node(in data: Data, cursor: inout Int) -> Node? {
        guard cursor < data.count else { return nil }
        let tag = data[cursor]
        cursor += 1
        guard cursor < data.count else { return nil }
        let firstLength = Int(data[cursor])
        cursor += 1
        let length: Int
        if firstLength & 0x80 == 0 {
            length = firstLength
        } else {
            let byteCount = firstLength & 0x7f
            guard byteCount > 0, byteCount <= 4, cursor + byteCount <= data.count else { return nil }
            var result = 0
            for _ in 0..<byteCount {
                result = (result << 8) | Int(data[cursor])
                cursor += 1
            }
            length = result
        }
        guard length >= 0, cursor + length <= data.count else { return nil }
        let value = data.subdata(in: cursor..<(cursor + length))
        cursor += length
        return Node(tag: tag, value: value)
    }

    private static func children(of node: Node) -> [Node] {
        var result: [Node] = []
        var cursor = 0
        while cursor < node.value.count {
            guard let child = self.node(in: node.value, cursor: &cursor) else { return [] }
            result.append(child)
        }
        return result
    }

    private static func distinguishedName(_ node: Node) -> String? {
        let labels = [
            oid(2, 5, 4, 3): "CN", oid(2, 5, 4, 10): "O", oid(2, 5, 4, 11): "OU",
            oid(2, 5, 4, 6): "C", oid(2, 5, 4, 7): "L", oid(2, 5, 4, 8): "ST"
        ]
        var pieces: [String] = []
        for set in children(of: node) where set.tag == 0x31 {
            for sequence in children(of: set) where sequence.tag == 0x30 {
                let pair = children(of: sequence)
                guard pair.count >= 2, pair[0].tag == 0x06,
                      let oid = oid(pair[0].value), let value = string(pair[1]) else { continue }
                pieces.append("\(labels[oid] ?? oid)=\(value)")
            }
        }
        return pieces.isEmpty ? nil : pieces.joined(separator: ", ")
    }

    private static func string(_ node: Node) -> String? {
        switch node.tag {
        case 0x0c, 0x13, 0x14, 0x16:
            return String(data: node.value, encoding: .utf8)
        case 0x1e:
            guard node.value.count.isMultiple(of: 2) else { return nil }
            var units: [UInt16] = []
            var index = 0
            while index < node.value.count {
                units.append(UInt16(node.value[index]) << 8 | UInt16(node.value[index + 1]))
                index += 2
            }
            return String(decoding: units, as: UTF16.self)
        default:
            return nil
        }
    }

    private static func oid(_ data: Data) -> String? {
        guard let first = data.first else { return nil }
        var values = [Int(first) / 40, Int(first) % 40]
        var current = 0
        for byte in data.dropFirst() {
            current = (current << 7) | Int(byte & 0x7f)
            if byte & 0x80 == 0 {
                values.append(current)
                current = 0
            }
        }
        guard current == 0 else { return nil }
        return values.map(String.init).joined(separator: ".")
    }

    private static func oid(_ components: Int...) -> String {
        components.map(String.init).joined(separator: ".")
    }

    private static func time(_ node: Node) -> Date? {
        guard node.tag == 0x17 || node.tag == 0x18,
              let raw = String(data: node.value, encoding: .ascii) else { return nil }
        let formats = node.tag == 0x17
            ? ["yyMMddHHmmss'Z'", "yyMMddHHmm'Z'"]
            : ["yyyyMMddHHmmss'Z'", "yyyyMMddHHmm'Z'"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }
}
