class_name Toys
extends RefCounted
## Soft toy art kit: every mesh is a smooth primitive with an ink outline (inverted hull).
## All functions are static. Use Toys.add(mesh, material, position, parent).

const INK := Color("6b4a3a")

static func mat(c: Color, rough := 0.85, outline := 0.025) -> StandardMaterial3D:
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

static func glow(c: Color, k := 2.5) -> StandardMaterial3D:
	var m := mat(c, 0.5, 0.0)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = k
	return m

static func sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new(); s.radius = r; s.height = r * 2.0; s.radial_segments = 32; s.rings = 16
	return s

static func capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new(); c.radius = r; c.height = h; c.radial_segments = 24; c.rings = 8
	return c

static func cyl(top: float, bot: float, h: float, seg := 24) -> CylinderMesh:
	var c := CylinderMesh.new(); c.top_radius = top; c.bottom_radius = bot; c.height = h; c.radial_segments = seg
	return c

static func box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new(); b.size = Vector3(x, y, z)
	return b

static func torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new(); t.inner_radius = inner; t.outer_radius = outer; t.rings = 24; t.ring_segments = 12
	return t

static func add(m: Mesh, mt: Material, pos: Vector3, parent: Node3D, scl := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = m; n.material_override = mt; n.position = pos; n.scale = scl; n.rotation = rot
	parent.add_child(n)
	return n

static func group(pos: Vector3, parent: Node3D, rot_y := 0.0, s := 1.0) -> Node3D:
	var g := Node3D.new(); g.position = pos; g.rotation.y = rot_y; g.scale = Vector3.ONE * s
	parent.add_child(g)
	return g

# ---------------------------------------------------------------- characters
static func bear(parent: Node3D, sitting := false) -> Node3D:
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

static func cat(parent: Node3D, main: Color, patch := Color(0, 0, 0, 0), sleepy := false) -> Node3D:
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

static func moped(parent: Node3D) -> Node3D:
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


# ---------------------------------------------------------------- props
static func house(parent: Node3D, pos: Vector3, rot_y: float, wall: Color, roof: Color, w := 3.2, h := 2.6) -> Node3D:
	var g := group(pos, parent, rot_y)
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
	return g

static func tree(parent: Node3D, pos: Vector3, s := 1.0, c := Color("8cc79a")) -> Node3D:
	var g := group(pos, parent, 0, s)
	add(cyl(0.12, 0.18, 1.0), mat(Color("9a7058")), Vector3(0, 0.5, 0), g)
	add(sphere(0.8), mat(c), Vector3(0, 1.5, 0), g)
	add(sphere(0.55), mat(c.lightened(0.1)), Vector3(0.45, 1.25, 0.25), g)
	add(sphere(0.5), mat(c.darkened(0.06)), Vector3(-0.4, 1.3, -0.2), g)
	return g

static func lamp(parent: Node3D, pos: Vector3) -> Node3D:
	var g := group(pos, parent)
	add(cyl(0.06, 0.08, 2.4), mat(Color("6e6390")), Vector3(0, 1.2, 0), g)
	add(sphere(0.2), glow(Color("fff0c0"), 2.5), Vector3(0, 2.5, 0), g)
	var l := OmniLight3D.new(); l.light_color = Color("ffd89a"); l.light_energy = 1.4; l.omni_range = 4.5
	l.position = Vector3(0, 2.4, 0); g.add_child(l)
	return g

static func fish(parent: Node3D, body: Color, fin: Color, length := 1.0) -> Node3D:
	var g := group(Vector3.ZERO, parent, 0, length)
	add(sphere(0.3), mat(body, 0.4), Vector3.ZERO, g, Vector3(0.6, 0.8, 1.4))
	var t := PrismMesh.new(); t.size = Vector3(0.05, 0.45, 0.35)
	add(t, mat(fin), Vector3(0, 0, -0.5), g, Vector3.ONE, Vector3(PI / 2, 0, 0))
	add(sphere(0.05), mat(Color("3b2a24"), 0.2, 0.0), Vector3(0.14, 0.06, 0.28), g)
	add(sphere(0.05), mat(Color("3b2a24"), 0.2, 0.0), Vector3(-0.14, 0.06, 0.28), g)
	return g
