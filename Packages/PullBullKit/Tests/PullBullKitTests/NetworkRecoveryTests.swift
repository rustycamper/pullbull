import Testing
@testable import PullBullKit

/// Feeds `NetworkRecovery` path changes, `(satisfied, lastFailedOffline)`, and returns each answer.
private func answers(_ recovery: inout NetworkRecovery, _ changes: [(Bool, Bool)]) -> [Bool] {
    changes.map { recovery.pathChanged(satisfied: $0.0, lastFailedOffline: $0.1) }
}

private func failedOffline(_ recovery: inout NetworkRecovery) -> Bool {
    recovery.attemptFailedOffline()
}

@Suite struct NetworkRecoveryTests {
    @Test func comingBackAfterAnOfflineFailureIsDue() {
        var r = NetworkRecovery()
        #expect(answers(&r, [(false, true), (true, true)]) == [false, true])
        #expect(r.isDue)
    }

    @Test func comingBackWithNothingFailedIsNotDue() {
        var r = NetworkRecovery()
        #expect(answers(&r, [(true, false), (false, false), (true, false)]) == [false, false, false])
    }

    /// An interface switch or a VPN change while online refreshes nothing, after a wake too.
    @Test func satisfiedToSatisfiedIsNotDue() {
        var r = NetworkRecovery()
        #expect(answers(&r, [(true, false), (true, false)]) == [false, false])
        r.didWake()
        #expect(answers(&r, [(true, false)]) == [false])
    }

    /// Online but the last attempt failed offline (the path came back before it): any change is due.
    @Test func satisfiedChangeAfterAnOfflineFailureIsDue() {
        var r = NetworkRecovery()
        #expect(answers(&r, [(true, false), (true, true)]) == [false, true])
    }

    @Test func comingBackAfterWakeIsDueUntilARefreshSucceeds() {
        var r = NetworkRecovery()
        r.didWake()
        #expect(answers(&r, [(false, false), (true, false)]) == [false, true])
        r.clearDue()
        r.refreshSucceeded()
        #expect(answers(&r, [(false, false), (true, false)]) == [false, false])
    }

    /// The very first path seen is not a recovery, even after a wake.
    @Test func firstPathIsNotARecovery() {
        var r = NetworkRecovery()
        r.didWake()
        #expect(answers(&r, [(true, false)]) == [false])
    }

    /// Flapping: going down cancels the waiting refresh; each satisfied change while one is due
    /// restarts the debounce, even one that wouldn't be due on its own.
    @Test func goingDownCancelsAndSatisfiedChangesRestart() {
        var r = NetworkRecovery()
        #expect(answers(&r, [(false, true), (true, true), (false, true)]) == [false, true, false])
        #expect(!r.isDue)
        #expect(answers(&r, [(true, true), (true, false)]) == [true, true])
        r.clearDue()
        #expect(answers(&r, [(true, false)]) == [false])
    }

    /// An offline failure while satisfied makes a refresh due once per satisfied stretch; going down
    /// and back allows one more.
    @Test func offlineFailureWhileSatisfiedIsDueOncePerStretch() {
        var r = NetworkRecovery()
        #expect(!failedOffline(&r))
        _ = answers(&r, [(true, false)])
        #expect(failedOffline(&r))
        #expect(r.isDue)
        r.clearDue()
        #expect(!failedOffline(&r))
        _ = answers(&r, [(true, false)])
        r.clearDue()
        #expect(!failedOffline(&r))
        _ = answers(&r, [(false, true), (true, true)])
        r.clearDue()
        #expect(failedOffline(&r))
    }

    /// Nothing more is made due while a refresh is already waiting on the debounce.
    @Test func offlineFailureWhileDueAddsNothing() {
        var r = NetworkRecovery()
        _ = answers(&r, [(false, true), (true, true)])
        #expect(!failedOffline(&r))
        r.clearDue()
        #expect(failedOffline(&r))
    }

    @Test func offlineFailureWhileUnsatisfiedIsNotDue() {
        var r = NetworkRecovery()
        _ = answers(&r, [(false, true)])
        #expect(!failedOffline(&r))
    }

    @Test func debounceIsAboutTwoSeconds() {
        #expect(NetworkRecovery.debounce == .seconds(2))
    }
}
