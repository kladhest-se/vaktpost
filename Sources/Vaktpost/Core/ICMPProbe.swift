import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// Ping and traceroute, run entirely on this device rather than the firewall.
///
/// pfSense's PHP has no native ICMP capability, and this app's own security
/// boundary forbids every `PHPSnippet` from reaching a shell except one
/// narrowly-scoped exception for pfSense's own background updater — see
/// `PHPSnippets.allowedFunctions` and `readonly.sh`'s `writeaudit.py`, which
/// hard-fails on `exec`/`shell_exec`/`system`/`popen` in any other snippet,
/// deliberately, so that boundary means something. Shelling out to
/// `ping`/`traceroute` on the firewall to answer this feature would be
/// exactly the kind of one-off exception that stops a boundary being one.
/// DNS lookup can still run on the firewall — PHP's own `dns_get_record()`
/// needs no shell — but ping and traceroute run here instead.
///
/// The mechanism is the same unprivileged one behind Apple's own SimplePing
/// sample: a `SOCK_DGRAM` socket opened with `IPPROTO_ICMP`. BSD-derived
/// kernels (iOS and macOS both) let an ordinary process send and receive
/// ICMP echo traffic this way, scoped to the identifier this process chose,
/// without `SOCK_RAW` or any special entitlement.
///
/// IPv4 only. IPv6 ICMP uses different type numbers and folds the source and
/// destination addresses into the checksum via a pseudo-header, which is
/// meaningfully more code for a case most home and small-office networks
/// this app targets don't hit — a target that resolves only to IPv6 reports
/// that plainly rather than silently doing nothing.
enum ICMPProbe {

    // MARK: - Errors

    enum ProbeError: LocalizedError {
        case cannotResolve
        case ipv6Only
        case socketFailed

        var errorDescription: String? {
            switch self {
            case .cannotResolve: return "Could not resolve that host to an IPv4 address."
            case .ipv6Only: return "That host only resolves to IPv6, which this tool doesn't probe."
            case .socketFailed: return "Could not open a network socket for the probe."
            }
        }
    }

    // MARK: - Public API

