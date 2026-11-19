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
##
## PT5-2: the map is shown in every match (no longer only with D3 option (b)),
## as a cream card, north-up: the floor the player is on only ("Ground" /
## "Upstairs"), each house's footprint in its family colour, the family names on
## their lots, vault and jail icons, loose cash; bodies on the other floor faded.
## D3 option (b) `tell.minimap` now means "teammates only": enemies are hidden.
## Holding the map key (Tab) shows the same map big in the middle.

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

## PT5-2 map card: a share of the viewport's height (Tab held: the big one),
## top-right under the cash bar's names, never wider than MAP_MAX_WIDTH of the
## screen. A header row carries the floor label.
const MAP_HEIGHT_SHARE: float = 0.2
const MAP_BIG_SHARE: float = 0.6
const MAP_MAX_WIDTH: float = 0.3
const MAP_BIG_MAX_WIDTH: float = 0.9
const MAP_MARGIN: float = 16.0
const MAP_TOP: float = 130.0  # clear of the cash bar, its names and "YOU"
const MAP_PAD: float = 8.0
const MAP_HEADER: float = 20.0
## A body on the other floor: faded and smaller, so it is not taken for one on yours.
const OTHER_FLOOR_ALPHA: float = 0.35
const OTHER_FLOOR_SCALE: float = 0.7

var camera: Camera3D = null
var own_team: StringName = &""
var bodies: Array[Body] = []
var tell: TeamTell = null
var colours: Dictionary[StringName, Color] = {}
## True only while a match is being played on this machine (GreyBoxMain sets it
## every frame): never on the menu, in the lobby or under the results (PT4-4).
var in_match: bool = false
## Bundles at rest or in flight (not carried), sim positions; GreyBoxMain sets
## them from the confirmed world each frame (PT5-2).
var loose_cash: Array[Vector3] = []
## The big map while the map key is held (PT5-2).
var big: bool = false
## Family display names by team, for the lots (PT5-2).
var names: Dictionary[StringName, String] = {}
## What the map shows (MinimapOutline, built once per level). North-up and fixed
## (PT5-2): world -z is the top of the map on every machine.
var _outline: MinimapOutline = null
const UP: Vector2 = Vector2(0.0, -1.0)
var _up: Vector2 = UP
var _card: StyleBoxFlat = null

const MAP_LOT: Color = Color(0.60, 0.68, 0.52)
const MAP_YARD: Color = Color(0.66, 0.74, 0.57)
const MAP_HOUSE_SHARE: float = 0.45  # family colour over cream

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = StyleBoxFlat.new()
	_card.bg_color = UiTheme.CREAM
	_card.border_color = UiTheme.CHARCOAL
	_card.set_border_width_all(2)
	_card.set_corner_radius_all(UiTheme.CORNER)
	_card.anti_aliasing = true
	_card.shadow_color = UiTheme.SHADOW_COLOUR
	_card.shadow_size = UiTheme.SHADOW_SIZE
	_card.shadow_offset = Vector2(0.0, UiTheme.SHADOW_OFFSET)

## The map's world (null clears it).
func set_level(outline: MinimapOutline) -> void:
	_outline = outline

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if tell == null:
		return
	if tell.marker:
		_draw_marks()
	if in_match and _outline != null and _outline.lot.size != Vector2.ZERO:
		_draw_map()

## The map card's rect on a `viewport`-sized screen (PT5-2): small top-right,
## or centred and big while the map key is held. Height is a share of the
## screen's; width follows the lot's shape, capped.
static func card_rect(viewport: Vector2, lot: Rect2, held: bool) -> Rect2:
	var tall: float = viewport.y * (MAP_BIG_SHARE if held else MAP_HEIGHT_SHARE)
	var inner_h: float = tall - MAP_PAD * 2.0 - MAP_HEADER
	var aspect: float = lot.size.x / maxf(lot.size.y, 1.0)
	var wide: float = minf(inner_h * aspect + MAP_PAD * 2.0,
		viewport.x * (MAP_BIG_MAX_WIDTH if held else MAP_MAX_WIDTH))
	if held:
		return Rect2((viewport - Vector2(wide, tall)) * 0.5, Vector2(wide, tall))
	return Rect2(Vector2(viewport.x - wide - MAP_MARGIN, MAP_TOP), Vector2(wide, tall))

