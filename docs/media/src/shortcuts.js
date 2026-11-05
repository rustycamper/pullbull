// The Keyboard Shortcuts window (ShortcutsView) as HTML: a titled window with a filter field over a grouped Form.
// Sizes in points; see popover.css.
(function () {
  "use strict";
  const P = window.PullBull;
  const { esc } = P;

  /** ShortcutRow: RowLabel on the left, each way to press it as keycaps on the right. */
  function row(s) {
    const combos = s.keys.map((combo) => `<span class="hstack" style="gap:3px">${combo.map((k) => `<span class="keycap large">${esc(k)}</span>`).join("")}</span>`);
    return `<div class="form-row"><div class="form-label"><div class="f13">${esc(s.action)}</div>${s.note ? `<div class="f11 c-secondary">${esc(s.note)}</div>` : ""}</div>` +
      `<span class="hstack" style="gap:10px;flex:none">${combos.join("")}</span></div>`;
  }

  function section(s) {
    return `<div class="form-section"><div class="form-header">${esc(s.title)}</div><div class="form-card">${s.shortcuts.map(row).join('<div class="hairline form-rule"></div>')}</div></div>`;
  }

  function shortcutsWindow(d) {
    const light = (cls) => `<span class="traffic ${cls}"></span>`;
    return `<div class="window"><div class="titlebar">${light("close")}${light("off")}${light("zoom")}<span class="window-title f13 w-semibold">Keyboard Shortcuts</span></div>` +
      `<div class="filter-field f13">Filter: copy, board, search…</div><div class="form">${d.sections.map(section).join("")}</div></div>`;
  }

  Object.assign(P, { shortcutsWindow });
})();
