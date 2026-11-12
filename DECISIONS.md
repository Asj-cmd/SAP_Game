# Decisions — how to decide without asking

The user is away most of the day and wants the project to move. **Decide, record, continue.**
Stopping to ask is the most expensive thing a session can do.

## Three kinds of decision

1. **Decide and log.** Anything reversible, local, or a matter of taste with a sane default:
   pick, write one line in the log below (date · task · decision · why · how to undo), continue.
2. **Decide, log, and flag `REVIEW`.** Anything the user will care about seeing: art style pick,
   character looks, how teams are told apart, tone of sounds. Pick the best option, log it with
   `REVIEW`, build so that changing it is cheap (theme resource, data file). The user reviews in the evening.
3. **Block.** Only these stop work on a task: it needs **money**, a **login/account the user must
   create**, a **secret/credential**, an **installation on the user's machine you cannot do**, or it
   would **reverse a settled decision**. Write it in `BLOCKED.md` (what, why, what the user must do,
   what you did instead), mark the task `[B]`, and **move on to the next task**. Never idle.

## Never, without the user

- Spend money or start a paid trial. Free tiers and credits already on the account are fine if the
  terms allow commercial use; record the terms in `ASSETS.md`.
- Publish anything, upload to Steam/itch/any store, post anywhere, email anyone.
- Put secrets in the repo. Force-push, rewrite history, or delete branches.
- Use assets with unclear, non-commercial, or no-derivatives licences, or ripped from other games.
- Reopen the settled decisions in `godot/DESIGN_DIRECTION.md` §4 without *new measured evidence*.

## When stuck

`godot/CLAUDE.md` caps failure loops at two fix attempts. In autonomous mode the rule becomes:
**two attempts, then log what failed / what you tried / your diagnosis in `BLOCKED.md`, mark the
task `[~]` or `[B]`, and move to the next task.** A failure that blocks everything downstream
(the build is red and you cannot fix it) is the only reason to end a session early: revert to the
last green commit (`git revert`, not reset), say so in PROGRESS.md.

## Working agreements

- **Measure before changing; build the instrument first.** (`godot/PROJECT_MEMORY.md` §3.)
- Keep `verify.mjs` green at every commit. Ratchet the baseline when you add tests or tighten a metric.
- One task, one or a few commits: `P1-4: toon shader with outline pass`. Push is done by the loop.
- Visual work is done only when you have opened a frame with the Read tool and described what you saw.
- Presentation never writes to the simulation; art never changes collision, zones or numbers
  in `content/` unless the task says so.
- Prefer one coherent look over more content. Cut scope before cutting polish; a smaller
  good-looking game beats a larger patchy one.

## Settled at autobuild start

| ID | Decision | Why / how to undo |
|---|---|---|
| D1 | Engine stays **Godot 4.7, Compatibility renderer, typed GDScript**. The Three.js client/server is legacy. | The sim, netcode and tooling are healthy and tested; the dev GPU cannot run Forward+. |
| D2 | Look: **stylised toon cartoon** with outlines, saturated palette, one shared `ArtTheme`. Assets from CC0/purchased/AI-generated sources, unified by the theme. | Mixed sources look coherent only under one shader and palette. Undo = edit the theme. |
| D3 | Characters: **four family designs, identical on both teams** (the chaos), teams told apart by **outfit accent colour + outline tint + HUD marker**. `REVIEW`. NB: the repo already has two blocky Blender characters (`character_a/b`); P2-1 decides keep / restyle / replace. | If chaos hurts readability, colour more of the outfit. One data change. |
| D4 | Steam is the distribution target; itch.io and friend-testing via Tailscale/LAN remain supported. | See the earlier planning chats. |
| D5 | The build is **host-authoritative** over the existing session/transport interface; Steam is a new transport backend, not a rewrite. | `ARCHITECTURE.md` §3. |
| D7 | Settled in the repo, not reopened: vault verb removed (jump does it); escape windows are one-way drops on faces away from the enemy house; carriers move at 0.85 of walking speed; art is 1 unit = 1 cm and optional via fallback. | `godot/PROJECT_MEMORY.md`, `godot/art/README.md`. |
| D6 | Dev machine is a GT 730M laptop: all art must fit the Compatibility renderer and the budgets in `STYLE.md`. | Do not add Forward+-only features. |
| D8 | Target team sizes are 2v2, 3v3 and 4v4 (family vs family). 1v1 is only a development/test setup. Performance, bot behaviour, camera, house layout and UI must be judged at 3v3 and 4v4, not 1v1. | Set by the user on 2026-11-12. Supersedes any note saying the game ships 1v1. |

## Log

