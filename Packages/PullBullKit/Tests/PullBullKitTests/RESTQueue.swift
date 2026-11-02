import Foundation
import Testing
@testable import PullBullKit

/// Answers each REST request in turn with a status and a JSON body, or a thrown error, and records what was sent.
final class RESTQueue: GraphQLTransport, @unchecked Sendable {
    struct Sent { let method: String; let path: String; let body: [String: Any] }

    private enum Answer {
        case response(Int, String)
        case failure(any Error)
    }

    private let lock = NSLock()
    private var queue: [Answer]
    private var log: [Sent] = []

    init(_ answers: [(Int, String)]) { queue = answers.map { .response($0.0, $0.1) } }

    /// A transport whose one answer is `error`.
    init(failing error: any Error) { queue = [.failure(error)] }

    var sent: [Sent] { lock.withLock { log } }

    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        Issue.record("GraphQL request sent")
        throw APIError.server(500)
    }

    func send(_ method: String, path: String, body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        let answer = lock.withLock {
            log.append(Sent(
                method: method, path: path,
                body: (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]))
            return queue.removeFirst()
        }
        switch answer {
        case .failure(let error):
            throw error
        case .response(let status, let json):
            let response = HTTPURLResponse(
                url: URL(string: "https://api.github.com\(path)")!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(json.utf8), response)
        }
    }
}
