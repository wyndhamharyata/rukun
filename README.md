# thor research

The research track of thor: the test app built with thor, Electron, Tauri and GPUI, and the
material for the AFL documents. Public at https://github.com/wyndhamharyata/rukun.

The test app is a desktop slice of Rukun, the family workspace from the Ideation report for
Digital Entrepreneurship Product Development: spaces, tasks and notes.

- `spec/test-app.html`: what every app draws and does, and the settings the harness uses.
- `data/`: `generate.py` and its output: `rukun.json`, 400 photos and 5 avatars. The output is
  committed. To make it again: `python3 -I data/generate.py` (needs ImageMagick 7).
- `apps/thor/`: the thor app. `thor/` is a copy of thor's framework code (MIT, its own `LICENSE`)
  at thor commit `247161b`, so this repo builds on its own. `resources/` links
  the photos and avatars. Build with `odin build .` in that folder and run `./thor.bin`, or make
  `build/Rukun.app` with `./thor/bundle.sh Rukun`. `TESTAPP_PAGE=keluarga` opens a space.
  `odin test . -define:ODIN_TEST_THREADS=1` there tests adding a task and sending a message (the
  tests share the app's data, so they run one at a time).
- `apps/web/`: the React app that Electron and Tauri share, from Vite's React template. `npm run
  build` there makes `dist/`, which both shells load. `npm run dev` serves it on port 1420.
- `apps/electron/`: the Electron shell, from Electron Forge's base template. `npx electron-forge
  package` makes `out/Rukun-darwin-arm64/Rukun.app`. `RUKUN_DEV_URL=http://localhost:1420 npm
  start` loads the dev server instead of `dist/`.
- `apps/tauri/`: the Tauri shell, from create-tauri-app's React template with its frontend taken
  out. `npx tauri build --bundles app` builds the web app and makes
  `src-tauri/target/release/bundle/macos/Rukun.app`. `npx tauri dev` uses the dev server.
- `apps/gpui/`: the GPUI app, from GPUI Kit's getting-started guide (`cargo new` and the one
  `gpui-kit` dependency). `cargo run` runs it, and `./bundle.sh` makes `build/Rukun.app` as GPUI
  Kit's packaging guide does. GPUI stops drawing a window that is fully covered, so its captures
  need the window in front.
- `harness/`: the Tahap A measurements. `python3 -I harness/run.py` opens each app's `.app` in
  front (GPUI stops drawing a covered window) and runs S1 start, S2 and S3 scrolls and S4 idle,
  `--runs` times each, with `--apps`, `--idle`, `--scroll-seconds` and `--build` (a clean build
  first, slow). Results go to `harness/results/` (not committed); `harness/compare.py` lines up
  result files. `--self-test` checks its parsing. Leave the mouse and keyboard alone while it runs,
  with the 75 Hz external screen as the main display.
- `notes/`: one file per DSR iteration.
- `methods/`: drafts for the next AFL document, in Indonesian.
- `private/`: git ignores it. Keep Tahap B recordings, SUS forms and interview notes there, never
  in a commit.
