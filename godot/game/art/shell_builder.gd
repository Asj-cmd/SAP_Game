class_name ShellBuilder
extends RefCounted
## The house's visual shell, generated from the blockout data (PLAN P3-2,
## STYLE §3.3 "the kit": no modular kit, the shell is built from the blockers).
##
## Presentation only. It reads the level's blockers and zones and returns
## meshes; it adds no collision and changes no box, so what a body walks through
## is exactly what it walked through before (D7, DECISIONS "art never changes
## collision").
##
## WHAT IT DRAWS, all from the same AABBs the simulation collides with:
##
## - Every face of every blocker, cut where other boxes and the rooms' edges
##   meet it. A cell that another box covers is dropped (hidden faces, and the
##   coplanar pairs that would z-fight). Each cell takes a material from what is
##   in front of it: the room's wall finish, its floor, the ceiling, brick
##   outside, roof tile on top, fascia round the roof slab's edge.
## - Stair treads: oak tops, painted risers.
## - Openings, found as the air under a lintel: a painted casing round both
##   faces, in the family colour on the outside of an exterior opening, and a
##   pair of glazed doors standing open flat against the inside wall. Every
##   opening in the blockout is a full-height 240 x 240 gap, doors and windows
##   alike (`build_house.gd` `_panels`), so every exterior one is drawn as open
##   french doors; a sill would show a climb the rules do not have.
## - Skirting along the foot of every interior wall.
## - A hipped roof over each house, with an overhang and a soffit. The camera
##   never rises above the roof slab (its spring arm collides with the slab), so
##   the pitched roof is never between the camera and a body and needs no
##   cut-away.
##
## Everything is merged per house and per material: one MeshInstance3D per house
## with one surface per material, instead of one draw call per box.
##
## UVs are world positions in units (cm), so a material's `uv1_scale` of
## 1 / tile size gives true-size texture everywhere (STYLE §3.3 texel density),
## and a seam between two cells of one wall cannot show.

## How far off a face the point that decides its material is taken.
const PROBE: float = 0.5
## How far outside a room's box a face still belongs to that room: a wall's
## own thickness, which holds the doorway reveals and the sills inside the
## wall. Less than the 30.5 an outer wall's OUTSIDE face is from the room
## (wall 30 + PROBE), so the outside stays outside.
const REACH: float = 30.25
## The thinnest a box can be across and still be a wall (build_house WALL 30).
const WALL_MAX: float = 31.0
## A box this thick or thinner, wider than STAIR_MIN both ways, is a floor slab.
const SLAB_MAX: float = 41.0
## Stair treads (build_house: 30 rise, 48 run, 280 wide) and the soffits under them.
const TREAD_RISE_MAX: float = 31.0
const TREAD_RUN_MAX: float = 49.0
const STAIR_MIN: float = 200.0
const TINY: float = 0.5
## The ground floor's finish above the lawn box it is laid on. Twice the
## outdoor patches' 0.6 (greybox_main PATCH_THICKNESS): a yard patch carried
## out to its zone edge reaches through an exterior doorway's sill, and at the
## same height the two fought there in a sawtooth (P3-2 frames ext_a_east).
const GROUND_LIFT: float = 1.2
## Vertex orders for a quad / triangle whose corners turn counter-clockwise
## seen from the front (Godot draws clockwise fronts), and for one that already
## turns clockwise.
const QUAD_TURNED: Array[int] = [0, 2, 1, 0, 3, 2]
const QUAD_AS_IS: Array[int] = [0, 1, 2, 0, 2, 3]
const TRI_TURNED: Array[int] = [0, 2, 1]
const TRI_AS_IS: Array[int] = [0, 1, 2]

enum Shape { OTHER, WALL, SLAB, TREAD, SOFFIT }

class House:
	var team: StringName = &""
	var rect: Rect2 = Rect2()
	var top: float = -INF
	var tools: Dictionary[StringName, SurfaceTool] = {}

var _theme: ArtTheme = null
var _blockers: Array[AABB] = []
var _skip: int = -1
var _rooms: Array[ZoneDef] = []
var _houses: Array[House] = []
var _lot: House = null
var _materials: Dictionary[StringName, StandardMaterial3D] = {}
var quads: int = 0

## The shell for `level`: one node per house plus one for anything outside
## the houses. `skip` is the index of a blocker drawn elsewhere (the lot's
## ground, which keeps its lawn box and its outdoor render layer).
static func build(level: GreyBoxLevel, theme: ArtTheme, skip: int) -> Array[MeshInstance3D]:
	var builder: ShellBuilder = ShellBuilder.new()
	return builder._build(level, theme, skip)

