class_name WalkableSurfaceDef
extends Resource
## A walkable surface, precomputed and stored with the level it belongs to.
##
## The surface is a pure function of static geometry and a body size, so
## computing it every time a level loads is work with a known answer. It cost
## ~800 ms for the grey-box house and scales with level VOLUME, which is the
## wrong direction to be heading in before the real house exists. The baker
## works it out once; loading is then reading two arrays.
##
## Stored as CSR (compressed sparse row) rather than a dictionary of arrays:
## `edge_offsets[i]` to `edge_offsets[i + 1]` is node i's slice of
## `edge_targets`. Two flat arrays serialise into a .tres cleanly and load
## without allocating a container per node.
##
## The runtime builder does NOT go away. Fixtures build surfaces directly, a
## level whose bake is stale rebuilds rather than trusting it, and the two paths
## must agree - see WalkableSurface.from_def.

@export var nodes: PackedVector3Array = PackedVector3Array()
## Node i's neighbours are edge_targets[edge_offsets[i] .. edge_offsets[i+1]].
## Sized nodes + 1, so the last node needs no special case.
@export var edge_offsets: PackedInt32Array = PackedInt32Array()
@export var edge_targets: PackedInt32Array = PackedInt32Array()

@export_group("What it was built for")
@export var radius: float = 0.0
@export var step_up_height: float = 0.0
@export var cell_size: float = 0.0
@export var layer_height: float = 0.0
## Identifies the geometry and body this was computed from. A bake that no
## longer describes the level must be detected, not trusted: moving one wall in
## the blockout and forgetting to re-bake would otherwise leave the gate
## certifying a level that no longer exists and bots pathing through a wall.
@export var fingerprint: String = ""

## Canonical description of the inputs a surface depends on.
##
## Hashed rather than stored whole, because a real house is hundreds of blockers
## and the point is a cheap comparison. `String.hash()` is stable within a build,
## which is all a staleness check needs - this is a cache-validity marker, never
## anything that crosses the wire.
static func fingerprint_of(
	collision: WorldCollisionDef,
	body_radius: float,
	step_up: float
) -> String:
	if collision == null:
		return ""
	var parts: PackedStringArray = PackedStringArray()
	parts.append("%s|%s" % [collision.bounds.position, collision.bounds.size])
	parts.append("r%.4f|s%.4f|n%d" % [body_radius, step_up, collision.blockers.size()])
	for blocker: AABB in collision.blockers:
		parts.append("%s/%s" % [blocker.position, blocker.size])
	return "%d" % "".join(parts).hash()

## Does this bake still describe the level and body it is being loaded for?
func matches(collision: WorldCollisionDef, body_radius: float, step_up: float) -> bool:
	if nodes.is_empty() or fingerprint == "":
		return false
	return fingerprint == fingerprint_of(collision, body_radius, step_up)
