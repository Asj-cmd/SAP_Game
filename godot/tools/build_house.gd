extends SceneTree
## Writes the blockout for one house, stamped twice, facing each other.
##
##   godot --headless --path godot --script res://tools/build_house.gd
##
## DRAWN, NOT COMPUTED. The house before this one was generated to satisfy a
## graph inequality - three independent ways into every room - and a generator
## pointed at an inequality builds the cheapest thing that satisfies it. That
## came out as eighteen rooms over three floors, two staircases and light wells
## with no visible entrance. Every number in it was derived and none of it was
## chosen, and it played like what it was.
##
## So the layout below is written out: six rooms, two floors, one staircase, the
## vault upstairs and the jail on the ground. The coordinates are picked and
## commented rather than solved for, and the scene this emits stays editable by
## hand afterwards - moving a wall means moving a wall, not re-deriving a plan.
##
## What is still generated is the PLACEMENT, and only that. The house is built
## once and stamped twice, the second copy turned through 180 degrees so the two
## fronts face each other across the garden. Two hand-written copies would
## drift, and a difference between the two houses is a balance bug nobody can
## see.
##
## The gate still runs and still refuses a room with one way in. That is a floor
## now, not a target (TuningDef.routes_required).

# ---- the threshold set (WORLD_AUTHORING.md §12) ----
const STEP: float = 30.0
const STOREY: float = 330.0 ## 11 steps exactly - §12: it has to divide
const BODY: float = 20.0 ## TuningDef.actor_radius

# ---- room dimensions (WORLD_AUTHORING.md §10) ----
const ROOM: float = 755.0 ## the camera needs it
const WALL: float = 30.0
const DOOR: float = 240.0
const SLAB: float = 40.0
const HEAD: float = 220.0 ## lintel height

## Stairs. 11 treads of 30 clears a storey; the RUN is set by the fill's sample
## pitch rather than by taste - a tread offers `run - BODY` of standable depth
## and that has to clear one 40-unit cell, or a tread goes missing and the
## staircase has a hole in it. See WORLD_AUTHORING §11.
const TREADS: int = int(STOREY / STEP)
const RUN: float = 64.0
const FLIGHT_W: float = 220.0
const FLIGHT_FROM_WALL: float = 50.0

# ---- the plan ----
#
#                    ^ garden, and the other house beyond it
#   ┌──────────┬──────────┬──────────┐
#   │ LANDING  │  VAULT   │ BEDROOM  │   upper,  y 370
#   ├──────────┼──────────┼──────────┤
#   │   HALL   │ KITCHEN  │   JAIL   │   ground, y  40
#   └──────────┴──────────┴──────────┘
#     stair        cash        pen
#
# Ways in, chosen per room rather than solved for:
#
#   hall      front door, kitchen, stair from the landing
#   kitchen   hall, jail, garden door
#   jail      kitchen, its own door on the end wall
#   landing   stair, vault
#   vault     landing, bedroom      - and a window OUT, one way, to the garden
#   bedroom   vault, trellis up from the garden
#
# Two is the floor everywhere and nothing reaches for a third. The vault has
# exactly two and both run through rooms somebody has to cross first, which is
# what makes holding it worth doing.
const GROUND: float = 40.0
const UPPER: float = GROUND + STOREY
const ROOF: float = UPPER + STOREY

const HOUSE_W: float = ROOM * 3.0 + WALL * 4.0 # 2385
const HOUSE_D: float = ROOM + WALL * 2.0 # 815

const GARDEN_D: float = 1400.0 ## between the two front doors
const SIDE: float = 400.0
const BEHIND: float = 200.0

const HOUSE_X: float = SIDE
const HOUSE_Z: float = BEHIND
const WORLD_W: float = HOUSE_W + SIDE * 2.0
const WORLD_D: float = (BEHIND + HOUSE_D) * 2.0 + GARDEN_D
const WORLD_H: float = ROOF + SLAB

## Slots left to right, as the plan reads.
const HALL: int = 0
const MIDDLE: int = 1
const FAR: int = 2

var _solids: Array[AABB] = []
var _root: Node3D = null
var _count: int = 0

