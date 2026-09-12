import SwiftUI

/// Protected administrative history for the active firewall only.
struct AuditTrailView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore

    @State private var showClearConfirmation = false
    @State private var localError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summary

                if let error = store.auditTrail.persistenceError ?? localError {
                    Notice(
                        symbol: "lock.trianglebadge.exclamationmark",
                        title: "Protected history unavailable",
                        detail: error,
                        health: .bad
                    )
                }

                GroupHeading(text: "Retention")
                retention

                if store.auditTrail.entries.isEmpty {
                    Notice(
                        symbol: "checkmark.shield",
                        title: "No administrative attempts recorded",
                        detail: "Monitor-only activity is not part of this trail."
                    )
                } else {
                    GroupHeading(text: "Operations")
                    ForEach(Array(store.auditTrail.entries.reversed())) { entry in
                        entryCard(entry)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .readableWidth()
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("Administrative history")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                ShareLink(
                    item: store.auditTrail.redactedExport(),
                    preview: SharePreview("Redacted Vaktpost administrative history")
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(store.auditTrail.entries.isEmpty)

                Button(role: .destructive) {
                    showClearConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(store.auditTrail.entries.isEmpty)
            }
        }
        .confirmationDialog("Clear this firewall's administrative history?",
                            isPresented: $showClearConfirmation,
                            titleVisibility: .visible) {
            Button("Clear history", role: .destructive) { clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the encrypted local records for the active firewall. It does not change pfSense configuration history.")
        }
    }

    private var summary: some View {
        Slab(rail: store.auditTrail.persistenceError == nil ? .info : .bad,
             title: store.profile.displayName) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(store.auditTrail.entries.count) protected operation record\(store.auditTrail.entries.count == 1 ? "" : "s")")
                    .scaledFont(14, weight: .semibold)
                    .foregroundStyle(theme.label)
                Text("A pending record is encrypted before a change is sent. Completion records whether the intended state was verified, differed, or could not be determined.")
                    .scaledFont(12)
                    .foregroundStyle(theme.labelMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var retention: some View {
        Slab(rail: .idle) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Keep records", selection: Binding(
                    get: { store.auditTrail.retentionLimit },
                    set: { updateRetention($0) }
                )) {
                    ForEach(AuditTrail.retentionOptions, id: \.self) { count in
                        Text("Latest \(count)").tag(count)
                    }
                }
                Text("The limit applies separately to each firewall. Redacted exports omit firewall names, targets and preview text.")
                    .scaledFont(11)
                    .foregroundStyle(theme.labelFaint)
            }
        }
    }

    private func entryCard(_ entry: AuditTrail.Entry) -> some View {
        Slab(rail: health(for: entry.verification)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.summary)
                        .scaledFont(13, weight: .semibold)
                        .foregroundStyle(theme.label)
                    Spacer(minLength: 8)
                    StatusPill(text: statusText(entry.verification),
                               health: health(for: entry.verification))
                }

                Text(entry.preview)
                    .scaledFont(11)
                    .foregroundStyle(theme.labelMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = entry.verificationDetail {
                    Text(detail)
                        .scaledFont(11)
                        .foregroundStyle(theme.labelMuted)
                }

                Hairline()
                HStack {
                    Text(entry.timestamp, style: .date)
                    Text(entry.timestamp, style: .time)
                    Spacer()
                    Text(String(entry.id.uuidString.prefix(8)).lowercased())
                }
                .scaledFont(10, design: .monospaced)
                .foregroundStyle(theme.labelFaint)
            }
        }
    }

    private func health(for verification: AuditVerification) -> Health {
        switch verification {
        case .verified, .readBack: return .ok
        case .pending, .unavailable: return .warn
        case .mismatch, .outcomeUnknown: return .bad
        }
    }

    private func statusText(_ verification: AuditVerification) -> String {
        switch verification {
        case .pending: return "pending"
        case .verified: return "verified"
        case .readBack: return "read back"
        case .mismatch: return "mismatch"
        case .unavailable: return "unverified"
        case .outcomeUnknown: return "unknown"
        }
    }

    private func updateRetention(_ value: Int) {
        do {
            try store.auditTrail.setRetentionLimit(value)
            localError = nil
        } catch {
            localError = error.localizedDescription
        }
    }

    private func clear() {
        do {
            try store.auditTrail.clear()
            localError = nil
        } catch {
            localError = error.localizedDescription
        }
    }
}
