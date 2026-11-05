// Demo data for Stats: This week, the pointer on Monday's bar. The rows under Right now are the list's own:
// frank's PR has waited longest on devon, and bob has had devon's export job for a day. Issues sits below the fold.
window.SCENES = window.SCENES || {};
window.SCENES.stats = {
  view: "stats",
  viewer: { login: "devon", org: "initech" },
  menuBar: { count: 3, open: true },
  stats: {
    periods: ["This week", "This month", "90 days"],
    period: "This week",
    span: "Last 7 days",
    reviews: [
      { label: "Reviews", parts: ["14"], comparison: "last week 9" },
      { label: "Turnaround", parts: ["3", "h", "10", "m"], comparison: "last week 5 h" },
    ],
    chart: {
      hover: 3,
      days: [
        { initial: "F", date: "Fri 30 Oct", count: 3 },
        { initial: "S", date: "Sat 31 Oct", count: 0 },
        { initial: "S", date: "Sun 1 Nov", count: 0 },
        { initial: "M", date: "Mon 2 Nov", count: 4 },
        { initial: "T", date: "Tue 3 Nov", count: 2 },
        { initial: "W", date: "Wed 4 Nov", count: 3 },
        { initial: "T", date: "Thu 5 Nov", count: 2 },
      ],
    },
    pullRequests: [
      { label: "Merged", parts: ["6"], comparison: "last week 4" },
      { label: "Time to merge", parts: ["1", "d", "4", "h"], comparison: "last week 2 d" },
      { label: "First review", parts: ["2", "h", "40", "m"], comparison: "last week 4 h" },
    ],
    topReviewers: [{ login: "alice", count: 4 }, { login: "bob", count: 3 }, { login: "erin", count: 2 }],
    rightNow: [
      {
        caption: "Waiting on you longest", tab: "review",
        row: { title: "Return 404 for unknown webhook IDs", repo: "api", number: 479, author: "frank", age: "3h", ci: "failure", info: [{ viaTeam: "initech/platform" }, { wait: "1d" }] },
      },
      {
        caption: "Your PR waiting longest", tab: "mine",
        row: { title: "Add retries to the export job", repo: "widgets", number: 1305, author: "devon", age: "5h", ci: "success", info: [{ wait: "@bob 1d" }] },
      },
    ],
    footer: "From GitHub, for devon in initech",
  },
};