func _initialize() -> void:
	_draw_house()

	_root = Node3D.new()
	_root.name = "HouseBlockout"
	_box("shell", Vector3(WORLD_W, WORLD_H, WORLD_D) * 0.5,
		Vector3(WORLD_W, WORLD_H, WORLD_D))
	# One slab under the whole world. Both ground floors and the garden sit at
	# the same height, so there is nothing to excavate, and nothing to fall into
	# whose edge a player cannot see.
	_blocker(AABB(Vector3.ZERO, Vector3(WORLD_W, GROUND, WORLD_D)))

	_stamp(false, &"team_a", "a")
	_stamp(true, &"team_b", "b")
	_outdoors()

	var scene: PackedScene = PackedScene.new()
	_own(_root)
	scene.pack(_root)
	var path: String = "res://game/blockout/house.tscn"
	var wrote: int = ResourceSaver.save(scene, path)
	print("%s: %s" % [path, "written" if wrote == OK else "FAILED (%d)" % wrote])
	print("world %d x %d x %d, %d blockers, 6 rooms per house" % [
		int(WORLD_W), int(WORLD_D), int(WORLD_H), _count])
	quit(0)

# ---- one house, in local coordinates ----
#
# x runs 0..HOUSE_W across the three slots; z runs 0..HOUSE_D with the FRONT of
# the house at +z. y is absolute and is never turned.

func _draw_house() -> void:
	for level: float in [GROUND, UPPER]:
		var top: float = level + STOREY - SLAB
		# Ends own the corners, front and back run between the ends, dividers
		# run between those. Nothing shares a volume with anything (§7).
		_wall_x(WALL * 0.5, 0.0, HOUSE_D, level, top, [] as Array[Vector2])
		_wall_x(HOUSE_W - WALL * 0.5, 0.0, HOUSE_D, level, top, _end_openings(level))
		_wall_z(WALL * 0.5, WALL, HOUSE_W - WALL, level, top, [] as Array[Vector2])
		_wall_z(HOUSE_D - WALL * 0.5, WALL, HOUSE_W - WALL, level, top,
			_front_openings(level))
		var doorway: Array[Vector2] = [_across(HOUSE_D * 0.5, DOOR)] as Array[Vector2]
		_wall_x(_slot(MIDDLE) - WALL * 0.5, WALL, HOUSE_D - WALL, level, top, doorway)
		_wall_x(_slot(FAR) - WALL * 0.5, WALL, HOUSE_D - WALL, level, top, doorway)

	_slab(UPPER, Rect2(0.0, 0.0, HOUSE_W, HOUSE_D), [_stairwell()] as Array[Rect2])
	_slab(ROOF, Rect2(0.0, 0.0, HOUSE_W, HOUSE_D), [] as Array[Rect2])

	# One staircase, in the hall, arriving on the landing directly above it.
	_flight(_slot(HALL) + 100.0, FLIGHT_FROM_WALL, GROUND)

	# The trellis: garden up to a bedroom window, against the far end of the
	# front so it fouls neither ground-floor door.
	_flight_x(_slot(FAR), HOUSE_D, GROUND, 300.0)

## The front of the house, facing the garden.
func _front_openings(level: float) -> Array[Vector2]:
	if level == GROUND:
		return [
			_across(_slot(HALL) + ROOM * 0.5, DOOR), # front door, into the hall
			_across(_slot(MIDDLE) + ROOM * 0.5, DOOR), # garden door, into the kitchen
		] as Array[Vector2]
	return [
		# The vault's window. A way OUT and never in: 330 down is a drop you walk
		# away from, 330 up is not a verb this game has. Climb in slowly by the
		# stair or the trellis; leave fast and committed, out of the window.
		_across(_slot(MIDDLE) + ROOM * 0.5, DOOR),
		# Off the top of the trellis, into the bedroom. Pulled back far enough
		# that the whole opening is in the bedroom's own wall and still meets
		# the top tread.
		_across(_slot(FAR) + RUN * float(TREADS) - 120.0, DOOR),
	] as Array[Vector2]

## The jail's own door, on the end wall, so the pen is not reached only through
## the kitchen. One door is one defender, and a pen nobody can reach is a
## rescue that never happens.
func _end_openings(level: float) -> Array[Vector2]:
	if level != GROUND:
		return [] as Array[Vector2]
	return [_across(HOUSE_D * 0.5, DOOR)] as Array[Vector2]

## The hole the flight needs in the floor above it, from the tread where a
## standing body's head would otherwise be inside the slab.
##
## Worked out the way the FILL will see it, not from the clear height: a body
## occupies the layer whose centre is first above its rest height, and the layer
## is as tall as a step, so the rounding is worth a whole tread (§11).
func _stairwell() -> Rect2:
	var ceiling: float = GROUND + STOREY - SLAB - BODY
	var covered: int = TREADS
	for i: int in TREADS:
		var rest: float = GROUND + STEP * float(i + 1) + BODY
		if (ceil(rest / STEP - 0.5) + 0.5) * STEP >= ceiling:
			covered = i
			break
	var from: float = FLIGHT_FROM_WALL + RUN * float(covered) - 40.0
	return Rect2(_slot(HALL) + 100.0, from, FLIGHT_W, HOUSE_D - from)

