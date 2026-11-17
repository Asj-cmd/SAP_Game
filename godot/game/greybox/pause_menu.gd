class_name PauseMenu
extends CanvasLayer
## Esc in a match: Resume, Settings, Leave to menu. The simulation is never
## paused (DECISIONS: one code path, and online play cannot pause); the seat just
## stands still while this is up (LocalPlayerInput.suspended).

signal resumed
signal left

var _buttons: Control = null
var _settings: SettingsPanel = null

func _ready() -> void:
	layer = 9
	visible = false
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	var centre: CenterContainer = CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(centre)

	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size = Vector2(320.0, 0.0)
	column.add_theme_constant_override("separation", 12)
	centre.add_child(column)
	_buttons = column
	var title: Label = Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	column.add_child(title)
	var note: Label = Label.new()
	note.text = "The match keeps running."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.modulate = Color(1.0, 1.0, 1.0, 0.6)
	column.add_child(note)
	column.add_child(_button("Resume", func() -> void: resumed.emit()))
	column.add_child(_button("Settings", _show_settings))
	column.add_child(_button("Leave to menu", func() -> void: left.emit()))

	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(_show_buttons)
	centre.add_child(_settings)

func open() -> void:
	visible = true
	_show_buttons()

func close() -> void:
	visible = false

func is_open() -> bool:
	return visible

## True while a key is being rebound: Esc then belongs to the settings screen.
func is_rebinding() -> bool:
	return _settings != null and _settings.is_rebinding()

func _show_settings() -> void:
	_buttons.visible = false
	_settings.refresh()
	_settings.visible = true

func _show_buttons() -> void:
	_settings.visible = false
	_buttons.visible = true

func _button(text: String, on_press: Callable) -> Button:
	var made: Button = Button.new()
	made.text = text
	made.custom_minimum_size = Vector2(0.0, 40.0)
	made.pressed.connect(on_press)
	return made
