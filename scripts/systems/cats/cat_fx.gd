extends RefCounted
## Cat FX kit: a plush heart mesh, an exclamation mark and small material helpers.
## Everything is built from code in the soft toy style (see Toys). No emojis, no external assets.

static var _mats := {}

## Cached soft material (with a faint glow so hearts read against any light).
static func soft_mat(c: Color, outline := 0.05, glow := 0.35) -> StandardMaterial3D:
	var key := "%s_%s_%s" % [c.to_html(), outline, glow]
	if _mats.has(key): return _mats[key]
	var m := Toys.mat(c, 0.55, outline)
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	_mats[key] = m
	return m

## A plush heart (two round lobes and a cone) of the given world width, facing +Z. Returns a Node3D group.
static func heart(size: float, c: Color) -> Node3D:
	var g := Node3D.new()
	var m := soft_mat(c, 0.0, 0.35)
	var k := size * 0.5
	var l1 := Toys.add(Toys.sphere(0.56, 20), m, Vector3(-0.5, 0.3, 0) * k, g, Vector3(1, 1, 0.7) * k)
	var l2 := Toys.add(Toys.sphere(0.56, 20), m, Vector3(0.5, 0.3, 0) * k, g, Vector3(1, 1, 0.7) * k)
	var cone := CylinderMesh.new()
	cone.top_radius = 1.0; cone.bottom_radius = 0.0; cone.height = 1.45; cone.radial_segments = 20
	var cn := Toys.add(cone, m, Vector3(0, -0.28, 0) * k, g, Vector3(1.0, 1.0, 0.7) * k)
	for n in [l1, l2, cn]: n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return g

## Exclamation mark, about 0.9 units tall, centred on its middle. Scale the returned node.
static func exclaim() -> Node3D:
	var g := Node3D.new()
	var m := soft_mat(Color("ff9d2e"), 0.06, 0.5)
	Toys.add(Toys.capsule(0.13, 0.62), m, Vector3(0, 0.22, 0), g, Vector3(1, 1, 0.6))
	Toys.add(Toys.sphere(0.13), m, Vector3(0, -0.28, 0), g, Vector3(1, 1, 0.6))
	return g

## Colour from a hex string, with a fallback for empty or broken data.
static func col(v, fallback: Color) -> Color:
	var s := str(v)
	if s == "" or s == "null": return fallback
	if not s.is_valid_html_color(): return fallback
	return Color(s)

# ---------------------------------------------------------------- the one bubble
## The single head bubble cats use to talk: a word or a drawn icon, nothing else.
## kinds: "name" (data.text), "zzz", "alert", "heart", "hearts" (data.n, data.max, data.new_from), "dots", "want" (data.item).
## Built at world size (round bubble radius 0.3 m, tail tip about 0.42 m below the centre). Face it to the camera yourself.
const TEXT_PX := 0.0046
const TEXT_SIZE := 52
const INK_TEXT := Color("5b4036")

static func bubble(kind: String, data := {}) -> Node3D:
	var g := Node3D.new()
	var tint := Color("fffaf0")
	match kind:
		"alert": tint = Color("fff0bd")
		"heart", "hearts": tint = Color("ffeef2")
		"zzz": tint = Color("eaf1ff")
	var body := soft_mat(tint, 0.035, 0.2)
	var ry := 0.3
	var front := 0.09
	var icon := Node3D.new()
	icon.name = "Icon"
	var pops: Array = []
	if kind == "name" or kind == "zzz" or kind == "hearts":
		ry = 0.2
		var length := 0.0
		var text := ""
		if kind == "hearts":
			ry = 0.2
			length = 1.0
		else:
			text = String(data.get("text", "")) if kind == "name" else "Zzz"
			length = maxf(text_width(text) + 0.36, 0.7)
		length = maxf(length, ry * 2.0 + 0.02)
		Toys.add(Toys.capsule(ry, length), body, Vector3.ZERO, g, Vector3(1, 1, 0.3), Vector3(0, 0, PI / 2))
		front = ry * 0.3
		if kind == "hearts":
			var hm := heart(0.34, Color("ff5f86"))
			hm.position = Vector3(-length * 0.5 + 0.3, 0.0, front - 0.01)
			icon.add_child(hm)
			hm.set_meta("base", hm.scale)
			pops.append(hm)
			text = "%d/%d" % [int(data.get("n", 0)), int(data.get("max", 5))]
			var lb2 := _text_label(text)
			lb2.position = Vector3(0.14, 0.005, front + 0.012)
			icon.add_child(lb2)
		else:
			var lb := _text_label(text)
			lb.position = Vector3(0, 0.005, front + 0.012)
			icon.add_child(lb)
	else:
		Toys.add(Toys.sphere(ry), body, Vector3.ZERO, g, Vector3(1, 1, 0.3))
		front = ry * 0.3
		match kind:
			"alert":
				var ex := exclaim()
				ex.scale = Vector3.ONE * 0.4
				ex.position = Vector3(0, 0.01, front - 0.02)
				icon.add_child(ex)
			"heart":
				var hm := heart(0.38, Color("ff5f86"))
				hm.position = Vector3(0, 0.0, front - 0.02)
				icon.add_child(hm)
			"dots":
				var dm := soft_mat(Color("8a7068"), 0.04, 0.0)
				for i in 3:
					Toys.add(Toys.sphere(0.045), dm, Vector3((float(i) - 1.0) * 0.14, 0.0, front + 0.0), icon)
			"want":
				item_icon(icon, String(data.get("item", "")), front)
	var tail := CylinderMesh.new()
	tail.top_radius = 0.09; tail.bottom_radius = 0.0; tail.height = 0.2; tail.radial_segments = 14
	Toys.add(tail, body, Vector3(0, -ry - 0.02, 0), g, Vector3(1, 1, 0.3))
	g.add_child(icon)
	g.set_meta("pops", pops)
	_no_shadow(g)
	return g

