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

    init(config: BarConfig, screen: NSScreen) {
        // Wider than the bar itself so the emoji has room; still click-through.
        let windowWidth = CGFloat(config.widthPx) + 26
        let screenFrame = screen.frame
        let x = config.side == "left" ? screenFrame.minX : screenFrame.maxX - windowWidth
        let frame = NSRect(x: x, y: screenFrame.minY, width: windowWidth, height: screenFrame.height)

        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    }
}
