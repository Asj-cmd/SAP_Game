# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

## P4-6 — Bots and panic run

**OUT OF DATE (2026-11-16, user's playtest).** This brief was written before P4-8, which now runs
FIRST and removes the panic speed boost (the run becomes arms-up animation only). With no boost
there is nothing for bots to gain from holding `forward`, so do NOT add `panic_min_run` or a
`_wants_forward` rule. Read PLAN.md's P4-6 note: if `verify.mjs` is healthy after P4-8, tick the
task with that note and delete this section. The rest below is history.

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

## P4-7 — Verb readability audit by frames

**Approach**
1. Do NOT capture anything. Open, with Read, the frames earlier verb tasks already made:
   `autobuild/frames/p4_1/panic_sheet.png`, `p4_2/*` (carry, carry crouch, carry jump, crouch,
   jump run/stand, throw, panic), `p4_3/jail_*`, `p4_4/jail_*`, `p4_5/*` (throw, drop, fence
   throw), and `p4_8/panic_sheet.png` once P4-8 has made it. About 25 images: open one or two per
   verb, not all if the first answers it.
2. For each D9 verb (walk, panic run, jump + landing wobble, crouch-walk, grab, carry overhead,
   throw, seize, free, jail run-in-place, standing still), write one PROGRESS line: readable at a
   glance yes/no, and what is wrong if no. Judge against D2/D9 (deadpan, no acting, arms up when
   panicking, cash stiffly overhead).
3. Fix only small presentation defects you find (a clip pick in `FigureAnimator.base_clip`, a
   pose number, a missing one-shot), at most two, each a few lines in `godot/game/art/`. List
   anything bigger as a follow-up in PROGRESS; do not start it.
4. If nothing needs fixing, the audit itself is the deliverable: tick with the table.

**Already decided**
- The frames are evidence from before P4-8 (except the P4-8 sheet): a panic sheet showing 648 is
  the old boost, not a defect now.
- Seize and free have no sheet of their own in `p4_*`. Use `autobuild/frames/p2_3/` (seize,
  free), if present. If there is no frame, write "not seen". Do not shoot one.
- Any fix that changes a pose or clip is logged in DECISIONS.md as REVIEW.

**Files likely touched**
- `PROGRESS.md`, `PLAN.md`; maybe `godot/game/art/figure_animator.gd`,
  `godot/tools/build_figure_anims.gd` (only if an arm pose needs a number changed; re-run it to
  rebuild `art/characters/figure_anims.res`)

**Done means**
- A per-verb table in PROGRESS (verb, frame looked at, readable?, what is wrong).
- If code changed: `node autobuild/verify.mjs` once at the end, `VERIFY: healthy`. If only docs
  changed, no verify run is needed (no code touched).

**Do NOT**
- New captures, contact sheets, follows or pilots (testing diet: P4-7 is not one of the four
  capture tasks).
- Sim changes, new verbs, ragdoll/knockback, bot work.
- Rework animations wholesale or re-pick clips the user has not asked about.
