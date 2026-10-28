import Foundation
import Testing
@testable import PullBullKit

@Suite struct StatusTooltipTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let interval = Duration.seconds(300)

    func ok(ago seconds: TimeInterval = 180, refreshing: Bool = false) -> RefreshStatus {
        RefreshStatus(lastSuccess: now.addingTimeInterval(-seconds), error: nil, isRefreshing: refreshing)
    }

    func text(_ prs: Int, issues: Int = 0, source: BadgeSource = .review, countsIssues: Bool = false,
              status: RefreshStatus? = nil, issuesIncomplete: Bool = false) -> String {
        StatusTooltip.text(parts: BadgeParts(prs: prs, issues: issues), source: source, countsIssues: countsIssues,
                           status: status ?? ok(), staleAfter: interval, now: now, issuesIncomplete: issuesIncomplete)
    }

    @Test func reviewCountSingularAndPlural() {
        #expect(text(2) == "2 to review · 3m ago")
        #expect(text(1) == "1 to review · 3m ago")
    }

    @Test func zeroAndJustNow() {
        #expect(text(0, status: ok(ago: 5)) == "Nothing to review · just now")
    }

    @Test func mineSingularPluralZero() {
        #expect(text(1, source: .mine) == "1 PR of yours · 3m ago")
        #expect(text(3, source: .mine) == "3 PRs of yours · 3m ago")
        #expect(text(0, source: .mine) == "No PRs of yours · 3m ago")
    }

    @Test func combinedSources() {
        #expect(text(3, source: .reviewAndMine) == "3: review + mine · 3m ago")
        #expect(text(5, source: .all) == "5: review + mine + team · 3m ago")
        #expect(text(4, issues: 1, source: .reviewAndMine, countsIssues: true)
            == "5: review + mine + issues · 3m ago")
    }

    @Test func assignedIssues() {
        #expect(text(1, issues: 4, countsIssues: true) == "1 to review, 4 issues · 3m ago")
        #expect(text(2, issues: 1, countsIssues: true) == "2 to review, 1 issue · 3m ago")
        #expect(text(0, issues: 2, countsIssues: true) == "0 to review, 2 issues · 3m ago")
        #expect(text(0, issues: 0, countsIssues: true) == "Nothing to review · 3m ago")
    }

    @Test func refreshing() {
        #expect(text(2, status: ok(refreshing: true)) == "2 to review · refreshing…")
        let first = RefreshStatus(lastSuccess: nil, error: nil, isRefreshing: true)
        #expect(text(0, status: first) == "Refreshing…")
    }

    @Test func staleCount() {
        #expect(text(2, status: ok(ago: 12 * 60)) == "2 to review · stale, 12m ago")
        #expect(text(2, status: ok(ago: 3 * 3600)) == "2 to review · stale, 3h ago")
    }

    @Test func incompleteIssues() {
        #expect(text(1, issues: 2, countsIssues: true, issuesIncomplete: true)
            == "1 to review, 2 issues · issues didn't update")
        #expect(text(1, status: ok(ago: 12 * 60), issuesIncomplete: true) == "1 to review · stale, 12m ago")
    }

    @Test func offline() {
        let status = RefreshStatus(lastSuccess: now.addingTimeInterval(-720), error: .offline, isRefreshing: false)
        #expect(text(2, status: status) == "Offline · 12m ago")
        let never = RefreshStatus(lastSuccess: nil, error: .offline, isRefreshing: false)
        #expect(text(0, status: never) == "Offline")
    }

    @Test func rateLimitedAndOtherErrors() {
        let limited = RefreshStatus(lastSuccess: now, error: .rateLimited(nil), isRefreshing: false)
        #expect(text(2, status: limited) == "Rate limited")
        let at = RefreshStatus(lastSuccess: now, error: .rateLimited(now.addingTimeInterval(600)), isRefreshing: false)
        #expect(text(2, status: at).hasPrefix("Rate limited until "))
        let other = RefreshStatus(lastSuccess: now, error: .other("GitHub server error 502"), isRefreshing: false)
        #expect(text(2, status: other) == "GitHub server error 502")
        let unreachable = RefreshStatus(lastSuccess: now, error: .unreachable(.secureConnectionFailed), isRefreshing: false)
        #expect(text(2, status: unreachable) == "Couldn't reach GitHub (secure connection failed)")
        let forbidden = RefreshStatus(lastSuccess: now, error: .forbidden, isRefreshing: false)
        #expect(text(2, status: forbidden) == "GitHub refused access (403)")
    }

    @Test func noAccountPointsAtThePopover() {
        let status = RefreshStatus(lastSuccess: nil, error: StatusTooltip.noAccount, isRefreshing: false)
        #expect(text(0, status: status) == "No GitHub account. Open PullBull to sign in.")
        #expect(StatusTooltip.noAccountText == "No GitHub account. Open PullBull to sign in.")
    }

    @Test func notSignedIn() {
        for error in [RefreshError.notLoggedIn("me"), .unauthorized] {
            let status = RefreshStatus(lastSuccess: nil, error: error, isRefreshing: false)
            #expect(text(0, status: status) == "Not signed in")
        }
    }

    @Test func neverUpdatedWithoutError() {
        let status = RefreshStatus(lastSuccess: nil, error: nil, isRefreshing: false)
        #expect(text(0, status: status) == "Not updated yet")
    }
}

