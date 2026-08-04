class_name BlockoutBaker
extends RefCounted
## Turns a blockout scene into a LevelDef. See WORLD_AUTHORING.md §6.
##
## This is the export convention that document specifies, pointed at Godot
## instead of Blender for now. The convention is the durable part: boxes named
## one way become collision, boxes carrying zone data become rooms, empties
## become placement. Swapping the source from a .tscn to a .blend later changes
## where the boxes come from and nothing about what they mean.
##
## Art and collision stay separate (§6). Nothing here derives a blocker from a
## decorative mesh - a box is a blocker because it was NAMED one - so adding
## scenery can never silently change what a player walks through.
##
##   shell                -> WorldCollisionDef.bounds
##   blocker_*            -> WorldCollisionDef.blockers
##   BlockoutZone script  -> ZoneDef
##   spawn_<team>_<slot>  -> TeamDef.spawn_points
##   cash_<team>_<index>  -> TeamDef.cash_points

const BLOCKER_PREFIX: String = "blocker"
const SHELL_NAME: String = "shell"
const SPAWN_PREFIX: String = "spawn"
const CASH_PREFIX: String = "cash"

var failures: PackedStringArray = PackedStringArray()

## Reads `root` and returns the level it describes, or null if the scene is
## not bakeable. Problems are collected in `failures`.
## `body` is the tuning the level will be played with. The walkable surface
## depends on how big the thing walking is, so a bake is only valid for a body -
## and the fingerprint stored with it records which, so a tuning change is
## detected at load rather than silently navigated with the wrong footprint.
func bake(
	root: Node3D,
	level_id: StringName,
	source: String = "",
	body: TuningDef = null
) -> LevelDef:
	failures = PackedStringArray()

	var level: LevelDef = LevelDef.new()
	level.id = level_id
	level.display_name = String(level_id).capitalize()
	level.source_scene = source
	level.collision = WorldCollisionDef.new()

	var blockers: Array[AABB] = []
	var zones: Array[ZoneDef] = []
	var spawns: Dictionary[StringName, Array] = {}
	var cash: Dictionary[StringName, Array] = {}
	var found_shell: bool = false

	for placed: Dictionary in _walk(root, Transform3D.IDENTITY):
		var node: Node = placed["node"]
		var world: Transform3D = placed["transform"]

		var zone_node: BlockoutZone = node as BlockoutZone
		if zone_node != null:
			if zone_node.zone_id == &"":
				failures.append("zone node %s has no zone_id" % node.name)
				continue
			zones.append(zone_node.to_zone_def(_box_bounds(zone_node, world)))
			continue

		var node_name: String = String(node.name)
		if node_name == SHELL_NAME:
			var shell: MeshInstance3D = node as MeshInstance3D
			if shell == null:
				failures.append("shell must be a MeshInstance3D with a BoxMesh")
				continue
			level.collision.bounds = _box_bounds(shell, world)
			found_shell = true
		elif node_name.begins_with(BLOCKER_PREFIX):
			var solid: MeshInstance3D = node as MeshInstance3D
			if solid == null:
				failures.append("%s is named as a blocker but is not a MeshInstance3D" % node_name)
				continue
			blockers.append(_box_bounds(solid, world))
		elif node_name.begins_with(SPAWN_PREFIX):
			_record_marker(node, world, SPAWN_PREFIX, spawns)
		elif node_name.begins_with(CASH_PREFIX):
			_record_marker(node, world, CASH_PREFIX, cash)

	if not found_shell:
		failures.append("no node named %s - the level has no outer bounds" % SHELL_NAME)
	if zones.is_empty():
		failures.append("no BlockoutZone nodes - the level has no rooms")

	# Sorted so a bake is reproducible. Re-parenting or reordering nodes in the
	# editor must not change the baked file, or every save reads as an edit and
	# a real change is impossible to spot in a diff.
	zones.sort_custom(_compare_zones)
	blockers.sort_custom(_compare_boxes)
	level.collision.blockers = blockers
	level.zones = zones
	level.teams = _build_teams(spawns, cash)

	if not failures.is_empty():
		return null

	# Precomputed here so loading the level is a read rather than a fill. Done
	# last, because it needs the finished collision.
	if body != null:
		level.surface = WalkableSurface.build(
			level.collision, body.actor_radius, body.step_up_height, body.max_drop_height
		).to_def()
		if level.surface.nodes.is_empty():
			failures.append("nothing in this level can be stood on")
			return null
	return level

