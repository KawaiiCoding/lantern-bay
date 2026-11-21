extends Node
## SkyCycle (World owner): WorldEnvironment + sun/moon from GameState time and weather.
## Morning soft, afternoon warm, golden evening, blue hour, deep blue night (moon, stars, lamps on).
## Weather: cloudy (softer light), rain (dark, streaks + splash rings), fog (dense pastel fog).
## Drives global shader params (Toys): lb_ink_light, lb_glow, lb_day, lb_cloud, lb_wet, lb_wind,
## and the energy of every light in group "lamp_light" (meta base_energy).
## Debug: `-- weather=rain|fog|cloudy|sunny` forces the weather visuals.

var main: Node
var force_weather := ""
var env: Environment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var rain: CPUParticles3D
var splash: CPUParticles3D
var mist: CPUParticles3D
var _compat := false
var _nf := 0.0
var _wx := {"cloud": 0.0, "rain": 0.0, "fog": 0.0}
var _first := true

# hour, sky top, horizon, light colour, light energy, ambient colour, ambient energy
const KEYS := [
	[0.0, "141d45", "2c3a72", "a9bcff", 0.32, "4a5a9a", 0.42],
	[5.0, "1c2550", "4a4a80", "a9bcff", 0.25, "50609e", 0.42],
	[6.3, "7f9fd6", "ffc3a8", "ffc49a", 0.9, "b8a8c8", 0.45],
	[8.5, "7fbcef", "fde1c6", "fff0d8", 1.6, "b4c8e4", 0.5],
	[12.5, "62aaea", "cfe6f5", "fff6e8", 1.85, "bcd0ea", 0.52],
	[16.0, "72aee8", "f8dfc0", "ffe6c0", 1.75, "cfc4d8", 0.5],
	[18.2, "8099d8", "ffbf86", "ffb46a", 1.45, "d8b4a8", 0.46],
	[19.4, "6a6cb8", "ff9a86", "ff8f66", 0.75, "b08eb4", 0.44],
	[20.2, "3a3f88", "8e70b0", "9fb0ff", 0.2, "6a6aa8", 0.42],
	[21.3, "18214f", "34427c", "a9bcff", 0.32, "4a5a9a", 0.42],
	[24.0, "141d45", "2c3a72", "a9bcff", 0.32, "4a5a9a", 0.42],
]

const SKY_SHADER := """
shader_type sky;
uniform vec3 top_color : source_color;
uniform vec3 horizon_color : source_color;
uniform vec3 bottom_color : source_color;
uniform float stars = 0.0;
uniform vec3 moon_dir = vec3(0.3, 0.6, -0.7);
uniform float moon = 0.0;
float h1(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
void sky() {
	float y = EYEDIR.y;
	vec3 c = mix(horizon_color, top_color, smoothstep(0.0, 0.55, y));
	c = mix(c, bottom_color, smoothstep(0.0, -0.2, y));
	float sd = max(dot(EYEDIR, LIGHT0_DIRECTION), 0.0);
	c += LIGHT0_COLOR * (pow(sd, 48.0) * 0.35 + pow(sd, 6.0) * 0.08) * (1.0 - moon);
	vec3 cell = floor(EYEDIR * 160.0);
	float h = h1(cell);
	float tw = 0.6 + 0.4 * sin(TIME * 2.0 + h * 60.0);
	c += vec3(step(0.996, h) * tw * stars * smoothstep(0.02, 0.25, y));
	float md = dot(EYEDIR, normalize(moon_dir));
	c += vec3(1.0, 0.97, 0.88) * smoothstep(0.9993, 0.9996, md) * moon;
	c += vec3(0.5, 0.6, 0.9) * pow(max(md, 0.0), 200.0) * 0.35 * moon;
	COLOR = c;
}
"""

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=", true, 1)
		if kv.size() == 2 and kv[0] == "weather": force_weather = kv[1]
	Toys.ensure_globals()
	_compat = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	var mobile := RenderingServer.get_current_rendering_method() == "mobile"
	var we := WorldEnvironment.new(); we.name = "WorldEnvironment"
	env = Environment.new()
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new(); var sh := Shader.new(); sh.code = SKY_SHADER; sky_mat.shader = sh
	sky.sky_material = sky_mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.9
	env.tonemap_white = 5.0
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 0.95
	env.ssao_enabled = not _compat and not mobile
	env.ssao_radius = 1.0; env.ssao_intensity = 1.6; env.ssao_power = 1.4
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 45.0; env.fog_depth_end = 190.0; env.fog_depth_curve = 1.2
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.1
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new(); sun.name = "Sun"
	sun.shadow_enabled = true
	sun.shadow_blur = 1.4
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 40.0
	sun.light_angular_distance = 1.0
	add_child(sun)
	_build_weather_fx()
	_update(0.0)