## The floor this machine's body is on (0 ground, 1 upstairs), from its feet.
func own_floor() -> int:
	for body: Body in bodies:
		if body.mine:
			return MinimapOutline.floor_of(body.feet.y, _outline.upper_floor_y)
	return 0

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
	var box: Rect2 = card_rect(size, _outline.lot, big)
	draw_style_box(_card, box)
	var storey: int = own_floor()
	var scale_up: float = box.size.y / (size.y * MAP_HEIGHT_SHARE)  # 1 small, 3 big
	var font: Font = UiTheme.body_bold()
	var label_size: int = int(round(UiTheme.SMALL_SIZE * (1.0 + (scale_up - 1.0) * 0.4)))
	draw_string(font, box.position + Vector2(MAP_PAD + 2.0, MAP_PAD + label_size * 0.95),
		"Upstairs" if storey == 1 else "Ground", HORIZONTAL_ALIGNMENT_LEFT, -1.0, label_size,
		UiTheme.CHARCOAL)
	var area: Rect2 = Rect2(box.position + Vector2(MAP_PAD, MAP_PAD + MAP_HEADER * minf(scale_up, 1.6)),
		box.size - Vector2(MAP_PAD * 2.0, MAP_PAD * 2.0 + MAP_HEADER * minf(scale_up, 1.6)))
	var lot: Rect2 = _outline.lot
	var fit: float = minf(area.size.x / lot.size.x, area.size.y / lot.size.y)
	var centre: Vector2 = lot.get_center()
	var middle: Vector2 = area.get_center()
	# Lot, yards a shade lighter, each house's footprint on this floor in its
	# family colour, the fence as a dark line broken at its gates.
	draw_colored_polygon(_map_rect(lot, centre, middle, fit), MAP_LOT)
	for yard: Rect2 in _outline.yards:
		draw_colored_polygon(_map_rect(yard, centre, middle, fit), MAP_YARD)
	for foot: MinimapOutline.Footprint in _outline.footprints_on(storey):
		var family: Color = colours.get(foot.team, UiTheme.GREY)
		var corners: PackedVector2Array = _map_rect(foot.rect, centre, middle, fit)
		draw_colored_polygon(corners, UiTheme.CREAM.lerp(family, MAP_HOUSE_SHARE))
		corners.append(corners[0])
		draw_polyline(corners, family.darkened(0.35), 2.0)
	for panel: Vector2 in _outline.fence_panels:
		draw_line(_to_map(Vector2(_outline.fence_x, panel.x), centre, middle, fit),
			_to_map(Vector2(_outline.fence_x, panel.y), centre, middle, fit), UiTheme.CHARCOAL, 2.5)
	var lot_edge: PackedVector2Array = _map_rect(lot, centre, middle, fit)
	lot_edge.append(lot_edge[0])
	draw_polyline(lot_edge, Color(UiTheme.CHARCOAL, 0.5), 1.0)
	# Family names on their own lots.
	var name_size: int = int(round(11.0 * (1.0 + (scale_up - 1.0) * 0.5)))
	for i: int in _outline.houses.size():
		var team: StringName = _outline.house_teams[i]
		var text: String = names.get(team, String(team))
		var spot: Vector2 = _to_map(_outline.name_spot(_outline.houses[i]), centre, middle, fit)
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, name_size).x
		draw_string(font, spot + Vector2(-width * 0.5, name_size * 0.35), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, name_size, colours.get(team, UiTheme.CHARCOAL).darkened(0.45))
	# Vault and jail icons on this floor.
	var icon: float = 5.0 * (1.0 + (scale_up - 1.0) * 0.5)
	for mark: MinimapOutline.Mark in _outline.marks_on(storey):
		_draw_icon(_to_map(mark.at, centre, middle, fit), mark.kind, icon)
	# Loose cash on this floor.
	for cash: Vector3 in loose_cash:
		if MinimapOutline.floor_of(cash.y, _outline.upper_floor_y) != storey:
			continue
		var at: Vector2 = _to_map(Vector2(cash.x, cash.z), centre, middle, fit)
		draw_circle(at, icon * 0.75, UiTheme.CHARCOAL)
		draw_circle(at, icon * 0.55, UiTheme.CASH_GREEN)
	# Everyone else first, your own body last so it sits on top; a body on the
	# other floor faded and smaller.
	var body_scale: float = 1.0 + (scale_up - 1.0) * 0.4
	for pass_mine: bool in [false, true]:
		for body: Body in bodies:
			if body.mine != pass_mine:
				continue
			if not body.mine and body.team != own_team and (not MAP_SHOWS_ENEMIES or tell.minimap):
				continue
			var other: bool = MinimapOutline.floor_of(body.feet.y, _outline.upper_floor_y) != storey
			var at: Vector2 = _to_map(Vector2(body.feet.x, body.feet.z), centre, middle, fit)
			_draw_pointer(at, pointer(body.member, body.mine, body.heading, _up),
				colours.get(body.team, Color.WHITE),
				body_scale * (OTHER_FLOOR_SCALE if other else 1.0),
				OTHER_FLOOR_ALPHA if other else 1.0)

