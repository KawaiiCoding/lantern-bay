extends Node3D
## Lantern Bay — look-dev scene. Builds a small seaside town from primitives:
## soft rounded toys with an ink outline, golden-hour light, tilt-shift depth of field.
## Run with:  godot --path . -- shot=hero out=shots/hero.png   (saves a screenshot and quits)

const INK := Color("6b4a3a")
var args := {}

# ---------------------------------------------------------------- helpers
func mat(c: Color, rough := 0.85, outline := 0.025) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.rim_enabled = true
	m.rim = 0.25
	m.rim_tint = 0.6
	if outline > 0.0:
		var o := StandardMaterial3D.new()
		o.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		o.albedo_color = INK
		o.cull_mode = BaseMaterial3D.CULL_FRONT
		o.grow = true
		o.grow_amount = outline
		m.next_pass = o
	return m

func glow(c: Color, k := 2.5) -> StandardMaterial3D:
	var m := mat(c, 0.5, 0.0)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = k
	return m

func sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new(); s.radius = r; s.height = r * 2.0; s.radial_segments = 32; s.rings = 16
	return s

func capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new(); c.radius = r; c.height = h; c.radial_segments = 24; c.rings = 8
	return c

func cyl(top: float, bot: float, h: float, seg := 24) -> CylinderMesh:
	var c := CylinderMesh.new(); c.top_radius = top; c.bottom_radius = bot; c.height = h; c.radial_segments = seg
	return c

func box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new(); b.size = Vector3(x, y, z)
	return b

func torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new(); t.inner_radius = inner; t.outer_radius = outer; t.rings = 24; t.ring_segments = 12
	return t

