// Demo data for the Keyboard Shortcuts window as it opens, unfiltered: the top of ShortcutCatalog.sections with the
// toggle set to ⌃⌥P. The window's edge cuts the list, which scrolls.
window.SCENES = window.SCENES || {};
window.SCENES.shortcuts = {
  view: "shortcuts",
  sections: [
    {
      title: "PullBull",
      shortcuts: [
        { action: "Show or hide PullBull", keys: [["⌃", "⌥", "P"]], note: "From any app" },
        { action: "Settings", keys: [["⌘", ","]] },
        { action: "Keyboard shortcuts", keys: [["⌘", "/"]] },
        { action: "Refresh", keys: [["⌘", "R"]], note: "On Stats, refreshes the stats" },
        { action: "Close", keys: [["⌘", "W"]] },
      ],
    },
    {
      title: "Lists",
      shortcuts: [
        { action: "Select", keys: [["↑"], ["↓"]] },
        { action: "Previous / next group", keys: [["⌥", "↑"], ["⌥", "↓"]], note: "Section, repo, author, lane, Done, Closed. Folded lanes are skipped" },
        { action: "First / last row", keys: [["⌘", "↑"], ["⌘", "↓"]] },
        { action: "Previous / next chip", keys: [["←"], ["→"]] },
        { action: "Pull Requests", keys: [["⌘", "1"]] },
        { action: "Issues", keys: [["⌘", "2"]] },
        { action: "Stats", keys: [["⌘", "3"]] },
        { action: "Open detail", keys: [["↩"]] },
        { action: "Open on GitHub", keys: [["⌘", "↩"]] },
      ],
    },
  ],
};
