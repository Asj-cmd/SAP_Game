class_name WorldCollisionDef
extends Resource
## The solid geometry of a level. See WORLD_AUTHORING.md §2 and §3.
##
## This is the other half of the boundary that document calls its most
## important: a ZONE MEANS (ownership, role, safety) and may be generous and
## approximate; a BLOCKER BLOCKS and carries no rules whatsoever. Neither
## derives from the other, so a wall can move without changing what a room
## means and a room can change hands without moving a wall.
##
## A doorway is not a thing. It is an absence of blocker.
##
## Axis-aligned boxes only (§3). A suburban house is almost entirely right
## angles, and AABB tests stay inside the arithmetic ARCHITECTURE.md §6 asks
## movement to prefer. Oriented boxes for a diagonal stair wall are a
## deliberate future extension and must not be added speculatively.

## Walls, closed doors, and furniture that stops you.
@export var blockers: Array[AABB] = []
## The outer shell. Outside it is out of bounds, whatever the blockers say.
@export var bounds: AABB = AABB()

## A rig for exercising one rule, not a place anybody plays.
##
## Some gate rows only make sense for a whole level. "How many ways into this
## room" needs an outdoors to count from, and a two-room box has none - so the
## check has nothing to say and cannot fail. Which is the problem: a check that
## cannot fail is indistinguishable from one that passes, and a real level that
## quietly lost its neutral space would stop being checked without anybody
## noticing.
##
## So those rows fail closed, and content that is genuinely a rig says so here.
## Declared by hand and never by the baker, so a level cannot acquire the
## exemption by accident.
@export var is_fixture: bool = false

## Does a body of `radius` centred at `point` fit inside the shell?
##
## The shell is shrunk by the radius rather than the point being tested bare,
## so an actor's body cannot hang outside the world while its centre is
## technically within it.
func contains(point: Vector3, radius: float = 0.0) -> bool:
	if bounds.size == Vector3.ZERO:
		return true # unbounded: no shell authored
	return bounds.grow(-radius).has_point(point)

## How far apart, in world units (cm), a segment and a solid must be before
## blocks_segment skips the exact tests for that pair.
##
## The broadphase hands over every blocker in every grid cell the segment's box
## touches, and a bot's steering look-ahead is long enough to touch many - so
## most candidates are nowhere near the line, and each one paid for two looped
## exact tests to say so. Measured in a 3v3 bot match, 178 us a reachability check.
##
## NOT zero, deliberately. At exactly touching, the slab test's float arithmetic
## (float32 vectors, a reciprocal) can land a hair either side of t = 1, and a
## reject that disagreed with it there would change what blocks. One centimetre
## is many orders of magnitude above that error and still rejects nearly
## everything, so the answer is identical and only the cost moves.
const _REJECT_MARGIN: float = 1.0

## Does travelling from `from` to `to` cross anything solid?
##
## Tests the SEGMENT, never just the destination (§4). At 30 ticks per second
## a sprinting actor covers real ground in one step - more when sliding - and
## an endpoint-only test lets it pass clean through a thin wall with neither
## end inside. Segment-versus-AABB is cheap and exact, so tunnelling stops
## being a tuning problem and stops being a class of bug.
func blocks_segment(from: Vector3, to: Vector3, radius: float = 0.0) -> bool:
	var reach_lo: Vector3 = from.min(to) - Vector3.ONE * _REJECT_MARGIN
	var reach_hi: Vector3 = from.max(to) + Vector3.ONE * _REJECT_MARGIN
	for index: int in _candidates(from, to, radius):
		var blocker: AABB = blockers[index]
		# Growing the blocker by the body radius is the standard Minkowski
		# trick: it reduces a fat body against thin geometry to a point
		# against fat geometry. Slightly conservative at corners, which is the
		# forgiving direction - an actor stops a hair early rather than
		# clipping a wall it should not have reached through.
		var solid: AABB = blocker.grow(radius)

		# Clearly apart: the box around the whole segment misses the solid by
		# more than the margin on some axis. Then neither end is inside it and
		# the slab test's interval lies wholly outside [0, 1], so both tests
		# below would say no - this only skips paying for them. See _REJECT_MARGIN.
		var solid_end: Vector3 = solid.end
		if reach_hi.x < solid.position.x or reach_lo.x > solid_end.x 			or reach_hi.y < solid.position.y or reach_lo.y > solid_end.y 			or reach_hi.z < solid.position.z or reach_lo.z > solid_end.z:
			continue

		# ALREADY OVERLAPPING. Blocking every direction here would weld an
		# actor inside geometry with no way out, because the escape direction
		# is blocked along with the rest. Hard to reach by walking; guaranteed
		# once knockback and ragdolls can shove a body into a wall.
		#
		# So an overlapping actor may move, provided the move gets it OUT.
		# Depth strictly decreasing is the general form of "depenetrate along
		# the shallowest axis": leaving entirely scores zero, and the shallow
		# axis is the one that reaches zero first.
		var depth: float = penetration_depth(from, solid)
		if depth > 0.0:
			if penetration_depth(to, solid) < depth:
				continue # escaping, or at least surfacing - allow it
			return true # deeper, or sliding along at the same depth
		if segment_hits_box(from, to, solid):
			return true
	return false

