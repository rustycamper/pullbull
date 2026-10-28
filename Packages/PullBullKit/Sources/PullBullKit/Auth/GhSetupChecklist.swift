import Foundation

/// The "Set Up GitHub CLI" checklist: install `gh`, log in, allow board access. Each step's state comes
/// from the last `GhCLI.status()` pass, so the steps tick themselves off.
public struct GhSetupChecklist: Equatable, Sendable {
    public enum Purpose: Equatable, Sendable {
        /// From the first-run screen: any login counts, and board access is optional.
        case firstRun
        /// For `login`'s Projects board: that login, with board access.
        case board(login: String)
    }

    public struct Link: Equatable, Sendable {
        public let title: String
        public let url: URL

        public init(title: String, url: URL) {
            self.title = title
            self.url = url
        }
    }

    public struct Step: Equatable, Sendable, Identifiable {
        public let number: Int
        public let title: String
        /// "Optional, …" for a step the action doesn't need.
        public let subtitle: String?
        public let done: Bool
        public let note: String?
        /// What stops the step, on the step it affects.
        public let warning: String?
        /// The command to copy into Terminal, while the step is to do.
        public let command: String?
        public let link: Link?

        public var id: Int { number }

        /// The whole step as one VoiceOver element.
        public var accessibilityLabel: String {
            var parts = ["Step \(number)", title]
            if subtitle != nil { parts.append("optional") }
            parts.append(done ? "done" : "to do")
            return parts.joined(separator: ", ")
        }
    }

    public let intro: String
    public let steps: [Step]
    /// The login "Use X from GitHub CLI" switches to; nil until one is known.
    public let login: String?
    /// The final button is enabled: step 2 is done (and step 3, for a board).
    public let canUse: Bool

    public static let downloadURL = URL(string: "https://cli.github.com")!

    public static func make(
        purpose: Purpose, status: GhStatus?, homebrew: Bool, missedAfterRecheck: Bool
    ) -> GhSetupChecklist {
        let logins: [GhLogin]
        var path: String?
        var failure: String?
        switch status {
        case .logins(let gh, let list):
            path = gh
            logins = list
        case .failed(let gh, let message):
            path = gh
            failure = message
            logins = []
        case .notInstalled, nil:
            logins = []
        }
        let healthy = logins.filter { $0.health == .ok }
        let activeLogin = healthy.first(where: \.active)?.login
        let target: String?
        let targetLogin: GhLogin?
        switch purpose {
        case .board(let login):
            target = login
            targetLogin = logins.first { $0.login == login }
        case .firstRun:
            targetLogin = healthy.first(where: \.active) ?? healthy.first ?? logins.first
            target = targetLogin?.login
        }

        let install = installStep(path: path, notFound: status == .notInstalled, homebrew: homebrew,
                                  missedAfterRecheck: missedAfterRecheck)
        let loggedIn = targetLogin?.health == .ok
        let logIn = logInStep(
            purpose: purpose, target: target, targetLogin: targetLogin, healthy: healthy, failure: failure,
            installed: install.done, checked: status != nil)
        let canReadBoards = loggedIn && targetLogin?.canReadProjects == true
        let board = boardStep(purpose: purpose, target: target, activeLogin: activeLogin, done: canReadBoards)

        let intro = switch purpose {
        case .firstRun:
            "PullBull can use the login you already have in GitHub CLI (gh). Run each command in Terminal. The steps tick themselves off."
        case .board(let login):
            "GitHub doesn't let PullBull's own sign-in read personal Projects boards. A GitHub CLI login for \(login) can."
        }
        let needsBoard = if case .board = purpose { true } else { false }
        return GhSetupChecklist(
            intro: intro, steps: [install, logIn, board], login: target,
            canUse: target != nil && loggedIn && (!needsBoard || canReadBoards))
    }

