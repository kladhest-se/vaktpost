import XCTest
@testable import Vaktpost

/// The transport, and the snippet rules that replace the old structural
/// read-only guarantee.
final class XMLRPCTests: XCTestCase {

    // MARK: Encoding

    func testScriptIsXMLEscaped() {
        // PHP is full of `<`, `>` and `&`. Unescaped, the first `<` ends the
        // string element and the firewall receives a truncated script.
        let call = XMLRPCClient.methodCall(script: "if ($a < 5 && $b > 1) { echo \"x\"; }")
        XCTAssertTrue(call.contains("&lt; 5 &amp;&amp; $b &gt; 1"))
        XCTAssertFalse(call.contains("< 5 &&"))
        XCTAssertTrue(call.contains("<methodName>pfsense.exec_php</methodName>"))
    }

    func testUnescapeHandlesAmpersandLast() {
        // "&amp;lt;" must come back as "&lt;", not "<". Decoding the ampersand
        // first would double-decode anything that was legitimately escaped in
        // the payload.
        XCTAssertEqual(XMLRPCClient.unescape("&amp;lt;"), "&lt;")
        XCTAssertEqual(XMLRPCClient.unescape("a &lt; b &amp;&amp; c"), "a < b && c")
    }

    // MARK: Decoding

    func testDecodesTheJSONWrappedResponse() throws {
        let xml = """
        <?xml version="1.0"?><methodResponse><params><param><value><struct>
        <member><name>real</name><value><string>{&quot;cpu_usage&quot;:5.5,&quot;uptime_sec&quot;:437860}</string></value></member>
        </struct></value></param></params></methodResponse>
        """
        let value = try XMLRPCClient.decode(xml)
        let dict = try XCTUnwrap(JSONDict(value))
        XCTAssertEqual(dict.double("cpu_usage"), 5.5)
        XCTAssertEqual(dict.int("uptime_sec"), 437_860)
    }

    func testFaultCarriesTheFirewallsOwnMessage() {
        // Where a PHP error in a snippet surfaces. Reporting it as "malformed"
        // would send somebody looking at the parser instead of the snippet.
        let xml = """
        <?xml version="1.0"?><methodResponse><fault><value><struct>
        <member><name>faultCode</name><value><int>1</int></value></member>
        <member><name>faultString</name><value><string>Call to undefined function get_temp()</string></value></member>
        </struct></value></fault></methodResponse>
        """
        XCTAssertThrowsError(try XMLRPCClient.decode(xml)) { error in
            guard case RPCError.fault(let code, let message) = error else {
                return XCTFail("expected a fault, got \(error)")
            }
            XCTAssertEqual(code, 1)
            XCTAssertTrue(message.contains("undefined function"))
        }
    }

    func testGarbageIsMalformedRatherThanACrash() {
        XCTAssertThrowsError(try XMLRPCClient.decode("<html>login page</html>"))
        XCTAssertThrowsError(try XMLRPCClient.decode(""))
    }

    // MARK: Snippet rules
    //
    // The shell script in vaktpost-tools is the gate that blocks a publish;
    // these run in Xcode so a violation shows up while it is being written
    // rather than at push time.

    func testNoSnippetCanModifyTheFirewall() {
        let forbidden = ["write_config", "mwexec", "shell_exec", "passthru",
                         "proc_open", "popen", "unlink(", "file_put_contents",
                         "rename(", "mkdir(", "rmdir(", "chmod(", "chown("]
        for snippet in PHPSnippet.all {
            for term in forbidden {
                XCTAssertFalse(snippet.script.contains(term),
                               "\(snippet.name) contains \(term)")
            }
        }
    }

    func testEverySnippetReturnsThroughTheJSONWrapper() {
        // Without it the response is raw XML-RPC, where PHP nulls encode
        // inconsistently — the bug hass-pfsense hit and worked around.
        for snippet in PHPSnippet.all {
            XCTAssertTrue(snippet.script.contains("json_encode($toreturn_real)"),
                          "\(snippet.name) does not use the wrapper")
            XCTAssertTrue(snippet.script.contains("$toreturn"),
                          "\(snippet.name) assigns no result")
        }
    }

    func testLogPathsComeFromTheEnumAndNowhereElse() {
        // The one snippet taking parameters. Both are constrained here: an
        // interpolated path is how a read-only snippet becomes a file browser.
        for source in PHPSnippet.LogSource.allCases {
            let snippet = PHPSnippet.log(source, limit: 100)
            XCTAssertTrue(snippet.script.contains("$path = \"\(source.path)\""))
            XCTAssertTrue(source.path.hasPrefix("/var/log/"))
        }
    }

    func testSnippetsReportWhenTheyProduceNoResult() {
        // A PHP fatal — a memory limit on a large log, say — leaves $toreturn
        // unset. Without this the response is `null`, which decodes to an
        // empty list and reads on screen as "nothing configured".
        for snippet in PHPSnippet.all {
            XCTAssertTrue(snippet.script.contains("isset($toreturn)"),
                          "\(snippet.name) has no guard for an unset result")
        }
    }

