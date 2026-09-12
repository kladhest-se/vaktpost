import Foundation
import Observation

/// What one address did on one interface during one hour.
struct TalkerStat: Codable, Identifiable, Equatable {
    var address: String
    /// The best name the firewall knew at the time. Kept rather than resolved
    /// on display: a device that has since changed address or left the network
    /// would otherwise lose its name retroactively, which is exactly when
    /// somebody is looking at it.
    var name: String?
    var peakIn: Double
    var peakOut: Double
    /// Sum of the sampled rates, for a mean. Not a byte total — these are
    /// instantaneous rates taken at intervals, and multiplying them out into
    /// bytes transferred would be a number this app cannot actually support.
    var totalIn: Double
    var totalOut: Double
    var samples: Int

    var id: String { address }

    var meanIn: Double { samples > 0 ? totalIn / Double(samples) : 0 }
    var meanOut: Double { samples > 0 ? totalOut / Double(samples) : 0 }
    var peak: Double { max(peakIn, peakOut) }

    /// How this stat is keyed while an hour is being folded together.
    ///
    /// Normalised, so two spellings of one address are one talker — and, more
    /// importantly, computed the same way on the way in and on the way back
    /// out. They were not: entries went into the dictionary under the
    /// normalised key and came back out of storage under the raw address, so
    /// every lookup missed, every capture created a second entry for a host
    /// that was already there, and the third capture hit
    /// `Dictionary(uniqueKeysWithValues:)` with two entries of the same
    /// address and trapped. A crash on the third capture of any interface with
    /// anything on it — six seconds at a two-second interval.
    var key: String { ClientAddress.key(address) ?? address }

    /// Fold another record of the same address into this one.
    ///
    /// Only reachable from stored data that predates the keying fix, or from a
    /// file written by a future shape of this type. Merging rather than
    /// discarding means a bad file costs accuracy rather than history.
    func merging(_ other: TalkerStat) -> TalkerStat {
        var out = self
        out.name = name ?? other.name
        out.peakIn = max(peakIn, other.peakIn)
        out.peakOut = max(peakOut, other.peakOut)
        out.totalIn += other.totalIn
        out.totalOut += other.totalOut
        out.samples += other.samples
        return out
    }
}

/// One hour of one interface, and how much of it was actually watched.
///
/// `samples`, `firstSample` and `lastSample` are not decoration. This record
/// is built from captures taken while a traffic screen is open, so an hour in
/// it is almost never a whole hour — and a "busiest device between 2 and 3am"
/// derived from four captures at 2:05 is a different claim from one derived
/// from two hundred captures spread across the hour. The screen says which.
struct TalkerHour: Codable, Identifiable, Equatable {
    /// Firewall this was recorded against.
    var serverID: String
    /// pfSense's internal handle — "lan", "opt3".
    var interface: String
    /// The interface's description at the time, for display.
    var interfaceName: String
    /// Start of the hour, local time.
    var hour: Date
    var firstSample: Date
    var lastSample: Date
    var samples: Int
    var talkers: [TalkerStat]

    var id: String { "\(serverID)|\(interface)|\(hour.timeIntervalSince1970)" }

    /// Seconds between the first and last capture in this hour.
    ///
    /// Deliberately not "seconds observed". Each capture covers one second and
    /// the gaps between them are unobserved, so this is the span the record
    /// speaks about, not the time it actually measured.
    var span: TimeInterval { lastSample.timeIntervalSince(firstSample) }

    var busiest: [TalkerStat] { talkers.sorted { $0.peak > $1.peak } }
}

/// A rolling record of the busiest addresses per interface per hour.
///
/// **This only knows what it was watching.** Captures come from the traffic
/// screens, which run while they are on screen and not otherwise: iOS does not
/// let an app poll a firewall in the background, and a one-second packet
/// capture is not something to ask a firewall for from a background refresh
/// task even if it did. So this answers "what was busiest while I was
/// watching", and the gaps are real gaps rather than quiet periods.
///
/// That is worth being blunt about because the obvious use — coming back in
/// the morning to ask what saturated the line at 3am — is the one thing it
/// cannot do unless the app was open and on that screen at 3am. For unattended
/// history the answer is pfSense's own RRD graphs for totals, or a package
/// like ntopng for per-host, and this is not a substitute for either.
///
/// What it is good for is the case it was built from: leaving a screen open
/// while something is wrong, and being able to look back over the last hour
/// rather than only at the instant on screen.
@MainActor
@Observable
final class TopTalkerRecorder {

    /// How many addresses to keep per hour.
    ///
    /// pfSense returns ten per capture and different tens across an hour, so
    /// this is larger than ten and still bounded. Without a bound, an hour on
    /// a busy VLAN accumulates every address that was ever briefly in the top
    /// ten, and the file grows without limit.
    static let talkersPerHour = 20

    /// How long to keep hours for.
    static let retention: TimeInterval = 7 * 86_400

    /// And how many hours, in total, regardless of age.
    ///
    /// Retention alone is not a bound. Seven days across fifteen interfaces is
    /// 2,520 hourly buckets of up to twenty talkers each, and the whole record
    /// is re-encoded on every save — so the ceiling that matters is the number
    /// of entries, not their age. Oldest go first.
    static let maxHours = 600

    private(set) var hours: [String: TalkerHour] = [:]

