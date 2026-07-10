import AppKit
import ClaudeBarCore

final class OverlayWindow: NSWindow {
    init(config: BarConfig, screen: NSScreen) {
        // Wider than the bar itself so the emoji has room; still click-through.
        let windowWidth = max(CGFloat(config.widthPx), 24)
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
