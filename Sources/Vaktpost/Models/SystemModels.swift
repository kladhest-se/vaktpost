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

    var isConfigured: Bool { enabled != nil || !interfaces.isEmpty }

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

    init(_ d: JSONDict, isCA: Bool = false) {
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
        descr = d.string("descr", "description")?
            .replacingOccurrences(of: "\n", with: " ")
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
