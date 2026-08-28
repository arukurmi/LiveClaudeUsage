import CoreGraphics

/// Fixed geometry for the tab that hangs off the menu bar. Kept out of the
/// views so the sizes can be exercised without an AppKit run loop.
public enum RailMetrics {
    public static let ringDiameter: CGFloat = 42
    public static let ringStroke: CGFloat = 3.5
    public static let percentLabelHeight: CGFloat = 15
    public static let ringToLabelGap: CGFloat = 3
    public static let itemSpacing: CGFloat = 13
    public static let railPaddingTop: CGFloat = 18
    public static let railPaddingBottom: CGFloat = 14
    public static let railHorizontalPadding: CGFloat = 16
    /// Radius of the concave corners that blend the tab into the menu bar.
    public static let earRadius: CGFloat = 10
    public static let railBottomRadius: CGFloat = 20
    /// Gap between the tab body and the screen edge, wide enough that the upper
    /// concave corner still lands on screen.
    public static let screenEdgeInset: CGFloat = 12

    public static var itemHeight: CGFloat {
        ringDiameter + ringToLabelGap + percentLabelHeight
    }

    public static var railWidth: CGFloat {
        ringDiameter + railHorizontalPadding * 2
    }

    /// Size of the tab body for a given number of limits. Always tall enough
    /// for one item, so an empty or failed fetch still leaves something to
    /// hover.
    public static func railBodySize(itemCount: Int) -> CGSize {
        let count = max(itemCount, 1)
        let height = railPaddingTop
            + itemHeight * CGFloat(count)
            + itemSpacing * CGFloat(count - 1)
            + railPaddingBottom
        return CGSize(width: railWidth, height: height)
    }

    /// Top edge of one item inside the tab body, measured down from the top.
    public static func itemTopOffset(index: Int) -> CGFloat {
        railPaddingTop + (itemHeight + itemSpacing) * CGFloat(index)
    }

    // Popover
    public static let popoverWidth: CGFloat = 288
    public static let popoverCornerRadius: CGFloat = 18
    public static let popoverPadding: CGFloat = 14
    public static let popoverHeaderHeight: CGFloat = 20
    public static let popoverHeaderGap: CGFloat = 13
    public static let popoverRowHeight: CGFloat = 45
    public static let popoverRowSpacing: CGFloat = 13
    public static let popoverTrackHeight: CGFloat = 5
    /// How far the beak juts out toward the tab, and how tall its base is.
    public static let beakDepth: CGFloat = 9
    public static let beakHeight: CGFloat = 22
    /// Gap between the beak tip and the tab body.
    public static let popoverGap: CGFloat = 6
    /// The tab is part of the menu bar, so it starts flush with it. The panel
    /// is not, so it hangs just clear — otherwise its rounded top corners cut
    /// two small notches out of the bar's edge.
    public static let popoverTopInset: CGFloat = 8

    public static func popoverBodySize(rowCount: Int) -> CGSize {
        let count = max(rowCount, 1)
        let height = popoverPadding
            + popoverHeaderHeight
            + popoverHeaderGap
            + popoverRowHeight * CGFloat(count)
            + popoverRowSpacing * CGFloat(count - 1)
            + popoverPadding
        return CGSize(width: popoverWidth, height: height)
    }

    public static func popoverRowTopOffset(index: Int) -> CGFloat {
        popoverPadding + popoverHeaderHeight + popoverHeaderGap
            + (popoverRowHeight + popoverRowSpacing) * CGFloat(index)
    }
}
