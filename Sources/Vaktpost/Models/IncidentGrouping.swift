import Foundation

/// What a group of events was clustered by. One case today — grouping by
/// rule tracker, or correlating across sources entirely, are real ideas
/// left for later rather than built speculatively now.
enum GroupKey: Hashable {
    case sourceAddress(String)
}

/// One or more `IncidentEvent`s folded together because they came from the
/// same source within a short window of each other.
///
/// A `count` of 1 is not a special case at the type level — an event that
/// never clustered with anything is still a group, just one nothing else
/// joined. The view decides whether that's worth showing any differently;
/// this type doesn't need two shapes to say the same thing.
struct IncidentGroup: Identifiable {
    let id: String
    /// Newest first, matching `IncidentTimeline.build`'s own ordering — so
    /// the original log entries stay browsable in the order this list has
    /// always shown them, with nothing about the individual events lost or
    /// reordered by having been grouped.
    let events: [IncidentEvent]
    let groupKey: GroupKey?
    let severity: IncidentSeverity
    let firstSeen: Date?
    let lastSeen: Date?
    /// True if the most recent event in this group is still within the
    /// grouping window of now — the same threshold used to decide whether
    /// events belong together in the first place, rather than a second,
    /// separately-tuned number for "is this still happening".
    let isOngoing: Bool

    var count: Int { events.count }
}

enum IncidentGrouping {
    /// The rolling window in which same-source events are folded together,
    /// and how "isOngoing" is judged against now. 300 seconds: long enough
    /// that a burst of blocks a few seconds apart reads as one thing, short
    /// enough that two unrelated visits from the same address hours apart
    /// don't get folded into a single, misleadingly long-lived incident.
    static let window: TimeInterval = 300

    /// Clusters events into `IncidentGroup`s.
    ///
    /// Only firewall events with a parsed source address are eligible, and
    /// only above `.information` severity — a stream of ordinary `pass`
    /// traffic has no reason to be folded into anything. Everything else
    /// stays a singleton, so the shape of the timeline is unchanged unless
    /// something has actually recurred.
    ///
    /// `events` is taken as given: this does not re-derive severity, source,
    /// or ordering, so whatever scope, source, or search filtering the
    /// caller already applied continues to behave exactly as it does today.
    /// Grouping is a pass over the result of that filtering, not a
    /// replacement for it.
    static func group(_ events: [IncidentEvent], now: Date = Date()) -> [IncidentGroup] {
        // Walked oldest-to-newest so "does this event join an existing
        // cluster" only ever looks backward in time. IncidentTimeline.build
        // hands back newest-first, so this is the reverse of that ordering,
        // not a second, independently-tuned sort.
        let chronological = events.sorted { lhs, rhs in
            switch (lhs.date, rhs.date) {
            case let (l?, r?) where l != r: return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.position < rhs.position
            }
        }

        var clusters: [(source: String, events: [IncidentEvent])] = []
        // The most recent cluster index started for each source. Looking
        // too late does not reuse or overwrite this slot — it starts a new
        // cluster and points here at that instead, so an earlier burst from
        // the same address is never silently dropped in favour of a later,
        // unrelated one.
        var openIndexBySource: [String: Int] = [:]
        var singles: [IncidentEvent] = []

        for event in chronological {
            guard event.severity != .information,
                  let source = event.line.filterFields?.source
            else {
                singles.append(event)
                continue
            }

            if let index = openIndexBySource[source],
               let lastDate = clusters[index].events.last?.date,
               let eventDate = event.date,
               eventDate.timeIntervalSince(lastDate) <= window {
                clusters[index].events.append(event)
            } else {
                clusters.append((source: source, events: [event]))
                openIndexBySource[source] = clusters.count - 1
            }
        }

        var groups = singles.map(single)
        for cluster in clusters {
            if cluster.events.count == 1 {
                groups.append(single(cluster.events[0]))
            } else {
                groups.append(build(members: cluster.events, source: cluster.source, now: now))
            }
        }

        return groups.sorted { lhs, rhs in
            switch (lhs.lastSeen, rhs.lastSeen) {
            case let (l?, r?) where l != r: return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            default: return false
            }
        }
    }

    private static func single(_ event: IncidentEvent) -> IncidentGroup {
        IncidentGroup(
            id: event.id,
            events: [event],
            groupKey: nil,
            severity: event.severity,
            firstSeen: event.date,
            lastSeen: event.date,
            isOngoing: false
        )
    }

    private static func build(members: [IncidentEvent], source: String, now: Date) -> IncidentGroup {
        let severity = members.map(\.severity).max { $0.rank < $1.rank } ?? .information
        let dates = members.compactMap(\.date)
        let last = dates.max()
        let ongoing = last.map { now.timeIntervalSince($0) <= window } ?? false
        return IncidentGroup(
            id: "group-source-\(source)-\(members.first?.id ?? "")",
            events: members.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) },
            groupKey: .sourceAddress(source),
            severity: severity,
            firstSeen: dates.min(),
            lastSeen: last,
            isOngoing: ongoing
        )
    }
}
