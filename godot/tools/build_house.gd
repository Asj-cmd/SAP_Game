extends SceneTree
## Builds the house and the lot from HOUSE_LAYOUT.md.
##
##   godot --headless --path godot --script res://tools/build_house.gd
##
## THE SPEC IS THE SOURCE. Every dimension, opening and coordinate below is
## quoted from HOUSE_LAYOUT.md - §2 dimensions, §3 stacking, §4-6 the floors,
## §7 the opening schedule, §9 the lot. Where a number here disagrees with that
## document the document wins and this file is wrong.
##
## PHASE 1 ONLY: two floors, four quadrants, six rooms (Front Hall, Kitchen,
## Back Hall, Jail / Landing A, Master Bedroom, Landing B, Study - eight room
## instances across two floors), two straight staircases each hugging an
## exterior wall in the corner of the room it serves. No basement - §0 is
## explicit that Phase 1 reserves no space for Phase 2, so nothing below tries
## to.
##
## The house is drawn ONCE in house-local coordinates and stamped twice, the
## second copy rotated 180 degrees about the middle of the lot (§9). Two
## hand-written copies would drift, and a difference between the two houses is a
## balance bug nobody can see.

# ---- §2 dimensions ----
const STEP: float = 30.0
const RUN: float = 48.0 ## 30 rise / 48 run = 32 degrees, a real stair angle -
                        ## see HOUSE_LAYOUT.md §2 "48 run, not 64". Stays 8
                        ## units clear of the fill's 40-unit sampling cell
                        ## (WORLD_AUTHORING §11) so a column centre cannot miss
                        ## a tread.
## §2. A storey is a whole number of steps, and generous rather than economical.
##
## 360 is TWELVE steps of 30, which is the first constraint: the walkable fill
## quantises height at layer_height (= STEP), so a tread is only found when a
## layer centre falls inside it, and a storey that is not a whole number of
## steps silently drops treads nobody can climb (WORLD_AUTHORING §12).
##
## It was 300 - ten steps, 260 of clear height - and that was too MEAN for the
## room it sits in, not too tall. A 1000-unit room with a 260 ceiling is 3.85
## wide for every 1 tall, where a real domestic room is about 1.67; the house
## read as a wide flat box. At 360 the clear height is 320 and the ratio is
## 3.12, which is still generously wide but no longer a corridor with a lid.
##
## It also buys the headroom the verbs need. A standing body is 180 tall, so
## 260 of clear height left 80 above the head - not enough to jump ONTO
## anything, because landing on a vault-height (120) ledge needs the head to
## reach 300. 320 of clear height gives 140 of headroom and makes every
## waist-high surface in the house something a player can get on top of.
##
## The flight still fits the room, which is the second constraint: twelve
## treads at 48 is 576, plus a 120 landing, is 696 of a 1000 room - leaving 304
## of floor to walk onto. Eleven steps in a 755 room was what made the earlier
## house "difficult to get onto the stairs".
const STOREY: float = 360.0 ## 12 steps exactly
const QUAD: float = 1000.0 ## §2: room is 1000 square, holds a corner stair
const WALL: float = 30.0
const DOOR: float = 240.0
const SLAB: float = 40.0
const HEAD: float = 240.0 ## §7 drafting note: doorway head +240
const BODY: float = 20.0 ## TuningDef.actor_radius
const BODY_HEIGHT: float = 180.0 ## how tall the thing walking it LOOKS

## Window openings. Sills from §7.
const WINDOW: float = 240.0 ## passable ground-window climb, and escape windows
const SILL_UPPER: float = 80.0 ## escape window sill
const SILL_GROUND: float = 90.0 ## ground window sill

# ---- §3 heights ----
const GROUND: float = 300.0 ## garden / terrain surface sits here
## DERIVED, not restated. These were hardcoded at 600 and 900 while STOREY said
## 300, which is three numbers that have to agree by hand - exactly the shape of
## drift that let carry_speed_scale sit wrong for months. Change STOREY and the
## floors follow.
const UPPER: float = GROUND + STOREY
const ROOF: float = UPPER + STOREY

# ---- §3 house-local grid ----
#
#    Z=2090 +--------------+--------------+
#           |      NW      |      NE      |
#           |   30-1030    | 1060-2060    |
#    Z=1060 +--------------+--------------+
#    Z=1030 |      SW      |      SE      |
#           |   30-1030    | 1060-2060    |
#    Z=  30 +--------------+--------------+
#         X=30           1030 1060      2060
const LOW: float = WALL ## 30 - inner face of the outer wall
const MID_LOW: float = LOW + QUAD ## 1030 - near face of the internal wall
const MID_HIGH: float = MID_LOW + WALL ## 1060 - far face
const HIGH: float = MID_HIGH + QUAD ## 2060
const HOUSE: float = HIGH + WALL ## 2090 square (§2)

## Centre of an internal wall, for _wall_x / _wall_z which take a centreline.
const SPLIT: float = MID_LOW + WALL * 0.5 ## 1045

## Quadrant centres, for openings that sit in the middle of a room's face.
const NEAR_MID: float = LOW + QUAD * 0.5 ## 530
const FAR_MID: float = MID_HIGH + QUAD * 0.5 ## 1560

# ---- §2 straight stairs, hugging an exterior wall ----
#
# One flight per storey, no switchback and no mid-landing, run shortened from
# 64 to 48 so the flight reads as a stair rather than a ramp - 25 degrees was
# too shallow. 30 rise over 48 run is 32 degrees, still comfortably above the
# fill's 40-unit sampling cell (8 units of slack; below ~40 a column centre can
# miss a tread's centre entirely and the fill silently drops a stance, the same
# class of bug the lot-alignment guard exists to catch elsewhere in this file).
#
# Twelve treads at 48 is 576 plus a 120 landing, which is 696 of the 1000-unit
# room the flight stands in - it fits with 304 of floor to spare, and that
# margin is the point. An eleven-tread flight in a 755 room was what made
# "getting onto the stairs is difficult" a real complaint.
## Steps in one flight, derived from the storey rather than counted by hand.
## STOREY is a whole number of STEPs by construction (see above), so this is
## exact - and a flight that did not match its storey would either stop short of
## the floor or punch through it.
const FLIGHT_STEPS: int = int(STOREY / STEP)
const FLIGHT_RUN: float = RUN * float(FLIGHT_STEPS) ## full climb in one run
const FLIGHT_W: float = 280.0

## Flat clearance before the first riser, so the flight does not start flush
## against the doorway you just walked through. Purely a gap in front of the
## bottom step; the stair's own footprint (and therefore the floor cut above
## it) still starts at the base coordinate below.
const STAIR_LANDING: float = 120.0

