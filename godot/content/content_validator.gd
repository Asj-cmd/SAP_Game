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
## Lives in content/ and takes CONTENT rather than a SimWorld, because
## SimWorld.configure() calls it as a load gate. A validator the simulation
## depends on must sit below the simulation, or the dependency arrow points
## the wrong way (§1).
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
## The row about floors and gravity is now PAID OFF. The fill used to be
## volumetric because it predated the kinematic controller, and it certified
## anywhere a body fit - including sealed voids and any basement without a way
## down. It is a walkable-surface fill now (WalkableSurface), so reachable means
## an actor can WALK there.

## Every problem found. Empty means the content is playable.
##
## `prebuilt` lets a caller that already needs the walkable surface - SimWorld,
## which hands it to the bots afterwards - pass the one it built rather than pay
## for a second identical fill. Omitted, the surface is built here and dropped.
## Capacity standing in for "as many as you like", on the edges out of the
## source. Any real count of doorways is far below it.
const UNLIMITED: int = 1 << 20

static func validate(
	zone_defs: Array[ZoneDef],
	team_defs: Array[TeamDef],
	collision: WorldCollisionDef,
	tuning: TuningDef,
	prebuilt: WalkableSurface = null,
	advisories: Array[String] = []
) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	var zones: Array[ZoneDef] = _sorted_zones(zone_defs)
	var radius: float = tuning.actor_radius if tuning != null else 0.0
	var step_up: float = tuning.step_up_height if tuning != null else 0.0
	var max_drop: float = tuning.max_drop_height if tuning != null else 0.0
	var required: int = tuning.routes_required if tuning != null else 2
	var wanted: int = tuning.routes_wanted if tuning != null else 3

	_check_shell(collision, failures)
	_check_zone_priorities(zones, failures)
	if collision != null:
		_check_reference_points(zones, team_defs, collision, radius, failures)
		var surface: WalkableSurface = prebuilt
		if surface == null:
			surface = WalkableSurface.build(collision, radius, step_up, max_drop)
		_check_reachability(zones, team_defs, collision, radius, step_up, max_drop, failures, surface)
		_check_escapability(zones, team_defs, surface, failures)
		_check_redundant_routes(
			zones, surface, required, wanted, collision.is_fixture, failures, advisories
		)
	return failures

## Zones in a fixed order, so every message and every traversal below is
## deterministic regardless of the order content happened to load in.
static func _sorted_zones(zone_defs: Array[ZoneDef]) -> Array[ZoneDef]:
	var sorted: Array[ZoneDef] = zone_defs.duplicate()
	sorted.sort_custom(_compare_zone_id)
	return sorted

static func _compare_zone_id(a: ZoneDef, b: ZoneDef) -> bool:
	return NameOrder.compare(a.id, b.id)

# ---- shell ----

static func _check_shell(collision: WorldCollisionDef, failures: PackedStringArray) -> void:
	if collision == null:
		failures.append("collision: no WorldCollisionDef installed - the world has no walls")
		return
	var shell: AABB = collision.bounds
	if shell.size.x <= 0.0 or shell.size.y <= 0.0 or shell.size.z <= 0.0:
		failures.append("collision: shell bounds are degenerate %s" % shell)
		return
	for i: int in collision.blockers.size():
		var blocker: AABB = collision.blockers[i]
		if blocker.size.x <= 0.0 or blocker.size.y <= 0.0 or blocker.size.z <= 0.0:
			failures.append("collision: blocker %d is degenerate %s" % [i, blocker])
		if not shell.intersects(blocker):
			failures.append("collision: blocker %d lies outside the shell %s" % [i, blocker])

# ---- zones ----

## Overlap is legal and useful, but only when the winner is decided. Equal
## priorities leave "which room am I in" resolved by a tie-break nobody chose.
static func _check_zone_priorities(zones: Array[ZoneDef], failures: PackedStringArray) -> void:
	for i: int in zones.size():
		for j: int in range(i + 1, zones.size()):
			var a: ZoneDef = zones[i]
			var b: ZoneDef = zones[j]
			if not a.bounds.intersects(b.bounds):
				continue
			if a.priority == b.priority:
				failures.append(
					"zones: '%s' and '%s' overlap at equal priority %d - which room wins is arbitrary"
					% [a.id, b.id, a.priority]
				)

# ---- placement ----

