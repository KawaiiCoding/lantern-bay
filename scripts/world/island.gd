extends Node3D
## Island (World owner): Lantern Bay, built entirely in code.
## Contract (docs/TEAM.md): spot(), ground_y(), random_beach_point(), random_flats_point(), is_walkable(),
## refresh_unlocks(), lantern_node(); plus `sea_level` and is_shallow(p).
##
## Layout (x east, z south; the 3/4 camera looks north):
##   plaza + fountain at (0, 1.5) inside an oval road loop. Mocha's home NW of it, a neighbour in the middle,
##   Pip's shop NE with the request board to its east. Lighthouse on the NE point behind a gate (harbour
##   lantern). Hill to the W, reached by a ramp from the south, gated until the hill lantern. Pier SE.
##   Tide flats SSW (only walkable at low tide). Sand ring all around, invisible sea wall at the water.
## Ground is flat at y = 0 everywhere except the hill plateau (y = HILL_TOP) and its ramp.
##
## Self-test (temporary camera until the player exists, keeps working after):
##   godot --path . -- test=island [view=close|plaza|shop|pier|rocks|hill|flats|north|west|east|top|over]
##       [hour=17.5] [weather=rain] [unlock=harbour,hill] shot=/tmp/lb_world.png wait=2
##   godot --path . -- test=island snap=/tmp/lb_  (saves every view as /tmp/lb_<view>.png, then quits)

const SEA_Y := -0.32
const BASE_R := 17.6
const SHORE_WAVES := [[0.8, 3.0, 0.7], [0.5, 5.0, 2.1], [0.3, 7.0, 4.0]]
const PEN_A := -0.75                      # lighthouse point direction (NE)
const HILL_A := -3.05                     # hill direction (W)
const SHORE_BUMPS := [[4.6, -0.75, 0.26], [-2.4, -1.19, 0.2], [-2.4, -0.31, 0.2], [3.4, -3.05, 0.5]]
const BEACH_W := 3.4                      # sand width inland from the waterline
const WALL_D := 0.4                       # sea wall distance inland from the waterline
const HILL_C := Vector2(-13.6, -1.2)
const HILL_TOP := 1.8
const HILL_R := 3.2                       # walkable plateau radius
const HILL_BASE := 4.4
const RAMP_X := -13.6
const RAMP_HW := 1.05
const RAMP_Z0 := 1.9                      # top end (meets the plateau)
const RAMP_Z1 := 7.4                      # bottom end
const HILL_GATE_Z := 7.75
const PIER_X := 8.5
const PIER_HW := 1.2
const GATE_D := 15.0                      # harbour gate line: distance from the centre along the point direction
const FLATS_A := 1.95
const FLATS_AB := Vector2(4.6, 3.0)
const LOOP_C := Vector2(0.0, 1.5)
const LOOP_R := Vector2(8.0, 5.5)
const ROAD_W := 2.2
const PLAZA_R := 3.4
const HOME_POS := Vector3(-4.8, 0, -8.0)
const SHOP_POS := Vector3(4.8, 0, -8.0)
const BOARD_POS := Vector3(7.6, 0, -6.6)
const BOARD_ROT := -0.35

var sea_level := SEA_Y
var main: Node
var pier_z0 := 12.0
var pier_z1 := 24.0
var flats_c := Vector2.ZERO
var flats_u := Vector2.RIGHT
var flats_level := 0.0                     # 0 hidden .. 1 fully exposed

var _spots := {}
var _blocks: Array = []                    # Vector3(x, z, radius): solid round things
var _rects: Array = []                     # Rect2 (x, z): solid footprints
var _paths: Array = []                     # [PackedVector2Array, half_width]
var _rng := RandomNumberGenerator.new()
var _args := {}
var _static: Node3D
var _solid: StaticBody3D
var _hill_gate: Node3D
var _harbour_gate: Node3D
var _tide_gate: StaticBody3D
var _flats_bar: Node3D
var _lanterns := {}
var _lantern_glass := {}
var _boat: Node3D
var _blades: Node3D
var _beam: Node3D
var _lh_lamp: StandardMaterial3D
var _lh_light: OmniLight3D
var _sea_mat: ShaderMaterial
var _gulls: Array = []
var _flies: Array = []
var _sailboats: Array = []
var _ferry: Node3D
var _buoys: Array = []
var _fireflies: CPUParticles3D
var _petals: CPUParticles3D
var _unlocked_now := {}
var _test_cam: Camera3D
var _time := 0.0

# ================================================================ public API
func spot(name: String) -> Vector3:
	return _spots.get(name, Vector3.ZERO)

func spot_names() -> Array:
	return _spots.keys()

func ground_y(x: float, z: float) -> float:
	if absf(x - RAMP_X) <= RAMP_HW and z >= RAMP_Z0 and z <= RAMP_Z1:
		return HILL_TOP * (RAMP_Z1 - z) / (RAMP_Z1 - RAMP_Z0)
	if Vector2(x, z).distance_to(HILL_C) <= HILL_R:
		return HILL_TOP
	return 0.0

func random_beach_point(rng: RandomNumberGenerator) -> Vector3:
	for i in 60:
		var t := rng.randf_range(-PI, PI)
		var r := shore_r(t) - rng.randf_range(WALL_D + 0.9, BEACH_W - 0.4)
		var p := Vector3(cos(t) * r, 0.0, sin(t) * r)
		if _on_pier(p.x, p.z) or _near_pier(p.x, p.z, 1.0): continue
		if is_walkable(p) and _clear_of_solids(Vector2(p.x, p.z), 0.6):
			return p
	return spot("beach")

func random_flats_point(rng: RandomNumberGenerator) -> Vector3:
	for i in 60:
		var a := rng.randf_range(0.0, TAU)
		var k := sqrt(rng.randf()) * 0.75
		var q := flats_c + flats_u * cos(a) * k * (FLATS_AB.x - 0.6) + _perp(flats_u) * sin(a) * k * (FLATS_AB.y - 0.6)
		if dist_in(q.x, q.y) < WALL_D + 0.6:
			return Vector3(q.x, 0.0, q.y)
	return spot("flats")

func is_walkable(p: Vector3) -> bool:
	var x := p.x; var z := p.z
	if _on_pier(x, z): return true
	if _in_flats(x, z, 0.6) and dist_in(x, z) < WALL_D + 0.8:
		return _low_tide()
	if dist_in(x, z) < WALL_D + 0.35: return false
	if not _unlocked("harbour") and _in_harbour_zone(x, z): return false
	if absf(x - RAMP_X) < RAMP_HW + 0.15 and z > RAMP_Z0 - 0.3 and z < HILL_GATE_Z:
		return _unlocked("hill") and absf(x - RAMP_X) < RAMP_HW - 0.2
	var dh := Vector2(x, z).distance_to(HILL_C)
	if dh < HILL_BASE + 0.2:
		if not (_unlocked("hill") and dh < HILL_R - 0.25): return false
	return _clear_of_solids(Vector2(x, z), 0.1)

## True on the wet strip at the waterline (feet splash) and on the exposed tide flats near their edge.
func is_shallow(p: Vector3) -> bool:
	if _on_pier(p.x, p.z): return false
	var d := dist_in(p.x, p.z)
	if _in_flats(p.x, p.z, 0.0) and d < WALL_D + 0.8:
		return _ellipse_k(p.x, p.z) > 0.6
	return d < 1.7 and d > -0.5