## §7 G3: main stair, Front Hall (SE), against the EAST wall, running NORTH.
## Base at Z 60, beside the front door, so you enter and turn right to climb.
## The first riser sits STAIR_LANDING past the base; the schedule's Z 60-700
## footprint shrinks accordingly (see _stairs).
const STAIR_A_X: float = 1780.0
const STAIR_A_Z: float = 60.0
## §7 G7: second stair, Back Hall (NW), against the WEST wall, running SOUTH.
## Base at Z 2030, beside the back door, so you enter and turn left to climb.
## The flight climbs from its base (high Z) toward low Z, the mirror direction
## of stair A, so _straight_flight takes an explicit direction rather than
## assuming +z.
const STAIR_B_X: float = 30.0
const STAIR_B_Z: float = 2030.0

# ---- §9 the lot ----
## §9 gives 5380 x 3690 with 350 margins and a 500 corridor. Neither dimension
## is a whole number of 40-unit sampling cells (5380/40 = 134.5, 3690/40 =
## 92.25), and a lot that isn't costs the same bug it cost before: a 180-degree
## turn samples the fill grid at a different phase, so identical geometry
## produces a different surface for the two teams (WORLD_AUTHORING §11).
## Rounded UP to the next whole cell - 5400 x 3720 - keeping House A's origin
## exactly at the spec's (350, 350) and deriving House B's from the rounded
## lot so point symmetry stays exact. The corridor grows from 500 to 520 and
## the far margins land at exactly 350, matching House A's - the "keep the
## buildings close" intent survives a 4% corridor change untouched.
##
## P3-8 (the user's rules): the gap between the houses, wall to wall, went from
## 520 to 2400 - 4.4 s at walking speed (540 a second) - so the lot is 1880
## wider. Depth, margins and both houses' insides are unchanged.
const LOT_W: float = 7280.0 # 182 cells
const LOT_D: float = 3720.0 # 93 cells
const HOUSE_A_X: float = 350.0
const HOUSE_A_Z: float = 350.0
const HOUSE_B_X: float = LOT_W - HOUSE_A_X - HOUSE ## 4840
const HOUSE_B_Z: float = LOT_D - HOUSE_A_Z - HOUSE ## 1280
const LOT_H: float = ROOF + SLAB

# ---- P3-8 the boundary fence: the territory line ----
## The fence stands on the lot's x midline, the full depth of the lot. Each
## family owns everything on its side of it (no neutral ground). Tall-blocker
## height, so it looks and is unclimbable (WORLD_AUTHORING §12).
const FENCE_THICK: float = 30.0
const FENCE_HEIGHT: float = 230.0
## One main gate in the middle, and two small crossings near the ends. The
## houses sit a half turn apart, so one off-centre crossing could not be
## symmetric: each crossing is the "back" one for one family (its twin is the
## other family's).
const GATE: float = 400.0
const CROSSING: float = 160.0
const CROSSING_IN: float = 300.0 ## crossing centre from each end of the fence

# ---- P3-8 the outside back staircase ----
## One straight flight against the house's north (back) face, climbing west to
## a platform in front of a door into Landing B (never the master bedroom).
## The door sits over the back door G5 at NEAR_MID; the platform is a slab, so
## the back door opens underneath it with 320 of headroom.
const BACK_DOOR_X: float = NEAR_MID ## 530: the upper door's centre, over G5
const PLATFORM_X0: float = 380.0
const PLATFORM_X1: float = 680.0 ## the flight's top step starts here
const BACK_STAIR_DEPTH: float = FLIGHT_W ## out from the wall, like the indoor flight's width

## The walkable fill samples at cell centres, so the 180-degree turn maps a
## sampled point to another sampled point only when the lot is a whole number
## of cells across. See WORLD_AUTHORING §11.
const CELL: float = 40.0

## §9: team spawns sit in the team's OWN yard, spread along the back and side
## faces. House-local, so `_place` mirrors them onto B's own yard. Negative x
## is the back (west) face; the third and fourth sit off the front (south, low
## z) face so a squad does not spawn in a single line. One per seat at the
## largest team size, 4v4 (D8): slot N spawns on marker N, and a missing marker
## clamps onto the last one, which put two bodies on one point. The fourth is
## 500 along from the third and 440 short of the front door's jamb, so it does
## not start a body in the doorway. Slots 0-2 are unchanged, so only 4v4 moves.
const SPAWN_LOCAL: Array[Vector2] = [
	Vector2(-150.0, 500.0),
	Vector2(-150.0, 1400.0),
	Vector2(500.0, -150.0),
	Vector2(1000.0, -150.0),
]

var _solids: Array[AABB] = []
## P3-3 furniture: house-local collision boxes (stamped as
## `blocker_furniture_*`, so the shell knows not to draw them as walls) and the
## pieces drawn on them (stamped as `prop_*` markers). Both come from
## `_furnish`, so a drawn piece and its collision are one entry, never two.
var _furniture: Array[AABB] = []
var _props: Array[Dictionary] = []
## While true, _solid writes lot-space blockers directly instead of house-local
## geometry awaiting the stamp.
var _terrain_slab: bool = false
var _root: Node3D = null
var _count: int = 0

func _initialize() -> void:
	if not is_equal_approx(fmod(LOT_W, CELL), 0.0) \
		or not is_equal_approx(fmod(LOT_D, CELL), 0.0):
		printerr("lot %d x %d is not a whole number of %d-unit cells: the turned "
			% [int(LOT_W), int(LOT_D), int(CELL)]
			+ "house will be sampled at a different phase and will not match")
		quit(1)
		return

	_draw_house()

	_root = Node3D.new()
	_root.name = "HouseBlockout"
	_box("shell", Vector3(LOT_W, LOT_H, LOT_D) * 0.5, Vector3(LOT_W, LOT_H, LOT_D))
	_terrain()

	_stamp(false, &"team_a", "a")
	_stamp(true, &"team_b", "b")
	_outdoors()

	var scene: PackedScene = PackedScene.new()
	_own(_root)
	scene.pack(_root)
	var path: String = "res://game/blockout/house.tscn"
	var wrote: int = ResourceSaver.save(scene, path)
	print("%s: %s" % [path, "written" if wrote == OK else "FAILED (%d)" % wrote])
	print("lot %d x %d x %d, %d blockers, 4 rooms x 2 floors per house" % [
		int(LOT_W), int(LOT_D), int(LOT_H), _count])
	quit(0)

# ---- the ground the lot sits on ----

