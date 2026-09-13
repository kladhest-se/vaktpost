import SwiftUI

/// Firewall aliases, including staged create/edit/delete administration.
struct AliasesView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore

    @State private var query = ""
    @State private var showingNewAlias = false

    private var aliases: [FirewallAliasEntry] {
        guard !query.isEmpty else { return store.aliases }
        let q = query.lowercased()
        return store.aliases.filter {
            $0.name.lowercased().contains(q)
                || ($0.descr ?? "").lowercased().contains(q)
                || $0.addresses.contains { $0.lowercased().contains(q) }
                || (store.resolveAlias($0.name) ?? []).contains { $0.lowercased().contains(q) }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                FreshnessView(sections: [.aliases], showNames: true)
                pendingBanner
                AdministrationModeNotice()

                if let err = store.errors[.aliases] {
                    Notice(symbol: "exclamationmark.triangle",
                           title: "Aliases unavailable", detail: err, health: .warn)
                } else if store.aliases.isEmpty {
                    Notice(symbol: "tag.slash", title: "No aliases configured",
                           detail: "Use + to create a host, network, or port alias.")
                } else {
                    HStack {
                        Text("\(aliases.count) of \(store.aliases.count) aliases")
                            .scaledFont(12, design: .monospaced)
                            .foregroundStyle(theme.labelFaint)
                        Spacer()
                    }
                    ForEach(aliases) { alias in
                        NavigationLink {
                            AliasDetailView(aliasName: alias.name)
                        } label: {
                            AliasRow(alias: alias)
                        }
                        .buttonStyle(.plain)
                    }
                    if aliases.isEmpty {
                        Notice(symbol: "magnifyingglass", title: "No matches")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .readableWidth()
        }
        .refreshable { await store.refreshManually() }
        .background(theme.bg.ignoresSafeArea())
        .task { await store.loadFirewallObjects() }
        .searchable(text: $query, prompt: "Alias name, address or port")
        .navigationTitle("Aliases")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNewAlias = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New alias")
            }
        }
        .sheet(isPresented: $showingNewAlias) {
            AliasEditSheet(form: .blank, aliases: store.aliases) { form in
                _ = try await store.writeCoordinator.execute(
                    .saveAlias(alias: form.payload(), displayName: form.name)
                )
                await store.refreshFirewallObjectsAfterWrite()
            }
        }
    }

    @ViewBuilder
    private var pendingBanner: some View {
        if store.firewallChangesPending {
            NavigationLink {
                FirewallReloadView()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(theme.warn)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Firewall changes are waiting")
                            .scaledFont(13, weight: .semibold)
                            .foregroundStyle(theme.label)
                        Text("Saved, but not active. Review and apply changes.")
                            .scaledFont(11)
                            .foregroundStyle(theme.labelMuted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(theme.labelFaint)
                }
                .padding(13)
                .background(theme.warn.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

struct AliasRow: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    let alias: FirewallAliasEntry

    var body: some View {
        Slab(rail: .info, trailing: alias.type) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(alias.name)
                        .scaledFont(15, weight: .semibold, design: .monospaced)
                        .foregroundStyle(theme.label)
                    Spacer()
                    Text("\(alias.addresses.count)")
                        .scaledFont(12, weight: .bold, design: .monospaced)
                        .foregroundStyle(theme.labelFaint)
                    Image(systemName: "chevron.right")
                        .scaledFont(11)
                        .foregroundStyle(theme.labelFaint)
                }
                if let description = alias.descr, !description.isEmpty {
                    Text(description)
                        .scaledFont(12)
                        .foregroundStyle(theme.labelMuted)
                }
                if !alias.addresses.isEmpty {
                    Text(alias.addresses.prefix(3).joined(separator: "  "))
                        .scaledFont(11, design: .monospaced)
                        .foregroundStyle(theme.labelFaint)
                        .lineLimit(2)
                }
            }
        }
    }
}

