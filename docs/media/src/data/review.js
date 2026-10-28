// Demo data for the README hero: the Review tab with six PRs waiting on devon, grouped by repo (the
// group with the most recently updated PR first, rows newest first, as TabBuilder and
// ListNavigation.repoGroups order them). Default settings: drafts shown, PRs devon approved hidden, badge
// counts Review, so the menu bar reads the Review count.
window.SCENES = window.SCENES || {};
window.SCENES.review = {
  viewer: { login: "devon", org: "initech" },
  menuBar: { count: 6, open: true },
  mode: "pullRequests",
  tabs: [
    { id: "review", title: "Review", count: 6 },
    { id: "mine", title: "Mine", count: 4 },
    { id: "team", title: "Team", count: 12 },
  ],
  selectedTab: "review",
  search: { text: "", focused: false },
  filter: { repoTitle: "All repos" },
  groupByRepo: true,
  // The pointer on frank's failing CI glyph: its .help text, Palette.ciLabel(.failure), as the native tooltip.
  hover: { number: 479, on: "ci", tooltip: "Checks failed" },
  groups: [
    {
      repo: "api",
      rows: [
        // Requested of devon directly, first time: no "why" line.
        { title: "Add rate limiting to the public API", number: 482, author: "alice", age: "12m", ci: "pending", info: [], comments: 2 },
        { title: "Return 404 instead of 500 for unknown webhook IDs", number: 479, author: "frank", age: "3h", ci: "failure", info: [{ viaTeam: "initech/platform" }] },
      ],
    },
    {
      repo: "widgets",
      rows: [
        { title: "Fix flaky checkout test on CI", number: 1291, author: "bob", age: "1h", ci: "success", info: ["reRequested"], comments: 4 },
        { title: "Virtualize the long widget list", number: 1287, author: "erin", age: "5h", ci: "none", draft: true, info: [] },
      ],
    },
    {
      repo: "gadgets",
      rows: [
        { title: "Migrate settings to the new store", number: 77, author: "carol", age: "4h", ci: "success", info: ["newCommits"] },
        { title: "Bump the image library to 4.2", number: 75, author: "erin", age: "1d", ci: "skipped", info: [], comments: 1 },
      ],
    },
  ],
};
