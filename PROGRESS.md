# Progress log

Newest first. One entry per task: date, task id, what changed, what the frames showed, numbers, what is left.

## 2026-11-14 — P2-1b Evaluate all character packs (partly done)
- **Licences (all four read from the zips):** Animated low poly men, Animated low poly women, Ultimate Modular Men and Ultimate Modular Women are each CC0 1.0. The women's Modular licence file is headed "Ultimate Modular Males" but carries the same CC0 text. Recorded in ASSETS.md.
- **What is in them (`tools/probe_character.gd`):**
  - Low-poly men/women: FBX/OBJ/Blend only, about 2k triangles (Smooth_ variants 8.4k). They use their own 42-bone rig with the feet hanging off the root (IK), no clavicle or ball bones, and paddle hands.
  - Modular: glTF, 4.5–5.8k triangles per casual outfit. Also their own 62-bone rig with IK feet.
  - Neither uses the UAL rig that `figure_anims.res` is built for.
- **New tools:**
  - `autobuild/unzip_pack.mjs`: list or extract a zip with node.
  - `tools/probe_character.gd`: bones, triangles, materials and clips of a model.
  - `tools/convert_character.gd`: static preview of a candidate in its own idle, painted like the figures.
  - `autobuild/character_compare.mjs`: the current family and candidates in one row, with front, three-quarter, 20 m and `--close` shots. An entry `model+clip@t` holds a clip.
  - `tools/rerig_character.gd`: see below.
- **Comparison frame** (`autobuild/slice/p2_1b_packs_front.png`, `_three_quarter.png`). Left to right: dad, mom, low-poly man, low-poly woman, smooth low-poly man, Modular man, Modular woman, all in the same putty and the same painted clothes.
  - Dad and mom are the most sculpted: pecs, lats and a chest, standing in a wide, hunched idle stance.
  - The low-poly bodies stand straight and plain, slightly lanky, with small heads and big flat mitten hands. These are the plainest and silliest bodies in the row.
  - The Modular man has biceps and the woman has hips and a chest. Both are more "character".
  - At 20 m all seven are about the same.
  - **Pick: low-poly man (`Male_LongSleeve`) and woman (`Female_Casual`), REVIEW.**
- **Re-rig instead of retarget** (DECISIONS): `rerig_character.gd` turns the low-poly body, through its own skin, into the figure skeleton's rest stance, keeping its own segment lengths. It then moves the rig's joints onto that body (rest rotations unchanged), rebinds the weights by bone name, paints the body and egg-heads it. Results:
  - Man: 1,894 triangles, leg 81 against the rig's 89, hands ×1.35.
  - Woman: 1,596 triangles, leg 83 against 88, hands ×1.78.
- **Frames while building it** (`autobuild/frames/p2_1b/rerig*.png`; the keepers are in `autobuild/slice/p2_1b_rerig_*.png`):
  - rerig1: the skinning works. jog, carry_walk (cash arms overhead) and panic_run (arms up) all deform the new body cleanly, and the wristband sits on the cuff. But the bodies drew washed-out white, because my face normals were inverted (Godot winds clockwise). Fixed.
  - rerig2–3: dropping the hair left the scalp open (the head read as a cup), so hair is now kept as bare. The woman's hair strands scribbled over the head, so when a body has a separate scalp (`HairBase`) the strands are dropped.
  - rerig5–6: the faces still had eyes and a nose. The men's shoes share the eyes' material, so they came out bare; shoes are now chosen by foot weight. The face is weighted to the neck in this rig, so the head is now chosen by height above the head joint.
  - rerig7–9: no change at all. The cause: GDScript passes packed arrays by value, so the egg was never applied. Fixed by returning the result. Then still no change, although the written vertices sat on the ellipsoid within 3% (checked by decoding the .bin). The face was being drawn by **shading**: the folded eyes and nose cancel their welded normals.
  - rerig10: egged points now take the ellipsoid's own normal, and the eyes and nose are gone.
  - rerig11: inside-out triangles dropped as well. **What is still there:** a faint face-shaped smudge on both new heads at 1.8 m (darker brow and mouth area, a line at the old hairline). My guess is the chin/jaw blend zone (below joint + 3 % of height), plus the coplanar layers (eyes, hair) left on the egg catching the sun's shadow. I made more than two attempts on the head, so it is logged here and left.
- **Left for the next session (P2-1b stays `[~]`):**
  1. The smudge. Try a wider blend (start the egg at the head joint itself), or drop the eyeball and hair layers once they are on the egg.
  2. Point the six `FamilyMember`s in `default_theme.tres` at `figure_lp_male/female.gltf`.
  3. Re-run `tools/build_figure_anims.gd` against the new male (it reads `FIGURE`; add a `--figure=` option). The leg ratio changes from 88.8 to 81.3, which changes stride speeds and the pelvis track.
  4. Re-check the bone nudges: the new head is already small and the neck long, so the shared Head ×1.08 / neck ×1.08 may want to change.
  5. Re-shoot `family_lineup.mjs` and `turnaround.mjs`, then a live contact sheet.
- Nothing in the game changed: the theme still draws the P2-1 figures.
- Verify: `node autobuild/verify.mjs` healthy on the first run. 16 suites; symmetry 200/200.
  - Bot match 3v3: team_b in 439 s, 90 s of stalls. 1v1: 7 s. Bit-identical to P3-1.
  - Tick budget: 0 of 600 over at 1v1, 3v3 and 4v4. net_smoke: 1703 ticks agree.

## 2026-11-13 — P3-1 Kit selection
- **The pick (REVIEW; reasons in DECISIONS.md and STYLE §3.3 "The kit"):**
  - Furniture and appliances: **Kenney Furniture Kit** (CC0, 140 models), the one furniture pack.
  - Surfaces: **Poly Haven textures** (CC0), plus **ambientCG** (CC0) for carpet, wallpaper and upholstery only.
  - Shell (walls, floors, openings, frames, door leaves, stairs, roof): **generated from the blockout** in P3-2. No modular kit.
  - Safe/vault, jail pen and cash: **our own** procedural models (P3-3).
- **Survey (measured, not remembered):**
  - Poly Haven's API lists 522 models. Its 85 furniture pieces are almost all antique, gothic or industrial, and run 500–60k triangles. There is no kitchen unit, fridge, washer, modern bed or wardrobe.
  - Poly Haven's textures cover every surface STYLE §3.3 lists except a clean carpet (only `dirty_carpet`).
  - ambientCG has 16 carpets, 6 wallpapers and ~100 fabrics, and its licence page says CC0.
  - Quaternius Ultimate House Interior is CC0 but rounded and stylised, FBX/OBJ only, and only on Google Drive.
  - KayKit is toy-chunky and was ruled out by STYLE §3.3 without a download.
- **New tool:** `node autobuild/fetch_kenney.mjs <slug>`.
  - Reads the pack page, refuses it without the CC0 line, and downloads through the site's signed-link endpoint (a bare fetch got 403 in an earlier session).
  - Unzips with node's zlib and refuses `..` or absolute entries.
  - Writes `SOURCE.txt` with the zip's sha256. Furniture Kit: `e67652d0…46b0`, 5.1 MB, 1546 files, `License.txt` says CC0.
- **Trial imports** (`godot/art/props/kenney/`, all through `import_asset.mjs`, each with a `.source.json`):

  | Piece | Size (cm) | Triangles | Theme materials |
  |---|---|---|---|
  | kitchen_counter | 115 × 120 × 120 | 114 | painted, wood |
  | fridge | 130 × 230 × 101 | 436 | painted |
  | table | 309 × 120 × 164 | 120 | wood |
  | chair | 52 × 122 × 52 | 170 | wood |
  | washer | 91 × 110 × 91 | 720 | painted, steel |
  | bed_double | 249 × 98 × 293 | 264 | fabric, wood |
  | wardrobe | 108 × 230 × 68 | 296 | steel, wood |
  | sofa | 255 × 120 × 107 | 128 | fabric, wood |

  The Kenney pack is about half real size (door 101, fridge 92, counter 45), so the default is ×260, giving the house's 1.3× scale. Thresholds use `--height=`.