## Depth-first, accumulating each node's placement as it goes.
##
## Transforms are composed here rather than read from global_transform,
## because global_transform is only valid for a node that is inside the tree -
## and a baker should not require the level to be running to read it. This also
## makes the in-editor and headless bakes read identically, which is the whole
## reason two entry points can share one implementation.
func _walk(node: Node, inherited: Transform3D) -> Array[Dictionary]:
	var world: Transform3D = inherited
	var spatial: Node3D = node as Node3D
	if spatial != null:
		world = inherited * spatial.transform
	var found: Array[Dictionary] = [{"node": node, "transform": world}]
	for child: Node in node.get_children():
		found.append_array(_walk(child, world))
	return found

func _box_bounds(node: MeshInstance3D, world: Transform3D) -> AABB:
	var box: BoxMesh = node.mesh as BoxMesh
	var size: Vector3 = box.size if box != null else Vector3.ONE
	var extents: Vector3 = size * world.basis.get_scale()
	return AABB(world.origin - extents * 0.5, extents)

## Named <prefix>_<team>_<index>, so spawn_team_a_0 is team_a slot 0.
func _record_marker(
	node: Node,
	world: Transform3D,
	prefix: String,
	into: Dictionary[StringName, Array]
) -> void:
	var spatial: Node3D = node as Node3D
	if spatial == null:
		failures.append("%s is named as a marker but is not a Node3D" % node.name)
		return
	var parts: PackedStringArray = String(node.name).split("_")
	if parts.size() < 3:
		failures.append("marker %s should be named %s_<team>_<index>" % [node.name, prefix])
		return
	var team_parts: PackedStringArray = parts.slice(1, parts.size() - 1)
	var team: StringName = StringName("_".join(team_parts))
	if not into.has(team):
		into[team] = []
	into[team].append({"name": String(node.name), "position": world.origin})

func _build_teams(
	spawns: Dictionary[StringName, Array],
	cash: Dictionary[StringName, Array]
) -> Array[TeamDef]:
	var ids: Array[StringName] = []
	for team_id: StringName in spawns:
		ids.append(team_id)
	for team_id: StringName in cash:
		if not ids.has(team_id):
			ids.append(team_id)
	# By characters, not by interning identity (NameOrder). Here it decides the
	# order teams are written into the level file, so an interning-order sort
	# would make a bake depend on what the editor happened to intern first and
	# every re-bake read as an edit.
	ids = NameOrder.sorted_string_names(ids)

	var teams: Array[TeamDef] = []
	for team_id: StringName in ids:
		var team: TeamDef = TeamDef.new()
		team.id = team_id
		team.display_name = String(team_id).replace("_", " ").capitalize()
		team.spawn_points = _points(spawns.get(team_id, []))
		team.cash_points = _points(cash.get(team_id, []))
		if team.spawn_points.is_empty():
			failures.append("team %s has no spawn markers" % team_id)
		teams.append(team)
	return teams

## Ordered by marker NAME, not tree order, so re-parenting a marker in the
## editor cannot silently renumber a team's spawn slots.
func _points(markers: Array) -> Array[Vector3]:
	var sorted: Array = markers.duplicate()
	sorted.sort_custom(_compare_markers)
	var points: Array[Vector3] = []
	for marker: Dictionary in sorted:
		points.append(marker["position"])
	return points

func _compare_markers(a: Dictionary, b: Dictionary) -> bool:
	return String(a["name"]) < String(b["name"])

func _compare_zones(a: ZoneDef, b: ZoneDef) -> bool:
	return NameOrder.compare(a.id, b.id)

func _compare_boxes(a: AABB, b: AABB) -> bool:
	if a.position.x != b.position.x:
		return a.position.x < b.position.x
	if a.position.y != b.position.y:
		return a.position.y < b.position.y
	return a.position.z < b.position.z
