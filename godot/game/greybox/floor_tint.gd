class_name FloorTint
extends RefCounted
## Where each team's floor tint goes: rectangles on the floor of every owned
## zone, so which house you are in reads without labels or art.
##
## Presentation only. It reads the level (zones, walkable surface) and returns
## boxes; nothing here is read by a rule.
##
## THREE RULES, each learned from a frame:
##
## 1. ONLY WHERE THERE IS FLOOR. A box across the whole room paints over the
##    stairwell, and climbing the stairs becomes climbing through a solid
##    coloured floor at chest height. So the tint is built from the stances the
##    walkable surface found: a hole has no stances and gets no tint.
##
## 2. ONE ZONE PER POINT, THE GAME'S ZONE. Zones overlap on purpose - the yard
##    wraps the house and the rooms win by priority. Testing each zone's box on
##    its own drew the yard's tint under every ground-floor room as well (two
##    coplanar slabs fighting for the same pixels) and left the exterior door
##    sills, which belong to the yard, bare grey. Each stance is now given to the zone
##    `ZoneDef.sorted_for_resolution` puts first, the same order the rules use.
##
## 3. STRAIGHT EDGES. Stances sit a body radius off every wall and are not on a
##    grid that matches the zone boxes, so cell-sized runs left a grey margin
##    along each wall and a comb of teeth where the two yards meet at the
##    midline (P0-7 frames). Each rectangle is clipped to its zone, and an edge
##    that stops within a body radius plus a cell of the zone's own edge is
##    carried out to it. A stairwell is never inside that reach of a zone edge
##    on its open sides, so the holes stay open.

## One rectangle of tint: the zone it belongs to, the height of the floor it
## lies on, and its footprint (x/z; y unused).
class Patch:
	var zone: ZoneDef
	var floor_y: float
	var footprint: Rect2

## Every patch for `level`, merged into as few rectangles as the floor allows.
static func patches(level: GreyBoxLevel) -> Array[Patch]:
	var result: Array[Patch] = []
	var surface: WalkableSurfaceDef = level.surface
	if surface == null or surface.nodes.is_empty() or surface.cell_size <= 0.0:
		return result
	var cell: float = surface.cell_size
	var radius: float = level.tuning.actor_radius
	var ordered: Array[ZoneDef] = ZoneDef.sorted_for_resolution(level.zones)

	# Pass 1: which zone each stance is in, and each zone's lowest stance -
	# its main floor, so a room with a step in it tints from the floor proper.
	var owner_of: PackedInt32Array = PackedInt32Array()
	owner_of.resize(surface.nodes.size())
	var lowest: PackedFloat32Array = PackedFloat32Array()
	lowest.resize(ordered.size())
	lowest.fill(INF)
	for i: int in surface.nodes.size():
		var stance: Vector3 = surface.nodes[i]
		owner_of[i] = -1
		for z: int in ordered.size():
			if ordered[z].contains_point(stance):
				owner_of[i] = z
				lowest[z] = minf(lowest[z], stance.y)
				break

	# Pass 2: the cells on that floor, per zone, as rows of columns.
	var rows_by_zone: Dictionary[int, Dictionary] = {}
	for i: int in surface.nodes.size():
		var z: int = owner_of[i]
		if z < 0 or ordered[z].owner_team == &"":
			continue
		var stance: Vector3 = surface.nodes[i]
		if absf(stance.y - lowest[z]) > cell * 0.5:
			continue
		if not rows_by_zone.has(z):
			rows_by_zone[z] = {}
		var rows: Dictionary = rows_by_zone[z]
		var row: int = int(floor(stance.z / cell))
		if not rows.has(row):
			rows[row] = {}
		rows[row][int(floor(stance.x / cell))] = true

	var ground: Rect2 = _ground_footprint(level.collision.blockers)
	var reach: float = radius + cell
	var zone_keys: Array = rows_by_zone.keys()
	zone_keys.sort()
	for z: int in zone_keys:
		var zone: ZoneDef = ordered[z]
		var bounds: Rect2 = Rect2(zone.bounds.position.x, zone.bounds.position.z,
			zone.bounds.size.x, zone.bounds.size.z).intersection(ground)
		for block: Rect2 in _rectangles(rows_by_zone[z], cell):
			var fitted: Rect2 = _fit(block, bounds, reach)
			if fitted.size.x <= 0.0 or fitted.size.y <= 0.0:
				continue
			var patch: Patch = Patch.new()
			patch.zone = zone
			patch.floor_y = lowest[z] - radius
			patch.footprint = fitted
			result.append(patch)
	return result

