# DSR iteration 1: the Songs page on thor v0.1's raw API

9 November 2026. thor `v0.1` (commit `b453a93`), Odin `dev-2026-10`. The code is in
`apps/thor/`: `songs_page.odin` is the page, and `main.odin` loads the data and holds empty
boxes for the sidebar and the player bar. Phase 4 rebuilds the same page on the P0 API, and
iteration 2 compares the two.

## Result

- `odin build .` builds it with no flags. It compiled and drew the page on the first build.
- The page draws as the spec says: the heading, the search field, the column headers, the
  `4fr 3fr 3fr 56` columns, truncation, and the Japanese titles through font fallback.
- Not checked yet in a live window: typing in the search field, the click that selects a row,
  hover, and trackpad scrolling. The capture runs the page with no input.

## Lines of code

Lines that are not blank and not comments, as tokei counts code. tokei is not installed yet,
so these come from `grep`.

| File | Code | Total |
| --- | --- | --- |
| `songs_page.odin` | 158 | 194 |
| `main.odin` | 54 | 70 |

For scale: the plan's sketch of the same page on the proposed API is about 20 lines.

## Pain points

Each one names the backlog item in `thor/plan.html` that should remove it.

| # | Pain point | Lines it cost | Backlog |
| --- | --- | --- | --- |
| 1 | No docs. Every name came from reading thor's source: the `Style` fields, `Signal`'s fields, which kit procedures exist and what they take. | – | 7 |
| 2 | A search field takes four calls in three places: `kit.register_text_field` once at start, `kit.apply_text_events(platform.list_events())` before the page, `kit.build_text_field` in it, and `kit.finish_text_fields()` after. Miss one and typing never arrives. `app.run` calls none of them. | 4, plus an import of `platform` | 1, 3 |
| 3 | No virtual list. The page works out the first and last rows from the list's scroll and height, and adds a spacer above and below. | 9 | 4 |
| 4 | The list's height is the last frame's. On the first frame it is 0, and nothing in the API says whether thor runs another frame, so the page calls `platform.request_frame()` to be safe. The empty state reads the same height to centre its text. | 2 | 3, 4 |
| 5 | The zero value of `Style` is a box 0 by 0. Every box needs a width and a height: `fit_text` on every text, `fill` on every spacer. The page's `cell` procedure exists to fill in those defaults. | 22 | 5 |
| 6 | Containers take two statements each: `x := ui.box(...)`, then `if ui.scope(x)`. The page has 7. | 7 | 2 |
| 7 | `kit.text_box` takes no alignment, so the right-aligned time needed a text procedure of its own. | (in 5) | 3 |
| 8 | `kit.build_text_field` fills its parent, so a 240-point field needs a wrapper box. Its corner radius (8) and inset (9) are fixed, against the spec's 6 and 10. Changing two numbers means copying a 320-line file, so the page keeps kit's. Its `symbol` parameter has no default and needs `""`. | 2 | 3 |
| 9 | A border draws on every side. The column headers' bottom border is a 1-point box of its own, and the header row is 27 high to keep 28. | 2 | 5 |
| 10 | A selected row that still shows hover needs the rule written by hand: `background` and `hover_background` both become the selected colour when the row is selected. | 2 | 3 (a list row) |
| 11 | The window always has the live blur behind it. The spec wants an opaque window, so the root box paints over the blur, and the window server may still compute it. The plan's extraction step 3 asked for the blur as a window option, and v0.1 does not have one. | 1 | 1 |

## What worked

- Loading the data: `#load` and `json.unmarshal_string` in two lines, with the structs as the
  only schema.
- Selection is one string compared each frame. There is no state to keep in sync.
- Searching filters only when `field.is_changed` says the text changed.
- thor's packages import each other by relative path, so a `thor` folder beside the app is all
  the setup there is.

## For iteration 2

Remove pain points 2 to 11 with P0 items 1 to 5 and the Tier 1 components, then rebuild this
page and compare its lines and its pain list with this one. Pain point 11 also matters for
Tahap A: the window's background must be equal across the four apps before anything is
measured.
