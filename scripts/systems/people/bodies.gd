extends RefCounted
## Townsfolk body builders (soft toy style via Toys primitives). All static.
## build(parent, p) returns a Node3D root facing +Z, with metas for animation:
##   "torso" (Node3D, breathes), "head" (Node3D, looks), "arm_l" / "arm_r" (shoulder pivots, wave),
##   "legs" (Array of MeshInstance3D), "height" (float, top of head in local units).

const DARK := Color("3b2a24")

static func _c(v, fallback: String) -> Color:
	var s := str(v) if v != null else ""
	if s == "" or not Color.html_is_valid(s): s = fallback
	return Color(s)

static func _cone(r: float, h: float, seg := 16) -> CylinderMesh:
	var c := CylinderMesh.new(); c.top_radius = 0.0; c.bottom_radius = r; c.height = h; c.radial_segments = seg; c.rings = 2
	return c

static func build(parent: Node3D, p: Dictionary) -> Node3D:
	var species := str(p.get("species", "bear")).to_lower()
	var main := _c(p.get("main"), "d9a877")
	var accent := _c(p.get("accent"), "6fc2b6")
	var extra := _c(p.get("extra"), "f3dcc0")
	var root := Node3D.new(); root.name = "Body"
	parent.add_child(root)
	var s := float(p.get("scale", 1.0))
	root.scale = Vector3.ONE * clampf(s, 0.6, 1.4)
	# everything hangs off a rig that is lifted so the lowest foot point sits exactly at y = 0
	var rig := Toys.group(Vector3.ZERO, root)
	rig.name = "Rig"
	var feet: Array = []   # [mesh, half_height] for the ground calculation
	var fur := Toys.mat(main)
	var light := Toys.mat(extra if species != "sheep" else main.darkened(0.03), 0.85, 0.0)
	if species == "fox" or species == "frog" or species == "walrus": light = Toys.mat(extra, 0.85, 0.0)
	var body_scale := Vector3(1, 1.05, 0.9)
	if species == "walrus": body_scale = Vector3(1.22, 1.08, 1.05)
	if species == "frog": body_scale = Vector3(1.05, 0.95, 0.92)
	if species == "heron": body_scale = Vector3(0.88, 1.12, 0.86)
	if species == "raccoon" and p.get("extra") == null: extra = Color("eceae6")
	if species == "fox" and p.get("extra") == null: extra = Color("fff3e2")
	if species == "frog" and p.get("extra") == null: extra = Color("f4f0c8")
	if species == "walrus" and p.get("extra") == null: extra = Color("f6f1e6")
	if species == "heron" and p.get("extra") == null: extra = Color("fbf8f2")
	if species == "sheep" and p.get("extra") == null: extra = Color("b89a88")

	# legs (stay put while the torso breathes)
	var legs: Array = []
	for sd in [-1, 1]:
		var leg_c := main.darkened(0.08) if species != "sheep" else extra
		var leg: MeshInstance3D
		if species == "heron":
			leg = Toys.add(Toys.capsule(0.05, 0.5), Toys.mat(Color("e8b45a")), Vector3(0.13 * sd, 0.25, 0.04), rig)
			var toe := Toys.add(Toys.sphere(0.09), Toys.mat(Color("e8b45a")), Vector3(0.0, -0.21, 0.06), leg, Vector3(1.1, 0.4, 1.6))
			feet.append([leg, 0.25]); feet.append([toe, 0.0])
		else:
			leg = Toys.add(Toys.capsule(0.13, 0.36), Toys.mat(leg_c), Vector3(0.2 * sd, 0.18, 0.04), rig)
			feet.append([leg, 0.18])
		legs.append(leg)
		if species == "frog":
			var foot := Toys.add(Toys.sphere(0.13), Toys.mat(main.darkened(0.08)), Vector3(0.03 * sd, -0.12, 0.1), leg, Vector3(1.2, 0.45, 1.5))
			feet.append([foot, 0.0])
	# torso
	var torso := Toys.group(Vector3.ZERO, rig)
	torso.name = "Torso"
	if species == "heron": torso.position.y = 0.1
	if species == "sheep":
		# a cloud of wool puffs
		Toys.add(Toys.sphere(0.5), fur, Vector3(0, 0.6, 0), torso, Vector3(1.05, 1.0, 0.95))
		for i in 8:
			var a := TAU * float(i) / 8.0
			Toys.add(Toys.sphere(0.2), fur, Vector3(cos(a) * 0.43, 0.62 + sin(a * 2.0) * 0.1, sin(a) * 0.36), torso)
	else:
		Toys.add(Toys.sphere(0.5), fur, Vector3(0, 0.58, 0), torso, body_scale)
		Toys.add(Toys.sphere(0.3), light, Vector3(0, 0.52, 0.3 * body_scale.z), torso, Vector3(1.05, 1.1, 0.5))
	# arms on shoulder pivots
	var arms := []
	for sd in [-1, 1]:
		var pv := Toys.group(Vector3(0.36 * sd * body_scale.x, 0.86, 0.12), torso)
		var arm_c := main if species != "sheep" else extra
		Toys.add(Toys.capsule(0.11, 0.46), Toys.mat(arm_c), Vector3(0.06 * sd, -0.16, 0.1), pv, Vector3.ONE, Vector3(-0.75, 0, 0.35 * sd))
		arms.append(pv)
	# head
	var head_y := 1.28 if species != "walrus" else 1.3
	if species == "heron": head_y = 1.5
	var head := Toys.group(Vector3(0, head_y, 0.05), torso)
	head.name = "Head"
	match species:
		"fox": _fox_head(head, main, extra)
		"sheep": _sheep_head(head, main, extra)
		"frog": _frog_head(head, main, extra)
		"walrus": _walrus_head(head, main, extra)
		"cat": _cat_head(head, main, extra)
		"raccoon": _raccoon_head(head, main, extra)
		"heron": _heron_head(head, main, extra, torso)
		_: _bear_head(head, main, extra)
	# tail
	match species:
		"fox":
			var tail := Toys.group(Vector3(0, 0.38, -0.42), torso, 0.0)
			Toys.add(Toys.sphere(0.24), fur, Vector3(0.0, 0.12, -0.12), tail, Vector3(0.9, 0.9, 1.5), Vector3(-0.7, 0, 0))
			Toys.add(Toys.sphere(0.15), Toys.mat(extra), Vector3(0.0, 0.32, -0.32), tail, Vector3(0.9, 0.9, 1.1))
			root.set_meta("tail", tail)
		"sheep":
			Toys.add(Toys.sphere(0.13), fur, Vector3(0, 0.5, -0.5), torso)
		"cat":
			Toys.add(Toys.torus(0.2, 0.28), fur, Vector3(0, 0.35, -0.48), torso, Vector3(1, 1, 0.6), Vector3(0, PI / 2, 0.3))
		"bear":
			Toys.add(Toys.sphere(0.11), fur, Vector3(0, 0.35, -0.45), torso)
		"raccoon":
			var rt := Toys.group(Vector3(0, 0.34, -0.4), torso)
			rt.rotation.x = 0.45
			var ring := Toys.mat(Color("3b3540"))
			for k in 4:
				Toys.add(Toys.sphere(0.15 - k * 0.012), fur if k % 2 == 0 else ring, Vector3(0, 0, -0.1 - k * 0.13), rt, Vector3(1, 1, 0.9))
			Toys.add(Toys.sphere(0.1), ring, Vector3(0, 0, -0.62), rt)
			root.set_meta("tail", rt)
		"heron":
			for k in 3:
				Toys.add(Toys.sphere(0.12), Toys.mat(main.darkened(0.15)), Vector3(-0.08 + k * 0.08, 0.42, -0.46), torso, Vector3(0.5, 0.4, 1.4), Vector3(0.5, 0, 0))
	# outfit
	_outfit(str(p.get("outfit", "")), torso, head, accent, species, body_scale)
	# ground contact: lowest point of the feet (spheres: radius * scale.y, capsules: half height)
	var min_y := INF
	for f in feet:
		var mi: MeshInstance3D = f[0]
		var bottom := 0.0
		if mi.mesh is SphereMesh: bottom = (mi.mesh as SphereMesh).radius * mi.scale.y
		elif mi.mesh is CapsuleMesh: bottom = (mi.mesh as CapsuleMesh).height * 0.5 * mi.scale.y
		var y := mi.position.y - bottom
		var par := mi.get_parent()
		if par != rig and par is Node3D: y = (par as Node3D).position.y + mi.position.y * (par as Node3D).scale.y - bottom
		min_y = minf(min_y, y)
	if min_y != INF: rig.position.y = -min_y
	for l in legs: l.set_meta("y0", l.position.y); l.set_meta("z0", l.position.z)
	root.set_meta("rig", rig)
	root.set_meta("torso", torso)
	root.set_meta("head", head)
	root.set_meta("arm_l", arms[0])
	root.set_meta("arm_r", arms[1])
	root.set_meta("legs", legs)
	root.set_meta("height", head_y + 0.75 + rig.position.y)
	return root

