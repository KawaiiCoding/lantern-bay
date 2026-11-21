extends Node3D
## One shore pickup: a small cute toy-like find (shell, sea glass, driftwood, star stone, moon shell, bottle)
## with a gentle twinkle and a soft glow on the sand. Interactable: prompt "Pick up".
## Gold variants are tinted gold and twinkle harder.

const Dat := preload("res://scripts/systems/town/dat.gd")
const Fx := preload("res://scripts/systems/town/fx.gd")
const SCALE := 1.7      # toy scale-up so the finds read on a phone screen

var item_id := ""
var gold := false
var idx := 0
var flats := false
var shore: Node                 # owner system, has collect(pickup)
var interact_radius := 1.5
var interact_priority := 0

var _vis: Node3D
var _base_y := 0.0
var _star: MeshInstance3D
var _glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _t := 0.0
var _phase := 0.0
var _taken := false

func _ready() -> void:
	add_to_group("interactable")
	_phase = float(idx) * 1.7
	_build()
	_ground_fit()
	scale = Vector3.ONE * 0.01
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func get_prompt(_player: Variant) -> String:
	return "" if _taken else "Pick up"

func interact(_player: Variant) -> void:
	if _taken: return
	_taken = true
	remove_from_group("interactable")
	if shore != null and is_instance_valid(shore) and shore.has_method("collect"):
		shore.collect(self)
	_pop()

# ------------------------------------------------------------------ look
func _m(c: Color, rough := 0.85, outline := 0.025) -> StandardMaterial3D:
	if gold:
		var g := Toys.mat(Color("f2c14e"), 0.35, outline)
		g.emission_enabled = true
		g.emission = Color("e9a92e")
		g.emission_energy_multiplier = 0.55
		return g
	return Toys.mat(c, rough, outline)

func _glass(c: Color, alpha: float) -> StandardMaterial3D:
	var m := _m(c, 0.12)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var base := m.albedo_color
	m.albedo_color = Color(base.r, base.g, base.b, alpha)
	if not gold:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.35
	return m

func _kind() -> String:
	var id := item_id
	if id.contains("bottle"): return "bottle"
	if id.contains("moon"): return "moon"
	if id.contains("star"): return "star"
	if id.contains("glass"): return "glass"
	if id.contains("wood"): return "wood"
	if id.contains("shell"): return "shell"
	return "pebble"

