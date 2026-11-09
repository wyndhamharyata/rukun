# thor research

The research track of thor: the test app built with thor, Electron, Tauri and GPUI, and the
material for the AFL documents. thor itself lives in `../thor`.

The test app is a desktop slice of Rukun, the family workspace from the Ideation report for
Digital Entrepreneurship Product Development: spaces, tasks and notes.

- `spec/test-app.html`: what every app draws and does, and the settings the harness uses.
- `data/`: `generate.py` and its output: `rukun.json`, 400 photos and 5 avatars. The output is
  committed. To make it again: `python3 -I data/generate.py` (needs ImageMagick 7).
- `apps/thor/`: the thor app. `thor` is a link to `../../../thor/thor`, and `resources/` links
  the photos and avatars. Build with `odin build .` in that folder and run `./thor.bin`, or make
  `build/Rukun.app` with `./thor/bundle.sh Rukun`. `TESTAPP_PAGE=keluarga` opens a space.
- `notes/`: one file per DSR iteration.
- `methods/`: drafts for the next AFL document, in Indonesian.
