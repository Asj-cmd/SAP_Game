class_name MatchHud
extends Control
## The top bar (P5-2): a tug-of-war of banked cash. The first family is always on
## the left, on every machine. Presentation only; reads the confirmed world.
##
## Look (PT2-6, UiTheme): a framed bar in the two family colours, each family's
## display name and banked count at its own end (a banknote beside the count, the
## round wins as dots under the name), the clock on a charcoal plate in the middle
## that turns mustard for the last 10 s (no flashing). Under the world, one plain
## chip for what is true of your own body: carrying, a teammate to free, jailed.

const BAR_HEIGHT: float = 28.0
const BAR_TOP: float = 22.0
const BAR_WIDTH_SHARE: float = 0.56
const EASE_SECONDS: float = 0.3
const PLATE_SIZE: Vector2 = Vector2(132.0, 64.0)
const LAST_SECONDS: int = 10
const PIP_RADIUS: float = 7.0
const NOTE_SIZE: Vector2 = Vector2(36.0, 22.0)
const NOTE_GAP: float = 10.0
const BUMP_SECONDS: float = 0.2
const BUMP_SCALE: float = 0.15

var _colours: Dictionary[StringName, Color] = {}
var _first_id: StringName = &""
var _second_id: StringName = &""
var _split: float = 0.5
var _target: float = 0.5
var _left_name: Label = null
var _right_name: Label = null
var _left_count: Label = null
var _right_count: Label = null
var _left_you: Label = null
var _right_you: Label = null
var _clock: Label = null
var _round: Label = null
var _chip: PanelContainer = null
var _chip_icon: TextureRect = null
var _chip_text: Label = null
var _jail: PanelContainer = null
var _jail_text: Label = null
var _bar_rect: Rect2 = Rect2()
var _plate_rect: Rect2 = Rect2()
var _late: bool = false
var _wins: Vector2i = Vector2i.ZERO
var _to_win: int = 2
var _last_first: int = -1
var _last_second: int = -1
var _bump_left: float = 0.0
var _bump_right: float = 0.0
var _note: Texture2D = null
var _bar_frame: StyleBoxFlat = null
var _plate_box: StyleBoxFlat = null
var _plate_late: StyleBoxFlat = null
var _chip_urgent: StyleBoxFlat = null

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.current()
	_colours = ArtTheme.current().family_colours
	_note = UiTheme.cash_icon()
	_left_name = _label(UiTheme.HUD_BIG, 28, HORIZONTAL_ALIGNMENT_LEFT)
	_right_name = _label(UiTheme.HUD_BIG, 28, HORIZONTAL_ALIGNMENT_RIGHT)
	_left_count = _label(UiTheme.HUD_BIG, 44, HORIZONTAL_ALIGNMENT_RIGHT)
	_right_count = _label(UiTheme.HUD_BIG, 44, HORIZONTAL_ALIGNMENT_LEFT)
	_left_you = _label(UiTheme.HUD, 15, HORIZONTAL_ALIGNMENT_LEFT)
	_right_you = _label(UiTheme.HUD, 15, HORIZONTAL_ALIGNMENT_RIGHT)
	_clock = _label(UiTheme.HUD_BIG, 38, HORIZONTAL_ALIGNMENT_CENTER)
	_clock.add_theme_constant_override("outline_size", 0)
	_round = _label(UiTheme.HUD, 14, HORIZONTAL_ALIGNMENT_CENTER)
	_round.add_theme_constant_override("outline_size", 0)
	var chip: Array = _make_chip(22)
	_chip = chip[0]
	_chip_icon = chip[1]
	_chip_text = chip[2]
	var jail: Array = _make_chip(44)
	_jail = jail[0]
	_jail_text = jail[2]
	(jail[1] as TextureRect).texture = UiTheme.icon("locked")
	(jail[1] as TextureRect).custom_minimum_size = Vector2(52.0, 52.0)
	_bar_frame = StyleBoxFlat.new()
	_bar_frame.draw_center = false
	_bar_frame.border_color = UiTheme.CHARCOAL
	_bar_frame.set_border_width_all(UiTheme.BORDER)
	_bar_frame.set_corner_radius_all(4)
	_bar_frame.expand_margin_left = 1
	_bar_frame.expand_margin_right = 1
	_bar_frame.expand_margin_top = 1
	_bar_frame.expand_margin_bottom = 1
	_plate_box = _plate(UiTheme.CHARCOAL)
	_plate_late = _plate(UiTheme.MUSTARD)
	_chip_urgent = _plate(UiTheme.MUSTARD)
	for side: String in ["left", "right"]:
		_chip_urgent.set("content_margin_" + side, 14.0)
	for side: String in ["top", "bottom"]:
		_chip_urgent.set("content_margin_" + side, 8.0)

