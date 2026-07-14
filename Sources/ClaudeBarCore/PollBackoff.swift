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
}
