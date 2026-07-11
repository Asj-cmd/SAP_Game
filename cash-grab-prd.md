# Cash Grab — Phase 1 MVP: Product Requirements Document
## For Claude Code

---

## 0. Read This First

This is a complete specification to build a 2v2 multiplayer side-scrolling 2D browser game called **Cash Grab**. Two families of 2 players each compete to steal cash bundles from each other's master bedroom. Build this exactly as specified. Do not add features not listed. Do not simplify mechanics. Stop and ask before making any architectural decision not covered here.

---

## 1. Tech Stack (Non-Negotiable)

| Layer | Tool | Why |
|---|---|---|
| Game engine | **Phaser 3** (v3.60+) | Browser-native 2D, excellent physics, free |
| Multiplayer server | **Colyseus 0.15** | Free, open-source, built for games |
| Server runtime | **Node.js 18+** | Required by Colyseus |
| State schema | **@colyseus/schema** | Typed state sync, comes with Colyseus |
| Transport | **WebSocket** (via Colyseus) | Built-in |
| Frontend build | **Vite** | Fast, simple, no config needed |
| Language | **TypeScript** throughout | Type safety for game state is critical |

Do NOT use: Unity, React, Three.js, Socket.io standalone, or any physics engine other than Phaser's built-in Arcade Physics.

---

## 2. Project Structure

```
cash-grab/
├── client/                   # Phaser 3 frontend
│   ├── src/
│   │   ├── main.ts           # Phaser game config entry point
│   │   ├── scenes/
│   │   │   ├── BootScene.ts      # Preload assets
│   │   │   ├── LobbyScene.ts     # Room join / player name entry
│   │   │   ├── GameScene.ts      # Main game loop
│   │   │   └── UIScene.ts        # HUD overlay (runs parallel to GameScene)
│   │   ├── objects/
│   │   │   ├── Player.ts         # Player sprite + movement
│   │   │   ├── CashBundle.ts     # Cash bundle sprite
│   │   │   └── Zone.ts           # Zone collision areas
│   │   ├── network/
│   │   │   └── ColyseusClient.ts # All server communication
│   │   └── constants.ts          # World dimensions, speeds, timers
│   ├── index.html
│   ├── vite.config.ts
│   └── package.json
│
├── server/                   # Colyseus game server
│   ├── src/
│   │   ├── index.ts              # Express + Colyseus server bootstrap
│   │   ├── rooms/
│   │   │   └── GameRoom.ts       # All game logic lives here
│   │   └── schema/
│   │       └── GameState.ts      # Colyseus schema definitions
│   ├── tsconfig.json
│   └── package.json
│
└── README.md
```

---

## 3. World Layout

### 3.1 World Dimensions

```
Total world width:  3200px
Total world height:  720px (ground floor) + 300px (underground) = do NOT make it taller

Ground floor Y range:   0 to 720
Underground Y range:  720 to 1020
```

The camera follows the player (Phaser camera bounds = world bounds). The world is wider than the viewport — the camera scrolls horizontally and vertically as the player moves.

### 3.2 Zone Map (pixel coordinates)

```
GROUND FLOOR (Y: 0–720):
|-- Boundary wall --|-- TEAM B MASTER BEDROOM --|-- TEAM B LIVING ROOM --|-- GARDEN --|-- TEAM A LIVING ROOM --|-- TEAM A MASTER BEDROOM --|-- Boundary wall --|
  X: 0               X: 60–500                    X: 500–980                X: 980–2220  X: 2220–2700              X: 2700–3140                 X: 3140–3200

UNDERGROUND (Y: 720–1020):
|-- Boundary wall --|-- BASEMENT B --|-- (dirt, impassable) --|-- BASEMENT A --|-- Boundary wall --|
  X: 0               X: 60–980         X: 980–2220               X: 2220–3140      X: 3140–3200
```

### 3.3 Entry Points

Each entry point is a gap/door in the wall that players can physically walk through. Implement as open passages (no wall tile blocking them).

