extends SceneTree
## Generates the blockout for the three-storey house. See HOUSE_LAYOUT.md.
##
##   godot --headless --path godot --script res://tools/build_house.gd
##
## Written rather than hand-placed because the house is parametric and mirrored:
## two hundred boxes dragged into place would be two hundred chances to put one
## at a height that is not in the threshold set, and the mirror would be a
## second two hundred. Every dimension below comes from TuningDef or from
## WORLD_AUTHORING.md §10 and §12 - nothing here invents a number.
##
## The house is built once in LOCAL coordinates and emitted twice, the second
## time mirrored in x. That is the only way the two houses are guaranteed to be
## the same house: a mirror applied to finished geometry cannot drift, and a
## second hand-authored copy always does.
##
## THE SHAPE IS DRIVEN BY THE GATE. Every role-bearing room needs three
## independent ways in (WORLD_AUTHORING §7), and that requirement - not taste -
## decided the stair bay, the two outside staircases, the two light wells and
## the pair of doorways at each end of the vault. The connectivity was worked
## out and checked as a flow problem before any box was placed; the numbers
## below are what it costs to build.

# ---- the threshold set (WORLD_AUTHORING.md §12) ----
const STEP: float = 30.0 ## walk over
## Floor to floor, and it MUST be a whole number of steps.
##
## It was 320, which is 11 steps of 29.09, and eleven treads of 29.09 do not
## make a staircase. The fill quantises height at `layer_height` - 30 here, the
## step allowance - so a tread is only found when a layer centre falls between
## its top and the next tread's. A 29.09 window in a 30 grid misses sometimes,
## and it missed two treads out of twenty-two. At exactly 30 every window
## contains exactly one, always.
const STOREY: float = 330.0
const DROP: float = 480.0 ## fall this far and keep going

# ---- room dimensions (WORLD_AUTHORING.md §10) ----
const ROOM: float = 755.0 ## the camera needs it
const WALL: float = 30.0
const DOOR: float = 240.0
const SLAB: float = 40.0
const HEAD: float = 220.0 ## lintel height over a doorway
## `TuningDef.actor_radius`. Restated because the blockout has to be dimensioned
## against the body that walks it - see the stair run and _covered_from below.
const BODY: float = 20.0

## Stair geometry, and the run is NOT a taste decision.
##
## A tread has to be found by the walkable fill, which samples at one cell -
## `actor_radius * CELL_RADII`, 40 here. The next tread up, grown by the body
## radius, eats 20 off the front of this one, so a tread only offers `run - 20`
## of standable depth, and that has to be at least a cell or some tread gets no
## sample and the staircase has a hole in it. 64 leaves 44.
##
## Eleven treads of 30 clear a storey. The flight is therefore 704 long, which
## is most of a room - so a staircase IS a room, which is why this house has a
## stair bay rather than stairs tucked into a corner.
const TREADS: int = int(STOREY / STEP)
const RUN: float = 64.0
const FLIGHT_W: float = 220.0
## How far a flight starts from the wall behind it. A wall grown by the body
## radius reaches 20 past its own face, which ate the whole of the bottom tread
## the first time and left the staircase starting at tread one.
const FLIGHT_Z0: float = 50.0

# ---- storeys: the top of each slab is where a body stands ----
const BASEMENT: float = 40.0
const GROUND: float = BASEMENT + STOREY
const UPPER: float = GROUND + STOREY
const ROOF: float = UPPER + STOREY

# ---- plan ----
## Four bays across: the stairwell, then three rooms.
const SLOTS: int = 4
const HOUSE_W: float = ROOM * float(SLOTS) + WALL * float(SLOTS + 1)
const HOUSE_D: float = ROOM + WALL * 2.0

const BACK_STRIP: float = 300.0 ## room behind the house for the outside stairs
const FRONT_GARDEN: float = 700.0
const SIDE: float = 350.0
const GAP: float = 1200.0 ## between the two houses

