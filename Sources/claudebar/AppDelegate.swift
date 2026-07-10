import AppKit
import ClaudeBarCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let demo: Bool
    private var window: OverlayWindow!

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
        // Temporary: solid strip to verify placement; BarView replaces this next task.
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.8).cgColor
        window.contentView = view
        window.orderFrontRegardless()
    }
}