## A vault (a dark safe with a cream slot) or a jail (a square with three bars)
## at `at`, `half` its half-size in pixels.
func _draw_icon(at: Vector2, kind: StringName, half: float) -> void:
	var square: Rect2 = Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0)
	if kind == &"vault":
		draw_rect(square.grow(1.0), UiTheme.CREAM)
		draw_rect(square, UiTheme.CHARCOAL)
		draw_line(at + Vector2(-half * 0.55, 0.0), at + Vector2(half * 0.55, 0.0), UiTheme.CREAM, 1.5)
	else:
		draw_rect(square.grow(1.0), UiTheme.CREAM)
		draw_rect(square, UiTheme.CHARCOAL, false, 1.5)
		for step: int in 3:
			var x: float = at.x - half * 0.5 + half * 0.5 * step
			draw_line(Vector2(x, at.y - half), Vector2(x, at.y + half), UiTheme.CHARCOAL, 1.5)

## One figure's pointer on the map, `at` its map position, drawn `grow` times
## its size and `alpha` opaque.
func _draw_pointer(at: Vector2, shape: Dictionary, fill: Color, grow: float = 1.0,
		alpha: float = 1.0) -> void:
	var rim: Color = Color(0.05, 0.05, 0.05, 0.9 * alpha)
	var mine: bool = shape[&"mine"]
	var edge: Color = Color(UiTheme.CREAM, alpha) if mine else rim
	var edge_width: float = 2.0 if mine else 1.5
	fill = Color(fill, alpha)
	var points: PackedVector2Array = shape[&"points"]
	var radius: float = shape[&"radius"] * grow
	if points.is_empty():
		draw_circle(at, radius + edge_width, edge)
		draw_circle(at, radius, fill)
	else:
		var placed: PackedVector2Array = PackedVector2Array()
		for point: Vector2 in points:
			placed.append(at + point * grow)
		draw_colored_polygon(placed, fill)
		placed.append(placed[0])
		draw_polyline(placed, edge, edge_width, true)
	var notch: PackedVector2Array = shape[&"notch"]
	if notch.size() == 2:
		draw_line(at + notch[0] * grow, at + notch[1] * grow, edge, 2.5 if mine else 2.0)

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
