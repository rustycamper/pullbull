import Foundation
import Security

/// The version Settings shows, and whether this copy is a local build rather than a release.
enum BuildInfo {
    /// "1.0.0 (12)", from `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// A Debug build, or one not signed with a Developer ID Application certificate.
    static let isLocalBuild: Bool = {
        #if DEBUG
        return true
        #else
        return !isDeveloperIDSigned
        #endif
    }()

    /// Apple's Developer ID requirement: an Apple-anchored chain with the Developer ID CA and leaf markers.
    private static var isDeveloperIDSigned: Bool {
        var code: SecCode?
        var requirement: SecRequirement?
        let text = "anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
