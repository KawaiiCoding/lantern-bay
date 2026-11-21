extends CanvasLayer
## FishingUI: reel gauge (progress ring + tension meter), bite pop, flash words, touch catcher,
## and the catch card (3D turntable in a SubViewport). Built in code; owned by Fishing.
## Uses Style (scripts/ui/style.gd) when present, otherwise the local fallbacks below.

signal card_closed

const STYLE_PATH := "res://scripts/ui/style.gd"
const CREAM := Color("fffaf2")
const INK := Color("6b4a3a")
const TEAL := Color("6fc2b6")
const CORAL := Color("e8746a")
const GOLD := Color("f2c14e")
const SOFT := Color("efe3d3")
const NOTE := Color("8fd3a4")
const RADIUS := 22

var gauge: ReelGauge
var catcher: Control
var bite_pop: BitePop
var flash_label: Label
var card: Control
var _card_panel: Control
var _card_t := 0.0
var _closing := false
var _touch_down := false
var _font: Font
var _style: Script

func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.exists(STYLE_PATH):
		var s = load(STYLE_PATH)
		if s is Script: _style = s
	var sf = _style_call("font", [true])
	if sf is Font: _font = sf
	else:
		var sys := SystemFont.new()
		sys.font_names = PackedStringArray(["Nunito", "Avenir Next Rounded", "Avenir Next", "Helvetica Neue", "Arial"])
		sys.font_weight = 700
		_font = sys

	catcher = Control.new(); catcher.name = "TouchCatcher"
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.visible = false
	catcher.gui_input.connect(_on_catcher_input)
	add_child(catcher)

	gauge = ReelGauge.new(); gauge.font = _font
	gauge.set_anchors_preset(Control.PRESET_FULL_RECT)
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge.visible = false
	add_child(gauge)

	bite_pop = BitePop.new(); bite_pop.font = _font
	bite_pop.set_anchors_preset(Control.PRESET_FULL_RECT)
	bite_pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bite_pop.visible = false
	add_child(bite_pop)

	flash_label = _label("", 46, INK)
	flash_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	flash_label.offset_top = 170; flash_label.offset_bottom = 250
	flash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flash_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	flash_label.add_theme_color_override("font_outline_color", CREAM)
	flash_label.add_theme_constant_override("outline_size", 14)
	flash_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_label.modulate.a = 0.0
	add_child(flash_label)

func _process(dt: float) -> void:
	if card: _card_t += dt

# ---------------------------------------------------------------- touch catcher (tap / hold anywhere)
func set_catcher(on: bool) -> void:
	catcher.visible = on
	if not on and _touch_down:
		_touch_down = false
		InputBridge.release()

func _on_catcher_input(e: InputEvent) -> void:
	var down := -1
	if e is InputEventScreenTouch: down = 1 if e.pressed else 0
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT: down = 1 if e.pressed else 0
	if down == 1 and not _touch_down:
		_touch_down = true; InputBridge.press()
	elif down == 0 and _touch_down:
		_touch_down = false; InputBridge.release()
	if down != -1: catcher.accept_event()