## Re-reads GameState.lanterns: opens gates, lights the lantern glass. Safe to call any time.
func refresh_unlocks() -> void:
	for id in ["harbour", "hill"]:
		var open := _unlocked(id)
		var gate: Node3D = _harbour_gate if id == "harbour" else _hill_gate
		if is_instance_valid(gate):
			var was_open: bool = _unlocked_now.get(id, false)
			_set_body_enabled(gate, not open)
			if open and not was_open and gate.visible and _unlocked_now.has(id):
				var tw := create_tween()
				tw.tween_property(gate, "scale", Vector3(1, 0.01, 1), 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
				tw.tween_callback(func(): gate.visible = false)
			else:
				gate.visible = not open
				gate.scale = Vector3.ONE
		_unlocked_now[id] = open
		var gm: StandardMaterial3D = _lantern_glass.get(id)
		if gm:
			gm.emission_enabled = open
			gm.albedo_color = Color("ffe6a8") if open else Color("aab3c8")
			gm.emission = Color("ffd07a")
			gm.emission_energy_multiplier = 2.2

func lantern_node(id: String) -> Node3D:
	var n = _lanterns.get(id)
	if n == null:
		n = _lanterns.get(id.trim_prefix("lantern_"))
	return n if is_instance_valid(n) else null

# ================================================================ geometry helpers
static func _adiff(a: float, b: float) -> float:
	return wrapf(a - b, -PI, PI)

static func shore_r(t: float) -> float:
	var r := BASE_R
	for w in SHORE_WAVES: r += w[0] * sin(w[1] * t + w[2])
	for b in SHORE_BUMPS: r += b[0] * exp(-pow(_adiff(t, b[1]) / b[2], 2.0))
	return r

## Distance inland from the waterline (negative = in the sea).
static func dist_in(x: float, z: float) -> float:
	return shore_r(atan2(z, x)) - sqrt(x * x + z * z)

static func _dir(a: float) -> Vector2:
	return Vector2(cos(a), sin(a))

static func _perp(v: Vector2) -> Vector2:
	return Vector2(-v.y, v.x)

func _glsl_shore() -> String:
	var s := "float lb_adiff(float a, float b) { return mod(a - b + 3.14159265, 6.2831853) - 3.14159265; }\n"
	s += "float shore_r(float t) {\n\tfloat r = %.4f;\n" % BASE_R
	for w in SHORE_WAVES: s += "\tr += %.4f * sin(%.4f * t + %.4f);\n" % [w[0], w[1], w[2]]
	for b in SHORE_BUMPS: s += "\tr += %.4f * exp(-pow(lb_adiff(t, %.4f) / %.4f, 2.0));\n" % [b[0], b[1], b[2]]
	s += "\treturn r;\n}\n"
	return s

func _low_tide() -> bool:
	if _args.has("tide"): return _args["tide"] == "low"
	return GameState.low_tide()

func _unlocked(id: String) -> bool:
	if _args.has("unlock") and id in str(_args["unlock"]).split(","): return true
	return GameState.lanterns.has(id) and bool(GameState.lanterns.get(id, false))

func _on_pier(x: float, z: float) -> bool:
	return absf(x - PIER_X) <= PIER_HW and z >= pier_z0 - 0.5 and z <= pier_z1

func _near_pier(x: float, z: float, m: float) -> bool:
	return absf(x - PIER_X) <= PIER_HW + m and z >= pier_z0 - 1.5 - m and z <= pier_z1 + m

func _ellipse_k(x: float, z: float) -> float:
	var q := Vector2(x, z) - flats_c
	return Vector2(q.dot(flats_u) / FLATS_AB.x, q.dot(_perp(flats_u)) / FLATS_AB.y).length()

func _in_flats(x: float, z: float, shrink: float) -> bool:
	var q := Vector2(x, z) - flats_c
	var a := FLATS_AB.x - shrink; var b := FLATS_AB.y - shrink
	return pow(q.dot(flats_u) / a, 2) + pow(q.dot(_perp(flats_u)) / b, 2) < 1.0

func _in_harbour_zone(x: float, z: float) -> bool:
	var p := Vector2(x, z); var d := _dir(PEN_A)
	return p.dot(d) > GATE_D - 0.25 and absf(p.dot(_perp(d))) < 14.0

func _clear_of_solids(p: Vector2, m: float) -> bool:
	for r in _rects:
		if (r as Rect2).grow(m).has_point(p): return false
	for b in _blocks:
		if p.distance_to(Vector2(b.x, b.y)) < b.z + m: return false
	return true

func _dist_to_paths(p: Vector2) -> float:
	var best := 999.0
	for pa in _paths:
		var pts: PackedVector2Array = pa[0]
		for i in pts.size() - 1:
			var c := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
			best = minf(best, p.distance_to(c) - float(pa[1]))
	return best

## Free for scatter: grass/sand rules, away from roads, spots, buildings, hill, pier, and other solids.
func _free(p: Vector2, r: float, min_d: float, max_d := 99.0, gap := 1.4) -> bool:
	var d := dist_in(p.x, p.y)
	if d < min_d or d > max_d: return false
	if _dist_to_paths(p) < r + 0.25: return false
	if p.distance_to(LOOP_C) < PLAZA_R + r + 0.2: return false
	if p.distance_to(HILL_C) < HILL_BASE + r + 0.3: return false
	if absf(p.x - RAMP_X) < RAMP_HW + r + 0.6 and p.y > RAMP_Z0 - 1.0 and p.y < HILL_GATE_Z + 1.4: return false
	if _near_pier(p.x, p.y, r + 0.8): return false
	if _in_flats(p.x, p.y, -0.8): return false
	for k in _spots:
		if p.distance_to(Vector2(_spots[k].x, _spots[k].z)) < r + 1.5: return false
	for rr in _rects:
		if (rr as Rect2).grow(r + gap).has_point(p): return false
	for b in _blocks:
		if p.distance_to(Vector2(b.x, b.y)) < b.z + r + gap: return false
	return true

# ================================================================ collision helpers
func _col_box(body: StaticBody3D, center: Vector3, size: Vector3, rot_y := 0.0, rot_x := 0.0) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = size
	cs.shape = bs; cs.position = center; cs.rotation = Vector3(rot_x, rot_y, 0)
	body.add_child(cs)
	return cs

func _col_cyl(body: StaticBody3D, ground: Vector3, r: float, h := 2.0) -> void:
	var cs := CollisionShape3D.new()
	var c := CylinderShape3D.new(); c.radius = r; c.height = h
	cs.shape = c; cs.position = ground + Vector3(0, h * 0.5, 0)
	body.add_child(cs)

## Solid round obstacle: collision + is_walkable block.
func _solid_round(p: Vector3, r: float, h := 2.0) -> void:
	_col_cyl(_solid, p, r, h)
	_blocks.append(Vector3(p.x, p.z, r))

## Solid axis-aligned-ish footprint (rotation is applied to the collider; the walk rect is its AABB).
func _solid_rect(center: Vector3, size: Vector3, rot_y := 0.0) -> void:
	_col_box(_solid, center + Vector3(0, size.y * 0.5, 0), size, rot_y)
	var b := Basis(Vector3.UP, rot_y)
	var hx := absf(b.x.x) * size.x * 0.5 + absf(b.z.x) * size.z * 0.5
	var hz := absf(b.x.z) * size.x * 0.5 + absf(b.z.z) * size.z * 0.5
	_rects.append(Rect2(center.x - hx, center.z - hz, hx * 2.0, hz * 2.0))

## Straight wall of boxes between two ground points (fences, invisible walls).
func _col_line(body: StaticBody3D, a: Vector3, b: Vector3, h := 1.2, thick := 0.3) -> void:
	var d := b - a; d.y = 0.0
	var L := d.length()
	if L < 0.01: return
	_col_box(body, (a + b) * 0.5 + Vector3(0, h * 0.5, 0), Vector3(L + thick, h, thick), atan2(-d.z, d.x))

func _set_body_enabled(root: Node, on: bool) -> void:
	for c in root.find_children("*", "CollisionShape3D", true, false):
		(c as CollisionShape3D).set_deferred("disabled", not on)

# ================================================================ build
func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=", true, 1)
		if kv.size() == 2: _args[kv[0]] = kv[1]
	Toys.ensure_globals()
	_rng.seed = 20251121
	_static = Node3D.new(); _static.name = "Static"; add_child(_static)
	_solid = StaticBody3D.new(); _solid.name = "Solids"; add_child(_solid)
	_layout()
	_build_ground()
	_build_sea()
	_build_hill()
	_build_roads()
	_build_town()
	_build_pier()
	_build_lighthouse()
	_build_beach_props()
	_build_lanterns()
	_build_gates()
	_build_flats()
	_scatter()
	_build_backdrop()
	_build_life()
	_build_sea_wall()
	Toys.bake(_static, 12.0)
	for g in [_hill_gate, _harbour_gate]:
		Toys.bake(g, 50.0)
	_build_ao()
	refresh_unlocks()
	if _args.get("test", "") == "island":
		_setup_test()

func setup(m) -> void:
	main = m
	if _args.get("test", "") == "island":
		call_deferred("_apply_test_view")

# ---------------------------------------------------------------- layout & spots
func _loop_point(a: float, off := 0.0) -> Vector2:
	return LOOP_C + Vector2(cos(a) * (LOOP_R.x + off), sin(a) * (LOOP_R.y + off))

func _layout() -> void:
	# pier: starts on the sand, runs south into the sea
	var zs := 5.0
	while dist_in(PIER_X, zs) > 0.0 and zs < 40.0: zs += 0.05
	pier_z0 = zs - 3.2
	pier_z1 = zs + 7.5
	# tide flats
	flats_u = _dir(FLATS_A)
	flats_c = flats_u * (shore_r(FLATS_A) + 2.2)
	var pen := _dir(PEN_A)
	var pen_tip_r := shore_r(PEN_A)
	var lh := _dir(PEN_A - 0.07) * (pen_tip_r - 3.6)
	var rocks_a := PEN_A + 0.12
	var rocks := _dir(rocks_a) * (shore_r(rocks_a) - WALL_D - 1.0)
	var beach_a := 1.45
	var beach := _dir(beach_a) * (shore_r(beach_a) - WALL_D - 1.4)
	var home_door := HOME_POS + Vector3(3.6 * 0.22, 0, 1.5 + 0.75)
	var shop_door := SHOP_POS + Vector3(3.8 * 0.22, 0, 1.5 + 0.7)
	var bf := Vector3(sin(BOARD_ROT), 0, cos(BOARD_ROT))
	_spots = {
		"home": home_door,
		"porch": HOME_POS + Vector3(-0.85, 0, 1.5 + 0.75),
		"plaza": Vector3(LOOP_C.x, 0, LOOP_C.y + 2.3),
		"shop": shop_door,
		"shop_counter": SHOP_POS + Vector3(-3.8 * 0.22, 0, 1.5 + 1.15),
		"board": BOARD_POS + bf * 0.95,
		"pier": Vector3(PIER_X, 0, pier_z0 + 1.0),
		"pier_end": Vector3(PIER_X, 0, pier_z1 - 0.9),
		"beach": Vector3(beach.x, 0, beach.y),
		"rocks": Vector3(rocks.x, 0, rocks.y),
		"lighthouse": Vector3(lh.x, 0, lh.y) - Vector3(pen.x, 0, pen.y) * 2.2,
		"hill": Vector3(HILL_C.x + 0.9, HILL_TOP, HILL_C.y + 1.7),
		"flats": Vector3(flats_c.x, 0, flats_c.y) - Vector3(flats_u.x, 0, flats_u.y) * 0.8,
		"lantern_harbour": Vector3(PIER_X - 2.6, 0, pier_z0 + 0.4),
		"lantern_hill": Vector3(-10.9, 0, 7.4),
		"spawn": Vector3(-4.0, 0, -4.7),
	}
	set_meta("lighthouse_pos", Vector3(lh.x, 0, lh.y))
	# roads and paths (for scatter clearance)
	var loop := PackedVector2Array()
	for i in 97: loop.append(_loop_point(TAU * i / 96.0))
	_paths.append([loop, ROAD_W * 0.5])
	_paths.append([_pier_path(), 0.8])
	_paths.append([_lighthouse_path(), 0.7])
	_paths.append([_hill_path(), 0.7])
	_paths.append([PackedVector2Array([Vector2(home_door.x, home_door.z), Vector2(home_door.x, home_door.z + 1.6)]), 0.6])
	_paths.append([PackedVector2Array([Vector2(shop_door.x - 0.8, shop_door.z), Vector2(shop_door.x - 0.8, shop_door.z + 1.6)]), 1.1])

func _pier_path() -> PackedVector2Array:
	var a := _loop_point(deg_to_rad(55.0))
	return PackedVector2Array([a, Vector2(6.8, 9.4), Vector2(PIER_X, pier_z0 - 1.0), Vector2(PIER_X, pier_z0 + 0.4)])

func _lighthouse_path() -> PackedVector2Array:
	var d := _dir(PEN_A)
	var lh: Vector3 = get_meta("lighthouse_pos")
	return PackedVector2Array([_loop_point(deg_to_rad(-38.0)), Vector2(9.8, -6.6), d * (GATE_D - 1.5), d * (GATE_D + 1.0), Vector2(lh.x, lh.z) - d * 1.4])

func _hill_path() -> PackedVector2Array:
	return PackedVector2Array([_loop_point(deg_to_rad(158.0)), Vector2(-9.6, 8.6), Vector2(RAMP_X + 1.0, 8.8), Vector2(RAMP_X, HILL_GATE_Z + 0.2)])

# ---------------------------------------------------------------- ground
func _land_y(d: float) -> float:
	if d >= 1.1: return 0.0
	if d >= -0.2: return lerpf(-0.4, 0.0, smoothstep(0.0, 1.0, (d + 0.2) / 1.3))
	return maxf(-0.4 + d * 0.3, -2.2)

func _ground_shader(mode: int) -> ShaderMaterial:
	var code := """
shader_type spatial;
render_mode specular_schlick_ggx;
global uniform float lb_wet;
uniform float mode = 0.0;
uniform sampler2D ao_tex : filter_linear, repeat_disable, hint_default_white;
uniform vec3 ao_rect = vec3(-36.0, -36.0, 72.0);
uniform vec3 grass_a : source_color = vec3(0.56, 0.79, 0.49);
uniform vec3 grass_b : source_color = vec3(0.66, 0.85, 0.53);
uniform vec3 grass_c : source_color = vec3(0.45, 0.70, 0.47);
uniform vec3 sand_a : source_color = vec3(0.96, 0.86, 0.68);
uniform vec3 sand_wet : source_color = vec3(0.80, 0.70, 0.56);
varying vec3 wpos;
#COMMON
#SHORE
#LIGHT
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 xz = wpos.xz;
	float r = length(xz); float th = atan(xz.y, xz.x);
	float d = shore_r(th) - r;
	float n1 = lb_noise(xz * 0.3); float n2 = lb_noise(xz * 1.2 + 3.0); float n3 = lb_noise(xz * 4.5 + 9.0);
	float edge = 3.4 + 0.35 * sin(th * 9.0) + 0.5 * (n2 - 0.5);
	float gw = smoothstep(edge - 0.18, edge + 0.18, d);
	if (mode > 0.5 && mode < 1.5) gw = 1.0;
	if (mode > 1.5) gw = 0.0;
	vec3 grass = mix(grass_a, grass_b, smoothstep(0.3, 0.75, n1));
	grass = mix(grass, grass_c, 0.35 * smoothstep(0.55, 0.85, n3));
	grass *= 0.95 + 0.08 * n2;
	vec2 g = xz * 2.4; vec2 cell = floor(g); float h = lb_hash(cell);
	if (h > 0.93) {
		vec2 o = vec2(lb_hash(cell + 1.3), lb_hash(cell + 2.7)) - 0.5;
		float dd = length(fract(g) - 0.5 - o * 0.5);
		vec3 fc = h > 0.977 ? vec3(0.98, 0.70, 0.72) : (h > 0.953 ? vec3(1.0, 0.94, 0.68) : vec3(1.0, 0.98, 0.95));
		grass = mix(grass, fc, smoothstep(0.075, 0.045, dd));
	}
	vec3 sand = sand_a * (0.96 + 0.06 * n2);
	float sp = lb_hash(floor(xz * 16.0));
	sand *= sp > 0.93 ? 0.9 : (sp < 0.05 ? 1.04 : 1.0);
	float wave = 0.5 + 0.5 * sin(TIME * 0.9 + th * 3.0);
	float wet = 1.0 - smoothstep(0.5 + 0.6 * wave, 1.3 + 0.6 * wave, d);
	if (mode > 0.5 && mode < 1.5) wet = 0.0;
	if (mode > 1.5) wet = 0.6;
	sand = mix(sand, sand_wet, wet * 0.75);
	float fl = smoothstep(0.1, 0.0, abs(d - (0.15 + 0.6 * wave))) * (0.5 + 0.5 * n3) * (mode > 1.5 ? 0.0 : 1.0);
	sand = mix(sand, vec3(1.0), fl * 0.55);
	vec3 col = mix(sand, grass, gw);
	vec2 auv = (xz - ao_rect.xy) / ao_rect.z;
	float ao = texture(ao_tex, auv).r;
	col *= ao;
	col *= 1.0 - 0.3 * lb_clouds(xz);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.3, wet * (1.0 - gw));
	SPECULAR = 0.25 + 0.35 * wet * (1.0 - gw);
}
"""
	var sh := Shader.new()
	sh.code = code.replace("#COMMON", Toys.glsl_common()).replace("#SHORE", _glsl_shore()).replace("#LIGHT", Toys.glsl_light())
	var m := ShaderMaterial.new(); m.shader = sh
	m.set_shader_parameter("mode", float(mode))
	return m

var _ground_mats: Array = []

func _build_ground() -> void:
	var NA := 220
	var rings: Array = []   # each: [kind, value] kind 0 = fraction of inner radius, 1 = d offset
	for u in [0.0, 0.2, 0.4, 0.6, 0.8]: rings.append([0, u])
	var d := 8.0
	while d >= -7.0:
		rings.append([1, d]); d -= 0.33
	var v := PackedVector3Array(); var n := PackedVector3Array(); var idx := PackedInt32Array()
	for ring in rings:
		for k in NA + 1:
			var t := TAU * float(k) / NA
			var s := shore_r(t)
			var r: float; var dd: float
			if ring[0] == 0:
				r = float(ring[1]) * (s - 8.0); dd = s - r
			else:
				dd = float(ring[1]); r = s - dd
			var y := _land_y(dd)
			var slope := (_land_y(dd + 0.05) - _land_y(dd - 0.05)) / 0.1
			v.append(Vector3(cos(t) * r, y, sin(t) * r))
			n.append(Vector3(cos(t) * slope, 1.0, sin(t) * slope).normalized())
	for i in rings.size() - 1:
		for k in NA:
			var a := i * (NA + 1) + k
			Toys._quad(idx, v, n, a, a + 1, a + NA + 2, a + NA + 1)
	var mi := MeshInstance3D.new(); mi.name = "Ground"
	mi.mesh = Toys.arrays_mesh(v, n, idx)
	var gm := _ground_shader(0); _ground_mats.append(gm)
	mi.material_override = gm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# one big flat floor collider; walls and hill sit on it
	var floor_body := StaticBody3D.new(); floor_body.name = "Floor"; add_child(floor_body)
	_col_box(floor_body, Vector3(0, -0.5, 0), Vector3(140, 1.0, 140))

# ---------------------------------------------------------------- sea
func _build_sea() -> void:
	var code := """
shader_type spatial;
render_mode specular_schlick_ggx;
global uniform float lb_day;
global uniform float lb_wet;
uniform vec3 shallow : source_color = vec3(0.55, 0.86, 0.86);
uniform vec3 deep : source_color = vec3(0.27, 0.62, 0.78);
uniform vec3 far_col : source_color = vec3(0.36, 0.62, 0.80);
uniform vec3 foam : source_color = vec3(1.0, 1.0, 1.0);
uniform vec4 flats = vec4(0.0, 0.0, 1.0, 0.0);
uniform vec2 flats_ab = vec2(4.6, 3.0);
uniform float flats_amt = 0.0;
varying vec3 wpos;
#COMMON
#SHORE
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	float fade = 1.0 - smoothstep(45.0, 70.0, length(w.xz));
	float a1 = w.x * 0.32 + t * 1.1; float a2 = w.z * 0.41 - t * 0.9; float a3 = (w.x + w.z) * 0.7 + t * 1.7;
	VERTEX.y += (sin(a1) * 0.05 + sin(a2) * 0.045 + sin(a3) * 0.02) * fade;
	float dx = (cos(a1) * 0.016 + cos(a3) * 0.014) * fade;
	float dz = (cos(a2) * 0.0185 + cos(a3) * 0.014) * fade;
	NORMAL = normalize(vec3(-dx, 1.0, -dz));
	wpos = w;
}
void fragment() {
	vec2 xz = wpos.xz;
	float r = length(xz); float th = atan(xz.y, xz.x);
	float d = r - shore_r(th);
	float depth = smoothstep(-0.5, 10.0, d);
	vec3 col = mix(shallow, deep, depth);
	col = mix(col, far_col, smoothstep(25.0, 90.0, d));
	float fn = lb_noise(xz * 1.6 + vec2(TIME * 0.25, TIME * 0.15));
	float rip = lb_noise(xz * 0.9 - vec2(TIME * 0.12, TIME * 0.2));
	col += (1.0 - depth) * 0.07 * smoothstep(0.55, 0.85, rip);
	float wave = 0.5 + 0.5 * sin(TIME * 0.9 + th * 3.0);
	float f = (1.0 - smoothstep(0.1 + 0.35 * wave, 0.6 + 0.45 * wave, d)) * (0.65 + 0.35 * fn);
	float ph = fract(d * 0.33 - TIME * 0.1);
	float lines = smoothstep(0.05, 0.0, abs(ph - 0.5)) * (1.0 - smoothstep(1.0, 4.5, d)) * smoothstep(0.35, 0.7, fn) * step(0.0, d);
	f = max(f, lines * 0.55);
	if (flats_amt > 0.01) {
		vec2 q = xz - flats.xy;
		vec2 u = flats.zw;
		vec2 e = vec2(dot(q, u) / flats_ab.x, dot(q, vec2(-u.y, u.x)) / flats_ab.y);
		float k = length(e);
		float ring = smoothstep(0.12, 0.0, abs(k - (0.88 + 0.06 * wave))) * (0.6 + 0.4 * fn);
		f = max(f, ring * flats_amt);
		col = mix(col, shallow * 1.04, (1.0 - smoothstep(0.9, 1.4, k)) * 0.6 * flats_amt);
	}
	vec2 g = xz * 2.2 + vec2(TIME * 0.35, -TIME * 0.22);
	float gh = lb_hash(floor(g));
	float glint = step(0.975, gh) * smoothstep(0.3, 0.0, length(fract(g) - 0.5)) * (0.5 + 0.5 * sin(TIME * 4.0 + gh * 50.0));
	glint *= lb_day * (1.0 - smoothstep(30.0, 60.0, d)) * (1.0 - lb_wet);
	ALBEDO = mix(col, foam, f) * (1.0 - 0.25 * lb_clouds(xz));
	EMISSION = vec3(glint) * 1.3;
	ROUGHNESS = mix(0.06 + 0.15 * lb_wet, 0.8, f);
	SPECULAR = 0.55;
}
"""
	var sh := Shader.new()
	sh.code = code.replace("#COMMON", Toys.glsl_common()).replace("#SHORE", _glsl_shore())
	_sea_mat = ShaderMaterial.new(); _sea_mat.shader = sh
	_sea_mat.set_shader_parameter("flats", Vector4(flats_c.x, flats_c.y, flats_u.x, flats_u.y))
	_sea_mat.set_shader_parameter("flats_ab", FLATS_AB)
	# polar sea: dense near the island, sparse far out
	var radii: Array = []
	var r := 0.0
	while r < 62.0:
		radii.append(r); r += 0.9
	for rr in [70.0, 85.0, 105.0, 135.0, 175.0, 230.0, 320.0, 450.0]: radii.append(rr)
	var NA := 160
	var v := PackedVector3Array(); var n := PackedVector3Array(); var idx := PackedInt32Array()
	for rr in radii:
		for k in NA + 1:
			var t := TAU * float(k) / NA
			v.append(Vector3(cos(t) * rr, 0, sin(t) * rr)); n.append(Vector3.UP)
	for i in radii.size() - 1:
		for k in NA:
			var a := i * (NA + 1) + k
			Toys._quad(idx, v, n, a, a + 1, a + NA + 2, a + NA + 1)
	var mi := MeshInstance3D.new(); mi.name = "Sea"
	mi.mesh = Toys.arrays_mesh(v, n, idx)
	mi.material_override = _sea_mat
	mi.position.y = SEA_Y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 2.0
	add_child(mi)

# ---------------------------------------------------------------- hill
func _build_hill() -> void:
	var prof := PackedVector2Array([Vector2(0, HILL_TOP + 0.02), Vector2(1.6, HILL_TOP + 0.03), Vector2(2.9, HILL_TOP),
		Vector2(3.35, HILL_TOP - 0.12), Vector2(3.6, HILL_TOP - 0.45), Vector2(3.8, 0.9), Vector2(4.0, 0.3),
		Vector2(HILL_BASE, 0.02), Vector2(HILL_BASE + 0.25, -0.1)])
	var rev := PackedVector2Array()
	for i in range(prof.size() - 1, -1, -1): rev.append(prof[i])
	var mi := MeshInstance3D.new(); mi.name = "Hill"
	mi.mesh = Toys.lathe(rev, 40)
	var gm := _ground_shader(1); _ground_mats.append(gm)
	mi.material_override = gm
	mi.position = Vector3(HILL_C.x, 0, HILL_C.y)
	add_child(mi)
	# outline for the hill silhouette
	var ol := MeshInstance3D.new(); ol.mesh = mi.mesh; ol.material_override = Toys.outline_mat(0.03, Toys.INK.lerp(Color("4f7a4a"), 0.4))
	ol.position = mi.position; ol.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(ol)
	# collision: convex hull of the profile (steep sides, flat top)
	var pts := PackedVector3Array()
	for p in [Vector2(HILL_R + 0.05, HILL_TOP), Vector2(3.6, HILL_TOP - 0.45), Vector2(3.8, 0.9), Vector2(4.0, 0.3), Vector2(4.1, 0.0)]:
		for k in 24:
			var t := TAU * k / 24.0
			pts.append(Vector3(cos(t) * p.x, p.y, sin(t) * p.x))
	var body := StaticBody3D.new(); body.name = "HillBody"; body.position = mi.position; add_child(body)
	var cs := CollisionShape3D.new(); var cv := ConvexPolygonShape3D.new(); cv.points = pts; cs.shape = cv; body.add_child(cs)
	# ramp (smooth collision slope + stone steps + earth bank)
	var L := RAMP_Z1 - RAMP_Z0
	var ang := atan2(HILL_TOP, L)
	var slope_len := sqrt(L * L + HILL_TOP * HILL_TOP)
	var up := Vector3(0, cos(ang), sin(ang))
	var mid := Vector3(RAMP_X, HILL_TOP * 0.5, (RAMP_Z0 + RAMP_Z1) * 0.5)
	_col_box(_solid, mid - up * 0.25, Vector3(RAMP_HW * 2.0, 0.5, slope_len + 0.6), 0.0, ang)
	var bank := PrismMesh.new(); bank.left_to_right = 0.0; bank.size = Vector3(L + 0.4, HILL_TOP + 0.05, RAMP_HW * 2.0 + 0.5)
	Toys.add(bank, Toys.pmat(Color("93c98a"), Toys.PAT_LEAF), Vector3(RAMP_X, (HILL_TOP + 0.05) * 0.5 - 0.06, (RAMP_Z0 + RAMP_Z1) * 0.5 + 0.2), _static, Vector3.ONE, Vector3(0, -PI / 2, 0))
	var steps := int(L / 0.55)
	for i in steps:
		var z := RAMP_Z0 + (i + 0.5) * L / steps
		var y := ground_y(RAMP_X, z)
		Toys.add(Toys.rbox(RAMP_HW * 2.0 - 0.2, 0.12, L / steps - 0.06, 0.04), Toys.pmat(Color("e8d8bf"), Toys.PAT_ROCK), Vector3(RAMP_X, y + 0.0, z), _static, Vector3.ONE, Vector3(ang, 0, 0))
	# railings along the ramp (also stop riders from stepping onto it from the side)
	for sx in [-1.0, 1.0]:
		var x: float = RAMP_X + sx * (RAMP_HW + 0.12)
		var n := 6
		for i in n + 1:
			var z: float = RAMP_Z0 + 0.3 + (RAMP_Z1 + 0.3 - RAMP_Z0 - 0.3) * i / n
			var y := ground_y(RAMP_X, clampf(z, RAMP_Z0, RAMP_Z1))
			Toys.add(Toys.rcyl(0.06, 0.07, 0.8, 0.03, 8), Toys.pmat(Color("c99a6e"), Toys.PAT_WOOD), Vector3(x, y + 0.4, z), _static)
		var a := Vector3(x, HILL_TOP + 0.7, RAMP_Z0 + 0.3); var b := Vector3(x, 0.7, RAMP_Z1 + 0.3)
		var rail := Toys.add(Toys.rcyl(0.04, 0.04, a.distance_to(b), 0.02, 8), Toys.pmat(Color("c99a6e"), Toys.PAT_WOOD), (a + b) * 0.5, _static)
		rail.rotation = Vector3(PI / 2 - ang, 0, 0)
		_col_line(_solid, Vector3(x, 0, RAMP_Z0 + 0.2), Vector3(x, 0, HILL_GATE_Z), 3.0, 0.2)
	# hill top: windmill, bench, tree, flowers
	var top := Vector3(HILL_C.x, HILL_TOP, HILL_C.y)
	_build_windmill(top + Vector3(-1.1, 0, -1.2))
	Toys.bench(_static, top + Vector3(1.6, 0, -1.4), -0.9)
	_col_box(_solid, top + Vector3(1.6, 0.5, -1.4), Vector3(1.7, 1.0, 0.7), -0.9)
	_blocks.append(Vector3(top.x + 1.6, top.z - 1.4, 0.8))
	Toys.tree(_static, top + Vector3(-2.2, 0, 1.3), 0.85, Color("86c393"))
	_col_cyl(_solid, top + Vector3(-2.2, 0, 1.3), 0.3, 2.0)
	_blocks.append(Vector3(top.x - 2.2, top.z + 1.3, 0.4))
	for i in 14:
		var a := i * 2.39996; var rr := 1.0 + fmod(i * 0.77, 1.9)
		var p := top + Vector3(cos(a) * rr, 0, sin(a) * rr)
		if Vector2(p.x, p.z).distance_to(Vector2(top.x - 1.1, top.z - 1.2)) < 1.4: continue
		if Vector2(p.x, p.z).distance_to(Vector2(_spots["hill"].x, _spots["hill"].z)) < 0.8: continue
		Toys.flower(_static, p, [Color("f4a9a8"), Color("fff1b8"), Color("c9b6e4"), Color("ffffff")][i % 4])

func _build_windmill(p: Vector3) -> void:
	var g := Toys.group(p, _static)
	var prof := PackedVector2Array([Vector2(0, 0), Vector2(0.95, 0.0), Vector2(0.98, 0.1), Vector2(0.82, 1.4), Vector2(0.68, 2.5), Vector2(0.62, 2.6), Vector2(0, 2.6)])
	Toys.add(Toys.lathe(prof, 24), Toys.pmat(Color("fff3e2"), Toys.PAT_WALL), Vector3.ZERO, g)
	var cap := PackedVector2Array([Vector2(0, 0), Vector2(0.78, 0.0), Vector2(0.72, 0.3), Vector2(0.45, 0.7), Vector2(0.12, 0.92), Vector2(0, 0.95)])
	Toys.add(Toys.lathe(cap, 24), Toys.pmat(Color("e8857f"), Toys.PAT_ROOF), Vector3(0, 2.55, 0), g)
	Toys.add(Toys.rbox(0.55, 0.85, 0.12, 0.05), Toys.pmat(Color("9a6e5a"), Toys.PAT_WOOD), Vector3(0, 0.45, 0.93), g, Vector3.ONE, Vector3(0.1, 0, 0))
	Toys.add(Toys.rbox(0.4, 0.4, 0.08, 0.04), Toys.window_mat(), Vector3(0, 1.6, 0.76), g, Vector3.ONE, Vector3(0.12, 0, 0))
	_solid_round(p, 1.0, 3.0)
	_blades = Node3D.new(); _blades.position = p + Vector3(0, 2.4, 0.85); add_child(_blades)
	var bm := Toys.mat(Color("fffaf2"), 0.8, 0.02)
	var hub := Toys.mat(Color("9a7058"), 0.7, 0.02)
	Toys.add(Toys.rcyl(0.14, 0.14, 0.22, 0.05, 12), hub, Vector3.ZERO, _blades, Vector3.ONE, Vector3(PI / 2, 0, 0))
	for i in 4:
		var arm := Node3D.new(); arm.rotation.z = i * PI / 2; _blades.add_child(arm)
		Toys.add(Toys.rbox(0.07, 1.5, 0.05, 0.02), hub, Vector3(0, 0.8, 0.02), arm)
		Toys.add(Toys.rbox(0.34, 1.2, 0.03, 0.02), bm, Vector3(0.18, 0.95, 0.0), arm)

# ---------------------------------------------------------------- roads, plaza, paths
func _build_roads() -> void:
	var loop := PackedVector3Array()
	for i in 96:
		var p := _loop_point(TAU * i / 96.0)
		loop.append(Vector3(p.x, 0, p.y))
	Toys.add(Toys.ribbon(loop, ROAD_W, true, 0.035, 0.14), Toys.pmat(Color("d6cbe0"), Toys.PAT_COBBLE, 0.9, 0.0), Vector3.ZERO, _static)
	# soft centre dashes
	for i in 24:
		var a0 := TAU * (i + 0.15) / 24.0; var a1 := TAU * (i + 0.55) / 24.0
		var p0 := _loop_point(a0); var p1 := _loop_point(a1)
		var mid := (p0 + p1) * 0.5; var dir := p1 - p0
		Toys.add(Toys.rbox(dir.length(), 0.03, 0.14, 0.012), Toys.pmat(Color("fff8ee"), Toys.PAT_PLAIN, 0.9, 0.0), Vector3(mid.x, 0.045, mid.y), _static, Vector3.ONE, Vector3(0, atan2(-dir.y, dir.x), 0))
	# curb stones on both edges
	for side in [-1.0, 1.0]:
		var pts := PackedVector3Array()
		for i in 96:
			var p := _loop_point(TAU * i / 96.0, side * (ROAD_W * 0.5 + 0.1))
			pts.append(Vector3(p.x, 0, p.y))
		Toys.add(Toys.ribbon(pts, 0.18, true, 0.06, 0.06), Toys.pmat(Color("f2ece6"), Toys.PAT_PLAIN, 0.9, 0.0), Vector3.ZERO, _static)
	# plaza: cobbled disc with a ring of darker stones
	Toys.add(Toys.rcyl(PLAZA_R, PLAZA_R + 0.08, 0.08, 0.03, 48), Toys.pmat(Color("f1e1c8"), Toys.PAT_COBBLE, 0.9, 0.0), Vector3(LOOP_C.x, 0.0, LOOP_C.y), _static)
	Toys.add(Toys.torus(PLAZA_R - 0.12, PLAZA_R + 0.12), Toys.pmat(Color("d9c4a6"), Toys.PAT_COBBLE, 0.9, 0.0), Vector3(LOOP_C.x, 0.03, LOOP_C.y), _static, Vector3(1, 0.25, 1))
	# plaza spokes to the road
	for a in [PI / 2, -PI / 2, 0.0, PI]:
		var p0 := LOOP_C + _dir(a) * (PLAZA_R - 0.2)
		var p1 := _loop_point(a, -ROAD_W * 0.5)
		_ribbon_path(PackedVector2Array([p0, p1]), 1.6, Color("f1e1c8"), Toys.PAT_COBBLE)
	_ribbon_path(_pier_path(), 1.5, Color("ead8b8"), Toys.PAT_COBBLE)
	_ribbon_path(_lighthouse_path(), 1.3, Color("ead8b8"), Toys.PAT_COBBLE)
	_ribbon_path(_hill_path(), 1.3, Color("ead8b8"), Toys.PAT_COBBLE)
	for i in [4, 5]:
		var pts: PackedVector2Array = _paths[i][0]
		_ribbon_path(pts, float(_paths[i][1]) * 2.0, Color("e6d6c2"), Toys.PAT_COBBLE)
	_build_fountain()

func _ribbon_path(pts2: PackedVector2Array, w: float, c: Color, pat: int) -> void:
	var pts := PackedVector3Array()
	for i in pts2.size() - 1:
		var a := pts2[i]; var b := pts2[i + 1]
		var n := maxi(1, int(a.distance_to(b) / 0.6))
		for k in n:
			var p := a.lerp(b, float(k) / n)
			pts.append(Vector3(p.x, 0, p.y))
	pts.append(Vector3(pts2[pts2.size() - 1].x, 0, pts2[pts2.size() - 1].y))
	Toys.add(Toys.ribbon(pts, w, false, 0.025, 0.12), Toys.pmat(c, pat, 0.9, 0.0), Vector3.ZERO, _static)

func _build_fountain() -> void:
	var p := Vector3(LOOP_C.x, 0, LOOP_C.y)
	var basin := PackedVector2Array([Vector2(0, 0.05), Vector2(1.15, 0.05), Vector2(1.25, 0.12), Vector2(1.3, 0.45), Vector2(1.22, 0.55), Vector2(1.08, 0.5), Vector2(1.02, 0.3), Vector2(0, 0.3)])
	Toys.add(Toys.lathe(basin, 40), Toys.pmat(Color("e9e2ef"), Toys.PAT_ROCK), p, _static)
	var wm := Toys.mat(Color("8fd3dc"), 0.1, 0.0)
	wm.set_meta("nobake", true)
	wm.metallic_specular = 0.8
	var water := Toys.add(Toys.rcyl(1.06, 1.06, 0.04, 0.01, 40), wm, p + Vector3(0, 0.38, 0), self)
	water.set_meta("nobake", true)
	Toys.add(Toys.rcyl(0.16, 0.22, 1.0, 0.05, 16), Toys.pmat(Color("e9e2ef"), Toys.PAT_ROCK), p + Vector3(0, 0.8, 0), _static)
	var bowl := PackedVector2Array([Vector2(0, 1.3), Vector2(0.55, 1.32), Vector2(0.62, 1.42), Vector2(0.5, 1.48), Vector2(0, 1.42)])
	Toys.add(Toys.lathe(bowl, 28), Toys.pmat(Color("e9e2ef"), Toys.PAT_ROCK), p, _static)
	Toys.add(Toys.sphere(0.13, 12), Toys.pmat(Color("e9e2ef"), Toys.PAT_ROCK), p + Vector3(0, 1.6, 0), _static)
	_solid_round(p, 1.3, 1.0)
	# little water spray: soft sprites
	var sp := _sprite_particles(18, 1.1, Color(0.85, 0.95, 1.0, 0.7), 0.16)
	sp.position = p + Vector3(0, 1.55, 0)
	sp.direction = Vector3.UP; sp.spread = 35.0; sp.initial_velocity_min = 1.2; sp.initial_velocity_max = 1.6
	sp.gravity = Vector3(0, -4.0, 0)
	add_child(sp)

# ---------------------------------------------------------------- town
func _build_town() -> void:
	# Mocha's home (warm cream, terracotta roof) with porch
	var home := Toys.house(_static, HOME_POS, 0.0, Color("fbe6cf"), Color("e3866f"), 3.6, 2.7, 3.0)
	_chimney_smoke(home)
	_solid_rect(HOME_POS, Vector3(3.7, 3.0, 3.1))
	var deck_z := HOME_POS.z + 1.5 + 0.62
	Toys.add(Toys.rbox(3.8, 0.1, 1.3, 0.04), Toys.pmat(Color("c99a6e"), Toys.PAT_WOOD), Vector3(HOME_POS.x, 0.04, deck_z), _static)
	for sx in [-1.0, 1.0]:
		var pp := Vector3(HOME_POS.x + sx * 1.75, 0, deck_z + 0.55)
		Toys.add(Toys.rcyl(0.07, 0.08, 2.25, 0.03, 10), Toys.pmat(Color("fff8ee"), Toys.PAT_WOOD), pp + Vector3(0, 1.12, 0), _static)
		_solid_round(pp, 0.12, 2.0)
	Toys.add(Toys.rbox(4.0, 0.12, 1.6, 0.05), Toys.pmat(Color("e3866f"), Toys.PAT_ROOF), Vector3(HOME_POS.x, 2.3, deck_z + 0.1), _static, Vector3.ONE, Vector3(0.18, 0, 0))
	# porch chair + plant pots + mailbox
	var chair := Toys.group(Vector3(HOME_POS.x - 1.45, 0.05, deck_z - 0.25), _static, 0.5)
	Toys.add(Toys.rbox(0.6, 0.1, 0.55, 0.04), Toys.pmat(Color("8fd6c8"), Toys.PAT_WOOD), Vector3(0, 0.42, 0), chair)
	Toys.add(Toys.rbox(0.6, 0.6, 0.08, 0.04), Toys.pmat(Color("8fd6c8"), Toys.PAT_WOOD), Vector3(0, 0.72, -0.26), chair, Vector3.ONE, Vector3(-0.2, 0, 0))
	for x in [-0.25, 0.25]:
		Toys.add(Toys.rbox(0.06, 0.42, 0.5, 0.02), Toys.pmat(Color("6fae9f")), Vector3(x, 0.2, 0), chair)
	_solid_round(Vector3(HOME_POS.x - 1.45, 0, deck_z - 0.25), 0.35, 1.0)
	_pot(Vector3(HOME_POS.x + 1.4, 0.05, deck_z - 0.35), Color("f4a9a8"))
	_pot(Vector3(HOME_POS.x + 2.25, 0.0, deck_z + 0.75), Color("fff1b8"))
	var mb := Toys.group(Vector3(HOME_POS.x - 2.35, 0, deck_z + 0.9), _static)
	Toys.add(Toys.rcyl(0.04, 0.05, 1.0, 0.02, 8), Toys.pmat(Color("9a7058"), Toys.PAT_WOOD), Vector3(0, 0.5, 0), mb)
	Toys.add(Toys.rbox(0.3, 0.26, 0.45, 0.1), Toys.pmat(Color("7fb3e0")), Vector3(0, 1.1, 0), mb)
	Toys.add(Toys.rbox(0.03, 0.18, 0.06, 0.01), Toys.pmat(Color("e8747f"), Toys.PAT_PLAIN, 0.8, 0.0), Vector3(0.17, 1.22, -0.1), mb)
	_solid_round(Vector3(HOME_POS.x - 2.35, 0, deck_z + 0.9), 0.2, 1.3)
	# neighbour cottage
	var nb_pos := Vector3(0.1, 0, -8.8)
	var nb := Toys.house(_static, nb_pos, 0.0, Color("e8e0f6"), Color("9d8fd6"), 2.8, 2.4, 2.6)
	_chimney_smoke(nb)
	_solid_rect(nb_pos, Vector3(2.9, 2.6, 2.7))
	Toys.bush(_static, nb_pos + Vector3(-1.0, 0, 1.75), 0.75, Color("9fd39a"), Color("f4a9a8"))
	_solid_round(nb_pos + Vector3(-1.0, 0, 1.75), 0.55, 1.0)
	# Pip's shop
	_build_shop()
	# east cottage (faces the road)
	var ep := Vector3(12.3, 0, 2.2)
	var eh := Toys.house(_static, ep, -PI / 2, Color("fff0c8"), Color("e8a35c"), 3.2, 2.5, 2.8)
	_chimney_smoke(eh)
	_solid_rect(ep, Vector3(3.3, 2.6, 2.9), -PI / 2)
	# plaza furniture
	for a in [deg_to_rad(200.0), deg_to_rad(-20.0)]:
		var bp := LOOP_C + _dir(a) * (PLAZA_R - 0.7)
		var face := atan2(LOOP_C.x - bp.x, LOOP_C.y - bp.y)
		Toys.bench(_static, Vector3(bp.x, 0.02, bp.y), face)
		_col_box(_solid, Vector3(bp.x, 0.5, bp.y), Vector3(1.7, 1.0, 0.7), face)
		_blocks.append(Vector3(bp.x, bp.y, 0.85))
	# plaza lamps + bunting between them
	var lamp_pts: Array = []
	for i in 4:
		var a := deg_to_rad(45.0 + 90.0 * i)
		var lp := LOOP_C + _dir(a) * (PLAZA_R + 0.9)
		Toys.lamp(_static, Vector3(lp.x, 0, lp.y))
		_solid_round(Vector3(lp.x, 0, lp.y), 0.2, 2.8)
		lamp_pts.append(Vector3(lp.x, 2.75, lp.y))
	for i in 4:
		_bunting(lamp_pts[i], lamp_pts[(i + 1) % 4])
	# road lamps
	for deg in [20.0, 100.0, 140.0, 200.0, 250.0, 300.0, 340.0]:
		var lp := _loop_point(deg_to_rad(deg), ROAD_W * 0.5 + 0.45)
		if _free(lp, 0.2, BEACH_W, 99.0, 0.8):
			Toys.lamp(_static, Vector3(lp.x, 0, lp.y))
			_solid_round(Vector3(lp.x, 0, lp.y), 0.2, 2.8)
	# flower beds around the plaza
	for i in 10:
		var a := deg_to_rad(18.0 + i * 36.0)
		var fp := LOOP_C + _dir(a) * (PLAZA_R + 1.75)
		if absf(_adiff(a, PI / 2)) < 0.3 or absf(_adiff(a, -PI / 2)) < 0.3 or absf(_adiff(a, 0.0)) < 0.3 or absf(_adiff(a, PI)) < 0.3: continue
		for k in 4:
			var q := fp + _dir(a + k * 1.6) * 0.35
			Toys.flower(_static, Vector3(q.x, 0, q.y), [Color("f4a9a8"), Color("fff1b8"), Color("c9b6e4"), Color("ffd2a6")][(i + k) % 4], 1.1)
	# vegetable garden south-west of the loop
	_garden(Vector3(-5.6, 0, 9.8))

func _pot(p: Vector3, fc: Color) -> void:
	Toys.add(Toys.rcyl(0.2, 0.15, 0.32, 0.05, 14), Toys.pmat(Color("d98c6a"), Toys.PAT_ROCK), p + Vector3(0, 0.16, 0), _static)
	Toys.add(Toys.canopy_mesh(0.24, 0.8), Toys.pmat(Color("8cc79a"), Toys.PAT_LEAF, 0.8, 0.02, 0.6), p + Vector3(0, 0.28, 0), _static)
	for i in 3:
		Toys.add(Toys.sphere(0.06, 8), Toys.pmat(fc, Toys.PAT_PLAIN, 0.9, 0.0, 0.6), p + Vector3(cos(i * 2.1) * 0.13, 0.55, sin(i * 2.1) * 0.13), _static)
	_solid_round(Vector3(p.x, 0, p.z), 0.22, 0.8)

func _build_shop() -> void:
	var w := 3.8; var d := 3.0
	var shop := Toys.house(_static, SHOP_POS, 0.0, Color("d9f0e6"), Color("6fb7a8"), w, 2.8, d)
	_chimney_smoke(shop)
	_solid_rect(SHOP_POS, Vector3(w + 0.1, 3.0, d + 0.1))
	var fz := SHOP_POS.z + d * 0.5
	var cx := SHOP_POS.x - w * 0.22
	# counter ledge + crates of goods
	Toys.add(Toys.rbox(1.6, 0.14, 0.55, 0.05), Toys.pmat(Color("c99a6e"), Toys.PAT_WOOD), Vector3(cx, 0.95, fz + 0.3), _static)
	Toys.add(Toys.rbox(1.5, 0.88, 0.45, 0.05), Toys.pmat(Color("fff8ee"), Toys.PAT_WOOD), Vector3(cx, 0.44, fz + 0.25), _static)
	_solid_rect(Vector3(cx, 0, fz + 0.28), Vector3(1.6, 1.0, 0.6))
	for i in 3:
		Toys.add(Toys.sphere(0.12, 10), Toys.pmat([Color("f2b46d"), Color("e8747f"), Color("a9d99a")][i]), Vector3(cx - 0.45 + i * 0.45, 1.1, fz + 0.32), _static)
	# striped awning
	for i in 6:
		var c := Color("fff8ee") if i % 2 == 0 else Color("e8747f")
		Toys.add(Toys.rbox(0.33, 0.07, 1.0, 0.03), Toys.pmat(c, Toys.PAT_PLAIN, 0.9, 0.02, 2.5), Vector3(cx - 0.82 + i * 0.33, 2.15, fz + 0.45), _static, Vector3.ONE, Vector3(0.35, 0, 0))
	# sign board
	Toys.add(Toys.rbox(1.9, 0.48, 0.1, 0.06), Toys.pmat(Color("fff1df"), Toys.PAT_WOOD), Vector3(SHOP_POS.x, 2.62, fz + 0.12), _static)
	var lbl := Label3D.new(); lbl.text = "Pip's General Store"; lbl.font_size = 40; lbl.pixel_size = 0.0055
	lbl.modulate = Color("6b4a3a"); lbl.outline_size = 0; lbl.position = Vector3(SHOP_POS.x, 2.62, fz + 0.18)
	lbl.shaded = false; lbl.double_sided = false
	add_child(lbl)
	# crates by the door
	Toys.crate(_static, Vector3(SHOP_POS.x + w * 0.5 + 0.1, 0, fz - 0.25), 1.0, 0.2)
	Toys.crate(_static, Vector3(SHOP_POS.x + w * 0.5 + 0.12, 0.45, fz - 0.25), 0.8, -0.3, Color("e8c49a"))
	_solid_round(Vector3(SHOP_POS.x + w * 0.5 + 0.1, 0, fz - 0.25), 0.4, 1.0)
	# request board
	var b := Toys.group(BOARD_POS, _static, BOARD_ROT)
	for x in [-0.7, 0.7]:
		Toys.add(Toys.rcyl(0.07, 0.08, 1.9, 0.03, 10), Toys.pmat(Color("9a7058"), Toys.PAT_WOOD), Vector3(x, 0.95, 0), b)
	Toys.add(Toys.rbox(1.55, 1.0, 0.1, 0.05), Toys.pmat(Color("d9b48a"), Toys.PAT_WOOD), Vector3(0, 1.3, 0.02), b)
	Toys.add(Toys.rbox(1.8, 0.12, 0.4, 0.05), Toys.pmat(Color("6fb7a8"), Toys.PAT_ROOF), Vector3(0, 1.95, 0.02), b, Vector3.ONE, Vector3(0.15, 0, 0))
	var notes := [Color("fff8ee"), Color("fde3a7"), Color("cfe8f3")]
	for i in 3:
		Toys.add(Toys.rbox(0.36, 0.42, 0.02, 0.01), Toys.pmat(notes[i], Toys.PAT_PLAIN, 0.9, 0.01, 2.3), Vector3(-0.45 + i * 0.45, 1.3 + (0.06 if i == 1 else -0.02), 0.09), b, Vector3.ONE, Vector3(0, 0, 0.06 * (i - 1)))
		Toys.add(Toys.sphere(0.03, 6), Toys.pmat(Color("e8747f"), Toys.PAT_PLAIN, 0.5, 0.0), Vector3(-0.45 + i * 0.45, 1.48 + (0.06 if i == 1 else -0.02), 0.11), b)
	_solid_rect(BOARD_POS, Vector3(1.7, 2.0, 0.35), BOARD_ROT)

func _garden(c: Vector3) -> void:
	var hw := 1.6; var hd := 1.2
	var corners := [c + Vector3(-hw, 0, -hd), c + Vector3(hw, 0, -hd), c + Vector3(hw, 0, hd), c + Vector3(-hw, 0, hd)]
	for i in 4:
		Toys.fence(_static, corners[i], corners[(i + 1) % 4], Color("fff8ee"), 0.6)
	Toys.add(Toys.rbox(hw * 2 - 0.3, 0.12, hd * 2 - 0.3, 0.06), Toys.pmat(Color("a8805f"), Toys.PAT_ROCK, 0.95, 0.0), c + Vector3(0, 0.03, 0), _static)
	for row in 3:
		for k in 4:
			var p := c + Vector3(-1.05 + k * 0.7, 0.12, -0.7 + row * 0.7)
			if row == 1:
				Toys.add(Toys.canopy_mesh(0.22, 0.9), Toys.pmat(Color("a5d98a"), Toys.PAT_LEAF, 0.8, 0.02, 0.5), p, _static)
			else:
				Toys.add(Toys.canopy_mesh(0.26, 0.65), Toys.pmat(Color("8fcf9a") if row == 0 else Color("c7e59a"), Toys.PAT_LEAF, 0.8, 0.02, 0.4), p, _static)
	_solid_rect(c, Vector3(hw * 2 + 0.2, 0.8, hd * 2 + 0.2))
	Toys.bush(_static, c + Vector3(hw + 0.9, 0, -0.2), 0.7, Color("9fd39a"), Color("fff1b8"))
	_solid_round(c + Vector3(hw + 0.9, 0, -0.2), 0.5, 1.0)

func _bunting(a: Vector3, b: Vector3) -> void:
	var n := int(a.distance_to(b) / 0.42)
	var cols := [Color("e8747f"), Color("fff1b8"), Color("8fd6c8"), Color("c9b6e4"), Color("ffd2a6")]
	var dir := b - a
	var yaw := atan2(-dir.z, dir.x)
	var prev := a
	for i in range(1, n + 1):
		var t := float(i) / n
		var p := a.lerp(b, t) + Vector3(0, -0.55 * 4.0 * t * (1.0 - t), 0)
		var seg := p - prev
		var mid := (p + prev) * 0.5
		var rope := Toys.add(Toys.rcyl(0.012, 0.012, seg.length(), 0.005, 4), Toys.pmat(Color("fff8ee"), Toys.PAT_PLAIN, 0.9, 0.0, 2.2), mid, _static)
		rope.look_at_from_position(mid, p, Vector3.UP if absf(seg.normalized().y) < 0.99 else Vector3.RIGHT)
		rope.rotate_object_local(Vector3.RIGHT, PI / 2)
		if i < n:
			var fl := PrismMesh.new(); fl.size = Vector3(0.2, 0.26, 0.015)
			Toys.add(fl, Toys.pmat(cols[i % cols.size()], Toys.PAT_PLAIN, 0.9, 0.012, 2.8), p + Vector3(0, -0.15, 0), _static, Vector3.ONE, Vector3(0, yaw, PI))
		prev = p

# ---------------------------------------------------------------- pier & boat
func _build_pier() -> void:
	var L := pier_z1 - pier_z0
	var c := Vector3(PIER_X, 0.0, (pier_z0 + pier_z1) * 0.5)
	Toys.add(Toys.rbox(PIER_HW * 2.0 + 0.1, 0.14, L, 0.05), Toys.pmat(Color("c99a6e"), Toys.PAT_WOOD), c + Vector3(0, -0.02, 0), _static)
	Toys.add(Toys.rbox(PIER_HW * 2.0 + 0.3, 0.14, 0.3, 0.05), Toys.pmat(Color("a87c58"), Toys.PAT_WOOD), Vector3(PIER_X, -0.06, pier_z1 - 0.1), _static)
	var n := int(L / 1.8)
	for i in n + 1:
		var z := pier_z0 + 0.4 + (L - 0.6) * i / n
		for sx in [-1.0, 1.0]:
			var x: float = PIER_X + sx * (PIER_HW + 0.02)
			if dist_in(x, z) > 0.8 and i < n: continue
			Toys.add(Toys.rcyl(0.13, 0.14, 1.6, 0.05, 12), Toys.pmat(Color("9a7058"), Toys.PAT_WOOD), Vector3(x, -0.55, z), _static)
			if i % 2 == 0 or i == n:
				Toys.add(Toys.rcyl(0.12, 0.14, 0.5, 0.06, 12), Toys.pmat(Color("a87c58"), Toys.PAT_WOOD), Vector3(x, 0.25, z), _static)
	# lamps at the end, life ring, rope coil
	for sx in [-1.0, 1.0]:
		Toys.lamp(_static, Vector3(PIER_X + sx * (PIER_HW - 0.2), 0.04, pier_z1 - 0.35))
	var ring := Toys.add(Toys.torus(0.18, 0.3), Toys.pmat(Color("e8747f")), Vector3(PIER_X - PIER_HW + 0.05, 0.6, pier_z0 + 3.5), _static, Vector3.ONE, Vector3(0, 0, PI / 2))
	ring.rotation = Vector3(PI / 2, 0, PI / 2)
	Toys.add(Toys.rcyl(0.04, 0.04, 0.9, 0.02, 6), Toys.pmat(Color("fff8ee")), Vector3(PIER_X - PIER_HW + 0.05, 0.45, pier_z0 + 3.5), _static)
	Toys.add(Toys.torus(0.08, 0.2), Toys.pmat(Color("e8d6b0")), Vector3(PIER_X + 0.75, 0.08, pier_z0 + 5.0), _static, Vector3(1, 1.6, 1))
	# invisible pier walls (overlap the sea wall on land)
	var zr := pier_z0
	while dist_in(PIER_X, zr) > WALL_D and zr < pier_z1: zr += 0.05
	var wb := StaticBody3D.new(); wb.name = "PierWalls"; add_child(wb)
	for sx in [-1.0, 1.0]:
		var x: float = PIER_X + sx * (PIER_HW + 0.2)
		_col_line(wb, Vector3(x, 0, zr - 0.9), Vector3(x, 0, pier_z1 + 0.2), 3.0, 0.4)
	_col_line(wb, Vector3(PIER_X - PIER_HW - 0.4, 0, pier_z1 + 0.2), Vector3(PIER_X + PIER_HW + 0.4, 0, pier_z1 + 0.2), 3.0, 0.4)
	# boat moored beside the pier
	_boat = Toys.boat(self, Vector3(PIER_X + PIER_HW + 1.5, SEA_Y - 0.12, pier_z0 + 6.0), 0.12)

# ---------------------------------------------------------------- lighthouse
func _build_lighthouse() -> void:
	var p: Vector3 = get_meta("lighthouse_pos")
	var g := Toys.group(p, _static, -PEN_A + PI / 2 + PI)
	var bands := 4; var h := 1.25
	for i in bands:
		var r0 := 1.25 - i * 0.1; var r1 := r0 - 0.1
		var prof := PackedVector2Array([Vector2(0, 0), Vector2(r0, 0), Vector2(r0 + 0.02, 0.03), Vector2(r1 + 0.02, h - 0.03), Vector2(r1, h), Vector2(0, h)])
		Toys.add(Toys.lathe(prof, 32), Toys.pmat(Color("fffaf2") if i % 2 == 0 else Color("e8747f"), Toys.PAT_WALL), Vector3(0, i * h, 0), g)
	var top := bands * h
	Toys.add(Toys.rcyl(1.15, 1.0, 0.18, 0.06, 32), Toys.pmat(Color("57506e")), Vector3(0, top + 0.09, 0), g)
	Toys.add(Toys.torus(1.0, 1.08), Toys.pmat(Color("57506e")), Vector3(0, top + 0.6, 0), g, Vector3(1, 0.5, 1))
	for i in 10:
		var a := TAU * i / 10.0
		Toys.add(Toys.rcyl(0.025, 0.025, 0.45, 0.01, 6), Toys.pmat(Color("57506e")), Vector3(cos(a) * 1.04, top + 0.4, sin(a) * 1.04), g)
	_lh_lamp = Toys.mat(Color("fff1b8"), 0.4, 0.0)
	_lh_lamp.emission_enabled = true; _lh_lamp.emission = Color("ffe29a"); _lh_lamp.emission_energy_multiplier = 0.4
	_lh_lamp.set_meta("nobake", true)
	var lamp := Toys.add(Toys.rcyl(0.6, 0.6, 0.75, 0.05, 24), _lh_lamp, p + Vector3(0, top + 0.56, 0), self)
	lamp.set_meta("nobake", true)
	var cap := PackedVector2Array([Vector2(0, 0), Vector2(0.85, 0), Vector2(0.8, 0.12), Vector2(0.5, 0.5), Vector2(0.1, 0.72), Vector2(0, 0.74)])
	Toys.add(Toys.lathe(cap, 32), Toys.pmat(Color("e8747f"), Toys.PAT_ROOF), Vector3(0, top + 0.95, 0), g)
	Toys.add(Toys.sphere(0.12, 10), Toys.pmat(Color("57506e")), Vector3(0, top + 1.75, 0), g)
	Toys.add(Toys.rbox(0.8, 1.3, 0.2, 0.08), Toys.pmat(Color("8a6b5c"), Toys.PAT_WOOD), Vector3(0, 0.65, 1.2), g)
	Toys.add(Toys.rbox(0.42, 0.5, 0.08, 0.04), Toys.window_mat(), Vector3(0, 3.2, 1.0), g)
	_solid_round(p, 1.35, 6.0)
	_lh_light = OmniLight3D.new(); _lh_light.light_color = Color("ffe0a0"); _lh_light.omni_range = 9.0; _lh_light.light_energy = 0.0
	_lh_light.position = p + Vector3(0, top + 0.6, 0); add_child(_lh_light)
	# rotating beam (visible at night)
	_beam = Node3D.new(); _beam.position = p + Vector3(0, top + 0.56, 0); add_child(_beam)
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.albedo_color = Color(1.0, 0.9, 0.6, 0.16)
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	for s in [-1.0, 1.0]:
		var cone := Toys.add(Toys.cyl(0.25, 2.6, 22.0, 16), bm, Vector3(s * 11.3, 0, 0), _beam, Vector3(1, 1, 0.35), Vector3(0, 0, s * PI / 2))
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	# rocks around the point (fishing rocks): some in the water, a few big ones on the shore
	var ra := PEN_A + 0.12
	for i in 9:
		var a := ra - 0.35 + i * 0.09
		var r := shore_r(a) + 0.2 + fmod(i * 0.61, 1.0) * 1.3
		var q := _dir(a) * r
		Toys.rock(_static, Vector3(q.x, SEA_Y - 0.1, q.y), 0.9 + fmod(i * 0.37, 0.8), Color("aeb6c8"), i * 1.3)
	for k in [[-0.2, 1.6, 1.0], [0.22, 1.5, 0.8]]:
		var a2: float = ra + k[0]
		var q2 := _dir(a2) * (shore_r(a2) - WALL_D - k[1])
		Toys.rock(_static, Vector3(q2.x, -0.05, q2.y), k[2], Color("b9b4c4"), a2 * 3.0)
		_solid_round(Vector3(q2.x, 0, q2.y), 0.65 * k[2], 1.0)

# ---------------------------------------------------------------- beach props
func _build_beach_props() -> void:
	# umbrella + towel near the beach spot
	var b: Vector3 = _spots["beach"]
	var inward := -Vector3(b.x, 0, b.z).normalized()
	var side := Vector3(-inward.z, 0, inward.x)
	var up := b + inward * 1.4 + side * 2.2
	var ug := Toys.group(up, _static)
	Toys.add(Toys.rcyl(0.03, 0.03, 2.2, 0.01, 6), Toys.pmat(Color("fff8ee")), Vector3(0, 1.1, 0), ug, Vector3.ONE, Vector3(0.12, 0, 0.0))
	for i in 8:
		var c := Color("e8747f") if i % 2 == 0 else Color("fff8ee")
		var seg := PrismMesh.new(); seg.size = Vector3(0.78, 0.4, 0.04)
		var a := TAU * i / 8.0
		var pm := Toys.add(seg, Toys.pmat(c, Toys.PAT_PLAIN, 0.9, 0.015), Vector3(cos(a) * 0.55, 2.12, sin(a) * 0.55), ug)
		pm.rotation = Vector3(0, -a - PI / 2, 0)
		pm.rotate_object_local(Vector3.RIGHT, -1.15)
	Toys.add(Toys.sphere(0.07, 8), Toys.pmat(Color("fff8ee")), Vector3(0, 2.32, 0), ug)
	_solid_round(up, 0.15, 2.2)
	Toys.add(Toys.rbox(0.9, 0.03, 1.7, 0.015), Toys.pmat(Color("8fd6c8"), Toys.PAT_PLAIN, 0.9, 0.01), up + side * 1.0 + Vector3(0, 0.0, 0), _static, Vector3.ONE, Vector3(0, atan2(side.x, side.z), 0))
	# beached rowboat (upside down) and driftwood around the ring
	var ra := 2.55
	var q := _dir(ra) * (shore_r(ra) - 2.1)
	var rb := Toys.group(Vector3(q.x, 0.15, q.y), _static, -ra)
	Toys.add(Toys.sphere(0.8, 18), Toys.pmat(Color("8fb7e0"), Toys.PAT_WOOD, 0.6), Vector3.ZERO, rb, Vector3(0.75, 0.42, 1.6))
	_solid_round(Vector3(q.x, 0, q.y), 0.8, 1.0)
	for a in [0.4, 2.9, -2.0, -1.6, 0.9]:
		var dp := _dir(a) * (shore_r(a) - 1.7)
		if _near_pier(dp.x, dp.y, 1.5) or _in_flats(dp.x, dp.y, -1.0): continue
		var log := Toys.add(Toys.rcyl(0.11, 0.13, 1.4, 0.05, 10), Toys.pmat(Color("c8b39a"), Toys.PAT_WOOD), Vector3(dp.x, 0.08, dp.y), _static, Vector3.ONE, Vector3(PI / 2, a * 2.0, 0))
		log.rotation = Vector3(0, a + 1.2, PI / 2)

# ---------------------------------------------------------------- lanterns
func _build_lanterns() -> void:
	for id in ["harbour", "hill"]:
		var p: Vector3 = _spots["lantern_" + id]
		var post := Toys.lantern_post(_static, p)
		var head := post.get_node("Head") as Node3D
		head.set_meta("nobake", true)
		# move the head under the island so baking the posts never touches it
		var keep := head.global_transform
		post.remove_child(head); add_child(head); head.global_transform = keep
		head.name = "Lantern_" + id
		for mi in head.find_children("*", "MeshInstance3D", true, false):
			mi.set_meta("nobake", true)
		var glass := head.get_node("Glass") as MeshInstance3D
		var gm := (glass.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
		glass.material_override = gm
		_lantern_glass[id] = gm
		_lanterns[id] = head
		_lanterns["lantern_" + id] = head
		_solid_round(p, 0.42, 3.0)

# ---------------------------------------------------------------- gates
func _build_gates() -> void:
	# hill gate across the bottom of the ramp
	_hill_gate = Node3D.new(); _hill_gate.name = "HillGate"; add_child(_hill_gate)
	var gb := StaticBody3D.new(); _hill_gate.add_child(gb)
	var a := Vector3(RAMP_X - RAMP_HW - 0.12, 0, HILL_GATE_Z); var b := Vector3(RAMP_X + RAMP_HW + 0.12, 0, HILL_GATE_Z)
	_gate_visual(_hill_gate, a, b)
	_col_line(gb, a - Vector3(0.2, 0, 0), b + Vector3(0.2, 0, 0), 3.0, 0.35)
	# harbour gate: a straight fence across the neck of the lighthouse point, wall to wall
	_harbour_gate = Node3D.new(); _harbour_gate.name = "HarbourGate"; add_child(_harbour_gate)
	var hb := StaticBody3D.new(); _harbour_gate.add_child(hb)
	var d := _dir(PEN_A); var pp := _perp(d)
	var c := d * GATE_D
	var e0 := 0.0; var e1 := 0.0
	while dist_in((c + pp * e0).x, (c + pp * e0).y) > WALL_D - 0.3 and e0 < 20.0: e0 += 0.1
	while dist_in((c - pp * e1).x, (c - pp * e1).y) > WALL_D - 0.3 and e1 < 20.0: e1 += 0.1
	var A := c + pp * e0; var B := c - pp * e1
	var A3 := Vector3(A.x, 0, A.y); var B3 := Vector3(B.x, 0, B.y); var C3 := Vector3(c.x, 0, c.y)
	var gw := 1.6
	var pv := Vector3(pp.x, 0, pp.y)
	Toys.fence(_harbour_gate, A3, C3 + pv * gw * 0.5, Color("fff8ee"), 0.8)
	Toys.fence(_harbour_gate, C3 - pv * gw * 0.5, B3, Color("fff8ee"), 0.8)
	_gate_visual(_harbour_gate, C3 + pv * gw * 0.5, C3 - pv * gw * 0.5)
	_col_line(hb, A3 + Vector3(pp.x, 0, pp.y) * 0.4, B3 - Vector3(pp.x, 0, pp.y) * 0.4, 3.0, 0.35)
	set_meta("harbour_gate_ends", [A3, B3])

func _gate_visual(parent: Node3D, a: Vector3, b: Vector3) -> void:
	var wood := Toys.pmat(Color("c99a6e"), Toys.PAT_WOOD)
	for p in [a, b]:
		Toys.add(Toys.rcyl(0.11, 0.13, 1.3, 0.04, 10), wood, p + Vector3(0, 0.65, 0), parent)
		Toys.add(Toys.sphere(0.13, 10), wood, p + Vector3(0, 1.33, 0), parent)
	var dir := b - a; var L := dir.length(); var yaw := atan2(-dir.z, dir.x)
	var g := Toys.group((a + b) * 0.5, parent, yaw)
	for y in [0.35, 0.8]:
		Toys.add(Toys.rbox(L - 0.2, 0.12, 0.07, 0.04), wood, Vector3(0, y, 0), g)
	var diag := Toys.add(Toys.rbox(sqrt(pow(L - 0.3, 2) + 0.2), 0.1, 0.06, 0.03), wood, Vector3(0, 0.58, 0.02), g)
	diag.rotation.z = atan2(0.45, L - 0.3)
	# a small hanging sign with a lantern symbol (no text): "closed until lit"
	Toys.add(Toys.rbox(0.42, 0.32, 0.05, 0.03), Toys.pmat(Color("fff1df"), Toys.PAT_WOOD), Vector3(0, 1.0, 0.05), g)
	Toys.add(Toys.sphere(0.07, 8), Toys.pmat(Color("f2c46d"), Toys.PAT_PLAIN, 0.5, 0.01), Vector3(0, 1.0, 0.09), g, Vector3(1, 1.3, 0.5))

# ---------------------------------------------------------------- tide flats
func _build_flats() -> void:
	_flats_bar = Node3D.new(); _flats_bar.name = "TideFlats"; add_child(_flats_bar)
	_flats_bar.position = Vector3(flats_c.x, -0.75, flats_c.y)
	_flats_bar.rotation.y = -FLATS_A
	var prof := PackedVector2Array([Vector2(0, 0.36), Vector2(0.55, 0.33), Vector2(0.85, 0.22), Vector2(1.0, 0.0), Vector2(1.08, -0.2)])
	var mi := MeshInstance3D.new(); mi.mesh = Toys.lathe(prof, 36)
	var gm := _ground_shader(2); _ground_mats.append(gm)
	mi.material_override = gm
	mi.scale = Vector3(FLATS_AB.x, 1.0, FLATS_AB.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flats_bar.add_child(mi)
	# a few pebbles and a starfish-coloured rock on the bar
	for i in 5:
		var a := i * 1.3; var r := 0.3 + 0.12 * i
		var rk := Toys.rock(_flats_bar, Vector3(cos(a) * r * FLATS_AB.x * 0.8, 0.3, sin(a) * r * FLATS_AB.y * 0.8), 0.28 + 0.06 * (i % 3), Color("c9c2d6"), a)
		for m in rk.find_children("*", "MeshInstance3D", true, false): m.set_meta("nobake", true)
	# tide gate (sea wall segments in front of the flats) + walls around the flats
	_tide_gate = StaticBody3D.new(); _tide_gate.name = "TideGate"; add_child(_tide_gate)
	var fw := StaticBody3D.new(); fw.name = "FlatsWalls"; add_child(fw)
	var n := 72
	var prev := Vector2.ZERO
	for i in n + 1:
		var a := TAU * i / n
		var q := flats_c + flats_u * cos(a) * (FLATS_AB.x - 0.5) + _perp(flats_u) * sin(a) * (FLATS_AB.y - 0.5)
		if i > 0:
			var mid := (q + prev) * 0.5
			if dist_in(mid.x, mid.y) < WALL_D + 0.9:
				_col_line(fw, Vector3(prev.x, 0, prev.y), Vector3(q.x, 0, q.y), 3.0, 0.4)
		prev = q
	flats_level = 1.0 if _low_tide() else 0.0
	_apply_flats()

func _apply_flats() -> void:
	_flats_bar.position.y = lerpf(-0.75, -0.34, flats_level)
	_flats_bar.visible = flats_level > 0.02
	if _sea_mat: _sea_mat.set_shader_parameter("flats_amt", flats_level)
	var open := flats_level > 0.85
	_set_body_enabled(_tide_gate, not open)

# ---------------------------------------------------------------- sea wall
func _build_sea_wall() -> void:
	var wall := StaticBody3D.new(); wall.name = "SeaWall"; add_child(wall)
	var n := 360
	var pts: Array = []
	for i in n:
		var t := TAU * i / n - PI
		var r := shore_r(t) - WALL_D
		pts.append(Vector2(cos(t) * r, sin(t) * r))
	for i in n:
		var a: Vector2 = pts[i]; var b: Vector2 = pts[(i + 1) % n]
		var mid := (a + b) * 0.5
		if absf(mid.x - PIER_X) < PIER_HW + 0.1 and mid.y > 0.0: continue
		var body: StaticBody3D = wall
		if _in_flats(mid.x, mid.y, -0.4): body = _tide_gate
		_col_line(body, Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), 4.0, 0.4)

# ---------------------------------------------------------------- vegetation scatter
func _scatter() -> void:
	var leaf := [Color("8cc79a"), Color("9bd08f"), Color("7fbf95"), Color("a3d38c")]
	# trees: a ring near the grass edge and a few in the gaps
	var placed := 0
	for i in 900:
		if placed >= 44: break
		var t := _rng.randf_range(-PI, PI)
		var s := shore_r(t)
		var r := s - _rng.randf_range(BEACH_W + 0.6, BEACH_W + 6.0) if i < 600 else _rng.randf_range(4.0, s - BEACH_W - 0.6)
		var p := Vector2(cos(t) * r, sin(t) * r)
		if not _free(p, 0.5, BEACH_W + 0.4, 99.0, 1.5): continue
		var sc := _rng.randf_range(0.85, 1.25)
		if _rng.randf() < 0.3:
			Toys.pine(_static, Vector3(p.x, 0, p.y), sc, Color("6fae8a").lerp(leaf[placed % 4], 0.3))
		else:
			Toys.tree(_static, Vector3(p.x, 0, p.y), sc, leaf[placed % 4])
		_solid_round(Vector3(p.x, 0, p.y), 0.3 * sc, 2.5)
		_blocks[_blocks.size() - 1] = Vector3(p.x, p.y, 0.45 * sc)
		placed += 1
	# bushes (some with flower dots)
	placed = 0
	for i in 900:
		if placed >= 36: break
		var t := _rng.randf_range(-PI, PI)
		var r := _rng.randf_range(3.0, shore_r(t) - BEACH_W - 0.2)
		var p := Vector2(cos(t) * r, sin(t) * r)
		if not _free(p, 0.6, BEACH_W + 0.2, 99.0, 1.4): continue
		var dots := [Color("f4a9a8"), Color("fff1b8"), Color(0, 0, 0, 0), Color("c9b6e4")][placed % 4]
		Toys.bush(_static, Vector3(p.x, 0, p.y), _rng.randf_range(0.7, 1.05), [Color("9fd39a"), Color("8fca8a"), Color("a9d79a")][placed % 3], dots)
		_solid_round(Vector3(p.x, 0, p.y), 0.55, 1.0)
		placed += 1
	# beach rocks (sand)
	placed = 0
	for i in 600:
		if placed >= 12: break
		var t := _rng.randf_range(-PI, PI)
		var r := shore_r(t) - _rng.randf_range(WALL_D + 1.4, BEACH_W - 0.5)
		var p := Vector2(cos(t) * r, sin(t) * r)
		if not _free(p, 0.5, WALL_D + 1.2, BEACH_W, 1.5): continue
		var sc := _rng.randf_range(0.5, 0.9)
		Toys.rock(_static, Vector3(p.x, -0.05, p.y), sc, Color("c3bdd0"), t * 5.0)
		_solid_round(Vector3(p.x, 0, p.y), 0.6 * sc, 1.0)
		placed += 1
	# decor without collision: flowers and grass tufts on grass, shells on sand
	var fcols := [Color("f4a9a8"), Color("fff1b8"), Color("c9b6e4"), Color("ffffff"), Color("ffd2a6")]
	placed = 0
	for i in 2000:
		if placed >= 170: break
		var t := _rng.randf_range(-PI, PI)
		var r := sqrt(_rng.randf()) * (shore_r(t) - BEACH_W - 0.3)
		var p := Vector2(cos(t) * r, sin(t) * r)
		if not _free(p, 0.12, BEACH_W + 0.3, 99.0, 0.25): continue
		# little clusters
		for k in 3:
			var q := p + Vector2(_rng.randf_range(-0.35, 0.35), _rng.randf_range(-0.35, 0.35))
			Toys.flower(_static, Vector3(q.x, 0, q.y), fcols[(placed + k) % 5], _rng.randf_range(0.8, 1.15))
		placed += 1
	placed = 0
	for i in 2000:
		if placed >= 220: break
		var t := _rng.randf_range(-PI, PI)
		var r := sqrt(_rng.randf()) * (shore_r(t) - BEACH_W + 0.6)
		var p := Vector2(cos(t) * r, sin(t) * r)
		if not _free(p, 0.1, BEACH_W - 0.4, 99.0, 0.15): continue
		_tuft(Vector3(p.x, 0, p.y), Color("86c477").lerp(Color("b5dc8f"), _rng.randf()))
		placed += 1

var _tuft_mesh: Mesh
func _tuft(p: Vector3, c: Color) -> void:
	if _tuft_mesh == null: _tuft_mesh = Toys.cyl(0.0, 0.045, 0.32, 4)
	var g := Toys.group(p, _static, _rng.randf() * TAU, _rng.randf_range(0.8, 1.3))
	var m := Toys.pmat(c.lerp(Color("9fd38c"), 0.3), Toys.PAT_PLAIN, 0.95, 0.0, 1.0)
	for i in 3:
		var a := i * TAU / 3.0
		Toys.add(_tuft_mesh, m, Vector3(cos(a) * 0.05, 0.14, sin(a) * 0.05), g, Vector3.ONE, Vector3(sin(a) * 0.4, 0, cos(a) * 0.4))

# ---------------------------------------------------------------- backdrop (distant world, never empty)
func _haze(c: Color, k: float) -> Color:
	return c.lerp(Color("b9cde6"), k)

func _build_backdrop() -> void:
	var bd := Node3D.new(); bd.name = "Backdrop"; add_child(bd)
	# near islets (visible from the play camera at the island edge)
	_islet(bd, Vector2(-25, -25), 3.2, true, 2)
	_islet(bd, Vector2(29, 8), 2.6, false, 1, true)
	_islet(bd, Vector2(-30, 17), 2.2, false, 0)
	_islet(bd, Vector2(6, -33), 2.4, true, 1)
	_islet(bd, Vector2(23, 30), 2.0, false, 1)
	_islet(bd, Vector2(-14, 33), 2.6, true, 1, true)
	_islet(bd, Vector2(34, -20), 2.0, false, 2)
	# rocky stacks
	for p in [Vector2(-20, -32), Vector2(31, -6), Vector2(-33, 4), Vector2(16, 34), Vector2(-4, 36)]:
		Toys.rock(bd, Vector3(p.x, SEA_Y - 0.2, p.y), 1.6, Color("aeb6c8"), p.x)
	# mainland to the north: forested hills, cliffs, a seaside town with lit windows, a far city
	var main_z := -105.0
	for i in 15:
		var x := -150.0 + i * 21.0 + fmod(i * 7.3, 9.0)
		var r := 16.0 + fmod(i * 5.1, 9.0)
		Toys.add(Toys.canopy_mesh(r, 0.42), Toys.pmat(_haze(Color("8cbf9a"), 0.45 + 0.1 * (i % 2)), Toys.PAT_LEAF, 0.9, 0.06), Vector3(x, SEA_Y - 1.0, main_z - 18.0 - fmod(i * 3.7, 10.0)), bd, Vector3(1.4, 1, 1))
	for i in 9:
		var x := -130.0 + i * 8.0
		Toys.add(Toys.rbox(9.0, 6.0 + fmod(i * 2.3, 4.0), 7.0, 1.6), Toys.pmat(_haze(Color("c9b6d8"), 0.4), Toys.PAT_ROCK, 0.95, 0.06), Vector3(x, SEA_Y + 2.0, main_z + 4.0), bd)
	Toys.add(Toys.rbox(260.0, 1.2, 14.0, 0.5), Toys.pmat(_haze(Color("efdcb8"), 0.35), Toys.PAT_ROCK, 0.95, 0.0), Vector3(0, SEA_Y + 0.1, main_z + 6.0), bd)
	var hcols := [Color("fbe2d2"), Color("e6dcf6"), Color("dff1e6"), Color("fff0c8"), Color("f6e2ea")]
	var rcols := [Color("e58a94"), Color("9d8fd6"), Color("6fb7a8"), Color("e8a35c"), Color("c98a9a")]
	for i in 26:
		var x := -60.0 + i * 4.6 + fmod(i * 1.7, 1.5)
		var w := 3.0 + fmod(i * 0.9, 1.4); var h := 3.0 + fmod(i * 1.3, 3.0)
		var z := main_z + 2.0 - fmod(i * 2.9, 5.0)
		_far_house(bd, Vector3(x, SEA_Y + 0.6, z), w, h, _haze(hcols[i % 5], 0.3), _haze(rcols[i % 5], 0.3))
	for i in 9:
		var x := 50.0 + i * 7.0
		var h := 10.0 + fmod(i * 4.7, 12.0)
		var tw := Toys.group(Vector3(x, SEA_Y, main_z - 8.0 - fmod(i * 3.3, 6.0)), bd)
		Toys.add(Toys.rbox(6.0, h, 6.0, 0.8), Toys.pmat(_haze(Color("d8d2e6"), 0.5), Toys.PAT_WALL, 0.9, 0.06), Vector3(0, h * 0.5, 0), tw)
		for k in int(h / 2.5):
			Toys.add(Toys.rbox(4.6, 0.5, 0.1, 0.05), Toys.window_mat(), Vector3(0, 1.6 + k * 2.4, 3.02), tw)
	# east island with a village and a little lighthouse
	_far_island(bd, Vector3(85, 0, -15), 22.0, 6, true)
	# west cliffs island with pines
	_far_island(bd, Vector3(-80, 0, 18), 18.0, 3, false)
	# south-east low island
	_far_island(bd, Vector3(60, 0, 70), 16.0, 2, false)
	_far_island(bd, Vector3(-55, 0, 75), 14.0, 2, false)
	Toys.bake(bd, 60.0)
	# moving things out there: sailboats, a ferry, buoys
	for i in 4:
		var sb := Toys.boat(self, Vector3.ZERO, 0.0, Color("fffaf2"), [Color("8fb7e0"), Color("e8747f"), Color("8fd6c8"), Color("f2c46d")][i])
		sb.scale = Vector3.ONE * 1.4
		_sailboats.append([sb, 30.0 + i * 5.5, i * 1.7, 0.008 + 0.003 * i])
	_ferry = _build_ferry()
	for p in [Vector2(PIER_X + 4.0, pier_z1 + 2.0), Vector2(flats_c.x - 4.0, flats_c.y + 4.0), Vector2(19, -18)]:
		var bu := Toys.group(Vector3(p.x, SEA_Y, p.y), self)
		Toys.add(Toys.rcyl(0.05, 0.35, 0.7, 0.08, 14), Toys.mat(Color("e8747f")), Vector3(0, 0.3, 0), bu)
		Toys.add(Toys.rcyl(0.36, 0.36, 0.14, 0.05, 14), Toys.mat(Color("fffaf2")), Vector3(0, 0.15, 0), bu)
		Toys.add(Toys.sphere(0.09, 8), Toys.bulb_mat(), Vector3(0, 0.72, 0), bu)
		_buoys.append(bu)

func _islet(parent: Node3D, c: Vector2, r: float, tree_it: bool, rocks: int, hut := false) -> void:
	var g := Toys.group(Vector3(c.x, SEA_Y, c.y), parent, c.x)
	Toys.add(Toys.canopy_mesh(r, 0.22), Toys.pmat(Color("f1dcb2"), Toys.PAT_ROCK, 0.95, 0.02), Vector3(0, -0.35, 0), g, Vector3(1.0, 1, 0.8))
	Toys.add(Toys.canopy_mesh(r * 0.68, 0.3), Toys.pmat(Color("9fd38c"), Toys.PAT_LEAF, 0.9, 0.025), Vector3(0, -0.1, 0), g, Vector3(1.0, 1, 0.8))
	for i in rocks:
		Toys.rock(g, Vector3(r * 0.75 * cos(i * 2.5), -0.1, r * 0.6 * sin(i * 2.5)), 0.8 + 0.3 * i, Color("b9b4c4"), i)
	if tree_it:
		Toys.pine(g, Vector3(-r * 0.25, 0.2, 0), 1.2, Color("7fbf95"))
		Toys.tree(g, Vector3(r * 0.25, 0.2, r * 0.2), 0.9, Color("9bd08f"))
	if hut:
		var h := Toys.house(g, Vector3(0.1, 0.25, -0.1), 0.4, Color("fff0c8"), Color("e8747f"), 1.8, 1.4, 1.6)
		h.scale = Vector3.ONE * 0.9

func _far_house(parent: Node3D, p: Vector3, w: float, h: float, wall: Color, roof: Color) -> void:
	var g := Toys.group(p, parent)
	Toys.add(Toys.rbox(w, h, 3.0, 0.3), Toys.pmat(wall, Toys.PAT_WALL, 0.9, 0.05), Vector3(0, h * 0.5, 0), g)
	var pr := PrismMesh.new(); pr.size = Vector3(w + 0.4, 1.4, 3.3)
	Toys.add(pr, Toys.pmat(roof, Toys.PAT_ROOF, 0.9, 0.0), Vector3(0, h + 0.7, 0), g)
	Toys.add(Toys.rbox(0.8, 0.8, 0.1, 0.1), Toys.window_mat(), Vector3(-w * 0.2, h * 0.6, 1.52), g)
	if w > 3.6: Toys.add(Toys.rbox(0.8, 0.8, 0.1, 0.1), Toys.window_mat(), Vector3(w * 0.25, h * 0.6, 1.52), g)

func _far_island(parent: Node3D, c: Vector3, r: float, houses: int, beacon: bool) -> void:
	var g := Toys.group(c, parent, c.x * 0.1)
	Toys.add(Toys.canopy_mesh(r, 0.2), Toys.pmat(_haze(Color("efdcb8"), 0.3), Toys.PAT_ROCK, 0.95, 0.05), Vector3(0, SEA_Y - 1.2, 0), g, Vector3(1.3, 1, 0.8))
	Toys.add(Toys.canopy_mesh(r * 0.8, 0.45), Toys.pmat(_haze(Color("8fc79a"), 0.3), Toys.PAT_LEAF, 0.9, 0.06), Vector3(0, SEA_Y - 0.5, 0), g, Vector3(1.3, 1, 0.8))
	for i in houses:
		var a := i * 1.1 - 1.2
		var hp := Vector3(cos(a) * r * 0.55, SEA_Y + 2.0, sin(a) * r * 0.35 + r * 0.25)
		_far_house(g, hp, 2.6, 2.4, _haze([Color("fbe2d2"), Color("e6dcf6"), Color("fff0c8")][i % 3], 0.25), _haze([Color("e58a94"), Color("9d8fd6"), Color("e8a35c")][i % 3], 0.25))
	for i in 7:
		var a := i * 0.9 + 0.4
		Toys.pine(g, Vector3(cos(a) * r * 0.6, SEA_Y + 1.6, sin(a) * r * 0.4 - r * 0.1), 3.0, _haze(Color("6fae8a"), 0.3))
	if beacon:
		var b := Toys.group(Vector3(r * 0.9, SEA_Y + 0.5, r * 0.2), g)
		for i in 3:
			Toys.add(Toys.rcyl(0.9 - i * 0.1, 1.0 - i * 0.1, 1.6, 0.1, 16), Toys.pmat(Color("fffaf2") if i % 2 == 0 else Color("e8747f"), Toys.PAT_WALL, 0.9, 0.05), Vector3(0, 0.8 + i * 1.6, 0), b)
		Toys.add(Toys.rcyl(0.55, 0.55, 0.8, 0.05, 12), Toys.window_mat(), Vector3(0, 5.2, 0), b)

func _build_ferry() -> Node3D:
	var f := Node3D.new(); f.name = "Ferry"; add_child(f)
	Toys.add(Toys.rbox(14.0, 2.0, 4.0, 0.9), Toys.mat(Color("fffaf2")), Vector3(0, 0.6, 0), f)
	Toys.add(Toys.rbox(14.1, 0.5, 4.1, 0.25), Toys.mat(Color("e8747f")), Vector3(0, 0.0, 0), f)
	Toys.add(Toys.rbox(7.0, 1.8, 3.2, 0.5), Toys.mat(Color("eef3fa")), Vector3(-1.0, 2.4, 0), f)
	for i in 5:
		Toys.add(Toys.rbox(0.9, 0.6, 0.1, 0.1), Toys.window_mat(), Vector3(-3.6 + i * 1.3, 2.5, 1.62), f)
	Toys.add(Toys.rcyl(0.45, 0.55, 1.6, 0.15, 14), Toys.mat(Color("6fb7a8")), Vector3(2.4, 3.6, 0), f)
	var sm := _sprite_particles(6, 4.0, Color(1, 1, 1, 0.5), 1.4)
	sm.position = Vector3(2.4, 4.6, 0); sm.direction = Vector3(-0.3, 1, 0); sm.initial_velocity_min = 0.8; sm.initial_velocity_max = 1.2
	f.add_child(sm)
	return f

# ---------------------------------------------------------------- life (animated details)
func _sprite_tex() -> GradientTexture2D:
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL; gt.fill_from = Vector2(0.5, 0.5); gt.fill_to = Vector2(0.5, 0.0)
	var gr := Gradient.new(); gr.set_color(0, Color(1, 1, 1, 1)); gr.set_color(1, Color(1, 1, 1, 0))
	gr.add_point(0.45, Color(1, 1, 1, 0.55))
	gt.gradient = gr; gt.width = 64; gt.height = 64
	return gt

var _sprite_tex_cache: GradientTexture2D
## Soft billboard particles (smoke, spray, mist): fade in and out, no hard edges.
func _sprite_particles(amount: int, life: float, col: Color, size: float, additive := false) -> CPUParticles3D:
	if _sprite_tex_cache == null: _sprite_tex_cache = _sprite_tex()
	var p := CPUParticles3D.new()
	p.amount = amount; p.lifetime = life
	var q := QuadMesh.new(); q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive: m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _sprite_tex_cache
	m.disable_receive_shadows = true
	q.material = m
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, 0.0)); g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	g.add_point(0.25, col); g.add_point(0.7, Color(col.r, col.g, col.b, col.a * 0.6))
	p.color_ramp = g
	var c := Curve.new(); c.add_point(Vector2(0, 0.6)); c.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = c
	return p

