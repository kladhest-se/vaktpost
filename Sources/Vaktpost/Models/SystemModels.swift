import Foundation

// MARK: - CARP / HA

struct CARPStatus {
    var enabled: Bool?
    var maintenanceMode: Bool?
    var interfaces: [CARPInterface]

    init(_ d: JSONDict) {
        enabled = d.bool("enable", "enabled")
        maintenanceMode = d.bool("maintenance_mode", "maintenancemode")
        interfaces = d.list("interfaces", "vips").compactMap { JSONDict($0) }.map(CARPInterface.init)
    }

    /// Whether this firewall does HA at all.
    ///
    /// `enabled != nil` was too loose: the endpoint answers on every firewall,
    /// so a standalone box reported "configured" and the Overview carried a
    /// permanent "CARP disabled" row telling you about a feature you are not
    /// using. Something has to actually be switched on or present.
    var isConfigured: Bool { enabled == true || !interfaces.isEmpty }

    var health: Health {
        if maintenanceMode == true { return .warn }
        if enabled == false { return .idle }
        if interfaces.contains(where: { $0.health == .bad }) { return .bad }
        return interfaces.isEmpty ? .idle : .ok
    }

    var summary: String {
        if enabled == false { return "CARP disabled" }
        if maintenanceMode == true { return "Persistent maintenance mode" }
        let master = interfaces.filter { $0.status.contains("master") }.count
        let backup = interfaces.filter { $0.status.contains("backup") }.count
        if interfaces.isEmpty { return "No CARP virtual IPs" }
        return "\(master) master · \(backup) backup"
    }
}

struct CARPInterface: Identifiable {
    var id: String { "\(interfaceName)-\(vhid)" }
    var interfaceName: String
    var vhid: String
    var status: String
    var subnet: String?

    init(_ d: JSONDict) {
        interfaceName = d.string("interface", "if") ?? "—"
        vhid = d.string("vhid", "vhid_group") ?? ""
        status = (d.string("status", "state") ?? "unknown").lowercased()
        subnet = d.string("subnet", "address")
    }

    var health: Health {
        if status.contains("master") { return .ok }
        if status.contains("backup") { return .info }
        if status.contains("init") { return .warn }
        return .bad
    }
}

// MARK: - Config history

struct ConfigRevision: Identifiable {
    var id: String { "\(time)-\(version)" }
    var time: String
    var version: String
    var descr: String
    var username: String?
    var size: Int?

    init(_ d: JSONDict) {
        time = d.string("time", "timestamp") ?? ""
        version = d.string("version") ?? ""
        descr = d.string("description", "descr") ?? ""
        username = d.string("username", "user")
        size = d.int("filesize", "size")
    }

    /// The `time` field is a unix timestamp on most builds.
    var date: Date? {
        guard let secs = Double(time) else { return nil }
        return Date(timeIntervalSince1970: secs)
    }

