import SwiftUI

/// What was busiest, hour by hour, for as long as this app was watching.
///
/// The coverage line under each hour is the point of the screen as much as the
/// list is. A record built from captures taken while a screen is open is full
/// of holes, and an hour summarised from three captures reads identically to
/// one summarised from three hundred unless it says so.
struct TopTalkersView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore

    @State private var interface: String?
    @State private var confirmingClear = false

    private var serverID: String { store.profile.id.uuidString }

    private var recorded: [(interface: String, name: String)] {
        store.topTalkers.recordedInterfaces(serverID: serverID)
    }

    private var selected: String? {
        TopTalkerSelection.resolve(
            preferred: interface,
            available: recorded.map(\.interface)
        )
    }

    private var hours: [TalkerHour] {
        guard let selected else { return [] }
        return store.topTalkers.history(serverID: serverID, interface: selected)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let persistenceError = store.topTalkers.persistenceError {
                    Notice(symbol: "exclamationmark.triangle",
                           title: "History storage unavailable",
                           detail: persistenceError)
                }
                if recorded.isEmpty {
                    Notice(symbol: "clock.arrow.circlepath",
                           title: "Nothing recorded yet",
                           detail: "This fills in while a traffic screen is open. Leave one open and the hours will appear here.")
                } else {
                    picker
                    ForEach(hours) { hour in
                        hourSlab(hour)
                    }
                    clearButton
                }
                explanation
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("Top talkers")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var picker: some View {
        Picker("Interface", selection: Binding(
            get: { selected ?? "" },
            set: { interface = $0 }
        )) {
            ForEach(recorded, id: \.interface) { entry in
                Text(entry.name).tag(entry.interface)
            }
        }
        .pickerStyle(.menu)
        .tint(theme.accentColor)
    }

    private func hourSlab(_ hour: TalkerHour) -> some View {
        Slab(rail: .info, title: hourLabel(hour.hour), trailing: hour.interfaceName) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(hour.busiest.prefix(5))) { talker in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(talker.name ?? talker.address)
                                .scaledFont(13, weight: .semibold)
                                .foregroundStyle(theme.label)
                            if talker.name != nil {
                                Text(talker.address)
                                    .scaledFont(10, design: .monospaced)
                                    .foregroundStyle(theme.labelFaint)
                            }
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(Rate.bits(talker.peakIn)) / \(Rate.bits(talker.peakOut))")
                                .scaledFont(11, design: .monospaced)
                                .foregroundStyle(theme.label)
                            Text("peak in / out")
                                .scaledFont(8)
                                .foregroundStyle(theme.labelFaint)
                        }
                    }
                }

                Hairline()
                Text(coverage(hour))
                    .scaledFont(11)
                    .foregroundStyle(theme.labelFaint)
            }
        }
    }

    /// How much of the hour this summary actually rests on.
    ///
    /// Said in captures and span rather than as a percentage. A percentage
    /// would imply the gaps between captures were measured, and they were not
    /// — each capture is one second and everything between them is unobserved.
    private func coverage(_ hour: TalkerHour) -> String {
        let captures = hour.samples == 1 ? "1 capture" : "\(hour.samples) captures"
        guard hour.span >= 60 else {
            return "\(captures), all within a minute of \(clock(hour.firstSample))."
        }
        return "\(captures) between \(clock(hour.firstSample)) and \(clock(hour.lastSample))."
    }

    private func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func hourLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return time }
        if calendar.isDateInYesterday(date) { return "Yesterday \(time)" }
        return "\(date.formatted(date: .abbreviated, time: .omitted)) \(time)"
    }

    private var clearButton: some View {
        Button(role: .destructive) {
            confirmingClear = true
        } label: {
            Text("Clear recorded history")
                .scaledFont(13, weight: .medium)
                .foregroundStyle(theme.bad)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .confirmationDialog("Clear recorded history?",
                            isPresented: $confirmingClear,
                            titleVisibility: .visible) {
            Button("Clear", role: .destructive) { store.topTalkers.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every recorded hour for every firewall is removed. This cannot be undone.")
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The honest limit, stated on the screen rather than only in the
            // source. Somebody who reads this list as a complete history of
            // their network would be wrong in a way that matters.
            Text("This records what the traffic screens saw while they were open. iOS does not let an app poll a firewall in the background, "
                + "so the gaps are hours nothing was watching rather than hours nothing happened.")

            Text("For unattended history, pfSense's own Status > Monitoring keeps interface totals going back years, "
                + "and a package such as ntopng keeps per-host. "
                + "This is not a substitute for either — it is for looking back over the hour you just spent watching.")

            Text("Rates are what each address was doing at the moment of a capture. "
                + "They are not totals transferred, and multiplying them out would give a number this app cannot support.")

            Text("Kept for 7 days, at most \(TopTalkerRecorder.talkersPerHour) addresses an hour.")
        }
        .scaledFont(12)
        .foregroundStyle(theme.labelMuted)
        .padding(.horizontal, 2)
    }
}
