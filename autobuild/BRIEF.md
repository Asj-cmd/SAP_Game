# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

## P7-1 — Export

**Approach**
1. Export templates ARE installed: `%APPDATA%/Godot/export_templates/4.7.1.stable/` holds
   `windows_release_x86_64.exe` / `_console.exe`, matching the default `GODOT_BIN`
   (`Godot_v4.7.1-stable_win64_console.exe`). No BLOCKED.md entry, no download.
2. Deal with the Godot MCP plugin first (ASSETS.md row: licence unknown, must not ship). Remove its
   three runtime-bridge autoloads (`MCPRuntimeBridge`, `MCPInputBridge`, `MCPScreenshotBridge`) from
   `godot/project.godot` `[autoload]`, and add `addons/*` to the preset's `exclude_filter`. Leave the
   `addons/godot_mcp/` folder and the `[editor_plugins]` line in place (editor-only, never exported).
   Update the ASSETS.md row to say how it is kept out.
3. Preset (`godot/export_presets.cfg`, keep "Windows Desktop"): set `application/file_version` and
   `product_version` to `0.1.0.0`, `file_description` "Cash Grab", leave the icon empty. Keep
   `embed_pck=true`, x86_64, `console_wrapper=1`, `exclude_filter` `tests/*, tools/*, addons/*`.
   `steam_appid.txt` is not a resource, so the export already leaves it out; check, don't add it.
4. Write `autobuild/build.mjs` (new), in the style of `run_tool.mjs` (same `GODOT_BIN` default):
   (a) refuse with a clear message if `project.godot` still names `addons/godot_mcp` under
   `[autoload]` (the editor plugin can re-add them when the user opens the editor);
   (b) `GODOT_BIN --headless --path godot --import`, then
   `--headless --path godot --export-release "Windows Desktop" ../build/CashGrab.exe`;
   (c) check `build/CashGrab.exe` exists and print its size in MB;
   (d) smoke-run the exe once: `build/CashGrab.exe --headless --quit-after 900 -- --solo`, with a
   node timeout of 120 s, and fail if the output contains `SCRIPT ERROR`, `Parse Error` or
   `Failed to load`. Print `BUILD: ok <size> MB` at the end.
5. Run `node autobuild/build.mjs` once. If the smoke run shows errors that are missing files in the
   export (e.g. something loaded by path from outside `res://` or filtered out), fix the filter, max
   two attempts, then log in BLOCKED.md and mark `[~]`.
6. Update `godot/PLAYTEST.md` §2 "Get the build" to say `node autobuild/build.mjs` and the real size.

**Already decided**
- MCP autoloads removed from `project.godot`, `addons/*` excluded from export (log in DECISIONS.md;
  undo = put the three lines back). Not REVIEW.