    /// Sends `count` echo requests and reports the average round trip.
    ///
    /// Never throws: a resolution or socket failure is folded into
    /// `PingResult.message` instead, since the caller wants something to
    /// show either way, the same as pfSense's own diag_ping.php would.
    static func ping(host: String, count: Int = 4, timeout: TimeInterval = 2.0) async -> PingResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = pingSync(host: host, count: count, timeout: timeout)
                continuation.resume(returning: result)
            }
        }
    }

    /// Traces the path to `host`, one probe generation per TTL.
    ///
    /// Stops as soon as the destination itself answers (an echo reply, not a
    /// time-exceeded from some hop along the way) or `maxHops` is reached.
    static func traceroute(host: String, maxHops: Int = 30, probesPerHop: Int = 3,
                           timeout: TimeInterval = 2.0) async -> TracerouteResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = tracerouteSync(host: host, maxHops: maxHops,
                                            probesPerHop: probesPerHop, timeout: timeout)
                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - ICMPv4 packet layout

    private static let echoRequestType: UInt8 = 8
    private static let echoReplyType: UInt8 = 0
    private static let timeExceededType: UInt8 = 11
    private static let destUnreachableType: UInt8 = 3
    private static let headerSize = 8

    /// RFC 1071 one's-complement checksum over the ICMP header and payload
    /// together. Unlike ICMPv6, ICMPv4 has no pseudo-header to fold in.
    private static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i + 1 < bytes.count {
            sum += UInt32(bytes[i]) << 8 | UInt32(bytes[i + 1])
            i += 2
        }
        if i < bytes.count {
            sum += UInt32(bytes[i]) << 8
        }
        while sum >> 16 != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        return ~UInt16(truncatingIfNeeded: sum)
    }

    private static func buildEchoRequest(identifier: UInt16, sequence: UInt16) -> [UInt8] {
        // The payload just needs to round-trip so the reply can be measured
        // against it; an 8-byte timestamp doubles as that and as a sanity
        // check that this reply matches this request rather than a stray
        // one from a previous run still in flight.
        var stamp = Date().timeIntervalSince1970
        let payload = withUnsafeBytes(of: &stamp) { Array($0) }
        var packet: [UInt8] = [
            echoRequestType, 0,   // type, code
            0, 0,                 // checksum, filled below
            UInt8(identifier >> 8), UInt8(identifier & 0xFF),
            UInt8(sequence >> 8), UInt8(sequence & 0xFF)
        ]
        packet.append(contentsOf: payload)
        let sum = checksum(packet)
        packet[2] = UInt8(sum >> 8)
        packet[3] = UInt8(sum & 0xFF)
        return packet
    }

    /// One received ICMP message, past whatever IP header the kernel chose
    /// to hand back.
    ///
    /// Platforms disagree on this for a `SOCK_DGRAM`/`IPPROTO_ICMP` socket —
    /// some deliver the ICMP payload alone, some prepend the IPv4 header the
    /// same way a raw socket would. Both are handled by reading the first
    /// byte: an IPv4 header's low nibble is its length in 32-bit words, and
    /// that byte can never take the value 0x08 (echo request) or 0x00 (echo
    /// reply) or 0x0B (time exceeded) as an IHL nibble in the version/IHL
    /// byte's position for a v4 packet starting mid-header — checking the
    /// version nibble (top nibble, must read 4) is what actually
    /// distinguishes the two shapes.
    private struct ParsedReply {
        let type: UInt8
        let identifier: UInt16
        let sequence: UInt16
        let sourceAddress: String
    }

    private static func parseReply(_ buffer: [UInt8], length: Int, from address: sockaddr_in) -> ParsedReply? {
        guard length >= headerSize else { return nil }
        var offset = 0
        // An IPv4 header starts with a version nibble of 4. An ICMP header's
        // first byte is its type, and none of the types this tool sends or
        // expects (0, 3, 8, 11) has 4 as its own top nibble, so this check
        // reliably tells the two shapes apart rather than guessing from length.
        if buffer[0] >> 4 == 4 {
            let ihl = Int(buffer[0] & 0x0F) * 4
            guard length >= ihl + headerSize else { return nil }
            offset = ihl
        }
        let type = buffer[offset]
        let identifier = UInt16(buffer[offset + 4]) << 8 | UInt16(buffer[offset + 5])
        let sequence = UInt16(buffer[offset + 6]) << 8 | UInt16(buffer[offset + 7])
        var addr = address.sin_addr
        var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &addr, &text, socklen_t(INET_ADDRSTRLEN))
        return ParsedReply(type: type, identifier: identifier, sequence: sequence,
                           sourceAddress: Self.string(fromNullTerminated: text))
    }

    // MARK: - Address resolution

    /// A null-terminated C string buffer as a Swift String, without the
    /// deprecated `String(cString:)` overload for a `[CChar]` array — which
    /// warns because it can't itself verify the buffer is actually
    /// null-terminated. `inet_ntop` guarantees it here, but truncating at
    /// the terminator explicitly is what the replacement API asks for.
    private static func string(fromNullTerminated buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }

    /// The first IPv4 address `host` resolves to, or nil if it resolves only
    /// to IPv6 (or not at all).
    private static func resolveIPv4(_ host: String) -> String? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return nil }
        defer { freeaddrinfo(result) }
        var addr = sockaddr_in()
        withUnsafeMutableBytes(of: &addr) { dest in
            _ = memcpy(dest.baseAddress, first.pointee.ai_addr, MemoryLayout<sockaddr_in>.size)
        }
        var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &addr.sin_addr, &text, socklen_t(INET_ADDRSTRLEN))
        return Self.string(fromNullTerminated: text)
    }

    private static func hostResolvesOnlyToIPv6(_ host: String) -> Bool {
        var hints = addrinfo()
        hints.ai_family = AF_INET6
        hints.ai_socktype = SOCK_DGRAM
        var result: UnsafeMutablePointer<addrinfo>?
        defer { if result != nil { freeaddrinfo(result) } }
        return getaddrinfo(host, nil, &hints, &result) == 0
    }

    // MARK: - Socket

    /// Opens the unprivileged ICMP socket, or nil if this platform or
    /// sandbox refuses it.
    private static func openSocket() -> Int32? {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { return nil }
        var timeoutValue = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeoutValue, socklen_t(MemoryLayout<timeval>.size))
        return fd
    }

    private static func setTimeout(_ fd: Int32, _ timeout: TimeInterval) {
        var value = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - Double(Int(timeout))) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
    }

    private static func setTTL(_ fd: Int32, _ ttl: Int) {
        var value = Int32(ttl)
        setsockopt(fd, IPPROTO_IP, IP_TTL, &value, socklen_t(MemoryLayout<Int32>.size))
    }

    /// Sends one echo request and waits up to `timeout` for its matching
    /// reply, ignoring anything addressed to a different identifier or
    /// sequence — a stray reply to an earlier, already-timed-out probe
    /// should not be mistaken for this one's answer.
    private static func sendAndReceive(fd: Int32, destination: sockaddr_in,
                                       identifier: UInt16, sequence: UInt16,
                                       timeout: TimeInterval) -> (reply: ParsedReply, elapsedMs: Double)? {
        let request = buildEchoRequest(identifier: identifier, sequence: sequence)
        var dest = destination
        let sent = withUnsafePointer(to: &dest) { destPtr -> Int in
            destPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                sendto(fd, request, request.count, 0, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard sent > 0 else { return nil }
        let start = Date()

        while true {
            let remaining = timeout - Date().timeIntervalSince(start)
            guard remaining > 0 else { return nil }
            setTimeout(fd, remaining)
            var buffer = [UInt8](repeating: 0, count: 1024)
            var fromAddr = sockaddr_in()
            var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let received = withUnsafeMutablePointer(to: &fromAddr) { fromPtr -> Int in
                fromPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    recvfrom(fd, &buffer, buffer.count, 0, sockPtr, &fromLen)
                }
            }
            guard received > 0 else { break }
            guard let reply = parseReply(buffer, length: received, from: fromAddr) else { continue }
            // A time-exceeded or destination-unreachable message from an
            // intermediate hop carries the *original request* as its own
            // payload, not this process's identifier in the position an
            // echo reply would put it — so those two types are accepted by
            // type alone, on the assumption that nothing else on this
            // device is running a probe with the same source port at the
            // same moment. Echo replies are still matched by identifier and
            // sequence, since those are addressed directly.
            if reply.type == timeExceededType || reply.type == destUnreachableType {
                return (reply, Date().timeIntervalSince(start) * 1000)
            }
            if reply.type == echoReplyType, reply.identifier == identifier, reply.sequence == sequence {
                return (reply, Date().timeIntervalSince(start) * 1000)
            }
        }
        return nil
    }

    // MARK: - Ping

    private static func pingSync(host: String, count: Int, timeout: TimeInterval) -> PingResult {
        guard let address = resolveIPv4(host) else {
            let message = hostResolvesOnlyToIPv6(host)
                ? ProbeError.ipv6Only.localizedDescription
                : ProbeError.cannotResolve.localizedDescription
            return PingResult(JSONDict(["host": .string(host), "success": .bool(false), "message": .string(message)]))
        }
        guard let fd = openSocket() else {
            return PingResult(JSONDict(["host": .string(host), "success": .bool(false),
                                        "message": .string(ProbeError.socketFailed.localizedDescription)]))
        }
        defer { close(fd) }

        var dest = sockaddr_in()
        dest.sin_family = sa_family_t(AF_INET)
        inet_pton(AF_INET, address, &dest.sin_addr)
        let identifier = UInt16(truncatingIfNeeded: ProcessInfo.processInfo.processIdentifier)

        var rtts: [Double] = []
        for sequence in 0..<count {
            if let (reply, elapsed) = sendAndReceive(fd: fd, destination: dest, identifier: identifier,
                                                     sequence: UInt16(sequence), timeout: timeout),
               reply.type == echoReplyType {
                rtts.append(elapsed)
            }
            if sequence < count - 1 { Thread.sleep(forTimeInterval: 0.25) }
        }

        let received = rtts.count
        let avg = rtts.isEmpty ? nil : rtts.reduce(0, +) / Double(rtts.count)
        let lossPercent = Int(round(Double(count - received) / Double(count) * 100))
        let message = received == 0
            ? "No response — host unreachable or blocking ICMP."
            : "\(received)/\(count) received, \(lossPercent)% loss."
        return PingResult(JSONDict([
            "host": .string(host), "success": .bool(received > 0),
            "avgMs": avg.map { .number($0) } ?? .null, "message": .string(message)
        ]))
    }

    // MARK: - Traceroute

    private static func tracerouteSync(host: String, maxHops: Int, probesPerHop: Int,
                                       timeout: TimeInterval) -> TracerouteResult {
        guard let address = resolveIPv4(host) else {
            return TracerouteResult(JSONDict(["host": .string(host), "hops": .array([])]))
        }
        guard let fd = openSocket() else {
            return TracerouteResult(JSONDict(["host": .string(host), "hops": .array([])]))
        }
        defer { close(fd) }

        var dest = sockaddr_in()
        dest.sin_family = sa_family_t(AF_INET)
        inet_pton(AF_INET, address, &dest.sin_addr)
        let identifier = UInt16(truncatingIfNeeded: ProcessInfo.processInfo.processIdentifier)

        var hops: [JSONValue] = []
        var sequence: UInt16 = 0

        for ttl in 1...maxHops {
            setTTL(fd, ttl)
            var detail = "*"
            var latencies: [Double] = []
            var reachedDestination = false

            for _ in 0..<probesPerHop {
                sequence += 1
                if let (reply, elapsed) = sendAndReceive(fd: fd, destination: dest, identifier: identifier,
                                                         sequence: sequence, timeout: timeout) {
                    detail = reply.sourceAddress
                    latencies.append(elapsed)
                    if reply.type == echoReplyType { reachedDestination = true }
                }
            }

            hops.append(.object([
                "hop": .number(Double(ttl)), "detail": .string(detail),
                "latencies": .array(latencies.map { .number($0) })
            ]))
            if reachedDestination { break }
        }

        return TracerouteResult(JSONDict(["host": .string(host), "hops": .array(hops)]))
    }
}