## Every point the match puts a body on must be somewhere a body can be.
static func _check_reference_points(
	zones: Array[ZoneDef],
	team_defs: Array[TeamDef],
	collision: WorldCollisionDef,
	radius: float,
	failures: PackedStringArray
) -> void:
	for team: TeamDef in team_defs:
		for slot: int in team.spawn_points.size():
			_require_standable(collision, team.spawn_points[slot], radius,
				"spawn %s[%d]" % [team.id, slot], failures)

	# A cash room or holding pen whose centre is inside a wall means a round
	# that cannot be won or a prisoner who cannot be reached.
	for zone: ZoneDef in zones:
		if zone.role == ZoneDef.Role.CASH_ROOM or zone.role == ZoneDef.Role.JAIL:
			_require_standable(collision, zone.bounds.get_center(), radius,
				"%s centre '%s'" % [ZoneDef.Role.keys()[zone.role], zone.id], failures)

static func _require_standable(
	collision: WorldCollisionDef,
	point: Vector3,
	radius: float,
	label: String,
	failures: PackedStringArray
) -> void:
	if not collision.contains(point, radius):
		failures.append("placement: %s at %s is outside the shell" % [label, point])
		return
	if collision.blocks_segment(point, point, radius):
		failures.append("placement: %s at %s is inside a blocker" % [label, point])

# ---- reachability ----

## Confirm every spawn and every zone stands in ONE walkable component.
##
## This is the check that catches the failures nobody sees coming: a room walled
## off by an edit three rooms away, a vault reachable only through a gap
## narrower than a player, a basement with no way down.
##
## It walks WalkableSurface rather than a volume of its own, because the bots
## navigate that same surface. A gate with its own private idea of traversal
## would certify routes the bots cannot use, and reject levels they could cross
## perfectly well.
static func _check_reachability(
	zones: Array[ZoneDef],
	team_defs: Array[TeamDef],
	collision: WorldCollisionDef,
	radius: float,
	step_up: float,
	max_drop: float,
	failures: PackedStringArray,
	prebuilt: WalkableSurface = null
) -> void:
	if collision.bounds.size == Vector3.ZERO:
		return

	var surface: WalkableSurface = prebuilt
	if surface == null:
		surface = WalkableSurface.build(collision, radius, step_up, max_drop)
	if surface.is_empty():
		failures.append("reachability: no part of this level can be stood on")
		return

	var seeds: Array[Vector3] = _seed_points(zones, team_defs)
	if seeds.is_empty():
		failures.append("reachability: no spawn points authored - nothing to flood from")
		return

	# A seed is matched to the stance it would FALL onto, not the one nearest it
	# in space. Spawns sit a little above the floor, and the fallback seeds are
	# room centres floating halfway up the wall; both are directly above good
	# ground and nowhere near it by straight-line distance.
	var limit: float = surface.cell_size * 1.5
	var rooted: int = -1
	var seed_nodes: Array[int] = []
	for seed_point: Vector3 in seeds:
		var node: int = surface.stance_under(seed_point, limit)
		seed_nodes.append(node)
		if node < 0:
			failures.append("reachability: nothing standable near spawn at %s" % seed_point)
			continue
		if rooted < 0:
			rooted = node
	if rooted < 0:
		return

	# Flood from ONE seed, not all of them at once.
	#
	# Seeding every spawn together only proves each zone is reachable from SOME
	# spawn, which is a much weaker claim and passes a map sealed down the
	# middle - each team floods its own half and every room is covered. §7 asks
	# for reachable from EVERY spawn, and since every edge is symmetric that is
	# exactly "one connected component holds all of them".
	var reached: Dictionary[int, bool] = surface.component_from(rooted)

	for i: int in seeds.size():
		if seed_nodes[i] < 0:
			continue # already reported above
		if not reached.has(seed_nodes[i]):
			failures.append(
				"reachability: spawn at %s cannot be reached on foot from the rest of the map" % seeds[i]
			)

	for zone: ZoneDef in zones:
		var found: bool = false
		for node: int in reached:
			if zone.contains_point(surface.nodes[node]):
				found = true
				break
		if not found:
			failures.append("reachability: zone '%s' cannot be reached on foot from every spawn" % zone.id)

## Where the fill starts: authored spawns, falling back to the centre of each
## team's home so a fixture without a roster still validates.
static func _seed_points(zones: Array[ZoneDef], team_defs: Array[TeamDef]) -> Array[Vector3]:
	var seeds: Array[Vector3] = []
	for team: TeamDef in team_defs:
		if not team.spawn_points.is_empty():
			seeds.append_array(team.spawn_points)
		elif team.home_zone != &"":
			for zone: ZoneDef in zones:
				if zone.id == team.home_zone:
					seeds.append(zone.bounds.get_center())
					break
	if seeds.is_empty():
		for zone: ZoneDef in zones:
			seeds.append(zone.bounds.get_center())
	return seeds

# ---- getting back out ----