func _build(level: GreyBoxLevel, theme: ArtTheme, skip: int) -> Array[MeshInstance3D]:
	_theme = theme
	# Furniture is collision but not shell (P3-3): FurnitureDresser draws it. Left
	# in, it would be drawn as plaster boxes and would cut the walls and floors
	# it stands against, leaving holes wherever a model does not fill its box.
	var furniture: Dictionary[AABB, bool] = {}
	if level.level != null:
		for box: AABB in level.level.furniture:
			furniture[box] = true
	var skip_box: AABB = level.collision.blockers[skip] if skip >= 0 else AABB()
	_blockers = []
	for box: AABB in level.collision.blockers:
		if not furniture.has(box):
			_blockers.append(box)
	_skip = _blockers.find(skip_box) if skip >= 0 else -1
	for zone: ZoneDef in ZoneDef.sorted_for_resolution(level.zones):
		if not zone.outdoor:
			_rooms.append(zone)
	_find_houses()
	_lot = House.new()
	for i: int in _blockers.size():
		if i != _skip:
			_box_faces(i)
	# The ground floor stands on the lot's ground box, which is drawn elsewhere
	# (lawn). Its top inside each house is laid here like any other floor: cut
	# by the walls standing on it, each room's finish out to the wall faces and
	# through the doorway sills. Lifted off the lawn so the two do not fight.
	if _skip >= 0:
		var ground: AABB = _blockers[_skip]
		for house: House in _houses:
			var under: AABB = AABB(Vector3(house.rect.position.x, ground.position.y,
				house.rect.position.y), Vector3(house.rect.size.x, ground.size.y,
				house.rect.size.y)).intersection(ground)
			if under.size.x > 0.0 and under.size.z > 0.0:
				_face(_skip, under, house, Shape.SLAB, 1, 1.0, GROUND_LIFT)
	_openings()
	_banisters()
	for house: House in _houses:
		_roof(house)
	var made: Array[MeshInstance3D] = []
	for house: House in _houses + [_lot]:
		var node: MeshInstance3D = _commit(house)
		if node != null:
			node.name = "shell_%s" % (house.team if house.team != &"" else &"lot")
			made.append(node)
	return made

# ---- houses ----

## A house per team that owns indoor rooms: the rooms' union grown by a wall.
func _find_houses() -> void:
	var by_team: Dictionary[StringName, House] = {}
	for room: ZoneDef in _rooms:
		if room.owner_team == &"":
			continue
		var flat: Rect2 = Rect2(room.bounds.position.x, room.bounds.position.z,
			room.bounds.size.x, room.bounds.size.z)
		if not by_team.has(room.owner_team):
			var house: House = House.new()
			house.team = room.owner_team
			house.rect = flat
			by_team[room.owner_team] = house
		else:
			by_team[room.owner_team].rect = by_team[room.owner_team].rect.merge(flat)
	var teams: Array[StringName] = by_team.keys()
	teams.sort()
	for team: StringName in teams:
		var house: House = by_team[team]
		house.rect = house.rect.grow(WALL_MAX - 1.0)
		_houses.append(house)
	for i: int in _blockers.size():
		if i == _skip:
			continue
		var house: House = _house_of(_blockers[i].get_center())
		if house != _lot and house != null:
			house.top = maxf(house.top, _blockers[i].end.y)

func _house_of(point: Vector3) -> House:
	for house: House in _houses:
		if house.rect.grow(TINY).has_point(Vector2(point.x, point.z)):
			return house
	return _lot

## The room a point belongs to: the zone it is in (highest priority first), or
## the nearest room within REACH at the same height - a doorway's sill or
## reveal, inside the wall between rooms. Null = outdoors.
func _room_at(point: Vector3) -> ZoneDef:
	for room: ZoneDef in _rooms:
		if room.bounds.has_point(point):
			return room
	var best: ZoneDef = null
	var best_distance: float = REACH
	for room: ZoneDef in _rooms:
		var box: AABB = room.bounds
		if point.y < box.position.y or point.y > box.end.y:
			continue
		var dx: float = maxf(maxf(box.position.x - point.x, point.x - box.end.x), 0.0)
		var dz: float = maxf(maxf(box.position.z - point.z, point.z - box.end.z), 0.0)
		var distance: float = sqrt(dx * dx + dz * dz)
		if distance <= best_distance:
			best_distance = distance
			best = room
	return best

