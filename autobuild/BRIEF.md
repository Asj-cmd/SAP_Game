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

## P5-0 — Family display names

**Approach**
1. Read `godot/content/family_names.cfg` (it exists: comment lines, `team_a_name=`, `team_b_name=`)
   and the "Changing the family names" section of `HOW_TO_PLAY.md`.
2. Write the loader, `godot/game/greybox/family_names.gd`, `class_name FamilyNames`, all static:
   - `parse(text: String) -> Dictionary[StringName, String]`: pure, no file access. Per line: trim;
     skip blank lines and lines starting with `#`; split at the FIRST `=`; key `team_a_name` /
     `team_b_name` → `&"team_a"` / `&"team_b"`; value trimmed, then one pair of matching `"` or `'`
     stripped, then trimmed again. An empty value is not stored. Unknown keys are ignored.
   - `load_from(path: String) -> Dictionary[StringName, String]`: `parse` of the file's text, or an
     empty dictionary when the file is missing; then the fallbacks filled in.
   - `name_of(team_id: StringName) -> String`: reads `res://content/family_names.cfg` on the first
     call only (static cache), returns the name; an unknown id returns "Family".
3. Replace every player-visible use of `TeamDef.display_name` with `FamilyNames.name_of(team.id)`:
   `game/greybox/match_status.gd` (`line` and `_name`; the headline keeps `.to_upper()`), the debug
   HUD in `game/greybox/greybox_main.gd` (near line 2095). Then Grep `game/` and `net/` for
   `display_name`, `"Team`, `capitalize()` and team ids printed with `%s` to find any other text a
   player can see (lobby lines in `net/lobby_seat.gd`, `main_menu.gd`, `team_tell_overlay.gd`,
   `team_tell.gd`), and fix each the same way.
4. Write `godot/tests/family_names_test.gd` (new, table-driven, same shape as the other suites) and
   pin its count in `autobuild/test_baseline.json`.
5. Set `include_filter="content/family_names.cfg"` in `godot/export_presets.cfg` (a `.cfg` is not a
   resource and is left out of an export otherwise). Delete the "Until the task P5-0 is finished"
   note in `HOW_TO_PLAY.md`.
6. Do the searches in "Done means", then the one full verify, PROGRESS, DECISIONS, tick, commit.

**Already decided**
- Hand-parsed lines, not Godot's `ConfigFile` (that needs sections and quoted strings; the user was
  told plain text after the `=`).
- Fallbacks are exactly "Family A" and "Family B". They are generic, so they may be written in the
  loader and in the test.
- The loader lives in `game/`, not `sim/` or `content/`: names are presentation. Nothing in `sim/`,
  a network message, the snapshot or the world hash reads it. Each machine shows its own file.
- `TeamDef.display_name` and the "Team A" / "Team B" values in `content/levels/house.tres` STAY as
  an internal label (no re-bake in this task; `blockout_baker.gd` untouched). They are just no
  longer shown anywhere.
- The test is the one exception to "never test `game/`", because the task asks for it. Cases: both
  lines; spaces round key and value; double quotes; single quotes; empty value → fallback; one
  line missing → fallback for that team only; comment and blank lines; a value containing `=`; a
  missing file (`load_from` of a path that does not exist) → both fallbacks. The test uses made-up
  values (for example "Alpha Test"), never the real names. One case compares
  `name_of(&"team_a")` with `load_from("res://content/family_names.cfg")[&"team_a"]`.
- You never write the real names anywhere: not in code, tests, docs, `PROGRESS.md`,
  `DECISIONS.md` or the commit message. Write "the family display names".
- Bots' seat labels and the ids `team_a` / `team_b` do not change. `autoload/match_state.gd` is
  legacy code with its own "A" / "B" strings: leave it unless Grep shows the game draws it.
- Log in `DECISIONS.md` (plain, not REVIEW): loader location, hand parser, fallbacks, the export
  filter line. Leave a line in PROGRESS for P7-1: an exported game reads the packed copy, so
  changing names after export needs a re-export or an override file next to the exe (P7-1 decides).

**Files likely touched**
- `godot/game/greybox/family_names.gd` (new)
- `godot/tests/family_names_test.gd` (new), `autobuild/test_baseline.json`
- `godot/game/greybox/match_status.gd`, `godot/game/greybox/greybox_main.gd`
- maybe `godot/net/lobby_seat.gd`, `godot/game/greybox/main_menu.gd`,
  `godot/game/greybox/team_tell_overlay.gd`
