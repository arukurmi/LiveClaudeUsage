# ClaudeBar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS click-through edge bar showing live Claude 5-hour session usage (fill + green→red color + emoji), polling the OAuth usage endpoint every 2 minutes.

**Architecture:** Swift Package with two targets: `ClaudeBarCore` (pure-Foundation library: usage fetch/decode, config, color/emoji mapping — fully unit-tested) and `claudebar` (AppKit executable: overlay window, bar view, poller, CLI flags). Installed as a launchd agent.

**Tech Stack:** Swift 5.9+ / AppKit / XCTest / launchd / Makefile. No third-party dependencies.

## Global Constraints

- macOS only; builds with Command Line Tools alone (`swift build`, no Xcode project)
- No external dependencies in Package.swift
- Usage endpoint: `GET https://api.anthropic.com/api/oauth/usage` with headers `Authorization: Bearer <token>` and `anthropic-beta: oauth-2025-04-20`
- Token source: Keychain generic password, service `Claude Code-credentials`, JSON field `claudeAiOauth.accessToken`
- Config file: `~/.config/claudebar/config.json`; invalid/missing values must fall back to defaults, never crash
- Defaults: side right, width 6px, poll 120s, thresholds 50/75/90/100 → `#34C759`😊 / `#FFCC00`😐 / `#FF9500`😬 / `#FF3B30`🚨
- Every task ends with a working state, committed AND pushed (`git push`)
- Commit messages: conventional-commit style, ending with trailer `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

---

### Task 1: Swift package scaffold

**Files:**
- Create: `Package.swift`, `.gitignore`, `README.md`, `Sources/ClaudeBarCore/Placeholder.swift`, `Sources/claudebar/main.swift`, `Tests/ClaudeBarCoreTests/PlaceholderTests.swift`

**Interfaces:**
- Produces: package layout every later task adds files into; targets `ClaudeBarCore` (library), `claudebar` (executable, depends on core), `ClaudeBarCoreTests`.

- [ ] **Step 1: Write files**

`Package.swift`:
```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "claudebar",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ClaudeBarCore"),
        .executableTarget(name: "claudebar", dependencies: ["ClaudeBarCore"]),
        .testTarget(name: "ClaudeBarCoreTests", dependencies: ["ClaudeBarCore"]),
    ]
)
```

`.gitignore`:
```
.build/
.swiftpm/
*.xcodeproj
.DS_Store
```

`README.md`:
```markdown
# 🎨 ClaudeBar — Live Claude Usage Edge Bar for macOS

A whisper-thin, always-on-top bar on your screen edge that shows how much of your
Claude 5-hour session limit you've used. Green and 😊 when fresh, red and 🚨 when
you're about to hit the wall. Click-through — it never gets in your way.

> 🚧 Under construction — being built phase by phase.
```

`Sources/ClaudeBarCore/Placeholder.swift`:
```swift
public enum ClaudeBarCore {
    public static let version = "0.1.0"
}
```

`Sources/claudebar/main.swift`:
```swift
import ClaudeBarCore

print("claudebar \(ClaudeBarCore.version)")
```

`Tests/ClaudeBarCoreTests/PlaceholderTests.swift`:
```swift
import XCTest
import ClaudeBarCore

