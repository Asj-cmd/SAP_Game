class_name NavGraph
extends RefCounted
## Routes across a WalkableSurface. See ARCHITECTURE.md §2.
##
## Deliberately thin. All the geometry lives in the surface below it; this adds
## only the two questions a bot actually asks - "how far is that" and "how do I
## get there" - and it asks them of the same graph the load gate walked. A bot
## therefore cannot path somewhere the validator has not certified, and the
## validator cannot certify a route the bot is unable to follow.
##
## Breadth-first rather than A*. Every edge in the surface joins adjacent
## columns, so the edges are near enough uniform in length that hop count IS the
## shortest path, and BFS gets there with no priority queue - which matters more
## than it sounds, because a heap's tie-breaking is exactly the kind of
## incidental ordering that makes two machines disagree (§3).

var surface: WalkableSurface = null

static func of(walkable: WalkableSurface) -> NavGraph:
	var graph: NavGraph = NavGraph.new()
	graph.surface = walkable
	return graph

func is_ready() -> bool:
	return surface != null and not surface.is_empty()

## The stance nearest a world point, or -1 if the surface has none near it.
func node_at(point: Vector3) -> int:
	if not is_ready():
		return -1
	return surface.nearest(point)

## Hop counts from `origin` to every node; -1 where there is no walk at all.
##
## One flood answers "how far to each of these" for every candidate a bot is
## weighing, which is why the director floods once per decision instead of
## pathing to each option in turn.
func hops_from(origin: int) -> PackedInt32Array:
	var hops: PackedInt32Array = PackedInt32Array()
	if not is_ready():
		return hops
	hops.resize(surface.size())
	hops.fill(-1)
	if origin < 0 or origin >= surface.size():
		return hops

	hops[origin] = 0
	var queue: Array[int] = [origin]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for next: int in surface.neighbours(current):
			if hops[next] >= 0:
				continue
			hops[next] = hops[current] + 1
			queue.append(next)
	return hops

## Approximate walking distance in world units, or -1 when unreachable.
##
## Hops scaled by the grid pitch. Approximate is the right precision here: it
## feeds a utility comparison between candidate tasks, and a bot that weighs two
## errands correctly does not need either distance to be exact.
func distance_by_hops(hops: PackedInt32Array, node: int) -> float:
	if node < 0 or node >= hops.size() or hops[node] < 0:
		return -1.0
	return float(hops[node]) * surface.cell_size

## Waypoints from one point to another, empty when there is no route.
##
## The endpoints are the caller's actual positions rather than the stance nodes
## nearest them, so a bot walks to the cash and not to the grid cell beside it.
func route(from_point: Vector3, to_point: Vector3) -> PackedVector3Array:
	var empty: PackedVector3Array = PackedVector3Array()
	if not is_ready():
		return empty
	var start: int = surface.nearest(from_point)
	var goal: int = surface.nearest(to_point)
	if start < 0 or goal < 0:
		return empty

	var parents: PackedInt32Array = _trace(start, goal)
	if parents.is_empty():
		return empty

	var reversed: Array[int] = []
	var current: int = goal
	while current != start:
		reversed.append(current)
		current = parents[current]
		if current < 0:
			return empty
	reversed.reverse()

	var points: PackedVector3Array = PackedVector3Array()
	for node: int in reversed:
		points.append(surface.nodes[node])
	# The true destination replaces the last grid node, so arrival means being
	# at the thing rather than near it.
	if not points.is_empty():
		points[points.size() - 1] = to_point
	else:
		points.append(to_point)
	return _smooth(from_point, points)

## Parent links from `start`, stopping once `goal` is settled. Empty when the
## goal is not reachable.
func _trace(start: int, goal: int) -> PackedInt32Array:
	var parents: PackedInt32Array = PackedInt32Array()
	parents.resize(surface.size())
	parents.fill(-1)
	if start == goal:
		return parents

	var seen: PackedByteArray = PackedByteArray()
	seen.resize(surface.size())
	seen[start] = 1
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for next: int in surface.neighbours(current):
			if seen[next] == 1:
				continue
			seen[next] = 1
			parents[next] = current
			if next == goal:
				return parents
			queue.append(next)
	return PackedInt32Array()

## Drops waypoints the bot can see past.
##
## A four-neighbour grid produces staircase routes, and an actor following one
## literally walks in steps. Pulling the string taut against the geometry gives
## back the diagonals - and does it better than diagonal edges would, because
## the shortcut is tested against the real walls rather than against the lattice.
func _smooth(from_point: Vector3, points: PackedVector3Array) -> PackedVector3Array:
	if points.size() <= 1:
		return points
	var pulled: PackedVector3Array = PackedVector3Array()
	var anchor: Vector3 = from_point
	for i: int in points.size() - 1:
		if not surface.is_clear_between(anchor, points[i + 1]):
			pulled.append(points[i])
			anchor = points[i]
	pulled.append(points[points.size() - 1])
	return pulled
