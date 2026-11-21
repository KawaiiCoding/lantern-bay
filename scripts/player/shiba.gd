class_name Shiba
extends RefCounted
## Mocha the fluffy red-sesame shiba inu. Upright doll like Toys.bear (same proportions):
## feet at origin, faces +Z, head group at y 1.25, arms held forward, two stubby legs.
## Fluff is a few smooth, scaled forms tucked into the silhouette (no visible bubble clusters).
## Animated parts carry meta "part": "leg", "arm", "head", "tail", "scarf".

const FUR := Color("e8a25c")
const CREAM := Color("fff3e3")
const SESAME := Color("d48e4e")

static func build(parent: Node3D, sitting := false) -> Node3D:
	var g := Toys.group(Vector3.ZERO, parent)
	var fur := Toys.mat(FUR); var cream := Toys.mat(CREAM)
	var cream_in := Toys.mat(CREAM, 0.9, 0.0)       # inner cream marks: no outline, sit inside the fur
	var dark := Toys.mat(Color("2e211c"), 0.15, 0.0)
	var shine := Toys.glow(Color(1, 1, 1), 1.2)
	var blush := Toys.mat(Color("f4a3a8"), 0.9, 0.0)
	var scarf := Toys.mat(Color("6fc2b6"))

	# body: one smooth pear
	Toys.add(Toys.sphere(0.5), fur, Vector3(0, 0.55, 0), g, Vector3(1, 1.05, 0.9))
	# urajiro: a body-shaped cap nudged forward, so only a thin smooth oval shows (no ridge, no outline)
	Toys.add(Toys.sphere(0.5), cream_in, Vector3(0, 0.56, 0.06), g, Vector3(0.8, 0.86, 0.85))

	# head
	var h := Toys.group(Vector3(0, 1.25, 0.05), g)
	h.set_meta("part", "head")
	Toys.add(Toys.sphere(0.46), fur, Vector3.ZERO, h, Vector3(1.12, 0.92, 0.95))
	for s in [-1, 1]:
		# urajiro cheek mask, merged with the muzzle into one cream shape
		Toys.add(Toys.sphere(0.22), cream_in, Vector3(0.22 * s, -0.15, 0.26), h, Vector3(1.15, 0.82, 0.8))
	Toys.add(Toys.sphere(0.2), cream, Vector3(0, -0.13, 0.37), h, Vector3(1.2, 0.8, 0.85))
	Toys.add(Toys.sphere(0.065), dark, Vector3(0, -0.06, 0.54), h, Vector3(1.35, 0.95, 0.8))
	Toys.add(Toys.sphere(0.016), shine, Vector3(-0.025, -0.035, 0.588), h)
	var mouth := Toys.torus(0.03, 0.045)
	for s in [-1, 1]:
		Toys.add(mouth, dark, Vector3(0.038 * s, -0.175, 0.5), h, Vector3(1, 1, 0.5), Vector3(PI / 2, 0, 0))
	for s in [-1, 1]:
		Toys.add(Toys.sphere(0.065), dark, Vector3(0.17 * s, 0.04, 0.39), h, Vector3(1, 1.15, 0.6))
		Toys.add(Toys.sphere(0.02), shine, Vector3(0.17 * s - 0.022, 0.072, 0.43), h)
		Toys.add(Toys.sphere(0.045), cream_in, Vector3(0.16 * s, 0.19, 0.395), h, Vector3(1.3, 0.75, 0.45))   # kiro dots
		Toys.add(Toys.sphere(0.07), blush, Vector3(0.3 * s, -0.08, 0.33), h, Vector3(1, 0.6, 0.4))
		# pointy upright ears, cream inside
		var ear := Toys.group(Vector3(0.24 * s, 0.33, -0.02), h)
		ear.rotation = Vector3(-0.12, 0, -0.3 * s)
		var cone := CylinderMesh.new(); cone.top_radius = 0.0; cone.bottom_radius = 0.17; cone.height = 0.34; cone.radial_segments = 20
		Toys.add(cone, fur, Vector3(0, 0.15, 0), ear, Vector3(1, 1, 0.6))
		var inner := CylinderMesh.new(); inner.top_radius = 0.0; inner.bottom_radius = 0.1; inner.height = 0.22; inner.radial_segments = 16
		Toys.add(inner, Toys.mat(Color("ffe2cc"), 0.9, 0.0), Vector3(0, 0.12, 0.065), ear, Vector3(1, 1, 0.3))

	# mint scarf (kept from the bear)
	Toys.add(Toys.torus(0.26, 0.42), scarf, Vector3(0, 0.92, 0.02), g)
	var tail_scarf := Toys.add(Toys.capsule(0.09, 0.38), scarf, Vector3(0.17, 0.7, 0.42), g, Vector3.ONE, Vector3(0.2, 0, 0.25))
	tail_scarf.set_meta("part", "scarf")

	# arms held forward + stubby legs, paws cream-tipped
	for s in [-1, 1]:
		var arm := Toys.add(Toys.capsule(0.11, 0.5), fur, Vector3(0.38 * s, 0.72, 0.3), g, Vector3.ONE, Vector3(-1.1, 0, 0.3 * s))
		arm.set_meta("part", "arm")
		Toys.add(Toys.sphere(0.107), cream_in, Vector3(0, -0.152, 0), arm)   # paw tip cap, flush with the arm
		if sitting:
			var ft := Toys.add(Toys.capsule(0.13, 0.4), fur, Vector3(0.22 * s, 0.13, 0.32), g, Vector3.ONE, Vector3(PI / 2, 0, 0.15 * s))
			Toys.add(Toys.sphere(0.127), cream_in, Vector3(0, -0.08, 0), ft)
		else:
			var leg := Toys.add(Toys.capsule(0.13, 0.36), fur, Vector3(0.2 * s, 0.12, 0.05), g)
			leg.set_meta("part", "leg")
			Toys.add(Toys.sphere(0.127), cream_in, Vector3(0, -0.06, 0.01), leg)

	# big curled tail over the back: one fat torus curl, cream underside and tip
	var tail := Toys.group(Vector3(0, 0.62, -0.42), g)
	tail.set_meta("part", "tail")
	Toys.add(Toys.torus(0.015, 0.34), fur, Vector3(0.0, 0.2, -0.06), tail, Vector3(0.85, 1, 1), Vector3(0, 0, PI / 2))
	return g
