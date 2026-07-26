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

    let partial = BarConfig.load(from: tempFile(#"{"side": "left", "widthPx": 10}"#))
    expectEqual(partial.side, "left", "partial file side")
    expectEqual(partial.widthPx, 10, "partial file width")
    expectEqual(partial.pollIntervalSeconds, BarConfig.default.pollIntervalSeconds,
                "partial file keeps default poll interval")
    expectEqual(partial.thresholds, BarConfig.default.thresholds,
                "partial file keeps default thresholds")

    let invalid = BarConfig.load(from: tempFile(
        #"{"side": "top", "widthPx": -3, "pollIntervalSeconds": 1}"#))
    expectEqual(invalid.side, "left", "invalid side falls back")
    expectEqual(invalid.widthPx, 12, "invalid width falls back")
    expectEqual(invalid.pollIntervalSeconds, 120, "too-small poll interval falls back")

    expectEqual(BarConfig.load(from: tempFile("{oops")), .default,
                "malformed JSON gives defaults")

    // A threshold with an unparsable color is dropped; the valid one survives.
    let mixedColors = BarConfig.load(from: tempFile("""
        {"thresholds": [{"upTo": 50, "color": "not-a-hex", "emoji": "😊"},
                        {"upTo": 100, "color": "#FF3B30", "emoji": "🚨"}]}
        """))
    expectEqual(mixedColors.thresholds.count, 1, "threshold with bad color is dropped")
    expectEqual(mixedColors.thresholds.first?.color, "#FF3B30", "valid-color threshold kept")
    // If every threshold has a bad color we fall back to the defaults rather
    // than leaving the bar with no color table at all.
    let allBad = BarConfig.load(from: tempFile(
        #"{"thresholds": [{"upTo": 100, "color": "xyz", "emoji": "🚨"}]}"#))
    expectEqual(allBad.thresholds, BarConfig.default.thresholds,
                "all-invalid colors fall back to defaults")

    expect(BarConfig.default.showResetTime, "reset time shown by default")
    expect(!BarConfig.load(from: tempFile(#"{"showResetTime": false}"#)).showResetTime,
           "showResetTime can be disabled")

    let utc = TimeZone(identifier: "UTC")!
    expectEqual(ResetTimeFormatter.string(from: Date(timeIntervalSince1970: 0), timeZone: utc),
                "12:00AM", "midnight formats")
    expectEqual(ResetTimeFormatter.string(from: Date(timeIntervalSince1970: 59_400), timeZone: utc),
                "4:30PM", "afternoon formats without leading zero")

    let config = BarConfig.default
    expectEqual(config.threshold(forPercent: 0).emoji, "😊", "0%")
    expectEqual(config.threshold(forPercent: 50).emoji, "😊", "50% boundary")
    expectEqual(config.threshold(forPercent: 50.1).emoji, "😐", "just past 50%")
    expectEqual(config.threshold(forPercent: 75).emoji, "😐", "75% boundary")
    expectEqual(config.threshold(forPercent: 90).emoji, "😬", "90% boundary")
    expectEqual(config.threshold(forPercent: 90.1).emoji, "🚨", "just past 90%")
    expectEqual(config.threshold(forPercent: 100).emoji, "🚨", "100%")
    expectEqual(config.threshold(forPercent: 250).emoji, "🚨", "clamps above table")

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
