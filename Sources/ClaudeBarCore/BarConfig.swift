import Foundation

public struct Threshold: Codable, Equatable {
    public let upTo: Double
    public let color: String
    public let emoji: String

    public init(upTo: Double, color: String, emoji: String) {
        self.upTo = upTo
        self.color = color
        self.emoji = emoji
    }
}

public struct BarConfig: Equatable {
    public var side: String
    public var widthPx: Double
    public var pollIntervalSeconds: Double
    public var showEmoji: Bool
    public var showResetTime: Bool
    public var thresholds: [Threshold]

    public static let `default` = BarConfig(
        side: "left",
        widthPx: 12,
        pollIntervalSeconds: 120,
        showEmoji: true,
        showResetTime: true,
        thresholds: [
            Threshold(upTo: 50, color: "#34C759", emoji: "😊"),
            Threshold(upTo: 75, color: "#FFCC00", emoji: "😐"),
            Threshold(upTo: 90, color: "#FF9500", emoji: "😬"),
            Threshold(upTo: 100, color: "#FF3B30", emoji: "🚨"),
        ]
    )

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/claudebar/config.json")
    }

    private struct Partial: Decodable {
        let side: String?
        let widthPx: Double?
        let pollIntervalSeconds: Double?
        let showEmoji: Bool?
        let showResetTime: Bool?
        let thresholds: [Threshold]?
    }

    public static func load(from url: URL = defaultURL) -> BarConfig {
        guard
            let data = try? Data(contentsOf: url),
            let partial = try? JSONDecoder().decode(Partial.self, from: data)
        else { return .default }

        var config = BarConfig.default
        if let side = partial.side { config.side = side }
        if let widthPx = partial.widthPx { config.widthPx = widthPx }
        if let poll = partial.pollIntervalSeconds { config.pollIntervalSeconds = poll }
        if let showEmoji = partial.showEmoji { config.showEmoji = showEmoji }
        if let showResetTime = partial.showResetTime { config.showResetTime = showResetTime }
        if let thresholds = partial.thresholds { config.thresholds = thresholds }
        config.sanitize()
        return config
    }

    private mutating func sanitize() {
        if side != "left" && side != "right" { side = Self.default.side }
        if !(widthPx > 0 && widthPx <= 40) { widthPx = Self.default.widthPx }
        if !(pollIntervalSeconds >= 5) { pollIntervalSeconds = Self.default.pollIntervalSeconds }
        // Drop thresholds whose color can't be parsed — otherwise the renderer
        // silently falls back to red and the whole bar reads "almost out".
        thresholds = thresholds.filter { HexColor.rgb($0.color) != nil }
        if thresholds.isEmpty { thresholds = Self.default.thresholds }
        thresholds.sort { $0.upTo < $1.upTo }
    }

    public func threshold(forPercent percent: Double) -> Threshold {
        thresholds.first { percent <= $0.upTo } ?? thresholds.last!
    }

    /// Clamped colour lookup. Every renderer wants the same thing — a colour
    /// for a percentage that may be out of range — so none of them should be
    /// repeating the clamp or the hex fallback.
    public func color(forPercent percent: Double) -> (r: Double, g: Double, b: Double) {
        let clamped = min(max(percent, 0), 100)
        return HexColor.rgb(threshold(forPercent: clamped).color) ?? (r: 1, g: 0.29, b: 0.13)
    }
}

public enum HexColor {
    public static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        let stripped = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard stripped.count == 6, let value = UInt32(stripped, radix: 16) else { return nil }
        return (
            r: Double((value >> 16) & 0xFF) / 255.0,
            g: Double((value >> 8) & 0xFF) / 255.0,
            b: Double(value & 0xFF) / 255.0
        )
    }
}
