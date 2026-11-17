class_name ResultsPanel
extends CanvasLayer
## Shown at MATCH_END in place of the headline: who won, the round score, and each
## family's banked cash in the last round. Reads the confirmed world only.

signal play_again
signal main_menu

var _title: Label = null
var _score: Label = null
var _cash: Label = null
var _again: Button = null
var _wait: Label = null

func _ready() -> void:
	layer = 8
	visible = false
	var centre: CenterContainer = CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel: PanelContainer = PanelContainer.new()
	centre.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size = Vector2(420.0, 0.0)
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	_title = _label(34, column)
	_score = _label(26, column)
	_cash = _label(16, column)
	_cash.modulate = Color(1.0, 1.0, 1.0, 0.75)
	_again = Button.new()
	_again.text = "Play again"
	_again.custom_minimum_size = Vector2(0.0, 40.0)
	_again.pressed.connect(func() -> void: play_again.emit())
	column.add_child(_again)
	_wait = _label(16, column)
	_wait.text = "Waiting for the host"
	var menu: Button = Button.new()
	menu.text = "Main menu"
	menu.custom_minimum_size = Vector2(0.0, 40.0)
	menu.pressed.connect(func() -> void: main_menu.emit())
	column.add_child(menu)

## Fills and shows the panel from the confirmed world.
func show_for(world: SimWorld, level: GreyBoxLevel, can_rematch: bool) -> void:
	_title.text = "%s WINS THE MATCH" % FamilyNames.name_of(world.match_winner).to_upper()
	_score.text = MatchStatus.rounds_text(world, level)
	var cash: PackedStringArray = PackedStringArray()
	for team: TeamDef in level.teams:
		cash.append("%s  %d" % [FamilyNames.name_of(team.id), world.score_for(team.id)])
	_cash.text = "Banked in the last round:   " + "   |   ".join(cash)
	_again.visible = can_rematch
	_wait.visible = not can_rematch
	if not visible:
		visible = true

func hide_panel() -> void:
	visible = false

func _label(size: int, parent: Control) -> Label:
	var made: Label = Label.new()
	made.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	made.add_theme_font_size_override("font_size", size)
	parent.add_child(made)
	return made
