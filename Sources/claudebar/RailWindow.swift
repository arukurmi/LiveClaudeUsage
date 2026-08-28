import AppKit
import ClaudeBarCore

enum ScreenGeometry {
    /// The MacBook's built-in panel, so the rail never lands on an external monitor.
    static func builtInScreen() -> NSScreen? {
        let builtIn = NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                    as? NSNumber else { return false }
            return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
        }
        return builtIn ?? NSScreen.main
    }

    /// Height of the menu bar on that screen — zero while it is auto-hidden,
    /// which is the signal the rail uses to get out of the way in full screen.
    static func menuBarHeight(_ screen: NSScreen) -> CGFloat {
        screen.frame.maxY - screen.visibleFrame.maxY
    }

    static var menuBarIsVisible: Bool {
        guard let screen = builtInScreen() else { return false }
        return menuBarHeight(screen) > 5
    }

    /// Window frame for the rail. Wider than the tab itself: the concave corners
    /// that blend it into the menu bar are drawn outside the tab body.
    static func railFrame(config: BarConfig, screen: NSScreen, itemCount: Int) -> NSRect {
        let body = RailMetrics.railBodySize(itemCount: itemCount)
        let ear = RailMetrics.earRadius
        let inset = RailMetrics.screenEdgeInset
        let x = config.side == "left"
            ? screen.frame.minX + inset - ear
            : screen.frame.maxX - inset - body.width - ear
        let top = screen.frame.maxY - max(menuBarHeight(screen), 0)
        return NSRect(x: x, y: top - body.height, width: body.width + ear * 2, height: body.height)
    }

    /// Window frame for the popover, hung beside the rail with its beak tip
    /// `popoverGap` away from the tab.
    static func popoverFrame(config: BarConfig, screen: NSScreen,
                             railFrame: NSRect, rowCount: Int) -> NSRect {
        let body = RailMetrics.popoverBodySize(rowCount: rowCount)
        let depth = RailMetrics.beakDepth
        let width = body.width + depth
        let railBody = railFrame.insetBy(dx: RailMetrics.earRadius, dy: 0)
        let x = config.side == "left"
            ? railBody.maxX + RailMetrics.popoverGap
            : railBody.minX - RailMetrics.popoverGap - width
        let top = screen.frame.maxY - max(menuBarHeight(screen), 0)
        let clampedX = min(max(x, screen.frame.minX + 6), screen.frame.maxX - width - 6)
        let popoverTop = top - RailMetrics.popoverTopInset
        return NSRect(x: clampedX, y: popoverTop - body.height,
                      width: width, height: body.height)
    }

    /// Where the beak should point, in the popover view's own coordinates:
    /// level with the middle of the first ring.
    static func beakCenterY(popoverHeight: CGFloat) -> CGFloat {
        popoverHeight - RailMetrics.railPaddingTop - RailMetrics.ringDiameter / 2
            + RailMetrics.popoverTopInset
    }
}
