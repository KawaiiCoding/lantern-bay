extends CharacterBody3D
## Player: Mocha the bear. Movement + feel, moped, follow camera, interaction finder.
## Contract: docs/TEAM.md "Player". Visual rig hierarchy:
##   rig (yaw) -> tilt (bob, hop, lean/bank) -> squash (scale) -> bear_walk | bear_sit | moped
## Self-test: `godot --path . -- test=player [demo=walk|ride|sit] shot=/tmp/x.png wait=3`

const ShibaArt := preload("res://scripts/player/shiba.gd")
const FOOT_LIFT := 0.05
const WALK_SPEED := 4.2
const SNEAK_SPEED := 1.6
const SNEAK_STICK := 0.46          # stick length at or below this = sneak (keyboard Shift gives 0.45)
const RIDE_MULT := 2.2
const GRAVITY := 24.0
const ACCEL := 18.0
const DECEL := 24.0
const RIDE_ACCEL := 11.0
const RIDE_DECEL := 9.0
const TURN_SPEED := 11.0
const LOOK_RADIUS := 5.0           # head turns toward interactables this close
const ARM_PIVOT := 0.16            # shoulder: local +Y along the arm capsule (height 0.5)
const ARM_SWING := 0.5             # radians at full walk speed (sneak ~0.2)
const ARM_RELAX := 0.22            # arms drop a little from the held-forward pose while walking

const CAM_PITCH := 42.0
const CAM_DIST := 11.0
const CAM_DIST_SIT := 8.8
const CAM_FOV := 32.0
const CAM_LAG := 4.5
const CAM_LOOK_AHEAD := 0.32       # seconds of velocity
const CAM_FOCUS_UP := 0.7
const CAM_FOCUS_FWD := 1.0        # frame a little more of the world ahead (up the screen)
const FALL_Y := -5.0
const AIR_RESPAWN := 3.0          # seconds airborne before we assume we are lost and respawn

var riding := false
var sitting := false
var busy := false

var main: Node
var camera: Camera3D
var cam_attr: CameraAttributesPractical
var target: Node3D                 # current interactable (prompt not "")
var look_target: Node3D            # nearest interactable for the head to look at

var _rig: Node3D
var _tilt: Node3D
var _squash: Node3D
var _bear_walk: Node3D
var _bear_sit: Node3D
var _moped: Node3D
var _beam: SpotLight3D
var _shape: CapsuleShape3D
var _puffs: Array[CPUParticles3D] = []   # small pool of one-shot soft puffs (start/stop/turn/hop)
var _puff_i := 0
var _turn_cd := 0.0
var _was_idle := true
var _wind: CPUParticles3D
static var _soft_tex: Texture2D
var _splash: CPUParticles3D
var _blob: MeshInstance3D
var _scarves: Array[MeshInstance3D] = []
var _splash_cd := 0.0
var _legs: Array[MeshInstance3D] = []
var _arms: Array[MeshInstance3D] = []
var _heads: Array[Node3D] = []
var _tails: Array[Node3D] = []
var _fronts: Array[MeshInstance3D] = []
var _wag := 0.0                    # 0..1, tail wag happiness (interactions, nearby friends)

var _stick := 0.0
var _yaw := 0.0
var _turn_rate := 0.0
var _phase := 0.0
var _t := 0.0
var _move_amt := 0.0               # 0..1 smoothed "walking" blend for anim
var _was_moving := false
var _hopping := false
var _squash_tw: Tween
var _cam_focus := Vector3.ZERO
var _cam_ahead := Vector3.ZERO
var _cam_dist := CAM_DIST
var _last_prompt := "__none__"
var _sit_grace := 0.0
var _night_check := 0.0
var _air_time := 0.0
var _hop_tw: Tween
var _hop_time := 0.0
var _nudge := Vector3.ZERO         # sideways steer around a small obstacle we walked into head-on
var _nudge_side := 0.0
var _blocked_t := 0.0

var _test := false
var _demo := ""
var _demo_t := 0.0
var _demo_log_prompt := ""
var _wa := {}                      # walkabout self-test state (-- test=walkabout)

# ---------------------------------------------------------------- build
func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(50)
	floor_constant_speed = true
	var cs := CollisionShape3D.new()
	_shape = CapsuleShape3D.new(); _shape.radius = 0.42; _shape.height = 1.7
	cs.shape = _shape; cs.position = Vector3(0, 0.85, 0)
	add_child(cs)

	_rig = Node3D.new(); _rig.name = "Rig"; add_child(_rig)
	_tilt = Node3D.new(); _rig.add_child(_tilt)
	_squash = Node3D.new(); _tilt.add_child(_squash)

	_bear_walk = ShibaArt.build(_squash, false)
	_bear_walk.position.y = FOOT_LIFT   # soles rest on the ground (QA: was 7 cm sunk)
	_bear_sit = ShibaArt.build(_squash, true)
	_bear_sit.visible = false
	_scan_bear(_bear_walk, true)
	_scan_bear(_bear_sit, false)

	_moped = Toys.moped(_squash)
	_moped.visible = false
	for c in _moped.get_children():
		if c is SpotLight3D: _beam = c
	if _beam: _beam.visible = false

	for i in 4:
		var pf := _make_dust(4, 0.4, true)
		add_child(pf); _puffs.append(pf)
	_wind = _make_wind()
	add_child(_wind)
	_splash = _make_splash()
	add_child(_splash)
	_blob = _make_blob()
	add_child(_blob)
	for b in [_bear_walk, _bear_sit, _moped]: _cast_shadows(b)

	_build_camera()

	InputBridge.action_pressed.connect(_on_action)
	InputBridge.ride_pressed.connect(_on_ride)

	var args := _args()
	_test = args.get("test", "") == "player"
	if _test: _demo = args.get("demo", "walk")
	if args.get("test", "") == "walkabout": _wa = {"on": true, "step": float(args.get("step", "2.5")), "off": float(args.get("off", "0"))}
		if args.has("near"):   # e.g. near=2,5: only grid points around one spot (debugging a stuck report)
			var nv: PackedStringArray = str(args["near"]).split(",")
			if nv.size() == 2: _wa["near"] = Vector2(float(nv[0]), float(nv[1]))

