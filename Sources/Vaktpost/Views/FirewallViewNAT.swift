import SwiftUI

/// Everything the NAT pane renders, split out of `FirewallView.swift` on size alone. Nothing here
/// changed behaviour; each declaration was `private` and is now `internal`
/// only so the shell (`listColumn`, in the other file) can still call it.
extension FirewallView {
    /// Write a new port forward and refresh.
    ///
    /// Through the same coordinator as an edit: rate limit, audit, read-back.
    /// Rethrows rather than swallowing into a `Bool`.
    ///
    /// This used to catch here and stash the error on this view's own state —
    /// which is exactly wrong, because this view is still covered by the edit
    /// sheet when the failure happens. The sheet catches it now, where it is
    /// actually visible.
    func createForward(_ form: PortForwardEditForm) async throws {
        let dict = form.toDict(interface: form.interface)
        _ = try await store.writeCoordinator.execute(
            .saveNatRule(
                rule: dict,
                displayName: form.descr.isEmpty ? "new forward on \(form.interface)" : form.descr
            )
        )
        await store.refreshManually()
    }

    /// Stage a separator in the flat NAT table without applying the ruleset.
    func createNatSeparator(_ form: SeparatorEditForm) async throws {
        _ = try await store.writeCoordinator.execute(
            .saveNatSeparator(separator: form.toDict(), displayName: form.text)
        )
        await store.refreshFirewallObjectsAfterWrite()
    }

    // MARK: Rules

    var filteredForwards: [PortForward] {
        guard !query.isEmpty else { return store.portForwards }
        let q = query.lowercased()
        return store.portForwards.filter { matches($0, q) }
    }

    /// Whether a port forward matches, including through its aliases.
    func matches(_ pf: PortForward, _ q: String) -> Bool {
        if pf.descr.lowercased().contains(q) { return true }
        if (pf.proto ?? "").lowercased().contains(q) { return true }
        if pf.interfaceName.lowercased().contains(q) { return true }

        for field in [pf.destinationSide.address, pf.target,
                      pf.destinationSide.port ?? "", pf.localPort ?? ""]
        where !field.isEmpty {
            if field.lowercased().contains(q) { return true }
            if let members = store.resolveAlias(field),
               members.contains(where: { $0.lowercased().contains(q) }) {
                return true
            }
        }
        return false
    }

    var currentNatItems: [NatListItem] {
        mergedNatList(forwards: store.portForwards, separators: store.natSeparators)
    }

    var displayedNatItems: [NatListItem] {
        guard let pending = natPendingOrder,
              Set(pending.map(\.id)) == Set(currentNatItems.map(\.id)) else {
            return currentNatItems
        }
        return pending
    }

    var natOrderIsDirty: Bool {
        natPendingOrder.map { $0.map(\.id) != currentNatItems.map(\.id) } ?? false
    }

    var canReorderNatRules: Bool {
        query.isEmpty && currentNatItems.count > 1
    }

    @ViewBuilder
    var natPane: some View {
        if let err = store.errors[.portForwards] {
            Notice(symbol: "exclamationmark.triangle", title: "NAT unavailable", detail: err, health: .warn)
        } else if filteredForwards.isEmpty && (!query.isEmpty || store.natSeparators.isEmpty) {
            Notice(symbol: "arrow.left.arrow.right", title: query.isEmpty ? "No port forwards" : "No matches")
        } else {
            countLine("\(filteredForwards.count) port forwards")
            if canReorderNatRules {
                Text("Drag \(Image(systemName: "line.3.horizontal")) to reorder port forwards and separators in pfSense's flat NAT table.")
                    .scaledFont(11)
                    .foregroundStyle(theme.labelFaint)
                    .padding(.horizontal, 2)

                if natOrderIsDirty {
                    natOrderChangedBar
                }
            }

            let visibleItems = query.isEmpty
                ? displayedNatItems
                : currentNatItems.filter {
                    if case .forward(let item) = $0 {
                        return matches(item.forward, query.lowercased())
                    }
                    return false
                }
            ForEach(visibleItems) { item in
                if canReorderNatRules {
                    natReorderableRow(item)
                } else {
                    natRow(item)
                }
            }
        }
    }