## Every room you can walk into, you must be able to walk out of.
##
## Reachability alone stopped being enough the moment edges became directed. A
## drop is one-way: you leave a balcony and you cannot climb back onto it, so a
## room whose only exit is the way you fell in is a room a player is now stuck
## in for the rest of the round - and the forward flood says it is perfectly
## reachable, because it is.
##
## Until edges became directed this could not fail, which is the right order to
## have built it in: the check was there before the thing that could break it.
static func _check_escapability(
	zones: Array[ZoneDef],
	team_defs: Array[TeamDef],
	surface: WalkableSurface,
	failures: PackedStringArray
) -> void:
	if surface.is_empty():
		return
	var home: int = _first_seed_node(zones, team_defs, surface)
	if home < 0:
		return

	# Everywhere that can get BACK to a spawn.
	var can_return: Dictionary[int, bool] = surface.component_into(home)
	for zone: ZoneDef in zones:
		if zone.role == ZoneDef.Role.NEUTRAL:
			continue
		var stranded: bool = true
		for node: int in surface.nodes.size():
			if zone.contains_point(surface.nodes[node]) and can_return.has(node):
				stranded = false
				break
		if stranded:
			failures.append(
				"escapability: '%s' can be entered but not left - every way out is one-way"
				% zone.id
			)

# ---- more than one way in ----

## A room that matters must survive losing any one of its neighbours.
##
## The design rule is that no important room has a single approach: one door is
## a room where a defender stands still and the round stops. A rule nobody
## checks rots the first time somebody moves a wall, so it is checked.
##
## Counted as a MIN CUT from outdoors, which is Menger's theorem read backwards:
## the fewest doorways that must be closed to seal a room off is the number of
## independent ways into it. Max-flow on a graph small enough that the cost does
## not register.
##
## The first version looked for articulation points, and that is a weaker
## question wearing the same clothes. "Is there one room whose removal cuts this
## off" passes a garage with a single door straight onto the garden, because
## there is no third room to remove - one approach, one defender, exactly the
## failure the rule exists to catch. Min cut subsumes it and has no such blind
## spot.
##
## Three things make the count mean what it should:
##
## APERTURES, not rooms and not cells. The unit of capacity is a doorway,
## because a doorway is what a defender holds. Cells are far too fine - a door
## is forty cells wide, so any cell-level cut passes everything. Room adjacency
## is too coarse the other way - two separate front doors into the same hall are
## two ways in, and counting rooms calls them one. An aperture is a connected
## stretch of the boundary between two regions, so two doors count two and one
## wide door counts one.
##
## OUTDOORS is the source, and a source is never cut. That is what stops the
## yard between two houses reporting as a chokepoint: it is a cut vertex by
## construction, so asking about it could only ever have been answered by
## inventing a second yard.
##
## UNZONED space is a region like any other. Door thresholds and side passages
## are usually nobody's room, and leaving them out would silently merge the
## rooms they separate.
static func _check_redundant_routes(
	zones: Array[ZoneDef],
	surface: WalkableSurface,
	required: int,
	wanted: int,
	is_fixture: bool,
	failures: PackedStringArray,
	advisories: Array[String]
) -> void:
	if surface.is_empty() or zones.size() < 2:
		return
	var owner: Array[int] = _zone_of_each_node(zones, surface)
	var region: Array[int] = _regions(zones, owner, surface)
	var count: int = zones.size()
	for r: int in region:
		count = maxi(count, r + 1)

	# The source, sitting outside the graph and feeding every neutral region.
	var outdoors: int = count
	var capacity: Array[PackedInt32Array] = _aperture_capacities(surface, region, count + 1)
	var found_outside: bool = false
	for i: int in zones.size():
		if zones[i].role == ZoneDef.Role.NEUTRAL:
			capacity[outdoors][i] = UNLIMITED
			found_outside = true
	if not found_outside:
		# Fails closed. A rig with no outdoors is fine and says so on itself; a
		# level with no outdoors is a level this row cannot check, and silently
		# not checking it is the same as passing it.
		if is_fixture:
			advisories.append("routes: fixture content, so ways in were not counted")
		else:
			failures.append(
				"routes: cannot validate routes - no outdoor source, and this is not "
				+ "declared a fixture (WorldCollisionDef.is_fixture)"
			)
		return

	for i: int in zones.size():
		if zones[i].role == ZoneDef.Role.NEUTRAL:
			continue
		if not region.has(i):
			continue # no standing room in it at all; reachability says so already
		var ways: int = _max_flow(capacity, outdoors, i)
		if ways < required:
			failures.append(
				"routes: '%s' has %d way%s in - one doorway is one defender"
				% [zones[i].id, ways, "" if ways == 1 else "s"]
			)
		elif ways < wanted:
			advisories.append(
				"routes: '%s' has %d ways in, and %d is the target"
				% [zones[i].id, ways, wanted]
			)