- `godot/export_presets.cfg`, `HOW_TO_PLAY.md`
- `DECISIONS.md`, `PROGRESS.md`, `PLAN.md`
- NOT `godot/content/family_names.cfg` (the user's file: read it, do not edit it)

**Done means**
- `family_names_test` passes and is pinned; the other 16 suites keep their pinned counts.
- Search 1: a script reads the two values from the `.cfg` and searches the tracked files for each
  (`git grep -n -F -e <value>`, the values taken from the file by the script, not typed): the only
  hit is `godot/content/family_names.cfg`. Report "found only in the .cfg", not the values.
- Search 2: `git grep -n -e "Team A" -e "Team B" -- godot/game godot/net` has no hit in text a
  player sees (comments and the legacy autoload do not count; say which hits remain and why).
- The full `node autobuild/verify.mjs` ends `VERIFY: healthy`, run once, at the end.
- No frames, sheets, sweeps or probes.

**Do NOT**
- Build the HUD bar, lobby screen or results screen (P5-1, P5-2). Only swap the text.
- Put the names in `TeamDef`, a `.tres`, the lobby or seat message, the snapshot or any network frame.
- Re-bake the level or touch `sim/`.
- Capture frames. Write more than the one test file.
- Rename the `team_a` / `team_b` ids, zone ids or file names.

## P2-6 — Hair and builds

**Approach**
1. Read `godot/tools/rerig_character.gd` (step 5a builds the egg head: `_egg_head` returns
   `centre` and `radii`; paint regions are vertex colours from `PAINT`),
   `autobuild/rerig_family.mjs` (one entry per body, with `args`), `godot/game/art/art_theme.gd`
   (`outfit_figure`, `OUTFIT_REGIONS`, `shape_figure`) and `godot/game/art/family_member.gd`.
2. Add a paint region `hair` to `PAINT` in the re-rig tool (a mid brown, so a figure without theme
   colours still has plain hair) and to `ArtTheme.OUTFIT_REGIONS`.
3. Add `--hair=<style>` to the re-rig tool. After the egg step it appends closed, low-poly solid
   shapes, placed from the egg's `centre` and `radii`, painted `hair`, every vertex weighted 1.0 to
   the `Head` bone, with their own smooth normals. Styles below.
4. Add `--belly=<cm>` to the re-rig tool: pushes the front of the lower torso outward (see below).
5. Give each body its options in `rerig_family.mjs` (`args`) and re-run it for the six family
   bodies.
6. Add `@export var hair_colour: Color` to `FamilyMember`; `outfit_figure` colours the `hair`
   region from it (in every team-tell mode, option c too). Set the six colours and the new bone
   scales in `godot/art/theme/default_theme.tres`.
7. Check that `shape_figure` measures a member's height from the Head bone / body crown and not
   from the mesh's bounding box. If it uses the box, leave the hair out, so hair shrinks nobody.
8. Update `STYLE.md` §2.1 and §2.2, the note on D2, `DECISIONS.md` (REVIEW), `ASSETS.md` (one line:
   hair shapes are generated by our own tool, no new asset).
9. The one full verify; then the one capture set; judge it; at most one redo; PROGRESS; tick;
   commit.

**Already decided** (log all as REVIEW)
- Hair is our own generated geometry. The packs' own hair meshes stay dropped (they are styled and
  detailed). No texture, no strands, no alpha, no physics: rigid on the Head bone.
- Sizes are in egg radii: `rx` half width, `ry` half height, `rz` half depth; the "crown" is the
  egg's top. Hair sits 1 to 2 % outside the egg so it does not z-fight.
  - **Dad, comb-over:** a horseshoe band round the sides and back of the head (from ear height up
    to 0.5 `ry` above the centre, none on the forehead), plus three thin flat slabs laid across the
    bald crown from the left side to the right, with bare head showing between them.
  - **Mom, tall stiff hairdo:** a cap over the top and back of the head, and on it a tall rounded
    column (a beehive), about 0.9 `rx` wide, rising about 20 cm above the crown, leaning slightly
    back. Smooth, no curls.
  - **Boys, small mohawk:** no cap. One ridge along the middle of the head from the top of the
    forehead to the nape, about 0.18 `rx` thick; 8 cm high on the elder boy, 6 cm on the younger.
  - **Girls, two pigtails:** a thin cap over the top and back, and two bunches. Elder girl: long
    ones hanging from behind the ears down to the shoulders. Younger girl: short ones set high,
    sticking out sideways. So the two girls differ by more than size.
