import SwiftUI

/// Everything the Rules pane renders, split out of `FirewallView.swift` on size alone. Nothing here
/// changed behaviour; each declaration was `private` and is now `internal`
/// only so the shell (`listColumn`, in the other file) can still call it.
extension FirewallView {
    /// Write a new rule and refresh.
    ///
    /// Goes through the same coordinator as an edit — rate limit, audit,
    /// read-back — because a create is a write like any other. The only
    /// difference is that the firewall assigns the tracker.
    /// Rethrows rather than swallowing into a `Bool`, for the same reason as
    /// `createForward`: this view is still covered by the edit sheet when a
    /// failure happens, and the sheet is where it has to be shown.
    func createRule(_ form: RuleEditForm) async throws {
        let dict = form.toDict(tracker: "", interface: form.interface)
        _ = try await store.writeCoordinator.execute(
            .saveRule(
                rule: dict,
                displayName: form.descr.isEmpty ? "new rule on \(form.interface)" : form.descr
            )
        )
        await store.refreshManually()
    }

    /// Add a filter separator. Like rule edits, this only changes pfSense's
    /// saved configuration; the shared Apply Changes screen activates the
    /// pending ruleset in one deliberate step.
    func createSeparator(_ form: SeparatorEditForm) async throws {
        _ = try await store.writeCoordinator.execute(
            .saveFilterSeparator(separator: form.toDict(), displayName: form.text)
        )
        await store.refreshFirewallObjectsAfterWrite()
    }

    var filteredRules: [FirewallRule] {
        // No selection shows everything, floating included: with the All chip
        // gone, "nothing selected" is the way to see the whole set.
        var list = showFloating
            ? store.rules.filter(\.isFloating)
            : store.rules
        if let iface = interfaceFilter {
            // A floating rule's interface field holds several names — that is
            // the definition of `isFloating` — and this used to match it
            // against a single chosen tab if that tab happened to be one of
            // the several. pfSense never shows a floating rule under a named
            // interface's own tab; it belongs to Floating alone, regardless
            // of which interfaces it actually applies to. `RulePlacement` and
            // `reorderFilterRules` already compare the interface field for
            // exact equality, which excludes a multi-valued field
            // automatically — this now reasons about it the same way, rather
            // than the list of rules on screen disagreeing with what
            // placement and reordering already treated as true.
            list = list.filter { !$0.isFloating && $0.interfaceName == iface }
        }
        guard !query.isEmpty else { return list }
        let q = query.lowercased()
        return list.filter { matches($0, q) }
    }

    /// Whether a rule matches, including through its aliases.
    ///
    /// The rows show addresses and ports, not alias names — so searching only
    /// the raw fields meant typing `443` or `172.16.1.43` found nothing while
    /// the rule showing exactly those numbers sat on screen. What is displayed
    /// has to be what is searched.
    func matches(_ rule: FirewallRule, _ q: String) -> Bool {
        if rule.descr.lowercased().contains(q) { return true }
        if (rule.proto ?? "").lowercased().contains(q) { return true }
        if rule.interfaceName.lowercased().contains(q) { return true }

        // The name as written, and everything it stands for.
        for field in [rule.sourceSide.address, rule.destinationSide.address,
                      rule.sourceSide.port ?? "", rule.destinationSide.port ?? ""]
        where !field.isEmpty {
            if field.lowercased().contains(q) { return true }
            if let members = store.resolveAlias(field),
               members.contains(where: { $0.lowercased().contains(q) }) {
                return true
            }
        }
        return false
    }

    /// Separators for the interface currently selected, ordered by position.
    ///
    /// Only meaningful with exactly one interface chosen and nothing filtered
    /// out — a separator's position is a claim about *this interface's*
    /// unfiltered rule order, and interleaving it into "All interfaces" or a
    /// search result would be answering a question that no longer has the
    /// shape the position was recorded against.
    var rulesSeparatorsForCurrentSelection: [RuleSeparator] {
        guard let iface = interfaceFilter, !showFloating, query.isEmpty else { return [] }
        return store.filterSeparators.filter { $0.interfaceName?.lowercased() == iface.lowercased() }
    }

