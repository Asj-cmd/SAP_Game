# Cash Grab — Project Memory (auto-loaded)

Third-person **3D chaotic multiplayer party game** for Steam. Two families raid
each other's houses to steal cash, jail intruders, rescue teammates. 2v2/3v3/4v4,
best-of-3. This branch (`claude/game-mvp-dev-pl5suo`) is the **code source of
truth**.

## Fast context — use the knowledge graph before re-reading the whole repo

A **graphify** knowledge graph of this codebase is committed at `graphify-out/`:
- `graphify-out/GRAPH_REPORT.md` — start here: architecture summary + suggested queries.
- `graphify-out/graph.json` — queryable graph (1500+ nodes). The `graphify` skill
  reads it on demand; or query from the shell:
  - `graphify explain "GameController"` · `graphify path "GameController" "GameRoom"`
- Keep it fresh after code changes: **`graphify update .`** (pure tree-sitter, no
  API cost). If the `graphify` binary is missing in this session, install it once:
  `uv tool install graphifyy` (or `pip install graphifyy`).
- Built from commit `7ee4c0db`; compare with `git rev-parse HEAD` to spot staleness.

## Status: Phases 1–3 done · Phase 4 (Characters & Chaos) next

- **Server** (`server/`, Colyseus, authoritative): full game logic + REST
  (`/create-room`, `/rooms/:code`, `/health`) and serves the built client on one
  port. 2D zone model (`server/src/zones.ts`, `getZoneAt(x,y)`) — **flat plane, no
  height axis**.
- **Client** (`client/`, Three.js vanilla): `three/GameController.ts` orchestrates
  local movement (20 Hz `move`), remote sync, cash view, HUD, and the 5-way SPACE
  action. FPS mouse-look chase cam. `three/world/` dresses the flat plane as houses
  (roofs w/ reveal, see-through windows, instanced props, ACES + soft shadows).
- **Assets**: headless Blender bpy scripts (`assets/blender/build_*.py`) →
  committed `.glb`. Phase 4 adds **Blender MCP** for interactive character/world
  authoring; export to committed `.glb` so the runtime needs no Blender to play.

## Standing rules (do not break)

1. **No test code / test files / test functions / automated test or QA harnesses.**
   Verify by building + a manual checklist. Overrides any skill's default QA.
2. **Keep code properly structured** — single-purpose files, named exports, no dead
   code; new world code under `client/src/three/world/`.
3. **Server is authoritative** — client sends intent, never mutates game state.
4. **One coordinate mapping** — server `(x,y)` == Three `(x,z)`, Three `y` = up.
5. Don't change `server/`, `zones.ts`, or `geometry/floorplan.ts` numbers unless
   the current phase explicitly calls for it.

## Planning docs (on branch `claude/cash-grab-game-skills-qxd4ne`)

`prds/PROJECT_STATUS_AND_HANDOFF.md`, `prds/MASTER_PLAN.md`, and the per-phase
PRDs live on the planning branch. The next build task is the **Phase 4** PRD
(original funny/offbeat characters via Blender MCP + Rapier physics chaos).

## Build & run

```bash
npm run install:all      # once
npm run dev:server       # terminal 1 (Colyseus :2567)
npm run dev:client       # terminal 2 (Vite :5173)
# or one-URL:  npm run play   (builds client, server serves it on :2567)
```
