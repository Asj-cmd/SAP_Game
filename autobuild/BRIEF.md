# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

## PT2-1 — Stair gap

**Approach**
1. Measure first, no frames: in `godot/tools/build_house.gd`, the indoor flights are `_straight_flight`
   (12 treads of RUN 48, first riser STAIR_LANDING 120 past the base, top tread top = GROUND + STOREY = UPPER)
   and the hole in the upper slab is `_stairwell(...)`, passed to `_slab_at` from `_upper()` (~line 584).
2. The likely cause: `_stairwell` grows the hole by BODY (20) past BOTH ends of the footprint, so at the
   TOP end there is a 20-unit strip with no slab between the last tread and the upstairs floor. Work out
   the exact numbers (top tread's far edge vs the hole's far edge, slab top vs tread top) for stair A
   (dir +1) and stair B (dir −1) and write them in PROGRESS.md.
3. Fix: stop growing the hole at the TOP end only (keep the growth at the base end and on the open flank).
   The top tread and the slab are at the same height, so a body overhanging there stands on floor, not in it.
   If the numbers show a different cause (slab top ≠ tread top, an off-by-one RUN), fix that instead.
4. Check the outside back staircase (`_back_stair`): top step spans PLATFORM_X1..+RUN at UPPER, platform
   is PLATFORM_X0..PLATFORM_X1 with top UPPER − SLAB + SLAB = UPPER; also check the platform meets the
   Landing B door's sill (no strip between platform and the wall/door opening). Fix only if a gap is measured.
5. Re-bake the level: run `tools/build_house.gd` through `node autobuild/run_tool.mjs` (writes
   `res://game/blockout/house.tscn`). The shell (`game/art/shell_builder.gd`) and nav are built from the
   blockers at load, so they follow; check nothing in the shell hard-codes the old hole size (handrails /
   string boards near the top of each flight).
6. Run the content validator / symmetry probe only via the final full verify.

**Already decided**
- The staircase positions do not move (task says so). Only the hole's top edge (or whatever the measured cause is) changes.
- No banister or collision added at the top; the open flank stays open (see the long comment above `_straight_flight`).
- Log one line in `DECISIONS.md` (not REVIEW): "PT2-1: stairwell hole no longer grown past the top tread; why; undo = restore the `+ BODY` on that end".

**Files likely touched**
- `godot/tools/build_house.gd` (`_stairwell`, maybe `_back_stair`)
- `godot/game/blockout/house.tscn` (re-baked output)
- `godot/game/art/shell_builder.gd` (only if it derives the stair opening itself)
- `DECISIONS.md`, `PROGRESS.md`, `PLAN.md`

**Done means**
- The measured before/after numbers for both indoor flights and the back stair are in PROGRESS.md (gap 0).
- Full `node autobuild/verify.mjs`, run ONCE at the end before committing: healthy; symmetry probe exact
  (190 of 190 or whatever it prints now, all twins); bot matches deterministic with a winner; tick budget within limits.
- No frames.

**Do NOT**
- Move the stairs, change STEP/RUN/STOREY, or add walls next to treads (the comment explains five failed tries).
- Touch bot steering, run sweeps, capture frames, or add test files.
- Break the twin: both houses come from the same `_draw_house` placed twice; never special-case one house.

## PT2-2 — Remove the panic run; add a "spotted" startle

**Approach**
1. Remove from the sim: `MovementSystem.is_panicking`, `_panic_ticks`, the `forward_ticks` count and
   `forward_held` in `sim_entity.gd` (fields, copy, serialisation ~line 247), their reset in `sim_world.gd`
   (~line 356), `panic_after_seconds` in `content/tuning/tuning_def.gd` and any `.tres` that sets it.
   Nothing else uses the forward flag, so also remove `MoveCommand.forward` / `pushing_forward` and its codec
   field, and where `local_player_input.gd` sets it. Bots never set forward: there is no bot code to remove.
   Keep `home_speed_scale` 1.08 exactly as it is.
