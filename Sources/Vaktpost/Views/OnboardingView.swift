import SwiftUI

struct OnboardingView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore

    @State private var profile = ServerProfile()
    @State private var password = ""
    @State private var isTesting = false
    @State private var message: String?
    @State private var messageHealth: Health = .idle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                Slab(rail: .info, title: "Connect") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabelledField(title: "Base URL", text: $profile.baseURL,
                                      placeholder: "https://192.168.1.1",
                                      keyboard: .URL, autocap: false)
                        LabelledField(title: "Username", text: $profile.username,
                                      placeholder: "firewall account", autocap: false)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("PASSWORD")
                                .scaledFont(11, weight: .semibold)
                                .tracking(0.8)
                                .foregroundStyle(theme.labelFaint)
                            SecureField("password", text: $password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .scaledFont(14, design: .monospaced)
                                .padding(10)
                                .background(theme.cardRaised)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }

                        Text("HTTPS is required. If the certificate is not trusted by iOS, Vaktpost will show its "
                            + "SHA-256 fingerprint for explicit review before any credentials are sent.")
                            .scaledFont(12)
                            .foregroundStyle(theme.labelMuted)

                        Button {
                            Task { await connect() }
                        } label: {
                            HStack(spacing: 6) {
                                if isTesting { ProgressView().controlSize(.small) }
                                Text(isTesting ? "Connecting…" : "Connect")
                                    .scaledFont(15, weight: .semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(theme.accentColor)
                            .foregroundStyle(theme.palette.crust)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .disabled(isTesting || profile.baseURL.isEmpty || password.isEmpty)

                        if let message {
                            Text(message)
                                .scaledFont(12)
                                .foregroundStyle(messageHealth.color(theme))
                        }
                    }
                }

                Slab(rail: .idle, title: "Before you start") {
                    VStack(alignment: .leading, spacing: 8) {
                        step("1", "Nothing to install — this uses pfSense's built-in XML-RPC service.")
                        step("2", "Set System → Advanced → Max Processes to 5 or more.")
                        step("3", "Give the account the System - HA node sync privilege, which is administrator-equivalent. Read SECURITY.md first.")
                        step("4", "Use a dedicated account, not your own login. New firewalls start in monitor-only mode; "
                            + "administration must be enabled separately for each firewall after reviewing the risk warning.")
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .background(theme.bg.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                ForEach(0..<5) { i in
                    Capsule()
                        .fill(theme.accentColor.opacity(1.0 - Double(i) * 0.16))
                        .frame(width: 4, height: CGFloat(26 - i * 3))
                }
            }
            Text("Vaktpost")
                .scaledFont(30, weight: .bold, design: .rounded)
                .foregroundStyle(theme.label)
            Text("pfSense monitoring and administration")
                .scaledFont(14)
                .foregroundStyle(theme.labelMuted)
        }
        .padding(.top, 40)
    }

    private func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n)
                .scaledFont(11, weight: .bold, design: .rounded)
                .foregroundStyle(theme.palette.crust)
                .frame(width: 18, height: 18)
                .background(theme.accentColor)
                .clipShape(Circle())
            Text(text)
                .scaledFont(12)
                .foregroundStyle(theme.labelMuted)
        }
    }

    private func connect() async {
        isTesting = true
        defer { isTesting = false }

        var p = profile
        p.normalize()
        guard p.validatedBaseURL != nil else {
            message = "Enter an HTTPS firewall address without a path, query, fragment, or embedded credentials."
            messageHealth = .bad
            return
        }
        switch Keychain.setPassword(password, for: p.id) {
        case .success:
            break
        case .failure(let error):
            message = error.errorDescription ?? "Failed to save the password."
            messageHealth = .bad
            return
        }
        await store.saved(p)
        await store.switchTo(p)
        if let saved = store.registry.servers.first(where: { $0.id == p.id }) {
            p = saved
            profile = saved
        }

        do {
            let version = try await store.client.ping()
            message = "Connected — pfSense \(version)"
            messageHealth = .ok
        } catch {
            message = error.localizedDescription
            messageHealth = .bad
        }
    }
}
