# Style

What the game looks like, and the numbers that hold it to that. Art direction is DECISIONS.md
**D2 (deadpan)**, written out here by P1-3; the budgets below it are P1-1's. Every art task
(P1-4 onwards) is judged against this file, by frames.

**References.** `autobuild/references/` held no images when this was written (only
`.gitkeep`), so nothing here is derived from a picture. It is derived from D2, D3, D9, D10 and
the measured house (`godot/tools/build_house.gd`, `WORLD_AUTHORING.md` §10, §12). If the user
adds references later, they guide **tone only** (D10 alignment, commit `2a436e8`): no copying a
specific game's characters, art or look.

## 1. The idea in one paragraph

**Plain people in a real house.** The house is the straight man: an ordinary, believable
suburban home, lit warmly, furnished like someone lives there. The family members are the
joke: identical, featureless, slightly wrong-shaped figures who do absurd things (sprint with
their arms up, carry a cash brick over their heads, get teleported to jail) with no reaction at
all. Nothing in the world winks at the player. No outlines, no cartoon effects, no confetti, no
squash-and-stretch, no faces. If a frame would work as a still from an estate agent's listing
with some odd mannequins in it, it is on style.

## 2. The figures

### 2.1 What they are, and are not

- **Blank.** No eyes, eyebrows, mouth, nose detail, ears modelled out, hair, beards or
  fingernails. The head is a smooth rounded form. Hands are mitten-simple (fingers may stay on
  the mesh if the rig needs them, but smoothed so they read as one shape at chase distance).
- **Identical.** Every dad is the same dad, in both families. Members differ in **size and
  shape only** (2.2), never in colour, clothes or accessories, except the one optional team
  detail D3 (c) adds (2.4).
- **Slightly off.** Proportions are plausibly human and then nudged, never caricatured (2.2).
  The aim is "something is not quite right about these people", not "cartoon character".
- **Not crash-test dummies** (D2). So: no yellow/black, no quadrant target discs on the head or
  hips, no visible joint segmentation or bolts, no stencilled numbers. **Not shop mannequins
  either**: no seams at the neck or wrists, no stands, no glossy white fibreglass. They are
  people, rendered without the details that make a person somebody.
- **No acting.** No expressions (there is no face), no idle fidget, no breathing. Standing still
  is perfectly still (D9). Motion comes from the verbs only (P2-2/P2-3).

### 2.2 Proportions (sizes in units; 1 unit = 1 cm)

The simulation body is the same for everyone: a 20-radius sphere for collision and a
**180-tall visible body** for every vertical rule (`TuningDef.actor_height`). Art never changes
either. So the drawn figures may be **180 or shorter, never taller**, which keeps every
headroom and jump rule conservative for everybody.

| Member | Drawn height | Head : height | Off-proportion nudge (one each, subtle) | Base mesh (D10, P1-2) |
|---|---|---|---|---|
| Dad | 180 | 1 : 7 | Torso a touch long, legs a touch short; shoulders squared | Quaternius Superhero_Male, muscle detail smoothed out |
| Mom | 176 | 1 : 7 | Neck a touch long; hands a touch large | Quaternius Superhero_Female, smoothed |
| Elder child | 160 | 1 : 6 | Head a touch big for the body | Same two bodies, scaled, head enlarged |
| Younger child | 145 | 1 : 5 | Head clearly big; arms a touch short | Same two bodies, scaled, head enlarged |

**As built (P2-1, REVIEW).** Six `FamilyMember`s in `default_theme.tres` (`family`), on top of
the shared nudge in 2.3, each drawn at exactly its height measured after the nudges:
dad = male body, 180, legs ×0.97; mom = female body, 176, nothing extra; elder girl / boy =
female / male body, 160, build narrowed (pelvis x ×0.87, z ×0.9, which carries to everything
above and below it) with the head given back its width and enlarged a further ×1.08; younger
girl / boy = 145, build ×0.86 / ×0.9, head a further ×1.25, upper arms and thighs ×0.94. Slots
are drawn as `family_order` = dad, mom, elder girl, younger boy (both families; P2-4's kid swap
overrides one team through `family_order_by_team`). Each body is 5,000 triangles.
Frames: `autobuild/frames/p2_1/lineup_*.png` (`node autobuild/family_lineup.mjs`).

- "A touch" means **5 to 10 per cent** off normal, chosen so a still frame of one figure looks
  ordinary for a moment and wrong on a second look. If a nudge is noticeable on first glance in
  a chase-camera frame, halve it.
- **Silhouette first.** Each of the four sizes must be told apart by outline alone at 20 m
  (P2-4 checks this from 20 m and 40 m). Never by colour.
