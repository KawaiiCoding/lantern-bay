class_name Style
extends RefCounted
## Style (static helpers): the cozy UI kit. Cream panels, warm ink borders, rose / mint / gold accents.
## No emojis anywhere: icons are vector shapes drawn in code (Style.icon).
##
##   Style.panel_box(bg)                -> StyleBoxFlat
##   Style.button(text, kind)           -> Button   kinds: primary(rose) mint gold cream ghost
##   Style.icon_button(icon, kind)      -> Button   round, icon only, 88 px touch target
##   Style.label(text, size, color, bold) -> Label
##   Style.icon(name, size, tint)       -> Control  coin(=yen) yen clock sun moon cloud rain fog cat fish shell bag
##                                                  book moped hand heart heart_off spark star check close paw
##                                                  person note lock gear glass wood bottle flower dollar
##   Style.money(n) -> "¥1,250"          Style.hearts(n, max, size)   Style.bar(value, max, color)
##   Style.chip(text, bg, fg, size)      Style.squish(control)        Style.font(bold)
##   Style.slider(value)                 -> Control, signal value_changed(v) 0..1

const CREAM := Color("fffaf2")
const CREAM_DEEP := Color("f8eedc")      # inset cards
const CREAM_SHADE := Color("eadcc4")     # tracks, disabled fills
const INK := Color("6b4a3a")
const INK_SOFT := Color("8a6e5d")        # secondary text (4.5:1 on cream)
const ROSE := Color("e2607a")
const ROSE_DARK := Color("b8435c")
const MINT := Color("6fc2b6")
const MINT_DARK := Color("3f9488")
const GOLD := Color("f2c14e")
const GOLD_DARK := Color("c9962a")
const SKY := Color("9cc8ef")
const NIGHT := Color("3d3a72")
const DIM := Color(0.27, 0.17, 0.13, 0.58)
const SHADOW := Color(0.42, 0.29, 0.23, 0.30)

const MIN_TOUCH := 88.0                  # minimum touch target height (owner rule)

## kind -> colours. bg fill, fg text/icon, edge = darker rim colour used for text outlines.
const KINDS := {
	"primary": {"bg": ROSE, "fg": CREAM, "edge": ROSE_DARK},
	"mint": {"bg": MINT, "fg": CREAM, "edge": MINT_DARK},
	"gold": {"bg": GOLD, "fg": INK, "edge": GOLD_DARK},
	"cream": {"bg": CREAM, "fg": INK, "edge": CREAM_SHADE},
	"ghost": {"bg": CREAM_DEEP, "fg": INK, "edge": CREAM_SHADE},
}

static var _bold: FontVariation
static var _boxes := {}
static var _theme: Theme

# ------------------------------------------------------------------ text
static func font(bold := true) -> Font:
	var base: Font = ThemeDB.fallback_font
	if not bold: return base
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = base
		_bold.variation_embolden = 0.7
	return _bold

