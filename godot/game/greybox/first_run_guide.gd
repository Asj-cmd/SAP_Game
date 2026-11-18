class_name FirstRunGuide
extends Control
## The first-run guide (P5-5): a controls strip along the bottom and a step line
## under the top bar. It is a plain step list over a normal match, not a tutorial
## mode: it reads the confirmed world for the local actor and never touches the
## simulation, the camera or the player's control.
##
## Presentation only. Off in capture, pilot and net-smoke runs.

const STEP_TEXTS: Array[String] = [
	"Move with %s, look with the mouse.",
	"Cross the fence into the other family's yard.",
	"Find their cash and grab it (left mouse button).",
	"Carry it back into your own house.",
	"Catch intruders at home with %s. If you are caught, a teammate frees you.",
]
const STEP_HELP: Array[String] = [
	"Keep going; the houses are a short walk away.",
	"The other family's house is across the fence, on the far side of the street.",
	"Cash sits in the rooms of their house. Walk up to a bundle and click.",
	"Your own house is the one in your colour. Stay low if someone is chasing you.",
	"",
]
const MOVE_GOAL: float = 300.0
const HELP_AFTER: float = 20.0
const FINAL_SECONDS: float = 8.0
const STRIP_SECONDS: float = 60.0

var _line: Label = null
var _strip: Label = null
var _active: bool = false
var _step: int = 0
var _step_time: float = 0.0
var _match_time: float = 0.0
var _moved: float = 0.0
var _last_position: Vector3 = Vector3.ZERO
var _have_last: bool = false
var _score_at_step: int = 0

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line = _label(20)
	_strip = _label(16)

func _label(size: int) -> Label:
	var label: Label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.theme = UiTheme.current()
	label.theme_type_variation = UiTheme.HUD
	label.add_theme_font_size_override("font_size", size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

## A new match is starting: the strip timer and the steps start over.
func begin() -> void:
	_step = 0
	_step_time = 0.0
	_match_time = 0.0
	_moved = 0.0
	_have_last = false
	_score_at_step = 0
	_active = not PlayerSettings.transient() and not PlayerSettings.current().guide_done

func skip() -> void:
	if _active:
		_finish()

func is_active() -> bool:
	return _active

func _finish() -> void:
	_active = false
	var settings: PlayerSettings = PlayerSettings.current()
	settings.guide_done = true
	settings.save()

func _key_name(action: StringName) -> String:
	return OS.get_keycode_string(PlayerSettings.current().key_for(action))

func strip_text() -> String:
	return "%s%s%s%s move · Mouse look · %s jump · %s crouch · LMB grab/drop · RMB throw · %s seize/free · Esc menu" % [
		_key_name(&"forward"), _key_name(&"left"), _key_name(&"back"), _key_name(&"right"),
		_key_name(&"jump"), _key_name(&"crouch"), _key_name(&"seize")]

func refresh(world: SimWorld, mine: SimEntity, delta: float) -> void:
	var transient: bool = PlayerSettings.transient()
	var running: bool = mine != null and world.match_phase != SimWorld.MatchPhase.MATCH_END
	if running:
		_match_time += delta
	var show_strip: bool = not transient and running and (_active or _match_time < STRIP_SECONDS)
	_strip.visible = show_strip
	_line.visible = _active and running
	var width: float = size.x
	_strip.text = strip_text()
	_strip.position = Vector2(0.0, size.y - 40.0)
	_strip.size = Vector2(width, 28.0)
	_line.position = Vector2(0.0, 132.0)  # under the top bar's names (MatchHud)
	_line.size = Vector2(width, 30.0)
	if not _active or mine == null:
		return
	_step_time += delta
	var done: bool = false
	var own_team: StringName = mine.team
	match _step:
		0:
			if _have_last:
				_moved += Vector2(mine.position.x - _last_position.x, mine.position.z - _last_position.z).length()
			done = _moved >= MOVE_GOAL
		1:
			var zone: ZoneDef = world.zone_at(mine.position)
			done = zone != null and zone.owner_team != &"" and zone.owner_team != own_team
		2:
			done = mine.is_carrying()
		3:
			done = world.score_for(own_team) > _score_at_step
		4:
			done = _step_time >= FINAL_SECONDS
	_last_position = mine.position
	_have_last = true
	var text: String = "Step %d of %d: %s" % [_step + 1, STEP_TEXTS.size(), _step_text()]
	if _step_time >= HELP_AFTER and STEP_HELP[_step] != "":
		text += "\n" + STEP_HELP[_step]
	_line.text = text
	if done:
		_step += 1
		_step_time = 0.0
		_score_at_step = world.score_for(own_team)
		if _step >= STEP_TEXTS.size():
			_finish()

func _step_text() -> String:
	var text: String = STEP_TEXTS[_step]
	if _step == 0:
		return text % ("%s%s%s%s" % [_key_name(&"forward"), _key_name(&"left"),
			_key_name(&"back"), _key_name(&"right")])
	if _step == 4:
		return text % _key_name(&"seize")
	return text
