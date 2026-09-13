import XCTest
@testable import Vaktpost

/// `mergedRuleList` is the one function both the on-screen order and the
/// reorder drag's starting point are built from, and `WriteCoordinator`'s own
/// `reorderTokens` mirrors it deliberately rather than sharing code across a
/// module boundary that could not be tested this directly. If this function
/// disagrees with itself about where a separator belongs, the display and the
/// write would disagree about what "save this order" even means.
final class MergedRuleListTests: XCTestCase {

    private func rule(_ tracker: String, interface: String = "lan") -> FirewallRule {
        FirewallRule(JSONDict([
            "tracker": .string(tracker),
            "interface": .string(interface),
            "type": .string("pass"),
            "descr": .string(""),
            "source": .object(["address": .string("any")]),
            "destination": .object(["address": .string("any")])
        ]))
    }

    private func separator(_ key: String, position: Int?, interface: String = "lan") -> RuleSeparator {
        var raw: [String: JSONValue] = [
            "interface": .string(interface),
            "key": .string(key),
            "text": .string(key),
            "color": .string("info")
        ]
        if let position { raw["position"] = .string(String(position)) }
        return RuleSeparator(JSONDict(raw))
    }

    private func natSeparator(_ key: String, position: Int?) -> RuleSeparator {
        var raw: [String: JSONValue] = [
            "key": .string(key), "text": .string(key), "color": .string("info")
        ]
        if let position { raw["position"] = .string(String(position)) }
        return RuleSeparator(JSONDict(raw))
    }

    private func forward(_ port: String) -> PortForward {
        PortForward(JSONDict([
            "interface": .string("wan"),
            "destination": .object(["network": .string("wanip")]),
            "destination_port": .string(port),
            "target": .string("192.0.2.10")
        ]))
    }

    // MARK: Placement

    func testASeparatorAtZeroComesBeforeTheFirstRule() {
        let items = mergedRuleList(rules: [rule("a"), rule("b")],
                                   separators: [separator("sep0", position: 0)])
        XCTAssertEqual(items.map(\.id), ["separator:sep0", "rule:a", "rule:b"])
    }

    func testASeparatorInTheMiddleSitsBetweenTheRulesItCounted() {
        let items = mergedRuleList(rules: [rule("a"), rule("b"), rule("c")],
                                   separators: [separator("sep0", position: 1)])
        XCTAssertEqual(items.map(\.id), ["rule:a", "separator:sep0", "rule:b", "rule:c"])
    }

    func testASeparatorAtOrPastTheRuleCountComesLast() {
        let exact = mergedRuleList(rules: [rule("a"), rule("b")],
                                   separators: [separator("sep0", position: 2)])
        XCTAssertEqual(exact.map(\.id), ["rule:a", "rule:b", "separator:sep0"])

        let past = mergedRuleList(rules: [rule("a"), rule("b")],
                                  separators: [separator("sep0", position: 99)])
        XCTAssertEqual(past.map(\.id), ["rule:a", "rule:b", "separator:sep0"])
    }

    func testAnUnreadablePositionIsTreatedAsLastRatherThanDropped() {
        // A separator this app cannot place is still a separator that exists
        // on the firewall. Losing it from the list entirely would make a
        // save-the-current-order operation delete it by omission.
        let items = mergedRuleList(rules: [rule("a")],
                                   separators: [separator("sep0", position: nil)])
        XCTAssertEqual(items.map(\.id), ["rule:a", "separator:sep0"])
    }

    // MARK: Several separators

    func testTwoSeparatorsAtTheSamePositionBothAppearBeforeThatRule() {
        let items = mergedRuleList(rules: [rule("a"), rule("b")],
                                   separators: [separator("sep0", position: 1),
                                                separator("sep1", position: 1)])
        XCTAssertEqual(Set(items.prefix(3).map(\.id)),
                       Set(["rule:a", "separator:sep0", "separator:sep1"]))
        XCTAssertEqual(items.last?.id, "rule:b")
    }

    func testSeparatorsAtDifferentPositionsAreEachPlacedCorrectly() {
        let items = mergedRuleList(rules: [rule("a"), rule("b"), rule("c")],
                                   separators: [separator("top", position: 0),
                                                separator("mid", position: 2),
                                                separator("end", position: 3)])
        XCTAssertEqual(items.map(\.id),
                       ["separator:top", "rule:a", "rule:b",
                        "separator:mid", "rule:c", "separator:end"])
    }

    // MARK: Scoping

    func testOnlyMatchingInterfaceRulesAndSeparatorsMatter() {
        // The caller is responsible for filtering to one interface, exactly
        // as `RulePlacement` requires — this function trusts what it is
        // given and does not itself re-check the interface field. Passing it
        // an unfiltered mix produces an unfiltered mix, which is the
        // documented reason the display never calls it that way.
        let items = mergedRuleList(rules: [rule("a", interface: "lan"), rule("b", interface: "wan")],
                                   separators: [separator("sep0", position: 0, interface: "lan")])
        XCTAssertEqual(items.map(\.id), ["separator:sep0", "rule:a", "rule:b"])
    }

    func testNoRulesAndNoSeparatorsIsAnEmptyList() {
        XCTAssertTrue(mergedRuleList(rules: [], separators: []).isEmpty)
    }

    func testSeparatorsAloneWithNoRulesAllLandAtTheEnd() {
        // "The end" and "the beginning" are the same position when there are
        // no rules to be before or after, and `>=` on an empty list's count
        // (zero) is the branch that has to catch a position of zero too.
        let items = mergedRuleList(rules: [], separators: [separator("sep0", position: 0)])
        XCTAssertEqual(items.map(\.id), ["separator:sep0"])
    }

    // MARK: Round trip through ReorderItem

    func testEveryItemConvertsToTheMatchingReorderItem() {
        let items = mergedRuleList(rules: [rule("a")],
                                   separators: [separator("sep0", position: 0)])
        let reorderItems = items.map(\.reorderItem)
        guard case .separator(let key) = reorderItems[0] else {
            return XCTFail("expected the separator first")
        }
        XCTAssertEqual(key, "sep0")
        guard case .rule(let tracker) = reorderItems[1] else {
            return XCTFail("expected the rule second")
        }
        XCTAssertEqual(tracker, "a")
    }

    func testNatListMergesRulesAndSeparatorsByPrecedingRuleCount() {
        let items = mergedNatList(
            forwards: [forward("443"), forward("8443")],
            separators: [natSeparator("top", position: 0),
                         natSeparator("middle", position: 1),
                         natSeparator("end", position: 2)]
        )
        XCTAssertEqual(items.map(\.id), [
            "nat-separator:top",
            "nat:0:wan-wanip:443-192.0.2.10",
            "nat-separator:middle",
            "nat:1:wan-wanip:8443-192.0.2.10",
            "nat-separator:end"
        ])
    }

    func testNatSeparatorConvertsToASeparatorReorderItem() {
        let separator = natSeparator("sep0", position: 1)
        let item = NatListItem.separator(separator).reorderItem
        XCTAssertEqual(item.kind, .separator)
        XCTAssertEqual(item.separatorKey, "sep0")
        XCTAssertEqual(item.identityToken, "separator:sep0")
    }
}