static func _shape(box: AABB) -> Shape:
	var across: float = minf(box.size.x, box.size.z)
	var along: float = maxf(box.size.x, box.size.z)
	if box.size.y <= TREAD_RISE_MAX and across <= TREAD_RUN_MAX and along >= STAIR_MIN:
		return Shape.TREAD
	if across <= TREAD_RUN_MAX and across > WALL_MAX and along >= STAIR_MIN:
		return Shape.SOFFIT
	if across <= WALL_MAX and box.size.y > SLAB_MAX:
		return Shape.WALL
	if box.size.y <= SLAB_MAX and across >= STAIR_MIN:
		return Shape.SLAB
	return Shape.OTHER

# ---- faces ----

func _box_faces(index: int) -> void:
	var box: AABB = _blockers[index]
	var house: House = _house_of(box.get_center())
	var shape: Shape = _shape(box)
	for axis: int in 3:
		for sign: float in [-1.0, 1.0]:
			_face(index, box, house, shape, axis, sign, 0.0)

## One face of `box`, cut into cells; `lift` moves the drawn face off its plane.
func _face(index: int, box: AABB, house: House, shape: Shape, axis: int, sign: float,
		lift: float) -> void:
	var u: int = (axis + 1) % 3
	var w: int = (axis + 2) % 3
	var plane: float = box.end[axis] if sign > 0.0 else box.position[axis]
	var probe_at: float = plane + sign * PROBE
	var us: Array[float] = [box.position[u], box.end[u]]
	var ws: Array[float] = [box.position[w], box.end[w]]
	# Boxes that can cover part of this face: they hold the probe plane and
	# overlap the face. Their edges cut the face into cells.
	var covers: Array[AABB] = []
	for j: int in _blockers.size():
		if j == index:
			continue
		var other: AABB = _blockers[j]
		if probe_at <= other.position[axis] or probe_at >= other.end[axis]:
			continue
		if other.end[u] <= box.position[u] or other.position[u] >= box.end[u]:
			continue
		if other.end[w] <= box.position[w] or other.position[w] >= box.end[w]:
			continue
		covers.append(other)
		_cut(us, other.position[u], other.end[u], box.position[u], box.end[u])
		_cut(ws, other.position[w], other.end[w], box.position[w], box.end[w])
	# Room edges split a face between two rooms' finishes.
	for room: ZoneDef in _rooms:
		var grown: AABB = room.bounds.grow(REACH)
		if probe_at < grown.position[axis] or probe_at > grown.end[axis]:
			continue
		_cut(us, room.bounds.position[u], room.bounds.end[u], box.position[u], box.end[u])
		_cut(ws, room.bounds.position[w], room.bounds.end[w], box.position[w], box.end[w])
	us.sort()
	ws.sort()
	var normal: Vector3 = Vector3.ZERO
	normal[axis] = sign
	for i: int in us.size() - 1:
		if us[i + 1] - us[i] < TINY:
			continue
		for k: int in ws.size() - 1:
			if ws[k + 1] - ws[k] < TINY:
				continue
			var centre: Vector3 = Vector3.ZERO
			centre[axis] = probe_at
			centre[u] = (us[i] + us[i + 1]) * 0.5
			centre[w] = (ws[k] + ws[k + 1]) * 0.5
			var hidden: bool = false
			for other: AABB in covers:
				if other.has_point(centre):
					hidden = true
					break
			if hidden:
				continue
			var room: ZoneDef = _room_at(centre)
			var key: StringName = _key(box, house, shape, axis, sign, room)
			var a: Vector3 = Vector3.ZERO
			a[axis] = plane + sign * lift
			var corners: Array[Vector3] = []
			for corner: Vector2 in [Vector2(us[i], ws[k]), Vector2(us[i + 1], ws[k]),
					Vector2(us[i + 1], ws[k + 1]), Vector2(us[i], ws[k + 1])]:
				var p: Vector3 = a
				p[u] = corner.x
				p[w] = corner.y
				corners.append(p)
			_quad(house, key, corners, normal)
			if shape == Shape.WALL and axis != 1 and room != null:
				_skirting(house, corners, normal, axis, plane, sign)

static func _cut(cuts: Array[float], lo: float, hi: float, from: float, to: float) -> void:
	for value: float in [lo, hi]:
		if value > from + TINY and value < to - TINY:
			cuts.append(value)

