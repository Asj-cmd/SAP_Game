# Cash Grab — Project Memory (auto-loaded)

Third-person **3D chaotic multiplayer party game** for Steam. Two families raid
each other's houses to steal cash, jail intruders, rescue teammates. 2v2/3v3/4v4,
best-of-3.

## The game is the Godot project in `godot/`

**Source of truth: `godot/`** — Godot 4.7, Compatibility renderer, typed
GDScript, host-authoritative over a session/transport interface (DECISIONS.md D1,
D5). Start with `godot/CLAUDE.md` (testing policy, look-at-the-frame rule,
conventions) and `godot/PROJECT_MEMORY.md` (where things stand, working method).

The autonomous build is run from the repo root:

| File | What |
|---|---|
| `DECISIONS.md` | How to decide without asking; settled decisions D1–D10; decision log |
| `PLAN.md` | The task list (take the first unchecked, unblocked task) |
| `PROGRESS.md` | Newest-first log of what each session did and saw |
| `BLOCKED.md` | Things only the user can do |
| `autobuild/README.md` | The loop, `GODOT_BIN`, the tools |

```bash
node autobuild/verify.mjs            # the gate: tests, symmetry, bot match, tick budget, network
node autobuild/verify.mjs --quick    # tests + symmetry only
node autobuild/verify.mjs --frames   # also capture the views in autobuild/views.json
```

Godot is run through `GODOT_BIN` on the command line, never an editor or MCP.

## Legacy: `client/` and `server/` (Three.js + Colyseus)

The earlier Three.js client and Colyseus server are **legacy**: kept for
reference, not developed, not deleted. Rules that apply to them only:

1. **No test code / test files / automated test harnesses** in `client/` and
   `server/`. This does **not** apply to `godot/`, which has its own narrower
   testing policy in `godot/CLAUDE.md`.
2. Don't change `server/`, `zones.ts` or `geometry/floorplan.ts`.

The **graphify** knowledge graph in `graphify-out/` was built from the legacy
code (commit `7ee4c0db`) and does not cover `godot/`.

```bash
npm run install:all && npm run play   # legacy build, serves on :2567
```
