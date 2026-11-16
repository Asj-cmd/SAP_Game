class_name ExteriorBuilder
extends RefCounted
## What surrounds the two houses (PLAN P3-4): the lot's own ground and fences,
## and the suburb outside it.
##
## Presentation only. Nothing here has collision or is read by a rule. Inside
## the lot it draws only FLAT things (gravel, paths, soil) a body walks over;
## everything with height stands on or outside the level's bounds, where no
## body can go, so nothing drawn can be walked through or bumped into.
##
## THE PLACE. The lot is one block between two streets. House A fronts the
## south street, House B the north one (it is A turned half a circle), so the
## exterior is built once per side in a FRAME (along the lot edge, up, outward)
## and the opposite side is the same thing in the turned frame: point symmetry
## holds by construction, and neither team gets a landmark the other lacks.
##
## - Street sides (the lot edges the houses' fronts face): black railings on a
##   brick plinth between brick piers, a gate where a front door's path meets
##   it; then pavement, road, far pavement, low garden walls and a row of plain
##   houses across the street.
## - Garden sides: a close-board timber fence seen from its rail side; beyond
##   it the neighbouring plots (two more houses each), hedges and trees whose
##   crowns show over the fence.
## - Inside the lot: gravel on the neutral ground (the lot outside both yards),
##   a paved edge where gravel meets lawn, stepping stones down the line where
##   the two yards meet, a path from each front door to its gate, a paved apron
##   at every other ground-floor door, a soil border along the timber fences.
##
## Both fences are `fence_height` tall because the bounds stop a body there
## (WORLD_AUTHORING §12: what blocks must look tall). The camera's arm does NOT
## stop there, so the fence uses `fence_cutaway.gdshader`: a side is not drawn
## for a camera standing just outside it.
##
## Merged into three meshes (ground / solids / fence), a surface per material.

const CUTAWAY: Shader = preload("res://game/art/fence_cutaway.gdshader")

## Box faces, as a mask for `_box`.
const F_ALONG_LO: int = 1
const F_ALONG_HI: int = 2
const F_DOWN: int = 4
const F_UP: int = 8
const F_IN: int = 16
const F_OUT: int = 32
const F_SIDES: int = F_ALONG_LO | F_ALONG_HI | F_IN | F_OUT
const F_ALL: int = F_SIDES | F_UP | F_DOWN
const F_NO_BOTTOM: int = F_SIDES | F_UP

## Flat finishes inside the lot, above the lawn box. The yard patches lie at
## 0.6 (greybox_main PATCH_THICKNESS) and the indoor ground floor at 1.2.
const GRAVEL_LIFT: float = 0.6
const PAVING_LIFT: float = 0.9
## How far past the lot's ends the streets run: into the haze.
const STREET_REACH: float = 9000.0
const PAVEMENT_WIDTH: float = 220.0
const PAVEMENT_RISE: float = 12.0
const ROAD_WIDTH: float = 700.0
const ROAD_LIFT: float = 2.0
## A neighbour's house: the game house's footprint and height, as a plain box.
const HOUSE_SIZE: float = 2090.0
const HOUSE_WALL: float = 760.0
const HOUSE_SETBACK: float = 560.0
const ROOF_OVERHANG: float = 45.0
## A tree near the lot keeps its crown above any camera that backs out through
## the fence (arm 350, pivot 120: at most ~430 up, and lower the further out).
const NEAR_TRUNK: float = 400.0

## A lot edge: where it starts, which way it runs, and which way is out.
class Frame:
	var origin: Vector3
	var dir: Vector3
	var out: Vector3
	var length: float
	func at(along: float, up: float, outward: float) -> Vector3:
		return origin + dir * along + Vector3.UP * up + out * outward

var _theme: ArtTheme
var _level: GreyBoxLevel
var _lot: Rect2
var _ground: float
var _yards: Array[Rect2] = []
var _houses: Array[Rect2] = []
## group -> material key -> SurfaceTool
var _tools: Dictionary[StringName, Dictionary] = {}
var _materials: Dictionary[StringName, Material] = {}
## The outward direction written into UV2 for the fence group.
var _cut: Vector2 = Vector2.ZERO
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _noise: FastNoiseLite = FastNoiseLite.new()
var _sphere_points: PackedVector3Array = PackedVector3Array()
var _sphere_faces: PackedInt32Array = PackedInt32Array()
## Gates in the south and the north railings, as (centre along the side, width).
var _gates_south: Array[Vector2] = []
var _gates_north: Array[Vector2] = []

## The exterior for `level`; `ground_y` is the top of the lot's ground box.
static func build(level: GreyBoxLevel, theme: ArtTheme, ground_y: float) -> Array[Node3D]:
	var builder: ExteriorBuilder = ExteriorBuilder.new()
	return builder._build(level, theme, ground_y)

