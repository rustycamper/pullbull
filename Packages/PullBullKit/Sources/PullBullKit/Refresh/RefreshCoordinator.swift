import Foundation

// MARK: - Status

public enum RefreshError: Equatable, Sendable {
    /// No connectivity; the only kind a network path coming back retries early.
    case offline
    /// GitHub couldn't be reached for another reason (TLS, a bad response, …).
    case unreachable(URLError.Code)
    /// A 403 that is neither single sign-on nor a rate limit; retried at the poll interval.
    case forbidden
    case unauthorized
    case rateLimited(Date?)
    case ghMissing
    case notLoggedIn(String)
    /// A GitHub App account whose sign-in ended; polling pauses until `refreshNow()` or a restart.
    case signedOut(AccountRef)
    case ssoRequired(URL?)
    case other(String)

    public init(_ error: any Error) {
        switch error {
        case let error as APIError:
            switch error {
            case .network: self = .offline
            case .unreachable(let code): self = .unreachable(code)
            case .forbidden: self = .forbidden
            case .unauthorized: self = .unauthorized
            case .rateLimited(let resetAt): self = .rateLimited(resetAt)
            case .server(let status): self = .other("GitHub server error \(status)")
            case .graphQL(let message), .notFound(let message): self = .other(message)
            case .insufficientScopes: self = .other("Token is missing a required scope")
            case .ssoRequired(let url): self = .ssoRequired(url)
            case .boardForbidden: self = .other("GitHub won't let this sign-in read the board")
            }
        case let error as AuthError:
            switch error {
            case .signedOut(let account): self = .signedOut(account)
            }
        case let error as CredentialStoreError:
            switch error {
            case .locked: self = .other("Keychain is locked")
            case .unsignedBuild: self = .other("Keychain needs a signed build")
            case .keychain(let status): self = .other("Keychain error \(status)")
            }
        case let error as DeviceFlowError:
            // A refresh that failed without ending the sign-in; the next poll tries again.
            switch error {
            case .network: self = .offline
            case .unexpected(let code): self = .other("Couldn't renew the GitHub sign-in (\(code))")
            case .misconfigured: self = .other("Couldn't renew the GitHub sign-in (app misconfigured)")
            case .expired, .denied, .tooManyCodes, .badRefreshToken:
                self = .other("Couldn't renew the GitHub sign-in")
            }
        case let error as GhError:
            switch error {
            case .notInstalled: self = .ghMissing
            case .notLoggedIn(let login): self = .notLoggedIn(login)
            case .failed(let message): self = .other(message)
            }
        default:
            self = .other(error.localizedDescription)
        }
    }

    public var message: String {
        switch self {
        case .offline: "Offline"
        case .unreachable(let code): "Couldn't reach GitHub (\(code.unreachableReason))"
        case .forbidden: "GitHub refused access (403)"
        case .unauthorized: "Token rejected — run gh auth login"
        case .rateLimited(nil): "Rate limited"
        case .rateLimited(let resetAt?): "Rate limited until \(Self.clockTime(resetAt))"
        case .ghMissing: "gh not found"
        case .notLoggedIn(let login): "Log in to \(login) with gh auth login"
        case .signedOut: "Signed out of GitHub"
        case .ssoRequired: "Single sign-on required"
        case .other(let message): message
        }
    }

    /// `message`, naming the org that requires single sign-on when it is known.
    public func message(org: String?) -> String {
        guard case .ssoRequired = self, let org else { return message }
        return "\(org) uses single sign-on. Sign in on GitHub, then Retry"
    }

    /// `message(org:)` for an account from `source`: a GitHub App account gets no `gh` instructions.
    public func message(org: String?, source: AccountSource?) -> String {
        if source == .gitHubApp, case .unauthorized = self { return "GitHub rejected the sign-in" }
        return message(org: org)
    }

    private static func clockTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

/// Whether the loop checks for new activity between full refreshes.
public enum ActivityCheckState: Equatable, Sendable {
    /// No check for this loop (not offered, or found unsupported before).
    case off
    /// Checking, with no answer yet.
    case probing
    /// The check works: new activity starts a full refresh.
    case active
    /// The token can't read notifications; not asked again for this loop.
    case unsupported
}

public struct RefreshStatus: Equatable, Sendable {
    public var lastSuccess: Date?
    public var error: RefreshError?
    public var isRefreshing: Bool
    public var activity: ActivityCheckState
    /// This update is a fast CI follow merged into the last full refresh's snapshot (its `fetchedAt`
    /// and `lastSuccess` unchanged). Set on that one update only.
    public var isCIFollow: Bool

    public init(
        lastSuccess: Date?, error: RefreshError?, isRefreshing: Bool, activity: ActivityCheckState = .off,
        isCIFollow: Bool = false
    ) {
        self.lastSuccess = lastSuccess
        self.error = error
        self.isRefreshing = isRefreshing
        self.activity = activity
        self.isCIFollow = isCIFollow
    }

