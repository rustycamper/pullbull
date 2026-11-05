// Demo data for the saved searches close-up: the empty field open over the list, ↓ pressed once, so the first
// chip is selected and the caption shows its query. Chips whose name is their query draw as code. Two lines of
// chips, the cloud's collapsed height. The list shows below the panel, fading out at the frame's edge.
window.SCENES = window.SCENES || {};
window.SCENES["saved-searches"] = {
  ...window.SCENES.review,
  hover: null,
  fadeAt: 232,
  search: { text: "", focused: true },
  hints: {
    selected: 0,
    saved: [
      { name: "Quick reviews", query: "size:s review:none" },
      { name: "Bugs in api", query: "~bug repo:api" },
      { name: "Bob's week", query: "@bob updated:1w" },
      { name: "is:draft @devon", query: "is:draft @devon" },
      { name: "No bots", query: "-@dependabot" },
    ],
    tokens: [
      [["#", "number"], ["@", "person"], ["~", "label"], ["is:", "state"], ["status:"]],
      [["updated:"], ["review:"], ["repo:"], ["size:"], ["-", "not"]],
    ],
  },
};
