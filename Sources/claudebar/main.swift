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