## Runs of adjacent cells along x, stacked into rectangles wherever consecutive
## rows have exactly the same run. Fewer, larger boxes; fewer seams.
static func _rectangles(rows: Dictionary, cell: float) -> Array[Rect2]:
	var done: Array[Rect2] = []
	# Open rectangles: (first column, last column) -> (first row, last row).
	var open: Dictionary[Vector2i, Vector2i] = {}
	var ordered_rows: Array = rows.keys()
	ordered_rows.sort()
	for row: int in ordered_rows:
		var still_open: Dictionary[Vector2i, Vector2i] = {}
		for run: Vector2i in _runs(rows[row]):
			if open.has(run) and open[run].y == row - 1:
				still_open[run] = Vector2i(open[run].x, row)
			else:
				still_open[run] = Vector2i(row, row)
		for run: Vector2i in open:
			if not still_open.has(run) or still_open[run].x != open[run].x:
				done.append(_cells_to_rect(run, open[run], cell))
		open = still_open
	for run: Vector2i in open:
		done.append(_cells_to_rect(run, open[run], cell))
	return done

## The runs of consecutive columns in one row, as (first, last).
static func _runs(columns_set: Dictionary) -> Array[Vector2i]:
	var runs: Array[Vector2i] = []
	var columns: Array = columns_set.keys()
	columns.sort()
	var start: int = columns[0]
	var previous: int = columns[0]
	for i: int in range(1, columns.size()):
		if columns[i] == previous + 1:
			previous = columns[i]
			continue
		runs.append(Vector2i(start, previous))
		start = columns[i]
		previous = columns[i]
	runs.append(Vector2i(start, previous))
	return runs

static func _cells_to_rect(run: Vector2i, span: Vector2i, cell: float) -> Rect2:
	return Rect2(float(run.x) * cell, float(span.x) * cell,
		float(run.y - run.x + 1) * cell, float(span.y - span.x + 1) * cell)

## `block` clipped to `bounds`, with any edge that stops short of the matching
## edge of `bounds` by no more than `reach` carried out to it.
static func _fit(block: Rect2, bounds: Rect2, reach: float) -> Rect2:
	var left: float = maxf(block.position.x, bounds.position.x)
	var right: float = minf(block.end.x, bounds.end.x)
	var near: float = maxf(block.position.y, bounds.position.y)
	var far: float = minf(block.end.y, bounds.end.y)
	if left - bounds.position.x <= reach:
		left = bounds.position.x
	if bounds.end.x - right <= reach:
		right = bounds.end.x
	if near - bounds.position.y <= reach:
		near = bounds.position.y
	if bounds.end.y - far <= reach:
		far = bounds.end.y
	return Rect2(left, near, right - left, far - near)

## The footprint of the widest blocker - the lot's ground - so a yard whose box
## runs past the lot's edge is not tinted out over the grass beyond it.
static func _ground_footprint(blockers: Array[AABB]) -> Rect2:
	var widest: AABB = AABB()
	for blocker: AABB in blockers:
		if blocker.size.x * blocker.size.z > widest.size.x * widest.size.z:
			widest = blocker
	return Rect2(widest.position.x, widest.position.z, widest.size.x, widest.size.z)
