extends RefCounted
## Helpers shared by shore / town / lanterns: user args for self-tests, spot lookup with a fallback layout
## when the island does not exist, and a tiny stage (ground, light, camera) so self-tests still render.

const FALLBACK := {
	"shop_counter": Vector3(-3.0, 0, -4.0), "shop": Vector3(-3.0, 0, -2.0), "board": Vector3(2.6, 0, -3.4),
	"lantern_harbour": Vector3(7.0, 0, 3.0), "lantern_hill": Vector3(-7.0, 0, 3.0), "beach": Vector3(0, 0, 8.0),
	"flats": Vector3(2.0, 0, 12.0), "plaza": Vector3(0, 0, 0), "home": Vector3(-6.0, 0, -5.0), "spawn": Vector3(0, 0, 2.0),
}

static func args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=", true, 1)
		if kv.size() == 2: out[kv[0]] = kv[1]
	return out

static func island(main: Node) -> Node:
	if main == null: return null
	var i: Variant = main.get("island")
	return i if (i is Node and is_instance_valid(i)) else null

static func player(main: Node) -> Node:
	if main == null: return null
	var p: Variant = main.get("player")
	return p if (p is Node and is_instance_valid(p)) else null

static func hud(main: Node) -> Node:
	if main == null: return null
	var h: Variant = main.get("hud")
	return h if (h is Node and is_instance_valid(h)) else null

static func system(main: Node, id: String) -> Node:
	if main == null: return null
	var s: Variant = main.get("systems")
	if s is Dictionary and s.has(id) and is_instance_valid(s[id]): return s[id]
	return null

## Spot position from the island, or the fallback layout when the island (or the spot) is missing.
static func spot(main: Node, name: String) -> Vector3:
	var isl := island(main)
	if isl != null and isl.has_method("spot"):
		var p: Variant = isl.spot(name)
		if p is Vector3 and p != Vector3.ZERO: return p
	return FALLBACK.get(name, Vector3.ZERO)

static func ground_y(main: Node, x: float, z: float) -> float:
	var isl := island(main)
	if isl != null and isl.has_method("ground_y"):
		var y: Variant = isl.ground_y(x, z)
		if y is float or y is int: return float(y)
	return 0.0

## A People-system perk (shop discount, gold bonus, ...). 0 when the People system is absent.
static func perk(main: Node, name: String, default := 0.0) -> float:
	var pe := system(main, "people")
	if pe != null and pe.has_method("perk_value"):
		var v: Variant = pe.perk_value(name, default)
		if v is float or v is int: return float(v)
	return default

## Self-test stage: ground disc, light and a camera framing `focus` -- only what is missing.
static func ensure(main: Node, focus: Vector3, cam_off := Vector3(0, 6.5, 8.5)) -> void:
	if main == null: return
	if island(main) == null:
		var ground := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 40; cyl.bottom_radius = 40; cyl.height = 0.2
		ground.mesh = cyl
		ground.material_override = Toys.mat(Color("f0dfc0"), 0.95, 0.0)
		ground.position = Vector3(0, -0.1, 0)
		main.add_child(ground)
	if main.get("sky") == null:
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color("bfe3ee")
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("fff0dc")
		env.ambient_light_energy = 0.75
		var we := WorldEnvironment.new()
		we.environment = env
		main.add_child(we)
		var sun := DirectionalLight3D.new()
		sun.light_color = Color("ffe6bf")
		sun.light_energy = 1.2
		sun.shadow_enabled = true
		sun.rotation_degrees = Vector3(-50, -30, 0)
		main.add_child(sun)
	var pl := player(main)
	if pl != null:
		if pl is Node3D: pl.global_position = focus + Vector3(0, 0.2, 2.6)
	else:
		var cam := Camera3D.new()
		cam.fov = 45
		main.add_child(cam)
		cam.look_at_from_position(focus + cam_off, focus + Vector3(0, 0.6, 0))
		cam.current = true
