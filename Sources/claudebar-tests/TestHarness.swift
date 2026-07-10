// Minimal test harness: Command Line Tools ship neither XCTest nor Swift Testing,
// so tests run as a plain executable — `swift run claudebar-tests` exits non-zero on failure.

import Foundation

var testFailures = 0
var testCount = 0

func expect(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    testCount += 1
    if !condition {
        testFailures += 1
        let fileName = file.split(separator: "/").last.map(String.init) ?? file
        print("  ❌ \(fileName):\(line) — \(message)")
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "",
                               file: String = #file, line: Int = #line) {
    expect(actual == expected, "\(message) expected \(expected), got \(actual)",
           file: file, line: line)
}

func finishTests() -> Never {
    if testFailures == 0 {
        print("✅ all \(testCount) assertions passed")
        exit(0)
    } else {
        print("❌ \(testFailures) of \(testCount) assertions failed")
        exit(1)
    }
}
