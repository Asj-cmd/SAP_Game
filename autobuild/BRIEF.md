# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

## PT4-8 — Bots catch thieves (last)

REDO (from PT2-8):
REDO: The younger boy's (`casual`) crest reads from the front (`autobuild/frames/pt2_8/lineup_front.png`, leftmost figure) as a wide black dome covering the whole top of his head, not as a mohawk. In the side frame it looks like a black helmet. The elder boy's narrow blade is right. Narrow the younger boy's ridge base only: pass his own base half-width in `autobuild/rerig_family.mjs` (about 0.14–0.18 head widths, near the elder boy's look; keep the 13 cm height), re-run `rerig_family.mjs --only=casual`, and check by measuring (crest width at its base vs head width, under 0.4) and the triangle count (under 5,000). Numbers only, no frames: PT4-8 is not a frame task. Dad and the other four bodies stay byte-identical.
REDO: The elder girl's (`alt`) pigtails hardly differ from the front: one hangs to her collar and the other is barely visible. Make the short side clearly splayed (about 35–40° out instead of 22°, and about 30 % shorter than the long side) in the same `_build_hair` numbers, re-run with `--only=alt`, and check by the numbers (tip offsets left vs right). No frames.
Do both REDOs first, then commit them on their own (`PT2-8 REDO: ...`) before starting the bot work.