private struct AliasDetailView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    @Environment(\.dismiss) private var dismiss

    let aliasName: String
    @State private var showingEditor = false
    @State private var isDeleting = false
    @State private var showErrorAlert = false
    @State private var writeError: WriteError?

    private var alias: FirewallAliasEntry? {
        store.aliases.first { $0.name == aliasName }
    }

    private var canEdit: Bool {
        guard let alias else { return false }
        return ["host", "network", "port"].contains(alias.type.lowercased())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AdministrationModeNotice()
                if let alias {
                    Slab(rail: .info, title: "Alias", trailing: alias.type) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(alias.name)
                                .scaledFont(17, weight: .semibold, design: .monospaced)
                                .foregroundStyle(theme.label)
                            if let description = alias.descr, !description.isEmpty {
                                Text(description)
                                    .scaledFont(13)
                                    .foregroundStyle(theme.labelMuted)
                            }
                        }
                    }

                    Slab(rail: .info, title: "Members", trailing: "\(alias.addresses.count)") {
                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(Array(alias.addresses.enumerated()), id: \.offset) { index, member in
                                HStack(alignment: .top) {
                                    Text(member)
                                        .scaledFont(13, design: .monospaced)
                                        .foregroundStyle(theme.label)
                                    Spacer(minLength: 12)
                                    if alias.details.indices.contains(index), !alias.details[index].isEmpty {
                                        Text(alias.details[index])
                                            .scaledFont(11)
                                            .foregroundStyle(theme.labelMuted)
                                            .multilineTextAlignment(.trailing)
                                    }
                                }
                                if index < alias.addresses.count - 1 {
                                    Divider().overlay(theme.hairline)
                                }
                            }
                        }
                    }

                    if !canEdit {
                        Notice(symbol: "lock", title: "Managed alias",
                               detail: "Dynamic URL and package-managed aliases remain view-only so Vaktpost cannot overwrite their provider settings.",
                               health: .info)
                    }

                    VStack(spacing: 10) {
                        Button("Edit Alias") { showingEditor = true }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                            .disabled(!store.canAdminister || !canEdit || isDeleting)

                        Button(role: .destructive) {
                            Task { await delete(alias) }
                        } label: {
                            if isDeleting { ProgressView() } else { Text("Delete Alias") }
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .disabled(!store.canAdminister || isDeleting)
                    }

                    Notice(symbol: "clock.badge.checkmark", title: "Changes stay pending",
                           detail: "Creating, editing, or deleting an alias does not change active traffic until Apply Changes succeeds.",
                           health: .warn)
                } else {
                    Notice(symbol: "tag.slash", title: "Alias no longer present")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .readableWidth()
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle(aliasName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEditor) {
            if let alias {
                AliasEditSheet(form: AliasEditForm(alias), aliases: store.aliases) { form in
                    _ = try await store.writeCoordinator.execute(
                        .saveAlias(alias: form.payload(), displayName: form.name)
                    )
                    await store.refreshFirewallObjectsAfterWrite()
                }
            }
        }
        .writeErrorAlert(isErrorPresented: $showErrorAlert, error: $writeError)
    }

    private func delete(_ alias: FirewallAliasEntry) async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            _ = try await store.writeCoordinator.execute(
                .deleteAlias(name: alias.name, displayName: alias.name)
            )
            await store.refreshFirewallObjectsAfterWrite()
            dismiss()
        } catch {
            writeError = WriteError.from(error, operation: .other)
            showErrorAlert = true
        }
    }
}

private struct AliasMemberDraft: Identifiable, Equatable {
    let id: UUID
    var value: String
    var detail: String

    init(id: UUID = UUID(), value: String = "", detail: String = "") {
        self.id = id
        self.value = value
        self.detail = detail
    }
}

private struct AliasEditForm: Equatable {
    var name: String
    var originalName: String
    var type: String
    var descr: String
    var members: [AliasMemberDraft]
    var isCreating: Bool

    static let blank = AliasEditForm(
        name: "", originalName: "", type: "host", descr: "",
        members: [AliasMemberDraft()], isCreating: true
    )

    init(_ alias: FirewallAliasEntry) {
        name = alias.name
        originalName = alias.name
        type = alias.type.lowercased()
        descr = alias.descr ?? ""
        let count = max(alias.addresses.count, alias.details.count)
        members = (0..<count).map { index in
            AliasMemberDraft(
                value: alias.addresses.indices.contains(index) ? alias.addresses[index] : "",
                detail: alias.details.indices.contains(index) ? alias.details[index] : ""
            )
        }
        if members.isEmpty { members = [AliasMemberDraft()] }
        isCreating = false
    }

    private init(name: String, originalName: String, type: String, descr: String,
                 members: [AliasMemberDraft], isCreating: Bool) {
        self.name = name
        self.originalName = originalName
        self.type = type
        self.descr = descr
        self.members = members
        self.isCreating = isCreating
    }

    func payload() -> JSONDict {
        JSONDict([
            "name": .string(name.trimmingCharacters(in: .whitespacesAndNewlines)),
            "original_name": .string(originalName),
            "type": .string(type),
            "descr": .string(descr.trimmingCharacters(in: .whitespacesAndNewlines)),
            "members": .array(members.map {
                .string($0.value.trimmingCharacters(in: .whitespacesAndNewlines))
            }),
            "details": .array(members.map {
                .string($0.detail.trimmingCharacters(in: .whitespacesAndNewlines))
            }),
            "create": .bool(isCreating)
        ])
    }
}

