import Foundation

enum MacVendorLookupResult: Equatable, Sendable {
    case found(vendor: String, prefix: String, registry: String)
    case locallyAdministered
    case multicast
    case unknown
    case invalid
    case unavailable
}

struct MacVendorIndex: Sendable {
    enum IndexError: Error { case invalidFormat }

    private struct Record: Sendable {
        var bits: UInt8
        var prefix: UInt64
        var vendorOffset: UInt32
        var registry: UInt8
    }

    private static let magic = Array("VKIEEE01".utf8)
    private let records: [Record]
    private let strings: Data

    init(data: Data) throws {
        guard data.count >= 16, Array(data.prefix(8)) == Self.magic else {
            throw IndexError.invalidFormat
        }
        let count = Int(Self.uint32(data, at: 8))
        let stringByteCount = Int(Self.uint32(data, at: 12))
        let recordSize = 14
        let recordsEnd = 16 + count * recordSize
        guard count >= 0, stringByteCount >= 0, recordsEnd <= data.count,
              recordsEnd + stringByteCount == data.count else {
            throw IndexError.invalidFormat
        }

        var parsed: [Record] = []
        parsed.reserveCapacity(count)
        for index in 0..<count {
            let offset = 16 + index * recordSize
            let bits = data[offset]
            let prefix = Self.uint64(data, at: offset + 1)
            let vendorOffset = Self.uint32(data, at: offset + 9)
            let registry = data[offset + 13]
            guard [24, 28, 36].contains(bits), registry <= 3,
                  Int(vendorOffset) < stringByteCount else {
                throw IndexError.invalidFormat
            }
            parsed.append(Record(bits: bits, prefix: prefix,
                                 vendorOffset: vendorOffset, registry: registry))
        }
        records = parsed
        strings = data.subdata(in: recordsEnd..<data.count)
    }

    func lookup(mac: String) -> MacVendorLookupResult {
        guard let normalized = ClientAddress.macKey(mac),
              let address = UInt64(normalized, radix: 16),
              let firstByte = UInt8(normalized.prefix(2), radix: 16) else {
            return .invalid
        }
        if firstByte & 0x01 != 0 { return .multicast }
        if firstByte & 0x02 != 0 { return .locallyAdministered }

        for bits in [36, 28, 24] {
            let prefix = address >> UInt64(48 - bits)
            if let record = find(bits: UInt8(bits), prefix: prefix),
               let vendor = vendor(at: record.vendorOffset) {
                return .found(vendor: vendor,
                              prefix: Self.display(prefix: prefix, bits: bits),
                              registry: Self.registryName(record.registry))
            }
        }
        return .unknown
    }

    private func find(bits: UInt8, prefix: UInt64) -> Record? {
        var lower = 0
        var upper = records.count
        while lower < upper {
            let middle = (lower + upper) / 2
            let candidate = records[middle]
            if candidate.bits < bits || (candidate.bits == bits && candidate.prefix < prefix) {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        guard lower < records.count else { return nil }
        let candidate = records[lower]
        return candidate.bits == bits && candidate.prefix == prefix ? candidate : nil
    }

    private func vendor(at offset: UInt32) -> String? {
        let start = Int(offset)
        guard start < strings.count,
              let end = strings[start...].firstIndex(of: 0) else { return nil }
        return String(data: strings[start..<end], encoding: .utf8)
    }

    private static func display(prefix: UInt64, bits: Int) -> String {
        let digits = bits / 4
        let raw = String(prefix, radix: 16, uppercase: true)
        let padded = String(repeating: "0", count: max(0, digits - raw.count)) + raw
        return stride(from: 0, to: padded.count, by: 2).map { position in
            let start = padded.index(padded.startIndex, offsetBy: position)
            let end = padded.index(start, offsetBy: min(2, padded.count - position))
            return String(padded[start..<end])
        }.joined(separator: ":")
    }

    private static func registryName(_ code: UInt8) -> String {
        switch code {
        case 0: return "MA-L"
        case 1: return "MA-M"
        case 2: return "MA-S"
        default: return "IAB"
        }
    }

    private static func uint32(_ data: Data, at offset: Int) -> UInt32 {
        (0..<4).reduce(0) { result, byte in
            result | UInt32(data[offset + byte]) << UInt32(byte * 8)
        }
    }

    private static func uint64(_ data: Data, at offset: Int) -> UInt64 {
        (0..<8).reduce(0) { result, byte in
            result | UInt64(data[offset + byte]) << UInt64(byte * 8)
        }
    }
}

actor MacVendorDatabase {
    static let shared = MacVendorDatabase()

    private var index: MacVendorIndex?
    private var attemptedLoad = false

    func lookup(mac: String) -> MacVendorLookupResult {
        if !attemptedLoad {
            attemptedLoad = true
            if let url = Bundle.main.url(forResource: "ieee-oui", withExtension: "bin"),
               let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
                index = try? MacVendorIndex(data: data)
            }
        }
        return index?.lookup(mac: mac) ?? .unavailable
    }
}