# ---------------------------------------------------------------- reel gauge
func show_reel(fish: Dictionary) -> void:
	gauge.fish_col = GOLD if fish.get("gold", false) else fish.get("body", TEAL)
	gauge.progress = 0.0; gauge.tension = 0.0; gauge.t = 0.0
	gauge.visible = true
	gauge.modulate.a = 0.0
	gauge.appear = 0.0
	var tw := create_tween()
	tw.tween_property(gauge, "modulate:a", 1.0, 0.15)
	tw.parallel().tween_property(gauge, "appear", 1.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func set_reel(progress: float, tension: float, warn: bool, surging: bool, held: bool) -> void:
	gauge.progress = progress; gauge.tension = tension
	gauge.warn = warn; gauge.surging = surging; gauge.held = held

func hide_reel() -> void:
	if gauge.visible:
		var tw := create_tween()
		tw.tween_property(gauge, "modulate:a", 0.0, 0.18)
		tw.tween_callback(func() -> void: gauge.visible = false)

# ---------------------------------------------------------------- bite pop + flash
func show_bite(screen_pos: Vector2) -> void:
	var vs := get_viewport().get_visible_rect().size
	bite_pop.at = Vector2(clampf(screen_pos.x, 70, vs.x - 70), clampf(screen_pos.y - 70, 120, vs.y - 260))
	bite_pop.t = 0.0
	bite_pop.visible = true

func hide_bite() -> void:
	bite_pop.visible = false

func flash(text: String, col := INK) -> void:
	flash_label.text = text
	flash_label.add_theme_color_override("font_color", col)
	flash_label.pivot_offset = Vector2(get_viewport().get_visible_rect().size.x * 0.5, 40)
	flash_label.scale = Vector2(0.6, 0.6)
	flash_label.modulate.a = 1.0
	var tw := flash_label.create_tween()
	tw.tween_property(flash_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.75)
	tw.tween_property(flash_label, "modulate:a", 0.0, 0.35)

# ---------------------------------------------------------------- catch card
## info: {name, cm, rarity, gold, price, body, fin, record, first, prev_best, junk}
func show_card(info: Dictionary) -> void:
	if card: card.queue_free()
	_card_t = 0.0
	_closing = false
	card = Control.new(); card.name = "CatchCard"
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(_on_card_input)
	add_child(card)

	var dim := ColorRect.new(); dim.color = Color(INK.r * 0.4, INK.g * 0.4, INK.b * 0.4, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT); dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(dim)
	var cc := CenterContainer.new(); cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(cc)

	var gold: bool = info.get("gold", false)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_box())
	panel.custom_minimum_size = Vector2(452, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(panel)
	_card_panel = panel
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 6)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vb)

	var head := _label("Gold catch" if gold else ("Not quite a fish" if info.get("junk", false) else "You caught"), 20, Color(INK, 0.75))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(head)

	# stage: 3D turntable + ribbon + gold sparkle
	var stage := Control.new(); stage.custom_minimum_size = Vector2(404, 286)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(stage)
	var bg := Panel.new(); bg.set_anchors_preset(Control.PRESET_FULL_RECT); bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bgs := StyleBoxFlat.new(); bgs.bg_color = Color("fff1c4") if gold else Color("e6f2f0")
	bgs.set_corner_radius_all(18); bgs.border_color = Color(INK, 0.25); bgs.set_border_width_all(2)
	bg.add_theme_stylebox_override("panel", bgs)
	stage.add_child(bg)
	var svc := SubViewportContainer.new(); svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT); svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(svc)
	var sv := SubViewport.new(); sv.own_world_3d = true; sv.transparent_bg = true
	sv.msaa_3d = Viewport.MSAA_4X; sv.size = Vector2i(404, 286)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(sv)
	_build_turntable(sv, info)
	if gold:
		var sp := Sparkles.new(); sp.set_anchors_preset(Control.PRESET_FULL_RECT)
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(sp)
		var gb := _badge("Gold!", GOLD, INK, 0.12)
		gb.position = Vector2(300, 12)
		stage.add_child(gb)
		_pop_in(gb, 0.5)
	if info.get("trophy", false) and not gold:
		var tb := _badge("Trophy", Color("6fc2b6"), CREAM, 0.1)
		tb.position = Vector2(290, 236)
		stage.add_child(tb)
		_pop_in(tb, 0.6)
	if info.get("record", false) or info.get("first", false):
		var rb := _badge("New record!", CORAL, CREAM, -0.1)
		rb.position = Vector2(-14, 14)
		stage.add_child(rb)
		_pop_in(rb, 0.35)

	var nm := _label(str(info.get("name", "Fish")), 36, INK)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(nm)

	var cm := float(info.get("cm", 0.0))
	var sz := _label("%.1f cm" % cm, 30, Color("4f8f88") if not gold else Color("b8862a"))
	sz.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sz)
	var sub := ""
	if info.get("first", false): sub = "New to your notebook."
	elif info.get("record", false): sub = "Old best: %.1f cm" % float(info.get("prev_best", 0.0))
	else: sub = "Your best: %.1f cm" % float(info.get("prev_best", 0.0))
	var subl := _label(sub, 18, Color(INK, 0.7))
	subl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(subl)

	var stars := Stars.new(); stars.count = int(info.get("rarity", 1)); stars.custom_minimum_size = Vector2(0, 46)
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(stars)

	var price := int(info.get("price", 0))
	var hb := HBoxContainer.new(); hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 8); hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(hb)
	hb.add_child(_label("Pip pays about", 20, Color(INK, 0.8)))
	hb.add_child(_money(price))

	var btn: Button
	var sb = _style_call("button", ["Into the bag", "mint", 28])
	if sb is Button: btn = sb
	else:
		btn = Button.new(); btn.text = "Into the bag"
		_style_button(btn)
		btn.button_down.connect(func() -> void:
			btn.pivot_offset = btn.size * 0.5
			btn.create_tween().tween_property(btn, "scale", Vector2(0.94, 0.94), 0.06))
		btn.button_up.connect(func() -> void:
			btn.create_tween().tween_property(btn, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	btn.custom_minimum_size = Vector2(300, 88)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(close_card)
	vb.add_child(btn)
	var hint := _label("Tap anywhere to close", 15, Color(INK, 0.5))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(hint)

	# pop in
	panel.modulate.a = 0.0
	dim.modulate.a = 0.0
	card.create_tween().tween_property(dim, "modulate:a", 1.0, 0.2)
	await get_tree().process_frame
	if not is_instance_valid(panel): return
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.75, 0.75)
	var tw := panel.create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.12)
	tw.parallel().tween_property(panel, "scale", Vector2.ONE, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func card_open() -> bool:
	return is_instance_valid(card) and not _closing

func close_card() -> void:
	if not is_instance_valid(card) or _closing: return
	_closing = true
	var c := card
	var tw := c.create_tween()
	if is_instance_valid(_card_panel):
		tw.tween_property(_card_panel, "scale", Vector2(0.9, 0.9), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(c, "modulate:a", 0.0, 0.14)
	tw.tween_callback(func() -> void:
		if is_instance_valid(c): c.queue_free()
		if card == c: card = null
		_closing = false
		card_closed.emit())

func _on_card_input(e: InputEvent) -> void:
	var pressed: bool = (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT)
	if pressed:
		card.accept_event()
		if _card_t > 0.45: close_card()

func _build_turntable(sv: SubViewport, info: Dictionary) -> void:
	var root := Node3D.new(); sv.add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("f4e8f0"); env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new(); we.environment = env; root.add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(30), 0)
	sun.light_energy = 0.95; sun.light_color = Color("fff1dc"); sun.shadow_enabled = true
	root.add_child(sun)
	var fill := DirectionalLight3D.new(); fill.rotation = Vector3(deg_to_rad(-20), deg_to_rad(-140), 0)
	fill.light_energy = 0.35; fill.light_color = Color("cfe6ff"); root.add_child(fill)
	var cam := Camera3D.new(); cam.fov = 30.0
	var cp := Vector3(0, 1.2, 4.3)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 0.7, 0) - cp, Vector3.UP), cp)
	root.add_child(cam); cam.current = true

	var tt := Turntable.new(); root.add_child(tt)
	var gold: bool = info.get("gold", false)
	Toys.add(Toys.cyl(0.78, 0.86, 0.26, 40), Toys.mat(Color("f6dcb4")), Vector3(0, 0.13, 0), tt)
	Toys.add(Toys.cyl(0.72, 0.72, 0.05, 40), Toys.mat(GOLD if gold else Color("fff1df")), Vector3(0, 0.285, 0), tt)
	for i in 8:
		var a := TAU * i / 8.0
		Toys.add(Toys.sphere(0.05), Toys.mat(Color("6fc2b6") if i % 2 == 0 else Color("f4a9a8"), 0.8, 0.008),
			Vector3(cos(a) * 0.83, 0.15, sin(a) * 0.83), tt)
	var cm := float(info.get("cm", 20.0))
	var length := clampf(1.55 + (cm - 10.0) / 200.0, 1.55, 2.2)
	var body: Color = GOLD if gold else info.get("body", Color("a9c4d6"))
	var fin: Color = Color("d99a30") if gold else info.get("fin", Color("6f8fa8"))
	var swim := Node3D.new(); swim.position = Vector3(0, 0.62 + length * 0.12, 0); tt.add_child(swim)
	tt.fish = swim
	var f := Toys.fish(swim, body, fin, length)
	f.rotation.y = PI / 2
	if gold:
		for c in f.get_children():
			if c is MeshInstance3D and c.material_override is StandardMaterial3D:
				var m: StandardMaterial3D = c.material_override
				if m.albedo_color.v > 0.5:
					m.metallic = 0.55; m.roughness = 0.3
					m.emission_enabled = true; m.emission = GOLD; m.emission_energy_multiplier = 0.25

