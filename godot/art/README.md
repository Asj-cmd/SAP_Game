# Art

Blender-authored models for the Godot build. Source scripts in `blender/`,
exported `.glb` in `models/`.

## The one rule that matters

**ONE UNIT IS ONE CENTIMETRE.** The simulation uses it (actor radius 20, body
180 tall, room 1000 square), so models are authored at that scale directly - a
50-unit cash bundle is modelled as 50, not 0.5. Blender's unit is nominally a
metre, and the retired Three.js scripts in `/assets/blender/` built at metre
scale; a model authored that way imports a hundred times too small.

`_common.py` exports with scale 1 and Y-up, so authored units survive the trip.

## Build

```bash
blender --background --python godot/art/blender/build_cash.py
```

Then let Godot import once (`--headless --import`) before anything can
load the result.

## Where art comes from

| Kind | Path | Tool |
|---|---|---|
| Our own simple models (cash) | `models/` | Blender scripts in `blender/` |
| Family figures (skinned) | `characters/` | `autobuild/figure_bake.mjs` from the Quaternius zips (STYLE §2) |
| Figure animation set (one for every member) | `characters/figure_anims.res` | `node autobuild/run_tool.mjs build_figure_anims` from the Quaternius Animation Library (clip table `CLIPS` in `tools/build_figure_anims.gd`); `FigureAnimation.attach` plays it; `node autobuild/anim_sheet.mjs [--clips=] [--member=]` shoots contact sheets |
| Downloaded static props, furniture | `props/` | **the import pipeline below** (P1-6) |

## Importing a downloaded model (the pipeline)

Free sources only (DECISIONS D10): CC0 first. **Add the `ASSETS.md` row before the
file lands here.** Raw downloads stay in the gitignored `autobuild/Incoming/`.

```bash
# 1. Download (Poly Haven; checks every file's md5). Other CC0 sites: by hand into Incoming/.
node autobuild/fetch_polyhaven.mjs ArmChair_01
#    Kenney packs (CC0; refuses a page without the CC0 line, unzips, writes the zip's sha256):
node autobuild/fetch_kenney.mjs furniture-kit    # -> autobuild/Incoming/kenney/furniture-kit/Models/GLTF format/*.glb
#    Kenney pieces are about half real size: import them at --units=260 (STYLE §3.3 "The kit").

# 2. Look first: --dry reports size, triangles, materials and the budget, writes nothing.
node autobuild/import_asset.mjs autobuild/Incoming/polyhaven/ArmChair_01/gltf/ArmChair_01_1k.gltf \
     --out=res://art/props/armchair_01.glb --dry

# 3. Import for real, with the flags the dry run showed you need.
node autobuild/import_asset.mjs <same source> --out=res://art/props/armchair_01.glb \
     --units=130 --max-tris=2000 --material=fabric --url=https://polyhaven.com/a/ArmChair_01 --licence=CC0

# 4. Look at it in a room (drawn-only, dressed by the theme):
godot --path godot -- --capture --capture-clean \
     --capture-prop=res://art/props/armchair_01.glb,560,660,560,45 --capture-at=900,830,960 --capture-look=600,720,560
```

`godot/tools/import_asset.gd` does the work, headless, reading the source at runtime
(`.glb`, `.gltf` or `.fbx`; it does not need to be inside the project):

- **Scale to 1 unit = 1 cm.** `--units=auto` (default) reads anything whose longest side
  is under 20 as metres (×100) and says so; `--units=m|cm|<factor>` forces it
  (`--units=130` = metres at the house's 1.3× furniture scale, STYLE §3.1);
  `--height=120` scales uniformly to an exact height (a table to the 120 threshold);
  `--fit=x,y,z` scales each axis to a blockout box. `--yaw=deg` turns it first.
- **Y-up** comes with glTF/FBX; every node transform is baked into the vertices.
- **Pivot** `--pivot=base` (default): feet at the origin, centred in x/z, so a prop placed
  on a floor point stands on it. `centre`, `keep`.
- **No collision, ever.** Physics bodies, collision shapes, `-col`/`-colonly` nodes,
  cameras, lights and animation are dropped and counted. Skinned meshes are refused
  (characters go through `figure_bake.mjs`).
- **One mesh, one surface per material name** (a surface is a draw call).
- **Theme materials.** Textures are dropped, UVs kept; each surface keeps only a name.
  `--material=wood` (or `--material=Seat:fabric,Legs:wood`) renames to the theme's
  generic names, which `ArtTheme.by_source_name` maps (`wood`, `fabric`, `steel`,
  `painted` today; anything else gets the theme's `prop` default). Like-named surfaces merge.
- **Budget** per `--role=prop|hero|cash` (STYLE "Per asset": prop ≤ 2k typical / 6k max,
  ≤ 2 materials; hero ≤ 6k; cash ≤ 500, 1). Over the max = not written, exit 1.
  `--max-tris=N` decimates with the engine's simplifier, which keeps UV and normal seams
  and so stops at about half on a seamy model: it says "could NOT reach" when it cannot.
  A model that must go lower is decimated in Blender first.
- Prints a draft `ASSETS.md` row.

`autobuild/import_asset.mjs` runs it, lets Godot import the `.glb`, and writes
`<name>.source.json` beside it (source path, URL, licence, flags), so
`node autobuild/import_asset.mjs --again=godot/art/props/<name>.source.json` or `--all`
rebuilds every prop from a fresh download, byte for byte.

**In the game** a prop is `ArtTheme.current().prop_instance("res://art/props/x.glb")`:
dressed from the theme, or `null` when the file is missing, so the caller keeps its
primitive (below).

## Art is optional, and stays that way

Every model is loaded through a `ResourceLoader.exists` check with a primitive
fallback - see `greybox_main._cash_model`. A clean checkout with no `.glb` files
plays and screenshots exactly as it did before, because the game has to stay
runnable for people who have not run Blender.

## What art may NOT do

Collision comes from `content/levels/house.tres`, baked from `build_house.gd`
via named boxes (`blocker_*`, `shell`, `spawn_*`). Nothing in `models/` is ever
read by the simulation, and no model changes what a player walks through. See
WORLD_AUTHORING §6 - art and collision are separate on purpose, because
auto-generated collision inherits every modelling artefact.
