class_name UiTheme
extends RefCounted
## The one Theme every screen uses (PT2-6): fonts, panels, buttons, fields,
## checkboxes, sliders and pickers, built once in code. Every look number is a
## const here, so changing the UI's look is this file.
##
## The look is a plain painted sign (an estate agent's board): cream cards with a
## charcoal border, charcoal buttons with cream lettering, mustard for hover and
## focus. Flat, no gradients, no glow, no bounce (D2 deadpan). Family colours
## (ArtTheme) appear only on the HUD bar and the results card.
##
## Presentation only.

const CREAM: Color = Color(0.95, 0.92, 0.85)
const CREAM_DARK: Color = Color(0.88, 0.84, 0.75)
const PAPER: Color = Color(0.99, 0.97, 0.93)
const CHARCOAL: Color = Color(0.16, 0.15, 0.14)
const CHARCOAL_SOFT: Color = Color(0.16, 0.15, 0.14, 0.62)
const MUSTARD: Color = Color(0.85, 0.66, 0.25)
const MUSTARD_DARK: Color = Color(0.68, 0.51, 0.17)
const GREY: Color = Color(0.55, 0.53, 0.5)
const ERROR: Color = Color(0.66, 0.2, 0.16)

const BORDER: int = 3
const CORNER: int = 6
const PANEL_MARGIN: int = 26
const BODY_SIZE: int = 18
const SMALL_SIZE: int = 14
const BUTTON_SIZE: int = 22
const TITLE_SIZE: int = 44
const HUD_OUTLINE: int = 7

## One finish for every card and button (PT4-7): a soft shadow under it, which a
## held button nearly loses. Hover = HOVER_SCALE + the mustard fill; press =
## PRESS_SCALE + SHADOW_PRESSED.
const SHADOW_COLOUR: Color = CHARCOAL_SOFT
const SHADOW_SIZE: int = 4
const SHADOW_OFFSET: int = 3
const SHADOW_PRESSED: int = 1

const HOVER_SCALE: float = 1.04
const PRESS_SCALE: float = 0.97
const HOVER_SECONDS: float = 0.08
const OPEN_SECONDS: float = 0.15
const OPEN_RISE: float = 12.0

const DISPLAY_FONT_PATH: String = "res://art/ui/fonts/Anton-Regular.ttf"
const BODY_FONT_PATH: String = "res://art/ui/fonts/Inter-Variable.ttf"
const ICON_DIR: String = "res://art/ui/icons/"

## Type variations, set through `theme_type_variation`.
const TITLE: StringName = &"TitleLabel"      ## Anton, charcoal, on a card
const HEADING: StringName = &"HeadingLabel"  ## Anton, small, a section name
const NOTE: StringName = &"NoteLabel"        ## small, soft charcoal
const HUD: StringName = &"HudLabel"          ## cream with a charcoal outline, over the world
const HUD_BIG: StringName = &"HudBigLabel"   ## Anton, cream, outline: headlines
const SMALL_BUTTON: StringName = &"SmallButton"
const CARD: StringName = &"CardPanel"        ## the cream card (PanelContainer)
const PLATE: StringName = &"PlatePanel"      ## a charcoal plate (PanelContainer)

static var _theme: Theme = null
static var _display: Font = null
static var _body: Font = null
static var _body_bold: Font = null

static func current() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme

static func display_font() -> Font:
	if _display == null:
		_display = _load_font(DISPLAY_FONT_PATH)
	return _display

static func body_font() -> Font:
	if _body == null:
		_body = _weighted(_load_font(BODY_FONT_PATH), 450)
	return _body

static func body_bold() -> Font:
	if _body_bold == null:
		_body_bold = _weighted(_load_font(BODY_FONT_PATH), 650)
	return _body_bold

## A HUD icon from `art/ui/icons/`, or null when the file is missing (art stays optional).
static func icon(name: String) -> Texture2D:
	var path: String = ICON_DIR + name + ".png"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

static var _cash: Texture2D = null

## A plain banknote drawn in code (the icon pack has none): charcoal edge, green
## paper, a paler border line and a round middle. 72 x 44, drawn at half size.
static func cash_icon() -> Texture2D:
	if _cash != null:
		return _cash
	var w: int = 72
	var h: int = 44
	var image: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	image.fill_rect(Rect2i(0, 0, w, h), CHARCOAL)
	image.fill_rect(Rect2i(4, 4, w - 8, h - 8), CASH_GREEN)
	image.fill_rect(Rect2i(9, 9, w - 18, h - 18), CASH_PALE)
	image.fill_rect(Rect2i(12, 12, w - 24, h - 24), CASH_GREEN)
	var middle: Vector2 = Vector2(w * 0.5, h * 0.5)
	for y: int in h:
		for x: int in w:
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(middle)
			if d <= 9.0:
				image.set_pixel(x, y, CASH_PALE if d <= 6.5 else CHARCOAL)
	_cash = ImageTexture.create_from_image(image)
	return _cash