- Kid swap (D3 d) needs a girl and a boy at each child size: the elder and younger children are
  each built from both the male and the female base body.
- **Why the kids are not much smaller:** the crouch gap is 130 (`WORLD_AUTHORING` §12). Every
  member standing must look taller than a crouch gap, or the threshold stops reading. The
  younger child, at 145, is the floor. Crouched, every member must look at or under 130.
- **Width:** adults about 45–50 across the shoulders. They look broader than the 40 collision
  sphere; that is accepted, the same way 180 is accepted against a 40-tall sphere.

### 2.3 Material

**One material for every figure: smooth, warm-grey, satin, featureless.** Like unpainted
modelling clay or a matt vinyl toy, not skin and not glossy plastic.

| Property | Value (starting point; the ArtTheme owns it, P1-4) |
|---|---|
| Albedo | Warm putty grey, about `Color(0.72, 0.69, 0.64)`. No texture. Deliberately not a skin tone |
| Roughness | 0.55 (a soft, broad highlight that shows the form; never a sharp hotspot) |
| Metallic | 0 |
| Specular | 0.4 |
| Rim | A faint rim term (StandardMaterial3D `rim`, about 0.2, tint 0.5) so a figure separates from a dark wall without an outline. P1-4 checks by frame that Compatibility draws it; if not, drop it and rely on value contrast (3.4) |
| Vertex colour | Allowed for **baked ambient occlusion** only (armpits, under the chin), to keep the form readable without shadows |

Clothes: **painted, not modelled** (P1-5 STYLE-PICK, REVIEW; this replaces "none" above).
Every figure wears the same plain clothes through baked vertex colour in the one material: a
muted blue-grey long-sleeved shirt, grey-brown trousers, dark shoes, with bare putty head and
hands. The slice showed a bare body reading as an anatomical clay model, and the clothed one
as "a person without the details". Material as built: putty `(0.74, 0.71, 0.66)`, roughness
0.7, rim 0.2, `vertex_color_use_as_albedo`. Off-proportion as built (theme
`figure_bone_scales`): head ×1.08, neck ×1.08 long, torso ×1.04 long, hands ×1.06. Slice
frames: `autobuild/slice/`; the clothes colours are `PAINT` in `autobuild/figure_bake.mjs`.

### 2.4 Team identity (D3 is an experiment)

- **Figures carry no team colour.** The blockout's red/blue bodies (`greybox_main.gd`, team
  base colour) are a placeholder and go when the D2 figures arrive (P2-1). The game is built so
  that a still enemy is hard to tell from your own family (D3).
- The team tell is a data setting (P2-4): (a) a marker over **your own** teammates only,
  (b) a minimap of your own teammates only, (c) one small detail differs (a wristband), (d) kid
  swap. When (c) is on, the wristband is the only coloured thing on a figure: a 6–8 wide band on
  the left wrist, in the family colour below, same satin material.
- **Family colours** (REVIEW, logged in DECISIONS): Family A **sage** `Color(0.48, 0.58, 0.45)`,
  Family B **terracotta** `Color(0.70, 0.40, 0.30)`. Muted on purpose, both mid-value, so neither
  shouts. They are used for: the D3 (c) wristband, the HUD/minimap, and each house's **front
  door and window frames** (so you know whose house you are in, without telling you who a person
  is). Nowhere else. The blockout's red/blue floor tints are debug, not art.
- **As built (P2-4, REVIEW).** `TeamTell` (`game/art/team_tell.gd`, default
  `art/theme/team_tell.tres`): **minimap + wristband** on, marker and kid swap off. Switch in the
  menu (four checkboxes) or in a match with F5 marker / F6 minimap / F7 wristband / F8 kid swap;
  `--team-tell=` on the command line. Wristband: 7 long on the left forearm cuff, radius measured
  from the mesh, satin family colour (theme `wristband_*`). Marker: a small family-colour
  point-down triangle over each teammate's head, never over an enemy. Minimap: top right, rooms
  outlined, your teammates as dots, you as a white arrow, your house at the bottom. Kid swap uses
  the theme's `family_order_by_team` (B: dad, mom, elder boy, younger girl). Frames:
  `autobuild/frames/p2_4/<set>_{close,20m,40m}.png` (`node autobuild/team_tell_frames.mjs`).

## 3. The house

### 3.1 Scale: built to the thresholds, about a third larger than life

The house is sized for the camera (`WORLD_AUTHORING` §10): rooms 1000 square, 320 clear under
the ceiling, doorways 240 wide and 240 high, walls 30 thick, slabs 40. Furniture follows the
**threshold set** (§12), and that is binding on the art:

