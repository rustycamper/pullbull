// Demo data for the Mine tab: devon's open PRs with every review state Mine draws (Ready to merge,
// Changes requested, approvals, No reviews, Conflicts), a draft, a red CI failure, and the "Recently
// closed" group opened to show its Merged and Closed pills.
window.SCENES = window.SCENES || {};
window.SCENES.mine = {
  viewer: { login: "devon", org: "initech" },
  menuBar: { count: 6, open: true },
  mode: "pullRequests",
  tabs: [
    { id: "review", title: "Review", count: 6 },
    { id: "mine", title: "Mine", count: 4 },
    { id: "team", title: "Team", count: 12 },
  ],
  selectedTab: "mine",
  search: { text: "", focused: false },
  filter: { repoTitle: "All repos" },
  groupByRepo: true,
  groups: [
    {
      repo: "widgets",
      rows: [
        { title: "Add a retry budget to webhook delivery", number: 1302, author: "devon", age: "2h", ci: "success", info: [{ approvals: 2 }], action: "readyToMerge" },
        { title: "Split the widget registry into modules", number: 1296, author: "devon", age: "6h", ci: "pending", draft: true, info: ["noReviews"] },
      ],
    },
    {
      repo: "api",
      rows: [
        { title: "Paginate the audit log endpoint", number: 471, author: "devon", age: "1d", ci: "failure", info: [{ approvals: 1 }], comments: 3, action: { changesRequested: ["bob"] } },
        { title: "Cache tenant lookups per request", number: 468, author: "devon", age: "2d", ci: "success", info: [{ approvals: 1 }, "conflicts"] },
      ],
    },
  ],
  recentlyClosed: {
    count: 3,
    expanded: true,
    rows: [
      { title: "Remove the legacy v1 export endpoint", repo: "api", number: 466, state: "merged", when: "3h ago" },
      { title: "Try a CSS-only tooltip for widget cards", repo: "widgets", number: 1279, state: "closed", when: "1d ago" },
      { title: "Document the gadget sync settings", repo: "gadgets", number: 74, state: "merged", when: "2d ago" },
    ],
  },
};