const CASH_GREEN: Color = Color(0.3, 0.55, 0.35)
const CASH_PALE: Color = Color(0.72, 0.84, 0.66)

static func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var loaded: Font = load(path) as Font
		if loaded != null:
			return loaded
	return ThemeDB.fallback_font

static func _weighted(base: Font, weight: int) -> Font:
	if base == ThemeDB.fallback_font:
		return base
	var made: FontVariation = FontVariation.new()
	made.base_font = base
	made.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return made

# ---- building ----

static func _build() -> Theme:
	var t: Theme = Theme.new()
	t.default_font = body_font()
	t.default_font_size = BODY_SIZE

	# Labels: charcoal, because they sit on cream cards.
	t.set_color("font_color", "Label", CHARCOAL)
	t.set_font("font", "Label", body_font())
	_variation(t, TITLE, "Label")
	t.set_font("font", TITLE, display_font())
	t.set_font_size("font_size", TITLE, TITLE_SIZE)
	_variation(t, HEADING, "Label")
	t.set_font("font", HEADING, display_font())
	t.set_font_size("font_size", HEADING, 20)
	_variation(t, NOTE, "Label")
	t.set_color("font_color", NOTE, CHARCOAL_SOFT)
	t.set_font_size("font_size", NOTE, SMALL_SIZE)
	_variation(t, HUD, "Label")
	t.set_font("font", HUD, body_bold())
	t.set_color("font_color", HUD, CREAM)
	t.set_color("font_outline_color", HUD, CHARCOAL)
	t.set_constant("outline_size", HUD, HUD_OUTLINE)
	_variation(t, HUD_BIG, "Label")
	t.set_font("font", HUD_BIG, display_font())
	t.set_color("font_color", HUD_BIG, CREAM)
	t.set_color("font_outline_color", HUD_BIG, CHARCOAL)
	t.set_constant("outline_size", HUD_BIG, 12)
	t.set_font_size("font_size", HUD_BIG, 52)

	t.set_color("default_color", "RichTextLabel", CHARCOAL)
	t.set_font("normal_font", "RichTextLabel", body_font())
	t.set_font("bold_font", "RichTextLabel", body_bold())
	t.set_font_size("normal_font_size", "RichTextLabel", 15)
	t.set_font_size("bold_font_size", "RichTextLabel", 16)
	t.set_stylebox("normal", "RichTextLabel", _box(PAPER, CHARCOAL_SOFT, 1, 4, 10))
	t.set_stylebox("focus", "RichTextLabel", StyleBoxEmpty.new())

	# Panels.
	t.set_stylebox("panel", "PanelContainer", _lift(_box(CREAM, CHARCOAL, BORDER, CORNER, PANEL_MARGIN), SHADOW_OFFSET))
	_variation(t, CARD, "PanelContainer")
	t.set_stylebox("panel", CARD, _lift(_box(CREAM, CHARCOAL, BORDER, CORNER, PANEL_MARGIN), SHADOW_OFFSET))
	_variation(t, PLATE, "PanelContainer")
	t.set_stylebox("panel", PLATE, _box(CHARCOAL, CHARCOAL, 0, 4, 8, 3))

	# Buttons: charcoal slabs, cream Anton; mustard when hovered or focused.
	_button_type(t, "Button", BUTTON_SIZE, 10)
	_variation(t, SMALL_BUTTON, "Button")
	_button_styles(t, SMALL_BUTTON, 6)
	t.set_font_size("font_size", SMALL_BUTTON, 17)
	_button_type(t, "OptionButton", 17, 6)
	t.set_constant("arrow_margin", "OptionButton", 10)

	# Popups (the OptionButton list).
	t.set_stylebox("panel", "PopupMenu", _box(CREAM, CHARCOAL, 2, 4, 6))
	t.set_stylebox("hover", "PopupMenu", _box(MUSTARD, MUSTARD, 0, 2, 4))
	t.set_color("font_color", "PopupMenu", CHARCOAL)
	t.set_color("font_hover_color", "PopupMenu", CHARCOAL)
	t.set_font("font", "PopupMenu", body_font())
	t.set_font_size("font_size", "PopupMenu", 16)
	t.set_icon("radio_checked", "PopupMenu", _check_icon(true, true))
	t.set_icon("radio_unchecked", "PopupMenu", _check_icon(false, true))

	# Text fields: paper with a thin charcoal line.
	t.set_stylebox("normal", "LineEdit", _box(PAPER, CHARCOAL, 2, 4, 10))
	t.set_stylebox("focus", "LineEdit", _box(Color(0, 0, 0, 0), MUSTARD, 3, 4, 10))
	t.set_color("font_color", "LineEdit", CHARCOAL)
	t.set_color("font_placeholder_color", "LineEdit", Color(CHARCOAL, 0.4))
	t.set_color("caret_color", "LineEdit", CHARCOAL)
	t.set_color("selection_color", "LineEdit", Color(MUSTARD, 0.5))
	t.set_font_size("font_size", "LineEdit", 17)

	# Checkboxes: a drawn square box, mustard with a charcoal block when on.
	for kind: String in ["CheckBox", "CheckButton"]:
		t.set_color("font_color", kind, CHARCOAL)
		t.set_color("font_hover_color", kind, CHARCOAL)
		t.set_color("font_pressed_color", kind, CHARCOAL)
		t.set_color("font_hover_pressed_color", kind, CHARCOAL)
		t.set_color("font_focus_color", kind, CHARCOAL)
		t.set_font_size("font_size", kind, 16)
		t.set_font("font", kind, body_font())
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			t.set_stylebox(state, kind, _flat_margin(4))
		t.set_icon("checked", kind, _check_icon(true, false))
		t.set_icon("unchecked", kind, _check_icon(false, false))
		t.set_constant("h_separation", kind, 8)

	# Sliders: a charcoal groove, mustard fill, a charcoal tab.
	var groove: StyleBoxFlat = _box(CREAM_DARK, CHARCOAL, 2, 3, 0)
	groove.content_margin_top = 4
	groove.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", groove)
	var fill: StyleBoxFlat = _box(MUSTARD, CHARCOAL, 2, 3, 0)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _tab_icon(CHARCOAL))
	t.set_icon("grabber_highlight", "HSlider", _tab_icon(MUSTARD_DARK))

	var line: StyleBoxLine = StyleBoxLine.new()
	line.color = Color(CHARCOAL, 0.25)
	line.thickness = 2
	t.set_stylebox("separator", "HSeparator", line)
	t.set_constant("separation", "HSeparator", 10)

	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	return t

