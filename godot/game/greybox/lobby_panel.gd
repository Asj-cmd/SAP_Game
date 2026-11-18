class_name LobbyPanel
extends CanvasLayer
## Shown to a menu-hosted game before the match starts: the join code, a bots
## checkbox, Start and Cancel. Presentation only; the game starts the match.
##
## Look (PT2-6): the shared UiTheme; the code on a charcoal plate, large, since it
## is read out loud to a friend.

signal start_pressed(bots: bool)
signal cancelled

var _root: Control = null
var _code: Label = null
var _bots: CheckBox = null
var _size: Label = null
var _invite: Button = null
var _steam_token: String = ""

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
	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size = Vector2(460.0, 0.0)
	centre.add_child(UiTheme.card(column))

	var title: Label = Label.new()
	title.text = "LOBBY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.theme_type_variation = UiTheme.TITLE
	column.add_child(title)
	_size = Label.new()
	_size.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_size.theme_type_variation = UiTheme.HEADING
	column.add_child(_size)
	var hint: Label = Label.new()
	hint.text = "Give this code to the people joining (already copied):"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.theme_type_variation = UiTheme.NOTE
	column.add_child(hint)
	var plate: PanelContainer = PanelContainer.new()
	plate.theme_type_variation = UiTheme.PLATE
	column.add_child(plate)
	_code = Label.new()
	_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code.add_theme_font_override("font", UiTheme.display_font())
	_code.add_theme_font_size_override("font_size", 40)
	_code.add_theme_color_override("font_color", UiTheme.CREAM)
	plate.add_child(_code)
	_invite = Button.new()
	_invite.text = "Invite friends (Steam)"
	_invite.custom_minimum_size = Vector2(0.0, 46.0)
	_invite.visible = false
	_invite.pressed.connect(func() -> void: SteamTransport.invite_dialog(_steam_token))
	column.add_child(_invite)
	_bots = CheckBox.new()
	_bots.text = "Fill empty seats with bots"
	_bots.button_pressed = true
	column.add_child(_bots)
	var start: Button = Button.new()
	start.text = "Start match"
	start.custom_minimum_size = Vector2(0.0, 46.0)
	start.pressed.connect(func() -> void: start_pressed.emit(_bots.button_pressed))
	column.add_child(start)
	var cancel: Button = Button.new()
	cancel.text = "Cancel"
	cancel.theme_type_variation = UiTheme.SMALL_BUTTON
	cancel.pressed.connect(func() -> void: cancelled.emit())
	column.add_child(cancel)
	UiTheme.animate_buttons(_root)

## `steam_token` is the Steam lobby id when this is a Steam host, else "".
func open(code: String, team_size: int, steam_token: String = "") -> void:
	_steam_token = steam_token
	_invite.visible = steam_token != ""
	_code.text = code
	_size.text = "%d V %d" % [team_size, team_size]
	var was_open: bool = visible
	visible = true
	if not was_open:
		UiTheme.open_layer(self, _root)

func close() -> void:
	visible = false

func is_open() -> bool:
	return visible
