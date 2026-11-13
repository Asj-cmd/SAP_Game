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

- [ ] **P2-1 The family of four** from the Quaternius Universal Base Characters per DECISIONS.md D10:
  dad, mom, elder child, younger child (Regular male/female = dad/mom, Teen male/female = the kids).
  They differ in size and shape only, and all have blank faces per D2: remove eyes, hair and facial
  detail, smooth plastic-like material, slightly off proportions; decimate to the `STYLE.md` budget.
  Make both children available as a girl and a boy so D3 option (d) (kid swap) works. Unzip from
  `autobuild/incoming/` (keep the zips out of git), record in ASSETS.md. The old blocky
  `character_a/b.glb` stay in place until the new figures load (art stays optional via fallback).
- [ ] **P2-2 One skeleton, one animation set** from the Quaternius Universal Animation Library per
  D10 (same rig as the base characters). Needed: walk, panic-run with arms up, idle (completely
  still), jump and land, crouch-walk, carry-overhead walk and run, throw, jail run-in-place, free
  ally. Procedural wobble allowed but subtle. No ragdoll, stumble or get-up (D9).
- [ ] **P2-3 Animation driver.** AnimationTree/state machine driven from simulation state
  (read-only; presentation never mutates the sim). *Verify:* frames/gif-like contact sheets per state.
- [ ] **P2-4 Team tell (D3 experiment).** Implement the data-driven team-tell setting from
  DECISIONS.md D3 with all four options, combinable and switchable at runtime (lobby/settings and a
  debug key, no code change): (a) marker over your own teammates only, never over enemies;
  (b) minimap showing only your teammates (build a minimal minimap here; P5-2 makes it final);
  (c) both families identical except one small detail such as a wristband colour; (d) kid swap.
  Pick a default and log it as REVIEW. *Verify:* frames of each option, from 20 m and 40 m.
- [ ] **P2-5 Turnaround sheet.** One capture per character from 4 angles in `autobuild/slice/`.

## Phase 3 — The house and the lot

- [ ] **P3-1 Kit selection.** Choose wall/door/window/floor/roof/stair/furniture packs (Kenney,
  Quaternius, KayKit, others CC0). Log in ASSETS.md. Prefer one or two coherent packs over many.
- [ ] **P3-2 Shell dressing.** Visual shell from the existing blockout data (`godot/game/blockout`,
  `HOUSE_LAYOUT`/`WORLD_AUTHORING`): walls, floors, doors, windows, stairs, roof with reveal. Collision
  and zones unchanged. *Verify:* content validator + all tests green; frames of every room.
- [ ] **P3-3 Interiors.** Furnish every room. Obey `WORLD_AUTHORING.md` §12 thresholds: anything the
  rules let you climb must *look* climbable, anything that blocks must *look* tall. Distinct
  silhouettes for vault, cash bundle, jail/basement door, safe room.
- [ ] **P3-4 Exterior.** Lot, fences, garden, trees, path, neutral strip, street, sky, sun.
- [ ] **P3-5 Lighting and readability pass.** Lighting per room, shadow settings the Compatibility
  renderer can afford, contrast between floor/wall/characters/cash. *Verify:* frames at day-like
  exposure; cash readable at 30 m.
- [ ] **P3-6 Performance pass** against the budgets from P1-1. Merge meshes/instances where needed.

## Phase 4 — Verbs (DECISIONS.md D9; see `DESIGN_DIRECTION.md` §5)

The v1 verb set is fixed by D9. Each new verb: a sim command + system (general, never
location-gated) + tuning in `.tres` + a table-driven test for its *decisions* only + presentation +
frames + bot_match still deterministic. Crouch, jump and throw already exist in the sim; vault was
removed on purpose (do not rebuild it). No ragdoll, knockback, slide, shove or drop-from-height in v1.

- [ ] **P4-1 Panic run per D9:** sim tracks how long forward is held; speed boost from content data; deterministic; bot_match still green
- [ ] **P4-2 Presentation for jump, crouch, carry and throw per D9**
- [ ] **P4-3 Jail run-in-place per D9:** the jailed player's inputs drive animation and camera only, never position
- [ ] **P4-4 Players block each other like walls** (check what the sim does now; make bodies block if they pass through)
- [ ] **P4-5 Cash tumble and bounce after a throw or drop** (cosmetic; snaps to the sim's position)
- [ ] **P4-6 Bots use panic run sensibly**
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
