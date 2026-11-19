# Reactions on comments, descriptions and reviews

The PR and issue details show GitHub's emoji reactions on the description, each comment and each review with text, and let you add or remove your own. Today they show none, and acknowledging a comment means writing a reply or going to the browser. With this, a 👍 on "Done in the last commit" is one click, and you can see at a glance that three people already 👀'd a question.

This builds on `2026-11-02-comments-and-mentions-design.md` (the comments spec), which listed reactions as a non-goal; this spec reverses that one line. Its permission handling, failure line and anti-goals apply here. Where this document is silent, the comments spec and the edit specs it builds on apply.

## Why

- Seeing reactions: how a thread responded (agreement, a question already being looked at, a celebration) is part of reading it, and the detail leaves that out.
- Giving reactions: much of what's owed in a thread is an acknowledgement, not a reply. A reaction is that acknowledgement without the email that a comment sends to everyone subscribed.

## Goals

- Every description, comment and review with text in a detail shows its reactions as chips: emoji and count, your own tinted with the accent.
- Hovering a chip names who reacted.
- Clicking a chip adds or removes your reaction of that kind.
- A ☺︎ button, shown on hover, opens a picker of GitHub's eight reactions for anything you can react to.
- Your reaction shows the moment you click, and stays shown through a refresh that started before the click.

## Non-goals

- Telling you outside the detail that someone reacted: no notification, no row hint, no count on the list. GitHub sends no notification for reactions either.
- Reactions on rows, in search results or in Stats.
- Reactions on review comments on lines of a diff (PullBull shows none of those), on commits or on releases.
- Filtering or sorting by reactions.
- Keyboard shortcuts for reacting. VoiceOver gets actions (below), but there is no key to react.

## Anti-goals

The comments spec's anti-goals hold. In addition, the feature fails if:

- a reaction is sent that you didn't click: a click on a chip or picker emoji sends exactly one add or remove, and a reaction never goes out from a hover, a scroll or a keystroke in the comment field;
- the screen says you reacted when GitHub refused it, or says you didn't when GitHub took it, for longer than the failure takes to come back;
- a thread with no reactions looks different from today: no empty chip row, no reserved space, no always-visible button;
- reading reactions costs extra requests per detail.

## What it looks like

The chosen layout, B of the three shown:

```
┌ Conversation ─────────────────────── 2 comments ┐
│ (a) alice · 1d                             [☺︎]  │  ← ☺︎ only while the pointer is over the comment
│     Nice. Can we surface the budget in the       │
│     delivery log too?                            │
│     [👍 3] [🎉 1] [👀 2]                          │  ← 👍 tinted: you reacted
│                                                  │
│ (b) bob · 3h                                     │  ← no reactions: no chip row
│     Done in the last commit.                     │
└──────────────────────────────────────────────────┘
```

- **Chips** sit under the body, in GitHub's order (👍 👎 😄 🎉 😕 ❤️ 🚀 👀), only for reactions with a count above zero. Yours: accent fill and border, accent text. Others: the existing `Palette.fill` with a separator border. They wrap onto more lines when they don't fit.
- **Tooltip** on a chip: "alice, bob and frank reacted with 👍", "You and 4 others reacted with 👍". Up to three names, then "and N others". The names are the first three users GitHub returns for that reaction (`reactors(first:3)`), so a tooltip never names more than three people. When you reacted, "You" comes first and your login is dropped from the names, so a removal shown at once never names you. When GitHub returned no names, it reads "2 people" or "1 person".
- **☺︎ button** at the top right of the description, comment or review, shown while the pointer is over it and while its picker is open. It isn't shown when you can't react: GitHub says `viewerCanReact` is false (a locked conversation, an archived repo), the account can't make the edit (see Permissions), or the comment is still sending.
- **Picker**: a small panel with the eight emoji in a row, drawn above the detail like the Status picker and anchored on the ☺︎ that opened it. It sits over a full-size click catcher that covers the header, the scroll content and the comment field, so near the edges it may overlap the header or the bottom bar. The ones you've already given are tinted. Any pick closes the picker, even one that sends nothing because you can no longer react. It also closes on Esc (the only time Esc doesn't go Back), on a click anywhere else in the detail, and on leaving the detail. Closing without a pick sends nothing.
- **Description**: chips under the description text, ☺︎ at the top right of the Description section. Chips show whenever the description has reactions, even when its text is empty, so a reaction you just added to an empty description shows at once. An empty description with no reactions shows no chips and still has the ☺︎ on hover.
- **Reviews** with text appear as Conversation rows today; they get chips and ☺︎ like comments.

## Accessibility

- Each chip's label is "👍 3, including you" or "🎉 1". Its action is "Add reaction" or "Remove reaction".
- The description, each comment and each review get the VoiceOver action "React…", which opens the picker. The picker's emoji are buttons labelled with GitHub's names (Thumbs up, Thumbs down, Laugh, Hooray, Confused, Heart, Rocket, Eyes).
- Increased contrast: the chip borders use the same contrast handling as the other chips.

## Reading

The detail queries fetch reactions with what they fetch today, with no new requests:

```graphql
reactionGroups { content viewerHasReacted reactors(first: 3) { totalCount nodes { ... on Actor { login } } } }
viewerCanReact
```

