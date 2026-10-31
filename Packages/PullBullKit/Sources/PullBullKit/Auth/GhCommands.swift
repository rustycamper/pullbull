/// Commands PullBull shows for the user to run. `gh auth refresh` has no `--user` flag and acts on the
/// active account, so a named login is switched to first.
public enum GhCommands {
    public static let install = "brew install gh"
    /// Asks for `read:project` too, so a new login can read Projects boards without a second step.
    public static let logIn = "gh auth login --web -s read:project"

    /// Adds `scope` (`read:project` to read boards, `project` to change Status) to `login` when
    /// `activeLogin` is gh's active one: a plain refresh when they are the same (or no login is named),
    /// else a switch to `login` and back, so the user's active login stays as it was. With no active
    /// login known it only switches.
    public static func addProjectScope(login: String?, activeLogin: String?, scope: String = "read:project") -> String {
        let refresh = "gh auth refresh -s \(scope)"
        guard let login, !login.isEmpty,
              activeLogin.map({ $0.caseInsensitiveCompare(login) != .orderedSame }) ?? true
        else { return refresh }
        let switchAndRefresh = "gh auth switch --user \(login) && \(refresh)"
        guard let activeLogin else { return switchAndRefresh }
        return "\(switchAndRefresh) && gh auth switch --user \(activeLogin)"
    }
}