    /// The data is older than two poll intervals, e.g. because a refresh has not finished.
    public func isStale(now: Date, interval: Duration) -> Bool {
        guard let lastSuccess else { return false }
        let parts = interval.components
        let seconds = TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
        return now.timeIntervalSince(lastSuccess) > 2 * seconds
    }
}

// MARK: - Fetching

public protocol SnapshotFetching: Sendable {
    /// `previous` is the last snapshot for this same account and scope, if any. `board` is fetched only
    /// when it belongs to the scope's owner (`FetchScope.boardOwner`): an org's board in org mode, the
    /// user's own in no-org mode.
    func fetch(
        account: String, scope: FetchScope, board: BoardRef?, canReadProjects: Bool, previous: Snapshot?
    ) async throws -> Snapshot

    /// The pull requests `keys` name, looked up directly rather than searched (`CIFollow`).
    func pullRequests(_ keys: [PRKey], account: String) async throws -> [PullRequest]
}

extension SnapshotFetching {
    public func pullRequests(_ keys: [PRKey], account: String) async throws -> [PullRequest] {
        throw CancellationError()
    }
}

public struct LiveSnapshotFetcher: SnapshotFetching {
    private let api: GitHubAPI
    private let now: @Sendable () -> Date
    private let orgCache = OrgContextCache()
    /// Pages of 50: GitHub search returns at most 1,000 results.
    private static let issuePages = 20
    /// The most issues that left Assigned or Created one poll looks up.
    private static let closedLookups = 10

    public init(api: GitHubAPI, now: @escaping @Sendable () -> Date = Date.init) {
        self.api = api
        self.now = now
    }

    public func fetch(
        account: String, scope: FetchScope, board: BoardRef?, canReadProjects: Bool, previous: Snapshot?
    ) async throws -> Snapshot {
        let started = now()
        let closedSince = Self.day(started.addingTimeInterval(-7 * 86_400))
        let sameOrg = previous?.scope == scope
        // Issue searches keep to the org (`org:`) or, with none, to the user's own repos (`user:`), as
        // do PR searches then; `limited(to:)` below drops what the scope doesn't cover.
        let issueScope = "\(scope.searchQualifier) "
        let prScope = scope.org == nil ? issueScope : ""
        let boardRef = canReadProjects ? board.flatMap { scope.shows($0) ? $0 : nil } : nil
        // Every part runs at once. The first to throw (a PR search, the org context, or an issue search
        // hitting a rate limit or a rejected token) cancels the rest, so no further pages are requested.
        // Issue lists are secondary: like the board, other failures are recorded and never fail the poll.
        let parts = try await withThrowingTaskGroup(of: FetchPart.self) { group in
            group.addTask {
                let resolved = try await orgContext(account: account, scope: scope, previous: previous?.org, at: started)
                return .context(resolved, team: try await teamPRs(resolved))
            }
            group.addTask {
                .requested(try await api.searchPRs("is:open is:pr archived:false \(prScope)review-requested:@me"))
            }
            group.addTask {
                .reviewed(try await api.searchPRs("is:open is:pr archived:false \(prScope)reviewed-by:@me -author:@me"))
            }
            group.addTask { .mine(try await api.searchPRs("is:open is:pr archived:false \(prScope)author:@me")) }
            group.addTask {
                .closed(try await api.searchPRs(
                    "is:pr is:closed archived:false \(prScope)author:@me closed:>=\(closedSince)"))
            }
            group.addTask {
                .assigned(try await issues(
                    "is:open is:issue archived:false \(issueScope)assignee:@me", list: "assigned",
                    assignmentFor: account, previous: sameOrg ? previous?.assignedIssues : nil))
            }
            group.addTask {
                .created(try await issues(
                    "is:open is:issue archived:false \(issueScope)author:@me", list: "created",
                    previous: sameOrg ? previous?.createdIssues : nil))
            }
            group.addTask {
                .board(try await self.board(boardRef, previous: previous))
            }
            var parts = FetchParts()
            for try await part in group { parts.add(part) }
            return parts
        }
        guard let resolved = parts.context else { throw CancellationError() }
        let closed = await closedIssues(
            previous: sameOrg ? previous : nil, assigned: parts.assigned, created: parts.created)
        return Snapshot(
            fetchedAt: started,
            org: resolved,
            reviewCandidates: Self.union(parts.requested, parts.reviewed),
            mine: parts.mine,
            team: parts.team,
            recentlyClosed: parts.closed,
            boardIssues: parts.board.issues,
            boardProject: boardRef?.number,
            boardTitle: parts.board.title,
            boardError: parts.board.error,
            assignedIssues: parts.assigned.issues,
            createdIssues: parts.created.issues,
            boardStatusOptions: parts.board.statusOptions,
            assignedIssuesError: parts.assigned.error,
            createdIssuesError: parts.created.error,
            assignedIssuesFetchedAt: Self.fetchedAt(
                parts.assigned, started: started, previous: previous, previousAt: previous?.assignedIssuesFetchedAt),
            createdIssuesFetchedAt: Self.fetchedAt(
                parts.created, started: started, previous: previous, previousAt: previous?.createdIssuesFetchedAt),
            boardOwner: boardRef?.owner,
            closedIssues: closed?.found,
            pendingClosedLookups: closed.flatMap { $0.pending.isEmpty ? nil : $0.pending },
            boardIds: parts.board.ids
        ).limited(to: scope)
    }

