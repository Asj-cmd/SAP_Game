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

Then let Godot import once (`--editor --quit-after 100`) before anything can
load the result.

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
