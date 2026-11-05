// PullBull Stats as HTML pieces: StatsView (header, period chips, footer), StatsCards and StatsBarChart.
// Sizes in points; see popover.css.
(function () {
  "use strict";
  const P = window.PullBull;
  const { sym, avatar, esc } = P;

  /** StatColumn: label, the figure with its units small, and the comparison. Numbers and units alternate in `parts`. */
  function column(c) {
    const figure = c.parts.map((part, i) => i % 2 ? `<span class="stat-unit">${esc(part)}</span>` : `<span class="stat-figure-part">${esc(part)}</span>`).join("");
    return `<div class="stat-column"><div class="f11 c-secondary nowrap">${esc(c.label)}</div>` +
      `<div class="stat-figure">${figure}</div><div class="f11 c-secondary mono nowrap">${esc(c.comparison)}</div></div>`;
  }

  const columns = (list) => `<div class="stat-columns">${list.map(column).join("")}</div>`;
  const cardBox = (html) => `<div class="stat-card-box"><div class="detail-card stat-card">${html}</div></div>`;

  /** ReviewBars.marks: bars and their gaps (6 pt at 7 days) fill the width; a day with none is a 1-pt stub. */
  function marks(chart, width) {
    const gap = 6, n = chart.days.length;
    const barWidth = (width - gap * (n - 1)) / n;
    const busiest = Math.max(...chart.days.map((d) => d.count));
    return chart.days.map((day, index) => ({
      ...day, index, x: index * (barWidth + gap), width: barWidth,
      height: day.count === 0 ? 1 : Math.max(36 * day.count / busiest, 2),
    }));
  }

  /** StatsBarChart: the caption, then bars under the hovered day's label, then the initials. `chart.hover` is a day's index. */
  function barChart(chart) {
    const width = 312, baseline = 48, today = chart.days.length - 1;
    const bars = marks(chart, width);
    const fill = (m) => m.index === chart.hover ? "var(--label)" : m.index === today ? "var(--accent)" : m.count === 0 ? "var(--tertiary)" : "var(--secondary)";
    const drawn = bars.map((m) => `<span class="stat-bar" data-day="${m.index}" style="left:${m.x}px;top:${baseline - m.height}px;width:${m.width}px;height:${m.height}px;background:${fill(m)}"></span>`);
    const axis = bars.map((m) => `<span class="stat-axis" style="left:${m.x}px;width:${m.width}px;top:${baseline + 3}px;${m.index === today ? "color:var(--accent)" : ""}">${esc(m.initial)}</span>`);
    const shown = bars[chart.hover];
    const label = `<span class="stat-bar-label" style="left:${shown.x + shown.width / 2}px">${shown.count} · ${esc(shown.date)}</span>`;
    return `<div class="stat-caption">Per day</div><div class="stat-plot">${drawn.join("")}${axis.join("")}${label}</div>`;
  }

  /** TopReviewersRow */
  function topReviewers(people) {
    const person = (p) => `<span class="hstack" style="gap:5px;flex:none">${avatar(p.login, 18)}<span class="nowrap">${esc(p.login)}</span><span class="c-secondary mono">${p.count}</span></span>`;
    return `<div class="hstack f12 stat-reviewers"><span class="f11 c-secondary nowrap">Top reviewers</span><span class="spacer"></span>${people.map(person).join("")}</div>`;
  }

  /** RightNowSlot: a caption over the row as the list draws it. */
  function rightNow(slot) {
    return `<div class="f11 stat-right-now c-secondary">${esc(slot.caption)}</div>${P.prRow(slot.row, slot.tab, { showsRepo: true })}`;
  }

  function periodChips(s) {
    const chips = s.periods.map((title) => ({ id: title, title }));
    return `<div class="hstack stat-periods">${P.scopeChips(chips, s.period, false)}<span class="f11 c-secondary" style="letter-spacing:1px;flex:none">← →</span></div>`;
  }

  /** StatsView: pushed over the list like a detail, with its own header and footer. */
  function stats(d) {
    const s = d.stats;
    const button = (name) => `<span class="detail-icon c-secondary">${sym(name, 13, name === "chevron.left" ? "medium" : "regular")}</span>`;
    return `<div class="detail"><div class="detail-header">${button("chevron.left")}<span class="spacer"></span>${button("arrow.clockwise")}` +
      `<span class="detail-title f13 w-semibold">Stats</span></div><div class="hairline"></div>${periodChips(s)}` +
      `<div class="detail-scroll"><div class="stat-cards">` +
      P.sectionHeader({ title: "Your reviews", glyph: "bell", trailing: s.span }) +
      cardBox(columns(s.reviews) + barChart(s.chart)) +
      P.sectionHeader({ title: "Your pull requests", glyph: "pullbull.pullrequest" }) +
      cardBox(columns(s.pullRequests) + topReviewers(s.topReviewers)) +
      P.sectionHeader({ title: "Right now", glyph: "clock" }) +
      s.rightNow.map(rightNow).join("") +
      `</div></div><div class="hstack footer f11"><span class="ellipsis">${esc(s.footer)}</span></div></div>`;
  }

  /** The pointer on the hovered bar: no tooltip, the chart's own label names the day. */
  function placeBarCursor(root, day) {
    const bar = root.querySelector(`.stat-bar[data-day="${day}"]`);
    const base = root.getBoundingClientRect(), r = bar.getBoundingClientRect();
    const x = r.left - base.left + r.width / 2, y = r.top - base.top + r.height / 2;
    root.insertAdjacentHTML("beforeend", `<img class="cursor" src="symbols/cursor-arrow.png" style="left:${x - 5}px;top:${y - 5}px" alt="">`);
  }

  Object.assign(P, { stats, placeBarCursor });
})();