## Which material a face cell takes (see `_material`).
func _key(box: AABB, house: House, shape: Shape, axis: int, sign: float,
		room: ZoneDef) -> StringName:
	var kind: StringName = ArtTheme.room_kind(room.id) if room != null else &""
	if axis == 1 and sign > 0.0:
		if shape == Shape.TREAD:
			return &"tread"
		# The only slab outside the houses is a back staircase's platform (P3-8):
		# decked like the treads that lead to it.
		if shape == Shape.SLAB and house == _lot:
			return &"tread"
		if room != null:
			return StringName("floor:%s" % kind)
		if house != _lot and box.end.y >= house.top - TINY:
			return &"roof"
		return &"trim"
	if axis == 1:
		return &"ceiling" if room != null else &"trim"
	if shape == Shape.TREAD:
		# The flight runs along the tread's short side: those faces are risers.
		var short_axis: int = 0 if box.size.x < box.size.z else 2
		if axis == short_axis:
			return &"riser"
	if room != null:
		return StringName("wall:%s" % kind)
	if shape == Shape.SLAB and house != _lot and box.end.y >= house.top - TINY:
		return &"fascia"
	return &"wall_out"

## A skirting board along a wall cell whose foot stands on a floor.
func _skirting(house: House, corners: Array[Vector3], normal: Vector3, axis: int,
		plane: float, sign: float) -> void:
	var height: float = _theme.skirting_height
	if height <= 0.0:
		return
	var low: float = minf(corners[0].y, corners[2].y)
	var high: float = maxf(corners[0].y, corners[2].y)
	var foot: Vector3 = (corners[0] + corners[2]) * 0.5
	foot.y = low - PROBE
	foot += normal * 5.0
	if not _solid_at(foot):
		return
	var along: int = 2 if axis == 0 else 0
	var lo: float = minf(corners[0][along], corners[2][along])
	var hi: float = maxf(corners[0][along], corners[2][along])
	var size: Vector3 = Vector3.ZERO
	var at: Vector3 = Vector3.ZERO
	size[along] = hi - lo
	at[along] = lo
	size.y = minf(height, high - low)
	at.y = low
	size[axis] = _theme.skirting_depth
	at[axis] = plane if sign > 0.0 else plane - _theme.skirting_depth
	_box(house, &"trim", AABB(at, size), true)

func _solid_at(point: Vector3) -> bool:
	for i: int in _blockers.size():
		if _blockers[i].has_point(point):
			return true
	return false

# ---- openings: casings and leaves ----

## Every opening in a wall: the air under a lintel (a wall piece that does not
## stand on anything), from the floor below up to the lintel's underside.
func _openings() -> void:
	for i: int in _blockers.size():
		var box: AABB = _blockers[i]
		if i == _skip or _shape(box) != Shape.WALL:
			continue
		var under: Vector3 = box.get_center()
		under.y = box.position.y - 1.0
		if _solid_at(under):
			continue
		var floor_y: float = -INF
		for other: AABB in _blockers:
			if other.end.y <= box.position.y and other.position.x < under.x \
					and other.end.x > under.x and other.position.z < under.z \
					and other.end.z > under.z:
				floor_y = maxf(floor_y, other.end.y)
		if floor_y == -INF or box.position.y - floor_y < 100.0:
			continue
		var thin: int = 0 if box.size.x < box.size.z else 2
		var along: int = 2 if thin == 0 else 0
		_dress_opening(_house_of(box.get_center()), box, thin, along, floor_y)

func _dress_opening(house: House, lintel: AABB, thin: int, along: int, floor_y: float) -> void:
	var o0: float = lintel.position[along]
	var o1: float = lintel.end[along]
	var head: float = lintel.position.y
	var width: float = _theme.casing_width
	var depth: float = _theme.casing_depth
	var mid: Vector3 = lintel.get_center()
	mid.y = (floor_y + head) * 0.5
	var sides: Array[float] = [-1.0, 1.0]
	var indoor: Array[bool] = []
	for sign: float in sides:
		var probe: Vector3 = mid
		probe[thin] = (lintel.end[thin] if sign > 0.0 else lintel.position[thin]) + sign * 5.0
		indoor.append(_room_at(probe) != null)
	var exterior: bool = indoor[0] != indoor[1]
	var paint: StringName = StringName("paint:%s" % house.team)
	for s: int in 2:
		var sign: float = sides[s]
		var plane: float = lintel.end[thin] if sign > 0.0 else lintel.position[thin]
		var t0: float = plane if sign > 0.0 else plane - depth
		var key: StringName = &"trim" if indoor[s] or house == _lot else paint
		var pieces: Array[Vector4] = [
			Vector4(o0 - width, o0, floor_y, head + width), # jamb
			Vector4(o1, o1 + width, floor_y, head + width), # jamb
			Vector4(o0, o1, head, head + width), # head
		]
		for piece: Vector4 in pieces:
			var at: Vector3 = Vector3.ZERO
			var size: Vector3 = Vector3.ZERO
			at[along] = piece.x
			size[along] = piece.y - piece.x
			at.y = piece.z
			size.y = piece.w - piece.z
			at[thin] = t0
			size[thin] = depth
			_box(house, key, AABB(at, size), false)
		if exterior and indoor[s] and house != _lot:
			_leaves(house, paint, o0, o1, floor_y, head, thin, along, plane, sign)

