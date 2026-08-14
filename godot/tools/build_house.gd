extends SceneTree
## Builds the house and the lot from HOUSE_LAYOUT.md.
##
##   godot --headless --path godot --script res://tools/build_house.gd
##
## THE SPEC IS THE SOURCE. Every dimension, opening and coordinate below is
## quoted from HOUSE_LAYOUT.md - §2 dimensions, §3 stacking, §4-6 the floors,
## §11 the opening schedule, §12 the lot. Where a number here disagrees with
## that document the document wins and this file is wrong.
##
## Three floors, four quadrants, six rooms, two switchback staircases. Compact
## and heavily perforated: the possibility space comes from connection density
## rather than floor area (§1).
##
## The house is drawn ONCE in house-local coordinates and stamped twice, the
## second copy rotated 180 degrees about the middle of the lot (§9). Two
## hand-written copies would drift, and a difference between the two houses is a
## balance bug nobody can see.

# ---- §2 dimensions ----
const STEP: float = 30.0
const RUN: float = 64.0 ## a tread offers run-BODY of standable depth; that has
                        ## to clear a 40-unit sample cell (WORLD_AUTHORING §11)
const STOREY: float = 300.0 ## 10 steps exactly - §12 requires whole steps
const QUAD: float = 750.0 ## §2: above the camera minimum at the diagonal
const WALL: float = 30.0
const DOOR: float = 240.0
const SLAB: float = 40.0
const HEAD: float = 240.0 ## §11 drafting note: doorway head +240
const BODY: float = 20.0 ## TuningDef.actor_radius
const BODY_HEIGHT: float = 180.0 ## how tall the thing walking it LOOKS

## Window openings. Sills from the plan set's drafting assumptions.
const WINDOW: float = 240.0
const SILL_UPPER: float = 80.0
const SILL_GROUND: float = 90.0
const VENT_HEIGHT: float = 90.0 ## §11: crawl height

# ---- §3 heights ----
const BASEMENT: float = 0.0
const GROUND: float = 300.0 ## garden / terrain surface sits here
const UPPER: float = 600.0
const ROOF: float = 900.0

# ---- §11 house-local grid ----
#
#    Z=1590 +--------------+--------------+
#           |      NW      |      NE      |
#           |   30-780     |  810-1560    |
#    Z= 810 +--------------+--------------+
#    Z= 780 |      SW      |      SE      |
#           |   30-780     |  810-1560    |
#    Z=  30 +--------------+--------------+
#         X=30           780  810       1560
const LOW: float = WALL ## 30 - inner face of the outer wall
const MID_LOW: float = LOW + QUAD ## 780 - near face of the internal wall
const MID_HIGH: float = MID_LOW + WALL ## 810 - far face
const HIGH: float = MID_HIGH + QUAD ## 1560
const HOUSE: float = HIGH + WALL ## 1590 square (§2)

## Centre of an internal wall, for _wall_x / _wall_z which take a centreline.
const SPLIT: float = MID_LOW + WALL * 0.5 ## 795

## Quadrant centres, for openings that sit in the middle of a room's face.
const NEAR_MID: float = LOW + QUAD * 0.5 ## 405
const FAR_MID: float = MID_HIGH + QUAD * 0.5 ## 1185

# ---- §2 switchback stairs ----
#
# A straight flight is 10 x 64 = 640 and a quadrant is 750: two straight
# staircases would eat most of the house. Folded in half they are 560 x 580,
# which is the only reason this plan can afford two (§2).
const HALF_FLIGHT: int = 5
const FLIGHT_RUN: float = RUN * float(HALF_FLIGHT) ## 320
const FLIGHT_W: float = 280.0
const LANDING_D: float = 260.0
const STAIR_W: float = FLIGHT_W * 2.0 ## 560
const STAIR_D: float = FLIGHT_RUN + LANDING_D ## 580

