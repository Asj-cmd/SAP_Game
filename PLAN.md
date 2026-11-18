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

## Playtests 3 and 4 (user, 2026-11-18): do these first, in this order

Written after the user's third and fourth playtests. Order: PT4-1, PT3-1, PT3-2, PT3-3, PT4-2, PT4-3,
PT4-4, PT4-5, PT4-6, PT4-7, then the two open Playtest 2 tasks (PT2-7, PT2-8) further down, then
PT4-8 (last, below PT2-8). Planner and workers are Opus; no task is tagged with a worker model.
**Each task is checked as written: never tick a task the user would still see broken** (PT2-1 was
ticked and the user still sees the gap: PT4-1 is the redo). Frames: only PT4-1, PT4-6 and PT4-7
(and PT2-7, PT2-8) may capture them, one set at the end and at most one redo (`PROMPT.md`); every
other task here is checked by tests and numbers, with the full `verify.mjs` once at the end. PT3-3
changes the rule from P5-0 that the family display names come only from
`godot/content/family_names.cfg`: the file now holds only the defaults, and the names a match shows
are typed by the players (see PT3-3).

- [x] **PT4-1 Stair gap, for real.** *(Done 2026-11-18: PT2-1's fix never reached the baked `content/levels/house.tres` the game loads; re-baked. The open-flank slot beside each top tread is drawn closed (`ShellBuilder._top_cap`). Measured drawn gap 0 on all six flights; six frames from the landings in `autobuild/frames/pt4_1_*.png` show no gap. See PROGRESS.md.)* PT2-1 was ticked, but the user still sees a gap between the top
  tread and the upper floor, with the green lawn visible through it. Fix **every flight in both
  houses**, including the outside back stairs (list them first: the inside flights, the back stairs,
  anything else that reaches the upper floor). Find why PT2-1's fix did not reach what the user sees
  (the visible shell mesh, the floor slab, the stair mesh, the merged mesh, the string board or tread
  nosing may each end at a different place from the collision and nav it measured) and fix what is
  DRAWN as well as what is collided with. Collision and nav must still agree with the drawing, and the
  symmetry probe passes. **Done only when one frame per flight, taken from the top looking down at
  the top tread (a camera that stands on the landing), shows no gap and no light through it.** Open
  each frame with the Read tool and say in `PROGRESS.md` what it actually shows; if any shows a gap,
  fix it and redo once. **Frames allowed: one set (every flight in both houses), at most one redo.**

- [x] **PT3-1 Music only outside matches, and a quirky track.** *(Done 2026-11-18: `GameAudio.music_wanted` (menu, lobby, results) read each frame from what is open, 1 s fades, paused under a match; menu track "Trouble in the Garden" (HaelDB, CC0) in `content/music/menu.ogg`, two more CC0 candidates and the old jazz in `content/music/candidates/` (not exported). Unheard: REVIEW. See PROGRESS.md.)* Background music plays in the main
  menu, the lobby and the results panel only. It fades out (about 1 s) when a match starts and fades
  back in when the results panel appears (after PT2-7's end sequence and jingle, once that exists; the
  win or lose jingle stays and plays over the fade). Nothing plays under the match itself (the
  Music slider from PT2-3 still controls the volume). Replace the current jazz loop (Alex McCulloch,
  OpenGameArt; the user says it sounds like phone hold music and irritates them). Pick quirky,
  sneaky, cartoon-heist music (pizzicato, light percussion, playful), free to use commercially:
  **CC0 first; CC-BY only if credited in `CREDITS.md`**; no other licence, no meme clips. Download
  three candidates into `godot/content/music/candidates/` (each short or trimmed; if one is big,
  keep it out of git with a `.gitignore` line, and the export must not include the `candidates`
  folder), listen is not possible, so choose by title, description, tempo, loop length and how the
  source describes it, and say in `PROGRESS.md` which you picked and why. Use the best as
  `godot/content/music/menu.ogg` (loops cleanly, not annoyingly short or fast). Write in
  `HOW_TO_PLAY.md` how to swap one in by renaming (which file, which format, rebuild the exe). Log
  all three candidates in `ASSETS.md` (the unused ones marked "candidate, not shipped") and the one
  used in `CREDITS.md`, each with author, licence, URL and the licence proof. Remove the old jazz
  file and its credits row only if nothing else uses them (the user said never delete: move it
  to `godot/content/music/candidates/` instead). Test: table-driven check of when music is wanted
  (menu, lobby, results yes; match no) so the rule cannot drift. No frames.
- [x] **PT3-2 Cash sounds are paper.** *(Done 2026-11-18: Kenney RPG Audio (CC0) page flutters for grab, book thuds for banked cash, `drop` (leather bag) and `bundle_land` (book thud) events from the confirmed world; old coin/cloth files in `art/audio/sfx/retired/`. Unheard: REVIEW. See PROGRESS.md.)* Grabbing and dropping a bundle currently sounds like a gun
  being loaded. Replace the **grab** with a paper rustle or a quick banknote flutter, and the
  **drop and the landing** with a soft paper-bundle thud. CC0 only (Kenney, OpenGameArt CC0,
  freesound CC0 downloadable without an account, or similar); logged in `ASSETS.md` and `CREDITS.md`
  with proof of the licence. **Nothing metallic or click-like**: reject any candidate whose title or
  description says click, latch, snap, cock, reload or metal; prefer "paper", "page turn", "flutter",
  "cloth", "thud", "bag drop". Short (under about 0.6 s), trimmed, normalised to match the other
  effects; they play on the Effects bus (PT2-3). Keep the event names and the one file per event the
  audio table already uses, so swapping is a file change. Say in `HOW_TO_PLAY.md` which files they
  are. Move the replaced files to a `retired` folder next to them rather than deleting. No frames.
- [x] **PT3-3 Players name their families.** *(Done 2026-11-18: `FamilyNames` typed store + `clean` (one rule, in `LobbyState.clean_name`), shown as "<Name> Family", defaults "Green Family" / "Orange Family" in the cfg; lobby name boxes for host and (new) guest lobby panel, solo boxes on the menu; `MatchChannel.TAG_LOBBY` (host is the truth). Old names gone from tracked files. Not tried by two people. See PROGRESS.md.)* Remove the two old fixed family names everywhere (code,
  scenes, tests, docs, `family_names.cfg`, `HOW_TO_PLAY.md`, `PLAYTEST.md`, credits): nothing may
  contain them as text any more. Instead:
  1. **Lobby.** Each family has a name box. Any player seated on that family can type its surname;
     the host sees both boxes and can clear either with a Clear button. Rules, enforced where the
     text is entered AND where it is received: at most 16 characters, only letters, spaces, hyphens
     and apostrophes (strip anything else, trim ends, collapse runs of spaces). One small shared
     function does the cleaning (`FamilyNames.clean`, table-driven test: empty, 16 vs 17 characters,
     digits, symbols, emoji, accents, only spaces, hyphen and apostrophe kept).
  2. **Network.** The names travel in the lobby / session state to all players, as part of the
     existing lobby message (not the sim snapshot, not the match input stream); a joining or
     reconnecting player receives the current names; a change by a team-mate or the host reaches
     everyone within a second. A late or malformed message is cleaned and ignored if invalid; the
     host's copy is the truth (last typed wins). Keep the net smoke test green and add a table case
     for the new message.
  3. **Shown everywhere**: the cash bar, results, status line, the match-end titles from PT2-7
     (PT2-7 must use these names), round messages, minimap and team-tell labels, the debug HUD.
  4. **Solo games.** A name box for each family on the solo setup screen (above Play solo, next to
     the team-size picker).
  5. **Defaults when a name is empty**: "Green Family" and "Orange Family" (after the family
     colours; the first family is the green one, the second the rust orange one). The defaults live
     in `godot/content/family_names.cfg`, which keeps its two lines (`team_a_name=`, `team_b_name=`)
     and now holds ONLY these two defaults; the loader's own fallback if the file is missing is the
     same two words. Internal ids stay `team_a` / `team_b`.
  6. Update `HOW_TO_PLAY.md` (the "Changing the family names" section now explains the lobby boxes
     and the defaults file) and `PLAYTEST.md`. Delete the "custom family names" item from the
     backlog if it exists (none is listed at the moment: say so in `PROGRESS.md`). Log the changed
     rule against P5-0 in `DECISIONS.md`.
  *Verify:* the table-driven tests above, a search showing neither old name appears anywhere in the
  repo's tracked files, then the full `verify.mjs`. No frames.
- [x] **PT4-2 Family spawn.** *(Done 2026-11-18: one row per family on its own front lawn, house-local x 300..1050 at z -150, re-baked; 3 s countdown in every mode (REVIEW); `FamilyLineup` camera 600 out from the row during COUNTDOWN, bodies drawn facing it, family name above and role / "You" / "Bot" / player under each body. Spawn table in `greybox_level_test`. Not looked at (no frames, per the diet). See PROGRESS.md.)* At round start each family spawns **together in a lineup in front of
  its own house** (or in its ground-floor hall if that plays better: pick one, say why in
  `DECISIONS.md`), facing the camera for about 3 s while its member names show, then play starts.
  Deterministic in the sim and mirrored for both houses (the symmetry probe still passes). If the
  round start already has a frozen countdown, reuse it; no new rule beyond "everyone holds still and
  faces the lineup camera until play starts". The names shown are each member's role (Dad, Mom, Son,
  Daughter, with elder / younger where that applies) and who plays it: the player's name or "Bot"
  (PT3-3's family names above the lineup). The 3 s lineup is a presentation phase on top of the
  sim's own start, so snapshot and network changes are only what the spawn positions need. Table-
  driven test: spawn positions per team size (2v2, 3v3, 4v4), mirrored, no overlap with walls or
  each other, same result on every run. No frames.
- [x] **PT4-3 Choose your family member.** *(Done 2026-11-18: a member is a lobby seat slot; `Lobby.choose` / `resolve_random` (host's own RNG at Start) / `begin`; `LobbyState` version 2 carries seats, requests and a refusal notice; a moved player gets a fresh TAG_SEAT; "Play as" on the main menu (solo) and in the lobby under the own family's name box; lineup labels read player names on guests. `lobby_test` 57 -> 99. Headless host + two guests checked; not tried by two people. See PROGRESS.md.)* The solo setup screen lets the player pick Dad, Mom, Son,
  Daughter or "Random" (default Random); today the user always gets the dad. Online, each player
  picks in the lobby, next to their family's name box (PT3-3); no duplicates within a family; the
  host's copy of the choices is the truth (a second player picking a taken member is refused and sees
  why); bots take what is left; Random by default and Random never takes a member another player has
  picked. Offer only the members that exist at the chosen team size. The choice travels in the lobby
  message (as PT3-3's names do), not in the match input stream, and a rejoining player keeps their
  member (as the playtest guide already promises). Table-driven test: duplicates, Random, every
  team size, rejoin. No frames.
- [x] **PT4-4 HUD fixes.** *(Done 2026-11-18: the bar's code was right; at 0 v 6 it is all terracotta and "0 / 6" is banked-of-target, which read as broken. Colours only via `MatchHud.bar_layout` (theme), names in family colours, banked counts + "FIRST TO N"; minimap = `MinimapOutline` (lot, yards, houses, fence with gates), drawn only in a match; F1 hint only in debug builds. No frames. See PROGRESS.md.)* From the user's screenshots: (1) the cash bar shows the same terracotta
  on both sides and stays centred at 0 against 6. It must be the **first family's colour from the
  left** and the **second family's colour from the right**, and the split must follow each family's
  share of banked cash (0 against 0 is centred; 0 against 6 is all one side). Check with a
  table-driven test of the split and of the two colours (read from the theme, not typed in). (2) The
  minimap is an empty dark box with grey squares, and it also shows on the main menu behind the
  panel. Make it a readable top-down outline of both lots and both houses (walls, the fence line,
  the gate), drawn from the level data, shown **only in a match** (never on the menu, lobby or
  results). (3) Hide the "[F1] debug HUD" label unless the game is a debug/dev build
  (`OS.is_debug_build()`); the exe is a release build, so friends do not see it. No frames: check by
  tests and by what the code draws.
- [x] **PT4-5 Minimap pointers per member.** *(Done 2026-11-18: `TeamTellOverlay.pointer` (square / diamond / triangle / circle, notch or apex the drawn facing, own 6.5 px with a cream outline), both families drawn (`MAP_SHOWS_ENEMIES`, REVIEW); member from `member_for` with kid swap, heading from the drawn yaw; `match_status_test` 15 -> 63. No frames. See PROGRESS.md.)* Each figure on the minimap is a shape in its family
  colour: **dad square, mom diamond, son triangle, daughter circle** (elder and younger boys / girls
  keep the son and daughter shapes), each pointing the way it faces (a short pointer or notch;
  triangle points itself). The player's own one is outlined and slightly bigger. Bots and players
  alike. Presentation only. Table-driven test of the shape and size per member and that facing is
  read from the figure's heading. No frames.
- [x] **PT4-6 Hands and arms.** *(Done 2026-11-18: shorter forearms (along their length) and smaller hands per member through theme `bone_scales`; fingertips now end at mid-thigh, hands 0.105–0.114 of height; the carried bundle stays above the head for adults and elder kids. Lineup and dad-carry frames in `autobuild/frames/pt4_6/`. Measured with `tools/arm_probe.gd`. See PROGRESS.md.)* The dad's palms look too big and his arms too long; check all six
  members (both families' figures, elder and younger variants where they exist). Scale hands and
  forearms so they look normal next to the bodies, keeping the carry and throw poses working (the
  IK arm poses from P2-2 must still reach and hold a bundle overhead; check by the numbers the
  anim tests already give). Presentation only; no collision or sim change. **Frames allowed: one
  lineup of all members (plus one close shot of dad carrying) at the end, at most one redo.**
- [ ] **PT4-7 Menu and HUD polish.** Move the team-tell checkboxes from the main menu to Settings.
  Hide the host address behind a small "Advanced" toggle (Host just works; the address and the
  Tailscale note appear only when Advanced is open). Clear the fog / wash from the menu backdrop so
  the houses look crisp. Give buttons and cards one consistent finish (shadow, hover, press) through
  the shared `UiTheme`, not per screen. Tidy the results card. Keep the deadpan tone and the
  P5-0 / PT3-3 name rules. **Frames allowed: one set of every screen (menu, settings, pause, lobby,
  HUD, results) at the end, at most one redo.**

## Playtest 2 (user, 2026-11-17): do these eight first, in this order

Written after the user's second playtest of the exe. They come before everything else, so the loop
takes them first. Planner and workers are Opus (Fable needs paid usage credits): no task here is
tagged with a worker model. Milestone is still a friends playtest: a working, simple version beats a
polished one, except where the task is about looks (PT2-5, PT2-6, PT2-8). Frames: only PT2-5, PT2-6,
PT2-7 and PT2-8 may capture frames (one set at the end, at most one redo; see `PROMPT.md`). Every
other task here is verified by tests and numbers. The family display names come only from
`godot/content/family_names.cfg` (never write them as fixed text).

- [x] **PT2-1 Stair gap.** *(Done 2026-11-17: the stairwell hole was grown 20 past the top tread; now it ends at the tread. Back stair measured, no gap. See PROGRESS.md.)* In both houses the upper floor stops short of the top stair tread (user's
  screenshot: a visible gap between the last step and the upstairs floor). The staircase position is
  right; extend the upper floor / landing (shell, collision and nav) so it meets the top tread. Check
  every flight, including the new outside back stairs. The symmetry probe passes; the full
  `verify.mjs` is the gate. No frames.
- [x] **PT2-2 Remove the panic run; add a "spotted" startle.** *(Done 2026-11-17: panic run gone from sim, wire, snapshot (format 5), clips and tests; spotted jolt + pitched sting in `GreyBoxMain._spot_carriers`, 6 m, 8 s cooldown (REVIEW). Unseen. See PROGRESS.md.)* Delete the arms-up panic run: the sim
  state (`is_panicking`, the forward-held tracking if nothing else uses it), the animation, the bot
  code that deals with it, and the tests that pinned it. Replace it with a "spotted" moment: the first
  time a defender comes within the old panic distance of a player who is carrying that defender's
  family's cash, the carrier plays a one-shot stiff startle jolt (about 0.5 s; presentation only, no
  speed change, never in the sim's decisions) and an alarm sting plays for both players. Add a
  cooldown so it does not repeat constantly (log the value in `DECISIONS.md` as REVIEW). Keep the 1.08x
  home-side defender speed boost. Update D9 (the panic run row becomes the spotted startle; keep the
  home-side speed row). If the removal changes the snapshot, bump the format and keep the net smoke
  test green. No frames. (The alarm sting needs a sound: use a placeholder from the PT2-4 pool or a
  short generated tone, and log it in `ASSETS.md`.)
- [x] **PT2-3 Audio settings.** *(Done 2026-11-17: `Footsteps` bus + slider (default 0.4, 0 = off), Music / Effects / Footsteps saved under `[audio]`, per-event bus in `GameAudio.EVENTS`; `player_settings_test` 35 checks. See PROGRESS.md.)* Separate **Music**, **Effects** and **Footsteps** volume sliders in
  Settings, saved with the other settings. Footsteps default to 40 percent and can be turned off
  (slider at 0). Route each kind of sound to its own audio bus so the sliders work for every sound
  that exists now and for the ones PT2-4 adds. Table-driven test for the saved values. No frames.
- [x] **PT2-4 Music and stings.** *(Done 2026-11-17: CC0 jazz loop (Alex McCulloch, OpenGameArt), Kenney pizzicato win/lose jingles at MATCH_END for the local family, a CC0 boing in `content/sfx/jailed.ogg` at the seize; HOW_TO_PLAY, ASSETS, CREDITS. Nothing heard (headless). See PROGRESS.md.)* One CC0 background music loop (Kenney, OpenGameArt CC0 or similar;
  calm, slightly silly, not looping annoyingly fast), a short win jingle, a short lose jingle and a
  jail sound. The jail sound is a CC0 cartoon "boink" for now, loaded from the one file
  `godot/content/sfx/jailed.ogg` so the user can replace it with their own recording later; say in
  `HOW_TO_PLAY.md` how to swap it (which file, which format, rebuild the exe). Do not use any meme
  clip. Log every file in `ASSETS.md` and `CREDITS.md` (name, author, licence, URL), with the CC0
  proof next to it as for the other assets. The export must include the sfx folder. No frames.
- [x] **PT2-5 Bring back the realistic house.** *(Done 2026-11-18: nothing had been lost; what looked flat was never textured. Carpets, rugs, upholstery, ceiling, jail concrete and path now textured; furniture wood and worktops world-triplanar; walls shade darker toward the floor. Frames in `autobuild/frames/pt2_5/`. See PROGRESS.md.)* The user says the house looked more realistic and
  polished before; now it looks as flat and cartoony as the figures. The intended contrast is a
  realistic house with silly figures (D2). Compare an older commit's frames (around P3-2 / P3-3) with
  today's (a git worktree at the old commit is fine; do not touch the working tree). Find what
  flattened it (texture loss in the P3-6 mesh merge, lighting and shadow changes in P3-5, material or
  quality-preset changes, the P7-2 presets) and restore textures, materials and lighting on the
  **High** preset while staying inside the P1-1 budgets (the draws, triangles and GPU numbers the
  full verify gates). Log what you found in `DECISIONS.md`. **Frames allowed: one before/after set at
  the end, at most one redo.**
- [x] **PT2-6 UI art pass.** *(Done 2026-11-18: `UiTheme` (Anton + Inter, cream cards, charcoal buttons, mustard hover); menu with a tilted sign title over a camera circling the two houses; restyled settings, pause, lobby, results, HUD (framed tug-of-war bar, names, counts, banknotes, clock plate, icons); "<NAME> WIN". Frames in `autobuild/frames/pt2_6/`. See PROGRESS.md.)* The main menu, settings, pause, lobby, HUD and results screens look
  bland, like a web page or an .io game. Make them look like a polished commercial game: one shared
  Godot Theme; a real display font plus a readable body font (OFL or CC0, logged in `ASSETS.md` and
  `CREDITS.md`); styled panels and buttons with hover and press states and small animations; a title
  logo on the main menu over a live or rendered view of the two houses; icons in the HUD; a proper
  tug-of-war cash bar with the family colours, names and counts; a clear round timer. Keep the
  deadpan tone, no confetti. Fix "<OLD DEFAULT NAME> WINS": the result line is plural, so "WIN" (the family
  display names come from `family_names.cfg`; build the line so it never says "WINS" after a family
  name). Keeps the P5-0 rules (names only from the `.cfg`). **Frames allowed: one set of every screen
  at the end, at most one redo.**
- [ ] **PT2-7 Match end sequence.** An end-of-match sequence of about 4 to 6 s before the results
  panel: the camera circles the winning family doing a stiff deadpan victory pose holding cash, the
  losers stand blank; a big original title such as "THE <WINNERS> GOT RICH." in the winners' view and
  "THE <LOSERS> GOT ROBBED." in the losers' view (the exact lines live in ONE content file, with the
  family name filled in at run time: **the names the players typed in the lobby (PT3-3)**, or the
  defaults from `family_names.cfg` when a box was left empty; build the line so a name ending in "s"
  or not still reads right); the win or lose jingle from PT2-4. Skippable with any key. Presentation
  only: the sim and the network messages do not change (PT3-3's names are already on every
  machine). The results panel follows the sequence, and PT3-1's music comes back in then.
  **Frames allowed: one set at the end, at most one redo.**
- [ ] **PT2-8 Funnier hair.** The son's mohawk is clearly bigger. The daughter gets two shabby, uneven
  pigtails. Mom gets a tall stiff beehive or a curly perm (the planner picks the funnier one and says
  which in the brief). Dad is unchanged. Same in both families, elder and younger variants following
  the same idea (P2-6 rules: plain painted solid shapes in the figure material, colours in the
  theme). **Frames allowed: one lineup at the end, at most one redo.**
- [ ] **PT4-8 Bots catch thieves (last).** The user easily catches bots running off with cash, but
  bot defenders cannot catch the user, and bots carrying cash home ignore an opponent who runs into
  them on their own side. Fix: defenders prioritise (1) any opponent carrying their family's cash and
  (2) any opponent close by on their side, **including while the bot itself is carrying** (it drops
  the cash to seize if that is better), with a pursuit that **cuts the thief off** (aims at where the
  thief will be, toward the thief's way home or the nearest gate) rather than trailing behind. Goal:
  a bot defender catches a fleeing human about as often as the human catches a bot. Check with two or
  three short **staged chase scenarios** (a bot defender against a human-like runner with cash; a
  carrying bot meeting an intruder on its own side) in `bot_match` or one table-driven test, with the
  catch counts written in `PROGRESS.md`, plus the full `verify.mjs`. **No sweeps, no seed sweeps, no
  balance tuning beyond this**: this is the only bot task the user wants now (the exception to
  "Finish the game, not the bots" in `PROMPT.md`); the rest of "Backlog: bots" stays deferred. Keep
  the sim deterministic and the bot tick inside its time budget. No frames.

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

## Milestone — playtest feedback (user, 2026-11-16): do these five first, in this order

Written after the user's playtests. They come before the open Phase 4 and 5 tasks below, so the
loop takes them first. The order matters: names first (small, visible), then the figures' look,
then the fence rule and layout (which defines "own side"), then the isolation of the two houses
(which encloses whatever layout P3-8 leaves), then the home-side speed that depends on the
territory line. The parts of these tasks that were first missing (the gap, the back staircase,
P3-7) were filled in on 2026-11-16. Milestone: a friends playtest, so a working, simple version
beats a polished one. A task line tagged with a worker model (the tag is the word "worker", a colon
and a model name, in round brackets) runs on that model (see `loop.mjs`). No open task is tagged now:
Fable needs paid usage credits (2026-11-17), so the tags were removed from the open tasks.

- [x] **P5-0 Family display names.** *(Done 2026-11-16: `FamilyNames` in `game/greybox/family_names.gd` reads the `.cfg` once; status line, headlines and debug HUD use it; `family_names_test` 26 checks; the names are found only in the `.cfg`; export preset includes it. See PROGRESS.md.)* Each family gets a display name ("the family display names"),
  kept in ONE small text file, `godot/content/family_names.cfg`, two lines: `team_a_name=` and
  `team_b_name=` (plain text after the `=`, no quotes needed; blank lines and lines starting with `#`
  are ignored). The file already exists with the first two names, and `HOW_TO_PLAY.md` has a section
  "Changing the family names" that tells the user which file and lines to edit.
  Make the game read the file ONCE at start (one small loader class: trim spaces, strip optional
  quotes; a missing file or an empty value falls back to "Family A" / "Family B", never "Team A/B")
  and use the names everywhere a player sees a team: the HUD bar and status line, the menus and
  lobby, round and match results, the minimap and team-tell labels, any text a player can see.
  Internal ids stay `team_a` / `team_b` (sim, network, content, tests). No "Team A/B" text left on
  screen: search the UI code and scenes for it. **Nothing else in the project may contain the names
  as fixed text**: code, scenes, tests and docs say "the family display names"; tests compare with
  what the loader returns, never with a literal name. The names are presentation only: never in the
  sim, a snapshot or a network message (each machine shows what its own file says). The export
  (P7-1) must include the file. When done, delete the "until P5-0 is finished" caveat in
  `HOW_TO_PLAY.md`. *Verify:* one table-driven test of the loader (both lines, spaces, quotes, empty
  value, missing file, comment lines) and a search showing the names appear in no file but the
  `.cfg`; then the full `verify.mjs`. No frame captures.
- [x] **P2-6 Hair and builds: make each family member recognisable** *(Done 2026-11-17: hair shapes and dad's belly generated in `tools/rerig_character.gd` (`--hair=`, `--belly=`); hair colours and mom's / dad's builds in the theme; a member's drawn height is its body's, hair not counted. Frames in `autobuild/frames/p2_6/`; the lineup's 20 m and 40 m shots are blocked by the P3-4 exterior and show nothing. See PROGRESS.md.)* (the user's design notes from
  playtest; keep their spirit, refine as needed). Dad has a belly (dad bod) and a comb-over. Mom is a
  little jacked (broad shoulders, strong arms) with a tall stiff hairdo. The son has a small mohawk.
  The daughter has two pigtails. The elder and younger variants follow the same idea (the elder and
  younger boy each get the mohawk, the elder and younger girl each get the pigtails, told apart by
  size and shape). Hair is plain painted solid shapes in the figure material (no strands, no
  texture), built into the figure the way P2-1b's clothes are, following the Head bone; hair colours
  are data in the theme (REVIEW). Builds (belly, shoulders, arms) are bone scales and body shape in
  the theme data, as in P2-1. Faces stay blank and deadpan (D2): no eyes, mouth or nose; drawn faces
  are in the Backlog. Update STYLE.md §2.1 and §2.2 (hair is now allowed as plain shapes; faces are
  not) and note it on D2; log the choices in DECISIONS.md as REVIEW. Art stays optional via fallback;
  the poly budget and the animations still hold. *Verify:* the full `verify.mjs`; ONE lineup and
  turnaround capture set at the end, opened and judged against this text, and at most one redo.
- [x] **P3-8 Territory line, gate and house layout.** (The user's rules.) *(Done 2026-11-17: no neutral ground, the fence on x 3640 is the line; seize needs both bodies on the captor's side and no blocker between them; 400 gate + two 160 crossings; houses 2400 apart (was 520, 4.4 s at 540); an outside back staircase to Landing B per house; three yard props per house, same boxes, drawn per family. Frames in `autobuild/frames/` (`lot_overview`, `ext_gate_mid`, `ext_cross_*`, `ext_backstair_*`, `cam_backstair_top`, `cam_fence_gate`). See PROGRESS.md.)*
  1. **The boundary fence is the territory line: no neutral strip.** A defender can seize an
     opponent anywhere on the defender's side of the fence (house and yard); an opponent on their own
     side is safe. Check what the sim does today (zones, `ZoneDef.Role.NEUTRAL`, the seize rule, the
     validator) and change it to exactly this; update D9 and the docs (`HOUSE_LAYOUT.md`,
     `WORLD_AUTHORING.md`, `PROJECT_MEMORY.md`). Table-driven test for the seize decision on each
     side of the line.
  2. **One shared gate in the middle plus one smaller crossing at the back**, so the gate cannot be
     camped by one defender.
  3. **The gap between the two houses is double today's distance**, and a walk across should take
     4 to 6 seconds at walking speed (`move_speed` 540 a second, so about 2,200 to 3,200 units; measure
     today's distance first and check the result against both numbers). The planner may re-orient the
     houses (for example front doors facing each other across the fence) if that plays better. Both
     lots stay exact mirrors (the level-symmetry check in `verify.mjs` must stay exact).
  4. **Same layout in both houses, but each one visibly its own:** the family colours on trim, door
     and roof, plus two or three different yard props per house.
  5. **An outside back staircase: one per house, mirrored,** from the back yard up to the upstairs
     landing, never directly into the master bedroom. Real collision (matching how it is drawn), the
     bots' routes rebuilt, and the symmetry probe passes. If round times clearly break because of the
     longer walk, lengthen the rounds once in the mode files (REVIEW); no sweeps.
  Bots only have to keep working (the gate is `verify.mjs`); no bot tuning or sweeps. *Verify:* the
  full `verify.mjs`; ONE set of exterior, gate and staircase views at the end, opened and judged, and
  at most one redo.
- [x] **P3-7 Isolation: the two houses stand alone.** *(Done 2026-11-17: no other house anywhere; a 380 hedge behind both garden fences (cut away like the fence) and across both streets' far sides, tree belts beyond; each street a short dead end that leaves down a hedged lane into the trees; roof tiles and fascias in the family colours (theme `family_roof_colours`). All 25 exterior views opened, no third house. See PROGRESS.md.)* Remove every other house from the exterior
  (the neighbours' houses and the row of houses across the street that `ExteriorBuilder` draws since
  P3-4). Enclose the two lots with tall hedges and trees; the street is a short dead end. From every
  exterior camera only the two houses are visible. Each house gets its family's colours on trim, door
  and roof (colours are data in the theme; this overlaps P3-8's "visibly its own": P3-7 does the
  colours, P3-8 does the yard props). Do it after P3-8, so the hedges and trees enclose the final
  layout. Presentation only: no collision or zone change, and the bounds stay the real walls. The
  camera can stand outside the bounds (see `fence_cutaway.gdshader`), so a tall hedge near the
  bounds needs the same camera care as the fence. Update STYLE.md (the suburb is gone) and ASSETS.md
  for any new texture. *Verify:* the full `verify.mjs`; ONE set of every exterior view in
  `views.json` at the end, opened and judged (no third house in any of them), and at most one redo.
- [x] **P4-8 Panic run is animation only; defenders are faster at home.** *(Done 2026-11-17: `panic_speed_scale` removed, `home_speed_scale` 1.08 in `MovementSystem._speed_for`; the animator reads `is_panicking`; hedge REDO. See PROGRESS.md.)*
  1. **The chased player's panic run is animation only (arms up), with no speed boost.** Remove the
     speed multiplier (`panic_speed_scale`, 1.2, in `content/tuning/tuning_def.gd` and the `.tres`
     files, and where `MovementSystem` applies it). Keep what drives the arms-up pose (the forward
     count after about 2 s) because the animation uses it. The carrier's 0.85 factor is unchanged.
  2. **New: a player standing on their own side of the fence (a defender) moves at 1.08x**, a value
     in content data (REVIEW). Deterministic, decided in the sim from the territory line of P3-8,
     never from the presentation. Unspecified: it multiplies with the carrier's 0.85 (a carrier at
     home is 0.85 × 1.08); say so in the log.
  3. Update D9 (the panic run row, and the new home-side speed). Update the tests (the panic cases
     become "no speed change", plus table rows for the home-side factor on each side of the line)
     and the snapshot if a field is added or removed.
  4. Bot behaviour only has to keep working; no tuning, no sweeps. *Verify:* the full `verify.mjs`;
     ONE contact sheet of the panic run (arms up, same pace) and of a defender at home, at the end,
     and at most one redo.

## Phase 4 — Verbs (DECISIONS.md D9; see `DESIGN_DIRECTION.md` §5)

The v1 verb set is fixed by D9. Each new verb: a sim command + system (general, never
location-gated) + tuning in `.tres` + a table-driven test for its *decisions* only + presentation +
frames + bot_match still deterministic. Crouch, jump and throw already exist in the sim; vault was
removed on purpose (do not rebuild it). No ragdoll, knockback, slide, shove or drop-from-height in v1.

- [x] **P4-1 Panic run per D9:** sim tracks how long forward is held; speed boost from content data; deterministic; bot_match still green (this means verify.mjs passes, nothing more) *(Done 2026-11-16: `forward` flag on Move, `forward_ticks` count, ×1.2 after 2 s (REVIEW); snapshot format 3; 21 table cases; contact sheet `autobuild/frames/p4_1/panic_sheet.png`. See PROGRESS.md.)*
- [x] **P4-2 Presentation for jump, crouch, carry and throw per D9** *(Done 2026-11-16: audit sheets in `autobuild/frames/p4_2/` (own body via `--pilot=carry`); landing settle dip 6 / 0.2 s (REVIEW), grab without fade-in, released bundle eased from the hands onto its arc, bodies face their drawn travel (no face in the wall on a slide); crouch-walk kept at ×4.07 (REVIEW); MeshMerge fallback fix. See PROGRESS.md.)*
- [x] **P4-3 Jail run-in-place per D9:** the jailed player's inputs drive animation and camera only, never position *(Done 2026-11-16: jailed jumps counted in the sim (`held_jumps`, snapshot format 4), never kept for release; jog / crouch / crouch-walk / a 60-high drawn hop in place from the intent, facing the keys (REVIEW); mouse still turns the camera. `autobuild/frames/p4_3/jail_sheet.png`, `jail_chase.png`. See PROGRESS.md.)*
- [x] **P4-4 Players block each other like walls** (check what the sim does now; make bodies block if they pass through) *(Done 2026-11-16: measured with table rows at the game's numbers; head-on panic runners never passed through, but a running jump went through a standing body's chest. Sideways moves now meet a body as a cylinder of its drawn height, vertical moves keep the sphere; the sidestep round a body stays; nobody is moved by a bump. A fall onto a body still rests inside it (REVIEW lead). REDO: a jailed own body is not faded. See PROGRESS.md.)*
- [x] **P4-5 Cash tumble and bounce after a throw or drop** (cosmetic; snaps to the sim's position) *(Done 2026-11-16: `BundleTumble`: end-over-end spin in flight (540°/s thrown, 135°/s dropped), two hops on landing (first clamp(speed × 0.02, 4, 14), a drop ×0.4) while the spin eases to the nearest flat pose; drawn only, at the sim's x/z, exactly on the sim at rest. `--pilot=carry_out`, follow views `bundle` / `bundle_r`. Sheets in `autobuild/frames/p4_5/`. See PROGRESS.md.)*
- [x] **P4-6 Bots and panic run.** *(Done 2026-11-17: nothing to do. P4-8 removed the panic speed boost and its verify is healthy; bots never set forward.)* Bots may use panic run, but only so they do not break or get stuck. No tuning, no sweeps; verify.mjs is the gate. *(2026-11-16: P4-8 runs first and removes the panic speed boost, so there is no panic speed for bots to use. This task then shrinks to "bots do not break or get stuck with the new rules"; if verify is healthy, there is nothing to do: tick it with that note.)*
- [x] **P4-7 Verb readability audit by frames** *(Done 2026-11-17: audit table in PROGRESS.md, no code changed; seize and free not seen in current art.)* *(2026-11-16, testing diet: audit the frames the earlier verb tasks already made, `autobuild/frames/p4_*`; no new captures.)*

## Phase 5 — Game feel, UI, audio

- [x] **P5-1 Menus.** *(Lobby done 2026-11-17: `LobbyPanel`; see PROGRESS.md.)* *(2026-11-17: settings (sensitivity, volumes, rebindable keys), SFX/Music buses, pause, results panel done. Left: the lobby screen (seats/mode/bots/Start before a menu-hosted match); the menu host still starts at once. See PROGRESS.md.)* A basic main menu already exists (`main_menu.gd`): audit it, then build it out —
  host/join (code field, later Steam invite), lobby screen with
  seats/teams/mode/bundles/bots, pause, settings (sensitivity, volume, keybinds), results screen.
- [x] **P5-2 HUD: a fighting-game style top bar** *(Done 2026-11-17: `MatchHud` bar, `MatchStatus.cash_split` + 9-row test. See PROGRESS.md.)* (the tug-of-war cash bar). ONE bar across the top:
  the first family's colour fills from the left, the second family's from the right, and the split
  follows each family's share of the banked cash (equal at 0 and 0; the whole bar to one side only
  when the other has nothing). Each family's display name (from P5-0's loader, never typed into the
  UI) and its cash count sit at its own end of the bar; the round timer is in the middle. The family
  colours are the theme's. Also on the HUD: the carry state and the jail timer (and the rescue prompt
  and the teammates-only minimap that were already part of this task; D3 option b). Replace the
  debug text with it; the debug HUD stays behind its F-key. The split is a pure function of the two
  cash counts: give it a small table-driven test (0/0, 1/0, 3/1, equal, one side only). *Verify:*
  that test and the full `verify.mjs`; no frame captures.
- [x] **P5-3 Audio.** CC0 SFX and a music loop (Kenney, freesound CC0, OpenGameArt CC0): ordinary
  household sounds — footsteps, doors, grab, caught, free, cash, alarm-ish sting, UI. No cartoon
  sounds (D2). Audio buses, volume settings.
- [x] **P5-4 Deadpan feedback: plain, physical, short. No confetti or cartoon effects.** *(Done 2026-11-17: `GameFeedback`: event line, vanish puff, seized/freed cut, camera nudge, HUD cash bump. Unseen. See PROGRESS.md.)* (D2.)
  Cheap in the Compatibility renderer.
- [x] **P5-5 First-run clarity.** *(Done 2026-11-17: FirstRunGuide step line, controls strip, How to play panel, F9 skip. Unseen. See PROGRESS.md.)* Controls hints and a 60-second guided first match so a friend can
  join without a lecture.

## Phase 6 — Networking and Steam

- [x] **P6-1 Loss and lag.** *(Done 2026-11-17: `LinkConditions` on the loopback; net_loopback IN LOCKSTEP at 100 ms + 5% loss; net_prediction CONSISTENT at 3 and 6 ticks + 5% loss. See PROGRESS.md.)* Add latency/packet-loss options to the loopback transport; confirm
  prediction/rollback/snapshots hold at 100 ms + 5% loss; fix defects.
- [x] **P6-2 Host modes.** *(Done 2026-11-17: listen host documented in ARCHITECTURE.md; `--headless --dedicated` built as a thin flag in greybox_main.gd. See PROGRESS.md.)* Confirm what exists (player-hosted listen mode vs dedicated headless) and
  document in `godot/ARCHITECTURE.md`. Implement a headless dedicated host only if it is small.
- [x] **P6-3 Steam transport** *(Done 2026-11-17: `SteamTransport` + fake-Steam contract rows, 50 checks; live two-instance test waits on BLOCKED.md.)* behind the existing session/transport interface using GodotSteam
  (dev with Steam test app id 480). Works with two local instances where possible.
  Needs the user's Steamworks app for the real id → write BLOCKED.md for that part only.
- [x] **P6-4 Invite/join flow** *(Done 2026-11-17: Host on Steam, overlay invite, `+connect_lobby`, join_requested; live test waits on BLOCKED.md.)* through Steam lobbies, keeping the room-code path for Tailscale/LAN.

## Phase 7 — Release candidate

- [x] **P7-1 Export.** *(Done 2026-11-17: `node autobuild/build.mjs` -> `build/CashGrab.exe` 118.5 MB, smoke run clean. See PROGRESS.md.)* Windows export preset, a `autobuild/build.mjs` that produces `build/CashGrab.exe`;
  needs export templates installed (write BLOCKED.md if missing; do not download 800 MB unprompted — ask in the report).
- [x] **P7-2 Quality settings and performance** on the dev machine (windowed, real GPU): record FPS in `PLAYTEST.md`.
- [x] **P7-3 Docs.** *(Done 2026-11-17: README rewritten for the Godot game, PLAYTEST.md brought up to date, Credits button + `content/credits.md` copy, STORE_CHECKLIST.md. See PROGRESS.md.)* Update `README.md`, `PLAYTEST.md`, credits screen from `CREDITS.md`, a store-page asset checklist.
- [x] **P7-4 Release sweep.** *(Done 2026-11-17: build.mjs + full verify, no frames per the testing diet; tag v0.1.0-rc1 local.)* Full `verify.mjs --frames` over every room, final PROGRESS entry, tag `v0.1.0-rc1`.

## Backlog — do NOT start unless every task above is done

Proximity voice chat · clip export (seed + input log) · lag compensation · defender prep phase
(traps/locks) · loot variety (TV needing two people, piggy bank) · more maps · cosmetics/progression ·
decoy mannequins/figures placed in the house (must be subtle, not obvious; try after v1) ·
drawn faces on the figures (eyes, mouth: kept blank for v1, D2; hair is allowed from P2-6).

## Backlog: bots — revisit only when the user reports a problem

Paused by the user on 2026-11-15 (DECISIONS.md log): finish Phases 3 to 5 first. Open items, with
the measurements and leads in P3-3d, P3-3e and P3-3f above and in PROGRESS.md:

- **Level matches.** Matches that end level in regulation: 1 of 32 at 240 s rounds after P3-3e
  (5 of 32 before), with many rounds running to the clock.
- **team_a winning by seat name**: 23 of 32 (team_b 8) in the sweep after P3-3e.
- **House A winning 20 of 32** (House B 11) in the same sweep.

A stash on this machine holds session 7's unfinished P3-3f sweep statistics (`git stash list`:
"session 7 leftovers").

## Backlog: after the playtest — do NOT start before the user has played

- Trial of simple hand-drawn faces (our own dot eyes and line mouth) as a switchable setting; it
  would change D2.
- The user may supply their own recorded "fahhh" for the jail sound: it replaces
  `godot/content/sfx/jailed.ogg` (PT2-4) and is logged in `ASSETS.md` as the user's own recording.
- A swear-word filter for family names before strangers can play together on Steam (PT3-3: today
  only friends play, so names are only length- and character-limited).
