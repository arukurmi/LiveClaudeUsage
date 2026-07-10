import AppKit
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

let app = NSApplication.shared
let delegate = AppDelegate(demo: arguments.contains("--demo"))
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
