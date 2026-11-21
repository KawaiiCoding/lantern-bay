class_name Toys
extends RefCounted
## Soft toy art kit: every mesh is a smooth primitive with an ink outline (inverted hull).
## All functions are static. Use Toys.add(mesh, material, position, parent).
##
## Extras (World owner):
## - Outlines are a shared shader: width adapts a little to camera distance, tinted ink, dimmed at night
##   through the global shader parameter `lb_ink_light` (SkyCycle drives it).
## - Rounded meshes: rbox(), rcyl(), lathe() give soft edges and gap-free outlines.
## - pmat(color, pattern) is a cached palette material with a procedural surface pattern
##   (PAT_WOOD, PAT_ROOF, PAT_COBBLE, PAT_ROCK, PAT_LEAF, PAT_WALL) used by bake().
## - bake(root) merges every static MeshInstance3D under root into a few vertex-coloured meshes
##   (one draw call + one outline per cell) with wind sway, patterns and cloud shadows in the shader.
## Shaders are GLES3 / gl_compatibility safe.

const INK := Color("6b4a3a")

const PAT_PLAIN := 0
const PAT_WOOD := 1
const PAT_ROOF := 2
const PAT_COBBLE := 3
const PAT_ROCK := 4
const PAT_LEAF := 5
const PAT_WALL := 6

const GLOBALS := {"lb_ink_light": 1.0, "lb_wind": 1.0, "lb_cloud": 0.6, "lb_glow": 0.4, "lb_day": 1.0, "lb_wet": 0.0}

static var _globals_ready := false
static var _outline_cache := {}
static var _pmat_cache := {}
static var _mesh_cache := {}
static var _shaders := {}
static var _shared := {}

# ---------------------------------------------------------------- shader code
const GLSL_COMMON := """
global uniform float lb_wind;
global uniform float lb_cloud;
float lb_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float lb_noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(lb_hash(i), lb_hash(i + vec2(1.0, 0.0)), f.x), mix(lb_hash(i + vec2(0.0, 1.0)), lb_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
// w <= 0: still. 0..1: foliage sway. 2..3: flag flutter (w - 2).
vec3 lb_sway(vec3 wp, float w) {
	if (w <= 0.001) return vec3(0.0);
	float t = TIME;
	float ph = wp.x * 0.35 + wp.z * 0.27;
	if (w < 1.5) {
		vec3 o = vec3(sin(t * 1.3 + ph), 0.0, sin(t * 1.05 + ph * 1.3) * 0.6) * 0.07;
		o.x += sin(t * 3.9 + ph * 3.0) * 0.012;
		return o * w * lb_wind;
	}
	float k = w - 2.0;
	return vec3(sin(t * 5.0 + ph * 6.0) * 0.03, sin(t * 6.3 + ph * 5.0) * 0.05, sin(t * 5.6 + ph * 4.0) * 0.06) * k * (0.5 + lb_wind);
}
float lb_clouds(vec2 xz) {
	vec2 q = xz * 0.05 + vec2(TIME * 0.018, TIME * 0.009);
	float n = lb_noise(q) * 0.65 + lb_noise(q * 2.3 + 7.1) * 0.35;
	return smoothstep(0.48, 0.7, n) * lb_cloud;
}
"""

const GLSL_LIGHT := """
void light() {
	float ndl = dot(NORMAL, LIGHT);
	// soft two-band toon ramp: the shadow side keeps a little bounce, the lit side is flat and clean
	float d = smoothstep(-0.08, 0.16, ndl) * 0.72 + smoothstep(0.3, 0.62, ndl) * 0.28;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * d / PI;
	vec3 h = normalize(VIEW + LIGHT);
	float sp = smoothstep(0.9, 0.965, dot(NORMAL, h)) * 0.22 * (1.25 - ROUGHNESS);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * sp;
	float rim = smoothstep(0.6, 0.95, 1.0 - max(dot(NORMAL, VIEW), 0.0)) * smoothstep(-0.2, 0.4, ndl);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * rim * 0.16;
}
"""

