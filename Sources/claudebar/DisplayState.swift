import ClaudeBarCore

enum DisplayState: Equatable {
    case usage(UsageSnapshot)
    /// Fetch failing, but we have a last known value — show it with the rail
    /// marked as paused rather than blanking out numbers that are still useful.
    case stale(UsageSnapshot)
    case error

    var snapshot: UsageSnapshot? {
        switch self {
        case .usage(let snapshot), .stale(let snapshot): return snapshot
        case .error: return nil
        }
    }

    var isStale: Bool {
        if case .stale = self { return true }
        return false
    }
}
