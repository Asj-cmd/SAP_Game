class_name LobbyPanel
extends CanvasLayer
## Shown to a menu-hosted game before the match starts: the join code, a bots
## checkbox, Start and Cancel. Presentation only; the game starts the match.

signal start_pressed(bots: bool)
signal cancelled

var _code: Label = null
var _bots: CheckBox = null
var _size: Label = null

func _ready() -> void:
	layer = 9
	visible = false
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	var centre: CenterContainer = CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(centre)
	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size = Vector2(420.0, 0.0)
	column.add_theme_constant_override("separation", 12)
	centre.add_child(column)

	var title: Label = Label.new()
	title.text = "LOBBY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	column.add_child(title)
	_size = Label.new()
	_size.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_size)
	var hint: Label = Label.new()
	hint.text = "Give this code to the people joining (already copied):"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1.0, 1.0, 1.0, 0.6)
	column.add_child(hint)
	_code = Label.new()
	_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code.add_theme_font_size_override("font_size", 28)
	column.add_child(_code)
	_bots = CheckBox.new()
	_bots.text = "Fill empty seats with bots"
	_bots.button_pressed = true
	column.add_child(_bots)
	var start: Button = Button.new()
	start.text = "Start match"
	start.custom_minimum_size = Vector2(0.0, 40.0)
	start.pressed.connect(func() -> void: start_pressed.emit(_bots.button_pressed))
	column.add_child(start)
	var cancel: Button = Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(0.0, 40.0)
	cancel.pressed.connect(func() -> void: cancelled.emit())
	column.add_child(cancel)

func open(code: String, team_size: int) -> void:
	_code.text = code
	_size.text = "%dv%d" % [team_size, team_size]
	visible = true

func close() -> void:
	visible = false

func is_open() -> bool:
	return visible
