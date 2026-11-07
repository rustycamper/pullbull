import Foundation
import PullBullKit

extension AppModel {
    /// Called with every coordinator update, before the model applies it.
    func notifyChanges(_ snapshot: Snapshot?, _ status: RefreshStatus) {
        let service = NotificationService.shared
        service.attach(self)
        service.process(
            snapshot, status, toggles: settings.notify, filters: ReviewFilters(settings), mergedHere: mergedHere,
            readiedHere: Set(readiedHere.keys))
        // A start-of-refresh call diffs nothing. The window, not a listing as ready, ends a key: GitHub's
        // request can reach the search a poll after the PR does.
        guard !status.isRefreshing else { return }
        let now = Date()
        readiedHere = readiedHere.filter { now.timeIntervalSince($0.value) <= ChangeDetector.readiedHereWindow }
    }

    /// A notification click: shows the popover on that PR's detail.
    func openFromNotification(_ key: PRKey) {
        openDetail(key)
        detailOpenedWhileClosed = !MenuBarPopover.isShown
        MenuBarPopover.show()
    }

    /// An "assigned to you" click: shows the popover on that issue's detail.
    func openIssueFromNotification(_ key: PRKey) {
        openIssueDetail(key)
        detailOpenedWhileClosed = !MenuBarPopover.isShown
        MenuBarPopover.show()
    }
}
