class_name WalkableSurface
extends RefCounted
## Every place an actor can stand, and every step it can take between them.
##
## Replaces the volumetric flood the validator started with. "Somewhere a body
## fits" and "somewhere a body can STAND" are different claims, and only the
## second means anything once gravity exists: the old fill certified the inside
## of a sealed roof void, and would have certified a basement nobody can walk
## down into. That was recorded as a deferred row in ContentValidator; this is
## the row being paid off.
##
## ONE implementation, two consumers. The validator asks whether the level hangs
## together; the bots ask how to cross it. Those must be the same traversal, or
## the gate certifies routes the bots cannot use and the bots find routes the
## gate never checked (ARCHITECTURE.md §7 - "the same traversal the bots will
## want later, so the work is not spent twice").
##
## It lives in content/ rather than sim/ because ContentValidator depends on it
## and the validator sits BELOW the simulation - a load gate the simulation
## calls cannot point upward at sim/ (§1). It reads geometry and answers
## geometric questions; it holds no rules.
##
## EDGES ARE DIRECTED. A drop is a route you can take one way: you leave a
## balcony and you cannot climb back onto it. That used to be refused outright -
## symmetric edges made connectivity a single flood - but a one-way descent is a
## verb this game wants, and the upstairs vault depends on it: climb up slow and
## careful, drop out of a window fast and committed.
##
## The cost is that "reachable" stopped being sufficient. A room you can fall
## into and not leave is perfectly reachable and completely broken, so the gate
## now asks reachable AND escapable (ContentValidator). That check is the more
## correct one; it was previously satisfied only by an accident of symmetry.
##
## A drop further than max_drop is refused in both directions rather than
## offered as a trip nobody survives.

## Stance nodes, in build order: ascending column, then ascending height.
## Deterministic, because the validator's messages and the bots' paths both
## depend on the ordering being the same on every machine.
var nodes: Array[Vector3] = []

var radius: float = 0.0
var step_up_height: float = 0.0
## The furthest a body may drop and keep going. Zero means no drops at all,
## which is what every fixture that predates them still wants.
var max_drop_height: float = 0.0
var cell_size: float = 0.0
var layer_height: float = 0.0

## Kept so a caller can ask follow-up questions about the geometry the surface
## was built from - path smoothing needs "is this straight line clear", which
## the node graph alone cannot answer.
var _collision: WorldCollisionDef = null
## Blockers pre-grown by the body radius, computed once.
##
## The Minkowski growth is the same for every query, and re-deriving it inside
## the innermost loop of the build was costing more than the collision tests it
## was feeding. Nothing else about the predicate changes: the tests below call
## the same statics WorldCollisionDef does, against the same boxes.
var _grown: Array[AABB] = []
var _origin: Vector3 = Vector3.ZERO
var _counts: Vector3i = Vector3i.ZERO
## Cells whose centre is strictly inside a blocker grown by the body radius.
var _solid: Dictionary[Vector3i, bool] = {}
## node index -> node indices one step away, in the direction of travel.
var _edges: Dictionary[int, PackedInt32Array] = {}
## The same edges reversed, so the gate can ask what can reach a place as well
## as what a place can reach.
var _incoming: Dictionary[int, PackedInt32Array] = {}
## (x,z) column -> the node indices standing in it, ascending by height.
var _columns: Dictionary[Vector2i, PackedInt32Array] = {}

## Horizontal resolution, as a multiple of the body radius.
##
## Two, so a cell is exactly one body across. This is not a comfort margin, it
## is the coarsest grid that still WORKS: a doorway is sampled only where a
## column centre lands inside it, so the grid must be no wider than the gaps it
## has to find. At six radii a 20-wide doorway sat entirely between two columns
## and the room behind it was declared unreachable - and the real level's much
## wider doors were passing by less margin than anyone would have guessed.
##
## Nine times the nodes of the coarse version, which is why the segment tests
## below are broadphased rather than run against every blocker.
const CELL_RADII: float = 2.0

