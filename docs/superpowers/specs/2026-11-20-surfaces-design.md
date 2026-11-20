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
| Accent text | `Palette.accentText`: the accent blended 0.40 toward black | the accent | Every accent-coloured text and small glyph on glass or a selection fill (scope counts, filter bar, sort controls, Stats bars and labels, the empty list, reaction counts) |
| Warning strip | `amberFill` drawn on top of its surface, never under a material | same | Footer warning, failure line |
| Sliding detail edge | shadow at the raised layer's opacity | same | The detail's leading-edge shadow |

- `Solid background` reaches the modifiers through a `\.solidBackground` environment value set at the popover's root.
- The accent follows the user's system accent colour; `accentText` and `selection` derive from it, so they change with it.
- Accent fills (buttons, toggles, the caret, the focus halo, progress fills) keep the plain accent; only text and small glyphs use `accentText`.
- The comment field focuses with the same halo as the search field, replacing its 1pt accent ring.
- An edge-attached raised panel draws no edge on its attached side, and exactly one rule on its free side (its existing `Hairline`), so it never doubles the chrome's hairline.
- Reduce Transparency: system materials go opaque on their own; the lift, edge and shadow still separate raised layers.

## Docs

`docs/media/src/popover.css` mirrors the new light values (hints lift and shadow, selection, accent text), and the light stills are re-rendered.

## Approaches considered

- **Shared rules in Palette and two modifiers (chosen).** One pass, and the next view picks up the right look by using the token.
- **Per-view fixes.** Fewer files touched now, but the drift that caused this comes back.