static func label(text: String, size := 22, color := INK, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold: l.add_theme_font_override("font", font(true))
	return l

## "¥1,250". Negative numbers keep their sign.
static func money(n: Variant) -> String:
	var v := int(n)
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + "¥" + s + out

## Width in px of a string at a size (for fitting text).
static func text_width(text: String, size: int, bold := true) -> float:
	return font(bold).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

# ------------------------------------------------------------------ boxes
## Cream panel: ink border, rounded corners, soft drop shadow.
static func panel_box(bg := CREAM, radius := 22, border := 3, margin := 16, shadow := true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = INK
	sb.set_border_width_all(border)
	sb.set_corner_radius_all(radius)
	sb.set_corner_detail(10)
	sb.content_margin_left = margin; sb.content_margin_right = margin
	sb.content_margin_top = maxi(margin - 4, 4); sb.content_margin_bottom = maxi(margin - 4, 4)
	if shadow:
		sb.shadow_color = SHADOW
		sb.shadow_size = 8
		sb.shadow_offset = Vector2(0, 4)
	return sb

## Button / round-button box for a kind and state ("normal", "hover", "pressed", "disabled"). Cached.
static func box(kind: String, state := "normal", radius := 24) -> StyleBoxFlat:
	var key := "%s/%s/%d" % [kind, state, radius]
	if _boxes.has(key): return _boxes[key]
	var k: Dictionary = KINDS.get(kind, KINDS["primary"])
	var bg: Color = k["bg"]
	var sb := StyleBoxFlat.new()
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(radius)
	sb.set_corner_detail(14)
	sb.border_color = INK
	match state:
		"hover": bg = bg.lightened(0.07)
		"pressed": bg = bg.darkened(0.13)
		"disabled":
			bg = CREAM_SHADE.lerp(bg, 0.12)
			sb.border_color = Color(INK, 0.35)
	sb.bg_color = bg
	if state == "normal" or state == "hover":
		sb.shadow_color = SHADOW; sb.shadow_size = 7; sb.shadow_offset = Vector2(0, 5)
	elif state == "pressed":
		sb.shadow_color = SHADOW; sb.shadow_size = 2; sb.shadow_offset = Vector2(0, 1)
	_boxes[key] = sb
	return sb

static func chip_box(bg: Color, radius := 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg; sb.border_color = INK; sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius); sb.set_corner_detail(8)
	sb.content_margin_left = 12; sb.content_margin_right = 12; sb.content_margin_top = 3; sb.content_margin_bottom = 3
	return sb

static func chip(text: String, bg := GOLD, fg := INK, size := 17) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", chip_box(bg))
	p.add_child(label(text, size, fg, true))
	return p

# ------------------------------------------------------------------ buttons
## Chunky button: rounded, ink border, soft shadow, squishes on press, clear disabled state. 88 px tall by default.
static func button(text: String, kind := "primary", size := 26, min_h := MIN_TOUCH) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(min_h * 1.6, min_h)
	var k: Dictionary = KINDS.get(kind, KINDS["primary"])
	for st in ["normal", "hover", "pressed", "disabled"]:
		var sb := box(kind, st).duplicate() as StyleBoxFlat
		sb.content_margin_left = 28; sb.content_margin_right = 28; sb.content_margin_top = 10; sb.content_margin_bottom = 12
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_override("font", font(true))
	b.add_theme_font_size_override("font_size", size)
	var fg: Color = k["fg"]
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, fg)
	b.add_theme_color_override("font_disabled_color", Color(INK_SOFT, 0.75))
	if fg == CREAM:   # light text on a saturated fill gets a sticker outline
		b.add_theme_constant_override("outline_size", 5)
		b.add_theme_color_override("font_outline_color", k["edge"])
	squish(b)
	return b

## Round icon-only button (visual circle `visual` px, touch target `hit` px). kind as for button().
static func icon_button(icon_name: String, kind := "primary", visual := 64.0, hit := MIN_TOUCH) -> Button:
	var b := IconButton.new()
	b.setup(icon_name, kind, visual, maxf(hit, visual))
	squish(b)
	return b

## Squish on press: connect to any BaseButton (done by button() / icon_button()).
static func squish(c: Control, amount := 0.93) -> void:
	c.pivot_offset_ratio = Vector2(0.5, 0.5)
	if c is BaseButton:
		c.button_down.connect(press_anim.bind(c, true, amount))
		c.button_up.connect(press_anim.bind(c, false, amount))

static func _kill_tween(c: Control) -> void:
	if c.has_meta("_sq_tw"):
		var old = c.get_meta("_sq_tw")
		if old is Tween and old.is_valid(): old.kill()

## Tween scale down (down = true) or back with a little overshoot. For custom touch controls.
static func press_anim(c: Control, down: bool, amount := 0.93) -> void:
	if not is_instance_valid(c) or not c.is_inside_tree(): return
	_kill_tween(c)
	var tw := c.create_tween()
	c.set_meta("_sq_tw", tw)
	if down:
		tw.tween_property(c, "scale", Vector2(amount, amount), 0.06).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_property(c, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Scale pop (1 -> k -> 1) for "something changed" feedback.
static func pop(c: Control, k := 1.12) -> void:
	if not is_instance_valid(c) or not c.is_inside_tree(): return
	_kill_tween(c)
	var tw := c.create_tween()
	c.set_meta("_sq_tw", tw)
	tw.tween_property(c, "scale", Vector2(k, k), 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Theme with a slim rounded scroll bar, for ScrollContainers inside panels.
static func theme() -> Theme:
	if _theme: return _theme
	_theme = Theme.new()
	var track := StyleBoxFlat.new()
	track.bg_color = Color(INK, 0.08); track.set_corner_radius_all(6)
	track.content_margin_left = 6; track.content_margin_right = 6
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(INK, 0.45); grab.set_corner_radius_all(6)
	grab.content_margin_left = 6; grab.content_margin_right = 6
	var grab_h := grab.duplicate() as StyleBoxFlat
	grab_h.bg_color = Color(ROSE, 0.8)
	_theme.set_stylebox("scroll", "VScrollBar", track)
	_theme.set_stylebox("grabber", "VScrollBar", grab)
	_theme.set_stylebox("grabber_highlight", "VScrollBar", grab_h)
	_theme.set_stylebox("grabber_pressed", "VScrollBar", grab_h)
	return _theme

# ------------------------------------------------------------------ small widgets
static func icon(name: String, size := 28.0, tint := Color(0, 0, 0, 0)) -> Control:
	return Icon.new(name, size, tint)

## Row of drawn hearts: `n` filled out of `total`.
static func hearts(n: int, total := 5, size := 22.0, gap := 2) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", gap)
	for i in total:
		h.add_child(icon("heart" if i < n else "heart_off", size))
	return h

## Slim progress capsule.
static func bar(value: float, max_value: float, color := MINT, height := 16.0) -> Control:
	var b := Bar.new()
	b.value = value; b.max_value = maxf(max_value, 0.0001); b.color = color
	b.custom_minimum_size = Vector2(40, height)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b

## Big touch slider 0..1 (88 px tall hit area). Connect to its `value_changed(v)` signal.
static func slider(value := 0.5) -> Control:
	var sl := TouchSlider.new()
	sl.value = value
	return sl

static func spacer(h := 8.0, w := 0.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

# ================================================================== inner classes
class Bar extends Control:
	var value := 0.0
	var max_value := 1.0
	var color := Style.MINT
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var h := size.y
		var r := h * 0.5
		var track := StyleBoxFlat.new()
		track.bg_color = Style.CREAM_SHADE; track.border_color = Style.INK; track.set_border_width_all(2)
		track.set_corner_radius_all(int(r)); track.set_corner_detail(8)
		draw_style_box(track, Rect2(Vector2.ZERO, size))
		var f := clampf(value / max_value, 0.0, 1.0)
		if f > 0.0:
			var w := maxf(h - 4.0, (size.x - 4.0) * f)
			var fill := StyleBoxFlat.new()
			fill.bg_color = color; fill.set_corner_radius_all(int(r) - 2); fill.set_corner_detail(8)
			draw_style_box(fill, Rect2(Vector2(2, 2), Vector2(w, h - 4.0)))

## Rounded slider: capsule track, mint fill, round knob. Drag anywhere along it.
class TouchSlider extends Control:
	signal value_changed(v: float)
	var value := 0.5 : set = set_value
	var _drag := false
	func _init() -> void:
		custom_minimum_size = Vector2(120, Style.MIN_TOUCH)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	func set_value(v: float) -> void:
		value = clampf(v, 0.0, 1.0)
		queue_redraw()
	func _knob_x() -> float:
		return 30.0 + (size.x - 60.0) * value
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			_drag = e.pressed
			if e.pressed: _set_from(e.position.x)
			queue_redraw()
		elif e is InputEventMouseMotion and _drag:
			_set_from(e.position.x)
	func _set_from(x: float) -> void:
		var v := clampf((x - 30.0) / maxf(size.x - 60.0, 1.0), 0.0, 1.0)
		if absf(v - value) > 0.0005:
			value = v
			value_changed.emit(v)
	func _draw() -> void:
		var cy := size.y * 0.5
		var th := 22.0
		var track := StyleBoxFlat.new()
		track.bg_color = Style.CREAM_SHADE; track.border_color = Style.INK; track.set_border_width_all(3)
		track.set_corner_radius_all(int(th)); track.set_corner_detail(8)
		draw_style_box(track, Rect2(Vector2(8, cy - th * 0.5), Vector2(size.x - 16, th)))
		var kx := _knob_x()
		if kx > 22.0:
			var fill := StyleBoxFlat.new()
			fill.bg_color = Style.MINT; fill.set_corner_radius_all(int(th)); fill.set_corner_detail(8)
			draw_style_box(fill, Rect2(Vector2(11, cy - th * 0.5 + 3), Vector2(kx - 11, th - 6)))
		var r := 25.0 if _drag else 23.0
		draw_circle(Vector2(kx, cy + 4), r, Style.SHADOW, true, -1.0, true)
		draw_circle(Vector2(kx, cy), r, Style.ROSE, true, -1.0, true)
		draw_arc(Vector2(kx, cy), r, 0.0, TAU, 40, Style.INK, 3.0, true)
		draw_arc(Vector2(kx, cy), r - 8.0, deg_to_rad(200.0), deg_to_rad(285.0), 10, Color(1, 1, 1, 0.5), 4.0, true)

## Round icon button: hit area `hit`, drawn circle `visual`.
class IconButton extends Button:
	var kind := "primary"
	var visual := 64.0
	var _icon: Control
	func setup(icon_name: String, k: String, vis: float, hit: float) -> void:
		kind = k; visual = vis
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		custom_minimum_size = Vector2(hit, hit)
		size = custom_minimum_size
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(st, empty)
		var col: Color = Style.KINDS.get(k, Style.KINDS["primary"])["fg"]
		_icon = Style.icon(icon_name, vis * 0.5, col)
		_icon.position = (custom_minimum_size - _icon.custom_minimum_size) * 0.5
		add_child(_icon)
	func _draw() -> void:
		var st := "normal"
		match get_draw_mode():
			DRAW_PRESSED, DRAW_HOVER_PRESSED: st = "pressed"
			DRAW_HOVER: st = "hover"
			DRAW_DISABLED: st = "disabled"
		var sb := Style.box(kind, st, int(visual))
		var off := (size - Vector2(visual, visual)) * 0.5
		draw_style_box(sb, Rect2(off, Vector2(visual, visual)))
		if _icon: _icon.modulate.a = 0.5 if disabled else 1.0

## Vector icon drawn in unit space. Sticker style: flat fill, ink outline.
class Icon extends Control:
	var kind := "yen"
	var tint := Color(0, 0, 0, 0)       # transparent = natural colours
	var _w := 0.06                      # outline width in unit space
	var _s := 28.0                      # icon size in px
	var _off := Vector2.ZERO

	func _init(k := "yen", sz := 28.0, c := Color(0, 0, 0, 0)) -> void:
		kind = k; tint = c
		custom_minimum_size = Vector2(sz, sz)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_kind(k: String, c := Color(0, 0, 0, 0)) -> void:
		kind = k; tint = c; queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED: queue_redraw()

	# ---- geometry helpers (unit space, y down)
	func _col(natural: Color) -> Color:
		return tint if tint.a > 0.0 else natural
	func _circ(c: Vector2, r: float, n := 28) -> PackedVector2Array:
		return _ell(c, r, r, n)
	func _ell(c: Vector2, rx: float, ry: float, n := 28) -> PackedVector2Array:
		var p := PackedVector2Array()
		for i in n:
			var a := TAU * float(i) / float(n)
			p.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		return p
	func _cap(a: Vector2, b: Vector2, r: float) -> PackedVector2Array:
		var p := PackedVector2Array()
		var d := (b - a).angle()
		for i in range(0, 9):
			var t := d - PI * 0.5 + PI * float(i) / 8.0
			p.append(b + Vector2(cos(t), sin(t)) * r)
		for i in range(0, 9):
			var t := d + PI * 0.5 + PI * float(i) / 8.0
			p.append(a + Vector2(cos(t), sin(t)) * r)
		return p
	func _rr(x: float, y: float, w: float, h: float, r: float) -> PackedVector2Array:
		var p := PackedVector2Array()
		var cs := [Vector2(x + w - r, y + r), Vector2(x + w - r, y + h - r), Vector2(x + r, y + h - r), Vector2(x + r, y + r)]
		for ci in 4:
			for i in range(0, 7):
				var t := PI * 0.5 * float(ci - 1) + PI * 0.5 * float(i) / 6.0
				p.append(cs[ci] + Vector2(cos(t), sin(t)) * r)
		return p
	func _rot(p: PackedVector2Array, ang: float, pivot: Vector2) -> PackedVector2Array:
		var out := PackedVector2Array()
		for v in p: out.append(pivot + (v - pivot).rotated(ang))
		return out
	func _heart_pts() -> PackedVector2Array:
		var p := PackedVector2Array()
		for i in 36:
			var t := TAU * float(i) / 36.0
			var x := 16.0 * pow(sin(t), 3.0)
			var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
			p.append(Vector2(0.5 + x / 38.0, 0.47 + y / 38.0))
		return p
	func _star_pts(c: Vector2, r_out: float, r_in: float, points: int, rot := -PI * 0.5) -> PackedVector2Array:
		var p := PackedVector2Array()
		for i in points * 2:
			var r := r_out if i % 2 == 0 else r_in
			var a := rot + PI * float(i) / float(points)
			p.append(c + Vector2(cos(a), sin(a)) * r)
		return p

	## Fill polygons with `fill`, drawn as ONE merged silhouette with an ink outline.
	func _blob(parts: Array, fill: Color) -> void:
		var acc: Array = [parts[0]]
		for i in range(1, parts.size()):
			acc.append(parts[i])
		var changed := true
		while changed and acc.size() > 1:
			changed = false
			for a in acc.size():
				for b in range(a + 1, acc.size()):
					var m := Geometry2D.merge_polygons(acc[a], acc[b])
					if m.size() == 1:
						acc[a] = m[0]
						acc.remove_at(b)
						changed = true
						break
				if changed: break
		for p in acc: _poly(p, fill)
	func _area(p: PackedVector2Array) -> float:
		var a := 0.0
		for i in p.size():
			var q := p[(i + 1) % p.size()]
			a += p[i].x * q.y - q.x * p[i].y
		return a * 0.5
	func _poly(p: PackedVector2Array, fill: Color) -> void:
		var grown := Geometry2D.offset_polygon(p, _w, Geometry2D.JOIN_ROUND)
		for g in grown: _fill(g, Style.INK)
		_fill(p, fill)
	## unit space -> pixels
	func _px(v: Vector2) -> Vector2:
		return _off + v * _s
	func _pxs(p: PackedVector2Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for v in p: out.append(_px(v))
		return out
	## filled polygon with an anti-aliased edge
	func _fill(p: PackedVector2Array, c: Color) -> void:
		if p.size() < 3 or Geometry2D.triangulate_polygon(p).is_empty(): return
		var q := _pxs(p)
		draw_colored_polygon(q, c)
		q.append(q[0])
		draw_polyline(q, c, 1.2, true)
	func _outline(p: PackedVector2Array, c: Color, w: float) -> void:
		var q := _pxs(p)
		q.append(q[0])
		draw_polyline(q, c, maxf(w * _s, 1.0), true)
	func _stroke(pts: PackedVector2Array, c: Color, w: float) -> void:
		if pts.size() < 2: return
		var q := _pxs(pts)
		var wp := maxf(w * _s, 1.0)
		draw_polyline(q, c, wp, true)
		draw_circle(q[0], wp * 0.5, c, true, -1.0, true)
		draw_circle(q[q.size() - 1], wp * 0.5, c, true, -1.0, true)
	func _line(a: Vector2, b: Vector2, c: Color, w: float) -> void:
		_stroke(PackedVector2Array([a, b]), c, w)
	func _dot(c: Vector2, r: float, col: Color) -> void:
		draw_circle(_px(c), r * _s, col, true, -1.0, true)

	# ---- main draw
	func _draw() -> void:
		var s := minf(size.x, size.y)
		if s < 2.0: return
		_s = s
		_w = clampf(1.8 / s, 0.04, 0.075)
		_off = (size - Vector2(s, s)) * 0.5
		var fn := "_i_" + kind
		if not has_method(fn): fn = "_i_yen"
		call(fn)

	# ---- icons
	func _i_coin() -> void: _i_yen()
	func _i_yen() -> void:
		var pivot := Vector2(0.5, 0.52)
		var back := _rot(_rr(0.08, 0.16, 0.80, 0.52, 0.09), 0.2, pivot)
		_poly(back, Color("7cc592"))
		var front := _rot(_rr(0.06, 0.30, 0.88, 0.54, 0.10), -0.14, pivot)
		_poly(front, _col(Color("8fd3a4")))
		var inner := _rot(_rr(0.13, 0.37, 0.74, 0.40, 0.06), -0.14, pivot)
		_outline(inner, Color("4f9a6b"), 0.032)
		var c := pivot + (Vector2(0.0, 0.0)).rotated(-0.14)
		_poly(_circ(c, 0.17), Color("cdeed7"))
		var dk := Color("3b7a55")
		var mk := func(p: Vector2) -> Vector2: return c + (p - c).rotated(-0.14)
		_stroke(PackedVector2Array([mk.call(c + Vector2(-0.065, -0.085)), mk.call(c + Vector2(0, 0.005)), mk.call(c + Vector2(0.065, -0.085))]), dk, 0.04)
		_line(mk.call(c + Vector2(0, 0.0)), mk.call(c + Vector2(0, 0.095)), dk, 0.04)
		_line(mk.call(c + Vector2(-0.065, 0.025)), mk.call(c + Vector2(0.065, 0.025)), dk, 0.032)
		_line(mk.call(c + Vector2(-0.065, 0.065)), mk.call(c + Vector2(0.065, 0.065)), dk, 0.032)
		_dot(mk.call(Vector2(0.17, 0.63)), 0.03, Color("4f9a6b"))
		_dot(mk.call(Vector2(0.83, 0.51)), 0.03, Color("4f9a6b"))

	func _i_clock() -> void:
		_poly(_circ(Vector2(0.5, 0.5), 0.4), _col(Style.CREAM))
		_line(Vector2(0.5, 0.5), Vector2(0.5, 0.25), Style.INK, 0.075)
		_line(Vector2(0.5, 0.5), Vector2(0.68, 0.58), Style.INK, 0.075)
		_dot(Vector2(0.5, 0.5), 0.05, Style.ROSE)

	func _i_sun() -> void:
		for i in 8:
			var a := TAU * float(i) / 8.0
			var d := Vector2(cos(a), sin(a))
			_poly(_cap(Vector2(0.5, 0.5) + d * 0.34, Vector2(0.5, 0.5) + d * 0.4, 0.04), _col(Style.GOLD))
		_poly(_circ(Vector2(0.5, 0.5), 0.24), _col(Style.GOLD))
		_dot(Vector2(0.43, 0.43), 0.05, Color(1, 1, 1, 0.55))

	func _i_moon() -> void:
		var res := Geometry2D.clip_polygons(_circ(Vector2(0.5, 0.52), 0.4, 40), _circ(Vector2(0.7, 0.4), 0.32, 40))
		if res.is_empty(): return
		_poly(res[0], _col(Color("f7e7a6")))

	func _cloud_parts() -> Array:
		return [_circ(Vector2(0.28, 0.6), 0.19), _circ(Vector2(0.5, 0.42), 0.25), _circ(Vector2(0.73, 0.58), 0.2), _rr(0.2, 0.55, 0.6, 0.22, 0.11)]
	func _i_cloud() -> void:
		_blob(_cloud_parts(), _col(Color("e2eefa")))
		_dot(Vector2(0.42, 0.34), 0.05, Color(1, 1, 1, 0.8))
	func _i_rain() -> void:
		var parts := [_circ(Vector2(0.28, 0.4), 0.17), _circ(Vector2(0.5, 0.26), 0.22), _circ(Vector2(0.72, 0.38), 0.18), _rr(0.2, 0.36, 0.6, 0.2, 0.1)]
		for i in 3:
			var x := 0.3 + 0.2 * i
			_line(Vector2(x + 0.03, 0.68), Vector2(x - 0.04, 0.86), Style.INK, 0.12)
		_blob(parts, _col(Color("b8cde4")))
		for i in 3:
			var x := 0.3 + 0.2 * i
			_line(Vector2(x + 0.03, 0.68), Vector2(x - 0.04, 0.86), Style.SKY, 0.06)
	func _i_fog() -> void:
		var parts := [_circ(Vector2(0.28, 0.38), 0.17), _circ(Vector2(0.5, 0.24), 0.21), _circ(Vector2(0.72, 0.36), 0.18), _rr(0.2, 0.34, 0.6, 0.2, 0.1)]
		_blob(parts, _col(Color("e6e8f0")))
		for i in 2:
			var y := 0.7 + 0.15 * i
			var x0 := 0.14 + 0.1 * i
			_line(Vector2(x0, y), Vector2(x0 + 0.62, y), Style.INK, 0.1)
			_line(Vector2(x0, y), Vector2(x0 + 0.62, y), Color("dfe2ee"), 0.045)

	func _i_cat() -> void:
		var head := _ell(Vector2(0.5, 0.6), 0.37, 0.3, 36)
		var ear_l := PackedVector2Array([Vector2(0.15, 0.5), Vector2(0.18, 0.1), Vector2(0.46, 0.3)])
		var ear_r := PackedVector2Array([Vector2(0.85, 0.5), Vector2(0.82, 0.1), Vector2(0.54, 0.3)])
		_blob([head, ear_l, ear_r], _col(Color("f2cf9c")))
		_fill(PackedVector2Array([Vector2(0.2, 0.36), Vector2(0.22, 0.2), Vector2(0.34, 0.31)]), Color("f3a7b0"))
		_fill(PackedVector2Array([Vector2(0.8, 0.36), Vector2(0.78, 0.2), Vector2(0.66, 0.31)]), Color("f3a7b0"))
		_dot(Vector2(0.36, 0.57), 0.05, Color("3b2a24")); _dot(Vector2(0.64, 0.57), 0.05, Color("3b2a24"))
		_dot(Vector2(0.5, 0.67), 0.035, Color("f3a7b0"))
		_stroke(PackedVector2Array([Vector2(0.44, 0.73), Vector2(0.5, 0.76), Vector2(0.56, 0.73)]), Color("3b2a24"), 0.025)

	func _i_fish() -> void:
		var body := _ell(Vector2(0.52, 0.52), 0.34, 0.22, 36)
		var tail := PackedVector2Array([Vector2(0.24, 0.52), Vector2(0.05, 0.3), Vector2(0.05, 0.74)])
		var fin := PackedVector2Array([Vector2(0.4, 0.36), Vector2(0.56, 0.14), Vector2(0.66, 0.36)])
		_blob([body, tail, fin], _col(Color("8cc3d6")))
		_dot(Vector2(0.69, 0.47), 0.05, Color("3b2a24"))
		_dot(Vector2(0.705, 0.455), 0.016, Color.WHITE)
		_stroke(PackedVector2Array([Vector2(0.52, 0.4), Vector2(0.48, 0.52), Vector2(0.52, 0.64)]), Color(Style.INK, 0.5), 0.03)

	func _i_shell() -> void:
		var dome := Geometry2D.intersect_polygons(_ell(Vector2(0.5, 0.82), 0.44, 0.64, 44), _rr(0.0, 0.0, 1.0, 0.84, 0.0))
		if dome.is_empty(): return
		var parts: Array = [dome[0]]
		for i in range(0, 6):
			var a := deg_to_rad(-168.0 + 156.0 * (float(i) + 0.5) / 6.0)
			parts.append(_circ(Vector2(0.5, 0.82) + Vector2(cos(a) * 0.42, sin(a) * 0.62), 0.1, 14))
		_blob(parts, _col(Color("f6b8c4")))
		var dk := Color(Style.INK, 0.4)
		for i in range(1, 6):
			var a := deg_to_rad(-168.0 + 156.0 * float(i) / 6.0)
			_line(Vector2(0.5, 0.8), Vector2(0.5, 0.82) + Vector2(cos(a) * 0.36, sin(a) * 0.54), dk, 0.028)
		_poly(_rr(0.38, 0.8, 0.24, 0.13, 0.05), Color("e8a0ae"))

	func _i_bag() -> void:
		var h := PackedVector2Array()
		for i in 13:
			var a := PI + PI * float(i) / 12.0
			h.append(Vector2(0.5, 0.34) + Vector2(cos(a), sin(a)) * 0.2)
		_stroke(h, Style.INK, 0.15)
		_stroke(h, Color("c99565"), 0.06)
		_poly(_rr(0.16, 0.34, 0.68, 0.54, 0.15), _col(Color("dcae7c")))
		_stroke(PackedVector2Array([Vector2(0.17, 0.52), Vector2(0.5, 0.64), Vector2(0.83, 0.52)]), Color(Style.INK, 0.7), 0.04)
		_poly(_circ(Vector2(0.5, 0.64), 0.06), Style.GOLD)

	func _i_book() -> void:
		_poly(_rr(0.16, 0.08, 0.68, 0.84, 0.1), _col(Style.ROSE))
		_fill(_rr(0.16, 0.08, 0.14, 0.84, 0.07), Color(0, 0, 0, 0.14))
		_line(Vector2(0.31, 0.12), Vector2(0.31, 0.88), Color(Style.INK, 0.5), 0.03)
		var lab := _rr(0.4, 0.26, 0.34, 0.26, 0.05)
		_fill(lab, Style.CREAM)
		_outline(lab, Style.INK, 0.03)
		_line(Vector2(0.46, 0.36), Vector2(0.68, 0.36), Color(Style.INK, 0.7), 0.035)
		_line(Vector2(0.46, 0.44), Vector2(0.6, 0.44), Color(Style.INK, 0.7), 0.035)

	func _i_moped() -> void:
		var mint := _col(Color("8fd6c8"))
		var body := [
			_cap(Vector2(0.22, 0.56), Vector2(0.68, 0.6), 0.1),
			PackedVector2Array([Vector2(0.62, 0.28), Vector2(0.74, 0.28), Vector2(0.8, 0.68), Vector2(0.6, 0.68)]),
			_cap(Vector2(0.16, 0.5), Vector2(0.3, 0.5), 0.1),
		]
		_blob(body, mint)
		_poly(_rr(0.18, 0.34, 0.34, 0.1, 0.05), Style.ROSE)
		_line(Vector2(0.7, 0.26), Vector2(0.86, 0.22), Style.INK, 0.07)
		for wx in [0.22, 0.78]:
			_poly(_circ(Vector2(wx, 0.76), 0.15), Color("5a5470"))
			_dot(Vector2(wx, 0.76), 0.05, Color("e4e1ea"))

	func _i_hand() -> void:
		var parts := [
			_ell(Vector2(0.5, 0.64), 0.27, 0.23),
			_cap(Vector2(0.31, 0.5), Vector2(0.28, 0.2), 0.075),
			_cap(Vector2(0.44, 0.48), Vector2(0.43, 0.1), 0.075),
			_cap(Vector2(0.57, 0.48), Vector2(0.58, 0.13), 0.075),
			_cap(Vector2(0.69, 0.52), Vector2(0.73, 0.24), 0.07),
			_cap(Vector2(0.3, 0.66), Vector2(0.12, 0.5), 0.075),
		]
		_blob(parts, _col(Color("f6d9bd")))

	func _i_paw() -> void:
		_poly(_ell(Vector2(0.5, 0.66), 0.26, 0.2), _col(Color("f2cf9c")))
		for p in [Vector2(0.2, 0.46), Vector2(0.38, 0.28), Vector2(0.62, 0.28), Vector2(0.8, 0.46)]:
			_poly(_ell(p, 0.1, 0.125), _col(Color("f2cf9c")))

	func _i_heart() -> void:
		_poly(_heart_pts(), _col(Style.ROSE))
		_dot(Vector2(0.3, 0.32), 0.05, Color(1, 1, 1, 0.55))
	func _i_heart_off() -> void:
		_poly(_heart_pts(), Style.CREAM_SHADE)

	func _i_spark_at(c: Vector2, r: float, col: Color) -> void:
		_poly(_star_pts(c, r, r * 0.3, 4), col)
	func _i_spark() -> void:
		_i_spark_at(Vector2(0.46, 0.54), 0.46, _col(Style.GOLD))
		_i_spark_at(Vector2(0.8, 0.2), 0.17, _col(Style.GOLD))
	func _i_star() -> void:
		_poly(_star_pts(Vector2(0.5, 0.54), 0.46, 0.2, 5), _col(Style.GOLD))

	func _i_check() -> void:
		_poly(_circ(Vector2(0.5, 0.5), 0.4), _col(Style.MINT))
		_stroke(PackedVector2Array([Vector2(0.3, 0.52), Vector2(0.44, 0.65), Vector2(0.7, 0.36)]), Style.CREAM, 0.1)
	func _i_close() -> void:
		var c := _col(Style.INK)
		_line(Vector2(0.24, 0.24), Vector2(0.76, 0.76), c, 0.14)
		_line(Vector2(0.76, 0.24), Vector2(0.24, 0.76), c, 0.14)

	func _i_person() -> void:
		var body := Geometry2D.intersect_polygons(_ell(Vector2(0.5, 0.96), 0.4, 0.4, 40), _rr(0.0, 0.0, 1.0, 0.94, 0.0))
		var parts: Array = [_circ(Vector2(0.5, 0.34), 0.23)]
		if not body.is_empty(): parts.append(body[0])
		parts.append(_rr(0.4, 0.5, 0.2, 0.2, 0.04))
		_blob(parts, _col(Color("f6c9a8")))
		_fill(_ell(Vector2(0.5, 0.2), 0.21, 0.09, 20), Color("8a5a44"))
	func _i_note() -> void:
		_poly(_rr(0.2, 0.08, 0.6, 0.84, 0.08), _col(Style.CREAM))
		for i in 3:
			_line(Vector2(0.3, 0.28 + 0.17 * i), Vector2(0.7 - 0.1 * (i % 2), 0.28 + 0.17 * i), Color(Style.INK, 0.65), 0.05)
		_poly(_circ(Vector2(0.66, 0.76), 0.08), Style.ROSE)
	func _i_lock() -> void:
		var h := PackedVector2Array()
		for i in 13:
			var a := PI + PI * float(i) / 12.0
			h.append(Vector2(0.5, 0.4) + Vector2(cos(a), sin(a)) * 0.18)
		_stroke(h, Style.INK, 0.12)
		_poly(_rr(0.22, 0.4, 0.56, 0.46, 0.1), _col(Style.GOLD))
		_dot(Vector2(0.5, 0.6), 0.055, Style.INK)

	func _i_gear() -> void:
		var parts := [_circ(Vector2(0.5, 0.5), 0.3, 32)]
		for i in 8:
			var a := TAU * float(i) / 8.0
			var d := Vector2(cos(a), sin(a))
			parts.append(_cap(Vector2(0.5, 0.5) + d * 0.3, Vector2(0.5, 0.5) + d * 0.37, 0.085))
		_blob(parts, _col(Style.INK_SOFT))
		_poly(_circ(Vector2(0.5, 0.5), 0.12), Style.CREAM)

	func _i_glass() -> void:
		var p := PackedVector2Array([Vector2(0.18, 0.5), Vector2(0.3, 0.26), Vector2(0.56, 0.18), Vector2(0.8, 0.34), Vector2(0.84, 0.62), Vector2(0.64, 0.82), Vector2(0.36, 0.84), Vector2(0.2, 0.7)])
		_poly(p, _col(Color("9fd8b0")))
		_stroke(PackedVector2Array([Vector2(0.32, 0.4), Vector2(0.42, 0.3), Vector2(0.56, 0.28)]), Color(1, 1, 1, 0.7), 0.05)

	func _i_wood() -> void:
		_poly(_cap(Vector2(0.18, 0.7), Vector2(0.78, 0.3), 0.14), _col(Color("c9a882")))
		_stroke(PackedVector2Array([Vector2(0.3, 0.64), Vector2(0.42, 0.56)]), Color(Style.INK, 0.5), 0.04)
		_stroke(PackedVector2Array([Vector2(0.5, 0.5), Vector2(0.62, 0.42)]), Color(Style.INK, 0.5), 0.04)
		_poly(_circ(Vector2(0.78, 0.3), 0.07), Color("e2c9a4"))

	func _i_bottle() -> void:
		var parts := [_rr(0.3, 0.38, 0.4, 0.5, 0.14), _rr(0.4, 0.14, 0.2, 0.3, 0.05)]
		_blob(parts, _col(Color("bfe3ee")))
		_poly(_rr(0.4, 0.08, 0.2, 0.1, 0.03), Color("c98a5a"))
		_fill(_rr(0.38, 0.52, 0.24, 0.22, 0.04), Color("fffaf2"))

	func _i_flower() -> void:
		var petal := _col(Color("f2a0b8"))
		for i in 5:
			var a := -PI * 0.5 + TAU * float(i) / 5.0
			_poly(_circ(Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * 0.22, 0.17, 18), petal)
		_poly(_circ(Vector2(0.5, 0.5), 0.12), Style.GOLD)

	func _i_dollar() -> void:
		_poly(_circ(Vector2(0.5, 0.5), 0.4, 36), _col(Color("f2e6cf")))
		var dk := Color(Style.INK, 0.45)
		for i in 5:
			var a := -PI * 0.5 + TAU * float(i) / 5.0
			_line(Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * 0.07, Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * 0.27, dk, 0.045)
		_dot(Vector2(0.5, 0.5), 0.04, dk)
