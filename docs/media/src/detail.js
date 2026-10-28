// PullBull detail views (PRDetailView, IssueDetailView, DetailComponents, MarkdownBlocks) as HTML pieces.
// Builds on components.js (window.PullBull). Sizes in points; see popover.css.
(function () {
  "use strict";
  const P = window.PullBull;
  const { sym, avatar, esc } = P;

  // ---------- Markdown (MarkdownBlocks.swift), the subset the demo text uses ----------

  /** Inline markdown: `code`, **bold**, [links](url). */
  function inline(text) {
    return esc(text)
      .replace(/`([^`]+)`/g, '<code class="md-code-inline">$1</code>')
      .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
      .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<span class="link">$1</span>');
  }

  /**
   * Blocks: paragraphs, "- " lists with "[ ]"/"[x]" task boxes, and <details>/<summary> sections, collapsed
   * unless `<details open>` (MarkdownDetails). Blocks are 8 apart (MarkdownText's VStack).
   */
  function markdown(source) {
    const lines = source.trim().split("\n");
    const blocks = [];
    let i = 0;
    while (i < lines.length) {
      const line = lines[i];
      if (!line.trim()) { i++; continue; }
      const details = line.match(/^<details( open)?>\s*(?:<summary>(.*)<\/summary>)?/);
      if (details) {
        let summary = details[2] || "";
        const inner = [];
        i++;
        for (; i < lines.length && !lines[i].startsWith("</details>"); i++) {
          const s = lines[i].match(/^<summary>(.*)<\/summary>/);
          if (s) summary = s[1]; else inner.push(lines[i]);
        }
        i++;
        const open = Boolean(details[1]);
        blocks.push(`<div class="md-details"><div class="md-summary"><span class="md-chevron" style="transform:rotate(${open ? 90 : 0}deg)">${sym("chevron.right", 9, "bold")}</span><span>${inline(summary)}</span></div>` +
          (open ? `<div class="md-details-body">${markdown(inner.join("\n"))}</div>` : "") + `</div>`);
        continue;
      }
      if (/^\s*- /.test(line)) {
        const items = [];
        for (; i < lines.length && /^\s*- /.test(lines[i]); i++) {
          const m = lines[i].match(/^\s*- (?:\[( |x)\] )?(.*)$/);
          const marker = m[1] === undefined
            ? `<span class="c-secondary">•</span>`
            : `<span class="c-secondary md-task">${sym(m[1] === "x" ? "checkmark.square.fill" : "square", 11)}</span>`;
          items.push(`<div class="md-item">${marker}<span>${inline(m[2])}</span></div>`);
        }
        blocks.push(`<div class="md-list">${items.join("")}</div>`);
        continue;
      }
      const para = [];
      for (; i < lines.length && lines[i].trim() && !/^\s*- /.test(lines[i]) && !lines[i].startsWith("<details"); i++) para.push(lines[i]);
      blocks.push(`<p>${inline(para.join(" "))}</p>`);
    }
    return `<div class="md">${blocks.join("")}</div>`;
  }

  // ---------- Shared pieces (DetailComponents.swift) ----------

  /** The 44 pt header: back chevron, centred "repo #num", Copy Link and Refresh. */
  function detailHeader(title) {
    const button = (name, size, weight) => `<span class="detail-icon c-secondary">${sym(name, size, weight)}</span>`;
    return `<div class="detail-header">${button("chevron.left", 13, "medium")}<span class="spacer"></span>` +
      `${button("link", 13, "regular")}${button("arrow.clockwise", 13, "regular")}` +
      `<span class="detail-title f13 w-semibold mono">${esc(title)}</span></div><div class="hairline"></div>`;
  }

  function section(title, summary, content, accessory = "") {
    return `<div class="detail-section"><div class="section-head f11"><span class="w-semibold">${esc(title)}</span><span class="spacer"></span>` +
      `${summary ? `<span class="mono">${esc(summary)}</span>` : ""}${accessory}</div>${content}</div>`;
  }

  const card = (rows) => `<div class="detail-card">${rows.join('<div class="hairline"></div>')}</div>`;

  /** Pill (PRRow.swift): 16 tall capsule, 9 pt semibold glyph, 10 pt semibold text. */
  function pill(text, { symbol, fg, fill, symbolColor, stroke } = {}) {
    const glyph = symbol ? sym(symbol, 9, "semibold", { color: symbolColor || fg }) : "";
    return `<span class="pill" style="color:${fg};background:${fill || "transparent"};${stroke ? "box-shadow:inset 0 0 0 0.5px var(--separator);" : ""}">${glyph}<span>${esc(text)}</span></span>`;
  }

  /** CommentLine: avatar, "author · age", the Markdown body. */
  function commentLine(c) {
    return `<div class="comment">${avatar(c.author, 20)}<div class="vstack" style="gap:2px;flex:1;min-width:0">` +
      `<div class="hstack f12" style="gap:4px"><span class="w-semibold">${esc(c.author)}</span><span class="f11 c-secondary mono">· ${esc(c.age)}</span></div>` +
      `<div class="f12 comment-body">${markdown(c.body)}</div></div></div>`;
  }

  /** OutlinedIconButton: a 30×24 outlined icon button; the bar is right-aligned, 8 apart, 12/8 padding. */
  function bottomBar(symbols) {
    return `<div class="detail-bar"><span class="spacer"></span>` +
      symbols.map((s) => `<span class="outlined-button c-secondary">${sym(s, 12, "medium")}</span>`).join("") + `</div>`;
  }

  // Palette.ciGlyph at the detail's 12 pt
  const CI12 = {
    success: ["checkmark.circle", "var(--secondary)"], failure: ["xmark.circle.fill", "var(--red)"],
    pending: ["clock", "var(--secondary)"], skipped: ["minus.circle", "var(--secondary)"],
  };
  const CHECK_LABEL = { success: "passed", failure: "failed", pending: "running", skipped: "skipped", none: "no result" };

  // ---------- PR detail ----------

  function checksSection(pr) {
    const checks = pr.checks;
    const parts = [["failure", "failed"], ["pending", "running"], ["success", "passed"], ["skipped", "skipped"]]
      .map(([s, w]) => [checks.filter((c) => c.state === s).length, w]).filter(([n]) => n > 0).map(([n, w]) => `${n} ${w}`);
    // On an open PR a green run folds to "No checks failed" until clicked (checksExpanded).
    const folded = pr.state === "open" && !pr.checksExpanded && checks.length &&
      checks.every((c) => ["success", "skipped", "none"].includes(c.state));
    let rows;
    if (folded) {
      const g = CI12[checks.some((c) => c.state === "success") ? "success" : "skipped"];
      rows = [`<div class="card-line f12"><span class="icon14">${sym(g[0], 12, "regular", { color: g[1] })}</span><span class="spacer">No checks failed</span><span class="c-tertiary">${sym("chevron.down", 9, "semibold")}</span></div>`];
    } else {
      const order = ["failure", "pending", "success", "skipped", "none"];
      rows = order.flatMap((s) => checks.filter((c) => c.state === s)).map((c) => {
        const g = CI12[c.state];
        return `<div class="card-line f12"><span class="icon14">${sym(g[0], 12, "regular", { color: g[1] })}</span><span class="spacer ellipsis">${esc(c.name)}</span>` +
          `<span class="f11 c-secondary">${CHECK_LABEL[c.state]}</span>${c.url ? `<span class="c-tertiary">${sym("arrow.up.right", 9, "semibold")}</span>` : ""}</div>`;
      });
    }
    return section("Checks", parts.join(" · "), card(rows));
  }

  // ReviewerLine.look
  function reviewerPill(status) {
    switch (status) {
      case "approved": return pill("Approved", { symbol: "checkmark", fg: "var(--secondary)", fill: "var(--fill)", symbolColor: "var(--approved)" });
      case "requested": return pill("Requested", { symbol: "clock", fg: "var(--secondary)", fill: "var(--fill)" });
      case "changesRequested": return pill("Changes requested", { symbol: "arrow.uturn.backward", fg: "var(--changes-requested)", fill: "var(--changes-fill)" });
      default: return pill("Commented", { symbol: "bubble.left", fg: "var(--secondary)", fill: "var(--fill)" });
    }
  }

  function reviewersSection(pr, viewer) {
    const rows = pr.reviewers.map((r) => {
      const lead = r.team
        ? `<span class="team-badge c-secondary">${sym("person.2.fill", 9)}</span>`
        : avatar(r.login, 20);
      const name = `<span class="hstack spacer" style="gap:4px"><span>${esc(r.login)}</span>${r.login === viewer && !r.team ? '<span class="c-secondary">(you)</span>' : ""}${r.team ? '<span class="c-secondary">team</span>' : ""}</span>`;
      return `<div class="card-line reviewer f12">${lead}${name}${reviewerPill(r.status)}</div>`;
    });
    return section("Reviewers", null, card(rows));
  }

  function diffstatBar(blocks) {
    let html = "";
    for (let i = 0; i < 5; i++) {
      const color = i < blocks.additions ? "var(--approved)" : i < blocks.additions + blocks.deletions ? "var(--closed-text)" : "var(--strong-fill)";
      html += `<span class="diff-block" style="background:${color}"></span>`;
    }
    return `<span class="diffstat">${html}</span>`;
  }

  function filesSection(pr) {
    const f = pr.files;
    const count = f.total === 1 ? "1 file" : `${f.total} files`;
    const visible = f.list.slice(0, 5);
    const rows = visible.map((file) => {
      const slash = file.path.lastIndexOf("/");
      const name = file.path.slice(slash + 1), dir = slash > 0 ? file.path.slice(0, slash) : "";
      return `<div class="card-line"><span class="hstack spacer" style="gap:6px;align-items:baseline"><span class="f12 nowrap">${esc(name)}</span>` +
        `${dir ? `<span class="f11 c-secondary ellipsis">${esc(dir)}</span>` : ""}</span>` +
        `<span class="f11 c-secondary diff-count">+${file.additions} −${file.deletions}</span></div>`;
    });
    if (f.list.length > 5) rows.push(`<div class="card-line f11 w-medium"><span class="link">Show ${f.list.length - 5} more</span></div>`);
    return section("Files changed", `+${f.additions} −${f.deletions} · ${count}`, card(rows), diffstatBar(f.blocks));
  }

  function conversationSection(comments, total, earlier) {
    let html = "";
    if (earlier) html += `<div class="f11 c-secondary mono" style="padding-left:28px">${earlier === 1 ? "1 earlier comment" : `${earlier} earlier comments`} · <span class="link">view on GitHub</span></div>`;
    html += comments.length ? comments.map(commentLine).join("") : `<div class="f12 c-secondary">No comments</div>`;
    return section("Conversation", total === 1 ? "1 comment" : `${total} comments`, `<div class="vstack" style="gap:10px">${html}</div>`);
  }

  /** StatePill for an open PR: Draft, Ready to merge (on strongFill) or Open. */
  function prStatePill(pr) {
    if (pr.state === "merged") return pill("Merged", { symbol: "pullbull.pullrequest.merged", fg: "var(--merged-text)", fill: "var(--merged-fill)" });
    if (pr.readyToMerge) return pill("Ready to merge", { symbol: "arrow.triangle.merge", fg: "var(--secondary-text)", fill: "var(--strong-fill)" });
    return pill("Open", { symbol: "pullbull.pullrequest", fg: "var(--secondary-text)", fill: "var(--strong-fill)" });
  }

  function summaryBlock(title, pillHtml, author, opened, extra = "") {
    return `<div class="detail-summary"><div class="detail-heading">${esc(title)}</div>` +
      `<div class="hstack" style="gap:8px;margin-top:8px">${pillHtml}<span class="hstack f12 c-secondary" style="gap:6px">${avatar(author, 20)}<span class="nowrap">${esc(author)} opened ${esc(opened)}</span></span></div>${extra}</div>`;
  }

  function prDetail(d) {
    const pr = d.pr;
    const branches = `<div class="hstack" style="gap:6px;margin-top:10px"><span class="c-tertiary hstack">${sym("arrow.triangle.branch", 11)}</span>` +
      `<span class="branch-chip">${esc(pr.headRef)}</span><span class="c-tertiary hstack">${sym("arrow.right", 10, "semibold")}</span><span class="branch-chip">${esc(pr.baseRef)}</span></div>`;
    // Open PRs lead with status (checks, reviewers), then the description (PRDetailView.sections).
    const description = section("Description", null, `<div class="description">${markdown(pr.body)}</div>`);
    const body = summaryBlock(pr.title, prStatePill(pr), pr.author, pr.opened, branches) +
      checksSection(pr) + reviewersSection(pr, d.viewer.login) + description +
      conversationSection(pr.comments, pr.commentTotal ?? pr.comments.length) + filesSection(pr);
    return `<div class="detail">${detailHeader(`${pr.repo} #${pr.number}`)}<div class="detail-scroll"><div class="detail-content">${body}</div></div>` +
      bottomBar(["doc.on.doc", "arrow.up.right.square"]) + `</div>`;
  }

  // ---------- Issue detail ----------

  function cardRow(name, value) {
    return `<div class="card-row f12"><span class="f11 c-secondary card-row-name">${esc(name)}</span><span class="card-row-value">${value}</span></div>`;
  }

  function linkedPRLine(pr) {
    const glyph = { open: ["pullbull.pullrequest", "var(--secondary)"], merged: ["pullbull.pullrequest.merged", "var(--merged-text)"] }[pr.state];
    const ci = pr.ci && pr.ci !== "none" ? sym(CI12[pr.ci][0], 12, "regular", { color: CI12[pr.ci][1] }) : "";
    return `<div class="card-line linked f12"><span class="icon14">${sym(glyph[0], 12, "regular", { color: glyph[1] })}</span>` +
      `<span class="vstack spacer" style="gap:1px;min-width:0"><span class="ellipsis">${esc(pr.title)}</span><span class="f11 c-secondary mono">#${pr.number} · ${esc(pr.author)} · ${pr.state}</span></span>` +
      `${ci}<span class="c-tertiary">${sym("chevron.right", 9, "semibold")}</span></div>`;
  }

  function issueDetail(d, scheme) {
    const is = d.issue;
    const statusRow = cardRow("Status", `<span class="hstack" style="gap:6px"><span class="c-secondary hstack">${sym(is.status.toLowerCase().includes("progress") || is.status.toLowerCase().includes("review") ? "circle.lefthalf.filled" : "circle.dashed", 11)}</span><span>${esc(is.status)}</span></span>`);
    const assignees = cardRow("Assignees", `<span class="flow" style="gap:6px 10px">${is.assignees.map((a) =>
      `<span class="hstack" style="gap:5px">${avatar(a, 20)}<span>${esc(a)}</span>${a === d.viewer.login ? '<span class="c-secondary">(you)</span>' : ""}</span>`).join("")}</span>`);
    const labels = cardRow("Labels", `<span class="flow" style="gap:4px">${is.labels.map((l) => P.labelChip(l.name, l.color, scheme)).join("")}</span>`);
    const board = section(d.boardTitle, null, card([statusRow, assignees, labels]));
    const linked = section("Linked pull requests", String(is.linked.length), card(is.linked.map(linkedPRLine)));
    const description = section("Description", null, card([`<div class="issue-description">${markdown(is.body)}</div>`]));
    const conversation = conversationSection(is.lastComments, is.commentTotal, is.commentTotal - is.lastComments.length);
    const pillHtml = pill("Open", { symbol: "pullbull.issue", fg: "var(--secondary-text)", fill: "var(--strong-fill)" });
    const body = summaryBlock(is.title, pillHtml, is.author, is.opened) + board + linked + description + conversation;
    return `<div class="detail">${detailHeader(`${is.repo} #${is.number}`)}<div class="detail-scroll"><div class="detail-content">${body}</div></div>` +
      bottomBar(["rectangle.split.3x1", "arrow.up.right.square"]) + `</div>`;
  }

  Object.assign(P, { markdown, detailHeader, section, card, pill, commentLine, bottomBar, prDetail, issueDetail, diffstatBar });
})();
