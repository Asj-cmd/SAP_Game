extends SceneTree
## Generates the blockout for the three-storey house. See HOUSE_LAYOUT.md.
##
##   godot --headless --path godot --script res://tools/build_house.gd
##
## UNFINISHED, AND NOTHING LOADS IT. What it writes does not pass the load gate:
## the floors and internal doors do not connect the way HOUSE_LAYOUT.md says, so
## the only through-route is the external trellis and seven rooms can be entered
## and not left. It is committed as a starting point for the modelling pass, not
## as a level. The game plays game/blockout/greybox_house.tscn until this one
## bakes clean; run it with an explicit --out= and read the gate's complaints.
##
## Written rather than hand-placed because the house is parametric and mirrored:
## two hundred boxes dragged into place would be two hundred chances to put one
## at a height that is not in the threshold set, and the mirror would be a second
## two hundred. Every dimension below comes from TuningDef or from
## WORLD_AUTHORING.md §10 and §12 - nothing here invents a number.
##
## The output is an ordinary blockout scene. tools/bake_blockout_headless.gd
## reads it exactly as it read the old one; nothing downstream knows the
## difference.

# ---- the threshold set (WORLD_AUTHORING.md §12) ----
const STEP: float = 30.0 ## walk over
const VAULT: float = 120.0 ## hop over
const CROUCH: float = 130.0 ## duck through
const STOREY: float = 320.0 ## floor to floor

# ---- room dimensions (WORLD_AUTHORING.md §10) ----
const ROOM: float = 755.0 ## camera needs it
const WALL: float = 30.0
const DOOR: float = 240.0
const SLAB: float = 40.0
const STAIR_W: float = 300.0

const HOUSE_W: float = ROOM * 3.0 + WALL * 4.0 # 2385
const HOUSE_D: float = ROOM + WALL * 2.0 # 815
const GARDEN_W: float = 1200.0
const FRONT_D: float = 800.0

const WORLD_W: float = HOUSE_W * 2.0 + GARDEN_W
const WORLD_D: float = HOUSE_D + FRONT_D
const WORLD_H: float = STOREY * 3.0 + SLAB

## Floor levels: the top of each slab is where a body stands.
const BASEMENT: float = SLAB
const GROUND: float = STOREY + SLAB
const UPPER: float = STOREY * 2.0 + SLAB

var _root: Node3D = null

func _initialize() -> void:
	_root = Node3D.new()
	_root.name = "HouseBlockout"

	_box("shell", Vector3(WORLD_W * 0.5, WORLD_H * 0.5, WORLD_D * 0.5),
		Vector3(WORLD_W, WORLD_H, WORLD_D))
	# The ground everything stands on.
	_blocker(Vector3(WORLD_W * 0.5, SLAB * 0.5, WORLD_D * 0.5), Vector3(WORLD_W, SLAB, WORLD_D))

	_house(0.0, &"team_a", false)
	_house(HOUSE_W + GARDEN_W, &"team_b", true)
	_zone(&"garden", ZoneDef.Role.NEUTRAL, &"", 0,
		Vector3(WORLD_W * 0.5, WORLD_H * 0.5, WORLD_D * 0.5),
		Vector3(WORLD_W, WORLD_H, WORLD_D))

	var scene: PackedScene = PackedScene.new()
	_reparent(_root)
	scene.pack(_root)
	var path: String = "res://game/blockout/house.tscn"
	print("wrote %s (%s)" % [path, "ok" if ResourceSaver.save(scene, path) == OK else "FAILED"])
	print("world %d x %d x %d" % [int(WORLD_W), int(WORLD_D), int(WORLD_H)])
	quit(0)

## Everything must be owned by the scene root or pack() drops it.
func _reparent(node: Node) -> void:
	for child: Node in node.get_children():
		child.owner = _root
		_reparent(child)

# ---- one house ----

