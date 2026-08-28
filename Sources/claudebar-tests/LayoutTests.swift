import Foundation
import ClaudeBarCore

func runLayoutTests() {
    // Reset labels: relative while the window is close enough to plan around,
    // absolute once it is not. That split is what puts "Resets in 51 min" on a
    // session limit and "Resets Thu 12:00 AM" on a weekly one.
    let utc = TimeZone(identifier: "UTC")!
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    func label(_ seconds: TimeInterval) -> String {
        ResetLabel.string(for: now.addingTimeInterval(seconds), now: now, timeZone: utc)
    }
    expectEqual(label(51 * 60), "Resets in 51 min", "minutes")
    expectEqual(label(30), "Resets in under a min", "sub-minute")
    expectEqual(label(0), "Resetting now", "already elapsed")
    expectEqual(label(-500), "Resetting now", "past reset never reads as a future one")
    expectEqual(label(2 * 3600), "Resets in 2 hr", "whole hours drop the minutes")
    expectEqual(label(2 * 3600 + 15 * 60), "Resets in 2 hr 15 min", "hours and minutes")
    expectEqual(label(23 * 3600), "Resets in 23 hr", "still relative just under a day")
    expect(label(25 * 3600).hasPrefix("Resets "), "past a day switches to a weekday")
    expect(!label(25 * 3600).contains("in"), "past a day is not phrased as a countdown")
    // 1_700_000_000 is Tue 14 Nov 2023 22:13:20 UTC; +4 days lands on Saturday.
    expectEqual(label(4 * 86_400), "Resets Sat 10:13 PM", "weekday and time")

    // The tab grows by exactly one item's worth per limit, and never collapses
    // when there is nothing to show.
    let one = RailMetrics.railBodySize(itemCount: 1)
    let two = RailMetrics.railBodySize(itemCount: 2)
    let three = RailMetrics.railBodySize(itemCount: 3)
    expectEqual(two.height - one.height, RailMetrics.itemHeight + RailMetrics.itemSpacing,
                "second ring adds one item plus a gap")
    expectEqual(three.height - two.height, two.height - one.height, "growth stays linear")
    expectEqual(RailMetrics.railBodySize(itemCount: 0), one,
                "an empty tab still has room for one item")
    expectEqual(one.width, two.width, "width does not depend on the number of rings")

    // Every ring must sit inside the tab, padding included.
    for count in 1...4 {
        let size = RailMetrics.railBodySize(itemCount: count)
        let lastTop = RailMetrics.itemTopOffset(index: count - 1)
        expect(lastTop + RailMetrics.itemHeight <= size.height - RailMetrics.railPaddingBottom + 0.01,
               "\(count) rings fit inside the tab")
        expect(RailMetrics.itemTopOffset(index: 0) >= RailMetrics.railPaddingTop,
               "first ring clears the top padding")
    }

    // Same contract for the panel's rows.
    for count in 1...4 {
        let size = RailMetrics.popoverBodySize(rowCount: count)
        let lastTop = RailMetrics.popoverRowTopOffset(index: count - 1)
        expect(lastTop + RailMetrics.popoverRowHeight <= size.height - RailMetrics.popoverPadding + 0.01,
               "\(count) rows fit inside the panel")
    }
    expectEqual(RailMetrics.popoverBodySize(rowCount: 0),
                RailMetrics.popoverBodySize(rowCount: 1),
                "an empty panel keeps one row of height for its message")

    // The beak has to land on the straight part of the panel edge, clear of the
    // rounded corners, or it renders as a dent in a corner instead of an arrow.
    for count in 1...4 {
        let height = RailMetrics.popoverBodySize(rowCount: count).height
        let beak = height - RailMetrics.railPaddingTop - RailMetrics.ringDiameter / 2
            + RailMetrics.popoverTopInset
        let margin = RailMetrics.popoverCornerRadius + RailMetrics.beakHeight / 2
        expect(beak >= margin && beak <= height - margin,
               "beak clears the corners with \(count) rows (beak \(beak), height \(height))")
    }
}
