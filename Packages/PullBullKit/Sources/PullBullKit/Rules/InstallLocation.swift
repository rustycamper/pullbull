import Foundation

/// Where a running copy of PullBull lives, for launch at login: only an installed copy may change the
/// login item, so test builds and stray downloads leave it alone.
public enum InstallLocation {
    /// Installed means the bundle, symlinks resolved, sits directly in `/Applications` or
    /// `~/Applications`, not in a subfolder. A translocated copy runs from under
    /// `/private/var/folders/…/AppTranslocation/`, so it never counts. Folder names compare without
    /// case, as on the default case-insensitive volume; a trailing slash doesn't matter.
    public static func isInstalled(bundleURL: URL, homeDirectory: URL) -> Bool {
        let folder = canonicalPath(bundleURL.resolvingSymlinksInPath().deletingLastPathComponent())
        let applications = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true),
        ]
        return applications.contains { canonicalPath($0.resolvingSymlinksInPath()) == folder }
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.pathComponents.filter { $0 != "/" }.joined(separator: "/").lowercased()
    }
}
