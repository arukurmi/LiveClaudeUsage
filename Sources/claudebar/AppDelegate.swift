import AppKit
import ClaudeBarCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let demo: Bool
    private let config = BarConfig.load()

    private var railWindow: ChromelessPanel!
    private var railView: RailView!
    private var popoverWindow: ChromelessPanel!
    private var popoverView: PopoverView!

    private var poller: UsagePoller?
    private var demoTimer: Timer?
    private var hoverTimer: Timer?
    private var demoPercent: Double = 0
    private var demoRising = true
    private var popoverVisible = false
    private var railItemCount = 0

    private var activityToken: NSObjectProtocol?

    init(demo: Bool) {
        self.demo = demo
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // App Nap throttles accessory apps' timers, stretching the poll
        // cadence far past the configured interval. Opting out keeps ticks on
        // time; "AllowingIdleSystemSleep" means we never keep the Mac awake.
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "polling Claude usage on a fixed cadence")

        guard let screen = ScreenGeometry.builtInScreen() else {
            FileHandle.standardError.write(Data("claudebar: no screen available\n".utf8))
            NSApp.terminate(nil)
            return
        }

        railView = RailView(config: config)
        railView.onContextMenu = { [weak self] event in self?.showMenu(for: event) }
        railWindow = ChromelessPanel(
            contentRect: ScreenGeometry.railFrame(config: config, screen: screen, itemCount: 1),
            interactive: true)
        railWindow.contentView = railView
        railWindow.orderFrontRegardless()

        popoverView = PopoverView(config: config)
        popoverWindow = ChromelessPanel(contentRect: .zero, interactive: false)
        popoverWindow.contentView = popoverView
        popoverWindow.alphaValue = 0

        // Hover the rail to open the panel; leaving both closes it. A poll beats
        // tracking areas here — the panel is a separate window, so a single
        // tracking rect can't cover the pair.
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            self?.updateHover()
        }
        // The windows can get lost on Space switches, display sleep, or screen
        // reconfiguration even though the process keeps running.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.reposition() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.reposition() }

        render(.error)
        startDataSource()
    }

    // MARK: - Data

    private func startDataSource() {
        let arguments = CommandLine.arguments
        if let fixedIndex = arguments.firstIndex(of: "--fixed"), fixedIndex + 1 < arguments.count {
            let percents = arguments[fixedIndex + 1].split(separator: ",").compactMap { Double($0) }
            let kinds = ["session", "weekly_all", "weekly_opus", "weekly_sonnet"]
            let offsets: [TimeInterval] = [51 * 60, 4 * 86_400, 5 * 86_400, 6 * 86_400]
            let limits = percents.enumerated().map { index, percent in
                UsageLimit(kind: index < kinds.count ? kinds[index] : "limit_\(index)",
                           percent: percent,
                           resetsAt: Date().addingTimeInterval(offsets[min(index, 3)]))
            }
            render(.usage(UsageSnapshot(percent: percents.first ?? 0,
                                        resetsAt: limits.first?.resetsAt,
                                        limits: limits)))
            // Visual-test hook: pin the panel open so it can be screenshotted.
            if arguments.contains("--open") {
                hoverTimer?.invalidate()
                setPopoverVisible(true, animated: false)
            }
            return
        }

        if demo {
            demoTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.demoPercent += self.demoRising ? 1 : -1
                if self.demoPercent >= 100 { self.demoRising = false }
                if self.demoPercent <= 0 { self.demoRising = true }
                let weekly = (self.demoPercent * 0.4).rounded()
                self.render(.usage(UsageSnapshot(
                    percent: self.demoPercent,
                    resetsAt: Date().addingTimeInterval(2.5 * 3600),
                    limits: [
                        UsageLimit(kind: "session", percent: self.demoPercent,
                                   resetsAt: Date().addingTimeInterval(2.5 * 3600)),
                        UsageLimit(kind: "weekly_all", percent: weekly,
                                   resetsAt: Date().addingTimeInterval(4 * 86_400)),
                    ])))
            }
        } else {
            poller = UsagePoller(intervalSeconds: config.pollIntervalSeconds) { [weak self] state in
                self?.render(state)
            }
            poller?.start()
        }
    }

    private func render(_ state: DisplayState) {
        let count = max(state.snapshot?.limits.count ?? 0, 1)
        railView.render(state)
        popoverView.render(state)
        railItemCount = count
        reposition()
    }

    // MARK: - Placement

    private func reposition() {
        guard let screen = ScreenGeometry.builtInScreen() else { return }
        let count = max(railItemCount, 1)
        let railFrame = ScreenGeometry.railFrame(config: config, screen: screen, itemCount: count)
        railWindow.place(railFrame)

        let popoverFrame = ScreenGeometry.popoverFrame(config: config, screen: screen,
                                                       railFrame: railFrame, rowCount: count)
        popoverWindow.place(popoverFrame)
        popoverView.setBeakCenterY(ScreenGeometry.beakCenterY(popoverHeight: popoverFrame.height))
        popoverView.needsLayout = true

        // The tab belongs to the menu bar, so it leaves with it — full-screen
        // video gets the whole screen back without the user hiding anything.
        let shouldShow = ScreenGeometry.menuBarIsVisible
        if shouldShow {
            if !railWindow.isVisible { railWindow.orderFrontRegardless() }
            railWindow.orderFrontRegardless()
        } else {
            if railWindow.isVisible { railWindow.orderOut(nil) }
            setPopoverVisible(false, animated: false)
        }
    }

    // MARK: - Hover

    private func updateHover() {
        guard railWindow.isVisible else {
            setPopoverVisible(false, animated: true)
            return
        }
        let mouse = NSEvent.mouseLocation
        // Union of the two windows, so crossing the gap between them doesn't
        // read as leaving.
        var zone = railWindow.frame
        if popoverVisible { zone = zone.union(popoverWindow.frame) }
        if railWindow.frame.contains(mouse) {
            setPopoverVisible(true, animated: true)
        } else if !zone.insetBy(dx: -2, dy: -2).contains(mouse) {
            setPopoverVisible(false, animated: true)
        }
    }

    private func setPopoverVisible(_ visible: Bool, animated: Bool) {
        guard visible != popoverVisible else { return }
        popoverVisible = visible
        if visible {
            popoverWindow.alphaValue = 0
            popoverWindow.orderFrontRegardless()
            popoverWindow.invalidateShadow()
        }
        guard animated, !Motion.reduced else {
            popoverWindow.alphaValue = visible ? 1 : 0
            if !visible { popoverWindow.orderOut(nil) }
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = visible ? 0.16 : 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            popoverWindow.animator().alphaValue = visible ? 1 : 0
        } completionHandler: { [weak self] in
            guard let self, !self.popoverVisible else { return }
            self.popoverWindow.orderOut(nil)
        }
    }

    // MARK: - Menu

    private func showMenu(for event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh now", action: #selector(refreshNow), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ClaudeBar", action: #selector(quit), keyEquivalent: "")
            .target = self
        NSMenu.popUpContextMenu(menu, with: event, for: railView)
    }

    @objc private func refreshNow() {
        poller?.refreshNow()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
