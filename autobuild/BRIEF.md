# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

## P3-6 — Performance pass

*(Note added by the P3-5 session, 2026-11-16: the room lamps are built but OFF because the shell
is one mesh per house, so a single lamp redraws the whole house shell in every view (+4.2 ms GPU
for four lamps per house). If this task splits the shell per room, lamps in the jail, kitchen and
cash rooms become affordable again: measure `interior_lamps = true` after the split. Before this
task, with lamps off: kitchen 11.5 ms GPU, 535 draws, 328k triangles; approach 10.6-11.0 ms.)*

**Approach**
1. Measure everything first: `node autobuild/render_stats.mjs --timing=120` over all views (about 15 min, windowed, on this machine). Save the table in `PROGRESS.md` as "before". List every view over a number in `autobuild/render_budget.json`.
2. Find what the draws are. For the worst view, count nodes by kind (blockout boxes, shell, furniture pieces, exterior, figures, shadow pass). The known suspects: the blockout draws one object per box, and the sun's shadow pass draws every caster again (approach view went 526 → 1045 draws in P1-4).
3. Fix in this order, re-measuring the worst view after each:
   a. If the dressed shell covers the blockout boxes, do not draw the boxes at all when the shell is on (they stay as collision data and as the fallback when art is missing).
   b. Furniture: merge static pieces per room and material into one mesh, or MultiMesh for repeated pieces (chairs, cabinets).
   c. Shadow casters: turn `cast_shadow` off for things whose shadow is never seen (floors, ceilings, the ground, the far street, neighbours beyond the shadow distance, small props).
   d. Exterior: confirm it is still three meshes; give far neighbours and trees a visibility range if triangles are high.
   e. Textures: check import settings are VRAM-compressed with mipmaps; 1k only on big surfaces.
4. Make the budget a gate if it can be made stable: counters (draw calls, triangles) are deterministic per view, timings are not. Gate the counters only.
5. Final `render_stats` run, "after" table, frames of the three worst views opened to confirm nothing vanished. Verify once; commit.

**Already decided**
- Budgets are the ones in `STYLE.md` / `render_budget.json`: ≤ 1000 draws, ≤ 300k triangles, ≤ 9 ms GPU median, ≤ 12 ms frame median, per view. They are not loosened here. A view that cannot be brought under after two attempts is listed in `PROGRESS.md` with its numbers, and the task is marked `[~]`.
- Judge at 4v4 (D8): figures on screen count.
- The verify gate covers draw calls and triangles for a small fixed set of views (worst interior, worst exterior, `approach_from_south`), with about 10 % headroom over the measured value; GPU and frame time stay printed, not gated (laptop noise, same reasoning as the P0-2 tick decision). It needs a window, so it goes in the full verify only, not `--quick`. If windowed capture inside verify proves flaky in two tries, leave it out and log why. Log as a plain decision line.
- Quality is cut last: if a view is still over on GPU time, the order is lamps off in that room, then shadow distance down, then shadow off. Each is theme data; log REVIEW if any look setting changes.
- Merging happens at load in code (as `ShellBuilder` and `ExteriorBuilder` do), not by hand-editing scenes.

**Files likely touched**
- `godot/game/greybox/greybox_main.gd` (exists): blockout box drawing, where parts are added.
- `godot/game/art/furniture_dresser.gd` (exists): merge / MultiMesh.
- `godot/game/art/shell_builder.gd`, `godot/game/art/exterior_builder.gd`, `godot/game/greybox/world_backdrop.gd` (exist): shadow-caster flags, visibility ranges.
- `godot/art/theme/default_theme.tres` (exists): only if a quality setting must drop.
- `autobuild/verify.mjs`, `autobuild/render_stats.mjs`, `autobuild/render_budget.json`, `autobuild/metrics_budget.json` (exist): the counter gate.
- `godot/art/textures/**/*.import` (exist): compression flags, if wrong.
- `PROGRESS.md`, `PLAN.md`, `DECISIONS.md`, `STYLE.md` "what the baseline measured" (add the after numbers).

**Done means**
- Before and after tables in `PROGRESS.md` for every view: draws, triangles, GPU ms median, frame ms median; worst view named.
- Every view within the four budgets, or the exceptions listed with numbers and the task left `[~]`.
- Frames of the three worst views, plus `lot_overview`, one kitchen and one stair view, opened after the changes: nothing missing, no new holes where a blockout box used to show through, shadows still present where they were visible before.
- `node autobuild/verify.mjs` healthy, once, before the commit; symmetry 193 of 193, bot-match and tick numbers unchanged.

**Do NOT**
- Change collision, the baked blockout data, zones or anything in `sim/`: only what is DRAWN changes. The simulation tick budget is not this task.
- Tune bots, run sweeps, or chase the frame p95 (it is dominated by sim ticks).
- Lower the look to hit a number before trying merging and shadow-caster culling.
- Delete the blockout fallback (art must stay optional), add LOD systems or occlusion culling machinery beyond visibility ranges, or add Forward+ features.
- Write tests for presentation code. Add a timing gate that fails on laptop noise.