const TOY_SHADER := """
shader_type spatial;
render_mode specular_schlick_ggx;
global uniform float lb_glow;
global uniform float lb_wet;
uniform float glow_mode = 0.0;
varying vec3 wpos;
#COMMON
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += lb_sway(w, UV2.y);
	wpos = w;
}
void fragment() {
	vec3 c = COLOR.rgb;
	float p = floor(UV2.x + 0.001);
	vec2 uv = UV;
	float s = 1.0;
	if (p == 1.0) {
		float fy = fract(uv.y / 0.2);
		float row = floor(uv.y / 0.2);
		float tint = lb_hash(vec2(row, 3.7));
		float fx = fract(uv.x / 1.7 + tint);
		float seam = smoothstep(0.0, 0.07, fy) * smoothstep(1.0, 0.93, fy) * smoothstep(0.0, 0.012, fx) * smoothstep(1.0, 0.988, fx);
		float grain = lb_noise(vec2(uv.x * 2.0, uv.y * 30.0));
		s = mix(0.8, 1.0, seam) * (0.94 + 0.07 * tint) * (0.95 + 0.08 * grain);
	} else if (p == 2.0) {
		float rv = uv.y / 0.26; float row = floor(rv); float fy = fract(rv);
		float u = uv.x / 0.34 + 0.5 * mod(row, 2.0); float fx = fract(u) - 0.5;
		float edge = smoothstep(0.0, 0.3, fy) * (1.0 - 0.18 * smoothstep(0.36, 0.5, abs(fx)) * smoothstep(0.1, 0.6, fy));
		s = mix(0.8, 1.03, edge) * (0.95 + 0.07 * lb_hash(vec2(floor(u), row)));
	} else if (p == 3.0) {
		vec2 q = uv / 0.42; q.x += 0.5 * mod(floor(q.y), 2.0);
		vec2 f = fract(q) - 0.5;
		float d = length(max(abs(f) - 0.3, 0.0));
		s = mix(1.0, 0.84, smoothstep(0.04, 0.12, d)) * (0.94 + 0.09 * lb_hash(floor(q)));
	} else if (p == 4.0) {
		float n = lb_noise(uv * 2.5) * 0.6 + lb_noise(uv * 8.0) * 0.4;
		s = 0.86 + 0.2 * n;
		s *= (lb_hash(floor(uv * 34.0)) > 0.92) ? 0.9 : 1.0;
	} else if (p == 5.0) {
		float n = lb_noise(uv * 2.6) * 0.7 + lb_noise(uv * 7.0) * 0.3;
		s = 0.88 + 0.22 * n;
		c = mix(c, c * vec3(1.06, 1.08, 0.86), smoothstep(0.55, 0.8, n));
	} else if (p == 6.0) {
		s = 0.97 + 0.05 * lb_noise(uv * 5.0);
	}
	float cl = lb_clouds(wpos.xz);
	ALBEDO = c * s * (1.0 - 0.3 * cl);
	ROUGHNESS = clamp(COLOR.a - lb_wet * 0.35, 0.05, 1.0);
	SPECULAR = 0.3 + lb_wet * 0.3;
	if (glow_mode > 0.5) {
		ALBEDO = c * 0.6;
		EMISSION = c * lb_glow;
	}
}
#LIGHT
"""

