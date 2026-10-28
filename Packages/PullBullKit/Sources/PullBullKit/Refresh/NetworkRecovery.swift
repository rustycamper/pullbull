import Foundation

/// When a network path change should refresh. After wake the first refresh usually runs before
/// Wi-Fi is back and fails offline; without this the next try waits for the backoff.
///
/// A satisfied path is due a refresh when the last attempt failed offline, or when it comes back
/// from unsatisfied with a wake's refresh still to succeed. Other changes while online (an
/// interface switch, a VPN) refresh nothing, and with nothing failed and no wake pending, coming
/// back from unsatisfied refreshes nothing either. The caller waits `debounce` before refreshing;
/// each satisfied change while one is due restarts the wait, and an unsatisfied one cancels it.
///
/// An attempt that fails offline while the path is satisfied (a request that hung from before the
/// path came back) makes a refresh due once more, at most once until the path next goes down; later
/// failures wait for the backoff.
public struct NetworkRecovery: Equatable, Sendable {
    public static let debounce: Duration = .seconds(2)

    /// The last path seen; nil before the first.
    private var satisfied: Bool?
    /// A wake whose refresh hasn't succeeded yet.
    private(set) var wakePending = false
    /// A refresh is due once the debounce runs out.
    public private(set) var isDue = false
    /// An offline failure already made a refresh due while the path has been satisfied.
    private var retriedAfterFailure = false

    public init() {}

    /// Returns true when a refresh is due after the debounce, starting it over; false cancels any
    /// waiting one.
    public mutating func pathChanged(satisfied: Bool, lastFailedOffline: Bool) -> Bool {
        let recovering = self.satisfied == false
        self.satisfied = satisfied
        if !satisfied { retriedAfterFailure = false }
        isDue = satisfied && (isDue || lastFailedOffline || recovering && wakePending)
        return isDue
    }

    /// An attempt failed offline. Returns true when that makes a refresh due after the debounce:
    /// the path is satisfied, none is due yet, and none was made due this way since it last went down.
    public mutating func attemptFailedOffline() -> Bool {
        guard satisfied == true, !isDue, !retriedAfterFailure else { return false }
        retriedAfterFailure = true
        isDue = true
        return true
    }

    public mutating func didWake() {
        wakePending = true
    }

    /// The debounce ran out (the refresh starts) or the loop it was for stopped.
    public mutating func clearDue() {
        isDue = false
    }

    public mutating func refreshSucceeded() {
        wakePending = false
    }
}
