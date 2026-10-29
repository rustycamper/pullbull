// PullBull popover mockup: small functions that each return the HTML for one SwiftUI view, so a scene
// (or a later animated film) is data plus a composition of these. Sizes are points; see popover.css.
(function () {
  "use strict";

  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

  // ---------- Symbols ----------

  /** An exported symbol mask (symbols/manifest.js) at its own point size, tinted with `color` or the current colour. */
  function sym(name, size, weight = "regular", opts = {}) {
    const key = `${name}|${size}|${weight}`;
    const entry = window.SYMBOLS[key];
    if (!entry) throw new Error(`symbol not exported: ${key}`);
    const url = `symbols/${entry.file}`;
    const color = opts.color ? `color:${opts.color};` : "";
    const cls = opts.cls ? ` ${opts.cls}` : "";
    let box = `width:${entry.w}px;height:${entry.h}px;`;
    if (opts.fit) {
      // .resizable().scaledToFit() into a square box: the glyph's ink fills it, as in the reference.
      const [ix, iy, iw, ih] = entry.ink;
      const k = Math.min(opts.fit / iw, opts.fit / ih);
      const mask = `-webkit-mask-size:${entry.w * k}px ${entry.h * k}px;mask-size:${entry.w * k}px ${entry.h * k}px;` +
        `-webkit-mask-position:${-ix * k}px ${-iy * k}px;mask-position:${-ix * k}px ${-iy * k}px;`;
      box = `width:${iw * k}px;height:${ih * k}px;${mask}`;
    }
    return `<span class="sym${cls}" style="${color}${box}-webkit-mask-image:url('${url}');mask-image:url('${url}')"></span>`;
  }

  /** The menu bar glyph (MenuBarGlyph.imageset), drawn as a template in the menu bar ink. */
  function menuBarGlyph() {
    return `<svg class="glyph" viewBox="0 0 18 18"><g fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
      <circle cx="4.5" cy="3.75" r="1.75"/><circle cx="4.5" cy="14.25" r="1.75"/><circle cx="13.5" cy="14.25" r="1.75"/>
      <line x1="4.5" y1="5.5" x2="4.5" y2="12.5"/><path d="M13.5 12.5 V7.5 A2.5 2.5 0 0 0 11 5 H8.5"/><path d="M10.25 2.75 L8.25 5 L10.25 7.25"/></g></svg>`;
  }

  // ---------- Avatars ----------

  function hash(s) {
    let h = 0x811c9dc5;
    for (const ch of s) { h ^= ch.charCodeAt(0); h = Math.imul(h, 0x01000193) >>> 0; }
    return h;
  }

  function popcount(v) { let n = 0; for (; v; v &= v - 1) n++; return n; }

  /** A GitHub-style identicon: a 5×5 mirrored grid in one colour on a pale ground, from the login's hash. */
  function identicon(login) {
    const h = hash(login);
    const hue = h % 360;
    const fg = `hsl(${hue} 52% 58%)`;
    let cells = "";
    // Reseed until the pattern is neither sparse nor solid (7–11 of the 15 source cells), so every avatar reads.
    let bits = hash(login + "#");
    for (let seed = 1, n = popcount(bits & 0x7fff); n < 7 || n > 11; seed++, n = popcount(bits & 0x7fff)) bits = hash(login + "#" + seed);
    for (let y = 0; y < 5; y++) {
      for (let x = 0; x < 3; x++) {
        const on = (bits >>> (y * 3 + x)) & 1;
        if (!on) continue;
        cells += `<rect x="${x + 0.5}" y="${y + 0.5}" width="1.02" height="1.02"/>`;
        if (x < 2) cells += `<rect x="${4 - x + 0.5}" y="${y + 0.5}" width="1.02" height="1.02"/>`;
      }
    }
    return `<svg viewBox="0 0 6 6" shape-rendering="crispEdges"><rect width="6" height="6" fill="#f0f0f0"/><g fill="${fg}">${cells}</g></svg>`;
  }

  function avatar(login, size) {
    return `<span class="avatar" style="width:${size}px;height:${size}px">${identicon(login)}</span>`;
  }

  // ---------- Header ----------

  function modeToggle(mode) {
    const btn = (m, symbol) => {
      const selected = mode === m;
      return `<span class="mode-button${selected ? " selected" : ""}">${sym(symbol, 13, selected ? "semibold" : "regular")}</span>`;
    };
    return `<div class="hstack mode-toggle">${btn("pullRequests", "pullbull.pullrequest")}${btn("issues", "pullbull.issue")}<span class="hairline-v"></span></div>`;
  }

  function tabBar(tabs, selectedId) {
    const segs = tabs.map((t) => {
      const selected = t.id === selectedId;
      const count = t.count == null ? "" : `<span class="count f11 mono">${t.count > 99 ? "99+" : t.count}</span>`;
      return `<div class="segment${selected ? " selected" : ""}"><span class="label-run">` +
        `<span class="title f12" data-title="${esc(t.title)}"><span>${esc(t.title)}</span></span>${count}</span></div>`;
    });
    return `<div class="tab-bar">${segs.join("")}</div>`;
  }

  function searchField(search, mode) {
    const placeholder = mode === "issues" ? "Search issues" : "Search pull requests";
    // The typed text with the insertion point at its end while focused.
    const caret = search && search.focused ? `<span class="caret"></span>` : "";
    const text = search && search.text
      ? `<span class="text f12 ellipsis">${esc(search.text).replace(/ /g, "&nbsp;")}${caret}</span>`
      : `<span class="placeholder f12 ellipsis">${caret}${placeholder}</span>`;
    // SaveSearchButton (bookmark) and the clear button with text; "⌘F" only while unfocused and empty.
    const trailing = search && search.text
      ? `<span class="c-secondary" style="width:16px;height:16px;display:flex;align-items:center;justify-content:center">${sym("bookmark", 11)}</span>` +
        `<span class="c-secondary" style="width:16px;height:16px;border-radius:50%;background:var(--strong-fill);display:flex;align-items:center;justify-content:center">${sym("xmark", 7, "bold")}</span>`
      : (search && search.focused ? "" : `<span class="shortcut f11">⌘F</span>`);
    return `<div class="search-row"><div class="hstack search-field${search && search.focused ? " focused" : ""}">` +
      `<span class="c-tertiary hstack">${sym("magnifyingglass", 11)}</span>${text}${trailing}</div></div>`;
  }

  function header(d) {
    return `<div class="hstack title-row">${modeToggle(d.mode)}${tabBar(d.tabs, d.selectedTab)}</div>${searchField(d.search, d.mode)}`;
  }

  /** FilterBar: "▦ Roadmap ▾ · ▤ All repos ▾" on the Board tab, "▤ All repos ▾" elsewhere. */
  function filterBar(filter) {
    const board = filter.boardTitle
      ? `<span class="hstack" style="gap:6px">${sym("rectangle.split.3x1", 10, "medium")}<span class="nowrap">${esc(filter.boardTitle)} ▾</span></span><span class="c-tertiary">·</span>`
      : "";
    return `<div class="hstack filter-bar f11">${board}<span class="hstack" style="gap:6px">${sym("line.3.horizontal.decrease", 10, "medium")}<span class="nowrap">${esc(filter.repoTitle)} ▾</span></span><span class="spacer"></span></div>`;
  }

  // ---------- Rows ----------

  // RowChips.Info: symbol, meta text, and whether it is a count (sits after the age, unpunctuated).
  const INFO = {
    reRequested: { symbol: "arrow.uturn.left", text: "Re-requested" },
    newCommits: { symbol: "arrow.triangle.2.circlepath", text: "New commits" },
    noReviews: { symbol: "clock", text: "No reviews" },
    youApprovedNotCounted: { symbol: "checkmark", text: "You approved · not counted" },
    conflicts: { symbol: "exclamationmark.triangle", text: "Conflicts", warning: true },
  };
  function infoOf(item) {
    if (typeof item === "string") return INFO[item];
    if (item.approvals != null) return { symbol: "checkmark", text: String(item.approvals), isCount: true };
    if (item.viaTeam) return { symbol: "person.2", text: `via @${item.viaTeam}` };
    return item;
  }

  // Palette.ciGlyph
  function ciGlyph(state) {
    const g = {
      success: ["checkmark.circle", "var(--secondary)"],
      failure: ["xmark.circle.fill", "var(--red)"],
      pending: ["clock", "var(--secondary)"],
      skipped: ["minus.circle", "var(--secondary)"],
      none: ["minus", "var(--tertiary)"],
    }[state || "none"];
    return `<span class="ci">${sym(g[0], 13, "regular", { color: g[1] })}</span>`;
  }

  const PR_GLYPH = { open: "pullbull.pullrequest", draft: "pullbull.pullrequest.draft", merged: "pullbull.pullrequest.merged", closed: "pullbull.pullrequest.closed" };

  /** PRRow.fullBody */
  function prRow(pr, tab, opts = {}) {
    const dot = `<span class="dot">·</span>`;
    const infos = (pr.info || []).map(infoOf);
    let meta = "";
    if (pr.draft) meta += `<span class="pill draft">Draft</span>`;
    meta += `<span>${opts.showsRepo ? esc(pr.repo) + " " : ""}#${pr.number}</span>${dot}`;
    if (tab !== "mine") meta += `<span>${esc(pr.author)}</span>${dot}`;
    meta += `<span>${esc(pr.age)}</span>`;
    for (const info of infos.filter((i) => !i.isCount)) {
      const color = info.warning ? "var(--amber-glyph)" : "var(--secondary)";
      meta += `${dot}<span class="label">${sym(info.symbol, 9.5, "regular", { color })}<span>${esc(info.text)}</span></span>`;
    }
    for (const info of infos.filter((i) => i.isCount)) {
      meta += `<span class="label count">${sym(info.symbol, 9.5)}<span>${esc(info.text)}</span></span>`;
    }
    if (pr.comments > 0) meta += `<span class="label count" style="gap:3px">${sym("bubble.left", 9.5)}<span>${pr.comments}</span></span>`;
    // RowChips.Action: Mine's one capsule (PRRow.actionCapsule)
    if (pr.action === "readyToMerge") {
      meta += `<span class="pill ready" style="margin-left:4px">${sym("arrow.triangle.merge", 9, "semibold")}<span>Ready to merge</span></span>`;
    } else if (pr.action && pr.action.changesRequested) {
      meta += `<span class="pill changes" style="margin-left:4px">${sym("arrow.uturn.backward", 9, "semibold")}<span>Changes requested · ${esc(pr.action.changesRequested.join(", "))}</span></span>`;
    }

    const leading = tab === "mine"
      ? sym(PR_GLYPH[pr.draft ? "draft" : "open"], 13)
      : avatar(pr.author, 20);
    const cls = ["row", pr.draft ? "draft" : "", pr.dimmed ? "dimmed" : "", pr.hover ? "hover" : "", pr.selected ? "selected" : ""].filter(Boolean).join(" ");
    return `<div class="${cls}" data-number="${pr.number}"><span class="leading"${pr.dimmed ? ' style="opacity:.45"' : ""}>${leading}</span>` +
      `<div class="vstack body"><span class="title-text f13">${esc(pr.title)}</span><div class="hstack meta f11 mono">${meta}</div></div>` +
      `${ciGlyph(pr.ci)}</div>`;
  }

  /** PRListView.GroupHeader */
  function groupHeader(repo, count) {
    return `<div class="hstack group-header f11 w-semibold">${sym("book.closed", 10)}<span>${esc(repo)}</span>` +
      (count > 0 ? `<span class="w-medium mono">${count}</span>` : "") + `</div>`;
  }

  /** ClosedRow */
  function closedRow(pr) {
    const merged = pr.state === "merged";
    return `<div class="hstack closed-row"><span class="glyph">${sym(PR_GLYPH[pr.state], 12, "regular", { color: merged ? "var(--merged-text)" : "var(--closed-text)" })}</span>` +
      `<div class="vstack body"><span class="f12 ellipsis">${esc(pr.title)}</span><span class="f11 mono ellipsis">${esc(pr.repo)} #${pr.number} · ${merged ? "merged" : "closed"} ${esc(pr.when)}</span></div>` +
      `<span class="pill ${merged ? "merged" : "closed"}">${merged ? "Merged" : "Closed"}</span></div>`;
  }

  function closedSection(rc) {
    const chevron = `<span style="display:inline-flex;transform:rotate(${rc.expanded ? 90 : 0}deg)">${sym("chevron.right", 9, "bold")}</span>`;
    let html = `<div class="hairline closed-rule"></div><div class="hstack closed-header f11 w-semibold">${chevron}<span>Recently closed</span>` +
      `<span class="w-medium mono">${rc.count}</span><span class="spacer"></span><span style="font-weight:400">Last 7 days</span></div>`;
    if (rc.expanded) html += rc.rows.map(closedRow).join("");
    return html;
  }

  // ---------- Issues ----------

  // LabelDotColor.tuned: keep the hue, cap saturation at 0.72, walk lightness until 3.2:1 on the popover.
  function hls(c) {
    const r = ((c >> 16) & 255) / 255, g = ((c >> 8) & 255) / 255, b = (c & 255) / 255;
    const hi = Math.max(r, g, b), lo = Math.min(r, g, b), l = (hi + lo) / 2;
    if (hi === lo) return [0, l, 0];
    const d = hi - lo, s = l <= 0.5 ? d / (hi + lo) : d / (2 - hi - lo);
    const rc = (hi - r) / d, gc = (hi - g) / d, bc = (hi - b) / d;
    let h = r === hi ? bc - gc : g === hi ? 2 + rc - bc : 4 + gc - rc;
    h = (h / 6) % 1; if (h < 0) h += 1;
    return [h, l, s];
  }
  function fromHls(h, l, s) {
    const pack = (r, g, b) => [r, g, b].map((v) => Math.min(255, Math.max(0, Math.round(v * 255))));
    if (s <= 0) return pack(l, l, l);
    const m2 = l <= 0.5 ? l * (1 + s) : l + s - l * s, m1 = 2 * l - m2;
    const v = (hue) => {
      hue = hue % 1; if (hue < 0) hue += 1;
      if (hue < 1 / 6) return m1 + (m2 - m1) * hue * 6;
      if (hue < 0.5) return m2;
      if (hue < 2 / 3) return m1 + (m2 - m1) * (2 / 3 - hue) * 6;
      return m1;
    };
    return pack(v(h + 1 / 3), v(h), v(h - 1 / 3));
  }
  function luminance([r, g, b]) {
    const ch = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b);
  }
  function tunedLabelColor(hex, scheme) {
    let [h, l, s] = hls(parseInt(hex, 16));
    s = Math.min(s, 0.72);
    const bg = luminance(scheme === "light" ? [0xf2, 0xf1, 0xf5] : [0x28, 0x27, 0x2d]);
    const step = scheme === "light" ? -0.005 : 0.005;
    let c = fromHls(h, l, s);
    for (let i = 0; i < 200; i++) {
      c = fromHls(h, l, s);
      const lc = luminance(c);
      if ((Math.max(lc, bg) + 0.05) / (Math.min(lc, bg) + 0.05) >= 3.2) break;
      l = Math.min(1, Math.max(0, l + step));
    }
    return `rgb(${c.join(",")})`;
  }

  /** IssueRow's LabelChip: an outlined chip, led by a LabelDot in the label's tuned colour. */
  function labelChip(text, hex, scheme) {
    const dot = hex ? `<span class="label-dot" style="background:${tunedLabelColor(hex, scheme)}"></span>` : "";
    return `<span class="label-chip">${dot}<span>${esc(text)}</span></span>`;
  }

  /** AssigneeStack: up to three 18 pt avatars overlapping by 5, each cut 1.5 pt around the next; a dashed ring when unassigned. */
  function assigneeStack(logins, size, showUnassigned) {
    if (!logins.length) {
      if (!showUnassigned) return "";
      const r = size / 2 - 0.5;
      return `<span class="c-secondary" style="display:block;width:${size}px;height:${size}px;flex:none"><svg width="${size}" height="${size}"><circle cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="currentColor" stroke-width="1" stroke-dasharray="2 2"/></svg></span>`;
    }
    const shown = logins.slice(0, 3);
    return `<span class="hstack" style="flex:none">` + shown.map((login, i) => {
      const cut = i < shown.length - 1
        ? `-webkit-mask:radial-gradient(circle at ${size * 1.5 - 5}px 50%, transparent ${size / 2 + 1.5}px, #000 ${size / 2 + 1.5}px);`
        : "";
      return `<span style="display:block;${i ? "margin-left:-5px;" : ""}${cut}">${avatar(login, size)}</span>`;
    }).join("") + `</span>`;
  }

  // Palette.issueGlyph
  const ISSUE_GLYPH = {
    open: ["pullbull.issue", "var(--secondary)"],
    completed: ["pullbull.issue.closed", "var(--merged-text)"],
    notPlanned: ["pullbull.issue.notplanned", "var(--secondary)"],
  };

  /** IssueRow.fullBody with IssueMetaLine: repo #num · age, comments, two label chips then "+N". */
  function issueRow(issue, tab, scheme, opts = {}) {
    const [glyph, color] = ISSUE_GLYPH[issue.glyph || "open"];
    let meta = `<span>${opts.inRepoGroup ? "" : esc(issue.repo) + " "}#${issue.number}</span>`;
    if (issue.age) meta += `<span class="dot">·</span><span>${esc(issue.age)}</span>`;
    if (issue.comments > 0) meta += `<span class="label" style="margin-left:2px">${sym("bubble.left", 9.5)}<span>${issue.comments}</span></span>`;
    // Every candidate chip is drawn; fitIssueMeta() then drops chips from the end into "+N" until the
    // line fits, as ViewThatFits does in IssueMetaLine.
    const labels = issue.labels || [];
    labels.slice(0, 2).forEach((l) => {
      const name = l.name.length > 18 ? l.name.slice(0, 17) + "…" : l.name;
      meta += labelChip(name, l.color, scheme).replace('class="label-chip"', 'class="label-chip shown"');
    });
    meta += labelChip(`+${labels.length - Math.min(2, labels.length)}`, null, scheme).replace('class="label-chip"', `class="label-chip more" data-total="${labels.length}"`);
    return `<div class="row issue${opts.past ? " past" : ""}"><span class="leading" style="margin-top:0">${sym(glyph, 13, "regular", { color })}</span>` +
      `<div class="vstack body"><span class="title-text f13">${esc(issue.title)}</span><div class="hstack meta issue-meta f11 mono">${meta}</div></div>` +
      `<span style="margin-top:1px;flex:none">${assigneeStack(issue.assignees || [], 18, tab === "board")}</span></div>`;
  }

  // Palette.statusOptionColor; BoardStatusGlyph.symbol(forStatusNamed:)
  const STATUS_COLOR = {
    gray: "var(--secondary)", blue: "var(--status-blue)", green: "var(--status-green)", yellow: "var(--status-yellow)",
    orange: "var(--status-orange)", red: "var(--closed-text)", pink: "var(--status-pink)", purple: "var(--merged-text)",
  };
  function statusSymbol(name) {
    const n = name.toLowerCase();
    return n.includes("progress") || n.includes("review") || n.includes("doing") ? "circle.lefthalf.filled" : "circle.dashed";
  }

  /** IssueGroupHeader for a Board lane: chevron in the leading inset, tinted glyph in the icon column, title and count. */
  function laneHeader(lane) {
    const chevron = `<span class="lane-chevron c-secondary" style="transform:rotate(${lane.folded ? 0 : 90}deg)">${sym("chevron.right", 9, "bold")}</span>`;
    const color = STATUS_COLOR[lane.color || "gray"];
    return `<div class="hstack lane-header f11 w-semibold">${chevron}<span class="icon-col">${sym(statusSymbol(lane.name), 11, "regular", { color })}</span>` +
      `<span class="hstack" style="gap:6px"><span>${esc(lane.name)}</span><span class="w-medium mono">${lane.issues.length}</span></span></div>`;
  }

  /** IssueListView.doneSection: folded by default. */
  function doneSection(done, scheme) {
    const chevron = `<span class="lane-chevron c-secondary" style="transform:rotate(${done.expanded ? 90 : 0}deg)">${sym("chevron.right", 9, "bold")}</span>`;
    let html = `<div class="hstack done-header f11 w-semibold">${chevron}<span class="icon-col">${sym("checkmark.circle", 11)}</span>` +
      `<span class="hstack" style="gap:6px"><span>Done</span><span class="w-medium mono">${done.issues.length}</span><span style="font-weight:400">· last 14 days</span></span></div>`;
    if (done.expanded) html += done.issues.map((i) => issueRow(i, "board", scheme, { past: true })).join("");
    return html;
  }

  /** IssueMetaLine's ViewThatFits: the most chips that fit, the rest counted in "+N" (hidden at +0). */
  function fitIssueMeta(root) {
    for (const line of root.querySelectorAll(".issue-meta")) {
      const more = line.querySelector(".label-chip.more");
      const total = Number(more.dataset.total);
      const shown = [...line.querySelectorAll(".label-chip.shown")];
      const update = () => {
        const extra = total - shown.length;
        more.style.display = extra > 0 ? "" : "none";
        more.querySelector("span:last-child").textContent = `+${extra}`;
      };
      update();
      while (shown.length && line.scrollWidth > line.clientWidth) {
        shown.pop().remove();
        update();
      }
    }
  }

  function issueList(d, scheme) {
    let html = "";
    for (const lane of d.lanes) {
      html += laneHeader(lane);
      if (!lane.folded) html += lane.issues.map((i) => issueRow(i, d.selectedTab, scheme)).join("");
    }
    if (d.done) html += doneSection(d.done, scheme);
    return `<div class="list">${html}</div>`;
  }

  /**
   * The pointer resting on part of a PR row: the row takes RowFill's hover tint, the system arrow cursor
   * (NSCursor.arrow, hot spot 5,5) sits on the target, and the target's `.help` text shows as the native
   * tooltip just below and right of the pointer. `hover = { number, on: "ci", tooltip, at: [dx, dy] }`.
   */
  function placeHover(root, hover) {
    const row = root.querySelector(`.row[data-number="${hover.number}"]`);
    if (!row) return;
    row.classList.add("hover");
    const target = row.querySelector(hover.on === "ci" ? ".ci" : ".leading");
    const base = root.getBoundingClientRect(), r = target.getBoundingClientRect();
    const [dx, dy] = hover.at || [1, 2];
    const x = r.left - base.left + r.width / 2 + dx, y = r.top - base.top + r.height / 2 + dy;
    root.insertAdjacentHTML("beforeend",
      `<div class="tooltip f11" style="left:${x + 9}px;top:${y + 21}px">${esc(hover.tooltip)}</div>` +
      `<img class="cursor" src="symbols/cursor-arrow.png" style="left:${x - 5}px;top:${y - 5}px" alt="">`);
  }

  function list(d) {
    let html = "";
    for (const group of d.groups) {
      if (d.groupByRepo) html += groupHeader(group.repo, group.count ?? group.rows.length);
      html += group.rows.map((pr) => prRow(pr, d.selectedTab, { showsRepo: !d.groupByRepo })).join("");
    }
    if (d.selectedTab === "mine" && d.recentlyClosed) html += closedSection(d.recentlyClosed);
    return `<div class="list">${html}</div>`;
  }

  // ---------- Footer ----------

  function footer(viewer) {
    // FooterGlyph: a 12×12 box (scaledToFit) inside 24×24
    const button = (name) => `<span class="footer-button">${sym(name, 24, "medium", { fit: 12 })}</span>`;
    return `<div class="hstack footer f11"><span class="hstack account">${avatar(viewer.login, 14)}<span class="nowrap">${esc(viewer.login)} · ${esc(viewer.org || "personal")}</span></span>` +
      `<span class="spacer" style="min-width:8px"></span>${button("arrow.clockwise")}${button("arrow.up.right.square")}${button("gearshape")}</div>`;
  }

  // ---------- Assembly ----------

  function popover(d, scheme) {
    // A detail is a layer over the whole panel: its own header and bottom bar, no tabs or footer.
    if (d.view === "prDetail") return `<div class="panel">${window.PullBull.prDetail(d)}</div>`;
    if (d.view === "issueDetail") return `<div class="panel">${window.PullBull.issueDetail(d, scheme)}</div>`;
    const P = window.PullBull;
    const searching = d.view === "search";
    const body = searching ? P.searchBody(d) : d.mode === "issues" ? issueList(d, scheme) : list(d);
    const foot = d.completion ? P.completionFooter() : searching ? P.searchFooter(d.searchResults.count) : footer(d.viewer);
    // The completion list overlays the top of the filter row and everything under it (PopoverView.tabsAndSearch).
    const overlay = d.completion ? `<div class="completion-overlay">${P.completionList(d.completion)}</div>` : "";
    return `<div class="panel">${header(d)}${d.filter ? "" : '<div class="hairline"></div>'}` +
      `<div class="below-header">${d.filter ? filterBar(d.filter) : ""}${body}${overlay}</div>${foot}</div>`;
  }

  function menuBarItem(count, open) {
    return `<div class="status-item${open ? " open" : ""}">${menuBarGlyph()}${count > 0 ? `<span class="count">${count > 99 ? "99+" : count}</span>` : ""}</div>`;
  }

  /**
   * The whole scene: desktop, a menu bar slice with the PullBull item, and the popover 4 pt under it,
   * centred on the item (PopoverController.frameUnderStatusItem). Positions are measured after layout.
   */
  function renderScene(root, d, scene) {
    root.className = `scene scheme-${scene.scheme}`;
    root.style.width = `${scene.width}px`;
    root.style.height = `${scene.height}px`;
    root.innerHTML = `<div class="menubar">${menuBarItem(d.menuBar.count, d.menuBar.open)}</div>${popover(d, scene.scheme)}`;
    fitIssueMeta(root);
    const item = root.querySelector(".status-item");
    const panel = root.querySelector(".panel");
    const itemWidth = item.getBoundingClientRect().width;
    const centre = scene.itemCentre ?? scene.width / 2;
    item.style.left = `${centre - itemWidth / 2}px`;
    panel.style.left = `${centre - 180}px`;
    panel.style.top = `${24 + 4}px`;
    if (d.hover) placeHover(root, d.hover);
  }

  window.PullBull = { esc, sym, avatar, identicon, modeToggle, tabBar, searchField, header, filterBar, prRow, groupHeader, closedRow, closedSection, list, issueRow, laneHeader, doneSection, labelChip, assigneeStack, issueList, tunedLabelColor, footer, popover, menuBarItem, renderScene };
})();