func _slot(index: int) -> float:
	return WALL + (ROOM + WALL) * float(index)

func _across(centre: float, width: float) -> Vector2:
	return Vector2(centre - width * 0.5, centre + width * 0.5)

# ---- placing it twice ----

## `turned` rotates the house 180 degrees about the middle of the world, so its
## front faces back across the garden. Mirroring in x instead would leave both
## houses facing the same way, which is what the last one did.
func _stamp(turned: bool, team: StringName, side: String) -> void:
	for box: AABB in _solids:
		_blocker(_place(box, turned))

	var rooms: Array[Array] = [
		[&"hall", ZoneDef.Role.HOME, HALL, GROUND],
		[&"kitchen", ZoneDef.Role.HOME, MIDDLE, GROUND],
		[&"jail", ZoneDef.Role.JAIL, FAR, GROUND],
		[&"landing", ZoneDef.Role.HOME, HALL, UPPER],
		[&"vault", ZoneDef.Role.CASH_ROOM, MIDDLE, UPPER],
		[&"bedroom", ZoneDef.Role.HOME, FAR, UPPER],
	]
	for room: Array in rooms:
		_zone(StringName("%s_%s" % [room[0], side]), room[1], team, 1,
			_place(AABB(Vector3(_slot(room[2]), room[3], WALL),
				Vector3(ROOM, STOREY, ROOM)), turned), false)

	for i: int in 3:
		_marker("spawn_%s_%d" % [team, i], _place(AABB(Vector3(
			_slot(HALL) + 480.0, GROUND + BODY, 200.0 + 180.0 * float(i)),
			Vector3.ONE), turned).position)
		_marker("cash_%s_%d" % [team, i], _place(AABB(Vector3(
			_slot(MIDDLE) + 180.0 + 200.0 * float(i), UPPER + BODY, HOUSE_D * 0.5),
			Vector3.ONE), turned).position)

func _place(box: AABB, turned: bool) -> AABB:
	var x: float = HOUSE_X + box.position.x
	var z: float = HOUSE_Z + box.position.z
	if turned:
		x = WORLD_W - x - box.size.x
		z = WORLD_D - z - box.size.z
	return AABB(Vector3(x, box.position.y, z), box.size)

## The garden, in three strips: each side's own ground nearest its own house,
## neutral ground in the middle.
##
## Whose ground it is decides where a seizure is LEGAL, and open ground
## belonging to nobody is where two sides meet and can do nothing about each
## other (§13). The middle stays neutral so crossing it is a decision.
func _outdoors() -> void:
	var high: float = WORLD_H - GROUND
	var neutral: float = 400.0
	var edge_a: float = (WORLD_D - neutral) * 0.5
	var edge_b: float = edge_a + neutral
	_zone(&"yard_a", ZoneDef.Role.HOME, &"team_a", 0,
		AABB(Vector3(0, GROUND, 0), Vector3(WORLD_W, high, edge_a)), true)
	_zone(&"garden", ZoneDef.Role.NEUTRAL, &"", 0,
		AABB(Vector3(0, GROUND, edge_a), Vector3(WORLD_W, high, neutral)), true)
	_zone(&"yard_b", ZoneDef.Role.HOME, &"team_b", 0,
		AABB(Vector3(0, GROUND, edge_b), Vector3(WORLD_W, high, WORLD_D - edge_b)), true)

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
		# Clamped to the wall's own extent. An opening placed near the end of a
		# wall used to run its lintel out past the corner and into the wall
		# round it - nine units of two boxes sharing a volume, which is nine
		# units of flickering corner.
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

## A straight flight running in +z.
func _flight(x: float, from_z: float, base: float) -> void:
	for i: int in TREADS:
		var top: float = base + STEP * float(i + 1)
		_solid(AABB(Vector3(x, base, from_z + RUN * float(i)),
			Vector3(FLIGHT_W, top - base, RUN)))

## A straight flight running in +x, outside the house, with a landing on top.
func _flight_x(from_x: float, z: float, base: float, landing: float) -> void:
	for i: int in TREADS:
		var top: float = base + STEP * float(i + 1)
		_solid(AABB(Vector3(from_x + RUN * float(i), base, z),
			Vector3(RUN, top - base, 220.0)))
	_solid(AABB(Vector3(from_x + RUN * float(TREADS), base + STOREY - SLAB, z),
		Vector3(landing, SLAB, 220.0)))

func _solid(box: AABB) -> void:
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