## Garden at y=300, flat everywhere. Phase 1 has no basement, so unlike the
## retired three-storey plan this is a plain slab with no holes at all.
func _terrain() -> void:
	_terrain_slab = true
	_slab_at(GROUND, Rect2(0.0, 0.0, LOT_W, LOT_D), [] as Array[Rect2], GROUND)
	_terrain_slab = false

## A house-local footprint in lot coordinates, ignoring height.
func _flat(local: Rect2, turned: bool) -> Rect2:
	var box: AABB = _place(AABB(
		Vector3(local.position.x, 0.0, local.position.y),
		Vector3(local.size.x, 1.0, local.size.y)), turned)
	return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)

# ---- one house, in local coordinates ----

func _draw_house() -> void:
	_ground()
	_upper()
	_stairs()
	_back_stair()
	_furnish()
	_yard()

## P3-8. Outside the north wall: a platform at upper-floor height in front of
## the Landing B door, and twelve steps down from it running east along the
## wall, each solid to the ground like the indoor flights. The house wall is
## its inner side; the outer side is open (no blocker, so no banister).
func _back_stair() -> void:
	var z0: float = HOUSE
	# The platform: a slab, not solid, so the back door below stays open.
	_solid(AABB(Vector3(PLATFORM_X0, UPPER - SLAB, z0),
		Vector3(PLATFORM_X1 - PLATFORM_X0, SLAB, BACK_STAIR_DEPTH)))
	# Step i's top is GROUND + STEP * (i + 1); the top step is level with the
	# platform. Step 0 is the far (east) end, at the ground.
	var bottom: float = PLATFORM_X1 + RUN * float(FLIGHT_STEPS)
	for i: int in FLIGHT_STEPS:
		var top: float = GROUND + STEP * float(i + 1)
		var x: float = bottom - RUN * float(i + 1)
		_solid(AABB(Vector3(x, top - STEP, z0), Vector3(RUN, STEP, BACK_STAIR_DEPTH)))
		_solid(AABB(Vector3(x, GROUND, z0), Vector3(RUN, top - STEP - GROUND, BACK_STAIR_DEPTH)))

# ---- P3-8 yard props ----
#
# The same collision box at the turned spot in both yards, so the two lots stay
# exact twins; the drawn model differs by family (ArtTheme.yard_models: slot +
# team -> what is drawn). Heights follow the furniture thresholds: a 120 top
# you can get onto, or 230 that stops you. Each stands at least 120 clear of
# walls, doors, the back stair and the spawns.
func _yard() -> void:
	var g: float = GROUND
	# East of the house, toward the fence, in front of the side door's line.
	_yard_piece(&"yard_table", Rect2(2420.0, 520.0, 200.0, 120.0), g, TOP, FACE_W)
	# Behind the kitchen, clear of the back stair's foot.
	_yard_piece(&"yard_shed", Rect2(1560.0, 2700.0, 240.0, 180.0), g, TALL, FACE_S)
	# The front garden's east corner, by the street railings.
	_yard_piece(&"yard_bin", Rect2(2300.0, -230.0, 120.0, 120.0), g, TOP, FACE_N)

func _yard_piece(slot: StringName, rect: Rect2, base: float, height: float, face: float) -> void:
	var box: AABB = AABB(Vector3(rect.position.x, base, rect.position.y),
		Vector3(rect.size.x, height, rect.size.y))
	_furniture.append(box)
	_props.append({"model": slot, "box": box, "face": face, "fit": true, "yard": true})

# ---- furniture (P3-3) ----
#
# WORLD_AUTHORING §12 binds furniture as much as walls: every piece that stands
# on a floor BLOCKS, and its top is exactly at a threshold - 120 (you jump onto
# it: counters, tables, desks, beds, chests, the safes) or at least 210 (it
# stops you: fridges, wardrobes, bookcases, the pen's bars). Nothing between.
# That rules out seating for now: a sofa's seat or a chair's would sit between
# 30 and 120, a ledge at a height the rules do not have.
#
# Pieces stand FLUSH against walls or at least 120 clear of them (three body
# widths), never in between: a gap a body barely fits is where a bot wedges.
# Doorways, the stair approaches, the cash markers and the pen's middle (the
# prisoners' holding spot) are left clear.
#
# House-local, like everything here; `_stamp` places both houses' copies.
# Faces: which way a piece's front looks, in degrees about +y (0 = +z, north).
const FACE_N: float = 0.0
const FACE_E: float = 90.0
const FACE_S: float = 180.0
const FACE_W: float = 270.0
const TOP: float = 120.0 ## vault_height: every surface you can get onto
const TALL: float = 230.0 ## above 210: every piece that stops you
const PEN_HEIGHT: float = 220.0