const HOUSE_A_X: float = SIDE
const HOUSE_B_X: float = SIDE + HOUSE_W + GAP
const ORIGIN_Z: float = BACK_STRIP
const WORLD_W: float = HOUSE_B_X + HOUSE_W + SIDE
const WORLD_D: float = BACK_STRIP + HOUSE_D + FRONT_GARDEN
const WORLD_H: float = ROOF + SLAB

## Slot x-ranges in local coordinates.
const BAY: int = 0
const WEST: int = 1 ## cellar / hall / landing
const MID: int = 2 ## boiler / kitchen / vault
const EAST: int = 3 ## jail / living / bedroom

# ---- collected geometry, in local coordinates ----
var _solids: Array[AABB] = []
var _rooms: Array[Dictionary] = []
var _points: Array[Dictionary] = []

var _root: Node3D = null
var _count: int = 0

func _initialize() -> void:
	_build_house()

	_root = Node3D.new()
	_root.name = "HouseBlockout"
	_box("shell", Vector3(WORLD_W, WORLD_H, WORLD_D) * 0.5,
		Vector3(WORLD_W, WORLD_H, WORLD_D))
	_terrain()
	_emit(HOUSE_A_X, false, &"team_a", "a")
	_emit(HOUSE_B_X, true, &"team_b", "b")
	_garden()

	var scene: PackedScene = PackedScene.new()
	_own(_root)
	scene.pack(_root)
	var path: String = "res://game/blockout/house.tscn"
	var wrote: int = ResourceSaver.save(scene, path)
	print("%s: %s" % [path, "written" if wrote == OK else "FAILED (%d)" % wrote])
	print("world %d x %d x %d, %d blockers, %d rooms per house" % [
		int(WORLD_W), int(WORLD_D), int(WORLD_H), _count, _rooms.size(),
	])

	quit(0)

# ---- the house, once, in local coordinates ----

## x runs 0..HOUSE_W across the bays; z runs 0..HOUSE_D front to back, with the
## garden at +z and the back strip at -z. y is absolute and never mirrored.
func _build_house() -> void:
	_storeys()
	_slabs()
	_stair_bay()
	_outside_stairs()
	_light_wells()

	var levels: Array[float] = [BASEMENT, GROUND, UPPER]
	var names: Array[PackedStringArray] = [
		PackedStringArray(["cellar", "boiler", "jail"]),
		PackedStringArray(["hall", "kitchen", "living"]),
		PackedStringArray(["landing", "vault", "bedroom"]),
	]
	var roles: Array[Array] = [
		[ZoneDef.Role.HOME, ZoneDef.Role.HOME, ZoneDef.Role.JAIL],
		[ZoneDef.Role.HOME, ZoneDef.Role.HOME, ZoneDef.Role.HOME],
		[ZoneDef.Role.HOME, ZoneDef.Role.CASH_ROOM, ZoneDef.Role.HOME],
	]
	for storey: int in 3:
		for slot: int in 3:
			_rooms.append({
				"id": names[storey][slot],
				"role": roles[storey][slot],
				"x": _slot_from(slot + 1),
				"y": levels[storey],
			})

	# One spawn per body in the hall, and the cash upstairs in the vault.
	for i: int in 3:
		_points.append({"kind": "spawn", "slot": i,
			"at": Vector3(_slot_from(WEST) + 180.0 + 200.0 * float(i), GROUND + 20.0, 200.0)})
		_points.append({"kind": "cash", "slot": i,
			"at": Vector3(_slot_from(MID) + 180.0 + 200.0 * float(i), UPPER + 20.0, 400.0)})

## The x where slot `i` begins.
func _slot_from(i: int) -> float:
	return WALL + (ROOM + WALL) * float(i)

# ---- walls ----