    func natSeparatorRow(_ separator: RuleSeparator) -> some View {
        Button { selection = separator.id } label: {
            SeparatorBar(separator: separator, showsDisclosure: true)
        }
        .buttonStyle(.plain)
    }

    var natOrderChangedBar: some View {
        HStack(spacing: 10) {
            Text("NAT order changed")
                .scaledFont(12, weight: .semibold)
                .foregroundStyle(theme.warn)
            Spacer()
            Button("Discard") { natPendingOrder = nil }
                .scaledFont(12)
                .foregroundStyle(theme.labelMuted)
            Button {
                Task { await saveNatOrder() }
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

    func saveNatOrder() async {
        guard let items = natPendingOrder else { return }
        isSavingOrder = true
        do {
            _ = try await store.writeCoordinator.execute(.reorderNatRules(
                items: items.map(\.reorderItem),
                displayName: "NAT port forwards and separators"
            ))
            await store.refreshFirewallObjectsAfterWrite()
            natPendingOrder = nil
        } catch {
            natPendingOrder = nil
            reorderError = WriteError.from(error, operation: .other)
            showReorderErrorAlert = true
            await store.refreshFirewallObjectsAfterWrite()
        }
        isSavingOrder = false
    }

    func natReorderableRow(_ item: NatListItem) -> some View {
        HStack(spacing: 0) {
            RuleDragHandle()
                .onDrag {
                    natDraggingID = item.id
                    return NSItemProvider(object: item.id as NSString)
                }
            natRow(item)
                .frame(maxWidth: .infinity)
        }
        .onDrop(of: [.text], delegate: NatReorderDropDelegate(
            target: item,
            items: Binding(
                get: { displayedNatItems },
                set: { natPendingOrder = $0 }
            ),
            draggingID: $natDraggingID
        ))
    }

    @ViewBuilder
    func natRow(_ item: NatListItem) -> some View {
        switch item {
        case .forward(let rule):
            natForwardRow(rule.forward)
        case .separator(let separator):
            natSeparatorRow(separator)
        }
    }

    func natForwardRow(_ pf: PortForward) -> some View {
        Button { selection = pf.id } label: {
            Slab(rail: pf.health, muted: pf.disabled,
                 trailing: store.interfaceLabel(for: pf.interfaceName)) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text((pf.proto ?? "any").uppercased())
                            .scaledFont(10, weight: .semibold, design: .monospaced)
                            .foregroundStyle(theme.labelFaint)
                        if pf.disabled { StatusPill(text: "disabled", health: .idle) }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .scaledFont(10, weight: .semibold)
                            .foregroundStyle(theme.labelFaint)
                    }
                    natField("TO", pf.destinationSide.address)
                    natField("SENDS", pf.target)
                    if let port = natPorts(pf) { natField("PORT", port) }
                    if !pf.descr.isEmpty { natField("DESC", pf.descr, mono: false) }
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// The port it arrives on, and the port it is sent to when they differ.
    func natPorts(_ pf: PortForward) -> String? {
        let arriving = pf.destinationSide.port
        let local = pf.localPort
        switch (arriving, local) {
        case let (a?, l?) where a != l: return "\(a) → \(l)"
        case let (a?, _): return a
        case let (nil, l?): return l
        case (nil, nil): return nil
        }
    }

    func natField(_ label: String, _ value: String, mono: Bool = true) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .scaledFont(9, weight: .semibold)
                .foregroundStyle(theme.labelFaint)
                .frame(width: 44, alignment: .leading)
            // One line, truncated.
            //
            // A rule whose source expands to twenty networks was four lines
            // tall in a list of ninety-eight, and the list exists to be
            // scanned. The full value is on the detail screen, which has room
            // for it.
            Text(value)
                .scaledFont(12, weight: mono ? .medium : .regular,
                            design: mono ? .monospaced : .default)
                .foregroundStyle(mono ? theme.label : theme.labelMuted)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
    }

    // MARK: Aliases

    // MARK: Bits

    func countLine(_ text: String) -> some View {
        HStack {
            Text(text)
                .scaledFont(12, design: .monospaced)
                .foregroundStyle(theme.labelFaint)
            Spacer()
        }
    }
}
