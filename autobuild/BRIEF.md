# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

## PT4-4 — HUD fixes

**Approach**
1. Cash bar first. Read `MatchHud.refresh` / `_draw` (`game/greybox/match_hud.gd`) and
   `MatchStatus.cash_split` (`game/greybox/match_status.gd`). On paper they are already right: the
   colours come from `ArtTheme.current().family_colours` by team id, and the split is
   first / (first + second). So the user's screenshot has a cause the code does not show at a
   glance. Find it before you change anything. Candidates: `_colours` is copied in `_init`,
   possibly before the theme or the level is ready, and the fallbacks are hard-coded; `_first_id`
   may not match the theme's keys; `_split` only eases while visible; `score_for` may not be
   *banked* cash; "0/6" is the target readout, not the other side's score. Say in `PROGRESS.md`
   which one it was.
2. Make the bar's numbers one pure static function, for example
   `MatchHud.bar_layout(first_score, second_score, first_id, second_id, theme) -> {split, left, right}`.
   The colours are read through `ArtTheme.family_colour(team)`, never typed into the HUD, and
   `_draw` uses only that function. Remove the hard-coded `Color(0.48, …)` / `Color(0.7, …)`
   fallbacks.
3. Minimap. `TeamTellOverlay._draw_map` (`game/greybox/team_tell_overlay.gd`) draws a dark box and
   the indoor room rectangles, turned so your own house is at the bottom. Replace the content with a
   top-down outline built ONCE per level from level data:
   - the lot: `level.collision.bounds`, not `WorldBackdrop.widest_blocker`;
   - each house's outline: the union of its owned indoor zones, grown by the 30 wall, as in
     `ExteriorBuilder._find_yards_and_houses`;
   - each yard;
   - the boundary fence line with its gate openings: the fence's collision boxes on the lot's middle
     x, as in `ExteriorBuilder._middle_fence`.
   Put the geometry in a static helper, `MinimapOutline.build(level) -> Array of segments/rects`
   (new file), or as a static function in the overlay. Draw houses filled a shade lighter than the
   yards, walls as 2 px cream lines and the fence as a darker line broken at the gates.
4. Minimap only in a match: draw it only while a match is running (link ready, not at MATCH_END or
   results, no lobby, no menu). Clear the overlay's level (`_lot`, the outline) in the
   return-to-menu reset in `greybox_main.gd` (around line 495, next to `_tell_overlay.bodies = []`).
   Today `_lot` survives there, so the box is drawn behind the menu.
5. Hint label: in `GreyBoxMain._update_hud` (around line 2658), include "[F1] debug HUD" only when
   `OS.is_debug_build()`. In a release build a host or guest keeps the network line alone, and a
   solo player gets no line. F1 itself keeps working in both builds.

**Already decided**
- First family (`level.teams[0]`) on the left in its colour and second on the right, on every
  machine (as the file header says). 0–0 gives a split of 0.5; 0–6 gives 0.0 (all second colour);
  6–0 gives 1.0.
- The minimap stays a TeamTell option (`tell.minimap`). Do not change its default or its F6 key;
  PT4-7 moves the checkbox. Size, place and turn stay the same (top right, 210 px, own house at the
  bottom). PT4-5 changes what is drawn for the figures. Leave the figure dots as they are now.
- Release builds keep F1 working but show no hint text. Log this in `DECISIONS.md` (plain, no
  REVIEW). Log the minimap outline's look as REVIEW.

**Files likely touched**
`godot/game/greybox/match_hud.gd`, `godot/game/greybox/match_status.gd`,
`godot/game/greybox/team_tell_overlay.gd`, `godot/game/greybox/greybox_main.gd`,
`godot/game/greybox/minimap_outline.gd` (new, if you make it a class),
`godot/tests/match_status_test.gd`, `godot/tests/greybox_level_test.gd`,
`autobuild/test_baseline.json`, `DECISIONS.md`, `PROGRESS.md`, `PLAN.md`.

