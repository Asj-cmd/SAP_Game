class_name ContentValidator
extends RefCounted
## Checks authored content before anyone tries to play it.
## See WORLD_AUTHORING.md §7 - step two of §8's order of work.
##
## The premise is that care is not a strategy here. Every failure below is
## invisible by inspection: a room nobody can reach looks exactly like a room
## nobody happened to walk to, and a doorway too narrow for a body looks like a
## doorway. So the check is mechanical and it fails loudly.
##
## Calibrated against the two-room box, deliberately, before a real house
## exists - §8 puts the validator second precisely so it never has to be
## debugged at the same time as the content it is judging.
##
## Rows of §7's table NOT yet implemented, and why:
##
##   "Blocker shell is closed" - the shell is an AABB, so it cannot have a
##   seam. This becomes a real check when the shell is made of blockers.
##
##   "No blocker overlaps a doorway gap" and "every gap >= actor width" - a
##   doorway is an absence, so neither is directly expressible. Reachability
##   covers both in practice: a gap too narrow for a body does not admit the
##   flood fill, and the room behind it reports unreachable.
##
##   "Min gap between blockers > max per-tick displacement" - this guarded
##   against tunnelling, which swept segment tests (§4) removed as a class.
##   Implementing it now would flag every ordinary doorway.
##
##   Floors and gravity - the fill is volumetric because nothing falls yet.
##   It becomes a walkable-surface fill once the kinematic controller lands.

## Grid divisions along the longest axis of the shell.
##
## Finer than a body, so a doorway several bodies wide is several cells wide
## and the fill cannot miss it. Errs toward reporting unreachable, which is the
## direction that fails safe: a false alarm costs a look, a missed one ships a
## room nobody can enter.
const FILL_DIVISIONS: int = 64

## Every problem found. Empty means the content is playable.
static func validate(world: SimWorld) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	_check_shell(world, failures)
	_check_zone_priorities(world, failures)
	_check_reference_points(world, failures)
	_check_reachability(world, failures)
	return failures

# ---- shell ----

static func _check_shell(world: SimWorld, failures: PackedStringArray) -> void:
	if world.collision == null:
		failures.append("collision: no WorldCollisionDef installed - the world has no walls")
		return
	var shell: AABB = world.collision.bounds
	if shell.size.x <= 0.0 or shell.size.y <= 0.0 or shell.size.z <= 0.0:
		failures.append("collision: shell bounds are degenerate %s" % shell)
		return
	for i: int in world.collision.blockers.size():
		var blocker: AABB = world.collision.blockers[i]
		if blocker.size.x <= 0.0 or blocker.size.y <= 0.0 or blocker.size.z <= 0.0:
			failures.append("collision: blocker %d is degenerate %s" % [i, blocker])
		if not shell.intersects(blocker):
			failures.append("collision: blocker %d lies outside the shell %s" % [i, blocker])

# ---- zones ----

## Overlap is legal and useful, but only when the winner is decided. Equal
## priorities leave "which room am I in" resolved by a tie-break nobody chose.
static func _check_zone_priorities(world: SimWorld, failures: PackedStringArray) -> void:
	var ids: Array[StringName] = world.zone_ids_in_resolution_order()
	ids.sort()
	for i: int in ids.size():
		for j: int in range(i + 1, ids.size()):
			var a: ZoneDef = world.zones[ids[i]]
			var b: ZoneDef = world.zones[ids[j]]
			if not a.bounds.intersects(b.bounds):
				continue
			if a.priority == b.priority:
				failures.append(
					"zones: '%s' and '%s' overlap at equal priority %d - which room wins is arbitrary"
					% [a.id, b.id, a.priority]
				)

# ---- placement ----

## Every point the match puts a body on must be somewhere a body can be.
static func _check_reference_points(world: SimWorld, failures: PackedStringArray) -> void:
	if world.collision == null:
		return
	var radius: float = _actor_radius(world)

	for team_id: StringName in world.sorted_team_ids():
		var team: TeamDef = world.teams[team_id]
		for slot: int in team.spawn_points.size():
			_require_standable(world, team.spawn_points[slot], radius,
				"spawn %s[%d]" % [team_id, slot], failures)

	# A cash room or holding pen whose centre is inside a wall means a round
	# that cannot be won or a prisoner who cannot be reached.
	for zone_id: StringName in world.zone_ids_in_resolution_order():
		var zone: ZoneDef = world.zones[zone_id]
		if zone.role == ZoneDef.Role.CASH_ROOM or zone.role == ZoneDef.Role.JAIL:
			_require_standable(world, zone.bounds.get_center(), radius,
				"%s centre '%s'" % [ZoneDef.Role.keys()[zone.role], zone_id], failures)

static func _require_standable(
	world: SimWorld,
	point: Vector3,
	radius: float,
	label: String,
	failures: PackedStringArray
) -> void:
	if not world.collision.contains(point, radius):
		failures.append("placement: %s at %s is outside the shell" % [label, point])
		return
	if world.collision.blocks_segment(point, point, radius):
		failures.append("placement: %s at %s is inside a blocker" % [label, point])

# ---- reachability ----

