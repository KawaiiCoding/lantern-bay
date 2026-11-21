extends RefCounted
## Small UI kit for the shop and the request board. It uses the shared Style (scripts/ui/style.gd) when that
## script exists and falls back to the same look drawn here: cream panels, ink 3px borders, radius 22,
## big readable text for a 540x960 phone, touch targets at least 88 px tall.
## Style is loaded by path (not by class name) so a broken or missing Style never breaks the shop.

const CREAM := Color("fffaf2")
const INK := Color("6b4a3a")
const SOFT := Color("8a6e5d")
const ROW := Color("f8eedc")
const HILITE := Color("fff2c4")
const MINTY := Color("dff3e4")
const GREEN := Color("6fc2b6")      # -> Style kind "mint"
const PEACH := Color("f2c14e")      # -> Style kind "gold"
const PINK := Color("e2607a")       # -> Style kind "primary"
const GOLD := Color("f2c14e")
const DIS_FILL := Color("eadcc4")
const DIS_TEXT := Color("a8917f")
const MIN_TOUCH := 88.0

static var _style: Variant = null
static var _tried := false

## The Style script (loaded by path) when it has what we need, else null.
static func S() -> Variant:
	if not _tried:
		_tried = true
		if ResourceLoader.exists("res://scripts/ui/style.gd"):
			var s: Variant = load("res://scripts/ui/style.gd")
			if s is GDScript:
				var names := []
				for m in (s as GDScript).get_script_method_list(): names.append(str(m.get("name", "")))
				if "button" in names and "panel_box" in names and "label" in names:
					_style = s
	return _style

static func kind_of(fill: Color) -> String:
	if fill.is_equal_approx(GREEN): return "mint"
	if fill.is_equal_approx(PEACH): return "gold"
	if fill.is_equal_approx(PINK): return "primary"
	return "cream"

static func box(fill: Color, radius := 22, border := 3, pad := 0, border_col := INK) -> StyleBoxFlat:
	var st: Variant = S()
	if st != null and border_col == INK:
		var sb: StyleBoxFlat = st.panel_box(fill, radius, border, maxi(pad, 4), false)
		if pad <= 0: sb.set_content_margin_all(0)
		return sb
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_col
	if pad > 0: s.set_content_margin_all(pad)
	return s

static func label(text: String, size := 22, color := INK, wrap := false, bold := false) -> Label:
	var st: Variant = S()
	var l: Label
	if st != null:
		l = st.label(text, size, color, bold)
	else:
		l = Label.new()
		l.text = text
		l.add_theme_font_size_override("font_size", size)
		l.add_theme_color_override("font_color", color)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 60
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

## Chunky button (Style.button when available). `fill` picks the look: GREEN mint, PEACH gold, CREAM cream, PINK rose.
static func button(text: String, fill := GREEN, size := 22, min_h := MIN_TOUCH, min_w := 0.0) -> Button:
	var st: Variant = S()
	var b: Button
	if st != null:
		b = st.button(text, kind_of(fill), size, min_h)
		b.custom_minimum_size = Vector2(min_w, min_h)
		_tighten(b)
		return b
	b = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(min_w, min_h)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_disabled_color", DIS_TEXT)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_fallback_style(b, fill)
	_fallback_squish(b)
	return b

static func _tighten(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := b.get_theme_stylebox(state)
		if sb is StyleBoxFlat:
			sb.content_margin_left = 8
			sb.content_margin_right = 8

## Change a button's colour kind after creation (tab selection).
static func restyle(b: Button, fill: Color) -> void:
	var st: Variant = S()
	if st != null:
		var tmp: Button = st.button("x", kind_of(fill), 22, MIN_TOUCH)
		for state in ["normal", "hover", "pressed", "disabled"]:
			b.add_theme_stylebox_override(state, tmp.get_theme_stylebox(state))
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "font_disabled_color"]:
			b.add_theme_color_override(c, tmp.get_theme_color(c))
		b.add_theme_constant_override("outline_size", tmp.get_theme_constant("outline_size"))
		if tmp.has_theme_color_override("font_outline_color"):
			b.add_theme_color_override("font_outline_color", tmp.get_theme_color("font_outline_color"))
		tmp.free()
		_tighten(b)
	else:
		_fallback_style(b, fill)

static func _fallback_style(b: Button, fill: Color) -> void:
	var n := box(fill, 22, 3, 8)
	var h := box(fill.lightened(0.08), 22, 3, 8)
	var p := box(fill.darkened(0.12), 22, 3, 8)
	p.content_margin_top = 11
	p.content_margin_bottom = 5
	var d := box(DIS_FILL, 22, 3, 8, Color(INK.r, INK.g, INK.b, 0.3))
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("disabled", d)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

static func _fallback_squish(b: Button) -> void:
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	b.button_down.connect(func() -> void:
		if b.disabled: return
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2(0.94, 0.9), 0.06))
	var back := func() -> void:
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	b.button_up.connect(back)
	b.mouse_exited.connect(back)

## Small rounded tag ("Special x2").
static func chip(text: String, bg := GOLD, fg := INK, size := 16) -> Control:
	var st: Variant = S()
	if st != null:
		var names := []
		for m in (st as GDScript).get_script_method_list(): names.append(str(m.get("name", "")))
		if "chip" in names:
			var c: Variant = st.chip(text, bg, fg, size)
			if c is Control:
				(c as Control).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				return c
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.add_theme_stylebox_override("panel", box(bg, 14, 2, 4))
	p.add_child(label(text, size, fg))
	return p

## A scroll area that scrolls by dragging (touch) and never shows a horizontal bar.
static func scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	s.scroll_deadzone = 14
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s

static func card(fill := ROW, pad := 12, radius := 20, border := 2) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(fill, radius, border, pad))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p

## A pop-in for a freshly built panel: grows from 92% with a little overshoot.
static func pop_in(c: Control) -> void:
	c.pivot_offset = c.custom_minimum_size * 0.5
	c.scale = Vector2(0.92, 0.92)
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, 0.12)

## The shared yen note icon (Style.icon("yen")) when available, else null.
static func yen_icon(size: float) -> Control:
	var st: Variant = S()
	if st != null:
		var names := []
		for m in (st as GDScript).get_script_method_list(): names.append(str(m.get("name", "")))
		if "icon" in names:
			var ic: Variant = st.icon("yen", size)
			if ic is Control: return ic
	return null
