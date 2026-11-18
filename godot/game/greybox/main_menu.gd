class_name MainMenu
extends CanvasLayer
## The first screen: play alone, host a game, or join one.
##
## Before this existed the networking was complete and unusable. Hosting meant
## starting the game from a command prompt with `-- --host --advertise=<ip>`,
## and joining meant typing a code into a command line - fine for a developer,
## a wall for anybody being invited to play. Everything behind these buttons
## already worked; this is the door to it.
##
## Presentation only. It decides nothing about a match and holds no state the
## game needs: it reports what was chosen and the game starts it, exactly as the
## command-line flags still do for the tools and the frame capture.
##
## Look (PT2-6): the shared UiTheme; a tilted sign-like title on the left over the
## two houses (GreyBoxMain orbits a camera round the lot behind this layer), the
## choices on one cream card on the right.

signal solo_chosen(team_size: int)
signal host_chosen(address: String, team_size: int)
signal join_chosen(code: String)
signal host_steam_chosen(team_size: int)

const PANEL_WIDTH: float = 480.0
const CREDITS_PATH: String = "res://content/credits.md"
const TITLE_SIZE: int = 132
const TITLE_TILT_DEG: float = -3.0
const TITLE_SHADOW: int = 9

var _address: LineEdit = null
## Bodies a side for a solo or hosted match. A guest does not choose: it plays
## at the host's size.
var _team_size: OptionButton = null
var _code: LineEdit = null
var _note: Label = null
var _error: Label = null
var _root: Control = null
var _column: PanelContainer = null
var _settings: SettingsPanel = null
var _settings_card: PanelContainer = null
var _howto: PanelContainer = null
var _credits: PanelContainer = null
var _tell_boxes: Dictionary[StringName, CheckBox] = {}

func _ready() -> void:
	layer = 10
	_build()

## Shows the menu, optionally with the reason the last attempt failed.
func open(problem: String = "") -> void:
	var was_open: bool = visible
	visible = true
	_show(_column)
	# F5-F8 in a match may have changed the team tell since the menu was built.
	for option: StringName in _tell_boxes:
		_tell_boxes[option].set_pressed_no_signal(TeamTell.current().is_on(option))
	_error.text = problem
	_error.visible = problem != ""
	if not was_open:
		UiTheme.open_layer(self, _root)

func close() -> void:
	visible = false

## For a capture (`--capture-screen=settings`): the settings card, as the button opens it.
func show_settings() -> void:
	_settings.refresh()
	_show(_settings_card)

