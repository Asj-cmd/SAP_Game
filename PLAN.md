# Cash Grab — autonomous build plan

**Goal:** a polished, playable, deployable multiplayer version 1 of Cash Grab in Godot 4.7
(Compatibility renderer): toon-shaded 3D world and characters from free/CC0 and AI-generated
assets, the full verb set, menus and audio, Steam-ready networking, a Windows build.

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
  drop-from-height are not built.**
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
- [x] **P0-3 Bot stalls and a finishing match.** Already true at the start of the autobuild (stalls 42 s,
  winner `team_a`). `metrics_budget.json` pins it: stalls ≤ 42, a winner is required. Do not regress.
- [ ] **P0-4 Clean frames.** Add a capture option that hides the debug HUD (e.g. `--capture-clean`),
  and make the debug HUD hidden by default behind an F-key. Update `verify.mjs --frames` to use it.
  *Verify:* a frame with no text.
- [ ] **P0-5 Visible world.** Replace the black void: sky/background, ground plane beyond the lots,
  basic environment lighting and exposure. *Verify:* frames from `views.json` show horizon, no black voids.
- [ ] **P0-6 Camera everywhere.** Third-person camera must give a usable view in every space:
  basement/jail, upstairs, stairwells, vault, garden, doorways. Walls between camera and player
  must not blind the player (fade or cut away). Add one `views.json` entry per space.
  *Verify:* ≥12 frames, each judged readable; camera_controls_test still green.
- [ ] **P0-7 "Patchy graphics" sweep.** Capture every room, both houses, both floors. Log every
  defect (z-fighting, floor tint over stairwell, gaps, flipped normals, wrong colour, clipping),
  fix them, re-capture. *Verify:* before/after frame names in PROGRESS.md; validator still green.
- [ ] **P0-8 Playable local session.** One human + bots: start from the main scene, move, grab,
  drop, seize, free, score, win a round and a match, return to start. Fix whatever breaks.
  Use the capture tool's injected-input options and `bot_match --lone` to exercise it. Include the
  main menu → host/join → lobby → match → F10 back-to-menu path, and test jump, crouch and throw by eye.
  *Verify:* written walkthrough in PROGRESS.md with frames at each step.
- [ ] **P0-9 Network smoke.** `tools/net_loopback.gd` and `tools/net_lobby.gd` pass; two local
  Godot processes (host + join on localhost) complete a lobby and a short match. Add the
  headless variant to `verify.mjs` if it is stable. *Verify:* log excerpt in PROGRESS.md.
- [ ] **P0-10 Housekeeping.** Root `CLAUDE.md` still says the Three.js branch is the source of
  truth: point it at the Godot project, mark `client/` and `server/` legacy. Do not delete them.

## Phase 1 — Art foundation (style, shader, asset pipeline)

- [ ] **P1-1 Render stats tool.** `godot/tools/render_stats.gd`: print draw calls, triangles,
  objects in view for a given view. Propose budgets for the Compatibility renderer on a GT 730M-class
  GPU, record them in `STYLE.md`. Frame time is measured only when running windowed on the
  dev machine; software-rendered frame time is meaningless.
- [ ] **P1-2 Asset ledger.** Create `ASSETS.md` (name · source URL · license · date · modified?) and
  `CREDITS.md`. Allowed: CC0, CC-BY (credit it), assets the user bought, assets generated by
  services whose terms allow commercial use (record the terms). Never: NC/ND licences, ripped game
  assets, anything unclear. No money is spent without the user (see DECISIONS.md).
- [ ] **P1-3 STYLE.md.** Art direction from the brief: chaotic cartoon domestic comedy, saturated
  readable palette (≤12 base colours + 2 team colours), chunky shapes, big expressive heads,
  outlines, flat/ramped lighting. If the user left images in `autobuild/references/`, derive from
  them and cite which. Define proportions, outline width, palette hexes, what "polished" means.
- [ ] **P1-4 ArtTheme + toon shader.** One `ArtTheme` Resource (palette, toon ramp, outline width,
  rim light) and one toon spatial shader with an inverted-hull outline pass that works in the
  Compatibility renderer. Every imported mesh gets its material replaced from the theme so mixed
  sources look like one game. Changing the look later = editing the theme. *Verify:* frames.
- [ ] **P1-5 Style slice.** Build **three** variants (A/B/C) of the same room (use the vault room)
  with one placeholder character, different theme settings, captured from 4 views each into
  `autobuild/slice/`. Pick the recommended variant, write the reasoning in DECISIONS.md under
  `STYLE-PICK`. **Do not wait for the user** — adopt your pick and continue; the user may override
  and the theme makes that cheap.
