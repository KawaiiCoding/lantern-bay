extends Node3D
## One lantern of the bay: the interactable ("Light the lantern (X sparks)" once you can afford it) plus the
## warm light that appears when it is lit. The model itself comes from the island (island.lantern_node(id));
## when the island has none we build a simple lantern post here.

const Dat := preload("res://scripts/systems/town/dat.gd")
const Fx := preload("res://scripts/systems/town/fx.gd")
const Stage := preload("res://scripts/systems/town/stage.gd")

var lantern_id := ""
var cost := 10
var lname := "Lantern"
var unlocks := ""
var system: Node                 # owner, has light(spot)
var main: Node
var interact_radius := 2.8
var interact_priority := 3
var lit := false
var igniting := false

var host: Node3D                 # where visuals attach (island lantern node or our own post)
var _light: OmniLight3D
var _glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _halo: MeshInstance3D
var _lens_unlit: MeshInstance3D
var _label: Label3D
var _flies: CPUParticles3D
var _top := 2.2
var _t := 0.0
var _boost := 0.0                # celebration energy, decays to 0

func _ready() -> void:
	add_to_group("interactable")

# ------------------------------------------------------------------ visuals
## Build the light + glow on `h`. `own_post` builds a simple lantern post there first.
func attach(h: Node3D, own_post: bool) -> void:
	host = h
	if own_post:
		var post := Toys.mat(Color("6e6390"))
		Toys.add(Toys.cyl(0.08, 0.12, 2.1), post, Vector3(0, 1.05, 0), h)
		Toys.add(Toys.cyl(0.22, 0.22, 0.07), post, Vector3(0, 2.1, 0), h)
		_lens_unlit = Toys.add(Toys.sphere(0.26), Toys.mat(Color("d8d0c0"), 0.4), Vector3(0, 2.42, 0), h)
		var roof := CylinderMesh.new()
		roof.top_radius = 0.0; roof.bottom_radius = 0.36; roof.height = 0.3; roof.radial_segments = 16
		Toys.add(roof, post, Vector3(0, 2.82, 0), h)
		_top = 2.42
	else:
		_top = maxf(_top_of(h) - 0.35, 1.0)
	_light = OmniLight3D.new()
	_light.light_color = Color("ffcf7a")
	_light.omni_range = 7.5
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, _top + 0.1, 0)
	_light.visible = false
	h.add_child(_light)
	_glow_mat = Toys.glow(Color("ffd89a"), 3.0)
	_glow = Toys.add(Toys.sphere(0.27), _glow_mat, Vector3(0, _top, 0), h)
	_glow.visible = false
	_halo = MeshInstance3D.new()
	_halo.mesh = Fx.quad(2.4)
	_halo.material_override = Fx.sparkle_mat(Color(1.0, 0.8, 0.45, 0.55))
	_halo.position = Vector3(0, _top, 0)
	_halo.visible = false
	h.add_child(_halo)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = false
	_label.pixel_size = 0.006
	_label.font_size = 56
	_label.outline_size = 14
	_label.modulate = Color("fff6e0")
	_label.outline_modulate = Color("6b4a3a")
	_label.position = Vector3(0, _top + 0.85, 0)
	h.add_child(_label)
	_refresh_label()
	if not GameState.sparks_changed.is_connected(_on_sparks):
		GameState.sparks_changed.connect(_on_sparks)

static func _top_of(n: Node3D) -> float:
	var inv := n.global_transform.affine_inverse()
	var best := -INF
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children(): stack.append(c)
		if cur is MeshInstance3D and (cur as MeshInstance3D).mesh != null and (cur as MeshInstance3D).visible:
			var mi := cur as MeshInstance3D
			var box: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
			best = maxf(best, box.end.y)
	return best if best > -INF else 2.2

func _on_sparks(_s: int) -> void:
	_refresh_label()

func _refresh_label() -> void:
	if _label == null or not is_instance_valid(_label): return
	_label.visible = not lit
	_label.text = "%d / %d sparks" % [GameState.sparks, cost] if GameState.sparks < cost else "Ready to light"