## Minimum divisions along the shell's longest axis.
##
## The second of two independent resolution requirements, and the FINER of the
## two always wins - they are both lower bounds, and satisfying one does not
## excuse the other:
##
##   the BODY bound (CELL_RADII) keeps cells from outgrowing the thing walking
##   between them, which matters most on a large level;
##
##   this SHELL bound keeps a small level from being sampled at the same
##   coarseness as a large one. A gap only registers where a column centre lands
##   inside it, and a tight doorway - four units of clearance for a body eight
##   across, which is a legitimate door - is found at 64 divisions of a 200-unit
##   box and stepped clean over by a grid sized off the body alone.
##
## Neither bound guarantees finding an arbitrarily tight gap; nothing sampled
## can. Both together are what the fixtures and the real level need, and missing
## a gap errs toward reporting unreachable, which is the safe direction.
const SHELL_DIVISIONS: float = 64.0

## Neighbours considered for an edge. Four, not eight: a diagonal edge doubles
## the cost of the most expensive stage of the build, and NavGraph recovers the
## diagonals afterwards by string-pulling the path, which produces straighter
## routes than a diagonal lattice would anyway.
const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

## Builds the surface for a body of `radius` that can step up `step_up_height`.
##
## `cell_override` exists for fixtures: a two-metre test box needs a finer grid
## than a house, and hard-coding one resolution would make small fixtures
## unrepresentable rather than merely coarse.
static func build(
	collision: WorldCollisionDef,
	body_radius: float,
	step_up: float,
	max_drop: float = 0.0,
	cell_override: float = 0.0
) -> WalkableSurface:
	var surface: WalkableSurface = WalkableSurface.new()
	if collision == null or collision.bounds.size == Vector3.ZERO:
		return surface

	var shell_span: float = collision.bounds.size[collision.bounds.get_longest_axis_index()]
	surface.radius = maxf(body_radius, 0.0)
	surface.step_up_height = maxf(step_up, 0.0)
	surface.max_drop_height = maxf(max_drop, 0.0)
	surface.cell_size = cell_override
	if surface.cell_size <= 0.0:
		var by_shell: float = shell_span / SHELL_DIVISIONS
		var by_body: float = surface.radius * CELL_RADII
		# The finer of the two, and the shell bound alone when there is no body
		# to size against - a zero-radius fixture still needs a sane grid.
		surface.cell_size = minf(by_body, by_shell) if by_body > 0.0 else by_shell
		surface.cell_size = maxf(surface.cell_size, 0.001)
	# Layers are a step-up apart, so any height difference the actor can climb
	# is at most one layer and no legal step is invisible to the grid.
	surface.layer_height = maxf(surface.step_up_height, maxf(surface.radius, 1.0))

	var shell: AABB = collision.bounds
	surface._collision = collision
	surface._origin = shell.position
	surface._counts = Vector3i(
		maxi(1, int(ceil(shell.size.x / surface.cell_size))),
		maxi(1, int(ceil(shell.size.y / surface.layer_height))),
		maxi(1, int(ceil(shell.size.z / surface.cell_size)))
	)

	for blocker: AABB in collision.blockers:
		surface._grown.append(blocker.grow(surface.radius))

	surface._mark_solid()
	surface._find_stances()
	surface._link_stances()
	return surface

## Restores a surface that was computed by the baker. See WalkableSurfaceDef.
##
## Everything not stored is either build scaffolding (the solid mask, the cell
## counts, the columns) or cheap to re-derive: the grown blockers are one grow()
## per blocker and are needed for path smoothing, which asks about geometry the
## node graph cannot answer.
##
## The caller is responsible for having checked def.matches() first. Loading a
## stale surface is worse than building one, because it looks like it worked.
static func from_def(def: WalkableSurfaceDef, collision: WorldCollisionDef) -> WalkableSurface:
	var surface: WalkableSurface = WalkableSurface.new()
	surface._collision = collision
	surface.radius = def.radius
	surface.step_up_height = def.step_up_height
	surface.max_drop_height = def.max_drop_height
	surface.cell_size = def.cell_size
	surface.layer_height = def.layer_height

	for point: Vector3 in def.nodes:
		surface.nodes.append(point)
	for blocker: AABB in collision.blockers:
		surface._grown.append(blocker.grow(surface.radius))

	# Only nodes that actually have neighbours get an entry, matching what the
	# builder produces - neighbours() answers empty for the rest either way.
	for index: int in surface.nodes.size():
		if index + 1 >= def.edge_offsets.size():
			break
		var from: int = def.edge_offsets[index]
		var to: int = def.edge_offsets[index + 1]
		if to > from:
			var links: PackedInt32Array = def.edge_targets.slice(from, to)
			surface._edges[index] = links
			# Rebuilt, not stored. A baked surface with no reverse edges would
			# make the escapability check vacuous - and a check that cannot fail
			# is indistinguishable from one that passes.
			for other: int in links:
				var back: PackedInt32Array = surface._incoming.get(other, PackedInt32Array())
				back.append(index)
				surface._incoming[other] = back
	return surface