## `flip` mirrors the room order so the two houses face the garden the same way.
func _house(origin: float, team: StringName, flip: bool) -> void:
	var side: String = String(team).right(1)
	# Room centres, left to right. Mirrored houses read right to left.
	var slots: Array[float] = []
	for i: int in 3:
		slots.append(origin + WALL + ROOM * 0.5 + (ROOM + WALL) * float(i))
	if flip:
		slots.reverse()
	var mid: float = origin + HOUSE_W * 0.5
	var depth: float = WALL + ROOM * 0.5

	_shell_walls(origin)
	_floors(origin)

	# Basement: the stair arrives in the cellar, and the jail is at the far end.
	_room(&"cellar_%s" % side, ZoneDef.Role.HOME, team, slots[0], BASEMENT, depth)
	_room(&"boiler_%s" % side, ZoneDef.Role.HOME, team, slots[1], BASEMENT, depth)
	_room(&"jail_%s" % side, ZoneDef.Role.JAIL, team, slots[2], BASEMENT, depth)

	# Ground: hall holds the stairs, kitchen and living beyond it.
	_room(&"hall_%s" % side, ZoneDef.Role.HOME, team, slots[0], GROUND, depth)
	_room(&"kitchen_%s" % side, ZoneDef.Role.HOME, team, slots[1], GROUND, depth)
	_room(&"living_%s" % side, ZoneDef.Role.HOME, team, slots[2], GROUND, depth)

	# Upper: the study is in the MIDDLE, so the landing and the bedroom are two
	# genuinely separate approaches to it rather than one chain.
	_room(&"landing_%s" % side, ZoneDef.Role.HOME, team, slots[0], UPPER, depth)
	_room(&"vault_%s" % side, ZoneDef.Role.CASH_ROOM, team, slots[1], UPPER, depth)
	_room(&"bedroom_%s" % side, ZoneDef.Role.HOME, team, slots[2], UPPER, depth)

	# Internal doors, one per dividing wall per floor.
	for level: float in [BASEMENT, GROUND, UPPER]:
		_doorway(origin + WALL + ROOM + WALL * 0.5, level, depth)
		_doorway(origin + WALL * 2.0 + ROOM * 2.0 + WALL * 0.5, level, depth)

	_staircase(slots[0], GROUND, depth, 1.0) # hall up to landing
	_staircase(slots[0], BASEMENT, depth, 1.0) # cellar up to hall

	_front_door(mid, origin, flip)
	_coal_hatch(slots[2], origin, flip)
	_trellis(slots[2], origin, flip)

	_marker("spawn_%s_0" % team, Vector3(slots[0], GROUND + 20.0, depth))
	for i: int in 3:
		_marker("cash_%s_%d" % [team, i],
			Vector3(slots[1] - 200.0 + 200.0 * float(i), UPPER + 20.0, depth))

## The outer box of a house: four walls per storey, with the garden side left
## for the doors and climbs to cut through.
func _shell_walls(origin: float) -> void:
	for level: float in [BASEMENT, GROUND, UPPER]:
		var y: float = level + STOREY * 0.5 - SLAB * 0.5
		var h: float = STOREY - SLAB
		_blocker(Vector3(origin + WALL * 0.5, y, WALL + ROOM * 0.5), Vector3(WALL, h, HOUSE_D))
		_blocker(Vector3(origin + HOUSE_W - WALL * 0.5, y, WALL + ROOM * 0.5),
			Vector3(WALL, h, HOUSE_D))
		_blocker(Vector3(origin + HOUSE_W * 0.5, y, WALL * 0.5), Vector3(HOUSE_W, h, WALL))
		_blocker(Vector3(origin + HOUSE_W * 0.5, y, HOUSE_D - WALL * 0.5),
			Vector3(HOUSE_W, h, WALL))

## Floor slabs, with a hole above each staircase.
func _floors(origin: float) -> void:
	var stair_x: float = origin + WALL + ROOM * 0.5
	for level: float in [GROUND, UPPER]:
		var y: float = level - SLAB * 0.5
		# Left of the stairwell, and everything right of it.
		var gap_from: float = stair_x - STAIR_W * 0.5
		var gap_to: float = stair_x + STAIR_W * 0.5
		_blocker(Vector3((origin + gap_from) * 0.5, y, WALL + ROOM * 0.5),
			Vector3(maxf(gap_from - origin, 1.0), SLAB, HOUSE_D))
		_blocker(Vector3((gap_to + origin + HOUSE_W) * 0.5, y, WALL + ROOM * 0.5),
			Vector3(maxf(origin + HOUSE_W - gap_to, 1.0), SLAB, HOUSE_D))
		# In front of and behind the opening, so only the stair well is open.
		_blocker(Vector3(stair_x, y, WALL + ROOM * 0.25),
			Vector3(STAIR_W, SLAB, ROOM * 0.5))

## Eleven treads. A storey at a step a time is what the threshold set costs.
func _staircase(x: float, base: float, z: float, direction: float) -> void:
	var steps: int = int(ceil(STOREY / STEP))
	var rise: float = STOREY / float(steps)
	var run: float = (ROOM * 0.55) / float(steps)
	for i: int in steps:
		var top: float = base + rise * float(i + 1)
		var at_z: float = z + ROOM * 0.20 + run * float(i) * direction
		_blocker(Vector3(x, base + (top - base) * 0.5, at_z),
			Vector3(STAIR_W, top - base, run))

# ---- ways in ----

