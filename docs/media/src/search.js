// PullBull search as HTML pieces: the results body (SearchResultsView, built from the tab components in
// components.js) and SearchFooter. Sizes in points; see popover.css.
(function () {
  "use strict";
  const P = window.PullBull;
  const { esc } = P;

  /** Highlight.title: every query word on a soft highlight, not bold. */
  function highlight(title, words) {
    let html = esc(title);
    for (const w of words) {
      if (!w) continue;
      html = html.replace(new RegExp(w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "gi"), (m) => `<strong>${m}</strong>`);
    }
    return html;
  }

  const keycap = (k) => `<span class="keycap">${esc(k)}</span>`;
  const keyHint = (keys, label) => `<span class="hstack nowrap" style="gap:4px;flex:none">${keys.map(keycap).join("")}<span>${esc(label)}</span></span>`;

  /** SearchFooter: SearchSummary (SearchContext.footerText: coverage, then "· N matches"), "⌥⌘↩ Ask AI" when Ask is offered and the line fits (`s.ask`), then ↩ Open and esc "Back to <tab>" (`s.startedOn`), or Clear. */
  function searchFooter(s) {
    return `<div class="hstack footer f11" style="padding:0 14px;gap:10px"><span class="ellipsis" style="font-variant-numeric:tabular-nums">${esc(s.coverage)} · ${s.count === 1 ? "1 match" : `${s.count} matches`}</span><span class="spacer"></span>` +
      `${s.ask ? '<span class="nowrap">⌥⌘↩ Ask AI</span>' : ""}${keyHint(["↩"], "Open")}${keyHint(["esc"], s.startedOn ? `Back to ${s.startedOn}` : "Clear")}</div>`;
  }

  /** SearchResultsView: the open results as the Team tab lays them out (repo groups, Team rows), then the ended ones under "Closed and merged". */
  function searchBody(d) {
    const s = d.searchResults;
    let html = "";
    for (const group of s.groups) {
      html += P.groupHeader(group.repo, group.rows.length);
      html += group.rows.map((pr) => P.prRow(pr, "team", { words: s.words })).join("");
    }
    if (s.closed.length) html += P.closedSection({ title: "Closed and merged", count: s.closed.length, expanded: true, rows: s.closed, words: s.words });
    return `<div class="list">${html}</div>`;
  }

  Object.assign(P, { highlight, searchFooter, searchBody });
})();