| Entry Point | Location | Notes |
|---|---|---|
| Master bedroom B window | Top wall, X: 200–260, Y: 0 (top boundary) | Jump up to reach — place a platform |
| Master bedroom B door | Right wall of master bedroom, X: 498–502, Y: 560–660 | Internal door between master & living |
| Team B main door | Left outer wall, X: 60, Y: 580–680 | Enters living room B from outside left |
| Team B side door | Right wall of living room, X: 978–982, Y: 580–680 | Enters from garden |
| Garden garage/main entry | Floor of garden, X: 1450–1750, Y: 718–722 | Stairs down — connects garden to underground passage. NO underground passage between basements. This is only a staircase entry from garden ground level down to garden underground level, which is a dead zone with no rooms |
| Team A side door | Left wall of living room A, X: 2218–2222, Y: 580–680 | Enters from garden |
| Team A main door | Right outer wall, X: 3140, Y: 580–680 | Enters living room A from outside right |
| Master bedroom A door | Left wall of master bedroom A, X: 2698–2702, Y: 560–660 | Internal door |
| Master bedroom A window | Top wall, X: 2940–3000, Y: 0 | Jump platform to reach |
| Basement B external entry | Left outer wall, X: 60, Y: 820–920 | Underground, direct entry to Basement B |
| Basement A external entry | Right outer wall, X: 3140, Y: 820–920 | Underground, direct entry to Basement A |
| Stairs from living B to Basement B | Floor of living room B, X: 700–800, Y: 718–722 | Stairs down |
| Stairs from living A to Basement A | Floor of living room A, X: 2400–2500, Y: 718–722 | Stairs down |

**Important:** The two basements are NOT connected underground. The only underground access is via the stairs from each team's living room, and the external wall entries.

---

## 4. Game State (Colyseus Schema)

Define all state in `server/src/schema/GameState.ts`. Use `@colyseus/schema` decorators exactly.

```typescript
// GameState.ts
import { Schema, Context, type, MapSchema, ArraySchema } from "@colyseus/schema";

const { defineTypes } = Context;

export class PlayerState extends Schema {
  @type("string")  id: string = "";
  @type("string")  name: string = "";
  @type("string")  team: string = "";        // "A" or "B"
  @type("number")  x: number = 0;
  @type("number")  y: number = 0;
  @type("boolean") isCarryingCash: boolean = false;
  @type("boolean") isJailed: boolean = false;
  @type("number")  jailTimer: number = 0;    // seconds remaining, counts down from 60
  @type("boolean") connected: boolean = true;
}

export class CashBundleState extends Schema {
  @type("string")  id: string = "";
  @type("number")  x: number = 0;
  @type("number")  y: number = 0;
  @type("string")  location: string = "";    // "bedroomA" | "bedroomB" | "carried:{playerId}" | "scored:{team}"
  @type("boolean") isScored: boolean = false;  // true = sitting in a master bedroom as a score
}

export class GameState extends Schema {
  @type("string")  phase: string = "waiting";  // "waiting" | "countdown" | "playing" | "roundEnd" | "matchEnd"
  @type("number")  roundTimer: number = 300;    // seconds, counts down from 300
  @type("number")  countdown: number = 3;
  @type("number")  scoreA: number = 0;
  @type("number")  scoreB: number = 0;
  @type("number")  roundNumber: number = 1;
  @type("number")  winsA: number = 0;
  @type("number")  winsB: number = 0;
  @type("string")  roundWinner: string = "";    // "A" | "B" | ""
  @type("string")  matchWinner: string = "";    // "A" | "B" | ""
  @type({ map: PlayerState })    players: MapSchema<PlayerState> = new MapSchema<PlayerState>();
  @type({ map: CashBundleState }) cashBundles: MapSchema<CashBundleState> = new MapSchema<CashBundleState>();
}
```

---

## 5. Server Logic (GameRoom.ts)

### 5.1 Room Setup

```typescript
// Key room configuration
maxClients = 4;
// Room is private (join by room code)
// Do not allow more than 4 clients
// Assign first 2 joiners to Team B, next 2 to Team A
```

### 5.2 Cash Bundle Initialisation

On round start, create exactly 6 CashBundleState objects:

- Bundles b1, b2, b3 → `location: "bedroomB"`, positioned at 3 fixed spots inside the master bedroom B floor
- Bundles a1, a2, a3 → `location: "bedroomA"`, positioned at 3 fixed spots inside the master bedroom A floor

Scored bundles (collected by opponent and brought home) also sit in the master bedroom — they stack visually in the bedroom, same location. The `isScored` flag distinguishes "original bundle in enemy's bedroom" vs "scored bundle in your bedroom."

### 5.3 Message Handlers

The server handles these messages from clients. All game logic lives SERVER-SIDE — clients only send input, never modify state directly.