- Release export, not debug; console wrapper kept (friends' playtests need a way to see errors).
- No code signing, no icon, no installer (unsigned exe, as PLAYTEST.md already warns).
- `build/` stays gitignored (it already is). Nothing is uploaded anywhere.

**Files likely touched**
`godot/project.godot`, `godot/export_presets.cfg`, `autobuild/build.mjs` (new), `godot/PLAYTEST.md`,
`ASSETS.md`, `DECISIONS.md`, `PROGRESS.md`, `PLAN.md`.

**Done means**
- `node autobuild/build.mjs` ends `BUILD: ok`, exe size recorded in PROGRESS.md.
- The smoke run of the exported exe printed no script/parse/load errors.
- Full `node autobuild/verify.mjs` once at the end: healthy (the autoload removal must not break any
  tool; nothing in `game/` or `tools/` should reference the MCP bridges — grep to confirm).

**Do NOT**
- Download templates or anything else; publish or upload the build; add it to git.
- Delete `godot/addons/godot_mcp/` or the editor plugin line.
- Add GodotSteam or `steam_appid.txt` to the export.
- Run frames, captures or `--pilot`; write test files; change the sim.

## P7-2 — Quality settings and performance

**Approach**
1. Add a Graphics section to `PlayerSettings` (new `[video]` section in `user://settings.cfg`):
   `quality` (low / medium / high), `fullscreen` (bool), `vsync` (bool), `max_fps` (0 = off, 30, 60,
   120). Capture/pilot/net-smoke runs ignore saved values, as the other settings already do.
2. One apply function (e.g. `PlayerSettings.apply_video(viewport)`) called at start and when the
   panel changes a value. Presets, as data in one small dictionary in that file:
   - **high** (default = today's look): sun shadow on at the theme's `sun_shadow_size` (2048),
     render scale 1.0, MSAA off.
   - **medium**: sun shadow on at 1024, render scale 1.0.
   - **low**: sun shadow off, 3D render scale 0.75 (bilinear) on the seat viewports.
   Shadow on/off and atlas size go through what `world_backdrop.gd` already does (lines ~60–67:
   `sun.shadow_enabled`, `RenderingServer.directional_shadow_atlas_set_size`); add a small hook there
   rather than a second place that creates lights. The seats are SubViewports: set
   `scaling_3d_scale` on each seat viewport, not only the root.
3. Add a `--quality=low|medium|high` command-line override (wins over the saved value) so the
   measurement can pick a preset.
4. Add the Graphics rows to `SettingsPanel` (an OptionButton for quality and max FPS, two
   checkboxes). Applies at once, saved like the other settings.
5. Measure on the dev machine, windowed (real GPU), with the existing tool and only these views:
   `node autobuild/render_stats.mjs --views=<the three views verify gates + the kitchen view>
   --args="--team-size=4 --quality=<preset>"`, once per preset (3 runs, each well under 10 min; check
   the view names in `autobuild/views.json` and `render_budget.json`). That is a timing table, not
   a capture set: do not open or judge frames.
6. Write the table in `godot/PLAYTEST.md` (there is no root PLAYTEST.md; use the existing one): a new
   short section "Performance on the dev machine": GPU name, per preset and view the frame ms, GPU ms
   and the FPS they imply (1000 / frame ms), plus which preset a friend on a weak laptop should pick.

**Already decided**
- Default preset is **high** (current look; P3-6 measured it within budget on the GT 730M). REVIEW
  only the preset contents (log in DECISIONS.md as REVIEW: what low drops).
- No Forward+ features, no SSAO/glow/FXAA additions (D6). MSAA stays off in every preset.
- VSync default on, max FPS default 0, fullscreen default off (windowed, as today).
- Settings are presentation only: nothing reaches the sim, snapshots or the network.

**Files likely touched**
`godot/game/greybox/player_settings.gd`, `godot/game/greybox/settings_panel.gd`,
`godot/game/greybox/world_backdrop.gd`, `godot/game/greybox/greybox_main.gd` (apply at start, seat
viewports, `--quality=`), `godot/PLAYTEST.md`, `DECISIONS.md`, `PROGRESS.md`, `PLAN.md`.

**Done means**
- `--quality=low` measurably lowers GPU ms in the timing table (if it does not, say so; do not
  chase it).
- The table is in `godot/PLAYTEST.md` with real measured numbers.
- Full `node autobuild/verify.mjs` once at the end: healthy, gated draws/triangles unchanged at the
  default preset.

**Do NOT**
- Capture, open or judge frames; run `render_stats.mjs` over all views or more than once per preset.
- Change the theme's default look, budgets in `render_budget.json`, or the verify gates.
- Write a test for the settings (presentation; `godot/CLAUDE.md`).
- Touch the sim, bots, or networking.

## P7-3 — Docs

**Approach**
1. Root `README.md`: rewrite the top half for the Godot game (it still leads with the legacy
   Three.js `npm run play` guide). Order: one-paragraph pitch; "Play it" (get `build/CashGrab.exe`
   from `node autobuild/build.mjs`, or point at `godot/PLAYTEST.md` for friends and Tailscale/LAN,
   and the Steam section); controls (take them from `PlayerSettings.DEFAULT_KEYS` / the in-game
   How to play, not from the legacy README); "For developers" (`GODOT_BIN`, `verify.mjs`, links to
   `godot/CLAUDE.md`, `ARCHITECTURE.md`, `PLAN.md`). Move the legacy Three.js guide into one short
   "Legacy client/server" section at the bottom (keep its commands; do not delete the folders).
2. `godot/PLAYTEST.md`: check every step against the current game (menu buttons: solo, Host, Join,
   Settings, How to play, Quit; lobby panel; Esc pause; results panel; F10). Fix what is stale; keep
   P7-1's build line and P7-2's performance table.
3. Credits screen: a "Credits" button in `main_menu.gd` (next to "How to play", same pattern as
   `_build_howto`) opening a scrollable panel with the credits text and a Back button.
   The text comes from a copy of root `CREDITS.md` at `godot/content/credits.md`, committed; add it
   to the preset's `include_filter` (`content/family_names.cfg, content/credits.md`), and make
   `autobuild/build.mjs` refresh the copy from `CREDITS.md` before exporting. Show it in a
   RichTextLabel with the `#` heading markers turned into bold lines; no other markdown parsing.
   A missing file shows "Credits: see CREDITS.md".
4. Store-page checklist: new `STORE_CHECKLIST.md` at the root: what a Steam page needs (capsule
   images at Steam's sizes, 5+ screenshots, trailer, short and long description, tags, system
   requirements from P7-2's numbers, age rating questionnaire, price, the Steamworks app fee and
   partner account — both the user's to do, see BLOCKED.md). Each line: what, size/format, status
   (have / to make / user only). Look up sizes from memory; mark them "check on Steamworks" since
   nothing can be fetched or published.
5. Check that `CREDITS.md` covers every row in `ASSETS.md` that needs credit (CC0 rows credited as
   courtesy, as it already does); add missing ones.

**Already decided**
- `CREDITS.md` stays the source; `godot/content/credits.md` is a build-time copy (log in DECISIONS.md;
  undo = delete the copy and the button).
- Credits panel is plain text, same look as the How to play panel. Not REVIEW.
- No store text is posted anywhere; the checklist is a file in the repo only.

**Files likely touched**
`README.md`, `godot/PLAYTEST.md`, `godot/game/greybox/main_menu.gd`, `godot/content/credits.md`
(new), `godot/export_presets.cfg`, `autobuild/build.mjs` (from P7-1), `STORE_CHECKLIST.md` (new),
`CREDITS.md`, `PROGRESS.md`, `PLAN.md`.

**Done means**
- A headless `--menu` run prints no script errors (the credits file loads).
- If P7-1's `build.mjs` exists, one run ends `BUILD: ok` with the credits file inside the export
  (the smoke run is enough; do not inspect the pck by hand).
- Full `node autobuild/verify.mjs` once at the end: healthy.

**Do NOT**
- Capture frames of the menu or credits panel.
- Delete or rewrite `client/`, `server/` or their docs beyond moving the README section.
- Contact Steam, create accounts, publish, or put the user's name or email in any doc.
- Tag `v0.1.0-rc1` (that is P7-4).
