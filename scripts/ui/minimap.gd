extends Node
## Minimap: a small drawn island map in the top-right corner (under the Notebook button).
## Shows Mocha (arrow), the main places, and the current goal (gold star). Tap it for a big
## labelled map (closes with a tap / Escape). Land is sampled once from Island.is_walkable,
## so it always matches the real island. Screen up = away from the camera (-z).

const SAMPLE := 72                     # land grid resolution
const SMALL := 124.0                   # small map size in px
const PLACES := [
	["home", "Home"], ["shop", "Pip's Shop"], ["board", "Board"], ["plaza", "Plaza"],
	["pier_end", "Pier"], ["lighthouse", "Lighthouse"], ["hill", "Hill"], ["beach", "Beach"],
]

var main: Node
var _layer: CanvasLayer
var _small: MapView
var _big_panel: Control
var _land: ImageTexture
var _bounds := Rect2(-27, -27, 54, 54)   # world x/z covered by the map

func setup(m: Node) -> void:
	main = m
	_land = _build_land()
	_layer = CanvasLayer.new(); _layer.layer = 9; add_child(_layer)
	_small = MapView.new()
	_small.host = self; _small.big = false
	_small.size = Vector2(SMALL, SMALL)
	_small.anchor_left = 1.0; _small.anchor_right = 1.0
	_small.offset_right = -16.0; _small.offset_left = -16.0 - SMALL
	_small.offset_top = 206.0; _small.offset_bottom = 206.0 + SMALL
	_small.mouse_filter = Control.MOUSE_FILTER_STOP
	_small.gui_input.connect(_on_small_input)
	_layer.add_child(_small)

func _build_land() -> ImageTexture:
	var img := Image.create(SAMPLE, SAMPLE, false, Image.FORMAT_RGBA8)
	var sea := Color("8fcde0"); var sand := Color("f1dcb0"); var grass := Color("a9d68f"); var hill := Color("8fc27a")
	var isl = main.island if is_instance_valid(main) else null
	for j in SAMPLE:
		for i in SAMPLE:
			var x := _bounds.position.x + (i + 0.5) / SAMPLE * _bounds.size.x
			var z := _bounds.position.y + (j + 0.5) / SAMPLE * _bounds.size.y
			var c := sea
			if isl and isl.has_method("is_walkable"):
				var w: bool = isl.is_walkable(Vector3(x, 0, z))
				var gy: float = isl.ground_y(x, z) if isl.has_method("ground_y") else 0.0
				if w or gy > 0.5:
					c = hill if gy > 0.5 else grass
				else:
					# a soft sand rim where land meets sea
					for d in [Vector2(1.2, 0), Vector2(-1.2, 0), Vector2(0, 1.2), Vector2(0, -1.2)]:
						if isl.is_walkable(Vector3(x + d.x, 0, z + d.y)): c = sand; break
			img.set_pixel(i, j, c)
	return ImageTexture.create_from_image(img)

## world (x, z) -> 0..1 map coords
func to_map(p: Vector3) -> Vector2:
	return Vector2((p.x - _bounds.position.x) / _bounds.size.x, (p.z - _bounds.position.y) / _bounds.size.y)

func goal_target() -> Vector3:
	var g = main.systems.get("goals") if is_instance_valid(main) else null
	if g == null: return Vector3.ZERO
	var cur = g.get("_current")
	var tgt: Dictionary = g.get("TARGET") if g.get("TARGET") != null else {}
	if cur == null or not tgt.has(cur): return Vector3.ZERO
	return main.spot(tgt[cur])

func land() -> Texture2D: return _land

func _process(_dt: float) -> void:
	if not is_instance_valid(_small): return
	var hud_ok := true
	if is_instance_valid(main) and is_instance_valid(main.hud) and main.hud.has_method("controls_visible"):
		hud_ok = main.hud.controls_visible()
	_small.visible = hud_ok and not GameState.paused
	_small.queue_redraw()
	if is_instance_valid(_big_panel): _big_panel.queue_redraw()

