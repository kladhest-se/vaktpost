import SwiftUI

/// Fetches pfSense's own configuration file, exactly as it is on disk, and
/// hands it to the system share sheet — save to Files, AirDrop, email it to
/// yourself, whatever the person already uses for this.
///
/// There is deliberately no restore screen here. See ConfigBackup's own
/// comment for why: pfSense's own web UI already restores a file this
/// screen helped save, and that path is the one worth trusting with a
/// firewall's entire configuration.
struct ConfigBackupView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore

    @State private var isFetching = false
    @State private var backup: ConfigBackup?
    @State private var shareURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: "Configuration Backup", subtitle: "A copy of config.xml, straight from the firewall")

                Notice(
                    symbol: "exclamationmark.shield",
                    title: "Contains real secrets",
                    detail: "This file includes this firewall's own admin password hash, VPN keys, RADIUS "
                        + "secrets and certificate private keys — everything pfSense itself would warn about "
                        + "on an unencrypted backup. Store or send it the way you would any of those on their own.",
                    health: .warn
                )

                fetchButton

                if let errorMessage {
                    Notice(symbol: "exclamationmark.triangle", title: "Backup failed",
                          detail: errorMessage, health: .warn)
                }

                if let backup {
                    Slab(rail: .ok, title: "Ready") {
                        VStack(alignment: .leading, spacing: 8) {
                            FieldRow(key: "Firewall", value: backup.hostname)
                            FieldRow(key: "Size", value: Fmt.bytes(Double(backup.sizeBytes)))
                            FieldRow(key: "Fetched", value: backup.fetchedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                    if let shareURL {
                        ShareLink(
                            item: shareURL,
                            preview: SharePreview("\(backup.hostname) configuration backup")
                        ) {
                            HStack(spacing: 9) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Save or Share")
                            }
                            .foregroundStyle(.white)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(theme.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }

                Text("Read-only. Restoring a saved file back onto this or another firewall "
                    + "is done through pfSense's own web interface, under Diagnostics › Backup & Restore.")
                    .scaledFont(11)
                    .foregroundStyle(theme.labelFaint)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("Configuration Backup")
        .navigationBarTitleDisplayMode(.inline)
        // A backup fetched from one firewall means nothing offered as a
        // share for a different one now active — the file on disk is
        // still this device's own temp file either way, but the card
        // above it should not go on describing the firewall that is no
        // longer selected.
        .onChange(of: store.bindingID) { _, _ in
            backup = nil
            shareURL = nil
            errorMessage = nil
        }
    }

    private var fetchButton: some View {
        Button {
            Task { await fetch() }
        } label: {
            HStack(spacing: 9) {
                if isFetching {
                    ProgressView().controlSize(.small).tint(.white)
                    Text("Fetching…")
                } else {
                    Image(systemName: "arrow.down.doc")
                    Text(backup == nil ? "Fetch Configuration" : "Fetch Again")
                }
            }
            .foregroundStyle(.white)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(theme.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isFetching)
        .opacity(isFetching ? 0.7 : 1)
    }

    private func fetch() async {
        isFetching = true
        errorMessage = nil
        shareURL = nil
        defer { isFetching = false }
        do {
            guard let result = try await store.client.backupConfig() else {
                errorMessage = "The firewall reported that its configuration file could not be read."
                return
            }
            backup = result
            shareURL = try writeTempFile(result)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// A real file with the right name and extension, rather than sharing
    /// raw text — so "Save to Files" or an email attachment keeps the
    /// firewall's own hostname and today's date instead of a generic name.
    /// Lives in this device's own temporary directory; nothing here writes
    /// to or reads from the firewall's filesystem beyond the one snippet
    /// call that already happened.
    private func writeTempFile(_ backup: ConfigBackup) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(backup.suggestedFilename)
        try backup.xml.write(to: url, options: .atomic)
        return url
    }
}