## Both stairs are CENTRED in their quadrant, snapped to the 40 sampling grid.
##
## North is -z: NW is the low-x, low-z corner. Both of these used to be in the
## wrong quadrant - A at z=940 was in SW (Bedroom / Living / Boiler) and B at
## z=200 was in NE (Vault / Kitchen). The comments below were right the whole
## time; the numbers were not. It broke far more than the geometry, because §6's
## basement argument rests on the main stair landing in the NW Stair foot: with
## A in the SW the cellar and boiler lost their second way out and the escape-
## ability gate was correct to refuse the level.
##
## Centring leaves 95 of slack on x and 85 on z inside a 750 quadrant - enough
## that the body-grown stairwell opening stays clear of all four walls.

## §12: team spawns sit in the team's OWN yard, spread along the back and side
## faces. House-local, so `_place` mirrors them onto B's own yard.
##
## They used to be at x = HOUSE + 150, which is 150 PAST the east wall - in the
## corridor between the two houses. That is the contested middle: both teams
## started on neutral ground, nobody started at home, and the yard a defender is
## supposed to own was empty at the whistle.
##
## Negative x is the back (west) face; the third sits off the north side face so
## a squad does not spawn in a single line.
const SPAWN_LOCAL: Array[Vector2] = [
	Vector2(-150.0, 400.0),
	Vector2(-150.0, 1000.0),
	Vector2(400.0, -150.0),
]

## Main stair, NW quadrant: basement to upper, the spine (§3).
const STAIR_A_X: float = 120.0
const STAIR_A_Z: float = 120.0
## Second stair, SE quadrant: ground to upper only (§3, §5).
const STAIR_B_X: float = 920.0
const STAIR_B_Z: float = 880.0

# ---- §4, §11 the laundry chute ----
#
# Opens in Landing A's east wall, drops down the NW/NE boundary into the Cellar
# two floors below. The shaft is SEALED everywhere except its intake and its
# exit - a blocker in the Vault above and the Kitchen below (§4).
const CHUTE: float = 200.0
const CHUTE_X: float = MID_HIGH ## 810 - hard against the internal wall
const CHUTE_Z: float = 1360.0

# ---- §12 the lot ----
## §12 gives 4900 x 3450 with 550 margins. Neither is a whole number of
## sampling cells - 122.5 and 86.25 - and the guard below refuses that, because a
## turned copy landing at a different phase against the fill grid silently
## differs from its twin. Rounded UP to the next whole cell, 4920 x 3480, and
## House B moved 20/30 to keep the point symmetry exact. Every margin in the spec
## is preserved: 550 outside, 620 corridor.
const LOT_W: float = 4920.0 # 123 cells
const LOT_D: float = 3480.0 # 87 cells
const HOUSE_A_X: float = 550.0
const HOUSE_A_Z: float = 550.0
const HOUSE_B_X: float = LOT_W - HOUSE_A_X - HOUSE ## 2780
const HOUSE_B_Z: float = LOT_D - HOUSE_A_Z - HOUSE ## 1340
const LOT_H: float = ROOF + SLAB
## §12: ground within 400 of a house's outer wall belongs to that house.
const TERRITORY: float = 400.0

## The walkable fill samples at cell centres, so the 180-degree turn maps a
## sampled point to another sampled point only when the lot is a whole number of
## cells across. Otherwise the turned copy lands at a different PHASE against the
## grid and identical geometry produces a different surface - measured once at
## 4,072 stances against 3,986, with different route counts for the same rooms.
## See WORLD_AUTHORING §11.
const CELL: float = 40.0

var _solids: Array[AABB] = []
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
	print("lot %d x %d x %d, %d blockers, 6 rooms + basement per house" % [
		int(LOT_W), int(LOT_D), int(LOT_H), _count])
	quit(0)

# ---- the ground the lot sits on ----