func _plate(fill: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = UiTheme.CHARCOAL
	box.set_border_width_all(UiTheme.BORDER)
	box.set_corner_radius_all(UiTheme.CORNER)
	box.shadow_color = Color(0.0, 0.0, 0.0, 0.3)
	box.shadow_offset = Vector2(3.0, 3.0)
	return box

func _label(variation: StringName, font_size: int, align: HorizontalAlignment) -> Label:
	var label: Label = Label.new()
	label.theme_type_variation = variation
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

## [plate, icon, text]: a charcoal plate with an icon and a line of Anton.
func _make_chip(font_size: int) -> Array:
	var plate: PanelContainer = PanelContainer.new()
	plate.theme_type_variation = UiTheme.PLATE
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.visible = false
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	plate.add_child(row)
	var icon: TextureRect = TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(30.0, 30.0)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var text: Label = Label.new()
	text.add_theme_font_override("font", UiTheme.display_font())
	text.add_theme_font_size_override("font_size", font_size)
	text.add_theme_color_override("font_color", UiTheme.CREAM)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	add_child(plate)
	return [plate, icon, text]

## `input` may be null (no local player); it supplies the rescue prompt.
func refresh(world: SimWorld, level: GreyBoxLevel, mine: SimEntity, input: LocalPlayerInput) -> void:
	var first: TeamDef = level.teams[0]
	var second: TeamDef = level.teams[1]
	_first_id = first.id
	_second_id = second.id
	var first_score: int = world.score_for(first.id)
	var second_score: int = world.score_for(second.id)
	if first_score > _last_first and _last_first >= 0:
		_bump_left = BUMP_SECONDS
	if second_score > _last_second and _last_second >= 0:
		_bump_right = BUMP_SECONDS
	_last_first = first_score
	_last_second = second_score
	_target = MatchStatus.cash_split(first_score, second_score)
	_wins = Vector2i(world.round_wins_for(first.id), world.round_wins_for(second.id))
	_to_win = world.mode.rounds_to_win

	var width: float = size.x * BAR_WIDTH_SHARE
	_bar_rect = Rect2((size.x - width) * 0.5, BAR_TOP, width, BAR_HEIGHT)
	_plate_rect = Rect2(Vector2((size.x - PLATE_SIZE.x) * 0.5, BAR_TOP + BAR_HEIGHT * 0.5 - PLATE_SIZE.y * 0.5 + 4.0), PLATE_SIZE)
	var below: float = _bar_rect.end.y + 4.0
	var half: float = width * 0.5 - PLATE_SIZE.x * 0.5 - 12.0
	_place(_left_name, Vector2(_bar_rect.position.x, below), Vector2(half, 40.0))
	_place(_right_name, Vector2(_bar_rect.end.x - half, below), Vector2(half, 40.0))
	_place(_left_you, Vector2(_bar_rect.position.x + _to_win * PIP_RADIUS * 3.0 + 6.0, below + 40.0), Vector2(half, 24.0))
	_place(_right_you, Vector2(_bar_rect.end.x - half - _to_win * PIP_RADIUS * 3.0 - 6.0, below + 40.0), Vector2(half, 24.0))
	# [count][note][ bar ][note][count]
	var count_w: float = 110.0
	var count_y: float = _bar_rect.get_center().y - 30.0
	var gap: float = NOTE_GAP * 2.0 + NOTE_SIZE.x
	_place(_left_count, Vector2(_bar_rect.position.x - gap - count_w, count_y), Vector2(count_w, 60.0))
	_place(_right_count, Vector2(_bar_rect.end.x + gap, count_y), Vector2(count_w, 60.0))
	_left_name.text = FamilyNames.name_of(first.id).to_upper()
	_right_name.text = FamilyNames.name_of(second.id).to_upper()
	_left_count.text = "%d/%d" % [first_score, world.mode.score_to_win()]
	_right_count.text = "%d/%d" % [second_score, world.mode.score_to_win()]
	_left_you.text = "YOU" if mine != null and mine.team == first.id else ""
	_right_you.text = "YOU" if mine != null and mine.team == second.id else ""

	_clock.text = MatchStatus.clock_text(world)
	var seconds_left: int = ceili(SimWorld.ticks_to_seconds(world.phase_ticks_remaining))
	_late = world.match_phase == SimWorld.MatchPhase.PLAYING and seconds_left <= LAST_SECONDS
	_clock.add_theme_color_override("font_color", UiTheme.CHARCOAL if _late else UiTheme.CREAM)
	_round.add_theme_color_override("font_color", UiTheme.CHARCOAL if _late else Color(UiTheme.CREAM, 0.75))
	_place(_clock, _plate_rect.position + Vector2(0.0, 2.0), Vector2(PLATE_SIZE.x, 44.0))
	_round.text = "ROUND %d" % world.round_number
	_place(_round, _plate_rect.position + Vector2(0.0, 42.0), Vector2(PLATE_SIZE.x, 18.0))

	_chip.visible = false
	_jail.visible = false
	if mine != null:
		if mine.is_captured:
			_jail_text.text = "JAILED  %d" % ceili(SimWorld.ticks_to_seconds(mine.capture_ticks_remaining))
			_jail.visible = true
		elif mine.is_carrying():
			_set_chip(_note, "CARRYING CASH", false)
		if not mine.is_captured and input != null:
			var ally: int = input.rescue_target(world)
			if ally != SimEntity.NO_ENTITY:
				_set_chip(UiTheme.icon("unlocked"), "[%s]  FREE A TEAMMATE" %
					OS.get_keycode_string(PlayerSettings.current().key_for(&"seize")), true)
	_centre(_chip, size.y - 132.0)
	_centre(_jail, size.y * 0.3)
	queue_redraw()

func _set_chip(icon: Texture2D, text: String, urgent: bool) -> void:
	_chip_icon.texture = icon
	_chip_icon.visible = icon != null
	_chip_text.text = text
	_chip_text.add_theme_color_override("font_color", UiTheme.CHARCOAL if urgent else UiTheme.CREAM)
	_chip_icon.modulate = UiTheme.CHARCOAL if urgent else Color.WHITE
	if urgent:
		_chip.add_theme_stylebox_override("panel", _chip_urgent)
	else:
		_chip.remove_theme_stylebox_override("panel")
	_chip.visible = true

func _centre(control: Control, top: float) -> void:
	control.reset_size()
	control.position = Vector2((size.x - control.size.x) * 0.5, top)

static func _place(control: Control, at: Vector2, extent: Vector2) -> void:
	control.position = at
	control.size = extent

func _process(delta: float) -> void:
	if not visible:
		return
	_split = move_toward(_split, _target, delta / EASE_SECONDS)
	_bump_left = maxf(_bump_left - delta, 0.0)
	_bump_right = maxf(_bump_right - delta, 0.0)
	_apply_bump(_left_count, _bump_left, true)
	_apply_bump(_right_count, _bump_right, false)
	queue_redraw()

## The banked-cash count grows 1.0 -> 1.15 -> 1.0 over BUMP_SECONDS (P5-4).
func _apply_bump(label: Label, left: float, from_right: bool) -> void:
	var t: float = 1.0 - left / BUMP_SECONDS if left > 0.0 else 1.0
	var grow: float = BUMP_SCALE * sin(t * PI) if left > 0.0 else 0.0
	label.pivot_offset = Vector2(label.size.x if from_right else 0.0, label.size.y * 0.5)
	label.scale = Vector2.ONE * (1.0 + grow)

func _draw() -> void:
	if _bar_rect.size.x <= 0.0:
		return
	var first_colour: Color = _colours.get(_first_id, Color(0.48, 0.58, 0.45))
	var second_colour: Color = _colours.get(_second_id, Color(0.7, 0.4, 0.3))
	draw_rect(_bar_rect.grow(4.0), Color(UiTheme.CHARCOAL, 0.35))
	var left_w: float = _bar_rect.size.x * _split
	draw_rect(Rect2(_bar_rect.position, Vector2(left_w, BAR_HEIGHT)), first_colour)
	draw_rect(Rect2(_bar_rect.position + Vector2(left_w, 0.0),
		Vector2(_bar_rect.size.x - left_w, BAR_HEIGHT)), second_colour)
	# A lighter top half on each colour: a painted board catching the light, flat.
	draw_rect(Rect2(_bar_rect.position, Vector2(_bar_rect.size.x, BAR_HEIGHT * 0.35)), Color(1, 1, 1, 0.12))
	# The rope's knot: where the two colours meet.
	draw_rect(Rect2(_bar_rect.position.x + left_w - 2.0, _bar_rect.position.y - 4.0, 4.0, BAR_HEIGHT + 8.0), UiTheme.CREAM)
	draw_style_box(_bar_frame, _bar_rect)
	# The banknote beside each count, outside the bar's ends.
	if _note != null:
		var note_y: float = _bar_rect.get_center().y - NOTE_SIZE.y * 0.5
		draw_texture_rect(_note, Rect2(Vector2(_bar_rect.position.x - NOTE_GAP - NOTE_SIZE.x, note_y), NOTE_SIZE), false)
		draw_texture_rect(_note, Rect2(Vector2(_bar_rect.end.x + NOTE_GAP, note_y), NOTE_SIZE), false)
	# Round wins as dots under each name, filled in the family colour.
	var dot_y: float = _bar_rect.end.y + 4.0 + 40.0 + 11.0
	for i: int in _to_win:
		_pip(Vector2(_bar_rect.position.x + PIP_RADIUS + i * PIP_RADIUS * 3.0, dot_y), i < _wins.x, first_colour)
		_pip(Vector2(_bar_rect.end.x - PIP_RADIUS - i * PIP_RADIUS * 3.0, dot_y), i < _wins.y, second_colour)
	draw_style_box(_plate_late if _late else _plate_box, _plate_rect)

func _pip(at: Vector2, won: bool, colour: Color) -> void:
	draw_circle(at, PIP_RADIUS + 2.0, UiTheme.CHARCOAL)
	draw_circle(at, PIP_RADIUS, colour if won else Color(UiTheme.CREAM, 0.85))