final class PlaceholderTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(ClaudeBarCore.version, "0.1.0")
    }
}
```

- [ ] **Step 2: Verify build and tests**

Run: `swift build && swift test`
Expected: build succeeds, 1 test passes.

- [ ] **Step 3: Commit and push**

```bash
git add -A && git commit -m "chore: scaffold Swift package (core lib + executable + tests)" && git push
```

---

### Task 2: Usage decoding + Keychain token + `--once` CLI

**Files:**
- Create: `Sources/ClaudeBarCore/UsageFetcher.swift`
- Modify: `Sources/claudebar/main.swift`
- Test: `Tests/ClaudeBarCoreTests/UsageDecoderTests.swift`
- Delete: `Sources/ClaudeBarCore/Placeholder.swift`, `Tests/ClaudeBarCoreTests/PlaceholderTests.swift`

**Interfaces:**
- Produces:
  - `struct UsageSnapshot { let percent: Double; let resetsAt: Date? }`
  - `enum FetchError: Error, Equatable { case tokenUnavailable, network(String), badStatus(Int), decodeFailed }`
  - `enum UsageDecoder { static func decode(_ data: Data) -> Result<UsageSnapshot, FetchError>; static func extractToken(fromKeychainJSON: Data) -> String? }`
  - `protocol TokenProvider { func accessToken() throws -> String }`
  - `struct KeychainCLITokenProvider: TokenProvider`
  - `struct UsageFetcher { init(tokenProvider: TokenProvider = KeychainCLITokenProvider(), session: URLSession = .shared); func fetch() -> Result<UsageSnapshot, FetchError> }` (synchronous; call off the main thread)

- [ ] **Step 1: Write failing tests**

`Tests/ClaudeBarCoreTests/UsageDecoderTests.swift`:
```swift
import XCTest
import ClaudeBarCore

final class UsageDecoderTests: XCTestCase {
    // Trimmed real payload captured from the endpoint on 2026-07-10.
    let realPayload = """
    {"five_hour": {"utilization": 29.0, "resets_at": "2026-07-10T14:49:59.820872+00:00",
     "limit_dollars": null}, "seven_day": {"utilization": 14.0,
     "resets_at": "2026-07-11T15:59:59.820891+00:00"}, "extra_usage": {"is_enabled": false}}
    """.data(using: .utf8)!

    func testDecodesRealPayload() throws {
        let snap = try UsageDecoder.decode(realPayload).get()
        XCTAssertEqual(snap.percent, 29.0)
        XCTAssertNotNil(snap.resetsAt)
    }

    func testMissingResetsAtStillDecodes() throws {
        let data = #"{"five_hour": {"utilization": 88.5}}"#.data(using: .utf8)!
        let snap = try UsageDecoder.decode(data).get()
        XCTAssertEqual(snap.percent, 88.5)
        XCTAssertNil(snap.resetsAt)
    }

    func testGarbageFailsWithDecodeError() {
        let result = UsageDecoder.decode(Data("not json".utf8))
        XCTAssertEqual(result, .failure(.decodeFailed))
    }

    func testExtractTokenFromKeychainJSON() {
        let json = #"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-abc","refreshToken":"r"}}"#
        XCTAssertEqual(UsageDecoder.extractToken(fromKeychainJSON: Data(json.utf8)), "sk-ant-oat01-abc")
        XCTAssertNil(UsageDecoder.extractToken(fromKeychainJSON: Data("{}".utf8)))
    }
}
```

Also make `UsageSnapshot` `Equatable` so `Result` comparisons work in tests.

- [ ] **Step 2: Run tests, verify they fail**

Run: `swift test 2>&1 | tail -5`
Expected: compile error — `UsageDecoder` not defined.

- [ ] **Step 3: Implement**

`Sources/ClaudeBarCore/UsageFetcher.swift`:
```swift
import Foundation

public struct UsageSnapshot: Equatable {
    public let percent: Double
    public let resetsAt: Date?
    public init(percent: Double, resetsAt: Date?) {
        self.percent = percent
        self.resetsAt = resetsAt
    }
}

public enum FetchError: Error, Equatable {
    case tokenUnavailable
    case network(String)
    case badStatus(Int)
    case decodeFailed
}

public enum UsageDecoder {
    private struct Payload: Decodable {
        struct FiveHour: Decodable {
            let utilization: Double
            let resets_at: String?
        }
        let five_hour: FiveHour
    }

    public static func decode(_ data: Data) -> Result<UsageSnapshot, FetchError> {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return .failure(.decodeFailed)
        }
        let resetsAt = payload.five_hour.resets_at.flatMap(parseISO8601)
        return .success(UsageSnapshot(percent: payload.five_hour.utilization, resetsAt: resetsAt))
    }

    public static func parseISO8601(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: string) { return date }
        // Fractional seconds longer than milliseconds trip ISO8601DateFormatter; drop them.
        if let range = string.range(of: #"\.\d+"#, options: .regularExpression) {
            var trimmed = string
            trimmed.removeSubrange(range)
            return plain.date(from: trimmed)
        }
        return nil
    }

    public static func extractToken(fromKeychainJSON data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = object["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String
        else { return nil }
        return token
    }
}

