import CryptoKit
import Foundation
import Testing
@testable import PullBullKit

@Suite struct ChangedFileTests {
    private func file(_ path: String) -> ChangedFile { ChangedFile(path: path, additions: 0, deletions: 0) }

    @Test func splitsNameFromDirectory() {
        let nested = file("PullBull/Style/Metrics.swift")
        #expect(nested.fileName == "Metrics.swift")
        #expect(nested.directory == "PullBull/Style")
    }

    @Test func rootFileHasNoDirectory() {
        #expect(file("README.md").fileName == "README.md")
        #expect(file("README.md").directory == "")
    }

    @Test func dotfilesAndSpacesStayInTheName() {
        #expect(file(".github/workflows/ci.yml").fileName == "ci.yml")
        #expect(file(".github/workflows/ci.yml").directory == ".github/workflows")
        #expect(file("docs/My Notes.md").fileName == "My Notes.md")
    }

    @Test func leadingSlashLeavesAnEmptyDirectoryAndTheName() {
        #expect(file("/a.txt").directory == "")
        #expect(file("/a.txt").fileName == "a.txt")
    }

    @Test func diffURLAnchorsOnTheSha256OfThePath() {
        let pr = URL(string: "https://github.com/acme/web/pull/412")!
        #expect(file("README.md").diffURL(in: pr).absoluteString
            == "https://github.com/acme/web/pull/412/files#diff-b335630551682c19a781afebcf4d07bf978fb1f8ac04c6bf87428ed5106870f5")
    }

    @Test func diffURLKeepsTheEnterpriseHost() {
        let pr = URL(string: "https://ghe.example.com/acme/web/pull/7")!
        let url = file("README.md").diffURL(in: pr)
        #expect(url.host == "ghe.example.com")
        #expect(url.path == "/acme/web/pull/7/files")
    }

    @Test func diffURLHashesRawUTF8NotAPercentEncodedPath() {
        let pr = URL(string: "https://github.com/acme/web/pull/1")!
        let spaced = file("docs/My Notes.md").diffURL(in: pr).fragment
        let accented = file("docs/café.md").diffURL(in: pr).fragment
        #expect(spaced == "diff-" + sha256Hex("docs/My Notes.md"))
        #expect(accented == "diff-" + sha256Hex("docs/café.md"))
        #expect(spaced != "diff-" + sha256Hex("docs/My%20Notes.md"))
    }
}

private func sha256Hex(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
}
