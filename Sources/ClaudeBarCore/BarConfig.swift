import Foundation

/// A colour tier, applied to the ring arc and the popover's progress fill.
/// Configs written for the old edge bar carried an `emoji` key too; it is
/// simply ignored now rather than failing the whole decode.
public struct Threshold: Codable, Equatable {
    public let upTo: Double
    public let color: String

    public init(upTo: Double, color: String) {
        self.upTo = upTo
        self.color = color
    }
}

public struct BarConfig: Equatable {
    /// Which top corner the rail hangs from: "left" or "right".
    public var side: String
    public var pollIntervalSeconds: Double
    public var thresholds: [Threshold]

    public static let `default` = BarConfig(
        side: "right",
        pollIntervalSeconds: 120,
        thresholds: [
            Threshold(upTo: 40, color: "#3ADE79"),
            Threshold(upTo: 70, color: "#E8F03B"),
            Threshold(upTo: 100, color: "#FF4B22"),
        ]
    )

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/claudebar/config.json")
    }

    private struct Partial: Decodable {
        let side: String?
        let pollIntervalSeconds: Double?
        let thresholds: [Threshold]?
    }

    public static func load(from url: URL = defaultURL) -> BarConfig {
        guard
            let data = try? Data(contentsOf: url),
            let partial = try? JSONDecoder().decode(Partial.self, from: data)
        else { return .default }

        var config = BarConfig.default
        if let side = partial.side { config.side = side }
        if let poll = partial.pollIntervalSeconds { config.pollIntervalSeconds = poll }
        if let thresholds = partial.thresholds { config.thresholds = thresholds }
        config.sanitize()
        return config
    }

    private mutating func sanitize() {
        if side != "left" && side != "right" { side = Self.default.side }
        if !(pollIntervalSeconds >= 5) { pollIntervalSeconds = Self.default.pollIntervalSeconds }
        // Drop thresholds whose color can't be parsed — otherwise the renderer
        // silently falls back to red and every ring reads "almost out".
        thresholds = thresholds.filter { HexColor.rgb($0.color) != nil }
        if thresholds.isEmpty { thresholds = Self.default.thresholds }
        thresholds.sort { $0.upTo < $1.upTo }
    }

    public func threshold(forPercent percent: Double) -> Threshold {
        thresholds.first { percent <= $0.upTo } ?? thresholds.last!
    }

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