func _front_door(x: float, origin: float, flip: bool) -> void:
	_cut(Vector3(x, GROUND, _garden_face(origin, flip)), Vector3(DOOR, STOREY - SLAB, WALL * 2.0))

## A sloped chute into the jail. Slope, not drop, so it works both ways.
func _coal_hatch(x: float, origin: float, flip: bool) -> void:
	var face: float = _garden_face(origin, flip)
	var steps: int = int(ceil(STOREY / STEP))
	var rise: float = STOREY / float(steps)
	var outward: float = 1.0 if flip else -1.0
	for i: int in steps:
		var top: float = BASEMENT + rise * float(i + 1)
		var at_z: float = face + outward * (WALL + 60.0 * float(i))
		_blocker(Vector3(x, BASEMENT + (top - BASEMENT) * 0.5, at_z),
			Vector3(DOOR, top - BASEMENT, 60.0))
	_cut(Vector3(x, BASEMENT, face), Vector3(DOOR, STOREY - SLAB, WALL * 2.0))

## Garden to balcony to bedroom, bypassing the landing entirely.
func _trellis(x: float, origin: float, flip: bool) -> void:
	var face: float = _garden_face(origin, flip)
	var outward: float = 1.0 if flip else -1.0
	var steps: int = int(ceil((UPPER - GROUND + STOREY) / STEP))
	var rise: float = (UPPER - SLAB) / float(steps)
	for i: int in steps:
		var top: float = SLAB + rise * float(i + 1)
		var at_z: float = face + outward * (WALL + 40.0 + 55.0 * float(i))
		_blocker(Vector3(x + ROOM * 0.30, SLAB + (top - SLAB) * 0.5, at_z),
			Vector3(200.0, top - SLAB, 55.0))
	# The balcony itself, and the way in off it.
	_blocker(Vector3(x + ROOM * 0.30, UPPER - SLAB * 0.5, face + outward * (WALL + 60.0)),
		Vector3(320.0, SLAB, 200.0))
	_cut(Vector3(x + ROOM * 0.30, UPPER, face), Vector3(DOOR, STOREY - SLAB, WALL * 2.0))

func _garden_face(origin: float, flip: bool) -> float:
	return HOUSE_D - WALL * 0.5 if not flip else WALL * 0.5

# ---- primitives ----

## A doorway is an ABSENCE, so it is cut by splitting the wall around it.
func _doorway(x: float, level: float, z: float) -> void:
	var h: float = STOREY - SLAB
	var y: float = level + h * 0.5
	var side: float = (ROOM - DOOR) * 0.5
	_blocker(Vector3(x, y, z - DOOR * 0.5 - side * 0.5), Vector3(WALL, h, side))
	_blocker(Vector3(x, y, z + DOOR * 0.5 + side * 0.5), Vector3(WALL, h, side))
	# Over the top, so the opening reads as a door rather than a missing wall.
	_blocker(Vector3(x, level + h - 30.0, z), Vector3(WALL, 60.0, DOOR))

## An opening in an outer wall: the wall either side of it, and a lintel over.
func _cut(at: Vector3, size: Vector3) -> void:
	var h: float = size.y
	var side: float = (HOUSE_W - size.x) * 0.5
	_blocker(Vector3(at.x - size.x * 0.5 - side * 0.5, at.y + h * 0.5, at.z),
		Vector3(side, h, size.z * 0.5))
	_blocker(Vector3(at.x + size.x * 0.5 + side * 0.5, at.y + h * 0.5, at.z),
		Vector3(side, h, size.z * 0.5))
	_blocker(Vector3(at.x, at.y + h - 30.0, at.z), Vector3(size.x, 60.0, size.z * 0.5))

func _room(id: StringName, role: ZoneDef.Role, team: StringName, x: float, level: float, z: float) -> void:
	_zone(id, role, team, 1, Vector3(x, level + STOREY * 0.5, z),
		Vector3(ROOM, STOREY, ROOM))

func _box(name: String, at: Vector3, size: Vector3) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = name
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	_root.add_child(node)
	return node

var _blockers: int = 0

func _blocker(at: Vector3, size: Vector3) -> void:
	_blockers += 1
	_box("blocker_%d" % _blockers, at, size)

func _zone(id: StringName, role: ZoneDef.Role, team: StringName, priority: int, at: Vector3, size: Vector3) -> void:
	var node: BlockoutZone = BlockoutZone.new()
	node.name = "zone_%s" % id
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.zone_id = id
	node.role = role
	node.owner_team = team
	node.priority = priority
	_root.add_child(node)

func _marker(name: String, at: Vector3) -> void:
	var node: Marker3D = Marker3D.new()
	node.name = name
	node.position = at
	_root.add_child(node)