    /// Reordering needs the same well-defined order that showing a
    /// separator's position already needs — one interface, nothing filtered
    /// out by a search, no floating rules mixed in. Dragging under any other
    /// condition would be producing an order for a set of rules that is not
    /// actually the interface's whole, real ruleset.
    /// Rules on the selected interface with no tracker at all.
    ///
    /// Filter rules almost always get one — pfSense assigns it through its
    /// own `filter_rule_tracker()` — but `reorder_filter_rules` silently
    /// skips any same-interface rule that has none when it builds what it
    /// considers the interface's current set, matching the write path's
    /// established shape elsewhere (`save_rule`, `delete_rule` refuse an
    /// empty tracker the same way). If even one exists here, a submission
    /// built from every visible rule will never match what the firewall
    /// itself considers current — count for count — and every drag on this
    /// interface fails the same "mismatch" whether or not anything sensible
    /// was dragged, without saying why.
    ///
    /// A rule ending up untracked on an otherwise-normal firewall is itself
    /// unusual — a plausible source is a package that injects rules by some
    /// path other than the ordinary edit form, which would not run through
    /// `filter_rule_tracker()`. This does not depend on knowing which; it
    /// only needs to notice the rule has nothing stable to be moved by.
    var untrackedRulesOnSelectedInterface: [FirewallRule] {
        guard interfaceFilter != nil else { return [] }
        return filteredRules.filter(\.tracker.isEmpty)
    }

    var canReorderRules: Bool {
        interfaceFilter != nil && !showFloating && query.isEmpty
            && untrackedRulesOnSelectedInterface.isEmpty
    }

    var currentRuleListItems: [RuleListItem] {
        mergedRuleList(rules: filteredRules, separators: rulesSeparatorsForCurrentSelection)
    }

    /// The pending drag if one exists and still matches the live data
    /// exactly — same set of items, nothing added or removed underneath it
    /// by a refresh — otherwise the live order. A stale drag is discarded
    /// silently rather than shown: it would be an order for rules that may
    /// no longer be the interface's actual rules.
    var displayedRuleItems: [RuleListItem] {
        guard let pending = rulePendingOrder,
              Set(pending.map(\.id)) == Set(currentRuleListItems.map(\.id)) else { return currentRuleListItems }
        return pending
    }

    var ruleOrderIsDirty: Bool {
        rulePendingOrder.map { $0.map(\.id) != currentRuleListItems.map(\.id) } ?? false
    }

    @ViewBuilder
    var rulesPane: some View {
        if let err = store.errors[.firewall] {
            Notice(symbol: "exclamationmark.triangle", title: "Rules unavailable", detail: err, health: .warn)
        } else if filteredRules.isEmpty && rulesSeparatorsForCurrentSelection.isEmpty {
            let title = showFloating ? "No floating rules" : "No rules returned"
            Notice(symbol: "shield.slash", title: query.isEmpty ? title : "No matches")
        } else if !untrackedRulesOnSelectedInterface.isEmpty {
            // Named rather than folded into the ordinary "can't reorder
            // here" case below: a search or a multi-interface view not
            // supporting reordering is expected and needs no explanation,
            // but a firewall that cannot be reordered because of what one of
            // its own rules is missing is worth saying plainly, since
            // dragging here would otherwise fail the same opaque way no
            // matter what was actually dragged.
            countLine("\(filteredRules.count) rules")
            Notice(symbol: "questionmark.circle",
                   title: untrackedRulesOnSelectedInterface.count == 1
                       ? "One rule here has no stable ID"
                       : "\(untrackedRulesOnSelectedInterface.count) rules here have no stable ID",
                   detail: "The firewall itself does not treat \(untrackedRulesOnSelectedInterface.count == 1 ? "this rule" : "these rules") as reorderable, "
                       + "so nothing here can be dragged until that changes: "
                       + untrackedRulesOnSelectedInterface
                           .map { $0.descr.isEmpty ? "an unlabelled rule" : $0.descr }
                           .joined(separator: ", ")
                       + ". This app cannot edit, delete, or reorder a rule pfSense has not given a tracker, "
                       + "the same way it could not for a port forward until that forward was edited once elsewhere.",
                   health: .warn)
            ForEach(filteredRules) { rule in
                Button { selection = rule.id } label: { RuleRow(rule: rule) }
                    .buttonStyle(.plain)
            }
        } else if canReorderRules {
            countLine("\(filteredRules.count) rules")
            Text("Drag \(Image(systemName: "line.3.horizontal")) to reorder. "
                + "Position here is pfSense's own; check the web GUI if a separator looks out of place.")
                .scaledFont(11)
                .foregroundStyle(theme.labelFaint)
                .padding(.horizontal, 2)

            if ruleOrderIsDirty {
                orderChangedBar
            }

            ForEach(displayedRuleItems) { item in
                reorderableRow(item)
            }
        } else {
            countLine("\(filteredRules.count) rules")
            ForEach(filteredRules) { rule in
                Button { selection = rule.id } label: { RuleRow(rule: rule) }
                    .buttonStyle(.plain)
            }
        }
    }

