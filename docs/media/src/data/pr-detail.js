// Demo data for the PR detail: devon's agent-style PR, approved twice and green, so Ready to merge.
// Opened from the Mine tab. Its checks are all green, so on an open PR they fold to "No checks failed"
// (PRDetailView.checksSection) until clicked; set checksExpanded to show each named check.
window.SCENES = window.SCENES || {};
window.SCENES["pr-detail"] = {
  view: "prDetail",
  viewer: { login: "devon", org: "initech" },
  menuBar: { count: 6, open: true },
  pr: {
    repo: "widgets", number: 1302, state: "open", readyToMerge: true,
    title: "Add a retry budget to webhook delivery",
    author: "devon", opened: "2d ago",
    headRef: "devon/webhook-retry-budget", baseRef: "main",
    checksExpanded: false,
    checks: [
      { name: "build", state: "success", url: true },
      { name: "test (macOS)", state: "success", url: true },
      { name: "test (Linux)", state: "success", url: true },
      { name: "lint", state: "success", url: true },
      { name: "e2e", state: "skipped", url: true },
    ],
    reviewers: [
      { login: "alice", status: "approved" },
      { login: "bob", status: "approved" },
    ],
    body: [
      "Caps retries per endpoint at a **retry budget** of 20 an hour, so one failing receiver can't starve the queue.",
      "",
      "- Budget lives in `DeliveryPolicy`, configurable per org",
      "",
      "<details>",
      "<summary>Verification</summary>",
      "",
      "- [x] `make test` passes",
      "- [x] Replayed 10k deliveries against a failing endpoint",
      "</details>",
    ].join("\n"),
    comments: [
      { author: "alice", age: "1d", body: "Nice. Can we surface the budget in the delivery log too?" },
      { author: "devon", age: "1d", body: "Added in the last commit." },
    ],
    files: {
      additions: 184, deletions: 31, total: 6, blocks: { additions: 4, deletions: 1 },
      list: [
        { path: "Sources/Delivery/DeliveryPolicy.swift", additions: 72, deletions: 4 },
        { path: "Sources/Delivery/WebhookSender.swift", additions: 41, deletions: 19 },
        { path: "Sources/Delivery/DeliveryLog.swift", additions: 18, deletions: 2 },
        { path: "Tests/DeliveryTests/RetryBudgetTests.swift", additions: 46, deletions: 0 },
        { path: "docs/webhooks.md", additions: 6, deletions: 6 },
        { path: "Config/defaults.yml", additions: 1, deletions: 0 },
      ],
    },
  },
};