## Flattens this surface for storage. The inverse of from_def.
func to_def() -> WalkableSurfaceDef:
	var def: WalkableSurfaceDef = WalkableSurfaceDef.new()
	def.radius = radius
	def.step_up_height = step_up_height
	def.max_drop_height = max_drop_height
	def.cell_size = cell_size
	def.layer_height = layer_height
	def.fingerprint = WalkableSurfaceDef.fingerprint_of(
		_collision, radius, step_up_height, max_drop_height
	)

	def.nodes = PackedVector3Array(nodes)
	var offsets: PackedInt32Array = PackedInt32Array()
	var targets: PackedInt32Array = PackedInt32Array()
	for index: int in nodes.size():
		offsets.append(targets.size())
		targets.append_array(neighbours(index))
	offsets.append(targets.size())
	def.edge_offsets = offsets
	def.edge_targets = targets
	return def

func is_empty() -> bool:
	return nodes.is_empty()

func size() -> int:
	return nodes.size()

## Where you can go FROM here.
func neighbours(index: int) -> PackedInt32Array:
	return _edges.get(index, PackedInt32Array())

## Where you can arrive here FROM. The same set as neighbours() while every edge
## is symmetric; different the moment one-way drops exist.
func neighbours_into(index: int) -> PackedInt32Array:
	return _incoming.get(index, PackedInt32Array())

# ---- building ----

## Rasterises the blockers into the grid instead of testing every cell against
## every blocker.
##
## Same answer, transposed loop: a cell is solid exactly when its centre is
## strictly inside a grown blocker, and walking the blockers touches only the
## cells near them. Testing cell-by-cell is O(cells x blockers) and made the
## load gate slower than the level it was gating.
func _mark_solid() -> void:
	for solid: AABB in _grown:
		var low: Vector3i = _cell_of(solid.position)
		var high: Vector3i = _cell_of(solid.position + solid.size)
		for x: int in range(low.x, mini(high.x + 1, _counts.x)):
			for y: int in range(low.y, mini(high.y + 1, _counts.y)):
				for z: int in range(low.z, mini(high.z + 1, _counts.z)):
					var cell: Vector3i = Vector3i(x, y, z)
					if WorldCollisionDef.penetration_depth(_centre_of(cell), solid) > 0.0:
						_solid[cell] = true

## A stance is a free cell with something solid directly beneath it.
##
## "Solid beneath" includes the bottom of the grid, which is the shell floor -
## a level with no floor blocker still has ground to stand on.
func _find_stances() -> void:
	for x: int in _counts.x:
		for z: int in _counts.z:
			var column: PackedInt32Array = PackedInt32Array()
			for y: int in _counts.y:
				var cell: Vector3i = Vector3i(x, y, z)
				if not _is_free(cell):
					continue
				if _is_free(Vector3i(x, y - 1, z)):
					continue # open air: the actor would fall through it
				var centre: Vector3 = _centre_of(cell)
				var rest: Vector3 = _rest_position(centre)
				# The settled point can still be illegal where a low ceiling
				# leaves a gap a body does not fit in.
				if not _standable(rest):
					continue
				column.append(nodes.size())
				nodes.append(rest)
			if not column.is_empty():
				_columns[Vector2i(x, z)] = column

## Drops a cell centre onto whatever holds it up.
##
## Exact rather than swept: a blocker grown by the body radius has its top face
## exactly where a resting body's CENTRE sits, so the highest such face below
## the cell is the rest height with no bisection needed. Putting nodes where
## gravity would actually leave an actor is what keeps a bot's path and the
## movement system's idea of the floor from disagreeing.
func _rest_position(centre: Vector3) -> Vector3:
	var best: float = _collision.bounds.position.y + radius
	for solid: AABB in _grown:
		if centre.x <= solid.position.x or centre.x >= solid.position.x + solid.size.x:
			continue
		if centre.z <= solid.position.z or centre.z >= solid.position.z + solid.size.z:
			continue
		var top: float = solid.position.y + solid.size.y
		if top <= centre.y and top > best:
			best = top
	return Vector3(centre.x, best, centre.z)

