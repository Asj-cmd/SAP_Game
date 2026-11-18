class_name ResultsPanel
extends CanvasLayer
## Shown at MATCH_END in place of the headline: who won, the round score, and each
## family's banked cash in the last round. Reads the confirmed world only.
##
## Look (PT2-6): the shared UiTheme; one of the two places the family colours are
## used (with the HUD bar): a band in the winners' colour and each family's name
## in its own. The line is plural ("<NAME> WIN THE MATCH"): a family is several
## people, and the display names (FamilyNames) read as plurals.

signal play_again
signal main_menu

var _root: Control = null
var _title: Label = null
var _band: ColorRect = null
var _first_name: Label = null
var _second_name: Label = null
var _score: Label = null
var _cash: Label = null
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
	column.custom_minimum_size = Vector2(560.0, 0.0)
	column.add_theme_constant_override("separation", 12)
	centre.add_child(UiTheme.card(column))

	var over: Label = Label.new()
	over.text = "MATCH OVER"
	over.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over.theme_type_variation = UiTheme.HEADING
	column.add_child(over)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.theme_type_variation = UiTheme.TITLE
	_title.add_theme_font_size_override("font_size", 52)
	column.add_child(_title)
	_band = ColorRect.new()
	_band.custom_minimum_size = Vector2(0.0, 10.0)
	column.add_child(_band)

	var score_row: HBoxContainer = HBoxContainer.new()
	score_row.add_theme_constant_override("separation", 18)
	column.add_child(score_row)
	_first_name = _side_name(HORIZONTAL_ALIGNMENT_RIGHT)
	score_row.add_child(_first_name)
	_score = Label.new()
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score.add_theme_font_override("font", UiTheme.display_font())
	_score.add_theme_font_size_override("font_size", 64)
	score_row.add_child(_score)
	_second_name = _side_name(HORIZONTAL_ALIGNMENT_LEFT)
	score_row.add_child(_second_name)

	_cash = Label.new()
	_cash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cash.theme_type_variation = UiTheme.NOTE
	column.add_child(_cash)
	column.add_child(HSeparator.new())
	_again = Button.new()
	_again.text = "Play again"
	_again.custom_minimum_size = Vector2(0.0, 46.0)
	_again.pressed.connect(func() -> void: play_again.emit())
	column.add_child(_again)
	_wait = Label.new()
	_wait.text = "Waiting for the host"
	_wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wait.theme_type_variation = UiTheme.NOTE
	column.add_child(_wait)
	var menu: Button = Button.new()
	menu.text = "Main menu"
	menu.theme_type_variation = UiTheme.SMALL_BUTTON
	menu.pressed.connect(func() -> void: main_menu.emit())
	column.add_child(menu)
	UiTheme.animate_buttons(_root)

func _side_name(align: HorizontalAlignment) -> Label:
	var made: Label = Label.new()
	made.horizontal_alignment = align
	made.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	made.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	made.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	made.add_theme_font_override("font", UiTheme.display_font())
	made.add_theme_font_size_override("font_size", 26)
	return made

## The match result line for a winner's team id: "<NAME> WIN THE MATCH", never
## "WINS" (the name is a family, a plural). An empty id is a drawn match.
static func title_for(winner: StringName) -> String:
	if winner == &"":
		return "THE MATCH IS DRAWN"
	return "%s WIN THE MATCH" % FamilyNames.name_of(winner).to_upper()

## Fills and shows the panel from the confirmed world. `winner` overrides the
## world's winner (only the screen capture uses it, to show a result mid-match).
func show_for(world: SimWorld, level: GreyBoxLevel, can_rematch: bool, winner: StringName = &"") -> void:
	var won: StringName = winner if winner != &"" else world.match_winner
	var colours: Dictionary[StringName, Color] = ArtTheme.current().family_colours
	_title.text = title_for(won)
	_band.color = colours.get(won, UiTheme.CHARCOAL)
	var first: TeamDef = level.teams[0]
	var second: TeamDef = level.teams[1]
	_first_name.text = FamilyNames.name_of(first.id).to_upper()
	_first_name.add_theme_color_override("font_color", _ink(colours.get(first.id, UiTheme.CHARCOAL)))
	_second_name.text = FamilyNames.name_of(second.id).to_upper()
	_second_name.add_theme_color_override("font_color", _ink(colours.get(second.id, UiTheme.CHARCOAL)))
	_score.text = MatchStatus.rounds_text(world, level).replace("-", " - ")
	var cash: PackedStringArray = PackedStringArray()
	for team: TeamDef in level.teams:
		cash.append("%s  %d" % [FamilyNames.name_of(team.id), world.score_for(team.id)])
	_cash.text = "Banked in the last round:   " + "   |   ".join(cash)
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