func _furnish() -> void:
	var g: float = GROUND
	var u: float = UPPER

	# Kitchen (NE). Units along the blank north wall, a short run down the east
	# wall to the side door, the fridge in the corner by the back-hall door, an
	# island north of the west-east doorway line and a table you can get onto.
	_piece(&"fridge", Rect2(MID_HIGH, 1940.0, 120.0, 120.0), g, TALL, FACE_S)
	_run([&"kitchen_counter", &"kitchen_sink", &"kitchen_counter", &"kitchen_stove",
		&"kitchen_counter", &"kitchen_drawers"] as Array[StringName],
		Rect2(1180.0, 1960.0, HIGH - 1180.0, 100.0), g, TOP, FACE_S)
	_run([&"kitchen_drawers", &"kitchen_counter"] as Array[StringName],
		Rect2(1960.0, 1720.0, 100.0, 240.0), g, TOP, FACE_W)
	_run([&"kitchen_drawers", &"kitchen_drawers"] as Array[StringName],
		Rect2(1420.0, 1700.0, 280.0, 120.0), g, TOP, FACE_S)
	_piece(&"dining_table", Rect2(1740.0, 1180.0, 200.0, 140.0), g, TOP, FACE_S)
	_decor(&"microwave", Vector3(1850.0, g + TOP, 2010.0), FACE_S)
	_decor(&"toaster", Vector3(1260.0, g + TOP, 2010.0), FACE_S)
	_decor(&"plant_small", Vector3(1640.0, g + TOP, 1760.0), FACE_S)

	# Front Hall (SE). A console beside the front door, a coat stand in the
	# corner by the kitchen door, a mat and a runner.
	_piece(&"console", Rect2(MID_HIGH, LOW, 280.0, 70.0), g, TOP, FACE_N)
	_piece(&"coat_stand", Rect2(MID_HIGH, MID_LOW - 60.0, 60.0, 60.0), g, 210.0, FACE_E)
	_decor(&"doormat", Vector3(FAR_MID, g, LOW + 50.0), FACE_N)
	_decor(&"rug", Vector3(1420.0, g, 560.0), FACE_E)
	_decor(&"table_lamp", Vector3(1130.0, g + TOP, 65.0), FACE_N)

	# Back Hall (NW). A sideboard by the back door, a bookcase on the jail wall,
	# coats on the kitchen wall.
	_piece(&"sideboard", Rect2(730.0, HIGH - 70.0, MID_LOW - 730.0, 70.0), g, TOP, FACE_S)
	_piece(&"bookcase", Rect2(790.0, MID_HIGH, MID_LOW - 790.0, 70.0), g, TALL, FACE_N)
	_decor(&"doormat", Vector3(NEAR_MID, g, HIGH - 50.0), FACE_S)
	_decor(&"coat_rack", Vector3(MID_LOW - 18.0, g + 150.0, 1860.0), FACE_W)
	_decor(&"plant_small", Vector3(960.0, g + TOP, 2025.0), FACE_S)

	# Jail (SW): a laundry. Washer and dryer on the west wall, open shelving in
	# the corner, and the pen round the holding spot with its gate toward the
	# front-hall door.
	_run([&"washer", &"dryer"] as Array[StringName],
		Rect2(LOW, 60.0, 110.0, 240.0), g, TOP, FACE_E)
	_piece(&"shelf_open", Rect2(790.0, LOW, MID_LOW - 790.0, 70.0), g, TALL, FACE_N)
	_pen(Rect2(400.0, 400.0, 260.0, 260.0), g, FACE_E)

	# Landing A (SE, upstairs): a bookcase on the study wall, a runner.
	_piece(&"bookcase", Rect2(MID_HIGH, LOW, 240.0, 70.0), u, TALL, FACE_N)
	_decor(&"rug", Vector3(1420.0, u, 560.0), FACE_E)

	# Master Bedroom (NE, cash). Bed on the north wall, wardrobes on the east,
	# a chest of drawers on the landing-B wall, the safe in the corner.
	_piece(&"bed_double", Rect2(1440.0, HIGH - 300.0, 240.0, 300.0), u, TOP, FACE_S)
	_run([&"wardrobe", &"wardrobe"] as Array[StringName],
		Rect2(HIGH - 80.0, 1100.0, 80.0, 300.0), u, TALL, FACE_W)
	_piece(&"dresser", Rect2(MID_HIGH, 1100.0, 80.0, 260.0), u, TOP, FACE_E)
	_piece(&"safe", Rect2(HIGH - 140.0, HIGH - 110.0, 140.0, 110.0), u, TOP, FACE_S)
	_decor(&"table_lamp", Vector3(MID_HIGH + 40.0, u + TOP, 1160.0), FACE_E)

	# Study (SW, cash). Desk on the south wall, bookcases on the north, the
	# safe in the corner by the landing-A door.
	_piece(&"desk", Rect2(300.0, LOW, 460.0, 110.0), u, TOP, FACE_N)
	_run([&"bookcase", &"bookcase"] as Array[StringName],
		Rect2(LOW, MID_LOW - 70.0, 320.0, 70.0), u, TALL, FACE_S)
	_piece(&"safe", Rect2(MID_LOW - 140.0, LOW, 140.0, 110.0), u, TOP, FACE_N)
	_decor(&"screen", Vector3(530.0, u + TOP, LOW + 40.0), FACE_N)
	_decor(&"table_lamp", Vector3(360.0, u + TOP, LOW + 50.0), FACE_N)

	# Landing B (NW, upstairs): a sideboard on the north wall with a plant.
	_piece(&"sideboard", Rect2(730.0, HIGH - 70.0, MID_LOW - 730.0, 70.0), u, TOP, FACE_S)
	_decor(&"plant_small", Vector3(960.0, u + TOP, 2025.0), FACE_S)
	_decor(&"rug", Vector3(700.0, u, 1300.0), FACE_N)

## One blocking piece filling `rect` (x, z, width, depth) from `base` up to
## `base + height`; its model is fitted to that box.
func _piece(model: StringName, rect: Rect2, base: float, height: float, face: float) -> void:
	var box: AABB = AABB(Vector3(rect.position.x, base, rect.position.y),
		Vector3(rect.size.x, height, rect.size.y))
	_furniture.append(box)
	_props.append({"model": model, "box": box, "face": face, "fit": true})

## A run of units side by side: ONE collision box for the whole run (fewer
## blockers, no seams to catch on) and one fitted model per equal share of it,
## along the run's long side, in order from low x / low z.
func _run(models: Array[StringName], rect: Rect2, base: float, height: float,
		face: float) -> void:
	var box: AABB = AABB(Vector3(rect.position.x, base, rect.position.y),
		Vector3(rect.size.x, height, rect.size.y))
	_furniture.append(box)
	var along_x: bool = rect.size.x >= rect.size.y
	var share: float = (rect.size.x if along_x else rect.size.y) / float(models.size())
	for i: int in models.size():
		var part: AABB = box
		if along_x:
			part.position.x += share * float(i)
			part.size.x = share
		else:
			part.position.z += share * float(i)
			part.size.z = share
		_props.append({"model": models[i], "box": part, "face": face, "fit": true})

## Dressing that blocks nothing: a rug, a mat, a lamp on a counter, coats on a
## wall. Kept at its own size, standing on `at`.
func _decor(model: StringName, at: Vector3, face: float) -> void:
	_props.append({"model": model, "box": AABB(at, Vector3.ZERO), "face": face, "fit": false})

## The jail pen: bars on four sides, PropPlacement.PEN_BAR thick, PEN_HEIGHT
## tall (it stops you), with a PEN_GATE-wide gap in the middle of the side
## `face` looks toward. Several boxes of collision, one drawn piece.
func _pen(rect: Rect2, base: float, face: float) -> void:
	var bar: float = PropPlacement.PEN_BAR
	var gate: float = PropPlacement.PEN_GATE
	var x0: float = rect.position.x
	var z0: float = rect.position.y
	var x1: float = rect.end.x
	var z1: float = rect.end.y
	var sides: Array[Rect2] = []
	# West and east sides run the full depth; south and north fit between them.
	for at_x: float in [x0, x1 - bar]:
		var open: bool = (face == FACE_W and at_x == x0) or (face == FACE_E and at_x != x0)
		if open:
			var mid: float = (z0 + z1) * 0.5
			sides.append(Rect2(at_x, z0, bar, mid - gate * 0.5 - z0))
			sides.append(Rect2(at_x, mid + gate * 0.5, bar, z1 - mid - gate * 0.5))
		else:
			sides.append(Rect2(at_x, z0, bar, z1 - z0))
	for at_z: float in [z0, z1 - bar]:
		var open_z: bool = (face == FACE_S and at_z == z0) or (face == FACE_N and at_z != z0)
		if open_z:
			var mid_x: float = (x0 + x1) * 0.5
			sides.append(Rect2(x0 + bar, at_z, mid_x - gate * 0.5 - x0 - bar, bar))
			sides.append(Rect2(mid_x + gate * 0.5, at_z, x1 - bar - mid_x - gate * 0.5, bar))
		else:
			sides.append(Rect2(x0 + bar, at_z, x1 - x0 - bar * 2.0, bar))
	for side: Rect2 in sides:
		_furniture.append(AABB(Vector3(side.position.x, base, side.position.y),
			Vector3(side.size.x, PEN_HEIGHT, side.size.y)))
	_props.append({"model": &"jail_pen", "face": face, "fit": true,
		"box": AABB(Vector3(x0, base, z0), Vector3(rect.size.x, PEN_HEIGHT, rect.size.y))})

