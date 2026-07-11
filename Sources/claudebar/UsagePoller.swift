import Foundation
import ClaudeBarCore

final class UsagePoller {
    private let interval: TimeInterval
    private let onUpdate: (DisplayState) -> Void
    private let fetcher = UsageFetcher()
    private var timer: Timer?
    private var lastGoodPercent: Double?
    private var lastResetsAt: Date?
    private var consecutiveFailures = 0

    private static let lastGoodKey = "lastGoodPercent"
    private static let lastGoodAtKey = "lastGoodAt"
    private static let lastResetsAtKey = "lastResetsAt"

    init(intervalSeconds: TimeInterval, onUpdate: @escaping (DisplayState) -> Void) {
        self.interval = intervalSeconds
        self.onUpdate = onUpdate
        // Survive restarts: a value from the last hour beats a gray "no data" bar.
        let defaults = UserDefaults.standard
        let savedAt = defaults.double(forKey: Self.lastGoodAtKey)
        if savedAt > 0, Date().timeIntervalSince1970 - savedAt < 3600 {
            lastGoodPercent = defaults.double(forKey: Self.lastGoodKey)
            let savedReset = defaults.double(forKey: Self.lastResetsAtKey)
            // Only a reset time still in the future is worth showing.
            if savedReset > Date().timeIntervalSince1970 {
                lastResetsAt = Date(timeIntervalSince1970: savedReset)
            }
        }
    }

    func start() {
        if let percent = lastGoodPercent {
            onUpdate(.stale(percent: percent, resetsAt: lastResetsAt))
        }
        tick()
    }

    private func tick() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let result = self.fetcher.fetch()
            DispatchQueue.main.async {
                switch result {
                case .success(let snapshot):
                    self.consecutiveFailures = 0
                    self.lastGoodPercent = snapshot.percent
                    self.lastResetsAt = snapshot.resetsAt
                    let defaults = UserDefaults.standard
                    defaults.set(snapshot.percent, forKey: Self.lastGoodKey)
                    defaults.set(Date().timeIntervalSince1970, forKey: Self.lastGoodAtKey)
                    defaults.set(snapshot.resetsAt?.timeIntervalSince1970 ?? 0,
                                 forKey: Self.lastResetsAtKey)
                    self.onUpdate(.usage(percent: snapshot.percent, resetsAt: snapshot.resetsAt))
                case .failure:
                    self.consecutiveFailures += 1
                    if let percent = self.lastGoodPercent {
                        self.onUpdate(.stale(percent: percent, resetsAt: self.lastResetsAt))
                    } else {
                        self.onUpdate(.error)
                    }
                }
                self.scheduleNext()
            }
        }
    }

    /// Normal cadence on success; exponential backoff up to 10 minutes while
    /// failing (rate limits, offline) so we never hammer the endpoint.
    private func scheduleNext() {
        var delay = interval
        if consecutiveFailures > 0 {
            delay = min(interval * pow(2, Double(consecutiveFailures)), 600)
        }
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.tick()
        }
    }
}