- Hair budget: at most 400 triangles per figure, inside the figure budget in `STYLE.md`.
- Hair may rise above the 180 cap (mom about 196 drawn, with hair). The body crown keeps the STYLE
  §2.2 heights and the sim body is untouched. Hair passing through a low gap while crouched is
  accepted. Write this exception into STYLE §2.2.
- Hair colours belong to the member, the same in both families, dull natural tones: dad dark brown
  `(0.20, 0.15, 0.11)`, mom auburn `(0.42, 0.20, 0.12)`, both boys near-black `(0.13, 0.11, 0.10)`,
  both girls sandy `(0.62, 0.48, 0.28)`. Teams are still read from the clothes.
- **Dad's belly** is a vertex push in the re-rig tool, not a bone scale (a scale widens the whole
  torso evenly): vertices weighted to `pelvis` / `spine_01` / `spine_02` whose normal faces forward
  move forward by up to 9 cm, falling off smoothly up, down and to the sides. Fallback if it tears
  or reads wrong: bone scale `(1.12, 1, 1.35)` on `spine_01` and `spine_02` with the inverse on
  `spine_03`, the way P2-1 gave the kids' heads their width back.
- **Mom's build** is bone scales in the theme: wider shoulders (clavicles out, or `spine_03` x
  about 1.12 with the neck and head given the inverse), upper arms about 1.25 thick, forearms about
  1.12. Check which axis runs along the bone before scaling; scale only the two across it. Dad's
  arms 0.95 thick for contrast. The children keep their P2-1b shapes.
- Faces stay blank. STYLE §2.1: "hair" moves from the forbidden list to "allowed as plain solid
  shapes in the figure material"; eyes, brows, mouth and nose stay forbidden.
- Art stays optional: a missing `.gltf` still falls back as before. The animation set
  (`figure_anims.res`) is not rebuilt.

**Files likely touched**
- `godot/tools/rerig_character.gd`, `autobuild/rerig_family.mjs`
- `godot/art/characters/figure_lp_shirt`, `_dress`, `_alt`, `_male`, `_tank`, `_casual`
  (`.gltf` and `0.bin`, re-made)
- `godot/game/art/family_member.gd`, `godot/game/art/art_theme.gd`
- `godot/art/theme/default_theme.tres`
- `STYLE.md`, `DECISIONS.md`, `ASSETS.md`, `PROGRESS.md`, `PLAN.md`
- NOT `godot/art/theme/_tmp_noshell.tres` (an untracked leftover, not yours: do not add it)

**Done means**
- The full `node autobuild/verify.mjs` ends `VERIFY: healthy`, run once. A redo that changes only
  art files does not need a second full run; say so in PROGRESS.
- Each re-made body reports a triangle count within the figure budget.
- ONE capture set at the end: `node autobuild/family_lineup.mjs --import` and
  `node autobuild/turnaround.mjs`. Open every frame with the Read tool and write what it shows.
  - Lineup, front / side / back: six figures. Dad has a visible belly in the side view and slabs
    across a bald crown. Mom has broad shoulders, thick arms and the tall hairdo. Each boy has a
    ridge on a bare head. Each girl has two bunches, long on the elder, short and high on the
    younger. No face on anyone. No holes, no hair floating off the head or sunk inside it.
  - Lineup at 20 m: dad, mom, a boy and a girl told apart by outline alone. At 40 m: at least dad,
    mom and "a child" (as in P2-1b), with the hairdo and the belly still visible.
  - Turnaround, six sheets: from the back and the side each hair shape is closed and sits on the
    head; the belly joins chest and hips without a step; the arms do not pass through the belly.
- At most ONE redo of what looks wrong, then describe what is left.

**Do NOT**
- Draw faces, eyebrows, beards or ears. No hair texture, strands, transparency or bounce.
- Download anything. Change `sim/`, tuning, collision or the bodies' drawn heights.
- Rebuild or retime animations; change `FigureAnimator`.
- Colour hair by team. Add tests. Shoot team sheets, chase views or any second capture set.
- Copy another game's character designs.

## P3-8 — Territory line, gate and house layout

