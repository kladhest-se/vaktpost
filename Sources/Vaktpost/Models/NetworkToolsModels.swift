import Foundation

/// One speed test run against a known, unauthenticated HTTPS endpoint,
/// measured from the firewall itself rather than from the phone — so the
/// result reflects the WAN link, not the phone's own connection back to it.
///
/// `available == false` covers both "no curl extension" and "the WAN
/// couldn't reach the test server" — either way there is nothing to plot,
/// only `reason` to show.
struct SpeedtestResult: Codable, Identifiable, Sendable {
    var id: Date { date }
    let date: Date
    let available: Bool
    let reason: String?
    let server: String?
    let pingMs: Double?
    let downloadMbps: Double?
    /// Absent specifically when the download leg succeeded but the upload
    /// leg's own, separate request failed — see PHPSnippet.speedtest's own
    /// comment on why a failed upload does not blank out the rest.
    let uploadMbps: Double?

    init(_ d: JSONDict, date: Date = Date()) {
        self.date = date
        available = d.bool("available") ?? false
        reason = d.string("reason")
        server = d.string("server")
        pingMs = d.double("ping_ms")
        downloadMbps = d.double("download_mbps")
        uploadMbps = d.double("upload_mbps")
    }
}

/// A single snapshot of pfSense's own configuration file, fetched read-only.
///
/// There is deliberately no restore path anywhere in this app. Writing a
/// config back safely needs pfSense's own `parse_xml_config()`, which takes
/// a file path — and this app's own write-boundary rules forbid every way
/// of getting one there (`file_put_contents`, write-mode `fopen`) for the
/// same reason they forbid a shell: a hole big enough for one legitimate
/// write is big enough for anything. A hand-rolled XML-to-array converter
/// that avoided that path would be untested against real pfSense on exactly
/// the operation where a subtle mistake is hardest to notice and worst to
/// make. Backing up stays fully useful without it — pfSense's own web UI
/// already restores a file this screen helped save.
struct ConfigBackup {
    let hostname: String
    let xml: Data
    let sizeBytes: Int
    let fetchedAt: Date

    init?(_ d: JSONDict, fetchedAt: Date = Date()) {
        guard d.bool("available") == true,
              let base64 = d.string("xml_base64"),
              let data = Data(base64Encoded: base64) else { return nil }
        self.xml = data
        self.hostname = d.string("hostname") ?? "firewall"
        self.sizeBytes = d.int("size_bytes") ?? data.count
        self.fetchedAt = fetchedAt
    }

    /// A filename carrying the firewall's own hostname and the date, so a
    /// share sheet or Files save doesn't leave someone with five identically
    /// named "config.xml" files a week from now.
    var suggestedFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let safeHost = hostname.replacingOccurrences(of: "/", with: "-")
        return "\(safeHost)-config-\(formatter.string(from: fetchedAt)).xml"
    }
}
