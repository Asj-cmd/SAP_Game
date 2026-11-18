class_name SettingsPanel
extends VBoxContainer
## Mouse sensitivity, the four volumes (master, music, effects, footsteps), and the keyboard keys. Shared by the
## main menu and the pause panel. Every change is saved at once (PlayerSettings).
##
## A key is rebound by clicking it and pressing the new one; Esc cancels. Mouse
## buttons and the gamepad are fixed.
##
## Look (PT2-6): the shared UiTheme; sound and picture on the left, keys on the
## right, so the whole panel fits a 900-high window on one cream card.

signal closed

const COLUMN_WIDTH: float = 400.0

var _rebinding: StringName = &""
var _key_buttons: Dictionary[StringName, Button] = {}

func _init() -> void:
	var settings: PlayerSettings = PlayerSettings.current()

	var title: Label = Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.theme_type_variation = UiTheme.TITLE
	add_child(title)

	var columns: HBoxContainer = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 36)
	add_child(columns)
	var left: VBoxContainer = VBoxContainer.new()
	left.custom_minimum_size = Vector2(COLUMN_WIDTH, 0.0)
	columns.add_child(left)
	var right: VBoxContainer = VBoxContainer.new()
	right.custom_minimum_size = Vector2(COLUMN_WIDTH, 0.0)
	columns.add_child(right)

	left.add_child(_heading("Sound and mouse"))
	_slider(left, "Mouse sensitivity", settings.sensitivity, PlayerSettings.SENSITIVITY_MIN,
		PlayerSettings.SENSITIVITY_MAX, func(v: float) -> void: PlayerSettings.current().set_sensitivity(v))
	_slider(left, "Master", settings.master_volume, 0.0, 1.0,
		func(v: float) -> void: PlayerSettings.current().set_volume(&"Master", v))
	_slider(left, "Music", settings.music_volume, 0.0, 1.0,
		func(v: float) -> void: PlayerSettings.current().set_volume(&"Music", v))
	_slider(left, "Effects", settings.effects_volume, 0.0, 1.0,
		func(v: float) -> void: PlayerSettings.current().set_volume(&"SFX", v))
	_slider(left, "Footsteps (0 = off)", settings.footsteps_volume, 0.0, 1.0,
		func(v: float) -> void: PlayerSettings.current().set_volume(&"Footsteps", v))

	left.add_child(_heading("Picture"))
	var quality_box: OptionButton = OptionButton.new()
	for q: String in PlayerSettings.QUALITY_NAMES:
		quality_box.add_item(q.capitalize())
	quality_box.select(PlayerSettings.QUALITY_NAMES.find(settings.quality))
	quality_box.item_selected.connect(func(i: int) -> void:
		PlayerSettings.current().set_quality(PlayerSettings.QUALITY_NAMES[i]))
	_row(left, "Graphics quality", quality_box)
	var fps_box: OptionButton = OptionButton.new()
	for f: int in PlayerSettings.MAX_FPS_CHOICES:
		fps_box.add_item("Off" if f == 0 else str(f))
	fps_box.select(maxi(PlayerSettings.MAX_FPS_CHOICES.find(settings.max_fps), 0))
	fps_box.item_selected.connect(func(i: int) -> void:
		PlayerSettings.current().set_max_fps(PlayerSettings.MAX_FPS_CHOICES[i]))
	_row(left, "Max FPS", fps_box)
	var full: CheckBox = CheckBox.new()
	full.button_pressed = settings.fullscreen
	full.toggled.connect(func(on: bool) -> void: PlayerSettings.current().set_fullscreen(on))
	_row(left, "Fullscreen", full)
	var sync: CheckBox = CheckBox.new()
	sync.button_pressed = settings.vsync
	sync.toggled.connect(func(on: bool) -> void: PlayerSettings.current().set_vsync(on))
	_row(left, "VSync", sync)

	right.add_child(_heading("Keys"))
	var keys_label: Label = Label.new()
	keys_label.text = "Click one, then press the new key; Esc cancels."
	keys_label.theme_type_variation = UiTheme.NOTE
	right.add_child(keys_label)
	for action: StringName in PlayerSettings.ACTIONS:
		var row: HBoxContainer = HBoxContainer.new()
		var name_label: Label = Label.new()
		name_label.text = PlayerSettings.ACTION_LABELS[action]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var button: Button = Button.new()
		button.theme_type_variation = UiTheme.SMALL_BUTTON
		button.custom_minimum_size = Vector2(150.0, 0.0)
		button.pressed.connect(func() -> void: _begin_rebind(action))
		row.add_child(button)
		right.add_child(row)
		_key_buttons[action] = button
	_refresh_keys()

	var reset: Button = Button.new()
	reset.text = "Reset keys to defaults"
	reset.theme_type_variation = UiTheme.SMALL_BUTTON
	reset.pressed.connect(func() -> void:
		_rebinding = &""
		PlayerSettings.current().reset_keys()
		_refresh_keys())
	right.add_child(reset)

	add_child(HSeparator.new())
	var back: Button = Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0.0, 46.0)
	back.pressed.connect(func() -> void:
		_rebinding = &""
		_refresh_keys()
		closed.emit())
	add_child(back)
	UiTheme.animate_buttons(self)

static func _heading(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text.to_upper()
	label.theme_type_variation = UiTheme.HEADING
	return label

func _row(parent: Container, text: String, control: Control) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, 40.0 if control is CheckBox else 150.0)
	row.add_child(control)
	parent.add_child(row)

func _slider(parent: Container, text: String, value: float, low: float, high: float, on_change: Callable) -> void:
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
	slider.custom_minimum_size = Vector2(200.0, 30.0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(v: float) -> void: on_change.call(v))
	row.add_child(slider)
	parent.add_child(row)

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