# ---------------------------------------------------------------- style helpers (Style when present)
func _style_call(fn: String, args: Array):
	if _style == null: return null
	for m in _style.get_script_method_list():
		if m.get("name", "") == fn:
			var need: int = m.get("args", []).size() - m.get("default_args", []).size()
			if args.size() < need or args.size() > m.get("args", []).size(): return null
			return _style.callv(fn, args)
	return null

func _panel_box() -> StyleBox:
	var s = _style_call("panel_box", [CREAM, RADIUS, 3, 22])
	if s is StyleBox: return s
	var b := StyleBoxFlat.new()
	b.bg_color = CREAM; b.border_color = INK; b.set_border_width_all(3); b.set_corner_radius_all(RADIUS)
	b.content_margin_left = 24; b.content_margin_right = 24; b.content_margin_top = 18; b.content_margin_bottom = 18
	b.shadow_color = Color(0, 0, 0, 0.18); b.shadow_size = 10; b.shadow_offset = Vector2(0, 6)
	return b

func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new(); l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _style_button(b: Button) -> void:
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 28)
	for st in ["normal", "hover", "pressed", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = TEAL if st != "pressed" else TEAL.darkened(0.15)
		if st == "hover": s.bg_color = TEAL.lightened(0.08)
		s.border_color = INK; s.set_border_width_all(3); s.set_corner_radius_all(RADIUS)
		if st == "focus": s.draw_center = false
		s.shadow_color = Color(INK, 0.35); s.shadow_size = 0; s.shadow_offset = Vector2(0, 0 if st == "pressed" else 4)
		b.add_theme_stylebox_override(st, s)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, CREAM)
	b.add_theme_color_override("font_outline_color", INK)
	b.add_theme_constant_override("outline_size", 6)