func _build(level: GreyBoxLevel, theme: ArtTheme, ground_y: float) -> Array[Node3D]:
	_level = level
	_theme = theme
	_ground = ground_y
	var bounds: AABB = level.collision.bounds
	_lot = Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 1.0
	_noise.seed = 4
	_find_yards_and_houses()

	# The four sides. South and west are built; north and east are their twins
	# in the frame turned half a circle about the middle of the lot.
	var south: Frame = _frame(Vector3(_lot.position.x, _ground, _lot.position.y),
		Vector3.RIGHT, Vector3.FORWARD, _lot.size.x)
	var north: Frame = _frame(Vector3(_lot.end.x, _ground, _lot.end.y),
		Vector3.LEFT, Vector3.BACK, _lot.size.x)
	var west: Frame = _frame(Vector3(_lot.position.x, _ground, _lot.end.y),
		Vector3.FORWARD, Vector3.LEFT, _lot.size.y)
	var east: Frame = _frame(Vector3(_lot.end.x, _ground, _lot.position.y),
		Vector3.BACK, Vector3.RIGHT, _lot.size.y)

	_lot_ground(south, north)
	var streets: Array[Frame] = [south, north]
	for i: int in streets.size():
		_rng.seed = 71
		_railings(streets[i], _gates_south if i == 0 else _gates_north)
		_street(streets[i])
	var gardens: Array[Frame] = [west, east]
	for garden: Frame in gardens:
		_rng.seed = 72
		_timber_fence(garden)
		_neighbours(garden)
	return _commit()

static func _frame(origin: Vector3, dir: Vector3, out: Vector3, length: float) -> Frame:
	var frame: Frame = Frame.new()
	frame.origin = origin
	frame.dir = dir
	frame.out = out
	frame.length = length
	return frame

func _find_yards_and_houses() -> void:
	var by_team: Dictionary[StringName, Rect2] = {}
	for zone: ZoneDef in _level.zones:
		var flat: Rect2 = Rect2(zone.bounds.position.x, zone.bounds.position.z,
			zone.bounds.size.x, zone.bounds.size.z)
		if zone.owner_team == &"":
			continue
		if zone.outdoor:
			_yards.append(flat.intersection(_lot))
		elif by_team.has(zone.owner_team):
			by_team[zone.owner_team] = by_team[zone.owner_team].merge(flat)
		else:
			by_team[zone.owner_team] = flat
	var teams: Array[StringName] = by_team.keys()
	teams.sort()
	for team: StringName in teams:
		# The rooms' union grown by a wall (build_house WALL 30).
		_houses.append(by_team[team].grow(30.0))

# ---- inside the lot: flat finishes only ----

func _lot_ground(south: Frame, north: Frame) -> void:
	# Gravel on the neutral ground: the lot less both yards.
	var open: Array[Rect2] = [_lot]
	for yard: Rect2 in _yards:
		var left: Array[Rect2] = []
		for piece: Rect2 in open:
			left.append_array(_minus(piece, yard))
		open = left
	for piece: Rect2 in open:
		_flat(&"gravel", piece, GRAVEL_LIFT)

	# Along every yard edge inside the lot: a paved edge against gravel,
	# stepping stones against the other yard.
	for yard: Rect2 in _yards:
		for edge: int in 4:
			_yard_edge(yard, edge)

	# Doors: a path from each street-facing door to a gate, an apron elsewhere.
	for house: Rect2 in _houses:
		var to_south: float = house.position.y - _lot.position.y
		var to_north: float = _lot.end.y - house.end.y
		var street_face: int = 0 if to_south <= to_north else 1
		for face: int in 4:
			for opening: Vector2 in _openings(house, face):
				var from: float = opening.x
				var to: float = opening.y
				if face == street_face:
					var z0: float = _lot.position.y if face == 0 else house.end.y
					var z1: float = house.position.y if face == 0 else _lot.end.y
					_flat(&"pavement", Rect2(from, z0, to - from, z1 - z0), PAVING_LIFT)
					var middle: float = (from + to) * 0.5
					var side: Frame = south if face == 0 else north
					var along: float = (Vector3(middle, _ground, 0.0) - side.origin).dot(side.dir)
					if face == 0:
						_gates_south.append(Vector2(along, to - from))
					else:
						_gates_north.append(Vector2(along, to - from))
				else:
					_flat(&"pavement", _apron(house, face, from - 30.0, to + 30.0, 150.0), PAVING_LIFT)

	# A soil border inside each yard along the lot's two garden sides.
	for yard: Rect2 in _yards:
		for x_edge: float in [_lot.position.x, _lot.end.x]:
			var inward: float = 1.0 if is_equal_approx(x_edge, _lot.position.x) else -1.0
			if not (is_equal_approx(yard.position.x, x_edge) or is_equal_approx(yard.end.x, x_edge)):
				continue
			var x0: float = minf(x_edge, x_edge + inward * 46.0)
			_flat(&"soil", Rect2(x0, yard.position.y, 46.0, yard.size.y), PAVING_LIFT)
			var z: float = yard.position.y + 40.0
			while z < yard.end.y - 30.0:
				var size: float = _rng.randf_range(11.0, 19.0)
				_blob(&"solid", &"crown", Vector3(x_edge + inward * _rng.randf_range(18.0, 28.0),
					_ground + size * 0.25, z), Vector3(size, size * 0.8, size), Vector3.ZERO, 1,
					_rng.randf_range(0.85, 1.05))
				z += _rng.randf_range(55.0, 95.0)

## `piece` less `hole`, as up to four rectangles.
static func _minus(piece: Rect2, hole: Rect2) -> Array[Rect2]:
	var cut: Rect2 = piece.intersection(hole)
	if cut.size.x <= 0.0 or cut.size.y <= 0.0:
		return [piece]
	var left: Array[Rect2] = []
	if cut.position.y > piece.position.y:
		left.append(Rect2(piece.position.x, piece.position.y, piece.size.x, cut.position.y - piece.position.y))
	if cut.end.y < piece.end.y:
		left.append(Rect2(piece.position.x, cut.end.y, piece.size.x, piece.end.y - cut.end.y))
	if cut.position.x > piece.position.x:
		left.append(Rect2(piece.position.x, cut.position.y, cut.position.x - piece.position.x, cut.size.y))
	if cut.end.x < piece.end.x:
		left.append(Rect2(cut.end.x, cut.position.y, piece.end.x - cut.end.x, cut.size.y))
	return left

