import SwiftUI

/// Manages the set of firewalls and which one is on screen.
///
/// One row per firewall, and nothing else. The previous version carried a
/// section header repeating the navigation title, a status pill, a fingerprint
/// prefix, a TLS note, an edit button and an add button in a separate card —
/// six things competing on a screen that exists to answer "which firewall, and
/// is anything wrong with it".
///
/// What a row needs to say is the name, the address, and whether it can
/// connect. Everything else belongs to editing it, which is one tap away.
struct ServersView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    @Environment(\.serverRegistry) private var registry: ServerRegistry

    @State private var editing: ServerProfile?
    @State private var addingNew = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(registry.servers) { server in
                    ServerRow(
                        server: server,
                        isActive: server.id == registry.active?.id,
                        onSelect: { Task { await store.switchTo(server) } },
                        onEdit: { editing = server }
                    )
                    .contextMenu {
                        Button {
                            editing = server
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            delete(server)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }

                Button {
                    addingNew = true
                } label: {
                    // A row, not a card: it belongs to the same list as the
                    // firewalls above it and reads as the next item rather
                    // than a separate control.
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                            .scaledFont(13, weight: .semibold)
                        Text("Add firewall")
                            .scaledFont(14, weight: .medium)
                        Spacer()
                    }
                    .foregroundStyle(theme.accentColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(theme.card, in: RoundedRectangle(cornerRadius: 12,
                                                                 style: .continuous))
                }
                .buttonStyle(.plain)

                Text("Tap a firewall to switch to it. Press and hold to edit or remove.")
                    .scaledFont(11)
                    .foregroundStyle(theme.labelFaint)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .readableWidth()
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

    private func delete(_ server: ServerProfile) {
        Task { await store.removed(server) }
    }
}

/// One firewall.
///
/// The active one is marked once, by a filled dot rather than a pill — a pill
/// saying "active" beside a name is a label for something already obvious from
/// the tick, and it competed with the warnings that matter.
struct ServerRow: View {
    @Environment(\.themeManager) private var theme: ThemeManager

    let server: ServerProfile
    let isActive: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void

    var body: some View {
        Button {
            if isActive { onEdit() } else { onSelect() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                    .scaledFont(16)
                    .foregroundStyle(isActive ? theme.ok : theme.labelFaint)

                VStack(alignment: .leading, spacing: 3) {
                    Text(server.displayName)
                        .scaledFont(15, weight: .semibold)
                        .foregroundStyle(theme.label)

                    Text(server.baseURL)
                        .scaledFont(11, design: .monospaced)
                        .foregroundStyle(theme.labelFaint)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    // Only when something is worth saying. A pinned
                    // certificate is the expected state and says nothing by
                    // being mentioned; the absence of one does.
                    if !server.hasCredentials {
                        Text("No password saved")
                            .scaledFont(11)
                            .foregroundStyle(theme.warn)
                    } else if server.pinnedFingerprint.isEmpty && server.allowUntrustedTLS {
                        Text("Certificate not pinned")
                            .scaledFont(11)
                            .foregroundStyle(theme.warn)
                    }

                    Text(server.isAdministrationEnabled ? "Administration enabled" : "Monitor only")
                        .scaledFont(11, weight: .medium)
                        .foregroundStyle(server.isAdministrationEnabled ? theme.warn : theme.ok)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .scaledFont(11, weight: .semibold)
                    .foregroundStyle(theme.labelFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Edit

struct ServerEditView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    @Environment(\.serverRegistry) private var registry: ServerRegistry
    @Environment(\.dismiss) private var dismiss
    @State private var offerPinning = false
    @State private var confirmedFingerprint: String?
    @State private var pendingFingerprint: String?

    @State var profile: ServerProfile
    @State private var password = ""
    @State private var showKey = false
    @State private var isTesting = false
    @State private var message: String?
    @State private var messageHealth: Health = .idle
    @State private var confirmDelete = false
    @State private var showAdministrationRisk = false
    @State private var isAuthenticatingAdministration = false

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
                                            .textInputAutocapitalization(.never)
                                            .autocorrectionDisabled()
                                            .scaledFont(14, design: .monospaced)
                                    } else {
                                        SecureField("password", text: $password)
                                            .textInputAutocapitalization(.never)
                                            .autocorrectionDisabled()
                                            .scaledFont(14, design: .monospaced)
                                    }
                                }
                                toggleKeyButton
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

                        pinnedFingerprintField

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
                        refreshStepper
                        logLimitStepper
                    }
                }

                administrationSlab

                if message != nil {
                    messageView
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
                .disabled(isTesting || isAuthenticatingAdministration || profile.baseURL.isEmpty)
            }
        }
        .onAppear { password = Keychain.password(for: profile.id) ?? "" }
        .confirmationDialog("Pin this certificate?", isPresented: $offerPinning,
                            titleVisibility: .visible) {
            Button("Pin it") {
                if let fp = confirmedFingerprint {
                    profile.pinnedFingerprint = fp
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
            Text("Its password and encrypted local administrative history are deleted from this device.")
        }
        .confirmationDialog("Enable administrative actions?",
                            isPresented: $showAdministrationRisk,
                            titleVisibility: .visible) {
            Button("Authenticate and enable", role: .destructive) {
                Task { await authenticateForAdministration() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This firewall uses an administrator-equivalent XML-RPC credential. Enabling this mode allows Vaktpost to change rules, delete port forwards, reload the firewall, restart services, and drop active states. Face ID or Touch ID is required to enable it.")
        }
    }

    private var administrationSlab: some View {
        Slab(rail: profile.isAdministrationEnabled ? .warn : .ok,
             title: "Administration") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: profile.isAdministrationEnabled ? "lock.open.fill" : "eye.fill")
                        .foregroundStyle(profile.isAdministrationEnabled ? theme.warn : theme.ok)
                    Text(profile.isAdministrationEnabled ? "Administrative actions enabled" : "Monitor-only mode")
                        .scaledFont(14, weight: .semibold)
                        .foregroundStyle(theme.label)
                }

                Text(profile.isAdministrationEnabled
                     ? "Vaktpost may perform its declared, confirmed firewall mutations for this profile."
                     : "Vaktpost can inspect this firewall, but every mutation is blocked before a request is sent.")
                    .scaledFont(12)
                    .foregroundStyle(theme.labelMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if profile.isAdministrationEnabled {
                    Button("Return to monitor-only") {
                        profile.administrationEnabled = false
                        message = "Monitor-only mode selected. Tap Save to apply it."
                        messageHealth = .ok
                    }
                    .scaledFont(13, weight: .medium)
                    .foregroundStyle(theme.accentColor)
                } else {
                    Button {
                        showAdministrationRisk = true
                    } label: {
                        HStack(spacing: 6) {
                            if isAuthenticatingAdministration {
                                ProgressView().controlSize(.small)
                            }
                            Text(isAuthenticatingAdministration
                                 ? "Authenticating…"
                                 : "Enable administrative actions")
                        }
                        .scaledFont(13, weight: .semibold)
                        .foregroundStyle(theme.warn)
                    }
                    .disabled(isAuthenticatingAdministration)
                }
            }
        }
    }

    private func authenticateForAdministration() async {
        guard !isAuthenticatingAdministration else { return }
        isAuthenticatingAdministration = true
        defer { isAuthenticatingAdministration = false }

        switch await BiometricAuth.authenticate(
            reason: "Enable administrative actions for \(profile.displayName)",
            allowPasscode: false
        ) {
        case .success:
            profile.administrationEnabled = true
            message = "Identity verified. Tap Save to enable administrative actions for this firewall."
            messageHealth = .warn
        case let .failed(text), let .unavailable(text):
            profile.administrationEnabled = false
            message = "Administrative actions remain disabled. \(text)"
            messageHealth = .bad
        case .cancelled:
            profile.administrationEnabled = false
        }
    }

    private var refreshStepper: some View {
        Stepper(value: $profile.refreshSeconds, in: 10...300, step: 10) {
            HStack {
                Text("Auto-refresh")
                    .scaledFont(10, weight: .semibold)
                    .foregroundStyle(theme.labelFaint)
                Spacer()
                Text("\(profile.refreshSeconds)s")
                    .scaledFont(13, design: .monospaced)
                    .foregroundStyle(theme.label)
            }
        }
        .tint(theme.accentColor)
    }

    private var logLimitStepper: some View {
        Stepper(value: $profile.logLimit, in: 25...500, step: 25) {
            HStack {
                Text("Log lines fetched")
                    .scaledFont(10, weight: .semibold)
                    .foregroundStyle(theme.labelFaint)
                Spacer()
                Text("\(profile.logLimit)")
                    .scaledFont(13, design: .monospaced)
                    .foregroundStyle(theme.label)
            }
        }
        .tint(theme.accentColor)
    }

    private var messageView: some View {
        Group {
            if message != nil {
                let healthColor = messageHealth.color(theme)
                VStack(alignment: .leading, spacing: 8) {
                    Text(message ?? "")
                        .scaledFont(12)
                        .foregroundStyle(healthColor)
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
        }
    }

    private var pinnedFingerprintField: some View {
        TextField("not pinned", text: $profile.pinnedFingerprint)
            .scaledFont(11, design: .monospaced)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(10)
            .background(theme.cardRaised)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var toggleKeyButton: some View {
        Button { showKey.toggle() } label: {
            Image(systemName: showKey ? "eye.slash" : "eye")
                .foregroundStyle(theme.labelMuted)
        }
    }

    private func saveAndTest() async {
        isTesting = true
        defer { isTesting = false }

        switch Keychain.setPassword(password, for: profile.id) {
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
        // The trust delegate may have saved a pin during the refresh.
        if let saved = registry.servers.first(where: { $0.id == p.id }) { profile = saved }

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
                confirmedFingerprint = seen
                offerPinning = true
                message = "Connected — pfSense \(version)"
                messageHealth = .ok
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
    @Environment(\.themeManager) private var theme: ThemeManager
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
