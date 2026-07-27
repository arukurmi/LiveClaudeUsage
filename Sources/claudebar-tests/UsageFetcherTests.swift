import Foundation
import ClaudeBarCore

/// Canned-response URLProtocol so UsageFetcher's HTTP handling can be exercised
/// without touching the network. Each test sets `handler` to decide the reply.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError:
                NSError(domain: "mock", code: 0))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

private struct StubToken: TokenProvider {
    let token: String?
    func accessToken() throws -> String {
        guard let token else { throw FetchError.tokenUnavailable }
        return token
    }
}

private func mockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

private func respond(status: Int, body: String = "", headers: [String: String] = [:]) {
    MockURLProtocol.handler = { request in
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: "HTTP/1.1", headerFields: headers)!
        return (response, Data(body.utf8))
    }
}

func runUsageFetcherTests() {
    print("- UsageFetcher")

    // Missing token short-circuits before any request.
    let noToken = UsageFetcher(tokenProvider: StubToken(token: nil), session: mockSession())
    expectEqual(noToken.fetch(), .failure(.tokenUnavailable), "no token → tokenUnavailable")

    let fetcher = UsageFetcher(tokenProvider: StubToken(token: "sk-ant-oat01-x"),
                               session: mockSession())

    // 200 with a valid body decodes into a snapshot.
    respond(status: 200, body: #"{"five_hour": {"utilization": 42.0}}"#)
    switch fetcher.fetch() {
    case .success(let snapshot): expectEqual(snapshot.percent, 42.0, "200 decodes percent")
    case .failure(let error): expect(false, "200 should succeed, got \(error)")
    }

    // 429 with Retry-After surfaces as rateLimited carrying the delay.
    respond(status: 429, headers: ["Retry-After": "120"])
    expectEqual(fetcher.fetch(), .failure(.rateLimited(retryAfter: 120)),
                "429 → rateLimited with Retry-After")

    // 529 (overloaded) is also rate-limited; no header means nil delay.
    respond(status: 529)
    expectEqual(fetcher.fetch(), .failure(.rateLimited(retryAfter: nil)),
                "529 → rateLimited without Retry-After")

    // Other non-200s stay a generic bad status.
    respond(status: 500)
    expectEqual(fetcher.fetch(), .failure(.badStatus(500)), "500 → badStatus")

    // 200 with a body that isn't the expected shape fails to decode.
    respond(status: 200, body: "not json")
    expectEqual(fetcher.fetch(), .failure(.decodeFailed), "200 garbage → decodeFailed")
}
