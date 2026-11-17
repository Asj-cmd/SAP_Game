class_name GameFeedback
extends Control
## Deadpan feedback (P5-4, D2): a plain event line, a flat puff where a body
## vanishes or reappears, and a black cut when the local body is seized or freed.
## Presentation only: GreyBoxMain spots the events from the confirmed world and
## calls in here; nothing here reads or writes the simulation.
##
## Every number is a const so tuning is one place. No confetti, no shake, no
## coloured flashes.

const MAX_LINES: int = 3
const LINE_SECONDS: float = 3.0
const LINE_FADE_SECONDS: float = 0.2
const LINE_FONT_SIZE: int = 16
const LINE_ALPHA: float = 0.85
const LINE_MARGIN: Vector2 = Vector2(16.0, 16.0)
const PUFF_COUNT: int = 8
const PUFF_COUNT_SMALL: int = 4
const PUFF_SECONDS: float = 0.4
const PUFF_SIZE: float = 30.0
const PUFF_SPEED: float = 90.0
const PUFF_COLOUR: Color = Color(0.72, 0.68, 0.6)
const CUT_SECONDS_SEIZED: float = 0.25
const CUT_SECONDS_FREED: float = 0.2

var _lines: VBoxContainer = null
var _cut: ColorRect = null
var _cut_tween: Tween = null
var _puff_mesh: QuadMesh = null
var _puff_material: StandardMaterial3D = null

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines = VBoxContainer.new()
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_lines.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_lines.position = Vector2(LINE_MARGIN.x, -LINE_MARGIN.y)
	add_child(_lines)
	_cut = ColorRect.new()
	_cut.color = Color(0.0, 0.0, 0.0, 0.0)
	_cut.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cut.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_cut)
	_puff_mesh = QuadMesh.new()
	_puff_mesh.size = Vector2(PUFF_SIZE, PUFF_SIZE)
	_puff_material = StandardMaterial3D.new()
	_puff_material.albedo_color = PUFF_COLOUR
	_puff_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_puff_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_puff_mesh.material = _puff_material

## One plain line, shown LINE_SECONDS, then gone. At most MAX_LINES at once.
func add_line(text: String) -> void:
	if not is_inside_tree():
		return
	var label: Label = Label.new()
	label.text = text
	label.modulate = Color(1.0, 1.0, 1.0, LINE_ALPHA)
	label.add_theme_font_size_override("font_size", LINE_FONT_SIZE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.add_child(label)
	while _lines.get_child_count() > MAX_LINES:
		var oldest: Node = _lines.get_child(0)
		_lines.remove_child(oldest)
		oldest.queue_free()
	var tween: Tween = label.create_tween()
	tween.tween_interval(LINE_SECONDS)
	tween.tween_property(label, "modulate:a", 0.0, LINE_FADE_SECONDS)
	tween.tween_callback(label.queue_free)

func clear_lines() -> void:
	for child: Node in _lines.get_children():
		_lines.remove_child(child)
		child.queue_free()

## Black to clear over `seconds`: the jump to jail (or out of it) reads as a cut.
func cut(seconds: float) -> void:
	if _cut_tween != null:
		_cut_tween.kill()
	_cut.color = Color(0.0, 0.0, 0.0, 1.0)
	_cut_tween = create_tween()
	_cut_tween.tween_property(_cut, "color:a", 0.0, seconds)

## A flat grey-beige burst at `at` (world units), added under `parent`.
func puff(parent: Node3D, at: Vector3, count: int) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var burst: CPUParticles3D = CPUParticles3D.new()
	burst.mesh = _puff_mesh
	burst.amount = count
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.lifetime = PUFF_SECONDS
	burst.direction = Vector3.UP
	burst.spread = 180.0
	burst.gravity = Vector3.ZERO
	burst.initial_velocity_min = PUFF_SPEED * 0.5
	burst.initial_velocity_max = PUFF_SPEED
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(burst)
	burst.position = at
	burst.emitting = true
	burst.finished.connect(burst.queue_free)

## "dad", "mom", "elder girl": a member id made plain.
static func member_words(id: StringName) -> String:
	return String(id).replace("_", " ")
