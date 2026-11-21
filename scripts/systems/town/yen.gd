extends RefCounted
## Money is yen, shown as "¥1,250" next to a small green paper note. The word "coins" is never shown.
## GameState.coins / add_coins stay the internal API.

const Kit := preload("res://scripts/systems/town/kit.gd")

const GREEN := Color("8fd3a4")
const INK := Color("6b4a3a")

static func fmt(n: Variant) -> String:
	var v: int = int(n)
	var s: String = str(absi(v))
	var out := ""
	var cnt := 0
	for k in range(s.length() - 1, -1, -1):
		out = s[k] + out
		cnt += 1
		if cnt % 3 == 0 and k > 0:
			out = "," + out
	return ("-" if v < 0 else "") + "¥" + out

## A small green banknote control. Uses Style.icon("yen") when the shared Style exists, else draws its own.
static func note(w := 30.0) -> Control:
	var ic := Kit.yen_icon(w * 0.95)
	if ic != null:
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return ic
	var n := Note.new()
	n.custom_minimum_size = Vector2(w, w * 0.64)
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return n

## Icon + amount label in one row. Update with set_amount().
static func row(n: Variant, font_size := 22, color := INK) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(note(font_size * 1.4))
	var l := Label.new()
	l.name = "Amount"
	l.text = fmt(n)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	return h

static func set_amount(r: Node, n: Variant, color := Color(0, 0, 0, 0)) -> void:
	var l := r.get_node_or_null("Amount") as Label
	if l == null: return
	l.text = fmt(n)
	if color.a > 0.0: l.add_theme_color_override("font_color", color)

class Note extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var ink := Color("6b4a3a")
		var r := Rect2(Vector2.ONE, size - Vector2(2, 2))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("8fd3a4")
		sb.set_corner_radius_all(int(maxf(3.0, size.y * 0.2)))
		sb.set_border_width_all(2)
		sb.border_color = ink
		draw_style_box(sb, r)
		var c := size * 0.5
		draw_circle(c, size.y * 0.3, Color("c2ebcd"))
		draw_arc(c, size.y * 0.3, 0.0, TAU, 20, ink, 1.4, true)
		var f := ThemeDB.fallback_font
		var fs := int(size.y * 0.5)
		draw_string(f, Vector2(0, c.y + fs * 0.36), "¥", HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, ink)
		draw_circle(Vector2(size.x * 0.13, c.y), size.y * 0.07, ink)
		draw_circle(Vector2(size.x * 0.87, c.y), size.y * 0.07, ink)
