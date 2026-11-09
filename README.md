# thor research

The research track of thor: the test app built with thor, Electron, Tauri and GPUI, and the
material for the AFL documents. thor itself lives in `../thor`.

- `spec/test-app.html`: what every app draws and does, and the settings the harness uses.
- `data/`: `generate.py` and its output, `library.json` and 400 covers. The output is committed.
  To make it again: `python3 -I data/generate.py` (needs ImageMagick 7).
- `apps/thor/`: the thor app. `thor` is a link to `../../../thor/thor`. Build with
  `odin build .` in that folder, run `./thor.bin`.
- `notes/`: one file per DSR iteration.
- `methods/`: drafts for the next AFL document, in Indonesian.