# ---------------------------------------------------------------- faces
static func _eyes(h: Node3D, x: float, y: float, z: float, r := 0.05) -> void:
	var dark := Toys.mat(DARK, 0.2, 0.0)
	var shine := Toys.mat(Color(1, 1, 1), 0.2, 0.0)
	shine.emission_enabled = true; shine.emission = Color(1, 1, 1); shine.emission_energy_multiplier = 0.6
	for sd in [-1, 1]:
		Toys.add(Toys.sphere(r), dark, Vector3(x * sd, y, z), h, Vector3(1, 1.15, 0.7))
		Toys.add(Toys.sphere(r * 0.32), shine, Vector3(x * sd + r * 0.3, y + r * 0.4, z + r * 0.55), h)

static func _blush(h: Node3D, x: float, y: float, z: float) -> void:
	var blush := Toys.mat(Color("f2a0a6"), 0.9, 0.0)
	for sd in [-1, 1]:
		Toys.add(Toys.sphere(0.07), blush, Vector3(x * sd, y, z), h, Vector3(1, 0.6, 0.4))

static func _bear_head(h: Node3D, main: Color, extra: Color) -> void:
	var fur := Toys.mat(main); var light := Toys.mat(extra)
	Toys.add(Toys.sphere(0.46), fur, Vector3.ZERO, h, Vector3(1.08, 0.95, 0.95))
	for sd in [-1, 1]:
		Toys.add(Toys.sphere(0.15), fur, Vector3(0.32 * sd, 0.36, -0.02), h)
		Toys.add(Toys.sphere(0.08), Toys.mat(extra, 0.85, 0.0), Vector3(0.32 * sd, 0.36, 0.08), h, Vector3(1, 1, 0.5))
	_eyes(h, 0.16, 0.06, 0.41)
	_blush(h, 0.28, -0.07, 0.34)
	Toys.add(Toys.sphere(0.17), light, Vector3(0, -0.1, 0.37), h, Vector3(1.2, 0.85, 0.7))
	Toys.add(Toys.sphere(0.055), Toys.mat(DARK, 0.2, 0.0), Vector3(0, -0.04, 0.5), h)

