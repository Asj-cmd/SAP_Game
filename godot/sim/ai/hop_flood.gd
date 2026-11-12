class_name HopFlood
extends RefCounted
## A breadth-first hop count over the stance graph that can stop and resume.
##
## The whole flood visits every stance in the house - 16,000 of them - and costs
## a bot decision 12-20 ms in GDScript. With six or eight bots, two of those
## landing on one tick is the tick missing its 33 ms budget: in a 4v4 probe, 33
## of the 35 over-budget ticks had a flood in them. The loop below is already a
## cursor over flat arrays and there is no cheaper exact search left to write.
##
## So the flood is spread over ticks instead. Advancing it a fixed number of
## stances at a time gives the SAME table at the end - breadth-first order does
## not care when it is paused - and only changes when the table becomes
## available. Fixed by stance count, never by wall-clock, so every machine
## pauses at the same place and the bots stay deterministic.

var _out_at: PackedInt32Array = PackedInt32Array()
var _out_to: PackedInt32Array = PackedInt32Array()
var _hops: PackedInt32Array = PackedInt32Array()
var _queue: PackedInt32Array = PackedInt32Array()
var _head: int = 0
## Where the flood was started from, in world space, for the caller's staleness test.
var origin_point: Vector3 = Vector3.ZERO

## Begins a flood from `origin` over `surface`. An origin off the graph gives a
## table that is -1 everywhere, as hops_from always has.
static func start(surface: WalkableSurface, origin: int, at: Vector3) -> HopFlood:
	var flood: HopFlood = HopFlood.new()
	flood.origin_point = at
	flood._out_at = surface.out_at
	flood._out_to = surface.out_to
	flood._hops.resize(surface.size())
	flood._hops.fill(-1)
	if origin >= 0 and origin < surface.size():
		flood._hops[origin] = 0
		flood._queue.append(origin)
	return flood

func is_done() -> bool:
	return _head >= _queue.size()

## Settles up to `budget` more stances; a budget of zero or less runs to the end.
## Returns whether the flood is finished.
func advance(budget: int) -> bool:
	# Locals rather than members inside the loop: this is the hottest loop in
	# the bot layer, and a member access is a lookup every time.
	var hops: PackedInt32Array = _hops
	var queue: PackedInt32Array = _queue
	var out_at: PackedInt32Array = _out_at
	var out_to: PackedInt32Array = _out_to
	var head: int = _head
	var stop_at: int = head + budget if budget > 0 else 2147483647
	# Walked with a cursor rather than popped from the front. Array.pop_front is
	# O(n) - it shifts every remaining element - so a breadth-first walk that
	# dequeues that way is quadratic in the size of the graph.
	while head < queue.size() and head < stop_at:
		var current: int = queue[head]
		head += 1
		var reach: int = hops[current] + 1
		# Flat adjacency, for the reason NavGraph._trace gives.
		var slot: int = out_at[current]
		var stop: int = out_at[current + 1]
		while slot < stop:
			var next: int = out_to[slot]
			slot += 1
			if hops[next] >= 0:
				continue
			hops[next] = reach
			queue.append(next)
	_hops = hops
	_queue = queue
	_head = head
	return is_done()

## The finished table: hop counts to every stance, -1 where there is no walk.
## Only meaningful once is_done().
func hops() -> PackedInt32Array:
	return _hops
