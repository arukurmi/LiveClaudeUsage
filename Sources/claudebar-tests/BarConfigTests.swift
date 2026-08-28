import Foundation
import ClaudeBarCore

private func tempFile(_ contents: String) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".json")
    try! contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}

func runBarConfigTests() {
    let missing = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).json")
    expectEqual(BarConfig.load(from: missing), .default, "missing file gives defaults")

    let partial = BarConfig.load(from: tempFile(#"{"side": "left"}"#))
    expectEqual(partial.side, "left", "partial file side")
    expectEqual(partial.pollIntervalSeconds, BarConfig.default.pollIntervalSeconds,
                "partial file keeps default poll interval")
    expectEqual(partial.thresholds, BarConfig.default.thresholds,
                "partial file keeps default thresholds")

    let invalid = BarConfig.load(from: tempFile(#"{"side": "top", "pollIntervalSeconds": 1}"#))
    expectEqual(invalid.side, "right", "invalid side falls back")
    expectEqual(invalid.pollIntervalSeconds, 120, "too-small poll interval falls back")

    expectEqual(BarConfig.load(from: tempFile("{oops")), .default,
                "malformed JSON gives defaults")

    // Configs written for the old edge bar carried `emoji`, `widthPx` and
    // friends. Those keys are gone, but such a file must still load cleanly
    // instead of silently reverting every other setting to its default.
    let legacy = BarConfig.load(from: tempFile("""
        {"side": "left", "widthPx": 12, "showEmoji": true, "showResetTime": false,
         "pollIntervalSeconds": 60,
         "thresholds": [{"upTo": 50, "color": "#34C759", "emoji": "😊"},
                        {"upTo": 100, "color": "#FF3B30", "emoji": "🚨"}]}
        """))
    expectEqual(legacy.side, "left", "legacy config keeps its side")
    expectEqual(legacy.pollIntervalSeconds, 60, "legacy config keeps its poll interval")
    expectEqual(legacy.thresholds.count, 2, "legacy thresholds survive the dropped emoji key")

    // A threshold with an unparsable color is dropped; the valid one survives.
    let mixedColors = BarConfig.load(from: tempFile("""
        {"thresholds": [{"upTo": 50, "color": "not-a-hex"},
                        {"upTo": 100, "color": "#FF3B30"}]}
        """))
    expectEqual(mixedColors.thresholds.count, 1, "threshold with bad color is dropped")
    expectEqual(mixedColors.thresholds.first?.color, "#FF3B30", "valid-color threshold kept")
    // If every threshold has a bad color we fall back to the defaults rather
    // than leaving the rings with no color table at all.
    let allBad = BarConfig.load(from: tempFile(#"{"thresholds": [{"upTo": 100, "color": "xyz"}]}"#))
    expectEqual(allBad.thresholds, BarConfig.default.thresholds,
                "all-invalid colors fall back to defaults")

    let utc = TimeZone(identifier: "UTC")!
    expectEqual(ResetTimeFormatter.string(from: Date(timeIntervalSince1970: 0), timeZone: utc),
                "12:00AM", "midnight formats")
    expectEqual(ResetTimeFormatter.string(from: Date(timeIntervalSince1970: 59_400), timeZone: utc),
                "4:30PM", "afternoon formats without leading zero")

    // Tiers are now identified by colour rather than by the emoji that rode the
    // old bar's fill line.
    let config = BarConfig.default
    expectEqual(config.threshold(forPercent: 0).color, "#34C759", "0%")
    expectEqual(config.threshold(forPercent: 50).color, "#34C759", "50% boundary")
    expectEqual(config.threshold(forPercent: 50.1).color, "#FFCC00", "just past 50%")
    expectEqual(config.threshold(forPercent: 75).color, "#FFCC00", "75% boundary")
    expectEqual(config.threshold(forPercent: 90).color, "#FF9500", "90% boundary")
    expectEqual(config.threshold(forPercent: 90.1).color, "#FF3B30", "just past 90%")
    expectEqual(config.threshold(forPercent: 100).color, "#FF3B30", "100%")
    expectEqual(config.threshold(forPercent: 250).color, "#FF3B30", "clamps above table")

    if let green = HexColor.rgb("#34C759") {
        expect(abs(green.r - Double(0x34) / 255.0) < 0.001, "hex r channel")
        expect(abs(green.g - Double(0xC7) / 255.0) < 0.001, "hex g channel")
        expect(abs(green.b - Double(0x59) / 255.0) < 0.001, "hex b channel")
    } else {
        expect(false, "#34C759 should parse")
    }
    expect(HexColor.rgb("nope") == nil, "bad hex gives nil")
    expect(HexColor.rgb("FF3B30") != nil, "hash prefix optional")
}
