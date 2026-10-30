// Demo data for search: Pull Requests mode, "test" typed with the caret at the end. The results are laid out
// like the Team tab. Tab counts are each tab's matches; no tab is selected (search spans all tabs). The footer
// is SearchFooter: the coverage and match count, then Open and Clear. Ask AI is left out: with it the line is wider than the popover, so SearchFooter drops it.
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
  search: { text: "test", focused: true },
  filter: { repoTitle: "All repos" },
  searchResults: {
    words: ["test"],
    coverage: "Titles in all of initech",
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