| Threshold | Height | What is built to it |
|---|---|---|
| step_up 30 | ≤ 30 | Sills, kerbs, rugs, a stair tread (30 rise, 48 run) |
| vault 120 | **exactly 120** top surface | Kitchen counters, tables, desks, dressers, chests of drawers, sofa backs, railings, low garden walls |
| crouch gap 130 | **≥ 130** underside, open below | Tables and desks you can crawl under; nothing else looks like a gap |
| above 180 | ≥ 210 | Anything tall enough to block: wardrobes, fridges, bookcases, door heads (240), hedges |
| drop 480 | — | Upstairs windows and the balcony drop look like a fall you would survive |

So counters and tables are **about 1.3× real height** (120 against a real 90), and furniture is
scaled up to match: a sofa about 260 long, a bed about 260 by 200, doors 240 high. **The
figures are not scaled up.** Ordinary people in a house that is a little too big for them is
part of the "slightly off" (and makes rooms read larger, which the camera needs). Never fake a
height: nothing between 30 and 120 may look climbable unless it is at a threshold, and nothing
between 120 and 210 may look like it blocks a standing body (it would be vaultable).

### 3.2 Rooms and what they are

Both houses are the same house, turned (DESIGN_DIRECTION §4, mirrored). Two rooms by two, two
floors:

| Floor | Room | Reads as | Floor | Walls | Silhouette that must read |
|---|---|---|---|---|---|
| Ground | Front hall | Entrance hall with the main stair | Oak boards | Painted plaster | Stair, front door (family colour) |
| Ground | Kitchen | Family kitchen-diner | Cream ceramic tile | Painted plaster, tiled splashback | Counters at 120, table you can crawl under |
| Ground | Back hall | Hall to the garden door | Oak boards | Painted plaster | Garden door, coat hooks |
| Ground | Jail | Utility room / laundry, behind a door | Grey concrete, painted | Bare painted block | Washing machine, a barred or cage-like pen: obviously "you are kept here" |
| Upper | Landing SE / NW | Landings at the stair heads | Carpet, warm grey | Painted plaster | Banister rail at 120 |
| Upper | Study (cash) | Home office | Carpet, muted green-grey | Wallpaper, faint stripe | **The safe/vault**: squat, steel, dark, nothing else like it |
| Upper | Bedroom (cash) | Main bedroom | Carpet, muted beige | Painted plaster | Bed, wardrobe; the cash room's vault too |

Distinct silhouettes the player must find instantly (P3-3): **the vault/safe, the cash
bundle, the jail pen and its door, the safe room**. Each gets a shape nothing else in the house
shares. Everything else is background and should look it.

### 3.3 Materials and palette

Realistic-leaning means **believable materials, true proportions, restrained colour**. Not
photo-real: there is no GI, AO or reflections in Compatibility (D6), so detail goes into
albedo, roughness and baked vertex AO, not into lighting.

- **Surfaces are tiled PBR-style albedo + roughness** (normal maps only where they earn it at
  chase distance: brick, tile grout). Sources: CC0 only (Poly Haven, ambientCG, Kenney; P3-1
  chooses). Textures 512² or 1024² for big surfaces (budgets below), VRAM-compressed, mipmaps on.
- **Texel density:** about **2 texels per unit** (200 per metre) on walls and floors, 2–3 on
  furniture. Every surface in a frame must look equally sharp; a blurry floor under a crisp
  sofa is a defect.
- **Every imported mesh has its materials replaced from the ArtTheme** (P1-4), so packs from
  different sources look like one house. A pack's own stylised materials never ship.
- **Furniture packs that are stylised** (chunky bevels, toy proportions) are used only if their
  shapes pass for real furniture once re-materialed. Otherwise do not use them.

**The kit (P3-1, REVIEW; DECISIONS.md has the reasons):**

| What | Source | How |
|---|---|---|
| Furniture, appliances, lamps, rugs | **Kenney Furniture Kit** (CC0) | `fetch_kenney.mjs furniture-kit` → `import_asset.mjs` at `--units=260` or `--height=<threshold>` → `art/props/kenney/` |
| Wall, floor, ceiling, tile, brick, roof surfaces | **Poly Haven textures** (CC0) | Tiled through the theme's materials on the generated shell |
| Carpet, wallpaper, upholstery | **ambientCG** (CC0) | Same |
| Shell: walls, floors, openings, frames, door leaves, stairs, roof | **Generated from the blockout data** (P3-2) | No modular kit: Kenney's wall pieces are half-real tiles and do not fit 240 × 240 openings, 30 walls or a 360 storey |
| Safe/vault, jail pen and door, cash | **Our own** (procedural) | Each must have a shape nothing else in the house shares (§3.2) |

