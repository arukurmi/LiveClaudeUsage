import AppKit
import ClaudeBarCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let demo: Bool
    private var window: OverlayWindow!
    private var barView: BarView!

    init(demo: Bool) {
        self.demo = demo
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = BarConfig.load()
        guard let screen = NSScreen.main else {
            FileHandle.standardError.write(Data("claudebar: no screen available\n".utf8))
            NSApp.terminate(nil)
            return
        }
        window = OverlayWindow(config: config, screen: screen)
        let barView = BarView(config: config)
        window.contentView = barView
        self.barView = barView
        window.orderFrontRegardless()
        barView.render(.usage(percent: 63)) // temporary fixed value; poller arrives in Task 7
    }
}
