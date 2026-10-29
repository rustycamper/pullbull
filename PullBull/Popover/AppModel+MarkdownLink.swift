import Foundation
import PullBullKit

/// ⌥⌘C: what the highlighted row, the selected search result or the detail on screen copies.
extension AppModel {
    /// The highlighted row; false when no shown row is highlighted.
    func copyListSelectionMarkdownLink(in keys: [PRKey]) -> Bool {
        guard let link = listSelectionLink(in: keys) else { return false }
        let title = switch mode {
        case .pullRequests: pullRequest(for: link.key)?.title
        case .issues: issue(for: link.key)?.title
        }
        PRActions.copyMarkdownLink(title: title, key: link.key, url: link.url)
        return true
    }

    /// The selected search result; false without one.
    func copySearchSelectionMarkdownLink() -> Bool {
        guard let key = searchSelection, let results = searchResults else { return false }
        if let pr = (results.openPRs + results.closedPRs).first(where: { $0.key == key }) {
            PRActions.copyMarkdownLink(pr)
        } else if let issue = results.issues.first(where: { $0.key == key }) {
            PRActions.copyMarkdownLink(issue)
        } else {
            return false
        }
        return true
    }

    /// The detail on screen, titled as its header shows it; false outside a detail.
    func copyShownDetailMarkdownLink() -> Bool {
        guard let link = shownDetailLink else { return false }
        let title = switch route {
        case .detail(let key): pullRequest(for: key)?.title ?? linkedPR(for: key)?.title
        case .issueDetail(let key): (issueDetails[key]?.issue ?? issue(for: key))?.title
        case .list, .search, .ask: String?.none
        }
        PRActions.copyMarkdownLink(title: title, key: link.key, url: link.url)
        return true
    }
}
