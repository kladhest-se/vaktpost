import SwiftUI

/// ACME certificates.
///
/// Separate from the Certificates screen because they answer different
/// questions. That one says when a certificate expires; this one says whether
/// anything is going to renew it. A Let's Encrypt certificate with 40 days left
/// is fine if renewal is configured and a problem if it is not, and looking at
/// the certificate alone cannot tell you which.
///
/// So each entry is joined against the certificate store by name, and shows
/// both: the automation and what it produced.
struct ACMEView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore

    @State private var query = ""

    private var certificates: [ACMECertificate] {
        guard !query.isEmpty else { return store.acmeCertificates }
        let q = query.lowercased()
        return store.acmeCertificates.filter {
            $0.name.lowercased().contains(q)
                || ($0.descr ?? "").lowercased().contains(q)
                || $0.domains.contains { $0.lowercased().contains(q) }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                    FreshnessView(sections: [.acme], showNames: true)
                if let err = store.errors[.acme] {
                    Notice(symbol: "exclamationmark.triangle",
                           title: "ACME unavailable", detail: err, health: .warn)
                } else if !store.acmeInstalled {
                    Notice(symbol: "square.stack.3d.up.slash",
                           title: "The ACME package is not installed")
                } else if store.acmeCertificates.isEmpty {
                    Notice(symbol: "lock.doc", title: "No ACME certificates configured")
                } else {
                    summary
                    ForEach(certificates) { cert in
                        ACMERow(cert: cert, issued: store.issuedCertificate(for: cert))
                    }
                    if certificates.isEmpty {
                        Notice(symbol: "magnifyingglass", title: "No matches")
                    }
                    if !store.acmeAccounts.isEmpty {
                        GroupHeading(text: "Account keys")
                        ForEach(store.acmeAccounts) { account in
                            Slab(rail: account.isStaging ? .warn : .ok) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(account.descr ?? account.name)
                                            .scaledFont(14, weight: .semibold)
                                            .foregroundStyle(theme.label)
                                        Spacer()
                                        if account.isStaging {
                                            StatusPill(text: "staging", health: .warn)
                                        }
                                    }
                                    if account.isStaging {
                                        // Worth saying plainly: a staging
                                        // certificate is not trusted by any
                                        // browser, and the failure looks like
                                        // a certificate error rather than a
                                        // configuration one.
                                        Text("Certificates from this account are not trusted by browsers.")
                                            .scaledFont(11)
                                            .foregroundStyle(theme.labelFaint)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
            .readableWidth()
        }
        .refreshable { await store.refreshManually() }
        .background(theme.bg.ignoresSafeArea())
        .task(id: store.activeProfile?.id) { await store.loadACME() }
        .searchable(text: $query, prompt: "Certificate or domain")
        .navigationTitle("ACME Certificates")
    }

    private var summary: some View {
        let stalled = store.stalledACME
        return Slab(rail: stalled.isEmpty ? .ok : .warn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(stalled.isEmpty
                     ? "All \(store.acmeCertificates.count) set to renew"
                     : "\(stalled.count) of \(store.acmeCertificates.count) will not renew")
                    .scaledFont(14, weight: .semibold)
                    .foregroundStyle(theme.label)
                Text(stalled.isEmpty
                     ? "Expiry dates come from the certificate store, renewal from the package."
                     : "These will expire and nothing on the firewall will act on it.")
                    .scaledFont(11)
                    .foregroundStyle(theme.labelFaint)
            }
        }
    }
}

struct ACMERow: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    let cert: ACMECertificate
    /// The certificate this entry produced, if one can be matched by name.
    let issued: CertificateInfo?

    var body: some View {
        Slab(rail: worstHealth, trailing: cert.account) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(cert.descr ?? cert.name)
                        .scaledFont(14, weight: .semibold)
                        .foregroundStyle(theme.label)
                    Spacer(minLength: 8)
                    if let issued {
                        StatusPill(text: issued.expiryDescription, health: issued.health)
                    } else {
                        StatusPill(text: "not issued yet", health: .idle)
                    }
                }

                Text(cert.renewalDescription)
                    .scaledFont(11, design: .monospaced)
                    .foregroundStyle(cert.enabled ? theme.labelMuted : theme.warn)

                if !cert.domains.isEmpty {
                    Hairline()
                    ForEach(cert.domains, id: \.self) { domain in
                        Text(domain)
                            .scaledFont(12, design: .monospaced)
                            .foregroundStyle(theme.labelFaint)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    /// The worse of the two conditions, since either is worth acting on and a
    /// green rail beside a red pill would read as fine.
    private var worstHealth: Health {
        let renewal = cert.health
        guard let issued else { return renewal }
        return [renewal, issued.health].contains(.bad) ? .bad
            : [renewal, issued.health].contains(.warn) ? .warn : .ok
    }
}
