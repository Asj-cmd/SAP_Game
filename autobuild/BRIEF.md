# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

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
