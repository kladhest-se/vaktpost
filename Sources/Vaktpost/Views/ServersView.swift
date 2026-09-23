import SwiftUI
import UIKit

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
    @State private var pendingRemoval: ServerProfile?
    @State private var removalError: String?

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
                            pendingRemoval = server
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
        .confirmationDialog(
            "Remove this firewall?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { server in
            Button("Remove firewall and local data", role: .destructive) { delete(server) }
            Button("Cancel", role: .cancel) {}
        }
        .alert(removalError ?? "Could not remove firewall", isPresented: Binding(
            get: { removalError != nil },
            set: { if !$0 { removalError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        }
    }

    private func delete(_ server: ServerProfile) {
        Task {
            do {
                try await store.removed(server)
            } catch {
                removalError = error.localizedDescription
            }
            pendingRemoval = nil
        }
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
                    } else if let observed = server.certificateObservation,
                              !server.pinnedFingerprint.isEmpty,
                              !observed.matches(pin: server.pinnedFingerprint) {
                        Text("Certificate changed — connection blocked")
                            .scaledFont(11)
                            .foregroundStyle(theme.bad)
                    } else if server.pinnedFingerprint.isEmpty {
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
    @Environment(\.openURL) private var openURL
    @State private var offerPinning = false
    @State private var confirmedFingerprint: String?
    @State private var pendingFingerprint: String?
    @State private var showRepinConfirmation = false

    @State var profile: ServerProfile
    @State private var password = ""
    @State private var revealedPassword: String?
    @State private var showKey = false
    @State private var isTesting = false
    @State private var isAuthenticatingCredential = false
    @State private var message: String?
    @State private var messageHealth: Health = .idle
    /// Set when the last Save reached the firewall and it refused the
    /// sign-in. Shown as its own card, directly under the credentials,
    /// rather than as one line at the foot of the form.
    @State private var authProblem: AuthenticationProblem?
    /// Set only by `.unavailable` — biometry that cannot run at all right
    /// now (none enrolled, none set up, locked out) rather than one attempt
    /// that failed. The difference is what to do next: a failed attempt
    /// invites tapping the same button again, since the same prompt might
    /// succeed the second time. Unavailable won't, no matter how many times
    /// it's tapped, until something changes outside this screen — so that
    /// case gets a way there instead of a button that would just fail the
    /// same way again.
    @State private var showOpenSettingsButton = false
    @State private var confirmDelete = false
    @State private var showAdministrationRisk = false

    private var isExisting: Bool { registry.servers.contains { $0.id == profile.id } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Slab(rail: authProblem?.pointsAtCredentials == true ? .bad : .info, title: "Firewall") {
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
                                        TextField(passwordPlaceholder, text: $password)
                                            .textInputAutocapitalization(.never)
                                            .autocorrectionDisabled()
                                            .scaledFont(14, design: .monospaced)
                                    } else {
                                        SecureField(passwordPlaceholder, text: $password)
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

                // The outcome of Save sits under the fields it is about, where
                // it is seen without scrolling past the rest of the form.
                if let authProblem {
                    AuthenticationProblemCard(problem: authProblem)
                } else if message != nil {
                    messageView
                }

                CertificateSlab(profile: profile,
                                pendingFingerprint: $pendingFingerprint,
                                showRepinConfirmation: $showRepinConfirmation)

                Slab(rail: .info, title: "Refresh") {
                    VStack(alignment: .leading, spacing: 10) {
                        refreshStepper
                        logLimitStepper
                    }
                }

                administrationSlab

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
                .disabled(isTesting || isAuthenticatingCredential || profile.baseURL.isEmpty)
            }
        }
        // Never pull a saved administrator password into view state merely
        // because the editor appeared. It is loaded only when the person taps
        // reveal, with a fresh prompt when optional biometric protection is
        // enabled and available.
        .onDisappear {
            password = ""
            revealedPassword = nil
            showKey = false
        }
        // A message here is the result of a specific attempt under a
        // specific configuration — "TLS handshake failed" was true of the
        // settings at the moment that attempt ran. Changing any of the
        // settings that could have caused it and leaving the same message
        // on screen makes it read as still true of what's now configured,
        // when nothing has actually retried it yet. Clearing it here isn't
        // itself a retry — Save still is, via saveAndTest() — it just stops
        // the screen from looking like a fix already made didn't work.
        .onChange(of: profile.baseURL) { message = nil; authProblem = nil; showOpenSettingsButton = false }
        .onChange(of: profile.username) { message = nil; authProblem = nil; showOpenSettingsButton = false }
        .onChange(of: profile.pinnedFingerprint) { message = nil; showOpenSettingsButton = false }
        .onChange(of: password) { message = nil; authProblem = nil; showOpenSettingsButton = false }
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
            Text("The connection worked. Pinning means only this exact certificate is accepted from now on, "
                + "which stops anything else answering for your firewall. "
                + "You will need to pin again when you renew it.")
        }
        .confirmationDialog("Replace the certificate pin?",
                            isPresented: $showRepinConfirmation,
                            titleVisibility: .visible) {
            Button("Replace pin", role: .destructive) {
                guard let fingerprint = pendingFingerprint,
                      registry.replaceCertificatePin(fingerprint, for: profile.id) else {
                    message = "The new certificate pin could not be saved."
                    messageHealth = .bad
                    return
                }
                profile.pinnedFingerprint = CertificateObservation.normalized(fingerprint)
                profile.allowUntrustedTLS = false
                pendingFingerprint = nil
                message = "Certificate pin replaced. Tap Save to reconnect and verify it."
                messageHealth = .warn
            }
            Button("Cancel", role: .cancel) { pendingFingerprint = nil }
        } message: {
            Text("Only continue after comparing the complete SHA-256 fingerprint with pfSense "
                 + "through a separate trusted path. The changed certificate has not been trusted yet.")
        }
        .confirmationDialog("Remove this firewall?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                Task {
                    do {
                        try await store.removed(profile)
                        dismiss()
                    } catch {
                        message = error.localizedDescription
                        messageHealth = .bad
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its password and encrypted local administrative history are deleted from this device.")
        }
        .confirmationDialog("Enable administrative actions?",
                            isPresented: $showAdministrationRisk,
                            titleVisibility: .visible) {
            Button("Enable for this firewall", role: .destructive) {
                profile.administrationEnabled = true
                message = "Tap Save to enable administrative actions for this firewall."
                messageHealth = .warn
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This firewall uses an administrator-equivalent XML-RPC credential. "
                + "Enabling this mode allows Vaktpost to change rules, delete port forwards, reload the firewall, restart services, and drop active states. "
                + "The setting applies only to \(profile.displayName) and takes effect after you tap Save.")
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
                        Text("Enable administrative actions")
                        .scaledFont(13, weight: .semibold)
                        .foregroundStyle(theme.warn)
                    }
                }
            }
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
                                    if let problem = AuthenticationProblem(error, username: profile.username) {
                                        authProblem = problem
                                        self.message = nil
                                    } else {
                                        self.message = error.localizedDescription
                                        messageHealth = .bad
                                    }
                                }
                            }
                        }
                        .scaledFont(12, weight: .medium)
                        .foregroundStyle(theme.accentColor)
                    }
                    if showOpenSettingsButton {
                        Button("Open Settings") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            openURL(url)
                        }
                        .scaledFont(12, weight: .medium)
                        .foregroundStyle(theme.accentColor)
                    }
                }
            }
        }
    }

    private var toggleKeyButton: some View {
        Button {
            if showKey {
                showKey = false
            } else {
                Task { await authenticateToRevealPassword() }
            }
        } label: {
            Group {
                if isAuthenticatingCredential {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                }
            }
            .foregroundStyle(theme.labelMuted)
        }
        .accessibilityLabel(showKey ? "Hide password" : "Show password")
        .disabled(isAuthenticatingCredential)
    }

    private var passwordPlaceholder: String {
        isExisting && Keychain.hasPassword(for: profile.id)
            ? "saved password unchanged"
            : "password"
    }

    private func authenticateToRevealPassword() async {
        guard !isAuthenticatingCredential else { return }

        guard credentialProtectionRequired else {
            revealPassword()
            return
        }

        isAuthenticatingCredential = true
        defer { isAuthenticatingCredential = false }

        switch await BiometricAuth.authenticate(
            reason: "Reveal the firewall password for \(profile.displayName)",
            allowPasscode: false
        ) {
        case .success:
            revealPassword()
        case let .unavailable(text):
            showKey = false
            message = "Password remains hidden. \(text) Set up Face ID or Touch ID in "
                + "Settings, then try again."
            messageHealth = .bad
            showOpenSettingsButton = true
        case let .failed(text):
            showKey = false
            message = "Password remains hidden. \(text)"
            messageHealth = .bad
            showOpenSettingsButton = false
        case .cancelled:
            showKey = false
        }
    }

    private func authenticateToReplacePassword() async -> Bool {
        guard !isAuthenticatingCredential else { return false }

        // Biometry protects this action only when the user opted in and iOS
        // can provide it. Keychain storage and ordinary firewall sign-in do
        // not depend on biometric enrollment.
        guard credentialProtectionRequired else {
            message = nil
            showOpenSettingsButton = false
            return true
        }

        isAuthenticatingCredential = true
        defer { isAuthenticatingCredential = false }

        switch await BiometricAuth.authenticate(
            reason: "Replace the administrator-equivalent password for \(profile.displayName)",
            allowPasscode: false
        ) {
        case .success:
            message = nil
            showOpenSettingsButton = false
            return true
        case let .unavailable(text):
            message = "Password was not changed. \(text) Set up Face ID or Touch ID in "
                + "Settings, then try again."
            messageHealth = .bad
            showOpenSettingsButton = true
            return false
        case let .failed(text):
            message = "Password was not changed. \(text)"
            messageHealth = .bad
            showOpenSettingsButton = false
            return false
        case .cancelled:
            return false
        }
    }

    private func saveAndTest() async {
        isTesting = true
        defer { isTesting = false }

        var p = profile
        p.normalize()
        guard p.validatedBaseURL != nil else {
            profile = p
            message = "Use an HTTPS base URL with only a host and optional port. Credentials, paths, queries, and fragments are not allowed."
            messageHealth = .bad
            return
        }

        let hasStoredPassword = Keychain.hasPassword(for: profile.id)
        let mustSavePassword = !hasStoredPassword
            || (!password.isEmpty && password != revealedPassword)
        if mustSavePassword {
            guard !password.isEmpty else {
                message = "Password cannot be empty."
                messageHealth = .bad
                return
            }
            if isExisting {
                guard await authenticateToReplacePassword() else { return }
            }
            let result = isExisting
                ? Keychain.replacePassword(password, for: profile.id)
                : Keychain.setPassword(password, for: profile.id)
            switch result {
            case .success:
                revealedPassword = password
            case .failure(let error):
                message = error.errorDescription ?? "Failed to save the password."
                messageHealth = .bad
                return
            }
        }
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

        authProblem = nil
        do {
            let version = try await store.client.ping()
            if let saved = registry.servers.first(where: { $0.id == p.id }) { profile = saved }
            message = "Connected — pfSense \(version)"
            messageHealth = .ok
            dismiss()
        } catch {
            if let saved = registry.servers.first(where: { $0.id == p.id }) { profile = saved }
            // Stays open: the error is the reason to still be here. The
            // firewall itself is saved either way, so a typo can be fixed
            // here and saved again.
            if let problem = AuthenticationProblem(error, username: p.username) {
                authProblem = problem
                message = nil
            } else {
                message = error.localizedDescription
                messageHealth = .bad
            }
        }
    }
}

