import Foundation

// MARK: - Errors

enum RPCError: LocalizedError, Equatable {
    case notConfigured
    case badURL
    case noCredentials
    case administrationDisabled
    case unauthorized
    case forbidden
    case tls
    case transport(String)
    /// No route to the firewall, as distinct from a request that timed out.
    /// Not worth retrying: nothing about the second attempt is different.
    case offline(String)
    case fault(Int, String)
    /// The response was not XML-RPC, with whatever it actually was.
    ///
    /// "The response wasn't in the expected XML-RPC format" is true of a PHP
    /// fatal, an HTTP error page, a truncated body and a memory limit alike,
    /// and knowing which is the whole of the debugging. pfSense prints its
    /// fatals into the response, so the first line of it usually names the
    /// function and the file.
    case malformed(String?)
    case cancelled

    /// Worth trying once more. Only transport-level failures — a rejected
    /// credential or a PHP error in a snippet will fail identically the second
    /// time, and retrying a fault means running the snippet on the firewall
    /// twice for nothing.
    var isRetryable: Bool {
        if case .transport = self { return true }
        return false
    }

    /// Whether this means the firewall cannot be reached at all, as opposed to
    /// one request going wrong.
    var isConnectionFailure: Bool {
        switch self {
        case .transport, .offline: return true
        default: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case let .offline(detail): return detail
        case .notConfigured: return "No firewall configured yet."
        case .badURL: return "That base URL isn't valid."
        case .noCredentials: return "No password stored."
        case .administrationDisabled:
            return "This firewall is in monitor-only mode. Enable administrative actions in its firewall settings first."
        case .unauthorized:
            return "Sign-in was rejected (401). Check the username, password, and that the account holds the System - HA node sync privilege."
        case .forbidden:
            return "Authenticated, but XML-RPC was refused (403). The account needs the System - HA node sync privilege."
        case .tls: return "TLS handshake failed. Pin the certificate or enable untrusted TLS in Settings."
        case .transport(let m): return m
        case .fault(let code, let message):
            return "The firewall reported an error (\(code)): \(message)"
        case let .malformed(detail):
            guard let detail, !detail.isEmpty else {
                return "The response wasn't in the expected XML-RPC format."
            }
            return "The firewall did not return XML-RPC. It said: \(detail)"
        case .cancelled: return "Cancelled."
        }
    }
}

// MARK: - Transport