func _chimney_smoke(house: Node3D) -> void:
	var top := house.get_node_or_null("ChimneyTop") as Node3D
	if top == null: return
	var sm := _sprite_particles(7, 4.5, Color(1, 1, 1, 0.42), 0.55)
	sm.direction = Vector3(0.25, 1, 0.1); sm.spread = 10.0
	sm.initial_velocity_min = 0.3; sm.initial_velocity_max = 0.5
	sm.gravity = Vector3(0.12, 0.05, 0.0)
	add_child(sm)
	sm.global_position = top.global_position

func _build_life() -> void:
	# seagulls circling over the pier and the point
	var gull_body := Toys.mat(Color("fffaf2"), 0.8, 0.018)
	var gull_wing := Toys.mat(Color("e9ecf3"), 0.8, 0.018)
	var gull_beak := Toys.mat(Color("f2b46d"), 0.6, 0.0)
	var centers := [Vector3(PIER_X, 7.0, pier_z1 - 2.0), Vector3(12.0, 8.0, -12.0), Vector3(-6.0, 9.0, 14.0)]
	for i in 3:
		var g := Node3D.new(); add_child(g)
		Toys.add(Toys.sphere(0.18, 12), gull_body, Vector3.ZERO, g, Vector3(0.8, 0.75, 1.6))
		Toys.add(Toys.sphere(0.04, 6), gull_beak, Vector3(0, 0.02, 0.3), g, Vector3(0.6, 0.6, 1.6))
		var wings: Array = []
		for s in [-1.0, 1.0]:
			var hinge := Node3D.new(); hinge.position = Vector3(s * 0.08, 0.05, 0); g.add_child(hinge)
			Toys.add(Toys.rbox(0.55, 0.03, 0.2, 0.012), gull_wing, Vector3(s * 0.3, 0, 0), hinge)
			wings.append(hinge)
		_gulls.append([g, centers[i], 4.0 + i * 1.5, i * 2.1, wings])
	# butterflies (day)
	var bcols := [Color("fff1b8"), Color("f4a9a8"), Color("c9b6e4"), Color("ffffff"), Color("ffd2a6")]
	var anchors := [Vector3(-3.0, 0.8, 5.5), Vector3(4.5, 0.8, 5.0), Vector3(-5.6, 0.8, 8.2), Vector3(HILL_C.x, HILL_TOP + 0.8, HILL_C.y + 0.5), Vector3(-7.5, 0.8, -4.0)]
	for i in 5:
		var g := Node3D.new(); add_child(g)
		var wm := Toys.mat(bcols[i], 0.8, 0.012)
		var wings: Array = []
		for s in [-1.0, 1.0]:
			var hinge := Node3D.new(); g.add_child(hinge)
			Toys.add(Toys.rbox(0.16, 0.012, 0.13, 0.01), wm, Vector3(s * 0.085, 0, 0), hinge)
			wings.append(hinge)
		_flies.append([g, anchors[i], i * 1.9, wings])
	# drifting petals / leaves (sparse)
	_petals = CPUParticles3D.new()
	_petals.amount = 14; _petals.lifetime = 9.0
	_petals.mesh = Toys.rbox(0.1, 0.015, 0.06, 0.007)
	var pm := StandardMaterial3D.new(); pm.vertex_color_use_as_albedo = true; pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	pm.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	_petals.material_override = pm
	_petals.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_petals.emission_box_extents = Vector3(15, 0.5, 13)
	_petals.position = Vector3(0, 4.2, 0)
	_petals.direction = Vector3(1, -0.3, 0.3); _petals.spread = 40.0
	_petals.initial_velocity_min = 0.3; _petals.initial_velocity_max = 0.6
	_petals.gravity = Vector3(0.1, -0.12, 0.05)
	_petals.angular_velocity_min = -120.0; _petals.angular_velocity_max = 120.0
	_petals.angle_min = 0.0; _petals.angle_max = 360.0
	_petals.particle_flag_rotate_y = true
	var pg := Gradient.new(); pg.set_color(0, Color("f7b9c0")); pg.set_color(1, Color("bfe3a8"))
	_petals.color_initial_ramp = pg
	var sc := Curve.new(); sc.add_point(Vector2(0, 0)); sc.add_point(Vector2(0.1, 1)); sc.add_point(Vector2(0.85, 1)); sc.add_point(Vector2(1, 0))
	_petals.scale_amount_curve = sc
	_petals.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_petals)
	# fireflies (night): soft additive glows
	_fireflies = _sprite_particles(26, 4.0, Color(1.0, 0.95, 0.6, 0.9), 0.22, true)
	_fireflies.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_fireflies.emission_box_extents = Vector3(16, 0.8, 14)
	_fireflies.position = Vector3(-2, 1.1, 1)
	_fireflies.direction = Vector3(0, 1, 0); _fireflies.spread = 180.0
	_fireflies.initial_velocity_min = 0.1; _fireflies.initial_velocity_max = 0.3
	_fireflies.gravity = Vector3.ZERO
	var fc := Curve.new(); fc.add_point(Vector2(0, 0.3)); fc.add_point(Vector2(0.5, 1.0)); fc.add_point(Vector2(1, 0.3))
	_fireflies.scale_amount_curve = fc
	_fireflies.emitting = false
	add_child(_fireflies)

