class_name TeamTellOverlay
extends Control
## The on-screen half of the D3 team tell (TeamTell, P2-4): (a) a small mark
## over each of YOUR OWN teammates (never over enemies), and (b) a corner
## minimap. Since PT4-5 the minimap shows every figure of both families
## (MAP_SHOWS_ENEMIES), each as its member's shape in its family colour,
## pointing the way it faces (`pointer`).
##
## Presentation only. GreyBoxMain hands it the drawn bodies each frame; it reads
## nothing from the simulation itself. The minimap draws the level's outline
## (MinimapOutline: lot, yards, houses, fence with its gates, PT4-4), only while
## a match is being played.

## One drawn body: feet position, drawn height, team, whether it is yours, the
## family member it is drawn as ("dad", "younger_girl" ...; "" if none) and the
## yaw it is drawn facing (atan2(x, z): 0 faces world +z).
class Body:
	var feet: Vector3 = Vector3.ZERO
	var height: float = 180.0
	var team: StringName = &""
	var mine: bool = false
	var member: StringName = &""
	var heading: float = 0.0

## REVIEW (PT4-5): both families on the minimap, bots and players alike. False
## goes back to P2-4's "own family only".
const MAP_SHOWS_ENEMIES: bool = true
const POINTER_RADIUS: float = 5.0
const POINTER_MINE_RADIUS: float = 6.5
const NOTCH_LENGTH: float = 4.0

const MARK_LIFT: float = 30.0  # above the head, world units
const MARK_SIZE: float = 9.0  # half-width of the mark, pixels, up close
const MARK_FAR_SCALE: float = 0.55
const MAP_SIZE: float = 210.0  # pixels, square
const MAP_MARGIN: float = 16.0
const MAP_TOP: float = 70.0  # below the status line

var camera: Camera3D = null
var own_team: StringName = &""
var bodies: Array[Body] = []
var tell: TeamTell = null
var colours: Dictionary[StringName, Color] = {}
## True only while a match is being played on this machine (GreyBoxMain sets it
## every frame): never on the menu, in the lobby or under the results (PT4-4).
var in_match: bool = false
## What the map shows (MinimapOutline, built once per level), and which world
## direction is "up" on the map (toward the enemy house, so yours is at the bottom).
var _outline: MinimapOutline = null
var _up: Vector2 = Vector2(0.0, -1.0)

const MAP_BACK: Color = Color(0.06, 0.06, 0.07, 0.72)
const MAP_LOT: Color = Color(0.22, 0.27, 0.2, 0.85)
const MAP_YARD: Color = Color(0.28, 0.35, 0.25, 0.9)
const MAP_HOUSE: Color = Color(0.52, 0.5, 0.46, 0.95)
const MAP_WALL: Color = Color(0.95, 0.91, 0.82)
const MAP_FENCE: Color = Color(0.2, 0.13, 0.08)

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## The map's world (null clears it), and the two teams' spawn centres (own
## first) to turn the map so the player's house is at the bottom.
func set_level(outline: MinimapOutline, own_spawn: Vector3, enemy_spawn: Vector3) -> void:
	_outline = outline
	# Snapped to the nearer world axis: the houses are laid out square to the
	# axes, and the spawn centres are not exactly opposite each other.
	var toward: Vector2 = Vector2(enemy_spawn.x - own_spawn.x, enemy_spawn.z - own_spawn.z)
	if absf(toward.x) >= absf(toward.y):
		_up = Vector2(signf(toward.x) if toward.x != 0.0 else 1.0, 0.0)
	else:
		_up = Vector2(0.0, signf(toward.y))

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if tell == null:
		return
	if tell.marker:
		_draw_marks()
	if tell.minimap and in_match and _outline != null and _outline.lot.size != Vector2.ZERO:
		_draw_map()