## 0 = outside the lot or under a house, 1 = gravel, 2 = a yard.
func _ground_kind(point: Vector2) -> int:
	if not _lot.has_point(point):
		return 0
	for house: Rect2 in _houses:
		if house.has_point(point):
			return 0
	for yard: Rect2 in _yards:
		if yard.has_point(point):
			return 2
	return 1

## One edge of a yard (0 south, 1 north, 2 west, 3 east), walked in steps: runs
## that border gravel get a paved edge, runs that border the other yard get
## stepping stones.
func _yard_edge(yard: Rect2, edge: int) -> void:
	var step: float = 20.0
	var along_x: bool = edge < 2
	var fixed: float = [yard.position.y, yard.end.y, yard.position.x, yard.end.x][edge]
	var outward: float = -1.0 if edge == 0 or edge == 2 else 1.0
	var from: float = yard.position.x if along_x else yard.position.y
	var to: float = yard.end.x if along_x else yard.end.y
	var run_start: float = from
	var run_kind: int = -1
	var at: float = from
	while at <= to + step:
		var kind: int = -1
		if at < to:
			var probe: Vector2 = Vector2(at + step * 0.5, fixed + outward * 5.0) if along_x \
				else Vector2(fixed + outward * 5.0, at + step * 0.5)
			kind = _ground_kind(probe)
		if kind != run_kind:
			var run_end: float = minf(at, to)
			if run_kind == 1 and run_end > run_start:
				var strip: Rect2 = Rect2(run_start, fixed - 8.0, run_end - run_start, 16.0) if along_x \
					else Rect2(fixed - 8.0, run_start, 16.0, run_end - run_start)
				_flat(&"kerb", strip, PAVING_LIFT)
			elif run_kind == 2 and outward > 0.0 and run_end > run_start:
				# Each shared edge is found from both yards; only one lays it.
				var s: float = run_start + 50.0
				while s + 60.0 <= run_end:
					var stone: Rect2 = Rect2(s, fixed - 32.0, 62.0, 64.0) if along_x \
						else Rect2(fixed - 32.0, s, 64.0, 62.0)
					_flat(&"pavement", stone, PAVING_LIFT)
					s += 100.0
			run_start = at
			run_kind = kind
		at += step

## The ground-floor openings in one face of a house (0 south, 1 north, 2 west,
## 3 east), as (from, to) along the face: runs where the wall is air.
func _openings(house: Rect2, face: int) -> Array[Vector2]:
	var found: Array[Vector2] = []
	var along_x: bool = face < 2
	var fixed: float = [house.position.y + 15.0, house.end.y - 15.0,
		house.position.x + 15.0, house.end.x - 15.0][face]
	var from: float = house.position.x if along_x else house.position.y
	var to: float = house.end.x if along_x else house.end.y
	var start: float = NAN
	var at: float = from + 5.0
	while at <= to:
		var point: Vector3 = Vector3(at, _ground + 100.0, fixed) if along_x \
			else Vector3(fixed, _ground + 100.0, at)
		var solid: bool = at >= to - 5.0
		if not solid:
			for blocker: AABB in _level.collision.blockers:
				if blocker.has_point(point):
					solid = true
					break
		if not solid and is_nan(start):
			start = at
		elif solid and not is_nan(start):
			if at - start >= 100.0:
				found.append(Vector2(start - 5.0, at - 5.0))
			start = NAN
		at += 10.0
	return found

## A paved rectangle `depth` out from a house face, clipped to the lot.
func _apron(house: Rect2, face: int, from: float, to: float, depth: float) -> Rect2:
	var rect: Rect2
	match face:
		0: rect = Rect2(from, house.position.y - depth, to - from, depth)
		1: rect = Rect2(from, house.end.y, to - from, depth)
		2: rect = Rect2(house.position.x - depth, from, depth, to - from)
		_: rect = Rect2(house.end.x, from, depth, to - from)
	return rect.intersection(_lot)

## A flat rectangle on the lot's ground.
func _flat(key: StringName, rect: Rect2, lift: float) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var y: float = _ground + lift
	_quad(&"ground", key, [Vector3(rect.position.x, y, rect.position.y),
		Vector3(rect.end.x, y, rect.position.y), Vector3(rect.end.x, y, rect.end.y),
		Vector3(rect.position.x, y, rect.end.y)], Vector3.UP)

# ---- a street side: railings, then the street ----