Texture shortlist for P3-2 to try first (judge by frame, keep the theme's colour by tinting):
wall paint `white_plaster_02` / `beige_wall_001`; oak floor `laminate_floor_02` / `wood_floor`;
kitchen tile `interior_tiles` / `floor_tiles_06`; jail `concrete_floor_painted` (floor) and
`concrete_block_wall` (walls); carpet ambientCG `Carpet0NN` (16 to pick from); study wallpaper
ambientCG `Wallpaper001A`–`002C`, or plain paint if none is quiet enough; exterior
`brick_wall_001` or render `white_plaster_rough_01`; roof `grey_roof_tiles`. Poly Haven has
no clean carpet (only `dirty_carpet`).

Kenney's UVs index a colour atlas, so furniture keeps flat theme colours until a texture is
wanted there, and then gets it triplanar (world-space), never through the pack's UVs.

Seen in the P3-1 trial (`autobuild/frames/p3_1/`): the counter's `wood` surface is its door-panel
frames, not its top (P3-3 maps the top to a counter material); a table built to 120 has an
underside well under 130, so it is a vault surface, not a crawl-under (P3-3 picks which a given
table is).

Palette (sRGB, a starting point the theme owns):

| Material | Colour | Roughness | Notes |
|---|---|---|---|
| Wall paint | warm off-white `(0.86, 0.83, 0.77)` | 0.9 | The most common surface; must not be pure white |
| Ceiling | white `(0.92, 0.91, 0.88)` | 0.95 | Always the darkest face by lighting, not by colour |
| Oak floor | `(0.55, 0.40, 0.27)` | 0.6 | Boards run the long way of the room |
| Carpet | warm grey `(0.55, 0.52, 0.48)` / green-grey / beige | 1.0 | |
| Kitchen tile | cream `(0.85, 0.82, 0.74)` | 0.4 | Grout lines visible at 5 m |
| Concrete (jail) | `(0.55, 0.55, 0.53)` | 0.9 | Colder than the rest of the house |
| Painted wood trim | off-white `(0.90, 0.88, 0.83)` | 0.5 | Skirting, door frames, banisters |
| Brick (exterior) | `(0.55, 0.33, 0.25)` | 0.85 | Or render `(0.85, 0.82, 0.75)`; P3-4 picks one for both houses |
| Roof tile | dark grey `(0.30, 0.30, 0.32)` | 0.8 | |
| Steel (safe, jail bars) | `(0.30, 0.31, 0.33)` | 0.45, metallic 0.8 | The only metal surfaces of note |
| Grass | `(0.36, 0.50, 0.30)` | 1.0 | Today's `world_backdrop.gd` value; keep |
| Cash bundle | banknote green `(0.45, 0.62, 0.42)` + paper band | 0.7 | Must be the most saturated small object in any room (3.4) |

**Saturation rule:** the house stays below about 35 per cent saturation everywhere except
the cash and the two family colours. Then the eye goes to cash and doors without any effect.

### 3.4 Readability (the game comes first)

- **Cash is readable at 30 m** in daylight (P3-5's check): it is the most saturated small
  object in view, never placed on a surface of the same green, never hidden by dressing.
- **Figures separate from the background** by value: putty grey sits between the dark floors
  and the light walls, plus the rim term. Check in the darkest room (jail) and the brightest
  (kitchen at noon).
- **Thresholds look like their verbs** (3.1). This beats realism every time it conflicts.
- **Floors are not tinted by zone** in the art. Who owns a room is the HUD's job (P5-2).

## 4. Lighting

The Compatibility renderer has no GI, SSAO or SSR (D6), so the lighting is built from a few
cheap parts, each measured (P1-1's rule: run `render_stats.mjs --views=room_` before and after).

- **Outside:** one sun, warm late-morning white `(1.0, 0.95, 0.86)`, high enough that every room
  with a window gets a patch of it. Sky as now (`world_backdrop.gd`: procedural, horizon fog).
  The shadowless cool fill from the opposite side stays (P0-7) so unlit faces still differ.
- **Inside:** warm lamp light, **2700–3000 K** `(1.0, 0.84, 0.66)`, from fittings that exist
  in the room (ceiling light, desk lamp, under-cabinet light). **At most two omni/spot lights
  touch any object** (budget rule below), **no shadows on omni/spot lights**. Ambient lower
  indoors than out, so interiors read as interiors.
- **Contrast between inside and out** is the realism cue: windows are brighter than walls, and
  the garden seen from inside is a little over-exposed.
- **Shadows:** at most one shadowed light, the sun, and only if P3-5 measures that it fits. A
  **contact shadow under every figure and every cash bundle** (a soft dark disc on the floor,
  drawn as a transparent quad, since Compatibility has no decals) is mandatory either way: it is
  what makes a jump and a throw readable.
- **Baked vertex AO** in corners, under furniture and on figures substitutes for SSAO.
- **Tonemapping** filmic-style if the Compatibility renderer honours it (P1-4 checks by frame),
  exposure set so the wall paint sits at about 75–80 per cent brightness in a lit room. No
  bloom-heavy glow.
- Room by room: the jail is the coldest and dimmest (a single bare bulb), the kitchen the
  brightest, the study and bedroom warm and lamp-lit. Same at every team size.

**As built in P1-4** (`godot/art/theme/default_theme.tres`; measured on the GT 730M):

- Sun **with** shadow (one orthogonal map, 4000 reach). It is the cue that makes an interior an
  interior: without it the sun lights every indoor floor exactly as it lights the lawn. Cost: the
  shadow pass draws every caster again (approach view 526 → 1045 draws, over the 1000 budget
  until P3-6 merges the blockout) and ~2.5–3.4 ms of GPU.
- Room lamps are built (`interior_lamps`) but **off**: Compatibility redraws each object once per
  omni/spot touching it, and 16 ceiling spots cost ~3.7 ms of GPU in the kitchen view (10.2 ms
  with the shadow, over the 9 ms budget). The outdoor ground is on render layer 2, which lamps
  skip (that alone saved ~3.7 ms outdoors). P3-5 turns lamps on per room, with fittings.
- Indoors is lit by a warm-neutral ambient, the cool fill (+x/−z walls) and a shadowless warm
  **sky fill** from above, tilted from (−1, 3, 1) so the −x/+z walls get some and ceilings none.
  Directional lights are in the base pass, so the fills are nearly free.
- **Tonemap: Linear.** Filmic is honoured by Compatibility, but with any white/exposure tried it
  either washed interiors flat (white 1) or blew sunlit walls and lawn to white (white 4,
  exposure 1.2). On this renderer a directional light lit a floor ~2.4× harder per unit of energy
  than the Lambert estimate. Energies are therefore low (sun 0.38) and the ambient colour is read
  as sRGB.
- Seen in frames, open: the ceiling is only just darker than the darker walls; a sun-facing
  outside wall is near white; the warm ambient pushes the putty figures toward cream, and in the
  jail a figure sits close in value to the walls (P1-5 tries figure treatments); the rim term
  shows only as a thin highlight on sunlit edges.

## 5. Motion, effects, sound (summary; the tasks own the detail)

- Animation is stiff and committed, never cartoon (D9): no squash-and-stretch, no anticipation
  poses, no overshoot. Wobble (jump landing) is subtle and short, under 0.25 s.
- Effects (P5-4) are plain and physical: a puff of dust on a hard landing, a paper flutter when
  cash lands. No stars, no speed lines, no confetti, no screen-filling flashes.
- Sounds are ordinary household sounds (P5-3).

## 6. What "polished" means

A view is polished when all of these hold in a clean frame (`--capture-clean`), opened and
looked at:

1. **No construction artefacts:** no z-fighting, no gaps or light leaks at wall joins, no
   floating or sunken props, no flipped normals, no visible blockout grey, no debug colour.
2. **One material language:** every surface comes from the ArtTheme; no two packs' looks side
   by side; equal texel density across the frame (3.3).
3. **Grounded:** every figure and cash bundle has a contact shadow; furniture touches the floor.
4. **Readable:** cash visible at 30 m; the four must-read silhouettes (3.2) recognisable at a
   glance; every threshold-height surface looks like its verb; a figure always separates from
   what is behind it.
5. **Lit like a home:** warm interiors, brighter windows, ceilings darkest, no flat
   one-colour faces, no pitch-black corners.
6. **Deadpan intact:** no faces, no expressions, no idle motion, no team colour on figures
   beyond the D3 detail in use, no cartoon effect anywhere.
7. **Camera-clean:** no wall between camera and body (P0-6), the body fade works with the real
   figure (no inner faces showing).
8. **In budget:** the view is inside every per-view number below at 4v4.
9. **The same in both houses:** twin views of House A and House B differ only by the family
   colour and the bodies in them.

Smaller and consistent beats larger and patchy (DECISIONS working agreements): a room that is
not polished yet stays plain and tidy rather than half-dressed.

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
