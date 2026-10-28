import Foundation

/// Whether this build can use Sign in with GitHub.
public enum SignInAvailability: Equatable, Sendable {
    case available
    /// Configured, but the Keychain can't hold a sign-in: the build isn't team-signed.
    case needsTeamSignedBuild
    /// The build lacks the app's client ID or slug.
    case misconfigured
}

/// What launch found out about `gh` for the first-run screen. No new calls: it is what launch's
/// `gh auth status` already said.
public enum GhDetection: Equatable, Sendable {
    case notInstalled
    /// Installed, but no healthy login (or `gh auth status` failed).
    case noLogin
    /// Healthy logins, in gh's order.
    case logins([GhAccount])
}

/// The first-run screen's buttons, from what detection found (the onboarding design's first-run table).
public struct FirstRunChoice: Equatable, Sendable {
    public enum Primary: Equatable, Sendable {
        case useGh(String)
        case signIn
        /// Opens the GitHub CLI setup checklist.
        case setUpGh
    }

    /// The link under Sign in with GitHub; both open the checklist.
    public enum Link: Equatable, Sendable {
        /// `gh` is installed without a login: the checklist's step 2 is next.
        case logInToGh
        case useGh

        public var title: String {
            switch self {
            case .logInToGh: "Log in to GitHub CLI instead…"
            case .useGh: "Use GitHub CLI instead…"
            }
        }
    }

    public let primary: Primary
    /// The other `gh` logins, for the ▾ menu of the split [Use X from GitHub CLI] button.
    public let otherLogins: [String]
    /// Sign in with GitHub as a bordered second button, under a `gh` primary.
    public let offersSignIn: Bool
    public let link: Link?
    /// Why Sign in with GitHub is missing, for a build that can't sign in.
    public let note: String?

    public static let ghLine = "Works right away with every repo, org and board you can see."
    public static let signInLine = "Read-only, limited to repos you choose. Your org may need to approve PullBull."

    public static func useTitle(_ login: String) -> String { "Use \(login) from GitHub CLI" }
    public static func usingTitle(_ login: String) -> String { "Using \(login)…" }
    public static func failure(_ login: String, message: String) -> String { "Couldn't use \(login): \(message)" }

    /// What the [Use X from GitHub CLI] button shows and VoiceOver reads.
    public struct GhButtonText: Hashable, Sendable {
        public let title: String
        public let label: String
        /// "Using X…", drawn with a spinner.
        public let running: Bool
    }

    /// The button for `lead`: "Using X…" while login X is in use, X being whichever login was picked;
    /// Try Again only when the lead itself failed; otherwise "Use <lead> from GitHub CLI".
    public static func ghButtonText(lead: String, using: String?, failed: String?) -> GhButtonText {
        if let using {
            return GhButtonText(title: usingTitle(using), label: usingTitle(using), running: true)
        }
        if failed == lead {
            return GhButtonText(title: "Try Again", label: "Try again: \(useTitle(lead))", running: false)
        }
        return GhButtonText(title: useTitle(lead), label: useTitle(lead), running: false)
    }

    /// Every state the button can show for these logins, so it can be as wide as the widest and not move.
    public static func ghButtonStates(lead: String, others: [String]) -> [GhButtonText] {
        [ghButtonText(lead: lead, using: nil, failed: nil), ghButtonText(lead: lead, using: nil, failed: lead)]
            + ([lead] + others).map { ghButtonText(lead: lead, using: $0, failed: nil) }
    }

    /// A healthy `gh` login leads (gh's active one first); otherwise Sign in with GitHub leads, with
    /// GitHub CLI as a link; a build that can't sign in leads with the checklist.
    public static func make(gh: GhDetection, signIn: SignInAvailability) -> FirstRunChoice {
        let note: String? = switch signIn {
        case .available: nil
        case .needsTeamSignedBuild: "Sign in with GitHub needs a team-signed build."
        case .misconfigured: "Sign in with GitHub isn't set up in this build."
        }
        let canSignIn = signIn == .available
        if case .logins(let accounts) = gh, let lead = accounts.first(where: \.active) ?? accounts.first {
            return FirstRunChoice(
                primary: .useGh(lead.login), otherLogins: accounts.map(\.login).filter { $0 != lead.login },
                offersSignIn: canSignIn, link: nil, note: note)
        }
        guard canSignIn else {
            return FirstRunChoice(primary: .setUpGh, otherLogins: [], offersSignIn: false, link: nil, note: note)
        }
        let link: Link = gh == .notInstalled ? .useGh : .logInToGh
        return FirstRunChoice(primary: .signIn, otherLogins: [], offersSignIn: false, link: link, note: nil)
    }
}

public enum FirstRunPolicy {
    /// A fresh install (no saved account, never signed in with GitHub) with `gh` logins shows the
    /// one-click screen instead of adopting a login silently, and so does a user who signed out
    /// (`signedOutByUser`) until they choose an account. Everyone else is picked for as before.
    public static func waitsForChoice(
        saved: AccountRef?, appAccounts: [AccountSummary], ghLogins: [String], signedOutByUser: Bool
    ) -> Bool {
        guard saved == nil else { return false }
        return signedOutByUser || (appAccounts.isEmpty && !ghLogins.isEmpty)
    }
}