## Collect the tagged parts of a Shiba (meta "part") that we animate.
func _scan_bear(b: Node3D, _with_limbs := true) -> void:
	for c in b.get_children():
		var part := str(c.get_meta("part", ""))
		match part:
			"leg": _legs.append(c); c.set_meta("base", c.position)
			"arm":
				# swing from the shoulder (top end of the capsule), not around the arm's middle
				_arms.append(c); c.set_meta("base_xf", c.transform)
				c.set_meta("pivot", c.transform * Vector3(0, ARM_PIVOT, 0))
			"front": _fronts.append(c); c.set_meta("base", c.position); c.set_meta("base_rot", c.rotation)
			"scarf": _scarves.append(c); c.set_meta("base", c.rotation)
			"head": _heads.append(c)
			"tail": _tails.append(c)

func _cast_shadows(n: Node) -> void:
	if n is GeometryInstance3D: n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for c in n.get_children(): _cast_shadows(c)

## Soft round blob shadow that stays on the ground (reads well even where real shadows are faint).
func _make_blob() -> MeshInstance3D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.25, 0.2, 0.25, a * a * 0.55))
	var mt := StandardMaterial3D.new()
	mt.albedo_texture = ImageTexture.create_from_image(img)
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.render_priority = -1
	var q := PlaneMesh.new(); q.size = Vector2(1.5, 1.5)
	var m := MeshInstance3D.new()
	m.mesh = q; m.material_override = mt; m.position = Vector3(0, 0.03, 0)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m

## Thin streaks that stream past while riding fast.
func _make_wind() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 4; p.lifetime = 0.3; p.local_coords = false; p.emitting = false
	var m := Toys.capsule(0.012, 0.8); m.radial_segments = 6; m.rings = 2
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.vertex_color_use_as_albedo = true
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material = mt
	p.mesh = m
	p.particle_flag_align_y = true
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(1.3, 0.8, 0.6)
	p.spread = 4.0; p.gravity = Vector3.ZERO
	p.initial_velocity_min = 7.0; p.initial_velocity_max = 10.0
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0)); g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(0.35, Color(1, 1, 1, 0.35))
	p.color_ramp = g
	return p

func _make_splash() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 10; p.lifetime = 0.5; p.one_shot = true; p.explosiveness = 1.0
	p.local_coords = false; p.emitting = false
	var m := Toys.sphere(0.06); m.radial_segments = 8; m.rings = 4
	var mt := StandardMaterial3D.new()
	mt.vertex_color_use_as_albedo = true
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.roughness = 0.2
	m.material = mt
	p.mesh = m
	p.direction = Vector3.UP; p.spread = 35.0
	p.initial_velocity_min = 2.0; p.initial_velocity_max = 3.4
	p.gravity = Vector3(0, -12, 0)
	var g := Gradient.new()
	g.set_color(0, Color(0.92, 0.98, 1.0, 0.95)); g.set_color(1, Color(0.8, 0.93, 1.0, 0.0))
	p.color_ramp = g
	return p

## Soft round alpha sprite shared by all puffs (no visible "balls").
static func _soft() -> Texture2D:
	if _soft_tex: return _soft_tex
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a * (3.0 - 2.0 * a)))
	_soft_tex = ImageTexture.create_from_image(img)
	return _soft_tex

func _make_dust(amount: int, life: float, one_shot: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount; p.lifetime = life; p.one_shot = one_shot; p.explosiveness = 0.85 if one_shot else 0.0
	p.local_coords = false
	p.emitting = false
	var q := QuadMesh.new(); q.size = Vector2(0.32, 0.2)   # flattened soft puff
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mt.vertex_color_use_as_albedo = true
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.albedo_texture = _soft()
	q.material = mt
	p.mesh = q
	p.direction = Vector3(0, 0.25, 0); p.spread = 80.0
	p.initial_velocity_min = 0.5; p.initial_velocity_max = 1.0
	p.gravity = Vector3(0, 0.3, 0)
	p.damping_min = 2.5; p.damping_max = 3.5
	p.scale_amount_min = 0.7; p.scale_amount_max = 1.1
	var sc := Curve.new(); sc.add_point(Vector2(0, 0.5)); sc.add_point(Vector2(0.35, 1.0)); sc.add_point(Vector2(1, 1.2))
	p.scale_amount_curve = sc
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.97, 0.9, 0.5)); g.set_color(1, Color(1.0, 0.97, 0.92, 0.0))
	p.color_ramp = g
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE; p.emission_sphere_radius = 0.12
	return p

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "FollowCam"
	camera.top_level = true
	camera.keep_aspect = Camera3D.KEEP_WIDTH   # portrait: fov is horizontal so the island reads as a diorama
	camera.fov = CAM_FOV
	camera.near = 0.3; camera.far = 200.0
	# Web build runs gl_compatibility: no DOF there (unsupported; even setting the values warns).
	if _dof_supported():
		cam_attr = CameraAttributesPractical.new()
		cam_attr.dof_blur_far_enabled = true
		cam_attr.dof_blur_far_distance = CAM_DIST + 5.0
		cam_attr.dof_blur_far_transition = 9.0
		cam_attr.dof_blur_near_enabled = true
		cam_attr.dof_blur_near_distance = CAM_DIST - 3.5
		cam_attr.dof_blur_near_transition = 2.5
		cam_attr.dof_blur_amount = 0.05
		camera.attributes = cam_attr
	add_child(camera)
	camera.current = true

func _dof_supported() -> bool:
	return RenderingServer.get_current_rendering_method() != "gl_compatibility"

func setup(m) -> void:
	main = m
	if _test: _build_test_world()
	var p := Vector3.ZERO
	if main and main.has_method("spot"): p = main.spot("spawn")
	if p == Vector3.ZERO: p = Vector3(0, 0, 4)
	var isl = main.get("island") if main else null
	if is_instance_valid(isl) and isl.has_method("ground_y"): p.y = isl.ground_y(p.x, p.z)
	global_position = p + Vector3(0, 0.05, 0)
	if _test and _demo.begins_with("portrait") and (main == null or main.get("island") == null):
		global_position = Vector3(16, 0.05, 16)   # clear of other systems' test NPCs
	_yaw = 0.0   # face the camera (+Z) on spawn
	_rig.rotation.y = _yaw
	_cam_focus = global_position + Vector3(0, CAM_FOCUS_UP, 0)
	_place_camera(0.0, true)
	if not _wa.is_empty(): _walkabout_begin()

# ---------------------------------------------------------------- contract API
func speed_ratio() -> float:
	if riding: return 1.0
	return clampf(Vector2(velocity.x, velocity.z).length() / WALK_SPEED, 0.0, 1.0)

func noise_level() -> float:
	var hs := Vector2(velocity.x, velocity.z).length()
	if riding: return 1.5 if hs > 0.3 else 0.5
	if hs < 0.3 or _stick <= SNEAK_STICK: return 0.0
	return lerpf(0.5, 1.0, clampf((_stick - SNEAK_STICK) / (0.95 - SNEAK_STICK), 0.0, 1.0))

