import Foundation
import Testing
@testable import PullBullKit

@Suite struct InstallLocationTests {
    private let home = URL(fileURLWithPath: "/Users/devon", isDirectory: true)

    private func installed(_ path: String) -> Bool {
        InstallLocation.isInstalled(bundleURL: URL(fileURLWithPath: path), homeDirectory: home)
    }

    @Test func applicationsCounts() {
        #expect(installed("/Applications/PullBull.app"))
    }

    @Test func userApplicationsCounts() {
        #expect(installed("/Users/devon/Applications/PullBull.app"))
    }

    @Test func anotherUsersApplicationsDoesNotCount() {
        #expect(!installed("/Users/someone/Applications/PullBull.app"))
    }

    @Test func aSubfolderOfApplicationsDoesNotCount() {
        #expect(!installed("/Applications/Tools/PullBull.app"))
        #expect(!installed("/Users/devon/Applications/Tools/PullBull.app"))
    }

    @Test func applicationsItselfDoesNotCount() {
        #expect(!installed("/Applications"))
    }

    @Test func derivedDataDoesNotCount() {
        #expect(!installed(
            "/Users/devon/Library/Developer/Xcode/DerivedData/PullBull-abc/Build/Products/Debug/PullBull.app"))
        #expect(!installed("/Users/devon/src/pullbull/build/Build/Products/Release/PullBull.app"))
    }

    @Test func aWorktreeBuildDoesNotCount() {
        #expect(!installed(
            "/Users/devon/src/pullbull/.claude/worktrees/agent-1/build/Build/Products/Release/PullBull.app"))
    }

    @Test func downloadsDoesNotCount() {
        #expect(!installed("/Users/devon/Downloads/PullBull.app"))
    }

    @Test func aTranslocatedCopyDoesNotCount() {
        #expect(!installed("/private/var/folders/xy/abc123/T/AppTranslocation/1A2B-3C4D/d/PullBull.app"))
    }

    @Test func aTrailingSlashDoesNotMatter() {
        #expect(installed("/Applications/PullBull.app/"))
        #expect(InstallLocation.isInstalled(
            bundleURL: URL(fileURLWithPath: "/Users/devon/Applications/PullBull.app/", isDirectory: true),
            homeDirectory: URL(fileURLWithPath: "/Users/devon/")))
    }

    @Test func folderCaseDoesNotMatter() {
        #expect(installed("/applications/PullBull.app"))
        #expect(installed("/Users/Devon/APPLICATIONS/PullBull.app"))
    }

    @Test func dotSegmentsAreResolved() {
        #expect(installed("/Applications/Tools/../PullBull.app"))
        #expect(!installed("/Applications/../Users/devon/Downloads/PullBull.app"))
    }

    @Test func aSymlinkIntoApplicationsCounts() throws {
        try withTemporaryHome { home, root in
            let app = home.appendingPathComponent("Applications/PullBull.app")
            try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
            let link = root.appendingPathComponent("PullBull.app")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: app)
            #expect(InstallLocation.isInstalled(bundleURL: link, homeDirectory: home))
        }
    }

    @Test func aSymlinkInApplicationsToABuildDoesNotCount() throws {
        try withTemporaryHome { home, root in
            let build = root.appendingPathComponent("DerivedData/PullBull.app")
            try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
            let applications = home.appendingPathComponent("Applications")
            try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
            let link = applications.appendingPathComponent("PullBull.app")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: build)
            #expect(!InstallLocation.isInstalled(bundleURL: link, homeDirectory: home))
        }
    }

    @Test func aSymlinkedHomeStillMatches() throws {
        try withTemporaryHome { home, root in
            let app = home.appendingPathComponent("Applications/PullBull.app")
            try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
            let linkedHome = root.appendingPathComponent("linked-home")
            try FileManager.default.createSymbolicLink(at: linkedHome, withDestinationURL: home)
            #expect(InstallLocation.isInstalled(bundleURL: app, homeDirectory: linkedHome))
            #expect(InstallLocation.isInstalled(
                bundleURL: linkedHome.appendingPathComponent("Applications/PullBull.app"), homeDirectory: home))
        }
    }

    /// A scratch root holding a fake home, removed afterwards; the temporary folder itself sits behind
    /// the `/var` → `/private/var` symlink.
    private func withTemporaryHome(_ body: (_ home: URL, _ root: URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstallLocationTests-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(home, root)
    }
}