func _badge(text: String, bgc: Color, fg: Color, rot: float) -> Control:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new(); s.bg_color = bgc; s.border_color = INK; s.set_border_width_all(3); s.set_corner_radius_all(14)
	s.content_margin_left = 16; s.content_margin_right = 16; s.content_margin_top = 4; s.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", s)
	var l := _label(text, 24, fg)
	if fg == CREAM:
		l.add_theme_color_override("font_outline_color", INK); l.add_theme_constant_override("outline_size", 6)
	p.add_child(l)
	p.rotation = rot
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

func _pop_in(c: Control, delay: float) -> void:
	c.scale = Vector2.ZERO
	var tw := c.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func() -> void: c.pivot_offset = c.size * 0.5)
	tw.tween_property(c, "scale", Vector2(1.15, 1.15), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2.ONE, 0.1)

## Money as yen: Style.money(n) when it exists, else a green banknote icon + "¥n".
func _money(n: int) -> Control:
	var v = _style_call("money", [n])
	if v is Control: return v
	var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", 6)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon = _style_call("icon", ["yen", 30.0])
	if icon is Control: hb.add_child(icon)
	elif icon is Texture2D:
		var tr := TextureRect.new(); tr.texture = icon; tr.custom_minimum_size = Vector2(40, 26)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hb.add_child(tr)
	else:
		var note := Banknote.new(); note.custom_minimum_size = Vector2(40, 26); note.font = _font
		note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(note)
	var text: String = v if v is String else "¥%d" % n
	hb.add_child(_label(text, 24, Color("3f7f55")))
	return hb