## Turn the light on. `animated` plays the little celebration; otherwise it is simply lit (after a reload).
func set_lit(on: bool, animated := false) -> void:
	lit = on
	if _label != null: _refresh_label()
	if _lens_unlit != null: _lens_unlit.visible = not on
	if _glow == null: return
	_light.visible = on
	_glow.visible = on
	_halo.visible = on
	if on:
		_light.light_energy = 1.4
		_start_flies()
		if animated: _celebrate()

func _start_flies() -> void:
	if _flies != null and is_instance_valid(_flies): return
	var p := CPUParticles3D.new()
	var q := Fx.quad(0.16)
	q.material = Fx.sparkle_mat(Color.WHITE)
	p.mesh = q
	p.amount = 6
	p.lifetime = 3.2
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.9
	p.direction = Vector3.UP
	p.spread = 30.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.35
	p.color = Color("ffe2a0")
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.add_point(0.3, Color(1, 1, 1, 1))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	p.color_ramp = g
	p.position = Vector3(0, _top - 0.2, 0)
	host.add_child(p)
	p.emitting = true
	_flies = p

func _celebrate() -> void:
	igniting = true
	_boost = 1.0
	_glow.scale = Vector3.ONE * 0.05
	_halo.scale = Vector3.ONE * 0.1
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_glow, "scale", Vector3.ONE * 1.7, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(_glow, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_SINE)
	var tw2 := create_tween()
	tw2.tween_property(_halo, "scale", Vector3.ONE * 2.2, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw2.tween_property(_halo, "scale", Vector3.ONE, 1.2).set_trans(Tween.TRANS_SINE)
	var parent: Node = get_parent()
	if parent != null:
		var base := Vector3(global_position.x, global_position.y, global_position.z)
		Fx.burst(parent, base + Vector3(0, _top, 0), Color("ffd98a"), 46, 4.2, 1.5, 0.3)
		Fx.ring(parent, base, Color("ffd27a"), 7.0, 1.3)
		get_tree().create_timer(0.35).timeout.connect(func() -> void:
			if is_instance_valid(parent): Fx.ring(parent, base, Color("fff0b8"), 10.0, 1.7))
		get_tree().create_timer(0.2).timeout.connect(func() -> void:
			if is_instance_valid(parent): Fx.burst(parent, base + Vector3(0, _top + 0.3, 0), Color("fff3c8"), 28, 2.4, 1.8, 0.22))
	var done := get_tree().create_timer(1.6)
	done.timeout.connect(func() -> void: igniting = false)

# ------------------------------------------------------------------ interactable contract
func get_prompt(_player: Variant) -> String:
	if lit or igniting: return ""
	if GameState.sparks >= cost:
		return "Light the lantern (%d sparks)" % cost
	return ""

func interact(_player: Variant) -> void:
	if lit or igniting: return
	if system != null and is_instance_valid(system) and system.has_method("light"):
		system.light(self)

func _process(dt: float) -> void:
	_t += dt
	if _label != null and _label.visible:
		var pl := Stage.player(main)
		var near := true
		if pl is Node3D:
			near = (pl as Node3D).global_position.distance_to(global_position) < 9.0
		_label.visible = near and not lit
	if not lit or _light == null: return
	_boost = maxf(0.0, _boost - dt * 0.7)
	var h := GameState.hour()
	var night := 0.0
	if h >= 17.0 and h < 20.0: night = (h - 17.0) / 3.0
	elif h >= 20.0 or h < 5.0: night = 1.0
	elif h >= 5.0 and h < 7.5: night = 1.0 - (h - 5.0) / 2.5
	var flick := 1.0 + 0.05 * sin(_t * 7.0 + 1.3) + 0.03 * sin(_t * 11.3)
	_light.light_energy = (lerpf(1.1, 3.2, night) + _boost * 5.0) * flick
	_light.omni_range = 7.5 + _boost * 3.0
	_glow_mat.emission_energy_multiplier = lerpf(2.0, 4.2, night) + _boost * 3.0