## Two glazed door leaves standing open flat against the inside wall, one each
## side of the opening, hinged at its edges. A leaf that would run into
## anything (a corner, a stair) is left out.
func _leaves(house: House, paint: StringName, o0: float, o1: float, floor_y: float,
		head: float, thin: int, along: int, plane: float, sign: float) -> void:
	var half: float = (o1 - o0) * 0.5
	var stand_off: float = _theme.casing_depth
	var thick: float = _theme.leaf_depth
	for spans: Vector2 in [Vector2(o0 - half, o0), Vector2(o1, o1 + half)]:
		var at: Vector3 = Vector3.ZERO
		var size: Vector3 = Vector3.ZERO
		at[along] = spans.x
		size[along] = half
		at.y = floor_y + 1.0
		size.y = head - floor_y - 2.0
		var near: float = plane + sign * stand_off
		at[thin] = near if sign > 0.0 else near - thick
		size[thin] = thick
		var leaf: AABB = AABB(at, size)
		var clash: bool = false
		for other: AABB in _blockers:
			if other.intersects(leaf.grow(1.0)) and not _flush_behind(other, plane, thin, sign):
				clash = true
				break
		if clash:
			continue
		_box(house, paint, leaf, false)
		# The pane: inset from the leaf's edges, standing just proud of both faces.
		var frame: float = _theme.leaf_frame
		var pane: AABB = leaf
		pane.position[along] += frame
		pane.size[along] -= frame * 2.0
		pane.position.y = floor_y + _theme.leaf_rail
		pane.size.y = head - frame - pane.position.y
		pane.position[thin] -= 0.4
		pane.size[thin] += 0.8
		if pane.size[along] > 0.0 and pane.size.y > 0.0:
			_box(house, &"glass", pane, false)

## True when `other` is the wall the leaf lies against (it ends at the plane).
static func _flush_behind(other: AABB, plane: float, thin: int, sign: float) -> bool:
	if sign > 0.0:
		return other.end[thin] <= plane + TINY
	return other.position[thin] >= plane - TINY

# ---- stairs: handrail and string ----

## Each flight's two long sides (P3-5). A side that stands against a wall (the
## house's outer wall, a blocker) gets an oak handrail on brackets, fixed to
## that wall. The other side, the open flank, has NO blocker: a body can step
## off it, so it gets no rail, which would look like a barrier it is not
## (WORLD_AUTHORING §12, "looks like it blocks = blocks"). It gets a painted
## string board along the nosings instead, which finishes the stepped edge.
## Collision is untouched either way.
func _banisters() -> void:
	var flights: Dictionary[String, Array] = {}
	for i: int in _blockers.size():
		var box: AABB = _blockers[i]
		if i == _skip or _shape(box) != Shape.TREAD:
			continue
		var along: int = 0 if box.size.x > box.size.z else 2
		var key: String = "%d:%.1f:%.1f" % [along, box.position[along], box.end[along]]
		if not flights.has(key):
			flights[key] = []
		flights[key].append(box)
	var keys: Array[String] = flights.keys()
	keys.sort()
	for key: String in keys:
		var treads: Array[AABB] = []
		for box: AABB in flights[key]:
			treads.append(box)
		if treads.size() < 2:
			continue
		treads.sort_custom(func(a: AABB, b: AABB) -> bool: return a.end.y < b.end.y)
		_flight_sides(treads)

