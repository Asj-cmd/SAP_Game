# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

## PT2-4 — Music and stings

**Approach**
1. Jingles: the Kenney `music-jingles` pack is already fetched (PT2-3 entry, gitignored in
   `autobuild/Incoming/kenney/music-jingles/`, CC0, sha256 in PROGRESS.md). Pick from the **pizzicato**
   set (plucked strings sound polite and a bit silly, which suits deadpan; 8-bit and steel do not). Win = a short
   one that ends going up, lose = a short one that ends going down; 1.5 to 3 s each. You cannot listen: choose by
   file length (ffprobe or the .ogg header via node) and file order, and log the pick as REVIEW so the user can swap.
   Copy them as `godot/art/audio/music/jingle_win.ogg` and `jingle_lose.ogg`.
2. Music loop: Kenney has none. Look for ONE CC0 loop, calm and slightly silly (light jazz, lounge, easy
   listening, or quirky acoustic; tempo under ~110 bpm; at least 60 s long so the loop does not grate). Places to
   look, in order: OpenGameArt filtered to CC0, then Free Music Archive artists who release everything CC0
   (Loyalty Freak Music, HoliznaCC0). Keep the licence page text or URL as the CC0 proof. Save as
   `godot/art/audio/music/loop.ogg` (OGG Vorbis; convert with ffmpeg if it is installed, else take an .ogg
   original). `GameAudio` already plays `MUSIC_PATH` on the Music bus, quieter in a match.
3. Jail sound: a CC0 cartoon "boink". Look first in Kenney packs through `node autobuild/fetch_kenney.mjs <slug>`
   (`impact-sounds`, `interface-sounds`, `digital-audio`), then OpenGameArt CC0 "boing". If neither has a fitting
   one, generate it (a ~0.35 s sine whose pitch falls from ~600 to ~180 Hz with a little wobble, written as a WAV by a
   small node script and converted, or an `AudioStreamWAV` saved by a Godot tool script) and log it as our own (CC0).
   It goes in `godot/content/sfx/jailed.ogg` (new folder; the user will replace it).
