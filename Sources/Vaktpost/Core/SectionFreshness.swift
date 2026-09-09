import Foundation

struct SectionFreshness: Equatable {
    var lastSuccess: Date?
    var lastAttempt: Date?
    var failure: String?
    var requestID: UUID?

    mutating func begin(_ id: UUID, at date: Date) {
        requestID = id
        lastAttempt = date
    }

    mutating func succeed(_ id: UUID, at date: Date) {
        guard requestID == id else { return }
        lastSuccess = date
        failure = nil
        requestID = nil
    }

    mutating func fail(_ id: UUID, message: String?) {
        guard requestID == id else { return }
        if let message { failure = message }
        requestID = nil
    }

    func isStale(at date: Date, interval: TimeInterval) -> Bool {
        guard let lastSuccess else { return true }
        return failure != nil || date.timeIntervalSince(lastSuccess) > max(60, interval * 2)
    }
}