private extension ServerEditView {
    var credentialProtectionRequired: Bool {
        let enabled = BiometricAuth.isEnabled
        let available = enabled && BiometricAuth.canUseBiometrics()
        return CredentialProtectionPolicy.requiresAuthorization(
            isEnabled: enabled,
            canUseBiometrics: available
        )
    }

    func revealPassword() {
        if password.isEmpty, isExisting, Keychain.hasPassword(for: profile.id) {
            guard let stored = Keychain.password(for: profile.id) else {
                message = "The password is unavailable while the device is locked."
                messageHealth = .bad
                return
            }
            password = stored
            revealedPassword = stored
        }
        showKey = true
        message = nil
        showOpenSettingsButton = false
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

/// The certificate this firewall presented, and what Vaktpost will do about
/// it. Its own view because `ServerEditView` is at the limit its type body
/// is allowed, and this is the part of that form which depends on nothing
/// the rest of it edits.
private struct CertificateSlab: View {
    @Environment(\.themeManager) private var theme: ThemeManager

    let profile: ServerProfile
    @Binding var pendingFingerprint: String?
    @Binding var showRepinConfirmation: Bool

    var body: some View {
        let observation = profile.certificateObservation
        let pinMatches = observation?.matches(pin: profile.pinnedFingerprint) == true
        let changed = observation != nil && !profile.pinnedFingerprint.isEmpty && !pinMatches
        let health: Health = changed ? .bad
            : observation?.expiryState().health ?? (profile.pinnedFingerprint.isEmpty ? .warn : .idle)

        return Slab(rail: health, title: "Certificate") {
            VStack(alignment: .leading, spacing: 10) {
                FieldRow(key: "Host", value: profile.host)
                if let observation {
                    FieldRow(key: "Subject", value: observation.subject, mono: false)
                    if let issuer = observation.issuer {
                        FieldRow(key: "Issuer", value: issuer, mono: false)
                    }
                    if let validFrom = observation.validFrom {
                        HStack {
                            Text("VALID FROM").scaledFont(9, weight: .semibold)
                                .foregroundStyle(theme.labelFaint)
                            Spacer()
                            Text(validFrom, style: .date).scaledFont(12)
                                .foregroundStyle(theme.label)
                        }
                    }
                    if let validUntil = observation.validUntil {
                        HStack {
                            Text("VALID UNTIL").scaledFont(9, weight: .semibold)
                                .foregroundStyle(theme.labelFaint)
                            Spacer()
                            Text(validUntil, style: .date).scaledFont(12)
                                .foregroundStyle(observation.expiryState().health.color(theme))
                        }
                    }
                    FieldRow(key: "SHA-256", value: observation.fingerprint)
                    FieldRow(key: "Trust", value: changed ? "certificate changed — blocked"
                             : pinMatches ? "pinned and matched"
                             : observation.systemTrusted ? "system trusted, not pinned"
                             : "presented, awaiting explicit pin", mono: false)

                    if changed {
                        Text("The firewall presented a different certificate. Vaktpost rejected the connection and will not trust it automatically.")
                            .scaledFont(12)
                            .foregroundStyle(theme.bad)
                        Button("Review and replace pin") {
                            pendingFingerprint = observation.fingerprint
                            showRepinConfirmation = true
                        }
                        .scaledFont(13, weight: .semibold)
                        .foregroundStyle(theme.warn)
                    }
                } else {
                    Text("Connect to observe the active certificate. Self-signed certificates must be explicitly pinned on first use.")
                        .scaledFont(12)
                        .foregroundStyle(theme.labelMuted)
                    if !profile.pinnedFingerprint.isEmpty {
                        FieldRow(key: "Pinned SHA-256", value: profile.pinnedFingerprint)
                    }
                }
            }
        }
    }
}