func _storeys() -> void:
	for level: float in [BASEMENT, GROUND, UPPER]:
		var top: float = level + STOREY - SLAB
		# End walls, solid.
		_wall_x(WALL * 0.5, 0.0, HOUSE_D, level, top, [])
		_wall_x(HOUSE_W - WALL * 0.5, 0.0, HOUSE_D, level, top, [])
		_wall_z(WALL * 0.5, 0.0, HOUSE_W, level, top, _back_openings(level))
		_wall_z(HOUSE_D - WALL * 0.5, 0.0, HOUSE_W, level, top, _garden_openings(level))
		for divider: int in [1, 2, 3]:
			_wall_x(_slot_from(divider) - WALL * 0.5, 0.0, HOUSE_D, level, top,
				_divider_openings(divider, level))

## Between the bays. The vault has TWO doorways at each end rather than one,
## which is the whole reason it reaches three ways in without a second
## staircase: two doors in one wall are two apertures, and one defender cannot
## stand in both.
func _divider_openings(divider: int, level: float) -> Array[Vector2]:
	var centre: float = HOUSE_D * 0.5
	if level == UPPER and divider != BAY + 1:
		return [
			Vector2(centre - 340.0, centre - 100.0),
			Vector2(centre + 100.0, centre + 340.0),
		] as Array[Vector2]
	return [Vector2(centre - DOOR * 0.5, centre + DOOR * 0.5)] as Array[Vector2]

## The back of the house: where the two outside staircases arrive.
func _back_openings(level: float) -> Array[Vector2]:
	if level != UPPER:
		return [] as Array[Vector2]
	return [
		_span(_slot_from(WEST) + 135.0, DOOR), # off the west stair, into the landing
		_span(_slot_from(EAST) + 165.0, DOOR), # off the east stair, into the bedroom
	] as Array[Vector2]

## The garden face: the doors everybody uses, the two light wells below them,
## and the vault's window - which is an exit and never an entrance, because
## climbing 320 back up is not a verb this game has.
func _garden_openings(level: float) -> Array[Vector2]:
	if level == BASEMENT:
		return [
			_span(_slot_from(WEST) + 550.0, DOOR), # out of the west light well
			_span(_slot_from(EAST) + 190.0, DOOR), # out of the east light well
		] as Array[Vector2]
	if level == GROUND:
		return [
			_span(_slot_from(WEST) + 220.0, DOOR), # front door
			_span(_slot_from(MID) + 377.0, DOOR), # back door
			_span(_slot_from(EAST) + 560.0, DOOR), # french windows
		] as Array[Vector2]
	return [_span(_slot_from(MID) + 377.0, DOOR)] as Array[Vector2] # the way out

func _span(centre: float, width: float) -> Vector2:
	return Vector2(centre - width * 0.5, centre + width * 0.5)

# ---- floors ----

func _slabs() -> void:
	var house: Rect2 = Rect2(0.0, 0.0, HOUSE_W, HOUSE_D)
	_slab(BASEMENT, house, [])
	_slab(GROUND, house, [
		_bay_well(BASEMENT, 150.0),
		Rect2(_slot_from(MID) + 50.0, 80.0, 200.0, 200.0), # the laundry chute
		Rect2(_slot_from(EAST) + 65.0, 80.0, 200.0, 200.0), # trapdoor into the jail
	] as Array[Rect2])
	_slab(UPPER, house, [
		_bay_well(GROUND, 445.0),
		Rect2(_slot_from(EAST) + 465.0, 500.0, 200.0, 200.0), # the airing cupboard
	] as Array[Rect2])
	_slab(ROOF, house, [])

## The opening a flight needs in the floor above it.
##
## Not the whole flight: only the top of it, from the tread where a standing
## body would otherwise have its head in the slab. Cutting the full footprint
## would leave the room above as two disconnected halves either side of a
## full-depth void, which is how the first attempt at this house failed.
func _bay_well(base: float, x: float) -> Rect2:
	var from: float = FLIGHT_Z0 + RUN * float(_covered_from(base)) - 40.0
	return Rect2(x, from, FLIGHT_W, HOUSE_D - from)

