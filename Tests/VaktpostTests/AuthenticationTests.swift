import XCTest
@testable import Vaktpost

/// pfSense reports a refused sign-in as an XML-RPC fault, not an HTTP status.
/// These pin the translation from that fault to something a person can act on.
final class AuthenticationTests: XCTestCase {

    func testCredentialActionsDoNotRequireUnavailableOrDisabledBiometry() {
        XCTAssertFalse(CredentialProtectionPolicy.requiresAuthorization(
            isEnabled: false,
            canUseBiometrics: false
        ))
        XCTAssertFalse(CredentialProtectionPolicy.requiresAuthorization(
            isEnabled: false,
            canUseBiometrics: true
        ))
        XCTAssertFalse(CredentialProtectionPolicy.requiresAuthorization(
            isEnabled: true,
            canUseBiometrics: false
        ))
    }

    func testCredentialActionsRequireUsableOptedInBiometry() {
        XCTAssertTrue(CredentialProtectionPolicy.requiresAuthorization(
            isEnabled: true,
            canUseBiometrics: true
        ))
    }

    private func fault(_ code: Int, _ message: String) -> String {
        """
        <?xml version="1.0"?>
        <methodResponse><fault><value><struct>
        <member><name>faultCode</name><value><int>\(code)</int></value></member>
        <member><name>faultString</name><value><string>\(message)</string></value></member>
        </struct></value></fault></methodResponse>
        """
    }

    private func decodeError(_ xml: String) -> RPCError? {
        do {
            _ = try XMLRPCClient.decode(xml)
            return nil
        } catch {
            return error as? RPCError
        }
    }

    func testAWrongPasswordFaultIsUnauthorized() {
        let error = decodeError(fault(-1, "Authentication failed: Invalid username or password"))
        XCTAssertEqual(error, .unauthorized)
    }

    func testAMissingPrivilegeFaultIsForbidden() {
        let error = decodeError(fault(-2, "Authentication failed: not enough privileges"))
        XCTAssertEqual(error, .forbidden)
    }

    func testTheClassificationIgnoresCase() {
        XCTAssertEqual(XMLRPCClient.classifyFault(code: 0, message: "AUTHENTICATION FAILED"), .unauthorized)
    }

    func testAnOrdinaryFaultStaysAFault() {
        let error = decodeError(fault(-32601, "Only pfsense.exec_php is available in this simulator"))
        XCTAssertEqual(error, .fault(-32601, "Only pfsense.exec_php is available in this simulator"))
    }

    func testASnippetErrorMentioningAuthenticationIsNotASignInFailure() {
        // A snippet's own `__error` is reported text, not the service refusing
        // the request, so it must not be read as a rejected password.
        let body = """
        <?xml version="1.0"?>
        <methodResponse><params><param><value><struct>
        <member><name>real</name><value><string>{&quot;__error&quot;:&quot;log line: Authentication failed for admin&quot;}</string></value></member>
        </struct></value></param></params></methodResponse>
        """
        guard case .fault = decodeError(body) else {
            return XCTFail("expected an ordinary fault")
        }
    }

    func testOnlyIdentityErrorsCountAsAuthenticationFailures() {
        XCTAssertTrue(RPCError.unauthorized.isAuthenticationFailure)
        XCTAssertTrue(RPCError.forbidden.isAuthenticationFailure)
        XCTAssertTrue(RPCError.noCredentials.isAuthenticationFailure)
        XCTAssertFalse(RPCError.tls.isAuthenticationFailure)
        XCTAssertFalse(RPCError.offline("offline").isAuthenticationFailure)
        XCTAssertFalse(RPCError.fault(-1, "boom").isAuthenticationFailure)
        XCTAssertFalse(RPCError.unauthorized.isRetryable)
    }

    func testTheProblemNamesTheCauseAndTheAccount() {
        let wrong = AuthenticationProblem(RPCError.unauthorized, username: "vaktpost")
        XCTAssertEqual(wrong?.kind, .wrongCredentials)
        XCTAssertEqual(wrong?.title, "Wrong username or password")
        XCTAssertTrue(wrong?.summary.contains("vaktpost") == true)
        XCTAssertTrue(wrong?.pointsAtCredentials == true)

        let denied = AuthenticationProblem(RPCError.forbidden, username: "vaktpost")
        XCTAssertEqual(denied?.kind, .missingPrivilege)
        XCTAssertTrue(denied?.steps.contains { $0.contains("System - HA node sync") } == true)
        XCTAssertFalse(denied?.pointsAtCredentials == true)

        XCTAssertEqual(AuthenticationProblem(RPCError.noCredentials, username: "")?.kind, .noPassword)
    }

    func testOtherErrorsAreNotAuthenticationProblems() {
        XCTAssertNil(AuthenticationProblem(RPCError.tls, username: "admin"))
        XCTAssertNil(AuthenticationProblem(RPCError.offline("offline"), username: "admin"))
        XCTAssertNil(AuthenticationProblem(URLError(.timedOut), username: "admin"))
    }

    func testAnEmptyUsernameStillReadsNaturally() {
        let problem = AuthenticationProblem(RPCError.unauthorized, username: "")
        XCTAssertTrue(problem?.summary.contains("this account") == true)
    }
}
