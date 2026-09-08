import Foundation

/// A permissive JSON representation.
///
/// The pfSense REST API package evolves its model fields between releases, and
/// several status endpoints return values that are sometimes strings and
/// sometimes numbers (percentages, RTT, lease timestamps). Decoding into a
/// strict `Codable` struct makes the whole screen fail on one renamed key, so
/// responses are decoded into `JSONValue` and read through the accessors below,
/// each of which accepts a list of candidate keys and coerces types.
indirect enum JSONValue: Decodable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        self = .null
    }

    var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }

    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s):
            // Handles "12", "12.5", "12.5%", "23ms", "1.2 Mbps"
            let filtered = s.prefix { $0.isNumber || $0 == "." || $0 == "-" }
            return Double(filtered)
        case .bool(let b): return b ? 1 : 0
        default: return nil
        }
    }

    var intValue: Int? { doubleValue.map { Int($0) } }

    var boolValue: Bool? {
        switch self {
        case .bool(let b): return b
        case .number(let n): return n != 0
        case .string(let s):
            switch s.lowercased() {
            case "true", "yes", "1", "up", "on", "enabled", "running": return true
            case "false", "no", "0", "down", "off", "disabled", "stopped": return false
            default: return nil
            }
        default: return nil
        }
    }
}

/// Convenience reader over a decoded JSON object.
struct JSONDict {
    let raw: [String: JSONValue]

    init(_ raw: [String: JSONValue]) { self.raw = raw }
    init?(_ value: JSONValue?) {
        guard let o = value?.objectValue else { return nil }
        self.raw = o
    }

    /// Raw access for callers that need to inspect a nested object themselves.
    func value(_ keys: String...) -> JSONValue? { first(keys) }

    private func first(_ keys: [String]) -> JSONValue? {
        for k in keys { if let v = raw[k], !v.isNull { return v } }
        return nil
    }

    func string(_ keys: String...) -> String? { first(keys)?.stringValue }
    func double(_ keys: String...) -> Double? { first(keys)?.doubleValue }
    func int(_ keys: String...) -> Int? { first(keys)?.intValue }
    func bool(_ keys: String...) -> Bool? { first(keys)?.boolValue }
    func dict(_ keys: String...) -> JSONDict? { JSONDict(first(keys)) }
    func list(_ keys: String...) -> [JSONValue] { first(keys)?.arrayValue ?? [] }
}

extension JSONValue {
    var isNull: Bool { if case .null = self { return true }; return false }
}
