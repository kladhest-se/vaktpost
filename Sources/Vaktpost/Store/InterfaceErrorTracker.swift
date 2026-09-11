import Foundation

/// Whether an interface's error counters are moving.
///
/// `get_interface_info` returns `inerrs`, `outerrs` and `collisions` as totals
/// since the NIC came up, and the app has been showing them as such. A total
/// is almost never the question: twelve errors on a link that has been up for
/// two hundred days is noise, and twelve in the last minute is a cable about
/// to fail. They read identically.
///
/// So this keeps the previous reading and reports the difference. Everything
/// it is careful about follows from one fact — these counters are not
/// guaranteed to only go up.
struct InterfaceErrorTracker {

    struct Reading: Equatable {
        var inErrors: Double
        var outErrors: Double
        var collisions: Double
        var at: Date

        var total: Double { inErrors + outErrors + collisions }
    }

    struct Change: Equatable {
        /// New errors since the previous reading. Never negative.
        var inErrors: Double
        var outErrors: Double
        var collisions: Double
        /// How long that took.
        var interval: TimeInterval
        /// The counters went backwards, so the interface or the firewall
        /// restarted between readings and the difference is meaningless.
        var counterReset: Bool

        var total: Double { inErrors + outErrors + collisions }
        var isRising: Bool { !counterReset && total > 0 }

        /// New errors a minute, for a reading that spans enough time to mean
        /// anything.
        ///
        /// Nil under ten seconds. Two errors across a two-second poll is
        /// "sixty a minute", which is a projection rather than a measurement
        /// and reads as far more alarming than what was seen.
        var perMinute: Double? {
            guard !counterReset, interval >= 10 else { return nil }
            return total / interval * 60
        }
    }

    private var readings: [String: Reading] = [:]
    private(set) var changes: [String: Change] = [:]

    /// Fold in a refresh.
    ///
    /// Keyed by the interface's device name rather than its description: a
    /// description can be edited on the firewall, and renaming an interface
    /// should not look like a counter reset.
    mutating func record(_ interfaces: [InterfaceStat], at now: Date = Date()) {
        for iface in interfaces {
            guard let inErrors = iface.inErrors,
                  let outErrors = iface.outErrors else { continue }
            let collisions = iface.collisions ?? 0
            let reading = Reading(inErrors: inErrors, outErrors: outErrors,
                                  collisions: collisions, at: now)
            let key = iface.device

            defer { readings[key] = reading }

            guard let previous = readings[key] else {
                // First sight of this interface. There is no change to report
                // and inventing one from the total since boot would flag every
                // interface on the first refresh after launch.
                continue
            }

            let interval = now.timeIntervalSince(previous.at)
            guard interval > 0 else { continue }

            // Counters go backwards on a reboot, an interface bounce, or a
            // driver reload. A negative difference is not negative errors, and
            // subtracting anyway would produce a large positive number on the
            // next reading when the baseline is wrong.
            let wentBackwards = inErrors < previous.inErrors
                || outErrors < previous.outErrors
                || collisions < previous.collisions

            changes[key] = Change(
                inErrors: wentBackwards ? 0 : inErrors - previous.inErrors,
                outErrors: wentBackwards ? 0 : outErrors - previous.outErrors,
                collisions: wentBackwards ? 0 : collisions - previous.collisions,
                interval: interval,
                counterReset: wentBackwards
            )
        }
    }

    func change(for iface: InterfaceStat) -> Change? { changes[iface.device] }

    /// Interfaces whose errors went up since the previous refresh.
    func rising(among interfaces: [InterfaceStat]) -> [InterfaceStat] {
        interfaces.filter { changes[$0.device]?.isRising == true }
    }

    /// Forget everything. A different firewall's counters are not a
    /// continuation of this one's.
    mutating func reset() {
        readings = [:]
        changes = [:]
    }
}
