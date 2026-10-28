import Foundation
import PullBullKit

/// The registered GitHub App, read from the Info.plist keys that `Config/Shared.xcconfig` fills in.
struct GitHubAppConfig {
    let clientID: String
    let appSlug: String

    /// nil when either value is empty or missing, or the slug is malformed: the build is misconfigured.
    static var current: GitHubAppConfig? {
        let info = Bundle.main.infoDictionary
        return make(clientID: info?["PBGitHubClientID"] as? String, appSlug: info?["PBGitHubAppSlug"] as? String)
    }

    static func make(clientID: String?, appSlug: String?) -> GitHubAppConfig? {
        guard let clientID, !clientID.isEmpty, let appSlug, AccessChecker.isValidAppSlug(appSlug) else { return nil }
        return GitHubAppConfig(clientID: clientID, appSlug: appSlug)
    }
}