func _link_stances() -> void:
	for column: Vector2i in _columns:
		for index: int in _columns[column]:
			var links: PackedInt32Array = PackedInt32Array()
			for offset: Vector2i in NEIGHBOURS:
				var beside: Vector2i = column + offset
				if not _columns.has(beside):
					continue
				for other: int in _columns[beside]:
					if _passable(index, other):
						links.append(other)
			if not links.is_empty():
				_edges[index] = links
				for other: int in links:
					var back: PackedInt32Array = _incoming.get(other, PackedInt32Array())
					back.append(index)
					_incoming[other] = back

## May a body go from node `index` to node `other`?
##
## Asked separately for each direction, which is where directedness comes from:
## a step UP of more than the allowance is refused while the matching step DOWN
## is offered as a drop, so the pair is a one-way route without anything having
## to special-case it.
func _passable(index: int, other: int) -> bool:
	var climb: float = nodes[other].y - nodes[index].y
	if climb > step_up_height:
		return false # too high to get up without a verb we do not have
	if climb >= -step_up_height:
		return _walkable_between(nodes[index], nodes[other])
	if -climb > max_drop_height:
		return false # far enough to hurt: refused, not offered
	return _droppable_between(nodes[index], nodes[other])

## Can a body step off here and land there?
##
## Out over the edge at the height it was standing, then down. Deliberately not
## the step-up test in reverse: leaving a ledge does not need the lip to be
## climbable, only clear.
func _droppable_between(from: Vector3, to: Vector3) -> bool:
	var across: Vector3 = Vector3(to.x, from.y, to.z)
	if _crosses(from, across):
		return false
	return not _crosses(across, to)

## Can an actor walk from `from` to `to` in one step?
##
## Mirrors MovementSystem: try it flat, and failing that lift by the step-up
## allowance, cross, and settle back down. The emulation matters - a doorway
## with a 30-unit sill is passable in the game, and a surface that called it a
## wall would report the room behind it unreachable and fail a level that plays
## perfectly well.
func _walkable_between(from: Vector3, to: Vector3) -> bool:
	if not _crosses(from, to):
		return true
	if step_up_height <= 0.0:
		return false
	var raised: Vector3 = from + Vector3(0.0, step_up_height, 0.0)
	if _crosses(from, raised):
		return false
	var across: Vector3 = Vector3(to.x, raised.y, to.z)
	if _crosses(raised, across):
		return false
	return not _crosses(across, to)

## Is the straight move from `from` to `to` obstructed, or does it leave the
## world? Both are reasons a step cannot be taken, and callers never care which.
func _crosses(from: Vector3, to: Vector3) -> bool:
	if not _collision.contains(to, radius):
		return true
	return _blocked(from, to)

## Exactly WorldCollisionDef.blocks_segment, because it IS it.
##
## It used to be a hand-copy of that loop with its own pre-grown list and its own
## cheap bounding-box reject in front. The copy was WRONG, and wrong in the
## permissive direction: `AABB.intersects` treats a touching edge as no overlap,
## so a sight line lying exactly along the top of the terrain - which is where
## every sight line lies, because that is where bodies stand - rejected blockers
## the real predicate would have tested. `is_clear_between` therefore reported
## clear through geometry, and the bots smoothed and steered through walls they
## could not walk through.
##
## That is why this reads as a one-line delegation and changed a whole match. It
## was found by running both against a full scan inside a live match and printing
## the first disagreement, after two rounds of offline equivalence testing on
## 200,000 random and then 106,000 lattice-aligned segments had found nothing:
## the queries that diverge are long sight lines from an ARBITRARY body position,
## and neither sample contained any.
##
## Keep it a delegation. A second implementation of the movement predicate is a
## second thing to be wrong, and the gate certifying routes on one while movement
## enforces the other is the failure this whole file exists to prevent.
func _blocked(from: Vector3, to: Vector3) -> bool:
	return _collision.blocks_segment(from, to, radius)

