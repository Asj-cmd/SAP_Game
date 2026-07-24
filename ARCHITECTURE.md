# Cash Grab — Architecture & Modularity Map

A guide to how the code is structured, the **global knobs** that reshape the
whole game from one number, and exactly where each planned next step plugs in
(Rapier physics, Blender-MCP assets, deeper 3D, a possible Godot port, Steam
multiplayer + publish). Read this before a large change — it tells you the *one*
place to touch.

## Layout

```
server/            Colyseus, AUTHORITATIVE game logic. Renders nothing.
  src/zones.ts        World geometry + zone/floor lookup + bot pathing graph.
  src/rooms/GameRoom.ts  Rules, round/match flow, AI bots. (Tuning block up top.)
  src/schema/GameState.ts  Networked state (players, bundles, floor axis).
  src/index.ts        HTTP + WS transport; also serves the built client.
client/            Three.js, RENDERING + input only. Sends intent, never mutates rules.
  src/constants.ts    ALL client tunables (the control panel).
  src/assets.ts       Central model-URL registry (asset swap seam).
  src/geometry/floorplan.ts  Engine-agnostic world data — MIRROR of zones.ts.
  src/three/          The renderer: scene, camera, character, environment, HUD.
  src/three/world/    Procedural geometry (walls, roofs, stairs, windows, props).
assets/blender/    Headless bpy scripts that author the committed .glb models.
```

## The two layers (this is what makes a Godot port feasible)

- **Engine-agnostic core** — pure numbers, no Three.js: `server/src/zones.ts`,
  `client/src/geometry/floorplan.ts`, `client/src/three/world/HeightField.ts`,
  and all of `GameRoom.ts`. Zones, floors, distances, collision math, scoring,
  jail/rescue, bot AI — nothing here imports a renderer. **A Godot (or any) port
  reuses this logic as-is and only re-implements the rendering layer.**
- **Rendering layer** — everything else under `client/src/three/` + the HUD.
  Swappable without touching a single rule.

## Global knobs (change one number → everything readjusts)

| Knob | File | Effect |
|---|---|---|
| `WORLD_SCALE` | `constants.ts` **and** `zones.ts` | Scales the whole floor plan (x & y); speeds/ranges scale with it so balance is invariant. |
| `MAP_DEPTH_SCALE` | `constants.ts` **and** `zones.ts` (`YS`) | Squashes only the y-axis (room depth) — compact vs. roomy interiors. |
| `STORY_HEIGHT` | `constants.ts` | One vertical unit: wall height, floor rise, ceiling, roof, camera cap all derive from it. Client-only (server floor axis is discrete). |
| Speeds / action ranges | `constants.ts` (client) + top of `GameRoom.ts` (server) | Movement + pickup/lock/rescue distances. |
| Bot AI weights | top of `GameRoom.ts` (`BOT_*` block) | One labelled table = the AI's whole personality; a difficulty tier is a different table, never a logic edit. |

## The one manual coupling: the geometry SYNC CONTRACT

`client/src/geometry/floorplan.ts` is a **hand-kept mirror** of
`server/src/zones.ts` (same pre-scale numbers: `WALLS`, `CONNECTORS`,
`WORLD_SCALE`, `MAP_DEPTH_SCALE`/`YS`, zone boundaries, `getZoneAt`,
`resolveFloor`). They are separate because client (Vite/ESM) and server
(tsc/CommonJS) are separate packages. **If you change world geometry, change
both files identically.** (A future cleanup could hoist this into a shared
package; today the duplication is intentional and localized to these two files.)

## Floor model (the stacked town-house)

Each house stacks three floors on ONE (x,y) footprint, told apart by a discrete
networked `floor` (-1 basement / 0 living+garden+backyards / +1 two bedrooms).
`CONNECTORS` (staircases/ladders/cellar-steps) flip a player's floor as they
walk across them (`resolveFloor`); owner-sealed connectors are solid to the
owner and open to raiders. Height is `floor * STORY_HEIGHT`, ramped on a
connector (`HeightField.visualHeight`).

## Where each next step plugs in

- **Rapier physics (knockback / shove / ragdoll)** → the movement/collision
  seam. Today it's hand-rolled: `CharacterController` (client) + `moveBotWith
  collision`/`botHitsWall` (server) do circle-vs-AABB move-and-slide against
  `WALLS`/`CONNECTORS`. Introduce a physics world that consumes the same rect
  data; keep the server authoritative (simulate there, replicate impulses).
- **Blender-MCP assets** → `client/src/assets.ts` (URL registry) +
  `client/public/models/` + `assets/blender/*` (authoring scripts). Regenerate a
  `.glb`, drop it in `public/models/`, and only `assets.ts` changes if names do.
- **Deeper 3D world** → already Three.js under `client/src/three/`. New
  procedural geometry goes in `client/src/three/world/`; new floors are just a
  new `floor` value with a `ZONE_RECT` (all vertical math derives from
  `STORY_HEIGHT`).
- **Godot port** → reuse the engine-agnostic core (above) verbatim; re-implement
  only the rendering layer. The Colyseus protocol is transport-agnostic.
- **Steam multiplayer + publish** → networking is Colyseus (`server/src/index.ts`
  transport + the lobby/host flow in `GameRoom`). Steam integration replaces the
  matchmaking/transport entry points and the client bootstrap; game rules are
  untouched. Serving is single-port today (`index.ts` serves the built client).

## Standing rules (see CLAUDE.md)

Server is authoritative (client sends intent). No test files in the repo —
verify by build + a manual/ephemeral checklist. Keep files single-purpose and
new world geometry under `client/src/three/world/`.
