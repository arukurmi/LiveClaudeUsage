import Foundation
import ClaudeBarCore

final class UsagePoller {
    private let interval: TimeInterval
    private let onUpdate: (DisplayState) -> Void
    private let fetcher = UsageFetcher()
    private var timer: Timer?

    init(intervalSeconds: TimeInterval, onUpdate: @escaping (DisplayState) -> Void) {
        self.interval = intervalSeconds
        self.onUpdate = onUpdate
    }

    func start() {
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let result = self.fetcher.fetch()
            DispatchQueue.main.async {
                switch result {
                case .success(let snapshot):
                    self.onUpdate(.usage(percent: snapshot.percent))
                case .failure:
                    self.onUpdate(.error)
                }
            }
        }
    }
}