```
"move"          → { x, y, vx, vy }    Update player position
"pickupCash"    → { bundleId }         Player picks up a bundle
"depositCash"   → { bundleId }         Player crosses own threshold while carrying
"lockPlayer"    → { targetId }         Player locks an opponent
"rescuePlayer"  → { targetId }         Player touches a jailed teammate
"stealScored"   → { bundleId }         Player picks up an already-scored bundle from enemy bedroom
```

### 5.4 Core Logic Rules — Implement Exactly

**PICKUP:**
- Validate: player is inside enemy master bedroom zone
- Validate: bundle is present there and not already carried
- Validate: player is NOT already carrying a bundle
- Validate: player is NOT jailed
- Set bundle `location = "carried:{playerId}"`, `isCarryingCash = true` on player

**DEPOSIT:**
- Validate: player is carrying a bundle
- Validate: player has crossed their OWN home threshold (inside own living room or own master bedroom)
- Move bundle to own master bedroom: `location = "scored:{team}"`, `isScored = true`
- Set player `isCarryingCash = false`
- Increment team score (scoreA or scoreB)
- Check win condition: if score >= 5, end round

**LOCK:**
- Validate: locking player is inside their OWN living room or own master bedroom (not garden, not enemy home)
- Validate: target player is also inside the locking player's home (same zone)
- Validate: locking player and target player are on DIFFERENT teams
- If target is carrying a bundle: immediately return that bundle to the enemy master bedroom it came from. Set `location` back to "bedroomA" or "bedroomB" (whichever is the target's own team's bedroom — i.e. the bundle goes back to the team that originally owned it)
- Set target `isJailed = true`, `jailTimer = 60`
- Teleport target to jail position (Basement B or Basement A depending on whose home they were caught in)
- Set target `isCarryingCash = false`

**RESCUE:**
- Validate: rescuing player is in the correct basement (must be on SAME team as jailed player)
- Validate: target player IS jailed
- Set target `isJailed = false`, `jailTimer = 0`
- Do NOT teleport — target stays in basement and can walk out

**AUTO-RELEASE (server tick):**
- Every second, decrement `jailTimer` for all jailed players
- When `jailTimer` reaches 0: set `isJailed = false`. Player stays in basement and walks out normally. No debuff.

**STEAL-BACK:**
- A scored bundle (isScored = true) sitting in the enemy master bedroom CAN be picked up by an invader
- Same flow as PICKUP — validate player is in the enemy bedroom, pick it up, carry it, deposit it
- On deposit: the score for the original team drops by 1, the score for the stealing team increases by 1
- Check win condition after every score change

**ROUND TIMER:**
- Server ticks every 1 second
- Decrement `roundTimer` by 1 each tick
- When `roundTimer` reaches 0: end round, team with higher score wins. Tie = no round winner (replay that round — do not advance round number)

**WIN CONDITION:**
- First team to hold 5 cash bundles simultaneously in their master bedroom wins the round
- Best of 3 rounds — first to 2 round wins wins the match
- On round end: reset all cash bundles to starting positions, reset all players to spawn points, increment roundNumber, start 3-second countdown

**DEPOSIT THRESHOLD — critical logic:**
- Team B players: crossing from the garden into living room B (X < 980 from garden direction) triggers deposit
- Team A players: crossing from the garden into living room A (X > 2220 from garden direction) triggers deposit
- The deposit fires the moment the player's X coordinate crosses the home threshold while carrying cash
- Do not wait for the player to reach the master bedroom — deposit fires at home entry

### 5.5 Spawn Points

```
Team B spawn 1: x=600, y=620  (inside living room B)
Team B spawn 2: x=750, y=620
Team A spawn 1: x=2450, y=620 (inside living room A)
Team A spawn 2: x=2600, y=620

Jail positions:
Basement B (holds Team A prisoners): x=400, y=880
Basement A (holds Team B prisoners): x=2800, y=880
```

---

## 6. Client — Phaser 3 Scenes

### 6.1 BootScene

- Load all assets (spritesheets, tilemaps, audio)
- Transition to LobbyScene when done

### 6.2 LobbyScene

- Simple form: text input for player name + "Create Room" button and "Join Room" (with room code input)
- On "Create Room": connect to Colyseus, create a room, display the 4-character room code
- On "Join Room": connect to Colyseus, join the specified room
- Show a waiting screen: "Waiting for players... (X/4 connected)"
- When 4 players are connected: server sets phase to "countdown", client transitions to GameScene

### 6.3 GameScene

This is the main scene. It renders the world and handles input.

