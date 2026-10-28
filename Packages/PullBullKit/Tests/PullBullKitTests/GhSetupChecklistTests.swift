import Foundation
import Testing
@testable import PullBullKit

@Suite struct GhSetupChecklistTests {
    private let path = "/opt/homebrew/bin/gh"

    private func login(
        _ name: String, active: Bool = false, health: GhLogin.Health = .ok, scopes: Set<String> = ["repo"]
    ) -> GhLogin {
        GhLogin(login: name, active: active, health: health, scopes: scopes)
    }

    private func make(
        _ status: GhStatus?, for purpose: GhSetupChecklist.Purpose = .firstRun, homebrew: Bool = true,
        missedAfterRecheck: Bool = false
    ) -> GhSetupChecklist {
        GhSetupChecklist.make(purpose: purpose, status: status, homebrew: homebrew, missedAfterRecheck: missedAfterRecheck)
    }

    @Test func noGhWithHomebrew() {
        let list = make(.notInstalled)
        let install = list.steps[0]
        #expect(!install.done)
        #expect(install.title == "Install GitHub CLI")
        #expect(install.command == "brew install gh")
        #expect(install.link == nil)
        #expect(install.warning == nil)
        #expect(list.steps[1].command == "gh auth login --web -s read:project")
        #expect(!list.canUse)
        #expect(list.login == nil)
        #expect(list.intro
            == "PullBull can use the login you already have in GitHub CLI (gh). Run each command in Terminal. The steps tick themselves off.")
    }

    @Test func noGhWithoutHomebrewLinksToTheDownload() {
        let install = make(.notInstalled, homebrew: false).steps[0]
        #expect(install.command == nil)
        #expect(install.note == "Homebrew isn't installed. Download GitHub CLI from cli.github.com instead.")
        #expect(install.link == GhSetupChecklist.Link(title: "Open cli.github.com", url: URL(string: "https://cli.github.com")!))
    }

    @Test func ghStillMissingAfterARecheckSaysWhereItLooks() {
        let install = make(.notInstalled, missedAfterRecheck: true).steps[0]
        #expect(install.warning
            == "PullBull can't find gh. It looks in /opt/homebrew/bin, /usr/local/bin and your login shell's PATH.")
    }

    @Test func installedWithoutALogin() {
        let list = make(.logins(gh: path, []))
        #expect(list.steps[0].done)
        #expect(list.steps[0].note == "Installed (/opt/homebrew/bin/gh)")
        #expect(!list.steps[1].done)
        #expect(list.steps[1].note == "Opens GitHub in your browser.")
        #expect(list.steps[2].subtitle == "Optional, for your Projects board")
        #expect(list.steps[2].command == "gh auth refresh -s read:project")
        #expect(!list.canUse)
    }

    @Test func aNewLoginWithTheBoardScopeTicksEveryStep() {
        let list = make(.logins(gh: path, [login("devon", active: true, scopes: ["repo", "read:project"])]))
        #expect(list.steps.allSatisfy { $0.done })
        #expect(list.steps[1].note == "Logged in as devon")
        #expect(list.steps[2].note == "devon can read Projects boards")
        #expect(list.login == "devon")
        #expect(list.canUse)
    }

    @Test func firstRunUsesTheActiveLoginAndCountsTheOthers() {
        let list = make(.logins(gh: path, [login("rustycamper"), login("devon", active: true), login("third")]))
        #expect(list.login == "devon")
        #expect(list.steps[1].note == "Logged in as devon, and 2 others")
        // The board step is optional from first run.
        #expect(!list.steps[2].done)
        #expect(list.steps[2].command == "gh auth refresh -s read:project")
        #expect(list.canUse)
        #expect(make(.logins(gh: path, [login("a", active: true), login("b")])).steps[1].note
            == "Logged in as a, and 1 other")
    }

    @Test func boardTargetThatIsNotActiveSwitchesThereAndBack() {
        let list = make(.logins(gh: path, [
            login("rustycamper", active: true), login("devon"),
        ]), for: .board(login: "devon"))
        #expect(list.login == "devon")
        #expect(list.steps[1].done)
        let board = list.steps[2]
        #expect(!board.done)
        #expect(board.subtitle == nil)
        #expect(board.command
            == "gh auth switch --user devon && gh auth refresh -s read:project && gh auth switch --user rustycamper")
        #expect(board.note == "gh adds access only to its active login, so this switches to devon and back to rustycamper.")
        // From the board row the board step is required.
        #expect(!list.canUse)
        #expect(list.intro
            == "GitHub doesn't let PullBull's own sign-in read personal Projects boards. A GitHub CLI login for devon can.")
    }

    @Test func boardTargetLoggedInAsSomeoneElse() {
        let list = make(.logins(gh: path, [login("rustycamper", active: true)]), for: .board(login: "devon"))
        let step = list.steps[1]
        #expect(!step.done)
        #expect(step.note == "Opens GitHub in your browser. Sign in as devon.")
        #expect(step.warning
            == "gh is logged in as rustycamper, not devon. Run the command and sign in as devon on GitHub; rustycamper stays logged in.")
    }

    @Test func anExpiredLogin() {
        let list = make(.logins(gh: path, [login("devon", active: true, health: .invalid, scopes: [])]))
        #expect(!list.steps[1].done)
        #expect(list.steps[1].warning == "gh's login for devon has expired or was revoked.")
        #expect(list.steps[1].command == "gh auth login --web -s read:project")
        #expect(!list.canUse)
    }

    @Test func offlineKeepsChecking() {
        let list = make(.logins(gh: path, [login("devon", active: true, health: .unreachable, scopes: [])]))
        #expect(list.steps[1].warning == "Can't reach GitHub to check gh's login. Still checking…")
    }

    @Test func statusFailed() {
        let list = make(.failed(gh: path, message: "error connecting to keyring"))
        #expect(list.steps[0].done)
        #expect(list.steps[1].warning == "Couldn't ask gh who's logged in: error connecting to keyring")
    }

    @Test func beforeTheFirstPassNothingIsDoneOrWarned() {
        let list = make(nil)
        #expect(list.steps.allSatisfy { !$0.done && $0.warning == nil })
    }

    @Test func eachStepIsOneVoiceOverElement() {
        let list = make(.logins(gh: path, [login("devon", active: true)]))
        #expect(list.steps[1].accessibilityLabel == "Step 2, Log in to GitHub CLI, done")
        #expect(list.steps[2].accessibilityLabel == "Step 3, Allow board access, optional, to do")
    }

    @Test func announcesTheStepsThatTicked() {
        let before = make(.logins(gh: path, []))
        let after = make(.logins(gh: path, [login("devon", active: true)]))
        #expect(GhSetupChecklist.announcements(from: before, to: after) == ["Step 2 done: Logged in as devon"])
        #expect(GhSetupChecklist.announcements(from: after, to: after).isEmpty)
    }

    @Test func usingTheLogin() {
        let list = make(.logins(gh: path, [login("devon", active: true)]))
        #expect(list.isUsed(by: AccountRef(login: "devon", source: .gh)))
        #expect(!list.isUsed(by: AccountRef(login: "devon", source: .gitHubApp)))
        #expect(!list.isUsed(by: nil))
    }

    @Test func checkedLine() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(GhSetupChecklist.checkedText(at: now.addingTimeInterval(-20), now: now) == "Checked just now")
        #expect(GhSetupChecklist.checkedText(at: now.addingTimeInterval(-130), now: now) == "Checked 2 min ago")
    }

    @Test func aPassChangedWhenTheStatusDid() {
        let one = GhStatus.logins(gh: path, [])
        let two = GhStatus.logins(gh: path, [login("devon")])
        #expect(GhSetupChecklist.recheckResult(from: one, to: two) == .changed)
        #expect(GhSetupChecklist.recheckResult(from: two, to: two) == .unchanged)
    }
}
