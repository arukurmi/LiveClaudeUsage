import Foundation

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