## Garden at y=300, and solid earth below it everywhere the basement is not.
##
## The basement is genuinely below grade (§3), so the terrain is a slab with the
## two basement footprints and their outside entrances cut out of it. Digging the
## holes rather than building walls round them means the sides of the pit ARE the
## earth - no redundant boxes buried inside the ground they duplicate.
func _terrain() -> void:
	var holes: Array[Rect2] = []
	for turned: bool in [false, true]:
		# The L: NW, NE, SW. The south-east quadrant is solid earth (§6).
		holes.append(_flat(Rect2(0.0, MID_LOW, HOUSE, HOUSE - MID_LOW), turned))
		holes.append(_flat(Rect2(0.0, 0.0, MID_HIGH, MID_LOW), turned))
		# The exterior basement steps, descending from the north garden (§12).
		holes.append(_flat(Rect2(1280.0, HOUSE, 250.0, 640.0), turned))

	# One slab from y=0 to grade, holed for the basements. Terrain IS the earth.
	#
	# Emitted STRAIGHT TO BLOCKERS, not through `_solids`. That list is the house
	# drawn in house-local coordinates and everything in it gets stamped twice -
	# once turned. The terrain is already lot-space and singular; putting it
	# through the stamp rotated the whole map off its west edge.
	_terrain_slab = true
	_slab_at(GROUND, Rect2(0.0, 0.0, LOT_W, LOT_D), holes, GROUND)
	_terrain_slab = false

## A house-local footprint in lot coordinates, ignoring height.
func _flat(local: Rect2, turned: bool) -> Rect2:
	var box: AABB = _place(AABB(
		Vector3(local.position.x, 0.0, local.position.y),
		Vector3(local.size.x, 1.0, local.size.y)), turned)
	return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)

# ---- one house, in local coordinates ----

func _draw_house() -> void:
	_basement()
	_ground()
	_upper()
	_stairs()
	_chute()

## §6. L-shaped, open arches rather than doors: a prisoner must have more than
## one way out, and open space is the cheapest way to guarantee it.
func _basement() -> void:
	var top: float = BASEMENT + STOREY - SLAB

	# Outer walls of the L. The south-east quadrant is earth, so the shell
	# steps in: east wall runs only to the NE/SE boundary, south wall only to
	# the NW/SW boundary.
	_wall_x(WALL * 0.5, 0.0, HOUSE, BASEMENT, top, [
		_at(NEAR_MID, WINDOW), # coal chute, west face (§11)
	] as Array[Vector2])
	_wall_x(HOUSE - WALL * 0.5, MID_LOW, HOUSE, BASEMENT, top, [] as Array[Vector2])
	_wall_z(WALL * 0.5, WALL, MID_HIGH, BASEMENT, top, [
		_at(NEAR_MID, WINDOW), # vent, south face (§11)
	] as Array[Vector2])
	_wall_z(HOUSE - WALL * 0.5, WALL, HOUSE - WALL, BASEMENT, top, [
		_at(1405.0, 250.0), # exterior basement steps, into the CELLAR (§6)
	] as Array[Vector2])
	# The two faces that close the L off from the solid earth beyond it.
	_wall_z(SPLIT, MID_HIGH, HOUSE, BASEMENT, top, [] as Array[Vector2])
	_wall_x(SPLIT, WALL, MID_LOW, BASEMENT, top, [] as Array[Vector2])

	# Wide arches, not doors. 480 across, full storey height (§11).
	_wall_x(SPLIT, MID_HIGH, HOUSE, BASEMENT, top,
		[_at(1185.0, 480.0)] as Array[Vector2])
	_wall_z(SPLIT, WALL, MID_LOW, BASEMENT, top,
		[_at(405.0, 480.0)] as Array[Vector2])

