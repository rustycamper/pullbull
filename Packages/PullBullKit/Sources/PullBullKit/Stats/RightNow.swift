import Foundation

/// A row and the wait it shows.
public struct RightNowItem: Sendable {
    public let row: Row
    public let wait: ReviewWait

    public init(row: Row, wait: ReviewWait) {
        self.row = row
        self.wait = wait
    }
}

/// The two waits the Stats screen leads with: the oldest review asked of the viewer, and the viewer's
/// own PR that has waited longest for a first review.
public struct RightNow: Sendable {
    public let waitingOnMe: RightNowItem?
    public let myLongest: RightNowItem?

    public init(waitingOnMe: RightNowItem?, myLongest: RightNowItem?) {
        self.waitingOnMe = waitingOnMe
        self.myLongest = myLongest
    }

    /// `review` and `mine` are the tabs' rows as listed, so the list's filters apply. Rows without a known
    /// start are skipped; the earliest start wins and a tie keeps list order.
    public static func pick(review: [Row], mine: [Row], me: String, myTeams: Set<String>, now: Date) -> RightNow {
        let owed = review.filter(\.counted)
        let unreviewed = mine.filter { row in
            row.pr.state == .open && !row.pr.isDraft && !row.pr.latestReviews.contains {
                $0.state != .pending && $0.submittedAt != nil && $0.byBot != true
                    && $0.author.lowercased() != me.lowercased()
            }
        }
        return RightNow(
            waitingOnMe: oldest(owed, on: .review, me: me, myTeams: myTeams, now: now),
            myLongest: oldest(unreviewed, on: .mine, me: me, myTeams: myTeams, now: now))
    }

    private static func oldest(_ rows: [Row], on tab: PRTab, me: String, myTeams: Set<String>, now: Date) -> RightNowItem? {
        var best: (item: RightNowItem, since: Date)?
        for row in rows {
            guard let wait = ReviewWait.make(for: row, on: tab, me: me, myTeams: myTeams, now: now),
                let since = wait.since else { continue }
            if best == nil || since < best!.since { best = (RightNowItem(row: row, wait: wait), since) }
        }
        return best?.item
    }
}