    private let store: URL?
    private var saveTask: Task<Void, Never>?

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        store = base?.appendingPathComponent("vaktpost-top-talkers.json")
        load()
    }

    // MARK: Recording

    /// Fold one capture into the record.
    ///
    /// `names` resolves an address to whatever the client list calls it, asked
    /// at record time rather than at display time so a device keeps its name
    /// after it leaves the network.
    func record(_ hosts: [HostTraffic],
                serverID: String,
                interface: String,
                interfaceName: String,
                names: (String) -> String?,
                at when: Date = Date(),
                calendar: Calendar = .current,
                now: Date = Date(),
                skipPrune: Bool = false) {
        guard !hosts.isEmpty else { return }

        let hourStart = calendar.dateInterval(of: .hour, for: when)?.start ?? when
        let key = "\(serverID)|\(interface)|\(hourStart.timeIntervalSince1970)"

        var hour = hours[key] ?? TalkerHour(
            serverID: serverID,
            interface: interface,
            interfaceName: interfaceName,
            hour: hourStart,
            firstSample: when,
            lastSample: when,
            samples: 0,
            talkers: []
        )

        hour.interfaceName = interfaceName
        hour.lastSample = max(hour.lastSample, when)
        hour.firstSample = min(hour.firstSample, when)
        hour.samples += 1

        // `uniquingKeysWith`, never `uniqueKeysWithValues`.
        //
        // The trapping initialiser is a crash waiting on data this app does
        // not control — here, its own stored file. Merging cannot crash, and
        // a duplicate in a file written by an older build costs accuracy
        // rather than the app.
        var byAddress = Dictionary(hour.talkers.map { ($0.key, $0) },
                                   uniquingKeysWith: { $0.merging($1) })

        for host in hosts {
            // The same key the stored entries were rebuilt under. These two
            // computing it differently is the whole of the bug above.
            let address = ClientAddress.key(host.ip) ?? host.ip
            var stat = byAddress[address] ?? TalkerStat(
                address: host.ip, name: nil, peakIn: 0, peakOut: 0,
                totalIn: 0, totalOut: 0, samples: 0
            )
            stat.name = names(host.ip) ?? stat.name
            stat.peakIn = max(stat.peakIn, host.bandwidthIn)
            stat.peakOut = max(stat.peakOut, host.bandwidthOut)
            stat.totalIn += host.bandwidthIn
            stat.totalOut += host.bandwidthOut
            stat.samples += 1
            byAddress[address] = stat
        }

        // Keep the busiest, by peak. An address that was briefly loud is more
        // interesting in this record than one that was quietly present, which
        // is the opposite of how a mean would rank them.
        hour.talkers = Array(byAddress.values.sorted { $0.peak > $1.peak }
            .prefix(Self.talkersPerHour))

        hours[key] = hour
        if !skipPrune {
            prune(now: now)
        }
        scheduleSave()
    }

    // MARK: Reading

    /// Hours for one interface, newest first.
    func history(serverID: String, interface: String) -> [TalkerHour] {
        hours.values
            .filter { $0.serverID == serverID && $0.interface == interface }
            .sorted { $0.hour > $1.hour }
    }

    /// Which interfaces this firewall has any record for.
    func recordedInterfaces(serverID: String) -> [(interface: String, name: String)] {
        var seen: [String: String] = [:]
        for hour in hours.values where hour.serverID == serverID {
            seen[hour.interface] = hour.interfaceName
        }
        return seen.map { (interface: $0.key, name: $0.value) }
            .sorted { $0.name < $1.name }
    }

    func isEmpty(serverID: String) -> Bool {
        !hours.values.contains { $0.serverID == serverID }
    }

    // MARK: Housekeeping

    func prune(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Self.retention)
        hours = hours.filter { $0.value.hour >= cutoff }

        guard hours.count > Self.maxHours else { return }
        let keep = hours.values
            .sorted { $0.hour > $1.hour }
            .prefix(Self.maxHours)
            .map(\.id)
        let keepSet = Set(keep)
        hours = hours.filter { keepSet.contains($0.value.id) }
    }

    /// Forget everything. Offered on the screen, because a record of which
    /// devices were busy and when is the most personal thing this app keeps.
    func clear() {
        hours = [:]
        scheduleSave()
    }

    // MARK: Persistence

    private func load() {
        guard let store, let data = try? Data(contentsOf: store) else { return }
        guard let decoded = try? JSONDecoder().decode([String: TalkerHour].self, from: data) else {
            // A file this app cannot read is a file from an older shape of
            // this type. Losing a week of it is better than refusing to record
            // anything until somebody deletes it by hand.
            return
        }
        hours = decoded
    }

    /// Debounced, because recording happens on every capture and a capture can
    /// be every two seconds. Writing the whole file that often would be the
    /// most expensive thing on the screen.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// Encode and write away from the main actor.
    ///
    /// This was doing both on the main actor every five seconds while a
    /// capture loop was running. The record is a dictionary of value types, so
    /// a copy can be handed to a detached task and encoded there — and the one
    /// moment this cost the most was the one where the app is drawing a live
    /// trace, which is the worst possible time to stall the main thread.
    func save() {
        guard let store else { return }
        let snapshot = hours
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? FileManager.default.createDirectory(
                at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: store, options: .atomic)
        }
    }

    /// Encode and write here and now, for a test that needs the file on disk
    /// before it reads it back.
    func saveSynchronously() {
        guard let store else { return }
        guard let data = try? JSONEncoder().encode(hours) else { return }
        try? FileManager.default.createDirectory(
            at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: store, options: .atomic)
    }
}
