class_name TeamTellOverlay
extends Control
## The on-screen half of the D3 team tell (TeamTell, P2-4): (a) a small mark
## over each of YOUR OWN teammates, and (b) a corner minimap showing only your
## own teammates and you. Enemies are never drawn by either: that is the point
## of D3, a still enemy should be hard to tell from your own family.
##
## Presentation only. GreyBoxMain hands it the drawn bodies each frame; it reads
## nothing from the simulation itself. The minimap is the minimal one P2-4 asks
## for; P5-2 makes the final HUD.

## One drawn body: feet position, drawn height, team, and whether it is yours.
class Body:
	var feet: Vector3 = Vector3.ZERO
	var height: float = 180.0
	var team: StringName = &""
	var mine: bool = false

const MARK_LIFT: float = 30.0  # above the head, world units
const MARK_SIZE: float = 9.0  # half-width of the mark, pixels, up close
const MARK_FAR_SCALE: float = 0.55
const MAP_SIZE: float = 210.0  # pixels, square
const MAP_MARGIN: float = 16.0
const MAP_TOP: float = 70.0  # below the status line
const DOT_RADIUS: float = 4.5

var camera: Camera3D = null
var own_team: StringName = &""
var bodies: Array[Body] = []
var tell: TeamTell = null
var colours: Dictionary[StringName, Color] = {}
## The world the map shows (x/z), the rooms drawn on it, and which world
## direction is "up" on the map (toward the enemy house, so yours is at the bottom).
var _lot: Rect2 = Rect2()
var _rooms: Array[Rect2] = []
var _up: Vector2 = Vector2(0.0, -1.0)

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## The map's world: the lot's ground box, the indoor rooms, and the two teams'
## spawn centres (own first) to turn the map so the player's house is at the
## bottom.
func set_level(lot: AABB, zones: Array[ZoneDef], own_spawn: Vector3, enemy_spawn: Vector3) -> void:
	_lot = Rect2(lot.position.x, lot.position.z, lot.size.x, lot.size.z)
	_rooms.clear()
	for zone: ZoneDef in zones:
		if zone.outdoor or zone.owner_team == &"":
			continue
		_rooms.append(Rect2(zone.bounds.position.x, zone.bounds.position.z,
			zone.bounds.size.x, zone.bounds.size.z))
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
	if tell.minimap and _lot.size != Vector2.ZERO:
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
	draw_rect(box, Color(0.06, 0.06, 0.07, 0.72))
	draw_rect(box, Color(1.0, 1.0, 1.0, 0.25), false, 1.0)
	var fit: float = (MAP_SIZE - 16.0) / maxf(_lot.size.x, _lot.size.y)
	var centre: Vector2 = _lot.get_center()
	var middle: Vector2 = box.get_center()
	for room: Rect2 in _rooms:
		var corners: PackedVector2Array = PackedVector2Array()
		for corner: Vector2 in [room.position, Vector2(room.end.x, room.position.y), room.end,
				Vector2(room.position.x, room.end.y), room.position]:
			corners.append(_to_map(corner, centre, middle, fit))
		draw_polyline(corners, Color(0.85, 0.82, 0.76, 0.35), 1.0)
	var own: Color = colours.get(own_team, Color.WHITE)
	for body: Body in bodies:
		if body.team != own_team or body.mine:
			continue
		var at: Vector2 = _to_map(Vector2(body.feet.x, body.feet.z), centre, middle, fit)
		draw_circle(at, DOT_RADIUS + 1.5, Color(0.05, 0.05, 0.05, 0.9))
		draw_circle(at, DOT_RADIUS, own)
	for body: Body in bodies:
		if not body.mine:
			continue
		var at: Vector2 = _to_map(Vector2(body.feet.x, body.feet.z), centre, middle, fit)
		var facing: Vector2 = Vector2(0.0, -1.0)
		if camera != null:
			var look: Vector3 = -camera.global_transform.basis.z
			facing = _turn(Vector2(look.x, look.z))
			facing = facing.normalized() if facing.length() > 0.01 else Vector2(0.0, -1.0)
		var side: Vector2 = Vector2(-facing.y, facing.x)
		var arrow: PackedVector2Array = PackedVector2Array([
			at + facing * 8.0, at - facing * 5.0 + side * 5.5, at - facing * 5.0 - side * 5.5])
		draw_colored_polygon(arrow, Color(0.05, 0.05, 0.05, 0.9))
		draw_colored_polygon(PackedVector2Array([
			at + facing * 6.0, at - facing * 3.5 + side * 3.8, at - facing * 3.5 - side * 3.8]),
			Color(1.0, 1.0, 1.0))

## World x/z -> map pixels, turned so `_up` points up the screen.
func _to_map(world: Vector2, centre: Vector2, middle: Vector2, fit: float) -> Vector2:
	return middle + _turn(world - centre) * fit

## A world x/z direction in map axes: `_up` maps to screen up (-y).
func _turn(world: Vector2) -> Vector2:
	var right: Vector2 = Vector2(-_up.y, _up.x)
	return Vector2(world.dot(right), -world.dot(_up))
