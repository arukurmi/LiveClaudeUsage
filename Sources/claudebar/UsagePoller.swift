import AppKit
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
    /// Absolute moment before which the server (via Retry-After) asked us not to
    /// poll again. Honored even across wake/unlock refreshes so we never poll
    /// inside a window the server explicitly closed.
    private var rateLimitedUntil: Date?
    private var inFlight = false
    private var watchdog: Timer?
    /// Latest moment by which the next tick should have started; the watchdog
    /// force-restarts polling past this point.
    private var nextTickDeadline = Date.distantFuture

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
        startWatchdog()
        // Ticks that failed while the machine was asleep or the keychain was
        // locked leave the backoff at up to 10 minutes; without these the bar
        // sat stale that long after opening the lid.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshNow()
            }
        }
    }

    /// Forget accumulated backoff and fetch immediately — unless the server
    /// asked us to wait, in which case the pending timer for that window stands.
    private func refreshNow() {
        if let until = rateLimitedUntil, until > Date() { return }
        consecutiveFailures = 0
        timer?.invalidate()
        tick()
    }

    /// The poll loop is a chain of one-shot timers; if any link ever drops
    /// (missed timer, lost fetch completion), polling used to stop until the
    /// app restarted. The watchdog notices a missed deadline and restarts it.
    private func startWatchdog() {
        let watchdog = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            guard let self, Date() > self.nextTickDeadline else { return }
            self.inFlight = false // a completion this overdue is lost, not pending
            self.tick()
        }
        watchdog.tolerance = 5
        RunLoop.main.add(watchdog, forMode: .common)
        self.watchdog = watchdog
    }

    /// Main thread only. Multiple callers (timer, watchdog, wake refresh) may
    /// request a tick; only one fetch runs at a time.
    private func tick() {
        guard !inFlight else { return }
        inFlight = true
        // fetch() is bounded at ~30s; a completion 120s out is lost.
        nextTickDeadline = Date().addingTimeInterval(120)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let result = self.fetcher.fetch()
            DispatchQueue.main.async {
                self.inFlight = false
                switch result {
                case .success(let snapshot):
                    self.consecutiveFailures = 0
                    self.rateLimitedUntil = nil
                    self.lastGoodPercent = snapshot.percent
                    self.lastResetsAt = snapshot.resetsAt
                    let defaults = UserDefaults.standard
                    defaults.set(snapshot.percent, forKey: Self.lastGoodKey)
                    defaults.set(Date().timeIntervalSince1970, forKey: Self.lastGoodAtKey)
                    defaults.set(snapshot.resetsAt?.timeIntervalSince1970 ?? 0,
                                 forKey: Self.lastResetsAtKey)
                    self.onUpdate(.usage(percent: snapshot.percent, resetsAt: snapshot.resetsAt))
                case .failure(let error):
                    self.consecutiveFailures += 1
                    if case .rateLimited(let retryAfter) = error, let retryAfter {
                        self.rateLimitedUntil = Date().addingTimeInterval(
                            min(retryAfter, PollBackoff.maxDelay))
                    }
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

    private func scheduleNext() {
        var delay = PollBackoff.jitteredDelay(interval: interval,
                                              consecutiveFailures: consecutiveFailures)
        // A server that explicitly asked us to wait wins over our own backoff,
        // but never shrinks a longer computed delay. The window is already
        // capped at the backoff ceiling when it's set.
        if let until = rateLimitedUntil {
            delay = max(delay, until.timeIntervalSinceNow)
        }
        nextTickDeadline = Date().addingTimeInterval(delay + 60)
        // .common mode: default-mode timers stall while the run loop tracks
        // mouse events, which could hold a tick back indefinitely.
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = min(delay * 0.1, 10)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