func _draw_marks() -> void:
	if camera == null or own_team == &"":
		return
	var shade: Color = Color(0.08, 0.08, 0.08, 0.85)
	for body: Body in bodies:
		if body.mine or body.team != own_team:
			continue
		var top: Vector3 = body.feet + Vector3(0.0, body.height + MARK_LIFT, 0.0)
		if camera.is_position_behind(top):
			continue
		var at: Vector2 = camera.unproject_position(top)
		# A small point-down triangle: a pointer, not a badge. Shrinks with
		# distance (full at 10 m, MARK_FAR_SCALE from 30 m) so a far teammate's
		# mark is not bigger than their head.
		var far: float = clampf((camera.global_position.distance_to(top) - 1000.0) / 2000.0, 0.0, 1.0)
		var s: float = MARK_SIZE * lerpf(1.0, MARK_FAR_SCALE, far)
		var tri: PackedVector2Array = PackedVector2Array([
			at + Vector2(-s, -s * 1.1), at + Vector2(s, -s * 1.1), at + Vector2(0.0, s * 0.6)])
		var rim: PackedVector2Array = PackedVector2Array([
			at + Vector2(-s - 2.0, -s * 1.1 - 1.5), at + Vector2(s + 2.0, -s * 1.1 - 1.5),
			at + Vector2(0.0, s * 0.6 + 2.5)])
		draw_colored_polygon(rim, shade)
		draw_colored_polygon(tri, colours.get(own_team, Color.WHITE))

func _draw_map() -> void:
	var box: Rect2 = Rect2(Vector2(size.x - MAP_SIZE - MAP_MARGIN, MAP_TOP), Vector2(MAP_SIZE, MAP_SIZE))
	draw_rect(box, MAP_BACK)
	draw_rect(box, Color(1.0, 1.0, 1.0, 0.25), false, 1.0)
	var lot: Rect2 = _outline.lot
	var fit: float = (MAP_SIZE - 16.0) / maxf(lot.size.x, lot.size.y)
	var centre: Vector2 = lot.get_center()
	var middle: Vector2 = box.get_center()
	# Lot, yards a shade lighter, houses lighter still with cream walls, then the
	# fence as a dark line broken at its gates.
	draw_colored_polygon(_map_rect(lot, centre, middle, fit), MAP_LOT)
	for yard: Rect2 in _outline.yards:
		draw_colored_polygon(_map_rect(yard, centre, middle, fit), MAP_YARD)
	for house: Rect2 in _outline.houses:
		var corners: PackedVector2Array = _map_rect(house, centre, middle, fit)
		draw_colored_polygon(corners, MAP_HOUSE)
		corners.append(corners[0])
		draw_polyline(corners, MAP_WALL, 2.0)
	for panel: Vector2 in _outline.fence_panels:
		draw_line(_to_map(Vector2(_outline.fence_x, panel.x), centre, middle, fit),
			_to_map(Vector2(_outline.fence_x, panel.y), centre, middle, fit), MAP_FENCE, 3.0)
	var lot_edge: PackedVector2Array = _map_rect(lot, centre, middle, fit)
	lot_edge.append(lot_edge[0])
	draw_polyline(lot_edge, Color(MAP_WALL, 0.45), 1.0)
	# Everyone else first, your own body last so it sits on top.
	for pass_mine: bool in [false, true]:
		for body: Body in bodies:
			if body.mine != pass_mine:
				continue
			if not body.mine and body.team != own_team and not MAP_SHOWS_ENEMIES:
				continue
			var at: Vector2 = _to_map(Vector2(body.feet.x, body.feet.z), centre, middle, fit)
			_draw_pointer(at, pointer(body.member, body.mine, body.heading, _up),
				colours.get(body.team, Color.WHITE))

