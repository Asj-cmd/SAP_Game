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
## Breadth-first, from both ends. Every edge in the surface joins adjacent
## columns, so the edges are uniform in length and hop count IS the shortest
## path, and BFS gets there with no priority queue - which matters more than it
## sounds, because a heap's tie-breaking is exactly the kind of incidental
## ordering that makes two machines disagree (§3).
##
## A GUIDED VERSION WAS BUILT AND MEASURED, and is not here. An admissible
## heuristic exists - horizontal cell distance, floored, verified over 380
## origin/target pairs with zero overestimates - and filing nodes into integer
## buckets by estimated cost does halve the nodes settled, 10,354 to 5,414. It
## was still SLOWER end to end: 35.6 ms against 25.6, because rescanning for the
## next non-empty bucket and swapping an array per lane cost more than the five
## thousand expansions it saved.
##
## The lesson is worth keeping: at this size the per-node BOOKKEEPING is the
## cost, not the node count, so anything clever has to be nearly free to be
## worth it. Two things that were nearly free are in: the flat adjacency the
## surface now exposes, and PackedInt32Array queues instead of Array[int].
## Together those took a route from 38 ms to 25.6 with identical results.

var surface: WalkableSurface = null

## Nodes settled by the last _trace, for the performance probe.
##
## Diagnostic only - nothing in the simulation reads it, and it must stay that
## way: a rule that branched on it would make behaviour depend on how hard the
## search happened to work, which differs the moment the graph does.
var last_expanded: int = 0

## stance_near's answers, per exact point. See stance_near.
var _near_memo: Dictionary[Vector3, int] = {}
const _NEAR_MEMO_LIMIT: int = 4096

## The surface's edges, each stance's set re-sorted into one fixed order of
## directions and into the same order turned half a circle. See _trace.
var _out_ahead: PackedInt32Array = PackedInt32Array()
var _out_turned: PackedInt32Array = PackedInt32Array()
var _in_ahead: PackedInt32Array = PackedInt32Array()
var _in_turned: PackedInt32Array = PackedInt32Array()

## Edge directions, as a rank to visit them in: +x, -x, +z, -z. Indexed by
## _direction_of. TURNED is the same sequence after a half turn, which swaps
## +x with -x and +z with -z.
const _RANK_AHEAD: PackedInt32Array = [0, 1, 2, 3]
const _RANK_TURNED: PackedInt32Array = [1, 0, 3, 2]

static func of(walkable: WalkableSurface) -> NavGraph:
	var graph: NavGraph = NavGraph.new()
	graph.surface = walkable
	if walkable != null and not walkable.is_empty():
		graph._out_ahead = graph._ordered(walkable.out_at, walkable.out_to, _RANK_AHEAD)
		graph._out_turned = graph._ordered(walkable.out_at, walkable.out_to, _RANK_TURNED)
		graph._in_ahead = graph._ordered(walkable.in_at, walkable.in_to, _RANK_AHEAD)
		graph._in_turned = graph._ordered(walkable.in_at, walkable.in_to, _RANK_TURNED)
	return graph

func is_ready() -> bool:
	return surface != null and not surface.is_empty()

## The stance nearest a world point, or -1 if the surface has none near it.
func node_at(point: Vector3) -> int:
	if not is_ready():
		return -1
	return surface.nearest(point)

## node_at, remembered per exact point - for the places bots ask about again
## and again.
##
## A decision weighs every errand, and most errand destinations are the same
## few points every time: zone centres for patrols and deposits, cash lying
## still. Those are the points FURTHEST from any stance - a room centre is
## mid-air above the floor - so nearest()'s ring search walks a long way for
## them: measured at 147 us a call in a 4v4 probe, 2.3 ms of every tick, most
## of what a decision cost once the flood was spread out.
##
## Exact, not approximate: the surface never changes after load, so the same
## point always has the same answer. Shared by every bot using this graph.
func stance_near(point: Vector3) -> int:
	if _near_memo.has(point):
		return _near_memo[point]
	var node: int = node_at(point)
	# A cap rather than an eviction policy: dropping the lot is always correct.
	# Moving targets (bodies) add points that are never asked about again.
	if _near_memo.size() >= _NEAR_MEMO_LIMIT:
		_near_memo.clear()
	_near_memo[point] = node
	return node

## Hop counts from `origin` to every node; -1 where there is no walk at all.
##
## One flood answers "how far to each of these" for every candidate a bot is
## weighing, which is why the director floods once per decision instead of
## pathing to each option in turn.
##
## STOPPING EARLY WAS TRIED AND IS NOT HERE. Passing the handful of nodes a bot
## actually asks about, and halting once the flood has reached them all, sounds
## obviously cheaper and measured 30% SLOWER: a bot's errands are scattered
## across both houses, so reaching all of them means visiting 15,839 of 15,987
## stances anyway, and the per-node bookkeeping is pure loss on top. The flood
## is cheap per node and there is no useful subset of it.
func hops_from(origin: int) -> PackedInt32Array:
	if not is_ready():
		return PackedInt32Array()
	var flood: HopFlood = start_hops(origin, Vector3.ZERO)
	flood.advance(0)
	return flood.hops()

