import Foundation
import ClaudeBarCore

func runPollBackoffTests() {
    print("- PollBackoff")

    expectEqual(PollBackoff.delay(interval: 60, consecutiveFailures: 0), 60,
                "healthy polling keeps the configured interval")
    expectEqual(PollBackoff.delay(interval: 60, consecutiveFailures: 1), 120,
                "first failure doubles the interval")
    expectEqual(PollBackoff.delay(interval: 60, consecutiveFailures: 2), 240,
                "second failure doubles again")
    expectEqual(PollBackoff.delay(interval: 60, consecutiveFailures: 10), 600,
                "backoff caps at 10 minutes")
    expectEqual(PollBackoff.delay(interval: 60, consecutiveFailures: 1000), 600,
                "huge failure counts don't overflow past the cap")
    expectEqual(PollBackoff.delay(interval: 5, consecutiveFailures: 3), 40,
                "cap only kicks in when the delay actually exceeds it")

    // Healthy polling stays exact — jitter only spreads retries after a failure.
    expectEqual(PollBackoff.jitteredDelay(interval: 60, consecutiveFailures: 0), 60,
                "no jitter while healthy")
    // Full-swing jitter stays within ±25% of the base delay and never below the
    // configured interval nor above the cap.
    let low = PollBackoff.jitteredDelay(interval: 60, consecutiveFailures: 1) { $0.lowerBound }
    let high = PollBackoff.jitteredDelay(interval: 60, consecutiveFailures: 1) { $0.upperBound }
    expectEqual(low, 90, "lower jitter bound is 75% of the 120s base")
    expectEqual(high, 150, "upper jitter bound is 125% of the 120s base")
    let jitteredCap = PollBackoff.jitteredDelay(interval: 60, consecutiveFailures: 20) { $0.upperBound }
    expectEqual(jitteredCap, PollBackoff.maxDelay, "jitter never pushes past the cap")
    let jitteredFloor = PollBackoff.jitteredDelay(interval: 60, consecutiveFailures: 1) { _ in 0.1 }
    expect(jitteredFloor >= 60, "jitter never dips below the configured interval")
}