@Suite struct MenuBarGlyphTests {
    private func glyph(_ error: RefreshError?, noAccount: Bool = false, signedOut: Bool = false) -> MenuBarGlyph {
        MenuBarGlyph.glyph(for: error, noAccount: noAccount, signedOut: signedOut)
    }

    @Test func offlineSlashesAndDims() {
        #expect(glyph(.offline) == .offline)
    }

    @Test(arguments: [
        RefreshError.unreachable(.secureConnectionFailed), .unreachable(.badServerResponse), .forbidden,
        .other("GitHub server error 502"), .other("Keychain is locked"), .ssoRequired(nil), .unauthorized,
        .signedOut(AccountRef(login: "octocat", source: .gitHubApp)), .ghMissing, .notLoggedIn("octocat"),
    ])
    func actionableErrorsBadgeTheNormalGlyph(error: RefreshError) {
        #expect(glyph(error) == .error)
    }

    /// A rate limit clears by itself: no badge.
    @Test func rateLimitIsNormal() {
        #expect(glyph(.rateLimited(nil)) == .normal)
        #expect(glyph(.rateLimited(Date(timeIntervalSince1970: 1_800_000_000))) == .normal)
    }

    @Test func noErrorIsNormal() {
        #expect(glyph(nil) == .normal)
    }

    /// Offline and not-set-up always dim; the badge never does; the normal glyph dims only for stale or
    /// incomplete data.
    @Test(arguments: [(false, false), (true, false), (false, true), (true, true)])
    func dimming(stale: Bool, issuesIncomplete: Bool) {
        #expect(MenuBarGlyph.offline.dimmed(stale: stale, issuesIncomplete: issuesIncomplete))
        #expect(MenuBarGlyph.notSetUp.dimmed(stale: stale, issuesIncomplete: issuesIncomplete))
        #expect(!MenuBarGlyph.error.dimmed(stale: stale, issuesIncomplete: issuesIncomplete))
        #expect(MenuBarGlyph.normal.dimmed(stale: stale, issuesIncomplete: issuesIncomplete) == (stale || issuesIncomplete))
    }

    /// No account yet is setup, whatever the last lookup said: the normal glyph, dimmed. A signed-out app
    /// account is a failure: the badge, at full strength.
    @Test func noAccountIsDimmedButSignedOutIsAnError() {
        #expect(glyph(nil, noAccount: true) == .notSetUp)
        #expect(glyph(nil, noAccount: true).dimmed(stale: false, issuesIncomplete: false))
        #expect(glyph(StatusTooltip.noAccount, noAccount: true) == .notSetUp)
        #expect(glyph(StatusTooltip.noAccount) == .normal)
        #expect(glyph(.ghMissing, noAccount: true) == .notSetUp)
        #expect(glyph(.rateLimited(nil), noAccount: true) == .notSetUp)
        #expect(glyph(.offline, noAccount: true) == .offline)
        #expect(glyph(.offline, noAccount: true).dimmed(stale: false, issuesIncomplete: false))
        #expect(glyph(nil, signedOut: true) == .error)
        #expect(!glyph(nil, signedOut: true).dimmed(stale: true, issuesIncomplete: true))
        #expect(glyph(nil, noAccount: true, signedOut: true) == .error)
        #expect(glyph(.signedOut(AccountRef(login: "octocat", source: .gitHubApp)), signedOut: true) == .error)
        #expect(glyph(.rateLimited(nil), signedOut: true) == .error)
        #expect(glyph(.offline, signedOut: true) == .offline)
    }
}