## The same flood as hops_from, returned unstarted so the caller can spread it
## over several ticks. See HopFlood. Null when there is no graph.
func start_hops(origin: int, at: Vector3) -> HopFlood:
	if not is_ready():
		return null
	return HopFlood.start(surface, origin, at)

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
	var seen_back: PackedByteArray = PackedByteArray()
	seen_back.resize(size)
	seen_back[goal] = 1
	var next_back: PackedInt32Array = PackedInt32Array()
	next_back.resize(size)
	next_back.fill(-1)

	# Bound to locals once. A property read through `surface.` inside the loop
	# is a dispatch per neighbour, and this loop runs ten thousand times.
	#
	# WHICH WAY ROUND the neighbours are visited is the tie-break between equal
	# shortest paths, so it is taken from the direction of travel rather than
	# from the world's axes. Visiting in one fixed world order gave the turned
	# house the mirror-image tie-break on every trip - same lengths, other side
	# of every stairwell and doorway - and the team living in House A won 15 of
	# 16 bot matches at 2v2 (P0-5b). Now a trip and its half-turned twin visit
	# twin neighbours in twin order, so they find twin routes, exactly.
	var travel: Vector3 = surface.nodes[goal] - surface.nodes[start]
	var turned: bool = travel.x < 0.0 or (travel.x == 0.0 and travel.z < 0.0)
	var out_at: PackedInt32Array = surface.out_at
	var out_to: PackedInt32Array = _out_turned if turned else _out_ahead
	var in_at: PackedInt32Array = surface.in_at
	var in_to: PackedInt32Array = _in_turned if turned else _in_ahead

	# A SINGLE FLAT QUEUE PER SIDE, kept sorted by construction rather than by a
	# sort. Every node enters with an estimate no smaller than the one being
	# expanded - the heuristic is consistent on a uniform grid - so appending is
	# enough to keep the queue in non-decreasing order and a cursor sweeps it.
	#
	# An array-of-buckets was tried first and measured SLOWER than the plain
	# breadth-first search it replaced, despite settling half as many nodes:
	# rescanning for the next non-empty lane, and swapping a PackedInt32Array
	# per lane, cost more than the ~5,000 node expansions it saved. The lesson
	# is that at this scale the bookkeeping IS the cost, so the guided search
	# only pays if guiding is nearly free.
	var ahead: PackedInt32Array = PackedInt32Array()
	var behind: PackedInt32Array = PackedInt32Array()
	ahead.append(start)
	behind.append(goal)
	var head: int = 0
	var tail: int = 0
	var cost: PackedInt32Array = PackedInt32Array()
	cost.resize(size)
	var cost_back: PackedInt32Array = PackedInt32Array()
	cost_back.resize(size)
	var settled: int = 0

	while head < ahead.size() and tail < behind.size():
		# Expand the side with fewer nodes waiting, for the same reason the
		# unguided version did: spend the work on the cheaper frontier.
		if ahead.size() - head <= behind.size() - tail:
			var current: int = ahead[head]
			head += 1
			settled += 1
			var reach: int = cost[current] + 1
			var slot: int = out_at[current]
			var stop: int = out_at[current + 1]
			while slot < stop:
				var next: int = out_to[slot]
				slot += 1
				if seen[next] == 1:
					continue
				seen[next] = 1
				parents[next] = current
				cost[next] = reach
				if seen_back[next] == 1:
					last_expanded = settled
					return _stitch(parents, next_back, next, goal)
				ahead.append(next)
		else:
			var current: int = behind[tail]
			tail += 1
			settled += 1
			var reach: int = cost_back[current] + 1
			# BACKWARD steps take INCOMING edges. The graph is directed - a drop
			# is one-way - so walking the outgoing set here would plan a route
			# up a ledge nothing can climb.
			var slot: int = in_at[current]
			var stop: int = in_at[current + 1]
			while slot < stop:
				var prev: int = in_to[slot]
				slot += 1
				if seen_back[prev] == 1:
					continue
				seen_back[prev] = 1
				next_back[prev] = current
				cost_back[prev] = reach
				if seen[prev] == 1:
					last_expanded = settled
					return _stitch(parents, next_back, prev, goal)
				behind.append(prev)

	last_expanded = settled
	return PackedInt32Array()

## `targets` (compressed sparse row, offsets `at`) with each stance's edges
## stably re-sorted by the rank of their direction. The offsets do not change.
##
## Every edge joins adjacent columns, so all the edges in one direction go to
## ONE neighbouring column, and the stable sort keeps them in the order the
## surface built them: ascending height, which a half turn does not change.
## One native sort over packed keys, because a sort per stance in GDScript
## would cost more than the routes it serves.
func _ordered(at: PackedInt32Array, targets: PackedInt32Array, rank: PackedInt32Array) -> PackedInt32Array:
	var nodes: Array[Vector3] = surface.nodes
	var keys: PackedInt64Array = PackedInt64Array()
	keys.resize(targets.size())
	for node: int in at.size() - 1:
		var here: Vector3 = nodes[node]
		for slot: int in range(at[node], at[node + 1]):
			var direction: int = _direction_of(nodes[targets[slot]] - here)
			keys[slot] = (node << 24) | (rank[direction] << 20) | (slot - at[node])
	keys.sort()
	var ordered: PackedInt32Array = PackedInt32Array()
	ordered.resize(targets.size())
	for slot: int in keys.size():
		var key: int = keys[slot]
		ordered[slot] = targets[at[key >> 24] + (key & 0xFFFFF)]
	return ordered

## Which of the four horizontal directions an edge runs in: +x, -x, +z, -z.
static func _direction_of(step: Vector3) -> int:
	if absf(step.x) >= absf(step.z):
		return 0 if step.x > 0.0 else 1
	return 2 if step.z > 0.0 else 3

## Fewest edges any path between these two points could possibly use.
##
## HORIZONTAL ONLY, floored. See the class comment: a stair gains height while
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