public protocol TokenProvider {
    func accessToken() throws -> String
}

/// Reads the Claude Code OAuth token via `/usr/bin/security` (same credential the CLI uses).
public struct KeychainCLITokenProvider: TokenProvider {
    public init() {}

    public func accessToken() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do { try process.run() } catch { throw FetchError.tokenUnavailable }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw FetchError.tokenUnavailable }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let token = UsageDecoder.extractToken(fromKeychainJSON: data) else {
            throw FetchError.tokenUnavailable
        }
        return token
    }
}

public struct UsageFetcher {
    private let tokenProvider: TokenProvider
    private let session: URLSession

    public init(tokenProvider: TokenProvider = KeychainCLITokenProvider(),
                session: URLSession = .shared) {
        self.tokenProvider = tokenProvider
        self.session = session
    }

    /// Synchronous; call off the main thread.
    public func fetch() -> Result<UsageSnapshot, FetchError> {
        guard let token = try? tokenProvider.accessToken() else {
            return .failure(.tokenUnavailable)
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<UsageSnapshot, FetchError> = .failure(.network("no response"))
        session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                result = .failure(.network(error.localizedDescription))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                result = .failure(.network("not an HTTP response"))
                return
            }
            guard http.statusCode == 200 else {
                result = .failure(.badStatus(http.statusCode))
                return
            }
            guard let data else {
                result = .failure(.decodeFailed)
                return
            }
            result = UsageDecoder.decode(data)
        }.resume()
        semaphore.wait()
        return result
    }
}
```

Replace `Sources/claudebar/main.swift`:
```swift
import Foundation
import ClaudeBarCore

let arguments = CommandLine.arguments

if arguments.contains("--once") {
    switch UsageFetcher().fetch() {
    case .success(let snapshot):
        var line = "session: \(snapshot.percent)%"
        if let resetsAt = snapshot.resetsAt {
            line += " (resets \(resetsAt))"
        }
        print(line)
        exit(0)
    case .failure(let error):
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        exit(1)
    }
}

print("claudebar: run with --once to print usage (overlay comes in a later phase)")
```

Delete `Placeholder.swift` and `PlaceholderTests.swift`.

- [ ] **Step 4: Run tests, verify pass; smoke-test live**

Run: `swift test 2>&1 | tail -3`
Expected: all 4 tests pass.

Run: `swift run claudebar --once`
Expected: `session: <N>% (resets <date>)` with a real percentage.

- [ ] **Step 5: Commit and push**

```bash
git add -A && git commit -m "feat: usage fetcher with keychain token and --once CLI" && git push
```

---

### Task 3: BarConfig loader

**Files:**
- Create: `Sources/ClaudeBarCore/BarConfig.swift`
- Test: `Tests/ClaudeBarCoreTests/BarConfigTests.swift`

**Interfaces:**
- Produces:
  - `struct Threshold: Codable, Equatable { let upTo: Double; let color: String; let emoji: String }`
  - `struct BarConfig: Equatable { var side: String; var widthPx: Double; var pollIntervalSeconds: Double; var showEmoji: Bool; var thresholds: [Threshold]; static let default: BarConfig; static var defaultURL: URL; static func load(from url: URL) -> BarConfig; func threshold(forPercent: Double) -> Threshold }`
  - `enum HexColor { static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double)? }`

- [ ] **Step 1: Write failing tests**

`Tests/ClaudeBarCoreTests/BarConfigTests.swift`:
```swift
import XCTest
import ClaudeBarCore

final class BarConfigTests: XCTestCase {
    func tempFile(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testMissingFileGivesDefaults() {
        let missing = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).json")
        XCTAssertEqual(BarConfig.load(from: missing), .default)
    }