- [ ] **P1-6 Asset import pipeline.** A documented, repeatable path from a downloaded `.glb`/`.fbx`
  to `godot/art/…`: **scale to world units (1 unit = 1 cm, so most downloaded assets, authored in
  metres, need ×100)**, Y-up, pivot, theme material, LOD/poly check against the budget. Keep the
  `ResourceLoader.exists` + primitive fallback convention from `godot/art/README.md`.
  Art meshes never carry collision; the blockout/collision data stays the source of truth.

## Phase 2 — Characters and animation

- [ ] **P2-1 Source four family characters** (dad, mom, son, daughter). First audit what exists:
  `godot/art/blender/build_character.py` produced `character_a.glb` / `character_b.glb` (blocky
  voxel people) — decide whether they are team skins or family members, and whether to keep, restyle
  or replace them; log it as D3-REVIEW. Preferred route for new ones: AI generation
  (Meshy tools, if signed in) with prompts from `STYLE.md`, several candidates each, pick the best.
  **Fallback, no waiting:** CC0 humanoids (Quaternius, KayKit) recoloured with silly additions
  (hats, glasses, moustache, pyjamas). If sign-in/credits are missing, write BLOCKED.md and take the fallback.
- [ ] **P2-2 One skeleton, one animation set.** Retarget everything to a shared skeleton. Needed:
  idle, walk, run, crouch-walk, grab, carry-walk, caught/jailed, free-ally, stumble, fall/ragdoll
  start, get-up. Source: CC0 animation libraries (Quaternius etc.); Mixamo only if the user has signed in.
- [ ] **P2-3 Animation driver.** AnimationTree/state machine driven from simulation state
  (read-only; presentation never mutates the sim). *Verify:* frames/gif-like contact sheets per state.
- [ ] **P2-4 Team readability.** Decide per DECISIONS.md D3 how teams are told apart at distance and
  implement it (outfit accent colour + outline tint + HUD marker). *Verify:* frames from 20 m, 40 m.
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

## Phase 4 — Verbs and chaos (see `DESIGN_DIRECTION.md` §5)

Each new verb: a sim command + system (general, never location-gated) + tuning in `.tres` + a
table-driven test for its *decisions* only + presentation + frames + bot_match still deterministic.
Crouch, jump and throw already exist in the sim; vault was removed on purpose (do not rebuild it).

- [ ] **P4-1 Crouch, jump, throw — presentation.** Crouch is drawn; jump and throw "look like nothing
  in particular". Add animation/pose, dust/landing, throw arc preview and cash spin; sounds come in P5-3.
- [ ] **P4-2 Verb readability audit.** Play all three by eye (frames), fix anything that reads wrong
  (the camera, floating/sinking, throw feel), per the "low precision, high consequence" rule.
- [ ] **P4-4 Slide.** Fast, loud, low; interacts with crouch gaps and knockback.
- [ ] **P4-5 Drop from height.** One-way, instant (the escape windows already exist as one-way drops).
- [ ] **P4-6 Cosmetic ragdoll and knockback.** Client-side only. The sim stays authoritative; physics
  never becomes the source of truth (`DESIGN_DIRECTION.md` §7.4).
- [ ] **P4-7 Dropped cash tumbles** to its canonical position, then snaps to the sim's value.
- [ ] **P4-8 Bots use the new verbs** at a basic level, without degrading `bot_match` metrics.

## Phase 5 — Game feel, UI, audio

- [ ] **P5-1 Menus.** A basic main menu already exists (`main_menu.gd`): audit it, then build it out —
  host/join (code field, later Steam invite), lobby screen with
  seats/teams/mode/bundles/bots, pause, settings (sensitivity, volume, keybinds), results screen.
- [ ] **P5-2 HUD.** Replace the debug text with a real HUD (cash per team, round timer, carry state,
  jail timer, rescue prompt). Debug HUD stays behind F-key.
- [ ] **P5-3 Audio.** CC0 SFX and a music loop (Kenney, freesound CC0, OpenGameArt CC0): footsteps,
  doors, grab, caught, free, cash, alarm-ish sting, UI. Domestic comedy tone. Audio buses, volume settings.
- [ ] **P5-4 VFX and juice.** Catch pop, cash confetti, dust on slide, camera shake, funny failure
  states ("failure should be funnier than success"). Cheap in the Compatibility renderer.
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
(traps/locks) · loot variety (TV needing two people, piggy bank) · more maps · cosmetics/progression.