2. Snapshot: bump `FORMAT` in `godot/net/world_snapshot.gd` by one with a comment line ("N: forward_held /
   forward_ticks removed, PT2-2"). Update `snapshot_test.gd` and `command_codec_test.gd` rows that pinned them.
3. `movement_system_test.gd`: delete `_test_panic_run` and the `"panic"` keys in the home-speed and wall rows
   (the head-on rows keep their gaps at plain walking speed; rename them "head-on runners"). Keep the
   home-factor rows. Suites shrink, so lower their counts in `autobuild/test_baseline.json` BY HAND
   (`--update-baseline` only raises) and say which and why in PROGRESS.md.
4. Animation: remove `panic_run` / `arms_panic` from `tools/build_figure_anims.gd` CLIPS and the arm pose,
   re-run it to rebuild `art/characters/figure_anims.res` (+ `figure_anims.json`); remove the `panicking`
   argument from `FigureAnimator.base_clip` / its caller in `greybox_main.gd` (~line 1607).
5. Startle (presentation only, in `game/`): each frame, from the confirmed world, for each actor carrying a
   bundle, find any actor of the bundle's `team` (the family whose cash it is) that is not captured, within
   SPOTTED_DISTANCE horizontally and |Δy| < 200. First time in the cooldown → trigger "spotted" for that carrier.
6. The jolt: a drawn-only figure offset on the carrier (no new clip): up 10 units over 0.08 s, back to 0 over
   0.42 s, with a 4° lean back of the model root, total 0.5 s; plus `ChaseCamera.nudge` if the carrier is the
   local body. Put it next to the landing settle dip from P4-2 (same pattern).
7. Sound: new `GameAudio` event `&"spotted"` using the existing `sting` file at `pitch_scale` 1.25 (placeholder),
   played flat when the local seat is the carrier OR the defender who spotted them; positional (`play`) otherwise
   is not needed. Log the reuse in `ASSETS.md`. PT2-4 may swap the file.
8. Update D9 in `DECISIONS.md`: the panic-run sentence becomes the spotted startle (presentation only); keep
   the 1.08x home-side row. Fix the panic mentions in `godot/DESIGN_DIRECTION.md` / `PROJECT_MEMORY.md` /
   `HOW_TO_PLAY.md` / `godot/PLAYTEST.md` if they describe it as a feature.

**Already decided**
- SPOTTED_DISTANCE = 600 units (6 m), there was no old "panic distance" (the panic run was time-based only). REVIEW.
- Cooldown: 8 s per carrier, and it also re-arms when that carrier drops or banks the cash (a new carry can be spotted at once). REVIEW.
- No line-of-sight test (simple; a wall between them still startles). REVIEW-note it.
- The startle never feeds back into the sim, bots or network; each machine computes it from its own confirmed world.
- Log the three values above in `DECISIONS.md` as one REVIEW row; also log the snapshot format bump.

**Files likely touched**
- `godot/sim/systems/movement_system.gd`, `godot/sim/core/sim_entity.gd`, `godot/sim/core/sim_world.gd`,
  `godot/sim/systems/move_command.gd`, `godot/content/tuning/tuning_def.gd` (+ `.tres` under `godot/content/tuning/`)
- `godot/net/world_snapshot.gd`, `godot/game/greybox/local_player_input.gd`, `godot/game/greybox/greybox_main.gd`
- `godot/game/art/figure_animator.gd`, `godot/game/art/figure_animation.gd`, `godot/tools/build_figure_anims.gd`,
  `godot/art/characters/figure_anims.res` / `.json` (rebuilt)
- `godot/game/audio/game_audio.gd`, `godot/game/greybox/game_feedback.gd` (good home for the spotted detector)
- tests: `godot/tests/movement_system_test.gd`, `snapshot_test.gd`, `command_codec_test.gd`; `autobuild/test_baseline.json`
- `DECISIONS.md`, `ASSETS.md`, `PROGRESS.md`, `PLAN.md`

**Done means**
- `grep -ri panic godot/sim godot/net godot/game godot/content godot/tools` finds nothing but history comments (ideally nothing).
- Full `node autobuild/verify.mjs` ONCE at the end: healthy, including net_smoke (all ticks agree) and net_loopback/lobby;
  bot matches deterministic with a winner; the lowered pins in test_baseline.json match the new counts.
- A headless `--solo` run through `run_game.mjs` prints no script errors (cheap check for the presentation code).
- No frames.

**Do NOT**
- Add a speed change of any kind to the startle, or touch `home_speed_scale` / the 0.85 carry factor.
- Write a test for the startle (presentation; testing policy). No new test files.
- Bot tuning, sweeps, frames, or a new animation clip / IK pose for the jolt.

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
