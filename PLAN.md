# Cash Grab — autonomous build plan

**Goal:** a polished, playable, deployable multiplayer version 1 of Cash Grab in Godot 4.7
(Compatibility renderer): a deadpan look (DECISIONS.md D2: blank-faced, slightly off-proportioned
figures in a realistic-leaning suburban house) from free CC0 assets only (D10), the v1 verb set
(D9), menus and audio, Steam-ready networking, a Windows build.

**How to use this file.** The loop gives each session one task. Take the **first unchecked task
whose dependencies are done and which is not marked `BLOCKED`**. Finish it, verify it, tick it,
add a line to `PROGRESS.md`, commit. Do not start another task in the same session if you are past
roughly 60% of your turn budget.

- `[ ]` open · `[x]` done · `[~]` partly done (say what is left in PROGRESS.md) · `[B]` blocked (see BLOCKED.md)
  · `[-]` deferred by the user (never start it; see the Backlog sections)
- **Verify** = what proves it. Visual tasks are not done until a frame has been opened and looked at.
- Standing rules: `DECISIONS.md` (how to decide without asking), `godot/CLAUDE.md` (testing policy,
  look at the frame, conventions), `godot/DESIGN_DIRECTION.md` (settled design — do not reopen
  without new evidence).

## Where the project actually stands (measured at the start of the autobuild)

Measured on branch `claude/godot-port` at merge commit `5ac27d6` (the user's 29 local commits from
Aug 16–Oct 10 are in; an earlier version of this plan was written against the stale Aug-15 state).

- Rules/simulation/netcode: **healthy.** 16 suites, 16 pinned in `test_baseline.json`, all green; bot
  match deterministic, ends with a winner, **42 s** of stalls (was 474 s on the stale branch).
- Verbs built in the sim: **crouch, jump, throw** (vault was built and removed on purpose — jump
  does the job). Controls: move WASD, jump SPACE, crouch SHIFT, seize/free E, grab-drop LMB/X, throw RMB,
  F10 leave to menu. Only crouch is *drawn*; jump and throw have no presentation. **Slide and
  drop-from-height are not built, and are not in v1 (DECISIONS.md D9).**
- Multiplayer sits behind a **main menu** (`game/greybox/main_menu.gd`) — never played by two people over a real network.
- Art: a Blender pipeline exists (`godot/art/`): `cash.glb`, `character_a.glb`, `character_b.glb`,
  procedurally built, blocky/voxel look. The house is still the grey blockout. Black void around the
  level, debug HUD baked into every frame, no lighting/sky to speak of.
- Known engine issue (documented in `PROJECT_MEMORY.md` §6): bot decisions + routing exceed the 33 ms
  tick (p99 ≈ 57–73 ms, 43–47 of 600 ticks over budget) → hitching. Fix is scheduling, not a faster search.
- Art rules already in force (`godot/art/README.md`): **1 unit = 1 cm** (models authored at that scale,
  Y-up, export scale 1 — a metre-scale asset imports 100× too small); art is optional via
  `ResourceLoader.exists` + primitive fallback; art never feeds collision or the sim.

## Phase 0 — Make the engine playable (before any art)

- [x] **P0-1 Baseline.** `node autobuild/verify.mjs` is green on this machine (set `GODOT_BIN`).
  Record Godot path and machine notes in PROGRESS.md. *Verify:* output ends `VERIFY: healthy`.