**Done means**
- `match_status_test`: table cases for `bar_layout`: 0–0 → 0.5, 0–6 → 0.0, 6–0 → 1.0, 3–1 → 0.75.
  The left colour equals `theme.family_colour(teams[0].id)` and the right equals the second; the
  two differ. Ratchet its pin in `test_baseline.json` (9 → the new count).
- `greybox_level_test`: one case on the baked level. The outline has 2 houses, both inside the lot;
  the fence has at least one gate gap; the result is the same on a second build.
- From the code: no minimap draw path runs while the menu, lobby or results are showing.
- The full `node autobuild/verify.mjs`, run ONCE at the end, just before committing: healthy, all
  suites at their pins.

**Do NOT**
- Shoot frames or sheets (not a frame task).
- Draw enemies or new figure shapes on the minimap (that is PT4-5).
- Touch collision, zones, `build_house.gd` or the bake to get fence data; read what is already there.
- Move the team-tell checkboxes (that is PT4-7).
- Restyle the bar beyond the colour and split fix.

## PT4-5 — Minimap pointers per member

**Approach**
1. Extend `TeamTellOverlay.Body` (`game/greybox/team_tell_overlay.gd`) with `member: StringName`
   and `heading: float`. Fill both in `GreyBoxMain._update_tell` (`greybox_main.gd`, around line
   1783):
   - the member from `ArtTheme.current().member_for(team, slot, …)`, the same call
     `FamilyLineup` uses, so kid swap (`family_order_by_team`) is honoured. Find how the lineup gets
     the slot and reuse it;
   - the heading from the drawn facing (`_facings[entity_id]`), not from the camera.
2. Write one pure static function, for example
   `TeamTellOverlay.pointer(member, mine, heading) -> {shape, radius, points: PackedVector2Array}`
   in map axes (after `_turn`). `_draw_map` only draws what it returns.
3. Shapes:
   - dad: a square;
   - mom: a diamond;
   - any `*_boy`: a triangle whose apex is the facing;
   - any `*_girl`: a circle.
   Each one except the triangle gets a short notch or tick pointing the way it faces.
   Fill: the family colour (`ArtTheme.family_colour`). Each shape has a thin dark rim, as the dots
   have now.
4. The player's own body: 1.3× radius plus a 2 px cream outline. It replaces the white camera arrow.
5. Draw every actor body of both families, bots and players alike. Draw the own body last, so it
   sits on top.

**Already decided**
- Base radius 5 px; own body 6.5 px. Elder and younger children share the son and daughter shapes.
- Both families are drawn on the minimap. This reverses STYLE §2.4's "(b) teammates only". The
  user's PT4-5 text asks for each figure in its family colour, bots and players alike. Log as
  **REVIEW** in `DECISIONS.md`, and keep it one constant (`MAP_SHOWS_ENEMIES := true`) so it is
  cheap to undo. Update the minimap line in `STYLE.md` §2.4.
- The marker (`_draw_marks`) stays teammates only. Do not change it.
- Heading convention: use the same yaw the body is drawn with. Check one known case, a body facing
  +z in world space, and confirm its notch points the way `_turn` maps +z.

**Files likely touched**
`godot/game/greybox/team_tell_overlay.gd`, `godot/game/greybox/greybox_main.gd`,
`godot/tests/match_status_test.gd` (the overlay's case table goes here, next to the other HUD
helpers), `autobuild/test_baseline.json`, `STYLE.md`, `DECISIONS.md`, `PROGRESS.md`, `PLAN.md`.

**Done means**
- One table-driven test of `pointer(...)` over dad, mom, elder_girl, elder_boy, younger_girl and
  younger_boy, each with `mine` true and false: the shape name, the radius (5 / 6.5), and for two
  headings (0 and 90°) that the facing point or notch sits in the expected direction. Ratchet the
  pin.
- The full `node autobuild/verify.mjs`, run ONCE at the end: healthy.

**Do NOT**
- Shoot frames (not a frame task).
- Add a new test file.
- Read the sim from the overlay; it gets everything from `GreyBoxMain`.
- Change the minimap outline from PT4-4, or the marker.
- Add icons or textures; these are plain polygons.