static func _cat_head(h: Node3D, main: Color, extra: Color) -> void:
	var fur := Toys.mat(main)
	Toys.add(Toys.sphere(0.44), fur, Vector3.ZERO, h, Vector3(1.12, 0.95, 0.95))
	for sd in [-1, 1]:
		Toys.add(_cone(0.15, 0.3, 12), fur, Vector3(0.24 * sd, 0.4, 0), h, Vector3.ONE, Vector3(0, 0, -0.3 * sd))
	_eyes(h, 0.15, 0.04, 0.4)
	_blush(h, 0.27, -0.08, 0.34)
	Toys.add(Toys.sphere(0.13), Toys.mat(extra), Vector3(0, -0.12, 0.36), h, Vector3(1.3, 0.8, 0.6))
	Toys.add(Toys.sphere(0.04), Toys.mat(Color("f3a7b0"), 0.9, 0.0), Vector3(0, -0.06, 0.45), h)

static func _fox_head(h: Node3D, main: Color, extra: Color) -> void:
	var fur := Toys.mat(main); var light := Toys.mat(extra); var dark := Toys.mat(DARK, 0.3, 0.0)
	Toys.add(Toys.sphere(0.44), fur, Vector3.ZERO, h, Vector3(1.12, 0.92, 0.95))
	# cream cheeks
	for sd in [-1, 1]:
		Toys.add(Toys.sphere(0.2), Toys.mat(extra, 0.85, 0.0), Vector3(0.2 * sd, -0.13, 0.25), h, Vector3(1.1, 0.8, 0.8))
	# big pointed ears with dark tips
	for sd in [-1, 1]:
		var ear := Toys.group(Vector3(0.24 * sd, 0.38, -0.02), h, 0.0)
		ear.rotation = Vector3(0, 0, -0.32 * sd)
		Toys.add(_cone(0.17, 0.42, 12), fur, Vector3(0, 0.12, 0), ear, Vector3(1, 1, 0.6))
		Toys.add(_cone(0.07, 0.15, 10), dark, Vector3(0, 0.27, 0), ear, Vector3(1, 1, 0.6))
		Toys.add(_cone(0.09, 0.22, 10), Toys.mat(Color("f6c9b8"), 0.9, 0.0), Vector3(0, 0.06, 0.05), ear, Vector3(1, 1, 0.3))
	# snout: a soft pointed muzzle
	Toys.add(Toys.sphere(0.16), light, Vector3(0, -0.12, 0.38), h, Vector3(1.0, 0.75, 1.15))
	Toys.add(Toys.sphere(0.055), dark, Vector3(0, -0.08, 0.56), h)
	_eyes(h, 0.16, 0.06, 0.39)
	_blush(h, 0.3, -0.06, 0.3)

