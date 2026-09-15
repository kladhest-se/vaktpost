import XCTest
@testable import Vaktpost

final class NetworkToolsModelTests: XCTestCase {

    private func dict(_ json: String) throws -> JSONDict {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        return try XCTUnwrap(JSONDict(value))
    }

    // MARK: SpeedtestResult

    func testAvailableResultDecodesAllFields() throws {
        let result = SpeedtestResult(try dict("""
        {"available": true, "server": "speed.cloudflare.com", "ping_ms": 9.4,
         "download_mbps": 241.3, "upload_mbps": 27.1}
        """))
        XCTAssertTrue(result.available)
        XCTAssertEqual(result.server, "speed.cloudflare.com")
        XCTAssertEqual(result.pingMs, 9.4)
        XCTAssertEqual(result.downloadMbps, 241.3)
        XCTAssertEqual(result.uploadMbps, 27.1)
        XCTAssertNil(result.reason)
    }

    func testUnavailableResultCarriesAReasonNotNumbers() throws {
        // No curl extension, or the WAN could not reach the test server —
        // either way there is a reason to show and nothing to plot.
        let result = SpeedtestResult(try dict("""
        {"available": false, "reason": "The download test failed with HTTP status 0."}
        """))
        XCTAssertFalse(result.available)
        XCTAssertEqual(result.reason, "The download test failed with HTTP status 0.")
        XCTAssertNil(result.downloadMbps)
        XCTAssertNil(result.uploadMbps)
    }

    func testAFailedUploadLegLeavesDownloadAndPingIntact() throws {
        // PHPSnippet.speedtest's own comment: a failed upload leg does not
        // blank out a download leg that already succeeded.
        let result = SpeedtestResult(try dict("""
        {"available": true, "server": "speed.cloudflare.com", "ping_ms": 11.0, "download_mbps": 180.5}
        """))
        XCTAssertTrue(result.available)
        XCTAssertEqual(result.downloadMbps, 180.5)
        XCTAssertNil(result.uploadMbps)
    }

    func testResultRoundTripsThroughCodableForHistoryPersistence() throws {
        let original = SpeedtestResult(try dict("""
        {"available": true, "server": "speed.cloudflare.com", "ping_ms": 9.4,
         "download_mbps": 241.3, "upload_mbps": 27.1}
        """), date: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SpeedtestResult.self, from: data)
        XCTAssertEqual(decoded.date, original.date)
        XCTAssertEqual(decoded.downloadMbps, original.downloadMbps)
        XCTAssertEqual(decoded.uploadMbps, original.uploadMbps)
    }

    // MARK: ConfigBackup

    func testAvailableBackupDecodesAndBase64DecodesTheXML() throws {
        let xml = "<pfsense><version>24.11</version></pfsense>"
        let encoded = Data(xml.utf8).base64EncodedString()
        let backup = try XCTUnwrap(ConfigBackup(try dict("""
        {"available": true, "xml_base64": "\(encoded)", "size_bytes": \(xml.utf8.count), "hostname": "fw01"}
        """)))
        XCTAssertEqual(backup.hostname, "fw01")
        XCTAssertEqual(backup.sizeBytes, xml.utf8.count)
        XCTAssertEqual(String(data: backup.xml, encoding: .utf8), xml)
    }

    func testUnavailableBackupDecodesToNilRatherThanAnEmptyFile() throws {
        // "available: false" (unreadable config file) must not decode into
        // a ConfigBackup with empty data that looks like a valid, if tiny,
        // backup.
        let backup = ConfigBackup(try dict("""
        {"available": false, "reason": "The configuration file could not be read."}
        """))
        XCTAssertNil(backup)
    }

    func testMalformedBase64DecodesToNilRatherThanCrashing() throws {
        let backup = ConfigBackup(try dict("""
        {"available": true, "xml_base64": "not valid base64!!", "hostname": "fw01"}
        """))
        XCTAssertNil(backup)
    }

    func testSuggestedFilenameIsFilesystemSafeAndIncludesHostAndDate() throws {
        let xml = "<pfsense/>"
        let encoded = Data(xml.utf8).base64EncodedString()
        let backup = try XCTUnwrap(ConfigBackup(try dict("""
        {"available": true, "xml_base64": "\(encoded)", "hostname": "se-lin-fw/localdomain"}
        """), fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)))
        XCTAssertFalse(backup.suggestedFilename.contains("/"))
        XCTAssertTrue(backup.suggestedFilename.hasSuffix(".xml"))
        XCTAssertTrue(backup.suggestedFilename.contains("config"))
    }
}
