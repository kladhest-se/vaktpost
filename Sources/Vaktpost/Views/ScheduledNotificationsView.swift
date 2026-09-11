import SwiftUI

/// What iOS is actually holding, read back from it.
///
/// The Settings row reports a count, which says something is scheduled and
/// nothing about whether it is still true. A renewed certificate leaving a
/// stale "expires in 7 days" behind looks exactly like a correct one until the
/// date on it is read, and reconciling is the part of that feature most likely
/// to be quietly wrong: it runs on every refresh, removes by prefix, and there
/// is no other way to see what it did.
///
/// Read back from `UNUserNotificationCenter` rather than from anything this app
/// remembers. A list built from the app's own intentions would agree with
/// itself and tell nobody anything — and iOS silently drops requests past its
/// 64-notification limit, which is exactly the kind of disagreement worth
/// being able to see.
struct ScheduledNotificationsView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    @Environment(\.serverRegistry) private var registry: ServerRegistry

    @State private var pending: [ScheduledNotification]?
    @State private var isReconciling = false

    /// iOS keeps at most this many pending notifications per app and discards
    /// the rest. Five thresholds per certificate reaches it faster than it
    /// sounds: thirteen certificates across two firewalls is already over.
    private let systemLimit = 64

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch pending {
                case nil:
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                case let list? where list.isEmpty:
                    Notice(symbol: "bell.slash",
                           title: "Nothing scheduled",
                           detail: store.expiryNotifier.isEnabled
                               ? "No certificate on a firewall this app has read expires within 30 days."
                               : "Certificate expiry notifications are switched off in Settings.")
                case let list?:
                    if list.count > systemLimit - 8 {
                        Notice(symbol: "exclamationmark.triangle",
                               title: "Close to the system limit",
                               detail: "iOS holds at most \(systemLimit) pending notifications per app and drops the rest without saying so. \(list.count) are scheduled.",
                               health: .warn)
                    }
                    ForEach(groups(list), id: \.name) { group in
                        GroupHeading(text: group.name)
                        ForEach(group.items) { item in
                            row(item)
                        }
                    }
                }

                reconcileButton
                explanation
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("Scheduled")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func row(_ item: ScheduledNotification) -> some View {
        Slab(rail: rail(item), trailing: item.daysBefore.map { "\($0)d before" }) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .scaledFont(13, weight: .semibold)
                    .foregroundStyle(theme.label)
                Text(item.body)
                    .scaledFont(11)
                    .foregroundStyle(theme.labelMuted)
                Text(when(item))
                    .scaledFont(11, design: .monospaced)
                    .foregroundStyle(item.fireAt == nil ? theme.warn : theme.labelFaint)
            }
        }
    }

    private func rail(_ item: ScheduledNotification) -> Health {
        guard let fireAt = item.fireAt else { return .warn }
        return fireAt.timeIntervalSinceNow < 7 * 86_400 ? .warn : .info
    }

    private func when(_ item: ScheduledNotification) -> String {
        guard let fireAt = item.fireAt else {
            // A calendar trigger that will not resolve to a date is the one
            // entry worth chasing, so it says so rather than showing a dash.
            return "no delivery date — this will not fire"
        }
        return "\(Fmt.dateTime(fireAt)) — \(relative(fireAt))"
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Grouped by firewall, because a notification outlives the profile being
    /// the active one and "which box do I log into" is the first question its
    /// arrival raises.
    private func groups(_ list: [ScheduledNotification]) -> [(name: String, items: [ScheduledNotification])] {
        var order: [String] = []
        var byServer: [String: [ScheduledNotification]] = [:]
        for item in list {
            let name = serverName(item.serverID)
            if byServer[name] == nil { order.append(name) }
            byServer[name, default: []].append(item)
        }
        return order.map { (name: $0, items: byServer[$0] ?? []) }
    }

    private func serverName(_ id: String?) -> String {
        guard let id, let uuid = UUID(uuidString: id) else { return "Unknown firewall" }
        // A firewall that has since been removed keeps its notifications until
        // something reconciles them, and there is no name left to show.
        return registry.servers.first { $0.id == uuid }?.displayName ?? "Removed firewall"
    }

    @ViewBuilder
    private var reconcileButton: some View {
        if store.expiryNotifier.isEnabled {
            Button {
                Task {
                    isReconciling = true
                    defer { isReconciling = false }
                    store.scheduleExpiryNotifications()
                    // The reconcile is a detached task; give it a moment to
                    // land before reading back, rather than showing the list
                    // as it was a second ago and looking broken.
                    try? await Task.sleep(for: .seconds(1))
                    await reload()
                }
            } label: {
                HStack(spacing: 6) {
                    if isReconciling { ProgressView().controlSize(.small) }
                    Text(isReconciling ? "Rescheduling…" : "Reschedule from this firewall")
                        .scaledFont(13, weight: .medium)
                }
                .foregroundStyle(theme.accentColor)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .disabled(isReconciling)
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Read back from iOS rather than from anything this app remembers, so what is listed is what will actually be delivered.")

            Text("Rescheduling only touches the firewall this app is currently connected to. Another firewall's notifications are left alone, which is why they are grouped separately — reconciling one must never cancel another's.")

            Text("A certificate renewed since these were scheduled keeps its old dates until the next refresh reconciles them. If a date here disagrees with the Certificates screen, that is the reconcile not having run, and the button above forces it.")
        }
        .scaledFont(12)
        .foregroundStyle(theme.labelMuted)
        .padding(.horizontal, 2)
    }

    private func reload() async {
        await store.expiryNotifier.refreshPermission()
        pending = await store.expiryNotifier.pending()
    }
}
