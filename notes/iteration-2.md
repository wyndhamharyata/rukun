# DSR iteration 2: the whole test app on thor's P0 API

9 November 2026. thor at commit `c539b59` (after `v0.1`), Odin `dev-2026-10`, test app spec
version 2. The code is in `apps/thor/`: `main.odin` (the data, the page switch and the shared
pieces), `sidebar.odin`, `tasks_page.odin`, `space_page.odin` and `note_page.odin`. Iteration 1
is at the tag `iteration-1`.

## What changed in thor between the iterations

Each change came from a pain point of iteration 1, or from building this iteration.

| Iteration 1 pain point | What thor does now |
| --- | --- |
| 2. A text field takes four calls in three places | `app` passes the events to the fields and places the caret. A field registers itself. `kit.text_field` returns true when its text changed. |
| 3. No virtual list | `kit.list` builds only the rows on screen, rows of one height or measured ones. |
| 4. The list's first frame has no height | `kit.list` asks for the frame itself. |
| 5. A zero `Style` is a box 0 by 0 | A zero size fits the text or the children. Text with no colour takes the theme's. |
| 6. Containers take two statements each | `ui.row`, `ui.col` and `ui.scroll` close themselves at the end of their `if`. |
| 7. `kit.text_box` takes no alignment | `kit.text` takes `align`. |
| 8. The text field fills its parent and fixes its look | Every component takes a `style`, and only the fields it sets change the component's own. |
| 10. Selection and hover written by hand | `kit.list_row` writes the selected id through a pointer and shows it. |
| 11. The window always blurs | The window is opaque unless `Config.is_blurred`. |
| 12. No image component | `kit.image` crops an image to fill its box, with rounded corners. |
| 13. No path for the app's files | `app.resource_path`, and `bundle.sh` copies `resources/` into the `.app`. |
| 14. The image fade cannot be turned off | `kit.image(..., is_fading = false)`. |
| 15. No checkbox, and no centring on the main axis | `kit.checkbox`, and `Style.justify`. |
| Found here: no line height | `Style.line_height`, so text takes the spec's line boxes. |

Pain points 1 (no docs) and 9 (a border on every side) remain.

## Result

- `odin build .` builds it with no flags. All three pages and the sidebar compiled on the first
  build.
- The captures match the spec: the Tasks page, `#keluarga` opening at its end with a colour
  emoji, `#liburan` with list and note cards, `#kebun` with a photo, and a note page with its
  checklist, tasks, links and "Mentioned in". Body text has 18-point lines, so a one-line
  message is 56 points from the next, as the spec works out.
- `THOR_STARTUP_MARK=1` prints `first-frame` on the Tasks page and on `#keluarga`.
- Not checked yet in a live window: typing in the search, ticking a task, selecting a row,
  hover, trackpad scrolling, the sidebar, opening a note and a space from links, sending a
  message and adding a task. Tests cover what sending and adding do to the data. The bench
  over the timeline has not run, as it takes the screen.

## Lines of code

Lines that are not blank and not comments, counted with `grep` as in iteration 1.

| | Iteration 1 | Iteration 2 |
| --- | --- | --- |
| The Tasks page, with the helpers it uses | 256 | 127 |
| Boxes the page builds by hand (`ui.box`) | 16 | 1 |
| `ui.scope` calls | 9 | 0 |

The whole app was 446 lines: `main.odin` 139, `sidebar.odin` 22, `tasks_page.odin` 93,
`space_page.odin` 126, `note_page.odin` 66. Spec version 3 then added writing: a composer that
sends a message in a space, and a New task field whose `#name` picks the task's space. With
them the app is 544 lines (`main.odin` 159, `tasks_page.odin` 146, `space_page.odin` 151), and
`rukun_test.odin` tests the two with `odin test .` in 50 more. The 127 above counts the Tasks
page before the New task field, so it compares with iteration 1 feature for feature. odinfmt puts each field of a style on its own line
once the style is too long for one, which adds a line per field.

For scale: the plan's sketch of a page like this is about 20 lines. The difference is the
columns, the avatar, the empty state and the spec's exact sizes.

## Pain points

| # | Pain point | Backlog |
| --- | --- | --- |
| 1 | Still no docs. Every name came from thor's source. | 7 |
| 2 | A card that opens something on a click, such as a note card, takes a raw `ui.box`, `ui.signal` and `ui.scope`: kit has no clickable container that is not a selection. | 3 |
| 3 | `kit.list(id, count, 0, ...)`: a row height of 0 to ask for measured rows reads as a mistake. | 3 |
| 4 | The spec puts different gaps between siblings (16 then 24 then 8), so the app writes its own `gap` procedure. kit's `spacer` fills instead. | 3 |
| 5 | The column headers' bottom border is still a 1-point box, and the header row 27 high to keep 28. | 5 |
| 6 | The note page lists links and mentions that can hold the same note, so their ids need prefixes. Nothing warns of two boxes with one id. | 10 |
| 7 | Each text that wraps or sets a height needs `line_height` written on it. A theme with a type scale would set it once. | 13 |
| 8 | The bench needs the list's box: `dev.bench_scroll(ui.find_box("list", page))`, with `page` taken from `ui.current_parent()` first. | 6 |

### Fixed after this iteration (thor `cc87504`, 10 November 2026)

- 2: `kit.clickable(id, style)` returns `(is_clicked, ok)` and holds its children, so the note
  card is one `if`.
- 3: `kit.MEASURED` names the row height of a list whose rows differ.
- 6: a second box with an id its parent already built gets a box of its own, which keeps the
  layout whole, and thor prints once which id repeats. Before, it took the first box and cut the
  tree.
- The "Window move completed without beginning" line: AppKit prints it on the move-end event
  (subtype 21) under thor's own event loop, even after the move's begin. GPUI, Tauri and Electron
  do not print it. thor now keeps that event from AppKit (`thor` after `cc87504`). Checked with
  real drags: the window moves, the line is gone, and clicks still work after a drag.

## What worked

- The measured `kit.list` showed a 4,000-item timeline at its end on the first try.
- No page asks for a frame itself. A click already runs frames while its press fades out.
- Ticking a task changes `task.done` in place, so the Tasks page, the timeline's task cards
  and the note page show the same state with no code to keep them in step.

## Changed by this iteration

- thor: `kit.list` merges its style onto a default that fits where it sits (`eec0bf9`),
  `Style.line_height` (`c539b59`), and `kit.list` shows its end when a scroll is set past it, as
  sending a message does (`cc25f22`).
- A guess that turned out wrong: a click that opens another page seemed to need a frame of its
  own. A test showed the press fade already runs those frames, so the change was not made.