func _flight_sides(treads: Array[AABB]) -> void:
	var first: AABB = treads[0]
	var last: AABB = treads[treads.size() - 1]
	var house: House = _house_of(first.get_center())
	var along: int = 0 if first.size.x > first.size.z else 2
	var run: int = 2 if along == 0 else 0
	# Which way the flight climbs along `run`, and each tread's nosing (its
	# downhill edge) on the line the rail and string follow.
	var climb: float = signf(last.get_center()[run] - first.get_center()[run])
	var low_nose: float = first.position[run] if climb > 0.0 else first.end[run]
	var high_nose: float = last.position[run] if climb > 0.0 else last.end[run]
	var half_run: float = first.size[run] * 0.5
	var rise: float = (last.end.y - first.end.y) / float(treads.size() - 1)
	var slope: float = rise / first.size[run]
	for side: float in [-1.0, 1.0]:
		var plane: float = first.end[along] if side > 0.0 else first.position[along]
		var across: Vector3 = Vector3.ZERO
		across[along] = side
		# A wall flush against this side, at a height above the treads.
		var probe: Vector3 = (first.get_center() + last.get_center()) * 0.5
		probe[along] = plane + side * 5.0
		probe.y = (first.end.y + last.end.y) * 0.5 + 100.0
		var walled: bool = _solid_at(probe)
		if walled:
			var rail_h: float = _theme.handrail_height
			var inset: float = _theme.handrail_wall_gap + _theme.handrail_width * 0.5
			var line: float = plane - side * inset
			# Past the bottom and top nosings by half a tread, on the slope.
			var from: Vector3 = Vector3.ZERO
			from[along] = line
			from[run] = low_nose - climb * half_run
			from.y = first.end.y + rail_h - slope * half_run
			var to: Vector3 = Vector3.ZERO
			to[along] = line
			to[run] = high_nose + climb * half_run
			to.y = last.end.y + rail_h + slope * half_run
			_beam(house, &"tread", from, to, across, _theme.handrail_width, _theme.handrail_depth)
			# Brackets from the wall to the rail's underside.
			var length: float = absf(to[run] - from[run])
			var count: int = maxi(2, int(length / maxf(_theme.handrail_bracket_spacing, 30.0)) + 1)
			for k: int in count:
				var t: float = (float(k) + 0.5) / float(count)
				var at: Vector3 = from.lerp(to, t)
				var bracket: AABB = AABB()
				var lo: float = minf(plane, at[along])
				bracket.position = Vector3.ZERO
				bracket.position[along] = lo
				bracket.position[run] = at[run] - 1.5
				bracket.position.y = at.y - _theme.handrail_depth * 0.5 - 7.0
				bracket.size = Vector3.ZERO
				bracket.size[along] = absf(plane - at[along])
				bracket.size[run] = 3.0
				bracket.size.y = 7.0
				_box(house, &"steel_dark", bracket, false)
		else:
			# The string: a painted board along the open side, its top a little
			# above the nosing line, from the floor at the bottom (where the line
			# meets it, one tread before the first nosing; the rest of the board is
			# under the floor) to the top nosing, which is level with the floor above.
			var board: float = _theme.string_height
			var line_out: float = plane + side * 1.5
			var from: Vector3 = Vector3.ZERO
			from[along] = line_out
			from[run] = low_nose - climb * first.size[run]
			from.y = first.end.y - rise + 4.0 - board * 0.5
			var to: Vector3 = Vector3.ZERO
			to[along] = line_out
			to[run] = high_nose
			to.y = last.end.y + 4.0 - board * 0.5
			_beam(house, &"trim", from, to, across, 3.0, board)

## A straight bar from `a` to `b` whose section is `width` across (along
## `across`, horizontal) and `height` tall, measured vertically: its sides stay
## plumb on a slope, as a handrail's and a stair string's do.
func _beam(house: House, key: StringName, a: Vector3, b: Vector3, across: Vector3,
		width: float, height: float) -> void:
	var w: Vector3 = across.normalized() * width * 0.5
	var h: Vector3 = Vector3(0.0, height * 0.5, 0.0)
	var dir: Vector3 = (b - a).normalized()
	var top: Vector3 = dir.cross(across.normalized())
	if top.y < 0.0:
		top = -top
	var flat: Vector3 = Vector3(dir.x, 0.0, dir.z).normalized()
	_quad(house, key, [a + w + h, b + w + h, b - w + h, a - w + h], top)
	_quad(house, key, [a + w - h, b + w - h, b - w - h, a - w - h], -top)
	_quad(house, key, [a + w + h, b + w + h, b + w - h, a + w - h], w.normalized())
	_quad(house, key, [a - w + h, b - w + h, b - w - h, a - w - h], -w.normalized())
	_quad(house, key, [a + w + h, a - w + h, a - w - h, a + w - h], -flat)
	_quad(house, key, [b + w + h, b - w + h, b - w - h, b + w - h], flat)