## One figure's pointer on the map, `at` its map position.
func _draw_pointer(at: Vector2, shape: Dictionary, fill: Color) -> void:
	var rim: Color = Color(0.05, 0.05, 0.05, 0.9)
	var mine: bool = shape[&"mine"]
	var edge: Color = UiTheme.CREAM if mine else rim
	var edge_width: float = 2.0 if mine else 1.5
	var points: PackedVector2Array = shape[&"points"]
	var radius: float = shape[&"radius"]
	if points.is_empty():
		draw_circle(at, radius + edge_width, edge)
		draw_circle(at, radius, fill)
	else:
		var placed: PackedVector2Array = PackedVector2Array()
		for point: Vector2 in points:
			placed.append(at + point)
		draw_colored_polygon(placed, fill)
		placed.append(placed[0])
		draw_polyline(placed, edge, edge_width, true)
	var notch: PackedVector2Array = shape[&"notch"]
	if notch.size() == 2:
		draw_line(at + notch[0], at + notch[1], edge, 2.5 if mine else 2.0)

## The minimap pointer for one figure (PT4-5), in map pixels about its map
## position: dad a square, mom a diamond, a son (any `*_boy`) a triangle whose
## apex is the facing, a daughter (any `*_girl`) a circle; anyone else a circle.
## Every shape but the triangle carries a short notch out the way it faces.
## `heading` is the drawn yaw (atan2(x, z)); `up` the world x/z direction the
## map shows at the top. Your own is bigger.
##
## Returns {shape, radius, mine, facing (map unit vector), points (polygon,
## empty for a circle), notch ([from, to], empty for the triangle), tip (the
## point that shows the facing: apex or notch end)}.
static func pointer(member: StringName, mine: bool, heading: float, up: Vector2) -> Dictionary:
	var radius: float = POINTER_MINE_RADIUS if mine else POINTER_RADIUS
	var facing: Vector2 = turn(Vector2(sin(heading), cos(heading)), up).normalized()
	var side: Vector2 = Vector2(-facing.y, facing.x)
	var text: String = String(member)
	var shape: StringName = &"circle"
	if member == &"dad":
		shape = &"square"
	elif member == &"mom":
		shape = &"diamond"
	elif text.ends_with("_boy"):
		shape = &"triangle"
	var points: PackedVector2Array = PackedVector2Array()
	var notch: PackedVector2Array = PackedVector2Array()
	var tip: Vector2 = facing * (radius + NOTCH_LENGTH)
	match shape:
		&"square":
			var r: float = radius * 0.9
			points = PackedVector2Array([(facing + side) * r, (facing - side) * r,
				(-facing - side) * r, (-facing + side) * r])
		&"diamond":
			points = PackedVector2Array([facing * radius * 1.25, side * radius,
				-facing * radius * 1.25, -side * radius])
			tip = facing * (radius * 1.25 + NOTCH_LENGTH)
		&"triangle":
			tip = facing * radius * 1.5
			points = PackedVector2Array([tip, -facing * radius * 0.8 + side * radius,
				-facing * radius * 0.8 - side * radius])
	if shape != &"triangle":
		var from: Vector2 = facing * (radius * 1.25 if shape == &"diamond" else radius)
		notch = PackedVector2Array([from, tip])
	return {&"shape": shape, &"radius": radius, &"mine": mine, &"facing": facing,
		&"points": points, &"notch": notch, &"tip": tip}

## A world x/z rectangle's four corners in map pixels.
func _map_rect(rect: Rect2, centre: Vector2, middle: Vector2, fit: float) -> PackedVector2Array:
	var corners: PackedVector2Array = PackedVector2Array()
	for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
			Vector2(rect.position.x, rect.end.y)]:
		corners.append(_to_map(corner, centre, middle, fit))
	return corners

## World x/z -> map pixels, turned so `_up` points up the screen.
func _to_map(world: Vector2, centre: Vector2, middle: Vector2, fit: float) -> Vector2:
	return middle + turn(world - centre, _up) * fit

## A world x/z direction in map axes: `up` maps to screen up (-y).
static func turn(world: Vector2, up: Vector2) -> Vector2:
	var right: Vector2 = Vector2(-up.y, up.x)
	return Vector2(world.dot(right), -world.dot(up))
