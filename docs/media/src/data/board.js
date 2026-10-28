// Demo data for Issues → Board: the "Roadmap" board's lanes in board order, each lane's Status colour
// on its glyph, open issues (Board lanes hold only open, not-done items), and the folded Done group.
// Board count = issues in the lanes (Backlog included, Done not).
window.SCENES = window.SCENES || {};
const LABELS = {
  bug: { name: "bug", color: "d73a4a" },
  enhancement: { name: "enhancement", color: "a2eeef" },
  docs: { name: "documentation", color: "0075ca" },
  goodFirst: { name: "good first issue", color: "7057ff" },
  ci: { name: "ci", color: "fbca04" },
  flaky: { name: "flaky-test", color: "e99695" },
  perf: { name: "performance", color: "1d76db" },
};
window.SCENES.board = {
  viewer: { login: "devon", org: "initech" },
  menuBar: { count: 6, open: true },
  mode: "issues",
  tabs: [
    { id: "assigned", title: "Assigned", count: 3 },
    { id: "created", title: "Created", count: 2 },
    { id: "board", title: "Board", count: 7 },
  ],
  selectedTab: "board",
  search: { text: "", focused: false },
  filter: { boardTitle: "Roadmap", repoTitle: "All repos" },
  lanes: [
    { name: "Backlog", color: "gray", folded: true, issues: [{}, {}] },
    {
      name: "Todo", color: "blue",
      issues: [
        { title: "Widget picker loses focus on close", repo: "widgets", number: 214, age: "3h", comments: 2, labels: [LABELS.bug, LABELS.goodFirst], assignees: [] },
        { title: "Dark mode preview in gadget editor", repo: "gadgets", number: 92, age: "1d", labels: [LABELS.enhancement], assignees: ["carol"] },
      ],
    },
    {
      name: "In progress", color: "yellow",
      issues: [
        { title: "Timeouts in the api contract tests", repo: "api", number: 503, age: "25m", comments: 5, labels: [LABELS.ci, LABELS.flaky, LABELS.bug], assignees: ["devon", "bob"] },
        { title: "Write the migration guide for v3 webhooks", repo: "api", number: 498, age: "4h", labels: [LABELS.docs], assignees: ["erin"] },
      ],
    },
    {
      name: "In review", color: "purple",
      issues: [
        { title: "Speed up the search index rebuild", repo: "gadgets", number: 88, age: "1h", comments: 1, labels: [LABELS.perf], assignees: ["alice", "frank", "devon"] },
      ],
    },
  ],
  done: { expanded: false, issues: [{}, {}, {}, {}, {}] },
};
