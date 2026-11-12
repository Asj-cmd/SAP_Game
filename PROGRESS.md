# Progress log

Newest first. One entry per task: date, task id, what changed, what the frames showed, numbers, what is left.

## 2026-11-11 — setup (written by the planning session, not the loop)
- Measured: 16 suites / 444 checks green; bot match deterministic; 474 s of stalls at 5 spots; no winner ("ran out of ticks", rounds 1-1); black void; capsules and boxes; debug HUD on every frame.
- Frames seen: `autobuild/frames/spawn_default.png` (red capsule in grey room, black void), `stall_spot_a.png` / `stall_spot_b.png` (flat grey/red/blue blocks, stairs, HUD text over everything).
- Software-rendered capture works under xvfb with `--rendering-driver opengl3`; on the Windows dev PC it runs windowed.
- Added: PLAN.md, DECISIONS.md, autobuild/{verify,loop}.mjs, test baseline (16 suites), metrics budget.
