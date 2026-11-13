# Style

Art direction (DECISIONS.md D2, deadpan) is written by P1-3. This file starts with the
**render budgets** (P1-1), because every art task after it is checked against them.

## Budgets (P1-1)

**Machine:** the dev laptop's GeForce GT 730M (Kepler, 64-bit DDR3), OpenGL 3.3 driver
425.91, Godot 4.7.1 **Compatibility** renderer (D1, D6), window 1600×900. If the game holds
these numbers there, it runs on nearly any Steam PC.

**Instrument:** `node autobuild/render_stats.mjs [--views=prefix] [--timing=N]` shoots every
view in `autobuild/views.json` windowed through the real game and prints, per view, the
renderer's own counters for that frame (draw calls, triangles, objects) and N uncapped frames of
timing (median / p95 frame interval, GPU time of the seat viewport). `verify.mjs --frames` prints
the counters under each shot. The limits below are also in `autobuild/render_budget.json`, which
the runner checks (not yet a verify gate; P3-6 makes it one). Counters are zero under
`--headless`, and frame time from a software renderer means nothing: measure windowed, here.

**Target: 60 fps (16.7 ms) at 4v4 with bots, in the worst view**, with the 30 Hz simulation
running on the same main thread. The simulation's bad ticks already put the frame p95 near
16 ms on their own (see the baseline), so rendering has to leave room, not fill the frame.

Per view (any view in `views.json`; `render_budget.json` holds the same numbers):

| What | Budget | Baseline max | Why this number |
|---|---|---|---|
| Draw calls | **≤ 1000** | 526 | The seat's CPU render time is ~4.5 µs a draw (2.35 ms at 526), so 1000 ≈ 4.5 ms of the main thread |
| Triangles in view | **≤ 300k** | 27k | GPU time barely moves with triangles today (2.3 ms empty view → 2.9 ms at 27k); 300k keeps a Kepler laptop part well clear of vertex-bound |
| Seat GPU time, median | **≤ 9 ms** | 5.4 | 2.3 ms is the floor (sky + fog + fill at 1600×900); 9 leaves half the 60 fps frame for it |
| Frame interval, median (vsync off) | **≤ 12 ms** | 8.0 | Everything a frame costs incl. sim and HUD |
| Frame interval, p95 | target ≤ 16.7 ms, recorded, not budgeted | 16.0 | Dominated by simulation ticks with bots (P0-2b), not rendering |
| Texture memory | **≤ 256 MB** | 24 | The GT 730M has 1–2 GB of slow DDR3; leave most of it alone |
| Video memory, total | **≤ 512 MB** | 50 | Same |

Per asset (so the per-view numbers hold when a room is full of them):

| Asset | Triangles | Materials | Textures |
|---|---|---|---|
| Family member (D10 base, decimated) | **≤ 6k** (8 on screen at 4v4 ≈ 48k) | 1 (theme) | ≤ 512², or none (flat theme colour) |
| Furniture / prop | ≤ 2k typical, **≤ 6k** hero (vault, safe, jail door) | 1, at most 2 | ≤ 512² default, ≤ 1024² for big surfaces |
| Cash bundle | ≤ 500 | 1 | ≤ 256² |
| One furnished room, total dressing | ≤ 40k | — | — |
| One room, dressing draw calls | ≤ 60 | — | — |

Textures are imported VRAM-compressed; mipmaps on.

### Rules that follow from the renderer

- **A draw call per mesh surface per object.** Omni/spot lights are cheap only up to
  Compatibility's per-object light limit (`rendering/limits/opengl/max_lights_per_object`);
  shadowed ones are drawn as additional passes. Not yet measured here: light a room with the
  sun/fill plus **at most two** omni/spot lights touching any one object, and run
  `render_stats.mjs --views=room_` before and after the lights go in (P1-4, P3-5).
- **Shadows draw the scene again.** `shadow_draw_calls` counts it separately. One shadowed
  directional light at most (P3-5 decides whether any); no shadowed omni/spot lights.
- **Merge static dressing.** The blockout draws every box as its own object (one draw each);
  art meshes should be merged per room and material, or instanced (MultiMesh) when repeated.
- **One material per mesh where possible**, shared through the ArtTheme (P1-4): a second
  surface is a second draw call.
- **No Forward+-only features** (D6): no SSAO, SSR, SDFGI, volumetric fog, glow-heavy post.
  Fog, procedural sky, directional lights, vertex/fragment shaders on the theme materials are fine.

### What the baseline measured (2026-11-13, grey blockout, 3v3 with bots)

`node autobuild/render_stats.mjs --timing=120`, 45 views, all within budget:

- **Draw calls:** median 168, max 526 (`lot_overview`, `approach_from_south`, `ext_a_west`: the
  whole lot in view). Draw calls = objects: every blockout box is its own mesh. Inside a room
  95–167 (jail, halls, landings), 323–324 (kitchen/bedroom, which look through doorways into
  the rest of the house). Chase views 47–524.
- **Triangles:** median 8.9k, max 27k. Nothing yet comes close to mattering.
- **Seat GPU time:** median 3.75 ms, range 2.3 (`yard_b_horizon`: sky and ground only) to 5.35
  (`cam_garden_wall_backed`, where the own body is faded: the alpha copies plus depth pre-pass,
  P0-6, cost ~1.5 ms). GPU time follows pixels and shaders, not geometry, at these counts.
- **Frame interval (vsync off, 3v3 bots playing):** median 5.6 ms (~175 fps), worst view median
  8.0; p95 8.5–16.0 ms; single worst frame 27.7 ms. The p95 and worst frames are simulation
  ticks, not drawing: GPU time is flat across the same views.
- **Memory:** video 37–50 MB, textures 24 MB, buffers 13–25 MB. No shadow passes (0 shadow
  draw calls; the sun casts none yet).
- Twin rooms agree within the bodies in view (e.g. back hall A 95 vs B 119 draw calls: bots).

So the budget is almost all headroom today, and it will be spent on three things in this order:
interior lights (extra passes per lit object), merged-or-not art meshes, and shadows.
