# Phase 2 · Milestone C — 3D Multiplayer Cutover
## Product Requirements Document for Claude Code

---

## 0. Read This First

This PRD takes the game from a **2D Phaser client** to a **3D Three.js client**
running against the **existing, unchanged Colyseus server**. Milestones A
(static 3D world), A2 (character + cash assets), and B (local character
controller + 3rd-person chase camera) are already built and verified in the
`client/src/three/preview.ts` dev harness. This milestone — **C** — wires that
3D layer to real multiplayer: it becomes the actual game client, renders every
player and cash bundle from authoritative server state, and drives the full core
loop over the network. After this milestone the Phaser scenes are retired.

**Build exactly what is specified here. Do not add features not listed. Do not
simplify mechanics. Stop and ask before making any architectural decision not
covered here.**

### 0.1 Two hard rules for this and every future PRD

1. **DO NOT write any test code, test files, test functions, test harnesses,
   or automated test scripts.** No unit tests, no integration tests, no
   Playwright/Vitest/Jest specs, no `*.test.ts`, no throwaway validation
   scripts. Verify your work by building the client and reasoning through the
   manual checklist in Section 10 — nothing else. Writing and running test
   scaffolding burns tokens for output nearly identical to building without it.
   The one existing dev harness (`preview.ts`) is a manual visual harness, not a
   test — do not extend the codebase's automated-verification surface.
2. **Keep the code properly structured.** One responsibility per file, clear
   module boundaries, named exports, no dead code, no giant catch-all files.
   Match the existing structure and naming in `client/src/three/` and
   `client/src/network/`. Reuse existing modules; do not duplicate logic that
   already exists on the server or in a shared module.

---

## 1. Current State (What Already Exists — Do Not Rebuild)

### 1.1 Server — complete and authoritative. Do NOT modify in this milestone.
- `server/src/rooms/GameRoom.ts` — all game logic: pickup, deposit, steal-back,
  lock, jail, rescue, auto-release, round/match flow, 2v2/3v3/4v4, win scoring.
- `server/src/schema/GameState.ts` — `PlayerState` (`x, y, vx, vy`,
  `isCarryingCash`, `isJailed`, `jailTimer`, `team`, `connected`),
  `CashBundleState` (`x, y, location, isScored`), `GameState` (`phase`,
  `teamSize`, `winScore`, `roundTimer`, `countdown`, `scoreA/B`, `roundNumber`,
  `winsA/B`, `roundWinner`, `matchWinner`, `players`, `cashBundles`).
- Server message handlers already accepted by the room:
  `"move" {x, y, vx, vy}`, `"pickupCash" {bundleId}`, `"depositCash" {bundleId}`,
  `"lockPlayer" {targetId}`, `"rescuePlayer" {targetId}`,
  `"stealScored" {bundleId}`.

### 1.2 Client 3D layer — built, currently preview-only.
- `three/SceneManager.ts` — scene, renderer, resize, render loop.
- `three/EnvironmentBuilder.ts` — builds the 3D world (walls + floor merged
  meshes) from `geometry/floorplan.ts` (`ZONE_RECTS`, `WALLS`, `DOORS`), the same
  rect data the server validates against.
- `three/CharacterModel.ts` — loads `character.glb`, `setFacing`, walk update.
- `three/CharacterController.ts` — absolute-direction WASD, circle-vs-AABB
  collision against the wall rects, world-bounds clamp. Works in `(x, z)`.
- `three/CameraRig.ts` — 3rd-person chase camera, slew-limited yaw, raycast
  wall-avoidance.
- `three/preview.ts` + `three-preview.html` — **dev-only** manual harness.
  Explicitly marked "Deleted during the Milestone C cutover."

### 1.3 Client 2D layer — to be retired by this milestone.
- `scenes/GameScene.ts`, `scenes/UIScene.ts`, `scenes/LobbyScene.ts`,
  `scenes/BootScene.ts`, `objects/*`, and the Phaser dependency.
- **These are the behavioral reference.** Read them to learn the exact network
  cadence, the SPACE context-action rules, and the HUD contents — then
  reproduce that behavior in the 3D client. Do not invent new rules.

---

## 2. Scope of This Milestone

### 2.1 In scope
- Replace Phaser as the game client with the Three.js client.
- Keep a lobby (name entry, create/join by room code, waiting screen). Reuse the
  existing lobby's Colyseus flow; it may stay in DOM/HTML rather than Phaser.
- Render **all** players (local + remote) and **all** cash bundles from server
  state, every frame.
- Local player: immediate movement via `CharacterController`; send `"move"`
  every 50ms.
