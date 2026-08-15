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
const STOREY: float = 300.0 ## 10 steps exactly
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
const UPPER: float = 600.0
const ROOF: float = 900.0

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
# Ten steps, one flight, no switchback and no mid-landing, run shortened from
# 64 to 48 so the flight reads as a stair rather than a ramp - 25 degrees was
# too shallow. 30 rise over 48 run is 32 degrees, still comfortably above the
# fill's 40-unit sampling cell (8 units of slack; below ~40 a column centre can
# miss a tread's centre entirely and the fill silently drops a stance, the same
# class of bug the lot-alignment guard exists to catch elsewhere in this file).
# Total flight 480, not 640 - a real saving on top of the switchback's removal.
const FLIGHT_RUN: float = RUN * 10.0 ## 480 - full climb in one run
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
const LOT_W: float = 5400.0 # 135 cells
const LOT_D: float = 3720.0 # 93 cells
const HOUSE_A_X: float = 350.0
const HOUSE_A_Z: float = 350.0
const HOUSE_B_X: float = LOT_W - HOUSE_A_X - HOUSE ## 2960
const HOUSE_B_Z: float = LOT_D - HOUSE_A_Z - HOUSE ## 1280
const LOT_H: float = ROOF + SLAB
## §9: ground within 400 of a house's outer wall belongs to that house.
const TERRITORY: float = 400.0

## The walkable fill samples at cell centres, so the 180-degree turn maps a
## sampled point to another sampled point only when the lot is a whole number
## of cells across. See WORLD_AUTHORING §11.
const CELL: float = 40.0

## §9: team spawns sit in the team's OWN yard, spread along the back and side
## faces. House-local, so `_place` mirrors them onto B's own yard. Negative x
## is the back (west) face; the third sits off the north side face so a squad
## does not spawn in a single line.
const SPAWN_LOCAL: Array[Vector2] = [
	Vector2(-150.0, 500.0),
	Vector2(-150.0, 1400.0),
	Vector2(500.0, -150.0),
]

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
	# West outer: Landing B window (decorative per §6 - not in this list).
	_wall_x(WALL * 0.5, 0.0, HOUSE, UPPER, top, [] as Array[Vector2])
	# East outer: nothing passable. This face looks straight across the 500-unit
	# corridor at the other house - the closest, most exposed wall either house
	# has - so no escape route opens onto it (see U2 below).
	_wall_x(HOUSE - WALL * 0.5, 0.0, HOUSE, UPPER, top, [] as Array[Vector2])
	# South outer: Study escape window (U4). Already the away-facing side - the
	# same face the front door opens onto - so it needed no change.
	_wall_z(WALL * 0.5, WALL, HOUSE - WALL, UPPER, top, [
		_at(NEAR_MID, WINDOW), # U4 Study (SW) escape window, one-way down
	] as Array[Vector2])
	# North outer: Master Bedroom escape window (U2). Moved off the east wall,
	# which faced straight across the corridor at the other house - a raider
	# could grab the cash and be over the sill and home in seconds, defeating
	# the sneak-in-sneak-out design entirely. North faces open lot instead:
	# the other house is offset diagonally and does not sit across from this
	# wall the way it does the east one.
	_wall_z(HOUSE - WALL * 0.5, WALL, HOUSE - WALL, UPPER, top, [
		_at(FAR_MID, WINDOW), # U2 Master Bedroom (NE) escape window, one-way down
	] as Array[Vector2])
	_ring(UPPER, top, [
		&"D5", # Landing A <-> Master Bedroom
		&"D6", # Master Bedroom <-> Landing B
		&"D7", # Landing B <-> Study
		&"D8", # Study <-> Landing A
	])

	_slab_at(UPPER, Rect2(0.0, 0.0, HOUSE, HOUSE),
		[_stairwell(STAIR_A_X, STAIR_A_Z, 1.0), _stairwell(STAIR_B_X, STAIR_B_Z, -1.0)]
			as Array[Rect2], SLAB)
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
## Stair A hugs the EAST wall (its high-x edge touches it, so the open room-
## facing side is at -x). Stair B hugs the WEST wall (its low-x edge touches
## it, so the open side is at +x) - mirror images, not the same shape rotated,
## so the side-wall direction is passed explicitly rather than assumed.
func _stairs() -> void:
	_straight_flight(STAIR_A_X, STAIR_A_Z, GROUND, 1.0, -1.0) # main stair, +z
	_straight_flight(STAIR_B_X, STAIR_B_Z, GROUND, -1.0, 1.0) # second stair, -z

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
## The treads alone leave the flight open underneath and on its inner (room-
## facing) side - a body can walk in at floor level, past the first couple of
## risers, and end up standing inside or behind the stair. Closing that off
## went through three wrong shapes before this one, each found by actually
## looking at a frame or measuring the fill rather than trusting box
## arithmetic on paper:
##
##   1. A single box spanning the whole flight's height on the open side, as
##      its own separate wall (touching but not merged with the soffit).
##      Broke the fill's stance connectivity outright - every upper-floor zone
##      became unreachable.
##   2. The same box SEGMENTED to match each step's rise, still separate from
##      the soffit. Fixed the gate, but read as a second stepped profile
##      running parallel to the real treads.
##   3. A single continuous box at a fixed LOW height (50, comfortably under
##      the second step's own surface), on the theory that proximity wasn't
##      the problem and height was. It broke the gate exactly like attempt 1 -
##      which disproved that theory outright: a solid that does not touch a
##      single tread box still shrinks the grown-radius footprint around the
##      nearest stance column once it is close enough, and 30 units (the
##      column spacing) is close enough regardless of how short the wall is.
##
## What actually worked, and is kept here: WIDEN the per-step soffit itself by
## WALL on the open side, so the closing geometry is never a second object
## sitting NEAR a tread - it is the tread's own soffit, wider. There is only
## ever one box per step, so there is nothing for the fill to see as an
## intrusion and nothing for the eye to see as a second staircase.
##
## The one piece that was still wrong: the LANDING'S kerb, which has no tread
## above it to merge into, stayed only STEP (30) tall - floor height, by the
## old assumption that the landing needed no more than a kerb. A coverage
## probe over the footprint at standing height found the whole landing strip
## still open on its side. Raised to the same clamped height as the tallest
## per-step segment gets (STOREY - SLAB) - not because the landing needs to be
## that tall, but because a landing-only exception was exactly the kind of
## per-piece special-casing that produced bugs 1 through 3, and matching the
## flight's own rule removes the special case rather than tuning it again.
func _straight_flight(x: float, z: float, base: float, dir: float,
		open_side: float) -> void:
	var skirt_x: float = x - WALL if open_side < 0.0 else x
	var skirt_w: float = FLIGHT_W + WALL
	var skirt_limit: float = STOREY - SLAB
	for i: int in 10:
		var top: float = base + STEP * float(i + 1)
		var near: float = z + dir * (STAIR_LANDING + RUN * float(i))
		var lo: float = minf(near, near + dir * RUN)
		_solid(AABB(Vector3(x, top - STEP, lo), Vector3(FLIGHT_W, STEP, RUN)))
		var skirt_h: float = minf(top - STEP - base, skirt_limit)
		_solid(AABB(Vector3(skirt_x, base, lo), Vector3(skirt_w, skirt_h, RUN)))
	_solid(AABB(Vector3(skirt_x, base, z),
		Vector3(skirt_w, skirt_limit, dir * STAIR_LANDING)).abs())

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
## `dir` matches _straight_flight: the footprint runs from the base (at `z`)
## to the top of the flight, `STAIR_LANDING + FLIGHT_RUN` further along in
## whichever direction the stair climbs.
func _stairwell(x: float, z: float, dir: float) -> Rect2:
	var far: float = z + dir * (STAIR_LANDING + FLIGHT_RUN)
	var lo: float = minf(z, far)
	var hi: float = maxf(z, far)
	return Rect2(x, lo, FLIGHT_W, hi - lo)

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
	for i: int in 3:
		_marker("spawn_%s_%d" % [team, i], _place(AABB(Vector3(
			SPAWN_LOCAL[i].x, GROUND + BODY, SPAWN_LOCAL[i].y),
			Vector3.ONE), turned).position)

	# §5/§9: cash split randomly each round between Master Bedroom and Study.
	# Both rooms carry markers; which ones are live is a spawn rule, not
	# geometry. Two markers per room, spaced across its floor.
	for i: int in 2:
		_marker("cash_%s_%d" % [team, i], _place(AABB(Vector3(
			MID_HIGH + 250.0 + 400.0 * float(i), UPPER + BODY, FAR_MID),
			Vector3.ONE), turned).position)
	for i: int in 2:
		_marker("cash_%s_%d" % [team, i + 2], _place(AABB(Vector3(
			LOW + 250.0 + 400.0 * float(i), UPPER + BODY, NEAR_MID),
			Vector3.ONE), turned).position)

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

