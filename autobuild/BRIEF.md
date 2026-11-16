# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

## P4-2 — Presentation for jump, crouch, carry and throw

**Approach**
Most of this was built in P2-2/P2-3 (`FigureAnimator`, the `carry_*` clips, the arms-only throw). This task is an
audit by contact sheets of live bodies against D9, then fixes to what the sheets show.
1. Shoot one sheet per verb into `autobuild/frames/p4_2/` with `--capture-follow` (see `godot/CLAUDE.md`):
   jump (`--capture-press=SPACE@…`, standing and at a jog), crouch idle and crouch-walk (`SHIFT`), grab and carry
   (idle, jog, crouch, jump), throw (`on:throw`), and the panic run from P4-1.
2. Open every sheet with Read and write down what each shows against the D9 line for that verb.
3. Fix in this order, re-shooting only the sheet concerned:
   a. Landing: D9 wants a tiny wobble. Today `jump_land` plays only when the body lands and stays still. Add a
      short procedural settle (a dip of the drawn body, no sim change) that also plays when landing at a run.
   b. Crouch-walk plays at about ×4.07 since P0-11 (DECISIONS 2026-11-14 `MAX_RATE`). Judge it in the sheet.
   c. Carry: the bundle must sit on both hands above the head in every carry clip, flat like a brick, with the
      arms straight and still (`_hold_carried`, `hands_point`, `CARRY_HAND_LIFT` in `greybox_main.gd`).
   d. Throw: both hands push forward as the bundle leaves; the bundle must not pop from the hands to the sim's
      position on the first flight frame.
4. Check the fallback bodies (capsule, `figure_model = ""`) still draw the crouch squash and the overhead bundle.

**Already decided**
- Presentation only: nothing in `sim/`, `content/` or `net/` changes. Motion is read from the predicted world for
  the local body and the confirmed world for everyone else, as `_animate` does now.
- Landing settle: the drawn figure dips 6 and returns over 0.2 s, once per landing, no overshoot, no squash and
  stretch (D2: no cartoon acting). A theme or animator constant; log as **REVIEW**.
- Crouch-walk: if ×4 reads as a fault (blurred legs, feet not readable), cap that clip's rate at 2.5 and accept
  a small foot slide; say which in `DECISIONS.md` as **REVIEW**. Do not change the crouch speed.
- Jump keeps one held air pose with stiff hanging arms; the carry jump keeps the cash overhead.
- Standing still stays fully motionless (D9): the settle must end in the exact idle pose.
- The bundle's tumble and bounce is P4-5, not this task.

**Files likely touched** (all exist)
- `godot/game/art/figure_animator.gd`, `godot/game/greybox/greybox_main.gd` (`_animate`, `_hold_carried`, `_drawn_height`)
- `godot/tools/build_figure_anims.gd` and `godot/art/characters/figure_anims.res` only if a clip itself is wrong
- `godot/art/theme/default_theme.tres` / `godot/game/art/art_theme.gd` if a number becomes theme data
- `autobuild/frames/p4_2/` (new folder), `DECISIONS.md`, `PLAN.md`, `PROGRESS.md`

**Done means**
- Sheets in `autobuild/frames/p4_2/`, each opened and described in `PROGRESS.md` (what is seen, not what should be):
  `jump_stand`, `jump_run`, `crouch`, `carry`, `carry_jump`, `throw`, `panic`.
- In them: lift-off, one air pose and a landing dip are three different cells; a crouched body is clearly lower
  than a standing one and its feet are on the floor; the bundle is above the head on the hands in every carry
  cell, including crouched and in the air; in the throw sheet the hands are forward in the cell where the bundle
  first leaves them.
- One chase-camera frame of the local body carrying (`--capture-chase`), to confirm the bundle is visible from behind.
- `node autobuild/verify.mjs` ends `VERIFY: healthy` (once, before committing).

**Do NOT**
- No sim, tuning or network change; no new sim events for presentation's sake.
- No ragdoll, stumble, knockback, squash and stretch, dust puffs, trails or any effect (D2, D9).
- No idle animation. No new facial or expressive acting.
- No tests for presentation (`godot/CLAUDE.md`), no bot work, no sweeps.
- Do not rebuild the animation set or swap clips unless a sheet shows the clip itself is the fault.

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
