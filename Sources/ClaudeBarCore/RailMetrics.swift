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
}
