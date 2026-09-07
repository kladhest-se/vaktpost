import Foundation
import os.log

private let apiLog = OSLog(subsystem: "se.kladhest.vaktpost", category: "API")

// MARK: - Errors

enum APIError: LocalizedError, Equatable {
    case notConfigured
    case badURL
    case noAPIKey
    case unauthorized
    case forbidden
    case notFound(String)
    case server(Int, String)
    case tls
    case transport(String)
    case decoding
    /// The request was cancelled — app backgrounded, firewall switched, or a
    /// refresh superseded. Not a failure, and never shown.
    case cancelled

    /// True for transient network problems worth retrying (DNS timeouts,
    /// Wi-Fi handoffs, ECONNRESET). Authentication and TLS failures are
    /// never retried.
    var isRetryable: Bool {
        if case .transport = self { return true }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "No firewall configured yet."
        case .badURL: return "That base URL isn't valid."
        case .noAPIKey: return "No API key stored."
        case .unauthorized: return "The API key was rejected (401)."
        case .forbidden: return "This key lacks privileges for that endpoint (403)."
        case .notFound(let p): return "Endpoint not available on this firewall: \(p)"
        case .server(let c, let m): return m.isEmpty ? "Firewall returned HTTP \(c)." : m
        case .tls: return "TLS handshake failed. Pin the certificate or enable untrusted TLS in Settings."
        case .transport(let m): return m
        case .decoding: return "The response didn't look like the REST API v2 format."
        case .cancelled: return "Cancelled."
        }
    }
}

// MARK: - Envelope

/// Every v2 response is wrapped:
/// `{"code":200,"status":"ok","response_id":"SUCCESS","message":"","data":…}`
private struct Envelope: Decodable {
    let code: Int?
    let status: String?
    let message: String?
    let data: JSONValue?
}

// MARK: - Client