static func _variation(t: Theme, name: StringName, base: StringName) -> void:
	t.set_type_variation(name, base)

static func _button_type(t: Theme, kind: StringName, font_size: int, pad: int) -> void:
	_button_styles(t, kind, pad)
	t.set_font_size("font_size", kind, font_size)

static func _button_styles(t: Theme, kind: StringName, pad: int) -> void:
	t.set_font("font", kind, display_font())
	t.set_stylebox("normal", kind, _lift(_box(CHARCOAL, CHARCOAL, 0, CORNER, pad, 0, 18), SHADOW_OFFSET))
	t.set_stylebox("hover", kind, _lift(_box(MUSTARD, CHARCOAL, BORDER, CORNER, pad, 0, 18), SHADOW_OFFSET))
	t.set_stylebox("pressed", kind, _lift(_box(MUSTARD_DARK, CHARCOAL, BORDER, CORNER, pad, 0, 18), SHADOW_PRESSED))
	t.set_stylebox("hover_pressed", kind, _lift(_box(MUSTARD_DARK, CHARCOAL, BORDER, CORNER, pad, 0, 18), SHADOW_PRESSED))
	t.set_stylebox("disabled", kind, _box(GREY, GREY, 0, CORNER, pad, 0, 18))
	var focus: StyleBoxFlat = _box(Color(0, 0, 0, 0), MUSTARD, BORDER, CORNER + 2, 0)
	focus.expand_margin_left = 3
	focus.expand_margin_right = 3
	focus.expand_margin_top = 3
	focus.expand_margin_bottom = 3
	t.set_stylebox("focus", kind, focus)
	t.set_color("font_color", kind, CREAM)
	t.set_color("font_focus_color", kind, CREAM)
	t.set_color("font_hover_color", kind, CHARCOAL)
	t.set_color("font_pressed_color", kind, CHARCOAL)
	t.set_color("font_hover_pressed_color", kind, CHARCOAL)
	t.set_color("font_disabled_color", kind, Color(CREAM, 0.6))
	t.set_color("icon_normal_color", kind, CREAM)
	t.set_color("icon_hover_color", kind, CHARCOAL)
	t.set_color("icon_pressed_color", kind, CHARCOAL)

