# Cash Grab (Godot) — working rules

Read `ARCHITECTURE.md` before any structural work. It is the specification this
project is reviewed against.

## Testing policy

This supersedes the repo-root "no test code" rule, which applies to the legacy
Three.js client only.

Tests exist to catch rule regressions cheaply. They are not a deliverable, not a
coverage target, and not a substitute for looking at the game.

**Test only this**

- `sim/` — and within it, only logic that contains a *decision*: score
  derivation, capture/release/timeout, win and round-end conditions, command
  validation, state-machine transitions.

**Never test**

- `game/`, `ui/`, presentation, camera, VFX, audio. These are verified by eye.
- Data classes, getters, constants, resource loading.
- Godot engine behaviour.
- Anything whose test would merely restate the implementation.

**When to write them.** Once, when a system is complete. Not per function, not
per edit, not speculatively ahead of the code.

**When to run them.** Before committing a change that touches `sim/`. Not after
every file write. Not at all for edits confined to presentation.

**Failure loop cap — the important one.** If a test fails, you get at most
**two** fix attempts. Then stop and report what failed, what you tried, and your
best diagnosis. Do not keep iterating unprompted. An agent looping on a red test
is the largest single source of wasted budget on this project.

**Style.** Table-driven: one test function iterating a list of cases beats a
dozen near-identical functions, and costs a fraction of the tokens to write,
read, and re-run.

## Conventions

- Static typing is mandatory. An untyped declaration is a defect.
- `sim/` may not reference `game/`, `ui/`, or `net/`. Dependencies point one way.
- If a change can be expressed as data, it belongs in `content/*.tres`, not code.
- The headless runner must work at all times. It is the cheapest correctness
  signal available and it must never be allowed to rot.
- Prefer finishing one system to green over starting the next.