## §4. Front Hall (SE, front door + main stair), Kitchen (NE, side door),
## Back Hall (NW, back door + second stair), Jail (SW, no exterior opening).
## Five ways onto this floor: front door, back door, side door, and the two
## ground windows (Back Hall west, Front Hall east), both slow two-way climbs.
func _ground() -> void:
	var top: float = GROUND + STOREY - SLAB
	# West outer: Back Hall window (G6), moved south of the second stair's top.
	_wall_x(WALL * 0.5, 0.0, HOUSE, GROUND, top, [
		Vector2(1105.0, 1345.0), # G6 Back Hall (NW) west window, south of stair top
	] as Array[Vector2])
	# East outer: Kitchen side door (G4), Front Hall window (G2, north of the
	# main stair's top).
	_wall_x(HOUSE - WALL * 0.5, 0.0, HOUSE, GROUND, top, [
		_at(FAR_MID, DOOR), # G4 SIDE DOOR, Kitchen (NE) east
		Vector2(745.0, 985.0), # G2 Front Hall (SE) east window, north of stair top
	] as Array[Vector2])
	# South outer: Front Hall front door (G1).
	_wall_z(WALL * 0.5, WALL, HOUSE - WALL, GROUND, top, [
		_at(FAR_MID, DOOR), # G1 FRONT DOOR, Front Hall (SE) south
	] as Array[Vector2])
	# North outer: Back Hall back door (G5).
	_wall_z(HOUSE - WALL * 0.5, WALL, HOUSE - WALL, GROUND, top, [
		_at(NEAR_MID, DOOR), # G5 BACK DOOR, Back Hall (NW) north
	] as Array[Vector2])
	_ring(GROUND, top, [
		&"D1", # Front Hall <-> Kitchen
		&"D2", # Kitchen <-> Back Hall
		&"D3", # Back Hall <-> Jail
		&"D4", # Jail <-> Front Hall
	])

	# No basement in Phase 1: the ground floor's own slab has nothing below it
	# to hole for. Only the stairwells punch through to the storey ABOVE, and
	# that hole lives in _upper()'s slab, not this one.


## §5. Landing A (SE, head of main stair), Master Bedroom (NE, cash), Landing B
## (NW, head of second stair), Study (SW, cash). Both cash rooms open onto
## both landings - two independent approaches, neither holdable alone.
func _upper() -> void:
	var top: float = UPPER + STOREY - SLAB
	# West outer: Study escape window (U4), toward the front of the house so it
	# clears stair B - the second flight runs up the inside of this wall from
	# z 1334 to 2030, and a window over it opens onto the staircase rather than
	# onto air. NEAR_MID puts it at z 530, well clear.
	_wall_x(WALL * 0.5, 0.0, HOUSE, UPPER, top, [
		_at(NEAR_MID, WINDOW), # U4 Study (SW) escape, one-way down
	] as Array[Vector2])
	# East outer: nothing passable. This face looks straight across the 500-unit
	# corridor at the other house - the closest, most exposed wall either house
	# has - so no escape route opens onto it (see U2 below).
	_wall_x(HOUSE - WALL * 0.5, 0.0, HOUSE, UPPER, top, [] as Array[Vector2])
	# South outer: nothing. The Study now escapes west (above), and giving one
	# room two exits would hand it the cheapest route twice over.
	_wall_z(WALL * 0.5, WALL, HOUSE - WALL, UPPER, top, [] as Array[Vector2])
	# North outer: Landing B's door onto the outside back staircase (P3-8),
	# over the back door. The Master Bedroom side of this wall stays blank.
	#
	# Master Bedroom escape window (U2), and this is the honest
	# answer rather than the one that sounded best.
	#
	# U2 HAS MOVED THREE TIMES and is back where the second move put it. The
	# history is worth keeping because two of the three were reasoned rather
	# than measured:
	#
	#   EAST, originally. Faces straight across the corridor; a raider was over
	#   the sill and home in seconds.
	#
	#   NORTH, on the reasoning that the houses sit diagonally. Better, but the
	#   run home was still only 5 legs against 20-23 out, which a player found
	#   and described as "the same easy monotonous route".
	#
	#   WEST, to put it on the furthest face. WRONG TWICE OVER, and the frame
	#   showed it: the west wall does not border the Master Bedroom at all - the
	#   bedroom is the NE quadrant and the west wall serves NW and SW - so the
	#   window opened out of the wrong room, over stair B's flight, which runs
	#   up the inside of that wall from z 1334 to 2030. It read as broken
	#   geometry because it was.
	#
	# THE BEDROOM HAS ONLY TWO EXTERIOR FACES, east and north, and both are
	# near: 1648 and 2097 from the other house's centre, against the study's
	# 3902 and 3681. There is no far wall to move the window to, so it is gone.
	#
	# THE NEAR CASH ROOM HAS NO DROP. Take its cash and you carry it back down
	# the stairs and out of a door, which is the long way and is the point - the
	# quick exit now belongs to the STUDY, the far room, so crossing the house
	# to reach it is a real decision rather than a formality. A one-way drop
	# that lands a raider nearly home was the whole complaint, and on this
	# quadrant every wall does that.
	#
	# The room still has TWO WAYS IN, which is what routes_required actually
	# checks: both landings open onto it. The window was never one of them - it
	# is a one-way drop and cannot be entered through - so removing it costs the
	# gate nothing, and the gate agrees.
	_wall_z(HOUSE - WALL * 0.5, WALL, HOUSE - WALL, UPPER, top, [
		_at(BACK_DOOR_X, DOOR), # U5 Landing B (NW) north, to the back staircase
	] as Array[Vector2])
	_ring(UPPER, top, [
		&"D5", # Landing A <-> Master Bedroom
		&"D6", # Master Bedroom <-> Landing B
		&"D7", # Landing B <-> Study
		&"D8", # Study <-> Landing A
	])

	_slab_at(UPPER, Rect2(0.0, 0.0, HOUSE, HOUSE),
		[_stairwell(STAIR_A_X, STAIR_A_Z, 1.0, -1.0),
		_stairwell(STAIR_B_X, STAIR_B_Z, -1.0, 1.0)] as Array[Rect2], SLAB)
	# The roof. No holes: nothing goes up from the top floor.
	_slab_at(ROOF, Rect2(0.0, 0.0, HOUSE, HOUSE), [] as Array[Rect2], SLAB)