    var orderChangedBar: some View {
        HStack(spacing: 10) {
            Text("Order changed")
                .scaledFont(12, weight: .semibold)
                .foregroundStyle(theme.warn)
            Spacer()
            Button("Discard") { rulePendingOrder = nil }
                .scaledFont(12)
                .foregroundStyle(theme.labelMuted)
            Button {
                Task { await saveRuleOrder() }
            } label: {
                if isSavingOrder {
                    ProgressView()
                } else {
                    Text("Save order").scaledFont(12, weight: .semibold)
                }
            }
            .disabled(isSavingOrder)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(theme.warn.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    func saveRuleOrder() async {
        guard let interface = interfaceFilter, let items = rulePendingOrder else { return }
        isSavingOrder = true
        do {
            _ = try await store.writeCoordinator.execute(.reorderFilterRules(
                interface: interface,
                items: items.map(\.reorderItem),
                displayName: store.interfaceLabel(for: interface) ?? interface
            ))
            // Re-read only what changed, before dropping the optimistic drag
            // order. A full dashboard refresh may be skipped when an automatic
            // cycle is already running, and is needlessly slow for this screen.
            await store.refreshFirewallObjectsAfterWrite()
            rulePendingOrder = nil
        } catch {
            // A refresh here, not only on success. A "mismatch" means the
            // rules this order was built from are not what the firewall
            // currently has — before this, nothing re-fetched them, `refresh()`
            // silently no-opped for the same reason, and every retry
            // resubmitted the identical stale order and failed the identical
            // way. The pending drag is discarded rather than kept and offered
            // again: a "Save order" built from data just proven wrong is not
            // worth preserving, and forcing a fresh drag against current data
            // is the only way the next attempt can mean anything.
            rulePendingOrder = nil
            reorderError = WriteError.from(error, operation: .other)
            showReorderErrorAlert = true
            await store.refreshFirewallObjectsAfterWrite()
        }
        isSavingOrder = false
    }

    /// One row, draggable by its leading handle only. The row's own tap
    /// target — selection, navigation — is untouched; only the handle
    /// initiates a drag, so picking up a rule and opening it remain two
    /// different gestures rather than one gesture doing both badly.
    @ViewBuilder
    func reorderableRow(_ item: RuleListItem) -> some View {
        HStack(spacing: 0) {
            RuleDragHandle()
                .onDrag {
                    ruleDraggingID = item.id
                    return NSItemProvider(object: item.id as NSString)
                }
            Group {
                switch item {
                case .rule(let rule):
                    Button { selection = rule.id } label: { RuleRow(rule: rule) }
                        .buttonStyle(.plain)
                case .separator(let separator):
                    Button { selection = separator.id } label: {
                        SeparatorBar(separator: separator, showsDisclosure: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .onDrop(of: [.text], delegate: RuleReorderDropDelegate(
            target: item,
            items: Binding(
                get: { displayedRuleItems },
                set: { rulePendingOrder = $0 }
            ),
            draggingID: $ruleDraggingID
        ))
    }

    // MARK: NAT

}
