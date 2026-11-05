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

  /** SearchResultsView: the open results in the list's sections (nothing folds), then the ended ones under "Closed and merged". */
  function searchBody(d) {
    const s = d.searchResults;
    const sections = s.sections.map((sec) => ({ ...sec, words: s.words }));
    let html = P.sectionList(sections);
    if (s.closed.length) html += P.closedSection({ title: "Closed and merged", count: s.closed.length, expanded: true, rows: s.closed, words: s.words });
    return `<div class="list">${html}</div>`;
  }

  /** SearchHints: saved chips (filled, a code font when the name is the query, ⌃N after the first nine), two token lines, and the caption. */
  function searchHints(h) {
    const chip = (s, i) => `<span class="hint-chip${i === h.selected ? " selected" : ""}"><span class="${s.name === s.query ? "code" : ""}">${esc(s.name)}</span><span class="f11 c-secondary">⌃${i + 1}</span></span>`;
    const token = ([sigil, word]) => `<span class="hint-token"><span class="sigil">${esc(sigil)}</span>${word ? `<span class="c-secondary">${esc(word)}</span>` : ""}</span>`;
    const line = (tokens) => `<div class="hstack" style="gap:4px">${tokens.map(token).join("")}</div>`;
    const picked = h.saved[h.selected];
    return `<div class="hints"><div class="hint-cloud">${h.saved.map(chip).join("")}</div><div class="hint-tokens">${h.tokens.map(line).join("")}</div>` +
      `<div class="hstack hint-caption"><span class="code f11 ellipsis">${esc(picked.query)}</span><span class="spacer"></span>${keycap("↩")}</div></div>`;
  }

  Object.assign(P, { highlight, searchFooter, searchBody, searchHints });
})();
