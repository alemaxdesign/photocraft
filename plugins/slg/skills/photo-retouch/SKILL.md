---
name: photo-retouch
description: Retouch a photo in the running PhotoCraft app (remove objects, wires, stains; masks; colour fixes) the safe way - test every edit on a copy with photocraft-cli, apply it to the live document on a new layer through the photocraft-live MCP bridge, then verify by exporting. Use when the user asks to edit, retouch, clean up or remove something from a photo in PhotoCraft.
---

# Photo retouch in PhotoCraft

The user works in the PhotoCraft desktop app and asks for edits in plain words ("remove the wires",
"remove the shoes", "make the leaves purple"). Do the edit for them, carefully and reversibly.

## Hard rules

- **Stay on AIML03.** Never read, search, open or write anything outside `/Volumes/AIML03`. The
  internal-disk home `/Users/slegrand` is off limits. Search with
  `find /Volumes/AIML03/Users/slegrand/Pictures -iname '*<name>*'`, never plain `mdfind`. Check every
  path a tool returns before using it.
- **No Python.** Drive the app with the `photocraft-live` MCP tools and `photocraft-cli` only.
- **Never touch the user's pixels destructively.** Every edit goes on a new, clearly named layer
  (`layer.duplicate` + `layer.renameLayer`, or `layer.new.layer`) or an adjustment layer with a mask.
  Never edit `Background`. Never save over the user's file; tell them how to save.
- **Images you look at are sent to Anthropic.** Say so the first time in a session. If the user has
  set up the local vision model (see the `local-vlm-plan` memory), use it for visual checks instead.

## Setup

PhotoCraft repo: `/Volumes/AIML03/Users/slegrand/claude-code/alemaxdesign/photocraft`.
Work folder (all test renders): `/Volumes/PhotoEditing/photocraft-work`.
Token: `/Volumes/AIML03/Users/slegrand/Library/Application Support/Photocraft/control.token`.

1. Build with HEIC support if needed (iPhone photos are HEIC):
   `cargo build -p photocraft -p photocraft-cli --features heif`.
2. If the app is not running (`pgrep -f "target/debug/photocraft --control"`), launch it **detached**
   so it is never killed by a background-task timeout:
   ```sh
   cd <repo> && nohup ./target/debug/photocraft --control 7878 \
     --control-token-file "<token>" \
     --automation-read-root /Volumes/AIML03/Users/slegrand/Pictures \
     --automation-write-root /Volumes/PhotoEditing/photocraft-work \
     > /Volumes/PhotoEditing/photocraft-work/app.log 2>&1 < /dev/null & disown
   ```
   Never start it with `run_in_background` (killed after 30 min, unsaved work lost).
3. The MCP server `photocraft-live` (`photocraft-cli mcp --bridge 127.0.0.1:7878 --control-token-file <token>`)
   must be registered; if its tools are missing, register it and ask the user to restart Claude Code.

## Workflow

1. **Look first.** `doc_inspect` (layers, history: the user may have changed things since your last
   step), then render a preview with the CLI:
   `photocraft-cli run <file> --cmd image.imageSize --params '{"width":W,"height":H}' --out <work>/p.png`
   (keep the aspect ratio: check `photocraft-cli info <file> --compact` for width/height). Crop and
   zoom on the target area. For precise coordinates, render a crop with a grid overlay (fill 1–2 px
   rects every 20/50/100 px on a new layer) and read positions off the grid.
2. **Test on a copy, never live.** Run the full sequence with `photocraft-cli run <original> --cmd … --out <work>/test.png`,
   crop the result and look at it at 2–4×. Iterate here. Keep the step list in a file in the work
   folder so the final version can be replayed exactly.
3. **Apply live in one batch** with `command_batch`: duplicate the right layer, rename it, then the
   tested steps. Watch for variable names in shell loops overwriting your file path.
4. **Verify the live result**: `doc_export` to `<work>/check.png`, then crop/measure with the CLI.
   Full-window `ui_screenshot` is too large on the 5K displays; don't use it.
5. **Report**: what is fixed, what is still visible (be specific), which layers you added, how to
   undo (hide/delete the layer), and remind the user to save as `.psd` (HEIC/JPEG lose layers).

## Techniques that worked

| Problem | Method |
|---|---|
| Thin wires in sky | Select "not sky": `select.colorRange` on ~20 sky samples, `select.inverse`, intersect with a lasso of the sky area, expand 6–8, then `filter.noise.median` 24 (×2) and a second pass at fuzziness 22 + median 16. No streaks. |
| Wires crossing a building/dome | Trace each wire on a grid, `paint.remove` along it, size 20–30, hardness 90. Protect the building outline from the sky filter: lasso the exact silhouette, expand 5, `select.saveSelection` "dome", and `select.loadSelection … operation: subtract` before the median. Dab `paint.remove` (size ~26) where wires meet the silhouette. |
| Objects on sand/ground | `edit.contentAwareFill` with `sampling: custom` on a textured area next to the object, `colorAdaptation: high`, feathered irregular lasso (no straight edges). Strips at the image edge: Clone Stamp from just above, not a hard-edged fill. |
| Fill came out darker/lighter | Measure with `document.sampleColor` (size 51) inside vs around, then a Curves adjustment layer masked with a 60 px feathered selection. |
| Thin structure the fill destroyed (lantern openings) | Clear that area on the edit layer so the original shows, then thin Clone Stamp strokes copying the band just above (vertical structures line up). |
| Recolour (leaves to purple) | Mask from `select.colorRange` sampled points, then a masked Hue/Saturation adjustment layer. |

## Know when to stop

Automatic tools cannot rebuild what is hidden: branches across a gap in a treetop, a garden behind a
fence, flowers the same colour as the background, wires over textured stone. After two failed
approaches on such an area, stop, say plainly it needs hand work, and give exact Clone Stamp steps:
new layer, Sample **All Layers**, soft brush sized to the defect, ⌥-click a matching source close by,
short irregular strokes, change source often, judge at 100%.

## Known PhotoCraft quirks

- The bridge often answers "Broken pipe (os error 32)" on the first call after a pause: run
  `doc_inspect`/`session_list` to see what actually happened, then retry. Opening a file may have
  succeeded despite the error.
- `doc_export` in bridge mode can't set JPEG quality; export PNG for checks.
- Opening files over control needs `--automation-read-root`; without it opens fail.
- The Clone Stamp on an empty layer copies nothing unless Sample is "All Layers".
- macOS Save dialog has no format menu: users export JPEG/TIFF with File ▸ Export ▸ Export As….