func set_busy(b: bool) -> void:
	if busy == b: return
	busy = b
	if busy:
		_cancel_hop()
		if riding:   # nobody fishes from a moped: step off quietly
			riding = false; _set_riding_visual(false); _update_shape()
		velocity.x = 0.0; velocity.z = 0.0
	else:
		_last_prompt = "__none__"   # force a HUD refresh when we get control back

func sit(on: bool) -> void:
	if sitting == on: return
	_cancel_hop()
	if on and riding: _set_riding_visual(false); riding = false; _update_shape()
	sitting = on
	velocity.x = 0.0; velocity.z = 0.0
	_sit_grace = 0.35
	_bear_walk.visible = not on and not riding
	_bear_sit.visible = on or riding
	_bear_sit.position = Vector3.ZERO
	_squash_pulse(Vector3(1.12, 0.84, 1.12) if on else Vector3(0.92, 1.12, 0.92))
	if on: _puff(global_position + Vector3(0, 0.08, 0), 3)

func face(t: Vector3) -> void:
	var d := t - global_position
	d.y = 0.0
	if d.length() < 0.01: return
	_yaw = atan2(d.x, d.z)

func carrying(item_id: String) -> bool:
	return GameState.has_item(item_id)

# ---------------------------------------------------------------- input
func _on_action() -> void:
	if busy or _hopping or GameState.paused: return
	if is_instance_valid(target) and target.has_method("interact") and str(target.get_prompt(self)) != "":
		var t := target
		face(t.global_position)
		_squash_pulse(Vector3(1.06, 0.94, 1.06))
		_wag = 1.0
		t.interact(self)
		_last_prompt = "__none__"   # the thing may have changed its prompt; refresh next frame
	elif sitting:
		sit(false)

func _on_ride() -> void:
	if not bool(GameState.flags.get("moped_unlocked", false)) and GameState.day < 2: return   # Pip lends the moped on day 2
	if busy or sitting or _hopping or GameState.paused: return
	_hop_toggle_ride()

func _hop_toggle_ride() -> void:
	_hopping = true
	_hop_time = 0.0
	var mounting := not riding
	var tw := create_tween()
	_hop_tw = tw
	tw.tween_property(_squash, "scale", Vector3(1.15, 0.8, 1.15), 0.07)
	tw.tween_property(_squash, "scale", Vector3(0.9, 1.15, 0.9), 0.08)
	tw.parallel().tween_property(_tilt, "position:y", 0.9, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		riding = mounting
		_set_riding_visual(mounting)
		_update_shape())
	tw.tween_property(_tilt, "position:y", 0.0, 0.17).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_squash, "scale", Vector3.ONE, 0.17)
	tw.tween_callback(func():
		_puff(global_position + Vector3(0, 0.08, 0), 4)
		_hopping = false
		_squash_pulse(Vector3(1.14, 0.84, 1.14)))

## Stop a mount/dismount hop mid-air and leave a clean state (used by sit/busy and a watchdog).
func _cancel_hop() -> void:
	if not _hopping: return
	if _hop_tw and _hop_tw.is_valid(): _hop_tw.kill()
	_hopping = false
	_tilt.position.y = 0.0
	_squash.scale = Vector3.ONE
	_set_riding_visual(riding)
	_update_shape()

