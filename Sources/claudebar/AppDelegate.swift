import AppKit
import ClaudeBarCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let demo: Bool
    private var window: OverlayWindow!
    private var barView: BarView!
    private var poller: UsagePoller?
    private var demoTimer: Timer?
    private var demoPercent: Double = 0
    private var demoRising = true

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
        // The window can get lost on Space switches, display sleep, or screen
        // reconfiguration even though the process keeps running — re-assert it
        // on those events and on every data update.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.window.reassert() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.window.reassert() }

        if let fixedIndex = CommandLine.arguments.firstIndex(of: "--fixed"),
           fixedIndex + 1 < CommandLine.arguments.count,
           let fixedPercent = Double(CommandLine.arguments[fixedIndex + 1]) {
            barView.render(.usage(percent: fixedPercent))
            return
        }

        if demo {
            demoTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.demoPercent += self.demoRising ? 1 : -1
                if self.demoPercent >= 100 { self.demoRising = false }
                if self.demoPercent <= 0 { self.demoRising = true }
                self.barView.render(.usage(percent: self.demoPercent))
            }
        } else {
            poller = UsagePoller(intervalSeconds: config.pollIntervalSeconds) { [weak self] state in
                self?.barView.render(state)
                self?.window.reassert()
            }
            poller?.start()
        }
    }
}