## How far inside `box` a point is: 0 when outside OR resting exactly on a
## face, positive only when strictly within.
##
## The distinction matters at the boundary. An actor flush against a wall is
## touching it, not embedded in it, and must keep every freedom a free actor
## has - otherwise standing against a wall would trigger the escape path and,
## worse, sliding along that wall would read as a collision.
##
## The value is the distance to the nearest face, which is exactly the
## shallowest-axis penetration.
static func penetration_depth(point: Vector3, box: AABB) -> float:
	var depth: float = INF
	for axis: int in 3:
		var lo: float = box.position[axis]
		var hi: float = box.position[axis] + box.size[axis]
		var inside_lo: float = point[axis] - lo
		var inside_hi: float = hi - point[axis]
		if inside_lo <= 0.0 or inside_hi <= 0.0:
			return 0.0
		depth = minf(depth, minf(inside_lo, inside_hi))
	return depth

## Slab test: does the segment [from, to] overlap `box`?
##
## Parameterised on t in [0,1] along the segment, intersecting the per-axis
## entry/exit intervals. An axis with no motion is handled separately because
## it has no finite t range - the segment either lies within that axis's slab
## for its whole length or misses the box entirely.
##
## The per-axis step is taken in double precision from the two endpoints, not
## from a float32 `to - from`, and the entry is a quotient, not a product with
## a reciprocal. A segment that ENDS exactly on a face - a route waypoint on a
## stance flush against a doorway jamb, which is common - then enters at
## exactly t = 1 and counts as the contact it is. Before, it entered a hair
## before or after 1 depending on where in the world it was, so the same
## doorway was see-through in one house and not in its half-turned twin
## (P0-5b, tools/twin_probe.gd).
static func segment_hits_box(from: Vector3, to: Vector3, box: AABB) -> bool:
	var t_min: float = 0.0
	var t_max: float = 1.0

	for axis: int in 3:
		var lo: float = box.position[axis]
		var hi: float = box.position[axis] + box.size[axis]
		var origin: float = from[axis]
		var step: float = to[axis] - origin

		if is_zero_approx(step):
			# Stationary on this axis: no crossing to solve for, so this axis
			# either contains the whole segment or rules the box out.
			#
			# STRICT on purpose. An actor flush against a face has origin
			# exactly at lo or hi; treating that as "within the slab" would
			# make sliding ALONG the face register as a hit and weld the actor
			# to the wall it is merely leaning on.
			if origin <= lo or origin >= hi:
				return false
			continue

		# Divided, not multiplied by a reciprocal: a rounded 1/step times the
		# same difference is not exactly 1, a quotient of equals is.
		var enter: float = (lo - origin) / step
		var exit: float = (hi - origin) / step
		if enter > exit:
			var swap: float = enter
			enter = exit
			exit = swap

		t_min = maxf(t_min, enter)
		t_max = minf(t_max, exit)
		if t_min > t_max:
			return false

	# The overlap must have positive length AND lie ahead of the start.
	#
	# t_min < t_max rejects a zero-length graze along a corner or a face;
	# t_max > 0 rejects an actor resting against a face and moving away, whose
	# interval closes at t = 0. Both are contact rather than penetration, and
	# treating contact as collision is what strands actors against walls.
	return t_min < t_max and t_max > 0.0


# ---- broadphase ----
#
# Testing the whole list was costing 2 us a blocker, and the house has three
# hundred of them where the grey box had twenty-five. That is roughly 600 us per
# swept test, and a tick spends dozens of them - between the movement sweep, the
# axis slides, the step-up and the bots' line-of-sight lookahead. Measured, it
# was 55% of the 30 Hz budget for a ONE-ON-ONE match before a single frame was
# drawn, and it grew with the level rather than with what was happening in it.
#
# A uniform grid of blocker indices fixes the shape of that: a query walks only
# the cells its own segment passes through.
#
# The answer must not change, only the cost. blocks_segment is an OR over
# independent per-blocker decisions, so which order they are visited in cannot
# affect the result - but a broadphase that MISSES one is a wall an actor walks
# through, so cells are keyed off the ungrown blocker and the query box is grown
# instead. Conservative in the safe direction: extra candidates cost time, a
# missing candidate costs correctness.

## Cells across the longest axis of the shell. Coarse on purpose - the point is
## to stop testing the far side of the map, not to build a perfect index.
const GRID_DIVISIONS: float = 32.0

var _grid: Dictionary[Vector3i, PackedInt32Array] = {}
var _grid_cell: float = 0.0
## The blocker count the index was built for. Content is immutable once loaded,
## so this is a staleness guard rather than a change notification.
var _grid_built_for: int = -1
## The occupied part of the grid. A query is clamped to it, which is exact:
## a cell outside it holds no blocker by construction.
var _grid_low: Vector3i = Vector3i.ZERO
var _grid_high: Vector3i = Vector3i.ZERO

