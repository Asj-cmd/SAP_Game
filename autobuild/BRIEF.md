# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

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
