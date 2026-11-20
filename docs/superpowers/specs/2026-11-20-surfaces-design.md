# One set of surface rules

The popover draws its layers, fields, cards, selection and accent text with values chosen view by view. In light mode the search hints panel doesn't read as raised over the list, accent text on grey glass is hard to read, and floating layers look different from each other. This replaces those choices with one set of rules, carried by `Palette` tokens and two shared modifiers.

Owner-approved on 2026-11-20 from a UI audit, including the darker accent text in light mode.

## Goals

- Every layer that floats over content reads as above it, the same way, in light and dark, with Solid background on and off.
- Fields, cards and selection each look the same wherever they appear.
- Accent-coloured text and small glyphs are readable on light glass.
- Increased Contrast strengthens floating layers and selection.

## Non-goals

- New layouts, sizes, spacing, typography or icons.
- Dark-mode accent text: it stays the system accent.
- A theme switch.

## Anti-goals

- The chrome (header, filter bar, footer) stops reading as one sheet of glass with the list.
- A floating layer that hides less of what's below than today, or a shadow that falls on top of the layer above it.
- Text that was readable becomes less readable in any appearance or setting.

## Rules

| Role | Light | Dark | Used by |
|---|---|---|---|
| Base glass | `.popover` material behind the window; with Solid background, `windowBackground` over the opaque fill | same | The panel (unchanged). SearchHints' private `PopoverMaterial` moves to Style as the shared `GlassBackground(solid:)` |
| Chrome on base | Base glass, no lift, `Hairline` between parts | same | Header, filter bar, footer (unchanged) |
| Sticky header | `GlassBackground`, no lift, in place of `.thinMaterial` | same | `pinnedHeaderBackground()`. If the AppKit view misbehaves in the lazy list's pinned headers (flicker, wrong blur, a gap while scrolling), keep `.thinMaterial` there and record it here |
| Raised layer | `GlassBackground` + `Palette.lift` white 0.30, 0.5pt `Palette.separator` edge, shadow black 0.18 (radius 8, y 2; a panel attached to an edge gets an 8pt gradient on its free side instead) | lift white 0.06, shadow black 0.40 | `.raisedSurface(radius:attachedEdge:)`: search hints, completion list, @ mention list, Status, set and reaction pickers, the edit failure line. Only the topmost raised layer casts a shadow |
| Raised, Increased Contrast | edge 1pt primary 0.5, shadow opacity ×1.3 | same | Inside the modifier |
| Field | `Palette.field` (white 0.5), 0.5pt separator edge; focus is a 3.5pt halo of accent 0.35 | `Palette.field` (white 0.07) | Search field, comment field, picker filter fields |
| Chip / neutral fill | `Palette.fill` primary 0.06; hover or neutral selection `strongFill` 0.10 | same | Unchanged |
| Card | `Palette.card` primary 0.04 + 0.5pt separator edge | same | DetailCard, the detail skeleton, Ask, IssueListView's card, CopyableCommand, GhSetupView |
| Selection | `Palette.selection`: the accent blended 0.70 toward white, alpha 0.75; Increased Contrast adds a 1pt accent edge | accent at 0.25 | RowFill, completion, mention and picker rows, hint chips, ModeToggle, your reaction chips |
| Accent text | `Palette.accentText`: the accent blended 0.40 toward black | the accent | Every accent-coloured text and small glyph on glass (scope counts, filter bar, sort controls, Stats bars and labels, the empty list) |
| Accent text on selection | `Palette.accentTextOnSelection`: same as `accentText` | the accent blended 0.25 toward white, since the plain accent on the 0.25 selection fill drops near 3:1 | Accent text and glyphs that sit on a selection fill: your reaction counts, ModeToggle's chosen glyph |
| Warning strip | `amberFill` drawn on top of its surface, never under a material | same | Footer warning, failure line |
| Sliding detail edge | shadow at the raised layer's opacity | same | The detail's leading-edge shadow |

- `Solid background` reaches the modifiers through a `\.solidBackground` environment value set at the popover's root.
- The accent follows the user's system accent colour; `accentText` and `selection` derive from it, so they change with it.
- Accent fills (buttons, toggles, the caret, the focus halo, progress fills) keep the plain accent; only text and small glyphs use `accentText`.
- The comment field focuses with the same halo as the search field, replacing its 1pt accent ring.
- An edge-attached raised panel draws no edge on its attached side, and exactly one rule on its free side (its existing `Hairline`), so it never doubles the chrome's hairline.
- Reduce Transparency: system materials go opaque on their own; the lift, edge and shadow still separate raised layers.

## How it is built

The rules live in `PullBull/Style/Palette.swift` (tokens) and `PullBull/Style/Surface.swift` (`GlassBackground`, `\.solidBackground`, `.raisedSurface`, `.fieldSurface`, `.cardSurface`, `.selectionFill`).

