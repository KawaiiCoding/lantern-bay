extends RefCounted
## 3D bits for fishing: rod, bobber, line ribbon, ripples, splashes, soft fish shadow.
## Everything uses Toys materials so it shares the soft toy + ink outline look.

const INK := Color("6b4a3a")
const LINE := Color("4a3a40")
const FOAM := Color("f4fbff")

static var _shadow_tex: GradientTexture2D
const SHADOW_TINT := Color(0.08, 0.13, 0.22)

# ---------------------------------------------------------------- rod
## Two-segment rod (butt + tip) so it can bend. Returns {root, butt, tip, butt_len, tip_len}.
static func rod(parent: Node3D) -> Dictionary:
	var root := Node3D.new(); root.name = "Rod"; root.top_level = true
	parent.add_child(root)
	var butt := Node3D.new(); root.add_child(butt)
	var tip := Node3D.new(); root.add_child(tip)
	var bl := 1.15; var tl := 0.9
	var wood := Toys.mat(Color("7a5240"), 0.6, 0.012)
	var cork := Toys.mat(Color("e8c9a0"), 0.9, 0.01)
	var tipm := Toys.mat(Color("e8746a"), 0.6, 0.01)
	var rot := Vector3(-PI / 2, 0, 0)    # cylinder Y axis -> -Z (look direction)
	Toys.add(Toys.cyl(0.032, 0.042, bl, 10), wood, Vector3(0, 0, -bl / 2), butt, Vector3.ONE, rot)
	Toys.add(Toys.cyl(0.055, 0.055, 0.32, 12), cork, Vector3(0, 0, -0.2), butt, Vector3.ONE, rot)
	Toys.add(Toys.cyl(0.05, 0.05, 0.05, 14), Toys.mat(Color("e4e1ea"), 0.3, 0.01), Vector3(0, -0.05, -0.38), butt, Vector3.ONE, Vector3(0, 0, PI / 2))
	Toys.add(Toys.cyl(0.016, 0.03, tl, 8), tipm, Vector3(0, 0, -tl / 2), tip, Vector3.ONE, rot)
	Toys.add(Toys.sphere(0.022), Toys.mat(Color("e8746a"), 0.6, 0.0), Vector3(0, 0, -tl), tip)
	return {"root": root, "butt": butt, "tip": tip, "butt_len": bl, "tip_len": tl}

## Point a segment node (built along -Z) from a to b.
static func place(n: Node3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	if d.length() < 0.0001: return
	d = d.normalized()
	var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.97 else Vector3.FORWARD
	n.global_transform = Transform3D(Basis.looking_at(d, up), a)

# ---------------------------------------------------------------- bobber
static func bobber(parent: Node3D) -> Node3D:
	var g := Node3D.new(); g.name = "Bobber"; g.top_level = true
	parent.add_child(g)
	var red := Toys.mat(Color("e8746a"), 0.5, 0.012)
	var white := Toys.mat(Color("fffaf2"), 0.5, 0.012)
	Toys.add(Toys.sphere(0.1), white, Vector3(0, 0.0, 0), g, Vector3(1, 0.9, 1))
	Toys.add(Toys.sphere(0.1), red, Vector3(0, 0.05, 0), g, Vector3(0.98, 0.75, 0.98))
	Toys.add(Toys.cyl(0.012, 0.012, 0.12, 6), Toys.mat(Color("fff1b8"), 0.5, 0.006), Vector3(0, 0.16, 0), g)
	return g

# ---------------------------------------------------------------- line
static func line_mesh(parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.name = "Line"; mi.top_level = true
	mi.mesh = ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = LINE
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 50.0
	parent.add_child(mi)
	mi.global_transform = Transform3D.IDENTITY
	return mi

## Camera-facing ribbon from a to b sagging by `sag` metres (0 = taut).
static func draw_line(mi: MeshInstance3D, a: Vector3, b: Vector3, sag: float, cam_pos: Vector3, width := 0.02) -> void:
	var im := mi.mesh as ImmediateMesh
	if im == null: return
	im.clear_surfaces()
	if a.distance_to(b) < 0.01: return
	var pts := PackedVector3Array()
	var n := 18
	for i in n + 1:
		var t := float(i) / n
		pts.append(a.lerp(b, t) - Vector3.UP * sag * 4.0 * t * (1.0 - t))
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in pts.size():
		var p := pts[i]
		var tan := (pts[mini(i + 1, n)] - pts[maxi(i - 1, 0)]).normalized()
		var view := (cam_pos - p).normalized()
		var side := tan.cross(view)
		if side.length() < 0.001: side = Vector3.RIGHT
		side = side.normalized() * width * 0.5
		im.surface_add_vertex(p - side)
		im.surface_add_vertex(p + side)
	im.surface_end()

# ---------------------------------------------------------------- water fx
static func _fx_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 9
	return m

static func ripple(parent: Node3D, pos: Vector3, r0 := 0.15, r1 := 0.9, dur := 0.8, alpha := 0.85) -> void:
	if not is_instance_valid(parent) or not parent.is_inside_tree(): return
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new(); t.inner_radius = 0.86; t.outer_radius = 1.0; t.rings = 40; t.ring_segments = 6
	mi.mesh = t
	var m := _fx_mat(Color(FOAM, alpha))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.02, 0)
	mi.scale = Vector3(r0, 0.25, r0)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(r1, 0.12, r1), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)

