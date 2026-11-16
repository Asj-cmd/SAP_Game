# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

## P4-5 — Cash tumble and bounce after a throw or drop

**Approach**
1. Read `godot/sim/systems/carry_system.gd` (`_try_throw`, `_advance_flight`, `_land`: a fixed arc,
   "no bounce and no roll", `in_flight` goes false where it first hits) and, in
   `godot/game/greybox/greybox_main.gd`, `_render`, `_release_blend`, `_face` (check whether it yaws
   bundle views too), `_hold_carried`, `_place_contact_shadows`.
2. New small class `godot/game/art/bundle_tumble.gd` (`BundleTumble`, RefCounted, typed): per bundle
   id it keeps spin angle, spin axis, last in-flight velocity, and a bounce timer. One call per
   frame per loose bundle from `_render`: `update(id, entity, delta) -> {lift: float, basis: Basis}`.
3. While `in_flight` and not held: spin about the horizontal axis at right angles to the flat
   velocity (it tumbles end over end, forward). A drop or a seized carrier's bundle (flat speed under
   40) gets a quarter of the spin rate about a fixed axis.
4. On the frame `in_flight` goes true → false (not picked up): start the bounce: a lift on a
   parabola, then a second smaller one, while the rotation eases to the nearest FLAT pose (a multiple
   of 180° about the spin axis) so it always ends lying flat exactly as it does today.
5. Apply: `view.position.y += lift` (after `_release_blend`), `view.basis` = yaw × tumble. x and z
   are never offset. When the bounce ends, lift is exactly 0 and the basis exactly the resting one.
   Held or picked up mid-bounce: state cleared at once, `_hold_carried` owns the bundle.
6. Shoot the sheets, open them, adjust numbers once, verify, PROGRESS, DECISIONS, tick, commit.

**Already decided** (log the numbers as one REVIEW line)
- Presentation only. The sim's "stops where it first hits" stays; the drawn bundle is at the sim's
  x/z every frame and at the sim's y at rest. Read `in_flight` / held from the CONFIRMED world
  (`truth`), as `_animate` does, so a guest draws the same.
- Tumble: 540°/s on a throw (about 1.5 turns over a full arc); 135°/s on a drop.
- Bounce: first lift peak = clamp(landing speed × 0.02, 4, 14) units over 0.22 s; second = 30 % of
  that over 0.12 s; then nothing. Lift is never negative (never under the floor). A drop from the
  hands gets the low end (about 4–6): "bounces a little" (D9), subtle and short.
- No sound (P5-3), no dust or particles (D2), no squash and stretch, no roll along the floor.
- The contact shadow already reads drawn positions and fades with height: leave it; check in the
  sheet that it stays on the floor under the bouncing bundle.
- Constants live in `BundleTumble` (`SPIN_THROW`, `SPIN_DROP`, `BOUNCE_*`); setting `BOUNCE_PEAK_MAX`
  and the spins to 0 is the undo.
- Bundles on a 120 furniture top bounce the same; nothing special-cased by location.

**Files likely touched**
- `godot/game/art/bundle_tumble.gd` — new
- `godot/game/greybox/greybox_main.gd` (`_render`, a field for the tumble state)
- `DECISIONS.md`, `PROGRESS.md`, `PLAN.md`

**Done means**
- Sheets in `autobuild/frames/p4_5/`, opened with the Read tool and described cell by cell:
  - `throw_sheet.png`: own body, `--pilot=carry` + `--capture-follow=on:grab:me,<≥30 cells>,0.06,side,<dist>`
    + `--capture-press=RMB@2.0` (as P4-2's throw sheet; widen the distance or use another view until the
    landing is in frame). Must show: the bundle at a different angle in successive flight cells, a
    visible small hop after first contact, then lying flat and still with its shadow under it.
  - `drop_sheet.png`: same with `LMB@2.0`: a short fall, one tiny hop, flat.
  - One chase frame of a bundle at rest after a throw: flat, not tilted, not sunk in or floating.
- Print or note for one throw: the drawn x/z equals the sim's on every cell, and lift = 0 at rest.
- `node autobuild/verify.mjs` healthy, with the bot match numbers UNCHANGED from P4-4 (nothing in
  `sim/` moved; if they changed, something leaked into the sim).

**Do NOT**
- Touch `sim/`, `net/`, `content/`, the snapshot, or add a bounce to the rules.
- Offset x/z, or let the drawn bundle rest anywhere but the sim's position.
- Tests (presentation is verified by eye), new test files, bot work, sweeps.
- RigidBody3D or any physics node; confetti, trails, glow, cartoon effects.
- Rework `_release_blend` (P4-2) beyond adding to its result.

