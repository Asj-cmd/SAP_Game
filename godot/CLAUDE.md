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
godot --path godot -- --capture --capture-clean   # no on-screen text, world only
```

To judge what the PLAYER sees somewhere, stand a stand-in body there and shoot
through the real chase rig (spring arm, pitch, body fade) rather than a free camera:

```bash
godot --path godot -- --capture-chase=880,300,1250 --capture-facing=880,300,400 --capture-pitch=-12
node autobuild/verify.mjs --frames-only --views=cam_   # the cam_* views in views.json
```

To check that a whole session PLAYS through the real input path (menu click,
WASD + mouse turn, jump, crouch, grab, throw, deposit, seize, free, round and
match results, Enter rematch, F10), run the pilot. It injects keys and mouse
events and writes frames plus a report to `user://pilot*/`:

```bash
godot --path godot -- --pilot --pilot-speed=2             # solo, ~8 min
godot --path godot -- --pilot=host   &   godot --path godot -- --pilot=guest
```

To see what the renderer does for a view (draw calls, triangles, objects, and
frame/GPU time on this machine's GPU), against the budgets in the root `STYLE.md`:

```bash
godot --path godot -- --capture-at=... --capture-stats        # counters for the shot
godot --path godot -- --capture-at=... --capture-timing=120   # plus 120 uncapped frames timed
node autobuild/render_stats.mjs [--views=room_]               # every view, one table
```

Counters are zero under `--headless`; measure windowed.

To compare looks, swap the whole ArtTheme and stand drawn-only figures in the shot:

```bash
godot --path godot -- --art-theme=res://art/theme/slice_b.tres --capture-figure=780,660,720,40
node autobuild/style_slice.mjs [--variants=a,b,c,pick] [--import]   # P1-5 slice
node autobuild/figure_bake.mjs --body=male|female    # re-bake a figure from the zips
node autobuild/family_lineup.mjs [--import]          # the six family members, front/side/back, 20 m, 40 m
godot --path godot -- --capture-figure=2700,300,1000,180,younger_girl   # one member by id
godot --path godot -- --capture-figure=2700,300,1000,-90,,walk@0.4      # held in a clip of the animation set
node autobuild/anim_sheet.mjs [--clips=walk,throw] [--member=younger_boy]   # contact sheets per clip
```

To see the animation DRIVER (FigureAnimator, P2-3) in live play, follow one body
with a free camera beside it; it writes one contact sheet and prints the clip each
cell shows. Godot is launched through node here (`autobuild/run_game.mjs`):

```bash
node autobuild/run_game.mjs --timeout=300 -- --capture-follow=team_a:1,16,2.5,side,380 \
    --capture-delay=25 --capture-clean --capture-path=C:/abs/path/a1.png   # -> a1_sheet.png
```

The debug HUD is hidden by default (`[F1]` toggles it, `--debug-hud` starts
with it on); `--capture-clean` also hides the hint line and banner.

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

## Autonomous mode (autobuild)

When running under `autobuild/loop.mjs` this file is amended as follows. `DECISIONS.md` and `PLAN.md` at the repo root govern.

- **Failure loop cap:** two fix attempts, then log in `BLOCKED.md` and move to the next task; do not stop the session.
- **Tests:** unchanged policy (sim decisions only). Plus `node autobuild/verify.mjs`, which pins per-suite check counts so a suite cannot quietly shrink.
- **No MCP servers** in unattended runs. Use the Godot command line, headless runner and `--capture`.
- **Looking at the screen is mandatory for visual tasks** and the description goes in `PROGRESS.md`.
- **Art never changes collision/zones/tuning** unless the task says so.
