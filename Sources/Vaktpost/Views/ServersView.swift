import SwiftUI

/// Manages the set of firewalls and which one is on screen.
struct ServersView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore
    @EnvironmentObject private var registry: ServerRegistry

    @State private var editing: ServerProfile?
    @State private var addingNew = false
    @State private var confirmLogout = false
    @State private var selectedServerID: UUID?

    var body: some View {
        List {
            Section("Firewalls") {
                ForEach(registry.servers) { server in
                    ServerCard(
                        server: server,
                        isActive: server.id == registry.active?.id,
                        onSelect: {
                            Task { await store.switchTo(server) }
                        },
                        onEdit: {
                            editing = server
                        }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                }
                .onDelete(perform: deleteServers)
            }

            if !registry.servers.isEmpty {
                Section {
                    Button {
                        addingNew = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add firewall")
                                .scaledFont(14, weight: .semibold)
                            Spacer()
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(theme.card)
                        .foregroundStyle(theme.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            if store.isConfigured {
                Section {
                    Button(role: .destructive) {
                        confirmLogout = true
                    } label: {
                        Text("Log out")
                            .scaledFont(14, weight: .semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(theme.card)
                            .foregroundStyle(theme.bad)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("Firewalls")
        .sheet(item: $editing) { server in
            NavigationStack { ServerEditView(profile: server) }
        }
        .sheet(isPresented: $addingNew) {
            NavigationStack { ServerEditView(profile: ServerProfile()) }
        }
        .confirmationDialog("Log out?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Log out", role: .destructive) {
                Task { await store.logout() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All metrics, logs, and cached data will be cleared.")
        }
    }

    private func deleteServers(at offsets: IndexSet) {
        for index in offsets {
            let server = registry.servers[index]
            Task { await store.removed(server) }
        }
    }
}

struct ServerCard: View {
    @EnvironmentObject private var theme: ThemeManager
    let server: ServerProfile
    let isActive: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void

    var body: some View {
        Slab(rail: isActive ? .ok : .idle) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(server.displayName)
                            .scaledFont(15, weight: .semibold)
                            .foregroundStyle(theme.label)
                        if isActive { StatusPill(text: "active", health: .ok) }
                        if !server.hasCredentials { StatusPill(text: "no password", health: .warn) }
                    }
                    Text(server.baseURL)
                        .scaledFont(11, design: .monospaced)
                        .foregroundStyle(theme.labelFaint)
                        .lineLimit(2)
                    if !server.pinnedFingerprint.isEmpty {
                        Text("pinned \(server.pinnedFingerprint.prefix(12))…")
                            .scaledFont(10, design: .monospaced)
                            .foregroundStyle(theme.ok)
                    } else if server.allowUntrustedTLS {
                        Text("untrusted TLS accepted")
                            .scaledFont(10, design: .monospaced)
                            .foregroundStyle(theme.warn)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { if !isActive { onSelect() } }
        }
        .swipeActions(edge: .trailing) {
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(theme.accentColor)
        }
    }
}

// MARK: - Edit

struct ServerEditView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore
    @EnvironmentObject private var registry: ServerRegistry
    @Environment(\.dismiss) private var dismiss
    @State private var offerPinning = false
    @State private var pendingFingerprint: String?

    @State var profile: ServerProfile
    @State private var password = ""
    @State private var showKey = false
    @State private var isTesting = false
    @State private var message: String?
    @State private var messageHealth: Health = .idle
    @State private var confirmDelete = false

    private var isExisting: Bool { registry.servers.contains { $0.id == profile.id } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Slab(rail: .info, title: "Firewall") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabelledField(title: "Label", text: $profile.label,
                                      placeholder: "fw01 — Stockholm")
                        LabelledField(title: "Base URL", text: $profile.baseURL,
                                      placeholder: "https://192.168.1.1",
                                      keyboard: .URL, autocap: false)
                        LabelledField(title: "Username", text: $profile.username,
                                      placeholder: "admin", autocap: false)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("PASSWORD")
                                .scaledFont(11, weight: .semibold)
                                .tracking(0.8)
                                .foregroundStyle(theme.labelFaint)
                            HStack {
                                Group {
                                    if showKey {
                                        TextField("password", text: $password)
                                    } else {
                                        SecureField("password", text: $password)
                                    }
                                }
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .scaledFont(14, design: .monospaced)
                                Button { showKey.toggle() } label: {
                                    Image(systemName: showKey ? "eye.slash" : "eye")
                                        .foregroundStyle(theme.labelMuted)
                                }
                            }
                            .padding(10)
                            .background(theme.cardRaised)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }

                Slab(rail: profile.pinnedFingerprint.isEmpty && profile.allowUntrustedTLS ? .warn : .info,
                     title: "TLS") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $profile.allowUntrustedTLS) {
                            Text("Allow untrusted certificate")
                                .scaledFont(14)
                                .foregroundStyle(theme.label)
                        }
                        .tint(theme.accentColor)

                        TextField("not pinned", text: $profile.pinnedFingerprint)
                            .scaledFont(11, design: .monospaced)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(10)
                            .background(theme.cardRaised)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        Button {
                            Task {
                                if let fp = await store.client.lastSeenFingerprint {
                                    profile.pinnedFingerprint = fp
                                    message = "Pinned the certificate from the last connection."
                                    messageHealth = .ok
                                } else {
                                    message = "Connect once first, then pin what was presented."
                                    messageHealth = .warn
                                }
                            }
                        } label: {
                            Text("Pin last seen certificate")
                                .scaledFont(13, weight: .medium)
                                .foregroundStyle(theme.accentColor)
                        }
                    }
                }

                Slab(rail: .info, title: "Refresh") {
                    VStack(alignment: .leading, spacing: 10) {
                        Stepper(value: $profile.refreshSeconds, in: 10...300, step: 10) {
                            FieldRow(key: "Auto-refresh", value: "\(profile.refreshSeconds)s")
                        }
                        .tint(theme.accentColor)
                        Stepper(value: $profile.logLimit, in: 25...500, step: 25) {
                            FieldRow(key: "Log lines fetched", value: "\(profile.logLimit)")
                        }
                        .tint(theme.accentColor)
                    }
                }

                if let message {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message)
                            .scaledFont(12)
                            .foregroundStyle(messageHealth.color(theme))
                        if messageHealth == .warn, !isExisting {
                            Button("Test Connection") {
                                Task {
                                    isTesting = true
                                    defer { isTesting = false }
                                    do {
                                        let version = try await store.client.ping()
                                        self.message = "Connected — pfSense \(version)"
                                        messageHealth = .ok
                                    } catch {
                                        self.message = error.localizedDescription
                                        messageHealth = .bad
                                    }
                                }
                            }
                            .scaledFont(12, weight: .medium)
                            .foregroundStyle(theme.accentColor)
                        }
                    }
                }

                if isExisting {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Text("Remove this firewall")
                            .scaledFont(14, weight: .semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(theme.card)
                            .foregroundStyle(theme.bad)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle(isExisting ? "Edit firewall" : "Add firewall")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await saveAndTest() }
                } label: {
                    if isTesting { ProgressView().controlSize(.small) } else { Text("Save") }
                }
                .disabled(isTesting || profile.baseURL.isEmpty)
            }
        }
        .onAppear { password = Keychain.password(for: profile.id) ?? "" }
        .confirmationDialog("Pin this certificate?", isPresented: $offerPinning,
                            titleVisibility: .visible) {
            Button("Pin it") {
                if let pendingFingerprint {
                    profile.pinnedFingerprint = pendingFingerprint
                    profile.allowUntrustedTLS = false
                    Task {
                        await store.saved(profile)
                        dismiss()
                    }
                }
            }
            Button("Not now", role: .cancel) { dismiss() }
        } message: {
            Text("The connection worked. Pinning means only this exact certificate is accepted from now on, which stops anything else answering for your firewall. You will need to pin again when you renew it.")
        }
        .confirmationDialog("Remove this firewall?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                Task {
                    await store.removed(profile)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its password is deleted from the keychain.")
        }
    }

    private func saveAndTest() async {
        isTesting = true
        defer { isTesting = false }

        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        switch Keychain.setPassword(trimmedPassword, for: profile.id) {
        case .success:
            break
        case .failure(let error):
            message = error.errorDescription ?? "Failed to save the password."
            messageHealth = .bad
            return
        }
        var p = profile
        p.normalize()
        profile = p
        await store.saved(p)

        guard registry.active?.id == p.id else {
            // Not the active firewall, so there is nothing to test against.
            // Saving is the whole action; staying open would leave the person
            // wondering what else the screen wanted.
            dismiss()
            return
        }

        do {
            let version = try await store.client.ping()

            // Offer to pin what we just connected to.
            //
            // pfSense ships a self-signed certificate, so the first connection
            // is necessarily made with untrusted TLS allowed. That is the one
            // moment the app knows the certificate is the right one — the
            // person is looking at the firewall they just typed in — and it is
            // the moment to fix it in place. Asking rather than pinning
            // silently, because pinning is a commitment that breaks the
            // connection when the certificate is renewed.
            if profile.pinnedFingerprint.isEmpty,
               profile.allowUntrustedTLS,
               let seen = await store.client.lastSeenFingerprint {
                pendingFingerprint = seen
                message = "Connected — pfSense \(version)"
                messageHealth = .ok
                offerPinning = true
                return
            }

            message = "Connected — pfSense \(version)"
            messageHealth = .ok
            dismiss()
        } catch {
            // Stays open: the error is the reason to still be here.
            message = error.localizedDescription
            messageHealth = .bad
        }
    }
}

// MARK: - Shared field

struct LabelledField: View {
    @EnvironmentObject private var theme: ThemeManager
    let title: String
    @Binding var text: String
    var placeholder: String
    var keyboard: UIKeyboardType = .default
    var autocap: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .scaledFont(11, weight: .semibold)
                .tracking(0.8)
                .foregroundStyle(theme.labelFaint)
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocap ? .sentences : .never)
                .autocorrectionDisabled()
                .scaledFont(14)
                .foregroundStyle(theme.label)
                .padding(10)
                .background(theme.cardRaised)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}
