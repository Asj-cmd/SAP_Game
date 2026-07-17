# Cash Grab — Project Status & Handoff Brief

**Purpose:** a self-contained snapshot another chat can read cold to produce
detailed next-step instructions. Covers what the game is, what's built today,
the full tech stack, the master plan, and the Blender-MCP + Claude-Code workflow
we want to use for building the 3D world and characters.

- **Code source of truth:** branch **`claude/game-mvp-dev-pl5suo`** (always read
  the latest there). This planning branch (`claude/cash-grab-game-skills-qxd4ne`)
  holds only PRDs/master-plan/skills.
- **Last verified commit read:** `858d287` (Phase 3 complete + polished).

---

## 1. What the game is

A **third-person 3D chaotic multiplayer party game** for **Steam**. Two families
raid each other's houses to **steal cash bundles**, **jail** intruders caught at
home, and **rescue** jailed teammates. Modes: 2v2 / 3v3 / 4v4 (host picks),
best-of-3 rounds, host-configurable bundle count. Reference *feel* (not content):
the rough, readable, one-more-round energy of viral indie party games (Meccha
Chameleon's UI vibe). Concept, world, and cast are original.

**Guiding constraints:** validate cheaply (near-$0 until proven), fun-first,
ship on Steam. Distinctive art/characters are the human/creative bottleneck;
Claude Code carries the code.

---

## 2. Current status — DONE (Phases 1–3)

The game is **fully playable in 3D over the network today.**

### 2.1 Server — Colyseus, authoritative, deploy-ready shape
- `server/src/rooms/GameRoom.ts` (~726 lines): all game logic, server-validated.
  Message handlers: `move`, `pickupCash`, `depositCash`, `lockPlayer`,
  `rescuePlayer`, `stealScored`, plus host controls `startGame`, `assignTeam`,
  `setBotCount`. AI bots (`addBot`/`removeBot`). Best-of-3, win scoring, jail
  timers, steal-back with anti-exploit handling.
- `server/src/zones.ts`: 2D zone model (`getZoneAt(x,y)`), mirrored houses
  (bedroom/living/basement) + private backyards + shared garden. **No height
  axis** (flat plane).
- `server/src/index.ts`: REST (`/create-room`, `/rooms/:code`, `/health`), CORS,
  and **serves the built client from `client/dist` on the same port** — so a
  match is reachable on ONE URL ("friends open one link"). Dev uses Vite :5173
  pointing back at :2567.
- `server/src/schema/GameState.ts`: `PlayerState` (`x,y,vx,vy`, carrying, jailed,
  jailTimer, team, isBot), `CashBundleState` (location/isScored), `GameState`
  (hostId, phase, teamSize, winScore, timers, scores, wins, players, bundles).

### 2.2 Client — Three.js (vanilla), one render loop
- `client/src/main.ts` → `LobbyView` → `GameController`. **No Phaser.**
- `three/GameController.ts` (~304 lines): the orchestrator — local movement,
  20 Hz `move` send, remote sync, cash view, HUD, and the 5-way SPACE context
  action (pickup / lock / rescue / steal + auto-deposit on home threshold).
- `three/CharacterController.ts`: camera-relative WASD, circle-vs-AABB collision
  against wall + solid-prop rects, world-bounds clamp. Flat plane, no gravity.
- `three/CameraRig.ts`: FPS-style pointer-lock mouse-look third-person chase cam
  with raycast wall-avoidance.
- `three/CharacterModel.ts`: loads `character.glb`, Idle/Walk blend by speed,
  team color, carried-cash indicator, jailed dimming.
- `three/RemoteCharacterSync.ts`, `three/CashBundleView.ts`: remote players and
  cash rendered from server state (interp for remotes, snap on jail teleport).
- `lobby/LobbyView.ts`: DOM lobby — create/join by code, host team assignment,
  bot count, Start Game, auto-start when full.
- `ui/HudOverlay.ts`: timer, round, context prompts, jail banner, pointer-lock
  hint, round/match overlays. (Score is read from bedroom cash stacks, not shown
  numerically.)

### 2.3 World — flat plane *dressed as real houses* (Phase 3)
- `three/EnvironmentBuilder.ts` + `three/world/`:
  - `RoofSystem.ts` — per-room roof slabs with a **fade reveal** of whichever
    room the local player is in (dollhouse view); backyards/garden open-air.
  - `WindowBuilder.ts` — **real see-through window openings** punched into walls
    (mullioned 4-pane frames), collision unchanged.
  - `propManifest.ts` — pure placement data (pre-scale coords, House A mirrored
    from House B), marks props solid vs decorative.
  - `PropLibrary.ts` / `HouseDresser.ts` / `InstancedPropBuilder.ts` — load-once
    prop GLBs, place per zone, and **instance** repeated props
    (trees/bushes/fences/crates/jail-bars/path/rugs). Draw calls 168→125,
    ~47k triangles. Solid props feed the controller's collider rects.
  - `SceneManager.ts` — upgraded lighting: **VSM soft shadows**, **ACES Filmic
    tone mapping** (exposure 1.2) + sRGB output, hemisphere/ambient fill.
- **17 prop GLBs** in `client/public/models/props/` (bed, nightstand, dresser,
  sofa, coffee_table, tv, rug, crate, shelf, pipes, jail_bars, fence, tree,
  bush, fountain, shed, stone_path).

### 2.4 Asset pipeline — headless Blender bpy (committed, reproducible)
- `assets/blender/build_character.py`, `build_cashbundle.py`,
  `build_furniture.py`, `build_nature.py` — run via
  `blender --background --python <script>.py`. Generated `.glb`s are committed so
  a fresh checkout runs without Blender.

### 2.5 What's NOT built yet (the road ahead)
- **Characters are placeholder** — one team-colored Blender figure with Idle/Walk.
  Not the funny/offbeat/chaotic cast we want. → **Phase 4**.
- **No physics engine** — no ragdoll/knockback/tackle chaos; flat plane, no
  gravity/jump. → **Phase 4** (Rapier).
- **No true verticality / functional stairs / climb-through windows.** → Phase 5.
- **No audio, limited juice/VFX.** → Phase 6.
- **Not deployed / no matchmaking hardening / no reconnection.** → Phase 7.
- **No Steam packaging** (Electron + steamworks.js). → Phase 8.

---

## 3. Tech stack (current + target)

| Layer | Now | Target / later |
|---|---|---|
| Authoritative server | **Colyseus** + TypeScript | Deploy on Fly.io/Railway/Colyseus Cloud (Phase 7) |
| Rendering | **Three.js** (vanilla) + Vite | — |
| Physics | custom kinematic (flat) | **Rapier.js** (WASM) for chaos/ragdoll (Phase 4); verticality (Phase 5) |
| Language | TypeScript (client + server) | — |
| Networking | colyseus.js, 20 Hz move, server-authoritative | matchmaking, reconnection, regions (Phase 7) |
| 3D asset authoring | **headless Blender bpy scripts** | + **Blender MCP** interactive authoring (see §5) |
| Free asset sources | procedural bpy | **PolyHaven** CC0 (textures/HDRIs/models); **Hyper3D Rodin** text/image→3D (free daily limit) |
| Audio | none | FMOD/Wwise or Web Audio; freesound/sfxr (Phase 6) |
| Desktop/Steam wrapper | none | **Electron + steamworks.js** (Tauri as lighter alt) (Phase 8) |
| Validation distribution | local single-URL | **itch.io** free web build → Steam ($100 one-time) |

**Cost posture:** ~$0 through the first web validation gate; ~$5–20/mo when
always-on servers are needed; $100 one-time for Steam. Hyper3D Rodin free tier
has a daily generation cap; PolyHaven is fully free CC0.

---

## 4. Master plan (phase map)

| Phase | Name | Status | Outcome |
|---|---|---|---|
| 1 | 2D Concept MVP | ✅ done | Phaser + Colyseus full game logic |
| 2 | 3D Cutover (A–D) | ✅ done | Flat-plane 3D multiplayer, mouse-look cam, host lobby + bots, single-URL hosting |
| 3 | Real Houses & World Believability | ✅ done | Roofs w/ reveal, see-through windows, 17 furnished props, instancing, ACES + soft shadows |
| **4** | **Characters & Chaos** | **▶ next** | Original funny/offbeat cast (Blender MCP), **Rapier physics**: knockback, ragdoll, dropped-cash, shove/tackle. Biggest fun lever. |
| 5 | Verticality & Houses v2 | planned | True multi-floor, **functional stairs**, climb-through windows; server gains a height/floor axis (needs Phase 4 physics) |
| 6 | Game Feel & UI Polish | planned | Meccha-style HUD/menus, audio, VFX/juice, settings |
| 7 | Online Hardening | planned | Deploy Colyseus, matchmaking, reconnection, regions, anti-cheat basics |
| 8 | Steam Packaging | planned | Electron + steamworks.js; Windows + Steam Deck |
| 9 | Launch | planned | Store page (start early for wishlists), capsule/key art, trailer, release |
| 10 | Post-launch | planned | Patches, new maps/characters, scaling, community |

**Validation gates:** Gate 1 (free web build on itch.io) after Phase 4 — watch
real people play, go/no-go before spending. Gate 2 (Steam playtest/demo) after
Phase 8.

**Sequencing note:** Phase 4 is the single biggest "is it fun" lever. If Gate 1
says the loop needs more juice before more content, Phases 5/6 can be reordered.

---

## 5. Building the 3D world & characters with **Blender MCP + Claude Code**

We want to author the world and (especially) the **characters** interactively via
**Blender MCP** — a shift/augment from the headless bpy scripts that made the
current props.

### 5.1 What Blender MCP gives us
[Blender MCP](https://github.com/ahujasid/blender-mcp) (by ahujasid) connects
Claude to a **running Blender** via an addon + MCP server. Claude Code can then:
- create/move/delete objects, set materials/colors, adjust lighting,
- run **arbitrary bpy Python** in the live session,
- capture **viewport screenshots** for visual feedback (iterate by seeing),
- pull free **PolyHaven** CC0 textures/HDRIs/models,
- generate meshes from text/images via **Hyper3D Rodin** (free daily limit).

This is ideal for the **funny/offbeat characters** (iterative sculpt + pose +
material with visual feedback) and hero world pieces, where the headless
"write-script-blind" loop is slow.

### 5.2 Setup (on the user's local machine — Blender has a GUI, the cloud sandbox does not)
1. Blender **3.6+**: Edit → Preferences → Add-ons → Install `addon.py` from the
   repo → enable it. Press **N** for the sidebar; optionally tick *Use assets
   from Poly Haven* and/or *Use Hyper3D Rodin*.
2. Configure the **blender-mcp** MCP server in Claude Code (e.g. `uvx
   blender-mcp`); in Blender's sidebar click **Connect to Claude**. Do **not**
   also run the uvx command manually in a terminal (double-run is the #1 connect
   bug).
3. Verify Claude can "get scene info" and screenshot the viewport.

### 5.3 Recommended hybrid workflow (keeps the repo reproducible)
- **Author** characters/world pieces interactively with Blender MCP (screenshots
  + PolyHaven/Hyper3D as needed).
- **Export** results to `.glb` and **commit** them under `client/public/models/`
  (characters) / `.../props/` — the runtime stays asset-based, **no Blender
  needed to play**.
- **Back-fill a headless bpy script** (`assets/blender/build_*.py`) for anything
  we'll want to regenerate deterministically, matching the existing pattern.
- Keep art **stylized and cohesive** with the current low-poly look; keep
  polycounts/draw budget in check (use the `threejs-debug-profiler` skill).
- Characters must keep the rig/animation contract the client expects
  (`CharacterModel` plays clips named **Idle**/**Walk**, has a **Body** material
  for team tinting, and a head-top anchor for the carried-cash indicator) — or
  update `CharacterModel.ts` deliberately alongside new rigs.

---

## 6. Installed skills (on the code branch, in `.claude/skills/`)

- **threejs-game-skills** bundle (majidmanzarpour, 973★): `threejs-game-director`
  (orchestrator), `threejs-gameplay-systems`, `threejs-aaa-graphics-builder`,
  `threejs-game-ui-designer`, `threejs-debug-profiler`, `threejs-qa-release`.
- **Vetted add-ons:** `three-best-practices` (MIT), `blender-3d-modeling`
  (Apache-2.0, procedural bpy), `3d-modeling`, `shader-techniques`.
- Not installed (need paid API keys): the Tripo/Gemini/ElevenLabs generators.
- These are already committed to the code branch — any session that checks it out
  loads them automatically.

---

## 7. Standing rules (honor these in every phase)

1. **No test code / test files / test functions / automated test or QA
   harnesses.** Verify by building + a manual checklist. This overrides any
   skill's default QA (e.g. `threejs-qa-release`'s bot-playtest/visual harness).
2. **Keep code properly structured** — single-purpose files, named exports, no
   dead code, reuse over duplication; new world code under `three/world/`.
3. **Server stays authoritative** — client sends intent, never mutates game
   state (anti-cheat foundation).
4. **One coordinate mapping** — server `(x,y)` == Three `(x,z)`, Three `y` = up.
5. Don't change `server/`, `zones.ts`, or `geometry/floorplan.ts` numbers unless
   the phase explicitly calls for it.

---

## 8. What to ask the next chat (immediate: Phase 4)

Ask it to produce a **detailed Phase 4 "Characters & Chaos" build PRD +
step-by-step instructions**, covering:
1. **Original character cast** — concept + how many, authored via **Blender MCP**
   (§5), exported to committed `.glb`, honoring the `CharacterModel` rig/anim
   contract (Idle/Walk, Body material, carry anchor) or updating it deliberately.
2. **Rapier.js physics integration** — replace/augment the kinematic controller
   with Rapier on the flat plane first: knockback, shove/tackle, ragdoll on jail/
   hit, dropped-cash that bounces — while keeping the **server authoritative**
   (decide what physics is cosmetic-client vs authoritative-server).
3. **Game-feel/chaos tuning** — hitstop, screenshake, impact feedback (use
   `threejs-gameplay-systems` + `threejs-aaa-graphics-builder`).
4. A **manual** Definition-of-Done checklist (no test code).

**Open questions for the next chat to resolve or ask us:**
- How many characters, and how distinct (skins vs different bodies/rigs)?
- Is ragdoll/knockback **authoritative** (server simulates) or **cosmetic**
  (client-only, server keeps simple positions)? Recommendation: keep server
  simple/authoritative, ragdoll cosmetic on clients — but confirm.
- Do we invest in Hyper3D Rodin (paid beyond free daily cap) for characters, or
  stay fully free (PolyHaven + hand modeling)?
- Reconfirm the environment-first vs chaos-first ordering still holds now that
  Phase 3 shipped.

---

*Snapshot as of commit `858d287`. Phases 1–3 shipped; Phase 4 (Characters &
Chaos, via Blender MCP + Rapier) is next.*
