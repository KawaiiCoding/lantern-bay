extends Control
## Round HUD button driven by the Hud's multi-touch router (so Action can be held while the other thumb
## steers). Draws like Style.icon_button: ink border, soft shadow; squishes while held.
## Content is an icon, a (fitted) text, or an icon above a short text.

var kind := "primary"
var diameter := 100.0
var held := false : set = set_held

var _box: VBoxContainer
var _icon: Control
var _label: Label
var _badge: Control
var _icon_name := ""
var _icon_tint := Color(0, 0, 0, 0)
var _text := ""

func setup(d: float, k: String) -> void:
	diameter = d
	kind = k
	custom_minimum_size = Vector2(d, d)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset_ratio = Vector2(0.5, 0.5)
	_box = VBoxContainer.new()
	_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override("separation", -2)
	add_child(_box)
	_icon = Control.new()
	_icon.visible = false
	_box.add_child(_icon)
	_label = Style.label("", 28, Style.CREAM, true)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_label.visible = false
	_box.add_child(_label)
	_badge = Style.icon("check", 30.0)
	_badge.visible = false
	_badge.position = Vector2(d * 0.74, d * 0.02)
	add_child(_badge)
	queue_redraw()

func set_kind(k: String) -> void:
	if k == kind: return
	kind = k
	queue_redraw()

func set_badge(on: bool) -> void:
	if _badge: _badge.visible = on

func set_held(b: bool) -> void:
	if held == b: return
	held = b
	queue_redraw()
	Style.press_anim(self, b, 0.92)

## Icon only.
func set_icon(icon_name: String, tint := Color(0, 0, 0, 0), icon_size := 0.0) -> void:
	_icon_name = icon_name; _icon_tint = tint
	_text = ""
	_label.visible = false
	_show_icon(icon_size if icon_size > 0.0 else diameter * 0.5)

## Text (with an optional small icon above it when the text fits on one line).
func set_content(text: String, icon_name := "") -> void:
	_text = text
	if text == "":
		_label.visible = false
		_icon.visible = false
		return
	var fit := _fit(text)
	var lines: PackedStringArray = fit[0]
	var fs: int = fit[1]
	_label.text = "\n".join(lines)
	_label.add_theme_font_size_override("font_size", fs)
	_label.add_theme_constant_override("outline_size", 6 if fs >= 24 else 5)
	_label.add_theme_color_override("font_outline_color", Style.KINDS.get(kind, Style.KINDS["primary"])["edge"])
	_label.visible = true
	if icon_name != "" and lines.size() == 1:
		_icon_name = icon_name
		_icon_tint = Style.CREAM
		_show_icon(diameter * 0.30)
	else:
		_icon.visible = false

func _show_icon(s: float) -> void:
	var idx := _icon.get_index()
	_box.remove_child(_icon)
	_icon.queue_free()
	_icon = Style.icon(_icon_name, s, _icon_tint)
	_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_icon.visible = _icon_name != ""
	_box.add_child(_icon)
	_box.move_child(_icon, idx)

## Split into at most two lines and pick the biggest font that fits inside the circle.
func _fit(text: String) -> Array:
	var max_w := diameter * 0.76
	var sizes := [32, 30, 28, 26, 24, 22, 20, 18]
	var lines := PackedStringArray([text])
	for fs in sizes:
		if Style.text_width(text, fs) <= max_w: return [lines, fs]
	var words := text.split(" ", false)
	if words.size() >= 2:
		var best := 1
		var best_diff := 1e9
		for i in range(1, words.size()):
			var a := " ".join(words.slice(0, i)); var b := " ".join(words.slice(i))
			var d := absf(Style.text_width(a, 24) - Style.text_width(b, 24))
			if d < best_diff: best_diff = d; best = i
		lines = PackedStringArray([" ".join(words.slice(0, best)), " ".join(words.slice(best))])
		for fs in sizes:
			if maxf(Style.text_width(lines[0], fs), Style.text_width(lines[1], fs)) <= max_w: return [lines, fs]
		return [lines, 17]
	return [lines, 17]

## True when a canvas-space point is on the button (slightly generous for thumbs).
func hit(p: Vector2) -> bool:
	if not is_visible_in_tree(): return false
	var c := get_global_rect().get_center()
	return p.distance_to(c) <= diameter * 0.5 + 12.0

func _draw() -> void:
	draw_style_box(Style.box(kind, "pressed" if held else "normal", int(diameter)), Rect2(Vector2.ZERO, size))
	var r := diameter * 0.5
	draw_arc(Vector2(r, r), r - 10.0, deg_to_rad(205.0), deg_to_rad(280.0), 14, Color(1, 1, 1, 0.38), 5.0, true)