4. `GameAudio`: rows carry an optional `"path"` (full res:// path) that wins over `SFX_DIR + file`, so `jailed`
   can live in `content/sfx/`. New rows: `win` and `lose` (bus `Music`, flat), `jailed` (bus `SFX`).
   In `match_state`, at the change to MATCH_END play `win` or `lose` for the local seat's team instead of
   `sting` (ROUND_END keeps `sting`); this needs the local team passed in or set once. Keep it one call site so
   PT2-7 can move the jingle into its end sequence. A machine with no local seat (dedicated) plays nothing.
5. Jailed: where the seize sound is triggered now (find it from `play(&"seize"` / the captured-state change in
   `greybox_main.gd`), also play `jailed` at the victim's position (`own` true for the local victim). The seize
   thump stays.
6. Export: add `content/sfx/*` to `include_filter` in `godot/export_presets.cfg`.
7. Docs: `HOW_TO_PLAY.md` gets a short section "Changing the jail sound": the file `godot/content/sfx/jailed.ogg`,
   OGG Vorbis, mono or stereo, 44.1 or 48 kHz, keep it under about 2 s, same file name, then rebuild with
   `node autobuild/build.mjs` (it imports first). `ASSETS.md` and `CREDITS.md`: one row per file (name, author,
   licence, URL, CC0 proof, modified?), and replace the "Music: none shipped" line.

**Already decided**
- Pizzicato jingles; jingles on the Music bus (the Music slider controls them). REVIEW.
- The boink is a deliberate exception to D2's "no cartoon sounds", because the task asks for it and the user plans to
  replace it. Log as REVIEW.
- No meme clips, nothing non-CC0. If no verifiable CC0 music loop is found after two sources fail, ship the rest,
  mark the task `[~]` with "loop missing" in PROGRESS.md and move on; do not synthesise music.
- The `spotted` row may keep the pitched sting (PT2-2); do not change it.

**Files likely touched**
- `godot/game/audio/game_audio.gd`, `godot/game/greybox/greybox_main.gd` (local team to GameAudio; jailed trigger)
- `godot/art/audio/music/` (new files: `loop.ogg`, `jingle_win.ogg`, `jingle_lose.ogg`), `godot/content/sfx/jailed.ogg` (new folder and file)
- `godot/export_presets.cfg`, `HOW_TO_PLAY.md`, `ASSETS.md`, `CREDITS.md`, `DECISIONS.md`
- maybe a small fetch or tone script under `autobuild/` (new)

**Done means**
- One headless `--solo` run (about 60 s) and one `--menu` run print no script errors (sound is not heard headless; say so).
- `node autobuild/build.mjs` gives `BUILD: ok` (it smoke-runs the exe).
- Full `node autobuild/verify.mjs` once at the end, just before the final commit: healthy, test pins unchanged.
- No frames.

**Do NOT**
- Write a test (audio is presentation). Touch `sim/`, the snapshot or the network.
- Restyle the settings panel (PT2-6) or build the end sequence (PT2-7).
- Use paid packs, credits, YouTube rips, "royalty free" non-CC0 music, or CC-BY without a credit line.

## PT2-5 — Bring back the realistic house

**Approach**
1. Diagnose by reading code first, no frames yet. The reference is commit `23ad3fd` (P3-3b: textured shell
   and furniture, before P3-4 exterior, P3-5 lighting and P3-6 merge). Diff it against HEAD for
   `godot/art/theme/default_theme.tres`, `godot/game/art/art_theme.gd`, `shell_builder.gd`, `mesh_merge.gd`,
   `furniture_dresser.gd`, `godot/game/greybox/world_backdrop.gd`, `player_settings.gd`.
2. Suspects found in a quick read, check each:
   - `interior_energy` went 1.2 → 0.4 in P3-5, and room lamps are off: interiors may be lit only by ambient and fill,
     which flattens them.
   - `MeshMerge` (P3-6) appends every surface into one SurfaceTool per material. `SurfaceTool.append_from` takes the
     vertex format of what is appended first: if a piece without UVs or tangents comes first, the merged surface can
     lose UVs and its textures draw as one flat colour. Check that the merged furniture, cash and tree meshes keep
     `ARRAY_TEX_UV` and normals.
   - Roughness changes in the theme (several surfaces 0.7 → 0.55 etc.), tints added in P3-4 / P3-7.
   - P7-2 quality presets: what High does to the shadow atlas size (`shadow_size: -1`) and `scaling_3d_scale`.
   - Texture imports: mipmaps / VRAM compression settings in the `.import` files of `godot/art/textures/*`.
3. Fix on the **High** preset: restore textures (UVs through the merge), materials, interior light. Medium and Low
   may keep the cheaper settings. Room lamps stay off unless the gate still passes with them (P3-5 measured
   +4.2 ms per indoor view; it will not).
4. Before half of the frame set: `git worktree add ../cg_before 23ad3fd` (never touch the working tree), one
   `--import` there, then the views below with that commit's own `views.json` (P3-8 moved some views; compare by name).
   Copy the results to `autobuild/frames/pt2_5/before_<view>.png`. Remove the worktree after (`git worktree remove`).
5. After half: the same views on HEAD into `autobuild/frames/pt2_5/after_<view>.png`
   (`node autobuild/verify.mjs --frames-only --views=...`).
6. Log in `DECISIONS.md` what flattened it and what you changed (REVIEW for the look), and STYLE.md §4 if the lighting
   numbers change.

**Already decided**
- Reference commit `23ad3fd`. Realistic house, silly figures (D2): only the house changes.
- The fix goes in theme data and the merge / builder code; High preset only where it costs GPU.
- Budgets are what the full verify gates (draws and triangles of three views). No separate `render_stats.mjs` timing runs.

**Files likely touched**
- `godot/art/theme/default_theme.tres`, `godot/game/art/art_theme.gd`, `godot/game/art/mesh_merge.gd`,
  `godot/game/art/shell_builder.gd`, `godot/game/greybox/world_backdrop.gd`, `godot/game/greybox/player_settings.gd`
- `DECISIONS.md`, `STYLE.md`, `PROGRESS.md`

**Done means**
- Full `node autobuild/verify.mjs` once at the end: healthy, render counters within limits.
- **Frames (one before/after set, at most one redo of the after half):** views `room_a_gf_kitchen`, `room_a_up_study`,
  `room_a_up_bedroom`, `room_a_gf_fronthall`, `cam_kitchen_look_down`, `ext_a_south`. Each after frame must show
  textured surfaces with visible grain (wood floors, tile, plaster, brick), furniture with its own shading and
  texture (not one flat colour per piece), walls, floor and ceiling clearly different in brightness, a sun shadow on
  the exterior, and look at least as realistic as its before frame. In PROGRESS.md describe what each before and
  after frame actually shows.

**Do NOT**
- Change collision, zones, `build_house.gd` geometry, `house.tscn`, or anything in `content/`.
- Touch the figures, hair (PT2-8) or UI (PT2-6).
- Add Forward+-only features (SSAO, SSR, SDFGI, volumetric fog) or new downloaded textures (the CC0 ones in `godot/art/textures/` are enough).
- Run render sweeps, more capture sets, or bot work.

## PT2-6 — UI art pass

**Approach**
1. One shared theme: new `godot/game/greybox/ui_theme.gd` (`class_name UiTheme`), a static `current() -> Theme`
   built once in code (fonts, sizes, StyleBoxFlat panels and buttons for normal / hover / pressed / focus /
   disabled, LineEdit, CheckBox, HSlider, OptionButton, ScrollContainer). Every UI root sets `theme =
   UiTheme.current()`, and the per-control `add_theme_*` overrides now in the panels are removed where the theme covers
   them. The look numbers sit as constants at the top of that file (one place to change).
2. Fonts (OFL, Google Fonts repo on GitHub, `ofl/<family>/`): display **Anton** (`Anton-Regular.ttf`), body **Inter**
   (the variable `Inter[opsz,wght].ttf`, or static Regular and SemiBold). Put them in `godot/art/ui/fonts/` (new)
   with each `OFL.txt`; add `art/ui/fonts/*.txt` to `include_filter` in `godot/export_presets.cfg`.
3. Look: cream card panels (about `Color(0.95, 0.92, 0.85)`) with a 3 px charcoal border and 6 px corners, charcoal
   text; buttons solid charcoal with cream Anton text; hover = mustard `Color(0.85, 0.66, 0.25)` and a 1.04 scale tween
   (0.08 s), press = darker and 0.97. Panels fade and rise 12 px in over 0.15 s when opened. Think "estate agent's
   For Sale sign", flat and plain, so it is not a web page. Family colours (ArtTheme) only on the HUD bar and results.
4. Main menu: title "CASH GRAB" in Anton, about 120 px, cream with a 6 px charcoal outline and a hard drop shadow,
   slightly tilted (−3°) like a sign. Behind it a live view of the two houses: if `main_menu.gd` runs over a built
   level, add a Camera3D on a slow orbit (one turn per 90 s) over the lot centre, high enough to see both houses; if
   the menu has no world, build the level visuals only (no sim, no bots) for it; if that is too heavy, a dimmed sky and
   ground is the fallback (log it).
5. HUD (`match_hud.gd`): tug-of-war bar thicker (about 28 px), family colours from the theme, display names
   (`FamilyNames`) in Anton at each end with the cash count large beside them, the round timer as `m:ss` in a
   charcoal plate in the middle (cream text; in the last 10 s the plate turns the mustard colour, no flashing).
   Icons for cash, jail timer, carry state and rescue prompt: fetch the Kenney `game-icons` pack with
   `node autobuild/fetch_kenney.mjs game-icons` (CC0) and copy only the 4 to 6 icons you use into `godot/art/ui/icons/`;
   if the pack has none that fit, draw them as simple shapes in `_draw`.
6. Results (`results_panel.gd`) and headline (`match_status.gd`): the line is plural. Build it as
   `"%s WIN THE MATCH"` and `"%s WIN ROUND %d"` with the name from `FamilyNames`, so it reads "<NAME> WIN". No line
   says "WINS" after a family name (grep for `WINS` in `godot/game` when done; `WINS_NEEDED` in `autoload/match_state.gd` is a constant, leave it).
7. Restyle settings, pause, lobby, first-run guide and the feedback event line through the theme.
8. Capture: no flag shows a menu screen today. Add a small debug flag in `game/debug/frame_capture.gd`,
   `--capture-screen=menu|settings|pause|lobby|hud|results`, that opens that screen (results: from a forced MATCH_END
   in a solo world, presentation only) and shoots it. It is a debug tool, not a test.

**Already decided** (log the look, fonts and icons in `DECISIONS.md` as REVIEW)
- Theme in code (`UiTheme`), Anton + Inter, cream / charcoal / mustard, family colours only on bar and results.
- Deadpan: no confetti, no bouncing, no particle bursts; animations are short fades, rises and small scales.
- Names only from `family_names.cfg` through `FamilyNames` (P5-0); no family name typed anywhere.

**Files likely touched**
- new: `godot/game/greybox/ui_theme.gd`, `godot/art/ui/fonts/*`, `godot/art/ui/icons/*`
- `godot/game/greybox/main_menu.gd`, `settings_panel.gd`, `pause_menu.gd`, `lobby_panel.gd`, `match_hud.gd`,
  `results_panel.gd`, `match_status.gd`, `first_run_guide.gd`, `game_feedback.gd`, `greybox_main.gd` (only to apply the theme)
- `godot/game/debug/frame_capture.gd`, `godot/export_presets.cfg`, `ASSETS.md`, `CREDITS.md`, `DECISIONS.md`, `STYLE.md` (a short UI section)

**Done means**
- `family_names_test` still passes (run it once if you touch `match_status.gd`); no other tests.
- Full `node autobuild/verify.mjs` once at the end: healthy.
- **Frames (one set, at most one redo):** `menu`, `settings`, `pause`, `lobby`, `hud` (3v3 mid-round, someone
  carrying if possible), `results` into `autobuild/frames/pt2_6/`. Each must show: the Anton and Inter fonts (no Godot
  default font), cream panels with charcoal borders, the shared button style; menu: the tilted title over the houses;
  hud: the tug-of-war bar with both names, counts, the timer plate and at least one icon; results: "<NAME> WIN THE
  MATCH" with no "WINS". Describe in PROGRESS.md what each frame actually shows.

**Do NOT**
- Copy another game's UI, logo or fonts; no paid or non-OFL/CC0 fonts.
- Touch `sim/`, the network, the match flow or the HUD's data (the `cash_split` function and its test stay as they are).
- Build the match end sequence (PT2-7) or change audio (PT2-4).
- Add new test files, sweeps, or capture more than the one set.
