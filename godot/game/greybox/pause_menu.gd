class_name PauseMenu
extends CanvasLayer
## Esc in a match: Resume, Settings, Leave to menu. The simulation is never
## paused (DECISIONS: one code path, and online play cannot pause); the seat just
## stands still while this is up (LocalPlayerInput.suspended).
##
## Look (PT2-6): the shared UiTheme, one cream card over a charcoal wash.

signal resumed
signal left

var _root: Control = null
var _buttons: PanelContainer = null
var _settings: SettingsPanel = null
var _settings_card: PanelContainer = null

func _ready() -> void:
	layer = 9
	visible = false
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiTheme.current()
	add_child(_root)
	_root.add_child(UiTheme.shade())
	var centre: CenterContainer = CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(centre)
	var stack: VBoxContainer = VBoxContainer.new()
	centre.add_child(stack)

	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size = Vector2(340.0, 0.0)
	_buttons = UiTheme.card(column)
	stack.add_child(_buttons)
	var title: Label = Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.theme_type_variation = UiTheme.TITLE
	column.add_child(title)
	var note: Label = Label.new()
	note.text = "The match keeps running."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.theme_type_variation = UiTheme.NOTE
	column.add_child(note)
	column.add_child(_button("Resume", func() -> void: resumed.emit()))
	column.add_child(_button("Settings", _show_settings))
	column.add_child(_button("Leave to menu", func() -> void: left.emit()))

	_settings = SettingsPanel.new()
	_settings.closed.connect(_show_buttons)
	_settings_card = UiTheme.card(_settings)
	_settings_card.visible = false
	stack.add_child(_settings_card)
	UiTheme.animate_buttons(_root)

func open() -> void:
	var was_open: bool = visible
	visible = true
	_show_buttons()
	if not was_open:
		UiTheme.open_layer(self, _root)

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
	_settings_card.visible = true
	UiTheme.fade_in(_settings_card)

func _show_buttons() -> void:
	_settings_card.visible = false
	_buttons.visible = true

func _button(text: String, on_press: Callable) -> Button:
	var made: Button = Button.new()
	made.text = text
	made.custom_minimum_size = Vector2(0.0, 46.0)
	made.pressed.connect(on_press)
	return made