- [x] **P0-2 Tick budget (hitching).** *(Done for the shipped 1v1; 3v3 still 38–46 of 600 over — see PROGRESS.md.)* Bot decision + routing exceed the 33 ms tick (see "Known engine
  issue" above and `PROJECT_MEMORY.md` §6 3c). Spread a bot decision across several ticks in
  `BotDirector` (scheduling change, not an algorithm change; do not retry route variety). Use the
  existing timing instrument (find it in `godot/tools/`; build the measuring step first if it does not
  report p99 and over-budget tick counts). Target: p99 < 33 ms, over-budget ticks < 5 in 600, bot_match
  still deterministic with a winner. *Verify:* before/after numbers in PROGRESS.md; budget ratcheted.
- [x] **P0-2b Tick budget in 3v3 and 4v4.** *(Done: 3v3 0–1 of 600 over, gated in verify.mjs; 4v4 0 in 8 of 10 runs, 2 and 5 in the others, printed but not gated. See PROGRESS.md.)* The game ships 2v2 to 4v4. Make perf_probe --team-size=3 and --team-size=4 stay under 5 of 600 ticks over 33 ms, using the ideas listed under 'Left' in the P0-2 PROGRESS entry (walk only the cells a segment crosses, nearest-first look-ahead, fewer checks per tick). bot_match must stay deterministic, with stalls no higher than 42 s. Add the 3v3 check to verify.mjs once it holds.
- [x] **P0-2c Tuning per team size.** *(Done: `content/modes/house_NvN.tres`; 24 of 24 sweep matches at 2v2–4v4 decided; verify gates 3v3 + 1v1. Strong team_a side bias found — see PROGRESS.md.)* Make round length, jail time, cash per team and any other per-match numbers scale with team size (data in content/, not code), so a bot match at 2v2, 3v3 and 4v4 each ends with a winner inside the round timer. Measure first: run bot_match at each size, record rounds, captures, rescues, deposits and time to win. Keep the 1v1 numbers unchanged. When all sizes produce a winner, change verify.mjs to run the bot match at 3v3 as the main gate (deterministic, a winner, stalls budget re-measured for 3v3) and keep 1v1 as a second quick check. Log the chosen numbers in DECISIONS.md as REVIEW: they are tuned against bots, and a human playtest may change them.
- [x] **P0-3 Bot stalls and a finishing match.** Already true at the start of the autobuild (stalls 42 s,
  winner `team_a`). `metrics_budget.json` pins it: stalls ≤ 42, a winner is required. Do not regress.
- [x] **P0-4 Clean frames.** Add a capture option that hides the debug HUD (e.g. `--capture-clean`),
  and make the debug HUD hidden by default behind an F-key. Update `verify.mjs --frames` to use it.
  *Verify:* a frame with no text.
- [x] **P0-5 Visible world.** Replace the black void: sky/background, ground plane beyond the lots,
  basic environment lighting and exposure. *Verify:* frames from `views.json` show horizon, no black voids.
- [x] **P0-5b Team A bias.** *(Done: team_a 13, team_b 9, 2 undecided over 24 (was 20–4). Cause: ties broken in world scan order in five places; see PROGRESS.md and PROJECT_MEMORY §6c-ii.)* In bot matches at 2v2-4v4 team_a won 20 of 24 (see PROGRESS P0-2c). Measure first: swap which team is seated first and which house each team gets, compare raiding % and wins over 8 seeds per size, find the cause (seating, spawn order, bot director, layout) and fix it. Target: no side wins more than 15 of 24. Log the cause in PROJECT_MEMORY.md.
- [x] **P0-5c Four spawn points per team.** *(Done: fourth marker off the front face, 500 along from the third; 4v4 bot match deterministic with a winner.)* 4v4 seats 4 per team but the level has 3 spawn markers, so two bodies start on one point. Add a fourth marker per house in build_house.gd and re-bake. Validator, tests and bot match must stay green.
- [x] **P0-5d Default to a team game.** *(Done: 3v3 default, Team size on the menu for solo/host, `--team-size=N`; a guest rejoins at the host's size. Two-process 4v4 host + default guest checked.)* The game still seats 1v1 by default (DEFAULT_TEAM_SIZE). Make the local and hosted default 3v3 with bots filling empty seats, with team size selectable in the lobby/menu. 1v1 remains available for testing.
- [x] **P0-6 Camera everywhere.** *(Done: `--capture-chase` shoots through the real rig; 16 `cam_*` views, all readable; the own body fades when the arm is pushed in. No basement exists — the jail is the ground-floor SW room. See PROGRESS.md.)* Third-person camera must give a usable view in every space:
  basement/jail, upstairs, stairwells, vault, garden, doorways. Walls between camera and player
  must not blind the player (fade or cut away). Add one `views.json` entry per space.
  *Verify:* ≥12 frames, each judged readable; camera_controls_test still green.
- [x] **P0-7 "Patchy graphics" sweep.** *(Done: 16 `room_*` + 6 exterior views; fill light for unlit faces, floor tint resolved by zone priority with straight edges. See PROGRESS.md.)* Capture every room, both houses, both floors. Log every
  defect (z-fighting, floor tint over stairwell, gaps, flipped normals, wrong colour, clipping),
  fix them, re-capture. *Verify:* before/after frame names in PROGRESS.md; validator still green.
- [x] **P0-8 Playable local session.** *(Done: `--pilot` plays a whole 3v3 solo session and the host/join path through injected input; always-on status line + round/match headline, Enter rematch, carried cash drawn overhead. See PROGRESS.md.)* One human + bots: start from the main scene, move, grab,
  drop, seize, free, score, win a round and a match, return to start. Fix whatever breaks.
  Use the capture tool's injected-input options and `bot_match --lone` to exercise it. Include the
  main menu → host/join → lobby → match → F10 back-to-menu path, and test jump, crouch and throw by eye.
  *Verify:* written walkthrough in PROGRESS.md with frames at each step.
- [x] **P0-9 Network smoke.** *(Done: `autobuild/net_smoke.mjs` runs a headless host + guest of the real game over ENet and compares every tick's world hash; 5 of 5 runs clean incl. two whole matches to MATCH_END; gated in full verify with net_loopback/net_lobby. Snapshot format 2 fixed a mid-throw divergence. See PROGRESS.md.)* `tools/net_loopback.gd` and `tools/net_lobby.gd` pass; two local
  Godot processes (host + join on localhost) complete a lobby and a short match. Add the
  headless variant to `verify.mjs` if it is stable. *Verify:* log excerpt in PROGRESS.md.
- [x] **P0-10 Housekeeping.** *(Done: root CLAUDE.md points at `godot/` and the autobuild files; Three.js rules scoped to legacy `client/`/`server/`.)* Root `CLAUDE.md` still says the Three.js branch is the source of
  truth: point it at the Godot project, mark `client/` and `server/` legacy. Do not delete them.
- [x] **P0-11 Faster movement.** *(Done: `move_speed` 440 → 540 (+23 %); crouch 297 and carry 459 follow through their scales. Sweep at 2v2–4v4: 47 of 48 matches decided with the round and jail times unchanged; a shorter jail was tried and was worse at 2v2, so the mode files stay. See PROGRESS.md.)* The user found movement too slow and boring. Raise walking and jogging speed by about 20-25 % and crouch speed by the same ratio; carriers keep their 0.85 factor. Speeds stay in content data. Re-check that jumps, ledges, crouch gaps and seize/free reach still work (validator, tests, bot match). Re-run the per-team-size tuning sweep from P0-2c, since faster movement ends rounds sooner, and adjust round and jail times so every size still ends with a winner. Log the new numbers in DECISIONS.md as REVIEW. Note for P4-1: the panic run boost is added on top of the new speed.

## Phase 1 — Art foundation (style, shader, asset pipeline)

- [x] **P1-1 Render stats tool.** *(Done: `RenderStats` via `--capture-stats`/`--capture-timing=N` + `autobuild/render_stats.mjs` over every view; budgets in STYLE.md and `autobuild/render_budget.json`; baseline max 526 draws, 27k tris, GPU 5.4 ms on the GT 730M. See PROGRESS.md.)* `godot/tools/render_stats.gd`: print draw calls, triangles,
  objects in view for a given view. Propose budgets for the Compatibility renderer on a GT 730M-class
  GPU, record them in `STYLE.md`. Frame time is measured only when running windowed on the
  dev machine; software-rendered frame time is meaningless.
- [x] **P1-2 Asset ledger.** *(Done: ASSETS.md + CREDITS.md; both Quaternius zips checked CC0. The free character pack has only Superhero male/female bodies, no Regular/Teen: substitute logged REVIEW, note in BLOCKED.md.)* Create `ASSETS.md` (name · source URL · license · date · modified?) and
  `CREDITS.md`. Free sources only (DECISIONS.md D10): CC0 first, CC-BY if credited. No paid AI
  tools or credits, nothing bought. Never: NC/ND licences, ripped game assets, anything unclear.
  Add the two Quaternius packs the user downloaded (Universal Base Characters, Universal Animation
  Library, both CC0, zips in `autobuild/incoming/`).
- [x] **P1-3 STYLE.md.** *(Done: STYLE.md §1–6 above the budgets: figures (blank, putty-grey satin, heights 180/176/160/145, one nudge each), team identity and family colours, house scale to the thresholds, rooms, palette, lighting, the 9-point "polished" checklist. No references were supplied. See PROGRESS.md.)* Art direction per DECISIONS.md D2 (deadpan): identical, blank-faced,
  slightly off-proportioned, silly figures with no facial features and no expressive acting (not
  literal crash-test dummies); the house is the realistic side — believable suburban furniture,
  materials and warm lighting, as realistic as the Compatibility renderer allows. No toon outlines,
  no cartoon VFX or confetti. Comedy comes from plain bodies doing absurd things straight-faced.
  If the user left images in `autobuild/references/`, derive from them and cite which. Define the
  figures' proportions and material, the house's materials and palette, the lighting, the budgets
  from P1-1, and what "polished" means.
- [x] **P1-4 ArtTheme: one shared material and lighting setup.** *(Done: `ArtTheme` + `art/theme/default_theme.tres`; figures, cash and blockout re-materialed from it; sun shadow on, lamps built but off on cost, warm sky fill + ambient, linear tonemap. See PROGRESS.md.)* One `ArtTheme` Resource holding the
  character material, realistic-leaning house materials and warm interior lighting, working in the
  Compatibility renderer. No outline shader. Every imported mesh gets its material replaced from
  the theme so mixed sources look like one game. Changing the look later = editing the theme.
  *Verify:* frames.
- [x] **P1-5 Style slice.** *(Done: `autobuild/style_slice.mjs` shoots A putty / B painted clothes / C vinyl big-head (+ the pick) in the study from 4 views into `autobuild/slice/`; figures baked blank by `autobuild/figure_bake.mjs`; STYLE-PICK = painted clothes + halved nudge + P1-4 lighting, adopted in `default_theme.tres`. See PROGRESS.md.)* Build **three** variants (A/B/C) of the same room (use the vault room),
  all following D2. They differ in how the Quaternius figures (D10) are made deadpan — three
  different blank, silly treatments — and in the house lighting. Capture each from 4 views into
  `autobuild/slice/`. Pick the recommended variant, write the reasoning in DECISIONS.md under
  `STYLE-PICK` (REVIEW). **Do not wait for the user** — adopt your pick and continue; the user may
  override and the theme makes that cheap.
- [x] **P1-6 Asset import pipeline.** *(Done: `fetch_polyhaven.mjs` → `import_asset.mjs` / `tools/import_asset.gd` (scale, pivot, no collision, one mesh, theme material names, budget, decimation) → `ArtTheme.prop_instance` with null fallback; `--capture-prop` to see one; documented in `godot/art/README.md`; two Poly Haven samples in `godot/art/props/`. See PROGRESS.md.)* A documented, repeatable path from a downloaded `.glb`/`.fbx`
  to `godot/art/…`: **scale to world units (1 unit = 1 cm, so most downloaded assets, authored in
  metres, need ×100)**, Y-up, pivot, theme material, LOD/poly check against the budget. Keep the
  `ResourceLoader.exists` + primitive fallback convention from `godot/art/README.md`.
  Art meshes never carry collision; the blockout/collision data stays the source of truth.

## Phase 2 — Characters and animation

- [x] **P2-1 The family of four** *(Done: both bodies decimated to 5,000 triangles in `figure_bake.mjs`; six `FamilyMember`s (dad, mom, elder girl/boy, younger girl/boy) in the theme, drawn per roster slot; `autobuild/family_lineup.mjs` shoots them. See PROGRESS.md.)* from the Quaternius Universal Base Characters per DECISIONS.md D10:
  dad, mom, elder child, younger child (Regular male/female = dad/mom, Teen male/female = the kids).
  They differ in size and shape only, and all have blank faces per D2: remove eyes, hair and facial
  detail, smooth plastic-like material, slightly off proportions; decimate to the `STYLE.md` budget.
  Make both children available as a girl and a boy so D3 option (d) (kid swap) works. Unzip from
  `autobuild/incoming/` (keep the zips out of git), record in ASSETS.md. The old blocky
  `character_a/b.glb` stay in place until the new figures load (art stays optional via fallback).
- [x] **P2-1b Distinct family members in family outfits (DECISIONS.md D3, updated 2026-11-14).**
  *(Done 2026-11-15: six bodies, one per member (dad Male_Shirt, mom Female_Dress, elder girl/boy
  Female_Alternative/Male_LongSleeve, younger girl/boy Female_TankTop/Male_Casual), each with an
  `outfit`; `family_palettes` in the theme (A green + denim, B rust + mustard); frames in
  `autobuild/frames/p2_1b/teams_*.png`. At 40 m the teams read; members only as dad / mom / a child.
  See PROGRESS.md.)*
  *(First pass done 2026-11-14: all four packs in `autobuild/Incoming/` checked CC0; pick =
  Quaternius Animated low poly men/women (REVIEW), re-rigged onto the figure skeleton by
  `tools/rerig_character.gd` (`autobuild/rerig_family.mjs`) with a clean egg head; the whole family
  and `figure_anims.res` use them. See PROGRESS.md.)*
  **Reopened after the user's playtest: identical figures made the game confusing.** Build the
  family to the new D3 default: dad, mom, elder child and younger child each have a clearly
  different body shape and outfit, readable at a distance, and each family wears matching outfits
  in its own colour scheme (like a family in matching sweaters), so teams are obvious. Figures stay
  blank-faced and deadpan per D2: only clothes, colours and body shapes differ. Use the bodies and
  outfits in the four packs already checked (any of their bodies, not only the two picked); stay
  within the poly budget and keep the existing animations working. Keep a girl and a boy at each
  child size so the kid swap option still works. Outfits and colour schemes are data in the theme.
  Log the result in DECISIONS.md as REVIEW. *Verify:* lineup and turnaround frames re-shot; both
  families side by side from 20 m and 40 m, each member and each team told apart in the frame.
- [x] **P2-2 One skeleton, one animation set** *(Done: `art/characters/figure_anims.res`, 24 clips built by `tools/build_figure_anims.gd`; deadpan picks and IK arm poses (carry overhead, panic arms, throw); stride speeds per loop; `anim_sheet.mjs` contact sheets. See PROGRESS.md.)* from the Quaternius Universal Animation Library per
  D10 (same rig as the base characters). Needed: walk, panic-run with arms up, idle (completely
  still), jump and land, crouch-walk, carry-overhead walk and run, throw, jail run-in-place, free
  ally. Procedural wobble allowed but subtle. No ragdoll, stumble or get-up (D9).
- [x] **P2-3 Animation driver.** *(Done: `FigureAnimator` (AnimationTree: base Transition, stride-matched rate, arms-only one-shots) from sim state; one-shots from confirmed-state changes; contact sheets of live bodies for jog/walk, jump, crouch, grab/carry, throw, seize, free in `autobuild/frames/p2_3/`. Panic run waits for P4-1's speed boost, jail run-in-place for P4-3. See PROGRESS.md.)* AnimationTree/state machine driven from simulation state
  (read-only; presentation never mutates the sim). *Verify:* frames/gif-like contact sheets per state.
- [x] **P2-4 Team tell (DECISIONS.md D3, updated 2026-11-14).** *(Done 2026-11-15: default = family
  outfits with all four options off; (c) switches the outfits back to identical plain clothes plus
  the wristband; choices saved under the old default are not read. Frames of the default and each
  option in `autobuild/frames/p2_4/`. See PROGRESS.md.)* *(First pass done 2026-11-13:
  `TeamTell` setting, all four options combinable; menu checkboxes, F5-F8, `--team-tell=`; default
  minimap + wristband; frames of every set close/20 m/40 m in `autobuild/frames/p2_4/`. See PROGRESS.md.)*
  **Reopened after the user's playtest; do it after P2-1b.** The shipped default becomes the new D3
  default: distinct family members in matching family outfits (from P2-1b), so teams are obvious
  with no other tell. Keep the earlier ideas as switchable options for later playtests, data-driven,
  combinable, from the settings and a debug key with no code change: (a) marker over your own
  teammates only, never over enemies; (b) minimap showing only your teammates; (c) identical
  families except one detail (this option switches the family outfits back to identical, plus the
  wristband); (d) kid swap. They are off by default. Log the new default in DECISIONS.md as REVIEW.
  *Verify:* frames of the default and of each option, from 20 m and 40 m.
- [x] **P2-5 Turnaround sheet.** *(Done: `node autobuild/turnaround.mjs` → `autobuild/slice/turnaround_<member>.png`, the six family members, each one frame of four copies turned front/right/back/left against their own line of sight. See PROGRESS.md.)* One capture per character from 4 angles in `autobuild/slice/`.

## Phase 3 — The house and the lot

- [x] **P3-1 Kit selection.** *(Done: Kenney Furniture Kit for furniture and appliances; Poly Haven textures plus ambientCG for carpet/wallpaper; the shell generated from the blockout; safe, jail pen and cash our own. `autobuild/fetch_kenney.mjs`; 8 trial pieces in `art/props/kenney/`, seen in kitchen A and bedroom A. REVIEW. See PROGRESS.md.)* Choose wall/door/window/floor/roof/stair/furniture packs (Kenney,
  Quaternius, KayKit, others CC0). Log in ASSETS.md. Prefer one or two coherent packs over many.
- [x] **P3-2 Shell dressing.** *(Done: `ShellBuilder` generates the textured shell from the blockers at load: plaster/block/brick walls, tiled/oak/carpet floors, ceilings, oak treads with painted risers, casings, open family-colour french doors, skirting, a hipped roof; one mesh per house. Collision and zones untouched. Frames of all 16 rooms, 6 exteriors, 16 camera views. See PROGRESS.md.)* Visual shell from the existing blockout data (`godot/game/blockout`,
  `HOUSE_LAYOUT`/`WORLD_AUTHORING`): walls, floors, doors, windows, stairs, roof with reveal. Collision
  and zones unchanged. *Verify:* content validator + all tests green; frames of every room.
- [x] **P3-3 Interiors.** *(Closed 2026-11-15 by the user's re-plan: its bot items are in "Backlog: bots"; GPU timing was done in P3-3b. Banisters were not built.)* *(Partly done: every room furnished with real collision at the 120/≥210 thresholds from one table in `build_house.gd`; Kenney pieces fitted to their boxes; procedural safe and jail pen. Left: a 4v4 bot stall in the upstairs study corner, a team_a lean in the sweep, GPU timing, banisters. See PROGRESS.md.)* Furnish every room. Obey `WORLD_AUTHORING.md` §12 thresholds: anything the
  rules let you climb must *look* climbable, anything that blocks must *look* tall. Distinct
  silhouettes for vault, cash bundle, jail/basement door, safe room.
- [x] **P3-3b Furniture follow-ups.** *(Done: the "study corner" stall was bots patrolling a zone's box centre (the yard's is inside the house wall, the lot's nearest stance is House A's bedroom, jail/kitchen centres are nearest furniture tops); `NavGraph.zone_point` now gives an on-foot stance in the zone. 4v4 seed 8 stalls 626 → 169 s; sweep side lean team_a 10 / team_b 13, house A 22 / B 20; kitchen GPU 8.7 ms; cash on a top is out of floor reach (pickup 70), so bots ignore it. 4v4 stairwell congestion left as P3-3c. See PROGRESS.md.)* With furniture in (P3-3): (1) 4v4 bot_match seeds 3 and 8
  stall 600+ s, 88 % of it in five spots, the worst being the upstairs study NE corner in both houses, bots at leg 0
  of a PATROL route. Find what the leg aims at and fix it (measure first; `bot_match --team-size=4 --seed=8 --once`).
  (2) Re-run `autobuild/side_sweep.mjs`: the decided matches leaned team_a 16 to 6. (3) GPU timing of the kitchen and
  bedroom views against the 9 ms budget (`render_stats.mjs`). (4) Check that bots can fetch cash lying on a
  120 top. *Verify:* 4v4 sweep stalls back near the 3v3 range, and side lean within P0-5b's target.
- [x] **P3-3c 4v4 stairwell congestion.** *(Done 2026-11-15: not congestion. One bot at a time failed to step off a landing onto the flight below: the route's drop waypoints were ticked off from the lip, and re-aiming at the landing spot turned the body back. Fixed in `BotDirector` (`_has_reached`, `_drop_pending`). 4v4 sweep stalls 16–69 s, median 56 (3v3: 14–88, median 42). Undecided matches went up; see P3-3d and PROGRESS.md.)* After P3-3b, 4 of 16 4v4 sweep matches still stall 228–374 s
  (median 125; 3v3 range 24–132), all with `--swap-houses`. `bot_match --team-size=4 --seed=4 --once --swap-houses`:
  63 % of 374 s in five spots at the two stairwells (House A local ~(250–370, 1450) by stair B, ~(1570–1690, 490)
  by stair A), DEPOSIT routes at legs 3–5, many bodies at once. Measure first (who is pressed against whom, which
  leg); the give-way rule in `BotDirector._steer` is the likely place. *Verify:* 4v4 sweep stalls within the 3v3 range.
- [-] **P3-3d Matches that end level after the drop fix.** *(Deferred by the user, bot balance, 2026-11-15; see "Backlog: bots".)* *(Partly done 2026-11-15: the patrol-post idling was a bot standoff; `risk_weight` 1400 → 800 in the bot profile ended it (idle median 10–24 s a match) and the house lean (A 13, B 14), drawn rounds 11 → 6, but 5 of 32 matches still end level (target 2). Mode files unchanged. Left: P3-3e. See PROGRESS.md.)* With bots no longer stuck on landings (P3-3c), the
  3v3 + 4v4 sweep (seeds 1–8, as-is and swapped) left 6 of 32 matches undecided, against 1 of 32 at P0-11: 28 of
  85 rounds ended on the clock and 11 were drawn, and 91 % of seizures were rescued (85 % before). 3v3 also leaned
  to House B, 10 to 3 (4v4: A 8, B 5). Measure first (`node autobuild/side_sweep.mjs --sizes=3,4`, and
  `--mode.capture_seconds=` / `--mode.round_seconds=` as arguments): is it the rescue rate, the 1117 s of
  patrol-post idling at 4v4 (`bot_match --why-idle`: STEAL scores about −3400 with 4 threats), or the clock?
  Change mode data, not rules; tuned against bots, so REVIEW. *Verify:* at most 2 of 32 undecided, and neither
  house above P0-5b's 15-of-24 rate; stalls stay within the P3-3c range.
- [-] **P3-3e Level matches, second attempt (the clock).** *(Deferred by the user, bot balance, 2026-11-15; see "Backlog: bots".)* *(Partly done 2026-11-15: 3v3 and 4v4 rounds are 240 s (REVIEW); level matches 5 → 1 of 32. The one stall outlier was a movement fault (a body flush against a stair's side wall never got the step-up), fixed in `MovementSystem`. Not met: House A 20 of 32 (at the limit, not under it), stalls 13–125 s against 14–88, and a new lean by seat name, team_a 23 to 8. Left: P3-3f. See PROGRESS.md.)* After P3-3d's bot fix, 5 of 32 sweep matches (3v3 + 4v4,
  seeds 1–8, as-is and swapped) still end level in regulation: 35 of 88 rounds run to the clock and 6 of those are
  drawn, with 91 % of seizures rescued. A half-sweep at `--mode.round_seconds=240` with the OLD bots gave 1 of 16
  level (reference 4 of 16) but matches up to 735 s. Run the full sweep at 240 (and 210) with the new bots:
  `node autobuild/side_sweep.mjs --sizes=3,4 --mode.round_seconds=240` (about 30 min). If it reaches at most 2 of 32
  without the match median going far past 400 s, put it in `house_3v3.tres` / `house_4v4.tres` (REVIEW); if not, log
  that level rounds are a rules question (a drawn round is replayed; the target is 7 of 8) for the user, and leave
  the numbers. *Verify:* at most 2 of 32 undecided, neither house above 15 of 24, stalls within the P3-3c range.
- [-] **P3-3f team_a wins by seat name.** *(Deferred by the user, bot balance, 2026-11-15; see "Backlog: bots".)* The sweep after P3-3e (`node autobuild/side_sweep.mjs --sizes=3,4`, 240 s rounds,
  with the step-up fix) gave team_a 23, team_b 8 by NAME (as-is 14 to 2, swapped 9 to 6) and House A 20, B 11. The same
  sweep before the step-up fix, at `--mode.round_seconds=240`, gave 17 to 15 by name and A 19, B 13; at 210, 13 to 18. So
  either the fix (`_apply_displacement`: a single-axis slide now tries `_try_step_up`) favours the lower entity ids, or it
  is one unlucky sample (about 2.7 standard deviations). Measure first: run seeds 9–16 (`--first-seed=9`) to see whether
  the lean repeats. If it does, PROJECT_MEMORY §6c-ii says where to look (seat-ordered loops: movement order, sidestep
  side, capture loop) and `tools/twin_probe.gd` finds the first tick a match and its swapped twin part. Also re-measure
  stalls per minute of match rather than per match (matches are a third longer at 240 s, and the range is 13–125 s
  against P3-3c's 14–88). *Verify:* over 32 fresh matches neither name nor house above 15 of 24; at most 2 level.
- [x] **P3-4 Exterior.** *(Done 2026-11-15: `ExteriorBuilder` (railings, timber fence, streets, neighbours, hedges, trees, gravel, paths); own sky shader with clouds that fade before the horizon, haze curve in the theme, outdoor textures mipmapped, tints and a softened brick at the right size. 22 exterior views opened. Exterior views measure 10.1–10.9 ms GPU and 255–383k triangles, over budget since the exterior went in: left to P3-6. See PROGRESS.md.)* Lot, fences, garden, trees, path, neutral strip, street, sky, sun.
- [x] **P3-5 Lighting and readability pass.** *(Done 2026-11-16: contact shadows under figures and loose bundles; emerald cash; jail cold and dim through materials; ceiling fittings drawn but room lamps OFF (+4.2 ms GPU in every indoor view because the shell is one mesh per house); oak handrails on every flight's walled side, string boards on the open sides, which have no collision and stay open. Views are over the 9 ms GPU budget as before this task (kitchen 11.5): P3-6. See PROGRESS.md.)* Lighting per room, shadow settings the Compatibility
  renderer can afford, contrast between floor/wall/characters/cash. Stair banisters (railings) on
  every flight, with collision matching the existing stair walls, checked from the stair cameras.
  *Verify:* frames at day-like exposure; cash readable at 30 m.
- [x] **P3-6 Performance pass** against the budgets from P1-1. Merge meshes/instances where needed. *(Done 2026-11-16: furniture, cash bundles and trees merged at load by `MeshMerge`; sun shadow map 2048 (REVIEW). All 61 views within draws/triangles (worst `approach_from_south` 404 / 233k, was 654 / 384k); 8 timed views at 4v4 all within GPU 9 ms and frame 12 ms (worst kitchen 8.3 / 10.7, was 11.6 / 14.0). Draws and triangles of three views gated in the full verify. See PROGRESS.md.)*

## Phase 4 — Verbs (DECISIONS.md D9; see `DESIGN_DIRECTION.md` §5)

The v1 verb set is fixed by D9. Each new verb: a sim command + system (general, never
location-gated) + tuning in `.tres` + a table-driven test for its *decisions* only + presentation +
frames + bot_match still deterministic. Crouch, jump and throw already exist in the sim; vault was
removed on purpose (do not rebuild it). No ragdoll, knockback, slide, shove or drop-from-height in v1.

- [x] **P4-1 Panic run per D9:** sim tracks how long forward is held; speed boost from content data; deterministic; bot_match still green (this means verify.mjs passes, nothing more) *(Done 2026-11-16: `forward` flag on Move, `forward_ticks` count, ×1.2 after 2 s (REVIEW); snapshot format 3; 21 table cases; contact sheet `autobuild/frames/p4_1/panic_sheet.png`. See PROGRESS.md.)*
- [x] **P4-2 Presentation for jump, crouch, carry and throw per D9** *(Done 2026-11-16: audit sheets in `autobuild/frames/p4_2/` (own body via `--pilot=carry`); landing settle dip 6 / 0.2 s (REVIEW), grab without fade-in, released bundle eased from the hands onto its arc, bodies face their drawn travel (no face in the wall on a slide); crouch-walk kept at ×4.07 (REVIEW); MeshMerge fallback fix. See PROGRESS.md.)*
- [x] **P4-3 Jail run-in-place per D9:** the jailed player's inputs drive animation and camera only, never position *(Done 2026-11-16: jailed jumps counted in the sim (`held_jumps`, snapshot format 4), never kept for release; jog / crouch / crouch-walk / a 60-high drawn hop in place from the intent, facing the keys (REVIEW); mouse still turns the camera. `autobuild/frames/p4_3/jail_sheet.png`, `jail_chase.png`. See PROGRESS.md.)*
- [x] **P4-4 Players block each other like walls** (check what the sim does now; make bodies block if they pass through) *(Done 2026-11-16: measured with table rows at the game's numbers; head-on panic runners never passed through, but a running jump went through a standing body's chest. Sideways moves now meet a body as a cylinder of its drawn height, vertical moves keep the sphere; the sidestep round a body stays; nobody is moved by a bump. A fall onto a body still rests inside it (REVIEW lead). REDO: a jailed own body is not faded. See PROGRESS.md.)*
- [ ] **P4-5 Cash tumble and bounce after a throw or drop** (cosmetic; snaps to the sim's position)
- [ ] **P4-6 Bots and panic run.** Bots may use panic run, but only so they do not break or get stuck. No tuning, no sweeps; verify.mjs is the gate.
- [ ] **P4-7 Verb readability audit by frames**

## Phase 5 — Game feel, UI, audio

- [ ] **P5-1 Menus.** A basic main menu already exists (`main_menu.gd`): audit it, then build it out —
  host/join (code field, later Steam invite), lobby screen with
  seats/teams/mode/bundles/bots, pause, settings (sensitivity, volume, keybinds), results screen.
- [ ] **P5-2 HUD.** Replace the debug text with a real HUD (cash per team, round timer, carry state,
  jail timer, rescue prompt) and a minimap (needed for DECISIONS.md D3 option b: it shows only your
  own teammates). Debug HUD stays behind F-key.
- [ ] **P5-3 Audio.** CC0 SFX and a music loop (Kenney, freesound CC0, OpenGameArt CC0): ordinary
  household sounds — footsteps, doors, grab, caught, free, cash, alarm-ish sting, UI. No cartoon
  sounds (D2). Audio buses, volume settings.
- [ ] **P5-4 Deadpan feedback: plain, physical, short. No confetti or cartoon effects.** (D2.)
  Cheap in the Compatibility renderer.
- [ ] **P5-5 First-run clarity.** Controls hints and a 60-second guided first match so a friend can
  join without a lecture.

## Phase 6 — Networking and Steam

- [ ] **P6-1 Loss and lag.** Add latency/packet-loss options to the loopback transport; confirm
  prediction/rollback/snapshots hold at 100 ms + 5% loss; fix defects.
- [ ] **P6-2 Host modes.** Confirm what exists (player-hosted listen mode vs dedicated headless) and
  document in `godot/ARCHITECTURE.md`. Implement a headless dedicated host only if it is small.
- [ ] **P6-3 Steam transport** behind the existing session/transport interface using GodotSteam
  (dev with Steam test app id 480). Works with two local instances where possible.
  Needs the user's Steamworks app for the real id → write BLOCKED.md for that part only.
- [ ] **P6-4 Invite/join flow** through Steam lobbies, keeping the room-code path for Tailscale/LAN.

## Phase 7 — Release candidate

- [ ] **P7-1 Export.** Windows export preset, a `autobuild/build.mjs` that produces `build/CashGrab.exe`;
  needs export templates installed (write BLOCKED.md if missing; do not download 800 MB unprompted — ask in the report).
- [ ] **P7-2 Quality settings and performance** on the dev machine (windowed, real GPU): record FPS in `PLAYTEST.md`.
- [ ] **P7-3 Docs.** Update `README.md`, `PLAYTEST.md`, credits screen from `CREDITS.md`, a store-page asset checklist.
- [ ] **P7-4 Release sweep.** Full `verify.mjs --frames` over every room, final PROGRESS entry, tag `v0.1.0-rc1`.

## Backlog — do NOT start unless every task above is done

Proximity voice chat · clip export (seed + input log) · lag compensation · defender prep phase
(traps/locks) · loot variety (TV needing two people, piggy bank) · more maps · cosmetics/progression ·
decoy mannequins/figures placed in the house (must be subtle, not obvious; try after v1).

## Backlog: bots — revisit only when the user reports a problem

Paused by the user on 2026-11-15 (DECISIONS.md log): finish Phases 3 to 5 first. Open items, with
the measurements and leads in P3-3d, P3-3e and P3-3f above and in PROGRESS.md:

- **Level matches.** Matches that end level in regulation: 1 of 32 at 240 s rounds after P3-3e
  (5 of 32 before), with many rounds running to the clock.
- **team_a winning by seat name**: 23 of 32 (team_b 8) in the sweep after P3-3e.
- **House A winning 20 of 32** (House B 11) in the same sweep.

A stash on this machine holds session 7's unfinished P3-3f sweep statistics (`git stash list`:
"session 7 leftovers").
