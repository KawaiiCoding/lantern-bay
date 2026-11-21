extends Node3D
## One townsperson in the world: body, idle/walk animation, interactable (Talk / Give <item>).
## The People system owns the rules; this node only moves, animates and forwards interactions.

const BodiesScr := preload("res://scripts/systems/people/bodies.gd")
const WALK_SPEED := 1.3
const STRIDE := 0.13                 # leg swing amplitude (local units); step rate is derived so feet do not slide
const LOOK_RADIUS := 6.0
const WAVE_RADIUS := 3.6

var id := ""
var data := {}
var system: Node                     # the People system
var interact_radius := 2.2
var interact_priority := 1
var body: Node3D
var hidden_body := false             # true when town.gd draws Pip itself
var show_tag := false                # set by the system: only the nearest person shows a name tag

var target := Vector3.ZERO
var walking := false
var hold_still := false              # test / dialogue: no routine walking
var _yaw := 0.0
var _t := 0.0
var _walk_amt := 0.0
var _step := 0.0                     # step phase, advanced by distance walked
var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _legs: Array = []
var _tail: Node3D
var _wave_t := -1.0
var _wave_day := -1
var _talking := false
var _tag: Label3D
var _hop_tw: Tween
var _blocker: AnimatableBody3D

func setup_person(pid: String, d: Dictionary, sys: Node) -> void:
	id = pid; data = d; system = sys
	name = "Person_" + pid
	add_to_group("interactable")
	add_to_group("people")
	body = BodiesScr.build(self, d)
	_torso = body.get_meta("torso") if body.has_meta("torso") else null
	_head = body.get_meta("head") if body.has_meta("head") else null
	_arm_l = body.get_meta("arm_l") if body.has_meta("arm_l") else null
	_arm_r = body.get_meta("arm_r") if body.has_meta("arm_r") else null
	_legs = body.get_meta("legs", [])
	_tail = body.get_meta("tail") if body.has_meta("tail") else null
	_t = randf() * 10.0
	# name tag, shown when Mocha is near
	_tag = Label3D.new()
	_tag.text = str(d.get("name", pid.capitalize()))
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.font_size = 40; _tag.outline_size = 12; _tag.pixel_size = 0.006
	_tag.modulate = Color("fffaf2"); _tag.outline_modulate = Color("6b4a3a")
	_tag.no_depth_test = true
	_tag.position = Vector3(0, float(body.get_meta("height", 2.0)) * body.scale.y + 0.35, 0)
	_tag.visible = false
	add_child(_tag)
	# a soft blocker so Mocha bumps into people instead of walking through them
	_blocker = AnimatableBody3D.new()
	_blocker.sync_to_physics = false
	var cs := CollisionShape3D.new(); var sh := CapsuleShape3D.new()
	sh.radius = 0.4 * body.scale.x; sh.height = 1.6 * body.scale.y
	cs.shape = sh; cs.position = Vector3(0, sh.height * 0.5, 0)
	_blocker.add_child(cs)
	add_child(_blocker)

## Hide our mesh (town.gd draws Pip) but keep the interactable and the relationship.
func set_body_hidden(h: bool) -> void:
	hidden_body = h
	if is_instance_valid(body): body.visible = not h
	if is_instance_valid(_blocker): _blocker.process_mode = Node.PROCESS_MODE_DISABLED if h else Node.PROCESS_MODE_INHERIT
	if is_instance_valid(_tag) and h: _tag.visible = false

func walk_to(p: Vector3, snap := false) -> void:
	target = p
	if snap or global_position.distance_to(p) > 45.0:
		global_position = p
		walking = false
	else:
		walking = global_position.distance_to(p) > 0.15

func face_point(p: Vector3) -> void:
	var d := p - global_position
	d.y = 0.0
	if d.length() > 0.01: _yaw = atan2(d.x, d.z)

func set_facing(yaw: float) -> void:
	_yaw = yaw
	if is_instance_valid(body): body.rotation.y = yaw

func set_talking(on: bool) -> void:
	_talking = on

# ---------------------------------------------------------------- interactable contract
func get_prompt(_player) -> String:
	if system == null or not is_instance_valid(system): return ""
	return system.prompt_for(id)

func interact(player) -> void:
	if system == null or not is_instance_valid(system): return
	if player is Node3D: face_point(player.global_position)
	hop()
	system.interact_with(id)