## P4-6 — Bots and panic run

**Approach**
1. Read `godot/sim/ai/bot_director.gd`: `_steer`, `_send_intent` (the one place a bot's
   `MoveCommand.move(actor_id, intent, tick)` is made; bots never set `forward`), `_has_reached`,
   `_drop_pending`; and `godot/sim/systems/move_command.gd` (4th argument `pushing_forward`), and
   the panic rules in `movement_system.gd` (`forward_ticks`: grows after 2 s of forward, resets on
   letting go, stopping, BLOCKED, crouch, seizure).
2. Add one pure function in `BotDirector`, e.g. `_wants_forward(me, waypoint, world) -> bool`, and
   pass its result from `_steer` to `_send_intent`.
3. Add `panic_min_run: float = 500.0` to `godot/content/ai/bot_profile_def.gd` (0 = bots never
   panic-run).
4. Table rows in `godot/tests/bot_director_test.gd` for the decision only (far level waypoint →
   true; near → false; waypoint above/below → false; drop pending → false; `panic_min_run` 0 →
   false). Ratchet the pinned count.
5. Run `node autobuild/verify.mjs` once. Read the bot match lines: winner, deterministic, stalls
   against the budget in `autobuild/metrics_budget.json`, tick budget.
6. One follow sheet of a bot to see the arms-up run actually happens, PROGRESS, DECISIONS, tick.

**Already decided**
- The rule: a bot holds `forward` only while the flat distance to its CURRENT waypoint is over
  `panic_min_run` (500), the waypoint is within one `step_up_height` of its own height (not on a
  stair, not a drop), and `_drop_pending` is false. Everything else sends `forward = false`, so the
  sim drops the boost before the bot reaches a corner, a door or a stair (letting go resets the
  count). Because the boost needs 2 s of unbroken forward, this only shows on long straights (yards,
  the lot), which is where a person would do it. Carrying bots follow the same rule.
- No use of the panic run as a TACTIC (chasing, fleeing, scoring): the task says only so they do not
  break. No change to decisions, scores, routes, arrival radius or give-way.
- A step at 648 is 21.6 a tick against the arrival radius of 30: no overshoot handling needed. If the
  match shows bots orbiting a waypoint anyway, raise `panic_min_run` to 800, once.
- If verify is not healthy after two attempts (no winner, stalls over budget, tick budget, symmetry):
  set `panic_min_run = 0` in `content/ai/bot_profile_standard.tres` / the default (bots do not
  panic-run), keep the code and tests, log it in DECISIONS.md and tick the task: "may use" allows off.
- The stall and other budgets in `metrics_budget.json` are NOT loosened to pass. If the new numbers
  are healthy but differ, record them in PROGRESS; do not re-pin the budget tighter either.
- Log as REVIEW: bots panic-run on long level straights (the user will see arms-up bots).
- No snapshot or wire change: `forward` is already on `MoveCommand`.

**Files likely touched**
- `godot/sim/ai/bot_director.gd`
- `godot/content/ai/bot_profile_def.gd`, maybe `godot/content/ai/bot_profile_standard.tres`
- `godot/tests/bot_director_test.gd` (existing), the pinned test baseline
- `godot/PROJECT_MEMORY.md` only if it states "bots never set forward" (Grep `forward`)
- `DECISIONS.md`, `PROGRESS.md`, `PLAN.md`

**Done means**
- New table rows pass; count ratcheted.
- `node autobuild/verify.mjs` ends `VERIFY: healthy`: 3v3 and 1v1 bot match deterministic with a
  winner, stalls within the existing budgets, tick budget ≤ 5 of 600 at 1v1 and 3v3, symmetry, net
  smoke. Old and new bot match numbers (time to win, stalls, captures) both written in PROGRESS.
- One sheet `autobuild/frames/p4_6/bot_panic_sheet.png` (`node autobuild/run_game.mjs -- --capture-follow=team_a:1,24,0.5,side,380 --capture-delay=10 --capture-clean ...`),
  opened: at least one cell's printed clip is the panic run with both arms up, on open ground, and
  no cell shows a bot running arms-up into a wall or door frame. If no cell catches it, try another
  slot or delay, twice at most, then say so.

**Do NOT**
- Sweeps (`side_sweep.mjs`), seeds beyond the gate's, balance or `risk_weight` / mode tuning: bots are
  paused by the user (PLAN "Backlog: bots").
- Change `panic_after_seconds` / `panic_speed_scale`, the movement system, or how humans trigger it.
- Make bots jump, crouch or throw.
- New test files; tests of anything but the flag decision.
- Loosen any budget in `metrics_budget.json` or `render_budget.json`.