    func testPartialFileMergesOverDefaults() throws {
        let url = try tempFile(#"{"side": "left", "widthPx": 10}"#)
        let config = BarConfig.load(from: url)
        XCTAssertEqual(config.side, "left")
        XCTAssertEqual(config.widthPx, 10)
        XCTAssertEqual(config.pollIntervalSeconds, BarConfig.default.pollIntervalSeconds)
        XCTAssertEqual(config.thresholds, BarConfig.default.thresholds)
    }

    func testInvalidValuesFallBackToDefaults() throws {
        let url = try tempFile(#"{"side": "top", "widthPx": -3, "pollIntervalSeconds": 1}"#)
        let config = BarConfig.load(from: url)
        XCTAssertEqual(config.side, "right")
        XCTAssertEqual(config.widthPx, 6)
        XCTAssertEqual(config.pollIntervalSeconds, 120)
    }

    func testMalformedJSONGivesDefaults() throws {
        let url = try tempFile("{oops")
        XCTAssertEqual(BarConfig.load(from: url), .default)
    }

    func testThresholdMappingIncludingBoundaries() {
        let config = BarConfig.default
        XCTAssertEqual(config.threshold(forPercent: 0).emoji, "😊")
        XCTAssertEqual(config.threshold(forPercent: 50).emoji, "😊")
        XCTAssertEqual(config.threshold(forPercent: 50.1).emoji, "😐")
        XCTAssertEqual(config.threshold(forPercent: 75).emoji, "😐")
        XCTAssertEqual(config.threshold(forPercent: 90).emoji, "😬")
        XCTAssertEqual(config.threshold(forPercent: 90.1).emoji, "🚨")
        XCTAssertEqual(config.threshold(forPercent: 100).emoji, "🚨")
        XCTAssertEqual(config.threshold(forPercent: 250).emoji, "🚨") // clamp above table
    }

    func testHexColorParsing() {
        let green = HexColor.rgb("#34C759")
        XCTAssertNotNil(green)
        XCTAssertEqual(green!.r, 0x34 / 255.0, accuracy: 0.001)
        XCTAssertEqual(green!.g, 0xC7 / 255.0, accuracy: 0.001)
        XCTAssertEqual(green!.b, 0x59 / 255.0, accuracy: 0.001)
        XCTAssertNil(HexColor.rgb("nope"))
        XCTAssertNotNil(HexColor.rgb("FF3B30")) // hash optional
    }
}
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `swift test 2>&1 | tail -5`
Expected: compile error — `BarConfig` not defined.

- [ ] **Step 3: Implement**

`Sources/ClaudeBarCore/BarConfig.swift`:
```swift
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
    public var thresholds: [Threshold]

    public static let `default` = BarConfig(
        side: "right",
        widthPx: 6,
        pollIntervalSeconds: 120,
        showEmoji: true,
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
        if let thresholds = partial.thresholds { config.thresholds = thresholds }
        config.sanitize()
        return config
    }

    private mutating func sanitize() {
        if side != "left" && side != "right" { side = Self.default.side }
        if !(widthPx > 0 && widthPx <= 40) { widthPx = Self.default.widthPx }
        if !(pollIntervalSeconds >= 30) { pollIntervalSeconds = Self.default.pollIntervalSeconds }
        if thresholds.isEmpty { thresholds = Self.default.thresholds }
        thresholds.sort { $0.upTo < $1.upTo }
    }

    public func threshold(forPercent percent: Double) -> Threshold {
        thresholds.first { percent <= $0.upTo } ?? thresholds.last!
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
```

- [ ] **Step 4: Run tests, verify pass**

Run: `swift test 2>&1 | tail -3`
Expected: all tests pass (4 decoder + 7 config).

- [ ] **Step 5: Commit and push**

```bash
git add -A && git commit -m "feat: config loader with defaults, sanitization, threshold/hex mapping" && git push
```

---

### Task 4: Bare overlay window (click-through strip)

**Files:**
- Create: `Sources/claudebar/OverlayWindow.swift`, `Sources/claudebar/AppDelegate.swift`
- Modify: `Sources/claudebar/main.swift`

**Interfaces:**
- Consumes: `BarConfig` from Task 3.
- Produces:
  - `final class OverlayWindow: NSWindow { init(config: BarConfig, screen: NSScreen) }` — borderless, transparent, `.statusBar` level, click-through, all Spaces; width `max(config.widthPx, 24)` hugging the configured edge, full screen height.
  - `final class AppDelegate: NSObject, NSApplicationDelegate { init(demo: Bool) }` — later tasks add the bar view and poller here.

- [ ] **Step 1: Implement**

`Sources/claudebar/OverlayWindow.swift`:
```swift
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
```

`Sources/claudebar/AppDelegate.swift`:
```swift
import AppKit
import ClaudeBarCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let demo: Bool
    private var window: OverlayWindow!

    init(demo: Bool) {
        self.demo = demo
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = BarConfig.load()
        guard let screen = NSScreen.main else {
            FileHandle.standardError.write(Data("claudebar: no screen available\n".utf8))
            NSApp.terminate(nil)
            return
        }
        window = OverlayWindow(config: config, screen: screen)
        // Temporary: solid strip to verify placement; BarView replaces this next task.
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.8).cgColor
        window.contentView = view
        window.orderFrontRegardless()
    }
}
```

Replace the last line of `Sources/claudebar/main.swift` (the `print(...)` fallthrough) with:
```swift
import AppKit  // add at top, alongside existing imports

let app = NSApplication.shared
let delegate = AppDelegate(demo: arguments.contains("--demo"))
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 2: Build and visually verify**

Run: `swift build && (.build/debug/claudebar & sleep 5; kill %1)`
Expected: a green strip appears on the right screen edge for 5 seconds, floats above windows, clicks pass through it.

- [ ] **Step 3: Commit and push**

```bash
git add -A && git commit -m "feat: click-through always-on-top overlay window on screen edge" && git push
```

---

### Task 5: BarView — proportional fill + threshold colors

**Files:**
- Create: `Sources/claudebar/BarView.swift`
- Modify: `Sources/claudebar/AppDelegate.swift`

**Interfaces:**
- Consumes: `BarConfig.threshold(forPercent:)`, `HexColor.rgb(_:)` from Task 3.
- Produces:
  - `enum DisplayState: Equatable { case usage(percent: Double), error }`
  - `final class BarView: NSView { init(config: BarConfig); func render(_ state: DisplayState) }` — animated fill; Task 6 adds the emoji, Task 8 implements `.error`.

- [ ] **Step 1: Implement**

`Sources/claudebar/BarView.swift`:
```swift
import AppKit
import ClaudeBarCore

enum DisplayState: Equatable {
    case usage(percent: Double)
    case error
}

final class BarView: NSView {
    private let config: BarConfig
    private let trackLayer = CALayer()
    private let fillLayer = CALayer()
    private var state: DisplayState = .usage(percent: 0)

    init(config: BarConfig) {
        self.config = config
        super.init(frame: .zero)
        wantsLayer = true
        trackLayer.backgroundColor = NSColor.gray.withAlphaComponent(0.15).cgColor
        layer?.addSublayer(trackLayer)
        layer?.addSublayer(fillLayer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        applyState(animated: false)
    }

    func render(_ state: DisplayState) {
        self.state = state
        applyState(animated: true)
    }

    private var barRect: (x: CGFloat, width: CGFloat) {
        let width = CGFloat(config.widthPx)
        let x = config.side == "left" ? 0 : bounds.width - width
        return (x, width)
    }

    private func applyState(animated: Bool) {
        let (barX, barWidth) = barRect
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.6 : 0)
        trackLayer.frame = CGRect(x: barX, y: 0, width: barWidth, height: bounds.height)

        switch state {
        case .usage(let percent):
            let clamped = min(max(percent, 0), 100)
            let threshold = config.threshold(forPercent: clamped)
            let rgb = HexColor.rgb(threshold.color) ?? (r: 1, g: 0, b: 0)
            fillLayer.backgroundColor = CGColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 0.9)
            let fillHeight = bounds.height * clamped / 100
            fillLayer.frame = CGRect(x: barX, y: 0, width: barWidth, height: fillHeight)
        case .error:
            break // Task 8
        }
        CATransaction.commit()
    }
}
```

Modify `AppDelegate.applicationDidFinishLaunching` — replace the temporary green `NSView` block with:
```swift
        let barView = BarView(config: config)
        window.contentView = barView
        self.barView = barView
        window.orderFrontRegardless()
        barView.render(.usage(percent: 63)) // temporary fixed value; poller arrives in Task 7
```
and add the property `private var barView: BarView!` to `AppDelegate`.

- [ ] **Step 2: Build and visually verify**

Run: `swift build && (.build/debug/claudebar & sleep 5; kill %1)`
Expected: bar fills ~63% from the bottom in yellow (63 → 😐 tier color `#FFCC00`), dim track above.

- [ ] **Step 3: Commit and push**

```bash
git add -A && git commit -m "feat: proportional fill bar with threshold colors" && git push
```

---

### Task 6: Emoji riding the fill line

**Files:**
- Modify: `Sources/claudebar/BarView.swift`

**Interfaces:**
- Consumes: `Threshold.emoji`, `BarConfig.showEmoji`.
- Produces: emoji label inside `BarView`, positioned at the fill line, hidden when `showEmoji` is false.

- [ ] **Step 1: Implement**

In `BarView`, add the field after `fillLayer`:
```swift
    private let emojiField = NSTextField(labelWithString: "")
```

In `init`, after the `addSublayer` calls:
```swift
        emojiField.font = .systemFont(ofSize: 13)
        emojiField.backgroundColor = .clear
        emojiField.isBezeled = false
        emojiField.alignment = .center
        addSubview(emojiField)
```

In `applyState`, inside `case .usage(let percent):` after the `fillLayer.frame = ...` line:
```swift
            emojiField.isHidden = !config.showEmoji
            if config.showEmoji {
                emojiField.stringValue = threshold.emoji
                positionEmoji(atFillHeight: fillHeight, barX: barX, barWidth: barWidth)
            }
```

Add the helper method:
```swift
    private func positionEmoji(atFillHeight fillHeight: CGFloat, barX: CGFloat, barWidth: CGFloat) {
        emojiField.sizeToFit()
        let size = emojiField.frame.size
        let y = min(max(fillHeight - size.height / 2, 0), bounds.height - size.height)
        let x = config.side == "left" ? barX + barWidth : barX - size.width
        emojiField.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
    }
```

- [ ] **Step 2: Build and visually verify**

Run: `swift build && (.build/debug/claudebar & sleep 5; kill %1)`
Expected: 😐 sits at the top edge of the 63% fill, just inside the bar.

- [ ] **Step 3: Commit and push**

```bash
git add -A && git commit -m "feat: emoji indicator riding the fill line" && git push
```

---

### Task 7: Polling loop (live data)

**Files:**
- Create: `Sources/claudebar/UsagePoller.swift`
- Modify: `Sources/claudebar/AppDelegate.swift`

**Interfaces:**
- Consumes: `UsageFetcher.fetch()` (Task 2), `DisplayState` (Task 5).
- Produces: `final class UsagePoller { init(intervalSeconds: TimeInterval, onUpdate: @escaping (DisplayState) -> Void); func start() }` — fetches immediately, then on a repeating timer; `onUpdate` always called on the main thread.

- [ ] **Step 1: Implement**

`Sources/claudebar/UsagePoller.swift`:
```swift
import Foundation
import ClaudeBarCore

final class UsagePoller {
    private let interval: TimeInterval
    private let onUpdate: (DisplayState) -> Void
    private let fetcher = UsageFetcher()
    private var timer: Timer?

    init(intervalSeconds: TimeInterval, onUpdate: @escaping (DisplayState) -> Void) {
        self.interval = intervalSeconds
        self.onUpdate = onUpdate
    }

    func start() {
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let result = self.fetcher.fetch()
            DispatchQueue.main.async {
                switch result {
                case .success(let snapshot):
                    self.onUpdate(.usage(percent: snapshot.percent))
                case .failure:
                    self.onUpdate(.error)
                }
            }
        }
    }
}
```

In `AppDelegate`: add `private var poller: UsagePoller?`, then replace the temporary `barView.render(.usage(percent: 63))` line with:
```swift
        poller = UsagePoller(intervalSeconds: config.pollIntervalSeconds) { [weak self] state in
            self?.barView.render(state)
        }
        poller?.start()
```

- [ ] **Step 2: Build and verify live data**

Run: `swift build && (.build/debug/claudebar & sleep 8; kill %1)`
Expected: bar animates from empty to your real current session percentage within a couple of seconds of launch.

- [ ] **Step 3: Commit and push**

```bash
git add -A && git commit -m "feat: live polling loop driving the bar" && git push
```

---

### Task 8: Error/stale state (gray + ⚠️)

**Files:**
- Modify: `Sources/claudebar/BarView.swift`

**Interfaces:**
- Consumes: `DisplayState.error` (already emitted by `UsagePoller` on any fetch failure).
- Produces: gray half-alpha full-height bar with centered ⚠️ when in error state.

- [ ] **Step 1: Implement**

In `BarView.applyState`, replace `case .error: break // Task 8` with:
```swift
        case .error:
            fillLayer.backgroundColor = NSColor.gray.withAlphaComponent(0.5).cgColor
            fillLayer.frame = CGRect(x: barX, y: 0, width: barWidth, height: bounds.height)
            emojiField.isHidden = false
            emojiField.stringValue = "⚠️"
            positionEmoji(atFillHeight: bounds.height / 2, barX: barX, barWidth: barWidth)
```

- [ ] **Step 2: Verify by forcing failure**

Run: `swift build && (.build/debug/claudebar --demo-error & sleep 4; kill %1)` — actually verify by temporarily
disabling network is unreliable; instead run with Wi-Fi off OR temporarily change the endpoint host in a scratch
build. Simplest deterministic check: run the app while passing a bogus keychain service is not injectable, so:
run `sudo ifconfig en0 down` is destructive — do NOT. Verification here: add a temporary line
`barView.render(.error)` after `poller?.start()` in AppDelegate, build, observe gray bar with ⚠️ centered,
then remove the line before committing.
Expected: full-height translucent gray bar with ⚠️ in the middle.

- [ ] **Step 3: Commit and push**

```bash
git add -A && git commit -m "feat: gray warning state on fetch failure" && git push
```

---

### Task 9: `--demo` mode

**Files:**
- Modify: `Sources/claudebar/AppDelegate.swift`

**Interfaces:**
- Consumes: `AppDelegate.demo` flag already parsed from `--demo` in `main.swift` (Task 4).
- Produces: demo animation sweeping 0→100→0 continuously, never touching the network.

- [ ] **Step 1: Implement**

In `AppDelegate`, add properties:
```swift
    private var demoTimer: Timer?
    private var demoPercent: Double = 0
    private var demoRising = true
```

In `applicationDidFinishLaunching`, wrap the poller block:
```swift
        if demo {
            demoTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.demoPercent += self.demoRising ? 1 : -1
                if self.demoPercent >= 100 { self.demoRising = false }
                if self.demoPercent <= 0 { self.demoRising = true }
                self.barView.render(.usage(percent: self.demoPercent))
            }
        } else {
            poller = UsagePoller(intervalSeconds: config.pollIntervalSeconds) { [weak self] state in
                self?.barView.render(state)
            }
            poller?.start()
        }
```

- [ ] **Step 2: Build and visually verify**

Run: `swift build && (.build/debug/claudebar --demo & sleep 10; kill %1)`
Expected: bar sweeps 0→100 and back, passing green → yellow → orange → red, emoji changing 😊→😐→😬→🚨 at 50/75/90.

- [ ] **Step 3: Commit and push**

```bash
git add -A && git commit -m "feat: --demo mode sweeping the full usage range" && git push
```

---

### Task 10: Makefile + launchd install

**Files:**
- Create: `Makefile`, `resources/com.arukurmi.claudebar.plist`

**Interfaces:**
- Produces: `make build|test|install|uninstall|demo` targets; launchd agent `com.arukurmi.claudebar` running `~/.local/bin/claudebar` at login with keep-alive.

- [ ] **Step 1: Implement**

`resources/com.arukurmi.claudebar.plist` (`__BIN__` replaced at install time):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.arukurmi.claudebar</string>
    <key>ProgramArguments</key>
    <array>
        <string>__BIN__</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
```

`Makefile`:
```make
PREFIX  ?= $(HOME)/.local
BIN      = $(PREFIX)/bin/claudebar
PLIST    = $(HOME)/Library/LaunchAgents/com.arukurmi.claudebar.plist
LABEL    = com.arukurmi.claudebar
UID     := $(shell id -u)

.PHONY: build test demo install uninstall

build:
	swift build -c release

test:
	swift test

demo: build
	.build/release/claudebar --demo

install: build
	mkdir -p $(PREFIX)/bin $(HOME)/Library/LaunchAgents
	cp .build/release/claudebar $(BIN)
	sed 's|__BIN__|$(BIN)|' resources/$(LABEL).plist > $(PLIST)
	-launchctl bootout gui/$(UID)/$(LABEL) 2>/dev/null
	launchctl bootstrap gui/$(UID) $(PLIST)
	@echo "claudebar installed and running (starts at login)."

uninstall:
	-launchctl bootout gui/$(UID)/$(LABEL) 2>/dev/null
	rm -f $(PLIST) $(BIN)
	@echo "claudebar uninstalled."
```

- [ ] **Step 2: Verify install cycle**

Run: `make install && sleep 4 && launchctl print gui/$(id -u)/com.arukurmi.claudebar | grep state`
Expected: `state = running`, bar visible with live data.

Run: `make uninstall`
Expected: bar disappears, plist and binary removed. Then `make install` again to leave it running for the user.

- [ ] **Step 3: Commit and push**

```bash
git add -A && git commit -m "feat: Makefile with launchd install/uninstall" && git push
```

---

### Task 11: Colorful README + polish

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: everything shipped in Tasks 1–10 (documents actual behavior — verify claims against the code).

- [ ] **Step 1: Write the full README**

Replace `README.md` with a colorful, complete document containing these sections (write real content for each, matching actual behavior):
- Title with emoji + one-line pitch
- Shields.io badges: `![Swift](https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift&logoColor=white)` `![Platform](https://img.shields.io/badge/macOS-13+-000000?logo=apple)` `![Deps](https://img.shields.io/badge/dependencies-0-brightgreen)` `![License](https://img.shields.io/badge/license-MIT-blue)`
- "Why" paragraph (the checking-usage-is-annoying story)
- ASCII diagram of the bar (reuse the design-spec mockup)
- Emoji/color threshold table (😊 <50 green, 😐 ≤75 yellow, 😬 ≤90 orange, 🚨 >90 red, ⚠️ error gray)
- Install: `git clone` → `make install`; note first-run Keychain permission prompt (click "Always Allow")
- Configuration: full `config.json` example from the spec + per-key table
- How it works: 3-step diagram (Keychain token → OAuth usage endpoint → AppKit overlay), notes it's the same credential the `claude` CLI uses and an undocumented endpoint
- CLI flags table: `--once`, `--demo`
- Uninstall: `make uninstall`

Also add an MIT `LICENSE` file (Copyright 2026 Aryansh Kurmi) so the badge is honest.

- [ ] **Step 2: Verify claims**

Run: `make test && .build/release/claudebar --once`
Expected: tests pass, live percent prints — confirming what the README claims.

- [ ] **Step 3: Commit and push**

```bash
git add -A && git commit -m "docs: full README with badges, config reference, and install guide" && git push
```
