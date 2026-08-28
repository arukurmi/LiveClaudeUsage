import Foundation

public enum FetchError: Error, Equatable {
    case tokenUnavailable
    case network(String)
    case badStatus(Int)
    /// 429/529 from the server. `retryAfter`, when present, is the number of
    /// seconds the server asked us to wait before trying again.
    case rateLimited(retryAfter: TimeInterval?)
    case decodeFailed
}

public enum RetryAfter {
    /// Parse an HTTP `Retry-After` header value. The spec allows either a
    /// delta in whole seconds ("120") or an HTTP date; Anthropic sends the
    /// former, so we honor seconds and ignore anything non-positive or unparsable.
    public static func seconds(from header: String?) -> TimeInterval? {
        guard let raw = header?.trimmingCharacters(in: .whitespaces),
              let value = TimeInterval(raw), value > 0 else { return nil }
        return value
    }
}

public enum UsageDecoder {
    private struct Payload: Decodable {
        struct Window: Decodable {
            let utilization: Double
            let resets_at: String?
        }
        struct Limit: Decodable {
            let kind: String?
            let percent: Double?
            let resets_at: String?
        }
        let five_hour: Window
        let seven_day: Window?
        let limits: [Limit]?
    }

    public static func decode(_ data: Data) -> Result<UsageSnapshot, FetchError> {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return .failure(.decodeFailed)
        }
        return .success(UsageSnapshot(
            percent: payload.five_hour.utilization,
            resetsAt: payload.five_hour.resets_at.flatMap(parseISO8601),
            limits: limits(from: payload)))
    }

    /// The server's own array is the source of truth. Older responses without
    /// it still carry the two windows we can name ourselves, so fall back to
    /// those rather than handing the UI nothing to draw. A limit missing its
    /// kind or percentage is dropped rather than rendered as an unnamed 0%.
    private static func limits(from payload: Payload) -> [UsageLimit] {
        if let limits = payload.limits, !limits.isEmpty {
            let mapped = limits.compactMap { limit -> UsageLimit? in
                guard let kind = limit.kind, let percent = limit.percent else { return nil }
                return UsageLimit(kind: kind,
                                  percent: percent,
                                  resetsAt: limit.resets_at.flatMap(parseISO8601))
            }
            if !mapped.isEmpty { return mapped }
        }
        var fallback = [UsageLimit(kind: "session",
                                   percent: payload.five_hour.utilization,
                                   resetsAt: payload.five_hour.resets_at.flatMap(parseISO8601))]
        if let weekly = payload.seven_day {
            fallback.append(UsageLimit(kind: "weekly_all",
                                       percent: weekly.utilization,
                                       resetsAt: weekly.resets_at.flatMap(parseISO8601)))
        }
        return fallback
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

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { throw FetchError.tokenUnavailable }
        // A locked keychain can make `security` block on a GUI unlock prompt
        // indefinitely; without a bound that stalls the whole poll loop. Give it
        // 10s, then kill it and report the token as unavailable. Read stdout
        // only after exit — the output is tiny, so the pipe buffer never fills.
        if exited.wait(timeout: .now() + 10) == .timedOut {
            process.terminate()
            throw FetchError.tokenUnavailable
        }
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

    /// A session that keeps nothing on disk: the usage request carries a bearer
    /// token and the response echoes account state, neither of which belong in
    /// the shared URL cache or cookie jar. Ephemeral config holds all of that in
    /// memory and drops it when the process exits.
    public static func makePrivateSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }

    public init(tokenProvider: TokenProvider = KeychainCLITokenProvider(),
                session: URLSession? = nil) {
        self.tokenProvider = tokenProvider
        self.session = session ?? UsageFetcher.makePrivateSession()
    }

    /// Synchronous; call off the main thread.
    public func fetch() -> Result<UsageSnapshot, FetchError> {
        guard let token = try? tokenProvider.accessToken() else {
            return .failure(.tokenUnavailable)
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        // A response that hasn't arrived in 15s isn't coming; without this the
        // session default (60s between bytes) can stretch a dead request for minutes.
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox()
        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                box.set(.failure(.network(error.localizedDescription)))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                box.set(.failure(.network("not an HTTP response")))
                return
            }
            if http.statusCode == 429 || http.statusCode == 529 {
                let retryAfter = RetryAfter.seconds(
                    from: http.value(forHTTPHeaderField: "Retry-After"))
                box.set(.failure(.rateLimited(retryAfter: retryAfter)))
                return
            }
            guard http.statusCode == 200 else {
                box.set(.failure(.badStatus(http.statusCode)))
                return
            }
            guard let data else {
                box.set(.failure(.decodeFailed))
                return
            }
            box.set(UsageDecoder.decode(data))
        }
        task.resume()
        // The request timeout should fire the callback well before this, but a
        // callback that never arrives must not freeze the poll loop forever.
        if semaphore.wait(timeout: .now() + 30) == .timedOut {
            task.cancel()
            return .failure(.network("request hung"))
        }
        return box.get()
    }
}

/// Lock-guarded result cell: the data-task callback may still fire after a
/// timed-out `fetch` has returned, so the two must not race on a plain var.
private final class ResultBox {
    private let lock = NSLock()
    private var value: Result<UsageSnapshot, FetchError> = .failure(.network("no response"))

    func set(_ newValue: Result<UsageSnapshot, FetchError>) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Result<UsageSnapshot, FetchError> {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
