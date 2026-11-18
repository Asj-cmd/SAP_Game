class_name FamilyNameBox
extends HBoxContainer
## One family's name box (PT3-3): a swatch in the family colour, a text field and
## a Clear button. Used by the lobby (one per family) and the main menu's solo
## setup. Presentation only: it says what was typed; whoever owns it decides
## what that means (`FamilyNames.set_typed`, `MatchLink.publish_names`).
##
## Typing is filtered as it happens with the same character rule as
## `FamilyNames.clean`, except that a trailing space is kept while the field has
## focus (or "Van Der" could never be typed); the stored name is always the
## fully cleaned one. A field that has focus is never overwritten by an echo.

signal edited(team_id: StringName, text: String)
signal cleared(team_id: StringName)

var team_id: StringName = &""
var _field: LineEdit = null
var _clear: Button = null
var _shown_revision: int = -1

static func make(team: StringName) -> FamilyNameBox:
	var box: FamilyNameBox = FamilyNameBox.new()
	box.team_id = team
	return box

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var swatch: ColorRect = ColorRect.new()
	swatch.color = ArtTheme.current().family_colours.get(team_id, UiTheme.GREY)
	swatch.custom_minimum_size = Vector2(14.0, 0.0)
	add_child(swatch)
	_field = LineEdit.new()
	_field.max_length = FamilyNames.MAX_TYPED
	_field.placeholder_text = FamilyNames.default_of(team_id)
	_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field.text_changed.connect(_on_text_changed)
	_field.focus_exited.connect(func() -> void: _field.text = FamilyNames.typed_of(team_id))
	_field.text_submitted.connect(func(_text: String) -> void: _field.release_focus())
	add_child(_field)
	_clear = Button.new()
	_clear.text = "Clear"
	_clear.theme_type_variation = UiTheme.SMALL_BUTTON
	_clear.pressed.connect(func() -> void:
		_field.text = ""
		cleared.emit(team_id))
	add_child(_clear)
	refresh()

## Whether this machine may type in it, and whether it shows Clear.
func set_rights(can_type: bool, can_clear: bool) -> void:
	_field.editable = can_type
	_field.focus_mode = Control.FOCUS_ALL if can_type else Control.FOCUS_NONE
	_clear.visible = can_clear

## Shows the stored typed name, unless the player is typing in this field.
func refresh() -> void:
	if _field == null or _shown_revision == FamilyNames.revision:
		return
	_shown_revision = FamilyNames.revision
	if not _field.has_focus():
		_field.text = FamilyNames.typed_of(team_id)

func _process(_delta: float) -> void:
	refresh()

func _on_text_changed(text: String) -> void:
	var typing: String = typing_filter(text)
	if typing != text:
		var caret: int = _field.caret_column - (text.length() - typing.length())
		_field.text = typing
		_field.caret_column = clampi(caret, 0, typing.length())
	edited.emit(team_id, FamilyNames.clean(typing))

## The character rule of `FamilyNames.clean` for text still being typed: no
## leading space, no double space, but one trailing space is allowed.
static func typing_filter(text: String) -> String:
	var kept: String = ""
	for i: int in text.length():
		var c: String = text[i]
		if c == " ":
			if kept != "" and not kept.ends_with(" "):
				kept += c
		elif FamilyNames.clean(c) == c:
			kept += c
	return kept.left(FamilyNames.MAX_TYPED)
