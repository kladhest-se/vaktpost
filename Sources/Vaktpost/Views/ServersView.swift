import SwiftUI

/// Manages the set of firewalls and which one is on screen.
struct ServersView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore
    @EnvironmentObject private var registry: ServerRegistry

    @State private var editing: ServerProfile?
    @State private var addingNew = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(registry.servers) { server in
                    ServerCard(
                        server: server,
                        isActive: registry.active?.id == server.id,
                        onSelect: { Task { await store.switchTo(server) } },
                        onEdit: { editing = server }
                    )
                }

                Button {
                    addingNew = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add firewall")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(theme.card)
                    .foregroundStyle(theme.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Slab(rail: .idle, title: "Switching") {
                    Text("Throughput history is per-firewall and is cleared on switch — byte counters from a different box would otherwise chart as one enormous spike.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.labelFaint)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("Firewalls")
        .sheet(item: $editing) { server in
            NavigationStack { ServerEditView(profile: server) }
        }
        .sheet(isPresented: $addingNew) {
            NavigationStack { ServerEditView(profile: ServerProfile()) }
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
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.label)
                        if isActive { StatusPill(text: "active", health: .ok) }
                        if !server.hasCredentials { StatusPill(text: "no password", health: .warn) }
                    }
                    Text(server.baseURL)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.labelFaint)
                        .lineLimit(1)
                    if !server.pinnedFingerprint.isEmpty {
                        Text("pinned \(server.pinnedFingerprint.prefix(12))…")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(theme.ok)
                    } else if server.allowUntrustedTLS {
                        Text("untrusted TLS accepted")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(theme.warn)
                    }
                }
                Spacer()
                Button(action: onEdit) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(theme.labelMuted)
                        .padding(8)
                }
                .buttonStyle(.plain)
            }
            .contentShape(Rectangle())
            .onTapGesture { if !isActive { onSelect() } }
        }
    }
}

// MARK: - Edit

struct ServerEditView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore
    @EnvironmentObject private var registry: ServerRegistry
    @Environment(\.dismiss) private var dismiss

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
                                .font(.system(size: 11, weight: .semibold))
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
                                .font(.system(size: 14, design: .monospaced))
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
                                .font(.system(size: 14))
                                .foregroundStyle(theme.label)
                        }
                        .tint(theme.accentColor)

                        TextField("not pinned", text: $profile.pinnedFingerprint)
                            .font(.system(size: 11, design: .monospaced))
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
                                .font(.system(size: 13, weight: .medium))
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
                            .font(.system(size: 12))
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
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.accentColor)
                        }
                    }
                }

                if isExisting {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Text("Remove this firewall")
                            .font(.system(size: 14, weight: .semibold))
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
        .confirmationDialog("Remove this firewall?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                Task {
                    await store.removed(profile)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its API key is deleted from the keychain.")
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
            message = error.errorDescription ?? "Failed to save API key."
            messageHealth = .bad
            return
        }
        var p = profile
        p.normalize()
        profile = p
        await store.saved(p)

        if registry.active?.id == p.id {
            do {
                let version = try await store.client.ping()
                message = "Connected — pfSense \(version)"
                messageHealth = .ok
            } catch {
                message = error.localizedDescription
                messageHealth = .bad
            }
        } else {
            message = "Saved (untested — tap to test)"
            messageHealth = .warn
        }
        isTesting = false
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
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(theme.labelFaint)
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocap ? .sentences : .never)
                .autocorrectionDisabled()
                .font(.system(size: 14))
                .foregroundStyle(theme.label)
                .padding(10)
                .background(theme.cardRaised)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}
