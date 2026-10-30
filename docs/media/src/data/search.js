// Demo data for search: Pull Requests mode, "test @al" typed with the caret at the end. The "@al" token is
// being picked, so it is left out of the query (SearchFieldState): the results behind are for "test", laid out
// like the Team tab, and the people list for "al" covers their top. Tab counts are each tab's matches; no tab
// is selected (search spans all tabs).
window.SCENES = window.SCENES || {};
window.SCENES.search = {
  view: "search",
  viewer: { login: "devon", org: "initech" },
  menuBar: { count: 6, open: true },
  mode: "pullRequests",
  tabs: [
    { id: "review", title: "Review", count: 1 },
    { id: "mine", title: "Mine", count: 0 },
    { id: "team", title: "Team", count: 3 },
  ],
  selectedTab: null,
  search: { text: "test @al", focused: true },
  filter: { repoTitle: "All repos" },
  completion: {
    selection: 0,
    candidates: [
      { login: "alice", isMember: true, openCount: 5 },
      { login: "alan-k", isMember: true, openCount: 1 },
      { login: "dalton", isMember: false, openCount: 1 },
    ],
  },
  searchResults: {
    words: ["test"],
    count: 5,
    // Laid out as the Team tab is, grouped by repo (newest group first) with Team's rows; no context line.
    groups: [
      { repo: "widgets", rows: [{ title: "Fix flaky checkout test on CI", number: 1291, author: "bob", age: "1h", ci: "success", info: [] }] },
      { repo: "api", rows: [{ title: "Add contract tests for webhook retries", number: 484, author: "erin", age: "3h", ci: "pending", info: [] }] },
      { repo: "gadgets", rows: [{ title: "Run the e2e test suite in the merge queue", number: 79, author: "frank", age: "1d", ci: "failure", info: [] }] },
    ],
    closed: [
      { title: "Retry flaky tests once before failing", repo: "widgets", number: 1270, state: "merged", when: "Oct 21" },
      { title: "Drop the legacy snapshot tests", repo: "api", number: 455, state: "closed", when: "Oct 14" },
    ],
  },
};
