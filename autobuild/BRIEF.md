# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

## P3-5 — Lighting and readability pass

**Approach**
1. Measure first: `node autobuild/render_stats.mjs --views=room_,cam_` and shoot `--frames-only --views=room_,cam_`. Open four or five (jail, kitchen, study, bedroom, a stair). Note where floor, wall, figure and cash sit close in brightness.
2. Contact shadows (STYLE §4, mandatory): a soft dark disc under every figure and every cash bundle, a transparent quad on the floor under it, placed in `GreyBoxMain._render` from drawn positions, staying on the floor below when the body jumps. Grep first: if one already exists, only tune it.
3. Room character without many lamps: per-room look from data. Start with what is nearly free: per-room ambient/tint is not available in Compatibility, so use at most ONE unshadowed spot per room, only in the rooms that need it (jail: one cold dim bulb; kitchen: one bright; study and bedroom: one warm). Turn on, measure the kitchen and a landing view. Keep it only if every view stays at or under 9 ms GPU; otherwise keep lamps for the jail and the two cash rooms only, or none, and log the numbers.
4. Sun shadow: keep one orthogonal map. Try `sun_shadow_distance` lower (2500) and look at shadow edges in `approach_from_south` and a room with a window; keep the cheaper setting if the frame is no worse.
5. Contrast: adjust theme materials so the order by brightness is ceiling < floor < wall in lit rooms, figures clearly off both, cash the most saturated thing in any room. Cash gets a material that reads at 30 m (a saturated banknote green with a pale band, slightly lower roughness); no glow, no outline, no floating marker.
6. Cash at 30 m: add two views with a bundle on the floor 3000 units from the camera, one indoors down the longest sight line, one in a yard. Open them.
7. Banisters: read `_stairs`, `_straight_flight`, `_stairwell` in `godot/tools/build_house.gd` to see which sides of each flight and stairwell already have a blocker. Draw a banister (newel posts, handrail, square balusters, painted trim + oak rail) in `ShellBuilder` on every such side, sized to the blocker. See "Already decided" for sides with no blocker.
8. Re-shoot stairs (`cam_stair_a_climb`, `cam_stair_a_top_down`, `cam_stair_b_climb`, `cam_landing_a`, the four `room_*_landing_*`), all rooms, and the cash views. Open, describe.
9. `render_stats` again; write before/after. Verify once; commit.

**Already decided**
- Tonemap stays Linear, sun energy stays low (P1-4 measured why). Do not retry Filmic.
- No shadowed omni/spot lights, at most two lamps touching any object, at most one shadowed light (the sun). No SSAO, glow or other Forward+ features (D6).
- Exposure is "day-like": a lit room's wall paint at about 75–80 % brightness. Jail coldest and dimmest, kitchen brightest (STYLE §4).
- Banister collision: where a flight's or stairwell's open side ALREADY has a blocker (a stair wall), the banister is drawn on it and no collision changes. Where an open side has NO blocker, do not add one: a new blocker changes routes, the symmetry probe and every bot match, and bot work is paused. Leave that side open, with only a newel post at the top and bottom if it does not look walk-through-able, and write the open sides in `PROGRESS.md` for the user. Log as REVIEW.
- Banister look: plain suburban, white-painted square balusters at about 12-unit spacing, oak handrail at about 110 above the tread line, square newel posts. Part of the house's single mesh (a surface per material), not separate nodes.
- Contact shadow: a disc about 1.2× the body radius, alpha about 0.35 at the centre fading to 0, fading further with height above the floor; unshaded, no depth write, render-only. Numbers go in the theme.
- Lamp choices and the cash material are REVIEW lines in `DECISIONS.md`.

**Files likely touched**
- `godot/art/theme/default_theme.tres`, `godot/game/art/art_theme.gd` (exist): lamp list/flags, shadow distance, material values, contact-shadow and banister numbers.
- `godot/game/greybox/world_backdrop.gd` (exists): lamps (`interior_lamps` path, line ~134), sun shadow.
- `godot/game/greybox/greybox_main.gd` (exists): contact-shadow quads in `_render`.
- `godot/game/art/shell_builder.gd` (exists): banisters.
- `godot/tools/build_house.gd` (exists): READ only, for the stair geometry.
- `autobuild/views.json` (exists): two cash-at-30-m views; a stair view if a flight is not covered (House B has no stair camera views).
- `godot/art/cash.glb` or the theme's cash material: check which one colours the bundle before changing.
- `PROGRESS.md`, `PLAN.md`, `DECISIONS.md`, `STYLE.md` §4 "as built" paragraph.

**Done means**
- Frames opened and described: all 16 `room_*`, the `cam_stair_*` and `cam_landing_a` views plus one stair view in House B, the two new cash views, `approach_from_south`.
- In them: a visible banister on every flight where a stair wall exists, not poking through walls or treads, not hiding the stairs from the stair cameras; a contact shadow under each figure and bundle; the jail visibly dimmer and cooler than the kitchen; a figure distinguishable from the wall behind it in the jail; the cash bundle found at a glance at 30 m in both cash views.
- Numbers: every `room_` and `cam_` view at or under 9 ms GPU median and 1000 draws in `render_stats.mjs`, or the over-budget views listed with numbers for P3-6. Before/after table in `PROGRESS.md`.
- `node autobuild/verify.mjs` healthy, once, before the commit; symmetry 193 of 193 and bot-match numbers unchanged.

**Do NOT**
- Add or move collision, re-bake the blockout, or edit `build_house.gd` (see the banister decision).
- Turn all 16 ceiling spots back on and hope: that was measured at 10.2 ms.
- Add outlines, glow, pulsing markers or beacons on cash (D2). Readable through colour and contrast only.
- Re-style figures or outfits, re-texture furniture room by room, or redo the exterior.
- Merge meshes for speed: P3-6. Touch bots, modes or sweeps. Write test files (presentation is verified by eye).

## P3-6 — Performance pass

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
