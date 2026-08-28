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

    /// Name to show for this limit. Unknown kinds are humanized rather than
    /// dropped, so a limit we have never seen still reads as something.
    public var title: String {
        switch kind {
        case "session": return "Current session"
        case "weekly_all": return "All models"
        case "weekly_opus": return "Opus"
        case "weekly_sonnet": return "Sonnet"
        default:
            let words = kind.split(separator: "_").map(String.init)
            guard let first = words.first else { return kind }
            return ([first.capitalized] + words.dropFirst()).joined(separator: " ")
        }
    }
}

public struct UsageSnapshot: Codable, Equatable {
    /// The session (5-hour) figure — the headline number, kept separate so
    /// callers never have to depend on the ordering of `limits`.
    public let percent: Double
    public let resetsAt: Date?
    public let limits: [UsageLimit]

    public init(percent: Double, resetsAt: Date?, limits: [UsageLimit] = []) {
        self.percent = percent
        self.resetsAt = resetsAt
        self.limits = limits
    }
}

public enum ResetLabel {
    /// The reset moment as a person would say it: relative while it is close
    /// enough to plan around ("Resets in 51 min"), absolute once it is not
    /// ("Resets Thu 12:00 AM"). Session limits land in the first form and
    /// weekly limits in the second, without either having to ask for it.
    public static func string(for date: Date,
                              now: Date = Date(),
                              timeZone: TimeZone = .current,
                              locale: Locale = Locale(identifier: "en_US_POSIX")) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds <= 0 { return "Resetting now" }
        if seconds < 60 { return "Resets in under a min" }

        let totalMinutes = Int(seconds / 60)
        if totalMinutes < 60 { return "Resets in \(totalMinutes) min" }

        if seconds < 24 * 3600 {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            return minutes == 0
                ? "Resets in \(hours) hr"
                : "Resets in \(hours) hr \(minutes) min"
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE h:mm a"
        return "Resets \(formatter.string(from: date))"
    }
}