# ---------------------------------------------------------------- contact shadows (AO texture for the ground)
func _build_ao() -> void:
	var N := 256; var size := 72.0; var x0 := -36.0; var z0 := -36.0
	var px := size / N
	var buf := PackedFloat32Array(); buf.resize(N * N); buf.fill(1.0)
	var blob := func(cx: float, cz: float, r: float, k: float) -> void:
		var i0 := maxi(0, int((cx - r - x0) / px)); var i1 := mini(N - 1, int((cx + r - x0) / px) + 1)
		var j0 := maxi(0, int((cz - r - z0) / px)); var j1 := mini(N - 1, int((cz + r - z0) / px) + 1)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var dx := x0 + (i + 0.5) * px - cx; var dz := z0 + (j + 0.5) * px - cz
				var d := sqrt(dx * dx + dz * dz) / r
				if d < 1.0:
					var v := k * pow(1.0 - d, 1.6)
					buf[j * N + i] *= 1.0 - v
	for b in _blocks:
		blob.call(b.x, b.y, b.z * 1.9 + 0.25, 0.38)
	for r in _rects:
		var rc := (r as Rect2)
		var c := rc.get_center()
		var steps := int(maxf(rc.size.x, rc.size.y) / 0.6) + 1
		for i in steps + 1:
			for j in steps + 1:
				var q := rc.position + Vector2(rc.size.x * i / steps, rc.size.y * j / steps)
				blob.call(q.x, q.y, 0.9, 0.12)
		blob.call(c.x, c.y, maxf(rc.size.x, rc.size.y) * 0.75, 0.15)
	blob.call(HILL_C.x, HILL_C.y, HILL_BASE + 0.8, 0.3)
	var bytes := PackedByteArray(); bytes.resize(N * N)
	for k in N * N: bytes[k] = int(clampf(buf[k], 0.0, 1.0) * 255.0)
	var img := Image.create_from_data(N, N, false, Image.FORMAT_L8, bytes)
	var tex := ImageTexture.create_from_image(img)
	for gm in _ground_mats:
		(gm as ShaderMaterial).set_shader_parameter("ao_tex", tex)
		(gm as ShaderMaterial).set_shader_parameter("ao_rect", Vector3(x0, z0, size))