func setup(m) -> void:
	main = m

func weather() -> String:
	return force_weather if force_weather != "" else GameState.weather()

func hour() -> float:
	return GameState.hour()

func is_night() -> bool:
	var h := hour()
	return h >= 20.5 or h < 5.5

## 0 = full day .. 1 = full night (smooth through dusk and dawn).
func night_factor() -> float:
	return _nf

func _key(h: float) -> Array:
	for i in KEYS.size() - 1:
		var a: Array = KEYS[i]; var b: Array = KEYS[i + 1]
		if h >= a[0] and h <= b[0]:
			var t := smoothstep(0.0, 1.0, (h - a[0]) / maxf(0.001, b[0] - a[0]))
			return [Color(a[1]).lerp(Color(b[1]), t), Color(a[2]).lerp(Color(b[2]), t), Color(a[3]).lerp(Color(b[3]), t),
				lerpf(a[4], b[4], t), Color(a[5]).lerp(Color(b[5]), t), lerpf(a[6], b[6], t)]
	return _key(0.0)

func _build_weather_fx() -> void:
	rain = CPUParticles3D.new(); rain.name = "Rain"
	rain.amount = 500; rain.lifetime = 0.9
	rain.mesh = Toys.box(0.015, 0.5, 0.015)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(0.85, 0.9, 1.0, 0.45)
	rain.material_override = rm
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(12, 0.5, 14)
	rain.direction = Vector3(0.1, -1, 0); rain.spread = 3.0
	rain.initial_velocity_min = 16.0; rain.initial_velocity_max = 20.0
	rain.gravity = Vector3(0, -6, 0)
	rain.particle_flag_align_y = true
	rain.emitting = false
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rain)
	splash = CPUParticles3D.new(); splash.name = "Splash"
	splash.amount = 60; splash.lifetime = 0.5
	splash.mesh = Toys.torus(0.06, 0.09)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.vertex_color_use_as_albedo = true
	splash.material_override = sm
	splash.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	splash.emission_box_extents = Vector3(10, 0.0, 12)
	splash.gravity = Vector3.ZERO
	var sc := Curve.new(); sc.add_point(Vector2(0, 0.4)); sc.add_point(Vector2(1, 2.2))
	splash.scale_amount_curve = sc
	var sg := Gradient.new(); sg.set_color(0, Color(1, 1, 1, 0.5)); sg.set_color(1, Color(1, 1, 1, 0.0))
	splash.color_ramp = sg
	splash.emitting = false
	splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(splash)
	mist = CPUParticles3D.new(); mist.name = "FogWisps"
	mist.amount = 14; mist.lifetime = 12.0
	var q := QuadMesh.new(); q.size = Vector2(6, 3)
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mm.vertex_color_use_as_albedo = true
	var gt := GradientTexture2D.new(); gt.fill = GradientTexture2D.FILL_RADIAL; gt.fill_from = Vector2(0.5, 0.5); gt.fill_to = Vector2(0.5, 0.0)
	var gg := Gradient.new(); gg.set_color(0, Color(1, 1, 1, 1)); gg.set_color(1, Color(1, 1, 1, 0)); gt.gradient = gg
	mm.albedo_texture = gt
	q.material = mm
	mist.mesh = q
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	mist.emission_box_extents = Vector3(18, 1.0, 18)
	mist.direction = Vector3(1, 0, 0.2); mist.spread = 20.0
	mist.initial_velocity_min = 0.3; mist.initial_velocity_max = 0.6
	mist.gravity = Vector3.ZERO
	var mg := Gradient.new(); mg.set_color(0, Color(1, 0.96, 0.97, 0)); mg.set_color(1, Color(1, 0.96, 0.97, 0))
	mg.add_point(0.5, Color(1, 0.96, 0.97, 0.35))
	mist.color_ramp = mg
	mist.emitting = false
	mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mist)

func _process(dt: float) -> void:
	_update(dt)