const OUTLINE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front;
global uniform float lb_ink_light;
uniform vec4 ink : source_color = vec4(0.42, 0.29, 0.23, 1.0);
uniform float width = 0.025;
uniform float baked = 0.0;
varying vec3 vcol;
#COMMON
void vertex() {
	float wd = width;
	if (baked > 0.5) {
		vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		VERTEX += lb_sway(w, UV2.y);
		wd = fract(UV2.x + 0.001) * 0.1;
	}
	vec3 vp = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 vn = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	wd *= clamp(-vp.z / 13.0, 0.7, 1.9);
	vp += vn * wd;
	vp.z -= wd * 0.6;
	POSITION = PROJECTION_MATRIX * vec4(vp, 1.0);
	vcol = COLOR.rgb;
}
void fragment() {
	vec3 k = ink.rgb;
	if (baked > 0.5) k = mix(ink.rgb, vcol * 0.42, 0.35);
	ALBEDO = k * lb_ink_light;
}
"""

## Registers the global shader parameters the world shaders use (safe to call many times).
static func ensure_globals() -> void:
	if _globals_ready: return
	_globals_ready = true
	for k in GLOBALS:
		RenderingServer.global_shader_parameter_add(k, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, GLOBALS[k])

static func set_global(k: String, v: float) -> void:
	ensure_globals()
	RenderingServer.global_shader_parameter_set(k, v)

static func shader(id: String) -> Shader:
	ensure_globals()
	if _shaders.has(id): return _shaders[id]
	var s := Shader.new()
	match id:
		"toy": s.code = TOY_SHADER.replace("#COMMON", GLSL_COMMON).replace("#LIGHT", GLSL_LIGHT)
		"outline": s.code = OUTLINE_SHADER.replace("#COMMON", GLSL_COMMON)
	_shaders[id] = s
	return s

## Shared toon light() function for world shaders in other files.
static func glsl_light() -> String:
	return GLSL_LIGHT

## Common GLSL snippet (noise, wind sway, cloud shadows) for world shaders in other files.
static func glsl_common() -> String:
	ensure_globals()
	return GLSL_COMMON

static func outline_mat(width: float, ink := INK, baked := false) -> ShaderMaterial:
	var key := "%s_%.4f_%s" % [ink.to_html(), width, baked]
	if _outline_cache.has(key): return _outline_cache[key]
	var o := ShaderMaterial.new()
	o.shader = shader("outline")
	o.set_shader_parameter("ink", ink)
	o.set_shader_parameter("width", width)
	o.set_shader_parameter("baked", 1.0 if baked else 0.0)
	_outline_cache[key] = o
	return o

# ---------------------------------------------------------------- materials
static func mat(c: Color, rough := 0.85, outline := 0.025) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	# toon look: soft two-band diffuse, small soft highlight, gentle rim, faint micro-noise (fur/yarn)
	m.roughness = clampf(rough * 0.75, 0.3, 0.7)
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	m.metallic_specular = 0.3
	m.rim_enabled = true
	m.rim = 0.25
	m.rim_tint = 0.6
	m.albedo_texture = micro_noise()
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 3.0
	if outline > 0.0:
		m.next_pass = outline_mat(outline, INK.lerp(c.darkened(0.6), 0.3))
	return m

## Cached palette material with a surface pattern (for static props that get baked). Do not mutate.
static func pmat(c: Color, pattern := PAT_PLAIN, rough := 0.85, outline := 0.025, sway := 0.0) -> StandardMaterial3D:
	var key := "%s_%d_%.2f_%.3f_%.2f" % [c.to_html(), pattern, rough, outline, sway]
	if _pmat_cache.has(key): return _pmat_cache[key]
	var m := mat(c, rough, outline)
	m.set_meta("pattern", pattern)
	m.set_meta("sway", sway)
	_pmat_cache[key] = m
	return m

## Shared faint mottling texture (0.9..1.0 grey) so flat colours never look plastic.
static func micro_noise() -> NoiseTexture2D:
	if not _shared.has("noise"):
		var n := FastNoiseLite.new(); n.frequency = 0.08; n.fractal_octaves = 2
		var t := NoiseTexture2D.new(); t.width = 128; t.height = 128; t.seamless = true; t.noise = n
		var g := Gradient.new(); g.set_color(0, Color(0.88, 0.88, 0.88)); g.set_color(1, Color(1, 1, 1))
		t.color_ramp = g
		_shared["noise"] = t
	return _shared["noise"]

static func glow(c: Color, k := 2.5) -> StandardMaterial3D:
	var m := mat(c, 0.5, 0.0)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = k
	return m

## Shared warm window glass: once baked, brightness follows the global `lb_glow` (night).
static func window_mat() -> StandardMaterial3D:
	if not _shared.has("window"):
		var m := glow(Color("ffd59a"), 0.8)
		m.set_meta("glow_global", true)
		_shared["window"] = m
	return _shared["window"]

static func bulb_mat() -> StandardMaterial3D:
	if not _shared.has("bulb"):
		var m := glow(Color("fff0c0"), 2.0)
		m.set_meta("glow_global", true)
		_shared["bulb"] = m
	return _shared["bulb"]

# ---------------------------------------------------------------- meshes
static func sphere(r: float, seg := 32) -> SphereMesh:
	var s := SphereMesh.new(); s.radius = r; s.height = r * 2.0; s.radial_segments = seg; s.rings = maxi(4, seg / 2)
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

static func _tri(idx: PackedInt32Array, v: PackedVector3Array, n: PackedVector3Array, a: int, b: int, c: int) -> void:
	var cr := (v[b] - v[a]).cross(v[c] - v[a])
	if cr.length_squared() < 1e-14: return
	if cr.dot(n[a] + n[b] + n[c]) > 0.0:
		idx.append(a); idx.append(c); idx.append(b)
	else:
		idx.append(a); idx.append(b); idx.append(c)

static func _quad(idx: PackedInt32Array, v: PackedVector3Array, n: PackedVector3Array, a: int, b: int, c: int, d: int) -> void:
	_tri(idx, v, n, a, b, c); _tri(idx, v, n, a, c, d)

static func arrays_mesh(v: PackedVector3Array, n: PackedVector3Array, idx: PackedInt32Array, col := PackedColorArray()) -> ArrayMesh:
	var a := []; a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = v; a[Mesh.ARRAY_NORMAL] = n; a[Mesh.ARRAY_INDEX] = idx
	if col.size() == v.size(): a[Mesh.ARRAY_COLOR] = col
	var m := ArrayMesh.new(); m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return m

static func _rb_coords(h: float, r: float, seg: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in seg + 1: out.append(-h + r * (1.0 - cos(k * PI * 0.5 / seg)))
	for k in seg + 1: out.append(h - r + r * sin(k * PI * 0.5 / seg))
	return out

## Rounded box (soft edges, smooth normals so the outline never cracks at corners). Centered like BoxMesh.
static func rbox(x: float, y: float, z: float, r := 0.08, seg := 3) -> ArrayMesh:
	var key := "rb_%.3f_%.3f_%.3f_%.3f_%d" % [x, y, z, r, seg]
	if _mesh_cache.has(key): return _mesh_cache[key]
	var h := Vector3(x, y, z) * 0.5
	r = minf(r, minf(h.x, minf(h.y, h.z)) * 0.98)
	var inner := h - Vector3.ONE * r
	var v := PackedVector3Array(); var n := PackedVector3Array(); var idx := PackedInt32Array()
	for a in 3:
		for sg in [-1.0, 1.0]:
			var u := (a + 1) % 3; var w := (a + 2) % 3
			var cu := _rb_coords(h[u], r, seg); var cw := _rb_coords(h[w], r, seg)
			var base := v.size()
			for i in cu.size():
				for j in cw.size():
					var p := Vector3.ZERO
					p[a] = h[a] * sg; p[u] = cu[i]; p[w] = cw[j]
					var inn := p.clamp(-inner, inner)
					var d := p - inn
					var nn := Vector3.ZERO
					if d.length_squared() > 1e-10: nn = d.normalized()
					else: nn[a] = sg
					v.append(inn + nn * r); n.append(nn)
			var nj := cw.size()
			for i in cu.size() - 1:
				for j in nj - 1:
					var a0 := base + i * nj + j
					_quad(idx, v, n, a0, a0 + nj, a0 + nj + 1, a0 + 1)
	var m := arrays_mesh(v, n, idx)
	_mesh_cache[key] = m
	return m

## Surface of revolution around Y from a (radius, y) profile listed bottom to top.
static func lathe(profile: PackedVector2Array, seg := 24) -> ArrayMesh:
	var v := PackedVector3Array(); var n := PackedVector3Array(); var idx := PackedInt32Array()
	var cnt := profile.size()
	for i in cnt:
		var t: Vector2 = profile[mini(i + 1, cnt - 1)] - profile[maxi(i - 1, 0)]
		var nn := Vector2(t.y, -t.x).normalized()
		for k in seg + 1:
			var ang := TAU * float(k) / float(seg)
			var cs := cos(ang); var sn := sin(ang)
			v.append(Vector3(profile[i].x * cs, profile[i].y, profile[i].x * sn))
			n.append(Vector3(nn.x * cs, nn.y, nn.x * sn).normalized())
	for i in cnt - 1:
		for k in seg:
			var a := i * (seg + 1) + k
			_quad(idx, v, n, a, a + 1, a + seg + 2, a + seg + 1)
	return arrays_mesh(v, n, idx)

## Rounded cylinder / cone (soft bevelled rims). Centered like CylinderMesh.
static func rcyl(top: float, bot: float, h: float, bevel := 0.06, seg := 24) -> ArrayMesh:
	var key := "rc_%.3f_%.3f_%.3f_%.3f_%d" % [top, bot, h, bevel, seg]
	if _mesh_cache.has(key): return _mesh_cache[key]
	var b := minf(bevel, h * 0.45)
	b = minf(b, bot * 0.9)
	if top > 0.01: b = minf(b, top * 0.9)
	b = maxf(b, 0.001)
	var y0 := -h * 0.5; var y1 := h * 0.5
	var p := PackedVector2Array()
	p.append(Vector2(0, y0))
	for k in 5:
		var a := -PI * 0.5 + PI * 0.5 * k / 4.0
		p.append(Vector2(bot - b + b * cos(a), y0 + b + b * sin(a)))
	if top > 0.01:
		for k in 5:
			var a := PI * 0.5 * k / 4.0
			p.append(Vector2(top - b + b * cos(a), y1 - b + b * sin(a)))
	p.append(Vector2(0, y1))
	var m := lathe(p, seg)
	_mesh_cache[key] = m
	return m

# ---------------------------------------------------------------- scene helpers
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
		add(rcyl(0.015, 0.13, 0.26, 0.03, 12), fur, Vector3(0.2 * s, 0.33, 0), h, Vector3.ONE, Vector3(0, 0, -0.3 * s))
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
	add(rbox(0.55, 0.32, 0.45, 0.06), mat(Color("c98a5a")), Vector3(0, 1.25, -1.05), g)
	add(cyl(0.1, 0.08, 0.22), cream, Vector3(0.1, 1.55, -1.05), g)
	add(cyl(0.105, 0.105, 0.05), mat(Color("e58a94")), Vector3(0.1, 1.67, -1.05), g)
	var beam := SpotLight3D.new(); beam.light_color = Color("fff1c4"); beam.light_energy = 3.0; beam.spot_range = 8.0; beam.spot_angle = 28
	beam.position = Vector3(0, 1.4, 0.95); g.add_child(beam)
	return g

static func fish(parent: Node3D, body: Color, fin: Color, length := 1.0) -> Node3D:
	var g := group(Vector3.ZERO, parent, 0, length)
	add(sphere(0.3), mat(body, 0.4), Vector3.ZERO, g, Vector3(0.6, 0.8, 1.4))
	var t := PrismMesh.new(); t.size = Vector3(0.05, 0.45, 0.35)
	add(t, mat(fin), Vector3(0, 0, -0.5), g, Vector3.ONE, Vector3(PI / 2, 0, 0))
	add(sphere(0.05), mat(Color("3b2a24"), 0.2, 0.0), Vector3(0.14, 0.06, 0.28), g)
	add(sphere(0.05), mat(Color("3b2a24"), 0.2, 0.0), Vector3(-0.14, 0.06, 0.28), g)
	return g

# ---------------------------------------------------------------- props
## Cottage: rounded walls, two-slab tiled roof with overhang, door, glowing windows, flower box, chimney.
## The front (door side) faces +Z. The chimney top is child "ChimneyTop".
static func house(parent: Node3D, pos: Vector3, rot_y: float, wall: Color, roof: Color, w := 3.2, h := 2.6, d := 2.6) -> Node3D:
	var g := group(pos, parent, rot_y)
	var wm := pmat(wall, PAT_WALL)
	add(rbox(w, h, d, 0.12), wm, Vector3(0, h / 2, 0), g)
	add(rbox(w + 0.14, 0.22, d + 0.14, 0.08), pmat(wall.darkened(0.12), PAT_ROCK), Vector3(0, 0.11, 0), g)
	var rise := minf(1.25, w * 0.42)
	var pr := PrismMesh.new(); pr.size = Vector3(w - 0.06, rise, d - 0.08)
	add(pr, pmat(wall, PAT_WALL, 0.85, 0.0), Vector3(0, h + rise * 0.5 - 0.02, 0), g)
	var pitch := atan2(rise, w * 0.5)
	var half := w * 0.5 + 0.32
	var slab := half / cos(pitch) + 0.08
	var rm := pmat(roof, PAT_ROOF)
	for s in [-1.0, 1.0]:
		var sl := add(rbox(slab, 0.2, d + 0.55, 0.08), rm, Vector3.ZERO, g)
		sl.rotation = Vector3(0, 0, -s * pitch)
		# slab centre sits on the roof plane, half way down from the ridge
		var dir := Vector3(s * cos(pitch), -sin(pitch), 0)
		sl.position = Vector3(0, h + rise + 0.08, 0) + dir * (slab * 0.5 - 0.04)
	add(rcyl(0.11, 0.11, d + 0.62, 0.05, 12), pmat(roof.darkened(0.15)), Vector3(0, h + rise + 0.12, 0), g, Vector3.ONE, Vector3(PI / 2, 0, 0))
	# door
	add(rbox(0.78, 1.45, 0.14, 0.06), pmat(Color("9a6e5a"), PAT_WOOD), Vector3(w * 0.22, 0.8, d / 2 + 0.02), g)
	add(sphere(0.045, 10), pmat(Color("f2d27a"), PAT_PLAIN, 0.3, 0.0), Vector3(w * 0.22 - 0.25, 0.82, d / 2 + 0.11), g)
	add(rbox(1.0, 0.1, 0.5, 0.04), pmat(Color("d8c8b8"), PAT_COBBLE), Vector3(w * 0.22, 0.05, d / 2 + 0.3), g)
	# front window: frame + glass + mullion + flower box
	var wx := -w * 0.22
	add(rbox(0.95, 0.85, 0.1, 0.05), pmat(Color("fff8ee")), Vector3(wx, 1.45, d / 2 + 0.02), g)
	add(rbox(0.75, 0.65, 0.06, 0.02), window_mat(), Vector3(wx, 1.45, d / 2 + 0.06), g)
	add(rbox(0.05, 0.62, 0.05, 0.02), pmat(Color("fff8ee"), PAT_PLAIN, 0.85, 0.0), Vector3(wx, 1.45, d / 2 + 0.1), g)
	add(rbox(1.1, 0.16, 0.26, 0.05), pmat(Color("c98a5a"), PAT_WOOD), Vector3(wx, 0.96, d / 2 + 0.14), g)
	for i in 5:
		var f: Color = [Color("f4a9a8"), Color("fff1b8"), Color("c9b6e4")][i % 3]
		add(sphere(0.085, 10), pmat(f, PAT_PLAIN, 0.9, 0.012, 0.4), Vector3(wx - 0.4 + i * 0.2, 1.08, d / 2 + 0.16), g)
	# side windows
	for s in [-1.0, 1.0]:
		add(rbox(0.1, 0.7, 0.7, 0.04), pmat(Color("fff8ee")), Vector3(s * (w / 2 + 0.02), 1.5, 0), g)
		add(rbox(0.06, 0.52, 0.52, 0.02), window_mat(), Vector3(s * (w / 2 + 0.06), 1.5, 0), g)
	# chimney
	add(rbox(0.42, 1.1, 0.42, 0.06), pmat(Color("c98a5a"), PAT_ROCK), Vector3(w / 2 - 0.6, h + rise * 0.6 + 0.2, -0.45), g)
	var top := Node3D.new(); top.name = "ChimneyTop"; top.position = Vector3(w / 2 - 0.6, h + rise * 0.6 + 0.8, -0.45); g.add_child(top)
	return g

## Soft canopy blob (lathe): an egg with a slightly flattened base. `tall` stretches it (cypress-like).
static func canopy_mesh(r := 0.9, tall := 1.0) -> ArrayMesh:
	var key := "canopy_%.2f_%.2f" % [r, tall]
	if _mesh_cache.has(key): return _mesh_cache[key]
	var h := r * 1.7 * tall
	var p := PackedVector2Array()
	p.append(Vector2(0.0, 0.0))
	for k in 13:
		var t := float(k) / 12.0
		var a := t * PI
		# egg: wider low, rounder top; flattened bottom
		var rad := sin(a) * r * (1.0 + 0.12 * cos(a))
		var y := (1.0 - cos(a)) * 0.5 * h
		if k == 0: continue
		p.append(Vector2(maxf(rad, 0.0), y))
	var m := lathe(p, 22)
	_mesh_cache[key] = m
	return m

## Neat tree: one smooth canopy (with a smaller side lobe on bigger trees). Sways once baked.
static func tree(parent: Node3D, pos: Vector3, s := 1.0, c := Color("8cc79a")) -> Node3D:
	var g := group(pos, parent, pos.x * 0.77, s)
	add(rcyl(0.11, 0.19, 1.3, 0.05, 10), pmat(Color("9a7058"), PAT_WOOD, 0.9, 0.025, 0.15), Vector3(0, 0.65, 0), g)
	add(canopy_mesh(0.95, 1.0), pmat(c, PAT_LEAF, 0.8, 0.025, 1.0), Vector3(0, 1.05, 0), g)
	return g

## Tall cypress-like tree (narrow silhouette).
static func pine(parent: Node3D, pos: Vector3, s := 1.0, c := Color("6fae8a")) -> Node3D:
	var g := group(pos, parent, 0, s)
	add(rcyl(0.09, 0.14, 0.7, 0.04, 8), pmat(Color("9a7058"), PAT_WOOD), Vector3(0, 0.35, 0), g)
	add(canopy_mesh(0.6, 2.2), pmat(c, PAT_LEAF, 0.8, 0.025, 0.8), Vector3(0, 0.45, 0), g)
	return g

## Low rounded bush: one smooth dome, optional sparse flower dots.
static func bush(parent: Node3D, pos: Vector3, s := 1.0, c := Color("9fd39a"), dots := Color(0, 0, 0, 0)) -> Node3D:
	var g := group(pos, parent, pos.x * 1.7, s)
	add(canopy_mesh(0.6, 0.62), pmat(c, PAT_LEAF, 0.8, 0.025, 0.45), Vector3(0, -0.02, 0), g, Vector3(1.25, 1, 1))
	if dots.a > 0.0:
		var dm := pmat(dots, PAT_PLAIN, 0.9, 0.0, 0.45)
		for i in 5:
			var a := i * 2.4 + 0.3
			add(sphere(0.055, 8), dm, Vector3(cos(a) * 0.55, 0.38 + 0.1 * sin(i * 1.7), sin(a) * 0.42), g)
	return g

static func flower(parent: Node3D, pos: Vector3, c: Color, s := 1.0) -> Node3D:
	var g := group(pos, parent, pos.z * 2.3, s)
	add(rcyl(0.012, 0.016, 0.3, 0.005, 5), pmat(Color("7fb87a"), PAT_PLAIN, 0.9, 0.0, 1.0), Vector3(0, 0.15, 0), g)
	add(sphere(0.085, 8), pmat(c, PAT_PLAIN, 0.9, 0.012, 1.0), Vector3(0, 0.32, 0), g, Vector3(1, 0.6, 1))
	add(sphere(0.035, 6), pmat(Color("f6c75e"), PAT_PLAIN, 0.9, 0.0, 1.0), Vector3(0, 0.36, 0), g)
	return g

## Small grass tuft (three soft blades).
static func tuft(parent: Node3D, pos: Vector3, c := Color("8fca7e"), s := 1.0) -> Node3D:
	var g := group(pos, parent, pos.x * 3.1, s)
	var m := pmat(c, PAT_PLAIN, 0.95, 0.0, 1.0)
	for i in 3:
		var a := i * TAU / 3.0
		add(rcyl(0.0, 0.05, 0.34, 0.02, 5), m, Vector3(cos(a) * 0.05, 0.15, sin(a) * 0.05), g, Vector3.ONE, Vector3(sin(a) * 0.35, 0, cos(a) * 0.35))
	return g

static func rock(parent: Node3D, pos: Vector3, s := 1.0, c := Color("b9b4c4"), rot := 0.0) -> Node3D:
	var g := group(pos, parent, rot, s)
	var m := pmat(c, PAT_ROCK, 0.95)
	add(sphere(0.6, 14), m, Vector3(0, 0.2, 0), g, Vector3(1.2, 0.7, 1.0))
	add(sphere(0.38, 12), pmat(c.lightened(0.06), PAT_ROCK, 0.95), Vector3(0.45, 0.12, 0.25), g, Vector3(1, 0.75, 1))
	return g

## Picket fence from a to b (ground points). Returns the group.
static func fence(parent: Node3D, a: Vector3, b: Vector3, c := Color("fff8ee"), height := 0.75) -> Node3D:
	var g := group(a, parent)
	var dv := b - a; var L := Vector2(dv.x, dv.z).length()
	g.rotation.y = atan2(-dv.z, dv.x)
	var m := pmat(c, PAT_WOOD)
	var n := maxi(1, int(round(L / 0.42)))
	for i in n + 1:
		var x := L * i / n
		add(rbox(0.13, height, 0.07, 0.04), m, Vector3(x, height * 0.5, 0), g)
		add(sphere(0.065, 8), m, Vector3(x, height, 0), g, Vector3(1, 0.8, 0.55))
	for y in [height * 0.32, height * 0.72]:
		add(rbox(L + 0.1, 0.09, 0.05, 0.03), m, Vector3(L * 0.5, y, -0.05), g)
	return g

static func bench(parent: Node3D, pos: Vector3, rot_y := 0.0, c := Color("c98a5a")) -> Node3D:
	var g := group(pos, parent, rot_y)
	var m := pmat(c, PAT_WOOD); var leg := pmat(Color("6e6390"), PAT_PLAIN, 0.6)
	for i in 3:
		add(rbox(1.6, 0.07, 0.15, 0.03), m, Vector3(0, 0.45, -0.17 + i * 0.17), g)
	for i in 2:
		add(rbox(1.6, 0.14, 0.06, 0.03), m, Vector3(0, 0.72 + i * 0.2, -0.3), g, Vector3.ONE, Vector3(-0.15, 0, 0))
	for x in [-0.65, 0.65]:
		add(rbox(0.08, 0.45, 0.5, 0.03), leg, Vector3(x, 0.22, -0.02), g)
		add(rbox(0.07, 0.55, 0.07, 0.03), leg, Vector3(x, 0.75, -0.3), g)
	return g

## Street lamp: post + bulb (glows with `lb_glow`) + OmniLight in group "lamp_light" (SkyCycle dims it by day).
static func lamp(parent: Node3D, pos: Vector3) -> Node3D:
	var g := group(pos, parent)
	var post := pmat(Color("6e6390"), PAT_PLAIN, 0.6)
	add(rcyl(0.14, 0.18, 0.2, 0.05, 12), post, Vector3(0, 0.1, 0), g)
	add(rcyl(0.05, 0.065, 2.3, 0.02, 10), post, Vector3(0, 1.25, 0), g)
	add(rcyl(0.06, 0.2, 0.12, 0.04, 12), post, Vector3(0, 2.36, 0), g)
	add(sphere(0.19, 14), bulb_mat(), Vector3(0, 2.55, 0), g)
	add(rcyl(0.04, 0.25, 0.14, 0.05, 12), post, Vector3(0, 2.78, 0), g)
	add(sphere(0.05, 8), post, Vector3(0, 2.88, 0), g)
	var l := OmniLight3D.new(); l.light_color = Color("ffd89a"); l.light_energy = 1.4; l.omni_range = 5.5
	l.omni_attenuation = 1.3
	l.position = Vector3(0, 2.4, 0); l.add_to_group("lamp_light"); l.set_meta("base_energy", 2.6)
	g.add_child(l)
	return g

## Old harbour lantern post. Child "Head" (Node3D) is where the light goes; its glass mesh is "Glass".
static func lantern_post(parent: Node3D, pos: Vector3) -> Node3D:
	var g := group(pos, parent)
	var iron := pmat(Color("57506e"), PAT_PLAIN, 0.55)
	add(rcyl(0.32, 0.4, 0.3, 0.08, 16), pmat(Color("c8c2cf"), PAT_ROCK), Vector3(0, 0.15, 0), g)
	add(rcyl(0.08, 0.11, 2.6, 0.03, 12), iron, Vector3(0, 1.55, 0), g)
	add(torus(0.07, 0.13), iron, Vector3(0, 0.6, 0), g)
	var head := group(Vector3(0, 3.1, 0), g); head.name = "Head"
	var gm := mat(Color("aab3c8"), 0.25, 0.02)
	gm.set_meta("nobake", true)
	var glass := add(rcyl(0.22, 0.17, 0.5, 0.06, 6), gm, Vector3.ZERO, head)
	glass.name = "Glass"; glass.set_meta("nobake", true)
	add(rcyl(0.04, 0.33, 0.22, 0.06, 6), iron, Vector3(0, 0.36, 0), head)
	add(sphere(0.07, 8), iron, Vector3(0, 0.5, 0), head)
	add(rcyl(0.26, 0.26, 0.08, 0.03, 6), iron, Vector3(0, -0.28, 0), head)
	return g

static func boat(parent: Node3D, pos: Vector3, rot_y := 0.0, c := Color("fffaf2"), trim := Color("e8747f")) -> Node3D:
	var g := group(pos, parent, rot_y)
	add(sphere(0.9, 24), pmat(c, PAT_WOOD, 0.6), Vector3(0, 0.15, 0), g, Vector3(0.85, 0.5, 1.9))
	add(torus(0.78, 0.92), pmat(trim), Vector3(0, 0.42, 0), g, Vector3(0.85, 1.4, 1.9))
	add(rbox(1.25, 0.08, 2.6, 0.03), pmat(Color("c99a6e"), PAT_WOOD), Vector3(0, 0.38, 0), g)
	add(rbox(1.3, 0.1, 0.3, 0.04), pmat(Color("c99a6e"), PAT_WOOD), Vector3(0, 0.5, 0.3), g)
	add(rcyl(0.04, 0.05, 2.2, 0.02, 8), pmat(Color("9a7058"), PAT_WOOD), Vector3(0, 1.4, 0.6), g)
	var sail := PrismMesh.new(); sail.size = Vector3(1.2, 1.6, 0.04); sail.left_to_right = 0.0
	add(sail, pmat(Color("fff1df"), PAT_PLAIN, 0.9, 0.015), Vector3(0, 1.45, 0.0), g, Vector3.ONE, Vector3(0, PI / 2, 0))
	return g

static func crate(parent: Node3D, pos: Vector3, s := 1.0, rot := 0.0, c := Color("d4a373")) -> Node3D:
	var g := group(pos, parent, rot, s)
	add(rbox(0.6, 0.45, 0.45, 0.05), pmat(c, PAT_WOOD), Vector3(0, 0.225, 0), g)
	return g

## Smooth low cloud: flat-bottomed soft dome, wide and calm (no bubble clusters).
static func cloud(parent: Node3D, pos: Vector3, s := 1.0, c := Color("ffffff")) -> Node3D:
	var g := group(pos, parent, pos.x * 0.3, s)
	var m := mat(c, 1.0, 0.0)
	m.rim = 0.5
	m.albedo_texture = null
	add(canopy_mesh(1.6, 0.55), m, Vector3.ZERO, g, Vector3(2.0, 1.0, 1.1))
	add(canopy_mesh(1.1, 0.6), m, Vector3(1.6, -0.05, 0.3), g, Vector3(1.6, 1.0, 1.0))
	return g

## Flat ribbon along a polyline (roads, paths) with soft bevelled edges sinking into the ground.
static func ribbon(pts: PackedVector3Array, width: float, closed := false, y := 0.03, edge := 0.12) -> ArrayMesh:
	var v := PackedVector3Array(); var n := PackedVector3Array(); var idx := PackedInt32Array()
	var cnt := pts.size()
	for i in cnt:
		var prev: Vector3 = pts[(i - 1 + cnt) % cnt] if (closed or i > 0) else pts[i]
		var next: Vector3 = pts[(i + 1) % cnt] if (closed or i < cnt - 1) else pts[i]
		var t := (next - prev); t.y = 0; t = t.normalized()
		var side := Vector3(-t.z, 0, t.x)
		var hw := width * 0.5
		v.append(pts[i] - side * (hw + edge) + Vector3(0, y - 0.05, 0)); n.append((Vector3.UP - side * 0.5).normalized())
		v.append(pts[i] - side * hw + Vector3(0, y, 0)); n.append(Vector3.UP)
		v.append(pts[i] + side * hw + Vector3(0, y, 0)); n.append(Vector3.UP)
		v.append(pts[i] + side * (hw + edge) + Vector3(0, y - 0.05, 0)); n.append((Vector3.UP + side * 0.5).normalized())
	var segs := cnt if closed else cnt - 1
	for i in segs:
		var a := i * 4; var b := ((i + 1) % cnt) * 4
		for k in 3:
			_quad(idx, v, n, a + k, b + k, b + k + 1, a + k + 1)
	return arrays_mesh(v, n, idx)

# ---------------------------------------------------------------- bake
## Merge every static MeshInstance3D under `root` into vertex-coloured meshes, one per `cell` metres
## (plus outline pass). Materials made with mat()/pmat() are read for colour, roughness, outline width,
## pattern and sway. Skipped: meshes or materials with meta "nobake", transparent materials, and
## emissive ones that are not window_mat()/bulb_mat(). Returns the number of meshes merged.
static func bake(root: Node3D, cell := 14.0) -> int:
	var inv := root.global_transform.affine_inverse()
	var groups := {}
	var merged := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null or mi.has_meta("nobake") or not mi.is_visible_in_tree(): continue
		var m := mi.material_override as StandardMaterial3D
		if m == null or m.has_meta("nobake") or m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: continue
		var glow_g := false
		if m.emission_enabled:
			if not m.get_meta("glow_global", false): continue
			glow_g = true
		var outline := 0.0
		if m.next_pass is ShaderMaterial:
			outline = float((m.next_pass as ShaderMaterial).get_shader_parameter("width"))
		var pattern: int = int(m.get_meta("pattern", 0))
		var sway: float = float(m.get_meta("sway", 0.0))
		var xf: Transform3D = inv * mi.global_transform
		var anc: Node = mi
		while anc.get_parent() != root and anc.get_parent() != null: anc = anc.get_parent()
		var base_y := xf.origin.y
		if anc is Node3D: base_y = (inv * (anc as Node3D).global_transform).origin.y
		var kind := "g" if glow_g else ("o" if outline > 0.0 else "n")
		var key := "%d_%d_%s" % [int(floor(xf.origin.x / cell)), int(floor(xf.origin.z / cell)), kind]
		if not groups.has(key):
			groups[key] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "uv": PackedVector2Array(), "uv2": PackedVector2Array(), "i": PackedInt32Array(), "kind": kind}
		var gr: Dictionary = groups[key]
		var arr := mi.mesh.surface_get_arrays(0)
		var sv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var sn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var si = arr[Mesh.ARRAY_INDEX]
		var col := m.albedo_color.srgb_to_linear()
		col.a = m.roughness
		var nb := xf.basis.inverse().transposed()
		var scl := xf.basis.get_scale()
		var sz := mi.mesh.get_aabb().size * scl
		var long_axis := 0
		if sz.y >= sz.x and sz.y >= sz.z: long_axis = 1
		elif sz.z >= sz.x: long_axis = 2
		var uv2x := float(pattern) + clampf(outline * 10.0, 0.0, 0.95)
		var gv: PackedVector3Array = gr["v"]; var gn: PackedVector3Array = gr["n"]; var gc: PackedColorArray = gr["c"]
		var guv: PackedVector2Array = gr["uv"]; var guv2: PackedVector2Array = gr["uv2"]; var gi: PackedInt32Array = gr["i"]
		var off := gv.size()
		var roof_flip := xf.basis.x.y < 0.0
		var wood_off := Vector2(xf.origin.x * 0.37, xf.origin.z * 0.61)
		for k in sv.size():
			var lv: Vector3 = sv[k]
			var wp := xf * lv
			gv.append(wp)
			gn.append((nb * sn[k]).normalized())
			gc.append(col)
			var uv := Vector2.ZERO
			if pattern == PAT_WOOD:
				var ls := lv * scl
				if long_axis == 0: uv = Vector2(ls.x, ls.z + ls.y)
				elif long_axis == 1: uv = Vector2(ls.y, ls.x + ls.z)
				else: uv = Vector2(ls.z, ls.x + ls.y)
				uv += wood_off
			elif pattern == PAT_ROOF:
				var ls := lv * scl
				uv = Vector2(ls.z, -ls.x if roof_flip else ls.x)
			elif pattern == PAT_COBBLE:
				uv = Vector2(wp.x, wp.z)
			else:
				uv = Vector2(wp.x + wp.z * 0.6, wp.y + wp.z * 0.4)
			guv.append(uv)
			var sw := 0.0
			if sway > 0.0:
				sw = sway * clampf((wp.y - base_y) / 2.6, 0.0, 1.0) if sway <= 1.0 else sway
			guv2.append(Vector2(uv2x, sw))
		if si == null or (si as PackedInt32Array).size() == 0:
			for k in sv.size(): gi.append(off + k)
		else:
			for k in (si as PackedInt32Array): gi.append(off + k)
		gr["v"] = gv; gr["n"] = gn; gr["c"] = gc; gr["uv"] = guv; gr["uv2"] = guv2; gr["i"] = gi
		mi.get_parent().remove_child(mi)
		mi.queue_free()
		merged += 1
	var toy := ShaderMaterial.new(); toy.shader = shader("toy")
	toy.next_pass = outline_mat(1.0, INK, true)
	var flat := ShaderMaterial.new(); flat.shader = shader("toy")
	var glowm := ShaderMaterial.new(); glowm.shader = shader("toy"); glowm.set_shader_parameter("glow_mode", 1.0)
	for key in groups:
		var gr: Dictionary = groups[key]
		var a := []; a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = gr["v"]; a[Mesh.ARRAY_NORMAL] = gr["n"]; a[Mesh.ARRAY_COLOR] = gr["c"]
		a[Mesh.ARRAY_TEX_UV] = gr["uv"]; a[Mesh.ARRAY_TEX_UV2] = gr["uv2"]; a[Mesh.ARRAY_INDEX] = gr["i"]
		var am := ArrayMesh.new(); am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		var out := MeshInstance3D.new(); out.name = "Baked_" + str(key)
		out.mesh = am
		match gr["kind"]:
			"o": out.material_override = toy
			"g": out.material_override = glowm
			_: out.material_override = flat
		root.add_child(out)
	return merged
