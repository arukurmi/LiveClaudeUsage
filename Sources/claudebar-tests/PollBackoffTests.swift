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
}
