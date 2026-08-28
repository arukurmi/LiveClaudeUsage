import Foundation

/// One rate limit the account is subject to, as reported by the usage
/// endpoint. The set is server-driven rather than hardcoded: a session limit
/// and an all-models weekly limit today, model-specific ones when the account
/// has them.
public struct UsageLimit: Codable, Equatable {
    public let kind: String
    public let percent: Double
    public let resetsAt: Date?

    public init(kind: String, percent: Double, resetsAt: Date?) {
        self.kind = kind
        self.percent = percent
        self.resetsAt = resetsAt
    }
}

public struct UsageSnapshot: Equatable {
    public let percent: Double
    public let resetsAt: Date?
    public init(percent: Double, resetsAt: Date?) {
        self.percent = percent
        self.resetsAt = resetsAt
    }
}

public enum ResetTimeFormatter {
    /// Short local-time string that fits a rotated label inside the bar, e.g. "4:30PM".
    public static func string(from date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mma"
        return formatter.string(from: date)
    }
}
