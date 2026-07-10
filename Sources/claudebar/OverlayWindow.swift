import AppKit
import ClaudeBarCore

final class OverlayWindow: NSWindow {
    /// The MacBook's built-in panel, so the bar never lands on an external monitor.
    static func builtInScreen() -> NSScreen? {
        let screens = NSScreen.screens
        let builtIn = screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return false }
            return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
        }
        return builtIn ?? NSScreen.main
    }

    static func desiredFrame(config: BarConfig, screen: NSScreen) -> NSRect {
        // Just wide enough for the emoji sitting on the bar; still click-through.
        let windowWidth = max(CGFloat(config.widthPx), 16)
        let screenFrame = screen.frame
        let x = config.side == "left" ? screenFrame.minX : screenFrame.maxX - windowWidth
        return NSRect(x: x, y: screenFrame.minY, width: windowWidth, height: screenFrame.height)
    }

    private let config: BarConfig

    init(config: BarConfig, screen: NSScreen) {
        self.config = config
        let frame = Self.desiredFrame(config: config, screen: screen)

        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    }

    /// Re-pin to the built-in screen and bring back to the front. Safe to call often;
    /// recovers from Space switches, display sleep, and resolution changes.
    func reassert() {
        if let screen = Self.builtInScreen() {
            let frame = Self.desiredFrame(config: config, screen: screen)
            if frame != self.frame { setFrame(frame, display: true) }
        }
        if !isVisible { orderFrontRegardless() }
        orderFrontRegardless()
    }
}
