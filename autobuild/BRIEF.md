# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

## PT3-2 — Cash sounds are paper

**Approach**
1. Today: `grab` = `grab_1/2.ogg` (rpg-audio cloth1/2) fires in `greybox_main.gd:1663`. `cash` =
   `cash_1/2.ogg` (rpg-audio handleCoins) is the deposit sting (`game_audio.gd:184`). The coin
   clicks are probably the "gun being loaded" the user hears when they drop cash at home. A plain
   drop and a bundle hitting the ground have no sound at all yet. `throw` plays `throw.ogg`.
2. Find CC0 candidates: Kenney packs through `node autobuild/fetch_kenney.mjs` (e.g. "rpg-audio"
   has bookFlip/bookPlace, "impact-sounds" has soft thuds), and OpenGameArt CC0 through
   `autobuild/fetch_url.mjs`. Apply the reject list from the task (click, latch, snap, cock,
   reload, metal) to title and description.
3. Trim each to under 0.6 s with no leading silence, and normalise its peak to the other effects
   (measure with `godot/tools/audio_probe.gd`). Use the PT2-4 decode/encode path for non-OGG sources.
4. Move the replaced files with `git mv` to `godot/art/audio/sfx/retired/` (grab_1, grab_2,
   cash_1, cash_2, plus their `.import`s). Put the new files under the same names, so `EVENTS`
   in game_audio.gd keeps its event names and file lists: `grab_1/2` = paper rustle/flutter,
   `cash_1/2` = soft paper-bundle thud.
5. Add two events, each with one file: `drop` (`drop.ogg`, the thud) and `bundle_land`
   (`bundle_land.ogg`, a quieter thud, may be the same source pitched or trimmed differently).
   In `greybox_main.gd` around line 1654: when `was_carrying` ends and the bundle is in flight
   WITHOUT sideways speed, play `drop` at the carrier. When any bundle goes from `in_flight` to not
   in flight, play `bundle_land` at the bundle's position. That needs a per-bundle `in_flight`
   tracker read from the confirmed world, like `_anim_carrying`, and it is presentation only. A
   deposit keeps playing `cash`.
6. Docs: add a "Cash sounds" line to HOW_TO_PLAY.md (which files under `godot/art/audio/sfx/`,
   OGG, keep the names). Add ASSETS.md rows (old rows marked "retired, not shipped") and
   CREDITS.md + `godot/content/credits.md` rows with the CC0 proof.

**Already decided**
- Event names stay. Two new events, `drop` and `bundle_land`, all on the default SFX (Effects) bus.
- Levels start at the old rows' dB (grab −4, cash −4); `drop` −5, `bundle_land` −7.
- Log the picks in DECISIONS.md as **REVIEW** (unheard).
- Make sure `retired/` is not exported: `art/audio/sfx/retired/*` goes in `exclude_filter` in
  `godot/export_presets.cfg`.

**Files likely touched**
- `godot/art/audio/sfx/` (grab_1, grab_2, cash_1, cash_2 replaced; drop.ogg and bundle_land.ogg new;
  `retired/` new)
- `godot/game/audio/game_audio.gd` (two EVENTS rows), `godot/game/greybox/greybox_main.gd` (drop + landing hooks)
- `godot/export_presets.cfg`, `HOW_TO_PLAY.md`, `ASSETS.md`, `CREDITS.md`, `godot/content/credits.md`,
  `DECISIONS.md`, `PROGRESS.md`, `PLAN.md`

**Done means**
- Every new file is under 0.6 s, measured with `ogg_info.mjs` (numbers in PROGRESS.md).
- A headless `--solo --anim-log` run (~75 s through `run_game.mjs`) prints no script errors.
- Full `node autobuild/verify.mjs` once at the end, just before committing: `VERIFY: healthy`, test
  pins unchanged. No frames. No new test file (audio is never tested, `godot/CLAUDE.md`).

**Do NOT**
- Don't use anything metallic or click-like, or anything not CC0. Don't make accounts.
- Don't delete the old files (retire them).
- Don't change sim, carry, throw physics or the snapshot. The landing is detected from the
  confirmed state, never written back to it.
- Don't retune the other sounds, and don't touch the music (PT3-1).
- Don't shoot frames.