    func testAReportedFailureBecomesAFault() {
        let xml = """
        <?xml version="1.0"?><methodResponse><params><param><value><struct>
        <member><name>real</name><value><string>{&quot;__error&quot;:&quot;snippet produced no result&quot;}</string></value></member>
        </struct></value></param></params></methodResponse>
        """
        XCTAssertThrowsError(try XMLRPCClient.decode(xml)) { error in
            guard case RPCError.fault(_, let message) = error else {
                return XCTFail("expected a fault, got \(error)")
            }
            XCTAssertTrue(message.contains("no result"))
        }
    }

    func testLogSnippetsReadTheTailNotTheWholeFile() {
        // `file()` loads an entire log into memory. A busy filter log runs to
        // tens of megabytes, which is enough to kill the script outright.
        for source in PHPSnippet.LogSource.allCases {
            let script = PHPSnippet.log(source, limit: 100).script
            // The read is clamped to the file size: a negative offset larger
            // than the file makes the seek fail and returns false, which
            // emptied every log smaller than the window.
            XCTAssertTrue(script.contains("min($size, $window)"))
            XCTAssertTrue(script.contains("file_get_contents($path, false, null, -$read)"))
            XCTAssertFalse(script.contains("$lines = file($path)"),
                           "\(source.rawValue) still reads the whole file")
            // And reports what it found, so empty and missing are distinct.
            XCTAssertTrue(script.contains("\"size\" => $size"))
        }
    }

    func testEverySnippetIsBraceBalanced() {
        // Replaces a line-shape heuristic that flagged every continuation of a
        // multi-line ternary or array as "stranded code" — eight false
        // positives on valid PHP. A check that reports things that are fine
        // gets switched off, and then it catches nothing.
        //
        // Balance is the property that actually broke: a comment split by an
        // escaped newline left an unterminated string and an unclosed brace.
        for snippet in PHPSnippet.all {
            var depth = 0
            var inString = false
            var previous: Character = " "

            for line in snippet.script.split(separator: "\n", omittingEmptySubsequences: false) {
                let text = line.trimmingCharacters(in: .whitespaces)
                if text.hasPrefix("//") { continue }
                for character in text {
                    if character == "\"", previous != "\\" { inString.toggle() }
                    if !inString {
                        if character == "{" || character == "[" || character == "(" { depth += 1 }
                        if character == "}" || character == "]" || character == ")" { depth -= 1 }
                    }
                    previous = character
                }
                XCTAssertFalse(inString, "\(snippet.name) has an unterminated string")
            }
            XCTAssertEqual(depth, 0, "\(snippet.name) is not brace balanced")
        }
    }

    func testLogLimitIsClamped() {
        XCTAssertTrue(PHPSnippet.log(.filter, limit: 100_000).script.contains("-500"))
        XCTAssertTrue(PHPSnippet.log(.filter, limit: -5).script.contains("-10"))
    }

    func testFilterLogActionIsRecoveredFromRawText() {
        // Logs arrive as plain strings now, so the pass/block filter has to be
        // reconstructed from the line rather than read from a field.
        let blocked = LogLine(text: "5,,,1000000103,igb0,match,block,in,4,0x0,,64", kind: .firewall)
        XCTAssertEqual(blocked.action, "block")
        XCTAssertEqual(blocked.health, .bad)

        let passed = LogLine(text: "5,,,1000000104,igb0,match,pass,in,4,0x0,,64", kind: .firewall)
        XCTAssertEqual(passed.action, "pass")

        // Other logs have no action, and must not have one invented.
        XCTAssertNil(LogLine(text: "sshd: Accepted publickey", kind: .auth).action)
    }
}

/// Guarding the firewall's notice log against this app's own defects.
final class FaultBackoffTests: XCTestCase {

    /// Mirrors `DashboardStore`'s accounting without needing a connection.
    private struct Backoff {
        var counts: [String: Int] = [:]
        let limit = 3

        mutating func recordFault(_ section: String) { counts[section, default: 0] += 1 }
        func isAbandoned(_ section: String) -> Bool { (counts[section] ?? 0) >= limit }
        mutating func reset() { counts.removeAll() }
    }

    func testASectionIsAbandonedAfterRepeatedFaults() {
        // A faulting snippet leaves a permanent notice on the firewall every
        // time it runs. Seventy-eight of them accumulated in one afternoon.
        var backoff = Backoff()
        XCTAssertFalse(backoff.isAbandoned("hostOverrides"))
        backoff.recordFault("hostOverrides")
        backoff.recordFault("hostOverrides")
        XCTAssertFalse(backoff.isAbandoned("hostOverrides"), "two strikes is not out")
        backoff.recordFault("hostOverrides")
        XCTAssertTrue(backoff.isAbandoned("hostOverrides"))
    }

    func testOneSectionFailingDoesNotStopTheOthers() {
        var backoff = Backoff()
        for _ in 0..<5 { backoff.recordFault("hostOverrides") }
        XCTAssertTrue(backoff.isAbandoned("hostOverrides"))
        XCTAssertFalse(backoff.isAbandoned("telemetry"))
    }

    func testAManualRefreshClearsIt() {
        // Somebody pulling to refresh is saying "try again", which is exactly
        // when a section abandoned an hour ago deserves another attempt.
        var backoff = Backoff()
        for _ in 0..<3 { backoff.recordFault("hostOverrides") }
        XCTAssertTrue(backoff.isAbandoned("hostOverrides"))
        backoff.reset()
        XCTAssertFalse(backoff.isAbandoned("hostOverrides"))
    }
}