func _railings(f: Frame, gates: Array[Vector2]) -> void:
	_cut = Vector2(f.out.x, f.out.z)
	var top: float = _theme.fence_height
	var pier: float = 34.0
	# What interrupts the plinth and the bars: gates and piers, as (from, to).
	var gaps: Array[Vector2] = []
	var piers: Array[float] = []
	for gate: Vector2 in gates:
		gaps.append(Vector2(gate.x - gate.y * 0.5, gate.x + gate.y * 0.5))
		piers.append(gate.x - gate.y * 0.5 - pier * 0.5)
		piers.append(gate.x + gate.y * 0.5 + pier * 0.5)
	var bays: int = int(round(f.length / 540.0))
	for i: int in bays + 1:
		var at: float = clampf(f.length * float(i) / float(bays), pier * 0.5, f.length - pier * 0.5)
		var clear: bool = true
		for gap: Vector2 in gaps:
			if at > gap.x - 200.0 and at < gap.y + 200.0:
				clear = false
		if clear:
			piers.append(at)
	for at: float in piers:
		_box(f, &"fence", &"fence_brick", at - pier * 0.5, at + pier * 0.5, 0.0, top + 15.0, 0.0, pier, F_SIDES)
		_box(f, &"fence", &"fence_cap", at - pier * 0.5 - 2.0, at + pier * 0.5 + 2.0, top + 15.0, top + 22.0,
			0.0, pier + 2.0, F_ALL)

	# Plinth, cap, rails and bars between the gates.
	var from: float = 0.0
	var spans: Array[Vector2] = []
	gaps.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	for gap: Vector2 in gaps:
		spans.append(Vector2(from, gap.x))
		from = gap.y
	spans.append(Vector2(from, f.length))
	for span: Vector2 in spans:
		_box(f, &"fence", &"fence_brick", span.x, span.y, 0.0, 45.0, 0.0, 22.0, F_SIDES)
		_box(f, &"fence", &"fence_cap", span.x, span.y, 45.0, 50.0, 0.0, 24.0, F_ALL)
		_box(f, &"fence", &"fence_steel", span.x, span.y, 54.0, 59.0, 8.0, 14.0, F_ALL)
		_box(f, &"fence", &"fence_steel", span.x, span.y, top - 12.0, top - 6.0, 8.0, 14.0, F_ALL)
		var at: float = span.x + 8.0
		while at < span.y - 4.0:
			var hidden: bool = false
			for p: float in piers:
				if absf(at - p) < pier * 0.5:
					hidden = true
			if not hidden:
				_box(f, &"fence", &"fence_steel", at - 1.9, at + 1.9, 50.0, top, 9.1, 12.9, F_SIDES | F_UP)
			at += 16.0

	# A gate: a heavier frame, closer bars, a latch plate. It does not open:
	# the bounds are the wall, and the gate is drawn shut.
	for gap: Vector2 in gaps:
		var g0: float = gap.x + 1.0
		var g1: float = gap.y - 1.0
		for rail: float in [14.0, 108.0, top - 6.0]:
			_box(f, &"fence", &"fence_steel", g0, g1, rail, rail + 9.0, 7.0, 15.0, F_ALL)
		for stile: float in [g0, g1 - 8.0, (g0 + g1) * 0.5 - 4.0]:
			_box(f, &"fence", &"fence_steel", stile, stile + 8.0, 14.0, top + 3.0, 7.0, 15.0, F_ALL)
		var bar: float = g0 + 20.0
		while bar < g1 - 12.0:
			if absf(bar - (g0 + g1) * 0.5) > 8.0:
				_box(f, &"fence", &"fence_steel", bar - 1.9, bar + 1.9, 23.0, top - 6.0, 9.1, 12.9, F_SIDES)
			bar += 12.0
		_box(f, &"fence", &"fence_steel", (g0 + g1) * 0.5 - 9.0, (g0 + g1) * 0.5 + 9.0, 96.0, 128.0,
			5.0, 17.0, F_ALL)

func _street(f: Frame) -> void:
	var a0: float = -STREET_REACH
	var a1: float = f.length + STREET_REACH
	var kerb: float = PAVEMENT_WIDTH
	var far_kerb: float = kerb + ROAD_WIDTH
	var far_edge: float = far_kerb + PAVEMENT_WIDTH
	# Near pavement, road, far pavement.
	_box(f, &"ground", &"pavement", a0, a1, 0.0, PAVEMENT_RISE, 0.0, kerb, F_UP)
	_box(f, &"ground", &"kerb", a0, a1, 0.0, PAVEMENT_RISE, kerb - 14.0, kerb, F_UP | F_OUT, PAVEMENT_RISE + 0.3)
	_surface(f, &"asphalt", a0, a1, kerb, far_kerb, ROAD_LIFT)
	_box(f, &"ground", &"pavement", a0, a1, 0.0, PAVEMENT_RISE, far_kerb, far_edge, F_UP)
	_box(f, &"ground", &"kerb", a0, a1, 0.0, PAVEMENT_RISE, far_kerb, far_kerb + 14.0, F_UP | F_IN, PAVEMENT_RISE + 0.3)
	var middle: float = (kerb + far_kerb) * 0.5
	var dash: float = a0
	while dash < a1:
		_surface(f, &"road_line", dash, dash + 300.0, middle - 6.0, middle + 6.0, ROAD_LIFT + 1.5)
		dash += 900.0

	# The neighbours' frontage on this side of the street: a hedge either side of the lot.
	_box(f, &"solid", &"hedge", -2.0 * f.length, -6.0, 0.0, 125.0, -62.0, -4.0, F_NO_BOTTOM)
	_box(f, &"solid", &"hedge", f.length + 6.0, 3.0 * f.length, 0.0, 125.0, -62.0, -4.0, F_NO_BOTTOM)

	# Across the street: a low garden wall, a row of houses, trees between and behind.
	var pitch: float = f.length * 0.5
	var front: float = far_edge + HOUSE_SETBACK
	var wall_from: float = a0
	for i: int in range(-4, 4):
		var centre: float = f.length * 0.5 + (float(i) + 0.5) * pitch
		var width: float = HOUSE_SIZE - 90.0 * float(posmod(i * 3, 4))
		var box: Rect2 = Rect2(centre - width * 0.5, front, width, HOUSE_SIZE - 150.0 * float(posmod(i, 3)))
		_house(f, box, 0, posmod(i, 3) == 1)
		# The path from its door to the pavement, and the wall's gap for it.
		_surface(f, &"pavement", centre - 75.0, centre + 75.0, far_edge, front, 1.0)
		_garden_wall(f, wall_from, centre - 110.0, far_edge)
		wall_from = centre + 110.0
		_tree(f, centre + pitch * 0.5 + _rng.randf_range(-120.0, 120.0),
			far_edge + _rng.randf_range(230.0, 330.0), _rng.randf_range(300.0, 380.0),
			_rng.randf_range(230.0, 290.0))
		for k: int in 2:
			_tree(f, centre + (float(k) - 0.25) * pitch * 0.5 + _rng.randf_range(-150.0, 150.0),
				front + HOUSE_SIZE + _rng.randf_range(350.0, 700.0), _rng.randf_range(330.0, 420.0),
				_rng.randf_range(300.0, 400.0))
	_garden_wall(f, wall_from, a1, far_edge)