private struct AliasEditSheet: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    @Environment(\.dismiss) private var dismiss

    let aliases: [FirewallAliasEntry]
    let onSave: (AliasEditForm) async throws -> Void

    @State private var edited: AliasEditForm
    @State private var isSaving = false
    @State private var showErrorAlert = false
    @State private var writeError: WriteError?
    private let original: AliasEditForm

    init(form: AliasEditForm, aliases: [FirewallAliasEntry],
         onSave: @escaping (AliasEditForm) async throws -> Void) {
        original = form
        _edited = State(initialValue: form)
        self.aliases = aliases
        self.onSave = onSave
    }

    private var normalizedName: String {
        edited.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nameIsUnique: Bool {
        !aliases.contains {
            $0.name.caseInsensitiveCompare(normalizedName) == .orderedSame
                && $0.name != edited.originalName
        }
    }

    private var isValid: Bool {
        FieldValidator.isAliasName(normalizedName)
            && nameIsUnique
            && ["host", "network", "port"].contains(edited.type)
            && !edited.members.isEmpty
            && edited.members.allSatisfy {
                let value = $0.value.trimmingCharacters(in: .whitespacesAndNewlines)
                return !value.isEmpty && value != normalizedName
            }
    }

    private var isDirty: Bool { edited.isCreating || edited != original }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    AdministrationModeNotice()
                    Slab(rail: .info, title: "Alias") {
                        VStack(alignment: .leading, spacing: 12) {
                            if edited.isCreating {
                                EditField(label: "Name", text: $edited.name,
                                          prompt: "alias_host_server")
                            } else {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("NAME")
                                        .scaledFont(9, weight: .semibold)
                                        .foregroundStyle(theme.labelFaint)
                                    Text(edited.name)
                                        .scaledFont(14, design: .monospaced)
                                        .foregroundStyle(theme.label)
                                        .padding(.vertical, 9)
                                    Text("The name stays fixed so existing rule references cannot break.")
                                        .scaledFont(10)
                                        .foregroundStyle(theme.labelFaint)
                                }
                            }
                            if edited.isCreating {
                                EditChoice(label: "Type", options: ["host", "network", "port"],
                                           selection: $edited.type)
                            } else {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("TYPE")
                                        .scaledFont(9, weight: .semibold)
                                        .foregroundStyle(theme.labelFaint)
                                    Text(edited.type)
                                        .scaledFont(14, design: .monospaced)
                                        .foregroundStyle(theme.label)
                                    Text("Create a new alias to change type; existing policy may depend on this one.")
                                        .scaledFont(10)
                                        .foregroundStyle(theme.labelFaint)
                                }
                            }
                            EditField(label: "Description", text: $edited.descr,
                                      prompt: "What this alias contains", mono: false)
                        }
                    }

                    Slab(rail: .info, title: "Members", trailing: "\(edited.members.count)") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach($edited.members) { $member in
                                VStack(alignment: .leading, spacing: 8) {
                                    EditField(label: edited.type == "port" ? "Port or port alias" : "Address, network, host, or alias",
                                              text: $member.value,
                                              prompt: edited.type == "port" ? "443" : "192.0.2.10")
                                    HStack(alignment: .bottom, spacing: 8) {
                                        EditField(label: "Member description", text: $member.detail,
                                                  prompt: "Optional", mono: false)
                                        Button(role: .destructive) {
                                            let id = member.id
                                            edited.members.removeAll { $0.id == id }
                                            if edited.members.isEmpty {
                                                edited.members.append(AliasMemberDraft())
                                            }
                                        } label: {
                                            Image(systemName: "trash")
                                                .frame(width: 36, height: 36)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                                if member.id != edited.members.last?.id {
                                    Divider().overlay(theme.hairline)
                                }
                            }
                            Button {
                                edited.members.append(AliasMemberDraft())
                            } label: {
                                Label("Add member", systemImage: "plus")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if !nameIsUnique {
                        Notice(symbol: "exclamationmark.triangle",
                               title: "Alias name already exists", health: .warn)
                    } else if !normalizedName.isEmpty && !FieldValidator.isAliasName(normalizedName) {
                        Notice(symbol: "exclamationmark.triangle", title: "Invalid alias name",
                               detail: "Start with a letter or underscore and use only letters, numbers, and underscores.",
                               health: .warn)
                    }

                    Notice(symbol: "clock.badge.checkmark",
                           title: "Saved as a pending firewall change",
                           detail: "Use Apply Changes when all alias, filter, and NAT edits are ready.",
                           health: .warn)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle(edited.isCreating ? "New alias" : "Edit alias")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(!store.canAdminister || !isDirty || !isValid)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .writeErrorAlert(isErrorPresented: $showErrorAlert, error: $writeError)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(edited)
            dismiss()
        } catch {
            writeError = WriteError.from(error, operation: .other)
            showErrorAlert = true
        }
    }
}
