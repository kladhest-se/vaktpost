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

