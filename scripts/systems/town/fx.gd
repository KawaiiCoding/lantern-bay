extends RefCounted
## Shared little effects: a soft four-point sparkle texture, sparkle bursts and expanding light rings.

static var _tex: ImageTexture

static func star_texture() -> ImageTexture:
	if _tex != null: return _tex
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (x + 0.5) / n * 2.0 - 1.0
			var v := (y + 0.5) / n * 2.0 - 1.0
			var star := 1.0 - (pow(absf(u), 0.5) + pow(absf(v), 0.5))
			var a := clampf(star * 2.4, 0.0, 1.0)
			var glow := exp(-(u * u + v * v) * 14.0)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(maxf(a, glow * 0.9), 0.0, 1.0)))
	_tex = ImageTexture.create_from_image(img)
	return _tex

static func sparkle_mat(color: Color, additive := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = star_texture()
	m.albedo_color = color
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if additive: m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m

static func quad(size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	return q

## A one-shot burst of sparkles at `pos` (world space, `parent` must be at identity or share the frame).
static func burst(parent: Node, pos: Vector3, color: Color, amount := 14, speed := 2.6, life := 0.9, size := 0.24) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := quad(size)
	q.material = sparkle_mat(Color.WHITE)
	p.mesh = q
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -3.2, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.color = color
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = g
	p.position = pos
	parent.add_child(p)
	p.emitting = true
	# a child timer dies with the particles, so nothing can call into a freed node
	var t := Timer.new(); t.one_shot = true; t.wait_time = life + 0.4; t.autostart = true
	t.timeout.connect(p.queue_free)
	p.add_child(t)
	return p

## A thin light ring that grows and fades on the ground.
static func ring(parent: Node, pos: Vector3, color: Color, radius := 3.0, dur := 0.9) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = 0.46; t.outer_radius = 0.5
	t.rings = 32; t.ring_segments = 6
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(color.r, color.g, color.b, 0.9)
	var mi := MeshInstance3D.new()
	mi.mesh = t
	mi.material_override = m
	mi.position = pos + Vector3(0, 0.06, 0)
	mi.scale = Vector3.ONE * 0.3
	parent.add_child(mi)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, dur)
	tw.chain().tween_callback(mi.queue_free)
	return mi
