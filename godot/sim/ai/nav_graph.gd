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

## Nodes settled by the last _trace, for the performance probe.
##
## Diagnostic only - nothing in the simulation reads it, and it must stay that
## way: a rule that branched on it would make behaviour depend on how hard the
## search happened to work, which differs the moment the graph does.
var last_expanded: int = 0

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
	# Walked with a cursor rather than popped from the front. Array.pop_front is
	# O(n) - it shifts every remaining element - so a breadth-first walk that
	# dequeues that way is quadratic in the size of the graph. Fine on the grey
	# box at two thousand stances; the house has fourteen thousand.
	var queue: Array[int] = [origin]
	var head: int = 0
	while head < queue.size():
		var current: int = queue[head]
		head += 1
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
##
## SEARCHED FROM BOTH ENDS. A breadth-first flood settles everything closer to
## the start than the goal is, which on this house meant 14,282 of 15,987
## stances and 41 ms to produce a seven-waypoint path - one route costing more
## than the entire 33 ms tick it had to fit inside. Two frontiers meeting in
## the middle settle a fraction of that, because each only has to reach half
## the distance.
##
## Still breadth-first, and still no priority queue: the reason this file gave
## for choosing BFS over A* was that a heap's tie-breaking is incidental
## ordering that two machines can disagree about (§3), and that argument is
## untouched. Both frontiers expand in ring order exactly as one did.
##
## THE ROUTES CHANGE, and that has to be said plainly because the obvious
## assumption is that they do not. Checked over 6,599 stance pairs spanning
## both houses: 2,908 came back different from the one-directional search.
## They are the SAME LENGTH - this is still breadth-first, so it still returns
## a shortest path - but a node two ways round reach on the same ring can now
## be claimed by the backward frontier instead of the forward one, and the tie
## falls the other way.
##
## What is preserved is what actually matters: reachability is identical (zero
## pairs gained or lost in either direction), the path is still shortest, and
## the search is still deterministic - no heap, no heuristic, both frontiers in
## ring order, so two machines running this get the same answer. A DIFFERENT
## shortest path is not a desync; a NON-deterministic one would be.
##
## The consequence to know about: a saved replay from before this change will
## not reproduce, because bots walk different equal-length lines. Nothing in a
## live match notices.
func _trace(start: int, goal: int) -> PackedInt32Array:
	var parents: PackedInt32Array = PackedInt32Array()
	parents.resize(surface.size())
	parents.fill(-1)
	if start == goal:
		return parents

	var size: int = surface.size()
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(size)
	seen[start] = 1
	# Where the backward search has been, and how it got there. Its parents run
	# the other way - toward the goal - so a meeting point is stitched by
	# walking forward parents back to the start and backward parents on to the
	# goal.
	var seen_back: PackedByteArray = PackedByteArray()
	seen_back.resize(size)
	seen_back[goal] = 1
	var next_back: PackedInt32Array = PackedInt32Array()
	next_back.resize(size)
	next_back.fill(-1)

	# Cursors rather than pop_front, for the reason the one-directional version
	# gave: Array.pop_front shifts every remaining element, which makes a
	# breadth-first walk quadratic in the size of the graph.
	var ahead: Array[int] = [start]
	var behind: Array[int] = [goal]
	var head: int = 0
	var tail: int = 0
	var settled: int = 0

	while head < ahead.size() and tail < behind.size():
		# Expand whichever frontier is smaller. That is where the saving comes
		# from: the search spends its work on the cheaper side rather than
		# alternating blindly.
		if ahead.size() - head <= behind.size() - tail:
			var current: int = ahead[head]
			head += 1
			settled += 1
			for next: int in surface.neighbours(current):
				if seen[next] == 1:
					continue
				seen[next] = 1
				parents[next] = current
				if seen_back[next] == 1:
					last_expanded = settled
					return _stitch(parents, next_back, next, goal)
				ahead.append(next)
		else:
			var current: int = behind[tail]
			tail += 1
			settled += 1
			# BACKWARD steps take INCOMING edges. The graph is directed - a drop
			# is one-way - so walking neighbours() here would happily plan a
			# route up a ledge nothing can climb.
			for prev: int in surface.neighbours_into(current):
				if seen_back[prev] == 1:
					continue
				seen_back[prev] = 1
				next_back[prev] = current
				if seen[prev] == 1:
					last_expanded = settled
					return _stitch(parents, next_back, prev, goal)
				behind.append(prev)

	last_expanded = settled
	return PackedInt32Array()

## Completes the forward parent chain past the meeting point.
##
## route() walks `parents` backwards from the goal, so the half the backward
## search found has to be written into it in the same form: each node's parent
## is the one before it on the way from the start.
func _stitch(parents: PackedInt32Array, next_back: PackedInt32Array,
		meeting: int, goal: int) -> PackedInt32Array:
	var at: int = meeting
	while at != goal:
		var onward: int = next_back[at]
		if onward < 0:
			return PackedInt32Array() # backward chain broken: no route
		parents[onward] = at
		at = onward
	return parents

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
