import Testing
@testable import PullBullKit

struct GhCommandsTests {
    @Test func installAndLogin() {
        #expect(GhCommands.install == "brew install gh")
        // Asks for read:project at login, so a new login can read boards at once.
        #expect(GhCommands.logIn == "gh auth login --web -s read:project")
    }

    @Test func projectScopeForTheActiveLoginNeedsNoSwitch() {
        #expect(GhCommands.addProjectScope(login: "me", activeLogin: "me", scope: "project") == "gh auth refresh -s project")
        #expect(GhCommands.addProjectScope(login: "me", activeLogin: "work", scope: "project")
            == "gh auth switch --user me && gh auth refresh -s project && gh auth switch --user work")
        #expect(GhCommands.addProjectScope(login: "devon", activeLogin: "devon")
            == "gh auth refresh -s read:project")
    }

    @Test func projectScopeForAnotherLoginSwitchesThereAndBack() {
        #expect(GhCommands.addProjectScope(login: "devon", activeLogin: "rustycamper")
            == "gh auth switch --user devon && gh auth refresh -s read:project && gh auth switch --user rustycamper")
    }

    @Test func projectScopeForTheActiveLoginIgnoresCase() {
        #expect(GhCommands.addProjectScope(login: "Devon", activeLogin: "devon")
            == "gh auth refresh -s read:project")
    }

    @Test func projectScopeWithoutALoginRefreshesTheActiveAccount() {
        #expect(GhCommands.addProjectScope(login: nil, activeLogin: "rustycamper") == "gh auth refresh -s read:project")
        #expect(GhCommands.addProjectScope(login: "", activeLogin: nil) == "gh auth refresh -s read:project")
    }

    @Test func projectScopeWithNoActiveLoginKnownSwitchesOnly() {
        #expect(GhCommands.addProjectScope(login: "devon", activeLogin: nil)
            == "gh auth switch --user devon && gh auth refresh -s read:project")
    }
}
