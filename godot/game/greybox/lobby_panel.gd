class_name LobbyPanel
extends CanvasLayer
## Shown before the match starts. On the host (a menu-hosted game): the join
## code, a name box per family, a bots checkbox, Start and Cancel. On a seated
## guest (PT3-3) the same panel without the code, bots and Start: the name boxes
## and "Waiting for the host to start". Presentation only; the game starts the
## match and owns what the names mean (FamilyNames, MatchLink.publish_names).
##
## Names (PT3-3): a player may type their OWN family's name; the host may also
## clear either box. The boxes show the stored typed names (the host's copy).
##
## Look (PT2-6): the shared UiTheme; the code on a charcoal plate, large, since it
## is read out loud to a friend.

signal start_pressed(bots: bool)
signal cancelled
signal name_edited(team_id: StringName, text: String)
signal name_cleared(team_id: StringName)
## The player picked a member of their own family (PT4-3): a slot, or Lobby.RANDOM.
signal member_chosen(slot: int)

var _root: Control = null
var _code: Label = null
var _bots: CheckBox = null
var _size: Label = null
var _invite: Button = null
var _steam_token: String = ""
var _hint: Label = null
var _plate: PanelContainer = null
var _start: Button = null
var _waiting: Label = null
var _name_boxes: Dictionary[StringName, FamilyNameBox] = {}
var _pickers: Dictionary[StringName, OptionButton] = {}
var _picker_rows: Dictionary[StringName, HBoxContainer] = {}
var _member_note: Label = null
var _rosters: Dictionary[StringName, Label] = {}
## What the pickers were last built from, so they are rebuilt only on a change.
var _members_shown: String = ""

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
	_hint = Label.new()
	_hint.text = "Give this code to the people joining (already copied):"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.theme_type_variation = UiTheme.NOTE
	column.add_child(_hint)
	_plate = PanelContainer.new()
	_plate.theme_type_variation = UiTheme.PLATE
	column.add_child(_plate)
	_code = Label.new()
	_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code.add_theme_font_override("font", UiTheme.display_font())
	_code.add_theme_font_size_override("font_size", 40)
	_code.add_theme_color_override("font_color", UiTheme.CREAM)
	_plate.add_child(_code)
	_invite = Button.new()
	_invite.text = "Invite friends (Steam)"
	_invite.custom_minimum_size = Vector2(0.0, 46.0)
	_invite.visible = false
	_invite.pressed.connect(func() -> void: SteamTransport.invite_dialog(_steam_token))
	column.add_child(_invite)

	var names_note: Label = Label.new()
	names_note.text = "Family names: type your own family's surname"
	names_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names_note.theme_type_variation = UiTheme.NOTE
	column.add_child(names_note)
	for team_id: StringName in LobbyState.TEAMS:
		var box: FamilyNameBox = FamilyNameBox.make(team_id)
		box.edited.connect(func(team: StringName, text: String) -> void: name_edited.emit(team, text))
		box.cleared.connect(func(team: StringName) -> void: name_cleared.emit(team))
		column.add_child(box)
		_name_boxes[team_id] = box
		# PT5-1: who plays whom in this family, "Dad - Sam (you)".
		var roster: Label = Label.new()
		roster.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		roster.theme_type_variation = UiTheme.NOTE
		column.add_child(roster)
		_rosters[team_id] = roster
		# PT4-3: "Play as" under the player's OWN family's box only.
		var row: HBoxContainer = HBoxContainer.new()
		var label: Label = Label.new()
		label.text = "Play as"
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var picker: OptionButton = OptionButton.new()
		picker.custom_minimum_size = Vector2(260.0, 0.0)
		picker.item_selected.connect(func(index: int) -> void:
			member_chosen.emit(_picker_slot(picker.get_item_id(index))))
		row.add_child(picker)
		row.visible = false
		column.add_child(row)
		_picker_rows[team_id] = row
		_pickers[team_id] = picker
	_member_note = Label.new()
	_member_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_member_note.add_theme_color_override("font_color", UiTheme.ERROR)
	_member_note.visible = false
	column.add_child(_member_note)

	_bots = CheckBox.new()
	_bots.text = "Fill empty seats with bots"
	_bots.button_pressed = true
	column.add_child(_bots)
	_start = Button.new()
	_start.text = "Start match"
	_start.custom_minimum_size = Vector2(0.0, 46.0)
	_start.pressed.connect(func() -> void: start_pressed.emit(_bots.button_pressed))
	column.add_child(_start)
	_waiting = Label.new()
	_waiting.text = "Waiting for the host to start"
	_waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_waiting.theme_type_variation = UiTheme.HEADING
	_waiting.visible = false
	column.add_child(_waiting)
	var cancel: Button = Button.new()
	cancel.text = "Cancel"
	cancel.theme_type_variation = UiTheme.SMALL_BUTTON
	cancel.pressed.connect(func() -> void: cancelled.emit())
	column.add_child(cancel)
	UiTheme.animate_buttons(_root)

