import Foundation
import Testing
@testable import PullBullKit

struct RecordedRequest: Sendable {
    let url: URL
    let method: String
    let headers: [String: String]
    let form: [String: String]
}

/// Scripted stand-in for github.com's OAuth endpoints. Refresh requests are answered from
/// `validRefreshTokens`, which rotate on use the way GitHub's do.
actor FakeGitHubOAuth: HTTPTransport {
    private var scripts: [String: [(status: Int, json: String)]] = [:]
    private var validRefreshTokens: Set<String>
    private var failure: URLError?
    private var issued = 0
    private(set) var requests: [RecordedRequest] = []

    init(validRefreshTokens: Set<String> = []) {
        self.validRefreshTokens = validRefreshTokens
    }

    func script(_ path: String, _ responses: [(status: Int, json: String)]) {
        scripts[path] = responses
    }

    func failNext(_ error: URLError) {
        failure = error
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = try #require(request.url)
        let form = Self.parse(request.httpBody)
        requests.append(
            RecordedRequest(
                url: url, method: request.httpMethod ?? "GET",
                headers: request.allHTTPHeaderFields ?? [:], form: form))
        if let failure {
            self.failure = nil
            throw failure
        }
        if form["grant_type"] == "refresh_token" {
            if let token = form["refresh_token"], validRefreshTokens.remove(token) != nil {
                issued += 1
                validRefreshTokens.insert("ghr_rotated\(issued)")
                return reply(
                    200,
                    """
                    {"access_token":"ghu_rotated\(issued)","expires_in":28800,\
                    "refresh_token":"ghr_rotated\(issued)","refresh_token_expires_in":15897600,\
                    "token_type":"bearer","scope":""}
                    """, url: url)
            }
            // A scripted reply stands in for GitHub's other answers to a dead token.
            if scripts[url.path]?.isEmpty ?? true {
                return reply(200, #"{"error":"bad_refresh_token"}"#, url: url)
            }
        }
        guard var queue = scripts[url.path], !queue.isEmpty else {
            return reply(404, "{}", url: url)
        }
        let next = queue.removeFirst()
        scripts[url.path] = queue
        return reply(next.status, next.json, url: url)
    }

    private func reply(_ status: Int, _ json: String, url: URL) -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(json.utf8), response)
    }

    private static func parse(_ body: Data?) -> [String: String] {
        guard let body, let text = String(data: body, encoding: .utf8) else { return [:] }
        var components = URLComponents()
        components.percentEncodedQuery = text
        return Dictionary(
            (components.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { _, last in last })
    }
}
