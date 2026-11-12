# Progress log

Newest first. One entry per task: date, task id, what changed, what the frames showed, numbers, what is left.

## 2026-11-11 — P0-2 Tick budget
- **The shipped config (1v1, `greybox_level.gd` team_size 1) already met the target before any change**, because of the `nearest()` fix in PROJECT_MEMORY §6b-ii; PLAN.md quoted older numbers. Before, 3 runs of `perf_probe`: p99 27.9 / 25.4 / 26.4 ms, 1 / 0 / 1 of 600 ticks over, bot thinking 3.2–3.3 ms/tick. After: p99 24.9 ms, 0 of 600 (inside verify).
- Instrument: `perf_probe.gd -- --team-size=N` measures the crowded case. **3v3 before: p99 44–51 ms, 45–46 of 600 over, bot thinking 13–14 ms/tick, median tick 12–13 ms.**
- Attribution, via temporary timers (removed) over ~690 ticks × 6 bots in 3v3: steering 5.9 s, of which `is_reachable_between` in the look-ahead loop was 4.1 s (23,265 checks, ~178 µs each, ~6 per bot per tick); decisions 3.0 s (255, ~11.8 ms each, mostly the distance flood); routes only 0.5 s (106 × 4.6 ms). The 3v3 problem is the steady steering cost, not flood + route landing on one tick.
- Attempt 1 (scheduling, as PLAN prescribed): split a decision so the flood runs alone and the choice and route come on the next tick. 1v1 p99 dropped to 19.6, but 3v3 did not move (36–51 over), and bot_match stalls went **42 → 178 s** (176 at one spot near (600,1800)). **Reverted.**
- Attempt 2 (kept): an exact bounding-box reject in `WorldCollisionDef.blocks_segment` that skips the two exact tests for blockers more than 1 cm from the segment. **Bot match is bit-identical** (12 pick-ups, 8 deposits, 6 seizures / 5 rescues, 42 s stalls, winner team_a, same 23,265 checks). Reachability loop 4.13 → 3.56 s (−14%). 3v3 after: p99 ~47 ms, 38 of 600 over. Not enough; the rest of the cost is gathering candidates from the many grid cells a long look-ahead line spans.
- Gate: `verify.mjs` now runs `perf_probe --team-size=1` and fails above `max_over_budget_ticks: 5` (`metrics_budget.json`), printing p99.
- **Left (3v3 only, which is not switched on):** a cheaper reachability check for long look-ahead segments (e.g. walk only the cells the segment actually crosses instead of its whole bounding box, or test the look-ahead nearest-first and stop early), or fewer checks per tick. Two attempts used; logged, not blocking.

## 2026-11-11 — P0-1 Baseline (Windows dev PC)
- Godot: `GODOT_BIN=C:\Godot\Godot_v4.7.1-stable_win64_console.exe` → `4.7.1.stable.official.a13da4feb`. Machine: Windows 10 Home 19045, GT 730M laptop (Compatibility renderer only, per D6).
- `node autobuild/verify.mjs` → **VERIFY: healthy**. 16 suites at exactly the pinned counts (bot_director 26, camera_controls 16, capture_system 42, carry 33, command_codec 23, content_validator 37, greybox_level 20, identity 15, lobby 42, movement 86, navigation 28, ordering 6, prediction 28, scoring_flow 44, snapshot 18, transport 28). Bot match: deterministic, winner team_a, 42 s stalls, 0 s idle, 6 captures, 6 legal encounters.
- `--frames` works windowed on this PC (no xvfb needed); 3 frames written. What they showed: `spawn_default` — voxel character (red shirt, blue-grey trousers) on a dark-red floor strip beside a grey wall, black void filling the left half, debug HUD over the top-left. `stall_spot_a` — red floor and red/grey wall slabs at close range, a black sliver at left, HUD over it. `stall_spot_b` — grey stair treads beside a navy-blue wall, black void at left. The HUD's `cam1 (200,493,1192)` line does not change with `--capture-at`, so it reports the player camera, not the capture camera.
- Housekeeping: every Godot run rewrites `godot/art/models/*.glb.import`; restored with `git checkout --`.
- Left: nothing for P0-1. Debug HUD and black void are P0-4 / P0-5.

## 2026-11-11 — setup, re-measured on the REAL branch (planning session)
- First measured the stale Aug-15 GitHub branch by mistake (474 s stalls, no winner, no verbs). The user's 29 local commits were then merged and pushed (merge `5ac27d6`); everything below is from that version.
- 16 suites green (carry 33, command_codec 23, greybox_level 20, movement 86, navigation 28, prediction 28 checks etc. — pinned in `autobuild/test_baseline.json`). Bot match deterministic, winner team_a, 42 s of stalls, 6 captures, 6 legal encounters.
- Frame seen (`spawn_default`): a blocky voxel-style person (red shirt, blue trousers) standing on a dark-red floor beside a flat grey wall, black void behind, debug text covering the top-left. Characters exist but are crude; the world is still grey boxes.
- Still open from the docs: tick overruns (bot decision + routing > 33 ms), slide, drop-from-height, presentation for jump/throw, Steam transport, all real art, real two-machine playtest.
- Software-rendered capture works under xvfb with `--rendering-driver opengl3`; on the Windows dev PC it runs windowed.
