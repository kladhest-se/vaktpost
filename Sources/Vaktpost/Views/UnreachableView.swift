import SwiftUI

/// Shown in place of the tabs when the firewall is not answering.
///
/// Five tabs of empty cards is a worse answer than one sentence: each screen
/// would explain its own emptiness separately, and none of them would say the
/// thing they have in common. Hiding them also stops somebody pulling to
/// refresh on five screens in turn to find out the same fact.
///
/// The toolbar stays, so switching firewalls or correcting this one's address
/// is still one tap away — those are the two things worth doing from here, and
/// both live up there.
struct UnreachableView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    @Environment(\.serverRegistry) private var registry: ServerRegistry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Slab(rail: .bad) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                .scaledFont(16)
                                .foregroundStyle(theme.bad)
                            Text(registry.active?.displayName ?? "The firewall")
                                .scaledFont(17, weight: .semibold)
                                .foregroundStyle(theme.label)
                        }

                        Text("Not answering.")
                            .scaledFont(14)
                            .foregroundStyle(theme.labelMuted)

                        if let error = store.connectionError {
                            // The firewall's own words, not a paraphrase. A
                            // refused certificate, a wrong password and an
                            // unreachable address need different things doing
                            // about them, and only this text distinguishes
                            // them.
                            Text(error)
                                .scaledFont(12, design: .monospaced)
                                .foregroundStyle(theme.warn)
                                .textSelection(.enabled)
                        }

                        if let address = registry.active?.baseURL, !address.isEmpty {
                            Text(address)
                                .scaledFont(11, design: .monospaced)
                                .foregroundStyle(theme.labelFaint)
                                .textSelection(.enabled)
                        }
                    }
                }

                Button {
                    Task { await store.refreshManually() }
                } label: {
                    HStack(spacing: 8) {
                        if store.isRefreshing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(store.isRefreshing ? "Trying…" : "Try again")
                            .scaledFont(14, weight: .semibold)
                        Spacer()
                    }
                    .foregroundStyle(theme.accentColor)
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(theme.card, in: RoundedRectangle(cornerRadius: 12,
                                                                 style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(store.isRefreshing)

                // What to check, in the order that resolves it quickest.
                Slab(rail: .idle, title: "Worth checking") {
                    VStack(alignment: .leading, spacing: 6) {
                        hint("Whether this phone is on a network that can reach the firewall — a mobile connection usually cannot.")
                        hint("That the address and port are right, in the firewall's settings.")
                        hint("That the account still holds the System - HA node sync privilege.")
                        if registry.active?.pinnedFingerprint.isEmpty == false {
                            // Only when pinning is on: it is a common cause,
                            // and mentioning it otherwise sends people to look
                            // at something they have not enabled.
                            hint("Whether the certificate was renewed. This firewall is pinned, so a new one is refused until it is pinned again.")
                        }
                    }
                }

                if registry.servers.count > 1 {
                    Text("Another firewall can be chosen from the menu in the top left.")
                        .scaledFont(11)
                        .foregroundStyle(theme.labelFaint)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .readableWidth()
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("Not connected")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func hint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .scaledFont(12)
                .foregroundStyle(theme.labelFaint)
            Text(text)
                .scaledFont(12)
                .foregroundStyle(theme.labelMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
