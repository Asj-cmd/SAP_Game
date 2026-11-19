class_name FamilyLineup
extends RefCounted
## The round-start lineup (PT4-2). While the confirmed world counts down, the
## local seat looks through a fixed camera standing out in front of its own
## family's row on the front lawn; the family's name shows above the row and
## each member's role and who plays it under each body. Back to the chase camera
## when play starts.
##
## Presentation only. The sim's countdown already holds everyone still, the row
## is the level's spawn points, and facing the camera is drawn (SimEntity has no
## facing). Nothing here writes to a world.

## The camera stands this far out from the row's middle, this high above the
## lawn, looking at a point this high over the row (the row sits in the lower
## half of the frame, under the round headline). The street railings are within
## their cut-away reach of a camera this far out (fence_cutaway.gdshader).
const DISTANCE: float = 600.0
const EYE: float = 170.0
const LOOK: float = 200.0
const FOV: float = 50.0
## Where the family name sits: its bottom edge this many pixels above a point
## this high over the row (just over the tallest head, 180).
const HEAD: float = 190.0
const NAME_GAP: float = 10.0
const LABEL_GAP: float = 6.0
const LABEL_SIZE: int = 20

var active: bool = false
var _camera: Camera3D = null
var _overlay: Control = null
var _title: Label = null
var _labels: Array[Label] = []

## The row's middle on the lawn and the way out of the house, from the spawn
## points of the seats in play and the family's cash (which is indoors): the
## outward axis is whichever of x or z the row lies further along from the cash.
static func frame(spawns: Array[Vector3], indoors: Vector3, ground_lift: float) -> Array[Vector3]:
	var middle: Vector3 = Vector3.ZERO
	for point: Vector3 in spawns:
		middle += point
	if not spawns.is_empty():
		middle /= float(spawns.size())
	middle.y -= ground_lift
	var away: Vector3 = middle - indoors
	var out: Vector3 = Vector3(signf(away.x), 0.0, 0.0) if absf(away.x) > absf(away.z) \
		else Vector3(0.0, 0.0, signf(away.z))
	return [middle, out]

## How a body is named wherever a player is named (PT5-1): "<Role> - <name>",
## " (you)" after the local player's own name, "<Role> - Bot" for a bot; a
## player with no name is "Player". "Dad - Sam (you)", "Mom - Bot".
static func player_text(role: String, shown: String, is_you: bool, is_bot: bool) -> String:
	if is_bot:
		return "%s - Bot" % role
	var who: String = shown if shown != "" else LobbyState.DEFAULT_PLAYER
	return "%s - %s%s" % [role, who, " (you)" if is_you else ""]

## The name the lobby view shows for the person in member `slot` of `team_id`,
## "" for a bot, an empty seat or no view.
static func seat_name(view: LobbyState, team_id: StringName, slot: int) -> String:
	if view == null:
		return ""
	var seat: LobbyState.Seat = view.seat_at(team_id, slot)
	if seat == null or seat.occupant != LobbyState.Occupant.HUMAN:
		return ""
	return seat.name

## Every member of `team_id` as the lobby view has them, one `player_text` each
## in slot order; an empty seat reads "<Role> - (empty)". `my_team` / `my_slot`
## mark the local player, whose own name is `own_name` until the view names them.
static func roster(view: LobbyState, team_id: StringName, my_team: StringName, my_slot: int,
		own_name: String = "") -> Array[String]:
	var lines: Array[String] = []
	if view == null:
		return lines
	var slots: Array[int] = []
	for seat: LobbyState.Seat in view.seats:
		if seat.team == team_id:
			slots.append(seat.slot)
	slots.sort()
	var words: Array[String] = slot_words(team_id, slots.size())
	for i: int in slots.size():
		var seat: LobbyState.Seat = view.seat_at(team_id, slots[i])
		var role: String = words[i] if i < words.size() else "Member %d" % (i + 1)
		var you: bool = team_id == my_team and seat.slot == my_slot
		if seat.occupant == LobbyState.Occupant.EMPTY and not you:
			lines.append("%s - (empty)" % role)
			continue
		var shown: String = seat.name if seat.name != "" else (own_name if you else "")
		lines.append(player_text(role, shown, you, seat.occupant == LobbyState.Occupant.BOT and not you))
	return lines