    public func pullRequests(_ keys: [PRKey], account: String) async throws -> [PullRequest] {
        try await api.pullRequests(keys)
    }

    /// The issues that left Assigned or Created since `previous` and are now closed, looked up one by
    /// one: leaving a list can also mean an unassignment or a transfer. An issue the open search still
    /// returns closed (it lags) has left too. A list is compared only when both its searches
    /// succeeded, as a failed one carries an older list forward. A lookup that fails, and any past
    /// `closedLookups`, is `pending`, tried again next poll with `previous`'s pending ones. Nil
    /// without a previous snapshot of this org.
    private func closedIssues(
        previous: Snapshot?, assigned: IssueList, created: IssueList
    ) async -> (found: [BoardIssue], pending: [BoardIssue])? {
        guard let previous else { return nil }
        let pairs = [
            (previous.assignedIssues, previous.assignedIssuesError, assigned),
            (previous.createdIssues, previous.createdIssuesError, created),
        ]
        var gone = previous.pendingClosedLookups ?? []
        var seen = Set(gone.map(\.key))
        for (before, beforeError, now) in pairs {
            guard let before, beforeError == nil, let issues = now.issues, now.error == nil else { continue }
            let still = Set(issues.filter(\.isOpen).map(\.key))
            for issue in before where issue.isOpen && !still.contains(issue.key) && seen.insert(issue.key).inserted {
                gone.append(issue)
            }
        }
        guard !gone.isEmpty else { return ([], []) }
        let api = api
        let batch = Array(gone.prefix(Self.closedLookups))
        return await withTaskGroup(of: (BoardIssue, Result<BoardIssue?, any Error>).self) { group in
            for issue in batch {
                group.addTask {
                    do { return (issue, .success(try await api.closedIssue(issue.key))) }
                    catch { return (issue, .failure(error)) }
                }
            }
            var found: [BoardIssue] = []
            var pending = Array(gone.dropFirst(Self.closedLookups))
            for await (listed, result) in group {
                switch result {
                case .success(let issue?) where !issue.isOpen: found.append(issue)
                case .success: break
                case .failure: pending.append(listed)
                }
            }
            return (found, pending)
        }
    }

    /// `started` when the issue search succeeded. A failed one keeps the previous list, and with it
    /// the time that list was fetched (`previousAt`, or the previous `fetchedAt` for a cache from
    /// before it was stored).
    private static func fetchedAt(
        _ list: IssueList, started: Date, previous: Snapshot?, previousAt: Date?
    ) -> Date? {
        guard list.error != nil else { return started }
        guard list.issues != nil, let previous else { return nil }
        return previousAt ?? previous.fetchedAt
    }