## A low brick garden wall with a cap, and a pier at each end.
func _garden_wall(f: Frame, from: float, to: float, at: float) -> void:
	if to - from < 60.0:
		return
	_box(f, &"solid", &"brick", from, to, 0.0, 72.0, at + 4.0, at + 26.0, F_SIDES)
	_box(f, &"solid", &"cap", from - 1.0, to + 1.0, 72.0, 78.0, at + 2.0, at + 28.0, F_ALL)
	for end: float in [from, to - 32.0]:
		_box(f, &"solid", &"brick", end, end + 32.0, 0.0, 96.0, at, at + 32.0, F_SIDES)
		_box(f, &"solid", &"cap", end - 2.0, end + 34.0, 96.0, 103.0, at - 2.0, at + 34.0, F_ALL)

# ---- a garden side: the timber fence, then the neighbouring plots ----

func _timber_fence(f: Frame) -> void:
	_cut = Vector2(f.out.x, f.out.z)
	var top: float = _theme.fence_height
	# Boards (vertical planks), a gravel board under them, a capping rail.
	_box(f, &"fence", &"fence_wood", 0.0, f.length, 15.0, top, 8.0, 12.0, F_SIDES | F_UP, 0.0, true)
	_box(f, &"fence", &"fence_post", 0.0, f.length, 0.0, 15.0, 6.0, 12.0, F_SIDES | F_UP)
	_box(f, &"fence", &"fence_post", 0.0, f.length, top, top + 4.0, 5.0, 15.0, F_ALL)
	# The rail side faces the lot: three arris rails and a post every bay.
	for rail: float in [38.0, 112.0, top - 24.0]:
		_box(f, &"fence", &"fence_post", 0.0, f.length, rail, rail + 10.0, 3.0, 8.0, F_IN | F_UP | F_DOWN)
	var bays: int = int(round(f.length / 240.0))
	for i: int in bays + 1:
		var at: float = clampf(f.length * float(i) / float(bays), 6.0, f.length - 6.0)
		_box(f, &"fence", &"fence_post", at - 6.0, at + 6.0, 0.0, top + 7.0, 0.0, 12.0, F_NO_BOTTOM)

func _neighbours(f: Frame) -> void:
	# Two more plots like this one, each with its two houses where this lot's
	# stand (seen from this side: one near the fence, one far).
	var house_gap: float = _houses[0].position.x - _lot.position.x if not _houses.is_empty() else 350.0
	var depth: float = _lot.size.x
	for plot: int in 2:
		var shift: float = float(plot) * depth
		_house(f, Rect2(house_gap, shift + house_gap, HOUSE_SIZE, HOUSE_SIZE), 1, plot == 1)
		_house(f, Rect2(f.length - house_gap - HOUSE_SIZE, shift + depth - house_gap - HOUSE_SIZE,
			HOUSE_SIZE, HOUSE_SIZE), 2, plot == 0)
		# The plot's far boundary: a tall hedge.
		_box(f, &"solid", &"hedge", 0.0, f.length, 0.0, 190.0, shift + depth - 30.0, shift + depth + 30.0, F_NO_BOTTOM)
	# Trees in the open corner of the nearest plot. Their crowns show over the
	# fence; trunks stand clear of it and crowns start above the camera (NEAR_TRUNK).
	var open_from: float = house_gap + HOUSE_SIZE
	_tree(f, open_from + 330.0, 520.0, NEAR_TRUNK, 225.0)
	_tree(f, f.length - 330.0, 600.0, NEAR_TRUNK + 30.0, 230.0)
	_tree(f, open_from + 700.0, 1450.0, 380.0, 330.0)
	_tree(f, f.length - 420.0, 2250.0, 360.0, 350.0)
	_tree(f, house_gap * 0.5, 720.0, NEAR_TRUNK, 150.0)
	_tree(f, open_from + 560.0, depth + 900.0, 380.0, 360.0)

