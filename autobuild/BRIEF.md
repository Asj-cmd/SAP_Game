# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

## P4-3 — Jail run-in-place

**Approach**
1. Check what the sim already does for a captured actor (`MovementSystem._resolve`): velocity zero, stance forced
   STANDING, state HELD; `handle` still records `move_intent` and `crouch_intent` ("a held actor may keep sending
   intent"). `jump_intent` is set by `handle` and never spent while captured, so it would fire on release: confirm
   that by reading, then fix it in step 2.
2. Sim, small: in the captured branch of `_resolve`, when `jump_intent` is set, clear it and add 1 to a new
   `SimEntity.held_jumps: int` (kept 0–255, reset to 0 on release). It is state, so every machine agrees and
   presentation can see a jailed jump of ANY player as a change in the number. Add it to `duplicate_entity`, the
   digest and the snapshot (`FORMAT` + 1). One table case in `tests/movement_system_test.gd`: a captured actor
   that sends move, crouch and jump does not change position, and does not jump on the tick it is released.
3. Presentation, `FigureAnimator.base_clip`: for a captured body, choose from its intents instead of `idle`:
   intent past the deadzone → `jog` in place (`crouch_walk` if `crouch_intent`), none → `idle` / `crouch_idle`.
   Playback rate as if moving at `move_speed` (or the crouch speed). The body stays on the holding spot.
4. Facing: a jailed body turns toward its `move_intent` (see `_face` in `greybox_main.gd`); with no intent it
   keeps its last facing.
5. Jump in place: when `held_jumps` changes, play `jump_start` → `jump_air` → `jump_land` with a drawn-only
   vertical hop (peak about 60, about 0.5 s) added in `_view_offset` / `_drawn_height`; the sim's y does not move.
6. Camera: confirm the mouse still turns the chase camera while jailed (`chase_camera.gd`,
   `local_player_input.gd`); fix if it is frozen.
7. Shoot a sheet of a jailed body, and one chase frame from inside the pen.

**Already decided**
- Jailed inputs never reach position: no sim movement, no real jump, no collision change. The only sim changes are
  the `jump_intent` clear and the `held_jumps` counter. Log both in `DECISIONS.md`; log the look of the
  run-in-place as **REVIEW**.
- Own body reads the predicted world (answers the key at once), others the confirmed world, as `_animate` does.
- Jailed bodies never play `panic_run`, however long forward is held (the sim count is 0 while captured, P4-1).
- A jailed body carries nothing, so no `carry_*` clips here.
- The hop is drawn only and smaller than a real jump (60 against about 200), so it stays inside the 220 pen.
- Crouch in jail is drawn through the crouch clips only; the sim's stance stays STANDING.

**Files likely touched** (all exist)
- `godot/sim/systems/movement_system.gd`, `godot/sim/core/sim_entity.gd`, `godot/net/world_snapshot.gd`
- `godot/sim/systems/capture_system.gd` (only to reset `held_jumps` on release, if that is where release happens)
- `godot/game/art/figure_animator.gd`, `godot/game/greybox/greybox_main.gd`
- `godot/game/greybox/chase_camera.gd`, `godot/game/greybox/local_player_input.gd` (only if the camera is frozen in jail)
- `godot/tests/movement_system_test.gd`, `godot/tests/snapshot_test.gd`, `autobuild/test_baseline.json`
- `autobuild/frames/p4_3/` (new folder), `DECISIONS.md`, `PLAN.md`, `PROGRESS.md`

**Done means**
- Test case green: captured + move/crouch/jump commands → position unchanged over 60 ticks, and no jump on release.
- `autobuild/frames/p4_3/jail_sheet.png`: a contact sheet following a jailed body whose keys are pressed
  (`--capture-follow` with `--capture-press`, or a bot's jailed body with `--anim-log` if the local seat cannot be
  jailed on cue; the pilot `--pilot` gets seized in about half its runs). The cells must show a jog cycle with the
  feet moving and the body at the same spot in every cell, a crouched cell, and a hop cell with the feet off the floor.
- `autobuild/frames/p4_3/jail_chase.png`: the chase view of the jailed local body, bars visible, body not hidden.
- Bot match numbers at 3v3 seed 1 and 1v1 unchanged (bots send no jump; if they moved, say why).
- `node autobuild/verify.mjs` ends `VERIFY: healthy` (once, before committing).

**Do NOT**
- Do not let a jailed body move, slide, push others, or block the pen (held actors stay non-solid).
- Do not change jail times, the holding spot, the pen or any zone.
- Do not add a struggle meter, button mashing to escape, or any way out other than the timer and a rescue (D9).
- No bot behaviour for jailed bots, no sweeps, no new test file.
- No effects, shouting, or expressive acting on the jailed body (D2).