## §9 territory. Ground within 400 of a house's outer wall belongs to it and
## capture is legal there; everything else is neutral.
func _outdoors() -> void:
	var high: float = LOT_H - GROUND
	# Priority -1: the lot underlies everything outdoors, and both yards sit on
	# top of it. Whichever zone is more specific must win, or which ground a
	# capture happens on is arbitrary.
	_zone(&"lot", ZoneDef.Role.NEUTRAL, &"", -1,
		AABB(Vector3(0.0, GROUND, 0.0), Vector3(LOT_W, high, LOT_D)), true)
	# §9 states territory as a DISTANCE - "within 400 of a house's outer wall".
	# Zones are boxes, so the box is the approximation, and the naive version
	# does not work: the two houses are point-symmetric about the lot centre
	# rather than side by side, so their z ranges interleave (A 350..2440,
	# B 1280..3370). Two squares wrapping them overlap on z at ANY territory
	# value - shrinking it does not help, because the overlap is caused by the
	# diagonal offset, not the size. Confirmed by the same failure in the
	# retired three-storey lot; the fix generalises unchanged.
	#
	# Two HOME zones overlapping at equal priority is a hard refusal: the
	# overlap covers ground a spawn can sit on, and which team owns a point
	# decides whether a capture there is legal.
	#
	# So each yard is clipped at the lot's x midline. The corridor is the
	# divider the plan already draws, the split is point-symmetric so neither
	# team is favoured, and most of the 400 survives on the contested east
	# face - the one face where the exact figure matters.
	var midline: float = LOT_W * 0.5
	for turned: bool in [false, true]:
		var yard: Rect2 = _flat(Rect2(-TERRITORY, -TERRITORY,
			HOUSE + TERRITORY * 2.0, HOUSE + TERRITORY * 2.0), turned)
		var from_x: float = maxf(yard.position.x, midline) if turned else yard.position.x
		var to_x: float = yard.end.x if turned else minf(yard.end.x, midline)
		# Priority 0: the yard WRAPS the house, so every room overlaps it.
		# Rooms win, and the yard is only what is left over outside them.
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
