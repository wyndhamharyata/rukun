# DSR iteration 3: thor's reviewed API, its look and feel, and VoiceOver

12 November 2026. thor from `cc87504` (10 November) to `247161b`, Odin `dev-2026-10`, test app
spec version 3. The app is in `apps/thor/`, with a copy of thor in `apps/thor/thor`. Iteration 2
ended at commit `934b553`.

Iteration 2 built the whole app. This iteration kept the app's features and changed thor under
it. The app followed each change in the same commit as thor's copy, with no shims.

## How thor changed

First the backlog from the plan, then three rounds of design. Each round started as a page in
thor's repository with live figures and questions. The owner commented on the page and answered
the questions, and only then did the build start.

| Work | Where | What it decided or added |
| --- | --- | --- |
| Backlog 9 to 20 and 26 to 28 | `plan.html` | The inspector, `watch.sh`, layout warnings, headless tests, zoom, forced states for every component, Tab focus, a menu bar, popovers on an overlay layer, macOS's appearance and accent, tokens on daisyUI's names, several windows, and the Tier 2 and Tier 3 components. A gallery app shows every component. |
| API review | `api.html`, `refactor.html`, `fat-struct.html` | Every component takes its id first and returns a `ui.Signal` that refers to its box. One procedure per element a person sees, such as `checkbox`, `toggle` and `toggle_chip`. 14 review comments were decided. |
| Look and feel | `feel.html` | Motion, contrast and transparency follow System Settings. Springs and fades, text that stays readable against the color under it, Liquid Glass, and Display P3. VoiceOver reads every element. 9 of 10 questions were decided; linear blending waits, behind a switch that is off. |
| VoiceOver actions | `voiceover.html` | VoiceOver presses, steps, opens menus, moves focus and pages through long lists. An icon-only button takes a tooltip, which VoiceOver also reads. All 5 questions were decided. |

| | Iteration 2 (`cc87504`) | Iteration 3 (`247161b`) |
| --- | --- | --- |
| thor's code, lines | 4,333 | 10,084 |
| kit's public procedures | 42 | 64 |
| thor's tests | 22 | 96 |
| thor's commits in between | | 61 |

Lines that are not blank and not comments, counted with `grep` as before.

## Iteration 2's open pain points

| # | Pain point | Now |
| --- | --- | --- |
| 1 | Still no docs. Every name came from thor's source. | Fixed. A README, a cheatsheet, six examples, the gallery, and a one-line doc comment on every public procedure in `ui`, `kit`, `app` and `headless`. |
| 4 | The spec puts different gaps between siblings, so the app writes its own `gap` procedure. | Open. The app still calls its `gap` 4 times. |
| 8 | The bench needs the list's box, found by id. | Open. The Tasks page finds the table's rows by two ids for `dev.bench_scroll`. |

## What it cost the app

Each change reached the app at once, as thor keeps no old names. Lines added and removed in the
app's six files, tests included:

| Change in thor | App lines |
| --- | --- |
| Components return a `ui.Signal` | +4 −3 |
| Tokens on daisyUI's names | +21 −21 |
| The Tasks list as a `kit.table` | +25 −32 |
| The reviewed API | +49 −48 |
| `checkbox` and `nav_row` | +4 −4 |
| `kit.colors.line` and `kit.with_opacity` | +9 −9 |
| Words for VoiceOver | +6 −4 |

In all, 126 lines added and 111 removed since iteration 2. Each update also copies thor into
`apps/thor/thor` and records the commit in the README, as there is no package manager.

## Result

- `odin test .` runs the app's 5 tests with no window. They pass on `247161b`, and the trees of
  three pages are snapshots.
- The app is 528 lines: `main.odin` 160, `sidebar.odin` 28, `tasks_page.odin` 137,
  `space_page.odin` 137, `note_page.odin` 66. Its tests are 80 lines. In iteration 2 these were
  544 and 50.
- Boxes the app builds by hand with `ui.box`: 2, down from 4. `ui.scope` calls: 0, down from 1.
- VoiceOver reads each task row and its checkbox as the task's title, each avatar as the
  member's name, and each note card as the note's title. Before, they read ids such as
  `t00001`, `done` and `m1.jpg`.
- Measured on thor's gallery, headless and CPU only: a page at rest makes no heap allocation per
  frame and builds in 0.01 to 0.09 ms. Scrolling a list of 10,000 rows makes 6 to 10 allocations
  per frame, which thor frees when the rows leave.
- VoiceOver's actions were checked in a live window of thor's gallery through the Accessibility
  API, with no sound: 18 of 18 checks pass. The check found that focus was not reported while
  no text field was active, which thor `63a4472` fixed. VoiceOver itself was not run.
- Not checked: the app in a live window by the agent (the owner opened it on 11 November), the
  bench, and the Tahap A runs on this thor.

## Pain points

| # | Pain point |
| --- | --- |
| 1 | VoiceOver reads a row's id, and a checkbox in a row reads "done", until the app gives them words with `ui.current_parent().label = task.title`. Nothing warns of a control that reads its id. |
| 2 | `headless.find` matches an id or a label, not a role. So two elements with the same words are ambiguous: a table's column title and its resize edge both read "Owner" until the edge took `width_label`. |
| 3 | A test that looks for a line of text in the tree breaks when the row takes that text as its label, as the new-task test did. |

## What worked

- Answering questions on a page with live figures before building. Where a build differed
  from its page, the page records it: four places on `feel.html` and six on `voiceover.html`.
- The headless tree and VoiceOver walk the same elements. VoiceOver's elements had tests from
  their first commit.
- A control that works from the keyboard works from VoiceOver. The app wrote no code for
  VoiceOver's actions, only words for the controls that had none.
- The app's code shrank while thor more than doubled.
