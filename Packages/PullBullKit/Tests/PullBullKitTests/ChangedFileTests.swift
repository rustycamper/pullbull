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
}
