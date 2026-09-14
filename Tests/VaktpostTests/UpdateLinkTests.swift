import XCTest
@testable import Vaktpost

final class UpdateLinkTests: XCTestCase {
    private func package(_ json: String) throws -> PackageInfo {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        return PackageInfo(try XCTUnwrap(JSONDict(value)))
    }

    func testFirmwareLinkPreservesConfiguredBasePathAndPort() throws {
        let url = try XCTUnwrap(PfSenseUpdateLink.firmware(
            baseURL: "HTTPS://admin:secret@firewall.example:8443/admin?old=1#old"
        ))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertNil(components.user)
        XCTAssertNil(components.password)
        XCTAssertEqual(url.path, "/admin/pkg_mgr_install.php")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "id", value: "firmware")])
        XCTAssertNil(components.fragment)
    }

    func testPackageLinkUsesInternalNameAndVersionReview() throws {
        let pkg = try package("""
        {"name": "acme", "shortname": "acme", "update_name": "pfSense-pkg-acme",
         "installed_version": "1.3.2", "latest_version": "1.4.0",
         "update_available": true}
        """)
        let url = try XCTUnwrap(PfSenseUpdateLink.package(pkg, baseURL: "https://fw.example"))
        XCTAssertEqual(pkg.updateIdentifier, "pfSense-pkg-acme")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items, [
            URLQueryItem(name: "mode", value: "reinstallpkg"),
            URLQueryItem(name: "pkg", value: "pfSense-pkg-acme"),
            URLQueryItem(name: "from", value: "1.3.2"),
            URLQueryItem(name: "to", value: "1.4.0")
        ])
    }

    func testCurrentPackageDoesNotOfferAnUpdateLink() throws {
        let pkg = try package("""
        {"name": "pfSense-pkg-acme", "installed_version": "1.3.2",
         "latest_version": "1.3.2", "update_available": false}
        """)
        XCTAssertNil(PfSenseUpdateLink.package(pkg, baseURL: "https://fw.example"))
    }

    func testUnsupportedURLSchemeIsRejected() {
        XCTAssertNil(PfSenseUpdateLink.firmware(baseURL: "file:///tmp/firewall"))
    }
}