## Flood fill the walkable volume at body size and confirm every zone is in it.
##
## This is the check that catches the failures nobody sees coming: a room
## walled off by an edit three rooms away, a vault reachable only through a gap
## narrower than a player. It is also the traversal the bots will want, so the
## work is not spent twice (§7).
static func _check_reachability(world: SimWorld, failures: PackedStringArray) -> void:
	if world.collision == null:
		return
	var shell: AABB = world.collision.bounds
	if shell.size == Vector3.ZERO:
		return

	var radius: float = _actor_radius(world)
	var step: float = maxf(shell.size[shell.get_longest_axis_index()] / float(FILL_DIVISIONS), 0.001)
	var counts: Vector3i = Vector3i(
		maxi(1, int(shell.size.x / step)),
		maxi(1, int(shell.size.y / step)),
		maxi(1, int(shell.size.z / step))
	)

	var seeds: Array[Vector3] = _seed_points(world)
	if seeds.is_empty():
		failures.append("reachability: no spawn points authored - nothing to flood from")
		return

	# Flood from ONE seed, not all of them at once.
	#
	# Seeding every spawn together only proves each zone is reachable from
	# SOME spawn, which is a much weaker claim and passes a map sealed down
	# the middle - each team floods its own half and every room is covered.
	# §7 asks for reachable from EVERY spawn, and since traversal is
	# symmetric that is exactly "one connected component holds all of them".
	var reached: Dictionary[Vector3i, bool] = {}
	var queue: Array[Vector3i] = []
	var rooted: bool = false
	for seed_point: Vector3 in seeds:
		var cell: Vector3i = _cell_of(seed_point, shell, step, counts)
		if not _standable(world, _centre_of(cell, shell, step), radius):
			failures.append("reachability: spawn at %s is not standable" % seed_point)
			continue
		if not rooted:
			rooted = true
			reached[cell] = true
			queue.append(cell)
	if not rooted:
		return

	const NEIGHBOURS: Array[Vector3i] = [
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
		Vector3i(0, 1, 0), Vector3i(0, -1, 0),
		Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	]
	while not queue.is_empty():
		var cell: Vector3i = queue.pop_front()
		var here: Vector3 = _centre_of(cell, shell, step, )
		for offset: Vector3i in NEIGHBOURS:
			var next: Vector3i = cell + offset
			if next.x < 0 or next.y < 0 or next.z < 0:
				continue
			if next.x >= counts.x or next.y >= counts.y or next.z >= counts.z:
				continue
			if reached.has(next):
				continue
			var there: Vector3 = _centre_of(next, shell, step)
			if not _standable(world, there, radius):
				continue
			if world.collision.blocks_segment(here, there, radius):
				continue
			reached[next] = true
			queue.append(next)

	# Every other spawn must be in the same component, or the map is cut in
	# two and each team is sealed into its own half.
	for seed_point: Vector3 in seeds:
		var cell: Vector3i = _cell_of(seed_point, shell, step, counts)
		if not _standable(world, _centre_of(cell, shell, step), radius):
			continue # already reported above
		if not reached.has(cell):
			failures.append(
				"reachability: spawn at %s cannot be reached from the rest of the map" % seed_point
			)

	for zone_id: StringName in world.zone_ids_in_resolution_order():
		var zone: ZoneDef = world.zones[zone_id]
		var found: bool = false
		for cell: Vector3i in reached:
			if zone.contains_point(_centre_of(cell, shell, step)):
				found = true
				break
		if not found:
			failures.append("reachability: zone '%s' cannot be reached from every spawn" % zone_id)

## Where the fill starts: authored spawns, falling back to the centre of each
## team's home so a fixture without a roster still validates.
static func _seed_points(world: SimWorld) -> Array[Vector3]:
	var seeds: Array[Vector3] = []
	for team_id: StringName in world.sorted_team_ids():
		var team: TeamDef = world.teams[team_id]
		if not team.spawn_points.is_empty():
			seeds.append_array(team.spawn_points)
		elif team.home_zone != &"":
			var home: ZoneDef = world.get_zone(team.home_zone)
			if home != null:
				seeds.append(home.bounds.get_center())
	if seeds.is_empty():
		for zone_id: StringName in world.zone_ids_in_resolution_order():
			seeds.append(world.zones[zone_id].bounds.get_center())
	return seeds

static func _standable(world: SimWorld, point: Vector3, radius: float) -> bool:
	if not world.collision.contains(point, radius):
		return false
	return not world.collision.blocks_segment(point, point, radius)

static func _cell_of(point: Vector3, shell: AABB, step: float, counts: Vector3i) -> Vector3i:
	var local: Vector3 = point - shell.position
	return Vector3i(
		clampi(int(local.x / step), 0, counts.x - 1),
		clampi(int(local.y / step), 0, counts.y - 1),
		clampi(int(local.z / step), 0, counts.z - 1)
	)

static func _centre_of(cell: Vector3i, shell: AABB, step: float) -> Vector3:
	return shell.position + (Vector3(cell) + Vector3(0.5, 0.5, 0.5)) * step

static func _actor_radius(world: SimWorld) -> float:
	return world.tuning.actor_radius if world.tuning != null else 0.0