- Remote players: interpolate toward server position (`REMOTE_LERP` 0.2); snap
  on jail teleport.
- Full SPACE context-action logic → the correct server message.
- 3D/DOM HUD: round timer, round number, jail overlay, context-action prompt,
  countdown, round-end / match-end overlays. Score read from bedroom bundle
  counts (no numeric score in HUD), matching the 2D behavior.
- Cash bundles rendered in their state-driven locations (in a bedroom, carried
  above a player's head, or stacked as scored bundles in a bedroom).
- Basic reconnection/disconnect handling parity with the 2D client.

### 2.2 Explicitly OUT of scope (do NOT build in this milestone)
- Any change to server logic, schema, or the geometry/floorplan data.
- Multi-floor houses, stairs, real windows, furnished rooms (that is Phase 3).
- New character art, ragdolls, physics engine swap, Rapier (that is Phase 4).
- Sound, music, particles, screen shake, menus polish (Phase 5).
- Server deployment, matchmaking service, Electron/Steam packaging (Phases 6–7).
- Any new gameplay mechanic, power-up, or rule.

---

## 3. Tech Stack (This Milestone)

| Concern | Tool | Note |
|---|---|---|
| Rendering | **Three.js** (already a dep) | Continue vanilla Three, no framework |
| Networking client | **colyseus.js** (already a dep) | Reuse `network/ColyseusClient.ts` patterns |
| Language | **TypeScript** | Shared coordinate/type conventions |
| Build | **Vite** | Existing config |
| Physics | **None new** — keep the existing kinematic controller | Rapier is Phase 4, not now |

Do NOT add new runtime dependencies in this milestone. Remove `phaser` from
`client/package.json` only after the cutover is complete and no code imports it.

---

## 4. Coordinate System (Authoritative Convention)

The server is 2D: `x` (horizontal), `y` (the second ground-plane axis). The 3D
client maps them as the existing code already does:

```
server x   ->  three.js x
server y   ->  three.js z
three.js y ->  UP (height). Ground-plane play happens at y ≈ 0.
```

- World bounds: `WORLD_WIDTH = 1600` (x), `WORLD_HEIGHT = 900` (z).
- All server positions sent/received use `(x, y)` == `(three.x, three.z)`.
- When sending `"move"`, send `{ x, y: z, vx, vy: vz }`. When reading a
  `PlayerState`, place the model at `(state.x, 0, state.y)`.
- Do not introduce a second, conflicting mapping anywhere.

---

## 5. Target File Structure

Add the following. Keep each file single-purpose. Names are fixed.

```
client/src/
├── main.ts                     # entry: boot -> lobby -> game (no Phaser)
├── game/
│   ├── GameClient.ts           # owns SceneManager, world, players map, cash map,
│   │                           #   camera rig, input, per-frame update, room binding
│   ├── PlayerEntity.ts         # one player's model + controller/interpolator + labels
│   ├── CashEntity.ts           # one bundle's mesh + placement-from-state logic
│   ├── InputManager.ts         # keyboard -> InputState + SPACE edge detection
│   └── ActionResolver.ts       # pure: (localState, world) -> which SPACE action + target
├── ui/
│   ├── Hud.ts                  # DOM overlay: timer, round, context prompt, jail banner
│   └── Overlays.ts             # countdown, round-end, match-end DOM overlays
├── lobby/
│   └── Lobby.ts                # name entry, create/join, waiting screen (DOM)
├── network/
│   └── ColyseusClient.ts       # reuse/extend existing; typed room + message senders
├── three/                      # existing — reuse as-is where possible
│   ├── SceneManager.ts
│   ├── EnvironmentBuilder.ts
│   ├── CharacterModel.ts
│   ├── CharacterController.ts
│   ├── CameraRig.ts
│   └── preview.ts              # DELETE at end of milestone
├── geometry/floorplan.ts       # existing — unchanged
└── constants.ts                # existing — extend only if a value is genuinely new
```

Delete after cutover: `scenes/`, `objects/`, `three/preview.ts`,
`three-preview.html`, and the `phaser` dependency.

---

## 6. Detailed Requirements

### 6.1 Application lifecycle (`main.ts`)
1. Show `Lobby`. On successful room join, tear down the lobby DOM and start
   `GameClient` with the joined `Room` handle.
2. `GameClient` owns the render loop from that point. It reads
   `state.phase` to decide what to show (waiting / countdown / playing /
   roundEnd / matchEnd) via `Hud` + `Overlays`.

### 6.2 World construction
- On game start, build the environment once via `buildEnvironment(myTeam)` (it
  already seals the local team's own bedroom doors as solid wall — preserve
  that). Pass the wall meshes to `CameraRig` as obstacles and the collider rects
  to each local `CharacterController`, exactly as `preview.ts` does today.

### 6.3 Players (`PlayerEntity`, managed by `GameClient`)
- Maintain a `Map<sessionId, PlayerEntity>` synced to `state.players`
  (`onAdd`/`onRemove`).
- **Local player** (matches the room's `sessionId`):
  - Driven by `InputManager` + `CharacterController` every frame (immediate,
    client-predicted). Do NOT interpolate the local player.
  - Every `MOVE_SEND_INTERVAL_MS` (50ms) send `"move" { x, y, vx, vy }` from the
    controller's current position/velocity (`y` = z, `vy` = vz).
  - When the server sets `isJailed` true (or teleports on jail), **snap** the
    local controller to `state.x/state.y` immediately — do not smooth a
    teleport. While `isJailed`, disable input-driven movement.
- **Remote players:**
  - Each frame, interpolate the model position toward `(state.x, 0, state.y)`
    using `REMOTE_LERP` (0.2). Snap (no lerp) if the position delta is large
    enough to be a teleport (jail) — reuse the 2D client's threshold logic.
  - Face direction from movement delta or `vx/vy` via `CharacterModel.setFacing`.
- **All players** render: team color tint, a floating name label, a carried-cash
  indicator when `isCarryingCash`, and a jailed appearance (dimmed + a simple
  lock marker) when `isJailed`. Mirror the 2D visual semantics; 3D styling is
  fine (billboarded sprites/labels), but keep it simple — this is not the polish
  phase.

### 6.4 Cash bundles (`CashEntity`, managed by `GameClient`)
- Maintain a `Map<bundleId, CashEntity>` synced to `state.cashBundles`.
- Placement is driven entirely by `location` + `isScored`:
  - `"bedroomA"` / `"bedroomB"` — sit at the bundle's `(x, y)` on that bedroom
    floor. If `isScored`, it is a banked bundle: arrange scored bundles in a neat
    stack/grid in the owning bedroom so players can **count them by looking**
    (score is not shown numerically — same as the 2D build).
  - `"carried:{playerId}"` — hide the world bundle; the carrying player's
    carried-cash indicator represents it.
  - Follow the exact same reading of `location` the 2D `GameScene` uses. Do not
    re-derive scoring on the client — just render what state says.

### 6.5 Input (`InputManager`)
- WASD / arrow keys -> `InputState { left, right, up, down }` (already the shape
  `CharacterController` expects).
- SPACE: expose a rising-edge "pressed this frame" signal (do not fire an action
  every frame SPACE is held).
- Ignore input while the local player `isJailed` (movement) — but SPACE-driven
  rescue is a teammate's action, not the jailed player's, so the jailed player
  simply cannot act.

### 6.6 Context action (`ActionResolver` — pure function, no side effects)
Given the local player's state and the current world, return at most one action
+ target, using the **same precedence the 2D client uses**:
1. Not carrying + inside enemy master bedroom + a pickable bundle within
   `ACTION_RANGE` (60) -> `pickupCash { bundleId }`.
2. Carrying + just crossed own home threshold -> `depositCash { bundleId }`
   fires **automatically** (no SPACE needed) — detect the threshold crossing as
   the 2D client does.
3. Inside own home + a non-teammate within `ACTION_RANGE` -> `lockPlayer
   { targetId }` (nearest enemy).
4. Inside a basement + a jailed teammate within `ACTION_RANGE` -> `rescuePlayer
   { targetId }`.
5. Inside enemy master bedroom + a scored bundle within `ACTION_RANGE` ->
   `stealScored { bundleId }`.
`GameClient` calls the resolver, shows the matching prompt via `Hud`, and on the
SPACE rising edge sends the corresponding message. The **server** validates and
mutates state; the client never mutates game state locally.

### 6.7 HUD & overlays (`Hud`, `Overlays` — DOM overlay over the canvas)
- Top-left: round timer `MM:SS` (large) + "Round X of 3" below it.
- Bottom-center: control hint ("WASD: Move · SPACE: Action").
- Context prompt above/near the player when an action is available:
  "SPACE: Pick up cash" / "SPACE: Lock {name}" / "SPACE: Rescue {name}" /
  "SPACE: Steal cash". Hidden when no action applies. Deposit is automatic, so
  no deposit prompt.
- Jail banner (only for the local jailed player): "JAILED — {n}s · Teammate can
  rescue you · Auto-release in {n}s", driven by the local player's `jailTimer`.
- `Overlays`: 3-2-1 countdown; "ROUND X WINNER: TEAM {A/B}" then "Next round
  in 3…"; "TEAM {A/B} WINS THE MATCH!" on match end. Contents mirror the 2D
  `UIScene`.
- No numeric score anywhere — score is read from the bedroom cash stacks.

### 6.8 Networking parity (`ColyseusClient`)
- Reuse the existing connection/room-join code. Add typed helpers for the six
  message senders in 1.1. Keep the 50ms move cadence and `REMOTE_LERP`.
- Disconnect: mark the player's entity removed on `onRemove`; the room continues
  for others. On local disconnect, surface a simple "Disconnected" overlay
  (parity with 2D). Deep reconnection/matchmaking is Phase 6 — do not build it
  here.

---

## 7. Reuse vs Replace

- **Reuse unchanged:** `SceneManager`, `EnvironmentBuilder`, `CharacterModel`,
  `CharacterController`, `CameraRig`, `geometry/floorplan.ts`, `constants.ts`,
  the server, and the Colyseus connection code.
- **Port behavior from (then delete):** `scenes/GameScene.ts` (movement send
  cadence, remote interp, SPACE precedence, threshold deposit),
  `scenes/UIScene.ts` (HUD contents), `scenes/LobbyScene.ts` (join flow).
- **Delete at the end:** all `scenes/`, all `objects/`, `three/preview.ts`,
  `three-preview.html`, and the `phaser` dependency + its imports.

---

## 8. Constraints (Hard Rules)

- **No test code / test functions / test scripts of any kind** (see 0.1). Verify
  via build + the Section 10 manual checklist only.
- **Keep code properly structured** (see 0.1): single-purpose files, named
  exports, no dead code, reuse over duplication.
- Server is authoritative: the client sends intent, never mutates game state.
- Do not modify the server, schema, or floorplan data in this milestone.
- Do not add runtime dependencies. Remove `phaser` after the cutover.
- One coordinate mapping only (Section 4).
- Do not add any gameplay rule, mechanic, or asset not listed here.

---

## 9. Build & Run

```bash
# from repo root
npm run install:all       # installs server + client deps
npm run dev:server        # terminal 1 — Colyseus on ws://localhost:2567
npm run dev:client        # terminal 2 — Vite on http://localhost:5173
# open multiple browser tabs: create a room in one, join by code in the others
```

Keep these scripts working. If the entry point changes, update `index.html` /
`main.ts` so `npm run dev:client` launches the 3D game directly (not the preview
harness).

---

## 10. Definition of Done (Manual Verification — No Automated Tests)

Confirm each by playing in browser tabs. This replaces, and must not become,
test code.

**Cutover**
- [ ] `npm run dev:client` launches the 3D game (not the Phaser build, not the
      preview harness).
- [ ] No file imports `phaser`; the dependency is removed; `scenes/`, `objects/`,
      `three/preview.ts`, `three-preview.html` are deleted.

**Multiplayer rendering**
- [ ] 4 tabs join one room by code; each sees all players in the 3D world.
- [ ] Local player moves immediately; remote players move smoothly (interpolated).
- [ ] A jail teleport snaps the affected player instantly in every tab (no glide).
- [ ] Every tab shows the same cash bundle count in each bedroom at all times.

**Core loop (all server-validated, just rendered here)**
- [ ] Pick up a bundle in the enemy bedroom -> bundle leaves the floor, appears
      as the carrier's carried indicator in all tabs.
- [ ] Cross own home threshold while carrying -> auto-deposit; a scored bundle
      appears stacked in your bedroom in all tabs.
- [ ] Get locked while carrying -> bundle returns to the enemy bedroom it came
      from; you are teleported to the correct basement.
- [ ] Rescue a jailed teammate in the basement within range -> they are freed.
- [ ] Steal a scored bundle from the enemy bedroom -> counts update in all tabs.

**HUD / flow**
- [ ] Timer, round number, context prompts, jail banner, countdown, and
      round-end / match-end overlays all display and update correctly.
- [ ] No numeric score is shown; score is readable only from bedroom stacks.

**Structure**
- [ ] Files match Section 5; each is single-purpose; no test files exist; no dead
      Phaser code remains.

---

## 11. Next Milestone (context only — do not build now)

Phase 3 turns the flat zone-rects into real multi-floor houses (stairs, windows,
multiple furnished rooms, backyard, basement as stacked levels) and extends the
server's zone model from 2D rects to simple 3D volumes. A separate PRD will
cover it.

---

*Phase 2 · Milestone C. Wire the existing 3D client to the existing Colyseus
server. Reuse everything already built. No tests. Keep it clean.*