- **Frames** (`autobuild/frames/p3_1/`, drawn-only props via `--capture-prop`):
  - `kenney_kitchen.png` (kitchen A, from the SW corner): a run of three cream counters with framed door panels, a white side-by-side fridge with handles, and a big brown farmhouse table with a stretcher and two ladder-back chairs. A white front-loading washer with a dark round door stands on the far right. All read as plain real household furniture, not toys.
    - The theme's `wood` landed on the counter's door-panel frames, not its top.
    - My counter run stood in front of a bright doorway.
  - `kenney_bedroom.png` (bedroom A, with a figure and two cash bundles on the floor): a two-door dark-wood wardrobe with steel handles, a double bed (low wood frame, grey duvet, two pillows) and a boxy grey fabric sofa.
    - Beside the 180 figure they are a little large, as intended.
    - The cash bundles stay the most saturated thing in view.
  - Both rooms are otherwise the flat grey blockout (P3-2's job).
- **Seen, left for P3-3:**
  - Counter tops need their own material mapping.
  - A Kenney table built to the 120 vault height has an underside well under 130, so it is a vault surface, not a crawl-under. P3-3 decides which each table is.
  - Kenney UVs index a colour atlas, so furniture keeps flat theme colours, or gets textures triplanar (DECISIONS).
- **Next:** P3-2 builds the shell from the blockout and tries the texture shortlist (STYLE §3.3). P3-3 imports the rest of the Kenney pieces each room needs (`import_asset.mjs` at `--units=260`).
- **Not placed in the level:** the trial pieces are seen only through `--capture-prop`. P3-3 furnishes the rooms.
- Verify: `node autobuild/verify.mjs` healthy on the second run. 16 suites; symmetry 200/200.
  - Bot match 3v3: team_b in 439 s with 90 s of stalls. 1v1: 7 s of stalls. These are bit-identical to P2-4/P2-5: nothing in the game changed.
  - Tick budget: 1v1 0, 3v3 3 of 600 over, 4v4 3 (not gated). net_smoke: 1691 ticks agree.
  - **The first run failed on two wall-clock checks only**: 3v3 7 of 600 (p99 47.8 ms) and net_smoke "only 750 ticks compared (need 852)". The machine was slow during that run (same bot-match numbers, same sim). The re-run passed both. If either gate flakes again with no sim change, its margin needs looking at, not the code.

## 2026-11-13 — P2-5 Turnaround sheet
- **Tool:** `node autobuild/turnaround.mjs [--members=...] [--clip=jog@0.2]` writes `autobuild/slice/turnaround_<member>.png` for dad, mom, elder_girl, elder_boy, younger_girl, younger_boy. Each sheet is one capture of four drawn-only copies of the member in a row.
  - Left to right: front, right side, back, left side.
  - Each copy is turned against its own line of sight to the camera, so the outer copies are not skewed by perspective.
  - Same camera for all six (3 m away, level at 95 cm), so heights compare across sheets.
  - Drawn in the theme's rest pose (Idle frame 0), the same still pose the in-game idle shows.
- **Fixed from the frames:**
  - First attempt was in the strip between the houses, where the lineup stands. The two right copies stood in House A's shadow and the fronts were backlit. Moved to House A's back yard, shot toward the plain back wall: all four are evenly sunlit.
  - Side labels were swapped in my first reasoning. The wristband (left wrist, sage) is visible on the near arm of the copy facing screen-left, so that copy is the LEFT side. Labels and comments are corrected.
  - The row was moved along the wall so the back door is not behind a figure.
- **What the six sheets show:**
  - Every figure has the same blank egg head, a blue-grey long-sleeved shirt, grey-brown trousers, dark feet, putty hands, and a sage band on the left cuff. The band fits snugly on adults and kids alike and shows in the front, back and left views.
  - In profile every member's head sits on a neck tilted forward, the head ahead of the chest, as if peering. This reads as the intended slight "off" look and is the same on all six.
  - All six have the rest pose's wide stance and half-closed fists.
  - Female bodies (mom, elder_girl, younger_girl) show a chest and hips in front and profile. Male bodies show broader shoulders, and from the back the superhero V-shaped lats and deltoids still show through the shirt (known since P1-5).
  - Kids are visibly shorter, with bigger heads; younger_girl and younger_boy have the largest heads for their size.
  - **Defect seen, not fixed:** on the three male backs (dad, elder_boy, younger_boy) there is a ragged light patch at the back of the neck where the putty neck meets the shirt. The paint border is jagged there. The female backs have a clean neckline. It is small at chase distance. A fix belongs in `figure_bake.mjs` PAINT and needs a re-bake; left for the readability audit (P4-7) or a later figure pass.
- Counters per sheet: 609 draws, 78.6k triangles (the whole yard view plus four figures).
- Verify: `node autobuild/verify.mjs` healthy. 16 suites; symmetry 200/200. Bot match 3v3 won by team_b in 439 s with 90 s of stalls; 1v1 7 s. These are the same numbers as P2-4: nothing in the game changed. Tick budget 1v1 0, 3v3 0 of 600 over, 4v4 2 (not gated). net_smoke 1692 ticks agree.

## 2026-11-13 — P2-4 Team tell (D3 experiment)
- **The setting** is `TeamTell` (`godot/game/art/team_tell.gd`): four booleans, any combination: marker, minimap, wristband, kid_swap.
  - Shipped default in `godot/art/theme/team_tell.tres`.
  - The menu's four checkboxes and F5–F8 in a match save to `user://settings.cfg`.
  - `--team-tell=none|marker,minimap,...` overrides and is never saved.
  - Per machine, presentation only; nothing reaches the sim or the network.
  - Capture/pilot/net-smoke runs ignore the saved file, so tool frames depend only on their command line.
- **(a) marker**, `TeamTellOverlay`: a small point-down triangle in the family colour with a dark rim, over each of your own teammates' heads. Never over enemies or yourself; shown through walls; shrinks with distance.
- **(b) minimap**, same overlay: a top-right square with the indoor rooms outlined, your teammates as family-colour dots, you as a white arrow facing the camera. Turned so your house is at the bottom.
- **(c) wristband**, `ArtTheme.add_wristband`: a ring on `lowerarm_l` at the shirt cuff, in a satin family-colour material. Its radius is measured from the mesh's forearm/hand-weighted vertices, so it fits the adult and kid bodies alike. It rides every animation clip and fades with the local body.
- **(d) kid swap**: `member_for(team, slot, kid_swap)` uses the theme's new `family_order_by_team` (team_b: dad, mom, elder boy, younger girl). Toggling (c) or (d) in a match rebuilds the figures.
- **Default (REVIEW): minimap + wristband.** Why: see DECISIONS.
- **Frames** (`node autobuild/team_tell_frames.mjs` → `autobuild/frames/p2_4/<set>_{close,20m,40m}.png`):
  - Setup: both families stand in the strip, paired by slot. Seen from the camera, left to right: B younger, A younger, B elder, A elder, B mom, A mom, B dad, A dad. This machine is team_a.
  - `none_close`: the pairs are identical. Two younger boys, two elder girls, two moms, two dads.
  - `kid_swap_close`: B's younger child is now the girl (female body, smallest, chest visible) and B's elder child the boy (broader shoulders). Readable at 4 m only if you know the families. Adults stay identical.
  - `wristband_close`: a small terracotta or sage band on each figure's left wrist, on the cuff, neither floating nor sunk. The only colour on the figures.
  - `wristband_20m`, `wristband_40m`: the bands cannot be seen. Figures are ~45 px tall at 20 m and ~20 px at 40 m.
  - `marker_*`: triangles over the four team_a figures and over the live team_a bots, one of them inside House A (through the wall). None over team_b.
    - At 40 m the triangles were at first bigger than the heads. They now shrink from 9 px at 10 m to 5 px at 30 m, and `marker_40m` shows them about head-sized.
  - `minimap_*`: the minimap shows House A's 2×2 rooms at the bottom and House B's at the top. The stand-ins are a dot cluster in the gap, the two live team_a bots are dots, and you are a white arrow at your spawn. No team_b dots.
  - `default_20m`: nothing on the figures tells the families apart; only the minimap dots do.
  - `all_*`: everything at once. Close up, the markers and bands agree.
  - `menu.png`: a "Team tell" row of four checkboxes under Team size; Minimap and Wristband ticked. Unticked boxes are hard to see on the dark menu (Godot default theme; P5-1).
  - `toggle_sheet.png` (live, F7/F8/F5/F6 injected): the minimap is gone after F6. The figure was rebuilt after F7/F8 with no error.
- **Fixed from the frames:**
  - The first wristband frame showed 4 m-tall cylinders. The skinned mesh is in metres under a ×100 armature, so width and clearance are now converted to mesh units.
  - The minimap was tilted ~30°: the two spawn centres are not exactly opposite. It is now snapped to the nearer axis.
- **Note:** the toggle test wrote `user://settings.cfg` before capture runs were made transient. The session reset it to the default values (the file could not be deleted from here). It now pins minimap + wristband for this machine until changed in the menu.
- **Left:**
  - Whether the default is right needs a human playtest (D3 says playtesting decides).
  - The minimap is minimal (no floors, no rotation with the camera); P5-2 makes the final one.
  - The setting is not synced from the host (P5-1 lobby).
- Verify: `node autobuild/verify.mjs` healthy. 16 suites; symmetry 200/200. Bot match 3v3 won by team_b in 439 s with 90 s of stalls, 1v1 stalls 7 s; both are the same numbers as P2-3, as expected for a change that is presentation only. Tick budget 3v3 0 of 600 over, 4v4 0. net_smoke 1698 ticks agree.

## 2026-11-13 — P2-3 Animation driver
- **Picked up a cut-off session.** The driver was committed as `P2-3 (part)` (8c7fe69). The working tree held `--capture-press` (keys injected during a follow) and five P2-3 decision rows. Both were finished work; committed as e97825b.
- **The driver** is `FigureAnimator` (`game/art/figure_animator.gd`): one AnimationTree per figure, built in code and advanced by hand from `GreyBoxMain._render`.
  - A Transition over 17 base clips, a TimeScale from each clip's stride speed × figure scale (feet do not slide), then an arms-only OneShot for throw / grab / interact.
  - The clip choice is the static `base_clip`. Motion comes from the predicted world for your own body and the confirmed world for everyone else. Carrying and captured always come from the confirmed world.
- **Fixed this session, from the sheets:**
  - **Throw misfire.** A drop and a seized carrier's bundle also go `in_flight`, falling straight down. So the victim of a seize played a throw. The first scout run showed throws at the same instant as seizes (t=40.9 and t=75.5).
    - A throw now needs the bundle moving sideways (> 1 unit/s).
    - Re-scout: 3 throws in 95 s, all by the bot that was carrying, none at a seize.
  - **Throw timing.** The sim releases the bundle on the command's tick. In `throw_sheet` cell 1 the cash was already flying low ahead of hands still held up behind the head.
    - The one-shot now plays 0.2–0.9 s of the clip.
    - `throw2_sheet`: cell 1 shows the arms coming over and forward. Cell 2 shows both hands pushed out at shoulder height, the bundle just past the fingertips. Cell 3 shows arms extended, bundle flying ahead. Then the jog arms return.
  - **Seize/free reach barely visible.** Interact played the whole 2 s at ×2.2. It now plays 0.4–1.6 s at ×1.6.
    - `seize3_sheet` cells 2–4: one arm held straight out at chest height through three cells (~0.25 s) while the legs keep jogging.
  - **Stride hitch.** Bots stop for one tick between errands (`seize2_sheet` cell 4: speed 0, clip idle). The Transition then restarted the jog from frame 0.
    - Added `STILL_GRACE` 0.1 s.
    - `seize3_sheet` cell 3 has the same one-tick stop (speed 0) and the clip stays `jog`.
- **New tools:**
  - `--capture-follow=on:<throw|grab|seize|free>,…` waits for that one-shot and follows whoever fires it.
  - `--anim-log` prints every one-shot.
  - Why: windowed bot matches drift apart between runs. A fixed-time follow meant to catch a throw at t≈41 instead shot a body sitting in jail for all 24 cells (`a0_throw_sheet`).
- **Contact sheets** (`autobuild/frames/p2_3/`, live 3v3 bot play unless noted; each cell's clip is printed by the run):
  - `a1_side`, `b0_side`: jog everywhere at 440. Long strides with a flight phase on floors, stairs and lawn. Feet on the ground, no visible slide. Clip `jog` every cell.
  - `me_jump_side` (own seat, W held + Space): jog → knees tucked in the air → a stoop on landing → upright → idle. Idle is motionless with arms at the sides.
  - `me_crouch_side` (own seat, Shift + W): a low hunched crouch-walk, knees deep, arms hanging back. At ×3.0 the stills show no foot slide. Whether it looks frantic in motion is not visible in stills.
  - `a1_grab_front` (elder girl): jog, then a grab reach, then both hands overhead with the bundle sitting on them, held through the carry jog.
  - `throw2`, `seize3`, `free`: as above. In `free` the freer is seen beside the released teammate in cells 1–2, then jogs off with a small forward reach.
- **Left:**
  - Panic run (arms up) never shows yet: nothing moves faster than move_speed until P4-1's boost. The driver reads speed, so it needs no change.
  - Jail run-in-place: a captured body plays idle (P4-3).
  - On the release frame the bundle jumps from the hands to the sim's arc start at the body's centre (P4-5 tumble/bounce).
  - The follow camera has no collision and ends up inside walls in some cells (tool only).
  - The grab reaches to table height while cash lies on the floor.
- Verify: `node autobuild/verify.mjs` healthy. 16 suites; symmetry 200/200; bot match 3v3 won by team_b in 439 s with 90 s of stalls (budget 400); 1v1 stalls 7 s; tick budget 3v3 0 of 600 over, 4v4 3 (not gated); net_smoke 1709 ticks agree.

## 2026-11-13 — P2-2 One skeleton, one animation set
- **The set** is `godot/art/characters/figure_anims.res`: one `AnimationLibrary`, 24 clips, 348 KB, the same for all six family members. `figure_anims.json` beside it lists lengths and stride speeds.
  - Built by `node autobuild/run_tool.mjs build_figure_anims` (`tools/build_figure_anims.gd`). Godot reads `UAL1_Standard.glb` from the gitignored zip folder at runtime and resamples the chosen clips at 30 fps. A rebuild is byte-identical (same SHA-1).
  - Rotation tracks only, for 22 body bones, plus the pelvis position as a change from the library's idle, ×1.07 for the bodies' longer legs. No scale tracks, so the family's sizes and the theme nudge survive playback. Fingers keep the rest pose.
  - Leg ratio measured: figure 0.888 m hip→ankle against the library's 0.830.
- **Clips (D9 list → name):**
  - idle (one still frame) and walk (Walk_Formal: arms held at the sides). `walk_loose` (arm swing) is kept as an alternative.
  - jog and sprint, and panic_run = the jog with both arms straight up.
  - crouch_idle (still) and crouch_walk, both with stiff hanging arms.
  - jump_start (lift-off → tuck, 0.33 s), jump_air (one held pose) and jump_land (last 0.52 s: a stoop back to standing). Arms stiff; the pelvis never rises above idle (the sim owns height).
  - carry_* versions of idle/walk/jog/crouch_idle/crouch_walk/jump_*, with the cash held overhead. There is no carry_sprint: a panicking carrier runs as carry_jog, faster.
  - throw (carry → hands back → two-handed push → arms down, 0.9 s), grab (PickUp_Table), and interact (Interact: one arm reaches out, for free ally and seize).
  - arms_carry and arms_panic are arm-only layers.
  - Jail run-in-place has no clip of its own: every clip is in place, so a jailed body plays jog/panic_run where it stands (P4-3).
- **Arm poses the library lacks** are two-bone IK on the figure's own rest skeleton: cash overhead, panic arms, throw back and push. Each is stored as clavicle-relative rotations, so it rides whatever torso it is laid on.
- **Stride speeds** (model units/s at playback 1, from the root-motion copy): walk 104, jog 573, sprint 883, crouch-walk 80. The sim moves at 440 (jog ×0.77), carry 374 (jog ×0.65) and crouch 242 (crouch-walk ×3.0, which may look frantic; P2-3 to judge).
  - These are in the model's own units, before `shape_figure` scales it to the member's height. P2-3 must multiply by the figure's scale.
- **Seeing it:** `--capture-figure=x,y,z,yaw,member,clip@seconds` holds a stand-in in a clip (`FigureAnimation.pose`). `node autobuild/anim_sheet.mjs [--clips=] [--member=]` stands six figures at six moments in the strip between the houses and shoots side and three-quarter views to `autobuild/frames/p2_2/<clip>[_member]_{side,front}.png`.
- **What the frames showed** (dad unless named; the sheets read left to right after one fix, see below):
  - `walk_side`: a stiff stride, arms still at the sides, head pitched forward (the idle's posture), soles on the lawn in every phase. `walk_loose_side`: the same legs with the arms swinging.
  - `jog`: long strides with a forward lean and a flight phase where both feet leave the ground. `panic_run_side`/`_front`: the same jog, upright, both arms straight up with fists over the head. It reads as "running from something".
    - First attempt was on the sprint: a deep athletic lean with the arms reaching forward. Changed to the jog with the arms aimed slightly back.
  - `carry_idle_front` and `carry_jog_front`: both hands together a hand-width apart above the crown, elbows out. The cash (P2-3 attaches it) will sit there.
  - `throw_front`/`_side`: carry → hands drawn back behind the head → arms straight out at shoulder height → arms coming down → standing.
  - `crouch_walk_side`: a low hunched shuffle, knees deep, arms hanging back along the bent torso.
    - The library's own crouch held its hands up by the face (a sneak) and was replaced.
  - `jump_start_side`: knees tucking up, arms at the sides, feet leaving the ground. `jump_land_side`: a forward stoop straightening to standing.
    - The library's jump (crouch wind-up, one arm flung skyward, deep landing squat) was replaced.
  - `interact_side`: one arm reaches forward at chest height and returns. `grab_side`: both hands reach down-forward to waist height and return. `idle_front`: six identical motionless figures.
  - `walk/jog/crouch_walk_younger_boy_side`: the narrowed pelvis and short thighs (P2-1's worry) show no shearing or stretching, and the feet meet the ground.
- **Fixed on the way:**
  - `carry_crouch_walk` pointed the arms straight AHEAD at head height, like a battering ram. The carry pose is torso-relative and the crouch bends the torso ~80°.
    - The crouch rows now carry a `carry_crouch` pose, solved by IK on the skeleton bent into the crouch, aiming the hands 24 cm over the head in world up.
    - Re-shot, `carry_crouch_walk_side` and `carry_crouch_idle_front`: hunched figures with the hands clasped over the top and back of the head. That reads as "something held on the head", not ahead. The hands sit closer to the crown than aimed; accepted.
    - `carry_sprint` showed the same tilt; it was dropped.
  - The first sheets ran right to left (the cameras look +z, so screen right is −x), so the order was reversed.
  - The three-quarter camera stood inside House A.
  - The last figure clipped House A's wall; spacing 105 → 90.
- **Left for P2-3:**
  - The driver: state machine, playback speed from `stride_speed`, the carried bundle placed between the hands.
  - Judging crouch-walk at ×3.0 and whether jump_land's stoop is the "tiny wobble" D9 asks for; a procedural dip may be better.
  - grab reaches to table height; cash on the floor may want a lower reach.
  - The crouch's pelvis drop is scaled for dad's legs. The younger kids' ×0.94 thighs may leave the feet 1-2 cm below the floor in a deep crouch (not visible in the sheets).

## 2026-11-13 — P2-1 The family of four
- **Decimation** (`autobuild/figure_bake.mjs`): the bodies are welded by position first. UV seams buy nothing without a texture, and they are what stopped the P1-6 simplifier at half. Then a quadric half-edge collapse runs to `--max-tris` (default 5000). Every kept vertex keeps its own skin weights. It never collapses across a paint border, never moves an open boundary inward, never flips a face, and keeps the mesh manifold.
  - Male 12,566 → 5,000 triangles (2,502 vertices); female 12,812 → 5,000. Under a second each. 199 KB per .bin (was ~565 KB).
  - STYLE budget is ≤ 6k per member.
- **Muscle relief** (P1-5 left it): shading normals now come from a 24-pass Laplacian-smoothed copy of the body. The positions are untouched (`--normal-smooth`). In `cam_garden_open` the abs, pecs and back muscles stopped catching the light. The outline is still the broad superhero one (lats, deltoids).
- **Collar:** at 0.815 of the height, the decimated shirt read as a low scoop with a bare upper chest. Raised to 0.832, and the shoulder tops (wider than the head) are now clothed up to 0.88. After those two attempts a small pale patch remains at the sternum/neck in sunlit frames. Left as is.
- **The family is data** (`FamilyMember` resource, `game/art/family_member.gd`; six in `default_theme.tres`). Each has a model, a drawn height and its own bone scales, multiplied onto the theme's shared nudge.
  - Dad: male body, 180, legs ×0.97.
  - Mom: female body, 176.
  - Elder girl / elder boy: female / male body, 160. Pelvis x ×0.87, z ×0.9 narrows the whole build; the head is given its width back and enlarged a further ×1.08.
  - Younger girl / younger boy: 145. Build ×0.86 / ×0.9, head a further ×1.25, upper arms and thighs ×0.94.
  - `family_order` maps roster slot to member: dad, mom, elder girl, younger boy, the same in both families. `family_order_by_team` is the hook for P2-4's kid swap.
  - The game draws each body as `member_for(entity.team, entity.slot)`. `--capture-figure=x,y,z,yaw,<member id>` stands one member.
- **Height after the nudges:** `shape_figure` now measures the crown raise from the posed Head bone and the feet lift from the posed foot bone. It scales the model to exactly the member's height and moves it down by the lift.
  - Measured: the shared nudge alone adds ~8 cm of crown (dad would have stood 188 against the 180 cap). Younger kids: +16 cm crown, 4.7 cm feet lift.
  - Without a member the old cap-only path is unchanged, so the P1-5 slice reproduces.
- **Frames** (`node autobuild/family_lineup.mjs` → `autobuild/frames/p2_1/lineup_*.png`; six members in a row between the houses):
  - `lineup_front` (~4.5 m): four clear height steps, blank egg heads, blue-grey shirts, grey-brown trousers, dark shoes.
    - Dad and mom read as adults (broad dad, narrower mom with a waist).
    - The elder pair are visibly narrower; shoulder width / height ≈ 0.33 against dad's 0.43.
    - The younger pair have clearly big heads on narrow bodies and read as children.
    - The elder boy still reads a little like a short slim man.
  - `lineup_side`: every figure leans its head forward on a long neck. That is the idle frame's posture plus the neck nudge, and it reads as "slightly off" rather than broken. Feet are flat on the lawn for all six, including the shortened legs.
  - `lineup_back`: smooth backs, no holes or torn seams from the decimation.
  - `lineup_front_20m`: the four sizes step down plainly by outline.
  - `lineup_front_40m`: figures ~20 px tall; the steps are only just visible.
  - In game: `cam_garden_open` shows two dads (slot 0 of each team), shaded flatter than before. `cam_jail` shows the own body standing in the room. In `cam_study_vault_a` the faded own body draws as one clean see-through mesh. The P0-6 box placeholder's inner faces are gone; only finger interiors faintly show.
  - Render: lineup close-up 549 draws / 84k triangles with six figures and their shadow pass. `cam_garden_open` 62k triangles (was 82k at P1-5).
- verify (full): healthy.
  - 16 suites at their pinned counts; symmetry 200/200.
  - Bot match 3v3: deterministic, winner team_b, 90 s stalls. 1v1: team_b, 7 s. Identical to P1-6, since nothing in the sim changed.
  - Tick budget: 0 of 600 over at 1v1/3v3/4v4 (p99 6.6 / 22.7 / 24.4 ms).
  - Network ok, 1685 ticks agree.
- **Left:**
  - The bodies are still superhero-built in outline. A real Regular/Teen body (BLOCKED.md) would fix it; the theme would take it by changing `model` only.
  - Kids' proportions are bone scales on adult bodies. P2-2/P2-3 must check that the walk cycle on a ×0.87 pelvis and short thighs does not shear visibly.
  - The idle frame baked into the rest pose stays until P2-3 drives the skeleton. Bots still slide without walking.

## 2026-11-13 — P1-6 Asset import pipeline
- **Picked up from a cut-off session.** Three untracked files were waiting: `autobuild/fetch_polyhaven.mjs`, `autobuild/import_asset.mjs` and `godot/tools/import_asset.gd`, with `wooden_table_02` already downloaded. It was one task, so this session finished it.
- **The path** (documented in `godot/art/README.md`, "Importing a downloaded model"):
  1. `fetch_polyhaven.mjs <slug>` downloads into the gitignored `autobuild/Incoming/` and checks every file's md5.
  2. `import_asset.mjs <source> --out=res://art/props/<name>.glb [flags]` runs `tools/import_asset.gd` headless. It reads glb, gltf or fbx at runtime, drops collision, cameras, lights and animation, and refuses skinned meshes. It bakes transforms and scales to 1 unit = 1 cm (`--units=auto|m|cm|<factor>`, `--height`, `--fit`, `--yaw`). Pivot goes at the base. Output is one mesh with one surface per material name. Textures are dropped, UVs kept, and surfaces are renamed to theme names (`--material=`). Budget is checked per `--role`, with decimation via `--max-tris`. It prints a draft ASSETS.md row. After that, Godot imports the .glb, and the importer writes `<name>.source.json` so `--again`/`--all` can rebuild it.
  3. In game: `ArtTheme.current().prop_instance(path)` dresses the prop from the theme, or returns `null` when the file is missing so the caller keeps its primitive. The theme gained a `prop` default and four generic materials (`wood`, `fabric`, `steel`, `painted`) in `by_source_name`.
  4. To see a prop: `--capture-prop=res://model,x,y,z,yaw` stands a drawn-only one in every shot.
- **Fixed in what the previous session left:**
  - The texture-error filter leaked PNG errors whose keyword was on the `at:` line. It now judges each engine error block as a whole.
  - Decimation did nothing on a small mesh and only halved a big one. It now repeats the engine simplifier on its own output and compacts unused vertices. It also says plainly when it cannot reach the target. Measured on Poly Haven `ArmChair_01` (5626 triangles): one level at exactly half, then nothing, at normal-merge angles 25, 90 and 180. The simplifier will not cross UV/normal seams. That was two attempts, so it was logged rather than replaced with a seam-tearing simplifier (DECISIONS).
  - The flag lines printed as "units"; they now print as "step". The ASSETS.md row uses `--url`/`--licence`.
- **Samples** (CC0, ASSETS.md + CREDITS.md):
  - `wooden_table_02`: `--height=120 --material=wood`, 196 triangles, 170 × 120 × 106.
  - `armchair_01`: `--units=130 --max-tris=2000 --material=fabric`, decimated 5626 → 2366, so "heavy" (under the 6k max), 110 × 139 × 100.
  - `--all` re-run: both .glb byte-identical (same SHA-1).
- **Frames** (`autobuild/frames/p1_6/`, House A study, with a dad figure for scale):
  - `props_1`, `props_2`: the table stands on the green carpet, legs and top intact, in the theme's red-brown oak. Its top is at about two thirds of the figure's height, as STYLE §3.1's 120 threshold intends. The armchair was hidden behind the figure in both.
  - `chair_1`, `chair_2`: after decimation the armchair is intact: carved legs, curved back, arms and seat cushion, no holes or torn seams. It is in the grey-taupe theme fabric and stands on the floor. Seat height is about mid-thigh on the figure (1.3× real).
  - Render stats for `chair_1`: 65 draws, 50k triangles (the figure is 12.6k of it).
- verify (full): healthy. 16 suites at their pinned counts; symmetry 200/200. Bot match 3v3: DETERMINISTIC, winner team_b, 90 s stalls. Bot match 1v1: team_b, 7 s (the same as P1-5; nothing in the sim changed). Tick budget 0 of 600 over at 1v1/3v3/4v4 (p99 6.5 / 24.1 / 24.1 ms). Network ok, 1712 ticks agree.
- **Left:**
  - P3-1 picks the real kit. The two samples are placed nowhere in the level.
  - Theme materials have no textures yet. The UVs are kept for when they do.
  - Models that need cutting below about half go through Blender first, and nothing in the loop does that yet.

## 2026-11-13 — P1-5 Style slice
- **Figures first.** The slice needed the Quaternius bodies, and none had been extracted yet. The free bodies (D10, P1-2) come T-posed, metre scale, 12.6k triangles, with separate eye and eyebrow meshes. New `autobuild/figure_bake.mjs` (Node, reads the zips extracted into the gitignored `autobuild/Incoming/x/`) writes `godot/art/characters/figure_{male,female}.gltf/.bin`:
  - eyes, brows and textures dropped;
  - the head projected onto a fitted ellipsoid (an egg: no eyes, nose, mouth or ears);
  - `Idle_Loop` frame 0 from the Animation Library (same bone names) baked into the rest pose;
  - ×100 to centimetres;
  - a painted-clothes vertex colour added. A theme material uses it or ignores it.

  The male is 181 tall, the female 177. Godot draws them at ≤ 180 (`figure_height`).
  - First tried Taubin smoothing for the face (60 passes). It moved the head 0.4 cm on average and the frame still showed sockets and a mouth. There were no holes to fill (the hole-fill found 0). So the head is projected instead.
- **Theme hooks** (`ArtTheme`):
  - `figure_model`, `figure_height` (cap, never stretch), `figure_bone_scales` (the "slightly off", as bone pose scale);
  - `--art-theme=res://...tres` swaps the whole theme, no code change.

  `--capture-figure=x,y,z,yaw[,model]` stands drawn-only figures in every shot. The game now draws every body as the theme's figure. `_figure_instance` wraps it in a holder so the crouch squash does not undo the theme scale. Fallbacks are unchanged.
- **The slice:** `autobuild/style_slice.mjs`. It shoots House A's study (a cash/vault room) with a dad (male body) and a mom (female body) stood by the cash. Four views each: `chase` (the real rig and the seat's own faded body), `room`, `figures` (close), `backlit`. Variants are whole theme files, `godot/art/theme/slice_{a,b,c}.tres`, generated from the default by `autobuild/slice_themes.mjs`. `pick` = `default_theme.tres`. 16 frames in `autobuild/slice/`.
- **What each frame showed** (final captures):
  - **A "putty"** (bare satin putty, torso +6 %, P1-4 lighting): smooth egg heads, no features. But bare superhero bodies, with sculpted abs, pecs, a female chest and buttocks. That reads as an anatomy model or mannequin, not as a person. Figure value is close to the warm beige walls (`a_figures`, `a_room`). Chase: the faded own body shows through itself.
  - **B "painted"** (vertex-painted clothes, matt; warm lamps on, low sun):
    - First try: clothes read as a dark wetsuit and the room was murky brown (ambient 0.55).
    - Second try: ambient 0.7, lighter paint. The room was warm and readable.
    - Then found that paints 2 and 3 had never reached Godot (below).
    - Final B: blue-grey shirt, grey-brown trousers, dark shoes; pale blank head and hands pop. Lamp pools faint on the green carpet.
  - **C "vinyl"** (glossy pale, head ×1.14, neck ×1.18, small hands; overcast, no sun shadow): cool grey-white room, even and flat. The figures read as shop-window mannequins (STYLE §2.1 says not). The big head is plainly visible in `c_chase`, so the bone scales work. It is cheapest (no shadow pass: 24–379 draws against A's 59–684).
  - **Pick** (`pick_*`): B's clothes, C's nudge halved (head ×1.08, neck ×1.08, torso ×1.04, hands ×1.06), A's lighting. `pick_figures`: a blue-grey shirt a step under the pale egg head, grey-brown trousers, dark shoes. The figures separate from the warm walls by hue as well as value. `pick_room`: the two figures and both cash bundles are readable at room distance.
- **STYLE-PICK** (DECISIONS, REVIEW): the pick above, adopted into `default_theme.tres`; STYLE §2.3 updated.
- **Bug found and fixed:** Godot re-imports a `.gltf` only when the .gltf changes, not its `.bin`. Two paint changes produced identical frames. The bake now writes the bin's SHA-1 into `asset.extras`.
- **In game** (`verify --frames-only --views=cam_garden_open,cam_jail`):
  - `cam_garden_open`: bots drawn as the new figure, idle-posed and sliding (no animation until P2-3), with sun shadows on the lawn. Sunlit heads are near white; muscle relief shows through the painted shirt.
  - `cam_jail`: the figure's blue-grey shirt separates from the warm concrete. That was P1-4's open "figure close in value to the walls" item.
  - Garden view 680 draws, 82k triangles (was 27k; 8 figures × 12.6k + shadow pass); budget 300k.
- verify (full): healthy. 16 suites at pinned counts; symmetry 200/200; bot_match 3v3 DETERMINISTIC team_b, 90 s stalls; 1v1 team_b, 7 s (unchanged: presentation only); tick budget 0 of 600 over at 1v1/3v3/4v4 (p99 6.4 / 23.5 / 22.3 ms); network ok (1711 ticks agree).
- **Left:** decimate the figures to the 6k budget and build the four family members (P2-1); smooth the muscle relief (P2-1). Bodies are static idle until P2-3, and crouch still squashes the figure. Sunlit heads lean white outdoors (P3-5).

## 2026-11-13 — P1-4 ArtTheme
- **Picked up from a cut-off session.** The tree held an uncommitted, unverified P1-4: `game/art/art_theme.gd`, `art/theme/default_theme.tres`, and edits to `greybox_main.gd` / `world_backdrop.gd`. `verify --quick` was green with it, so this session finished it rather than stashing it.
- **What it is.** `ArtTheme` (Resource; `ArtTheme.current()` loads the .tres, or built-in defaults if it is missing) holds the figure material (STYLE §2.3 putty satin with rim), family colours, cash materials by source name, the blockout's wall/floor/ceiling/lawn/roof colours, a floor finish per room kind, the sky, sun, fills, ambient, tonemap, and the room lamps.
  - Every figure (stand-in, `.glb` model or capsule fallback) is drawn in a per-body copy of the one figure material, so the P0-6 fade still works.
  - The cash `.glb` is re-materialed by source material name (NotePale / NoteDeep / Band / Seal).
  - Each blockout box is one vertex-coloured mesh: walls, floor and ceiling by face direction, the lawn on the lot's ground box, roof tile on the highest boxes. Still one draw per box.
  - Team floor tints are gone. Each room gets its finish by room kind instead (oak halls, cream tile kitchen, concrete jail, grey/green/beige carpets, lawn yards, path lot).
  - Figures carry no team colour (`figure_family_tint` 0, STYLE §2.4). Until P2-4 a player has no team tell at all.
- **Measured (render_stats, GT 730M, 60 timed frames). GPU ms for kitchen / approach_from_south:**
  - As found (2-split sun shadow + 16 ceiling spots): 11.5 / 9.0. Over the 9 ms budget.
  - Shadow off: 8.1 / 7.1.
  - Shadow off and lamps off: 4.3 / 3.1.
  - Lamps on, but the outdoor ground, backdrop plane and yard finishes moved to render layer 2, which the lamps skip: 8.0 / 3.4. Compatibility redraws each object for every spot touching it, and the screen-filling ground was being redrawn for each ground-floor lamp.
  - One orthogonal shadow + lamps: 10.2 / 5.9.
  - **Final (one orthogonal shadow, lamps off): 7.7 / 6.0, draws 652 / 1045.** `cam_garden_wall_backed` (faded body) 7.8 ms. The 1045 is over the 1000 draw budget because the shadow pass draws every unmerged blockout box again (526 → 1045). P3-6 merges them.
- **Frames, what they showed, in order:**
  1. As found: interiors cold blue-grey (the sun's shadow left only a cool ambient), lamps a barely visible pool, the house's shadow a near-black green slab, roofs orange (box tops were all "floor"). The palette also came out washed: vertex colours were read as linear (fixed with `vertex_color_is_srgb`).
  2. Warm ambient + Filmic: warm, but the lawn went lime and interiors were one flat beige, the ceiling lighter than the walls.
  3. Added a shadowless warm "sky fill" directional from above (base pass, nearly free) and set the tonemap white to 4: floors brightest, ceiling darker. But the overview showed sunlit walls and figures pure white and the lawn lime.
  4. Back to Linear with energies recomputed from what the frames showed (a directional light lit about 2.4× harder per unit than the Lambert estimate): natural green lawn, grey roofs, a sun shadow under every figure. Interiors were too flat at ambient 1.0.
  5. **Final** (ambient 0.75 warm-neutral, sky fill 0.5 from (−1, 3, 1), cool fill 0.2, sun 0.38):
     - `room_a_gf_kitchen`: cream floor brightest, walls taupe, ceiling darkest by a small margin over one wall.
     - `room_b_gf_kitchen`: the same, plus a sun patch through the garden door onto the floor.
     - `cam_garden_open`: three putty figures with sun shadows on a mid-green lawn; the sun-facing wall behind them is near-white cream.
     - `cam_study_vault_a`: banded green cash clearly readable on the green-grey carpet; the faded own body is translucent putty with its inner boxes showing (the known placeholder artefact).
     - `cam_jail`: warm, but the figure is close in value to the walls.
     - `lot_overview`: two cream houses with grey roofs, a shadow on the lawn, blue sky fading to a pale horizon.
- **Not done, on cost:** room lamps are built but off (`interior_lamps`). Filmic was dropped after two attempts. Both are logged in DECISIONS (REVIEW) and STYLE §4 "As built".
- verify (full): healthy. 16 suites at pinned counts; symmetry 200/200; bot_match 3v3 DETERMINISTIC team_b, 90 s stalls; 1v1 team_b, 7 s (unchanged: presentation only); tick budget 0 of 600 over at 1v1/3v3/4v4 (p99 6.4 / 22.9 / 22.9 ms); network ok (1707 ticks agree).
- Left for P1-5/P3-5: figure-vs-wall value separation in the jail, and figures leaning cream under the warm ambient (P1-5's figure treatments). Ceilings only just darkest; sun-facing outside walls near white (P3-5's lighting pass). Lamps per room once fittings exist and the blockout is merged (P3-5/P3-6). The rim term is faint.

## 2026-11-13 — P1-3 STYLE.md
- **STYLE.md now has the art direction (§1–6) above P1-1's budgets.** §1 says it in one paragraph: plain people in a real house. The house plays it straight and the figures are the joke. §2 covers the figures: blank (no eyes, brows, mouth, hair or ears), identical across both families, and "slightly off" by one 5–10 % nudge each. Explicitly not crash-test dummies and not shop mannequins. Heights are dad 180, mom 176, elder child 160, younger 145. None is ever taller than the 180 sim body, and every one standing is taller than the 130 crouch gap. One material: satin warm putty grey, deliberately not a skin tone, with a faint rim term and vertex AO only. §2.4 covers team identity: figures carry no team colour. The family colours (sage / terracotta, REVIEW) are used only for the D3 (c) wristband, HUD/minimap and each house's front door and window frames. §3 covers the house. It is built to the threshold set (counters and tables exactly 120, crawl-unders ≥ 130 clear, blockers ≥ 210), so furniture is about 1.3× real and the figures are not scaled up. §3 also has a room-by-room table (the jail is a utility room with a cage-like pen, the cash rooms are a study and a bedroom with a steel safe), the palette with roughness, a saturation rule (the house stays below ~35 % except cash and family colours), about 2 texels per unit, and the readability rules. §4 covers lighting: warm sun, shadowless cool fill, warm 2700–3000 K interior lights at ≤ 2 per object with no omni/spot shadows, the sun as the only possible shadow caster, a contact shadow under every figure and bundle, and baked vertex AO. §5 summarises motion, effects and sound. §6 is a 9-point "polished" checklist to judge clean frames by.
- **References:** `autobuild/references/` holds only `.gitkeep`, so nothing in STYLE.md is derived from an image. It comes from D2/D3/D9/D10, `WORLD_AUTHORING` §10/§12 and the measured house (`build_house.gd`: rooms 1000², doors 240×240, 320 clear, walls 30, slabs 40).
- **Decisions logged** (DECISIONS.md, P1-3): figure material (REVIEW), drawn heights (REVIEW), family colours and where they appear (REVIEW), furniture at threshold scale with figures unscaled, and room uses.
- verify (full): healthy. 16 suites at pinned counts; symmetry 200/200; bot_match 3v3 DETERMINISTIC team_b, 90 s stalls; 1v1 team_b, 7 s; tick budget 1v1 0, 3v3 0, 4v4 3 of 600 over (p99 6.6 / 21.9 / 29.6 ms; 4v4 not gated); network ok (1713 ticks agree).
- Left: whether Compatibility draws the rim term and honours tonemapping is checked by frame in P1-4. P1-5 tries three figure treatments against §2.

## 2026-11-13 — P1-2 Asset ledger
- **`ASSETS.md`** (name · source · licence · date · modified? · where) and **`CREDITS.md`** (what the credits screen will show) are new. Rows: the two Quaternius packs, the project's own procedural models (cash, placeholder figures A/B), Godot itself, and the Godot MCP editor plugin.
- **Checked inside the zips** by reading their central directories with Node (no extraction, nothing new on disk). Both carry a CC0 1.0 licence file: `License_Standard.txt` in the characters zip, and `License.txt` plus `README.txt` in the animation zip.
- **Finding: the free character pack has no Regular or Teen bodies.** Its 128 entries are `Superhero_Male_FullBody` and `Superhero_Female_FullBody` (glTF for Godot at ~0.8 MB each, plus FBX), 2K-ish skin/eye/hair textures, and 8 hair/eyebrow/beard meshes. The Regular/Teen bodies D10 names are in the paid Source version. Decision (REVIEW): build the family of four from the two free bodies on their shared rig. Note in BLOCKED.md in case the user wants to buy or find the real ones; nothing waits on it. The animation zip holds `UAL1_Standard.glb` and `UAL1_Standard_RM.glb` (root motion).
- **Flagged:** `godot/addons/godot_mcp` ("by mkdevkit", v0.1.0) has no licence or URL in the repo, and its three runtime bridges are autoloads, so an export would ship them. It is recorded as something to strip from release builds (or license) before P7-1.
- `project.godot` points `config/icon` at `res://icon.svg`, which does not exist. Not an asset problem now; the game icon is a P7 job.
- verify --quick: healthy (docs only; the full verify for P1-1 ran healthy on the same code minutes earlier).
- Left: nothing for P1-2. P2-1 extracts what it uses from the zips into `godot/art/` and fills in the "Modified?" column.

## 2026-11-13 — P1-1 Render stats tool
- **Instrument:** `game/debug/render_stats.gd` (`RenderStats`). It reads the renderer's own counters for the frame a capture just saved: draw calls, triangles, objects, video/texture/buffer memory, and the seat viewport's shadow-pass draws and triangles. With `--capture-timing=N` it also turns vsync off and times N frames while the match plays: median/p95/worst frame interval, plus the seat viewport's measured GPU and CPU render time. Flags on the existing capture path: `--capture-stats` and `--capture-timing=N`. One `RENDER_STATS <view> {json}` line per shot. `autobuild/render_stats.mjs [--views=prefix] [--timing=N]` runs every view in views.json windowed, prints a table and a summary, checks `autobuild/render_budget.json`, and writes `autobuild/frames/render_stats.json` plus each frame to `autobuild/frames/stats/`. `verify.mjs --frames` now prints the counters under each shot.
- It is not `godot/tools/render_stats.gd` as PLAN named it. Tools run `--headless`, and there every counter is zero (logged in DECISIONS).
- **Machine check:** Godot prints `OpenGL API 3.3.0 NVIDIA 425.91 - Compatibility - Using Device: NVIDIA - GeForce GT 730M`. So windowed captures on this PC use the real dGPU, not the Intel iGPU, and the frame times are real.
- **Baseline** (45 views, 120 timed frames each, 3v3 with bots, grey blockout, 1600×900): draw calls median 168, max 526 (whole-lot views). Draw calls equal objects, because every blockout box is its own mesh. Triangles median 8.9k, max 27k. Seat GPU time median 3.75 ms, range 2.3 ms (sky and ground only) to 5.35 ms. Frame interval median 5.6 ms (~175 fps), worst view's median 8.0. p95 8.5–16.0 ms, single worst frame 27.7 ms. Video memory 37–50 MB, textures 24 MB. No shadow passes. GPU time hardly moves with geometry (2.3 → 2.9 ms from 0 to 27k triangles), so the p95 and worst frames are simulation ticks, not drawing. Full table in STYLE.md.
- **What the frame showed for the heaviest GPU view** (`cam_garden_wall_backed`, 5.35 ms): the own body faded to 25% filling the middle third of the screen, as a stack of translucent red/grey/blue boxes over the green ground and the red yard tint. That is overdraw from the P0-6 fade (alpha copies plus depth pre-pass), about 1.5 ms over a normal chase view. The same is seen in `cam_jail_corner` and `cam_study_vault_a/b`, which are all faded-body views. The verify line under it read `draws 52, triangles 4048, objects 74`.
- **Budgets proposed** (STYLE.md §Budgets, `render_budget.json`). The target is 60 fps at 4v4 in the worst view. Per view: ≤ 1000 draw calls (the seat's CPU render time measured ~4.5 µs a draw), ≤ 300k triangles, seat GPU ≤ 9 ms, frame median ≤ 12 ms, textures ≤ 256 MB, video ≤ 512 MB. Per asset: family member ≤ 6k triangles, one theme material. Prop ≤ 2k (hero ≤ 6k). Cash ≤ 500. A furnished room ≤ 40k triangles and ≤ 60 dressing draws. Plus rules: no shadowed omni/spot lights, at most one shadowed directional, ≤ 2 omni/spot per object, merge or instance static dressing. All views are within budget today.
- STYLE.md is new and holds only the budgets; P1-3 writes the art direction above them. godot/CLAUDE.md lists the new flags.
- verify (full): healthy. 16 suites at pinned counts; symmetry 200/200; bot_match 3v3 DETERMINISTIC team_b 90 s stalls, 1v1 team_b 7 s (unchanged: presentation-side change only); tick budget 0 of 600 over at 1v1/3v3/4v4 (p99 6.6 / 23.9 / 22.8 ms); network ok (1710 ticks agree).
- Left: the budget is not a verify gate (one run ~15 min; P3-6 makes it one). The cost of an interior omni light in Compatibility is not yet measured, so P1-4/P3-5 should run `render_stats.mjs --views=room_` before and after adding lights. The p95 frame spikes belong to the simulation (P0-2b territory), not the renderer.

## 2026-11-13 — P0-10 Housekeeping
- Root `CLAUDE.md` rewritten. It said the Three.js branch `claude/game-mvp-dev-pl5suo` was the code source of truth with "Phase 4 next". It now names `godot/` (Godot 4.7, Compatibility, typed GDScript; D1/D5) as the source of truth, points to `godot/CLAUDE.md` and `godot/PROJECT_MEMORY.md`, lists the autobuild files (DECISIONS / PLAN / PROGRESS / BLOCKED / autobuild README) and the three verify commands, and says Godot runs through `GODOT_BIN`.
- `client/` and `server/` are marked **legacy** (kept, not developed, nothing deleted). The no-test-code rule and "don't change server/zones.ts/floorplan.ts" are scoped to them only. The note that `godot/` has its own testing policy is kept.
- The graphify graph in `graphify-out/` was checked: GRAPH_REPORT.md never mentions godot, so CLAUDE.md now says it covers the legacy code only.
- verify --quick: healthy (docs only; the full verify for P0-9, run minutes earlier on the same code, was healthy).
- Left: root `README.md` still describes the Three.js MVP; P7-3 rewrites it.

## 2026-11-13 — P0-9 Network smoke
- **Picked up from a cut-off session.** Commit `42d6cc4` ("P0-9 (part)") had added the two-process smoke and the snapshot fix but no verify gate and no log entry. This session measured it, gated it and wrote it up.
- **Instrument: `autobuild/net_smoke.mjs` + `game/debug/net_smoke.gd`.** Two headless copies of the REAL game scene on this PC: `--host` starts and prints `NETSMOKE host listening`, then `--join` (no code = this machine) joins over ENet. Lobby, bots in empty seats and the 3v3 default are all as a player gets them. The guest walks by injected WASD (a new key every 2 s), so its input has to cross the wire. Each end hashes the world it treats as true (host: authoritative; guest: confirmed) on every tick it sees. Pass = guest seated, the guest's body moved in the HOST's world, both ended cleanly, every tick both hashed agrees, and at least half the seated ticks were compared. This session added the host/guest last tick, match winner, round wins and the guest's team to the report.
- **Bug it found (fixed in `42d6cc4`, recorded here):** the keyframe snapshot did not carry `stance`, crouch/jump intent or a bundle's `in_flight`. Those fields were added with crouch, jump and throw. A guest that adopted a keyframe while a bundle was mid-throw then diverged from the host until the round reset. Snapshot `FORMAT` 1 → 2 now carries them, and `snapshot_test`'s awkward world sets all four (still 18 checks).
- **Runs (all 3v3, all `ok`, 0 mismatched ticks):**
  - default 60 s ×3: compared 1704 / 1692 / 1711 ticks; guest seated at tick 96 / 106 / 89, in 2010 / 2011 / 1751 ms; guest moved 959 / 1133 / 951 units on the host. Two bodies were human (host + guest, both team_a) and 5 were bots. Round 2 in progress at the end (team_b won round 1).
  - whole match, `--ticks=20000 --speed=3` ×2: both reached **MATCH_END**. The second (with the fuller report): host last tick 5439, guest 5289, 4698 ticks compared, **winner team_b 2–0**, guest on team_a, moved 2863. Short because team_a's two "humans" are an idle host and a guest walking a square, so three bots play against one. ~63 s wall clock.
  - Inside full verify: 1711 ticks agree, seated in 1781 ms, moved 952.
- **In-process tools:** `net_loopback` IN LOCKSTEP (2701 ticks, 10384 commands, 100 bytes/tick, scores agree 3/1 – 4/0). `net_lobby` SEAT KEPT (joined tick 61 by a 1734-byte snapshot, dropped at 300, a bot covered the seat, reclaimed the same actor at 701, host and guest agree).
- **Gate:** new "Network" block in `verify.mjs` (full run only, not `--quick`: ~70 s) runs net_loopback, net_lobby and net_smoke and fails on a missing verdict, a non-ok report or any mismatched tick.
- verify (full): healthy. 16 suites at pinned counts; symmetry 200/200; bot_match 3v3 DETERMINISTIC team_b, 90 s stalls; 1v1 team_b, 7 s; tick budget 0 of 600 over at 1v1/3v3/4v4 (p99 6.6 / 24.0 / 23.7 ms); network ok.
- Left: headless runs, so no frames (nothing visual changed). The windowed two-process menu path was covered by `--pilot=host/guest` in P0-8. Not tested: loss and latency (P6-1), two machines (needs the user and a friend, PROJECT_MEMORY §7), and a guest on team_b.

## 2026-11-13 — P0-8 Playable local session
- **Instrument first: `--pilot`** (`game/debug/playtest_pilot.gd`). It plays the local seat through a whole session using only injected input: a mouse click on the menu button, WASD, mouse motion to turn the camera, SPACE, SHIFT, LMB, RMB, E, Enter, F10. It reads the confirmed world to know where things are and to report, and uses the bots' NavGraph routes only as directions to walk in. It writes `user://pilot/NN_<step>.png` plus `report.txt`, prints one `PILOT` line per step, and quits. `--pilot-speed=2` speeds up the play-out after the scripted steps. `--pilot=host` and `--pilot=guest` do the menu's network path in two windows: the host clicks Host and writes its code to `user://pilot_code.txt`; the guest clicks the Join box, types the code key by key, clicks Join. Both walk, jump and press F10. It's a debug tool, not a gate (≈8 min solo).
- **What broke, and the fixes:**
  1. **No clock, score or result without F1.** With the debug HUD hidden (P0-4), a player saw nothing when a round or the match ended. Bodies froze, reset and went again. New `game/greybox/match_status.gd`: one line, always on, at the top (`ROUND n  m:ss   > Team A c (rounds r)   Team B …   cash to win 7   CARRYING CASH / JAILED ns`). Plus a big centred headline: countdown `ROUND n / 3…`, `TEAM X WIN ROUND n`, `ROUND n DRAWN - replayed`, and `TEAM X WIN THE MATCH a-b / [Enter] play again  [F10] menu`. Both are hidden while F1's debug HUD is up (it shows the same numbers) and cleared on leaving to the menu.
  2. **MATCH_END was a dead end** (terminal; only F10 got out). **Enter** now sends `MatchCommand.rematch` on solo/host; a guest's headline says "waiting for the host".
  3. **Carried cash was invisible.** The renderer hid a held bundle (the sim puts it inside the carrier), so the status said CARRYING CASH while the frame showed no cash anywhere, and nobody could tell who to chase. Attempt 1 put it in front of the chest. Frame `06_grab` (run 3) showed only a green sliver beside the torso, because the chase camera is behind. Attempt 2 (kept): it rides over the carrier's head, crouch-aware (`_hold_carried`, `CARRY_GAP`).
  4. **`--capture-grab` still pressed Q** (grab has been LMB since the controls changed). Now it injects a left click.
  5. Pilot's own bug, found on run 1: injected mouse motion reaches the camera a frame later, so re-sending the full turn every frame doubled it and the pilot weaved into the lot corner (grab failed, at (87, 320, 83)). It now waits for each turn to land.
- **Walkthrough (run 4, 3v3 solo, frames in `autobuild/frames/p08/solo/`, local only):**
  - `01_menu`: title, Team size 3v3, Play solo / Host / Join / Quit. The pilot clicked Play solo at its drawn position.
  - `02_countdown`: big `ROUND 1 / 1` over the red strip beside House A, status line `ROUND 1 --:-- > Team A 4 (rounds 0) Team B 4 (rounds 0) cash to win 7`.
  - Move: W for 1.4 s, 631 units (`03_walk`). Jump: rose 188, landed exactly (`04_jump`, body clear of the floor). Crouch: SHIFT → CROUCHED, release → STANDING (`05_crouch`).
  - Grab: walked into House B's bedroom (blue floor) and pressed LMB after 15 s (`06_grab`). The bundle is over the head and the status reads CARRYING CASH, B 4 → 3.
  - Throw: RMB, in flight, landed 371 away; LMB picked it up again. In `07_throw` the bundle can't be seen in the air: 0.15 s in, it is already out of frame or behind the body. A throw arc is P4-1.
  - Drop/score: the scripted carry home was seized on the way (pilot jailed in jail_b; same in runs 2 and 3, which is the game working). In the play-out the pilot banked 2 bundles. `11_deposit`: LMB in study_a, team cash 1 → 2, the bundle at its feet on the red floor.
  - Seize: E on a team_b intruder in front_hall_a after 33 s (`08_seize`). Free: E on a jailed team-mate in jail_b after 115 s (`09_free`, two red-shirted bodies in House B's dark-blue jail).
  - Rounds: `ROUND 2 DRAWN - replayed` twice (`10`, `12`), then `TEAM B WIN ROUND 2` (`13`). `14_match_end`: `TEAM B WIN THE MATCH 0-2 / [Enter] play again [F10] menu`, status `Team A 1 (rounds 0) Team B 4 (rounds 2)`.
  - `15_rematch`: Enter → `ROUND 1 / 2` countdown, 4–4, rounds 0–0, back on the spawn strip. `16_back_to_menu`: F10 → menu, session closed, no status text left over the menu.
  - Run-to-run: run 2 passed 14 of 15 steps and run 3 also 14 of 15. Every failure was the pilot being seized while carrying. Team B won all 4 matches: the pilot plays worse than the bot it replaces.
- **Network path (two windows on this PC, `autobuild/frames/p08/host|guest/`):** host clicked Host (code `070A-G05P-W5FG`, 6 bodies), guest joined (1 connected). In `02_join_typed` the Join box reads exactly the code. The guest was seated as actor 2 (team_a). Both played, both F10'd to the menu with the session closed (host: 0 failures). Host `02_lobby`: `HOSTING code … 1 connected tick 183` above the status line. **Guest walk moved only 71 units:** `04_walk` shows its spawn (team_a seat 2) facing straight into the house wall at the camera's starting yaw, so W walked into the wall.
- **Closing session (the first was cut off before committing):** re-opened `06_grab` and `14_match_end` and they show what is written above (bundle over the red-shirted pilot's head on House B's blue bedroom floor, status reads CARRYING CASH; match-end headline over two team-mates in a dark-blue room). Changed the headline text from `TEAM X WIN` to `TEAM X WINS` (the frames above still show the old wording). Fixed PLAYTEST.md, which still said the bundle is drawn in front of the chest. `autobuild/Incoming/` is now gitignored: the user dropped `Universal Base Characters[Standard].zip` (129 MB) and `Universal Animation Library[Standard].zip` (16 MB) there, which look like the Quaternius packs. **P2-1/P2-2 should start from these** (check the licence file inside and record it in ASSETS.md).
- verify (full): healthy. 16 suites green, symmetry 200 of 200. bot_match 3v3: deterministic, winner team_b, 439 s, 3 rounds, 27 captures, stalls 90 s (budget 400). 1v1: deterministic, winner team_b, stalls 7 s. Tick budget: 1v1 p99 6.4 ms, 0 over; 3v3 p99 22.2 ms, 0 over; 4v4 p99 21.5 ms, 0 over.
- **Left / seen, not fixed:** every seat's camera starts at yaw 0, so some spawns open nose-to-wall (camera start facing is a small first-impression task). In `12_round_2_end` (near House B's west side) there's a soft dark smudge low in the sky, left of the house; not investigated. Thrown cash isn't readable mid-air (P4-1). The `[1]/[2]` safe-room restart is still listed in the debug HUD only. A human still has to play it: the pilot proves the input path and the screens, not the fun.

## 2026-11-13 — P0-7 "Patchy graphics" sweep
- **Instrument:** 16 `room_*` free-camera views in `views.json`: every room on both floors of both houses (jail, front hall, kitchen, back hall; study, landing SE, bedroom, landing NW). Each camera stands in the room corner nearest the house middle, 260 above the floor, looking at the far corner. House B's 8 are the exact turned twins of A's, so a defect in one house only would show up as a mismatch. Plus 6 exterior views (`ext_a_south/west/east/north`, `ext_b_north`, `yard_midline_top`, which looks down on the corridor where the two yards meet). Before frames are in `autobuild/frames/p07_before/` (ignored by git, local only).
- **Defects found (before):**
  1. **Lighting: three face directions were one flat slate colour.** The sun lights +y, −x and +z faces. Everything else (ceilings, +x walls, −z walls) got ambient only, which is the same value everywhere. A wall ran into the ceiling with no edge. Worst in `room_a_up_landing_nw`: the far walls, the ceiling and the stairwell opening were one sheet, so the stairwell read as a notch in a flat grey. Also `room_a_gf_backhall`, `room_b_gf_kitchen` (right wall invisible against the ceiling), and `ext_a_east` (a whole house face with no detail).
  2. **Yard tint under every ground-floor room.** The floor tint tested each zone's box on its own. The yard wraps the house (rooms win by priority), so yard_a's tint was also laid under all four ground rooms, a second coplanar slab under the room's. It was invisible only because both were the same colour. The doorway sills, which the game itself puts in the yard, were left bare grey.
  3. **Ragged tint edges.** `yard_midline_top`: a comb of teeth where yard_a (red) meets yard_b (blue) on the lot midline, and notches along House A's east face. Every room had a grey strip about a body radius wide along each wall base, because stances stop a body radius off the wall and the cell-sized runs never reached it.
- **Checked and not defects:** close floor shots (kitchen, bedroom) showed no z-fighting or seams. No flipped faces (all box meshes). The thin light slivers along the stair flank, seen from the top of the flight, are the tread tops, which is correct geometry. The thin vertical strip in the kitchen doorway is the jamb's inner face. Stairwell holes stay untinted on both landings in both houses.
- **Fixes:**
  - `world_backdrop.gd`: a second, shadowless, level directional **fill light** from +x/−z (energy 0.45, slightly cool), and ambient 0.9 → 0.65. Per face, sun + fill: +y 0.94, +z 0.51, −x 0.42, +x 0.37, −z 0.25, ceiling 0 (ambient only, so ceilings are always the darkest face). No two faces that meet share a value. Constants are named in the file for the ArtTheme (P1-4) to take over.
  - New `game/greybox/floor_tint.gd` (`FloorTint.patches(level)`): each stance goes to the zone `ZoneDef.sorted_for_resolution` puts first (the rules' own order), so a point gets one tint. Rows are merged into rectangles. Each rectangle is clipped to its zone (and to the lot), and an edge that stops within body radius + one cell of its zone's edge is carried out to it. This replaced `_floor_runs`/`_run_box`/`_floor_of` in `greybox_main.gd` (89 lines fewer there).
- **After (same views):** `room_a_up_landing_nw`: dark ceiling, a mid-blue left wall and a lighter right wall, with the corner edge and the stairwell notch both readable. `room_a_up_study`, `room_a_up_landing_se`, `room_a_gf_fronthall`: ceiling-to-wall edges are clear all round and the tint runs to the wall base with no grey strip. `room_b_*` match their A twins with the light sides swapped, as expected. `yard_midline_top`: the red/blue boundary is one straight line and both yards run to the house walls. `ext_a_south`: the front-door sill is now red like the room behind it. **verify (full): healthy.** 16 suites at pinned counts; symmetry 200/200; bot_match 3v3 DETERMINISTIC team_b 90 s stalls, 1v1 team_b 7 s (unchanged, as expected: presentation only); tick budget 1v1 0, 3v3 1, 4v4 0 of 600 over. `lot_overview`: unchanged in layout; shaded faces lighter and bluer.
- Chase views (`cam_*`, all 16 re-shot under the new light): `cam_stair_a_climb` has light tread tops, blue-grey risers and the darkest ceiling, and the stairwell edge and landing above are clear. `cam_jail`: the doorway frames the room, and its lintel, jambs and back wall are each a different shade. Arm lengths and body fade are unchanged (83/118/129 compressed views, as in P0-6).
- Left: interior doorway sills stay grey on both floors (`cam_jail`'s D3 sill, `room_a_gf_backhall`). Only the exterior door sills picked up the yard tint. It reads as a door sill, so I left it. The stair's flank and end faces are close in shade (−x 0.42 vs +z 0.51), so from some angles the step profile reads mostly by the tread tops. Real art (P3) replaces this.

## 2026-11-13 — P0-6 Camera everywhere
- **Instrument first.** The existing `--capture-at` is a free camera: it shows a room, not what a player standing in it sees. New `--capture-chase=x,y,z` (a body's FEET) with `--capture-facing=x,y,z` and `--capture-pitch=deg` (`FrameCapture`, `greybox_main._capture_chase`): a drawn-only team_a stand-in is put there, the seat's own chase rig is parked on it (`ChaseCamera.pose`, `_posing_chase` stops it following the real body), the spring arm settles over 3 physics frames, and the shot goes through the ordinary seat viewport. Prints `chase arm N, body opacity X`. `views.json` entries with a `chase` field use it; `verify.mjs --frames-only [--views=prefix]` takes just the frames (≈2 min for 16) and prints the arm line.
- **16 `cam_*` views** (one per space; numbers are arm length in units, full arm 350): garden open (350), garden backed against the house (83), front door from outside (350), front-door threshold (350, camera outside looking through the door), doorway turn front hall→kitchen (350), jail (350, camera in the back hall looking through the D3 door), jail corner (118), kitchen pitch −60 (209, stopped by the ceiling) and +25 (241, stopped by the floor), stair A mid-climb (350), stair A top looking down (314), stair B mid-climb (350), landing A (339), study (cash) A (129), bedroom (cash) A (237), study B (129). There is no basement: Phase 1's jail is the ground-floor SW room, so "basement/jail" is the jail views. The "vault" is the two upstairs cash rooms.
- **What the first pass showed:** in 12 of 16 the player is a small, clear figure in the lower-middle with the room ahead readable: the stairs read as stairs from behind on both flights, both doorways frame the body, and steep pitch stops cleanly at ceiling and floor without seeing through either. **No frame had a wall between camera and body**: the spring arm (sphere probe on the blockers) already keeps every wall behind the camera. The defect was the player's **own body**: in the 4 compressed shots (garden wall-backed 83, jail corner 118, both studies 129) the body filled the middle third of the screen, head cut off at the top when backed against the house, the room and the cash hidden behind it.
- **Fix: fade the own body as the arm shortens** (`ChaseCamera.body_opacity()`: full at ≥ 200, 0.25 at ≤ 90, from `SpringArm3D.get_hit_length()`; `greybox_main._fade_body` each frame for each seat's own actor, only re-walking the model when the value changes). Attempt 1, `GeometryInstance3D.transparency`: frame identical, the body drawn solid; the Compatibility renderer ignores it. Attempt 2, per-surface alpha copies of the model's own materials: works. `ALPHA_HASH` drew solid, only darker. Kept blended alpha with a depth pre-pass.
- **After:** study A/B at opacity 0.51: the torso is see-through, with the cash bundle, the doorway and the far wall visible through it. Jail corner 0.44: the doorway to the hall shows through the body. Garden wall-backed 0.25: sky, field and lot read through the figure. Uncompressed views unchanged (opacity 1.00). **Known artefact:** the placeholder voxel character is many boxes, so when faded its inner box faces show as an x-ray tangle (the pre-pass works per mesh). A one-mesh character (P2-1) won't do this; re-check then.
- Solo game path (`--solo --capture`) ran with no script errors. **verify (full): healthy.** 16 suites at pinned counts (camera_controls_test 16); symmetry 200/200; bot_match 3v3 DETERMINISTIC team_b 90 s stalls, 1v1 team_b 7 s (both unchanged); tick budget 0 of 600 over at 1v1/3v3/4v4 (p99 6.5 / 22.6 / 24.4 ms).
- Left: other bodies (team-mates/enemies) right in front of the camera don't fade (only your own does). The camera has no cut-away for a body hidden laterally behind a doorway jamb; not seen as a problem in these frames. Judged on the voxel placeholder; redo the four compressed views when real characters land.

## 2026-11-13 — P0-5d Default to a team game
- **Default 3v3:** `GreyBoxLevel.DEFAULT_TEAM_SIZE` 1 → 3, plus `TEAM_SIZES` [1, 2, 3, 4]. The game (`greybox_main.gd`) builds its level at `_team_size`, read from `--team-size=N` (clamped to 1–4) or from the menu. Bots fill empty seats as before (lobby fill, on by default).
- **Menu** (`main_menu.gd`): a "Team size" row with a dropdown (1v1 (test), 2v2, 3v3, 4v4; 3v3 selected) above Play solo. `solo_chosen` / `host_chosen` now carry the size. Join has no picker.
- **Guest at the host's size:** the guest builds its worlds before it connects, so it can't know the host's size up front. The host's seat message now carries its team size (`MatchChannel.frame_seat(actor, team_size)` / `team_size_of`). A guest whose level differs sets `MatchLink.rejoin_team_size`. `greybox_main` then tears down (`_tear_down`, split out of `_return_to_menu`) and starts again at that size with the same identity, so the lobby's reclaim-by-identity hands back the same seat. A size this build has no mode file for is reported as a failure, not retried.
- **What I checked, and what the frames showed:**
  - `--menu --capture` (`p05d_menu.png`): the title, a "Team size … 3v3 ▾" row directly under the strapline, then Play solo, Host (address prefilled), Join, Quit. Nothing overlaps.
  - `--solo --debug-hud --capture` (`p05d_solo.png`): HUD reads LOCAL, PLAYING round 1 178.0 s (the 3v3 180 s round), P1 free, then five `BOT … LOBBY_FILL STEAL` lines (2 team_a, 3 team_b). The character stands on the red strip by the wall, grass and sky behind. Capture reports 14 bodies (as I read it, 6 people plus 8 cash).
  - **Two real processes on this PC over ENet:** host `--host --team-size=4`, and 6 s later a guest `--join` at the default (3). Guest frame (`p05d_guest_rejoined.png`, debug HUD): "JOINED confirmed 665 predicting +1", round 1 159.8 s, its body in the blue (House B) interior by a doorway, "HELD 20.6s". It took over a lobby-fill bot's body that was already jailed 22 s into the match, which is normal play. Both processes report **16 bodies** (4v4), so the guest rejoined at 4. Host frame (clean): its character on the red strip, sky and grass, no text.
  - `net_lobby` (now 3v3 by default): SEAT KEPT, reclaimed the same actor, 5 bots, host and guest agree. `net_loopback`: IN LOCKSTEP, 2701 ticks, scores agree.
- verify (full): healthy. 16 suites at pinned counts; symmetry 200/200; bot_match 3v3 DETERMINISTIC team_b 90 s stalls, 1v1 team_b 7 s (unchanged); tick budget 0 of 600 over at 1v1/3v3/4v4 (p99 6.7 / 21.8 / 22.8 ms).
- Docs: PLAYTEST.md (team size, `--team-size`, bots fill every empty seat), PROJECT_MEMORY §2/§6.
- New `autobuild/run_tool.mjs <tool> [args]`: runs a `godot/tools/*.gd` script headless through node and strips the exit-time leak spam. Added because direct Godot calls got permission prompts in this unattended session.
- Left: the in-match lobby has no size change (back to the menu with F10 and pick again). Bots are tuned against 3v3/4v4 numbers from P0-2c and nobody has played a human 3v3 yet. The `[1]/[2]` restart key keeps the current size.

## 2026-11-13 — P0-5c Four spawn points per team
- Picked up from a cut-off session: its diff (one P0-5c change in `build_house.gd` plus the re-bake) was in the working tree, uncommitted. Checked and finished it rather than stashing.
- **Change:** `SPAWN_LOCAL` in `tools/build_house.gd` gains a fourth entry, house-local (1000, −150): off the front (south, low-z) face, 500 along from the third marker and 440 short of the front door's jamb (door spans x 1440–1680), so no body starts in the doorway. The stamp loop now runs over `SPAWN_LOCAL.size()` instead of a hard-coded 3. The old comment called the third spawn's face "north"; it is the south face (z low = front), now corrected. Baked world positions: team_a (1350, 320, 200), team_b (4050, 320, 3520), each the turned twin of the other.
- **Bake is reproducible:** re-running `build_house.gd` gave a byte-identical `house.tres` and the same `house.tscn` content (only Godot's random `unique_id`s change). HOUSE_LAYOUT.md §9 already specified "Team spawns ×4"; the build had been one short. PROJECT_MEMORY's "bakes THREE spawns" line updated.
- **verify (full): healthy.** 16 suites at pinned counts (content validator checks every spawn is standable); symmetry exact, 200 of 200; bot_match 3v3 DETERMINISTIC, team_b, 90 s stalls; 1v1 DETERMINISTIC, team_b, 7 s (both identical to before, as expected: slots 0–2 did not move); tick budget 0 of 600 over at 1v1, 3v3 and 4v4 (p99 5.8 / 23.9 / 21.9 ms).
- **4v4 bot match** (`bot_match --team-size=4`): DETERMINISTIC, winner team_b 2–0 (round 1 180 s on time 5–2, round 2 122 s on target 7–0), 46 pick-ups, 30 deposits, 35 seizures, 28 rescues, 120 s stalls, raiding team_b 190% / team_a 245%. 4v4 isn't gated; no earlier 4v4 number at this seed to compare with.
- Not visual work, so no frame taken. The game still seats 1v1 (P0-5d), so a 4v4 frame needs that task first.
- Noticed: `autobuild/Incoming/` holds two zips the user dropped in (`Universal Base Characters[Standard].zip`, 129 MB, and `Universal Animation Library[Standard].zip`, 16 MB, which look like Quaternius packs). Left untracked and not committed. They're for P2-1/P2-2; check their licence file before using them.
- Left: nothing for P0-5c.

## 2026-11-12 — P0-5b follow-up: seat order measured
- A second session, running at the same time on the same working tree, had picked up P0-5b from the cut-off session's diff. It ran the house-swapped sweep the entry below calls "cut for time". This entry is that sweep. It also explains that entry's tick-budget noise and the five seeds that read "none": they were this session's jobs.
- **`autobuild/side_sweep.mjs`** (a tool, not a gate): `bot_match --once` over seeds × sizes, each seed played as-is and with `--swap-houses`, tallying wins by team name and by house. `--sizes=2,3,4 --seeds=8 --first-seed=1 --jobs=3`. It prints the output tail of any run it can't parse. Use `--jobs=2` for 4v4 on this laptop.
- **Result, 48 matches (8 seeds × 2v2/3v3/4v4 × as-is/swapped), on the committed P0-5b code:**
  - as-is: team_a 13, team_b 9, 2 undecided (same as the entry below; 2v2 5–3, 3v3 4–3 +1, 4v4 4–3 +1).
  - swapped: team_a 11, team_b 11, 2 undecided (2v2 4–3 +1, 3v3 4–3 +1, 4v4 3–5).
  - **by house: A 24, B 20** (2v2 8–7, 3v3 7–7, 4v4 9–6). Before the fix, House A won 8 of 8 swapped at 2v2.
  - **by seat name: team_a 24, team_b 20.** One standard deviation over 44 decided matches is ~3.3, so neither house nor seat leans beyond noise. The seat-ordered loops (movement order, sidestep side, capture loop) were left as they are. PROJECT_MEMORY §6c-ii updated.
- The five 4v4 runs that came back blank in the first pass (the other session killed them) were re-run, two at a time, and all finished normally. The totals above include those re-runs.
- verify (full, quiet machine): healthy. 16 suites at pinned counts; symmetry exact (200 of 200); bot_match 3v3 DETERMINISTIC, team_b, 90 s stalls; 1v1 DETERMINISTIC, team_b, 7 s; tick budget 1v1 0, 3v3 1, 4v4 0 of 600 over.
- Left: 4 of 48 matches undecided in regulation. The P0-2c round numbers may want a re-check now that the bots are fair (already noted below).

## 2026-11-12 — P0-5b Team A bias
- **Result: team_a 13, team_b 9, 2 undecided over 24 bot matches** (8 seeds × 2v2/3v3/4v4), from 20–4. 2v2 5–3, 3v3 4–3 +1, 4v4 4–3 +1. Raiding time is now close to even (2v2: team_b 96–133%, team_a 89–121% of the match on enemy ground; before: team_b 123–173%, team_a 51–107%).
- **Measured first.** New `bot_match --swap-houses` gives each team the other's house with seating unchanged, and per-team lines (pick-ups, drops, times seized, stalls). Before any fix, 2v2: team_a 7 of 8 normally, and **the team in House A won 8 of 8 when the houses were swapped** (3v3 swapped: 3 of 3). So the house decided it, not the seat. The House B side spent ~2× as long on enemy ground and got seized carrying cash (seed 1: team_b 16 pick-ups, 6 drops, seized 10 times), 15 of 33 encounters at one spot by House A's front stair against 7 at its twin.
- **Instrument 1, `tools/symmetry_probe.gd` (now a verify.mjs gate, also in `--quick`):** turns blockers, rooms, spawns, cash, every stance and its neighbours, and routes 200 random trips both ways. Content: exact (189 blockers, 19 rooms, 15,921 stances, same neighbours), except **every House B spawn/cash marker sat 1 unit off its twin** (placed as a one-unit box's corner) → `build_house.gd` `_place_point`, re-baked. Routes: **161 of 200 trips took a different equal-length line from their twin**, because BFS broke ties in one world-axis edge order. Reversing that order moved 2v2 to team_a 2 / team_b 5 / 1 draw: confirmed as a cause. Fix: `NavGraph` keeps edges in two orders and `_trace` picks by direction of travel → 200 of 200. Graph build ~150–400 ms at match start.
- **That alone changed nothing: team_a still 8 of 8 at 2v2, House A still 4 of 4 swapped.** Instrument 2, `tools/twin_probe.gd`: plays a match and its house-swapped twin together (same ids, same random streams) and stops at the first tick a body stops being its twin's turned copy, printing the run-up and re-testing reachability. Each stop was a tie broken by index or neighbour order (= world scan order), fixed one at a time:
  1. tick 106: `stance_under` returned the first stance by index at equal height — the one furthest toward −x/−z, not the one under the body — so the escape step pulled a bot backwards in House A only. Now nearest wins (and it reads only the buckets in reach instead of all 15,921 stances; exact, bot_match bit-identical before/after that part).
  2. tick 176: a sight line ending exactly on a doorway jamb entered at t = 1 ± a float32 hair (`to - from` in float32, times a reciprocal) → see-through in one house only. Now a double-precision step and a quotient: exactly 1, contact.
  3. tick 465 (`--no-noise`): prisoners placed on a different corner of the pen's middle (4-way tie). Now nearer the world's middle wins.
  4. tick 795: `_stance_step_toward` broke an equal-gap tie by neighbour order. Now the shorter step wins.
  After these, 2v2 seed 1 stays an exact twin to tick 850 (28 s), where float drift (0.4 units: x and 5400−x round differently) changes a re-route. Noise, not direction. Not fixed (unbiased): bots' choice noise is drawn per candidate in room-name order.
- **Seat order (entity ids) still orders movement, the head-on sidestep side and the capture loop.** Not measured separately after the fixes (the swapped sweep was cut for time); with 13–9 it is at most a small effect. Worth one swapped sweep if a bias shows up again.
- verify: test suites at pinned counts; symmetry exact; bot_match 3v3 DETERMINISTIC, winner team_b, **stalls 327 → 90 s**; 1v1 DETERMINISTIC, winner team_b, **stalls 42 → 7 s**. Budgets re-set to 1v1 7 (exact), 3v3 150 (the sweep's 3v3 per-match totals were 62–113 s). Winners flipped to team_b at both gate seeds, which is a seed, not a bias.
- **Tick budget: noisy machine, not a regression.** Cause found late: a second session was running `autobuild/side_sweep.mjs --jobs=3` (a house-swapped side-bias sweep built on `--swap-houses`) against this working tree, holding 3 of 4 cores; I took its Godot jobs for my own orphans and killed five of them, so that sweep's tally under-counts those seeds (they read "none"). `side_sweep.mjs` is not mine and is left uncommitted. Identical runs ranged 0–28 over at 3v3 while it ran. **On the quiet machine afterwards, A/B against HEAD, alternated, 3 runs each at 3v3: HEAD p50 9.9–10.1 ms, p99 26.9–28.4, 1/1/1 over; now p50 6.9–7.2 ms, p99 24.4–26.5, 0/0/1 over.** Cheaper, not dearer (mostly `stance_under` reading only the buckets in reach). Final verify on the quiet machine: 1v1 0, 3v3 4, 4v4 3 over (4v4 not gated).
- Left: 2 of 24 matches undecided in regulation (P0-2c had 24 of 24 decided): the per-size round numbers were tuned against the biased bots and may want a re-check. Docs: PROJECT_MEMORY §6c-ii (rule for new code: a tie in sim/ breaks on something that turns with the house, then index), WORLD_AUTHORING §11.

## 2026-11-12 — P0-5 Visible world
- **New `game/greybox/world_backdrop.gd` (`WorldBackdrop`)**, presentation only, no collision: a procedural sky (blue overhead, pale at the horizon), warm sun (1.15), flat-colour ambient tinted to the sky (0.62/0.66/0.74 × 0.9), **depth fog** from 6000 units to 500 short of the camera's far plane (11500) in the sky's horizon colour, and a **grass plane** 1 unit under the lot's ground, reaching past the far plane. The ground height and lot extent are found from the blockers (largest footprint = lot slab, y 300), not restated. `_build_lighting` now just adds what `WorldBackdrop.environment()` returns; `_build_geometry` adds `WorldBackdrop.ground()`.
- **Blockout grey 0.26 → 0.56** (`BLOCKOUT_GREY` in greybox_main.gd). With the dark grey, every wall face turned away from the sun read as a black hole under daylight (seen in `approach_from_south`, attempt 1).
- **views.json +4 views**: `lot_overview` (high, SW corner), `corridor_horizon` (between the houses, eye height, looking off the south edge), `yard_b_horizon` (B's east yard looking out), `approach_from_south` (outside the lot, facing both houses).
- **What the frames showed** (final run): `spawn_default`: the character on the red floor strip beside a light-grey wall; where the black void was there is now green grass to a soft horizon and a blue sky. `lot_overview`: both houses as light-grey boxes on the lot (grey neutral ground, red and blue team yards), the lot sitting in a green field; past ~120 m the field fades into a pale haze dome before the sky (that's the far-plane cut hidden by the fog, reads as haze). `corridor_horizon`: wall on the left, red and grey ground, green field, horizon, sky. `yard_b_horizon`: only field and sky, horizon soft with no band. `approach_from_south`: both houses side by side with readable blue-grey shaded faces and a door cut-out, lot edge visible as a thin pale strip on the grass. `stall_spot_a`/`stall_spot_b`: interior close-ups, light-grey walls and treads, red/blue floors, no black anywhere. Attempt 1 had a hard grey-teal band at the horizon (fog colour ≠ sky horizon colour) and haze greying the far house in the overview; fixed by fogging to the sky's horizon colour and starting the haze at 6000 instead of 3500.
- verify: healthy. 3v3 tick budget 1 of 600 over (limit 5); 1v1 and 4v4 0. Bot match unchanged (3v3 327 s stalls, team_a; 1v1 42 s).
- Left: lot ground and walls are the same flat grey (exterior dressing is P3-4, art P1/P3). No shadows yet (P3-5). Not measured on the real GPU (P1-1/P7-2); fog and a procedural sky are both Compatibility-safe.

## 2026-11-12 — P0-4 Clean frames
- **`--capture-clean`** (`game/debug/frame_capture.gd`): hides the whole in-game text layer (debug HUD, hint line, network banner) one frame before the shot. The menu is its own layer and is not affected. `verify.mjs --frames` now passes it for every view.
- **Debug HUD hidden by default** (`game/greybox/greybox_main.gd`): `[F1]` toggles it, `--debug-hud` starts with it on. While hidden, one faint line in the top-left says `[F1] debug HUD`; for a host or guest that line also carries the network status (join code, CONNECTING...), because that is the one thing they can't play without. The HUD text is not rebuilt while hidden. PLAYTEST.md and godot/CLAUDE.md list the key and flag.
- **What the frames showed** (`verify.mjs --frames`, all three views): no text at all. `spawn_default`: the voxel character (red shirt, blue-grey trousers) on a dark-red floor strip beside a grey wall, black void filling the left half and top. `stall_spot_a`: close-up of red floors and grey wall slabs, with dark wedges at top-left. `stall_spot_b`: grey stair treads between a black void (left) and a navy-blue wall (right). Two check frames from the same eye: default play shows only the faint `[F1] debug HUD` line top-left; with `--debug-hud` the full HUD text (LOCAL, SAFE ROOM 5.0s, PLAYING round 1 119.0s, team cash, bot task, cam1, controls) is drawn over the left half, exactly as before.
- verify: healthy (16 suites at the pinned counts; 3v3 bot match deterministic, team_a, 327 s stalls; 1v1 42 s; tick budget 0 of 600 over at 1v1/3v3/4v4).
- Left: the black void (P0-5). Until P5-2, a player has to press F1 to see score and timer.

## 2026-11-12 — P0-2c Tuning per team size
- **The problem wasn't too many rescues. Rounds were ending level on the clock.** Measured first with the old numbers (120 s rounds, 18 s jail, +6 s escalation), 4 seeds × 2v2/3v3/4v4: **0 of 32 rounds ended on the target** (7 of the 8 bundles). Every round ran its full 120 s and went to whoever led, usually 3–2 or 5–2. 2v2 drew 5 of 11 rounds (3–3, 4–4) and 2 of 4 matches were undecided. 3v3 and 4v4 were decided in 4 of 4, but 3v3 at the main seed only because the old fixed 6-minute tool limit was replaced (it had cut off round 3).
- **Instrument (tools/bot_match.gd):** one line per round (length, winner or draw, how it ended, cash), `--seed=N`, `--once` (one run, for sweeps; the gate always plays twice), `--mode.<field>=<value>` overrides, and a match limit taken from the mode: `2·rounds_to_win−1` full rounds, with draws counting against it. "No winner" now means "not decided in regulation".
- **Data, not code:** `content/modes/house_1v1.tres … house_4v4.tres`. `GreyBoxLevel.new(variant, level, team_size)` loads the file for that size (a missing file is a `push_error`). `cash_per_team` is still stamped from the level's markers. perf_probe and bot_match pass `--team-size` through to it. The game itself still seats 1v1 (`DEFAULT_TEAM_SIZE`).
- **Sweep** (results per config over 4 seeds; decided = winner in regulation):
  - 2v2: 120/18 → 2/4 decided, 5/11 draws · 120/24 → 3/4 · 120/30+8 → 3/4 · 150/18 → 4/4, 0 draws · 150/24 → 4/4, 3 on target, but 7/8 once seeds 4–7 were added · **180/24 → 8/8**, 2 draws in 18 rounds, 5 on target.
  - 3v3: 120/18 → 4/4, 0 on target · 150/24 → 2/4 · **180/30 → 8/8** over 8 seeds, 1 draw in 17 rounds, 10 on target.
  - 4v4: 120/18 → 4/4, 0 on target · 150/24 → 4/4, 4 on target · **180/30 → 8/8** over 8 seeds, 0 draws, 9 of 19 rounds on target.
- **Chosen (DECISIONS REVIEW):** 1v1 120 s / 18 s (unchanged, the bot match gives the same numbers: 12 pick-ups, 8 deposits, 6 seizures, 5 rescues, 42 s stalls, team_a 2–0); 2v2 180 s / 24 s; 3v3 and 4v4 180 s / 30 s. All with +6 s escalation. Matches run 266–555 s (4½–9 min) at 2v2–4v4.
- **Gate:** `verify.mjs` runs bot_match at 3v3 first (main gate), then 1v1. Each has its own stall budget in `metrics_budget.json` (`bot_match.{size}.max_stall_seconds`): 1v1 42, 3v3 400. 3v3 at the gate seed: DETERMINISTIC, winner team_a, 485 s (round 1 drawn 3–3 and replayed, then 5–2 on time, then 7–0 on target after 110 s), 53 pick-ups, 32 deposits, 35 seizures, 31 rescues, 327 s stalls. The winner check now requires a `team_*` name; the "none - not decided in regulation" line it rejects showed up in the 120 s 2v2 runs. Full verify healthy: 16 suites at pinned counts; tick budget 1v1 p99 8.3 ms, 3v3 26.4 ms, 4v4 26.5 ms, 0 of 600 over at each (perf_probe now loads each size's mode file).
- **Found, not fixed: a strong team_a bias.** At the chosen numbers team_a won 20 of 24 sweep matches (2v2 7–1, 3v3 6–2, 4v4 7–1), and it led most of the baseline runs too. The houses are a turned copy, so the cause is somewhere in seating, spawn order or the bots, not the layout. It matters as soon as people play bot-filled matches. Worth measuring next (e.g. swap which team each seed's bots join, compare raiding %).
- Also seen: 4v4 has 4 bodies per team and only 3 spawn markers, so `spawn_point_for_slot` clamps slot 3 onto slot 2's spawn (two bodies start on one point). 4v4 stall totals are noisy (seed 2: 640–827 s, most of it at one place). Neither was in scope.
- Left: human playtest of the numbers. Cash per team is not scaled; more cash means more markers in `build_house.gd` and a re-bake.

## 2026-11-12 — P0-2b Tick budget in 3v3 and 4v4
- **Result: under 5 of 600 ticks over 33 ms at 3v3 and, most of the time, at 4v4.** Before → after (perf_probe `--team-size=N`):
  - 1v1: p99 ~25 → 8.6–9.7 ms, 0 over.
  - 3v3: p99 45.7 → 24–29 ms, 35 → 0 over (0 in five runs, 1 in the run inside verify); median tick 12.2 → 8.6–9.4 ms.
  - 4v4: p99 58.3 → 26–33 ms, 73 → **0 over in 8 of 10 runs, 2 and 5 in the other two** (the 5 was inside a full verify, straight after the test suites). Median tick 15.6 → 7.6–8.7 ms. The worst single tick is 30–34 ms, so the margin is thin and 4v4 is **printed but not gated** in verify.mjs, so a later session doesn't chase noise.
- Measured first, with temporary counters and per-phase timers (all removed):
  1. **The broadphase handed each swept test 36.7 candidates, of which 6.1 were distinct.** Floor slabs and long walls are indexed into many cells, so a query covering several cells got them once per cell. Fix: `WorldCollisionDef` keeps a deduplicated candidate list per query box (cached, capped, clamped to the occupied grid). **Exact**: the same 183,801 tests and the same 1,117,582 distinct candidates before and after. 3v3 went 43 → 17 over from this alone.
  2. **What was left over budget was the decision flood** (in 4v4, 33 of 35 over-budget ticks had one in them). New `sim/ai/hop_flood.gd`: the same BFS, resumable, advanced `flood_stances_per_tick` = 2000 stances a tick (a `BotProfileDef` field; 0 = the whole flood at once). A bot decides on its previous distance table until the new one is finished (~8 ticks). Decisions and routes are never held back, which is what broke the rationing tried earlier (PROJECT_MEMORY §6b-ii). `hops_from` now uses the same class, so there is still only one BFS.
  3. **Steering look-ahead**: new `WalkableSurface.furthest_reachable` runs exactly the old furthest-first loop but tests the step-up's vertical lift once instead of once per waypoint. Exact. 4v4 steering 5.3 → 3.2 ms/tick.
  4. **`nearest()` cost 147 µs a call inside decisions** (1,166 ms over 7,919 calls at 4v4): zone centres are mid-air, far from any stance. New `NavGraph.stance_near` memoizes per exact point (the surface never changes, so the answer is the same). Decide time 2.9 → ~1 ms/tick, and this is what took 4v4 from 6–8 over to 0.
- **Behaviour.** 1v1 bot_match gives the same numbers as before: DETERMINISTIC, 12 pick-ups, 8 deposits, 6 seizures, 5 rescues, 42 s stalls, winner team_a. At bigger sizes (new `bot_match --team-size=N`) both runs are deterministic, but the matches play out differently because of the flood timing: 3v3 stalls 180 → 226 s, deposits 24 → 28, still no winner (tuning is P0-2c); 4v4 stalls 349 → 150 s, pick-ups 32 → 43, winner changed from team_a to team_b. Stall totals at 3v3/4v4 add up over 6/8 bodies, so they can't be compared with the 1v1 42 s budget.
- Gate: `verify.mjs` now runs perf_probe at 1v1, 3v3 and 4v4. 1v1 and 3v3 fail above `max_over_budget_ticks` (5); 4v4 is printed with "(not gated)". Full verify healthy.
- Left: firm up 4v4 before gating it. Routes are now the biggest single cost on a bad tick (one long route 12–19 ms). Next things to try: spread route searches over a bounded few ticks (carefully, given §6b-ii) or a cheaper long-route search. Then gate 4v4.

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
