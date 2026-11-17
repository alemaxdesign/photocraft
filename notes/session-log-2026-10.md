# PhotoCraft session log (10–16 October 2026)

Everything I (Claude) was asked to do in PhotoCraft over these sessions, what came out of it,
and the problems hit along the way. Photos live in `/Volumes/AIML03/Users/slegrand/Pictures`;
my test renders live in `/Volumes/AIML03/Users/slegrand/photocraft-work`.

## 1. Setup

| Task | Result |
|---|---|
| Build the project | `cargo build --workspace` passed (2 min 54 s). Built without `../craft-fonts`, so no bundled fonts. One warning: the `block v0.1.6` dependency will be rejected by a future Rust. |
| Run the app | `cargo run -p photocraft` (debug build). |
| Let Claude see and drive the app | Relaunched with `--control 7878` and a token file, and took screenshots through the control channel. |
| Add HEIC support | Rebuilt the app and the CLI with `--features heif`. HEIC support is off by default. |
| Switch from Python to PhotoCraft's own tools | Registered `photocraft-cli mcp --bridge 127.0.0.1:7878` as the `photocraft-live` MCP server. Token: `~/Library/Application Support/Photocraft/control.token` on AIML03. Remove with `claude mcp remove photocraft-live -s local`. |
| Keep the app open independently | Launched with `nohup … & disown` and read/write roots on AIML03 (read: Pictures, write: photocraft-work). |

## 2. Photo edits

### IMG_9362.jpg (plant leaves)
- New empty layer **Layer 1**.
- **Leaves** layer: a copy of the photo, masked to the leaves with Color Range, sampling 9 leaf colours at fuzziness 60.
- Leaves turned purple with a masked **Hue/Saturation** adjustment (hue +170, saturation +10).
- Brown stain removed with Content-Aware Fill on the Leaves layer, inside a feathered leaf outline.
- Problems:
  - The automatic greens + yellows Color Range left the leaves mid-grey, so I sampled leaf colours instead.
  - Soil specks crept into the mask, giving the soil a bluish tint.
  - The first stain fill had a hard edge and spilled onto the soil, so I undid it and redid it.
  - The edits were lost later because the document was closed without saving.

### IMG_6024 (church, tower, trees; saved as `IMG_6024 correction.psd`)

| Task | Outcome |
|---|---|
| Remove the two overhead wires | Done with Remove strokes on a **Wires removed** layer. |
| Fix the church lantern openings the Remove tool had filled | Done in 3 tries. **Lantern fix** layer: two thin Clone Stamp strokes copying from above. |
| Fix branch continuity where the wire crossed the treetop | Not solved. Tried Healing Brush, Clone Stamp (from above, and from above and below), Content-Aware Fill, Dust & Scratches, and a narrow 12 px Remove. Each left either a doubled or tripled line, a smear, or broken branches. Joining branches across the gap needs hand work. |
| Remove 2 wires in front of the dome, between the house roof and the trees | Done with 8 px Remove strokes. The user had mentioned 3; only 2 were found. |
| Remove 4 wires in the trees on the right | Done with 5 px Remove. A faint smoother band remains; the user retouched by hand. |
| Help with the user's own Clone Stamp | It did nothing because Sample was set to "Current Layer" on an empty layer. Fix: set Sample to **All Layers**. |
| Remove the grey fence at the bottom left | Crop tested (2874 × 2728, pixels kept); the user disliked it, so it was undone. Content-Aware Fill gave a flat orange surface or stacked agapanthus copies. A mirrored copy of the flower strip was obvious. Not done. |
| Remove the building and roof on the left | Content-Aware Fill on a **Building removed** layer, from 8 versions tested. A straight edge remains where the roof top was; the user retouched by hand. |
| Darken the orange fence | Tested a masked Hue/Saturation adjustment. The roses are almost the same colour as the fence, which left an orange outline around them. Not applied. |
| Erase the fences, shrubs and flowers but keep the palm | The palm was copied to a **Palm (kept)** layer. The fill put pieces of palm in the bottom-left corner; a second fill, sampling only the conifer, looked like "a pile of whatever". The user took over by hand. |

Problems specific to this photo:
- My first attempt to open the HEIC failed because the build lacked HEIC support.
- `IMG_6024.pxd` is a Pixelmator file; PhotoCraft can't read it.
- The first HEIC copy I opened was on the internal disk, not AIML03 (see section 3).

### IMG_6039.HEIC (beach)
- Removed the black sandals, the orange purse, and the beaded sandals in the bottom-left corner. Content-Aware Fill sampled from nearby textured sand, with feathered irregular outlines. Clone Stamp fixed the strip at the bottom edge.
- The sand where the purse was came out darker (about 145 vs 167 brightness around it). Fixed with a soft-masked **Curves 1** layer that lifts it to 163–175.
- "Remove just the shoes": the user had made their own **sac orange** layer, so the shoe removal went on a **Shoes removed** copy of it, under Curves 1.
- Problems:
  - The first fills were smooth patches with rectangular edges.
  - The purse area showed a seam, then an orange sliver at the right edge.
  - Bits of sandal remained at the bottom edge.
  - A hard-edged fill there made a flat band, so I used Clone Stamp instead.