func _update(dt: float) -> void:
	var h := hour()
	var k := _key(h)
	var w := weather()
	var rate := 1.0 if _first else clampf(dt * 0.5, 0.0, 1.0)
	_first = false
	_wx["cloud"] = lerpf(_wx["cloud"], 1.0 if w in ["cloudy", "rain"] else 0.0, rate)
	_wx["rain"] = lerpf(_wx["rain"], 1.0 if w == "rain" else 0.0, rate)
	_wx["fog"] = lerpf(_wx["fog"], 1.0 if w == "fog" else 0.0, rate)
	var cl: float = _wx["cloud"]; var rn: float = _wx["rain"]; var fg: float = _wx["fog"]
	# night factor: 0 day .. 1 night (dusk 19.3 -> 20.6, dawn 5.2 -> 6.4)
	if h >= 12.0: _nf = smoothstep(19.3, 20.6, h)
	else: _nf = 1.0 - smoothstep(5.2, 6.4, h)
	var top: Color = k[0]; var hor: Color = k[1]; var lc: Color = k[2]; var le: float = k[3]
	var amb: Color = k[4]; var ae: float = k[5]
	var grey := Color("9aa3b8").lerp(Color("3a4266"), _nf)
	top = top.lerp(grey, cl * 0.55); hor = hor.lerp(grey.lightened(0.15), cl * 0.5)
	var fogc := Color("f3dfe6").lerp(Color("4a5488"), _nf)
	top = top.lerp(fogc, fg * 0.7); hor = hor.lerp(fogc, fg * 0.85)
	le *= 1.0 - 0.45 * cl - 0.25 * rn - 0.35 * fg
	ae *= 1.0 + 0.15 * cl
	sky_mat.set_shader_parameter("top_color", top)
	sky_mat.set_shader_parameter("horizon_color", hor)
	sky_mat.set_shader_parameter("bottom_color", hor.lerp(Color("4f8fb8").lerp(Color("1a2448"), _nf), 0.5))
	sky_mat.set_shader_parameter("stars", _nf * (1.0 - cl) * (1.0 - fg))
	sky_mat.set_shader_parameter("moon", _nf * (1.0 - fg))
	# sun path (day) / moon (night); never fully overhead so toys keep shape
	var day_t := clampf((h - 6.0) / 14.0, 0.0, 1.0)
	var elev := lerpf(14.0, 52.0, sin(day_t * PI))
	var az := lerpf(70.0, -60.0, day_t)
	if _nf > 0.5:
		elev = 48.0; az = 25.0
	sun.rotation_degrees = Vector3(-elev, az, 0)
	sun.light_color = lc
	sun.light_energy = le * (0.85 if _compat else 1.0)
	sun.shadow_opacity = lerpf(0.85, 0.6, _nf) * (1.0 - 0.5 * cl)
	sky_mat.set_shader_parameter("moon_dir", -sun.global_transform.basis.z if _nf > 0.5 else Vector3(0.3, 0.5, -0.8))
	env.ambient_light_color = amb.lerp(Color("aab4c8"), cl * 0.4)
	env.ambient_light_energy = ae * (1.35 if _compat else 1.0)
	env.fog_light_color = hor.lerp(fogc, fg)
	if fg > 0.02:
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_density = lerpf(0.002, 0.045, fg)
		env.fog_sky_affect = fg
	else:
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_sky_affect = 0.0
	env.tonemap_exposure = lerpf(0.9, 1.0, _nf) * (1.0 + 0.1 * cl)
	env.adjustment_saturation = lerpf(1.12, 1.0, cl * 0.6 + rn * 0.3)
	# globals for the toy shaders
	Toys.set_global("lb_ink_light", lerpf(1.0, 0.45, _nf))
	Toys.set_global("lb_glow", lerpf(0.25, 2.6, smoothstep(0.0, 0.7, _nf + rn * 0.3 + fg * 0.3)))
	Toys.set_global("lb_day", 1.0 - _nf)
	Toys.set_global("lb_cloud", lerpf(0.55, 0.15, cl) * (1.0 - _nf) * (1.0 - fg))
	Toys.set_global("lb_wet", rn)
	Toys.set_global("lb_wind", 1.0 + rn * 0.8 + cl * 0.3)
	# lamps switch on at dusk (with a tiny per-lamp delay) and in heavy weather
	var lamp_on := clampf(_nf * 1.3 + rn * 0.5 + fg * 0.6, 0.0, 1.0)
	var i := 0
	for l in get_tree().get_nodes_in_group("lamp_light"):
		if l is Light3D:
			var base: float = float(l.get_meta("base_energy", 1.6))
			var on := clampf(lamp_on * 1.4 - fmod(i * 0.137, 0.4), 0.0, 1.0)
			(l as Light3D).light_energy = base * on
			(l as Light3D).visible = on > 0.01
		i += 1
	# weather particles follow the camera focus
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	rain.emitting = rn > 0.5
	splash.emitting = rn > 0.5
	mist.emitting = fg > 0.5
	if cam:
		var f := cam.global_position + (-cam.global_transform.basis.z) * 10.0
		rain.global_position = Vector3(f.x, f.y + 9.0, f.z)
		splash.global_position = Vector3(f.x, 0.04, f.z)
		mist.global_position = Vector3(f.x, 1.2, f.z)
