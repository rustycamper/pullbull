import Foundation
import Testing
@testable import PullBullKit

@Suite struct FirstRunChoiceTests {
    private let rusty = GhAccount(login: "rustycamper", scopes: ["repo"], active: false)
    private let devon = GhAccount(login: "devon", scopes: ["repo"], active: true)

    @Test func oneGhLoginLeadsWithSignInSecond() {
        let choice = FirstRunChoice.make(gh: .logins([rusty]), signIn: .available)
        #expect(choice.primary == .useGh("rustycamper"))
        #expect(choice.otherLogins.isEmpty)
        #expect(choice.offersSignIn)
        #expect(choice.link == nil)
        #expect(choice.note == nil)
    }

    @Test func theActiveLoginLeadsAndTheRestAreInTheMenu() {
        let choice = FirstRunChoice.make(gh: .logins([rusty, devon]), signIn: .available)
        #expect(choice.primary == .useGh("devon"))
        #expect(choice.otherLogins == ["rustycamper"])
        #expect(choice.offersSignIn)
    }

    @Test func withNoActiveLoginTheFirstLeads() {
        let other = GhAccount(login: "other", scopes: [])
        let choice = FirstRunChoice.make(gh: .logins([rusty, other]), signIn: .available)
        #expect(choice.primary == .useGh("rustycamper"))
        #expect(choice.otherLogins == ["other"])
    }

    @Test func ghWithoutALoginOffersLoggingIn() {
        let choice = FirstRunChoice.make(gh: .noLogin, signIn: .available)
        #expect(choice.primary == .signIn)
        #expect(!choice.offersSignIn)
        #expect(choice.link == .logInToGh)
        #expect(choice.link?.title == "Log in to GitHub CLI instead…")
        #expect(choice.note == nil)
        // An empty login list counts as no login.
        #expect(FirstRunChoice.make(gh: .logins([]), signIn: .available) == choice)
    }

    @Test func noGhOffersSettingItUp() {
        let choice = FirstRunChoice.make(gh: .notInstalled, signIn: .available)
        #expect(choice.primary == .signIn)
        #expect(choice.link == .useGh)
        #expect(choice.link?.title == "Use GitHub CLI instead…")
    }

    @Test func aBuildThatCantSignInLeadsWithTheChecklist() {
        let unsigned = FirstRunChoice.make(gh: .notInstalled, signIn: .needsTeamSignedBuild)
        #expect(unsigned.primary == .setUpGh)
        #expect(!unsigned.offersSignIn)
        #expect(unsigned.link == nil)
        #expect(unsigned.note == "Sign in with GitHub needs a team-signed build.")
        let misconfigured = FirstRunChoice.make(gh: .noLogin, signIn: .misconfigured)
        #expect(misconfigured.primary == .setUpGh)
        #expect(misconfigured.note == "Sign in with GitHub isn't set up in this build.")
    }

    @Test func aBuildThatCantSignInStillUsesAGhLogin() {
        let choice = FirstRunChoice.make(gh: .logins([rusty, devon]), signIn: .needsTeamSignedBuild)
        #expect(choice.primary == .useGh("devon"))
        #expect(choice.otherLogins == ["rustycamper"])
        #expect(!choice.offersSignIn)
        #expect(choice.note == "Sign in with GitHub needs a team-signed build.")
    }

    @Test func theActiveLoginLeadsWhenNotFirstAndTheOthersKeepGhsOrder() {
        let other = GhAccount(login: "other", scopes: [])
        let choice = FirstRunChoice.make(gh: .logins([rusty, devon, other]), signIn: .available)
        #expect(choice.primary == .useGh("devon"))
        #expect(choice.otherLogins == ["rustycamper", "other"])
    }

    @Test func theGhButtonReadsUseLeadAtRest() {
        let text = FirstRunChoice.ghButtonText(lead: "devon", using: nil, failed: nil)
        #expect(text.title == "Use devon from GitHub CLI")
        #expect(text.label == "Use devon from GitHub CLI")
        #expect(!text.running)
    }