static func _sheep_head(h: Node3D, main: Color, extra: Color) -> void:
	var wool := Toys.mat(main); var face := Toys.mat(extra)
	Toys.add(Toys.sphere(0.36), face, Vector3(0, -0.04, 0.08), h, Vector3(1.0, 1.05, 0.95))
	# wool cap of puffs
	for i in 7:
		var a := PI * (float(i) / 6.0)
		Toys.add(Toys.sphere(0.16), wool, Vector3(cos(a) * 0.3, 0.26 + sin(a) * 0.12, -0.02), h)
	Toys.add(Toys.sphere(0.2), wool, Vector3(0, 0.36, 0.02), h)
	Toys.add(Toys.sphere(0.32), wool, Vector3(0, 0.08, -0.16), h, Vector3(1.2, 1.1, 1.0))
	# floppy ears
	for sd in [-1, 1]:
		Toys.add(Toys.capsule(0.08, 0.32), face, Vector3(0.38 * sd, 0.05, 0.02), h, Vector3(1, 1, 0.6), Vector3(0, 0, 1.25 * sd))
	# light muzzle
	Toys.add(Toys.sphere(0.15), Toys.mat(extra.lightened(0.35), 0.85, 0.0), Vector3(0, -0.16, 0.34), h, Vector3(1.25, 0.8, 0.7))
	Toys.add(Toys.sphere(0.04), Toys.mat(DARK, 0.2, 0.0), Vector3(0, -0.1, 0.44), h, Vector3(1.4, 0.8, 1))
	_eyes(h, 0.13, 0.04, 0.38, 0.048)
	_blush(h, 0.23, -0.09, 0.33)