# ================================================================ inner widgets
class ReelGauge extends Control:
	const CREAM := Color("fffaf2")
	const INK := Color("6b4a3a")
	const TEAL := Color("6fc2b6")
	const CORAL := Color("e8746a")
	const SOFT := Color("efe3d3")
	var font: Font
	var progress := 0.0
	var tension := 0.0
	var shown_tension := 0.0
	var warn := false
	var surging := false
	var held := false
	var fish_col := Color("a9c4d6")
	var appear := 1.0
	var t := 0.0

	func _process(dt: float) -> void:
		if not visible: return
		t += dt
		shown_tension = lerpf(shown_tension, tension, 1.0 - exp(-18.0 * dt))
		queue_redraw()

	func _tension_col(k: float) -> Color:
		if k < 0.55: return Color("8fd18f").lerp(Color("f2c14e"), k / 0.55)
		return Color("f2c14e").lerp(CORAL, clampf((k - 0.55) / 0.3, 0.0, 1.0))

	func _draw() -> void:
		var vs := size
		var c := Vector2(minf(150.0, vs.x * 0.28), vs.y - 225.0)
		var k := shown_tension
		var shake := Vector2.ZERO
		if k > 0.75 or surging:
			var amp := 2.0 + 9.0 * clampf((k - 0.75) / 0.25, 0.0, 1.0) + (3.0 if surging else 0.0)
			shake = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * amp
		var sc := appear
		draw_set_transform(c + shake, 0.0, Vector2(sc, sc))
		var o := Vector2.ZERO
		# plate
		draw_circle(o + Vector2(0, 6), 120, Color(INK, 0.18))
		draw_circle(o, 120, CREAM)
		draw_arc(o, 120, 0, TAU, 96, CORAL if surging else INK, 3.5 if not surging else 5.0, true)
		# progress ring
		draw_arc(o, 95, 0, TAU, 96, SOFT, 20, true)
		if progress > 0.002:
			var a1 := -PI / 2 + TAU * progress
			draw_arc(o, 95, -PI / 2, a1, maxi(6, int(96 * progress)), TEAL, 20, true)
			draw_circle(o + Vector2(cos(a1), sin(a1)) * 95, 12, TEAL.lightened(0.2))
			draw_arc(o + Vector2(cos(a1), sin(a1)) * 95, 12, 0, TAU, 24, INK, 2.5, true)
		draw_arc(o, 106, 0, TAU, 96, INK, 2.5, true)
		draw_arc(o, 84, 0, TAU, 96, INK, 2.5, true)
		# fish icon (wiggles harder with tension / surges)
		var wig := sin(t * (9.0 + 14.0 * k)) * (0.08 + 0.25 * k + (0.35 if surging else 0.0))
		var pull := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * (4.0 if surging else 0.0)
		_fish_icon(o + Vector2(6, -14) + pull, wig)
		# surge warning
		if warn or surging:
			var pulse := 1.0 + 0.15 * sin(t * 30.0)
			var wp := o + Vector2(118, -112)
			draw_circle(wp, 26 * pulse, CORAL)
			draw_arc(wp, 26 * pulse, 0, TAU, 32, INK, 3.0, true)
			_text(wp + Vector2(0, 2), "!", 34, CREAM)
		# tension meter
		var mx := 170.0; var top := -125.0; var h := 250.0; var w := 44.0
		var box := StyleBoxFlat.new(); box.bg_color = CREAM; box.border_color = CORAL if k > 0.8 else INK
		box.set_border_width_all(3); box.set_corner_radius_all(22)
		box.shadow_color = Color(INK, 0.18); box.shadow_size = 0; box.shadow_offset = Vector2(0, 6)
		draw_style_box(box, Rect2(mx - w / 2, top, w, h))
		var inner := Rect2(mx - w / 2 + 6, top + 6, w - 12, h - 12)
		var danger := StyleBoxFlat.new(); danger.bg_color = Color(CORAL, 0.18); danger.set_corner_radius_all(16)
		draw_style_box(danger, Rect2(inner.position, Vector2(inner.size.x, inner.size.y * 0.22)))
		var fh := maxf(inner.size.y * clampf(k, 0.0, 1.0), 0.0)
		if fh > 2.0:
			var fill := StyleBoxFlat.new(); fill.bg_color = _tension_col(k); fill.set_corner_radius_all(int(minf(16.0, fh * 0.5)))
			draw_style_box(fill, Rect2(inner.position.x, inner.end.y - fh, inner.size.x, fh))
		var ly := inner.position.y + inner.size.y * 0.22
		draw_line(Vector2(inner.position.x - 2, ly), Vector2(inner.end.x + 2, ly), Color(INK, 0.6), 2.0)
		_text(Vector2(mx, top + h + 26), "LINE", 18, Color(INK, 0.75))
		# hint lives inside the ring, right under the fish: one glance covers both
		var hint := "Hold!"
		var hc := INK
		if (surging and held) or k > 0.8: hint = "Ease off!"; hc = CORAL
		elif warn: hint = "Careful..."; hc = CORAL
		elif held: hint = "Reeling"; hc = Color("3f9488")
		var bob := sin(t * 6.0) * 2.0 if not held else 0.0
		_text(o + Vector2(0, 46 + bob), hint, 25, hc)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _fish_icon(p: Vector2, ang: float) -> void:
		var pts := PackedVector2Array()
		for i in 28:
			var a := TAU * i / 28.0
			pts.append(p + Vector2(cos(a) * 40.0, sin(a) * 23.0).rotated(ang))
		var tail := PackedVector2Array([p + Vector2(-32, 0).rotated(ang), p + Vector2(-60, -21).rotated(ang * 1.8),
			p + Vector2(-56, 0).rotated(ang * 1.8), p + Vector2(-60, 21).rotated(ang * 1.8)])
		draw_colored_polygon(tail, fish_col.darkened(0.15))
		var tl := tail.duplicate(); tl.append(tail[0])
		draw_polyline(tl, INK, 3.0, true)
		draw_colored_polygon(pts, fish_col)
		var cl := pts.duplicate(); cl.append(pts[0])
		draw_polyline(cl, INK, 3.0, true)
		draw_circle(p + Vector2(20, -5).rotated(ang), 4.5, INK)

	func _text(p: Vector2, s: String, fs: int, col: Color, outline := false) -> void:
		var f := font if font else get_theme_default_font()
		var w := 420.0
		var pos := p + Vector2(-w / 2, fs * 0.35)
		if outline: draw_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_CENTER, w, fs, 10, CREAM)
		draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_CENTER, w, fs, col)

