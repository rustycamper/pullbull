import Testing
@testable import PullBullKit

@Suite struct LaunchAtLoginFollowTests {
    private let here = "/Applications/PullBull.app"
    private let elsewhere = "/Users/devon/Applications/PullBull.app"
    private let allStatuses: [LaunchAtLoginFollow.Status] = [.notRegistered, .enabled, .requiresApproval, .notFound]

    private func action(installed: Bool = true, _ status: LaunchAtLoginFollow.Status,
                        registered: String?) -> LaunchAtLoginFollow.Action {
        LaunchAtLoginFollow.action(installed: installed, status: status, registeredPath: registered,
                                   currentPath: here)
    }

    @Test func anEnabledItemFromThisCopyIsLeftAlone() {
        #expect(action(.enabled, registered: here) == .none)
    }

    @Test func anEnabledItemFromAnotherPathIsRepointed() {
        #expect(action(.enabled, registered: elsewhere) == .reregister)
    }

    @Test func anEnabledItemWithNoRememberedPathIsRepointed() {
        #expect(action(.enabled, registered: nil) == .reregister)
    }

    @Test func aCopyOutsideApplicationsNeverActs() {
        for status in allStatuses {
            for registered in [here, elsewhere, nil] {
                #expect(action(installed: false, status, registered: registered) == .none)
            }
        }
    }

    @Test func onlyAnEnabledItemIsRepointed() {
        for status in allStatuses where status != .enabled {
            for registered in [here, elsewhere, nil] {
                #expect(action(status, registered: registered) == .none)
            }
        }
    }
}
