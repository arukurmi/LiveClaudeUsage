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