class BitePop extends Control:
	const CREAM := Color("fffaf2")
	const INK := Color("6b4a3a")
	const CORAL := Color("e8746a")
	var font: Font
	var at := Vector2.ZERO
	var t := 0.0
	func _process(dt: float) -> void:
		if not visible: return
		t += dt; queue_redraw()
	func _draw() -> void:
		var k := 1.0 + 0.6 * exp(-t * 14.0) + 0.06 * sin(t * 25.0)
		draw_set_transform(at, sin(t * 40.0) * 0.08 * exp(-t * 4.0), Vector2(k, k))
		draw_colored_polygon(PackedVector2Array([Vector2(-12, 36), Vector2(12, 36), Vector2(0, 58)]), CREAM)
		draw_circle(Vector2(0, 4), 48, Color(INK, 0.2))
		draw_circle(Vector2.ZERO, 48, CREAM)
		draw_arc(Vector2.ZERO, 48, 0, TAU, 48, INK, 4.0, true)
		var f := font if font else get_theme_default_font()
		draw_string_outline(f, Vector2(-60, 24), "!", HORIZONTAL_ALIGNMENT_CENTER, 120, 72, 8, CREAM)
		draw_string(f, Vector2(-60, 24), "!", HORIZONTAL_ALIGNMENT_CENTER, 120, 72, CORAL)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