## The four internal doorways that make each floor a ring (§4, §5, §7 D1-D8).
##
## A ring rather than a chain is the whole reason a chase can circulate instead
## of ending in a corner. `tags` is unused by the geometry - it exists so the
## call site can read which D-number each doorway is, matching §7's schedule.
func _ring(level: float, top: float, _tags: Array[StringName]) -> void:
	_wall_x(SPLIT, WALL, HOUSE - WALL, level, top, [
		_at(FAR_MID, DOOR), # NW <-> NE / Landing B <-> Master Bedroom
		_at(NEAR_MID, DOOR), # SW <-> SE / Study <-> Landing A
	] as Array[Vector2])
	_wall_z(SPLIT, WALL, HOUSE - WALL, level, top, [
		_at(NEAR_MID, DOOR), # NW <-> SW / Back Hall <-> Jail, Landing B <-> Study
		_at(FAR_MID, DOOR), # NE <-> SE / Kitchen <-> Front Hall, Bedroom <-> Landing A
	] as Array[Vector2])

## §2. One straight flight per stair, ten steps, no switchback. Both stairs
## climb ONE storey (ground -> upper) since Phase 1 has no basement.
##
## Stair A runs +z (north) from its base at the front door. Stair B runs -z
## (south) from its base at the back door - the mirror direction, so the base
## sits beside its own door rather than both stairs climbing the same way.
##
## Stair A hugs the EAST wall, so its open flank faces -x. Stair B hugs the
## WEST wall, so its open flank faces +x. That is a mirror, not a rotation,
## so it cannot be derived from `dir` and is passed as `open_side` for the
## stairwell void to grow the correct way (see _stairwell).
func _stairs() -> void:
	_straight_flight(STAIR_A_X, STAIR_A_Z, GROUND, 1.0) # main stair, +z
	_straight_flight(STAIR_B_X, STAIR_B_Z, GROUND, -1.0) # second stair, -z

## One storey of stairs: ten steps in a single flight, hugging a wall.
##
## `dir` is +1.0 or -1.0: the flight climbs from (x, z) toward increasing or
## decreasing z. The first riser sits STAIR_LANDING past `z` so the flight does
## not start flush against the doorway; step i's near edge is at
## z + dir * (STAIR_LANDING + RUN * i), so both stairs share one function
## despite climbing opposite ways.
##
## TREADS ARE TREADS, NOT COLUMNS. Each step is a slab one riser thick at its
## own height, not a solid block from floor level up - a solid block would
## make the flight a ceiling over whatever is beneath it. Phase 1 only stacks
## one storey per stair, so that failure mode (the three-storey build's
## stacked-stair collision) cannot recur here, but the shape stays correct
## regardless.
##
## SOLID UNDERNEATH. Floating treads leave walkable floor under the flight, so
## the fill puts stances there, a body walks under the stairs, and its head
## goes into the treads above - which is what "walking through the steps"
## actually is. Measured: 118 mid-flight stances had a standing body's head
## inside geometry, and the overlaps named TREADS, not the slab.
##
## The soffit under each tread removes them. It is the tread's own box
## extended down to the floor - same x, same z, same width, no separate
## object anywhere near a tread.
##
## THAT DISTINCTION WAS THE LESSON of five failed attempts to close this by
## adding a wall as well - every one of them broke the fill's stance
## connectivity, because a solid merely NEAR a tread shrinks the body-radius-
## grown footprint around the neighbouring stance column. There is no wall
## here; the open flank stays open.
##
## SOFFITS TOUCH, EDGE TO EDGE. Do not inset them, and in particular do not
## inset one to "make room" for the body-radius growth of its neighbour.
##
## The temptation is real, because the overlap it addresses is real: a body
## settling onto tread N sweeps straight down at tread N's own z, and tread
## N+1's soffit - immediately adjacent, one riser taller - grows by the body
## radius under any swept test, reaching backward across the seam into tread
## N's airspace. Pulling each soffit's near edge back by BODY does stop that,
## and a targeted probe confirms the specific segment unblocks.
##
## It was still wrong, twice over. Visually it is a comb: tread N's soffit is
## one riser SHORTER than tread N+1's, so it cannot cover the strip N+1 gave
## up, and the flight renders as a row of detached fins with daylight between
## them. And it fixed nothing - a six-minute bot match either side of the
## change produced bit-identical stall counts, same 307 at the same bucket,
## same digest. Whatever the bots are catching on, it is not this.
##
## The stall is a STEERING problem, not a geometry one: mid-climb the bot's
## move_intent flips from (0,0,1) to a pure lateral (-1,0,0) and the body
## wedges against the flank. Start at BotDirector._steer(), not here.
func _straight_flight(x: float, z: float, base: float, dir: float) -> void:
	for i: int in FLIGHT_STEPS:
		var top: float = base + STEP * float(i + 1)
		var near: float = z + dir * (STAIR_LANDING + RUN * float(i))
		var lo: float = minf(near, near + dir * RUN)
		_solid(AABB(Vector3(x, top - STEP, lo), Vector3(FLIGHT_W, STEP, RUN)))
		# Step 0 sits on the floor, so its soffit is zero-height and _blocker
		# drops it. Every other step gets the void beneath it filled.
		_solid(AABB(Vector3(x, base, lo), Vector3(FLIGHT_W, top - STEP - base, RUN)))

