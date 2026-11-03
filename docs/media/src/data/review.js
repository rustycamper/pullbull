// Demo data for the README hero: the pull request list on All, as the popover opens. Needs your review
// holds three PRs waiting on devon, Your PRs the two that need him, Waiting on others one that waits on
// bob; Recently closed and Team are folded. Rows are not grouped by repo and name theirs. Default settings:
// drafts shown, PRs devon approved hidden, badge counts Review, so the menu bar reads the Review count.
window.SCENES = window.SCENES || {};
window.SCENES.review = {
  viewer: { login: "devon", org: "initech" },
  menuBar: { count: 3, open: true },
  mode: "pullRequests",
  chips: [
    { id: "all", title: "All" },
    { id: "review", title: "Needs you", count: 3, hot: true },
    { id: "mine", title: "Mine", count: 3 },
    { id: "team", title: "Team", count: 12 },
  ],
  selectedChip: "all",
  search: { text: "", focused: false },
  filter: { repoTitle: "All repos" },
  // The pointer on frank's failing CI glyph: its .help text, Palette.ciLabel(.failure), as the native tooltip.
  hover: { number: 479, on: "ci", tooltip: "Checks failed" },
  sections: [
    {
      id: "needsReview", title: "Needs your review", rowTab: "review",
      rows: [
        { title: "Add rate limiting to the public API", repo: "api", number: 482, author: "alice", age: "12m", ci: "pending", info: ["requested", { wait: "1h" }], comments: 2 },
        { title: "Return 404 for unknown webhook IDs", repo: "api", number: 479, author: "frank", age: "3h", ci: "failure", info: [{ viaTeam: "initech/platform" }, { wait: "1d" }] },
        { title: "Fix flaky checkout test on CI", repo: "widgets", number: 1291, author: "bob", age: "1h", ci: "success", info: ["reRequested", { wait: "1h" }], comments: 4 },
      ],
    },
    {
      id: "yourPRs", title: "Your PRs", rowTab: "mine",
      rows: [
        { title: "Add a retry budget to webhook delivery", repo: "widgets", number: 1302, author: "devon", age: "2h", ci: "success", info: [{ approvals: 2 }], action: "readyToMerge" },
        { title: "Paginate the audit log endpoint", repo: "api", number: 471, author: "devon", age: "1d", ci: "failure", info: [{ approvals: 1 }], action: { changesRequested: ["bob"] } },
      ],
    },
    {
      id: "waiting", title: "Waiting on others", rowTab: "mine",
      rows: [
        { title: "Add retries to the export job", repo: "widgets", number: 1305, author: "devon", age: "5h", ci: "success", info: [{ wait: "@bob 1d" }] },
      ],
    },
    { id: "recentlyClosed", title: "Recently closed", count: 3, trailing: "Last 7 days", folded: true, rows: [] },
    { id: "team", title: "Team", count: 12, folded: true, rows: [] },
  ],
};