## PT4-6 — Hands and arms

**Approach**
1. Measure before changing. In the idle rest pose, print the following for each of the six members
   (dad, mom, elder_girl, elder_boy, younger_girl, younger_boy): wrist height (`hand_*` bone
   origin) / drawn height, fingertip height / height, hand length / height and palm width / height.
   Use a temporary print in a headless tool run that builds the figures through
   `ArtTheme.shape_figure`, then remove it. Put the table in `PROGRESS.md`.
2. Targets (real people, then D2's slight off-ness):
   - wrist at about 0.48 × height;
   - fingertips at about 0.38 × height (mid-thigh);
   - hand length about 0.11 × height;
   - palm width about 0.05 × height.
   Allow ±10 %. Kids' arms may stay "a touch short" (STYLE §2.2).
3. Fix through data only: `bone_scales` on each `FamilyMember` in
   `godot/art/theme/default_theme.tres`:
   - `lowerarm_*`: y shortens the forearm;
   - `hand_*`: uniform, to shrink the palm.
   Bone scale is inherited by children in Godot, so a lowerarm scale also scales the hand: compute
   the hand factor after the forearm's. Keep non-uniform scale off bones that have rotated children,
   or the hand shears. Mom already has `lowerarm 0.9` / `hand 0.92` in x and z; re-measure her as
   well.
4. Check the carry. The bundle is drawn at `FigureAnimator.hands_point()`
   (`game/art/figure_animator.gd`), so it follows the hands. There is no anim test suite; the
   numbers are these: for each member, held in `carry_idle`, `hands_point().y` minus the crown
   height must be > 0 (bundle above the head), and the distance between the two hands must be at
   least the bundle's width. Use a temporary print, then remove it. Also print the before and after
   values.
5. Frames at the end (see Done means). Fix what they show, with one redo at most.

**Already decided**
- Data change only, in `default_theme.tres`. No re-bake of the gltf bodies and no edits to the
  rig.
- The shared `figure_bone_scales` (head, neck, spine) stay as they are.
- Log the per-member hand and forearm scales and the targets above in `DECISIONS.md` as
  **REVIEW**, and update the STYLE §2.2 table's notes (Mom "hands a touch large" goes if they are no
  longer large).

**Files likely touched**
`godot/art/theme/default_theme.tres`, `STYLE.md`, `DECISIONS.md`, `PROGRESS.md`, `PLAN.md`.
Read only: `godot/game/art/art_theme.gd` (`shape_figure`), `godot/game/art/figure_animator.gd`.

**Done means**
- The measured table, before and after, in `PROGRESS.md`. Every member's after-values are within
  the targets' ±10 %, or the reason they are not is written down (kids' short arms).
- The carry check holds for all six members.
- **Frames: one capture set at the end**, opened with the Read tool, and `PROGRESS.md` says what
  each one actually shows:
  - (a) `node autobuild/family_lineup.mjs --import`: the six members, front, side and back. Hands
    end at about mid-thigh, palms no wider than the wrist-to-elbow section, and no arm looks longer
    than its body warrants.
  - (b) one close shot of dad carrying, for example
    `godot --path godot -- --capture-figure=2700,300,1000,180,dad,,carry_idle@0.5`, or the
    `--pilot=carry` + `--capture-follow=on:grab:me,...` route in `godot/CLAUDE.md` if the bundle has
    to be in the shot. The bundle is held over the head with both hands touching it, and the hands
    look normal against the head.
  - **One redo at most.**
- The full `node autobuild/verify.mjs`, run ONCE at the end, just before committing: healthy (the
  render counters within limits).

**Do NOT**
- Change collision, the sim body, `actor_height` or the drawn heights.
- Re-rig or re-bake the bodies (`rerig_family.mjs`, `figure_bake.mjs`).
- Touch the animation clips or the IK code unless the carry check fails after the data change.
- Run turnaround or anim sheets for every clip, or sweeps. The capture set above is the only one.
- Copy another game's character proportions or designs.