## One card on the right at a time: the main choices, settings, how to play, credits.
func _show(card: Control) -> void:
	for each: Control in [_column, _settings_card, _howto, _credits]:
		if each != null:
			each.visible = each == card
	if card != null and visible:
		UiTheme.fade_in(card)

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiTheme.current()
	add_child(_root)

	# A light wash only: the two houses behind the menu are the picture.
	var wash: ColorRect = ColorRect.new()
	wash.color = Color(UiTheme.CHARCOAL, 0.18)
	wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(wash)

	var margins: MarginContainer = MarginContainer.new()
	margins.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margins.add_theme_constant_override("margin_" + side, 56)
	_root.add_child(margins)
	var split: HBoxContainer = HBoxContainer.new()
	split.add_theme_constant_override("separation", 40)
	margins.add_child(split)

	split.add_child(_build_title())

	var right: CenterContainer = CenterContainer.new()
	split.add_child(right)
	var stack: VBoxContainer = VBoxContainer.new()
	right.add_child(stack)

	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	_column = UiTheme.card(column)
	stack.add_child(_column)

	_settings = SettingsPanel.new()
	_settings.closed.connect(func() -> void: _show(_column))
	_settings_card = UiTheme.card(_settings)
	_settings_card.visible = false
	stack.add_child(_settings_card)
	_howto = UiTheme.card(_build_howto())
	_howto.visible = false
	stack.add_child(_howto)
	_credits = UiTheme.card(_build_credits())
	_credits.visible = false
	stack.add_child(_credits)

	_error = Label.new()
	_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.add_theme_color_override("font_color", UiTheme.ERROR)
	_error.visible = false
	column.add_child(_error)

	column.add_child(_heading("Play"))
	# One choice for both solo and hosting, above both: the size is the match,
	# not the way you reach it. Empty seats are filled with bots.
	var size_row: HBoxContainer = HBoxContainer.new()
	var size_label: Label = Label.new()
	size_label.text = "Team size"
	size_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_row.add_child(size_label)
	_team_size = OptionButton.new()
	_team_size.custom_minimum_size = Vector2(150.0, 0.0)
	for size: int in GreyBoxLevel.TEAM_SIZES:
		_team_size.add_item(_size_name(size), size)
	_team_size.select(GreyBoxLevel.TEAM_SIZES.find(GreyBoxLevel.DEFAULT_TEAM_SIZE))
	size_row.add_child(_team_size)
	column.add_child(size_row)

	# The D3 team tell (an experiment; TeamTell, P2-4): how you tell your own
	# family from the other one. Any combination; saved on this machine, and
	# F5-F8 flip the same four in a match.
	column.add_child(_note_label("Extra team tells (off = each family in its own colours)"))
	var tell_row: HBoxContainer = HBoxContainer.new()
	var tell: TeamTell = TeamTell.current()
	for option: StringName in TeamTell.OPTIONS:
		var box: CheckBox = CheckBox.new()
		box.text = TeamTell.label(option).capitalize()
		box.button_pressed = tell.is_on(option)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.toggled.connect(func(on: bool) -> void: TeamTell.current().set_option(option, on))
		tell_row.add_child(box)
		_tell_boxes[option] = box
	column.add_child(tell_row)

	var solo: Button = _button("Play solo  (against bots)")
	solo.pressed.connect(func() -> void: solo_chosen.emit(_chosen_size()))
	column.add_child(solo)

	column.add_child(HSeparator.new())

	# Hosting: the address is pre-filled with the best guess, because the join
	# code CONTAINS it and a wrong one produces a code nobody can reach - the
	# most common way a first networked session fails.
	var found: Dictionary = NetworkAddress.best()
	column.add_child(_heading("Host a game"))
	var host_row: HBoxContainer = HBoxContainer.new()
	_address = LineEdit.new()
	_address.text = found["address"]
	_address.placeholder_text = "this computer's address"
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_row.add_child(_address)
	var host: Button = _button("Host")
	host.custom_minimum_size = Vector2(120.0, 0.0)
	host.pressed.connect(func() -> void:
		host_chosen.emit(_address.text.strip_edges(), _chosen_size()))
	host_row.add_child(host)
	column.add_child(host_row)
	_note = _note_label(found["note"])
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_note)
	# Only when the Steam add-on is present; otherwise the menu is unchanged.
	if SteamTransport.available():
		var host_steam: Button = _button("Host on Steam  (invite friends)")
		host_steam.pressed.connect(func() -> void: host_steam_chosen.emit(_chosen_size()))
		column.add_child(host_steam)

	column.add_child(HSeparator.new())

	column.add_child(_heading("Join a game"))
	var join_row: HBoxContainer = HBoxContainer.new()
	_code = LineEdit.new()
	_code.placeholder_text = "code from the host, e.g. 05ZG-0001-W5FG"
	_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code.text_submitted.connect(func(_text: String) -> void: _join())
	join_row.add_child(_code)
	var join: Button = _button("Join")
	join.custom_minimum_size = Vector2(120.0, 0.0)
	join.pressed.connect(_join)
	join_row.add_child(join)
	column.add_child(join_row)

	column.add_child(HSeparator.new())

	var small_row: HBoxContainer = HBoxContainer.new()
	small_row.add_theme_constant_override("separation", 8)
	column.add_child(small_row)
	var settings_button: Button = _small_button("Settings", small_row)
	settings_button.pressed.connect(show_settings)
	var howto_button: Button = _small_button("How to play", small_row)
	howto_button.pressed.connect(func() -> void:
		# The next match shows the step guide again.
		var saved: PlayerSettings = PlayerSettings.current()
		saved.guide_done = false
		saved.save()
		_show(_howto))
	var credits_button: Button = _small_button("Credits", small_row)
	credits_button.pressed.connect(func() -> void: _show(_credits))
	var quit_button: Button = _small_button("Quit", small_row)
	quit_button.pressed.connect(func() -> void: get_tree().quit())

	UiTheme.animate_buttons(_root)