func _set_riding_visual(on: bool) -> void:
	_moped.visible = on
	_bear_walk.visible = not on and not sitting
	_bear_sit.visible = on or sitting
	_bear_sit.position = Vector3(0, 1.08, -0.32) if on else Vector3.ZERO
	for f in _fronts:   # paws up on the handlebars while riding
		var bp: Vector3 = f.get_meta("base")
		f.position = Vector3(bp.x * 1.3, 0.62, 0.42) if on else bp
		f.rotation = Vector3(-1.15, 0, -0.25 * signf(bp.x)) if on else f.get_meta("base_rot")
	if on:
		_moped.scale = Vector3(0.6, 0.6, 0.6)
		create_tween().tween_property(_moped, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _update_shape() -> void:
	_shape.radius = 0.62 if riding else 0.42
	_shape.height = maxf(1.7, _shape.radius * 2.0 + 0.1)

# ---------------------------------------------------------------- movement
func _input_move() -> Vector2:
	if _test and _demo != "": return _demo_move()
	return InputBridge.move

func _physics_process(dt: float) -> void:
	if not _wa.is_empty(): _walkabout_step(dt)
	var mv := _input_move()
	if busy or _hopping or GameState.paused: mv = Vector2.ZERO
	_stick = minf(mv.length(), 1.0)

	_sit_grace = maxf(0.0, _sit_grace - dt)
	if sitting:
		if _stick > 0.25 and _sit_grace <= 0.0 and not busy: sit(false)
		else: mv = Vector2.ZERO; _stick = 0.0

	# camera-relative direction (move.y negative = away from camera / up the screen)
	var cb := camera.global_transform.basis
	var right := Vector3(cb.x.x, 0, cb.x.z).normalized()
	var fwd := Vector3(-cb.z.x, 0, -cb.z.z).normalized()
	var dir := right * mv.x + fwd * (-mv.y)
	if dir.length() > 1.0: dir = dir.normalized()

	var spd := 0.0
	if _stick > 0.05:
		if _stick <= SNEAK_STICK: spd = lerpf(0.7, SNEAK_SPEED, _stick / SNEAK_STICK)
		else: spd = lerpf(2.6, WALK_SPEED, clampf((_stick - SNEAK_STICK) / (0.95 - SNEAK_STICK), 0.0, 1.0))
		if riding: spd = lerpf(spd, WALK_SPEED, 0.5) * RIDE_MULT
	var want := dir.normalized() * spd if _stick > 0.05 else Vector3.ZERO

	var hv := Vector3(velocity.x, 0, velocity.z)
	var rate := (RIDE_ACCEL if want.length() > hv.length() else RIDE_DECEL) if riding \
		else (ACCEL if want.length() > hv.length() else DECEL)
	if riding and hv.length() > 1.0 and want.length() > 0.1:
		# moped steers: rotate velocity toward the wanted heading instead of sliding sideways
		var cur := atan2(hv.x, hv.z)
		var goal := atan2(want.x, want.z)
		var ang := lerp_angle(cur, goal, 1.0 - exp(-7.0 * dt))
		var l := move_toward(hv.length(), want.length(), rate * dt)
		hv = Vector3(sin(ang), 0, cos(ang)) * l
	else:
		hv = hv.move_toward(want + _nudge, rate * dt)
	velocity.x = hv.x; velocity.z = hv.z

	if is_on_floor(): velocity.y = minf(velocity.y, 0.0)
	velocity.y -= GRAVITY * dt
	move_and_slide()
	_unstick(want, dt)
	_air_time = 0.0 if is_on_floor() else _air_time + dt
	if global_position.y < FALL_Y or _air_time > AIR_RESPAWN: _respawn()

	# facing
	var hs := Vector2(velocity.x, velocity.z).length()
	if hs > 0.25 and _stick > 0.05:
		var goal_yaw := atan2(velocity.x, velocity.z) if riding else atan2(want.x, want.z)
		_yaw = lerp_angle(_yaw, goal_yaw, 1.0 - exp(-(TURN_SPEED * (0.7 if riding else 1.0)) * dt))
	var turned := lerp_angle(_rig.rotation.y, _yaw, 1.0 - exp(-16.0 * dt))
	_turn_rate = lerpf(_turn_rate, wrapf(turned - _rig.rotation.y, -PI, PI) / maxf(dt, 0.001), 1.0 - exp(-10.0 * dt))
	_rig.rotation.y = turned

	# stop squash
	var moving := hs > 1.2
	if _was_moving and hs < 0.35 and not riding and not sitting:
		_squash_pulse(Vector3(1.08, 0.9, 1.08))
		_puff(global_position + _rig.global_basis.z * 0.2 + Vector3(0, 0.06, 0), 3)
		_was_moving = false
	elif moving:
		_was_moving = true

	_find_interactable()

## Gentle unstuck: walking head-on into a small round thing (post, lamp, bollard, a standing person) would
## stop Mocha dead, because the slide has no sideways component. After a moment, steer around it.
## Big walls/buildings are left alone (pushing into a wall should just stop).
func _unstick(want: Vector3, dt: float) -> void:
	var wl := want.length()
	var real := get_real_velocity(); real.y = 0.0
	var hit: KinematicCollision3D = null
	if wl > 0.5 and real.length() < wl * 0.4:
		var best := -0.6
		for k in get_slide_collision_count():
			var c := get_slide_collision(k)
			var n := c.get_normal(); n.y = 0.0
			if n.length() < 0.3: continue
			var d := n.normalized().dot(want / wl)
			if d < best and _small_obstacle(c): best = d; hit = c
	if hit == null:
		_blocked_t = 0.0
		_nudge = _nudge.move_toward(Vector3.ZERO, 8.0 * dt)
		if _nudge.length() < 0.05: _nudge_side = 0.0
		return
	_blocked_t += dt
	if _blocked_t < 0.06: return
	var n := hit.get_normal(); n.y = 0.0; n = n.normalized()
	var tan := Vector3(-n.z, 0, n.x)
	if _nudge_side == 0.0:
		var lean := tan.dot(want / wl)
		if absf(lean) < 0.05:   # dead centre: pass on the side of the contact we are already offset to
			var off := global_position - hit.get_position(); off.y = 0.0
			lean = tan.dot(off) if off.length() > 0.001 else 1.0
		_nudge_side = 1.0 if lean >= 0.0 else -1.0
	_nudge = tan * _nudge_side * wl * 0.9
	if not _wa.is_empty() and _wa.has("near"): print("[walkabout] nudge n=", n, " tan=", tan * _nudge_side, " real=", get_real_velocity(), " pos=", global_position)

func _small_obstacle(c: KinematicCollision3D) -> bool:
	var col := c.get_collider()
	if col is AnimatableBody3D or col is CharacterBody3D: return true   # townsfolk / cats
	var sh = c.get_collider_shape()
	if not (sh is CollisionShape3D) or (sh as CollisionShape3D).shape == null: return false
	var s: Shape3D = (sh as CollisionShape3D).shape
	if s is CylinderShape3D: return (s as CylinderShape3D).radius <= 0.7
	if s is CapsuleShape3D: return (s as CapsuleShape3D).radius <= 0.7
	if s is SphereShape3D: return (s as SphereShape3D).radius <= 0.7
	if s is BoxShape3D: return maxf((s as BoxShape3D).size.x, (s as BoxShape3D).size.z) <= 1.0
	return false

func _respawn() -> void:
	velocity = Vector3.ZERO
	_air_time = 0.0
	var p := Vector3(0, 0, 4)
	if main and main.has_method("spot"):
		var s: Vector3 = main.spot("spawn")
		if s != Vector3.ZERO: p = s
	var isl = main.get("island") if main else null
	if is_instance_valid(isl) and isl.has_method("ground_y"): p.y = isl.ground_y(p.x, p.z)
	global_position = p + Vector3(0, 0.3, 0)
	_cam_focus = global_position + Vector3(0, CAM_FOCUS_UP, 0)

# ---------------------------------------------------------------- interaction
func _find_interactable() -> void:
	var best: Node3D = null
	var best_d := INF
	var best_pri := -999999
	var near: Node3D = null
	var near_d := LOOK_RADIUS
	var me := global_position
	for n in get_tree().get_nodes_in_group("interactable"):
		if not is_instance_valid(n) or not (n is Node3D) or not n.is_inside_tree() or n.is_queued_for_deletion(): continue
		if n == self: continue
		var nd: Node3D = n
		var d := Vector2(nd.global_position.x - me.x, nd.global_position.z - me.z).length()
		if d < near_d: near_d = d; near = nd
		var r = nd.get("interact_radius")
		var radius: float = float(r) if r != null else 1.5
		if d > radius or not nd.has_method("get_prompt") or not nd.has_method("interact"): continue
		var pr = nd.get_prompt(self)
		if pr == null or str(pr) == "": continue
		var pp = nd.get("interact_priority")
		var pri: int = int(pp) if pp != null else 0
		# nearest wins; within 0.15 m counts as a tie and higher priority wins
		if best == null or d < best_d - 0.15 or (absf(d - best_d) <= 0.15 and pri > best_pri):
			best = nd; best_d = d; best_pri = pri
	target = best
	look_target = best if best else near
	if busy: return   # the busy system owns the action button meanwhile
	var prompt := ""
	if is_instance_valid(target):
		var pr2 = target.get_prompt(self)
		prompt = str(pr2) if pr2 != null else ""
	if prompt != _last_prompt:
		_last_prompt = prompt
		var hud = main.get("hud") if is_instance_valid(main) else null
		if is_instance_valid(hud) and hud.has_method("set_action"): hud.set_action(prompt)
		if _test and prompt != _demo_log_prompt:
			_demo_log_prompt = prompt
			print("[player test] prompt: '", prompt, "'")

# ---------------------------------------------------------------- animation + camera
func _process(dt: float) -> void:
	_t += dt
	if _hopping:
		_hop_time += dt
		if _hop_time > 1.0: _cancel_hop()
	var hs := Vector2(velocity.x, velocity.z).length()
	var walk_amt := clampf(hs / WALK_SPEED, 0.0, 1.0) if not riding and not sitting else 0.0
	_move_amt = lerpf(_move_amt, walk_amt, 1.0 - exp(-12.0 * dt))
	_phase += dt * (4.0 + hs * 2.1) * (1.0 if hs > 0.2 else 0.0)

	if not _hopping:
		if riding:
			var bump := sin(_t * 23.0) * 0.012 * clampf(hs / 4.0, 0.0, 1.0)
			_tilt.position.y = lerpf(_tilt.position.y, bump, 1.0 - exp(-20.0 * dt))
		else:
			_tilt.position.y = absf(sin(_phase)) * 0.085 * _move_amt
	var lean_fwd := _move_amt * 0.11
	var lean_side := clampf(-_turn_rate * (0.07 if riding else 0.035), -0.32 if riding else -0.18, 0.32 if riding else 0.18)
	if riding: lean_side *= clampf(hs / 5.0, 0.0, 1.0)
	else: lean_side *= _move_amt
	_tilt.rotation.x = lerpf(_tilt.rotation.x, lean_fwd if not riding else -0.03 * clampf(hs / 6.0, 0.0, 1.0), 1.0 - exp(-8.0 * dt))
	_tilt.rotation.z = lerpf(_tilt.rotation.z, lean_side, 1.0 - exp(-8.0 * dt))

	# limbs
	var sw := sin(_phase)
	for leg in _legs:
		var base: Vector3 = leg.get_meta("base")
		var s := float(leg.get_meta("swing", signf(base.x)))
		leg.position = base + Vector3(0, maxf(0.0, -sw * s) * 0.07 * _move_amt, sw * s * 0.14 * _move_amt)
	_animate_arms(sw)

	# tail: wags when happy (just interacted / something friendly close), sways while walking
	var want_wag := 0.0
	if is_instance_valid(target): want_wag = 0.55
	_wag = maxf(want_wag, _wag - dt * 0.35)
	for tl in _tails:
		tl.rotation.y = sin(_t * 15.0) * 0.42 * _wag + sin(_phase * 0.5) * 0.22 * _move_amt + sin(_t * 1.3) * 0.05
		tl.rotation.x = -0.08 * _move_amt + sin(_t * 15.0 + 0.8) * 0.06 * _wag

	# idle breathing (on top of any squash tween, which drives _squash)
	var breathe := sin(_t * 2.3) * (0.022 if hs < 0.3 else 0.006)
	var bear: Node3D = _bear_sit if _bear_sit.visible else _bear_walk
	bear.scale = Vector3(1.0 - breathe * 0.5, 1.0 + breathe, 1.0 - breathe * 0.5)

	# head looks at the nearest interactable
	var head_yaw := 0.0
	var head_pitch := 0.0
	if is_instance_valid(look_target):
		var d := look_target.global_position - global_position
		var la := wrapf(atan2(d.x, d.z) - _rig.rotation.y, -PI, PI)
		head_yaw = clampf(la, -0.9, 0.9) if absf(la) < 2.2 else 0.0
		head_pitch = 0.12 if sitting else 0.06
	else:
		head_yaw = sin(_t * 0.5) * 0.12 * (1.0 if hs < 0.3 else 0.0)
	for h in _heads:
		h.rotation.y = lerp_angle(h.rotation.y, head_yaw, 1.0 - exp(-6.0 * dt))
		h.rotation.x = lerpf(h.rotation.x, head_pitch + sin(_t * 2.3 + 0.6) * 0.02, 1.0 - exp(-6.0 * dt))

	# scarf tail flutters with speed (and a little in the breeze when idle)
	var flutter := clampf(hs / WALK_SPEED, 0.0, 1.6)
	for sc in _scarves:
		var sb: Vector3 = sc.get_meta("base")
		sc.rotation = sb + Vector3(-0.35 * flutter + sin(_t * 13.0) * 0.12 * flutter + sin(_t * 1.7) * 0.04,
			0, sin(_t * 9.0 + 1.0) * 0.18 * flutter)

	# soft puffs only on start, stop (see _physics_process) and sharp turns: no constant streams
	_turn_cd = maxf(0.0, _turn_cd - dt)
	var grounded := is_on_floor() and not sitting and not _hopping
	if grounded and _was_idle and hs > 1.2:
		_puff(_rig.global_transform * Vector3(0, 0.06, -1.0 if riding else -0.15), 4 if riding else 3)
		_try_splash()
	if grounded and absf(_turn_rate) > (2.2 if riding else 3.2) and hs > 2.5 and _turn_cd <= 0.0:
		_turn_cd = 0.45
		_puff(_rig.global_transform * Vector3(0, 0.06, -0.9 if riding else -0.1), 3)
	_was_idle = hs < 0.4
	if not riding and is_on_floor() and _move_amt > 0.4 and signf(sw) != signf(sin(_phase - dt * 6.0)):
		_try_splash()   # stepping into shallow foam
	var fast := riding and hs > WALK_SPEED * 1.2
	_wind.emitting = fast
	if fast:
		var vd := Vector3(velocity.x, 0, velocity.z).normalized()
		_wind.global_position = global_position + vd * 2.2 + Vector3(0, 1.1, 0)
		_wind.global_basis = Basis.looking_at(vd, Vector3.UP)
		_wind.direction = Vector3(0, 0, 1)   # local: backward relative to the emitter facing
	_splash_cd = maxf(0.0, _splash_cd - dt)
	if riding and hs > 2.0 and _splash_cd <= 0.0: _try_splash()

	# blob shadow shrinks while airborne (hop)
	var air := clampf(_tilt.position.y, 0.0, 1.0)
	var bs := (1.9 if riding else 1.0) * (1.0 - air * 0.45)
	_blob.scale = Vector3(bs * (0.8 if riding else 1.0), 1, bs * (1.4 if riding else 1.0))
	_blob.rotation.y = _rig.rotation.y

	_night_check -= dt
	if _night_check <= 0.0 and _beam:
		_night_check = 1.0
		var sky = main.get("sky") if is_instance_valid(main) else null
		_beam.visible = riding and is_instance_valid(sky) and sky.has_method("is_night") and sky.is_night()

	_place_camera(dt, false)
	if _test:
		var before := _demo_t
		_demo_t += dt
		if _demo == "full": _full_checks(before, _demo_t)

## Arms swing opposite to the legs, from the shoulder, scaled by speed (small when sneaking).
## Going back they roll slightly outward so the paws clear the round belly; idle = gentle breathing sway.
func _animate_arms(sw: float) -> void:
	var amt := _move_amt
	var idle := (1.0 - amt) * sin(_t * 2.3 + 0.4) * 0.035
	for arm in _arms:
		if not is_instance_valid(arm): continue
		var bx: Transform3D = arm.get_meta("base_xf")
		var pv: Vector3 = arm.get_meta("pivot")
		var s := signf(bx.origin.x)
		# leg on side s is forward when sw * s > 0 -> this arm goes back (positive x rotation = paw down/back)
		var swing := sw * s * ARM_SWING * amt
		var pitch := ARM_RELAX * amt + swing + idle
		var roll := (maxf(0.0, swing) * 0.32 + 0.05 * amt) * s
		var r := Basis(Vector3.BACK, roll) * Basis(Vector3.RIGHT, pitch)
		arm.transform = Transform3D(r * bx.basis, pv + r * (bx.origin - pv))

func _place_camera(dt: float, snap: bool) -> void:
	var hv := Vector3(velocity.x, 0, velocity.z)
	var ahead := hv * CAM_LOOK_AHEAD
	if ahead.length() > 2.6: ahead = ahead.normalized() * 2.6
	var want_dist := CAM_DIST_SIT if sitting else CAM_DIST
	if riding: want_dist = CAM_DIST + 0.8
	if snap:
		_cam_ahead = ahead; _cam_dist = want_dist
		_cam_focus = global_position + Vector3(0, CAM_FOCUS_UP, -CAM_FOCUS_FWD)
	else:
		_cam_ahead = _cam_ahead.lerp(ahead, 1.0 - exp(-1.8 * dt))
		_cam_dist = lerpf(_cam_dist, want_dist, 1.0 - exp(-2.0 * dt))
		var goal := global_position + Vector3(0, CAM_FOCUS_UP, -CAM_FOCUS_FWD) + _cam_ahead
		_cam_focus = _cam_focus.lerp(goal, 1.0 - exp(-CAM_LAG * dt))
	if _test and _demo.begins_with("portrait"):
		var face_at := global_position + Vector3(0, 0.95, 0)
		var fwd := _rig.global_basis.z
		if _demo in ["portrait_side", "portrait_walk", "portrait_sneak"]: fwd = _rig.global_basis.x
		elif _demo == "portrait_walk_front": fwd = (_rig.global_basis.z + _rig.global_basis.x * 0.6).normalized()
		elif _demo == "portrait_back": fwd = -_rig.global_basis.z
		camera.global_position = face_at + fwd * 3.3 + Vector3(0, 0.8, 0)
		camera.look_at(face_at + Vector3(0, -0.1, 0), Vector3.UP)
		if cam_attr: cam_attr.dof_blur_far_distance = 5.0; cam_attr.dof_blur_near_distance = 1.0
		return
	var p := deg_to_rad(CAM_PITCH)
	camera.global_position = _cam_focus + Vector3(0, sin(p), cos(p)) * _cam_dist
	camera.look_at(_cam_focus, Vector3.UP)
	if cam_attr and absf(cam_attr.dof_blur_far_distance - (_cam_dist + 5.0)) > 0.02:
		cam_attr.dof_blur_far_distance = _cam_dist + 5.0
		cam_attr.dof_blur_near_distance = _cam_dist - 3.5

# ---------------------------------------------------------------- juice helpers
## Splash when stepping in shallow water/foam. Island may expose `is_shallow(p)` or `sea_level`.
func _try_splash() -> void:
	var isl = main.get("island") if is_instance_valid(main) else null
	if not is_instance_valid(isl): return
	var wet := false
	if isl.has_method("is_shallow"):
		wet = bool(isl.is_shallow(global_position))
	else:
		var sl = isl.get("sea_level")
		if sl != null: wet = global_position.y < float(sl) + 0.08
	if not wet: return
	if _splash_cd > 0.0: return
	_splash_cd = 0.22
	_splash.global_position = global_position + Vector3(0, 0.05, 0)
	_splash.restart()

func _squash_pulse(s: Vector3) -> void:
	if _hopping: return
	if _squash_tw and _squash_tw.is_valid(): _squash_tw.kill()
	_squash_tw = create_tween()
	_squash_tw.tween_property(_squash, "scale", s, 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_squash_tw.tween_property(_squash, "scale", Vector3.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _puff(at: Vector3, n: int) -> void:
	if _puffs.is_empty(): return
	var p := _puffs[_puff_i]
	_puff_i = (_puff_i + 1) % _puffs.size()
	p.amount = clampi(n, 1, 6)
	p.global_position = at
	p.restart()

func _args() -> Dictionary:
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv: PackedStringArray = s.split("=", true, 1)
		if kv.size() == 2: a[kv[0]] = kv[1]
	return a

# ---------------------------------------------------------------- self-test (-- test=player)
func _demo_move() -> Vector2:
	var t := _demo_t
	match _demo:
		"ride":
			if t > 0.25 and t < 0.3 and not riding and not _hopping: _on_ride()
			if t < 0.7: return Vector2.ZERO
			if t < 1.6: return Vector2(0.4, -1.0).normalized()
			if t < 2.4: return Vector2(-1.0, -0.3).normalized()
			if t < 3.2: return Vector2(-0.3, 1.0).normalized()
			return Vector2.ZERO
		"sit":
			if t < 1.0: return Vector2(0.6, -0.8)
			if t > 1.3 and not sitting: sit(true)
			return Vector2.ZERO
		"none", "portrait", "portrait_side", "portrait_back":
			return Vector2.ZERO
		"portrait_walk", "portrait_walk_front":   # close-up of the walk cycle (arm/leg swing)
			return Vector2(1, 0)
		"portrait_sneak":
			return Vector2(0.4, 0)
		"full":
			if t < 0.6: return Vector2(0.55, -0.85).normalized()
			if t > 1.35 and t < 1.6: return Vector2(-1, 0)          # stand up from sitting by moving
			if t > 2.4 and t < 3.2: return Vector2(-0.3, 1.0).normalized()
			return Vector2.ZERO
		_:
			if t < 0.9: return Vector2(0.55, -0.85).normalized()
			if t < 1.5: return Vector2(-1.0, -0.2).normalized() * 0.4   # sneak
			if t < 2.3: return Vector2(-0.6, 0.8).normalized()
			if t < 2.75: return Vector2(1.0, 0.3).normalized()
			return Vector2.ZERO

## Scripted full loop for `demo=full` (run with wait=6): interact, sit/stand, ride, busy cancels ride,
## dismount, fall-off respawn. Prints PASS/FAIL lines.
func _full_checks(a: float, b: float) -> void:
	var at := func(x: float) -> bool: return a < x and b >= x
	if at.call(0.8):
		_check("finder has a prompt in range", is_instance_valid(target) and str(target.get_prompt(self)) != "")
		# act on our own test node only (other systems' interactables may open dialogue / set busy)
		for n in get_tree().get_nodes_in_group("interactable"):
			if is_instance_valid(n) and n.has_meta("player_test") and str(n.prompt) == "Pet": target = n
		_check("test Pet found", is_instance_valid(target) and target.has_meta("player_test"))
		_on_action()
		_check("interact keeps player free", not busy)
	if at.call(1.0): sit(true); _check("sit", sitting)
	if at.call(1.15): _check("sit holds while idle", sitting)
	if at.call(1.7): _check("moving stands up", not sitting)
	if at.call(1.8): _on_ride()
	if at.call(2.3): _check("mounted", riding and not _hopping)
	if at.call(3.3): set_busy(true); _check("busy dismounts", busy and not riding)
	if at.call(3.4): _on_ride(); _check("no ride while busy", not riding and not _hopping)
	if at.call(3.6): set_busy(false); _check("busy cleared", not busy)
	if at.call(3.8): _on_ride()
	if at.call(3.85): sit(true); _check("sit cancels hop cleanly", sitting and not riding and not _hopping)
	if at.call(4.0): sit(false)
	if at.call(4.1): _on_ride()
	if at.call(4.6): _check("remounted", riding); _on_ride()
	if at.call(5.1): _check("dismounted", not riding and not _hopping)
	if at.call(5.2): global_position = Vector3(30, -6, 30)
	if at.call(5.5): _check("fell off world -> respawn", global_position.y > -1.0 and global_position.distance_to(Vector3(0, 0, 4)) < 2.0)

func _check(what: String, ok: bool) -> void:
	print("[player test] ", "PASS " if ok else "FAIL ", what)

func _build_test_world() -> void:
	var root: Node = main if main else get_parent()
	if root == null: return
	if main == null or main.get("island") == null:
		var w := Node3D.new(); w.name = "PlayerTestWorld"
		root.add_child.call_deferred(w)
		var body := StaticBody3D.new(); w.add_child(body)
		var sh := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(60, 1, 60)
		sh.shape = bs; sh.position = Vector3(0, -0.5, 0); body.add_child(sh)
		Toys.add(Toys.box(60, 1, 60), Toys.mat(Color("a8d08f"), 0.95, 0.0), Vector3(0, -0.5, 0), body)
		# sand patch + water strip for scale
		Toys.add(Toys.cyl(5.0, 5.0, 0.04, 40), Toys.mat(Color("f3e2bf"), 0.95, 0.0), Vector3(-5, 0.01, -2), w)
		Toys.add(Toys.box(60, 0.05, 14), Toys.mat(Color("8fd0e0"), 0.3, 0.0), Vector3(0, 0.0, -22), w)
		var cols := [Color("e9b6a0"), Color("b9d4f0"), Color("f2d98a"), Color("c7b6e8")]
		var spots := [Vector3(3.5, 0, -1.5), Vector3(-4, 0, 1.5), Vector3(1.5, 0, -6), Vector3(-2.5, 0, -4.5)]
		for i in spots.size():
			var b := StaticBody3D.new(); b.position = spots[i] + Vector3(0, 0.5, 0); w.add_child(b)
			var c := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = Vector3(1.2, 1, 1.2)
			c.shape = bx; b.add_child(c)
			Toys.add(Toys.box(1.2, 1, 1.2), Toys.mat(cols[i]), Vector3.ZERO, b)
		# a gentle ramp to check floor snap
		var r := StaticBody3D.new(); r.position = Vector3(5, 0.3, 3); r.rotation.x = deg_to_rad(-12); w.add_child(r)
		var rc := CollisionShape3D.new(); var rb := BoxShape3D.new(); rb.size = Vector3(2.5, 0.3, 4)
		rc.shape = rb; r.add_child(rc)
		Toys.add(Toys.box(2.5, 0.3, 4), Toys.mat(Color("e8c79a")), Vector3.ZERO, r)
		for p in [Vector3(-6, 0, -1), Vector3(6, 0, -5), Vector3(-1, 0, -9)]:
			Toys.tree(w, p)
	if main == null or main.get("sky") == null:
		var sun := DirectionalLight3D.new()
		sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(35), 0)
		sun.light_energy = 1.1; sun.light_color = Color("fff1dc"); sun.shadow_enabled = true
		root.add_child.call_deferred(sun)
		var we := WorldEnvironment.new(); var env := Environment.new()
		env.background_mode = Environment.BG_COLOR; env.background_color = Color("bfe3ef")
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("e9e4f2"); env.ambient_light_energy = 0.45
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC if _dof_supported() else Environment.TONE_MAPPER_LINEAR
		we.environment = env
		root.add_child.call_deferred(we)
	var scr := load("res://scripts/player/test_interactable.gd")
	var defs := [["Pet", Vector3(1.6, 0, 0.6), Color("f2b880"), 0], ["Sit", Vector3(-1.5, 0, 2.2), Color("a9c9e8"), 0],
		["Talk", Vector3(-1.9, 0, 2.6), Color("e8a9c0"), 1]]
	for d in defs:
		var n: Node3D = scr.new()
		n.prompt = d[0]; n.color = d[2]; n.interact_priority = d[3]
		n.position = d[1]
		root.add_child.call_deferred(n)

# ---------------------------------------------------------------- self-test (-- test=walkabout)
## Walks 8 directions (0.6 s each) from every walkable grid point via InputBridge.touch_move and logs
## any run where speed stays under 20% of expected while the path ahead is walkable and free.
## Run fast: `godot --headless --fixed-fps 60 --path . -- test=walkabout [step=2.5]`.
const WA_DIRS := [Vector2(0, -1), Vector2(1, -1), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0), Vector2(-1, -1)]
const WA_RUN := 0.6
const WA_MEASURE := 0.25           # measure after accelerating

func _walkabout_begin() -> void:
	var isl = main.get("island") if is_instance_valid(main) else null
	var pts: Array[Vector3] = []
	if is_instance_valid(isl) and isl.has_method("is_walkable"):
		var st: float = maxf(0.5, float(_wa.get("step", 2.5)))
		var off: float = float(_wa.get("off", 0.0))
		var x := -60.0 + off
		while x <= 60.0:
			var z := -60.0 + off
			while z <= 60.0:
				var p := Vector3(x, 0, z)
				if isl.is_walkable(p) and (not _wa.has("near") or Vector2(p.x, p.z).distance_to(_wa["near"]) < 1.6): pts.append(p)
				z += st
			x += st
	_wa["pts"] = pts; _wa["i"] = 0; _wa["d"] = 0; _wa["t"] = -1.0; _wa["stuck"] = []; _wa["air"] = {}; _wa["runs"] = 0; _wa["open"] = 0
	print("[walkabout] %d walkable grid points" % pts.size())

func _wa_ground(p: Vector3) -> Vector3:
	var isl = main.get("island") if is_instance_valid(main) else null
	if is_instance_valid(isl) and isl.has_method("ground_y"): p.y = isl.ground_y(p.x, p.z)
	return p

## Camera-relative stick -> world direction (same mapping as _physics_process).
func _wa_world_dir(mv: Vector2) -> Vector3:
	var cb := camera.global_transform.basis
	var right := Vector3(cb.x.x, 0, cb.x.z).normalized()
	var fwd := Vector3(-cb.z.x, 0, -cb.z.z).normalized()
	return (right * mv.x + fwd * (-mv.y)).normalized()

## Path ahead (body width included) is walkable for the whole run distance.
func _wa_open_ahead(p: Vector3, dir: Vector3) -> bool:
	var isl = main.get("island")
	var side := Vector3(-dir.z, 0, dir.x)
	var d := 0.3
	while d <= WALK_SPEED * WA_RUN + 0.6:
		for o in [-0.45, 0.0, 0.45]:
			if not isl.is_walkable(p + dir * d + side * o): return false
		d += 0.25
	return true

func _walkabout_step(dt: float) -> void:
	var pts: Array = _wa.get("pts", [])
	var i: int = _wa["i"]
	if i >= pts.size():
		InputBridge.touch_move = Vector2.ZERO
		if not _wa.has("done"):
			_wa["done"] = true
			var stuck: Array = _wa["stuck"]
			print("[walkabout] runs=%d open=%d stuck=%d" % [_wa["runs"], _wa["open"], stuck.size()])
			for line in stuck: print("[walkabout] STUCK ", line)
			var air: Dictionary = _wa["air"]
			for line in air.values(): print("[walkabout] AIR ", line)
			print("[walkabout] PASS no stuck points" if stuck.is_empty() else "[walkabout] FAIL stuck points found")
			print("[walkabout] PASS never stands in the air" if air.is_empty() else "[walkabout] FAIL stood above the ground %d times" % air.size())
			get_tree().quit()
		return
	if riding or sitting or busy:
		if sitting: sit(false)
		if riding: riding = false; _set_riding_visual(false); _update_shape()
		if busy: set_busy(false)
	var p: Vector3 = pts[i]
	var mv: Vector2 = WA_DIRS[int(_wa["d"])].normalized()
	if _wa["t"] < 0.0:   # start a run: teleport back to the grid point at rest
		global_position = _wa_ground(p) + Vector3(0, 0.02, 0)
		velocity = Vector3.ZERO
		_wa["t"] = 0.0; _wa["hits"] = {}; _wa["from"] = Vector3.ZERO; _wa["stall"] = 0
	InputBridge.touch_move = mv
	var t: float = _wa["t"]
	if t >= WA_MEASURE and _wa["from"] == Vector3.ZERO: _wa["from"] = global_position
	if t >= WA_MEASURE:
		var rv := get_real_velocity(); rv.y = 0.0
		if rv.length() < WALK_SPEED * 0.2: _wa["stall"] = int(_wa["stall"]) + 1
	for k in get_slide_collision_count():
		var c := get_slide_collision(k)
		if c.get_normal().y > 0.7: continue   # floor
		var col := c.get_collider()
		var nm := "?"
		if col is Node:
			nm = str((col as Node).name)
			var sh = c.get_collider_shape()
			if sh is Node3D: nm += "/" + str((sh as Node3D).name) + "@" + str(((sh as Node3D).global_position * 10.0).round() / 10.0)
			if sh is CollisionShape3D and (sh as CollisionShape3D).shape: nm += ":" + (sh as CollisionShape3D).shape.get_class()
		_wa["hits"][nm] = true
	# "you cannot stand in the air": on the floor but clearly above the island's ground height
	if is_on_floor() and t > 0.1:
		var gy := _wa_ground(global_position).y
		if global_position.y - gy > 0.15:
			var fc := "?"
			for k in get_slide_collision_count():
				var c := get_slide_collision(k)
				if c.get_normal().y > 0.7:
					var col := c.get_collider()
					var sh = c.get_collider_shape()
					fc = (str((col as Node).name) if col is Node else "?") + "/" + (str((sh as Node).name) if sh is Node else "?")
					if sh is CollisionShape3D and (sh as CollisionShape3D).shape: fc += ":" + (sh as CollisionShape3D).shape.get_class() + "@" + str(((sh as Node3D).global_position * 10.0).round() / 10.0)
			var key := "%.0f,%.0f" % [global_position.x, global_position.z]
			if not _wa["air"].has(key):
				_wa["air"][key] = "at (%.2f, %.2f, %.2f) ground %.2f on %s (from grid (%.1f, %.1f))" % [global_position.x, global_position.y, global_position.z, gy, fc, p.x, p.z]
	_wa["t"] = t + dt
	if _wa["t"] < WA_RUN: return
	var moved := Vector2(global_position.x - _wa["from"].x, global_position.z - _wa["from"].z).length()
	var expect := WALK_SPEED * (WA_RUN - WA_MEASURE)
	_wa["runs"] += 1
	var dir := _wa_world_dir(mv)
	if _wa_open_ahead(p, dir):
		_wa["open"] += 1
		if moved < expect * 0.2 or int(_wa["stall"]) >= 9:
			_wa["stuck"].append("at (%.1f, %.1f) dir (%.2f, %.2f) moved %.2f m of %.2f, stalled %d frames; hit %s" % [p.x, p.z, dir.x, dir.z, moved, expect, int(_wa["stall"]), str(_wa["hits"].keys())])
	_wa["t"] = -1.0
	_wa["d"] = int(_wa["d"]) + 1
	if _wa["d"] >= WA_DIRS.size():
		_wa["d"] = 0; _wa["i"] = i + 1