/// Talks to pfSense's built-in `xmlrpc.php`.
///
/// One method is ever called — `pfsense.exec_php` — with a PHP snippet from
/// `PHPSnippet`. There is no REST package involved and nothing to install on
/// the firewall; the trade is that the credential is a webConfigurator login
/// with the "System - HA node sync" privilege, which is administrator-
/// equivalent. See `SECURITY.md`.
///
/// Every snippet ends by wrapping its result in `json_encode`. That is
/// borrowed from hass-pfsense, which found that XML-RPC's own encoding of PHP
/// nulls is inconsistent enough to break parsing. Coming back as one JSON
/// string means the existing `JSONValue` decoder and every model built on it
/// keep working unchanged, and this file only has to find one string in the
/// XML rather than implement the whole XML-RPC type system.
actor XMLRPCClient {

    private let profile: ServerProfile
    private let session: URLSession
    private let trust: TrustEvaluator

    /// pfSense serialises XML-RPC calls behind a lock, so concurrent requests
    /// queue on the firewall rather than overlapping. Issuing them one at a
    /// time from here keeps the timeout accounting honest and avoids piling
    /// work onto a box that is already the thing being monitored.
    private let queue = SerialRequestQueue()

    init(profile: ServerProfile, allowsTrustPrompt: Bool = true, onPin: @escaping TrustEvaluator.PinHandler) {
        self.profile = profile
        let evaluator = TrustEvaluator(profile: profile, allowsTrustPrompt: allowsTrustPrompt, onPin: onPin)
        self.trust = evaluator

        let config = URLSessionConfiguration.ephemeral
        // exec_php can take a while; the firmware-version snippet in
        // particular shells out to the package system.
        // Fifteen seconds, not thirty.
        //
        // This is a firewall on the local network: it answers in milliseconds
        // or it is not reachable. Thirty seconds — doubled by the retry, and
        // multiplied by the calls in a refresh — is how the app came to sit on
        // stale data for minutes after the Wi-Fi went off.
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = ["Content-Type": "text/xml; charset=utf-8"]
        self.session = URLSession(configuration: config, delegate: evaluator, delegateQueue: nil)
    }

    func invalidate() async {
        trust.invalidate()
        session.invalidateAndCancel()
        await queue.invalidate()
    }

    var lastSeenFingerprint: String? { trust.lastSeenFingerprint }

    // MARK: Calling

    /// Runs a snippet and returns its decoded result.
    /// Runs a snippet, optionally allowing it longer than the default.
    ///
    /// The package check reaches the package repository over the network and
    /// routinely takes longer than thirty seconds. Timing it out and reporting
    /// a transport failure would be wrong twice: it did not fail, and the
    /// person would try again and wait the same amount of time.
    func run(_ snippet: PHPSnippet, timeout: TimeInterval? = nil) async throws -> JSONValue {
        do {
            return try await queue.run {
                return try await self.perform(snippet, timeout: timeout)
            }
        } catch let error as RPCError where error.isRetryable {
            try await Task.sleep(for: .seconds(1))
            try Task.checkCancellation()
            do {
                return try await queue.run {
                    return try await self.perform(snippet, timeout: timeout)
                }
            } catch let retryError as RPCError where retryError.isRetryable {
                throw retryError
            }
        } catch is CancellationError {
            throw RPCError.cancelled
        }
    }

    func run(_ snippet: PHPSnippet, params: [String: JSONValue], timeout: TimeInterval? = nil) async throws -> JSONValue {
        do {
            return try await queue.run {
                return try await self.perform(snippet, params: params, timeout: timeout)
            }
        } catch let error as RPCError where error.isRetryable {
            try await Task.sleep(for: .seconds(1))
            try Task.checkCancellation()
            do {
                return try await queue.run {
                    return try await self.perform(snippet, params: params, timeout: timeout)
                }
            } catch let retryError as RPCError where retryError.isRetryable {
                throw retryError
            }
        } catch is CancellationError {
            throw RPCError.cancelled
        }
    }

    func runObject(_ snippet: PHPSnippet, timeout: TimeInterval? = nil) async throws -> JSONDict {
        guard let dict = JSONDict(try await run(snippet, timeout: timeout)) else {
            throw RPCError.malformed(nil)
        }
        return dict
    }

    func runObject(_ snippet: PHPSnippet, params: [String: JSONValue], timeout: TimeInterval? = nil) async throws -> JSONDict {
        guard let dict = JSONDict(try await run(snippet, params: params, timeout: timeout)) else {
            throw RPCError.malformed(nil)
        }
        return dict
    }

    /// Rows, whatever shape PHP chose to return them in.
    ///
    /// Three are possible and all three occur:
    ///
    ///   - a list at the top level
    ///   - a list under `data`
    ///   - an *associative array* under `data`, which JSON-encodes as an
    ///     object rather than a list
    ///
    /// The third is the one that bites. `return_gateways_status(true)` keys its
    /// result by gateway name, so `gateways` arrives as
    /// `{"data": {"WAN_DHCP": {…}, "WAN2_DHCP": {…}}}`. An earlier version fell
    /// through to folding the *top level* object, which produced exactly one
    /// row — named "data" — and a gateway list showing a single entry with no
    /// status. It read as a firewall with one broken gateway rather than as a
    /// parsing bug, which is the worst way for this to fail.
    /// The same unwrapping `runList` does, for a value that arrived inside a
    /// batch rather than as its own response.
    ///
    /// Factored out rather than duplicated: the `data` envelope, the bare
    /// list, and the keyed-object-folded-to-rows cases all have to behave
    /// identically whether a section came alone or grouped, or the batch would
    /// silently change what several screens show.
    static func rows(from value: JSONValue?) -> [JSONDict] {
        guard let value else { return [] }
        if let array = value.arrayValue { return array.compactMap { JSONDict($0) } }
        guard let dict = JSONDict(value) else { return [] }

        if let payload = dict.value("data") {
            if let array = payload.arrayValue { return array.compactMap { JSONDict($0) } }
            if let object = payload.objectValue { return Self.fold(object) }
            return []
        }
        return Self.fold(dict.raw)
    }

    func runList(_ snippet: PHPSnippet) async throws -> [JSONDict] {
        let value = try await run(snippet)
        return Self.rows(from: value)
    }

    /// Turns a keyed object into rows, keeping the key.
    ///
    /// The key is the row's own name in every case this handles — a gateway
    /// name, an interface name — so it is folded in as `name` when the row
    /// does not already carry one. Losing it would leave rows that cannot be
    /// told apart.
    private static func fold(_ object: [String: JSONValue]) -> [JSONDict] {
        object.compactMap { key, value in
            guard var row = JSONDict(value)?.raw else { return nil }
            if row["name"] == nil { row["name"] = .string(key) }
            return JSONDict(row)
        }
        .sorted { ($0.string("name") ?? "") < ($1.string("name") ?? "") }
    }

    private func perform(_ snippet: PHPSnippet, timeout: TimeInterval? = nil) async throws -> JSONValue {
        try Task.checkCancellation()
        guard profile.isConfigured else { throw RPCError.notConfigured }
        guard let password = Keychain.password(for: profile.id), !password.isEmpty else {
            throw RPCError.noCredentials
        }
        guard let base = URL(string: profile.baseURL.trimmingCharacters(in: .whitespaces)),
              let url = URL(string: "/xmlrpc.php", relativeTo: base)
        else { throw RPCError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let timeout { request.timeoutInterval = timeout }
        request.httpBody = Self.methodCall(script: snippet.script).data(using: .utf8)

        // Basic auth, supplied up front rather than waiting for a challenge.
        // The credential goes over the wire on every call — XML-RPC has no
        // session or token — which is the single biggest cost of this
        // transport and is documented rather than hidden.
        let pair = "\(profile.username):\(password)"
        if let encoded = pair.data(using: .utf8)?.base64EncodedString() {
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .serverCertificateUntrusted,
                 .serverCertificateHasBadDate,
                 .serverCertificateHasUnknownRoot,
                 .serverCertificateNotYetValid,
                 .secureConnectionFailed:
                throw RPCError.tls
            case .cancelled:
                throw RPCError.cancelled
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed:
                // The system already knows there is no route. Retrying waits
                // another fifteen seconds to be told the same thing, and a
                // refresh makes five of these — which is how the app sat on
                // stale readings for minutes after the Wi-Fi went off.
                throw RPCError.offline(error.localizedDescription)
            default:
                throw RPCError.transport(error.localizedDescription)
            }
        } catch is CancellationError {
            throw RPCError.cancelled
        } catch {
            throw RPCError.transport(error.localizedDescription)
        }

        let body = String(data: data, encoding: .utf8)

        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200...299: break
        case 401: throw RPCError.unauthorized
        case 403: throw RPCError.forbidden
        case let code:
            // pfSense returns XML-RPC faults with a 500 status, so the body
            // carries the firewall's own explanation. Throwing on the status
            // alone discarded it and left "HTTP 500" to be guessed at.
            if let body, body.contains("<fault>") {
                return try Self.decode(body)   // throws the fault, with its message
            }
            throw RPCError.transport("Firewall returned HTTP \(code).")
        }

        guard let body else { throw RPCError.malformed(nil) }
        return try Self.decode(body)
    }

    private func perform(_ snippet: PHPSnippet, params: [String: JSONValue], timeout: TimeInterval? = nil) async throws -> JSONValue {
        try Task.checkCancellation()
        guard profile.isConfigured else { throw RPCError.notConfigured }
        guard let password = Keychain.password(for: profile.id), !password.isEmpty else {
            throw RPCError.noCredentials
        }
        guard let base = URL(string: profile.baseURL.trimmingCharacters(in: .whitespaces)),
              let url = URL(string: "/xmlrpc.php", relativeTo: base)
        else { throw RPCError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let timeout { request.timeoutInterval = timeout }
        request.httpBody = Self.methodCall(script: snippet.script, params: params).data(using: .utf8)

        let pair = "\(profile.username):\(password)"
        if let encoded = pair.data(using: .utf8)?.base64EncodedString() {
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .serverCertificateUntrusted,
                 .serverCertificateHasBadDate,
                 .serverCertificateHasUnknownRoot,
                 .serverCertificateNotYetValid,
                 .secureConnectionFailed:
                throw RPCError.tls
            case .cancelled:
                throw RPCError.cancelled
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed:
                throw RPCError.offline(error.localizedDescription)
            default:
                throw RPCError.transport(error.localizedDescription)
            }
        } catch is CancellationError {
            throw RPCError.cancelled
        } catch {
            throw RPCError.transport(error.localizedDescription)
        }

        let body = String(data: data, encoding: .utf8)

        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200...299: break
        case 401: throw RPCError.unauthorized
        case 403: throw RPCError.forbidden
        case let code:
            if let body, body.contains("<fault>") {
                return try Self.decode(body)
            }
            throw RPCError.transport("Firewall returned HTTP \(code).")
        }

        guard let body else { throw RPCError.malformed(nil) }
        return try Self.decode(body)
    }

    // MARK: Encoding

    static func methodCall(script: String) -> String {
        """
        <?xml version="1.0"?>
        <methodCall>
        <methodName>pfsense.exec_php</methodName>
        <params><param><value><string>\(escape(script))</string></value></param></params>
        </methodCall>
        """
    }

    static func methodCall(script: String, params: [String: JSONValue]) -> String {
        // Encode params as a JSON string, then base64 to avoid all quoting issues.
        var parts: [String] = []
        for (key, value) in params {
            switch value {
            case .string(let s):
                parts.append("\"\(key)\":\"\(s)\"")
            case .number(let n):
                parts.append("\"\(key)\":\(n)")
            case .bool(let b):
                parts.append("\"\(key)\":\(b ? "true" : "false")")
            case .null:
                parts.append("\"\(key)\":null")
            case .object, .array:
                parts.append("\"\(key)\":null")
            }
        }
        let paramsJSON = "{\(parts.joined(separator: ","))}"
        let paramsB64 = Data(paramsJSON.utf8).base64EncodedString()
        
        let wrappedScript = "$_PARAMS = json_decode(base64_decode('\(paramsB64)'), true); \(script)"
        return """
        <?xml version="1.0"?>
        <methodCall>
        <methodName>pfsense.exec_php</methodName>
        <params><param><value><string>\(escape(wrappedScript))</string></value></param></params>
        </methodCall>
        """
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<")
         .replacingOccurrences(of: "&gt;", with: ">")
         .replacingOccurrences(of: "&quot;", with: "\"")
         .replacingOccurrences(of: "&apos;", with: "'")
         .replacingOccurrences(of: "&#039;", with: "'")
         // Last, or an escaped entity in the payload would be double-decoded.
         .replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: Decoding

    /// Pulls the JSON payload out of an XML-RPC response.
    ///
    /// Deliberately not a general XML-RPC parser. Every snippet returns a
    /// struct with a single `real` member holding JSON, so the job is to find
    /// that string, unescape it, and hand it to `JSONDecoder`. A fault
    /// response is recognised and reported with the firewall's own message,
    /// since that is where a PHP error in a snippet surfaces.
    /// The first useful line of a response that was not XML-RPC.
    ///
    /// Trimmed hard: a PHP fatal names its function and file in the first line
    /// and then prints a stack trace, and an HTML error page is mostly markup.
    /// Enough to identify the failure, not enough to paste a page into an
    /// alert.
    static func excerpt(_ body: String) -> String? {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return text.count > 200 ? String(text.prefix(200)) + "…" : text
    }

    static func decode(_ xml: String) throws -> JSONValue {
        if xml.contains("<fault>") {
            let code = Int(extract(xml, "int") ?? extract(xml, "i4") ?? "") ?? 0
            let message = extract(xml, "string").map(unescape) ?? "no detail"
            throw RPCError.fault(code, message)
        }
        guard let raw = extract(xml, "string") else { throw RPCError.malformed(excerpt(xml)) }
        let json = unescape(raw)
        guard let data = json.data(using: .utf8) else { throw RPCError.malformed(nil) }
        let value: JSONValue
        do {
            value = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw RPCError.malformed(excerpt(json))
        }
        // The wrapper sets this when a snippet finished without assigning a
        // result — a PHP fatal or a memory limit, which otherwise arrives as
        // an empty list and reads as "nothing configured".
        if let reported = JSONDict(value)?.string("__error") {
            throw RPCError.fault(0, reported)
        }
        return value
    }

    private static func extract(_ xml: String, _ tag: String) -> String? {
        guard let open = xml.range(of: "<\(tag)>"),
              let close = xml.range(of: "</\(tag)>", range: open.upperBound..<xml.endIndex)
        else { return nil }
        return String(xml[open.upperBound..<close.lowerBound])
    }
}
