// PullBull search as HTML pieces: the results body (SearchResultsView, built from the tab components in
// components.js), CompletionList, CompletionFooter and SearchFooter. Sizes in points; see popover.css.
(function () {
  "use strict";
  const P = window.PullBull;
  const { avatar, esc } = P;

  /** Highlight.title: every query word in bold. */
  function highlight(title, words) {
    let html = esc(title);
    for (const w of words) {
      if (!w) continue;
      html = html.replace(new RegExp(w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "gi"), (m) => `<strong>${m}</strong>`);
    }
    return html;
  }

  /** CompletionList for "@…": avatar 18, login 13 pt (or "me · login"), "member" and "· N" in 11 pt. */
  function completionList(c) {
    const rows = c.candidates.map((p, i) => {
      const name = p.isViewer ? `<span class="f13">me</span><span class="f11 c-secondary">· ${esc(p.login)}</span>` : `<span class="f13">${esc(p.login)}</span>`;
      return `<div class="completion-row${i === c.selection ? " selected" : ""}">${avatar(p.login, 18)}${name}<span class="spacer" style="min-width:8px"></span>` +
        `${p.isMember ? '<span class="f11 c-secondary">member</span>' : ""}${p.openCount > 0 ? `<span class="f11 c-secondary mono">· ${p.openCount}</span>` : ""}</div>`;
    });
    return `<div class="completion-list">${rows.join("")}</div>`;
  }

  const keycap = (k) => `<span class="keycap">${esc(k)}</span>`;
  const keyHint = (keys, label) => `<span class="hstack" style="gap:4px">${keys.map(keycap).join("")}<span>${esc(label)}</span></span>`;

  /** CompletionFooter: replaces the list or search footer while a completion list is open. */
  function completionFooter() {
    return `<div class="hstack footer f11" style="padding:0 14px;gap:10px">${keyHint(["↑", "↓"], "Choose")}${keyHint(["↩", "⇥"], "Complete")}${keyHint(["esc"], "Close")}<span class="spacer"></span></div>`;
  }

  /** SearchFooter: the result count, then ↩ Open and esc Clear. */
  function searchFooter(count) {
    return `<div class="hstack footer f11" style="padding:0 14px;gap:10px"><span class="mono">${count === 1 ? "1 result" : `${count} results`}</span><span class="spacer"></span>${keyHint(["↩"], "Open")}${keyHint(["esc"], "Clear")}</div>`;
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

  Object.assign(P, { highlight, completionList, completionFooter, searchFooter, searchBody });
})();