## §5. Three doors on three faces plus five climbable windows - eight ways onto
## this floor.
func _ground() -> void:
	var top: float = GROUND + STOREY - SLAB
	_wall_x(WALL * 0.5, 0.0, HOUSE, GROUND, top, [
		_at(FAR_MID, WINDOW), # Back Hall west window
		_at(NEAR_MID, WINDOW), # Living west window
	] as Array[Vector2])
	_wall_x(HOUSE - WALL * 0.5, 0.0, HOUSE, GROUND, top, [
		_at(FAR_MID, DOOR), # SIDE DOOR, Kitchen east
		_at(NEAR_MID, WINDOW), # Front Hall east window
	] as Array[Vector2])
	_wall_z(WALL * 0.5, WALL, HOUSE - WALL, GROUND, top, [
		_at(NEAR_MID, WINDOW), # Living south window
		_at(FAR_MID, DOOR), # FRONT DOOR, Front Hall south
	] as Array[Vector2])
	_wall_z(HOUSE - WALL * 0.5, WALL, HOUSE - WALL, GROUND, top, [
		_at(NEAR_MID, DOOR), # BACK DOOR, Back Hall north
		_at(FAR_MID, WINDOW), # Kitchen north window
	] as Array[Vector2])
	_ring(GROUND, top)

	# The floor of the ground storey, holed for the main stair only: the second
	# stair does not reach the basement and the earth under it is solid (§3).
	_slab_at(GROUND, Rect2(0.0, 0.0, HOUSE, HOUSE),
		[_stairwell(STAIR_A_X, STAIR_A_Z), _chute_hole()] as Array[Rect2], SLAB)

## §4. Eight windows, every one a one-way drop to the garden - two per room,
## covering all four faces.
func _upper() -> void:
	var top: float = UPPER + STOREY - SLAB
	_wall_x(WALL * 0.5, 0.0, HOUSE, UPPER, top, [
		_at(FAR_MID, WINDOW), # Landing A west
		_at(NEAR_MID, WINDOW), # Bedroom west
	] as Array[Vector2])
	_wall_x(HOUSE - WALL * 0.5, 0.0, HOUSE, UPPER, top, [
		_at(FAR_MID, WINDOW), # Vault east
		_at(NEAR_MID, WINDOW), # Landing B east
	] as Array[Vector2])
	_wall_z(WALL * 0.5, WALL, HOUSE - WALL, UPPER, top, [
		_at(NEAR_MID, WINDOW), # Bedroom south
		_at(FAR_MID, WINDOW), # Landing B south
	] as Array[Vector2])
	_wall_z(HOUSE - WALL * 0.5, WALL, HOUSE - WALL, UPPER, top, [
		_at(NEAR_MID, WINDOW), # Landing A north
		_at(FAR_MID, WINDOW), # Vault north
	] as Array[Vector2])
	_ring(UPPER, top)

	_slab_at(UPPER, Rect2(0.0, 0.0, HOUSE, HOUSE),
		[_stairwell(STAIR_A_X, STAIR_A_Z), _stairwell(STAIR_B_X, STAIR_B_Z),
		_chute_hole()] as Array[Rect2], SLAB)
	# The roof. No holes: nothing goes up from the top floor.
	_slab_at(ROOF, Rect2(0.0, 0.0, HOUSE, HOUSE), [] as Array[Rect2], SLAB)

## The four internal doorways that make each floor a ring (§4, §5).
##
## A ring rather than a chain is the whole reason a chase can circulate instead
## of ending in a corner (§8).
func _ring(level: float, top: float) -> void:
	_wall_x(SPLIT, WALL, HOUSE - WALL, level, top, [
		_at(FAR_MID, DOOR), # NW <-> NE
		_at(NEAR_MID, DOOR), # SW <-> SE
	] as Array[Vector2])
	_wall_z(SPLIT, WALL, HOUSE - WALL, level, top, [
		_at(NEAR_MID, DOOR), # NW <-> SW
		_at(FAR_MID, DOOR), # NE <-> SE
	] as Array[Vector2])

## §2. Two switchback flights per storey, five steps each, with a mid-landing.
func _stairs() -> void:
	# Main stair, NW: basement -> ground -> upper. The spine (§3).
	_switchback(STAIR_A_X, STAIR_A_Z, BASEMENT)
	_switchback(STAIR_A_X, STAIR_A_Z, GROUND)
	# Second stair, SE: ground -> upper only.
	_switchback(STAIR_B_X, STAIR_B_Z, GROUND)