static func _frog_head(h: Node3D, main: Color, extra: Color) -> void:
	var skin := Toys.mat(main); var belly := Toys.mat(extra, 0.85, 0.0)
	Toys.add(Toys.sphere(0.44), skin, Vector3(0, -0.04, 0), h, Vector3(1.28, 0.82, 1.0))
	# eyes on top, white bulbs with dark pupils
	var white := Toys.mat(Color("fffaf2"))
	for sd in [-1, 1]:
		Toys.add(Toys.sphere(0.17), skin, Vector3(0.22 * sd, 0.26, 0.08), h)
		Toys.add(Toys.sphere(0.12), white, Vector3(0.22 * sd, 0.29, 0.17), h, Vector3(1, 1, 0.8))
	_eyes(h, 0.22, 0.29, 0.27, 0.06)
	# wide smile
	var smile := Toys.add(Toys.torus(0.2, 0.225), Toys.mat(DARK, 0.4, 0.0), Vector3(0, -0.02, 0.32), h, Vector3(1.15, 1, 0.35), Vector3(PI / 2, 0, 0))
	smile.scale = Vector3(1.15, 0.6, 0.3)
	Toys.add(Toys.sphere(0.24), belly, Vector3(0, -0.2, 0.2), h, Vector3(1.3, 0.6, 0.9))
	_blush(h, 0.36, -0.06, 0.28)

static func _raccoon_head(h: Node3D, main: Color, extra: Color) -> void:
	var fur := Toys.mat(main); var light := Toys.mat(extra); var mask := Toys.mat(Color("3b3540"), 0.8, 0.0)
	Toys.add(Toys.sphere(0.45), fur, Vector3.ZERO, h, Vector3(1.12, 0.92, 0.95))
	for sd in [-1, 1]:
		var ear := Toys.group(Vector3(0.27 * sd, 0.34, -0.04), h)
		ear.rotation.z = -0.35 * sd
		Toys.add(_cone(0.15, 0.26, 12), fur, Vector3.ZERO, ear, Vector3(1, 1, 0.55))
		Toys.add(_cone(0.08, 0.14, 10), Toys.mat(extra, 0.85, 0.0), Vector3(0, -0.02, 0.05), ear, Vector3(1, 1, 0.3))
		# white brows and cheeks frame the mask
		Toys.add(Toys.sphere(0.12), Toys.mat(extra, 0.85, 0.0), Vector3(0.17 * sd, 0.2, 0.33), h, Vector3(1.2, 0.5, 0.6))
		Toys.add(Toys.sphere(0.15), Toys.mat(extra, 0.85, 0.0), Vector3(0.27 * sd, -0.13, 0.27), h, Vector3(1.0, 0.8, 0.8))
		# the bandit mask: a soft dark patch around each eye
		Toys.add(Toys.sphere(0.13), mask, Vector3(0.16 * sd, 0.04, 0.34), h, Vector3(1.35, 0.8, 0.55), Vector3(0, 0, 0.25 * sd))
	Toys.add(Toys.sphere(0.15), light, Vector3(0, -0.14, 0.36), h, Vector3(1.1, 0.75, 0.9))
	Toys.add(Toys.sphere(0.055), Toys.mat(DARK, 0.2, 0.0), Vector3(0, -0.08, 0.5), h)
	var shine := Toys.mat(Color(1, 1, 1), 0.2, 0.0)
	for sd in [-1, 1]:
		Toys.add(Toys.sphere(0.052), Toys.mat(Color("1e1a20"), 0.2, 0.0), Vector3(0.16 * sd, 0.05, 0.42), h, Vector3(1, 1.15, 0.7))
		Toys.add(Toys.sphere(0.018), shine, Vector3(0.16 * sd + 0.016, 0.07, 0.45), h)
	_blush(h, 0.3, -0.12, 0.3)

