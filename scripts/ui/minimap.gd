extends Node
## Minimap: a small drawn island map in the top-right corner (under the Notebook button).
## Shows Mocha (arrow), the main places, and the current goal (gold star). Tap it for a big
## labelled map (closes with a tap / Escape). Land is sampled once from Island.is_walkable,
## so it always matches the real island. Screen up = away from the camera (-z).

const SAMPLE := 96                     # land grid resolution
const SMALL := 124.0                   # small map size in px
const PLACES := [
	["home", "Home", "house"], ["shop", "Pip's Shop", "shop"], ["board", "Board", "board"], ["plaza", "Plaza", "fountain"],
	["pier_end", "Pier", "fish"], ["lighthouse", "Lighthouse", "tower"], ["hill", "Hill", "hill"], ["beach", "Beach", "shell"],
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
	if "map=1" in OS.get_cmdline_user_args():   # test hook: open the big map right away
		get_tree().create_timer(1.5).timeout.connect(_open_big)

func _build_land() -> ImageTexture:
	var img := Image.create(SAMPLE, SAMPLE, false, Image.FORMAT_RGBA8)
	var sea := Color("8fcde0"); var sand := Color("f1dcb0"); var grass := Color("a9d68f"); var hill := Color("8fc27a")
	var isl = main.island if is_instance_valid(main) else null
	for j in SAMPLE:
		for i in SAMPLE:
			var x := _bounds.position.x + (i + 0.5) / SAMPLE * _bounds.size.x
			var z := _bounds.position.y + (j + 0.5) / SAMPLE * _bounds.size.y
			var c := sea
			if isl and isl.has_method("dist_in"):
				# smooth island shape: inside the shoreline = land (props don't punch holes)
				var di: float = isl.dist_in(x, z)
				var gy: float = isl.ground_y(x, z) if isl.has_method("ground_y") else 0.0
				var on_pier: bool = isl.has_method("is_walkable") and di < 0.0 and isl.is_walkable(Vector3(x, 0, z))
				if di > 1.6: c = hill if gy > 0.5 else grass
				elif di > 0.0: c = sand
				elif on_pier: c = Color("e2cb9a")   # tide flats / pier: wet sand
			elif isl and isl.has_method("is_walkable") and isl.is_walkable(Vector3(x, 0, z)):
				c = grass
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
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		draw_texture_rect(host.land(), inner, false)
		var m = host.main
		if m == null: return
		# places: a small drawn icon each; on the big map a label placed where it doesn't overlap anything
		var font := ThemeDB.fallback_font
		var taken: Array[Rect2] = []
		var marks := []
		for pl in host.PLACES:
			var p: Vector3 = m.spot(pl[0])
			if p == Vector3.ZERO: continue
			var q: Vector2 = inner.position + host.to_map(p) * inner.size
			var ir := 13.0 if big else 6.5
			marks.append([q, pl, ir])
			taken.append(Rect2(q - Vector2(ir, ir), Vector2(ir, ir) * 2))
		for mk in marks:
			_icon(mk[0], mk[2], mk[1][2])
		if big:
			var fs := 16
			for mk in marks:
				var q: Vector2 = mk[0]; var ir: float = mk[2]; var text: String = mk[1][1]
				var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
				var box := Vector2(ts.x + 10, ts.y + 4)
				var tries := [Vector2(-box.x / 2, -ir - box.y - 2), Vector2(-box.x / 2, ir + 2),
					Vector2(ir + 4, -box.y / 2), Vector2(-ir - 4 - box.x, -box.y / 2)]
				for off in tries:
					var r2 := Rect2(q + off, box)
					if not inner.grow(-2).encloses(r2): continue
					var clash := false
					for t in taken:
						if t.intersects(r2): clash = true; break
					if clash: continue
					taken.append(r2)
					var lb := StyleBoxFlat.new(); lb.bg_color = Color(Style.CREAM, 0.92); lb.set_corner_radius_all(6)
					lb.border_color = Color(Style.INK, 0.5); lb.set_border_width_all(1)
					draw_style_box(lb, r2)
					draw_string(font, r2.position + Vector2(5, ts.y - 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Style.INK)
					break
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

	## Tiny readable map icons, drawn in a cream disc with an ink ring.
	func _icon(c: Vector2, r: float, kind: String) -> void:
		draw_circle(c, r, Style.CREAM)
		draw_arc(c, r, 0, TAU, 20, Style.INK, 1.6 if r < 8 else 2.2)
		var k := r * 0.55
		var ink := Style.INK
		match kind:
			"house":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-k, 0), c + Vector2(0, -k), c + Vector2(k, 0)]), Color("e8746a"))
				draw_rect(Rect2(c + Vector2(-k * 0.7, 0), Vector2(k * 1.4, k * 0.8)), Color("f4dcc4"))
			"shop":
				draw_rect(Rect2(c + Vector2(-k * 0.8, -k * 0.4), Vector2(k * 1.6, k * 1.2)), Color("e0a64a"))
				draw_arc(c + Vector2(0, -k * 0.4), k * 0.45, PI, TAU, 10, ink, 1.4)
			"board":
				draw_rect(Rect2(c + Vector2(-k * 0.8, -k * 0.7), Vector2(k * 1.6, k)), Color("c98a5a"))
				draw_line(c + Vector2(0, k * 0.3), c + Vector2(0, k * 0.9), ink, 1.5)
			"fountain":
				draw_circle(c, k * 0.8, Color("8fcde0"))
				draw_circle(c, k * 0.3, Color("fffaf2"))
			"fish":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-k, 0), c + Vector2(-k * 0.1, -k * 0.55), c + Vector2(k * 0.6, 0), c + Vector2(-k * 0.1, k * 0.55)]), Color("6fb4d6"))
				draw_colored_polygon(PackedVector2Array([c + Vector2(k * 0.5, 0), c + Vector2(k, -k * 0.45), c + Vector2(k, k * 0.45)]), Color("6fb4d6"))
			"tower":
				draw_rect(Rect2(c + Vector2(-k * 0.35, -k * 0.6), Vector2(k * 0.7, k * 1.5)), Color("e8746a"))
				draw_rect(Rect2(c + Vector2(-k * 0.35, -k * 0.2), Vector2(k * 0.7, k * 0.35)), Color("fffaf2"))
				draw_circle(c + Vector2(0, -k * 0.75), k * 0.3, Color("f2c14e"))
			"hill":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-k, k * 0.6), c + Vector2(-k * 0.1, -k * 0.7), c + Vector2(k, k * 0.6)]), Color("7fae73"))
			"shell":
				draw_arc(c + Vector2(0, k * 0.4), k * 0.85, PI, TAU, 12, Color("e8a0a0"), k * 0.5)
			_:
				draw_circle(c, k * 0.4, ink)

	func _star(c: Vector2, rad: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for i in 10:
			var a := -PI / 2 + i * PI / 5
			var rr := rad if i % 2 == 0 else rad * 0.45
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
		draw_colored_polygon(pts, col)
		pts.append(pts[0])
		draw_polyline(pts, Style.INK, 1.5)