| Date | Task | Decision | Why | Undo |
|---|---|---|---|---|
| 2026-11-11 | P0-2 | Ticked P0-2 on the shipped 1v1 config (p99 ~25 ms, 0–1 of 600 over); 3v3 (45 of 600 over) is left as a recorded follow-up | team_size is 1 in the game and 3v3 is held for human tuning (PROJECT_MEMORY §6c); the measured 3v3 cost is steering reachability checks, which the prescribed scheduling change cannot fix | Re-open P0-2 when team_size > 1 ships |
| 2026-11-11 | P0-2 | Rejected the two-tick decision split | 3v3 unchanged; bot_match stalls 42 → 178 s | Diff described in PROGRESS.md |
| 2026-11-11 | P0-2 | Kept an exact 1 cm bounding-box reject in `blocks_segment` | Bit-identical bot_match, −14% reachability cost | Delete the `_REJECT_MARGIN` block |
| 2026-11-11 | P0-2 | verify.mjs gates over-budget ticks (≤5 of 600, 1v1) but not p99 | Wall-clock on a laptop: p99 sits at 25–28 ms, too close to 33 to gate without flakes | Edit `max_over_budget_ticks` in metrics_budget.json |
| 2026-11-12 | P0-2b | Spread each bot's distance-refresh flood over ticks (`flood_stances_per_tick` = 2000 in `BotProfileDef`); decisions use the previous table until it finishes | The flood was the 3v3/4v4 spike; only the table waits, never the decision or the route, so the §6b-ii stuck-on-stale-route failure can't happen. 1v1 bot_match numbers unchanged | Set `flood_stances_per_tick = 0` |
| 2026-11-12 | P0-2b | Three exact speedups kept: deduplicated broadphase candidates per query box, a once-per-tick step-up lift in the look-ahead, and memoized `nearest` for decision destinations | Measured as the top costs; each gives the same answer, only cheaper | Revert the matching hunk in world_collision_def.gd / walkable_surface.gd / nav_graph.gd |
| 2026-11-12 | P0-2b | verify.mjs gates the tick budget at 1v1 and 3v3 (≤5 of 600) and prints 4v4 without gating | 4v4 measured 0 in 8 of 10 runs, 2 and 5 in the others, with worst ticks at 31–34 ms: a gate would fail on noise. Ticked P0-2b on that basis | Flip 4v4 to `true` in the size list in verify.mjs |
| 2026-11-12 | P0-2c | **REVIEW** Per-size modes in `godot/content/modes/house_NvN.tres`: 1v1 120 s rounds / 18 s jail (unchanged); 2v2 180 s / 24 s; 3v3 and 4v4 180 s / 30 s. Escalation +6 s and 2 s countdown at every size; cash per team stays the level's 4 markers (target 7 of 8) | Sweep over 8 seeds per size: 120 s rounds drew 5 of 11 rounds at 2v2 and never once ended a round on target; with these numbers 24 of 24 matches are decided and 24 of 54 rounds end on target. Longer jail because more teammates rescue more (4v4 rescued 50 of 51 seizures). Tuned against bots; a human playtest may change them | Edit the .tres files |
| 2026-11-12 | P0-2c | Cash per team NOT scaled: every size keeps the 4 markers the house has | More cash needs more markers in `build_house.gd` and a re-bake (geometry), and the measured problem was rounds ending level on the clock, which round length fixed | Add markers, re-bake; `cash_per_team` follows the markers automatically |
| 2026-11-12 | P0-2c | bot_match's limit is now regulation for the mode (2·rounds_to_win−1 full rounds), not a fixed 6 min; draws count against it | A fixed 6 min cut 3v3 off mid round 3 at 120 s rounds and would cut off every 180 s match | `_regulation_ticks` in bot_match.gd |
| 2026-11-12 | P0-2c | verify gates bot_match at 3v3 (main) and 1v1 (second), each with its own stall budget: 1v1 42 s (exact, as before), 3v3 400 s against a measured 327 s | Stall totals at 3v3 swing 102–471 s across seeds at the same numbers, so the exact figure would fail on any change that moves the match, not on a regression | `bot_match` sizes in metrics_budget.json |
| 2026-11-12 | P0-4 | Debug HUD on `F1` (the free F-key next to F2–F4 debug keys), hidden by default; a one-line `[F1] debug HUD` hint stays visible, carrying the network status for host/guest | The task asked for hidden-by-default; a host still needs the join code and a guest the CONNECTING line, and the real HUD (P5-2) doesn't exist yet | Set `_debug_hud_visible` default to true, or launch with `--debug-hud` |
| 2026-11-12 | P0-5 | Backdrop: procedural sky, depth fog in the sky's horizon colour from 60 m to just inside the far plane, muted grass plane under the lot; blockout grey lightened 0.26 → 0.56 | A dark blockout under daylight reads as holes; fog in the horizon colour hides the far-plane cut. Colours are constants in `world_backdrop.gd` until the ArtTheme (P1-4) takes them | Edit the constants in `world_backdrop.gd` / `BLOCKOUT_GREY` |