## One storey of stairs: up the near half, turn on the landing, up the far half.
##
## Flights run in +z side by side. The first climbs the western half, the
## mid-landing spans both at half height, and the second climbs the eastern half
## back down the z axis - so a body arrives at the top having turned 180 degrees,
## in 580 of depth rather than 640 of straight run.
## TREADS ARE TREADS, NOT COLUMNS.
##
## Each step is a slab one riser thick at its own height - not a solid block from
## floor level up. That distinction is invisible in a single-storey house and
## fatal in a stacked one: the main stair runs basement->ground->upper in the SAME
## footprint, so filling each tread down to its storey's floor makes the flight
## above into a solid ceiling over the flight below. Measured: blocker_139,
## occupying y 300..600, sat directly on the basement stair's top tread and the
## fill dropped every tread whose body would not fit under it. The basement
## became enterable and not escapable, and the upper floor unreachable, from one
## cause with two faces.
##
## A real staircase is a thin ramp with open space beneath it. So is this one.
func _switchback(x: float, z: float, base: float) -> void:
	var half: float = base + STEP * float(HALF_FLIGHT)
	for i: int in HALF_FLIGHT:
		var top: float = base + STEP * float(i + 1)
		_solid(AABB(Vector3(x, top - STEP, z + RUN * float(i)),
			Vector3(FLIGHT_W, STEP, RUN)))
	# Mid-landing: full width, both flights, one riser thick at half height.
	_solid(AABB(Vector3(x, half - STEP, z + FLIGHT_RUN),
		Vector3(STAIR_W, STEP, LANDING_D)))
	for i: int in HALF_FLIGHT:
		var top: float = half + STEP * float(i + 1)
		_solid(AABB(
			Vector3(x + FLIGHT_W, top - STEP, z + FLIGHT_RUN - RUN * float(i + 1)),
			Vector3(FLIGHT_W, STEP, RUN)))

## The opening a flight needs in the floor above it.
##
## NOT the stair footprint - a strip over the ARRIVING half only.
##
## A switchback climbs one storey in two halves. The first half tops out at
## mid-height, nowhere near the ceiling; only the second half approaches the
## floor it arrives at, and only its last treads foul the slab. Measured on this
## geometry: with a 300 storey and a 40 slab there is 260 clear, so a tread whose
## top is within `SLAB + 2 * BODY` of the floor above has no room for the body
## and the fill drops it.
##
##   step 2  top 240  clear 20   step 3  top 270  clear -10
##   step 4  top 300  clear -40  body needs 40
##
## Cutting the whole footprint instead is what a rectangle forces, and it takes
## the floor out from under the departing flight's head - so the body has nothing
## to step onto and the storey below becomes enterable but not escapable. Both
## halves of that were tried; each fixed one end and broke the other. The shape
## has to be asymmetric because the two flights are.
## DERIVED FROM THE TREADS THEMSELVES, never from an index or a fraction.
##
## The opening is the WHOLE stair footprint, grown by a body radius. That is not
## a conservative approximation - it is what the numbers force, and three
## earlier attempts to cut something smarter than this all failed:
##
##   - Ask of each tread "would a body standing on it have its head in the slab
##     above". Clear height under a slab is STOREY - SLAB = 260, a body is
##     BODY_HEIGHT = 180 tall, so the answer is yes for every tread above 80 -
##     which is everything from the third step up, both flights, and the whole
##     mid-landing. The minimal hole IS the footprint. Every version that
##     returned less than this left a tread roofed, no stance was generated on
##     it, and the fill correctly refused the resulting 60 climb.
##   - Two of those versions were additionally wrong about WHICH treads: one
##     counted the fouling index from the bottom of the flight and used it as an
##     offset from the top; one excluded the top tread on the theory that it "is
##     floor" (it is not - it tops out level with the storey ceiling with 40 of
##     slab above it).
##
## The lesson worth keeping: a staircase between two floors 300 apart is a
## SHAFT, not a notch in a slab. §3's stacking table already said so by giving
## each staircase its own footprint on every floor. The body's height, not the
## step geometry, is what decides it.
##
## Grown by BODY on all four sides because the fill works in body centres: a
## body walking the edge of the flight needs its whole radius clear of the slab,
## not just the point under its feet.
func _stairwell(x: float, z: float) -> Rect2:
	return Rect2(x - BODY, z - BODY, STAIR_W + BODY * 2.0, STAIR_D + BODY * 2.0)

