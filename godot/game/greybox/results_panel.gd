class_name ResultsPanel
extends CanvasLayer
## Shown at MATCH_END in place of the headline: who won, the round score, and each
## family's banked cash in the last round. Reads the confirmed world only.
##
## Look (PT2-6): the shared UiTheme; one of the two places the family colours are
## used (with the HUD bar): a band in the winners' colour and each family's name
## in its own. The line is singular ("<NAME> WINS THE MATCH", PT3-3): a display name
## reads "<Name> Family" (FamilyNames), one family.
##
## PT4-7: one title line, then a header and one aligned row per family (name in
## its colour, rounds won, banked in the last round), the buttons in one row.

signal play_again
signal main_menu

var _root: Control = null
var _title: Label = null
var _band: ColorRect = null
## One row per family (PT4-7): name, rounds won, banked in the last round.
var _names: Array[Label] = []
var _rounds: Array[Label] = []
var _banked: Array[Label] = []
var _again: Button = null
var _wait: Label = null

func _ready() -> void:
	layer = 8
	visible = false
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiTheme.current()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var shade: ColorRect = UiTheme.shade()
	shade.color.a = 0.35
	_root.add_child(shade)
	var centre: CenterContainer = CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(centre)
	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size = Vector2(620.0, 0.0)
	column.add_theme_constant_override("separation", 12)
	centre.add_child(UiTheme.card(column))

	var cup: TextureRect = TextureRect.new()
	cup.texture = UiTheme.icon("trophy")
	cup.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cup.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cup.custom_minimum_size = Vector2(0.0, 44.0)
	cup.modulate = UiTheme.CHARCOAL
	column.add_child(cup)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.theme_type_variation = UiTheme.TITLE
	# PT4-7: one line for the default names at this card width (52 wrapped).
	_title.add_theme_font_size_override("font_size", 40)
	column.add_child(_title)
	_band = ColorRect.new()
	_band.custom_minimum_size = Vector2(0.0, 10.0)
	column.add_child(_band)

	# PT4-7: one aligned row per family under a header: name (in its colour),
	# rounds won, cash banked in the last round.
	var table: GridContainer = GridContainer.new()
	table.columns = 3
	table.add_theme_constant_override("h_separation", 24)
	table.add_theme_constant_override("v_separation", 8)
	column.add_child(table)
	table.add_child(_cell("", HORIZONTAL_ALIGNMENT_LEFT, true))
	table.add_child(_cell("ROUNDS", HORIZONTAL_ALIGNMENT_CENTER, false))
	table.add_child(_cell("BANKED LAST ROUND", HORIZONTAL_ALIGNMENT_CENTER, false))
	for row: int in 2:
		var name_label: Label = _cell("", HORIZONTAL_ALIGNMENT_LEFT, true)
		name_label.theme_type_variation = &""
		name_label.add_theme_font_override("font", UiTheme.display_font())
		name_label.add_theme_font_size_override("font_size", 28)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var rounds: Label = _cell("", HORIZONTAL_ALIGNMENT_CENTER, false)
		rounds.theme_type_variation = &""
		rounds.add_theme_font_override("font", UiTheme.display_font())
		rounds.add_theme_font_size_override("font_size", 40)
		var banked: Label = _cell("", HORIZONTAL_ALIGNMENT_CENTER, false)
		banked.theme_type_variation = &""
		banked.add_theme_font_override("font", UiTheme.display_font())
		banked.add_theme_font_size_override("font_size", 28)
		for each: Label in [name_label, rounds, banked]:
			table.add_child(each)
		_names.append(name_label)
		_rounds.append(rounds)
		_banked.append(banked)

	column.add_child(HSeparator.new())
	# Buttons: one row at the bottom, the main one first, equal widths.
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	_again = Button.new()
	_again.text = "Play again"
	_again.custom_minimum_size = Vector2(0.0, 46.0)
	_again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_again.pressed.connect(func() -> void: play_again.emit())
	buttons.add_child(_again)
	_wait = Label.new()
	_wait.text = "Waiting for the host"
	_wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wait.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_wait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wait.theme_type_variation = UiTheme.NOTE
	buttons.add_child(_wait)
	var menu: Button = Button.new()
	menu.text = "Main menu"
	menu.custom_minimum_size = Vector2(0.0, 46.0)
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.pressed.connect(func() -> void: main_menu.emit())
	buttons.add_child(menu)
	UiTheme.animate_buttons(_root)

## A table cell; `wide` cells take the spare width (the family name column).
func _cell(text: String, align: HorizontalAlignment, wide: bool) -> Label:
	var made: Label = Label.new()
	made.text = text
	made.horizontal_alignment = align
	made.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	made.theme_type_variation = UiTheme.NOTE
	if wide:
		made.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		made.custom_minimum_size = Vector2(110.0, 0.0)
	return made

## The match result line for a winner's team id: "<NAME> WINS THE MATCH" (PT3-3:
## the name is "<Name> Family", singular). An empty id is a drawn match.
static func title_for(winner: StringName) -> String:
	if winner == &"":
		return "THE MATCH IS DRAWN"
	return "%s WINS THE MATCH" % FamilyNames.name_of(winner).to_upper()

## Fills and shows the panel from the confirmed world. `winner` overrides the
## world's winner (only the screen capture uses it, to show a result mid-match).
func show_for(world: SimWorld, level: GreyBoxLevel, can_rematch: bool, winner: StringName = &"") -> void:
	var won: StringName = winner if winner != &"" else world.match_winner
	var colours: Dictionary[StringName, Color] = ArtTheme.current().family_colours
	_title.text = title_for(won)
	_band.color = colours.get(won, UiTheme.CHARCOAL)
	for row: int in _names.size():
		var team: TeamDef = level.teams[row] if row < level.teams.size() else null
		_names[row].visible = team != null
		_rounds[row].visible = team != null
		_banked[row].visible = team != null
		if team == null:
			continue
		var ink: Color = _ink(colours.get(team.id, UiTheme.CHARCOAL))
		_names[row].text = FamilyNames.name_of(team.id).to_upper()
		_names[row].add_theme_color_override("font_color", ink)
		_rounds[row].text = str(world.round_wins_for(team.id))
		_banked[row].text = str(world.score_for(team.id))
	_again.visible = can_rematch
	_wait.visible = not can_rematch
	if not visible:
		visible = true
		UiTheme.open_layer(self, _root)

## A family colour darkened enough to read as text on the cream card.
static func _ink(colour: Color) -> Color:
	return colour.darkened(0.25)

func hide_panel() -> void:
	visible = false
