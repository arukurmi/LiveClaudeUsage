import Foundation

/// Poll cadence: the configured interval while healthy, doubling per
/// consecutive failure (rate limits, offline) up to a 10-minute ceiling
/// so we never hammer the endpoint.
public enum PollBackoff {
    public static let maxDelay: TimeInterval = 600

    public static func delay(interval: TimeInterval, consecutiveFailures: Int) -> TimeInterval {
        guard consecutiveFailures > 0 else { return interval }
        // Clamp the exponent so absurd failure counts can't overflow Double.
        let exponent = Double(min(consecutiveFailures, 16))
        return min(interval * pow(2, exponent), maxDelay)
    }

    /// Backoff delay with decorrelating jitter applied. Many clients that woke,
    /// slept, or hit a rate limit at the same moment would otherwise retry in
    /// lockstep and keep colliding; spreading each retry across ±25% breaks the
    /// synchronization. Healthy polling (no failures) is left exact so the
    /// steady-state cadence stays predictable.
    public static func jitteredDelay(interval: TimeInterval,
                                     consecutiveFailures: Int,
                                     random: (ClosedRange<Double>) -> Double = { Double.random(in: $0) }
    ) -> TimeInterval {
        let base = delay(interval: interval, consecutiveFailures: consecutiveFailures)
        guard consecutiveFailures > 0 else { return base }
        let jittered = base * random(0.75...1.25)
        return min(max(jittered, interval), maxDelay)
    }
}