## §4. The chute shaft, sealed everywhere except its intake and its exit.
##
## A blocker in the Vault (upper) and the Kitchen (ground) - it passes through
## those rooms without opening into them. The hole in each slab is what makes it
## a shaft rather than three unrelated boxes.
func _chute() -> void:
	# Intake: an opening in Landing A's east wall, at the shaft.
	_wall_x(SPLIT, CHUTE_Z, CHUTE_Z + CHUTE, UPPER, UPPER + STOREY - SLAB,
		[_at(CHUTE_Z + CHUTE * 0.5, CHUTE)] as Array[Vector2])
	# The shaft walls: three sides on each floor it passes through, so a body
	# cannot step out of it mid-fall.
	for level: float in [UPPER, GROUND]:
		var top: float = level + STOREY - SLAB
		_wall_x(CHUTE_X + CHUTE + WALL * 0.5, CHUTE_Z, CHUTE_Z + CHUTE,
			level, top, [] as Array[Vector2])
		_wall_z(CHUTE_Z - WALL * 0.5, CHUTE_X, CHUTE_X + CHUTE,
			level, top, [] as Array[Vector2])
		_wall_z(CHUTE_Z + CHUTE + WALL * 0.5, CHUTE_X, CHUTE_X + CHUTE,
			level, top, [] as Array[Vector2])

func _chute_hole() -> Rect2:
	return Rect2(CHUTE_X, CHUTE_Z, CHUTE, CHUTE)

## An opening centred on `centre`, `width` across.
func _at(centre: float, width: float) -> Vector2:
	return Vector2(centre - width * 0.5, centre + width * 0.5)

# ---- placing it twice (§9) ----

## `turned` rotates the house 180 degrees about the middle of the lot, so the two
## fronts face away from each other and the layout is identical for both teams
## without mirroring - mirroring in x once produced two houses facing the same
## way (§9).
func _stamp(turned: bool, team: StringName, side: String) -> void:
	for box: AABB in _solids:
		_blocker(_place(box, turned))

	# §3 vertical stacking. Quadrants stack identically on every floor; the
	# basement omits the south-east.
	var rooms: Array[Array] = [
		# id, role, x, z, y
		[&"landing_a", ZoneDef.Role.HOME, LOW, MID_HIGH, UPPER],
		[&"vault", ZoneDef.Role.CASH_ROOM, MID_HIGH, MID_HIGH, UPPER],
		[&"bedroom", ZoneDef.Role.CASH_ROOM, LOW, LOW, UPPER],
		[&"landing_b", ZoneDef.Role.HOME, MID_HIGH, LOW, UPPER],
		[&"back_hall", ZoneDef.Role.HOME, LOW, MID_HIGH, GROUND],
		[&"kitchen", ZoneDef.Role.HOME, MID_HIGH, MID_HIGH, GROUND],
		[&"living", ZoneDef.Role.HOME, LOW, LOW, GROUND],
		[&"front_hall", ZoneDef.Role.HOME, MID_HIGH, LOW, GROUND],
		[&"stair_foot", ZoneDef.Role.HOME, LOW, MID_HIGH, BASEMENT],
		[&"cellar", ZoneDef.Role.JAIL, MID_HIGH, MID_HIGH, BASEMENT],
		[&"boiler", ZoneDef.Role.HOME, LOW, LOW, BASEMENT],
	]
	for room: Array in rooms:
		_zone(StringName("%s_%s" % [room[0], side]), room[1], team, 1,
			_place(AABB(Vector3(room[2], room[4], room[3]),
				Vector3(QUAD, STOREY, QUAD)), turned), false)

	# §12: spawns in the team's own yard, along the back and side faces.
	for i: int in 3:
		_marker("spawn_%s_%d" % [team, i], _place(AABB(Vector3(
			SPAWN_LOCAL[i].x, GROUND + BODY, SPAWN_LOCAL[i].y),
			Vector3.ONE), turned).position)

	# §12: cash split randomly each round between the two upper cash rooms.
	# Both rooms carry points; which ones are live is a spawn rule, not geometry.
	for i: int in 2:
		_marker("cash_%s_%d" % [team, i], _place(AABB(Vector3(
			MID_HIGH + 220.0 + 300.0 * float(i), UPPER + BODY, FAR_MID),
			Vector3.ONE), turned).position)
	for i: int in 2:
		_marker("cash_%s_%d" % [team, i + 2], _place(AABB(Vector3(
			LOW + 220.0 + 300.0 * float(i), UPPER + BODY, NEAR_MID),
			Vector3.ONE), turned).position)

