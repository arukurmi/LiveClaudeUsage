import Foundation
import ClaudeBarCore

func runUsageDecoderTests() {
    // Trimmed real payload captured from the endpoint on 2026-07-10.
    let realPayload = """
    {"five_hour": {"utilization": 29.0, "resets_at": "2026-07-10T14:49:59.820872+00:00",
     "limit_dollars": null}, "seven_day": {"utilization": 14.0,
     "resets_at": "2026-07-11T15:59:59.820891+00:00"}, "extra_usage": {"is_enabled": false}}
    """.data(using: .utf8)!

    switch UsageDecoder.decode(realPayload) {
    case .success(let snapshot):
        expectEqual(snapshot.percent, 29.0, "real payload percent")
        expect(snapshot.resetsAt != nil, "real payload resetsAt parses")
    case .failure(let error):
        expect(false, "real payload should decode, got \(error)")
    }

    let noReset = #"{"five_hour": {"utilization": 88.5}}"#.data(using: .utf8)!
    switch UsageDecoder.decode(noReset) {
    case .success(let snapshot):
        expectEqual(snapshot.percent, 88.5, "percent without resets_at")
        expect(snapshot.resetsAt == nil, "missing resets_at is nil")
    case .failure(let error):
        expect(false, "payload without resets_at should decode, got \(error)")
    }

    expectEqual(UsageDecoder.decode(Data("not json".utf8)), .failure(.decodeFailed),
                "garbage input")

    let keychainJSON = #"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-abc","refreshToken":"r"}}"#
    expectEqual(UsageDecoder.extractToken(fromKeychainJSON: Data(keychainJSON.utf8)),
                "sk-ant-oat01-abc", "token extraction")
    expect(UsageDecoder.extractToken(fromKeychainJSON: Data("{}".utf8)) == nil,
           "empty keychain JSON gives nil token")
}
