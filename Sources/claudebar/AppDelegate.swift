import AppKit
import ClaudeBarCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let demo: Bool
    private var window: OverlayWindow!
    private var barView: BarView!
    private var poller: UsagePoller?
    private var demoTimer: Timer?
    private var hoverTimer: Timer?
    private var demoPercent: Double = 0
    private var demoRising = true

    private static let collapsedKey = "barCollapsed"

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

        // Hover the bar to reveal the hide chip; click it to collapse into a dot,
        // click the dot to bring the bar back. The choice survives restarts.
        barView.onToggleCollapse = { [weak self] in
            guard let self else { return }
            let collapsed = !self.window.collapsed
            UserDefaults.standard.set(collapsed, forKey: Self.collapsedKey)
            self.window.collapsed = collapsed
            self.barView.setCollapsed(collapsed)
        }
        if UserDefaults.standard.bool(forKey: Self.collapsedKey) {
            window.collapsed = true
            barView.setCollapsed(true)
        }
        // The window is click-through by default; a light poll flips mouse
        // handling on only while the pointer is actually over the bar. Global
        // event monitors would need extra permissions — polling doesn't.
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self else { return }
            let inside = self.window.frame.contains(NSEvent.mouseLocation)
            if self.window.ignoresMouseEvents == inside {
                self.window.ignoresMouseEvents = !inside
            }
            self.barView.setHovering(inside)
        }
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
            barView.render(.usage(percent: fixedPercent, resetsAt: Date().addingTimeInterval(2.5 * 3600)))
            // Visual-test hook: freeze the hover state so the hide chip can be screenshotted.
            if CommandLine.arguments.contains("--hover") {
                hoverTimer?.invalidate()
                barView.setHovering(true)
            }
            return
        }

        if demo {
            demoTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.demoPercent += self.demoRising ? 1 : -1
                if self.demoPercent >= 100 { self.demoRising = false }
                if self.demoPercent <= 0 { self.demoRising = true }
                self.barView.render(.usage(percent: self.demoPercent,
                                           resetsAt: Date().addingTimeInterval(2.5 * 3600)))
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