**Approach**
1. Read `godot/tools/build_house.gd` (lot constants near line 151; `_outdoors` at 733; `_stamp` and
   `_place` turn House A's parts into House B; `_straight_flight`; `_upper`),
   `godot/sim/systems/capture_system.gd` (`_try_capture`, `_may_capture_on`),
   `godot/content/content_validator.gd` (the two `Role.NEUTRAL` checks), `godot/HOUSE_LAYOUT.md` §5
   and §9, and how `game/art/shell_builder.gd` and `exterior_builder.gd` draw stairs, fences and
   the ground. Find how the level is re-baked (`tools/bake_blockout_headless.gd`, run through
   `node autobuild/run_tool.mjs`).
2. Measure today: the wall-to-wall gap is `HOUSE_B_X − (HOUSE_A_X + HOUSE)` = 520. Write it down.
3. Widen the lot (constants only), add the fence blockers with their openings, replace the zones.
4. Add the back staircase to the per-house build, so `_stamp` turns it for House B.
5. Change the seize rule and its table test. Re-bake. Fix what the validator and the tests say.
6. Draw it: the fence, its openings and the lawn in `ExteriorBuilder`; the staircase through the
   same code that draws the indoor flights; the yard props.
7. Move everything that has fixed lot coordinates (see "Files").
8. Docs, D9, the one full verify, the one capture set, at most one redo, PROGRESS, tick, commit.

**Already decided** (log all as REVIEW)
- **Gap.** Wall to wall goes from 520 to **2400** (4.4 s at 540 a second). The task's two numbers
  disagree if "distance" means wall to wall (double is 1040, under 2 s to walk). The walk time is
  what a player feels, so it wins, and 2400 is also more than double. Log both numbers. `LOT_W`
  becomes 5400 + 1880 = 7280 (182 cells of 40). `LOT_D`, both houses' z, the margins and the
  houses' insides do not change.
- **No re-orientation.** The houses keep the half turn about the lot centre and their diagonal
  offset: the smallest change that meets the rule, and the symmetry probe is built on the half
  turn. Front doors facing each other is not done.
- **Territory = which side of the lot's x midline.** Delete the NEUTRAL `lot` zone. `yard_a` is
  the whole lot with x below the midline, `yard_b` the rest: HOME, owned, outdoor, priority 0;
  rooms still win inside the houses. `TERRITORY` (400) goes. The `Role.NEUTRAL` enum value stays
  (tests use it). After this every point in the lot has an owning team: write that in
  `PROJECT_MEMORY.md`, because P4-8's home speed reads it.
- **The fence** is real collision on the midline: 30 thick, 230 high from the ground (the tall
  blocker height, so it looks and is unclimbable), the full depth of the lot, with openings:
  - one **main gate**, 400 wide, centred on the lot centre;
  - **two small crossings**, 160 wide, their centres 300 in from each end of the fence. The user
    asked for one at the back. With the houses a half turn apart, a single off-centre opening
    cannot be symmetric: it needs its twin. Each house's back is the other's front, so each
    crossing is "the back one" for one family. Log this.
- **Seize rule.** A seizure is legal when the captor and the target each stand on ground the
  captor's team owns, neither zone is the JAIL, they are within capture range, the target is not
  protected, and no blocker lies between them (the collision's `blocks_segment`). The line test
  replaces the "same zone id" test, whose purpose was to stop seizing through a wall. So a seizure
  from house to yard through a doorway now works, and nobody is seized on their own side. If two
  attempts cannot keep the bot match gate healthy with the line test, put the same-zone test back,
  keep the zone change, and log it.
- **Back staircase.** One straight flight outside each house's north face (House A's back: its
  front faces south), parallel to the wall, up to a small platform at upper-floor height and a
  normal 240 door into **Landing B** (the north-west landing), not the master bedroom. Use the
  indoor flight's rise, run and 280 width. Keep it clear of the master bedroom's north escape
  window and its drop spot, and of any ground-floor north door. Platform and flight are blockers
  with walkable tops like the indoor stairs. The house wall is its inner side; draw the outer side
  the way P3-5 drew open stair sides (no blocker there, so no banister). Two-way: a real route.
- **Yard props.** Two or three per house. The collision box is THE SAME at the turned spot in both
  yards (symmetry stays exact) and the drawn model differs by family (a theme table: team id →
  model per prop slot), for example a barbecue where the other yard has a wheelbarrow. Boxes follow
  the 120 / 210+ thresholds. Use pieces already in `godot/art/props/` or plain shapes built in
  code; no downloads.
- **Family colours on trim, door and roof belong to P3-7**, not to this task.
- **Ground.** There is no neutral ground now: the gravel that marked it becomes lawn, with a paved
  strip through the main gate. The neighbours' houses stay (P3-7 removes them).
- **Numbers that move.** A level change moves the bot match. A winner in regulation and a
  deterministic match are required. If a match is not decided, lengthen `round_seconds` ONCE in
  `content/modes/` (1v1 120 → 180, 2v2 180 → 240, 3v3 and 4v4 240 → 300). If only the pinned
  figures in `autobuild/metrics_budget.json`, or the gated draws and triangles in
  `autobuild/render_budget.json`, fail because the level is different, re-pin them once at the
  measured value plus the margin the file already uses, and log old and new. The tick budget
  (5 of 600) is not loosened.

**Files likely touched**
- `godot/tools/build_house.gd`, then the re-baked `godot/game/blockout/house.tscn` and
  `godot/content/levels/house.tres`
- `godot/sim/systems/capture_system.gd`, `godot/tests/capture_system_test.gd` (new rows: defender
  and intruder on the defender's side, in the yard and in the house; across a doorway; through a
  wall; an intruder on their own side; both in the gate opening, on each side of the line; jail),
  the pinned count in `autobuild/test_baseline.json`
- maybe `godot/content/content_validator.gd`, `godot/tests/content_validator_test.gd`,
  `godot/tests/greybox_level_test.gd`, `godot/tests/navigation_test.gd` (fixed coordinates)
- `godot/game/art/exterior_builder.gd`, `godot/game/art/shell_builder.gd`,
  `godot/game/art/furniture_dresser.gd`, `godot/game/art/art_theme.gd`,
  `godot/art/theme/default_theme.tres`
- Fixed lot coordinates: `autobuild/views.json` (every House B and exterior view: House B moves
  +1880 in x), `godot/game/debug/playtest_pilot.gd`, `godot/game/debug/frame_capture.gd`, the
  figure spots in `autobuild/family_lineup.mjs`, `family_teams.mjs`, `turnaround.mjs`,
  `team_tell_frames.mjs`, `anim_sheet.mjs` and the examples in `godot/CLAUDE.md`. Spots near
  x 2700 stood on the old midline; the fence now stands on the new one (3640), so move them into
  a yard.
- `godot/content/modes/house_*.tres` only if rounds must be lengthened
- `godot/HOUSE_LAYOUT.md` (§5, §7, §9), `godot/WORLD_AUTHORING.md`, `godot/PROJECT_MEMORY.md`,
  `DECISIONS.md` (the D9 row and the log), `PROGRESS.md`, `PLAN.md`

**Done means**
- The capture rows pass and are pinned; the validator, `greybox_level_test` and `navigation_test`
  pass on the re-baked level.
- The full `node autobuild/verify.mjs` ends `VERIFY: healthy`, run once at the end: symmetry probe
  exact, 3v3 and 1v1 bot matches deterministic with a winner, tick budget, net smoke. Old and new
  bot match numbers in PROGRESS.
- Numbers in PROGRESS: old gap 520, new gap, seconds to walk it at 540.
- ONE capture set at the end, `node autobuild/verify.mjs --frames-only --views=ext_,lot_,cam_fence,cam_backstair`,
  with the new views below added to `views.json` first. Open each with the Read tool:
  - `lot_overview`: two houses far apart, one fence down the middle, lawn on both sides, no gravel
    strip.
  - `ext_gate_mid` (new): the main gate from House A's yard at eye height: a clear opening a body
    fits through, fence on both sides taller than a person.
  - `ext_cross_n`, `ext_cross_s` (new): each small crossing: clearly narrower than the gate, open.
  - `ext_backstair_a`, `ext_backstair_b` (new): the flight from the yard: the steps reach the
    ground, the platform meets a door, nothing floats, it crosses no window. Both the same shape.
  - `cam_backstair_top` (new): through the chase camera on the platform: door and yard readable.
  - `ext_a_*` and `ext_b_north`: each yard's props are there and differ between the houses.
- At most ONE redo, then say what is left.

**Do NOT**
- Bot tuning, `side_sweep.mjs`, extra seeds, `risk_weight`: bots only have to pass the gate.
- Change the houses' inside layout, the rooms, the cash or the jail, or the existing doors and
  windows (the one new door is the back stair's).
- Give one house anything with collision that the other lacks.
- Add the home speed boost or touch the panic run (P4-8). Remove the neighbours, add hedges or
  paint the family colours (P3-7).
- Build a banister or railing with no blocker behind it. Loosen the tick budget.
- More than one capture set; any sweep or probe beyond what `verify.mjs` itself runs.