func add(m: Mesh, mt: Material, pos := Vector3.ZERO, parent: Node3D = null, scl := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = m; n.material_override = mt; n.position = pos; n.scale = scl; n.rotation = rot
	(parent if parent else self).add_child(n)
	return n

func group(pos := Vector3.ZERO, parent: Node3D = null, rot_y := 0.0, s := 1.0) -> Node3D:
	var g := Node3D.new(); g.position = pos; g.rotation.y = rot_y; g.scale = Vector3.ONE * s
	(parent if parent else self).add_child(g)
	return g

# ---------------------------------------------------------------- characters
func bear(parent: Node3D, sitting := false) -> Node3D:
	var g := group(Vector3.ZERO, parent)
	var fur := mat(Color("d9a877")); var light := mat(Color("f3dcc0")); var dark := mat(Color("3b2a24"), 0.2, 0.0)
	var blush := mat(Color("f2a0a6"), 0.9, 0.0); var scarf := mat(Color("6fc2b6"))
	add(sphere(0.5), fur, Vector3(0, 0.55, 0), g, Vector3(1, 1.05, 0.9))
	add(sphere(0.3), light, Vector3(0, 0.5, 0.28), g, Vector3(1, 1.1, 0.5))
	var h := group(Vector3(0, 1.25, 0.05), g)
	add(sphere(0.46), fur, Vector3.ZERO, h, Vector3(1.08, 0.95, 0.95))
	for s in [-1, 1]:
		add(sphere(0.15), fur, Vector3(0.32 * s, 0.36, -0.02), h)
		add(sphere(0.08), light, Vector3(0.32 * s, 0.36, 0.08), h, Vector3(1, 1, 0.5))
		add(sphere(0.05), dark, Vector3(0.16 * s, 0.06, 0.41), h)
		add(sphere(0.07), blush, Vector3(0.28 * s, -0.07, 0.34), h, Vector3(1, 0.6, 0.4))
	add(sphere(0.17), light, Vector3(0, -0.1, 0.37), h, Vector3(1.2, 0.85, 0.7))
	add(sphere(0.055), dark, Vector3(0, -0.04, 0.5), h)
	add(torus(0.26, 0.42), scarf, Vector3(0, 0.9, 0.02), g)
	add(capsule(0.09, 0.4), scarf, Vector3(0.16, 0.68, 0.38), g, Vector3.ONE, Vector3(0.2, 0, 0.25))
	for s in [-1, 1]:
		add(capsule(0.11, 0.5), fur, Vector3(0.38 * s, 0.72, 0.3), g, Vector3.ONE, Vector3(-1.1, 0, 0.3 * s))
		if not sitting:
			add(capsule(0.13, 0.36), fur, Vector3(0.2 * s, 0.12, 0.05), g)
	return g

func cat(parent: Node3D, main: Color, patch := Color(0, 0, 0, 0), sleepy := false) -> Node3D:
	var g := group(Vector3.ZERO, parent)
	var fur := mat(main); var dark := mat(Color("3b2a24"), 0.2, 0.0); var pink := mat(Color("f3a7b0"), 0.9, 0.0)
	add(sphere(0.46), fur, Vector3(0, 0.36, -0.05), g, Vector3(1.1, 0.85, 1.3))
	var h := group(Vector3(0, 0.82, 0.34), g)
	add(sphere(0.34), fur, Vector3.ZERO, h, Vector3(1.12, 0.95, 0.95))
	if patch.a > 0.0:
		add(sphere(0.22), mat(patch, 0.85, 0.0), Vector3(-0.17, 0.12, 0.14), h, Vector3(1, 0.9, 0.8))
	for s in [-1, 1]:
		var cone := CylinderMesh.new(); cone.top_radius = 0.0; cone.bottom_radius = 0.13; cone.height = 0.26; cone.radial_segments = 12
		add(cone, fur, Vector3(0.2 * s, 0.33, 0), h, Vector3.ONE, Vector3(0, 0, -0.3 * s))
		if sleepy:
			add(capsule(0.018, 0.12), dark, Vector3(0.13 * s, 0.03, 0.31), h, Vector3.ONE, Vector3(0, 0, PI / 2))
		else:
			add(sphere(0.045), dark, Vector3(0.13 * s, 0.03, 0.3), h)
		add(sphere(0.05), pink, Vector3(0.22 * s, -0.07, 0.26), h, Vector3(1, 0.6, 0.4))
	add(sphere(0.04), pink, Vector3(0, -0.05, 0.33), h)
	add(torus(0.26, 0.36), fur, Vector3(0, 0.35, -0.5), g, Vector3(1, 1, 0.6), Vector3(0, PI / 2, 0.3))
	return g

func moped(parent: Node3D) -> Node3D:
	var g := group(Vector3.ZERO, parent)
	var mint := mat(Color("8fd6c8"), 0.35); var cream := mat(Color("fff1df")); var tire := mat(Color("45405a"), 0.7)
	var chrome := mat(Color("e4e1ea"), 0.2)
	for z in [-0.85, 0.9]:
		add(torus(0.18, 0.34), tire, Vector3(0, 0.34, z), g, Vector3.ONE, Vector3(0, 0, PI / 2))
		add(cyl(0.12, 0.12, 0.22), chrome, Vector3(0, 0.34, z), g, Vector3.ONE, Vector3(0, 0, PI / 2))
	add(capsule(0.32, 1.7), mint, Vector3(0, 0.62, -0.1), g, Vector3(1, 1, 0.75), Vector3(PI / 2, 0, 0))
	add(sphere(0.5), mint, Vector3(0, 0.78, -0.55), g, Vector3(0.85, 0.65, 1.15))
	add(capsule(0.16, 0.7), mat(Color("7a5a4c")), Vector3(0, 1.06, -0.45), g, Vector3(1.4, 1, 1), Vector3(PI / 2, 0, 0))
	add(capsule(0.3, 1.1), mint, Vector3(0, 1.05, 0.72), g, Vector3(1.05, 1, 0.45), Vector3(-0.25, 0, 0))
	add(cyl(0.035, 0.035, 1.0), chrome, Vector3(0, 1.58, 0.66), g, Vector3.ONE, Vector3(0, 0, PI / 2))
	add(sphere(0.14), glow(Color("fff3c0"), 3.0), Vector3(0, 1.42, 0.92), g)
	add(box(0.55, 0.32, 0.45), mat(Color("c98a5a")), Vector3(0, 1.25, -1.05), g)
	add(cyl(0.1, 0.08, 0.22), cream, Vector3(0.1, 1.55, -1.05), g)
	add(cyl(0.105, 0.105, 0.05), mat(Color("e58a94")), Vector3(0.1, 1.67, -1.05), g)
	var beam := SpotLight3D.new(); beam.light_color = Color("fff1c4"); beam.light_energy = 3.0; beam.spot_range = 8.0; beam.spot_angle = 28
	beam.position = Vector3(0, 1.4, 0.95); g.add_child(beam)
	return g

# ---------------------------------------------------------------- world
func house(pos: Vector3, rot_y: float, wall: Color, roof: Color, w := 3.2, h := 2.6) -> void:
	var g := group(pos, null, rot_y)
	add(box(w, h, 2.6), mat(wall), Vector3(0, h / 2, 0), g)
	var pr := PrismMesh.new(); pr.size = Vector3(w + 0.5, 1.3, 2.9)
	add(pr, mat(roof), Vector3(0, h + 0.65, 0), g)
	add(box(0.7, 1.3, 0.1), mat(Color("8a6b5c")), Vector3(0.7, 0.65, 1.31), g)
	add(box(0.9, 0.7, 0.08), glow(Color("ffd9a0"), 0.9), Vector3(-0.7, 1.3, 1.31), g)
	add(box(1.1, 0.12, 0.25), mat(Color("fff6ea")), Vector3(-0.7, 0.9, 1.4), g)
	for i in 4:
		var f := Color("f4a9a8") if i % 2 == 0 else Color("fff1b8")
		add(sphere(0.09), mat(f, 0.9, 0.012), Vector3(-1.05 + i * 0.23, 1.02, 1.42), g)
	add(cyl(0.12, 0.12, 0.5), mat(Color("c98a5a")), Vector3(w / 2 - 0.4, h + 0.9, -0.4), g)

func tree(pos: Vector3, s := 1.0, c := Color("8cc79a")) -> void:
	var g := group(pos, null, 0, s)
	add(cyl(0.12, 0.18, 1.0), mat(Color("9a7058")), Vector3(0, 0.5, 0), g)
	add(sphere(0.8), mat(c), Vector3(0, 1.5, 0), g)
	add(sphere(0.55), mat(c.lightened(0.1)), Vector3(0.45, 1.25, 0.25), g)
	add(sphere(0.5), mat(c.darkened(0.06)), Vector3(-0.4, 1.3, -0.2), g)

func lamp(pos: Vector3) -> void:
	add(cyl(0.06, 0.08, 2.4), mat(Color("6e6390")), pos + Vector3(0, 1.2, 0))
	add(sphere(0.2), glow(Color("fff0c0"), 2.5), pos + Vector3(0, 2.5, 0))
	var l := OmniLight3D.new(); l.light_color = Color("ffd89a"); l.light_energy = 1.4; l.omni_range = 4.5
	l.position = pos + Vector3(0, 2.4, 0); add_child(l)

func world() -> void:
	# sea
	var sea := mat(Color("8fcde0"), 0.08, 0.0); sea.metallic = 0.2
	add(box(200, 0.2, 200), sea, Vector3(0, -0.25, 0))
	# island: sand rim + soft grass top
	add(cyl(15.5, 16.5, 0.5, 64), mat(Color("f4dfb6"), 0.95, 0.0), Vector3(0, -0.1, 0))
	add(cyl(14, 14.6, 0.5, 64), mat(Color("a9d99a"), 0.95, 0.0), Vector3(0, 0.05, 0))
	# road loop
	add(box(30, 0.06, 2.6), mat(Color("c9bfd9"), 0.9, 0.0), Vector3(0, 0.32, 1.5))
	for x in range(-12, 13, 3):
		add(box(1.0, 0.07, 0.12), mat(Color("fff6ea"), 0.9, 0.0), Vector3(x, 0.34, 1.5))
	# houses along the road
	house(Vector3(-7.5, 0.3, -3.2), 0.05, Color("fbe2d2"), Color("e58a94"))
	house(Vector3(-3.6, 0.3, -3.5), -0.03, Color("e6dcf6"), Color("9d8fd6"), 3.0, 3.1)
	house(Vector3(0.6, 0.3, -3.3), 0.02, Color("dff1e6"), Color("6fb7a8"))
	house(Vector3(4.8, 0.3, -3.6), -0.05, Color("fff0c8"), Color("e8a35c"), 3.4, 2.8)
	house(Vector3(-5.0, 0.3, 6.4), PI + 0.06, Color("f6e2ea"), Color("c98a9a"), 3.0, 2.4)
	# lighthouse on the point
	var lh := group(Vector3(10.5, 0.3, -5.5))
	for i in 4:
		add(cyl(0.95 - i * 0.12, 1.07 - i * 0.12, 1.2, 32), mat(Color("fffaf2") if i % 2 == 0 else Color("e8747f")), Vector3(0, 0.6 + i * 1.2, 0), lh)
	add(cyl(0.6, 0.6, 0.7, 24), glow(Color("fff1b8"), 1.6), Vector3(0, 5.15, 0), lh)
	var cone := CylinderMesh.new(); cone.top_radius = 0.0; cone.bottom_radius = 0.85; cone.height = 0.8; cone.radial_segments = 32
	add(cone, mat(Color("e8747f")), Vector3(0, 5.9, 0), lh)
	# pier + boat
	add(box(1.6, 0.18, 6), mat(Color("c98a5a")), Vector3(7.0, 0.35, 12.5))
	var boat := group(Vector3(8.6, 0.05, 14.5), null, 0.3)
	add(sphere(0.9), mat(Color("fffaf2"), 0.6), Vector3(0, 0.1, 0), boat, Vector3(0.8, 0.45, 1.8))
	add(box(1.2, 0.1, 2.4), mat(Color("9ad0e8")), Vector3(0, 0.35, 0), boat)
	# trees, bushes, flowers, lamps, fence
	for p in [Vector3(-11, 0.3, -1), Vector3(-1.3, 0.3, -6.5), Vector3(7.6, 0.3, -1.2), Vector3(2.5, 0.3, 6.6), Vector3(-9, 0.3, 5.5), Vector3(11, 0.3, 4)]:
		tree(p, 0.9 + fmod(abs(p.x), 3.0) * 0.12)
	for p in [Vector3(-6, 0.3, -0.6), Vector3(-2, 0.3, -0.7), Vector3(3, 0.3, -0.5), Vector3(6.6, 0.3, -0.8)]:
		add(sphere(0.45), mat(Color("9fd39a")), p, null, Vector3(1.3, 0.8, 1))
	var fc := [Color("f4a9a8"), Color("fff1b8"), Color("c9b6e4"), Color("ffffff")]
	for i in 40:
		var a := float(i) * 2.399
		var r := 4.0 + fmod(float(i) * 3.7, 9.0)
		var fp := Vector3(cos(a) * r, 0.36, sin(a) * r + 2.0)
		if abs(fp.z - 1.5) < 1.8: continue
		add(sphere(0.08), mat(fc[i % 4], 0.9, 0.0), fp)
	for x in [-8.5, -2.6, 2.8, 8.0]:
		lamp(Vector3(x, 0.3, 0.0))
	for i in 9:
		add(box(0.12, 0.6, 0.12), mat(Color("fffaf2")), Vector3(-1.5 + i * 0.6, 0.6, 3.5))
	add(box(5.2, 0.1, 0.08), mat(Color("fffaf2")), Vector3(0.9, 0.78, 3.5))

func env(sun_e := 2.2) -> void:
	var we := WorldEnvironment.new(); var e := Environment.new()
	var sky := Sky.new(); var ps := ProceduralSkyMaterial.new()
	ps.sky_top_color = Color("9fc2ee"); ps.sky_horizon_color = Color("ffd7c2")
	ps.ground_horizon_color = Color("ffd7c2"); ps.ground_bottom_color = Color("8fcde0")
	sky.sky_material = ps; e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY; e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_ACES; e.tonemap_exposure = 1.05; e.tonemap_white = 6.0
	e.ssao_enabled = true; e.ssao_radius = 1.2; e.ssao_intensity = 1.6
	e.glow_enabled = true; e.glow_intensity = 0.6; e.glow_bloom = 0.08
	e.fog_enabled = true; e.fog_light_color = Color("ffe3d2"); e.fog_density = 0.008; e.fog_aerial_perspective = 0.4
	e.adjustment_enabled = true; e.adjustment_saturation = 1.08
	we.environment = e; add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("ffe2b8"); sun.light_energy = sun_e
	sun.rotation_degrees = Vector3(-38, 35, 0)
	sun.shadow_enabled = true; sun.shadow_blur = 1.6; sun.directional_shadow_max_distance = 60
	add_child(sun)

func camera(pos: Vector3, look: Vector3, fov: float, focus: float, blur := true) -> void:
	var c := Camera3D.new(); c.fov = fov; add_child(c)
	c.position = pos; c.look_at(look)
	if blur:
		var a := CameraAttributesPractical.new()
		a.dof_blur_far_enabled = true; a.dof_blur_far_distance = focus + 6.0; a.dof_blur_far_transition = 10.0
		a.dof_blur_near_enabled = true; a.dof_blur_near_distance = max(1.0, focus - 7.0); a.dof_blur_near_transition = 3.0
		a.dof_blur_amount = 0.07
		c.attributes = a
	c.current = true

# ---------------------------------------------------------------- UI (no emojis)
func panel(parent: Control, rect: Rect2, bg := Color("fffaf2")) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg; sb.border_color = INK; sb.set_border_width_all(3); sb.set_corner_radius_all(22)
	sb.content_margin_left = 16; sb.content_margin_right = 16; sb.content_margin_top = 8; sb.content_margin_bottom = 8
	sb.shadow_color = Color(0.42, 0.29, 0.23, 0.35); sb.shadow_size = 0; sb.shadow_offset = Vector2(0, 3)
	p.add_theme_stylebox_override("panel", sb)
	p.position = rect.position; p.size = rect.size
	parent.add_child(p)
	return p

func label(parent: Control, t: String, size: int, c := INK) -> Label:
	var l := Label.new(); l.text = t
	l.add_theme_font_size_override("font_size", size); l.add_theme_color_override("font_color", c)
	parent.add_child(l)
	return l

func hud(place: String, sub: String, clock: String) -> Control:
	var cl := CanvasLayer.new(); add_child(cl)
	var root := Control.new(); root.size = Vector2(540, 960); cl.add_child(root)
	var top := panel(root, Rect2(18, 18, 504, 72))
	var hb := HBoxContainer.new(); top.add_child(hb)
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", -4); hb.add_child(vb)
	label(vb, place, 24); label(vb, sub, 15, Color("8a6f86"))
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hb.add_child(sp)
	var ck := panel(hb, Rect2(), Color("3d3a72")); ck.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label(ck, clock, 24, Color("ffe39a"))
	return root

# ---------------------------------------------------------------- shots
func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=", true, 1)
		if kv.size() == 2: args[kv[0]] = kv[1]
	var shot: String = args.get("shot", "hero")
	env()
	world()
	if shot == "hero":
		var rider := group(Vector3(-0.6, 0.32, 1.6), null, 0.55, 1.0)
		moped(rider)
		var b := bear(rider, true); b.position = Vector3(0, 0.85, -0.35)
		var c1 := cat(group(Vector3(1.8, 0.82, 3.55), null, -0.5, 0.75), Color("f6dcb4"), Color("e39a62"))
		var c2 := cat(group(Vector3(-2.4, 0.3, 4.6), null, 0.6, 0.7), Color("f2efee"), Color(0, 0, 0, 0), true)
		camera(Vector3(2.5, 9.0, 13.5), Vector3(-0.2, 0.9, 1.2), 30, 13.0)
		var ui := hud("Lantern Bay", "Harbour Road  ·  light breeze", "17:40")
		var hint := panel(ui, Rect2(150, 820, 240, 56))
		label(hint, "Pet the cat?", 22).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	elif shot == "island":
		var rider := group(Vector3(2.0, 0.32, 1.6), null, 1.4, 1.0)
		moped(rider)
		var b := bear(rider, true); b.position = Vector3(0, 0.85, -0.35)
		camera(Vector3(16, 26, 30), Vector3(0, 0, 0.5), 34, 36.0)
		hud("Lantern Bay", "Day 12  ·  Spring", "17:40")
	elif shot == "friends":
		var b := bear(group(Vector3(-0.9, 0.32, 2.2), null, 0.35, 1.3))
		cat(group(Vector3(0.6, 0.32, 2.6), null, -0.6, 1.0), Color("f6dcb4"), Color("e39a62"))
		cat(group(Vector3(1.7, 0.32, 2.0), null, -0.9, 0.9), Color("4a4560"), Color("2f2b40"))
		camera(Vector3(0.6, 2.9, 8.2), Vector3(0.2, 1.0, 2.2), 32, 6.3)
		hud("Lantern Bay", "Sunset at the fence", "18:05")
	if not args.has("out"):
		return # just watch it
	for i in 12:
		await RenderingServer.frame_post_draw
	var out: String = args.get("out", "shots/%s.png" % shot)
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