func _build() -> void:
	var info := Dat.entry("SHORE", item_id)
	var col := Dat.col(info.get("color", "fbf3e6"))
	_vis = Toys.group(Vector3.ZERO, self, float(idx) * 2.399, SCALE)
	match _kind():
		"shell":
			Toys.add(Toys.sphere(0.16), _m(col), Vector3(0, 0.04, 0), _vis, Vector3(1.0, 0.5, 0.86))
			var ridge := _m(col.darkened(0.16), 0.85, 0.0)
			for k in 5:
				var a := lerpf(-0.75, 0.75, k / 4.0)
				var dir := Vector3(sin(a), 0, cos(a))
				Toys.add(Toys.capsule(0.014, 0.16), ridge, Vector3(0, 0.078, -0.08) + dir * 0.09, _vis, Vector3.ONE, Vector3(PI / 2 - 0.12, a, 0))
			Toys.add(Toys.sphere(0.045), _m(col.darkened(0.1)), Vector3(0, 0.05, -0.15), _vis, Vector3(1.3, 0.8, 0.8))
		"glass":
			var gm := _glass(col, 0.78)
			Toys.add(Toys.sphere(0.15), gm, Vector3(0, 0.06, 0), _vis, Vector3(1.0, 0.56, 0.8), Vector3(0, 0.5, 0))
			Toys.add(Toys.sphere(0.07), gm, Vector3(0.1, 0.05, 0.05), _vis, Vector3(1.0, 0.7, 0.9))
			Toys.add(Toys.sphere(0.025), Toys.glow(Color.WHITE, 1.0), Vector3(-0.05, 0.12, 0.0), _vis, Vector3(1, 0.5, 1))
		"wood":
			var wm := _m(col)
			Toys.add(Toys.capsule(0.05, 0.46), wm, Vector3(0, 0.06, 0), _vis, Vector3.ONE, Vector3(0, 0, PI / 2))
			Toys.add(Toys.capsule(0.035, 0.2), wm, Vector3(0.07, 0.11, 0.07), _vis, Vector3.ONE, Vector3(0.5, 0.0, PI / 2 - 0.7))
			Toys.add(Toys.sphere(0.04), _m(col.darkened(0.22)), Vector3(-0.1, 0.1, 0.02), _vis, Vector3(1, 0.6, 1))
		"star":
			var sm := Toys.glow(col, 0.9) if not gold else _m(col)
			for k in 5:
				var arm := Toys.group(Vector3(0, 0.05, 0), _vis, TAU * k / 5.0)
				arm.scale = Vector3(1.0, 0.55, 1.0)
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0; cone.bottom_radius = 0.085; cone.height = 0.24; cone.radial_segments = 12
				Toys.add(cone, sm, Vector3(0, 0, 0.11), arm, Vector3.ONE, Vector3(PI / 2, 0, 0))
			Toys.add(Toys.sphere(0.1), sm, Vector3(0, 0.05, 0), _vis, Vector3(1, 0.6, 1))
		"moon":
			var mm := _m(col, 0.4)
			mm.emission_enabled = true
			mm.emission = col
			mm.emission_energy_multiplier = 0.5
			Toys.add(Toys.sphere(0.16), mm, Vector3(0, 0.08, 0), _vis, Vector3(1, 0.72, 1))
			Toys.add(Toys.sphere(0.07), mm, Vector3(0.12, 0.05, 0.08), _vis, Vector3(1, 0.7, 1))
			Toys.add(Toys.torus(0.035, 0.11), _m(col.darkened(0.2), 0.7, 0.0), Vector3(0, 0.15, 0), _vis, Vector3(1, 0.7, 1))
			Toys.add(Toys.torus(0.012, 0.045), _m(col.darkened(0.25), 0.7, 0.0), Vector3(0, 0.19, 0), _vis)
		"bottle":
			var bm := _glass(col, 0.6)
			var bt := Toys.group(Vector3(0, 0.1, 0), _vis)
			bt.rotation = Vector3(0, 0, 0.12)
			Toys.add(Toys.capsule(0.09, 0.36), bm, Vector3.ZERO, bt, Vector3.ONE, Vector3(0, 0, PI / 2))
			Toys.add(Toys.cyl(0.035, 0.055, 0.2), bm, Vector3(0.25, 0, 0), bt, Vector3.ONE, Vector3(0, 0, -PI / 2))
			Toys.add(Toys.sphere(0.042), Toys.mat(Color("c98a5a"), 0.9, 0.012), Vector3(0.36, 0, 0), bt)
			Toys.add(Toys.cyl(0.03, 0.03, 0.2), Toys.mat(Color("fff6ea"), 0.9, 0.0), Vector3(-0.02, 0, 0), bt, Vector3.ONE, Vector3(0, 0, PI / 2))
		_:
			Toys.add(Toys.sphere(0.12), _m(col), Vector3(0, 0.07, 0), _vis, Vector3(1, 0.7, 1))

	# soft glow on the sand
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.46; cyl.bottom_radius = 0.46; cyl.height = 0.01; cyl.radial_segments = 24
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_mat.albedo_color = Color(1.0, 0.86, 0.45, 0.16) if gold else Color(1.0, 0.95, 0.78, 0.1)
	_glow = MeshInstance3D.new()
	_glow.mesh = cyl
	_glow.material_override = _glow_mat
	_glow.position = Vector3(0, 0.025, 0)
	add_child(_glow)

	# twinkle
	_star = MeshInstance3D.new()
	_star.mesh = Fx.quad(0.5 if not gold else 0.7)
	_star.material_override = Fx.sparkle_mat(Color("ffe9a0") if gold else Color("fff6d6"))
	_star.position = Vector3(0.12, 0.5, 0.0)
	add_child(_star)

## Lowest mesh point of the visual sits on the sand (a hair above, so nothing z-fights or sinks in).
func _ground_fit() -> void:
	var inv := global_transform.affine_inverse()
	var lowest := INF
	var stack: Array = [_vis]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children(): stack.append(c)
		if cur is MeshInstance3D and (cur as MeshInstance3D).mesh != null:
			var mi := cur as MeshInstance3D
			var box: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
			lowest = minf(lowest, box.position.y)
	if lowest < INF:
		_base_y = -lowest + 0.004
		_vis.position.y = _base_y

func _process(dt: float) -> void:
	_t += dt
	if _taken or _vis == null: return
	_vis.position.y = _base_y + sin(_t * 2.0 + _phase) * 0.012
	var tw := 0.5 + 0.5 * sin(_t * 2.6 + _phase)
	var k := (0.18 + 0.82 * pow(tw, 2.2)) * (1.25 if gold else 1.0)
	_star.scale = Vector3.ONE * k
	_star.position.y = 0.46 + 0.07 * sin(_t * 1.7 + _phase)
	var base_a := 0.16 if gold else 0.1
	_glow_mat.albedo_color.a = base_a * (0.7 + 0.5 * tw)

# ------------------------------------------------------------------ pop and vanish
func _pop() -> void:
	var parent := get_parent()
	var tint := Color("ffd34a") if gold else Color("fff0b8")
	if parent != null:
		Fx.burst(parent, position + Vector3(0, 0.3, 0), tint, 22 if gold else 12, 3.2 if gold else 2.4)
		if gold: Fx.ring(parent, position, Color("ffd34a"), 1.6, 0.6)
	_star.visible = false
	_glow.visible = false
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_vis, "scale", Vector3.ONE * SCALE * 1.55, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_vis, "position:y", 0.5, 0.2).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(_vis, "scale", Vector3.ONE * 0.01, 0.14).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)

## The tide covers it again.
func vanish() -> void:
	if _taken: return
	_taken = true
	remove_from_group("interactable")
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 0.01, 0.4).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