## A flat box; `shadow` is a hard drop shadow offset down-right (0 = none).
static func _box(fill: Color, edge: Color, border: int, corner: int, margin: int,
		shadow: int = 0, side_margin: int = -1) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(border)
	box.set_corner_radius_all(corner)
	box.content_margin_left = side_margin if side_margin >= 0 else margin
	box.content_margin_right = side_margin if side_margin >= 0 else margin
	box.content_margin_top = margin
	box.content_margin_bottom = margin
	box.anti_aliasing = true
	if shadow > 0:
		box.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
		box.shadow_size = 0
		box.shadow_offset = Vector2(shadow, shadow)
	return box

## PT4-7: the one finish for cards and buttons, a soft drop shadow straight down;
## a held button's shadow shrinks to SHADOW_PRESSED, so it reads as pushed in.
static func _lift(box: StyleBoxFlat, offset: int) -> StyleBoxFlat:
	box.shadow_color = SHADOW_COLOUR
	box.shadow_size = SHADOW_SIZE
	box.shadow_offset = Vector2(0.0, offset)
	return box

static func _flat_margin(margin: int) -> StyleBoxEmpty:
	var box: StyleBoxEmpty = StyleBoxEmpty.new()
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = margin
	box.content_margin_bottom = margin
	return box

## A 22 px square box: charcoal edge, paper inside; on = mustard with a charcoal block.
static func _check_icon(on: bool, small: bool) -> Texture2D:
	var side: int = 16 if small else 22
	var image: Image = Image.create(side, side, false, Image.FORMAT_RGBA8)
	image.fill(CHARCOAL)
	image.fill_rect(Rect2i(2, 2, side - 4, side - 4), MUSTARD if on else PAPER)
	if on:
		var inset: int = 6 if not small else 5
		image.fill_rect(Rect2i(inset, inset, side - inset * 2, side - inset * 2), CHARCOAL)
	return ImageTexture.create_from_image(image)

## The slider's tab: a 14 x 24 block with a one-pixel cream inset line.
static func _tab_icon(colour: Color) -> Texture2D:
	var image: Image = Image.create(14, 24, false, Image.FORMAT_RGBA8)
	image.fill(colour)
	image.fill_rect(Rect2i(6, 6, 2, 12), CREAM)
	return ImageTexture.create_from_image(image)

# ---- small animations (short, plain: a fade, a rise, a small scale) ----

## Every Button under `root` grows a little on hover and shrinks a little while held.
static func animate_buttons(root: Node) -> void:
	for child: Node in root.get_children():
		animate_buttons(child)
	var button: BaseButton = root as BaseButton
	if button == null or button is CheckBox or button.has_meta(&"ui_animated"):
		return
	button.set_meta(&"ui_animated", true)
	button.resized.connect(func() -> void: button.pivot_offset = button.size * 0.5)
	button.mouse_entered.connect(func() -> void: _scale_to(button, HOVER_SCALE))
	button.mouse_exited.connect(func() -> void: _scale_to(button, 1.0))
	button.button_down.connect(func() -> void: _scale_to(button, PRESS_SCALE))
	button.button_up.connect(func() -> void:
		_scale_to(button, HOVER_SCALE if button.is_hovered() else 1.0))

static func _scale_to(control: Control, target: float) -> void:
	if not control.is_inside_tree():
		return
	control.pivot_offset = control.size * 0.5
	var tween: Tween = control.create_tween()
	tween.tween_property(control, "scale", Vector2.ONE * target, HOVER_SECONDS)

## A layer opening: its content fades in and rises OPEN_RISE px over OPEN_SECONDS.
static func open_layer(layer: CanvasLayer, content: CanvasItem) -> void:
	if not layer.is_inside_tree():
		return
	layer.offset = Vector2(0.0, OPEN_RISE)
	content.modulate.a = 0.0
	var tween: Tween = layer.create_tween().set_parallel(true)
	tween.tween_property(layer, "offset", Vector2.ZERO, OPEN_SECONDS).set_ease(Tween.EASE_OUT)
	tween.tween_property(content, "modulate:a", 1.0, OPEN_SECONDS)

## A card shown inside an open layer: a fade only (a container owns its position).
static func fade_in(content: CanvasItem) -> void:
	if not content.is_inside_tree():
		return
	content.modulate.a = 0.0
	content.create_tween().tween_property(content, "modulate:a", 1.0, OPEN_SECONDS)

## A cream card holding `content`, centred in `parent` (a full-rect CenterContainer).
static func card(content: Control) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.theme_type_variation = CARD
	panel.add_child(content)
	return panel

## The dimming behind a card over the world: a charcoal wash, not black.
static func shade() -> ColorRect:
	var rect: ColorRect = ColorRect.new()
	rect.color = Color(CHARCOAL, 0.55)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	return rect
