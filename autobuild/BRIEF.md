# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

## P3-4 — Exterior

REDO: The only exterior frames on disk (`autobuild/frames/ext_street_south.png`, `ext_street_along.png`, `lot_overview.png`, shot 18:27 on 2026-11-15) are OLDER than the committed code (`996d876`, 23:08). Re-shoot before judging anything: `node autobuild/verify.mjs --frames-only --views=ext_,cam_fence,cam_railing,cam_gravel,cam_garden,lot_,approach,yard_`. The REDO items below are what those three old frames show; skip any that the fresh frames no longer show.
REDO: `lot_overview` has a hard horizontal line right across the frame where the fog meets the sky (pale fog band below, blue sky above, a straight edge at about a quarter of the way down). Make the sky's horizon colour and the fog colour the same and fade the sky into it, so there is no visible line from a high camera.
REDO: Fog is far too thick. In `lot_overview` the neighbours' houses one plot away (60–80 m) are already milky white and the far street vanishes; in `ext_street_south` the street ends in white after about four houses. Push the fog start out so the game lot and the first ring of neighbours are clear and only the far street ends fade (`world_backdrop.gd` / theme fog numbers).
REDO: The gravel on the neutral ground is a saturated orange-yellow (reads as sand or a sports pitch). Bring it to a muted grey-buff: drop the albedo tint toward neutral so the Poly Haven `gravel_floor` texture shows its own colour.
REDO: The pavement is peach/salmon, not concrete. Same fix: neutral albedo on `pavement` so `concrete_pavement` reads grey. The kerb is a cream stripe; make it a slightly lighter grey than the pavement.
REDO: Brick is loud: high-contrast, and the bricks look oversized against doors and windows in `ext_street_along`. Check the tile size (a brick should be about 28 × 10 units at the house's 1.3× scale) and lower the contrast (albedo toward the STYLE §3.3 brick `(0.55, 0.33, 0.25)`). It is the house's own `wall_outside` material, so check `ext_a_south` too after changing it.
REDO: Clouds are blotchy smears with faint vertical streaks (`ext_street_south`, `ext_street_along`). Try `sky_clouds` 0.25 with a softer ramp; if it still smears, set it to 0 (clear sky) and log it.
REDO: Lawn is a loud saturated green next to everything else. Mute it a little (albedo on the `yard` floor material; the backdrop plane follows it).
REDO: Hedges are flat-topped dark boxes with knife edges (`ext_street_along`, right). Low priority: round the top edge or lump it with `_blob`, only if cheap.
REDO: The 11 new views (`ext_street_*`, `ext_gate_a`, `ext_gravel_a`, `ext_midline`, `ext_upstairs_out`, `cam_fence_*`, `cam_railing_*`, `cam_gravel`) have never been opened, except the two street ones. Open every one.

**Approach**
1. Read `godot/game/art/exterior_builder.gd` (header comment explains the whole layout) and the `Exterior` group in `art_theme.gd` / `default_theme.tres`. The builder is committed and hooked up in `greybox_main.gd`; this task is now review and finish, not build.
2. Shoot the views (command in the first REDO). Open each frame with Read. Write down what each shows.
3. Fix the REDO items, cheapest first: theme numbers (fog, sky, albedo tints, cloud amount) before code.
4. Check the camera cases specifically: `cam_fence_backed` and `cam_railing_backed` (player's back against the lot edge) must show the player and the yard, with the fence cut away, not a fence filling the screen; `cam_fence_west` / `cam_railing_out` must show a fence that looks too tall to climb.
5. Check the items the plan lists are all present in frames: lot ground, fences, garden (soil border, hedges), trees, path from each front door to its gate, neutral strip (gravel), street, sky, sun (shadows of trees/fence on the ground).
6. Check both houses' sides get the same thing (House B is House A turned half a circle): `ext_b_north` against `ext_a_south`.
7. Run `node autobuild/render_stats.mjs --views=ext_,lot_,approach` once and record draws / triangles / GPU ms. Over budget is recorded for P3-6, not fixed here, unless a view is over 1000 draws because of the exterior alone.
8. Re-shoot, open, describe in `PROGRESS.md`; tick; run verify once; commit.

**Already decided**
- The design in the builder's header stands: street sides = black railings on a brick plinth with piers and a gate; garden sides = close-board timber fence; neighbours = plain boxes under hipped roofs; gravel on neutral ground; stepping stones on the yard midline. Log as REVIEW (one line: the exterior layout and that it is point-symmetric by construction).
- Exterior walls of both houses are brick (STYLE §3.3 left brick-or-render to P3-4): brick. Some neighbours are render for variety. Log REVIEW.
- Fence height 210 (`fence_height`), drawn only; the level bounds stay the wall. No collision is added.
- Textures: the five Poly Haven ones already in `godot/art/textures/` plus generated lawn/foliage. No more downloads unless a REDO cannot be met by tinting. All already in `ASSETS.md`.
- Fog and sky colours are theme data; change numbers there, not constants in code.
- Trees stay simple lumpy crowns (deadpan, cheap). No wind, no particles, no birds, no cars.

**Files likely touched**
- `godot/art/theme/default_theme.tres` (exists): exterior materials, fog/sky/cloud numbers, lawn and brick tints.
- `godot/game/greybox/world_backdrop.gd` (exists): fog start/end, sky horizon blend.
- `godot/game/art/exterior_builder.gd` (exists): hedge shape, kerb, any gap or z-fight seen in frames.
- `godot/game/art/fence_cutaway.gdshader` (exists): only if the backed-against-fence views are wrong.
- `autobuild/views.json` (exists): only to add a view that is missing.
- `PROGRESS.md`, `PLAN.md`, `DECISIONS.md`.

**Done means**
- Fresh frames opened and described for: `lot_overview`, `approach_from_south`, `ext_a_south`, `ext_a_east`, `ext_a_north`, `ext_a_west`, `ext_b_north`, `ext_street_south`, `ext_street_along`, `ext_gate_a`, `ext_gravel_a`, `ext_midline`, `ext_upstairs_out`, `cam_fence_west`, `cam_fence_backed`, `cam_railing_out`, `cam_railing_backed`, `cam_gravel`, `cam_garden_open`, `cam_garden_wall_backed`.
- Each shows: no horizon line, no black or grey void, neighbours one plot away not fogged out, grey pavement, muted gravel, no z-fighting or seams on the lot ground (the old "thin pale line across the lawn" in `cam_garden_open` gone or explained), a gate in line with each front door.
- From inside (`ext_upstairs_out`, and one `room_` view with a window): the window shows fence, trees or a neighbour, not empty lawn to the horizon.
- `render_stats` numbers for the exterior views written in `PROGRESS.md`.
- `node autobuild/verify.mjs` healthy, run once just before the commit. Symmetry must stay 193 of 193 and bot-match numbers unchanged (nothing here touches the sim; if they move, something did).

**Do NOT**
- Add collision, move the bounds, change zones, spawns or `build_house.gd`. The exterior is drawn only.
- Touch bots, modes, sweeps, or write test files.
- Do the lighting pass (lamps, shadow settings, banisters): that is P3-5. Do the mesh merging: that is P3-6.
- Add props for their own sake (cars, bins, street lamps, mailboxes). One coherent look over more content.
- Copy a specific game's street or house design. Download anything not CC0.
- Rebuild the builder from scratch. It is 800 lines that work; fix what the frames show.

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
