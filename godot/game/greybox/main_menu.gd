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

signal solo_chosen(team_size: int)
signal host_chosen(address: String, team_size: int)
signal join_chosen(code: String)

const PANEL_WIDTH: float = 460.0

var _address: LineEdit = null
## Bodies a side for a solo or hosted match. A guest does not choose: it plays
## at the host's size.
var _team_size: OptionButton = null
var _code: LineEdit = null
var _note: Label = null
var _error: Label = null
var _root: Control = null

func _ready() -> void:
	layer = 10
	_build()

## Shows the menu, optionally with the reason the last attempt failed.
func open(problem: String = "") -> void:
	visible = true
	_error.text = problem
	_error.visible = problem != ""

func close() -> void:
	visible = false

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.07, 0.07, 0.09)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)

	var centre: CenterContainer = CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(centre)

	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	column.add_theme_constant_override("separation", 14)
	centre.add_child(column)

	var title: Label = Label.new()
	title.text = "CASH GRAB"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	column.add_child(title)

	var strap: Label = Label.new()
	strap.text = "Steal their cash. Keep yours."
	strap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	strap.modulate = Color(1.0, 1.0, 1.0, 0.6)
	column.add_child(strap)

	_error = Label.new()
	_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.modulate = Color(1.0, 0.45, 0.4)
	_error.visible = false
	column.add_child(_error)

	column.add_child(HSeparator.new())

	# One choice for both solo and hosting, above both: the size is the match,
	# not the way you reach it. Empty seats are filled with bots.
	var size_row: HBoxContainer = HBoxContainer.new()
	var size_label: Label = Label.new()
	size_label.text = "Team size"
	size_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_row.add_child(size_label)
	_team_size = OptionButton.new()
	for size: int in GreyBoxLevel.TEAM_SIZES:
		_team_size.add_item(_size_name(size), size)
	_team_size.select(GreyBoxLevel.TEAM_SIZES.find(GreyBoxLevel.DEFAULT_TEAM_SIZE))
	size_row.add_child(_team_size)
	column.add_child(size_row)

	var solo: Button = _button("Play solo  (against bots)")
	solo.pressed.connect(func() -> void: solo_chosen.emit(_chosen_size()))
	column.add_child(solo)

	column.add_child(HSeparator.new())

	# Hosting: the address is pre-filled with the best guess, because the join
	# code CONTAINS it and a wrong one produces a code nobody can reach - the
	# most common way a first networked session fails.
	var found: Dictionary = NetworkAddress.best()
	var host_label: Label = Label.new()
	host_label.text = "Host a game"
	column.add_child(host_label)
	_address = LineEdit.new()
	_address.text = found["address"]
	_address.placeholder_text = "this computer's address"
	column.add_child(_address)
	_note = Label.new()
	_note.text = found["note"]
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.modulate = Color(1.0, 1.0, 1.0, 0.55)
	_note.add_theme_font_size_override("font_size", 13)
	column.add_child(_note)
	var host: Button = _button("Host")
	host.pressed.connect(func() -> void:
		host_chosen.emit(_address.text.strip_edges(), _chosen_size()))
	column.add_child(host)

	column.add_child(HSeparator.new())

	var join_label: Label = Label.new()
	join_label.text = "Join a game"
	column.add_child(join_label)
	_code = LineEdit.new()
	_code.placeholder_text = "code from the host, e.g. 05ZG-0001-W5FG"
	_code.text_submitted.connect(func(_text: String) -> void: _join())
	column.add_child(_code)
	var join: Button = _button("Join")
	join.pressed.connect(_join)
	column.add_child(join)

	var quit_button: Button = _button("Quit")
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	column.add_child(quit_button)

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
	made.custom_minimum_size = Vector2(0.0, 40.0)
	return made
