import Foundation
import Testing
@testable import PullBullKit

struct AskRetrievalTests {
    struct Fixture: Decodable {
        struct Question: Decodable {
            let q: String
            let want: [String]
        }
        let items: [AskItem]
        let questions: [Question]
    }

    static func load() throws -> Fixture {
        let url = try #require(Bundle.module.url(forResource: "ask-fixture", withExtension: "json", subdirectory: "Fixtures"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Fixture.self, from: Data(contentsOf: url))
    }

    @Test func fixtureQuestionsFindWantedInTop20() async throws {
        let fixture = try Self.load()
        #expect(fixture.items.count >= 50)
        #expect(fixture.questions.count == 10)
        let index = try AskIndex(fileURL: AskIndexTests.tempURL())
        try await index.upsert(fixture.items)
        for question in fixture.questions {
            let found = try await index.search(question.q, limit: 20, excluding: [], repo: nil).map(\.key.askKey)
            #expect(question.want.contains { found.contains($0) }, "\(question.q) -> \(found)")
        }
    }
}