- On the pull request and the issue itself (the description), on each comment, and on each review in `latestReviews`. Reviews also gain `id`, which reacting to them needs.
- The issue detail keeps showing its newest two comments. Reactions come with those two.
- **Cached details:** `Comment`, `Review`, `PRDetail` and `IssueDetail` are persisted. Every new field (reaction groups, `viewerCanReact`, the subject's node id, `Review.id`) decodes as empty or nil when missing. A detail read from an old cache shows no chips and no ☺︎ until it is refetched, and a detail is always refetched on open.
- **Reviews:** reaction fields are left out of `Review`'s equality, since `ChangeDetector` compares reviews and a new reaction must not look like a new review. Only the detail's reviews carry reactions. The list's copies from `prFields` don't.
- **A comment posted from here:** it shows no ☺︎ while sending. Once GitHub answers, `postComment` has returned its node id, so it shows the ☺︎ with `viewerCanReact` taken as true: you just commented, so you can react. It has no chips until someone reacts.
- **A review submitted from here:** it is shown before a fetch with no id, so it has no ☺︎ and no chips until a fetch brings it. The submitted review stays laid over the fetched reviews until the override settles; once a fetch brings your review with the same state and commit, the laid-over copy takes that review's id and reactions, so its chips and ☺︎ show without waiting for the next list refresh. A fetched review of yours on another commit or in another state lends nothing. If it replaces your earlier review, which had a reaction pending, that override isn't dropped explicitly: the replaced review is no longer shown, so its override lapses unseen.

## Writing

- Adding uses GitHub's `addReaction(subjectId, content)`, removing `removeReaction`. Both answer with the subject's `reactionGroups`. The detail has one lookup for a subject's reactions by id (`PRDetail.reactions(of:)`, `IssueDetail.reactions(of:)`) and one for writing them back (`replacingReactions`); both live in the Kit.
- **At once:** the click records the change in `ReactionOverrides`, its own type in the Kit: an entry per subject id and reaction, added or removed. It isn't an `EditChange` case in `EditOverrides`: reactions live on details, `EditOverrides` reconciles against the list snapshot, and keeping them apart leaves every `EditChange` switch untouched. What's shown applies it: the count goes up or down by one, the tint goes on or off, and a chip appears or disappears.
- **GitHub's answer:** the subject's `reactionGroups` from the mutation's answer are written into the stored detail, in memory and in the cache, and the stored detail keeps its `fetchedAt`. The entry is marked answered at that time. Whether a detail fetch started after the answer is measured by `fetchedAt`, which `GitHubAPI` stamps when the request starts. An entry is never removed because a fetch landed. It stops applying while the stored detail's `fetchedAt` is later than its answer, since that fetch is GitHub's state, and applies again if an older fetch lands after it, so fetch order can't undo a click. An entry applies until `EditOverrides.lifetime` ends. A cached detail from before this feature has no `fetchedAt` and keeps the entry applied. A refresh in flight at the click is therefore shown with the click applied.
- **Failure:** when GitHub refuses, the override is dropped, so the chip goes back, and the detail's failure line says what happened, using the comments spec's wording rules: `Couldn't add 👍 on #12: …` or `Couldn't remove 👍 on #12: …`. The line stays when you leave the detail, as the other edit lines do. Transport failures on the GraphQL mutations, even with no connection at all, are classified as unknown and never as refused.
- **Unknown outcome:** a timeout or a lost connection leaves the click as shown, marks it answered and fetches the detail once, as the comment flow's confirm does. The confirm judges the reactions in the detail that fetch read, not the stored detail, which an older fetch landing meanwhile could have replaced. After that fetch, in this order:
  - the fetch failed: the override is dropped and the line `Couldn't confirm your 👍 on #12. Check it on GitHub.` shows;
  - the fetched detail already shows what the latest click asks for: nothing more happens;
  - you clicked the same reaction again meanwhile and the fetch still shows the old state: the new state is sent (reacting is idempotent on GitHub);
  - otherwise: the override is dropped and the unconfirmed line shows.
- **Recording:** a reaction is recorded without starting a new edit session, as a submitted review is, so it doesn't clear the failure line or ⌘Z for the previous edit.
- **One call at a time:** for one subject and reaction there is one write in flight. A click made meanwhile only updates what's wanted. After the answer the flow sends the opposite call when the latest click asks for it, or, when GitHub refused and you have since asked for the state it kept, drops the refusal quietly. GitHub ends in the state of the last click. When the first call is applied and a follow-up goes, the first answer is written through to the stored detail before the follow-up is sent, while the latest click's override, still unanswered, stays laid over it; so if GitHub refuses the follow-up, the dropped override reveals what GitHub holds.
- **Stale answers:** each in-flight send has its own id. An answer or a confirm acts only when the stored send's id and account still match, so an answer from before an org switch, or from an A→B→A account switch, never touches a newer send. When another account is running, the send is removed.
- **No undo:** ⌘Z doesn't take back a reaction. Clicking the chip again does.
- **Notifications:** your own reactions never notify. They don't today and this adds nothing that would.

## Permissions

- A reaction is gated like a comment (`EditField.comment`). It needs the same GitHub permission: Issues write on an issue, Pull requests write on a pull request, or a `gh` login.
- When the account can't react, the ☺︎ button doesn't show and chips can't be clicked. They still show counts and names.
- `needsAppApproval` shows nothing new in the detail. The comment field already explains it.

## Approaches considered

- **A · Show at once, then reconcile (chosen).** The chip flips on click, and `ReactionOverrides` keeps it through stale refreshes, applied by `fetchedAt`, until GitHub agrees. A reaction should feel cheaper than a reply, and only an instant click does.
- **B · Wait for GitHub.** The chip dims until GitHub answers, then shows its counts. It's simpler, but every click lags 0.3 to 1 s, and a refresh started before the click can still briefly undo it.
- **C · React, then reload the detail.** This is the simplest, but it's the slowest and the whole detail flickers.

The layout was chosen from three mockups: GitHub-style chips with a ☺︎+ chip at the end, chips with the ☺︎ on hover (chosen), and compact counts in the header line.

## Left to the builder

- Where the reaction types live in PullBullKit.
- The picker's exact size.
- How the tooltip text is built for edge cases (only you, ghost users), following the wording above.
