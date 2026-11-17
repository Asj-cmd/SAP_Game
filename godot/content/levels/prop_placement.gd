class_name PropPlacement
extends Resource
## One drawn piece of furniture or dressing (P3-3). Presentation only: the
## simulation never reads it. Baked from a `prop_*` node in the blockout scene.
##
## `model` is an id the ArtTheme maps to a model (`furniture_models`), so the
## level says WHAT stands here and the theme says what it looks like.

## The jail pen (model `jail_pen`): bars this thick on every side, and a gate
## this wide left open in the middle of its FRONT side (the one `yaw_deg`
## faces). tools/build_house.gd builds the pen's collision from the same two
## numbers the drawn pen uses, so the bars you see are the bars you hit.
const PEN_BAR: float = 10.0
const PEN_GATE: float = 120.0

@export var model: StringName = &""
## Lot space. With `fit`, the model is scaled per axis to fill this box exactly
## (a blocking piece's box is its collision box, so what you see is what you
## hit). Without, the model keeps its own size and stands on the box's
## bottom centre.
@export var box: AABB = AABB()
## Which way the piece's front faces, in degrees about +y; 0 = +z.
@export var yaw_deg: float = 0.0
@export var fit: bool = true
## A yard prop (P3-8): whose yard it stands in. `model` is then a SLOT, and the
## theme's `yard_models` says what that family has there. Empty for furniture.
@export var family: StringName = &""