## The first tread that needs the floor above it opened up.
##
## Worked out the way the fill will see it, not from the clear height. A body
## does not stand at its rest height in the grid - it occupies the layer whose
## CENTRE is the first one above that height, and the layer is as tall as a
## step, so the rounding is worth a whole tread. Computing this from the clear
## height instead left exactly one tread of each flight buried in the slab, and
## one missing tread is a staircase nobody can climb.
func _covered_from(base: float) -> int:
	var ceiling: float = base + STOREY - SLAB - BODY
	for i: int in TREADS:
		var rest: float = base + STEP * float(i + 1) + BODY
		var layer: float = (ceil(rest / STEP - 0.5) + 0.5) * STEP
		if layer >= ceiling:
			return i
	return TREADS

# ---- stairs ----

## Two flights side by side, one per storey, in a bay of their own. They are
## offset in x so that the floor beside each opening stays continuous and the
## doorway into the rooms is never over a void.
func _stair_bay() -> void:
	_flight(150.0, FLIGHT_Z0, BASEMENT)
	_flight(445.0, FLIGHT_Z0, GROUND)

## Outside, at the back: garden up to a landing at bedroom height, and in
## through a window. Two of them, because both end rooms upstairs need a way in
## that does not pass through the other one.
func _outside_stairs() -> void:
	_flight_x(0.0, -220.0, GROUND, 300.0)
	_flight_x(_slot_from(MID) + 100.0, -220.0, GROUND, 300.0)

## A pit against the house with a door into the basement at the bottom of it.
##
## One way in and no way back: 320 down is a fall you walk away from, and 320 up
## is a climb nothing in this game can make. Getting out means going through the
## house, which is the point - the basement is where you are put, not where you
## loiter.
func _light_wells() -> void:
	_well(_slot_from(WEST) + 400.0)
	_well(_slot_from(EAST) + 40.0)

func _well(x: float) -> void:
	# The floor of it, and the three sides that are not the house.
	_solid(AABB(Vector3(x, 0.0, HOUSE_D), Vector3(300.0, BASEMENT, 300.0)))
	_solid(AABB(Vector3(x - WALL, BASEMENT, HOUSE_D), Vector3(WALL, GROUND - BASEMENT, 330.0)))
	_solid(AABB(Vector3(x + 300.0, BASEMENT, HOUSE_D), Vector3(WALL, GROUND - BASEMENT, 330.0)))
	_solid(AABB(Vector3(x - WALL, BASEMENT, HOUSE_D + 300.0),
		Vector3(360.0, GROUND - BASEMENT, WALL)))

## A straight flight running in +z.
func _flight(x: float, from_z: float, base: float) -> void:
	var rise: float = STOREY / float(TREADS)
	for i: int in TREADS:
		var top: float = base + rise * float(i + 1)
		_solid(AABB(Vector3(x, base, from_z + RUN * float(i)),
			Vector3(FLIGHT_W, top - base, RUN)))

## A straight flight running in +x, with a landing at the top of it. Used
## outside, where the stair has to hug the wall rather than stick into the
## garden, and where the arrival needs to be wide enough to turn round on.
func _flight_x(from_x: float, z: float, base: float, landing: float) -> void:
	var rise: float = STOREY / float(TREADS)
	for i: int in TREADS:
		var top: float = base + rise * float(i + 1)
		_solid(AABB(Vector3(from_x + RUN * float(i), base, z),
			Vector3(RUN, top - base, -z)))
	_solid(AABB(Vector3(from_x + RUN * float(TREADS), base + STOREY - SLAB, z),
		Vector3(landing, SLAB, -z)))

# ---- primitives ----

## A wall running in z, at a fixed x. `gaps` are z-ranges left open.
func _wall_x(x: float, from: float, to: float, base: float, top: float,
		gaps: Array[Vector2]) -> void:
	for piece: Vector4 in _panels(from, to, base, top, gaps):
		_solid(AABB(Vector3(x - WALL * 0.5, piece.z, piece.x),
			Vector3(WALL, piece.w - piece.z, piece.y - piece.x)))