# ================================================================ per frame
func _night() -> float:
	var sky = main.get("sky") if is_instance_valid(main) else null
	if is_instance_valid(sky) and sky.has_method("night_factor"): return sky.night_factor()
	var h := GameState.hour()
	return 1.0 if (h >= 20.5 or h < 5.5) else 0.0

func _weather() -> String:
	var sky = main.get("sky") if is_instance_valid(main) else null
	if is_instance_valid(sky) and sky.has_method("weather"): return sky.weather()
	return GameState.weather()

func _process(dt: float) -> void:
	_time += dt
	var t := _time
	var nf := _night()
	var wx := _weather()
	# tide
	var want := 1.0 if _low_tide() else 0.0
	if not is_equal_approx(flats_level, want):
		flats_level = move_toward(flats_level, want, dt / 6.0)
		if want < 0.5 and flats_level < 0.86 and _player_on_flats():
			flats_level = 0.86   # wait until the player has walked off the flats
		_apply_flats()
	# boat + buoys bob
	if _boat:
		_boat.position.y = SEA_Y - 0.12 + sin(t * 1.3) * 0.05
		_boat.rotation = Vector3(sin(t * 1.1) * 0.03, 0.12, sin(t * 0.9 + 1.0) * 0.04)
	for i in _buoys.size():
		var bu: Node3D = _buoys[i]
		bu.position.y = SEA_Y - 0.08 + sin(t * 1.6 + i) * 0.06
		bu.rotation = Vector3(sin(t * 1.2 + i) * 0.1, 0, sin(t * 1.4 + i * 2.0) * 0.1)
	if _blades: _blades.rotation.z -= dt * (0.6 + (0.6 if wx == "rain" else 0.0))
	# lighthouse: lamp glow + beam at night
	if _lh_lamp:
		_lh_lamp.emission_energy_multiplier = lerpf(0.4, 4.0, nf)
		_lh_light.light_energy = nf * 2.5
		_beam.visible = nf > 0.3 or wx == "fog"
		_beam.rotation.y += dt * 0.7
	# sailboats and ferry
	for sb in _sailboats:
		var n: Node3D = sb[0]
		var a: float = sb[2] + t * float(sb[3])
		var r: float = sb[1]
		n.position = Vector3(cos(a) * r, SEA_Y - 0.15 + sin(t * 1.2 + a * 5.0) * 0.06, sin(a) * r)
		n.rotation = Vector3(sin(t + a) * 0.04, -a, sin(t * 0.8 + a) * 0.05)
	if _ferry:
		var period := 300.0
		var ph := fmod(t + 40.0, period) / 200.0
		_ferry.visible = ph < 1.0
		_ferry.position = Vector3(lerpf(-170.0, 170.0, ph), SEA_Y + sin(t * 0.8) * 0.08, -64.0)
	# gulls: glide in circles, flap now and then
	for gu in _gulls:
		var g: Node3D = gu[0]; var c: Vector3 = gu[1]; var r: float = gu[2]; var ph: float = gu[3]
		var a := ph + t * 0.35
		g.position = c + Vector3(cos(a) * r, sin(t * 0.7 + ph) * 0.6, sin(a) * r)
		g.rotation = Vector3(0, -a, 0.25)
		var flap := sin(t * 9.0 + ph) * (0.6 if fmod(t + ph, 6.0) < 1.6 else 0.08)
		(gu[4][0] as Node3D).rotation.z = flap
		(gu[4][1] as Node3D).rotation.z = -flap
		g.visible = wx != "rain" or nf < 0.5
	# butterflies by day, fireflies by night
	var day_ok := nf < 0.3 and wx != "rain" and wx != "fog"
	for f in _flies:
		var g: Node3D = f[0]; var c: Vector3 = f[1]; var ph: float = f[2]
		g.visible = day_ok
		if not day_ok: continue
		g.position = c + Vector3(sin(t * 0.5 + ph) * 1.6, sin(t * 1.7 + ph) * 0.3 + 0.2, sin(t * 0.37 + ph * 2.0) * 1.3)
		g.rotation.y = t * 0.5 + ph
		var fl := sin(t * 18.0 + ph) * 0.9
		(f[3][0] as Node3D).rotation.z = fl
		(f[3][1] as Node3D).rotation.z = -fl
	if _fireflies: _fireflies.emitting = nf > 0.6 and wx != "rain"
	if _petals: _petals.emitting = nf < 0.5 and wx != "rain"