func _on_small_input(e: InputEvent) -> void:
	var tap: bool = (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed)
	if not tap: return
	_small.accept_event()
	_open_big()

func _open_big() -> void:
	if not is_instance_valid(main) or not is_instance_valid(main.hud) or not main.hud.has_method("open_panel"): return
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel", Style.panel_box(Style.CREAM, 26, 3, 14))
	wrap.set_meta("autofree", true)
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 8); wrap.add_child(vb)
	var title := Style.label("Lantern Bay", 26, Style.INK, true); title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var view := MapView.new(); view.host = self; view.big = true
	view.custom_minimum_size = Vector2(460, 460)
	vb.add_child(view)
	_big_panel = view
	var close := Style.button("Close", "primary")
	close.pressed.connect(func(): main.hud.close_panel())
	vb.add_child(close)
	view.gui_input.connect(func(ev):
		if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
			main.hud.close_panel())
	main.hud.open_panel(wrap)


## The drawn map (used for both the small corner map and the big one).
class MapView extends Control:
	var host
	var big := false

	func _draw() -> void:
		if host == null: return
		var s := size
		var r := Rect2(Vector2.ZERO, s)
		var radius := 18.0 if big else 16.0
		# frame
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("8fcde0"); sb.set_corner_radius_all(int(radius))
		sb.border_color = Style.INK; sb.set_border_width_all(3)
		draw_style_box(sb, r)
		var inner := r.grow(-4)
		draw_texture_rect(host.land(), inner, false)
		var m = host.main
		if m == null: return
		# places
		var font := ThemeDB.fallback_font
		for pl in host.PLACES:
			var p: Vector3 = m.spot(pl[0])
			if p == Vector3.ZERO: continue
			var q: Vector2 = inner.position + host.to_map(p) * inner.size
			draw_circle(q, 6.0 if big else 3.5, Style.CREAM)
			draw_arc(q, 6.0 if big else 3.5, 0, TAU, 16, Style.INK, 2.0 if big else 1.5)
			if big:
				var fs := 17
				var w := font.get_string_size(pl[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				var at := q + Vector2(-w / 2.0, -12)
				at.x = clampf(at.x, inner.position.x + 4, inner.end.x - w - 4)
				draw_string_outline(font, at, pl[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Style.CREAM)
				draw_string(font, at, pl[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Style.INK)
		# goal star
		var g: Vector3 = host.goal_target()
		if g != Vector3.ZERO:
			var gq: Vector2 = inner.position + host.to_map(g) * inner.size
			var pulse := 1.0 + 0.15 * sin(Time.get_ticks_msec() / 250.0)
			_star(gq, (11.0 if big else 7.0) * pulse, Style.GOLD)
		# Mocha
		var pl_node = m.player
		if is_instance_valid(pl_node):
			var pq: Vector2 = inner.position + host.to_map(pl_node.global_position) * inner.size
			pq = pq.clamp(inner.position + Vector2(6, 6), inner.end - Vector2(6, 6))
			var ang: float = 0.0
			var vel = pl_node.get("velocity")
			if vel is Vector3 and Vector2(vel.x, vel.z).length() > 0.2:
				ang = Vector2(vel.x, vel.z).angle() + PI / 2
			var k := 1.6 if big else 1.0
			var pts := PackedVector2Array([Vector2(0, -9), Vector2(6.5, 6), Vector2(0, 3), Vector2(-6.5, 6)])
			var tp := PackedVector2Array()
			for v in pts: tp.append(pq + (v * k).rotated(ang))
			draw_colored_polygon(tp, Style.PRIMARY)
			tp.append(tp[0])
			draw_polyline(tp, Style.CREAM, 2.0)

	func _star(c: Vector2, rad: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for i in 10:
			var a := -PI / 2 + i * PI / 5
			var rr := rad if i % 2 == 0 else rad * 0.45
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
		draw_colored_polygon(pts, col)
		pts.append(pts[0])
		draw_polyline(pts, Style.INK, 1.5)