## The opening a flight needs in the floor above it.
##
## An earlier version cut only the top of the run - the theory being a
## climbing body's head only reaches the slab once it is far enough up the
## flight - and it produced exactly the failure a partial cut invites: the
## visible ceiling did not line up with where a body's head actually was,
## because the cut was derived from a per-step head-height calculation rather
## than from the flight's own geometry, and the two drifted. A player watching
## from outside saw the character clip through solid floor.
##
## The stair already owns its whole corner of the room - nothing else needs
## that ceiling - so the fix is to stop being clever and cut the WHOLE
## footprint, landing included, base to top. A void that is larger than
## strictly necessary is invisible; a void that is wrong by even one cell is
## not.
##
## GROWN BY A BODY RADIUS on every side a body can overhang. The fill puts a
## stance at a body's CENTRE, so a body standing on the outermost sliver of a
## tread has 20 units of itself hanging past the tread's edge. Cut the void to
## the flight's exact footprint and that overhang is inside the slab - which is
## precisely the "walking through the steps" a player sees, with the capsule
## sunk waist-deep at the top of the run.
##
## Grown on THREE sides, not four. The flight hugs an exterior wall along one
## long side, and a body cannot overhang into a wall that is already stopping
## it - growing there would push the void into the wall's own footprint and
## cut a slot through the building (measured: x reaches 2080 against an inner
## face at 2060). `open_side` is -1.0 when the open flank is at low x (stair A,
## hugging the east wall) and +1.0 when it is at high x (stair B, hugging the
## west wall).
##
## `dir` matches _straight_flight: the footprint runs from the base (at `z`)
## to the top of the flight, `STAIR_LANDING + FLIGHT_RUN` further along in
## whichever direction the stair climbs. Both ENDS are grown regardless of
## `dir` - a body overhangs the bottom of the run stepping on, and the top of
## it stepping off.
func _stairwell(x: float, z: float, dir: float, open_side: float) -> Rect2:
	var far: float = z + dir * (STAIR_LANDING + FLIGHT_RUN)
	var lo: float = minf(z, far) - BODY
	var hi: float = maxf(z, far) + BODY
	var from_x: float = x - (BODY if open_side < 0.0 else 0.0)
	var to_x: float = x + FLIGHT_W + (BODY if open_side > 0.0 else 0.0)
	return Rect2(from_x, lo, to_x - from_x, hi - lo)

## An opening centred on `centre`, `width` across.
func _at(centre: float, width: float) -> Vector2:
	return Vector2(centre - width * 0.5, centre + width * 0.5)

# ---- placing it twice (§9) ----

## `turned` rotates the house 180 degrees about the middle of the lot, so the
## two fronts face away from each other and the layout is identical for both
## teams without mirroring - mirroring in x once produced two houses facing
## the same way (§9).
func _stamp(turned: bool, team: StringName, side: String) -> void:
	for box: AABB in _solids:
		_blocker(_place(box, turned))
	for box: AABB in _furniture:
		_blocker(_place(box, turned), "blocker_furniture")
	# Drawn pieces. The half turn turns every piece's facing with it.
	for i: int in _props.size():
		var prop: Dictionary = _props[i]
		var box: AABB = prop["box"]
		var placed: AABB = _place(box, turned)
		var marker: Marker3D = Marker3D.new()
		marker.name = "prop_%s_%d" % [side, i]
		marker.position = placed.position + placed.size * 0.5
		marker.set_meta(&"model", prop["model"])
		marker.set_meta(&"box", placed)
		marker.set_meta(&"yaw_deg", fmod(float(prop["face"]) + (180.0 if turned else 0.0), 360.0))
		marker.set_meta(&"fit", prop["fit"])
		# A yard prop's drawing depends on whose yard it is (P3-8).
		if prop.get("yard", false):
			marker.set_meta(&"family", team)
		_root.add_child(marker)

	# §3 vertical stacking. Both floors share the same four quadrants.
	var rooms: Array[Array] = [
		# id, role, x, z, y
		[&"front_hall", ZoneDef.Role.HOME, MID_HIGH, LOW, GROUND],
		[&"kitchen", ZoneDef.Role.HOME, MID_HIGH, MID_HIGH, GROUND],
		[&"back_hall", ZoneDef.Role.HOME, LOW, MID_HIGH, GROUND],
		[&"jail", ZoneDef.Role.JAIL, LOW, LOW, GROUND],
		[&"landing_a", ZoneDef.Role.HOME, MID_HIGH, LOW, UPPER],
		[&"bedroom", ZoneDef.Role.CASH_ROOM, MID_HIGH, MID_HIGH, UPPER],
		[&"landing_b", ZoneDef.Role.HOME, LOW, MID_HIGH, UPPER],
		[&"study", ZoneDef.Role.CASH_ROOM, LOW, LOW, UPPER],
	]
	for room: Array in rooms:
		_zone(StringName("%s_%s" % [room[0], side]), room[1], team, 1,
			_place(AABB(Vector3(room[2], room[4], room[3]),
				Vector3(QUAD, STOREY, QUAD)), turned), false)

	# §9: spawns in the team's own yard, along the back and side faces.
	for i: int in SPAWN_LOCAL.size():
		_marker("spawn_%s_%d" % [team, i], _place_point(Vector3(
			SPAWN_LOCAL[i].x, GROUND + BODY, SPAWN_LOCAL[i].y), turned))

	# §5/§9: cash split randomly each round between Master Bedroom and Study.
	# Both rooms carry markers; which ones are live is a spawn rule, not
	# geometry. Two markers per room, spaced across its floor.
	for i: int in 2:
		_marker("cash_%s_%d" % [team, i], _place_point(Vector3(
			MID_HIGH + 250.0 + 400.0 * float(i), UPPER + BODY, FAR_MID), turned))
	for i: int in 2:
		_marker("cash_%s_%d" % [team, i + 2], _place_point(Vector3(
			LOW + 250.0 + 400.0 * float(i), UPPER + BODY, NEAR_MID), turned))

## House-local to lot coordinates.
##
## The turn is ONE rotation about the middle of the lot, so it is applied to
## the unrotated placement rather than to a second origin: `LOT - (A + local) -
## size`. Feeding House B's own origin in and THEN negating applies the offset
## twice. House B's origin is not an input - it falls out of the arithmetic.
func _place(box: AABB, turned: bool) -> AABB:
	var x: float = HOUSE_A_X + box.position.x
	var z: float = HOUSE_A_Z + box.position.z
	if turned:
		x = LOT_W - x - box.size.x
		z = LOT_D - z - box.size.z
	return AABB(Vector3(x, box.position.y, z), box.size)

## A house-local POINT in lot coordinates. Not a one-unit box's corner: that
## turns onto the opposite corner, which put every House B marker one unit off
## its twin (found by tools/symmetry_probe.gd).
func _place_point(local: Vector3, turned: bool) -> Vector3:
	return _place(AABB(local, Vector3.ZERO), turned).position

