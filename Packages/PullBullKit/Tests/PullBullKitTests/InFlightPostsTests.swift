import Foundation
import Testing
@testable import PullBullKit

private let k7 = PRKey(repo: "acme/widgets", number: 7)
private let k8 = PRKey(repo: "acme/widgets", number: 8)

@Suite struct InFlightPostsTests {
    @Test func insertedPostIsInFlightUntilRemoved() {
        var posts = InFlightPosts()
        #expect(!posts.contains(account: "pb", key: k7))
        posts.insert(account: "pb", key: k7)
        #expect(posts.contains(account: "pb", key: k7))
        #expect(!posts.contains(account: "pb", key: k8))
        #expect(!posts.contains(account: "work", key: k7))
        posts.remove(account: "pb", key: k7)
        #expect(!posts.contains(account: "pb", key: k7))
        #expect(posts == InFlightPosts())
    }

    @Test func accountIgnoresCase() {
        var posts = InFlightPosts()
        posts.insert(account: "PBojkov", key: k7)
        #expect(posts.contains(account: "pbojkov", key: k7))
        posts.remove(account: "pbOJKOV", key: k7)
        #expect(!posts.contains(account: "PBojkov", key: k7))
    }
}
