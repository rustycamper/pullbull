// Demo data for search: Pull Requests mode, "test @al" typed with the caret at the end. The "@al" token is
// being picked, so it is left out of the query (SearchFieldState): the results behind are for "test", and the
// people list for "al" covers their top. Tab counts are each tab's matches; no tab is selected.
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
    context: "Titles in all of initech",
    words: ["test"],
    count: 5,
    open: [
      { title: "Fix flaky checkout test on CI", repo: "widgets", number: 1291, author: "bob", when: "1h", state: "open", ci: "success" },
      { title: "Add contract tests for webhook retries", repo: "api", number: 484, author: "erin", when: "3h", state: "open", ci: "pending" },
      { title: "Run the e2e test suite in the merge queue", repo: "gadgets", number: 79, author: "frank", when: "1d", state: "open", ci: "failure" },
    ],
    closed: [
      { title: "Retry flaky tests once before failing", repo: "widgets", number: 1270, author: "carol", when: "Oct 21", state: "merged" },
      { title: "Drop the legacy snapshot tests", repo: "api", number: 455, author: "alice", when: "Oct 14", state: "closed" },
    ],
  },
};