actor APIClient {

    private var profile: ServerProfile
    private let session: URLSession
    private let trust: TrustEvaluator

    init(profile: ServerProfile) {
        self.profile = profile
        let evaluator = TrustEvaluator(profile: profile)
        self.trust = evaluator

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        self.session = URLSession(configuration: config, delegate: evaluator, delegateQueue: nil)
    }

    func update(profile: ServerProfile) {
        self.profile = profile
        trust.configure(with: profile)
    }

    var lastSeenFingerprint: String? { trust.lastSeenFingerprint }

    // MARK: Raw request

    /// Returns the decoded `data` member of the envelope.
    private func get(_ path: String, query: [URLQueryItem] = []) async throws -> JSONValue {
        guard profile.isConfigured else { throw APIError.notConfigured }
        guard let apiKey = Keychain.apiKey(for: profile.id), !apiKey.isEmpty else {
            throw APIError.noAPIKey
        }
        guard var comps = URLComponents(string: profile.baseURL.trimmingCharacters(in: .whitespaces)) else {
            throw APIError.badURL
        }
        comps.path = path
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw APIError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        /// Attempt the request with retries for transient transport errors.
        ///
        /// Transport errors like DNS timeouts, ECONNRESET, or Wi-Fi handoffs
        /// are worth one retry. Authentication and TLS failures are never
        /// retried — they only get worse.
        func attempt() async throws -> JSONValue {
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: req)
            } catch let err as URLError {
                switch err.code {
                case .serverCertificateUntrusted,
                     .serverCertificateHasBadDate,
                     .serverCertificateHasUnknownRoot,
                     .serverCertificateNotYetValid,
                     .secureConnectionFailed:
                    throw APIError.tls

                case .cancelled:
                    throw APIError.cancelled

                default:
                    throw APIError.transport(err.localizedDescription)
                }
            } catch {
                throw APIError.transport(error.localizedDescription)
            }

            let http = response as? HTTPURLResponse
            let code = http?.statusCode ?? 0

            let envelope: Envelope?
            do {
                envelope = try JSONDecoder().decode(Envelope.self, from: data)
            } catch {
                // Non-200 responses may not be JSON at all (HTML errors, etc.),
                // so a decode failure on error codes is benign.
                if code >= 400 {
                    envelope = nil
                } else {
                    os_log(.error, log: apiLog, "Decode failed on %{public}d: %{public}@", code, String(data: data.prefix(512), encoding: .utf8) ?? "<non-utf8>")
                    throw APIError.decoding
                }
            }

            switch code {
            case 200...299:
                guard let payload = envelope?.data else { throw APIError.decoding }
                return payload
            case 401:
                throw APIError.unauthorized
            case 403:
                throw APIError.forbidden
            case 404:
                throw APIError.notFound(path)
            default:
                throw APIError.server(code, envelope?.message ?? "")
            }
        }

        do {
            return try await attempt()
        } catch let err as APIError where err.isRetryable {
            // One retry with a short delay for transient transport errors.
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            return try await attempt()
        }
    }

    private func getObject(_ path: String, query: [URLQueryItem] = []) async throws -> JSONDict {
        let value = try await get(path, query: query)
        guard let dict = JSONDict(value) else { throw APIError.decoding }
        return dict
    }

    private func getList(_ path: String, query: [URLQueryItem] = []) async throws -> [JSONDict] {
        let value = try await get(path, query: query)
        guard let arr = value.arrayValue else { throw APIError.decoding }
        return arr.compactMap { JSONDict($0) }
    }

    private func page(limit: Int, offset: Int = 0) -> [URLQueryItem] {
        [URLQueryItem(name: "limit", value: String(limit)),
         URLQueryItem(name: "offset", value: String(offset))]
    }

    // MARK: Endpoints (read-only)

    func systemStatus() async throws -> SystemStatus {
        SystemStatus(try await getObject("/api/v2/status/system"))
    }

    func systemVersion() async throws -> SystemVersion {
        SystemVersion(try await getObject("/api/v2/system/version"))
    }

    func interfaces() async throws -> [InterfaceStat] {
        try await getList("/api/v2/status/interfaces", query: page(limit: 100))
            .map(InterfaceStat.init)
    }

    func gateways() async throws -> [GatewayStatus] {
        try await getList("/api/v2/status/gateways", query: page(limit: 50))
            .map(GatewayStatus.init)
    }

    func services() async throws -> [ServiceStatus] {
        try await getList("/api/v2/status/services", query: page(limit: 200))
            .map(ServiceStatus.init)
    }

    func leases() async throws -> [DHCPLease] {
        try await getList("/api/v2/status/dhcp_server/leases", query: page(limit: 500))
            .map(DHCPLease.init)
    }

    func arpTable() async throws -> [ARPEntry] {
        try await getList("/api/v2/diagnostics/arp_table", query: page(limit: 500))
            .map(ARPEntry.init)
    }

    func firewallLog(limit: Int) async throws -> [LogLine] {
        try await getList("/api/v2/status/logs/firewall", query: page(limit: limit))
            .map { LogLine($0, kind: .firewall) }
    }

    func systemLog(limit: Int) async throws -> [LogLine] {
        try await getList("/api/v2/status/logs/system", query: page(limit: limit))
            .map { LogLine($0, kind: .system) }
    }

    /// The authentication log — webConfigurator, SSH and API login attempts.
    ///
    /// Arguably the most useful of the five on an internet-facing firewall,
    /// and the one that tells you whether Login Protection is earning its keep.
    func authLog(limit: Int) async throws -> [LogLine] {
        try await getList("/api/v2/status/logs/auth", query: page(limit: limit))
            .map { LogLine($0, kind: .auth) }
    }

    func dhcpLog(limit: Int) async throws -> [LogLine] {
        try await getList("/api/v2/status/logs/dhcp", query: page(limit: limit))
            .map { LogLine($0, kind: .dhcp) }
    }

    func openvpnLog(limit: Int) async throws -> [LogLine] {
        try await getList("/api/v2/status/logs/openvpn", query: page(limit: limit))
            .map { LogLine($0, kind: .openvpn) }
    }

    func stateTableSize() async throws -> StateTableSize {
        StateTableSize(try await getObject("/api/v2/firewall/states/size"))
    }

    // MARK: Clients

    func staticMappings() async throws -> [StaticMapping] {
        try await getList("/api/v2/services/dhcp_server/static_mappings", query: page(limit: 500))
            .map(StaticMapping.init)
    }

    // MARK: VPN

    func openvpnServers() async throws -> [OpenVPNServerStatus] {
        try await getList("/api/v2/status/openvpn/servers", query: page(limit: 50))
            .map(OpenVPNServerStatus.init)
    }

    func openvpnClients() async throws -> [OpenVPNServerStatus] {
        try await getList("/api/v2/status/openvpn/clients", query: page(limit: 50))
            .map(OpenVPNServerStatus.init)
    }

    func ipsecSAs() async throws -> [IPsecSA] {
        try await getList("/api/v2/status/ipsec/sas", query: page(limit: 100))
            .map(IPsecSA.init)
    }

    func wireguardTunnels() async throws -> [WireGuardTunnel] {
        try await getList("/api/v2/status/wireguard/tunnels", query: page(limit: 50))
            .map(WireGuardTunnel.init)
    }

    func wireguardPeers() async throws -> [WireGuardPeer] {
        try await getList("/api/v2/status/wireguard/peers", query: page(limit: 200))
            .map(WireGuardPeer.init)
    }

    // MARK: Firewall objects

    func firewallRules() async throws -> [FirewallRule] {
        try await getList("/api/v2/firewall/rules", query: page(limit: 500))
            .map(FirewallRule.init)
    }

    func firewallAliases() async throws -> [FirewallAliasEntry] {
        try await getList("/api/v2/firewall/aliases", query: page(limit: 300))
            .map(FirewallAliasEntry.init)
    }

    func portForwards() async throws -> [PortForward] {
        try await getList("/api/v2/firewall/nat/port_forwards", query: page(limit: 300))
            .map(PortForward.init)
    }

    // MARK: System detail

    func carp() async throws -> CARPStatus {
        CARPStatus(try await getObject("/api/v2/status/carp"))
    }

    func configHistory() async throws -> [ConfigRevision] {
        try await getList("/api/v2/diagnostics/config_history/revisions", query: page(limit: 50))
            .map(ConfigRevision.init)
    }

    /// Certificates and CAs come from two endpoints but are one concern to the
    /// person reading the alerts list, so they are merged here.
    func certificates() async throws -> [CertificateInfo] {
        var out = try await getList("/api/v2/system/certificates", query: page(limit: 200))
            .map { CertificateInfo($0, isCA: false) }
        if let cas = try? await getList("/api/v2/system/certificate_authorities", query: page(limit: 100)) {
            out += cas.map { CertificateInfo($0, isCA: true) }
        }
        return out
    }

    func packages() async throws -> [PackageInfo] {
        try await getList("/api/v2/system/packages", query: page(limit: 100))
            .map(PackageInfo.init)
    }

    /// Every pf table with its contents.
    ///
    /// Deliberately not part of the periodic refresh: `bogons` alone runs to
    /// thousands of rows, and pulling that down every thirty seconds to render
    /// a blocked-hosts list nobody is looking at is the kind of thing that
    /// makes a phone warm.
    func tables() async throws -> [FirewallTable] {
        try await getList("/api/v2/diagnostics/tables", query: page(limit: 200))
            .map(FirewallTable.init)
    }

    /// Cheap call used to validate credentials during onboarding.
    func ping() async throws -> String {
        let v = try await systemVersion()
        return v.current ?? "connected"
    }
}
