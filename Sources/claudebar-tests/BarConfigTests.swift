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