- **Accent-derived tokens.** `selection`, `accentText` and `accentTextOnSelection` are `AccentStyle`, a `ShapeStyle` whose `resolve(in:)` starts from `Color.accentColor.resolve(in:)` and the environment's `colorScheme`, then blends per sRGB component as `NSColor.blended(withFraction:of:)` does. Resolving through the environment lets SwiftUI track the dependency, so the colours follow a change of system accent while the popover is open; a `Color(nsColor:)` would only re-resolve on a scheme or contrast change. Where a `Color` is required (the empty list's attributed action phrase) the view reads `\.self` from the environment and resolves the style there; Stats' canvas shades with `.style(...)`.
- **The raised shadow is drawn only outside the layer.** The glass is an AppKit view, and SwiftUI's `.shadow` on a view holding one would shadow only the SwiftUI parts (the faint lift, the text), all but vanishing in dark mode. So the free-floating shadow is a black copy of the layer's shape with `.shadow`, masked to everything outside the shape: the glass never darkens, and only the area around the layer does.
- **Increased Contrast shadow** is its own token, `raisedShadowIncreased` (black 0.234 light, 0.52 dark): `Color.opacity` can't multiply past 1.
- **Edge-attached panels.** The search hints panel is attached at its top (under the header), so its gradient falls below its bottom `Hairline`. The edit failure line is attached at its bottom (on the footer or the detail's bottom row), so its gradient rises above its top `Hairline`. Neither draws an edge stroke of its own.
- **Only the topmost layer casts a shadow.** The hints panel stops casting while the completion list covers it. The failure line stops casting while an edit picker is open, since the picker draws over it. The reaction picker sits inside the detail layer, below the failure line, so the line stays the top layer and keeps its shadow then. The completion and @ mention lists, the pickers and the reaction picker always cast one.
- **The failure line's amber** is drawn between its content and the glass, so the glass never washes it out.
- **The sliding detail's edge** is a 10pt gradient from clear to `raisedShadow`.
- **Fields.** The picker filter fields hold the focus while their picker is open, so their halo shows the whole time the picker does. The comment field's edge is the field rule's 0.5pt, down from 1pt.
- **Cards.** `DetailSkeleton` keeps drawing its card only in the chrome layer, filled with `Palette.card`. CopyableCommand, IssueListView's command box and GhSetupView's command box move from `Palette.fill` (0.06) to `Palette.card` (0.04). Ask's answer gains the card's separator edge.
- **Selection.** Rows draw their hover tint underneath and `selectionFill` on top of it while selected, so selected wins over hover as before. ModeToggle's own Increased Contrast edge is now `selectionFill`'s. The hint chips keep their own 1pt accent edge, drawn whenever a chip is selected for the keyboard, and fill with `Palette.selection` directly, so Increased Contrast never adds a second edge. Your reaction chips and given reactions in the picker keep their 0.5pt accent outline over `selectionFill`.
- **Accent text and glyphs** use `accentText`: the scope count, the filter bar's clock and repo-focus glyphs, the sort control, today's Stats bar and labels, the empty list's action phrase, the Needs your review bell, the saved-search bookmark, and the detail's Re-run failed jobs, Open Failing Check and Convert to draft. Your reaction counts and ModeToggle's chosen glyph sit on a selection fill and use `accentTextOnSelection`. Accent fills keep the plain accent: the account split button, ModeToggle's news dot, Merge, `AccentTextButton`, the focus halo and selection edges. Buttons in `.buttonStyle(.link)` without a tint (Open on GitHub on the failure line, the failure banner's action, Show for the hidden approved PRs) take the system link colour, not the accent, and are unchanged.
- **Sticky headers** use `GlassBackground` with no lift, through a small view that reads `\.solidBackground`. Rows scrolling under a pinned header are hidden by the glass, not blurred.
- **Solid background** is set on the popover's root outside its two overlays, so the failure line and the edit pickers read it too.

## Docs

`docs/media/src/popover.css` mirrors the new light values: the hints panel gets the white 0.30 lift and a 0.18 shadow, `.row.selected` and the selected hint chip use the new selection, and a light-only `--accent-text` (#004999, the mock's #007aff blended 0.40 toward black) colours `.c-accent`, the hot scope count, the chosen mode glyph, `.link`, the Needs your review bell and today's Stats bar and label. `--accent` stays for fills (the caret, the halo). The light stills are re-rendered; the dark stills are unchanged, so they still show the earlier dark selection (accent 0.15, where the app draws 0.25).

## Approaches considered

- **Shared rules in Palette and two modifiers (chosen).** One pass, and the next view picks up the right look by using the token.
- **Per-view fixes.** Fewer files touched now, but the drift that caused this comes back.