## A neighbour's house: a plain two-storey box under a hipped roof, a door on
## `front` (0 = the face toward the lot edge, 1 = along-low, 2 = along-high,
## 3 = the far face), windows on every face. `box` is (along, out).
func _house(f: Frame, box: Rect2, front: int, rendered: bool) -> void:
	var wall: StringName = &"render" if rendered else &"brick"
	_box(f, &"solid", wall, box.position.x, box.end.x, 0.0, HOUSE_WALL, box.position.y, box.end.y, F_SIDES)
	for face: int in 4:
		var span: float = box.size.x if face == 0 or face == 3 else box.size.y
		var bays: Array[float] = [span * 0.22, span * 0.78]
		if face == front:
			_decal(f, &"trim", face, box, span * 0.5 - 68.0, span * 0.5 + 68.0, 0.0, 226.0, 1.5)
			_decal(f, &"door", face, box, span * 0.5 - 55.0, span * 0.5 + 55.0, 0.0, 215.0, 3.0)
			_decal(f, &"trim", face, box, span * 0.5 - 150.0, span * 0.5 + 150.0, 262.0, 272.0, 14.0)
		else:
			bays.append(span * 0.5)
		for storey: float in [95.0, 455.0]:
			for bay: float in bays:
				_decal(f, &"trim", face, box, bay - 84.0, bay + 84.0, storey - 9.0, storey + 159.0, 1.5)
				_decal(f, &"glass", face, box, bay - 75.0, bay + 75.0, storey, storey + 150.0, 3.0)
				_decal(f, &"trim", face, box, bay - 3.0, bay + 3.0, storey, storey + 150.0, 4.0)
	# The roof: four slopes to a point, a fascia and a soffit round the eaves.
	var grown: Rect2 = box.grow(ROOF_OVERHANG)
	var rise: float = (minf(grown.size.x, grown.size.y) * 0.5) * tan(deg_to_rad(_theme.roof_pitch_deg))
	var eaves: Array[Vector3] = [f.at(grown.position.x, HOUSE_WALL, grown.position.y),
		f.at(grown.end.x, HOUSE_WALL, grown.position.y), f.at(grown.end.x, HOUSE_WALL, grown.end.y),
		f.at(grown.position.x, HOUSE_WALL, grown.end.y)]
	var inner: Array[Vector3] = [f.at(box.position.x, HOUSE_WALL - 18.0, box.position.y),
		f.at(box.end.x, HOUSE_WALL - 18.0, box.position.y), f.at(box.end.x, HOUSE_WALL - 18.0, box.end.y),
		f.at(box.position.x, HOUSE_WALL - 18.0, box.end.y)]
	var centre: Vector2 = grown.get_center()
	var apex: Vector3 = f.at(centre.x, HOUSE_WALL + rise, centre.y)
	var middle: Vector3 = f.at(centre.x, HOUSE_WALL, centre.y)
	for i: int in 4:
		var a: Vector3 = eaves[i]
		var b: Vector3 = eaves[(i + 1) % 4]
		var outward: Vector3 = ((a + b) * 0.5 - middle).normalized()
		var slope: Vector3 = (apex - (a + b) * 0.5)
		var normal: Vector3 = (outward * rise + Vector3.UP * slope.length()).normalized()
		var eave: float = a.distance_to(b)
		_tri(&"solid", &"roof", [a, b, apex], [normal, normal, normal],
			[Vector2(0.0, 0.0), Vector2(eave, 0.0), Vector2(eave * 0.5, -slope.length())], normal)
		var drop: Vector3 = Vector3(0.0, 18.0, 0.0)
		_quad(&"solid", &"trim", [a - drop, b - drop, b, a], outward)
		_quad(&"solid", &"trim", [a - drop, inner[i], inner[(i + 1) % 4], b - drop], Vector3.DOWN)

## A flat rectangle on one face of a house box, `lift` off the wall. `from`/`to`
## run along the face from its low end.
func _decal(f: Frame, key: StringName, face: int, box: Rect2, from: float, to: float,
		low: float, high: float, lift: float) -> void:
	var corners: Array[Vector3] = []
	var normal: Vector3
	for corner: Vector2 in [Vector2(from, low), Vector2(to, low), Vector2(to, high), Vector2(from, high)]:
		match face:
			0: corners.append(f.at(box.position.x + corner.x, corner.y, box.position.y - lift))
			3: corners.append(f.at(box.position.x + corner.x, corner.y, box.end.y + lift))
			1: corners.append(f.at(box.position.x - lift, corner.y, box.position.y + corner.x))
			_: corners.append(f.at(box.end.x + lift, corner.y, box.position.y + corner.x))
	match face:
		0: normal = -f.out
		3: normal = f.out
		1: normal = -f.dir
		_: normal = f.dir
	_quad(&"solid", key, corners, normal)

## A tree at (along, out): a tapered trunk and a crown of a few lumps.
func _tree(f: Frame, along: float, outward: float, trunk: float, radius: float) -> void:
	var foot: Vector3 = f.at(along, 0.0, outward)
	var girth: float = radius * 0.075 + 7.0
	var sides: int = 8
	var top: float = trunk + radius * 0.45
	for i: int in sides:
		var a0: float = TAU * float(i) / float(sides)
		var a1: float = TAU * float(i + 1) / float(sides)
		var n0: Vector3 = Vector3(cos(a0), 0.0, sin(a0))
		var n1: Vector3 = Vector3(cos(a1), 0.0, sin(a1))
		var corners: Array[Vector3] = [foot + n0 * girth * 1.25, foot + n1 * girth * 1.25,
			foot + n1 * girth * 0.6 + Vector3.UP * top, foot + n0 * girth * 0.6 + Vector3.UP * top]
		_quad(&"solid", &"bark", corners, ((n0 + n1) * 0.5).normalized())
	var heart: Vector3 = foot + Vector3.UP * (trunk + radius * 0.8)
	var tint: float = _rng.randf_range(0.86, 1.06)
	var lumps: int = 5
	for i: int in lumps:
		var angle: float = TAU * float(i) / float(lumps - 1) + _rng.randf_range(-0.4, 0.4)
		var offset: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * radius * _rng.randf_range(0.36, 0.48)
		offset.y = radius * _rng.randf_range(-0.16, 0.12)
		var size: float = radius * _rng.randf_range(0.52, 0.64)
		if i == lumps - 1:
			# The last lump is the top of the crown.
			offset = Vector3(0.0, radius * 0.3, 0.0)
			size = radius * 0.62
		_blob(&"solid", &"crown", heart + offset, Vector3(size, size * 0.86, size), heart, 2, tint)

