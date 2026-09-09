import SwiftUI

/// Certificates and authorities.
///
/// Its own screen because a firewall doing TLS termination accumulates them —
/// sixteen here, between wildcards, an OpenVPN CA, per-user client certs and
/// the webConfigurator's own — and at the bottom of System they were a list
/// nobody could find anything in.
///
/// Sorted by expiry rather than by name, because the only question anybody
/// opens this screen to answer is which one runs out next.
struct CertificatesView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore

    @State private var query = ""
    @State private var filter: Filter = .certificates

    /// No "All": a certificate is either an authority or an end-entity
    /// certificate, and mixing them was the least useful of the three views —
    /// sixteen rows where the CAs never expire and the leaf certificates are
    /// the ones you came to check.
    enum Filter: String, CaseIterable, Identifiable {
        case authorities = "CAs", certificates = "Certificates", expiring = "Expiring"
        var id: String { rawValue }
    }

    private var certificates: [CertificateInfo] {
        var list = store.certificates
        switch filter {
        // ACME-managed certificates live on their own screen, where the
        // renewal state that matters for them is also shown. Listing them here
        // as well would put every one of them on two screens with less context
        // on this one.
        case .certificates: list = list.filter { !$0.isCA && !$0.isACME }
        case .expiring: list = list.filter { $0.health == .warn || $0.health == .bad }
        case .authorities: list = list.filter(\.isCA)
        }
        if !query.isEmpty {
            let q = query.lowercased()
            list = list.filter { $0.descr.lowercased().contains(q) }
        }
        // Soonest first. A certificate with no date sorts last: it is not
        // urgent, it is unreadable, and mixing the two hides the urgent ones.
        return list.sorted {
            switch ($0.validUntil, $1.validUntil) {
            case let (a?, b?): return a < b
            case (nil, _?): return false
            case (_?, nil): return true
            default: return $0.descr < $1.descr
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    FreshnessView(sections: [.certificates], showNames: true)
                    if let err = store.errors[.certificates] {
                        Notice(symbol: "exclamationmark.triangle",
                               title: "Certificates unavailable", detail: err, health: .warn)
                    } else if store.certificates.isEmpty {
                        Notice(symbol: "lock.doc", title: "No certificates")
                    } else {
                        summary
                        ForEach(certificates) { CertificateRow(cert: $0) }
                        if certificates.isEmpty {
                            Notice(symbol: "magnifyingglass", title: "No matches")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            .readableWidth()
            }
            .refreshable { await store.refreshManually() }
        }
        .background(theme.bg.ignoresSafeArea())
        .searchable(text: $query, prompt: "Certificate name")
        .navigationTitle("System Certificates")
    }

    private var summary: some View {
        let soon = store.certificates.filter {
            !$0.isACME && ($0.health == .warn || $0.health == .bad)
        }
        let next = certificates.first { $0.validUntil != nil }
        return Slab(rail: soon.isEmpty ? .ok : (soon.contains { $0.health == .bad } ? .bad : .warn)) {
            VStack(alignment: .leading, spacing: 4) {
                Text(soon.isEmpty
                     ? "Nothing expiring soon"
                     : "\(soon.count) expiring or expired")
                    .scaledFont(14, weight: .semibold)
                    .foregroundStyle(theme.label)
                if let next {
                    Text("Next: \(next.descr) — \(next.expiryDescription)")
                        .scaledFont(11)
                        .foregroundStyle(theme.labelFaint)
                }
            }
        }
    }
}

struct CertificateRow: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    let cert: CertificateInfo

    var body: some View {
        Slab(rail: cert.health, trailing: cert.isCA ? "CA" : nil) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(cert.descr.isEmpty ? "(unnamed)" : cert.descr)
                        .scaledFont(14, weight: .semibold)
                        .foregroundStyle(theme.label)
                        .textSelection(.enabled)
                    Spacer(minLength: 8)
                    StatusPill(text: cert.expiryDescription, health: cert.health)
                }
                if let until = cert.validUntil {
                    FieldRow(key: "Expires", value: Fmt.date(until), mono: false)
                }
                if let from = cert.validFrom {
                    FieldRow(key: "Issued", value: Fmt.date(from), mono: false)
                }
            }
        }
    }
}