    var displayTime: String {
        guard let date else { return time }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - Certificates

struct CertificateInfo: Identifiable {
    var id: String { refID.isEmpty ? descr : refID }
    var refID: String
    var descr: String
    var validFrom: Date?
    var validUntil: Date?
    var isCA: Bool
    /// Managed by the ACME package, and therefore shown on its own screen
    /// rather than twice.
    var isACME: Bool

    init(_ d: JSONDict, isCA: Bool = false) {
        isACME = d.bool("is_acme") ?? false
        refID = d.string("refid", "id") ?? ""
        descr = d.string("descr", "description", "name") ?? "certificate"
        self.isCA = isCA
        validFrom = Self.parse(d.value("valid_from", "validfrom", "not_before"))
        validUntil = Self.parse(d.value("valid_until", "validuntil", "not_after", "expires"))
    }

    private static func parse(_ v: JSONValue?) -> Date? {
        guard let v else { return nil }
        if let n = v.doubleValue, n > 1_000_000_000 { return Date(timeIntervalSince1970: n) }
        guard let s = v.stringValue else { return nil }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd HH:mm:ss", "MMM d HH:mm:ss yyyy zzz", "yyyy-MM-dd'T'HH:mm:ssZ"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    /// How long is left, in the terms somebody actually asks in.
    ///
    /// "expired 3 days ago" and "3 days left" are different enough situations
    /// that a signed number would be a poor way to say it.
    var expiryDescription: String {
        guard let days = daysRemaining else { return "no expiry date" }
        if days < 0 { return "expired \(-days)d ago" }
        if days == 0 { return "expires today" }
        if days < 60 { return "\(days)d left" }
        return "\(days / 30) months left"
    }

    var daysRemaining: Int? {
        guard let validUntil else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: validUntil).day
    }

    var health: Health {
        guard let days = daysRemaining else { return .idle }
        if days < 0 { return .bad }
        if days <= 14 { return .bad }
        if days <= 30 { return .warn }
        return .ok
    }
}

// MARK: - Packages

struct PackageInfo: Identifiable {
    var id: String { name }
    var name: String
    var shortName: String
    var descr: String?
    var installedVersion: String?
    var latestVersion: String?
    var updateAvailable: Bool

    init(_ d: JSONDict) {
        name = d.string("name") ?? "—"
        shortName = d.string("shortname") ?? name
            .replacingOccurrences(of: "pfSense-pkg-", with: "")
        // Descriptions carry hard line breaks from the package manifest.
        // Manifests carry hard line breaks and markup — pfBlockerNG's runs to
        // six lines with <br /> in it, which renders as literal tags in a
        // one-line summary.
        descr = d.string("descr", "description")
            .map { raw -> String in
                var text = raw.replacingOccurrences(of: "<br />", with: " ")
                text = text.replacingOccurrences(of: "<br/>", with: " ")
                text = text.replacingOccurrences(of: "<br>", with: " ")
                text = text.replacingOccurrences(of: "\n", with: " ")
                text = text.replacingOccurrences(of: "\t", with: " ")
                while text.contains("  ") {
                    text = text.replacingOccurrences(of: "  ", with: " ")
                }
                return text.trimmingCharacters(in: .whitespaces)
            }
        installedVersion = d.string("installed_version")
        latestVersion = d.string("latest_version")
        updateAvailable = d.bool("update_available") ?? false
    }

    var health: Health { updateAvailable ? .warn : .ok }

    var versionLine: String {
        guard let installed = installedVersion else { return "—" }
        if updateAvailable, let latest = latestVersion, latest != installed {
            return "\(installed) → \(latest)"
        }
        return installed
    }
}

// MARK: - pf tables

/// A pf table and its contents (`diagnostics/tables`).
///
/// Interesting ones: `sshguard` holds addresses Login Protection has blocked,
/// and `virusprot` holds those blocked by packages. The rest are the alias and
/// interface-network tables pf builds for itself.
struct FirewallTable: Identifiable {
    var id: String { name }
    var name: String
    var entries: [String]
    /// The real count, which may exceed what is retained below.
    var entryCount: Int

    /// Entries are capped because `bogons` runs to thousands of rows and there
    /// is no reason to hold them in memory on a phone. The count stays honest.
    private static let retain = 200

    init(_ d: JSONDict) {
        name = d.string("name", "id") ?? "—"
        let all = d.list("entries").compactMap { $0.stringValue }
        entryCount = all.count
        entries = Array(all.prefix(Self.retain))
    }

    var isTruncated: Bool { entryCount > entries.count }

    /// The tables worth showing a person, in the order they matter.
    static let notable = ["sshguard", "virusprot", "snort2c"]

    var isNotable: Bool { Self.notable.contains(name.lowercased()) }
}

// MARK: - Filesystems

/// One mounted filesystem (`get_mounted_filesystems`).
///
/// The REST transport reported a single aggregate `disk_usage`, so a full
/// `/var` on a box with a mostly-empty root looked like 40% and nobody noticed
/// until logging stopped.
struct Filesystem: Identifiable {
    var id: String { mountpoint }
    var mountpoint: String
    var device: String?
    var type: String?
    var percentUsed: Double?
    var totalSize: String?
    var used: String?
    var available: String?

    init(_ d: JSONDict) {
        mountpoint = d.string("mountpoint") ?? "/"
        device = d.string("device", "filesystem")
        type = d.string("type")
        percentUsed = d.double("percent_used", "percent")
        totalSize = d.string("total_size", "size")
        used = d.string("used")
        available = d.string("avail", "available")
    }

    var health: Health {
        guard let percentUsed else { return .idle }
        if percentUsed >= 92 { return .bad }
        if percentUsed >= 80 { return .warn }
        return .ok
    }
}

// MARK: - Notices

/// A pfSense system notice — what the bell icon in the webConfigurator shows.
///
/// Not reachable over the REST API at all. This is where pfSense puts the
/// things it decided a human needed to see: failed package installs, gateway
/// alarms, certificate problems, config-sync failures.
struct SystemNotice: Identifiable {
    var id: String { "\(createdAt)-\(notice)" }
    var createdAt: String
    var notice: String
    var category: String?
    var url: String?
    var priority: Int?

    init(_ d: JSONDict) {
        createdAt = d.string("created_at", "time") ?? ""
        // pfSense stores notices HTML-escaped, so a PHP stack trace arrives
        // full of &gt; and &#039;.
        notice = Self.decodeEntities(d.string("notice", "message") ?? "")
        category = d.string("category", "id")
        url = d.string("url")
        priority = d.int("priority")
    }

    static func decodeEntities(_ raw: String) -> String {
        var out = raw
        for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
                                    ("&#039;", "'"), ("&apos;", "'"), ("&nbsp;", " ")] {
            out = out.replacingOccurrences(of: entity, with: character)
        }
        // Last, or an escaped entity in the text would be decoded twice.
        return out.replacingOccurrences(of: "&amp;", with: "&")
    }

    /// The first line, which for a PHP error is the part naming the problem.
    ///
    /// A notice can be an entire stack trace. Shown whole it fills the screen
    /// and buries the five other alerts under it, so the list shows this and
    /// offers the rest on tap.
    var summary: String {
        let firstLine = notice.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? notice
        return firstLine.count > 160 ? String(firstLine.prefix(160)) + "…" : firstLine
    }

    var isMultiline: Bool { notice.contains("\n") || notice.count > 160 }

    /// Whether this notice is the app's own doing.
    ///
    /// A snippet that throws is recorded by pfSense as a notice, which the app
    /// then reads back and displays — so a bug in this app appears as a
    /// firewall problem. Saying which is which seems the least it can do.
    var isFromThisApp: Bool {
        notice.contains("xmlrpc.php") && notice.contains("eval()")
    }

    var date: Date? {
        guard let seconds = Double(createdAt) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    var displayTime: String {
        guard let date else { return createdAt }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    /// pfSense priorities run 1 (highest) upward.
    var health: Health {
        guard let priority else { return .warn }
        return priority <= 1 ? .bad : .warn
    }
}

// MARK: - Dynamic DNS

/// A dynamic DNS entry and the address it last pushed.
///
/// pfSense keeps no update history — only a per-entry cache file holding the
/// last address sent, and its modification time. So "when did this last
/// change", not "when was it last checked". An entry whose cached address no
/// longer matches the interface it watches is the failure worth catching, and
/// that comparison is done in `DashboardStore`.
struct DyndnsEntry: Identifiable {
    var id: String { "\(host)-\(type ?? "")" }
    var host: String
    var type: String?
    var interfaceName: String?
    var descr: String?
    var enabled: Bool
    var cachedAddress: String?
    var updatedAt: Date?

    init(_ d: JSONDict) {
        host = d.string("host") ?? "—"
        type = d.string("type")
        interfaceName = d.string("interface")
        descr = d.string("descr", "description")
        enabled = d.bool("enabled", "enable") ?? true
        let cached = d.string("cached_address")
        cachedAddress = (cached?.isEmpty ?? true) ? nil : cached
        if let seconds = d.double("updated_at"), seconds > 0 {
            updatedAt = Date(timeIntervalSince1970: seconds)
        }
    }

    var displayName: String {
        if let descr, !descr.isEmpty { return descr }
        return host
    }

    var updatedDescription: String {
        guard let updatedAt else { return "never updated" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: updatedAt)
    }
}

// MARK: - HAProxy

/// One server behind a backend.
struct HAProxyServer: Identifiable {
    var id: String { "\(name)-\(address):\(port)" }
    var name: String
    var address: String
    var port: String
    var enabled: Bool
    var ssl: Bool
    var weight: String?

    init(_ d: JSONDict) {
        name = d.string("name") ?? "—"
        address = d.string("address") ?? ""
        port = d.string("port") ?? ""
        enabled = d.bool("enabled") ?? true
        ssl = d.bool("ssl") ?? false
        let w = d.string("weight")
        weight = (w?.isEmpty ?? true) ? nil : w
    }

    var endpoint: String {
        port.isEmpty ? address : "\(address):\(port)"
    }

    var health: Health { enabled ? .ok : .idle }
}

/// A backend, which the pfSense package calls a pool.
struct HAProxyBackend: Identifiable {
    var id: String { name }
    var name: String
    var descr: String?
    var balance: String?
    var checkType: String?
    var checkURI: String?
    var checkInterval: String?
    var servers: [HAProxyServer]

    init(_ d: JSONDict) {
        name = d.string("name") ?? "—"
        descr = d.string("descr")
        balance = d.string("balance")
        checkType = d.string("check_type")
        checkURI = d.string("check_uri")
        checkInterval = d.string("check_interval")
        servers = d.list("servers").compactMap { JSONDict($0) }.map(HAProxyServer.init)
    }

    /// Whether HAProxy is checking these servers at all.
    ///
    /// The distinction that matters: a backend with no health check keeps
    /// sending traffic to a server after it dies. HAProxy will happily do that
    /// — it only knows a server is down if something told it to look.
    var isMonitored: Bool {
        guard let checkType, !checkType.isEmpty else { return false }
        return checkType.lowercased() != "none"
    }

    var checkDescription: String {
        guard isMonitored, let checkType else { return "no health check" }
        var parts = [checkType]
        if let uri = checkURI, !uri.isEmpty { parts.append(uri) }
        if let interval = checkInterval, !interval.isEmpty {
            parts.append("every \(interval)ms")
        } else {
            // Blank means HAProxy's own default rather than no interval, and
            // "HTTP · " trailing into nothing reads like missing data.
            parts.append("default interval")
        }
        return parts.joined(separator: " · ")
    }

    /// Unmonitored is the condition worth flagging; a disabled server is a
    /// choice somebody made.
    var health: Health {
        if servers.isEmpty { return .idle }
        if !isMonitored { return .warn }
        return servers.contains(where: \.enabled) ? .ok : .idle
    }
}

/// A frontend, which the package confusingly calls a backend.
struct HAProxyFrontend: Identifiable {
    var id: String { name }
    var name: String
    var descr: String?
    var type: String?
    var binds: [String]
    var aclCount: Int
    var backendName: String?
    var enabled: Bool

    init(_ d: JSONDict) {
        name = d.string("name") ?? "—"
        descr = d.string("descr")
        type = d.string("type")
        binds = d.list("binds").compactMap { $0.stringValue }
        aclCount = d.int("acl_count") ?? 0
        backendName = d.string("backend")
        // The package stores "active" here, and omits it when disabled.
        enabled = (d.string("status") ?? "active") == "active"
    }

    var health: Health { enabled ? .ok : .idle }

    var bindDescription: String {
        binds.isEmpty ? "no bind address" : binds.joined(separator: ", ")
    }

    /// What this frontend does with a request when no default backend is set.
    var routingDescription: String? {
        if let backendName, !backendName.isEmpty { return backendName }
        if aclCount > 0 { return "\(aclCount) ACL rule\(aclCount == 1 ? "" : "s")" }
        return nil
    }
}

// MARK: - ACME

/// An ACME account key. Its server URL says production or staging.
struct ACMEAccount: Identifiable {
    var id: String { name }
    var name: String
    var descr: String?
    var server: String?

    init(_ d: JSONDict) {
        name = d.string("name") ?? "—"
        descr = d.string("descr")
        server = d.string("server")
    }

    /// A staging certificate is not trusted by anything, which is worth
    /// saying out loud when it is sitting in front of a public service.
    var isStaging: Bool {
        (server ?? "").lowercased().contains("staging")
    }
}

/// An ACME certificate: the automation, not the certificate itself.
///
/// The certificate store says when something expires. This says whether
/// anything is going to renew it — a Let's Encrypt certificate with 40 days
/// left is fine if renewal is configured and a problem if it is not.
struct ACMECertificate: Identifiable {
    var id: String { name }
    var name: String
    var descr: String?
    var account: String?
    var renewAfter: String?
    var enabled: Bool
    var domains: [String]

    init(_ d: JSONDict) {
        name = d.string("name") ?? "—"
        descr = d.string("descr")
        account = d.string("account")
        renewAfter = d.string("renew_after")
        enabled = d.bool("enabled") ?? false
        domains = d.list("domains").compactMap { $0.stringValue }
    }

    var renewalDescription: String {
        guard enabled else { return "renewal disabled" }
        guard let renewAfter, !renewAfter.isEmpty else { return "renews on the package default" }
        return "renews after \(renewAfter) days"
    }

    /// A disabled entry is the condition worth flagging: the certificate will
    /// expire and nothing will notice.
    var health: Health { enabled ? .ok : .warn }
}

// MARK: - RRD history

/// One series of historical traffic, as pfSense recorded it.
struct RRDSeries: Identifiable, Sendable {
    var id: String { "\(file)-\(name)" }
    /// The interface the file belongs to, as pfSense names its files — `wan`,
    /// `opt3`, `lan`. Not the administrator's label, so it needs the same
    /// lookup everything else on screen gets.
    var file: String
    var name: String
    var points: [(at: Date, value: Double)]

    /// How many values the firewall had, and how many survived the filter.
    ///
    /// The difference is the diagnosis: equal and zero means nothing is
    /// recorded, a large drop means every value came back unknown, which is a
    /// different problem with a different fix.
    var valuesSeen: Int
    var valuesKept: Int

    /// When pfSense last wrote to this file.
    ///
    /// A day of unknown values has one dull explanation — the file is not
    /// being updated — and this is the number that separates it from the
    /// interesting ones.
    var lastUpdate: Date?
    var ageSeconds: Int

    /// Which resolution produced this series, in seconds; 0 means rrdtool's
    /// default was used after the five-minute request came up empty.
    var resolution: Int

    init(_ d: JSONDict) {
        file = d.string("file") ?? "?"
        name = d.string("series") ?? "?"
        lastUpdate = (d.int("last_update") ?? 0) > 0
            ? Date(timeIntervalSince1970: TimeInterval(d.int("last_update") ?? 0))
            : nil
        ageSeconds = d.int("age_seconds") ?? -1
        resolution = d.int("resolution") ?? 0
        valuesSeen = d.int("values_seen") ?? 0
        valuesKept = d.int("values_kept") ?? 0
        points = d.list("points").compactMap { entry in
            guard let row = JSONDict(entry),
                  let at = row.int("at"),
                  let value = row.double("value") else { return nil }
            return (Date(timeIntervalSince1970: TimeInterval(at)), value)
        }
    }

    /// The most recent sample that carries a value.
    ///
    /// Not the same as the file's last write: a file written a minute ago can
    /// still have nothing recorded in the last day, which is the state this
    /// firewall is in.
    var newestSample: Date? { points.last?.at }

    /// RRD stores traffic as bytes per second; the app speaks bits.
    var bitsPerSecond: [Double] { points.map { $0.value * 8 } }

    /// Whether this is traffic that was passed, rather than blocked.
    ///
    /// A pfSense traffic file holds eight data sources — pass and block, in
    /// and out, v4 and v6. Drawing all eight puts six near-flat lines under
    /// the two that matter, and the app has nowhere to explain which is which.
    var isPassSeries: Bool {
        let lower = name.lowercased()
        return lower.contains("pass") || lower == "in" || lower == "out"
    }

    var isInbound: Bool { name.lowercased().hasPrefix("in") }
}

/// What the firewall could tell us about its own history.
struct RRDHistory: Sendable {
    var available: Bool
    var series: [RRDSeries]

    init(_ d: JSONDict) {
        available = d.bool("available") ?? false
        series = d.list("data").compactMap { JSONDict($0) }.map(RRDSeries.init)
    }

    /// The two directions for one interface, matched on the file name pfSense
    /// uses rather than the name shown on screen.
    func series(forFile file: String) -> [RRDSeries] {
        series.filter { $0.file == file }
    }
}