## §9 territory, as changed by P3-8: the boundary fence on the lot's x midline
## is the line. Each family owns everything on its side of it, house and yard;
## there is no neutral ground (the old 400-unit yards and the NEUTRAL `lot`
## zone under them are gone). A defender may seize an intruder anywhere on its
## own side; nobody is seized on their own side.
func _outdoors() -> void:
	var high: float = LOT_H - GROUND
	var midline: float = LOT_W * 0.5
	for turned: bool in [false, true]:
		var from_x: float = midline if turned else 0.0
		# Priority 0: the yard WRAPS the house, so every room overlaps it.
		# Rooms win, and the yard is only what is left over outside them. The
		# two yards touch on the midline and do not overlap.
		_zone(&"yard_b" if turned else &"yard_a", ZoneDef.Role.HOME,
			&"team_b" if turned else &"team_a", 0,
			AABB(Vector3(from_x, GROUND, 0.0), Vector3(midline, high, LOT_D)), true)
	_fence(midline)

## The boundary fence: solid along the midline except the main gate in the
## middle and a small crossing CROSSING_IN from each end. Named as furniture
## (`blocker_furniture_*`) so the shell does not draw it as a brick wall;
## ExteriorBuilder draws it as a timber fence from these boxes.
func _fence(midline: float) -> void:
	var middle: float = LOT_D * 0.5
	var gaps: Array[Vector2] = [
		_at(CROSSING_IN, CROSSING),
		_at(middle, GATE),
		_at(LOT_D - CROSSING_IN, CROSSING),
	]
	var cursor: float = 0.0
	for gap: Vector2 in gaps:
		_fence_panel(midline, cursor, gap.x)
		cursor = gap.y
	_fence_panel(midline, cursor, LOT_D)

func _fence_panel(midline: float, from_z: float, to_z: float) -> void:
	_blocker(AABB(Vector3(midline - FENCE_THICK * 0.5, GROUND, from_z),
		Vector3(FENCE_THICK, FENCE_HEIGHT, to_z - from_z)), "blocker_furniture_fence")

# ---- primitives ----

func _wall_x(x: float, from: float, to: float, base: float, top: float,
		gaps: Array[Vector2]) -> void:
	for piece: Vector4 in _panels(from, to, base, top, gaps):
		_solid(AABB(Vector3(x - WALL * 0.5, piece.z, piece.x),
			Vector3(WALL, piece.w - piece.z, piece.y - piece.x)))

func _wall_z(z: float, from: float, to: float, base: float, top: float,
		gaps: Array[Vector2]) -> void:
	for piece: Vector4 in _panels(from, to, base, top, gaps):
		_solid(AABB(Vector3(piece.x, piece.z, z - WALL * 0.5),
			Vector3(piece.y - piece.x, piece.w - piece.z, WALL)))

## A wall as the parts of it that are still there. A doorway is an ABSENCE (§2).
func _panels(from: float, to: float, base: float, top: float,
		gaps: Array[Vector2]) -> Array[Vector4]:
	var pieces: Array[Vector4] = []
	var ordered: Array[Vector2] = gaps.duplicate()
	ordered.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var cursor: float = from
	for raw: Vector2 in ordered:
		# Clamped to the wall's own extent, so an opening near a corner cannot
		# run its lintel out past the end and into the wall round it.
		var gap: Vector2 = Vector2(maxf(raw.x, from), minf(raw.y, to))
		if gap.y <= gap.x:
			continue
		if gap.x > cursor:
			pieces.append(Vector4(cursor, gap.x, base, top))
		if base + HEAD < top:
			pieces.append(Vector4(gap.x, gap.y, base + HEAD, top))
		cursor = maxf(cursor, gap.y)
	if cursor < to:
		pieces.append(Vector4(cursor, to, base, top))
	return pieces

## A floor with holes in it, cut on the holes' own edges and merged back along x.
func _slab_at(top: float, area: Rect2, holes: Array[Rect2], thick: float) -> void:
	var xs: Array[float] = [area.position.x, area.end.x]
	var zs: Array[float] = [area.position.y, area.end.y]
	for hole: Rect2 in holes:
		xs.append_array([hole.position.x, hole.end.x])
		zs.append_array([hole.position.y, hole.end.y])
	xs.sort()
	zs.sort()
	for zi: int in zs.size() - 1:
		if zs[zi + 1] - zs[zi] < 0.5:
			continue
		var run_from: float = -1.0
		var run_to: float = -1.0
		for xi: int in xs.size() - 1:
			if xs[xi + 1] - xs[xi] < 0.5:
				continue
			var centre: Vector2 = Vector2(
				(xs[xi] + xs[xi + 1]) * 0.5, (zs[zi] + zs[zi + 1]) * 0.5)
			var open: bool = false
			for hole: Rect2 in holes:
				if hole.has_point(centre):
					open = true
					break
			if open:
				_slab_piece(top, run_from, run_to, zs[zi], zs[zi + 1], thick)
				run_from = -1.0
				continue
			if run_from < 0.0:
				run_from = xs[xi]
			run_to = xs[xi + 1]
		_slab_piece(top, run_from, run_to, zs[zi], zs[zi + 1], thick)

## `from` of -1 means "no run is open" - a sentinel, not a coordinate. The lot
## slab legitimately starts at x=0, so the test has to be for the sentinel
## itself rather than for any negative number.
func _slab_piece(top: float, from: float, to: float, z0: float, z1: float,
		thick: float) -> void:
	if from < -0.5 or to - from < 0.5:
		return
	_solid(AABB(Vector3(from, top - thick, z0), Vector3(to - from, thick, z1 - z0)))

func _solid(box: AABB) -> void:
	if _terrain_slab:
		_blocker(box.abs())
		return
	_solids.append(box.abs())

# ---- scene ----

func _own(node: Node) -> void:
	for child: Node in node.get_children():
		child.owner = _root
		_own(child)

func _box(node_name: String, at: Vector3, size: Vector3) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = node_name
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	_root.add_child(node)
	return node

func _blocker(box: AABB, prefix: String = "blocker") -> void:
	if box.size.x < 0.5 or box.size.y < 0.5 or box.size.z < 0.5:
		return
	_count += 1
	_box("%s_%d" % [prefix, _count], box.position + box.size * 0.5, box.size)

func _zone(id: StringName, role: ZoneDef.Role, team: StringName, priority: int,
		bounds: AABB, outdoor: bool) -> void:
	var node: BlockoutZone = BlockoutZone.new()
	node.name = "zone_%s" % id
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = bounds.size
	node.mesh = mesh
	node.position = bounds.position + bounds.size * 0.5
	node.zone_id = id
	node.role = role
	node.owner_team = team
	node.priority = priority
	node.outdoor = outdoor
	_root.add_child(node)

func _marker(node_name: String, at: Vector3) -> void:
	var node: Marker3D = Marker3D.new()
	node.name = node_name
	node.position = at
	_root.add_child(node)
