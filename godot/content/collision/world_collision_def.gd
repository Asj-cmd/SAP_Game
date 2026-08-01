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

## Does a body of `radius` centred at `point` fit inside the shell?
##
## The shell is shrunk by the radius rather than the point being tested bare,
## so an actor's body cannot hang outside the world while its centre is
## technically within it.
func contains(point: Vector3, radius: float = 0.0) -> bool:
	if bounds.size == Vector3.ZERO:
		return true # unbounded: no shell authored
	return bounds.grow(-radius).has_point(point)

## Does travelling from `from` to `to` cross anything solid?
##
## Tests the SEGMENT, never just the destination (§4). At 30 ticks per second
## a sprinting actor covers real ground in one step - more when sliding - and
## an endpoint-only test lets it pass clean through a thin wall with neither
## end inside. Segment-versus-AABB is cheap and exact, so tunnelling stops
## being a tuning problem and stops being a class of bug.
func blocks_segment(from: Vector3, to: Vector3, radius: float = 0.0) -> bool:
	for blocker: AABB in blockers:
		# Growing the blocker by the body radius is the standard Minkowski
		# trick: it reduces a fat body against thin geometry to a point
		# against fat geometry. Slightly conservative at corners, which is the
		# forgiving direction - an actor stops a hair early rather than
		# clipping a wall it should not have reached through.
		if segment_hits_box(from, to, blocker.grow(radius)):
			return true
	return false

## Slab test: does the segment [from, to] overlap `box`?
##
## Parameterised on t in [0,1] along the segment, intersecting the per-axis
## entry/exit intervals. An axis with no motion is handled separately because
## it has no finite t range - the segment either lies within that axis's slab
## for its whole length or misses the box entirely.
static func segment_hits_box(from: Vector3, to: Vector3, box: AABB) -> bool:
	var delta: Vector3 = to - from
	var t_min: float = 0.0
	var t_max: float = 1.0

	for axis: int in 3:
		var lo: float = box.position[axis]
		var hi: float = box.position[axis] + box.size[axis]
		var origin: float = from[axis]
		var step: float = delta[axis]

		if is_zero_approx(step):
			# Stationary on this axis: no crossing to solve for, so this axis
			# either contains the whole segment or rules the box out.
			if origin < lo or origin > hi:
				return false
			continue

		var inverse: float = 1.0 / step
		var enter: float = (lo - origin) * inverse
		var exit: float = (hi - origin) * inverse
		if enter > exit:
			var swap: float = enter
			enter = exit
			exit = swap

		t_min = maxf(t_min, enter)
		t_max = minf(t_max, exit)
		if t_min > t_max:
			return false

	# t_max must be strictly positive. An actor resting exactly against a face
	# has an overlap of zero length; treating that as a hit would weld it to
	# the wall, unable to move away along it.
	return t_max > 0.0