    private static func installStep(
        path: String?, notFound: Bool, homebrew: Bool, missedAfterRecheck: Bool
    ) -> Step {
        if let path {
            return Step(number: 1, title: "Install GitHub CLI", subtitle: nil, done: true,
                        note: "Installed (\(path))", warning: nil, command: nil, link: nil)
        }
        let warning = notFound && missedAfterRecheck
            ? "PullBull can't find gh. It looks in /opt/homebrew/bin, /usr/local/bin and your login shell's PATH."
            : nil
        guard homebrew else {
            return Step(number: 1, title: "Install GitHub CLI", subtitle: nil, done: false,
                        note: "Homebrew isn't installed. Download GitHub CLI from cli.github.com instead.",
                        warning: warning, command: nil, link: Link(title: "Open cli.github.com", url: downloadURL))
        }
        return Step(number: 1, title: "Install GitHub CLI", subtitle: nil, done: false, note: nil,
                    warning: warning, command: GhCommands.install, link: nil)
    }

    private static func logInStep(
        purpose: Purpose, target: String?, targetLogin: GhLogin?, healthy: [GhLogin], failure: String?,
        installed: Bool, checked: Bool
    ) -> Step {
        let title = "Log in to GitHub CLI"
        if let target, targetLogin?.health == .ok {
            // From first run any login counts, so the others are mentioned.
            let others = purpose == .firstRun ? healthy.filter { $0.login != target }.count : 0
            let note = "Logged in as \(target)" + (others == 0 ? "" : ", and \(others) other\(others == 1 ? "" : "s")")
            return Step(number: 2, title: title, subtitle: nil, done: true, note: note, warning: nil, command: nil,
                        link: nil)
        }
        var note = "Opens GitHub in your browser."
        if case .board(let login) = purpose { note += " Sign in as \(login)." }
        var warning: String?
        if installed, checked {
            if let failure {
                warning = "Couldn't ask gh who's logged in: \(failure)"
            } else if let targetLogin, targetLogin.health == .unreachable {
                warning = "Can't reach GitHub to check gh's login. Still checking…"
            } else if let targetLogin, targetLogin.health == .invalid {
                warning = "gh's login for \(targetLogin.login) has expired or was revoked."
            } else if let target, let other = healthy.first(where: \.active) ?? healthy.first {
                warning = "gh is logged in as \(other.login), not \(target). Run the command and sign in as "
                    + "\(target) on GitHub; \(other.login) stays logged in."
            }
        }
        return Step(number: 2, title: title, subtitle: nil, done: false, note: note, warning: warning,
                    command: GhCommands.logIn, link: nil)
    }

    private static func boardStep(purpose: Purpose, target: String?, activeLogin: String?, done: Bool) -> Step {
        let title = "Allow board access"
        let subtitle = purpose == .firstRun ? "Optional, for your Projects board" : nil
        guard !done else {
            return Step(number: 3, title: title, subtitle: subtitle, done: true,
                        note: target.map { "\($0) can read Projects boards" }, warning: nil, command: nil, link: nil)
        }
        guard let target else {
            return Step(number: 3, title: title, subtitle: subtitle, done: false, note: nil, warning: nil,
                        command: GhCommands.addProjectScope(login: nil, activeLogin: activeLogin), link: nil)
        }
        let switches = activeLogin.map { $0 != target } ?? false
        let note = switches
            ? "gh adds access only to its active login, so this switches to \(target) and back to \(activeLogin ?? "")."
            : nil
        return Step(number: 3, title: title, subtitle: subtitle, done: false, note: note, warning: nil,
                    command: GhCommands.addProjectScope(login: target, activeLogin: activeLogin), link: nil)
    }

    /// PullBull already polls with this login from `gh`.
    public func isUsed(by current: AccountRef?) -> Bool {
        guard let login, let current else { return false }
        return current == AccountRef(login: login, source: .gh)
    }

    /// What VoiceOver hears when a pass ticks steps off.
    public static func announcements(from old: GhSetupChecklist, to new: GhSetupChecklist) -> [String] {
        zip(old.steps, new.steps).compactMap { before, after in
            guard !before.done, after.done else { return nil }
            return "Step \(after.number) done" + (after.note.map { ": \($0)" } ?? "")
        }
    }

    /// The status line after a pass.
    public static func checkedText(at checked: Date, now: Date) -> String {
        let minutes = Int(max(0, now.timeIntervalSince(checked)) / 60)
        return minutes < 1 ? "Checked just now" : "Checked \(minutes) min ago"
    }

    /// For the timed passes: any change in what gh reports restarts their 10 minutes.
    public static func recheckResult(from old: GhStatus?, to new: GhStatus) -> RecheckResult {
        old == new ? .unchanged : .changed
    }
}