## Candidate lists for multi-cell query boxes, DEDUPLICATED, keyed by the box.
##
## Without this, a query spanning several cells collected every blocker once
## per cell it shares with the query - and floors and long walls share many.
## Measured in a 3v3 bot match: 36.7 candidates per swept test, of which 6.1
## were distinct, so six in seven exact tests were repeats of one already made.
## The look-ahead's long segments are the queries that span cells, and bots
## standing in the same rooms ask about the same few boxes over and over, so
## the list for a box is built once and reused.
##
## Same answer, by the argument at the top of this section: the result is an
## OR over the candidates, so neither their order nor a repeat can change it.
var _box_lists: Dictionary[int, PackedInt32Array] = {}
## Whether every box in the occupied grid fits _box_key. False only for a level
## absurdly far outside its own shell; then lists are built uncached.
var _box_keyable: bool = false
## A cap rather than an eviction policy: dropping the lot is always correct, and
## a match visits far fewer distinct boxes than this.
const _BOX_LIST_LIMIT: int = 65536
const _BOX_KEY_BITS: int = 10

## The blockers worth testing for a move from `from` to `to`.
func _candidates(from: Vector3, to: Vector3, radius: float) -> PackedInt32Array:
	_build_index()
	if _grid_cell <= 0.0:
		return _all_indices()

	var low: Vector3i = _grid_cell_of(from.min(to) - Vector3.ONE * radius).max(_grid_low)
	var high: Vector3i = _grid_cell_of(from.max(to) + Vector3.ONE * radius).min(_grid_high)
	if low.x > high.x or low.y > high.y or low.z > high.z:
		return PackedInt32Array()
	# One cell is the overwhelmingly common case - a tick of travel is tens of
	# units and a cell is hundreds - so it is worth not building a list at all.
	if low == high:
		return _grid.get(low, PackedInt32Array())

	if not _box_keyable:
		return _gather(low, high)
	var key: int = _box_key(low - _grid_low, high - _grid_low)
	if _box_lists.has(key):
		return _box_lists[key]
	var found: PackedInt32Array = _gather(low, high)
	if _box_lists.size() >= _BOX_LIST_LIMIT:
		_box_lists.clear()
	_box_lists[key] = found
	return found

## Every blocker in the cells from `low` to `high` inclusive, each once.
func _gather(low: Vector3i, high: Vector3i) -> PackedInt32Array:
	var found: PackedInt32Array = PackedInt32Array()
	for x: int in range(low.x, high.x + 1):
		for y: int in range(low.y, high.y + 1):
			for z: int in range(low.z, high.z + 1):
				var cell: Vector3i = Vector3i(x, y, z)
				if _grid.has(cell):
					found.append_array(_grid[cell])
	found.sort()
	var kept: int = 0
	for index: int in found.size():
		if kept == 0 or found[index] != found[kept - 1]:
			found[kept] = found[index]
			kept += 1
	found.resize(kept)
	return found

## One integer per query box, from its corners relative to the occupied grid.
static func _box_key(low: Vector3i, high: Vector3i) -> int:
	var key: int = low.x
	key = (key << _BOX_KEY_BITS) | low.y
	key = (key << _BOX_KEY_BITS) | low.z
	key = (key << _BOX_KEY_BITS) | high.x
	key = (key << _BOX_KEY_BITS) | high.y
	return (key << _BOX_KEY_BITS) | high.z

func _build_index() -> void:
	if _grid_built_for == blockers.size():
		return
	_grid_built_for = blockers.size()
	_grid.clear()
	_box_lists.clear()
	var span: float = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	if span <= 0.0 or blockers.is_empty():
		_grid_cell = 0.0
		return
	_grid_cell = maxf(span / GRID_DIVISIONS, 1.0)
	for index: int in blockers.size():
		var blocker: AABB = blockers[index]
		var low: Vector3i = _grid_cell_of(blocker.position)
		var high: Vector3i = _grid_cell_of(blocker.position + blocker.size)
		if index == 0:
			_grid_low = low
			_grid_high = high
		_grid_low = _grid_low.min(low)
		_grid_high = _grid_high.max(high)
		for x: int in range(low.x, high.x + 1):
			for y: int in range(low.y, high.y + 1):
				for z: int in range(low.z, high.z + 1):
					var cell: Vector3i = Vector3i(x, y, z)
					var held: PackedInt32Array = _grid.get(cell, PackedInt32Array())
					held.append(index)
					_grid[cell] = held
	var extent: Vector3i = _grid_high - _grid_low
	var key_limit: int = 1 << _BOX_KEY_BITS
	_box_keyable = extent.x < key_limit and extent.y < key_limit and extent.z < key_limit

func _grid_cell_of(point: Vector3) -> Vector3i:
	var local: Vector3 = point - bounds.position
	return Vector3i(
		int(floor(local.x / _grid_cell)),
		int(floor(local.y / _grid_cell)),
		int(floor(local.z / _grid_cell)))

## The unindexed fallback: a level with no shell to divide up.
func _all_indices() -> PackedInt32Array:
	var every: PackedInt32Array = PackedInt32Array()
	every.resize(blockers.size())
	for index: int in blockers.size():
		every[index] = index
	return every