# ---------------------------------------------------------------- feedback
func hop() -> void:
	if not is_instance_valid(body): return
	if _hop_tw and _hop_tw.is_valid(): _hop_tw.kill()
	var s0 := body.scale
	body.set_meta("base_scale", body.get_meta("base_scale", s0))
	var bs: Vector3 = body.get_meta("base_scale")
	_hop_tw = create_tween()
	_hop_tw.tween_property(body, "scale", Vector3(bs.x * 1.12, bs.y * 0.86, bs.z * 1.12), 0.07)
	_hop_tw.tween_property(body, "scale", bs, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func wave() -> void:
	_wave_t = 0.0

## Small floating text above the head ("+10", "Level 4").
func pop_text(t: String, c := Color("f2a0a6")) -> void:
	var l := Label3D.new()
	l.text = t; l.billboard = BaseMaterial3D.BILLBOARD_ENABLED; l.no_depth_test = true
	l.font_size = 44; l.outline_size = 12; l.pixel_size = 0.006
	l.modulate = c; l.outline_modulate = Color("6b4a3a")
	var h := float(body.get_meta("height", 2.0)) * body.scale.y if is_instance_valid(body) else 2.0
	l.position = Vector3(0, h + 0.1, 0)
	add_child(l)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", h + 0.9, 1.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 1.2).set_delay(0.5)
	tw.chain().tween_callback(l.queue_free)

# ---------------------------------------------------------------- per frame
func _ground(p: Vector3) -> float:
	if system and is_instance_valid(system) and system.has_method("ground_y"):
		return system.ground_y(p)
	return p.y

func _process(dt: float) -> void:
	_t += dt
	var player: Node3D = system.get_player() if system and is_instance_valid(system) else null
	# walking
	if walking and not hold_still and not _talking:
		var d := target - global_position
		d.y = 0.0
		var dist := d.length()
		if dist < 0.12:
			walking = false
		else:
			var step := minf(dist, WALK_SPEED * dt)
			# a foot's peak speed (STRIDE * scale * rate) matches the walk speed: no sliding feet
			var sc := body.scale.x if is_instance_valid(body) else 1.0
			_step += step / (STRIDE * sc)
			var np := global_position + d / dist * step
			np.y = _ground(np)
			global_position = np
			_yaw = atan2(d.x, d.z)
	_walk_amt = move_toward(_walk_amt, 1.0 if (walking and not hold_still and not _talking) else 0.0, dt * 4.0)
	# look at / wave at Mocha
	var near := false
	var head_yaw := 0.0
	if player and is_instance_valid(player):
		var to := player.global_position - global_position
		to.y = 0.0
		var dist_p := to.length()
		near = dist_p < LOOK_RADIUS
		if is_instance_valid(_tag): _tag.visible = show_tag and dist_p < 4.0 and not hidden_body and not _talking
		if near and dist_p > 0.05:
			var want := atan2(to.x, to.z)
			if _talking or (not walking and dist_p < 2.6):
				_yaw = lerp_angle(_yaw, want, minf(1.0, dt * 5.0))
			head_yaw = clampf(wrapf(want - _yaw, -PI, PI), -0.9, 0.9)
		if dist_p < WAVE_RADIUS and _wave_day != GameState.day and not hidden_body:
			_wave_day = GameState.day
			if not _talking: wave()
	if not is_instance_valid(body): return
	body.rotation.y = lerp_angle(body.rotation.y, _yaw, minf(1.0, dt * 8.0))
	# breathing + walk bob
	var breathe := sin(_t * 2.2) * 0.025
	if is_instance_valid(_torso):
		var bob := absf(sin(_step)) * 0.05 * _walk_amt
		_torso.position.y = bob
		_torso.scale = Vector3(1.0 - breathe * 0.5, 1.0 + breathe, 1.0 - breathe * 0.5)
		_torso.rotation.z = sin(_step) * 0.06 * _walk_amt
	for i in _legs.size():
		var leg: Node3D = _legs[i]
		if is_instance_valid(leg):
			var ph := 0.0 if i == 0 else PI
			var y0 := float(leg.get_meta("y0", leg.position.y))
			var z0 := float(leg.get_meta("z0", 0.04))
			# planted foot moves back with the ground, lifted foot swings forward (only lifts, never sinks)
			leg.position.z = z0 + sin(_step + ph) * STRIDE * _walk_amt
			leg.position.y = y0 + maxf(0.0, cos(_step + ph)) * 0.05 * _walk_amt
	if is_instance_valid(_head):
		var idle_look := sin(_t * 0.5) * 0.25 * (1.0 - _walk_amt)
		var hy := head_yaw if near else idle_look
		_head.rotation.y = lerp_angle(_head.rotation.y, hy, minf(1.0, dt * 4.0))
		var tilt := sin(_t * 1.1) * 0.06
		if _talking: tilt = sin(_t * 7.0) * 0.08
		_head.rotation.z = tilt
		_head.rotation.x = sin(_t * 2.2 + 0.6) * 0.03
	if is_instance_valid(_tail):
		_tail.rotation.y = sin(_t * 3.0) * 0.35
	# arms: swing when walking, wave when greeting
	var swing := sin(_step) * 0.5 * _walk_amt
	if is_instance_valid(_arm_l): _arm_l.rotation = Vector3(swing, 0, sin(_t * 2.2) * 0.04)
	if is_instance_valid(_arm_r):
		if _wave_t >= 0.0:
			_wave_t += dt
			var k := clampf(minf(_wave_t / 0.25, (1.6 - _wave_t) / 0.3), 0.0, 1.0)
			_arm_r.rotation = Vector3(-0.3 * k, 0, (2.4 + sin(_wave_t * 14.0) * 0.35) * k)
			if _wave_t > 1.6: _wave_t = -1.0
		else:
			_arm_r.rotation = Vector3(-swing, 0, -sin(_t * 2.2) * 0.04)