## A wall running in x, at a fixed z.
func _wall_z(z: float, from: float, to: float, base: float, top: float,
		gaps: Array[Vector2]) -> void:
	for piece: Vector4 in _panels(from, to, base, top, gaps):
		_solid(AABB(Vector3(piece.x, piece.z, z - WALL * 0.5),
			Vector3(piece.y - piece.x, piece.w - piece.z, WALL)))

## Splits a wall into the solid pieces around its openings.
##
## A doorway is an ABSENCE (WORLD_AUTHORING §2), so a wall with a door in it is
## built as the parts that are still there rather than as a wall with something
## subtracted. Returns (from, to, y_base, y_top) per piece: the full-height
## stretches between openings, and a lintel over each opening.
func _panels(from: float, to: float, base: float, top: float,
		gaps: Array[Vector2]) -> Array[Vector4]:
	var pieces: Array[Vector4] = []
	var ordered: Array[Vector2] = gaps.duplicate()
	ordered.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var cursor: float = from
	for gap: Vector2 in ordered:
		if gap.x > cursor:
			pieces.append(Vector4(cursor, gap.x, base, top))
		if base + HEAD < top:
			pieces.append(Vector4(gap.x, gap.y, base + HEAD, top))
		cursor = maxf(cursor, gap.y)
	if cursor < to:
		pieces.append(Vector4(cursor, to, base, top))
	return pieces

## A floor with holes in it.
##
## Decomposed on the grid formed by the holes' own edges, then merged back along
## x. General rather than clever: any arrangement of rectangular openings comes
## out right, which matters because the openings here are a stairwell, a laundry
## chute and two floor hatches, and no two of them line up.
func _slab(top: float, area: Rect2, holes: Array[Rect2]) -> void:
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
				_slab_piece(top, run_from, run_to, zs[zi], zs[zi + 1])
				run_from = -1.0
				continue
			if run_from < 0.0:
				run_from = xs[xi]
			run_to = xs[xi + 1]
		_slab_piece(top, run_from, run_to, zs[zi], zs[zi + 1])

func _slab_piece(top: float, from: float, to: float, z0: float, z1: float) -> void:
	if from < 0.0 or to - from < 0.5:
		return
	_solid(AABB(Vector3(from, top - SLAB, z0), Vector3(to - from, SLAB, z1 - z0)))

func _solid(box: AABB) -> void:
	_solids.append(box.abs())

# ---- emitting, twice ----

## The ground everything outside the houses stands on, with the houses and the
## light wells dug out of it.
func _terrain() -> void:
	_blocker(AABB(Vector3.ZERO, Vector3(WORLD_W, BASEMENT, WORLD_D)))
	var holes: Array[Rect2] = []
	for origin: float in [HOUSE_A_X, HOUSE_B_X]:
		holes.append(Rect2(origin, ORIGIN_Z, HOUSE_W, HOUSE_D))
	for box: AABB in _solids:
		# The light wells are the only local geometry that reaches outside the
		# footprint on the garden side, and each needs its own hole.
		if box.position.z >= HOUSE_D and box.size.y <= BASEMENT:
			for i: int in 2:
				var placed: AABB = _place(box, HOUSE_A_X if i == 0 else HOUSE_B_X, i == 1)
				holes.append(Rect2(placed.position.x, placed.position.z,
					placed.size.x, placed.size.z))
	_dig(BASEMENT, GROUND - BASEMENT, holes)

## The terrain slab, minus the holes, by the same decomposition the floors use.
func _dig(base: float, height: float, holes: Array[Rect2]) -> void:
	var xs: Array[float] = [0.0, WORLD_W]
	var zs: Array[float] = [0.0, WORLD_D]
	for hole: Rect2 in holes:
		xs.append_array([hole.position.x, hole.end.x])
		zs.append_array([hole.position.y, hole.end.y])
	xs.sort()
	zs.sort()
	for zi: int in zs.size() - 1:
		if zs[zi + 1] - zs[zi] < 0.5:
			continue
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
			if not open:
				_blocker(AABB(Vector3(xs[xi], base, zs[zi]),
					Vector3(xs[xi + 1] - xs[xi], height, zs[zi + 1] - zs[zi])))