func _player_on_flats() -> bool:
	var pl = main.get("player") if is_instance_valid(main) else null
	if not is_instance_valid(pl) or not (pl is Node3D): return false
	var p: Vector3 = (pl as Node3D).global_position
	return _in_flats(p.x, p.z, -0.3) and dist_in(p.x, p.z) < WALL_D + 1.0

# ================================================================ test camera
const VIEWS := ["close", "plaza", "shop", "pier", "rocks", "hill", "flats", "north", "west", "east", "top", "over"]

func _setup_test() -> void:
	if _args.has("hour"):
		GameState.minute = float(_args["hour"]) * 60.0
	GameState.set_paused(true)
	_test_cam = Camera3D.new(); _test_cam.name = "TestCam"
	_test_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_test_cam.far = 400.0
	add_child(_test_cam)
	if _args.has("snap"):
		_snap_all.call_deferred()

func _view_focus(v: String) -> Vector3:
	match v:
		"plaza": return Vector3(0, 0, 2.5)
		"shop": return spot("shop_counter") + Vector3(1.0, 0, 0)
		"pier": return spot("pier_end") + Vector3(0, 0, -2.0)
		"rocks": return spot("rocks")
		"hill": return spot("hill")
		"flats": return spot("flats")
		"north": return Vector3(-2, 0, -16.5)
		"west": return Vector3(-18.0, 0, 6.0)
		"east": return Vector3(16.5, 0, 4.0)
		"close": return spot("spawn")
	return Vector3.ZERO

func _apply_test_view(v := "") -> void:
	if not is_instance_valid(_test_cam): return
	if v == "": v = str(_args.get("view", "close"))
	if v == "top":
		_test_cam.fov = 62.0
		_test_cam.position = Vector3(0, 62, 44); _test_cam.look_at(Vector3(0, 0, 1.0))
	elif v == "over":
		_test_cam.fov = 55.0
		_test_cam.position = Vector3(26, 22, 44); _test_cam.look_at(Vector3(-2, 0, -4))
	else:
		_test_cam.fov = 32.0
		var f := _view_focus(v) + Vector3(0, 0.7, -1.0)
		var p := deg_to_rad(42.0)
		_test_cam.position = f + Vector3(0, sin(p), cos(p)) * 11.0
		_test_cam.look_at(f)
	_test_cam.current = true

func _snap_all() -> void:
	var prefix: String = _args["snap"]
	var views: Array = VIEWS
	if _args.has("views"): views = str(_args["views"]).split(",")
	await get_tree().create_timer(1.0).timeout
	for v in views:
		_apply_test_view(v)
		for i in 8: await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s%s.png" % [prefix, v])
	get_tree().quit()
