// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "claudebar",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ClaudeBarCore"),
        .executableTarget(name: "claudebar", dependencies: ["ClaudeBarCore"]),
        // CLT-only environment (no Xcode): tests are a plain executable, run via `swift run claudebar-tests`.
        .executableTarget(name: "claudebar-tests", dependencies: ["ClaudeBarCore"]),
    ]
)