### IMG_6026.heic (round chapel at sunset)
- Analysis: about 12 wires, a street lamp, 5 green insulators on a curved bracket, and a wooden pole.
- Plan agreed with the user: phase 1 wires, lamp and insulators; phase 2 the pole; then decide how to handle the foliage.
- Phase 1, current state of the **Wires removed** layer, rebuilt once:
  - **Sky:** a "not sky colour" selection treated with Median 24 ×2 and 16. No streaks.
  - **Lamp and bracket:** wide Remove strokes.
  - **Dome:** the 6 wires were traced on a coordinate grid and removed with 22–30 px Remove strokes.
  - **Dome outline:** protected from the sky filter (saved selection "dome"), with small Remove dabs where wires cross the edge.
  - **Left sky:** 4 traced wires removed.
- Problems:
  - Content-Aware Fill on thin wire masks produced bright colourful ghost lines.
  - A light median left "beaded" leftovers.
  - Sunlit wires are brighter than the sky, so dark-only scans missed them.
  - The first version cut notches into the dome edge, because the sky filter caught dome pixels where the wires crossed. Fixed by protecting the exact dome outline.
  - Protecting the dome by colour also protected the wires, since the wires are dark like the slates. Switched to a traced outline.
  - Brightness scans give false readings on stone and leaves, so wires there were traced by eye on 20 px grids at 3×.
  - Still open:
    - Wires between the two trees, across the dome's right eave and the dark stone wall: automatic attempts left pale smears.
    - Faint traces on the lit left wall, and a grey smudge on the tree tops at the far left.
    - Wires in the big tree and around the pole: deferred to phase 2.

## 3. Problems in how I worked (and the rules that came out of them)

- **Accessed the internal disk.** A Spotlight search (`mdfind`) found `Kertugal_6025.heic` in `/Users/slegrand/Documents/Pixelmator Pro/`, and I opened it in PhotoCraft without noticing it was off AIML03. The scratch folder in `/private/tmp` is also on the internal disk; it held screenshots, the token copy and logs. **Rule now in memory:** never touch anything outside `/Volumes/AIML03`.
- **Python.** I used small Python scripts as a control client, and later two stray one-liners. They ran outside the project and changed nothing in the repo. Switched to `photocraft-cli` at the user's request.
- **Images sent to Anthropic.** Every screenshot or crop I looked at was sent to Anthropic as part of the conversation. A local-model alternative is planned; see `local-vlm-plan` in Claude's memory.
- **App closed by a timeout.** PhotoCraft was started as a Claude Code background task and stopped automatically after 30 minutes. Fixed by launching it fully detached.
- **Too many tries on hard areas.** Treetops, fences and flower strips are beyond what Content-Aware Fill, Remove and Clone Stamp can do automatically. I should say so sooner rather than make repeated attempts.

## 4. PhotoCraft issues noticed (possible bug reports)

- The bridge often answers **"Broken pipe (os error 32)"** on the first call after a pause, though the next call works. Sometimes the operation did complete, for example opening a file.
- **Screenshots of the full window** exceed the 8 MB response limit on the 5K displays, even with `max_side`.
- The macOS **Save As / Save a Copy** dialog shows no format menu. You have to type the `.jpg` or `.tif` extension, or use **File ▸ Export ▸ Export As…**.
- `doc_export` in bridge mode can't set JPEG quality ("quality needs headless mode").
- `select.object` found nothing on the shrubs; Color Range can't separate sunset-lit shrubs from the orange fence.
- Opening a file over the control channel needs `--automation-read-root`. Without one it fails with a confusing broken-pipe error rather than "no read root".

## 5. Advice given

- **Print file:** keep the PSD as master and export **JPEG at 100%** (or TIFF if the lab takes it).
  - For a 4 × 5 print: crop to 4:5 portrait. The ~2299 × 2874 result gives about 575 ppi.
  - Convert to **sRGB** first. The user's file was already sRGB.
- **Screen vs print:**
  - Turn off True Tone and Night Shift, and set brightness to 50–60%.
  - Soft-proof with the lab's profile, and order a test print.
- **Spyder5 Pro:** Datacolor's 6.3 software supports Apple Silicon and macOS through 26 "and later". Untested on 27; DisplayCAL is the fallback.
  - Targets: D65, gamma 2.2, 100–120 cd/m².
  - The Spyder5 is less accurate on the mini-LED XDR panel.
- **Machine:** MacBook Pro 16" M1 Max (10-core CPU, 32-core GPU), 64 GB, macOS 27.0.1, two Dell S2721QS monitors. Enough for a local vision model, up to about 32B parameters.