# ---- roof ----

## A hipped roof over the house: four slopes from the eaves (the footprint
## grown by the overhang) up to a point, a soffit under the overhang and a
## fascia round its edge. Purely on top of the flat roof slab.
func _roof(house: House) -> void:
	if house.top == -INF:
		return
	var pitch: float = deg_to_rad(_theme.roof_pitch_deg)
	if pitch <= 0.0:
		return
	var foot: Rect2 = house.rect # the outer wall faces (`_find_houses`)
	var eave: Rect2 = foot.grow(_theme.roof_overhang)
	var top: float = house.top
	var fascia: float = _theme.roof_fascia
	var run: float = minf(eave.size.x, eave.size.y) * 0.5
	var apex: Vector3 = Vector3(eave.get_center().x, top + run * tan(pitch), eave.get_center().y)
	var corners: Array[Vector3] = [
		Vector3(eave.position.x, top, eave.position.y),
		Vector3(eave.end.x, top, eave.position.y),
		Vector3(eave.end.x, top, eave.end.y),
		Vector3(eave.position.x, top, eave.end.y),
	]
	var inner: Array[Vector3] = [
		Vector3(foot.position.x, top - fascia, foot.position.y),
		Vector3(foot.end.x, top - fascia, foot.position.y),
		Vector3(foot.end.x, top - fascia, foot.end.y),
		Vector3(foot.position.x, top - fascia, foot.end.y),
	]
	for i: int in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		var edge: Vector3 = (b - a).normalized()
		var outward: Vector3 = edge.cross(Vector3.UP).normalized()
		if outward.dot(a - apex) < 0.0:
			outward = -outward
		var slope_normal: Vector3 = (outward * sin(pitch) + Vector3.UP * cos(pitch)).normalized()
		# Roof tile laid along the eave, rows running up the slope.
		var uvs: Array[Vector2] = []
		for p: Vector3 in [a, b, apex]:
			var horizontal: Vector3 = Vector3(p.x - a.x, 0.0, p.z - a.z)
			uvs.append(Vector2(p.dot(edge), horizontal.dot(outward) / cos(pitch)))
		_triangle(house, &"roof", [a, b, apex], uvs, slope_normal)
		# Fascia: the eave's edge, a board facing out.
		var low_a: Vector3 = a - Vector3(0.0, fascia, 0.0)
		var low_b: Vector3 = b - Vector3(0.0, fascia, 0.0)
		_quad(house, &"trim", [low_a, low_b, b, a], outward)
		# Soffit: the underside of the overhang, between the eave and the wall.
		var c: Vector3 = inner[i]
		var d: Vector3 = inner[(i + 1) % 4]
		_quad(house, &"trim", [low_a, c, d, low_b], Vector3.DOWN)

# ---- mesh building ----

func _tool(house: House, key: StringName) -> SurfaceTool:
	if not house.tools.has(key):
		var tool: SurfaceTool = SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		house.tools[key] = tool
	return house.tools[key]

## World-position UVs for a point on a face with this normal: horizontal faces
## take (x, z); walls take (along, -height) so a texture's top is up.
static func _uv(p: Vector3, normal: Vector3) -> Vector2:
	if absf(normal.y) > 0.5:
		return Vector2(p.x, p.z)
	if absf(normal.x) > absf(normal.z):
		return Vector2(p.z * signf(normal.x), -p.y)
	return Vector2(-p.x * signf(normal.z), -p.y)

## One flat quad. The corners may come in either turning order; they are wound
## so the face points along `normal` (Godot: clockwise seen from the front).
func _quad(house: House, key: StringName, corners: Array[Vector3], normal: Vector3) -> void:
	var tool: SurfaceTool = _tool(house, key)
	var turning: float = (corners[1] - corners[0]).cross(corners[2] - corners[0]).dot(normal)
	var order: Array[int] = QUAD_TURNED if turning > 0.0 else QUAD_AS_IS
	for index: int in order:
		tool.set_normal(normal)
		tool.set_uv(_uv(corners[index], normal))
		tool.add_vertex(corners[index])
	quads += 1

func _triangle(house: House, key: StringName, points: Array[Vector3], uvs: Array[Vector2],
		normal: Vector3) -> void:
	var tool: SurfaceTool = _tool(house, key)
	var turning: float = (points[1] - points[0]).cross(points[2] - points[0]).dot(normal)
	var order: Array[int] = TRI_TURNED if turning > 0.0 else TRI_AS_IS
	for index: int in order:
		tool.set_normal(normal)
		tool.set_uv(uvs[index])
		tool.add_vertex(points[index])