static func _text_label(text: String) -> Label3D:
	var lb := Label3D.new()
	lb.text = text
	lb.font_size = TEXT_SIZE
	lb.pixel_size = TEXT_PX
	lb.modulate = INK_TEXT
	lb.outline_size = 0
	lb.shaded = false
	lb.double_sided = false
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return lb

static func text_width(text: String) -> float:
	var f: Font = ThemeDB.fallback_font
	if f != null:
		return f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE).x * TEXT_PX
	return float(text.length()) * 0.5 * float(TEXT_SIZE) * TEXT_PX

static func _no_shadow(n: Node) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D: (c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_no_shadow(c)

## Small drawn icon of what a cat wants: its favourite fish (real colours) or treat.
static func item_icon(parent: Node3D, item: String, front: float) -> void:
	var z := front - 0.01
	if item.begins_with("fish:"):
		var f = Data.FISH.get(item.substr(5), {})
		var fd: Dictionary = f if typeof(f) == TYPE_DICTIONARY else {}
		var fg := Toys.fish(parent, col(fd.get("body", ""), Color("a9c4d6")), col(fd.get("fin", ""), Color("6f8fa8")), 0.36)
		fg.rotation.y = PI / 2.0
		fg.position = Vector3(0.02, 0.0, z)
	elif item == "treat:cream":
		var cup := soft_mat(Color("fff6ea"), 0.04, 0.1)
		Toys.add(Toys.cyl(0.12, 0.085, 0.17), cup, Vector3(-0.015, -0.03, z), parent)
		Toys.add(Toys.sphere(0.115), soft_mat(Color("ffdca0"), 0.03, 0.1), Vector3(-0.015, 0.06, z), parent, Vector3(1, 0.5, 1))
		Toys.add(Toys.torus(0.03, 0.07), cup, Vector3(0.12, -0.02, z), parent, Vector3.ONE, Vector3(PI / 2, 0, 0))
	elif item == "treat:catnip":
		var leaf := soft_mat(Color("7ccf8e"), 0.04, 0.1)
		Toys.add(Toys.sphere(0.09), leaf, Vector3(-0.07, 0.05, z), parent, Vector3(0.7, 1.7, 0.45), Vector3(0, 0, 0.5))
		Toys.add(Toys.sphere(0.09), leaf, Vector3(0.07, 0.05, z), parent, Vector3(0.7, 1.7, 0.45), Vector3(0, 0, -0.5))
		Toys.add(Toys.capsule(0.02, 0.2), soft_mat(Color("5aa86f"), 0.04, 0.0), Vector3(0, -0.08, z), parent)
	elif item == "treat:tuna_bites":
		var bite := soft_mat(Color("f0a8a0"), 0.04, 0.1)
		for i in 3:
			Toys.add(Toys.sphere(0.065), bite, Vector3((float(i) - 1.0) * 0.12, -0.02 + (0.05 if i == 1 else 0.0), z), parent, Vector3(1, 0.85, 0.7))
	else:
		Toys.add(Toys.sphere(0.12), soft_mat(Color("e8c08a"), 0.04, 0.1), Vector3(0, 0, z), parent, Vector3(1, 0.8, 0.6))
