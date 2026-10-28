// PullBull search (SearchResultsView, CompletionList, CompletionFooter) as HTML pieces. Builds on
// components.js (window.PullBull). Sizes in points; see popover.css.
(function () {
  "use strict";
  const P = window.PullBull;
  const { sym, avatar, esc } = P;

  /** Highlight.title: every query word in bold. */
  function highlight(title, words) {
    let html = esc(title);
    for (const w of words) {
      if (!w) continue;
      html = html.replace(new RegExp(w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "gi"), (m) => `<strong>${m}</strong>`);
    }
    return html;
  }

  /** SearchGroupHeader: 11 pt semibold title and medium count, 12 above, 4 below. */
  const groupHeader = (title, count) =>
    `<div class="hstack search-group f11 w-semibold">${esc(title)}<span class="w-medium mono">${count}</span></div>`;

  /** SearchPRRow: state glyph, highlighted title, "repo #num · author · when"; CI glyph or Merged/Closed pill. */
  function prRow(pr, words) {
    const glyph = {
      open: ["pullbull.pullrequest", "var(--secondary)"],
      merged: ["pullbull.pullrequest.merged", "var(--merged-text)"],
      closed: ["pullbull.pullrequest.closed", "var(--closed-text)"],
    }[pr.state];
    const size = pr.state === "open" ? 13 : 12;
    const trailing = pr.state === "merged" ? `<span class="pill merged">Merged</span>`
      : pr.state === "closed" ? `<span class="pill closed">Closed</span>`
      : `<span class="ci" style="margin:0">${sym({ success: "checkmark.circle", failure: "xmark.circle.fill", pending: "clock", skipped: "minus.circle" }[pr.ci], 13, "regular", { color: pr.ci === "failure" ? "var(--red)" : "var(--secondary)" })}</span>`;
    const dim = pr.state !== "open" || pr.draft;
    return `<div class="row search-row-pr"><span class="leading" style="margin-top:0">${sym(glyph[0], size, "regular", { color: glyph[1] })}</span>` +
      `<div class="vstack body"><span class="title-text f13" style="${dim ? "color:var(--secondary)" : ""}">${highlight((pr.draft ? "Draft: " : "") + pr.title, words)}</span>` +
      `<div class="hstack meta f11 mono"><span class="w-semibold">${esc(pr.repo)} #${pr.number}</span><span>·</span><span>${esc(pr.author)}</span><span>·</span><span>${esc(pr.when)}</span>${pr.role ? `<span>·</span><span>${esc(pr.role)}</span>` : ""}</div></div>` +
      `<span style="margin-top:1px;flex:none">${trailing}</span></div>`;
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

  function searchBody(d) {
    const s = d.searchResults;
    const ctx = `<div class="hstack search-context f11">${s.login ? avatar(s.login, 14) : ""}<span class="ellipsis">${esc(s.context)}</span></div>`;
    let html = ctx;
    if (s.open.length) html += groupHeader("Open pull requests", s.open.length) + s.open.map((pr) => prRow(pr, s.words)).join("");
    if (s.closed.length) html += groupHeader("Closed and merged pull requests", s.closed.length) + s.closed.map((pr) => prRow(pr, s.words)).join("");
    return `<div class="list">${html}</div>`;
  }

  Object.assign(P, { highlight, searchPRRow: prRow, completionList, completionFooter, searchFooter, searchBody });
})();
