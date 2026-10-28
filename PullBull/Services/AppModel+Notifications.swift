import PullBullKit

extension AppModel {
    /// Called with every coordinator update, before the model applies it.
    func notifyChanges(_ snapshot: Snapshot?, _ status: RefreshStatus) {
        let service = NotificationService.shared
        service.attach(self)
        service.process(snapshot, status, toggles: settings.notify, filters: ReviewFilters(settings))
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
