class_name SettingsPanel
extends VBoxContainer
## Mouse sensitivity, the three volumes, and the keyboard keys. Shared by the
## main menu and the pause panel. Every change is saved at once (PlayerSettings).
##
## A key is rebound by clicking it and pressing the new one; Esc cancels. Mouse
## buttons and the gamepad are fixed.

signal closed

var _rebinding: StringName = &""
var _key_buttons: Dictionary[StringName, Button] = {}

func _init() -> void:
	custom_minimum_size = Vector2(460.0, 0.0)
	add_theme_constant_override("separation", 8)
	var settings: PlayerSettings = PlayerSettings.current()

	var title: Label = Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	add_child(title)

	_slider("Mouse sensitivity", settings.sensitivity, PlayerSettings.SENSITIVITY_MIN,
		PlayerSettings.SENSITIVITY_MAX, func(v: float) -> void: PlayerSettings.current().set_sensitivity(v))
	_slider("Master volume", settings.master_volume, 0.0, 1.0,
		func(v: float) -> void: PlayerSettings.current().set_volume(&"Master", v))
	_slider("Effects volume", settings.effects_volume, 0.0, 1.0,
		func(v: float) -> void: PlayerSettings.current().set_volume(&"SFX", v))
	_slider("Music volume", settings.music_volume, 0.0, 1.0,
		func(v: float) -> void: PlayerSettings.current().set_volume(&"Music", v))

	add_child(HSeparator.new())
	var keys_label: Label = Label.new()
	keys_label.text = "Keys  (click one, then press the new key; Esc cancels)"
	add_child(keys_label)
	for action: StringName in PlayerSettings.ACTIONS:
		var row: HBoxContainer = HBoxContainer.new()
		var name_label: Label = Label.new()
		name_label.text = PlayerSettings.ACTION_LABELS[action]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(140.0, 0.0)
		button.pressed.connect(func() -> void: _begin_rebind(action))
		row.add_child(button)
		add_child(row)
		_key_buttons[action] = button
	_refresh_keys()

	var reset: Button = Button.new()
	reset.text = "Reset keys to defaults"
	reset.pressed.connect(func() -> void:
		_rebinding = &""
		PlayerSettings.current().reset_keys()
		_refresh_keys())
	add_child(reset)

	var back: Button = Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0.0, 40.0)
	back.pressed.connect(func() -> void:
		_rebinding = &""
		_refresh_keys()
		closed.emit())
	add_child(back)

func _slider(text: String, value: float, low: float, high: float, on_change: Callable) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var slider: HSlider = HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(220.0, 0.0)
	slider.value_changed.connect(func(v: float) -> void: on_change.call(v))
	row.add_child(slider)
	add_child(row)

func _begin_rebind(action: StringName) -> void:
	_rebinding = action
	_refresh_keys()

func _refresh_keys() -> void:
	var settings: PlayerSettings = PlayerSettings.current()
	for action: StringName in _key_buttons:
		_key_buttons[action].text = "press a key..." if action == _rebinding \
			else OS.get_keycode_string(settings.key_for(action) as Key)

## Runs before the game's own key handling, so a key pressed to rebind is not
## also read as a game key.
func _input(event: InputEvent) -> void:
	if _rebinding == &"" or not is_visible_in_tree():
		return
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.is_echo():
		return
	get_viewport().set_input_as_handled()
	if key.keycode != KEY_ESCAPE:
		PlayerSettings.current().set_key(_rebinding, key.keycode)
	_rebinding = &""
	_refresh_keys()

func is_rebinding() -> bool:
	return _rebinding != &""

## Re-reads the saved values (the panel is built once and shown many times).
func refresh() -> void:
	_rebinding = &""
	_refresh_keys()
