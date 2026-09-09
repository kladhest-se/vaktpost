import Foundation

enum IncidentSeverity: String, CaseIterable, Identifiable {
    case attention = "Attention"
    case warning = "Warning"
    case information = "Information"

    var id: String { rawValue }
    var rank: Int {
        switch self {
        case .attention: return 2
        case .warning: return 1
        case .information: return 0
        }
    }
}

enum IncidentAnalysis {
    static func severity(action: String?, text: String) -> IncidentSeverity {
        let normalizedAction = action?.lowercased()
        if normalizedAction == "block" || normalizedAction == "reject" {
            return .attention
        }

        let words = Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        let attention = ["critical", "denied", "error", "failed", "failure", "fatal", "panic"]
        if attention.contains(where: words.contains) { return .attention }

        let warning = ["decline", "declined", "disconnected", "down", "expired", "refused",
                       "stopped", "timeout", "unreachable", "warn", "warning"]
        if warning.contains(where: words.contains) { return .warning }
        return .information
    }

    static func date(from value: String?, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard let value else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let seconds = Double(text), seconds > 100_000_000 {
            return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1_000 : seconds)
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = iso.date(from: text) { return parsed }
        iso.formatOptions = [.withInternetDateTime]
        if let parsed = iso.date(from: text) { return parsed }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy/MM/dd HH:mm:ss", "MMM d yyyy HH:mm:ss"] {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: text) { return parsed }
        }

        formatter.dateFormat = "MMM d HH:mm:ss"
        guard let partial = formatter.date(from: text) else { return nil }
        let parts = calendar.dateComponents([.month, .day, .hour, .minute, .second], from: partial)
        var combined = parts
        combined.year = calendar.component(.year, from: now)
        guard var parsed = calendar.date(from: combined) else { return nil }
        if parsed > now.addingTimeInterval(86_400),
           let previousYear = calendar.date(byAdding: .year, value: -1, to: parsed) {
            parsed = previousYear
        }
        return parsed
    }
}
