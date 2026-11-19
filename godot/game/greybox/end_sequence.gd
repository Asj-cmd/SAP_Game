class_name EndSequence
extends Node
## The match end sequence (PT2-7): about five seconds between the match ending
## and the results panel. A camera swings round the winning family, who stand in
## a row on their own front lawn holding bundles of cash overhead, stiff, with
## the losing family standing blank behind them; a big title says who got rich
## (the winners' view) or who got robbed (the losers' view). Any key or mouse
## button after SKIP_AFTER ends it early.
##
## Presentation only. The sim's MATCH_END already holds everyone; the bodies in
## the shot are drawn-only figures GreyBoxMain stands there (the real bodies are
## hidden while it runs), and nothing here writes to a world or the network.
## Every machine runs it from its own confirmed world, so nothing travels.
##
## The two lines live in ONE file, `content/end_titles.cfg` (`win=` and `lose=`,
## `{name}` filled in with the family's display name, upper-cased).

const TITLES_PATH: String = "res://content/end_titles.cfg"
## If the file is missing or a line is empty.
const FALLBACK_TITLES: Dictionary[String, String] = {
	"win": "THE {name} GOT RICH.",
	"lose": "THE {name} GOT ROBBED.",
}
## Seconds the sequence lasts, and how long before a key may skip it (so a key
## still held from play does not skip it unseen). REVIEW.
const LENGTH: float = 5.0
const SKIP_AFTER: float = 0.5
## The camera: an arc of ARC_DEGREES centred on the way out of the house, at
## this height, looking at a point LOOK above the winners' row. The arc is
## 150 degrees rather than a full half-turn: at 90 degrees either side the
## camera looks straight down the row and the bodies hide one another.
const ARC_DEGREES: float = 150.0
const RADIUS_MIN: float = 450.0
## Added to half the row's length, so the end of a long row is never on top of
## the camera when it swings to that side.
const RADIUS_MARGIN: float = 280.0
const EYE: float = 170.0
const LOOK: float = 120.0
const FOV: float = 50.0
const TITLE_SIZE: int = 72

var running: bool = false
## True once the sequence has run its length or been skipped; GreyBoxMain then
## opens the results panel.
var finished: bool = false
var elapsed: float = 0.0

var _camera: Camera3D = null
var _layer: CanvasLayer = null
var _title: Label = null
var _centre: Vector3 = Vector3.ZERO
var _out: Vector3 = Vector3.FORWARD
var _along: Vector3 = Vector3.RIGHT
var _radius: float = RADIUS_MIN

static var _titles: Dictionary[String, String] = {}
static var _titles_loaded: bool = false

func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 7  # over the HUD text, under the results panel (8)
	_layer.visible = false
	add_child(_layer)
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(root)
	_title = Label.new()
	_title.theme = UiTheme.current()
	_title.theme_type_variation = UiTheme.HUD_BIG
	_title.add_theme_font_size_override("font_size", TITLE_SIZE)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title.offset_left = 60.0
	_title.offset_right = -60.0
	_title.offset_top = 90.0
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_title)

## The title a viewer sees: the win line with the winners' name if the viewer's
## family won, else the lose line with the viewer's own family's name. `names`
## maps team id -> display name (FamilyNames.name_of). "" for a drawn match or a
## viewer with no family (no sequence then).
static func title_for(winner: StringName, viewer_team: StringName,
		names: Dictionary[StringName, String]) -> String:
	if winner == &"" or viewer_team == &"":
		return ""
	var won: bool = winner == viewer_team
	var line: String = titles()["win" if won else "lose"]
	var family: String = names.get(winner if won else viewer_team, "")
	return line.replace("{name}", family.to_upper())

## The two lines from TITLES_PATH (read once), FALLBACK_TITLES for any missing.
static func titles() -> Dictionary[String, String]:
	if not _titles_loaded:
		_titles_loaded = true
		var text: String = ""
		if FileAccess.file_exists(TITLES_PATH):
			text = FileAccess.get_file_as_string(TITLES_PATH)
		_titles = parse_titles(text)
	return _titles

## `win=` / `lose=` lines; `#` comments and blank lines skipped; FALLBACK_TITLES
## for a key that is missing or empty.
static func parse_titles(text: String) -> Dictionary[String, String]:
	var found: Dictionary[String, String] = {}
	for raw: String in text.split("\n"):
		var line: String = raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var at: int = line.find("=")
		if at < 0:
			continue
		var key: String = line.substr(0, at).strip_edges()
		var value: String = line.substr(at + 1).strip_edges()
		if FALLBACK_TITLES.has(key) and value != "":
			found[key] = value
	for key: String in FALLBACK_TITLES:
		if not found.has(key):
			found[key] = FALLBACK_TITLES[key]
	return found

## Starts the sequence: a camera in `viewport` swinging round `centre` (the
## winners' row middle at their feet; `out` the way out of their house, `along`
## the row), wide enough for a row `row_length` long; the title in `colour`.
func begin(viewport: Node, centre: Vector3, out: Vector3, along: Vector3,
		row_length: float, title: String, colour: Color) -> void:
	_centre = centre
	_out = out.normalized()
	_along = along.normalized()
	_radius = maxf(RADIUS_MIN, row_length * 0.5 + RADIUS_MARGIN)
	if _camera == null or not is_instance_valid(_camera) or _camera.get_parent() != viewport:
		if _camera != null and is_instance_valid(_camera):
			_camera.queue_free()
		_camera = Camera3D.new()
		_camera.fov = FOV
		_camera.near = ChaseCamera.NEAR_PLANE
		_camera.far = ChaseCamera.FAR_PLANE
		viewport.add_child(_camera)
	_title.text = title
	_title.add_theme_color_override("font_color", colour.lightened(0.15))
	_layer.visible = true
	running = true
	finished = false
	elapsed = 0.0
	_place_camera()
	_camera.current = true

## One frame on: the camera moves along its arc; `finished` at LENGTH.
func advance(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	if elapsed >= LENGTH:
		finished = true
	_place_camera()

## Ends it: the title hides and `chase` is the seat's camera again.
func end(chase: Camera3D) -> void:
	_layer.visible = false
	if not running:
		return
	running = false
	if _camera != null and is_instance_valid(_camera):
		_camera.current = false
	if chase != null and is_instance_valid(chase):
		chase.current = true

## Where the camera is `elapsed` seconds in: one even sweep of ARC_DEGREES.
func _place_camera() -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var t: float = clampf(elapsed / LENGTH, 0.0, 1.0)
	var angle: float = deg_to_rad(ARC_DEGREES) * (t - 0.5)
	var at: Vector3 = _centre + (_out * cos(angle) + _along * sin(angle)) * _radius
	_camera.global_position = at + Vector3.UP * EYE
	_camera.look_at(_centre + Vector3.UP * LOOK, Vector3.UP)

## Any key or mouse button skips it after SKIP_AFTER, and is used up here so it
## does not also act in the match (Enter would ask for a rematch at once).
func _input(event: InputEvent) -> void:
	if not running:
		return
	var key: InputEventKey = event as InputEventKey
	var button: InputEventMouseButton = event as InputEventMouseButton
	var pressed: bool = (key != null and key.pressed and not key.is_echo()) \
		or (button != null and button.pressed)
	var joy: InputEventJoypadButton = event as InputEventJoypadButton
	if joy != null and joy.pressed:
		pressed = true
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	if elapsed >= SKIP_AFTER:
		finished = true