**Approach**
1. Read `godot/sim/ai/bot_director.gd` (`_candidates`, `_decide`, `_destination_of`, `_plan`, `_steer`, `_act`), `godot/sim/ai/utility_scorer.gd` and `godot/content/ai/bot_profile_def.gd`. What a quick read found:
   - A carrying bot never defends. DEFEND tasks ARE offered while carrying (the actor loop sits outside the `is_carrying()` branch), but `value_deposit` is 100000 against `value_defend` 4000, so DEPOSIT always wins.
   - A thief carrying our cash is valued the same as any intruder (4000, below RESCUE's 6000).
   - Pursuit aims at `target.position` (`_destination_of`). The route is re-planned only on the decide (0.4 s) and repath (0.9 s) timers, so the bot trails behind.
   - `CaptureSystem` lets a carrier seize: there is no captor-carrying check. So a carrying bot does not have to drop anything to seize.
2. **Measure first: build the staged chases before changing the bot.** Add a `--chase` mode to `godot/tools/bot_match.gd` that stages scenarios on the real house level (3v3 seats, the other bodies parked in their jails or held still out of the way):
   - (A) A human-like runner: a seat with no BotDirector, sent `MoveCommand`s along `nav.route` to its own cash room at carry speed, holding the defender family's cash. It starts 300–500 from one bot defender on the defender's side. Try 8 start spots from a fixed table, not seeds.
   - (B) The same runner crossing past the defender sideways, toward the nearest gate (this is the cut-off case).
   - (C) A carrying bot heading home that meets an intruder 200–400 from it on its own side, 8 spots.
   - (R) The reverse, for the "about as often" goal: a scripted pursuer that steers straight at a bot thief carrying cash, 8 spots.
   Each prints `caught N of 8` and the mean time to catch. Run it on the old code and write the numbers down.
3. Thief priority. In `_decide`, compute a per-task bonus and pass it to `UtilityScorer.score` as one new `bonus: float` argument, so the scorer still has no numbers of its own. A DEFEND whose target carries a carriable whose `origin_position` lies in a zone owned by `me.team` gets `profile.thief_bonus`. A DEFEND whose target is within `profile.alert_radius` (flat) of me gets `profile.alert_bonus`.
4. Defending while carrying. In `_candidates`, while carrying, offer a DEFEND only when its target is within `alert_radius`. Such a DEFEND gets `profile.value_deposit` added to its bonus, so it beats banking. The bot then seizes while still holding the cash (the rule allows it), and DEPOSIT comes back on the next decision.
5. Cut-off pursuit. In `_destination_of`, for DEFEND, aim at a lead point: `target.position + target.velocity * t`, with `t = clamp(flat_distance / my_speed, 0, profile.lead_max_seconds)`. Snap it to a stance with `nav.stance_near`. If the stance is unreachable, aim at the target itself.
6. Close in straight. In `_steer`, while DEFEND's target is within `profile.close_in_radius` and `world.collision.blocks_segment` (chest height, as `CaptureSystem._reach_blocked` does) shows a clear line, steer straight at the lead point instead of following the route. While chasing, re-plan on `profile.chase_repath_seconds` instead of `repath_seconds`.
7. Re-run `--chase`, write before and after counts for A, B, C and R in `PROGRESS.md`. If A and B are still well under R, tune only the new fields (at most two tries), then stop.
8. Add the decision cases to `godot/tests/bot_director_test.gd` as one table-driven `_test_pursuit`:
   - a thief carrying our cash outranks RESCUE;
   - a carrier picks DEFEND for an intruder inside `alert_radius`, and DEPOSIT for one outside it;
   - "decide/carrying means depositing" still holds with nobody near;
   - the lead point is ahead of a moving target and equals its position when the target stands still.
   Ratchet `autobuild/test_baseline.json` for the new check count.
9. Full `node autobuild/verify.mjs` once at the end. bot_match will play differently: it must stay deterministic with a winner and inside its stall budgets. Update only the expected numbers that are allowed to move. Tick, commit.

**Already decided**
- The rules do not change. A carrier may already seize, so the bot does NOT drop the cash to seize: the task's "drops the cash if that is better" is met without a drop. Log it in DECISIONS (plain log, not REVIEW).
- New `BotProfileDef` fields, with these defaults, in the profile data and not in code: `thief_bonus` 7000 (so a thief DEFEND, 11000, beats RESCUE 6000), `alert_radius` 450, `alert_bonus` 2500, `lead_max_seconds` 0.8, `close_in_radius` 350, `chase_repath_seconds` 0.3. Log these numbers in DECISIONS as **REVIEW** (tuned against staged chases, not humans).
- "Our family's cash" means the carriable's `origin_position` lies in a zone owned by the bot's team (read `world.zone_at(origin_position)`). Do not add a new field to `SimEntity`.
- Keep the existing BotTask kinds (DEFEND covers the chase). Do not add an INTERCEPT kind; it would touch claims, keys and `_act` for nothing.
- `--chase` is a tool mode, not a verify gate (like the sweeps and `twin_probe`). Its counts go in `PROGRESS.md`. The pinned cases are the unit-level ones in `bot_director_test`.
- Update the "Backlog: bots" note only to say PT4-8 is done. The rest stays deferred.

**Files likely touched**
- `godot/sim/ai/bot_director.gd`
- `godot/sim/ai/utility_scorer.gd`
- `godot/content/ai/bot_profile_def.gd` (and `bot_profile_standard.tres` only if values must be set there)
- `godot/tools/bot_match.gd` (`--chase`)
- `godot/tests/bot_director_test.gd`
- `autobuild/test_baseline.json`
- `autobuild/metrics_budget.json`, only if a pinned bot_match number legitimately moves
- `DECISIONS.md`, `PLAN.md`, `PROGRESS.md`
- For the REDOs: `autobuild/rerig_family.mjs`, `godot/tools/rerig_character.gd`, and the re-rigged `casual` and `alt` files under `godot/art/characters/`

**Done means**
- `bot_match --chase` before and after counts are in `PROGRESS.md` for A, B, C and R.
- After the change, A and B each catch at least 5 of 8 and no fewer than R minus 1.
- C seizes in at least 6 of 8 without dropping the cash.
- `bot_director_test` passes with the new `_test_pursuit` cases, and the baseline is ratcheted.
- The full `node autobuild/verify.mjs`, run ONCE at the end just before the commit, ends `VERIFY: healthy`. That covers: all suites at their pins, symmetry 190 of 190, bot_match 3v3 and 1v1 deterministic with a winner and within their stall budgets, the tick budget at 1v1 and 3v3 at most 5 of 600, and net_smoke agreeing.

**Do NOT**
- No sweeps, no seed sweeps, no `side_sweep.mjs`. Do no balance tuning of the existing weights (`risk_weight`, `value_*`, mode files). Only the new fields may be tuned, at most twice.
- Do not change `CaptureSystem`, `MovementSystem`, capture range, speeds or any rule; do not touch the snapshot or network.
- Do not give bots knowledge a player lacks (no reading another bot's task or a human's input); `velocity` and position of a visible body are fair.
- No new test files, no frames, no captures (the REDOs above are checked by numbers).
- Do not start the deferred "Backlog: bots" items (P3-3d/e/f and the rest).
- Do not run the full verify at the start or more than once.