## House-local to lot coordinates.
##
## The turn is ONE rotation about the middle of the lot, so it is applied to the
## unrotated placement rather than to a second origin: `LOT - (A + local) - size`.
## Feeding House B's own origin in and THEN negating applies the offset twice and
## puts the whole building off the west edge of the map, which is what it did.
## House B's origin is not an input - it falls out of the arithmetic.
func _place(box: AABB, turned: bool) -> AABB:
	var x: float = HOUSE_A_X + box.position.x
	var z: float = HOUSE_A_Z + box.position.z
	if turned:
		x = LOT_W - x - box.size.x
		z = LOT_D - z - box.size.z
	return AABB(Vector3(x, box.position.y, z), box.size)

## §12 territory. Ground within 400 of a house's outer wall belongs to it and
## capture is legal there; everything else is neutral.
##
## This matters more than it looks. An earlier build put every encounter on
## neutral ground, so no capture was ever legal and the game had no interactions
## at all. Never let the only safe place also be the only crossing.
func _outdoors() -> void:
	var high: float = LOT_H - GROUND
	# Priority -1: the lot underlies everything outdoors, and both yards sit on
	# top of it. Whichever zone is more specific must win, or which ground a
	# capture happens on is arbitrary.
	_zone(&"lot", ZoneDef.Role.NEUTRAL, &"", -1,
		AABB(Vector3(0.0, GROUND, 0.0), Vector3(LOT_W, high, LOT_D)), true)
	# §12 states territory as a DISTANCE - "ground within 400 of a house's outer
	# wall". Zones are boxes, so the box is the approximation, and the naive
	# version of it does not work: the two houses are point-symmetric about the
	# lot centre rather than side by side, so their z ranges interleave (A
	# 550..2140, B 1340..2930). Two squares wrapping them overlap by 1600 on z
	# at ANY territory value - shrinking it does not help, because the overlap
	# is caused by the diagonal offset, not by the size.
	#
	# Two HOME zones overlapping at equal priority is a hard refusal, and
	# rightly: the overlap covers ground a spawn can sit on, and which team owns
	# a point decides whether a capture there is legal.
	#
	# So each yard is clipped at the lot's x midline. The corridor is the
	# divider the plan already draws, the split is point-symmetric so neither
	# team is favoured, and 320 of the 400 survives on the contested east face -
	# the one face where the exact figure matters.
	var midline: float = LOT_W * 0.5
	for turned: bool in [false, true]:
		var yard: Rect2 = _flat(Rect2(-TERRITORY, -TERRITORY,
			HOUSE + TERRITORY * 2.0, HOUSE + TERRITORY * 2.0), turned)
		var from_x: float = maxf(yard.position.x, midline) if turned else yard.position.x
		var to_x: float = yard.end.x if turned else minf(yard.end.x, midline)
		# Priority 0: the yard WRAPS the house, so every room overlaps it. Rooms
		# win, and the yard is only what is left over outside them. Equal
		# priority would make which one a point belongs to arbitrary, and
		# "arbitrary" here decides whether a capture is legal.
		_zone(&"yard_b" if turned else &"yard_a", ZoneDef.Role.HOME,
			&"team_b" if turned else &"team_a", 0,
			AABB(Vector3(from_x, GROUND, yard.position.y),
				Vector3(to_x - from_x, high, yard.size.y)), true)

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

func _blocker(box: AABB) -> void:
	if box.size.x < 0.5 or box.size.y < 0.5 or box.size.z < 0.5:
		return
	_count += 1
	_box("blocker_%d" % _count, box.position + box.size * 0.5, box.size)

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
