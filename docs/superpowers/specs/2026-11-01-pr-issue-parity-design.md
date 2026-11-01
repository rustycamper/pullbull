# PR and issue display parity

PR rows and issue rows, and the PR and issue pages, show the same kinds of information in the same places and the same words. Someone who learns one screen can read the other.

## Why

The two halves of the app grew separately. A side-by-side audit found the same fact shown differently (comment order, where the comment count sits, what a closed item's pill looks like, a boxed description on one page and an unboxed one on the other) and some facts on one side only. The owner's rule is that the two screens stay close in what they display.

## Rows

- **Meta line order is the same:** `repo #num · age · search role · comment count · …`. An issue row's comment count sits where a PR row's does, before the label chips.
- **The age is the last update while open**, with "Updated 1h ago" on hover and for VoiceOver (from the review-wait work).
- **A merged or closed item's age is when it ended:** "merged 3d ago" for the first week, then "merged Oct 12", with the year once it isn't this year (`EndedAge`). When the close date is unknown the row says just "merged" or "closed". `EndedAge.label` is the one source for the row and the page.
- **Ended pills on full rows:**
  - A merged or closed PR shows its Merged or Closed pill.
  - A closed issue shows its pill in the issue page's colours, as GitHub does: purple "Closed" when completed, gray when not planned (`IssueEndedPill`).
  - VoiceOver says "Closed as completed" or "Closed as not planned", because the shared word "Closed" doesn't tell them apart.
- **Compact rows have no ended pill**, for PRs or issues. The glyph and "merged 3d ago" already say it, and a compact line has no room to spare: on an issue row the pill crowded out the title next to the assignees.
- **Closed PR rows follow compact mode** like every other row: glyph, title, `repo #num`, when it ended. Before this they were always drawn full.

## Pages

- **The byline names what the row shows beside the opening:**
  - Open: "rado opened 4d ago · updated 1h ago". The update is left out when it reads the same as the opening.
  - Merged or closed: "rado opened Oct 2 · merged Oct 12", the row's ended text, in place of the update. Someone opening a closed row then finds the row's date on the page.
  - One line when it fits beside the state pill; otherwise it breaks at the " · ", a line per part, never inside "merged 7h ago" (`OpenedLine.parts`, the `Byline` view).
- **The description is the same view on both pages** (`DescriptionSection`). It sits unboxed on the material at the section gutter, 12.5pt with 3pt line spacing, and folds when long. Cards are for structured data and prose isn't. An empty description reads "No description provided.".
- **Conversation shows the newest comments**, with "N earlier comments · view on GitHub" counted above them, on both pages. A PR page holds the newest 50 (`comments(last:50)`). An issue page holds the last two.
- **The comment total comes from the page's own data**, `PRDetail.commentTotal` from the query's `totalCount` and not the row's count. A linked PR opened from an issue page has no row to borrow from. Details cached before the total was stored fall back to the comments held.
- **Details stays a card:** it holds a field name and a clickable value per row, which is the macOS grouped-form pattern. An empty value ("No one", "None") is tertiary, as macOS draws a field's placeholder (`EmptyValue`). It sits below the secondary field name, so a filled field stands out from an empty one. The same secondary for both made an empty card read as busy as a full one.
- **An empty section looks the same:** an issue page's "Linked pull requests" with none shows the empty card (`DetailCard` with an `EmptyLine`) that a PR page's empty sections use.
- **The issue page's state pill is the row's pill** (`IssueEndedPill` with its glyph), so a closed issue looks the same in the list and on its page.

## Non-goals

- Fields only one kind has stay on that side: checks, reviewers, files and branches for PRs; board status and linked PRs for issues.
- Fetching more issue comments to match the PR page's 50. The issue page stays a summary that links to GitHub.
