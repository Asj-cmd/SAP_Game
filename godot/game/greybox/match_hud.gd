class_name MatchHud
extends Control
## The top bar (P5-2): a tug-of-war of banked cash. The first family is always on
## the left, on every machine. Presentation only; reads the confirmed world.

const BAR_HEIGHT: float = 28.0
const EASE_SECONDS: float = 0.3

var _colours: Dictionary[StringName, Color] = {}
var _first_id: StringName = &""
var _second_id: StringName = &""
var _split: float = 0.5
var _target: float = 0.5
var _left: Label = null
var _right: Label = null
var _middle: Label = null
var _below: Label = null
var _jail: Label = null
var _bar_rect: Rect2 = Rect2()

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_colours = ArtTheme.current().family_colours
	_left = _label(18, HORIZONTAL_ALIGNMENT_LEFT)
	_right = _label(18, HORIZONTAL_ALIGNMENT_RIGHT)
	_middle = _label(18, HORIZONTAL_ALIGNMENT_CENTER)
	_below = _label(20, HORIZONTAL_ALIGNMENT_CENTER)
	_jail = _label(48, HORIZONTAL_ALIGNMENT_CENTER)

func _label(size: int, align: HorizontalAlignment) -> Label:
	var label: Label = Label.new()
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

## `input` may be null (no local player); it supplies the rescue prompt.
func refresh(world: SimWorld, level: GreyBoxLevel, mine: SimEntity, input: LocalPlayerInput) -> void:
	var first: TeamDef = level.teams[0]
	var second: TeamDef = level.teams[1]
	_first_id = first.id
	_second_id = second.id
	_target = MatchStatus.cash_split(world.score_for(first.id), world.score_for(second.id))
	var width: float = size.x * 0.6
	_bar_rect = Rect2((size.x - width) * 0.5, 8.0, width, BAR_HEIGHT)
	_left.text = _end_text(world, level, first, mine)
	_right.text = _end_text(world, level, second, mine)
	_left.position = Vector2(_bar_rect.position.x, _bar_rect.end.y + 2.0)
	_left.size = Vector2(width * 0.5, 50.0)
	_right.position = Vector2(_bar_rect.position.x + width * 0.5, _bar_rect.end.y + 2.0)
	_right.size = Vector2(width * 0.5, 50.0)
	_middle.text = "ROUND %d  %s" % [world.round_number, MatchStatus.clock_text(world)]
	_middle.position = Vector2(_bar_rect.position.x, _bar_rect.position.y)
	_middle.size = Vector2(width, BAR_HEIGHT)
	_below.text = ""
	_jail.text = ""
	if mine != null:
		if mine.is_captured:
			_jail.text = "JAILED  %d" % ceili(SimWorld.ticks_to_seconds(mine.capture_ticks_remaining))
		elif mine.is_carrying():
			_below.text = "CARRYING CASH"
		if not mine.is_captured and input != null:
			var ally: int = input.rescue_target(world)
			if ally != SimEntity.NO_ENTITY:
				_below.text = "[E] Free a teammate"
	_below.position = Vector2(0.0, _bar_rect.end.y + 56.0)
	_below.size = Vector2(size.x, 30.0)
	_jail.position = Vector2(0.0, size.y * 0.3)
	_jail.size = Vector2(size.x, 60.0)
	queue_redraw()

func _end_text(world: SimWorld, level: GreyBoxLevel, team: TeamDef, mine: SimEntity) -> String:
	var pips: String = ""
	var to_win: int = world.mode.rounds_to_win
	for i: int in to_win:
		pips += "●" if i < world.round_wins_for(team.id) else "○"
	var text: String = "%s\n%d / %d  %s" % [FamilyNames.name_of(team.id),
		world.score_for(team.id), world.mode.score_to_win(), pips]
	if mine != null and mine.team == team.id:
		text += "  YOU"
	return text

func _process(delta: float) -> void:
	if not visible:
		return
	_split = move_toward(_split, _target, delta / EASE_SECONDS)
	queue_redraw()

func _draw() -> void:
	if _bar_rect.size.x <= 0.0:
		return
	var first_id: StringName = _first_id
	var second_id: StringName = _second_id
	draw_rect(_bar_rect, Color(0.15, 0.15, 0.15, 0.6))
	var left_w: float = _bar_rect.size.x * _split
	draw_rect(Rect2(_bar_rect.position, Vector2(left_w, BAR_HEIGHT)),
		_colours.get(first_id, Color(0.48, 0.58, 0.45)))
	draw_rect(Rect2(_bar_rect.position + Vector2(left_w, 0.0),
		Vector2(_bar_rect.size.x - left_w, BAR_HEIGHT)),
		_colours.get(second_id, Color(0.7, 0.4, 0.3)))
	draw_rect(_bar_rect, Color.BLACK, false, 2.0)
