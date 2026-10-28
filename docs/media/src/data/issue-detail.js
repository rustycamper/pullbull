// Demo data for the issue detail: an In progress issue on the Roadmap board, with an open and a merged
// linked PR and the last two of four comments (IssueDetailView shows the last two).
window.SCENES = window.SCENES || {};
window.SCENES["issue-detail"] = {
  view: "issueDetail",
  viewer: { login: "devon", org: "initech" },
  menuBar: { count: 6, open: true },
  boardTitle: "Roadmap",
  issue: {
    repo: "api", number: 503, title: "Timeouts in the api contract tests",
    author: "erin", opened: "3d ago", status: "In progress",
    assignees: ["devon", "bob"],
    labels: [
      { name: "ci", color: "fbca04" },
      { name: "flaky-test", color: "e99695" },
      { name: "bug", color: "d73a4a" },
    ],
    linked: [
      { title: "Raise the contract test timeout to 30s", number: 512, author: "devon", state: "open", ci: "pending" },
      { title: "Reuse one HTTP client across contract tests", number: 507, author: "bob", state: "merged", ci: "success" },
    ],
    body: "About one run in ten fails with `context deadline exceeded` in the **contract** suite, always against the staging mock. Retrying the job passes.",
    commentTotal: 4,
    lastComments: [
      { author: "bob", age: "1d", body: "The shared client in #507 cut the failures by half." },
      { author: "devon", age: "2h", body: "#512 should cover the rest. Watching the next 20 runs." },
    ],
  },
};