func _is_free(cell: Vector3i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.z < 0:
		return false
	if cell.x >= _counts.x or cell.y >= _counts.y or cell.z >= _counts.z:
		return false
	if _solid.has(cell):
		return false
	return _collision.contains(_centre_of(cell), radius)

func _standable(point: Vector3) -> bool:
	if not _collision.contains(point, radius):
		return false
	return not _blocked(point, point)

# ---- queries ----

## The stance nearest `point`, or -1 when nothing is within `limit`.
##
## Ties break on the lower node index rather than on iteration order, so two
## machines asking where a spawn stands get the same answer.
func nearest(point: Vector3, limit: float = INF) -> int:
	var best: int = -1
	var best_distance: float = limit * limit if limit < INF else INF
	for index: int in nodes.size():
		var distance: float = nodes[index].distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			best = index
	return best

## Is the straight line between two points clear of geometry?
##
## Weaker than an edge: it asks only whether the way is open, with no step-up
## allowance and no support underneath. That is exactly what smoothing a route
## needs - the waypoints being joined are already known to be standable, so the
## only remaining question is whether the shortcut between them hits a wall.
func is_clear_between(from: Vector3, to: Vector3) -> bool:
	if _collision == null:
		return false
	return not _crosses(from, to)

## The stance an actor placed at `point` would come to rest on, or -1.
##
## NOT the nearest node in three dimensions, which is a different and wrong
## question. A reference point authored mid-air - a spawn marker floating a
## little above the floor, or the CENTRE of a room, which is where the fallback
## seeds sit - is nowhere near any stance by straight-line distance, while being
## directly above a perfectly good one. Gravity is what resolves it, so this
## resolves it the same way: look down the column first.
##
## `reach` is horizontal only. Height is deliberately unbounded downward,
## because how far something falls before it lands is a property of the level
## and not something a caller should have to predict.
func stance_under(point: Vector3, reach: float) -> int:
	var below: int = -1
	var above: int = -1
	var limit: float = reach * reach
	for index: int in nodes.size():
		var node: Vector3 = nodes[index]
		var flat: float = Vector2(node.x - point.x, node.z - point.z).length_squared()
		if flat > limit:
			continue
		if node.y <= point.y + radius:
			# Falls onto it. The highest such stance is the one it lands on.
			if below < 0 or node.y > nodes[below].y:
				below = index
		elif above < 0 or node.y < nodes[above].y:
			above = index
	# Nothing underneath means the point is below the floor or buried in
	# geometry; the lowest stance above it is the honest answer.
	return below if below >= 0 else above

## Every stance reachable on foot from `start`, as a set of node indices.
##
## `blocked` is a set of nodes to pretend are not there, which is how the gate
## asks "is this room still reachable without going through that one".
func component_from(start: int, blocked: Dictionary[int, bool] = {}) -> Dictionary[int, bool]:
	return _flood(start, blocked, true)

## Every stance from which `start` can be REACHED - the flood run backwards.
##
## Not the same set as component_from once edges are directed. A balcony you can
## drop off is reachable from the landing and cannot get back to it, and the
## difference between those two floods is exactly the failure "you can get in
## but not out". While every edge is symmetric this returns the same answer as
## component_from, which is fine: it means the check exists before the thing
## that can break it.
func component_into(start: int, blocked: Dictionary[int, bool] = {}) -> Dictionary[int, bool]:
	return _flood(start, blocked, false)

func _flood(start: int, blocked: Dictionary[int, bool], forward: bool) -> Dictionary[int, bool]:
	var reached: Dictionary[int, bool] = {}
	if start < 0 or start >= nodes.size() or blocked.has(start):
		return reached
	reached[start] = true
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		var onward: PackedInt32Array = neighbours(current) if forward else neighbours_into(current)
		for next: int in onward:
			if reached.has(next) or blocked.has(next):
				continue
			reached[next] = true
			queue.append(next)
	return reached

# ---- grid arithmetic ----

func _cell_of(point: Vector3) -> Vector3i:
	var local: Vector3 = point - _origin
	return Vector3i(
		clampi(int(floor(local.x / cell_size)), 0, _counts.x - 1),
		clampi(int(floor(local.y / layer_height)), 0, _counts.y - 1),
		clampi(int(floor(local.z / cell_size)), 0, _counts.z - 1)
	)

func _centre_of(cell: Vector3i) -> Vector3:
	return _origin + Vector3(
		(float(cell.x) + 0.5) * cell_size,
		(float(cell.y) + 0.5) * layer_height,
		(float(cell.z) + 0.5) * cell_size
	)
