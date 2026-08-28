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
        // No `limits` array in this older payload — the two named windows still
        // have to reach the rail, or it renders empty.
        expectEqual(snapshot.limits.count, 2, "windows synthesized without a limits array")
        expectEqual(snapshot.limits.first?.kind, "session", "synthesized session kind")
        expectEqual(snapshot.limits.last?.kind, "weekly_all", "synthesized weekly kind")
        expectEqual(snapshot.limits.last?.percent, 14.0, "synthesized weekly percent")
    case .failure(let error):
        expect(false, "real payload should decode, got \(error)")
    }

    // Current payload: the server names every limit itself.
    let withLimits = """
    {"five_hour": {"utilization": 24.0, "resets_at": "2026-08-28T13:20:00.453063+00:00"},
     "seven_day": {"utilization": 27.0, "resets_at": "2026-08-29T16:00:00.453086+00:00"},
     "limits": [
       {"kind": "session", "group": "session", "percent": 24,
        "resets_at": "2026-08-28T13:20:00.453063+00:00"},
       {"kind": "weekly_all", "group": "weekly", "percent": 27,
        "resets_at": "2026-08-29T16:00:00.453086+00:00"},
       {"kind": "weekly_opus", "group": "weekly", "percent": 61, "resets_at": null}
     ]}
    """.data(using: .utf8)!
    switch UsageDecoder.decode(withLimits) {
    case .success(let snapshot):
        expectEqual(snapshot.percent, 24.0, "headline percent still comes from five_hour")
        expectEqual(snapshot.limits.count, 3, "every limit is kept")
        expectEqual(snapshot.limits.map(\.kind), ["session", "weekly_all", "weekly_opus"],
                    "server ordering is preserved")
        expectEqual(snapshot.limits[2].percent, 61, "third limit percent")
        expect(snapshot.limits[2].resetsAt == nil, "null resets_at is nil, not a crash")
    case .failure(let error):
        expect(false, "limits payload should decode, got \(error)")
    }

    // A limit missing its percent is dropped rather than rendering as 0%.
    let partialLimits = """
    {"five_hour": {"utilization": 5.0},
     "limits": [{"kind": "session", "percent": 5}, {"kind": "mystery"}]}
    """.data(using: .utf8)!
    switch UsageDecoder.decode(partialLimits) {
    case .success(let snapshot):
        expectEqual(snapshot.limits.count, 1, "limit without a percent is dropped")
    case .failure(let error):
        expect(false, "partial limits should decode, got \(error)")
    }

    // An empty limits array must not blank the rail.
    let emptyLimits = #"{"five_hour": {"utilization": 9.0}, "limits": []}"#.data(using: .utf8)!
    switch UsageDecoder.decode(emptyLimits) {
    case .success(let snapshot):
        expectEqual(snapshot.limits.count, 1, "empty limits array falls back to five_hour")
    case .failure(let error):
        expect(false, "empty limits should decode, got \(error)")
    }

    expectEqual(UsageLimit(kind: "session", percent: 0, resetsAt: nil).title,
                "Current session", "session title")
    expectEqual(UsageLimit(kind: "weekly_all", percent: 0, resetsAt: nil).title,
                "All models", "weekly_all title")
    expectEqual(UsageLimit(kind: "weekly_cowork", percent: 0, resetsAt: nil).title,
                "Weekly cowork", "unknown kind is humanized, not dropped")

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

    expectEqual(RetryAfter.seconds(from: "120"), 120, "plain-seconds Retry-After")
    expectEqual(RetryAfter.seconds(from: "  30 "), 30, "whitespace is trimmed")
    expect(RetryAfter.seconds(from: nil) == nil, "missing header is nil")
    expect(RetryAfter.seconds(from: "0") == nil, "non-positive delay is ignored")
    expect(RetryAfter.seconds(from: "-5") == nil, "negative delay is ignored")
    expect(RetryAfter.seconds(from: "Wed, 21 Oct 2026 07:28:00 GMT") == nil,
           "HTTP-date form is not treated as seconds")
}