static func _heron_head(h: Node3D, main: Color, extra: Color, torso: Node3D) -> void:
	var feather := Toys.mat(extra); var grey := Toys.mat(main)
	# long neck from the body up to the head
	Toys.add(Toys.capsule(0.13, 0.62), feather, Vector3(0, 1.17, 0.06), torso, Vector3.ONE, Vector3(0.12, 0, 0))
	Toys.add(Toys.sphere(0.34), feather, Vector3.ZERO, h, Vector3(1.0, 0.95, 1.0))
	Toys.add(Toys.sphere(0.3), grey, Vector3(0, 0.08, -0.06), h, Vector3(1.04, 0.85, 1.0))
	# crest plume
	for k in 2:
		Toys.add(Toys.capsule(0.03, 0.34), Toys.mat(Color("3b4250")), Vector3(0, 0.12 + k * 0.05, -0.3 - k * 0.04), h, Vector3.ONE, Vector3(-1.1 - k * 0.25, 0, 0))
	# long beak
	var beak := Toys.mat(Color("eab458"), 0.5)
	Toys.add(_cone(0.07, 0.46, 12), beak, Vector3(0, -0.06, 0.46), h, Vector3(1, 1, 0.8), Vector3(PI / 2, 0, 0))
	_eyes(h, 0.15, 0.05, 0.27, 0.045)
	_blush(h, 0.22, -0.08, 0.22)

static func _walrus_head(h: Node3D, main: Color, extra: Color) -> void:
	var skin := Toys.mat(main); var light := Toys.mat(main.lightened(0.25))
	Toys.add(Toys.sphere(0.46), skin, Vector3.ZERO, h, Vector3(1.1, 0.92, 0.98))
	# big whisker pads
	for sd in [-1, 1]:
		Toys.add(Toys.sphere(0.17), light, Vector3(0.13 * sd, -0.15, 0.36), h, Vector3(1.0, 0.85, 0.8))
		for k in 3:
			Toys.add(Toys.sphere(0.018), Toys.mat(DARK, 0.4, 0.0), Vector3(0.1 * sd + 0.06 * sd * (k - 1), -0.12 - 0.035 * (k % 2), 0.5), h)
	# tusks
	var tusk := Toys.mat(extra, 0.5, 0.02)
	for sd in [-1, 1]:
		Toys.add(_cone(0.045, 0.3, 10), tusk, Vector3(0.1 * sd, -0.36, 0.42), h, Vector3.ONE, Vector3(PI, 0, 0.12 * sd))
	Toys.add(Toys.sphere(0.07), Toys.mat(DARK, 0.3, 0.0), Vector3(0, -0.02, 0.47), h, Vector3(1.3, 0.8, 0.8))
	# bushy grey brows
	for sd in [-1, 1]:
		Toys.add(Toys.capsule(0.04, 0.18), Toys.mat(Color("eae4dc")), Vector3(0.17 * sd, 0.17, 0.38), h, Vector3.ONE, Vector3(0, 0, PI / 2 - 0.25 * sd))
	_eyes(h, 0.16, 0.07, 0.41, 0.045)
	_blush(h, 0.3, -0.05, 0.32)

