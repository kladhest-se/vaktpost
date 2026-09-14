import XCTest
@testable import Vaktpost

@MainActor
final class UpdateSafetyTests: XCTestCase {
    func testPackageIdentifiersAcceptOnlyThePkgNameAlphabet() throws {
        XCTAssertNoThrow(try WriteCoordinator.validatePackageUpdate(
            identifier: "pfSense-pkg-acme_1.2+meta", installed: "1.0", target: "1.1"))
        for value in ["", "pkg name", "pkg;reboot", "pkg$(id)", "pkg/../../tmp"] {
            XCTAssertThrowsError(try WriteCoordinator.validatePackageUpdate(
                identifier: value, installed: "1.0", target: "1.1"))
        }
    }

    func testCurrentVersionsCannotStartAnUpdate() {
        XCTAssertThrowsError(try WriteCoordinator.validateFirmwareUpdate(
            current: "26.03", target: "26.03"))
        XCTAssertThrowsError(try WriteCoordinator.validatePackageUpdate(
            identifier: "pfSense-pkg-acme", installed: "1.3.2", target: "1.3.2"))
    }

    func testUpdaterHasOneFixedExecutableAndQuotesThePackageArgument() {
        let body = PHPSnippet.startUpdate(
            kind: "package", packageIdentifier: "pfSense-pkg-acme"
        ).body
        XCTAssertTrue(PHPSnippet.writeOperations.contains("start_update"))
        XCTAssertTrue(body.contains("pkg_valid_name($vaktpost_package)"))
        XCTAssertTrue(body.contains("get_pkg_info([$vaktpost_package], false, true)"))
        XCTAssertTrue(body.contains("escapeshellarg($vaktpost_package)"))
        XCTAssertTrue(body.contains("mwexec_bg($vaktpost_command)"))
        XCTAssertTrue(body.contains("posix_kill($vaktpost_pid, 0)"))
        XCTAssertTrue(body.contains("__RC=([0-9]+)"))
        XCTAssertTrue(body.contains("/usr/local/sbin/"))
        XCTAssertFalse(body.contains("escapeshellarg($vaktpost_package) . \" -f\""))
        XCTAssertFalse(body.contains("shell_exec("))
        XCTAssertFalse(body.contains("eval("))
    }

    func testUpdaterCreatesRestorePointBeforeLaunching() {
        let body = PHPSnippet.startUpdate(kind: "firmware").body
        let restorePoint = body.range(of: "write_config(")
        let launch = body.range(of: "mwexec_bg(")
        XCTAssertNotNil(restorePoint)
        XCTAssertNotNil(launch)
        XCTAssertLessThan(restorePoint?.lowerBound ?? body.endIndex,
                          launch?.lowerBound ?? body.startIndex)
    }
}