## A lumpy ball: an icosphere pushed in and out by noise. Its normals lean
## toward `heart` -> surface (when given), so a crown of several lumps shades as
## one mass; its colour darkens toward the underside.
func _blob(group: StringName, key: StringName, centre: Vector3, size: Vector3, heart: Vector3,
		detail: int, tint: float) -> void:
	_sphere(detail)
	var tool: SurfaceTool = _tool(group, key)
	var points: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colours: PackedColorArray = PackedColorArray()
	var wobble: float = 0.2 if detail > 1 else 0.1
	for unit: Vector3 in _sphere_points:
		var swell: float = 1.0 + wobble * _noise.get_noise_3dv(unit * 1.7 + centre * 0.013)
		var point: Vector3 = centre + unit * size * swell
		var normal: Vector3 = unit
		if heart != Vector3.ZERO:
			normal = (unit * 0.45 + (point - heart).normalized() * 0.55).normalized()
		var shade: float = lerpf(0.5, 1.08, clampf(unit.y * 0.5 + 0.5, 0.0, 1.0)) * tint
		points.append(point)
		normals.append(normal)
		colours.append(Color(shade, shade, shade))
	for i: int in range(0, _sphere_faces.size(), 3):
		# Clockwise seen from outside (Godot's front face).
		for corner: int in [0, 2, 1]:
			var index: int = _sphere_faces[i + corner]
			tool.set_normal(normals[index])
			tool.set_color(colours[index])
			tool.set_uv(Vector2.ZERO)
			tool.add_vertex(points[index])

## The unit icosphere at `detail` subdivisions (1 = 80 faces, 2 = 320), faces
## counter-clockwise seen from outside.
var _sphere_detail: int = -1
func _sphere(detail: int) -> void:
	if detail == _sphere_detail:
		return
	_sphere_detail = detail
	var t: float = (1.0 + sqrt(5.0)) * 0.5
	var points: Array[Vector3] = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i: int in points.size():
		points[i] = points[i].normalized()
	var faces: Array[int] = [0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2,
		10, 7, 6, 7, 1, 8, 3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10,
		8, 6, 7, 9, 8, 1]
	for pass_index: int in detail:
		var next: Array[int] = []
		var mids: Dictionary[int, int] = {}
		for i: int in range(0, faces.size(), 3):
			var corners: Array[int] = [faces[i], faces[i + 1], faces[i + 2]]
			var between: Array[int] = []
			for k: int in 3:
				var a: int = corners[k]
				var b: int = corners[(k + 1) % 3]
				var id: int = mini(a, b) * 100000 + maxi(a, b)
				if not mids.has(id):
					mids[id] = points.size()
					points.append(((points[a] + points[b]) * 0.5).normalized())
				between.append(mids[id])
			next.append_array([corners[0], between[0], between[2], corners[1], between[1], between[0],
				corners[2], between[2], between[1], between[0], between[1], between[2]])
		faces = next
	_sphere_points = PackedVector3Array(points)
	_sphere_faces = PackedInt32Array(faces)

# ---- mesh building ----

func _tool(group: StringName, key: StringName) -> SurfaceTool:
	if not _tools.has(group):
		_tools[group] = {}
	var keys: Dictionary = _tools[group]
	if not keys.has(key):
		var tool: SurfaceTool = SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		keys[key] = tool
	return keys[key]

## A flat strip on a street, in frame coordinates.
func _surface(f: Frame, key: StringName, a0: float, a1: float, o0: float, o1: float, lift: float) -> void:
	_quad(&"ground", key, [f.at(a0, lift, o0), f.at(a1, lift, o0), f.at(a1, lift, o1), f.at(a0, lift, o1)],
		Vector3.UP)

## A box in frame coordinates, drawing only the faces in `faces`. `top_at`
## overrides the height the top face is drawn at (a kerb a hair above the
## pavement it sits in). `upright` turns the texture a quarter (vertical planks).
func _box(f: Frame, group: StringName, key: StringName, a0: float, a1: float, u0: float, u1: float,
		o0: float, o1: float, faces: int, top_at: float = 0.0, upright: bool = false) -> void:
	var top: float = top_at if top_at > 0.0 else u1
	if faces & F_UP:
		_quad(group, key, [f.at(a0, top, o0), f.at(a1, top, o0), f.at(a1, top, o1), f.at(a0, top, o1)],
			Vector3.UP, upright)
	if faces & F_DOWN:
		_quad(group, key, [f.at(a0, u0, o0), f.at(a1, u0, o0), f.at(a1, u0, o1), f.at(a0, u0, o1)],
			Vector3.DOWN, upright)
	if faces & F_IN:
		_quad(group, key, [f.at(a0, u0, o0), f.at(a1, u0, o0), f.at(a1, u1, o0), f.at(a0, u1, o0)],
			-f.out, upright)
	if faces & F_OUT:
		_quad(group, key, [f.at(a0, u0, o1), f.at(a1, u0, o1), f.at(a1, u1, o1), f.at(a0, u1, o1)],
			f.out, upright)
	if faces & F_ALONG_LO:
		_quad(group, key, [f.at(a0, u0, o0), f.at(a0, u0, o1), f.at(a0, u1, o1), f.at(a0, u1, o0)],
			-f.dir, upright)
	if faces & F_ALONG_HI:
		_quad(group, key, [f.at(a1, u0, o0), f.at(a1, u0, o1), f.at(a1, u1, o1), f.at(a1, u1, o0)],
			f.dir, upright)