# ---------------------------------------------------------------- outfits
static func _outfit(kind: String, torso: Node3D, head: Node3D, accent: Color, species: String, bs: Vector3) -> void:
	var m := Toys.mat(accent)
	var front_z := 0.45 * bs.z
	match kind:
		"apron":
			# shop apron: a smooth shell over the lower body with a cream waist tie
			var ac := accent.lightened(0.18) if accent.get_luminance() < 0.3 else accent
			var cloth := Toys.mat(ac)
			var trim := Toys.mat(Color("fff6ea"))
			Toys.add(Toys.sphere(0.5), cloth, Vector3(0, 0.47, 0.0), torso, Vector3(1.04, 0.8, 1.07) * bs)
			Toys.add(Toys.torus(0.46, 0.53), trim, Vector3(0, 0.56, 0), torso, Vector3(bs.x, 0.7, bs.z))
		"scarf":
			Toys.add(Toys.torus(0.24, 0.42), m, Vector3(0, 0.98, 0.02), torso)
			Toys.add(Toys.capsule(0.09, 0.42), m, Vector3(-0.17, 0.76, 0.36), torso, Vector3.ONE, Vector3(0.2, 0, -0.25))
			Toys.add(Toys.capsule(0.08, 0.3), Toys.mat(accent.lightened(0.2)), Vector3(0.05, 0.8, 0.4), torso, Vector3.ONE, Vector3(0.25, 0, 0.15))
		"beret":
			var b := Toys.group(Vector3(0.05, 0.36 if species != "frog" else 0.28, -0.04), head)
			b.rotation = Vector3(-0.12, 0, -0.28)
			Toys.add(Toys.cyl(0.3, 0.27, 0.08), m, Vector3.ZERO, b)
			Toys.add(Toys.sphere(0.36), m, Vector3(0.04, 0.08, -0.02), b, Vector3(1.05, 0.42, 1.05))
			Toys.add(Toys.cyl(0.02, 0.03, 0.08), m, Vector3(0, 0.15, 0), b)
			# a little satchel strap
			Toys.add(Toys.torus(0.44, 0.52), Toys.mat(Color("8a5e44")), Vector3(0, 0.62, 0), torso, Vector3(1.02, 1, 0.94) * Vector3(bs.x, 1, bs.z), Vector3(0, 0, 0.7))
			var bag := Toys.add(Toys.sphere(0.2), Toys.mat(Color("c98a5a")), Vector3(0.46, 0.3, 0.12), torso, Vector3(0.7, 1.0, 1.1))
			bag.rotation.y = 0.3
			Toys.add(Toys.sphere(0.12), Toys.mat(Color("b07448")), Vector3(0.5, 0.38, 0.12), torso, Vector3(0.8, 0.5, 1.15))
		"cap":
			var c := Toys.group(Vector3(0, 0.3, 0.0), head)
			c.rotation.x = -0.12
			Toys.add(Toys.sphere(0.42), m, Vector3.ZERO, c, Vector3(1.08, 0.55, 1.02))
			Toys.add(Toys.cyl(0.25, 0.25, 0.04), m, Vector3(0, -0.03, 0.4), c, Vector3(1.0, 1, 0.75))
			Toys.add(Toys.sphere(0.05), Toys.mat(Color("fff6ea")), Vector3(0, 0.23, 0), c)
			# fisher vest
			Toys.add(Toys.sphere(0.5), Toys.mat(Color("e9d9a8")), Vector3(0, 0.6, -0.02), torso, Vector3(1.04, 0.85, 0.92) * bs)
		"smock":
			# painter's smock: a loose coat with dabs of paint, and a pencil tucked in the collar
			Toys.add(Toys.sphere(0.5), m, Vector3(0, 0.55, 0.0), torso, Vector3(1.06, 0.93, 1.08) * bs)
			var dabs := [[Color("e2607a"), Vector3(-0.2, 0.48, 0.0)], [Color("6fc2b6"), Vector3(0.16, 0.36, 0.0)], [Color("f2c14e"), Vector3(0.06, 0.62, 0.0)]]
			for dab in dabs:
				var dp: Vector3 = dab[1]
				dp.z = sqrt(maxf(0.0, 0.25 - dp.x * dp.x - pow((dp.y - 0.55) / 0.93, 2.0))) * 1.08 * bs.z - 0.005
				Toys.add(Toys.sphere(0.05), Toys.mat(dab[0], 0.6, 0.0), dp, torso, Vector3(1.2, 0.9, 0.35))
			Toys.add(Toys.torus(0.22, 0.31), Toys.mat(accent.darkened(0.1)), Vector3(0, 1.0, 0.03), torso, Vector3(1, 1.6, 1))
		"sunhat":
			var sh := Toys.group(Vector3(0.0, 0.3, -0.02) if species != "frog" else Vector3(0.0, 0.42, -0.22), head)
			sh.rotation = Vector3(-0.15, 0, 0.12) if species != "frog" else Vector3(-0.42, 0, 0.1)
			Toys.add(Toys.cyl(0.58, 0.6, 0.04, 32), m, Vector3.ZERO, sh)
			Toys.add(Toys.sphere(0.3), m, Vector3(0, 0.06, 0), sh, Vector3(1, 0.62, 1))
			Toys.add(Toys.cyl(0.305, 0.31, 0.07), Toys.mat(Color("8fbf7a")), Vector3(0, 0.05, 0), sh)
			Toys.add(Toys.sphere(0.07), Toys.mat(Color("f2a0b8")), Vector3(0.26, 0.09, 0.12), sh)
		"beanie":
			var bn := Toys.group(Vector3(0, 0.26, -0.02), head)
			Toys.add(Toys.sphere(0.44), m, Vector3.ZERO, bn, Vector3(1.06, 0.62, 1.02))
			Toys.add(Toys.torus(0.38, 0.47), Toys.mat(accent.darkened(0.12)), Vector3(0, -0.02, 0), bn, Vector3(1.03, 1.4, 1.0))
			Toys.add(Toys.sphere(0.1), Toys.mat(accent.lightened(0.2)), Vector3(0, 0.3, 0), bn)
			# old fisher's vest with a pocket
			Toys.add(Toys.sphere(0.5), Toys.mat(Color("6f7f68")), Vector3(0, 0.6, 0.0), torso, Vector3(1.05, 0.9, 1.06) * bs)
		"keeper":
			var kc := Toys.group(Vector3(0, 0.24, -0.02), head)
			kc.rotation.x = -0.1
			Toys.add(Toys.cyl(0.27, 0.25, 0.15), m, Vector3(0, 0.05, 0), kc)
			Toys.add(Toys.cyl(0.2, 0.2, 0.03), Toys.mat(accent.darkened(0.3)), Vector3(0, -0.02, 0.2), kc, Vector3(1, 1, 0.7))
			Toys.add(Toys.sphere(0.045), Toys.glow(Color("f2c14e"), 0.5), Vector3(0, 0.06, 0.26), kc, Vector3(1, 1, 0.5))
			# long keeper's coat with brass buttons
			Toys.add(Toys.sphere(0.5), m, Vector3(0, 0.54, 0.0), torso, Vector3(1.06, 0.95, 1.08) * bs)
			Toys.add(Toys.torus(0.2, 0.3), m.duplicate(), Vector3(0, 1.0, 0.03), torso, Vector3(1, 1.6, 1))
			for i in 3:
				Toys.add(Toys.sphere(0.04), Toys.mat(Color("f2c14e"), 0.4, 0.0), Vector3(0, 0.74 - i * 0.16, 0.53 * bs.z), torso)
		"captain":
			var hat := Toys.group(Vector3(0, 0.34, -0.02), head)
			hat.rotation = Vector3(-0.1, 0, 0.08)
			Toys.add(Toys.cyl(0.34, 0.3, 0.22), Toys.mat(Color("fff6ea")), Vector3(0, 0.1, 0), hat, Vector3(1.05, 1, 1))
			Toys.add(Toys.cyl(0.31, 0.31, 0.1), m, Vector3(0, -0.02, 0), hat)
			Toys.add(Toys.cyl(0.24, 0.24, 0.035), Toys.mat(accent.darkened(0.3)), Vector3(0, -0.06, 0.25), hat, Vector3(1, 1, 0.7))
			Toys.add(Toys.sphere(0.06), Toys.glow(Color("f2c14e"), 0.6), Vector3(0, 0.03, 0.31), hat, Vector3(1, 1, 0.5))
			# navy coat with gold buttons
			Toys.add(Toys.sphere(0.5), m, Vector3(0, 0.56, -0.03), torso, Vector3(1.04, 0.9, 0.96) * bs)
			for i in 3:
				Toys.add(Toys.sphere(0.04), Toys.mat(Color("f2c14e"), 0.4, 0.0), Vector3(0, 0.75 - i * 0.17, 0.48 * bs.z), torso)
