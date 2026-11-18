# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

## PT2-3 — Audio settings

**Approach**
1. Buses: in `godot/default_bus_layout.tres` add bus 3 `Footsteps` (send `Master`). `SFX` and `Music` already exist.
2. `GameAudio` (`godot/game/audio/game_audio.gd`): add an optional `"bus"` key to `EVENTS` rows (default `&"SFX"`);
   `&"step"` gets `&"Footsteps"`. In `play` / `play_flat`, set `player.bus` from the row before `play()` (the pool
   players currently all sit on SFX). Music stays on `Music`, UI clicks on SFX. PT2-4's new events just add rows.
3. `PlayerSettings` (`godot/game/greybox/player_settings.gd`): add `footsteps_volume` default 0.4; extend
   `set_volume` / `volume_of` / `apply_audio` (bus list gains `&"Footsteps"`), `_load` / `save` under `[audio]`
   key `footsteps`, clamped 0..1. A value of 0 mutes the bus (already how `apply_audio` treats 0).
4. To make it testable without touching the real file: add `load_from(path)` / `save_to(path)` (the existing
   `_load` / `save` call them with `PATH`).
5. `SettingsPanel` (`godot/game/greybox/settings_panel.gd` ~lines 28–32): label the rows Master, **Music**,
   **Effects**, **Footsteps** (footsteps row after effects), same slider helper.
6. New test `godot/tests/player_settings_test.gd`, table-driven: rows of (written cfg text or values → expected
   volumes after load), covering defaults when the file is missing (footsteps 0.4), save→load round trip,
   footsteps 0 stays 0, out-of-range values clamped, missing `footsteps` key in an old file → 0.4. Use
   `user://settings_test.cfg` and delete it after. Pin its count in `autobuild/test_baseline.json` (`--update-baseline`).

**Already decided**
- Footsteps are independent of Effects (Footsteps → Master, not → SFX). Only `step` goes on Footsteps; `land` stays an effect. REVIEW (one row).
- Master slider stays.
- The test of a `game/` class is an exception the PLAN asks for; say so in the DECISIONS log row.

**Files likely touched**
- `godot/default_bus_layout.tres`, `godot/game/audio/game_audio.gd`, `godot/game/greybox/player_settings.gd`,
  `godot/game/greybox/settings_panel.gd`
- `godot/tests/player_settings_test.gd` (new), `autobuild/test_baseline.json`
- `DECISIONS.md`, `PROGRESS.md`, `PLAN.md`; `godot/PLAYTEST.md` / `HOW_TO_PLAY.md` if they list the settings

**Done means**
- `player_settings_test` passes and is pinned; full `node autobuild/verify.mjs` ONCE at the end: healthy.
- A headless `--menu` run through `run_game.mjs` prints no script errors.
- No frames.

**Do NOT**
- Add music, jingles or new sound files (that is PT2-4).
- Restyle the settings panel (PT2-6 does the UI art).
- Touch the sim, bots or network; no sweeps, no frames.