    /// Every page of an issue search. A failure, or a list longer than the page cap (search itself
    /// stops at 1,000 results, which the cap covers), is recorded rather than thrown, and `previous`
    /// (this account and org's last list, nil when never fetched) is kept unchanged instead of passing
    /// a partial list for the whole. Cancellation, a rate limit, a rejected token, single sign-on and
    /// a sign-in or Keychain failure are thrown, so the poll waits, reauthenticates or pauses as it does
    /// when a PR search hits them.
    private func issues(
        _ query: String, list: String, assignmentFor viewer: String? = nil, previous: [BoardIssue]?
    ) async throws -> IssueList {
        do {
            // Assigned and Created carry what issue notifications read.
            let found = try await api.searchIssues(
                query, maxPages: Self.issuePages, assignmentFor: viewer, activity: true)
            guard !found.hasMore else { return (previous, "incomplete \(list) issues list") }
            return (found.issues, nil)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as APIError where error.failsThePoll {
            throw error
        } catch let error where Self.isAuthFailure(error) {
            throw error
        } catch {
            return (previous, RefreshError(error).message)
        }
    }

    private func orgContext(account: String, scope: FetchScope, previous: OrgContext?, at date: Date) async throws
        -> OrgContext {
        if let previous, let reused = await orgCache.reusable(account: account, scope: scope, previous: previous, at: date) {
            return reused
        }
        let context = switch scope {
        case .org(let org): try await api.orgContext(org: org)
        case .personal: try await api.personalContext().limited(to: scope)
        }
        await orgCache.store(context, account: account, at: date)
        return context
    }

    /// Nothing for the personal scope, which has no members.
    private func teamPRs(_ context: OrgContext) async throws -> [PullRequest] {
        guard !context.isPersonal else { return [] }
        let authors = context.members.filter { $0.caseInsensitiveCompare(context.viewer) != .orderedSame }
        guard !authors.isEmpty else { return [] }
        let qualifiers = authors.map { "author:\($0)" }.joined(separator: " ")
        return try await api.searchPRs("is:open is:pr archived:false org:\(context.org) \(qualifiers)")
    }

    /// The board is optional: a failure other than cancellation or a sign-in failure is recorded, not
    /// thrown. The previous items and Status options are kept only when they belong to the same
    /// board (owner and number). Without a board, or when it failed with no previous fetch of it, the
    /// options are nil (never fetched).
    private func board(_ board: BoardRef?, previous: Snapshot?) async throws -> BoardResult {
        guard let board else { return (nil, nil, [], nil, nil) }
        do {
            let fetched = try await api.board(board)
            return (fetched.title, fetched.statusOptions, fetched.issues, nil, fetched.ids)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error where Self.isAuthFailure(error) {
            throw error
        } catch {
            let message = RefreshError(error).message
            guard let previous, board.matches(previous.board) else { return (nil, nil, [], message, nil) }
            // No title while the board can't be read: search may list issues that aren't on it.
            return (nil, previous.boardStatusOptions, previous.boardIssues, message, previous.boardIds)
        }
    }

    /// The account's token couldn't be had: signed out, the Keychain unreadable, or a failed renewal.
    /// These hit every query alike, so they fail the poll rather than one list.
    private static func isAuthFailure(_ error: any Error) -> Bool {
        error is AuthError || error is CredentialStoreError || error is DeviceFlowError
    }

    private static func union(_ first: [PullRequest], _ second: [PullRequest]) -> [PullRequest] {
        var seen = Set<PRKey>()
        return (first + second).filter { seen.insert($0.key).inserted }
    }

    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

/// One concurrent part of a fetch.
private enum FetchPart: Sendable {
    case context(OrgContext, team: [PullRequest])
    case requested([PullRequest]), reviewed([PullRequest]), mine([PullRequest]), closed([PullRequest])
    case assigned(IssueList), created(IssueList)
    case board(BoardResult)
}

private typealias IssueList = (issues: [BoardIssue]?, error: String?)
private typealias BoardResult = (
    title: String?, statusOptions: [StatusOption]?, issues: [BoardIssue], error: String?, ids: BoardIds?
)

/// The parts of a fetch as they finish; every field is set once the group finishes without throwing.
private struct FetchParts {
    var context: OrgContext?
    var team: [PullRequest] = []
    var requested: [PullRequest] = []
    var reviewed: [PullRequest] = []
    var mine: [PullRequest] = []
    var closed: [PullRequest] = []
    var assigned: IssueList = (nil, nil)
    var created: IssueList = (nil, nil)
    var board: BoardResult = (nil, nil, [], nil, nil)

    mutating func add(_ part: FetchPart) {
        switch part {
        case .context(let context, let team): (self.context, self.team) = (context, team)
        case .requested(let prs): requested = prs
        case .reviewed(let prs): reviewed = prs
        case .mine(let prs): mine = prs
        case .closed(let prs): closed = prs
        case .assigned(let list): assigned = list
        case .created(let list): created = list
        case .board(let board): self.board = board
        }
    }
}

private extension APIError {
    /// Account-wide failures the coordinator handles itself (a rate-limit wait, a token refresh, an
    /// SSO session).
    var failsThePoll: Bool {
        switch self {
        case .rateLimited, .unauthorized, .ssoRequired: true
        case .network, .unreachable, .server, .forbidden, .graphQL, .insufficientScopes, .boardForbidden, .notFound: false
        }
    }
}

/// Remembers when the org (or personal) context was fetched, so it is reused for at most an hour and
/// only for the same account and scope whose snapshot the caller passes back in.
private actor OrgContextCache {
    private static let maxAge: TimeInterval = 3600
    private var entry: (account: String, context: OrgContext, fetchedAt: Date)?

    func reusable(account: String, scope: FetchScope, previous: OrgContext, at date: Date) -> OrgContext? {
        guard let entry, entry.account == account, entry.context.scope == scope, entry.context == previous else {
            return nil
        }
        let age = date.timeIntervalSince(entry.fetchedAt)
        return age >= 0 && age < Self.maxAge ? entry.context : nil
    }

    func store(_ context: OrgContext, account: String, at date: Date) {
        entry = (account, context, date)
    }
}

// MARK: - Coordinator

/// Runs the poll loop. `updates` has a single consumer: it gets the cached snapshot when a loop
/// starts, a marker when each attempt starts (`isRefreshing`), and the result of each attempt.
/// A failed attempt re-emits the last snapshot with `error` set; cached data is never replaced by nil.
public actor RefreshCoordinator {
    public nonisolated let updates: AsyncStream<(Snapshot?, RefreshStatus)>

    private struct Config: Sendable, Equatable {
        let account: String
        let scope: FetchScope
        let chosenBoard: BoardRef?
        let canReadProjects: Bool
        let interval: Duration
        /// Mine's pending CI is looked at every `CIFollow.interval` between full refreshes.
        let followsPendingCI: Bool

        /// The board this config fetches, if any: the chosen one when the token can read it and it
        /// belongs to the scope's owner.
        var board: BoardRef? { canReadProjects ? chosenBoard.flatMap { scope.shows($0) ? $0 : nil } : nil }
    }

    private static let firstRetry: Duration = .seconds(15)
    private static let maxRateLimitWait: TimeInterval = 3600

    private let continuation: AsyncStream<(Snapshot?, RefreshStatus)>.Continuation
    private let fetcher: any SnapshotFetching
    private let store: SnapshotStore
    private let clock: any Clock<Duration>
    private let now: @Sendable () -> Date
    private let showsCache: @Sendable () async -> Bool

    private var config: Config?
    private var generation = 0
    private var snapshot: Snapshot?
    private var status = RefreshStatus(lastSuccess: nil, error: nil, isRefreshing: false)
    private var failures = 0
    private var inFlight: (generation: Int, task: Task<Void, Never>)?
    private var timer: Task<Void, Never>?
    /// The loop's activity check, its next wait, and the timer that runs it (one at a time).
    private var activity: (any ActivityChecking)?
    private var pollInterval = ActivityCheck.minimumPollInterval
    private var checkTimer: Task<Void, Never>?
    /// When the attempt in flight, and the last successful one, started: activity from before then
    /// is already in the data.
    private var inFlightStarted: Date?
    private var lastSuccessStarted: Date?
    /// Activity newer than the start of the attempt in flight: one more refresh once it succeeds.
    private var refreshAgain = false
    /// Loads and emits the cached snapshot for the current generation; every attempt waits for it.
    private var cacheLoad: (generation: Int, task: Task<Void, Never>)?
    /// When a network path change refreshes, and the debounce timer before that refresh. Each timer
    /// carries the token current when it was set; a timer replaced or cancelled after its sleep ended
    /// finds a newer token and does nothing.
    private var recovery = NetworkRecovery()
    private var recoveryTimer: Task<Void, Never>?
    private(set) var recoveryToken = 0
    /// The fast CI follow: what it follows, its timer, and when the next full refresh is due. A failed
    /// follow sets `followBlocked` until a full refresh succeeds. `fullStarts` counts full attempts, so a
    /// follow that one overtook while it ran is dropped.
    private var ciFollow = CIFollow()
    private var followTimer: Task<Void, Never>?
    private var followBlocked = false
    private var nextFullAt: Date?
    private var fullStarts = 0

    /// Callers currently waiting on someone else's in-flight fetch.
    private(set) var joinedWaiters = 0
    /// Fetch results discarded because the loop was restarted or stopped while they ran.
    private(set) var droppedResults = 0
    /// Follow results discarded because a full refresh started, or the loop changed, while they ran.
    private(set) var droppedFollows = 0
    /// The snapshot the loop currently holds (tests).
    var heldSnapshot: Snapshot? { snapshot }
    /// The status the loop last emitted (tests).
    var heldStatus: RefreshStatus { status }

    public init(
        fetcher: any SnapshotFetching,
        store: SnapshotStore,
        clock: any Clock<Duration> = ContinuousClock(),
        now: @Sendable @escaping () -> Date = Date.init,
        showsCache: @Sendable @escaping () async -> Bool = { true }
    ) {
        self.fetcher = fetcher
        self.store = store
        self.clock = clock
        self.now = now
        self.showsCache = showsCache
        (updates, continuation) = AsyncStream.makeStream(of: (Snapshot?, RefreshStatus).self)
    }

    deinit {
        timer?.cancel()
        checkTimer?.cancel()
        recoveryTimer?.cancel()
        followTimer?.cancel()
        inFlight?.task.cancel()
        continuation.finish()
    }

    /// Cancels any previous loop and starts polling for this account and scope. Results of fetches
    /// started before this call are dropped. With `activity` (a fresh checker for this loop), new
    /// activity found between polls starts a full refresh at once; the poll interval is unchanged. With
    /// `followsPendingCI`, Mine's pending CI is looked at between polls (`CIFollow`).
    public func start(
        account: String, scope: FetchScope, board: BoardRef?, canReadProjects: Bool, interval: Duration,
        activity: (any ActivityChecking)? = nil, followsPendingCI: Bool = false
    ) {
        cancelLoop()
        config = Config(
            account: account, scope: scope, chosenBoard: board,
            canReadProjects: canReadProjects, interval: interval, followsPendingCI: followsPendingCI)
        snapshot = nil
        status = RefreshStatus(
            lastSuccess: nil, error: nil, isRefreshing: false, activity: activity == nil ? .off : .probing)
        failures = 0
        self.activity = activity
        pollInterval = ActivityCheck.minimumPollInterval
        let current = generation
        cacheLoad = (current, Task { [weak self] in await self?.loadCache(current) })
        timer = Task { [weak self] in await self?.tick(current) }
        if activity != nil { scheduleCheck(after: .zero, current) }
    }

    /// Changes the board, project access or interval of the running loop without restarting it: the
    /// snapshot and status (including an error) stay. Turning the board off or switching to another
    /// drops the old board's items at once; a new board is fetched once, after the fetch in flight if
    /// there is one. A new interval counts from the last success. Turning `followsPendingCI` off
    /// cancels the next follow; turning it on schedules one when Mine has pending CI.
    public func update(board: BoardRef?, canReadProjects: Bool, interval: Duration, followsPendingCI: Bool = false) {
        guard let old = config else { return }
        let new = Config(
            account: old.account, scope: old.scope, chosenBoard: board,
            canReadProjects: canReadProjects, interval: interval, followsPendingCI: followsPendingCI)
        guard new != old else { return }
        config = new
        if let current = snapshot, current.boardStatus != .none, !(new.board?.matches(current.board) ?? false) {
            snapshot = Self.withoutBoard(current)
            emit()
        }
        let current = generation
        if new.followsPendingCI != old.followsPendingCI { scheduleFollow(current) }
        // The attempt in flight reschedules when it ends, refetching if the board changed meanwhile.
        if let inFlight, inFlight.generation == current { return }
        // During backoff or a rate-limit wait the pending retry picks the new config up.
        if new.board != nil, new.board != old.board, failures == 0 {
            schedule(after: .zero, current)
        } else if new.interval != old.interval, failures == 0 {
            let elapsed = status.lastSuccess.map { now().timeIntervalSince($0) } ?? 0
            schedule(after: max(.zero, new.interval - .seconds(max(elapsed, 0))), current)
        }
    }

    /// Fetches now, or waits for the fetch already in flight.
    public func refreshNow() async {
        await attempt()
    }

    /// Skips the fetch while a rate limit is still in effect (the scheduled retry handles it) and
    /// while signed out (only `refreshNow()` resumes).
    public func refreshIfOlderThan(_ age: Duration) async {
        guard config != nil else { return }
        if case .rateLimited(let resetAt?) = status.error, resetAt > now() { return }
        if case .signedOut = status.error { return }
        if let last = status.lastSuccess, now().timeIntervalSince(last) < Self.seconds(age) { return }
        await attempt()
    }

    /// Runs the activity check now rather than at its next time (after wake), if the loop has one.
    public func checkActivitySoon() {
        guard config != nil, status.activity == .probing || status.activity == .active else { return }
        scheduleCheck(after: .zero, generation)
    }

    /// Marks a wake: until a refresh succeeds, the network path coming back refreshes (the wake's own
    /// refresh usually runs before Wi-Fi reconnects).
    public func didWake() {
        recovery.didWake()
    }

    /// A network path change (`NWPathMonitor`). Coming back after an offline failure or a wake
    /// refreshes once no other change has arrived for `NetworkRecovery.debounce`, joining a fetch in
    /// flight as `refreshNow()` does, then runs the activity check. Other changes refresh nothing.
    /// Skipped, like `refreshIfOlderThan`, during a rate-limit wait and while signed out.
    public func networkPathChanged(satisfied: Bool) {
        let due = recovery.pathChanged(satisfied: satisfied, lastFailedOffline: status.error == .offline)
        cancelRecovery()
        guard due, config != nil else {
            recovery.clearDue()
            return
        }
        scheduleRecovery()
    }

    /// Returns once the fetch or follow in flight, if any, has finished: after that no poll writes the
    /// cache, so a caller may delete it.
    public func stop() async {
        let running = inFlight?.task
        let following = followTimer
        cancelLoop()
        config = nil
        activity = nil
        await running?.value
        await following?.value
    }

    // MARK: Loop

    private func cancelLoop() {
        generation += 1
        timer?.cancel()
        timer = nil
        nextFullAt = nil
        cancelFollow()
        ciFollow = CIFollow()
        followBlocked = false
        checkTimer?.cancel()
        checkTimer = nil
        inFlight?.task.cancel()
        inFlight = nil
        inFlightStarted = nil
        lastSuccessStarted = nil
        refreshAgain = false
        cacheLoad?.task.cancel()
        cacheLoad = nil
        cancelRecovery()
        recovery.clearDue()
    }

    private func loadCache(_ expected: Int) async {
        guard let config, expected == generation else { return }
        // `showsCache` false (an app account found signed out): the loop starts with no snapshot.
        let cached = await showsCache() ? await store.load(account: config.account, scope: config.scope) : nil
        guard expected == generation else { return }
        // A board turned off or changed since this was saved isn't shown (its number may be another
        // owner's board); a personal cache shows only what the scope covers now (its installation's
        // repositories may have changed).
        let scoped = cached?.limited(to: config.scope)
        let board = self.config?.board
        snapshot = scoped.map { Self.keepingOnly(board, in: $0) }
        status.lastSuccess = cached?.fetchedAt
        emit()
    }

    // MARK: Network recovery

    private func cancelRecovery() {
        recoveryToken += 1
        recoveryTimer?.cancel()
        recoveryTimer = nil
    }

    private func scheduleRecovery() {
        cancelRecovery()
        let token = recoveryToken
        let clock = clock
        recoveryTimer = Task { [weak self] in
            do {
                try await clock.sleep(for: NetworkRecovery.debounce)
            } catch {
                return
            }
            await self?.recover(token)
        }
    }

    /// The debounce ran out (internal for tests: a stale `token` does nothing).
    func recover(_ token: Int) async {
        guard token == recoveryToken, config != nil else { return }
        recoveryTimer = nil
        recovery.clearDue()
        if case .rateLimited(let resetAt?) = status.error, resetAt > now() { return }
        if case .signedOut = status.error { return }
        await attempt()
        checkActivitySoon()
    }

    private func tick(_ expected: Int) async {
        guard expected == generation else { return }
        await attempt()
    }

    private func attempt() async {
        let current = generation
        if let cacheLoad, cacheLoad.generation == current { await cacheLoad.task.value }
        guard let config, current == generation else { return }
        if let inFlight, inFlight.generation == current {
            joinedWaiters += 1
            await inFlight.task.value
            joinedWaiters -= 1
            return
        }
        status.isRefreshing = true
        emit()
        let previous = snapshot
        let started = now()
        let task = Task { await self.perform(current, config, previous: previous, started: started) }
        inFlight = (current, task)
        fullStarts += 1
        inFlightStarted = started
        await task.value
    }

    private func perform(_ expected: Int, _ config: Config, previous: Snapshot?, started: Date) async {
        guard expected == generation else { return }
        var result: Result<Snapshot, any Error>
        do {
            result = .success(try await fetcher.fetch(
                account: config.account, scope: config.scope, board: config.chosenBoard,
                canReadProjects: config.canReadProjects, previous: previous))
        } catch {
            result = .failure(error)
        }
        guard expected == generation else {
            droppedResults += 1
            return
        }
        // A board switched or turned off while this ran is never saved under the new one.
        if case .success(let fresh) = result {
            result = .success(Self.keepingOnly((self.config ?? config).board, in: fresh))
        }
        if case .success(let fresh) = result {
            try? await store.save(fresh, account: config.account, scope: config.scope)
            guard expected == generation else {
                droppedResults += 1
                return
            }
        }
        // The config may have been updated in place while the fetch or the save ran; nothing below
        // suspends, so an update arriving later finds no attempt in flight and reschedules itself.
        let latest = self.config ?? config
        if case .success(let fresh) = result { result = .success(Self.keepingOnly(latest.board, in: fresh)) }
        inFlight = nil
        inFlightStarted = nil
        status.isRefreshing = false
        // A failed attempt's backoff retry refreshes anyway; a cancelled one retries at once instead.
        let again = refreshAgain
        refreshAgain = false

        var delay: Duration
        switch result {
        case .success(let fresh):
            snapshot = fresh
            failures = 0
            status.lastSuccess = fresh.fetchedAt
            status.error = nil
            lastSuccessStarted = started
            recovery.refreshSucceeded()
            ciFollow.observe(fresh, now: now())
            followBlocked = false
            delay = again ? .zero : latest.interval
        case .failure(is CancellationError):
            // After a failure, the wait that failure sets: a 403 or a rate limit never retries early.
            delay = again ? .zero : status.error.map { retryDelay(after: $0, interval: latest.interval) } ?? latest.interval
        case .failure(let error):
            failures += 1
            let mapped = RefreshError(error)
            status.error = mapped
            // A failing poll stops following until a full refresh succeeds again.
            cancelFollow()
            if case .signedOut = mapped {
                // Retrying can't sign back in: nothing is scheduled until `refreshNow()` or a restart.
                timer?.cancel()
                timer = nil
                nextFullAt = nil
                emit()
                return
            }
            delay = retryDelay(after: mapped, interval: latest.interval)
            if mapped == .offline, recovery.attemptFailedOffline() { scheduleRecovery() }
        }
        if latest.board != nil, latest.board != config.board, failures == 0 { delay = .zero }
        emit()
        schedule(after: delay, expected)
        if case .success = result { scheduleFollow(expected) }
    }

    private func schedule(after delay: Duration, _ expected: Int) {
        timer?.cancel()
        nextFullAt = now().addingTimeInterval(Self.seconds(delay))
        let clock = clock
        timer = Task { [weak self] in
            do {
                try await clock.sleep(for: delay)
            } catch {
                return
            }
            await self?.tick(expected)
        }
    }

    // MARK: Fast CI follow

    private func cancelFollow() {
        followTimer?.cancel()
        followTimer = nil
    }

    /// Sets the follow timer when following is on, not blocked by a failed follow, the last poll
    /// succeeded and Mine has pending CI to follow; otherwise cancels it.
    private func scheduleFollow(_ expected: Int) {
        cancelFollow()
        guard expected == generation, let config, config.followsPendingCI, !followBlocked, status.error == nil,
              let snapshot, !ciFollow.selection(in: snapshot, now: now()).isEmpty
        else { return }
        let clock = clock
        followTimer = Task { [weak self] in
            do {
                try await clock.sleep(for: CIFollow.interval)
            } catch {
                return
            }
            await self?.follow(expected)
        }
    }

    /// One follow, run by `followTimer` (which `stop()` waits for): looks Mine's pending pull requests
    /// up, merges them into the snapshot, saves it and emits it as a full refresh would, with
    /// `isCIFollow` set (nothing when nothing changed). Skipped, and not rescheduled (the next full
    /// refresh schedules again), when `CIFollow.shouldRun` says so. A failure is silent and blocks
    /// following until a full refresh succeeds. The result is dropped when it was cancelled, or a full
    /// refresh started while it ran, since that refresh's data is as new or newer.
    private func follow(_ expected: Int) async {
        guard expected == generation, let config, config.followsPendingCI, !followBlocked, let snapshot else { return }
        let fullInFlight = inFlight?.generation == expected
        guard CIFollow.shouldRun(now: now(), nextFullAt: nextFullAt, fullInFlight: fullInFlight, error: status.error)
        else { return }
        let keys = ciFollow.selection(in: snapshot, now: now())
        guard !keys.isEmpty else { return }
        let starts = fullStarts
        let result: Result<[PullRequest], any Error>
        do {
            result = .success(try await fetcher.pullRequests(keys, account: config.account))
        } catch {
            result = .failure(error)
        }
        guard !Task.isCancelled, expected == generation, starts == fullStarts, inFlight == nil,
              status.error == nil, self.config?.followsPendingCI == true, let current = self.snapshot
        else {
            droppedFollows += 1
            return
        }
        guard case .success(let followed) = result else {
            followBlocked = true
            return
        }
        let merged = current.merging(followed: followed)
        if merged != current {
            try? await store.save(merged, account: config.account, scope: config.scope)
            // A full refresh that started during the save saves and emits its own data; a stop or the
            // toggle turned off during it drops the result too.
            guard !Task.isCancelled, expected == generation, starts == fullStarts, inFlight == nil,
                  self.config?.followsPendingCI == true, let latest = self.snapshot
            else {
                droppedFollows += 1
                return
            }
            // The board may have been turned off meanwhile: merged into what the loop holds now.
            self.snapshot = latest.merging(followed: followed)
            status.isCIFollow = true
            emit()
            status.isCIFollow = false
        }
        ciFollow.observe(self.snapshot ?? merged, now: now())
        scheduleFollow(expected)
    }

    // MARK: Activity check

    private func scheduleCheck(after delay: Duration, _ expected: Int) {
        checkTimer?.cancel()
        let clock = clock
        checkTimer = Task { [weak self] in
            do {
                try await clock.sleep(for: delay)
            } catch {
                return
            }
            await self?.checkActivity(expected)
        }
    }

    /// One check. New activity starts a full refresh, or one more after the one in flight; a success
    /// restarts the poll timer, so the next timed poll counts from it. Activity older than the last
    /// refresh's start is already shown and refreshes nothing. A failed check (offline, a 5xx, a rate
    /// limit, a rejected token) changes nothing: the polls own the error state, and the check simply
    /// runs again later. While a poll is failing, its retries run as without the check.
    private func checkActivity(_ expected: Int) async {
        guard expected == generation, let activity,
              status.activity == .probing || status.activity == .active
        else { return }
        guard status.error == nil else {
            scheduleCheck(after: pollInterval, expected)
            return
        }
        let result: ActivityCheck
        do {
            result = try await activity.check()
        } catch is CancellationError {
            return
        } catch {
            guard expected == generation else { return }
            var wait = pollInterval
            if case .rateLimited(let resetAt?) = error as? APIError {
                wait = max(wait, .seconds(min(max(resetAt.timeIntervalSince(now()), 0), Self.maxRateLimitWait)))
            }
            scheduleCheck(after: wait, expected)
            return
        }
        guard expected == generation else { return }
        pollInterval = result.pollInterval
        switch result.change {
        case .unsupported:
            // This task is the check timer; nothing reschedules it.
            checkTimer = nil
            status.activity = .unsupported
            emit()
            return
        case .changed:
            // Only activity a refresh may not have read: newer than the start of the one in flight
            // (then one more after it), else of the last successful one.
            if inFlight?.generation == expected {
                if ActivityCheck.isNewer(result.modifiedAt, than: inFlightStarted) { refreshAgain = true }
            } else if ActivityCheck.isNewer(result.modifiedAt, than: lastSuccessStarted) {
                Task { [weak self] in await self?.attempt() }
            }
        case .unchanged:
            break
        }
        if status.activity != .active {
            status.activity = .active
            emit()
        }
        scheduleCheck(after: pollInterval, expected)
    }

    /// The rate limit's reset; the poll interval after a 403, which retrying sooner won't change; else
    /// the backoff.
    private func retryDelay(after error: RefreshError, interval: Duration) -> Duration {
        switch error {
        case .rateLimited(let resetAt?):
            let wait = min(max(resetAt.timeIntervalSince(now()), Self.seconds(Self.firstRetry)), Self.maxRateLimitWait)
            return .seconds(wait)
        case .forbidden:
            return interval
        default:
            return backoff(interval)
        }
    }

    /// `min(15s × 2^(failures−1), interval)`.
    private func backoff(_ interval: Duration) -> Duration {
        let exponent = min(max(failures - 1, 0), 16)
        return min(Self.firstRetry * (1 << exponent), interval)
    }

    /// `snapshot`, without its board unless that is `board`.
    private static func keepingOnly(_ board: BoardRef?, in snapshot: Snapshot) -> Snapshot {
        snapshot.boardStatus == .none || board?.matches(snapshot.board) == true ? snapshot : withoutBoard(snapshot)
    }

    private static func withoutBoard(_ snapshot: Snapshot) -> Snapshot {
        var snapshot = snapshot
        snapshot.boardIssues = []
        snapshot.boardProject = nil
        snapshot.boardOwner = nil
        snapshot.boardTitle = nil
        snapshot.boardError = nil
        snapshot.boardStatusOptions = nil
        return snapshot
    }

    private func emit() {
        continuation.yield((snapshot, status))
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let parts = duration.components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