class Stars extends Control:
	const INK := Color("6b4a3a")
	var count := 1
	var max_stars := 4
	func _draw() -> void:
		var r := 19.0; var gap := 50.0
		var x0 := size.x * 0.5 - gap * (max_stars - 1) * 0.5
		for i in max_stars:
			var c := Vector2(x0 + gap * i, size.y * 0.5)
			var pts := PackedVector2Array()
			for j in 10:
				var a := -PI / 2 + PI * j / 5.0
				var rr := r if j % 2 == 0 else r * 0.47
				pts.append(c + Vector2(cos(a), sin(a)) * rr)
			draw_colored_polygon(pts, Color("f2c14e") if i < count else Color("efe3d3"))
			var cl := pts.duplicate(); cl.append(pts[0])
			draw_polyline(cl, INK, 3.0, true)

class Sparkles extends Control:
	var t := 0.0
	var seeds := []
	func _ready() -> void:
		for i in 12: seeds.append(Vector3(randf(), randf(), randf() * TAU))
	func _process(dt: float) -> void:
		t += dt; queue_redraw()
	func _draw() -> void:
		for s in seeds:
			var k := maxf(0.0, sin(t * 3.0 + s.z))
			if k < 0.05: continue
			var p := Vector2(s.x * size.x, s.y * size.y)
			var r := 14.0 * k
			var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r * 0.25, -r * 0.25), p + Vector2(r, 0), p + Vector2(r * 0.25, r * 0.25),
				p + Vector2(0, r), p + Vector2(-r * 0.25, r * 0.25), p + Vector2(-r, 0), p + Vector2(-r * 0.25, -r * 0.25)])
			draw_colored_polygon(pts, Color(1.0, 0.97, 0.75, 0.95))

class Banknote extends Control:
	const INK := Color("6b4a3a")
	const NOTE := Color("8fd3a4")
	var font: Font
	func _draw() -> void:
		var r := Rect2(Vector2(2, 2), size - Vector2(4, 4))
		var b := StyleBoxFlat.new(); b.bg_color = NOTE; b.border_color = INK; b.set_border_width_all(2); b.set_corner_radius_all(5)
		draw_style_box(b, r)
		draw_circle(r.get_center(), r.size.y * 0.3, Color("d8f2df"))
		draw_arc(r.get_center(), r.size.y * 0.3, 0, TAU, 20, INK, 1.5, true)
		var f := font if font else get_theme_default_font()
		draw_string(f, r.get_center() + Vector2(-10, 5), "¥", HORIZONTAL_ALIGNMENT_CENTER, 20, 13, INK)

class Turntable extends Node3D:
	var fish: Node3D
	var t := 0.0
	func _process(dt: float) -> void:
		t += dt
		rotation.y += dt * 0.9
		if is_instance_valid(fish):
			fish.position.y = 0.95 + sin(t * 2.2) * 0.05
			fish.rotation.z = sin(t * 3.1) * 0.08
