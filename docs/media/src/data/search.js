// Demo data for search: Pull Requests mode, "test" typed on All with the caret at the end. The results are
// laid out in the list's sections, and the chips are the scope picker: Everywhere is selected and counts the
// results, each other chip counts its own matches. Nothing folds in search; Closed and merged follows.
// SearchFooter: coverage and match count, then Open and Clear. No Ask AI: with it the line outgrows the popover.
window.SCENES = window.SCENES || {};
window.SCENES.search = {
  view: "search",
  viewer: { login: "devon", org: "initech" },
  menuBar: { count: 3, open: true },
  mode: "pullRequests",
  chips: [
    { id: "all", title: "All", count: 5 },
    { id: "review", title: "Needs you", count: 1 },
    { id: "mine", title: "Mine", count: 0 },
    { id: "team", title: "Team", count: 2 },
  ],
  selectedChip: "all",
  search: { text: "test", focused: true },
  filter: { repoTitle: "All repos" },
  searchResults: {
    words: ["test"],
    coverage: "Titles in all of initech",
    count: 5,
    sections: [
      {
        id: "needsReview", title: "Needs your review", rowTab: "review",
        rows: [{ title: "Fix flaky checkout test on CI", repo: "widgets", number: 1291, author: "bob", age: "1h", ci: "success", info: ["reRequested", { wait: "1h" }], comments: 4 }],
      },
      {
        id: "team", title: "Team", rowTab: "team",
        rows: [
          { title: "Add contract tests for webhook retries", repo: "api", number: 484, author: "erin", age: "3h", ci: "pending", info: [{ wait: "@initech/platform +1 5h" }] },
          { title: "Run the e2e test suite in the merge queue", repo: "gadgets", number: 79, author: "frank", age: "1d", ci: "failure", info: [{ wait: "No reviewer 1d" }] },
        ],
      },
    ],
    closed: [
      { title: "Retry flaky tests once before failing", repo: "widgets", number: 1270, state: "merged", when: "Oct 21" },
      { title: "Drop the legacy snapshot tests", repo: "api", number: 455, state: "closed", when: "Oct 14" },
    ],
  },
};