## The role words of a family's first `count` slots (slot n draws member n of
## the theme's order, without the kid swap): the "Play as" pickers (PT4-3).
static func slot_words(team_id: StringName, count: int) -> Array[String]:
	var theme: ArtTheme = ArtTheme.current()
	var ids: Array[StringName] = []
	for slot: int in count:
		var member: FamilyMember = theme.member_for(team_id, slot, false)
		ids.append(member.id if member != null else &"player")
	return role_words(ids)

## "Dad", "Mom", "Daughter", "Son" per member id, in the order given; "Elder" /
## "Younger" in front only when two children in the row share a sex.
static func role_words(member_ids: Array[StringName]) -> Array[String]:
	var girls: int = 0
	var boys: int = 0
	for id: StringName in member_ids:
		if String(id).ends_with("_girl"):
			girls += 1
		elif String(id).ends_with("_boy"):
			boys += 1
	var words: Array[String] = []
	for id: StringName in member_ids:
		var text: String = String(id)
		var word: String = text.capitalize()
		var twins: bool = false
		if text == "dad":
			word = "Dad"
		elif text == "mom":
			word = "Mom"
		elif text.ends_with("_girl"):
			word = "Daughter"
			twins = girls > 1
		elif text.ends_with("_boy"):
			word = "Son"
			twins = boys > 1
		if twins:
			word = ("Elder " if text.begins_with("elder") else "Younger ") + word
		words.append(word)
	return words

## Builds the overlay under `layer` (once).
func attach(layer: CanvasLayer) -> void:
	if _overlay != null and is_instance_valid(_overlay):
		return
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	layer.add_child(_overlay)
	_title = Label.new()
	_title.theme = UiTheme.current()
	_title.theme_type_variation = UiTheme.HUD_BIG
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay.add_child(_title)
	_labels = []

## Shows the lineup this frame: the camera in `viewport` in front of the row,
## the name above it, and one label per body. `bodies` holds per body a
## "foot" (its drawn feet, Vector3) and a "text" ("Dad - Sam (you)", PT5-1).
func show(viewport: Node, middle: Vector3, out: Vector3, family_name: String,
		colour: Color, bodies: Array[Dictionary]) -> void:
	if _camera == null or not is_instance_valid(_camera) or _camera.get_parent() != viewport:
		_camera = Camera3D.new()
		_camera.fov = FOV
		_camera.far = 20000.0
		viewport.add_child(_camera)
	_camera.global_position = middle + out * DISTANCE + Vector3.UP * EYE
	_camera.look_at(middle + Vector3.UP * LOOK, Vector3.UP)
	_camera.current = true
	active = true
	if _overlay == null:
		return
	_overlay.visible = true

	var top: Vector2 = _camera.unproject_position(middle + Vector3.UP * HEAD)
	_title.text = family_name.to_upper()
	_title.add_theme_color_override("font_color", colour)
	_title.reset_size()
	_title.position = Vector2(top.x - _title.size.x * 0.5, top.y - NAME_GAP - _title.size.y)

	while _labels.size() < bodies.size():
		var label: Label = Label.new()
		label.theme = UiTheme.current()
		label.theme_type_variation = UiTheme.HUD
		label.add_theme_font_size_override("font_size", LABEL_SIZE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_overlay.add_child(label)
		_labels.append(label)
	for i: int in _labels.size():
		var label: Label = _labels[i]
		label.visible = i < bodies.size()
		if not label.visible:
			continue
		var foot: Vector3 = bodies[i]["foot"]
		var at: Vector2 = _camera.unproject_position(foot)
		label.text = String(bodies[i]["text"])
		label.reset_size()
		label.position = Vector2(at.x - label.size.x * 0.5, at.y + LABEL_GAP)

## Ends the lineup: the overlay hides and `chase` is the seat's camera again.
func hide(chase: Camera3D) -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.visible = false
	if not active:
		return
	active = false
	if chase != null and is_instance_valid(chase):
		chase.current = true