## Which region each node belongs to: its zone, or the patch of unzoned space it
## shares with its neighbours. Zone indices come first so a zone's index is its
## region.
static func _regions(
	zones: Array[ZoneDef],
	owner: Array[int],
	surface: WalkableSurface
) -> Array[int]:
	var region: Array[int] = owner.duplicate()
	var next: int = zones.size()
	for start: int in region.size():
		if region[start] >= 0:
			continue
		region[start] = next
		var queue: Array[int] = [start]
		while not queue.is_empty():
			var current: int = queue.pop_back()
			# Both directions, because a region is a patch of space rather than
			# a set of places you can walk between: a ledge and the floor under
			# it are one unzoned area even though only one of them leads to the
			# other.
			for onward: PackedInt32Array in [
				surface.neighbours(current), surface.neighbours_into(current)
			]:
				for next_node: int in onward:
					if region[next_node] < 0:
						region[next_node] = next
						queue.append(next_node)
		next += 1
	return region

## How many separate doorways lead from each region into each other region.
static func _aperture_capacities(
	surface: WalkableSurface,
	region: Array[int],
	size: int
) -> Array[PackedInt32Array]:
	# Every place you arrive at, grouped by the pair of regions crossed.
	var arrivals: Dictionary[Vector2i, Dictionary] = {}
	for from_node: int in region.size():
		for to_node: int in surface.neighbours(from_node):
			if region[from_node] == region[to_node]:
				continue
			var crossing: Vector2i = Vector2i(region[from_node], region[to_node])
			var landing: Dictionary = arrivals.get(crossing, {})
			landing[to_node] = true
			arrivals[crossing] = landing

	var capacity: Array[PackedInt32Array] = []
	for i: int in size:
		var row: PackedInt32Array = PackedInt32Array()
		row.resize(size)
		row.fill(0)
		capacity.append(row)
	for crossing: Vector2i in arrivals:
		capacity[crossing.x][crossing.y] = _apertures(surface, arrivals[crossing])
	return capacity

## One doorway, or several? Connected runs of the landing places, counted.
##
## Adjacency is restricted to the landing set itself rather than followed into
## the room beyond, or every doorway in a room would merge into one.
static func _apertures(surface: WalkableSurface, landing: Dictionary) -> int:
	var seen: Dictionary[int, bool] = {}
	var found: int = 0
	var starts: Array = landing.keys()
	starts.sort()
	for start: int in starts:
		if seen.has(start):
			continue
		found += 1
		seen[start] = true
		var queue: Array[int] = [start]
		while not queue.is_empty():
			var current: int = queue.pop_back()
			for onward: PackedInt32Array in [
				surface.neighbours(current), surface.neighbours_into(current)
			]:
				for next_node: int in onward:
					if landing.has(next_node) and not seen.has(next_node):
						seen[next_node] = true
						queue.append(next_node)
	return found

## Edmonds-Karp. Shortest augmenting path first, so it terminates in polynomial
## time without anybody having to think about it, and BFS in index order so the
## answer does not depend on dictionary iteration.
static func _max_flow(base: Array[PackedInt32Array], source: int, sink: int) -> int:
	var size: int = base.size()
	var residual: Array[PackedInt32Array] = []
	for row: PackedInt32Array in base:
		residual.append(row.duplicate())

	var flow: int = 0
	while true:
		var came_from: PackedInt32Array = PackedInt32Array()
		came_from.resize(size)
		came_from.fill(-1)
		came_from[source] = source
		var queue: Array[int] = [source]
		var head: int = 0
		while head < queue.size() and came_from[sink] < 0:
			var current: int = queue[head]
			head += 1
			for next_node: int in size:
				if came_from[next_node] < 0 and residual[current][next_node] > 0:
					came_from[next_node] = current
					queue.append(next_node)
		if came_from[sink] < 0:
			return flow

		var along: int = UNLIMITED
		var node: int = sink
		while node != source:
			along = mini(along, residual[came_from[node]][node])
			node = came_from[node]
		node = sink
		while node != source:
			residual[came_from[node]][node] -= along
			residual[node][came_from[node]] += along
			node = came_from[node]
		flow += along
	return flow

## Which zone each node belongs to, in resolution order. -1 for none.
static func _zone_of_each_node(zones: Array[ZoneDef], surface: WalkableSurface) -> Array[int]:
	var owner: Array[int] = []
	owner.resize(surface.nodes.size())
	owner.fill(-1)
	for node: int in surface.nodes.size():
		for i: int in zones.size():
			if zones[i].contains_point(surface.nodes[node]):
				owner[node] = i
				break
	return owner

## The stance a match would start from.
static func _first_seed_node(
	zones: Array[ZoneDef],
	team_defs: Array[TeamDef],
	surface: WalkableSurface
) -> int:
	for seed_point: Vector3 in _seed_points(zones, team_defs):
		var node: int = surface.stance_under(seed_point, surface.cell_size * 1.5)
		if node >= 0:
			return node
	return -1
