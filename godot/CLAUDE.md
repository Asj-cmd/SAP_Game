# Cash Grab (Godot) — working rules

**Start with `PROJECT_MEMORY.md`.** It carries where the project stands, the live
queue, the working method, and the review errors worth not repeating — and it
maps the other documents, including which one is superseded.

Then `ARCHITECTURE.md` before any structural work; it is the specification this
project is reviewed against. `DESIGN_DIRECTION.md` before proposing any gameplay
change — most obvious improvements have already been argued once.

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

## Looking at the screen

Visual work is not done until a frame has been viewed. Not "the tests pass",
not "the scene tree looks right" — a frame, opened and looked at.

Two renderer regressions shipped past a green suite because nothing in the loop
ever looked at the window. Both times the rules were correct, the entities were
where they should be, and the screen was blank. No test in the policy above can
catch that, and none should be written to try: the failure lives between a
correct 3D scene and the window, which is exactly the region tests are barred
from.

```bash
godot --path godot -- --capture --capture-delay=2.5 --capture-path=user://shot.png
godot --path godot -- --split --capture     # the debug split-screen
```

Writes a PNG, prints its absolute path plus where the camera was, and exits.
`[F12]` does the same from inside a running game. `--capture-delay` exists
because a frame grabbed at t=0 shows an empty scene and proves nothing.

Report what the frame showed, not what it should have shown.

## Conventions

- Static typing is mandatory. An untyped declaration is a defect.
- `sim/` may not reference `game/`, `ui/`, or `net/`. Dependencies point one way.
- If a change can be expressed as data, it belongs in `content/*.tres`, not code.
- The headless runner must work at all times. It is the cheapest correctness
  signal available and it must never be allowed to rot.
- Prefer finishing one system to green over starting the next.