## A small box (trim, casing, leaf). `open_bottom` leaves its underside out
## (a skirting board stands on the floor).
func _box(house: House, key: StringName, box: AABB, open_bottom: bool) -> void:
	for axis: int in 3:
		for sign: float in [-1.0, 1.0]:
			if open_bottom and axis == 1 and sign < 0.0:
				continue
			var u: int = (axis + 1) % 3
			var w: int = (axis + 2) % 3
			var plane: float = box.end[axis] if sign > 0.0 else box.position[axis]
			var corners: Array[Vector3] = []
			for corner: Vector2 in [Vector2(box.position[u], box.position[w]),
					Vector2(box.end[u], box.position[w]), Vector2(box.end[u], box.end[w]),
					Vector2(box.position[u], box.end[w])]:
				var p: Vector3 = Vector3.ZERO
				p[axis] = plane
				p[u] = corner.x
				p[w] = corner.y
				corners.append(p)
			var normal: Vector3 = Vector3.ZERO
			normal[axis] = sign
			_quad(house, key, corners, normal)

func _commit(house: House) -> MeshInstance3D:
	if house.tools.is_empty():
		return null
	var mesh: ArrayMesh = ArrayMesh.new()
	var keys: Array[StringName] = house.tools.keys()
	keys.sort()
	for key: StringName in keys:
		var tool: SurfaceTool = house.tools[key]
		tool.set_material(_material(key, house.team))
		tool.commit(mesh)
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = mesh
	return node

## The theme's material for a key: `wall:<kind>` / `floor:<kind>` by room kind,
## `paint:<team>` the family colour, the rest by name.
func _material(key: StringName, team: StringName) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var text: String = String(key)
	var made: StandardMaterial3D = null
	if text.begins_with("wall:"):
		made = _theme.walls.get(StringName(text.trim_prefix("wall:")), _theme.wall_inside)
	elif text.begins_with("floor:"):
		made = _theme.floors.get(StringName(text.trim_prefix("floor:")), _theme.stair_tread)
	elif text.begins_with("paint:"):
		made = _theme.trim.duplicate() as StandardMaterial3D
		made.albedo_color = _theme.family_colour(StringName(text.trim_prefix("paint:")))
	else:
		match text:
			"wall_out": made = _theme.wall_outside
			"ceiling": made = _theme.ceiling
			"roof": made = _theme.roof
			"tread": made = _theme.stair_tread
			"riser", "trim", "fascia": made = _theme.trim
			"glass": made = _theme.glass
			"steel_dark": made = _theme.pen_bars
	if made == null:
		made = _theme.trim
	_materials[key] = made
	return made

## The floor finishes (FloorTint patches) as one mesh, a surface per finish,
## top faces only, with world UVs like the shell's.
static func floor_mesh(patches: Array[FloorTint.Patch], theme: ArtTheme, lift: float) -> ArrayMesh:
	var tools: Dictionary[StandardMaterial3D, SurfaceTool] = {}
	for patch: FloorTint.Patch in patches:
		var finish: StandardMaterial3D = theme.floors.get(ArtTheme.room_kind(patch.zone.id), null)
		if finish == null:
			continue
		if not tools.has(finish):
			var made: SurfaceTool = SurfaceTool.new()
			made.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[finish] = made
		var tool: SurfaceTool = tools[finish]
		var r: Rect2 = patch.footprint
		var y: float = patch.floor_y + lift
		var corners: Array[Vector3] = [Vector3(r.position.x, y, r.position.y),
			Vector3(r.end.x, y, r.position.y), Vector3(r.end.x, y, r.end.y),
			Vector3(r.position.x, y, r.end.y)]
		var turning: float = (corners[1] - corners[0]).cross(corners[2] - corners[0]).y
		var order: Array[int] = QUAD_TURNED if turning > 0.0 else QUAD_AS_IS
		for index: int in order:
			tool.set_normal(Vector3.UP)
			tool.set_uv(Vector2(corners[index].x, corners[index].z))
			tool.add_vertex(corners[index])
	if tools.is_empty():
		return null
	var mesh: ArrayMesh = ArrayMesh.new()
	for finish: StandardMaterial3D in tools:
		tools[finish].set_material(finish)
		tools[finish].commit(mesh)
	return mesh