**World rendering:**
- Use Phaser's TilemapLayer OR draw zones as colored rectangles (rectangles are fine for MVP)
- Zone colors:
  - Master bedrooms: warm orange fill `#F0997B` with label
  - Living rooms: blue fill `#B5D4F4` with label
  - Garden: green fill `#EAF3DE`
  - Basements: gray fill `#B4B2A9`
  - Ground: brown `#8B6914` line
  - Sky: light blue `#D6EEFF`
  - Underground dirt: dark brown `#6B4423`
- Draw simple rectangle "house" outlines in dark stroke
- Mark all entry points as gaps in the walls (literally no wall tiles/rects at entry point coordinates)

**Player rendering:**
- Simple stick-figure style: circle head (radius 14px) + rectangle body (12px × 22px) + two lines for legs
- All players look IDENTICAL in shape and size
- Team B players: rendered in color `#E85D24` (orange-red)
- Team A players: rendered in color `#185FA5` (blue)
- When carrying cash: render a small yellow rectangle above the player head
- When jailed: render player with 50% opacity and a small lock icon above head (draw as a simple rectangle with a half-circle on top)
- Player name label floats above head, 10px white text with dark stroke for readability

**Camera:**
- Camera follows the LOCAL player (the one you control)
- World bounds: 0, 0, 3200, 1020
- Camera bounds: same
- Deadzone: 100px horizontal, 80px vertical (so the camera doesn't always snap to center)

**Controls (keyboard):**
```
WASD or Arrow keys  →  Move (left/right = horizontal, up/W = jump)
SPACE               →  Action button (context-sensitive — see below)
```

**Action button (SPACE) context logic — client side determines what action to send:**
1. If NOT carrying cash AND inside enemy master bedroom AND a bundle is nearby → send "pickupCash"
2. If carrying cash AND just crossed own home threshold → auto-fires "depositCash" (no button press needed — fire automatically when threshold detected)
3. If inside OWN home AND a non-teammate is within 60px → send "lockPlayer" with nearest enemy's id
4. If inside basement AND a jailed teammate is within 60px → send "rescuePlayer" with teammate's id
5. If inside enemy master bedroom AND a SCORED bundle is there → send "stealScored"

Show a contextual button prompt above the player when SPACE would do something: "SPACE: Pick up cash", "SPACE: Lock [name]", "SPACE: Rescue [name]". Do not show the prompt if SPACE has no action in current context.

**Physics:**
- Use Phaser Arcade Physics
- Gravity: 800
- Player max speed: 220px/s horizontal, jump velocity: -520
- Players collide with the ground layer and all wall edges
- Players pass through entry point gaps (doors/windows) freely — no collision there

**Carrying cash slows player:**
- When carrying a bundle: max speed = 160px/s (not 220)

### 6.4 UIScene

Runs simultaneously with GameScene (additive scene). Renders UI overlay.

**Minimal HUD — only these elements:**
- Top-left: round timer (MM:SS format), large enough to read (36px)
- Top-left below timer: "Round X of 3" in smaller text
- Top-center: nothing (no score tracker in HUD — players must look at master bedroom)
- Bottom-center: control hints ("WASD: Move | SPACE: Action")
- When jailed: show "JAILED — [Xsec] | Teammate can rescue you | Auto-release in [X]s" in the center of the screen for the jailed player only (use player's own jail timer from state)
- On round end: large overlay "ROUND X WINNER: TEAM [A/B]!" with "Next round in 3..." or "TEAM [A/B] WINS THE MATCH!" if match is over

**Score visibility:**
- Score is NOT shown in the HUD
- The only way to know the score is to look at the master bedrooms — each bundle deposited there appears as a visible cash sprite in the bedroom
- In the master bedroom, render the cash bundles as stacked/arranged yellow rectangles so players can count them

### 6.5 Network Reconciliation

- Client sends player position 20 times per second (every 50ms) via "move" message
- On receiving server state update, smoothly interpolate OTHER players' positions (use Phaser's lerp, factor 0.2)
- DO NOT interpolate the local player — local player movement is immediate, server is authoritative for everything except position rendering
- If server teleports a player (jail), snap to new position immediately (no lerp)

---

## 7. Server Bootstrap (index.ts)

```typescript
import { Server } from "colyseus";
import { WebSocketTransport } from "@colyseus/ws-transport";
import express from "express";
import { createServer } from "http";
import { GameRoom } from "./rooms/GameRoom";

const app = express();
const httpServer = createServer(app);

const gameServer = new Server({
  transport: new WebSocketTransport({ server: httpServer }),
});

gameServer.define("game_room", GameRoom);

const PORT = Number(process.env.PORT) || 2567;
httpServer.listen(PORT, () => {
  console.log(`Cash Grab server running on port ${PORT}`);
});
```

---

## 8. Critical Logic Verification Checklist

Before considering any feature "done", verify these specific cases. Test each one:

### Cash Bundle Logic
- [ ] Player B picks up bundle from master bedroom A → bundle disappears from bedroom A, appears above player B's head
- [ ] Player B carries bundle and crosses into Team B's living room (X < 980) → bundle auto-deposits to master bedroom B, score B increments, bundle appears in bedroom B
- [ ] Player B is carrying a bundle and gets locked → bundle IMMEDIATELY returns to master bedroom A (where it came from), not to bedroom B
- [ ] Team A player walks into master bedroom B and picks up a SCORED bundle → score B decrements, bundle is now carried by Team A player
- [ ] Score never goes below 0
- [ ] Score never goes above 5 (win triggers at exactly 5)

### Lock / Jail Logic
- [ ] Player can only be locked when they are physically inside the enemy's living room or master bedroom zone (not in the garden, not outside)
- [ ] The Lock button prompt only appears when an enemy is within 60px AND you are in your own home
- [ ] Jailed player cannot move (velocity set to 0, physics disabled for that player)
- [ ] Jailed player is teleported to the correct basement (Team A players go to Basement B, Team B players go to Basement A)
- [ ] A teammate entering the basement and pressing SPACE within 60px of the jailed player frees them
- [ ] Auto-release fires at exactly 60 seconds (no debuff, player moves normally)
- [ ] Friendly fire is impossible: Lock button never appears next to a teammate

### Zone Logic
- [ ] Master bedroom can be entered by opponent players but NOT by own team players — own team players collide with an invisible wall blocking the master bedroom door/window on their side
- [ ] The garden is truly neutral: no locking possible there
- [ ] Players cannot move beyond world bounds (X < 60 or X > 3140)
- [ ] Underground basements are only reachable via stairs or external entry points — no jumping down through the ground elsewhere

### Win Condition
- [ ] Win condition checked after EVERY deposit and EVERY steal-back
- [ ] Round ends immediately when any team hits 5 — do not wait for timer
- [ ] Tie at timer expiry: no round winner, round replays (timer resets, players and cash reset, round number stays the same)
- [ ] Match ends after 2 round wins — does not continue to third round if one team wins rounds 1 and 2

### Multiplayer Sync
- [ ] All 4 clients see the same cash bundle count in each bedroom at all times
- [ ] Player positions sync across all clients with <100ms perceived lag on localhost
- [ ] Disconnecting player is removed from the game state cleanly; remaining players can continue

---

## 9. Build & Run Instructions to Include in README

```bash
# Install dependencies
cd server && npm install
cd ../client && npm install

# Run server (in one terminal)
cd server && npm run dev
# Server starts at ws://localhost:2567

# Run client (in another terminal)
cd client && npm run dev
# Client starts at http://localhost:5173

# Open 4 browser tabs, create a room in the first, join with the room code in the other 3
```

---

## 10. What Is Explicitly NOT in Phase 1

Do not build these. They will be added in a later phase:

- Sound effects or music
- Sprite art / character animations (stick figures only)
- Mobile / touch controls
- Spectator mode
- Chat
- Persistent accounts or stats
- The alarm mechanic
- Wall climbing
- Any power-ups or special abilities
- AI bots for missing players

---

## 11. Definition of Done for Phase 1

The build is complete when all of the following are true:

1. Four browser tabs on localhost can join the same game room using a room code
2. All players can move, jump, and interact with each entry point
3. Cash bundles can be picked up, carried (with slowdown), and deposited
4. Locking works: only inside own home, only on enemies, bundle returns to origin
5. Jailing works: player teleported to basement, jailTimer counts down visibly
6. Rescue works: teammate frees jailed player in basement
7. Auto-release works at 60 seconds exactly
8. Steal-back of scored bundles works correctly
9. Win condition fires at 5 bundles
10. Round resets correctly (3-second countdown, all positions and bundles reset)
11. Best-of-3 match tracking works
12. All 12 items in Section 8 checklist pass

---

*Cash Grab MVP — Phase 1. Build server first, verify schema, then build client scenes in order: Boot → Lobby → Game → UI.*