## Droplets + a little foam column. power ~0.5 (nibble) .. 1.5 (big catch).
static func splash(parent: Node3D, pos: Vector3, count := 10, power := 1.0) -> void:
	if not is_instance_valid(parent) or not parent.is_inside_tree(): return
	var root := Node3D.new(); root.top_level = true
	parent.add_child(root)
	root.global_position = pos
	var drop_mat := Toys.mat(FOAM, 0.3, 0.008)
	var life := 0.45 + 0.25 * power
	for i in count:
		var d := MeshInstance3D.new()
		d.mesh = Toys.sphere(randf_range(0.035, 0.07) * (0.7 + 0.4 * power))
		d.material_override = drop_mat
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(d)
		var a := randf() * TAU
		var v := Vector3(cos(a) * randf_range(0.6, 1.6), randf_range(2.2, 3.6) * (0.6 + 0.5 * power), sin(a) * randf_range(0.6, 1.6)) * (0.6 + 0.4 * power)
		var tw := d.create_tween()
		tw.tween_method(func(t: float) -> void:
			d.position = v * t + Vector3(0, -9.0, 0) * t * t * 0.5
			d.scale = Vector3.ONE * clampf(1.0 - t / life, 0.05, 1.0), 0.0, life, life)
	var col := MeshInstance3D.new()
	col.mesh = Toys.capsule(0.12, 0.5)
	var cm := _fx_mat(Color(FOAM, 0.9))
	col.material_override = cm
	root.add_child(col)
	col.scale = Vector3(0.6, 0.1, 0.6) * power
	var ct := col.create_tween()
	ct.tween_property(col, "scale", Vector3(1.0, 1.0 + 0.4 * power, 1.0) * power, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ct.parallel().tween_property(col, "position:y", 0.25 * power, 0.12)
	ct.tween_property(col, "scale", Vector3(1.3, 0.05, 1.3) * power, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	ct.parallel().tween_property(col, "position:y", 0.0, 0.25)
	ct.parallel().tween_property(cm, "albedo_color:a", 0.0, 0.25)
	root.get_tree().create_timer(life + 0.1).timeout.connect(root.queue_free)
	ripple(parent, pos, 0.2, 0.9 + 0.5 * power, 0.9, 0.9)

# ---------------------------------------------------------------- fish shadow
static func shadow(parent: Node3D) -> MeshInstance3D:
	if _shadow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1)); g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.5, Color(1, 1, 1, 0.92))
		_shadow_tex = GradientTexture2D.new()
		_shadow_tex.gradient = g
		_shadow_tex.fill = GradientTexture2D.FILL_RADIAL
		_shadow_tex.fill_from = Vector2(0.5, 0.5); _shadow_tex.fill_to = Vector2(1.0, 0.5)
		_shadow_tex.width = 64; _shadow_tex.height = 64
	var mi := MeshInstance3D.new(); mi.name = "FishShadow"; mi.top_level = true
	var pm := PlaneMesh.new(); pm.size = Vector2(1, 1)
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = _shadow_tex
	m.albedo_color = Color(SHADOW_TINT, 0.0)
	m.render_priority = 8           # draw over (possibly transparent) water
	m.set_meta("nobake", true)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func set_shadow(mi: MeshInstance3D, pos: Vector3, heading: Vector3, length: float, alpha: float) -> void:
	if not is_instance_valid(mi): return
	var h := Vector3(heading.x, 0, heading.z)
	if h.length() < 0.001: h = Vector3.FORWARD
	h = h.normalized()
	# plane: x across, z along; head points along -z (heading), the tapered tail trails at +z
	var b := Basis.looking_at(h, Vector3.UP) * Basis.from_scale(Vector3(length * 0.5, 1.0, length))
	mi.global_transform = Transform3D(b, pos)
	var m := mi.material_override as StandardMaterial3D
	if m: m.albedo_color = Color(SHADOW_TINT, alpha)