## One flat quad with world-position UVs (ShellBuilder's convention), wound to
## face along `normal`.
func _quad(group: StringName, key: StringName, corners: Array[Vector3], normal: Vector3,
		upright: bool = false) -> void:
	var tool: SurfaceTool = _tool(group, key)
	var turning: float = (corners[1] - corners[0]).cross(corners[2] - corners[0]).dot(normal)
	var order: Array[int] = ShellBuilder.QUAD_TURNED if turning > 0.0 else ShellBuilder.QUAD_AS_IS
	for index: int in order:
		var uv: Vector2 = ShellBuilder._uv(corners[index], normal)
		tool.set_normal(normal)
		tool.set_uv(Vector2(uv.y, uv.x) if upright else uv)
		if group == &"fence":
			tool.set_uv2(_cut)
		tool.add_vertex(corners[index])

func _tri(group: StringName, key: StringName, points: Array[Vector3], normals: Array[Vector3],
		uvs: Array[Vector2], facing: Vector3) -> void:
	var tool: SurfaceTool = _tool(group, key)
	var turning: float = (points[1] - points[0]).cross(points[2] - points[0]).dot(facing)
	var order: Array[int] = ShellBuilder.TRI_TURNED if turning > 0.0 else ShellBuilder.TRI_AS_IS
	for index: int in order:
		tool.set_normal(normals[index])
		tool.set_uv(uvs[index])
		tool.add_vertex(points[index])

func _commit() -> Array[Node3D]:
	var nodes: Array[Node3D] = []
	var groups: Array[StringName] = _tools.keys()
	groups.sort()
	for group: StringName in groups:
		var mesh: ArrayMesh = ArrayMesh.new()
		var keys: Array = _tools[group].keys()
		keys.sort()
		for key: StringName in keys:
			var tool: SurfaceTool = _tools[group][key]
			tool.set_material(_material(group, key))
			tool.commit(mesh)
		var view: MeshInstance3D = MeshInstance3D.new()
		view.name = "exterior_%s" % group
		view.mesh = mesh
		view.layers = WorldBackdrop.OUTDOOR_LAYER
		if group != &"solid":
			view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		nodes.append(view)
		if group == &"fence":
			# The cut-away never takes the fence's shadow with it.
			var shadow: MeshInstance3D = MeshInstance3D.new()
			shadow.name = "exterior_fence_shadow"
			shadow.mesh = mesh
			shadow.material_override = _plain(Color.WHITE, 1.0)
			shadow.layers = WorldBackdrop.OUTDOOR_LAYER
			shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			nodes.append(shadow)
	return nodes

## Built-in looks for names the theme does not list.
const FALLBACK: Dictionary[StringName, Color] = {
	&"pavement": Color(0.6, 0.58, 0.54), &"kerb": Color(0.66, 0.65, 0.62),
	&"asphalt": Color(0.24, 0.24, 0.25), &"road_line": Color(0.82, 0.81, 0.76),
	&"gravel": Color(0.6, 0.57, 0.51), &"soil": Color(0.25, 0.19, 0.14),
	&"fence_wood": Color(0.45, 0.33, 0.23), &"fence_post": Color(0.36, 0.27, 0.19),
	&"fence_steel": Color(0.1, 0.105, 0.11), &"fence_cap": Color(0.72, 0.69, 0.63),
	&"cap": Color(0.72, 0.69, 0.63), &"hedge": Color(0.2, 0.33, 0.17),
	&"crown": Color(0.25, 0.4, 0.2), &"bark": Color(0.33, 0.27, 0.21),
	&"render": Color(0.84, 0.81, 0.74), &"door": Color(0.2, 0.22, 0.25),
}

func _material(group: StringName, key: StringName) -> Material:
	var id: StringName = StringName("%s/%s" % [group, key])
	if _materials.has(id):
		return _materials[id]
	var source: StandardMaterial3D = null
	match key:
		&"brick", &"fence_brick": source = _theme.wall_outside
		&"roof": source = _theme.roof
		&"trim": source = _theme.trim
		&"glass": source = _theme.glass
		&"cap": source = _theme.exterior_materials.get(&"fence_cap", null)
		_: source = _theme.exterior_materials.get(key, null)
	if source == null:
		source = _plain(FALLBACK.get(key, Color(0.6, 0.6, 0.6)), 0.9)
		if key == &"crown":
			source.vertex_color_use_as_albedo = true
	var made: Material = source
	if group == &"fence":
		var cut: ShaderMaterial = ShaderMaterial.new()
		cut.shader = CUTAWAY
		cut.set_shader_parameter(&"albedo", source.albedo_color)
		cut.set_shader_parameter(&"use_texture", source.albedo_texture != null)
		if source.albedo_texture != null:
			cut.set_shader_parameter(&"albedo_texture", source.albedo_texture)
		cut.set_shader_parameter(&"uv_scale", Vector2(source.uv1_scale.x, source.uv1_scale.y))
		cut.set_shader_parameter(&"roughness", source.roughness)
		cut.set_shader_parameter(&"metallic", source.metallic)
		made = cut
	_materials[id] = made
	return made

static func _plain(colour: Color, roughness: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = roughness
	return material
