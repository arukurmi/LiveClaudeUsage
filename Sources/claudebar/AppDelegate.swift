import AppKit
import ClaudeBarCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let demo: Bool
    private var window: OverlayWindow!
    private var barView: BarView!
    private var poller: UsagePoller?

    init(demo: Bool) {
        self.demo = demo
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = BarConfig.load()
        guard let screen = OverlayWindow.builtInScreen() else {
            FileHandle.standardError.write(Data("claudebar: no screen available\n".utf8))
            NSApp.terminate(nil)
            return
        }
        window = OverlayWindow(config: config, screen: screen)
        let barView = BarView(config: config)
        window.contentView = barView
        self.barView = barView
        window.orderFrontRegardless()
        poller = UsagePoller(intervalSeconds: config.pollIntervalSeconds) { [weak self] state in
            self?.barView.render(state)
        }
        poller?.start()
    }
}