## The host's lobby. `own_team` is the host's family (its box is editable); the
## host may clear both. `steam_token` is the Steam lobby id when this is a Steam
## host, else "".
func open(code: String, team_size: int, steam_token: String = "", own_team: StringName = &"") -> void:
	_steam_token = steam_token
	_invite.visible = steam_token != ""
	_code.text = code
	_set_guest(false)
	_set_rights(own_team, true)
	_show(team_size)

## A seated guest's lobby: its own family's box editable, no Clear, no Start.
func open_guest(team_size: int, own_team: StringName) -> void:
	_invite.visible = false
	_set_guest(true)
	_set_rights(own_team, false)
	_show(team_size)

## Is this the guest's version (closed by the game when the match starts)?
func is_guest() -> bool:
	return _waiting.visible

func _set_guest(guest: bool) -> void:
	_hint.visible = not guest
	_plate.visible = not guest
	_bots.visible = not guest
	_start.visible = not guest
	_waiting.visible = guest

func _set_rights(own_team: StringName, can_clear: bool) -> void:
	for team_id: StringName in _name_boxes:
		_name_boxes[team_id].set_rights(team_id == own_team, can_clear)

func _show(team_size: int) -> void:
	_size.text = "%d V %d" % [team_size, team_size]
	_members_shown = ""
	var was_open: bool = visible
	visible = true
	if not was_open:
		UiTheme.open_layer(self, _root)

## The "Play as" picker of the player's own family (PT4-3), from the lobby state:
## Random, then each member at this team size. A member another player PICKED is
## disabled and says who; the player's own pick is selected, or Random when they
## have not picked. `notice` is why the last request was refused ("" = none).
func show_members(view: LobbyState, own_team: StringName, my_slot: int, notice: String,
		own_name: String = "") -> void:
	var key: String = "%s|%d|%s|%s" % [own_team, my_slot, notice, own_name]
	if view != null:
		for seat: LobbyState.Seat in view.seats:
			key += "|%s:%d:%d:%d:%s" % [seat.team, seat.slot, seat.occupant, int(seat.chosen), seat.name]
	if key == _members_shown:
		return
	_members_shown = key
	for team_id: StringName in _rosters:
		var lines: Array[String] = FamilyLineup.roster(view, team_id, own_team, my_slot, own_name)
		_rosters[team_id].text = "   ".join(PackedStringArray(lines))
		_rosters[team_id].visible = not lines.is_empty()
	_member_note.text = notice
	_member_note.visible = notice != ""
	for team_id: StringName in _pickers:
		_picker_rows[team_id].visible = view != null and team_id == own_team
	if view == null or not _pickers.has(own_team):
		return
	var picker: OptionButton = _pickers[own_team]
	picker.clear()
	picker.add_item("Random", 0)
	var slots: Array[int] = []
	for seat: LobbyState.Seat in view.seats:
		if seat.team == own_team:
			slots.append(seat.slot)
	slots.sort()
	var words: Array[String] = FamilyLineup.slot_words(own_team, slots.size())
	var selected: int = 0
	for i: int in slots.size():
		var seat: LobbyState.Seat = view.seat_at(own_team, slots[i])
		var text: String = words[i] if i < words.size() else "Member %d" % (i + 1)
		var taken: bool = seat.occupant == LobbyState.Occupant.HUMAN and seat.chosen \
			and seat.slot != my_slot
		if taken:
			text += "  (taken by %s)" % (seat.name if seat.name != "" else "a player")
		picker.add_item(text, seat.slot + 1)
		picker.set_item_disabled(picker.item_count - 1, taken)
		if seat.slot == my_slot and seat.chosen:
			selected = picker.item_count - 1
	picker.select(selected)

static func _picker_slot(item_id: int) -> int:
	return Lobby.RANDOM if item_id == 0 else item_id - 1

func close() -> void:
	visible = false

func is_open() -> bool:
	return visible
