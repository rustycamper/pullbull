// Demo data for the Mine chip: devon's open PRs in Your PRs (Ready to merge, a draft, Changes requested, a
// red CI failure, Conflicts) and Waiting on others, with "Recently closed" opened to show its Merged and
// Closed pills. Mine is not grouped by repo: rows name theirs.
window.SCENES = window.SCENES || {};
window.SCENES.mine = {
  viewer: { login: "devon", org: "initech" },
  menuBar: { count: 3, open: true },
  mode: "pullRequests",
  chips: [
    { id: "all", title: "All" },
    { id: "review", title: "Needs you", count: 3, hot: true },
    { id: "mine", title: "Mine", count: 5 },
    { id: "team", title: "Team", count: 12 },
  ],
  selectedChip: "mine",
  search: { text: "", focused: false },
  filter: { repoTitle: "All repos" },
  sections: [
    {
      id: "yourPRs", title: "Your PRs", rowTab: "mine",
      rows: [
        { title: "Add a retry budget to webhook delivery", repo: "widgets", number: 1302, author: "devon", age: "2h", ci: "success", info: [{ approvals: 2 }], action: "readyToMerge" },
        { title: "Split the widget registry into modules", repo: "widgets", number: 1296, author: "devon", age: "6h", ci: "pending", draft: true, info: [] },
        { title: "Paginate the audit log endpoint", repo: "api", number: 471, author: "devon", age: "1d", ci: "failure", info: [{ approvals: 1 }], action: { changesRequested: ["bob"] } },
        { title: "Cache tenant lookups per request", repo: "api", number: 468, author: "devon", age: "2d", ci: "success", info: [{ approvals: 1 }, "conflicts"] },
      ],
    },
    {
      id: "waiting", title: "Waiting on others", rowTab: "mine",
      rows: [
        { title: "Add retries to the export job", repo: "widgets", number: 1305, author: "devon", age: "5h", ci: "success", info: [{ wait: "@bob 1d" }] },
      ],
    },
    {
      id: "recentlyClosed", title: "Recently closed", trailing: "Last 7 days", folded: false,
      rows: [
        { title: "Remove the legacy v1 export endpoint", repo: "api", number: 466, state: "merged", when: "3h ago" },
        { title: "Try a CSS-only tooltip for widget cards", repo: "widgets", number: 1279, state: "closed", when: "1d ago" },
        { title: "Document the gadget sync settings", repo: "gadgets", number: 74, state: "merged", when: "2d ago" },
      ],
    },
  ],
};
