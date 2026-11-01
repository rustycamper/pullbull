# Edit Assignees and Labels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add and remove an issue's assignees and labels from PullBull: ⌥⌘A / ⌥⌘L, a multi-select picker that applies when it closes, the right-click menu and the detail, with ⌘Z and the failure line Status already has.

**Architecture:** The kit gains candidate fetching (`GitHubAPI.labelCandidates` / `assigneeCandidates`), a pure picker model (`SetPicker`), a sender (`SetEditor`) and partial-result handling in `EditSession`. The app reuses the Status picker's layer, anchor, `run` path, `EditSelection` and failure line; the picker layer shows either picker. Views stay thin.

**Tech Stack:** Swift 6, macOS 14, SwiftUI/AppKit, Swift Testing in PullBullKit, GitHub GraphQL.

**Spec:** `docs/superpowers/specs/2026-10-31-edit-status-assignees-labels-design.md` (delivery step 3). Steps 1 (#27) and 2 (#28) are merged.

## Global Constraints

- **Issues only** (user decision, 2026-11-01). Pull requests stay read-only: no assignee or label key, menu item or clickable field on PR rows or the PR detail.
- PullBull writes exactly: a board item's Status, assignees and labels, each only when the user picks a value.
- Labels and assignees go as a diff (added, removed), never "replace with this set"; both halves in one request (`GitHubAPI.changeLabels` / `changeAssignees`, already merged).
- GitHub allows at most 10 assignees (`SetPicker.assigneeLimit = 10`).
- Candidates are kept in memory for the session, never written to disk.
- Logic lives in PullBullKit with tests; the app has no test target, so app tasks are verified by a clean build.
- CI fails on Swift warnings. No TODO comments, no `print`.
- Copy follows the spec's wording; failure text comes from `EditMessage` (already has labels, assignees and partial wording).

Commands:
- Kit tests: `cd Packages/PullBullKit && swift test --filter <Suite> 2>&1 | tail -20`; whole suite: `cd Packages/PullBullKit && swift test 2>&1 | grep -E "error:|warning:|recorded an issue|Test run with"`.
- App build: from the worktree root, `xcodegen generate >/dev/null && xcodebuild build -scheme PullBull -derivedDataPath build 2>&1 | grep -E "warning:|error:|BUILD" | grep -v appintents | sort -u`. Expected: `** BUILD SUCCEEDED **` and no `warning:` lines.

## Review Focus

1. Candidates arriving after the user has filtered or ticked (a background refetch, an assignee query past 100) keep the ticks, the row order and the highlighted row: nothing jumps under the cursor. → Task 2 `aLaterLoadKeepsTicksOrderAndSelection`.
2. A shown label or assignee with no candidate (a renamed or deleted label, an assignee outside the first 100 whose lookup failed) shows ticked and can't be unticked, so an edit never sends a removal without an ID. → Task 2 `aCurrentValueWithoutCandidateIsTickedAndLocked`.
3. GitHub applies one half of an edit: only that half stays on screen and only it is undone. → Task 3 `partlyAppliedKeepsTheAppliedHalfAndArmsUndoForIt`.
4. Closing the picker by hiding the popover applies the ticks, like a click outside (spec: "Closing applies all the toggles"); switching accounts drops it without sending. → Task 5, app ruling; reviewer checks `popoverDidHide` and `clearAccountData`.
5. A candidate fetch that lands after the picker closed, or after it reopened on another issue or field, or after an account switch, changes nothing. → Task 5, guarded by key + field + account; reviewer checks.

---

### Task 1: Candidate fetching

**Files:**
- Create: `Packages/PullBullKit/Sources/PullBullKit/Edit/SetCandidate.swift`
- Modify: `Packages/PullBullKit/Sources/PullBullKit/GraphQL/Mutations.swift` (two queries, beside `projectItems` and `nodeId`)
- Modify: `Packages/PullBullKit/Sources/PullBullKit/GraphQL/GitHubAPI.swift` (MARK: Writes section)
- Test: `Packages/PullBullKit/Tests/PullBullKitTests/CandidateQueryTests.swift` (copy `QueueTransport` from `MutationTests.swift`)

**Interfaces:**
- Produces:
  ```swift
  /// A label or a person the picker offers: `name` is the label name or the login.
  public struct SetCandidate: Equatable, Sendable, Identifiable {
      public let id: String          // node ID, which the mutations take
      public let name: String
      public let detail: String?     // a label's description
      public let color: String?      // a label's 6-hex colour
      public let avatarURL: URL?     // a person's avatar
      public init(id: String, name: String, detail: String? = nil, color: String? = nil, avatarURL: URL? = nil)
  }
  public struct SetCandidates: Equatable, Sendable {
      public let all: [SetCandidate]      // the repo's labels, or assignable people
      public let current: [SetCandidate]  // the issue's own, with IDs, as GitHub has them now
      public let complete: Bool           // false when GitHub had more than were read
      public init(all: [SetCandidate], current: [SetCandidate], complete: Bool)
  }
  extension GitHubAPI {
      public static let maxLabelPages = 10
      public func labelCandidates(for key: PRKey) async throws -> SetCandidates
      public func assigneeCandidates(for key: PRKey, query: String?) async throws -> SetCandidates
  }
  ```

- [ ] **Step 1: Write the failing tests** in `CandidateQueryTests`:
  - `labelsReadEveryPageInNameOrder`: two responses, page 1 `hasNextPage:true endCursor:"c1"` with labels `bug`, `docs` and the issue's labels `[bug]`; page 2 `hasNextPage:false` with `triage`. Expect `all.map(\.name) == ["bug","docs","triage"]`, `current.map(\.id) == ["LA_bug"]`, `complete == true`, the second request's `after == "c1"`, the query text contains `orderBy:{field:NAME,direction:ASC}`, and `color`/`detail` come from `color`/`description`.
  - `labelsStopAtTheLastPage`: 10 responses all `hasNextPage:true`; expect 10 requests and `complete == false`.
  - `assigneesReadTheFirstHundredAndTheIssuesOwn`: one response with `assignableUsers` (`alice`, `bob`, `pageInfo.hasNextPage:true`) and `issue.assignees` `[carol]`; expect `all.map(\.name) == ["alice","bob"]`, `current.map(\.name) == ["carol"]`, `avatarURL` parsed, `complete == false`, variables `first`-free with `query` absent.
  - `assigneeQuerySendsTheFilter`: `assigneeCandidates(for:query:"al")` sends variable `q == "al"`.
  - `aMissingIssueHasNoCurrentValues`: `issue: null` with a repository present → `current == []`, `all` and `complete` read as usual, no throw.
  - `laterLabelPagesSkipTheIssue`: the first request sends `withIssue == true`, the second `false`, and neither sends `after` on page 1.
  - `aMissingRepositoryThrowsNotFound`: `repository: null` → throws `APIError.notFound`.
- [ ] **Step 2: Run** `swift test --filter CandidateQueryTests`. Expected: compile failure, `labelCandidates` not found.
- [ ] **Step 3: Implement.** Queries take `$owner`, `$name`, `$n` (the issue number), as `Mutations.nodeId` does.
  - `Mutations.labelCandidates`, with variables `$owner:String!, $name:String!, $n:Int!, $after:String, $withIssue:Boolean!`: `repository(owner,name){ issue(number:$n) @include(if:$withIssue){labels(first:100){nodes{id name color description}}} labels(first:100, after:$after, orderBy:{field:NAME,direction:ASC}){nodes{id name color description} pageInfo{hasNextPage endCursor}} }`.
    - `withIssue` is true on page 1 only, and `after` is omitted on page 1.
    - Stop after `maxLabelPages` pages.
    - An issue's own labels past 100 are not read; that's a known limit.
  - `Mutations.assigneeCandidates`, with `$q:String` nullable: `repository(owner,name){ issue(number:$n){assignees(first:10){nodes{id login avatarUrl}}} assignableUsers(first:100, query:$q){nodes{id login avatarUrl} pageInfo{hasNextPage}} }`; send `q` only when `query` is non-empty.
  - A null `repository` throws `APIError.notFound("\(key.repo) not found")`; use `execute` like `nodeId(of:)`.
- [ ] **Step 4: Run** `swift test --filter CandidateQueryTests`. Expected: all pass.
- [ ] **Step 5: Commit** `git add` the three source files and the test; message `Candidates for the assignee and label pickers`.

---

### Task 2: SetPicker model

**Files:**
- Create: `Packages/PullBullKit/Sources/PullBullKit/Edit/SetPicker.swift`
- Test: `Packages/PullBullKit/Tests/PullBullKitTests/SetPickerTests.swift`

**Interfaces:**
- Consumes: `SetCandidate`, `SetCandidates` (Task 1); `EditField`, `EditPermission`, `EditChange`, `LabelRef`, `PersonRef` (merged).
- Produces:
  ```swift
  public struct SetPickerRow: Equatable, Sendable, Identifiable {
      public let candidate: SetCandidate
      public let isChecked: Bool
      /// False for an unticked person at the 10-assignee limit, and for a ticked value with no candidate.
      public let isEnabled: Bool
      public var id: String { candidate.id }
  }
  public struct SetPicker: Equatable, Sendable {
      public static let assigneeLimit = 10
      public let key: PRKey
      public let field: EditField              // .labels or .assignees
      public let permission: EditPermission
      public private(set) var filter: String
      public private(set) var rows: [SetPickerRow]   // filtered
      public private(set) var selection: Int
      public private(set) var isLoading: Bool        // true until the first load or failure
      public private(set) var loadError: String?
      public private(set) var isComplete: Bool       // false: a filter asks GitHub (assignees past 100)
      public var title: String { "\(key.repo)#\(key.number)" }
      /// `current`: the label names or logins the issue shows now (overrides applied); `viewer`: the signed-in login.
      public init(field: EditField, key: PRKey, current: [String], viewer: String, permission: EditPermission)
      /// `fromQuery`: an answer to a filter query, which leaves `isComplete` alone.
      public mutating func load(_ candidates: SetCandidates, fromQuery: Bool = false)
      public mutating func failedToLoad(_ message: String)
      public mutating func setFilter(_ text: String)
      public mutating func move(by offset: Int)
      public mutating func toggleSelected()
      /// What closing sends; nil when nothing changed.
      public var change: EditChange? { get }
  }
  ```

Rules the tests pin:
- **Before the first load,** `rows` is empty and `isLoading` is true, with no placeholder rows.
- **The first load builds the rows:**
  - A row is ticked when its `name` matches one of `current`, case ignored.
  - `SetCandidates.current` entries missing from `all` are added as candidates.
  - A `current` name with no candidate at all gets a placeholder row, `id "missing:<name>"`, ticked and disabled.
- **The first load fixes the order:** ticked rows in `current` order, then (assignees only) the viewer when unticked, then the rest. Labels keep GitHub's order; people sort by login, case ignored.
- **Later loads** only append candidates not seen yet, and keep every tick, the order and the highlighted row.
  - A candidate whose name matches a placeholder (case ignored) replaces it in place: same position, ticked, enabled. A highlight on the placeholder moves to it.
- **`isComplete`** comes from `candidates.complete` on every load except `fromQuery: true`.
- Filter: rows whose name contains the text, case ignored. A new filter highlights the first row.
- Toggling a disabled row does nothing. At 10 ticked people, every unticked person row is disabled.
- `change`: `added` = ticked now, not at first; `removed` = ticked at first, not now; in row order. Labels map to `LabelRef(id, name, color)`, people to `PersonRef(id, login: name, avatarURL)`. Ticking and unticking the same row leaves nil.
- `failedToLoad` sets `loadError` and ends `isLoading` only before the first load; after a load (cached candidates), it changes nothing.

- [ ] **Step 1: Write the failing tests:** `tickedFirstThenViewerThenTheRest`, `labelsKeepGitHubsOrder`, `currentFromGitHubJoinsTheCandidates`, `aCurrentValueWithoutCandidateIsTickedAndLocked`, `aLaterCandidateReplacesItsPlaceholder`, `aQueryAnswerLeavesIsCompleteAlone`, `filterMatchesPartOfTheNameIgnoringCase`, `toggleBackAndForthSendsNothing`, `changeListsAddedAndRemovedInRowOrder` (labels: expect `.labels(added: [LabelRef(id:"LA_docs", name:"docs", color:"0075ca")], removed: [LabelRef(id:"LA_bug", name:"bug", color:"d73a4a")])`), `assigneesStopAtTen` (10 ticked → unticked rows `isEnabled == false`, toggle on one is a no-op; untick one → enabled again), `aLaterLoadKeepsTicksOrderAndSelection`, `aFailedLoadWithoutRowsSaysWhy` (with `current: ["bug"]`: `loadError` set, `isLoading` false, no rows), `aFailedRefetchKeepsTheCachedRows`, `stillLoadingHasNoChange`.
- [ ] **Step 2: Run** `swift test --filter SetPickerTests`. Expected: compile failure, `SetPicker` not found.
- [ ] **Step 3: Implement** in `SetPicker.swift`. Keep all rows in a private list with the first-load ticks and the current ticks; `rows` is the filtered view of it. Track the highlighted row by ID across a later load.
- [ ] **Step 4: Run** `swift test --filter SetPickerTests`. Expected: all pass.
- [ ] **Step 5: Commit** `SetPicker: rows, ticks and the diff for the assignee and label pickers`.

---

### Task 3: Sending, and partial results

**Files:**
- Create: `Packages/PullBullKit/Sources/PullBullKit/Edit/SetEditor.swift`
- Modify: `Edit/EditChange.swift`, `Edit/EditOverrides.swift`, `Edit/EditSession.swift`
- Test: `Packages/PullBullKit/Tests/PullBullKitTests/SetEditorTests.swift` (copy `QueueTransport` from `StatusEditorTests.swift`), `EditSessionTests.swift`, `EditOverridesTests.swift`

**Interfaces:**
- Consumes: `GitHubAPI.changeLabels(of:adding:removing:)`, `changeAssignees(of:adding:removing:)`, `nodeId(of:)`, `SetChangeResult`, `EditMessage.partial` (merged).
- Produces:
  ```swift
  /// Sends a label or assignee change, or its undo. A Status change sends nothing here.
  public struct SetEditor: Sendable {
      public init(api: GitHubAPI)
      /// `contentId`: the issue's node ID; looked up when an old cache lacks it.
      public func apply(_ change: EditChange, on key: PRKey, contentId: String?) async throws -> SetChangeResult
  }
  extension EditChange {
      /// The halves `result` says GitHub applied; a Status change is returned as is.
      public func keeping(_ result: SetChangeResult) -> EditChange
  }
  extension EditOverrides {
      /// Replaces edit `id`'s change in place, keeping its date and its position in the order; drops it
      /// when `change` is empty.
      public mutating func replace(_ id: UUID, with change: EditChange)
  }
  extension EditSession {
      /// GitHub applied part of edit `id`: the refused half leaves the screen, the failure line says
      /// which half, and ⌘Z (when `id` is still the last edit, and it isn't an undo) takes back only the
      /// applied half.
      public mutating func partlyApplied(
          _ id: UUID, change: EditChange, result: SetChangeResult, on key: PRKey, url: URL, isUndo: Bool,
          at now: Date)
  }
  ```

- [ ] **Step 1: Write the failing tests:**
  - `SetEditorTests`: `labelsSendBothHalvesInOneRequest` (variables `subject`, `add`, `remove` are the node IDs), `assigneesSendUserIds`, `aMissingContentIdIsLookedUpFirst` (operations: `issueOrPullRequest` then the mutation), `aStatusChangeSendsNothing` (no request; result fully applied), `bothHalvesRefusedThrowsWriteRefused`.
  - `EditOverridesTests`: `replaceKeepsOnlyTheAppliedHalf` (a `.labels(added:[docs], removed:[bug])` replaced with `.labels(added:[docs], removed:[])` shows `bug` and `docs`), `replaceWithNothingDrops`, `replaceKeepsTheOrder` (an older and a newer label edit on one issue; replacing the older keeps the newer applying last).
  - `EditSessionTests`:
    - `partlyAppliedKeepsTheAppliedHalfAndArmsUndoForIt` (`addApplied: true, removeApplied: false, refusal: "nope"`): the shown issue keeps `bug` and gains `docs`; the failure text is `"Added docs to #412, but couldn't remove bug: nope"`; `takeUndo` gives `.labels(added:[docs], removed:[])`.
    - `partlyAppliedToAnOlderEditDoesNotArmUndo`.
    - `aPartlyAppliedUndoDoesNotArmUndo`.
    - `keepingDropsTheRefusedHalf`.
  - `ChangeDetectorTests`: `labelChangesDoNotNotify` (two snapshots differing only in an issue's and a PR's labels yield no events) and `assigningOthersByTheViewerDoesNotNotify`, if no test already covers it. These pin today's behaviour, as the spec asks, and pass at once; say so in the report, and commit them on their own (`ChangeDetector: pin that label changes and the viewer's assignments don't notify`).
- [ ] **Step 2: Run** `swift test --filter "SetEditorTests|EditSessionTests|EditOverridesTests"`. Expected: compile failures for the new names.
- [ ] **Step 3: Implement.** `SetEditor` maps `LabelRef.id` / `PersonRef.id` to the mutation's IDs. `partlyApplied`:
  - `let applied = change.keeping(result)`, then `overrides.replace(id, with: applied)`;
  - sets `failure` from `EditMessage.partial(change, on:, result:)`;
  - arms undo with `EditRecord(key:, change: applied, madeAt: now, addedItemId: nil)` only when `!isUndo`, `id == last` and `applied` isn't empty.
- [ ] **Step 4: Run** the whole kit suite. Expected: all pass, no warnings.
- [ ] **Step 5: Commit** `SetEditor and partial results: keep and undo only what GitHub applied`.

---

### Task 4: App model — open, load, apply

**Files:**
- Modify: `PullBull/AppModel.swift` (state beside `statusPicker`; reset in `clearAccountData`)
- Modify: `PullBull/AppModel+Edit.swift`

**Interfaces:**
- Consumes: Tasks 1–3; `run(_:on:addedItemId:isUndo:)`, `followEditedRow`, `allows(_:)`, `issue(for:)`, `runningAccount`, `api(for:)` (merged).
- Produces (all on `AppModel`):
  ```swift
  var setPicker: SetPicker?
  /// Per field and repo ("labels|acme/widgets"): the last `all` and `complete` read. Not stored on disk.
  private(set) var setCandidates: [String: SetCandidates]   // `current` kept empty
  /// The key of the open picker, Status or set; the popover's focus and key routing read it.
  var editPickerKey: PRKey? { get }
  func isSetEditOffered(for key: PRKey) -> Bool           // an issue PullBull holds, with a running account
  func setEditPermission(_ field: EditField, for key: PRKey) -> EditPermission
  func openSetPicker(_ field: EditField, for key: PRKey)  // field is .labels or .assignees
  func filterSetPicker(_ text: String)
  func moveSetPicker(by offset: Int)
  func toggleSetPicker()
  /// Closes the picker; `apply` sends its change (Esc, ⌘↩, its key, a click outside, the popover hiding).
  func closeSetPicker(apply: Bool)
  ```

- [ ] **Step 1: State.** Add `setPicker`, `setCandidates` and a private `setPickerTask: Task<Void, Never>?` to `AppModel`. `clearAccountData` sets `setPicker = nil` (no apply), cancels the task and empties `setCandidates`.
- [ ] **Step 2: Permission and offer.** `setEditPermission` calls `EditPermission.of(field, account:, boardOwner: nil, installation:, ghAccounts: accounts)`. The installation is the loaded one whose `org` is the repo's owner, case ignored. `isSetEditOffered` is true when `issue(for: key) != nil` and `runningAccount != nil`.
- [ ] **Step 3: Open and load.** `openSetPicker` closes the Status picker. It builds `SetPicker(field:key:current:viewer:permission:)` from `issue(for:)` (label names, or assignee logins) and `shownSnapshot?.org.viewer ?? settings.account ?? ""`. `openStatusPicker` closes an open set picker with `closeSetPicker(apply: true)`. When the permission allows:
  - load the cached `setCandidates` entry at once, if any;
  - then fetch with `labelCandidates` / `assigneeCandidates(query: nil)`;
  - store `all` and `complete` in the cache, and `load` the result;
  - on error, `failedToLoad(RefreshError(error).message)`.

  Each answer applies only while `setPicker` still has the same key and field and `runningAccount` is unchanged.
- [ ] **Step 4: Filter past 100.** `filterSetPicker` sets the filter. For assignees with `isComplete == false` and a non-empty filter, it waits 0.3 s (cancelling the previous wait), asks `assigneeCandidates(for:query:)` and calls `load(answer, fromQuery: true)` under the same guard.
- [ ] **Step 5: Apply.** `closeSetPicker(apply:)` sets `setPicker = nil` and cancels the task. With `apply`, a non-nil `change` and `allows(permission)`, it calls `run(change, on: key, addedItemId: nil, isUndo: false)`. Extend `run`:
  - `.status` keeps `StatusEditor`.
  - `.labels` / `.assignees` use `SetEditor(api:).apply(change, on: key, contentId:)`.
  - A fully applied result calls `edits.applied(id, …)` when not an undo.
  - A partial one calls `edits.partlyApplied(id, change:, result:, on:, url:, isUndo:, at: Date())`, then `refreshShown()` and `followEditedRow`.
  - A throw takes the existing failure path.
- [ ] **Step 6: Build.** Run the app build. Expected: `** BUILD SUCCEEDED **`, no warnings.
- [ ] **Step 7: Commit** `AppModel: open, load and apply the assignee and label pickers`.

---

### Task 5: Picker view and keys

**Files:**
- Create: `PullBull/Popover/SetPickerView.swift`
- Modify: `PullBull/Popover/StatusPickerView.swift` (anchor and layer become shared)
- Modify: `PullBull/Popover/PopoverView.swift`, `PullBull/Popover/SearchKeyMonitor.swift`, `PullBull/Popover/IssueRow.swift`, `PullBull/Detail/IssueDetailView.swift` (anchor rename only)
- Modify: `Packages/PullBullKit/Sources/PullBullKit/Rules/ShortcutCatalog.swift`, `Packages/PullBullKit/Tests/PullBullKitTests/ShortcutCatalogTests.swift`

**Interfaces:**
- Consumes: Task 4's model API.
- Produces:
  - `EditPickerAnchorKey` (renamed from `StatusPickerAnchorKey`, same reduce).
  - `func editPickerAnchor(for key: PRKey, field: EditField?, model: AppModel) -> some View`: anchors when the open picker's key is `key`, and `field` is nil (a list row) or the open picker's field.
  - `EditPickerLayer` (renamed from `StatusPickerLayer`): shows `StatusPickerView` or `SetPickerView` at the same placement. Its outside click calls `closeStatusPicker()` or `closeSetPicker(apply: true)`.

- [ ] **Step 1: Shortcut catalog test first.** Update `ShortcutCatalogTests` to expect these Editing rows, in order:
  - "Set Status" ⌥⌘S, note "When a board is shown";
  - "Assignees" ⌥⌘A;
  - "Labels" ⌥⌘L;
  - "Undo the last edit" ⌘Z;
  - "Choose" ↑ ↓, note "In a picker; type to filter";
  - "Apply" ↩, note "Status picker";
  - "Tick or untick" ↩, note "Assignees and labels";
  - "Apply and close" ⌘↩;
  - "Close" Esc, note "Status: without change. Assignees and labels: applies".

  Run `swift test --filter ShortcutCatalogTests`. Expected: FAIL. Change `ShortcutCatalog` to match, then run it again. Expected: PASS.
- [ ] **Step 2: SetPickerView.** Same frame, material, header and filter field as `StatusPickerView`. Placeholder "Filter labels" / "Filter people". Each row:
  - a leading checkmark column, 18 pt;
  - `LabelDot(color: LabelDotColor.parse(color))` for a label, `AvatarView(login:url:size: 18)` for a person;
  - the name, and a label's description in secondary text on one line, truncated;
  - disabled rows at opacity 0.4.

  The other states:
  - while loading, a small `ProgressView` and "Loading labels…" / "Loading people…";
  - `loadError` shown as secondary text;
  - with no match, "No label called “…”" / "No one called “…”";
  - the permission note in place of the rows, reusing the Status picker's `PermissionNote` (make it internal).

  Clicking a row highlights and toggles it. Accessibility label: the name, plus ", assigned" or ", applied" when ticked.
- [ ] **Step 3: Anchor and layer.** Rename as in Interfaces:
  - `IssueRow` passes `field: nil`;
  - the detail's Status row passes `.status`;
  - `PopoverView` mounts `EditPickerLayer`.
- [ ] **Step 4: Keys.** Add `letterA = 0` and `letterL = 37` to `SearchKeyMonitor`, and their cases to `commandKey`.
  - **The ⌥⌘ test:** replace the private `isOptionCommandS` with `isOptionCommand(_ event:, flags:, letter: String) -> Bool` (⌥⌘ exactly, no ⇧ or ⌃) and use it for S, A and L. Leave ⌥⌘C's own helper.
  - **⌥⌘A / ⌥⌘L:** in the list/search block, right beside ⌥⌘S. This must sit before the ⌘-chord guard further down, which returns false for any ⌥. Also in the detail block. They act on `selectedIssueKey(in:)` or the issue detail's key, when `isSetEditOffered`.
  - **Routing:** replace `if model.statusPicker != nil` with a check on `editPickerKey`, routing to `handleStatusPickerKey` or a new `handleSetPickerKey`.
  - **`handleSetPickerKey`:** plain ↑ ↓ move; plain ↩/Enter toggles; ⌘↩ and Esc `closeSetPicker(apply: true)`; the picker's own ⌥⌘ key closes it the same way. The other pickers' ⌥⌘S/A/L are swallowed while a picker is open, and so are ⌥⌘A/L in `handleStatusPickerKey`. "Opening one closes the other" is only a safety rule in the model.
  - **Focus:** `onChange(of: model.statusPicker == nil)`, which puts the caret back in the search field, becomes `onChange(of: model.editPickerKey == nil)`. The search-field focus guard reads `model.editPickerKey != nil`.
  - **`popoverDidHide`** also calls `closeSetPicker(apply: true)`.
- [ ] **Step 5: Build.** Run the app build. Expected: `** BUILD SUCCEEDED **`, no warnings.
- [ ] **Step 6: Commit** `Assignee and label picker popup, ⌥⌘A and ⌥⌘L`.

---

### Task 6: Right-click and the detail

**Files:**
- Modify: `PullBull/Detail/PRActions.swift` (`issueContextMenu`, new `SetEditMenu`)
- Modify: `PullBull/Popover/IssueRow.swift` and every other caller that passes `status:`
- Modify: `PullBull/Detail/IssueDetailView.swift`

**Interfaces:**
- Consumes: Task 4 (`isSetEditOffered`, `openSetPicker`), Task 5 (`editPickerAnchor`).
- Produces: `struct SetEditMenu: View { static func make(model: AppModel, key: PRKey) -> SetEditMenu? }`, with buttons **Assignees…** (`person.badge.plus`) and **Labels…** (`tag`) opening the picker on the row. `issueContextMenu` gains `sets: SetEditMenu? = nil`, placed right after the Status submenu, above the copy items' separator.

- [ ] **Step 1: Menu.** Add `SetEditMenu` and the parameter. Pass it from every `issueContextMenu` call site that passes `status:`.
- [ ] **Step 2: Detail.** When `isSetEditOffered(for: key)`, make the Assignees and Labels `CardRow`s buttons, the way `statusRow` is: `.plain` style and the full row as the content shape. Help tags "Change assignees (⌥⌘A)" and "Change labels (⌥⌘L)". Anchors `editPickerAnchor(for: key, field: .assignees / .labels, model:)`. Accessibility hint "Opens the assignee picker" / "Opens the label picker".
- [ ] **Step 3: Build.** Run the app build. Expected: `** BUILD SUCCEEDED **`, no warnings.
- [ ] **Step 4: Commit** `Assignees and labels from the right-click menu and the detail`.

---

### Task 7: Docs and spec

**Files:**
- Modify: `README.md` (Privacy row, line ~156), `docs/manual.md` (Editing section, Keyboard tables, right-click lists), `docs/github-app-setup.md` (line ~29), `docs/superpowers/specs/2026-10-31-edit-status-assignees-labels-design.md`

- [ ] **Step 1: README.** Privacy row: "An issue's board Status, assignees and labels, only when you pick them. Never merges, comments, approves or closes".
- [ ] **Step 2: Manual.**
  - Editing intro: "Set an issue's board Status, assignees and labels from PullBull. It writes nothing else."
  - Add the ⌥⌘A / ⌥⌘L opening, the multi-select picker (ticked first, Return ticks, closing applies, ⌘↩, at most 10 assignees), undo of label and assignee edits, and the partial-failure line.
  - Add the keys to the Keyboard tables and the items to the right-click lists, wherever ⌥⌘S and Status appear.
- [ ] **Step 3: github-app-setup.** "PullBull writes to GitHub only an issue's board Status, assignees and labels you pick. …" (rest unchanged).
- [ ] **Step 4: Spec.** Edit the spec so it states the result as fact:
  - **Scope:**
    - Goals: assignees and labels on issues.
    - Keys table, Where column: "Issue row or issue detail".
    - "The issue the picker edits".
    - Delivery step 3: "…for issues".
  - **Permissions:** replace the PR-check bullets with "Pull requests stay read-only: PullBull edits no labels or assignees on them".
  - **Rulings made during the build:** the candidate queries also read the issue's own labels and assignees with their IDs; label pages are capped at 10 (1,000 labels); the row order is fixed at the first load (later loads append); a current value without a candidate is ticked and locked; the popover hiding applies the ticks; an account switch drops the picker unsent; `viewerCanUpdate` isn't used (triage users may label without it), so a refusal shows the failure line; opening one picker closes the other; while a picker is open, the other pickers' keys do nothing; a half-applied undo is not itself undoable; a filter query's answer never marks the assignee list complete; an issue's own labels past 100 aren't read.
  - **Testing list:** add candidate paging, picker ticks and order, and partial results.
  - **"Left to the builder":** trim the settled items.
- [ ] **Step 5: Commit** `Docs: PullBull now changes an issue's assignees and labels`.