    @Test func whileRunningTheGhButtonNamesThePickedLogin() {
        let lead = FirstRunChoice.ghButtonText(lead: "devon", using: "devon", failed: nil)
        #expect(lead.title == "Using devon…")
        #expect(lead.label == "Using devon…")
        #expect(lead.running)
        // A login picked from the ▾: the title and VoiceOver name it, not the lead.
        let other = FirstRunChoice.ghButtonText(lead: "devon", using: "rustycamper", failed: nil)
        #expect(other.title == "Using rustycamper…")
        #expect(other.label == "Using rustycamper…")
        #expect(other.running)
    }

    @Test func theGhButtonSaysTryAgainOnlyWhenTheLeadFailed() {
        let failed = FirstRunChoice.ghButtonText(lead: "devon", using: nil, failed: "devon")
        #expect(failed.title == "Try Again")
        #expect(failed.label == "Try again: Use devon from GitHub CLI")
        #expect(!failed.running)
        // Another login failing leaves the lead button as it was.
        let otherFailed = FirstRunChoice.ghButtonText(lead: "devon", using: nil, failed: "rustycamper")
        #expect(otherFailed == FirstRunChoice.ghButtonText(lead: "devon", using: nil, failed: nil))
    }

    @Test func theGhButtonStatesCoverEveryTitle() {
        let titles = FirstRunChoice.ghButtonStates(lead: "devon", others: ["rustycamper"]).map(\.title)
        #expect(titles == [
            "Use devon from GitHub CLI", "Try Again", "Using devon…", "Using rustycamper…",
        ])
    }

    @Test func copy() {
        #expect(FirstRunChoice.useTitle("devon") == "Use devon from GitHub CLI")
        #expect(FirstRunChoice.usingTitle("devon") == "Using devon…")
        #expect(FirstRunChoice.failure("devon", message: "Offline")
            == "Couldn't use devon: Offline")
        #expect(FirstRunChoice.ghLine == "Works right away with every repo, org and board you can see.")
        #expect(FirstRunChoice.signInLine == "Read-only, limited to repos you choose. Your org may need to approve PullBull.")
    }
}

@Suite struct FirstRunPolicyTests {
    @Test func aFreshInstallWithGhLoginsWaitsForTheUser() {
        #expect(FirstRunPolicy.waitsForChoice(saved: nil, appAccounts: [], ghLogins: ["devon"], signedOutByUser: false))
    }

    @Test func existingUsersArePickedForAsBefore() {
        let saved = AccountRef(login: "devon", source: .gh)
        #expect(!FirstRunPolicy.waitsForChoice(saved: saved, appAccounts: [], ghLogins: ["devon"], signedOutByUser: false))
        // App accounts signed in to before (e.g. all signed out): launch picks as before.
        let summary = AccountSummary(userID: 1, login: "devon")
        #expect(!FirstRunPolicy.waitsForChoice(saved: nil, appAccounts: [summary], ghLogins: ["devon"], signedOutByUser: false))
    }

    @Test func nothingToChooseFromMeansNoWait() {
        #expect(!FirstRunPolicy.waitsForChoice(saved: nil, appAccounts: [], ghLogins: [], signedOutByUser: false))
    }

    /// After the user's Sign Out, launch waits whatever accounts there are, until one is chosen.
    @Test func aSignOutWaitsForTheUser() {
        let summary = AccountSummary(userID: 1, login: "devon")
        #expect(FirstRunPolicy.waitsForChoice(saved: nil, appAccounts: [summary], ghLogins: ["devon"], signedOutByUser: true))
        #expect(FirstRunPolicy.waitsForChoice(saved: nil, appAccounts: [], ghLogins: [], signedOutByUser: true))
        let saved = AccountRef(login: "devon", source: .gh)
        #expect(!FirstRunPolicy.waitsForChoice(saved: saved, appAccounts: [], ghLogins: ["devon"], signedOutByUser: true))
    }
}