func _place(box: AABB, origin: float, flip: bool) -> AABB:
	var x: float = origin + (HOUSE_W - box.position.x - box.size.x if flip else box.position.x)
	return AABB(Vector3(x, box.position.y, ORIGIN_Z + box.position.z), box.size)

func _emit(origin: float, flip: bool, team: StringName, side: String) -> void:
	for box: AABB in _solids:
		_blocker(_place(box, origin, flip))
	for room: Dictionary in _rooms:
		var bounds: AABB = _place(
			AABB(Vector3(room["x"], room["y"], WALL), Vector3(ROOM, STOREY, ROOM)),
			origin, flip)
		_zone(StringName("%s_%s" % [room["id"], side]), room["role"], team, 1, bounds)
	for point: Dictionary in _points:
		var at: Vector3 = point["at"]
		var placed: AABB = _place(AABB(at, Vector3.ONE), origin, flip)
		_marker("%s_%s_%d" % [point["kind"], team, point["slot"]], placed.position)

## Outdoors, in pieces that do not overlap the houses.
##
## Several zones rather than one big one, because zone resolution takes the
## first match rather than the highest priority, and a garden drawn over the
## top of the houses would quietly claim every room in them.
##
## THE GROUND ROUND A HOUSE BELONGS TO IT. Not decoration: a seizure is only
## legal on ground your team owns, so an unowned garden is somewhere the two
## sides can meet and do nothing about each other. Measured, that is exactly
## what happened - eighteen encounters in a six-minute match, every one of them
## outdoors, not one where a capture was legal, and zero captures. The original
## 2D game drew this line the same way: its idea of home ground covered the
## yard.
##
## What stays neutral is the strip BETWEEN the two houses. Somewhere has to be,
## or the routes gate has no outdoors to count ways in from - and a no-man's
## land in the middle is what makes crossing it a decision.
func _garden() -> void:
	var high: float = WORLD_H - GROUND
	var front: float = ORIGIN_Z + HOUSE_D
	var edge_a: float = HOUSE_A_X + HOUSE_W
	var edge_b: float = HOUSE_B_X
	_ground("garden", ZoneDef.Role.NEUTRAL, &"",
		AABB(Vector3(edge_a, GROUND, 0), Vector3(GAP, high, WORLD_D)))
	for i: int in 2:
		var team: StringName = &"team_a" if i == 0 else &"team_b"
		var side: String = "a" if i == 0 else "b"
		var from: float = 0.0 if i == 0 else edge_b
		var span: float = edge_a if i == 0 else WORLD_W - edge_b
		_ground("yard_back_%s" % side, ZoneDef.Role.HOME, team,
			AABB(Vector3(from, GROUND, 0), Vector3(span, high, ORIGIN_Z)))
		_ground("yard_front_%s" % side, ZoneDef.Role.HOME, team,
			AABB(Vector3(from, GROUND, front), Vector3(span, high, WORLD_D - front)))
		_ground("yard_side_%s" % side, ZoneDef.Role.HOME, team,
			AABB(Vector3(from if i == 0 else edge_b + HOUSE_W, GROUND, ORIGIN_Z),
				Vector3(SIDE, high, HOUSE_D)))

## Everything this builds is open ground, whoever owns it - which is what the
## routes gate counts ways in from.
func _ground(name: String, role: ZoneDef.Role, team: StringName, bounds: AABB) -> void:
	_zone(StringName(name), role, team, 0, bounds, true)

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
		bounds: AABB, outdoor: bool = false) -> void:
	var node: BlockoutZone = BlockoutZone.new()
	node.outdoor = outdoor
	node.name = "zone_%s" % id
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = bounds.size
	node.mesh = mesh
	node.position = bounds.position + bounds.size * 0.5
	node.zone_id = id
	node.role = role
	node.owner_team = team
	node.priority = priority
	_root.add_child(node)

func _marker(node_name: String, at: Vector3) -> void:
	var node: Marker3D = Marker3D.new()
	node.name = node_name
	node.position = at
	_root.add_child(node)