## The game's name as a painted sign: Anton, cream with a charcoal outline and a
## hard drop shadow, tilted a few degrees. Original lettering, no logo art.
func _build_title() -> Control:
	var side: VBoxContainer = VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 6)
	var title: Label = Label.new()
	title.text = "CASH\nGRAB"
	title.add_theme_font_override("font", UiTheme.display_font())
	title.add_theme_font_size_override("font_size", TITLE_SIZE)
	title.add_theme_color_override("font_color", UiTheme.CREAM)
	title.add_theme_color_override("font_outline_color", UiTheme.CHARCOAL)
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_color_override("font_shadow_color", UiTheme.CHARCOAL)
	title.add_theme_constant_override("shadow_offset_x", TITLE_SHADOW)
	title.add_theme_constant_override("shadow_offset_y", TITLE_SHADOW)
	title.add_theme_constant_override("shadow_outline_size", 14)
	title.add_theme_constant_override("line_spacing", -34)
	title.rotation = deg_to_rad(TITLE_TILT_DEG)
	title.resized.connect(func() -> void: title.pivot_offset = title.size * 0.5)
	side.add_child(title)
	var strap: PanelContainer = PanelContainer.new()
	strap.theme_type_variation = UiTheme.PLATE
	strap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	strap.rotation = deg_to_rad(TITLE_TILT_DEG)
	var strap_text: Label = Label.new()
	strap_text.text = "Steal their cash. Keep yours."
	strap_text.add_theme_font_override("font", UiTheme.body_bold())
	strap_text.add_theme_font_size_override("font_size", 22)
	strap_text.add_theme_color_override("font_color", UiTheme.CREAM)
	strap.add_child(strap_text)
	var strap_holder: MarginContainer = MarginContainer.new()
	strap_holder.add_theme_constant_override("margin_left", 18)
	strap_holder.add_theme_constant_override("margin_top", 6)
	strap_holder.add_child(strap)
	side.add_child(strap_holder)
	return side

func _build_howto() -> VBoxContainer:
	var panel: VBoxContainer = VBoxContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	panel.add_child(_title_label("How to play"))
	var rules: Label = Label.new()
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.text = "Steal cash from the other family's house and bring it home.\n" \
		+ "Seize intruders on your own side; they go to jail.\n" \
		+ "Free jailed teammates before the timer runs out."
	panel.add_child(rules)
	panel.add_child(HSeparator.new())
	var controls: Label = Label.new()
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(controls)
	var back: Button = _button("Back")
	back.pressed.connect(func() -> void: _show(_column))
	panel.add_child(back)
	panel.visibility_changed.connect(func() -> void:
		if panel.is_visible_in_tree():
			var s: PlayerSettings = PlayerSettings.current()
			var k: Callable = func(a: StringName) -> String: return OS.get_keycode_string(s.key_for(a))
			controls.text = "%s%s%s%s move · Mouse look · %s jump · %s crouch (hold)\nLeft mouse grab or drop · Right mouse throw · %s seize or free · Esc menu" % [
				k.call(&"forward"), k.call(&"left"), k.call(&"back"), k.call(&"right"),
				k.call(&"jump"), k.call(&"crouch"), k.call(&"seize")])
	return panel

## The credits text is a build-time copy of the root CREDITS.md. `#` heading
## markers become bold lines; nothing else is parsed.
func _build_credits() -> VBoxContainer:
	var panel: VBoxContainer = VBoxContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH + 120.0, 0.0)
	panel.add_child(_title_label("Credits"))
	var text: RichTextLabel = RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = false
	text.custom_minimum_size = Vector2(0.0, 480.0)
	text.text = credits_bbcode(FileAccess.get_file_as_string(CREDITS_PATH))
	panel.add_child(text)
	var back: Button = _button("Back")
	back.pressed.connect(func() -> void: _show(_column))
	panel.add_child(back)
	return panel

static func credits_bbcode(raw: String) -> String:
	if raw.strip_edges() == "":
		return "Credits: see CREDITS.md"
	var lines: PackedStringArray = []
	for line: String in raw.replace("[", "[lb]").split("\n"):
		var trimmed: String = line.strip_edges(false, true)
		if trimmed.begins_with("#"):
			lines.append("[b]%s[/b]" % trimmed.lstrip("#").strip_edges())
		else:
			lines.append(trimmed.replace("**", ""))
	return "\n".join(lines)

func _join() -> void:
	var code: String = _code.text.strip_edges()
	if code == "":
		open("Type the code the host is showing, then press Join.")
		return
	join_chosen.emit(code)

func _chosen_size() -> int:
	return _team_size.get_selected_id()

static func _size_name(size: int) -> String:
	var label: String = "%dv%d" % [size, size]
	return label + "  (test)" if size == 1 else label

func _button(text: String) -> Button:
	var made: Button = Button.new()
	made.text = text
	made.custom_minimum_size = Vector2(0.0, 46.0)
	return made

func _small_button(text: String, row: HBoxContainer) -> Button:
	var made: Button = Button.new()
	made.text = text
	made.theme_type_variation = UiTheme.SMALL_BUTTON
	made.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(made)
	return made

static func _heading(text: String) -> Label:
	var made: Label = Label.new()
	made.text = text.to_upper()
	made.theme_type_variation = UiTheme.HEADING
	return made

static func _title_label(text: String) -> Label:
	var made: Label = Label.new()
	made.text = text.to_upper()
	made.theme_type_variation = UiTheme.TITLE
	made.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return made

static func _note_label(text: String) -> Label:
	var made: Label = Label.new()
	made.text = text
	made.theme_type_variation = UiTheme.NOTE
	return made
