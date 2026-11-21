extends Node3D
## One cat on the island. An interactable (group "interactable"): get_prompt / interact / interact_radius.
## Owned by the Cats system (scripts/systems/cats.gd). All rules (hearts, facts, sit sessions) live there;
## this node owns the body: look, idle behaviours, scamper, hearts and emotes.
##
## Hierarchy: self (ground position) -> _body (yaw) -> _root (fade pop) -> _rig (pose) -> awake / sleepy toy cat.
## FX (heart row, "!", name, z z z) hang off self so they never spin with the cat.

const CatFx := preload("res://scripts/systems/cats/cat_fx.gd")

enum S { IDLE, WANDER, SIT, GROOM, NAP, LOOK, HOP, REACT, FLEE, ALERT, TRAVEL, FOLLOW, LEAVE, SNIFF }

const PET_RANGE := 1.5
const BASE_SCALE := 0.55
const FOLLOW_NOTICE := 12.0
const WEIGHTS := {
	"Bold":    {"idle": 2.0, "wander": 3.0, "sit": 1.0, "groom": 1.0, "nap": 0.3, "look": 1.5, "approach": 1.4},
	"Lazy":    {"idle": 1.0, "wander": 0.5, "sit": 2.0, "groom": 1.2, "nap": 3.0, "look": 0.6, "approach": 0.3},
	"Shy":     {"idle": 2.0, "wander": 1.5, "sit": 1.5, "groom": 1.5, "nap": 0.3, "look": 1.0, "approach": 0.0},
	"Curious": {"idle": 1.0, "wander": 3.0, "sit": 1.0, "groom": 0.8, "nap": 0.2, "look": 2.0, "approach": 1.8},
	"Grumpy":  {"idle": 2.0, "wander": 0.8, "sit": 3.0, "groom": 1.0, "nap": 1.0, "look": 0.5, "approach": 0.0},
}
const WANDER_RADIUS := {"Bold": 1.2, "Lazy": 0.6, "Shy": 1.0, "Curious": 1.4, "Grumpy": 0.7}   # small, and only over walkable ground
const LOOK_WEIGHT := {"Bold": 1.0, "Lazy": 0.5, "Shy": 0.7, "Curious": 1.0, "Grumpy": 0.6}
const TAIL := {"Bold": [2.2, 0.4], "Lazy": [1.2, 0.25], "Shy": [1.6, 0.3], "Curious": [2.6, 0.45], "Grumpy": [5.0, 0.22]}

var cat_id := ""
var cdata := {}
var sys: Node = null
var interact_radius := 1.8
var interact_priority := 1
var haunt := ""                   # spot this cat belongs to right now
var home := Vector3.ZERO
var personality := "Bold"
var shy := false
var scares := false
var follow_item := ""
var pinned := false               # tests: do not wander or approach
var look_at_pos := Vector3.INF    # tests: look here instead of at the player
var state: int = S.IDLE
var state_t := 0.0
var state_len := 2.0
var fade := 0.0
var fade_goal := 1.0
var yaw := 0.0
var following := false
var near_sit_time := 0.0          # seconds within reach while the player sits (Cats system)
var sit_credited := false
var gone := false                 # leaving or removed: not interactable any more

var _rng := RandomNumberGenerator.new()
var _body: Node3D
var _root: Node3D
var _rig: Node3D
var _models: Array = []           # [{"root","head","tail"}]: 0 awake, 1 sleepy (also used as a blink)
var _meshes: Array = []
var _shadow: MeshInstance3D
var _model_meshes: Array = []     # per model: its MeshInstance3D list (for grounding)
var _bub: Node3D = null           # the one bubble above the head
var _bub_key := ""
var _bub_scale := 0.0
var _bub_goal := 0.0
var _bub_age := 0.0
var _evt_kind := ""
var _evt_t := 0.0
var _evt_data := {}

var _t := 0.0
var _slow := 0.0
var _target := Vector3.ZERO
var _speed := 1.0
var _moving := false
var _walk_phase := 0.0
var _y_off := 0.0
var _vy := 0.0
var _hops_left := 0
var _squash := 0.0
var _approach_mode := false
var _approach_cd := 4.0
var _scare_cd := 0.0
var _return_timer := 0.0
var _return_pending := false
var _follow_move_t := 0.0
var _blink := 0.0
var _blink_in := 3.0
var _fade_dest := Vector3.INF
var _scare_from := Vector3.ZERO
var _free_on_fade := false
var _after_hop := S.IDLE
var _wander_r := 1.5
var _look_w := 1.0
var _tail_rate := 2.0
var _tail_amp := 0.3
var _tail_cur_rate := 2.0
var _tail_cur_amp := 0.3
var _head_yaw := 0.0
var _head_pitch := 0.0
var _p_sit := 0.0
var _p_nap := 0.0
var _p_alert := 0.0
var _p_run := 0.0
var _p_groom := 0.0
var _p_happy := 0.0
var _p_sniff := 0.0
var _model_scale := BASE_SCALE

# ---------------------------------------------------------------- build
func setup(system: Node, id: String, data: Dictionary) -> void:
	sys = system
	cat_id = id
	cdata = data
	name = "Cat_" + id
	personality = String(data.get("personality", "Bold"))
	if not WEIGHTS.has(personality): personality = "Bold"
	shy = bool(data.get("shy", personality == "Shy" or personality == "Grumpy"))
	scares = bool(data.get("scares", shy))
	var fi := String(data.get("follows", ""))
	if fi == "" and id == "biscuit": fi = "fish:mackerel"
	follow_item = fi
	_wander_r = float(WANDER_RADIUS.get(personality, 1.5))
	_look_w = float(LOOK_WEIGHT.get(personality, 1.0))
	_rng.seed = hash(id) ^ int(Time.get_ticks_usec())
	_blink_in = _rng.randf_range(1.5, 5.0)
	add_to_group("interactable")
	_build()
	_enter(S.IDLE, _rng.randf_range(0.5, 2.0))

func _build() -> void:
	var h := absi(cat_id.hash())
	_model_scale = BASE_SCALE * (0.93 + float(h % 100) / 100.0 * 0.16)
	_body = Node3D.new(); _body.name = "Body"; add_child(_body)
	_root = Node3D.new(); _root.name = "Root"; _body.add_child(_root)
	_rig = Node3D.new(); _rig.name = "Rig"; _root.add_child(_rig)
	var main_c := CatFx.col(cdata.get("main", ""), Color("d9cbb5"))
	var patch_c := CatFx.col(cdata.get("patch", ""), Color(0, 0, 0, 0))
	for sleepy in [false, true]:
		var g := Toys.cat(_rig, main_c, patch_c, sleepy)
		g.scale = Vector3.ONE * _model_scale
		if personality == "Lazy": g.scale = Vector3(1.1, 0.96, 1.05) * _model_scale
		_models.append(_prepare(g))
	(_models[1].root as Node3D).visible = false
	# soft blob shadow so cats sit on the ground even without sun shadows
	_shadow = MeshInstance3D.new()
	var disc := CylinderMesh.new(); disc.top_radius = 0.42; disc.bottom_radius = 0.42; disc.height = 0.01; disc.radial_segments = 20
	_shadow.mesh = disc
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0.2, 0.12, 0.1, 0.16)
	_shadow.material_override = sm
	_shadow.position = Vector3(0, 0.03, -0.05)
	_shadow.scale = Vector3(1.1, 1.0, 1.35) * (_model_scale / BASE_SCALE)
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)
	fade = 0.0
	_apply_fade()

func _prepare(g: Node3D) -> Dictionary:
	var head: Node3D = null
	var tail: MeshInstance3D = null
	for c in g.get_children():
		if c is MeshInstance3D:
			if (c as MeshInstance3D).mesh is TorusMesh: tail = c
		elif c is Node3D:
			head = c
	var pivot: Node3D = null
	if tail != null:
		pivot = Node3D.new()
		pivot.position = tail.position + Vector3(0, 0, 0.05)
		g.remove_child(tail)
		g.add_child(pivot)
		pivot.add_child(tail)
		tail.position = Vector3(0, 0, -0.05)
	var before := _meshes.size()
	_collect(g)
	_model_meshes.append(_meshes.slice(before))
	return {"root": g, "head": head, "tail": pivot}

func _collect(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D: _meshes.append(c)
		_collect(c)

# ---------------------------------------------------------------- placement / schedule moves
## Put the cat at `dest` (or at `from` when it should walk in from there).
func spawn_at(dest: Vector3, from: Vector3, walk_in: bool, instant: bool) -> void:
	home = dest
	var p := from if walk_in else dest
	global_position = Vector3(p.x, _gy(p.x, p.z, p.y), p.z)
	yaw = _rng.randf_range(-PI, PI)
	fade_goal = 1.0
	if instant:
		fade = 1.0
		_apply_fade()
	if walk_in:
		_travel(dest, 2.3, false)
		yaw = atan2(dest.x - p.x, dest.z - p.z)

func set_haunt(spot: String, new_home: Vector3) -> void:
	haunt = spot
	home = new_home
	if gone: return
	if following or state in [S.FLEE, S.REACT, S.ALERT]:
		_return_pending = true
		_return_timer = 6.0
		return
	var d := _flat(global_position, new_home)
	if d < 0.6: return
	if d <= 16.0 and sys.path_clear(global_position, new_home):
		_travel(new_home, 2.4, false)
	else:
		_fade_move(new_home)

func _fade_move(dest: Vector3) -> void:
	_fade_dest = dest
	_free_on_fade = false
	fade_goal = 0.0

## Leave the island: walk off to `away` when close enough to be seen, then fade and free.
func leave(away: Vector3, walk: bool) -> void:
	if gone: return
	gone = true
	remove_from_group("interactable")
	following = false
	if walk:
		_target = away
		_speed = 2.2
		_enter(S.LEAVE, 30.0)
	else:
		_free_on_fade = true
		fade_goal = 0.0

# ---------------------------------------------------------------- interaction contract
func get_prompt(player) -> String:
	var v := _verb(player)
	return String(v[1])

func interact(player) -> void:
	if sys == null or not sys.claim_interact(): return
	var v := _verb(player)
	match String(v[0]):
		"pet": _do_pet(player)
		"give": _do_give(player, String(v[2]))
		"sit": sys.start_sit(self, player)
		"stand": sys.stop_sit(true)

func available() -> bool:
	return not gone and fade >= 0.7 and not (state in [S.FLEE, S.REACT, S.ALERT, S.LEAVE])

func is_napping() -> bool:
	return state == S.NAP

func pettable(st: Dictionary) -> bool:
	return int(st.get("last_pet_day", 0)) != GameState.day and (not shy or int(st.get("hearts", 0)) >= 1)

## Decide which verb the Action button would do now: [kind, label, item_id]; kind "" = nothing.
func _verb(player) -> Array:
	var none := ["", "", ""]
	if sys == null or not is_instance_valid(player) or not (player is Node3D) or not available(): return none
	var d := _flat((player as Node3D).global_position, global_position)
	if d > interact_radius + 0.3: return none
	var st: Dictionary = sys.st(cat_id)
	var today := GameState.day
	var in_session: bool = sys.sit_active and sys.sit_actor == self
	if d <= PET_RANGE and pettable(st): return ["pet", "Pet", ""]
	var fav := String(cdata.get("favourite", ""))
	if fav != "" and GameState.has_item(fav) and int(st.get("last_treat_day", 0)) != today:
		return ["give", "Give " + sys.item_name(fav), fav]
	if not in_session and int(st.get("last_sit_day", 0)) != today:
		return ["sit", "Sit with " + _short_name(), ""]
	var wrong: String = sys.wrong_treat(cat_id, fav)
	if wrong != "":
		return ["give", "Give " + sys.item_name(wrong), wrong]
	if in_session: return ["stand", "Stand up", ""]
	return ["sit", "Sit with " + _short_name(), ""]

func _short_name() -> String:
	return String(cdata.get("name", cat_id.capitalize()))

func _do_pet(player) -> void:
	var st: Dictionary = sys.st(cat_id)
	st["last_pet_day"] = GameState.day
	_face_point((player as Node3D).global_position)
	if player.has_method("face"): player.face(global_position)
	sys.add_hearts(cat_id, 1, "pet")
	joy_hop(2)

func _do_give(player, item: String) -> void:
	var st: Dictionary = sys.st(cat_id)
	var fav := String(cdata.get("favourite", ""))
	_face_point((player as Node3D).global_position)
	if player.has_method("face"): player.face(global_position)
	if item == fav:
		if not sys.treat_rule_ok(cat_id):
			GameState.say(sys.rule_hint(cat_id))
			show_dots(2.2)
			_shake_no()
			return
		if not GameState.remove_item(item): return
		st["last_treat_day"] = GameState.day
		sys.learn(cat_id, "favourite")
		if sys.has_treat_rule(cat_id): sys.learn(cat_id, "secret", true)
		sys.add_hearts(cat_id, 2, "treat")
		joy_hop(3)
	else:
		st["last_wrong_day"] = GameState.day
		sys.learn(cat_id, "favourite_hint")
		GameState.say(sys.wrong_line(fav, _short_name()))
		show_dots(2.2)
		_enter(S.SNIFF, 1.1)
		_p_sniff = 1.0

# ---------------------------------------------------------------- reactions called by the system
## One bubble per cat. Event bubbles last `dur` seconds; "alert" is automatic while nervous; ambient ones come from the system.
func show_bubble(kind: String, dur := 2.4, data := {}) -> void:
	_evt_kind = kind
	_evt_t = dur
	_evt_data = data

func show_hearts(before: int, after: int) -> void:
	if after > before:
		show_bubble("hearts", 2.8, {"n": after, "max": int(sys.max_hearts()), "new_from": before})
	else:
		show_bubble("heart", 1.8)

func show_dots(dur := 2.0) -> void:
	show_bubble("dots", dur)

func joy_hop(hops := 2) -> void:
	if gone: return
	_after_hop = S.SIT if state in [S.SIT, S.GROOM, S.NAP] or _rng.randf() < 0.4 else S.IDLE
	_hops_left = hops
	_enter(S.HOP, 0.5 * hops + 0.5)

func _shake_no() -> void:
	_enter(S.SNIFF, 0.7)
	_p_sniff = 0.0

func come_close(player_pos: Vector3, dist := 1.15) -> void:
	if gone or not available() or state == S.HOP: return
	var d := _flat(global_position, player_pos)
	if d <= dist + 0.2:
		if state in [S.WANDER, S.TRAVEL, S.IDLE, S.LOOK]: _enter(S.SIT, _rng.randf_range(5.0, 9.0))
		return
	var dir := Vector3(global_position.x - player_pos.x, 0, global_position.z - player_pos.z).normalized()
	var side := Vector3(-dir.z, 0, dir.x) * _rng.randf_range(-0.5, 0.5)
	var goal := player_pos + (dir + side).normalized() * dist
	goal.y = _gy(goal.x, goal.z, global_position.y)
	if not sys.is_walkable(goal) or not sys.path_clear(global_position, goal): return
	_travel(goal, 0.8 if (shy or personality == "Grumpy") else 1.4, true)

func scare_from(from: Vector3) -> void:
	if gone or state in [S.REACT, S.FLEE, S.ALERT]: return
	_enter(S.REACT, 0.38)
	_vy = 3.4
	_scare_from = from
	_approach_mode = false

# ---------------------------------------------------------------- state machine
func _enter(s: int, length := -1.0) -> void:
	state = s
	state_t = 0.0
	if length >= 0.0:
		state_len = length
		return
	match s:
		S.IDLE: state_len = _rng.randf_range(1.5, 4.0)
		S.SIT: state_len = _rng.randf_range(4.0, 9.0)
		S.GROOM: state_len = _rng.randf_range(3.0, 5.5)
		S.NAP: state_len = _rng.randf_range(10.0, 24.0)
		S.LOOK: state_len = _rng.randf_range(2.0, 3.5)
		_: state_len = 3.0

func _travel(dest: Vector3, spd: float, approach: bool) -> void:
	_fade_dest = Vector3.INF
	if not _free_on_fade: fade_goal = 1.0
	_target = dest
	_speed = spd
	_approach_mode = approach
	_enter(S.TRAVEL, 60.0)

func _process(dt: float) -> void:
	dt = minf(dt, 0.1)
	if sys == null or not is_instance_valid(sys): return
	_t += dt
	_approach_cd = maxf(0.0, _approach_cd - dt)
	_scare_cd = maxf(0.0, _scare_cd - dt)
	_return_timer = maxf(0.0, _return_timer - dt)
	_update_fade(dt)
	_moving = false
	_tick_ai(dt)
	_update_pose(dt)
	_update_bubble(dt)
	_slow -= dt
	if _slow <= 0.0:
		_slow = 0.2
		_slow_tick()

func _tick_ai(dt: float) -> void:
	state_t += dt
	_vertical(dt)
	match state:
		S.IDLE, S.SIT, S.GROOM, S.LOOK:
			_attend(dt)
			if following and _player_dist() > 2.7:
				_enter(S.FOLLOW, 60.0)
			elif state_t >= state_len:
				_pick_next()
		S.NAP:
			if state_t >= state_len: _pick_next()
			elif _player_dist() < 0.9 and not pinned and _look_w > 0.0 and state_t > 3.0 and _rng.randf() < dt * 0.15:
				_enter(S.IDLE, 1.0)
		S.WANDER:
			if _step_to(_target, 0.85, dt): _enter(S.IDLE, _rng.randf_range(0.8, 2.5))
			elif state_t > 14.0: _enter(S.IDLE)
		S.TRAVEL:
			if _step_to(_target, _speed, dt): _after_travel()
			elif state_t > 40.0: _enter(S.IDLE)
		S.FOLLOW:
			_tick_follow(dt)
		S.LEAVE:
			if _step_to(_target, _speed, dt) or state_t > 30.0:
				_free_on_fade = true
				fade_goal = 0.0
				_enter(S.IDLE, 99.0)
		S.HOP:
			if _hops_left > 0 and _y_off <= 0.001 and _vy <= 0.0:
				_vy = 3.0
				_hops_left -= 1
			if _hops_left <= 0 and _y_off <= 0.001 and _vy <= 0.0 and state_t > 0.25:
				_enter(_after_hop)
		S.REACT:
			if state_t >= state_len: _start_flee()
		S.FLEE:
			if _step_to(_target, 4.6, dt) or state_t > 3.0:
				_enter(S.ALERT, _rng.randf_range(3.0, 5.0))
		S.ALERT:
			if state_t >= state_len:
				_scare_cd = 2.5
				_return_pending = true
				_return_timer = _rng.randf_range(5.0, 9.0)
				_enter(S.IDLE, _rng.randf_range(1.5, 3.0))
		S.SNIFF:
			if state_t >= state_len:
				_p_sniff = 0.0
				_walk_off()

func _after_travel() -> void:
	if _approach_mode:
		_approach_mode = false
		_enter(S.SIT, _rng.randf_range(5.0, 9.0))
	else:
		_enter(S.IDLE, _rng.randf_range(1.0, 3.0))

func _walk_off() -> void:
	var dir := Vector3(global_position.x - _pp().x, 0, global_position.z - _pp().z)
	if dir.length() < 0.1: dir = Vector3.RIGHT
	var goal := global_position + dir.normalized().rotated(Vector3.UP, _rng.randf_range(-0.7, 0.7)) * 3.0
	goal.y = _gy(goal.x, goal.z, global_position.y)
	if sys.is_walkable(goal) and sys.path_clear(global_position, goal):
		_target = goal
		_enter(S.WANDER, 30.0)
	else:
		_enter(S.IDLE)

func _pick_next() -> void:
	if _return_pending and _return_timer <= 0.0 and not following:
		_return_pending = false
		if _flat(global_position, home) > _wander_r + 1.0:
			_travel(_rand_near_home(), 1.5, false)
			return
	var w := _weights()
	var total := 0.0
	for k in w: total += float(w[k])
	if total <= 0.0:
		_enter(S.IDLE); return
	var r := _rng.randf() * total
	var pick := "idle"
	for k in w:
		r -= float(w[k])
		if r <= 0.0:
			pick = String(k); break
	match pick:
		"wander":
			var tp := _wander_point()
			if tp != Vector3.INF:
				_target = tp
				_enter(S.WANDER, 30.0)
			else:
				_enter(S.IDLE)
		"sit": _enter(S.SIT)
		"groom": _enter(S.GROOM)
		"nap": _enter(S.NAP)
		"look": _enter(S.LOOK)
		"approach": _approach_player()
		_: _enter(S.IDLE)

func _weights() -> Dictionary:
	var w: Dictionary = (WEIGHTS[personality] as Dictionary).duplicate()
	var pd := _player_dist()
	var p = sys.get_player()
	var sess: bool = sys.sit_active
	if pinned:
		w["wander"] = 0.0; w["approach"] = 0.0; w["nap"] = 0.0
	if following:
		w["wander"] = 0.0; w["nap"] = 0.0; w["approach"] = 0.0
	if sess and pd < 3.0:
		w["wander"] = 0.0; w["approach"] = 0.0
		w["nap"] = float(w["nap"]) * 1.5 + 0.4
	var slot: String = sys.cur_slot()
	if slot == "night":
		w["nap"] = float(w["nap"]) * 1.5; w["wander"] = float(w["wander"]) * 0.7
	if slot == "afternoon" and personality == "Lazy":
		w["nap"] = float(w["nap"]) * 2.0
	if sys.cur_weather() == "rain":
		w["wander"] = float(w["wander"]) * 0.6
	# approach: friendly cats come over to a calm, close player
	var ok := p != null and not scares and not pinned and not following and _approach_cd <= 0.0 \
		and pd < 7.0 and pd > 1.8 and _flat(_pp(), home) < 9.0 and not bool(p.get("riding")) \
		and _player_noise(p) < 0.6 and sys.cats_near_player(5.0, self) == 0
	if not ok: w["approach"] = 0.0
	return w

func _approach_player() -> void:
	_approach_cd = 10.0
	var p = sys.get_player()
	if p == null: _enter(S.IDLE); return
	var pp: Vector3 = (p as Node3D).global_position
	var dir := Vector3(global_position.x - pp.x, 0, global_position.z - pp.z).normalized()
	var goal := pp + dir.rotated(Vector3.UP, _rng.randf_range(-0.6, 0.6)) * 1.25
	goal.y = _gy(goal.x, goal.z, global_position.y)
	if sys.is_walkable(goal) and sys.path_clear(global_position, goal): _travel(goal, 1.3, true)
	else: _enter(S.IDLE)

func _wander_point() -> Vector3:
	for i in 6:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(0.4, 1.0) * _wander_r
		var p := home + Vector3(cos(a), 0, sin(a)) * r
		p.y = _gy(p.x, p.z, home.y)
		if _flat(p, global_position) < 0.35: continue
		if not sys.is_walkable(p) or not sys.path_clear(global_position, p): continue
		if sys.crowded(p, self, 0.8): continue
		return p
	return Vector3.INF

func _rand_near_home() -> Vector3:
	var p := _wander_point()
	if p == Vector3.INF:
		p = home
	return p

func _tick_follow(dt: float) -> void:
	var p = sys.get_player()
	if p == null or not following:
		_enter(S.IDLE); _return_pending = true; _return_timer = 1.0; return
	var pp: Vector3 = (p as Node3D).global_position
	var d := _flat(global_position, pp)
	if d <= 1.5:
		_enter(S.IDLE, _rng.randf_range(1.0, 3.0))
		return
	var dir := Vector3(global_position.x - pp.x, 0, global_position.z - pp.z).normalized()
	var goal := pp + dir * 1.3
	_speed = clampf(d * 1.1, 1.8, 7.5)
	_step_to(goal, _speed, dt)

func _start_flee() -> void:
	var from := _scare_from
	var away := Vector3(global_position.x - from.x, 0, global_position.z - from.z)
	if away.length() < 0.05: away = Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))
	away = away.normalized()
	for dist in [6.0, 4.5, 3.0]:
		for ang in [0.0, 0.6, -0.6, 1.2, -1.2, 1.9, -1.9, 2.6, -2.6]:
			var p: Vector3 = global_position + away.rotated(Vector3.UP, ang) * dist
			p.y = _gy(p.x, p.z, global_position.y)
			if sys.is_walkable(p) and sys.path_clear(global_position, p):
				_target = p
				_enter(S.FLEE, 4.0)
				return
	_enter(S.ALERT, _rng.randf_range(2.5, 4.0))

func _attend(dt: float) -> void:
	# turn the body toward Mocha when he is close, otherwise keep a gentle fidget
	if state == S.NAP: return
	var look := look_at_pos
	var pd := INF
	if look == Vector3.INF:
		var p = sys.get_player()
		if p == null: return
		look = (p as Node3D).global_position
		pd = _flat(look, global_position)
		if pd > 3.6 and not (following and pd < FOLLOW_NOTICE): return
	if _look_w <= 0.0 or (shy and pd < 1.0): return
	var want := atan2(look.x - global_position.x, look.z - global_position.z)
	yaw = lerp_angle(yaw, want, 1.0 - exp(-3.5 * _look_w * dt))

func _vertical(dt: float) -> void:
	if _y_off > 0.0 or _vy > 0.0:
		_vy -= 14.0 * dt
		_y_off += _vy * dt
		if _y_off <= 0.0:
			if _vy < -1.5: _squash = 1.0
			_y_off = 0.0
			_vy = 0.0
	_squash = maxf(0.0, _squash - dt * 6.0)

func _step_to(goal: Vector3, spd: float, dt: float) -> bool:
	var p := global_position
	var dv := Vector3(goal.x - p.x, 0, goal.z - p.z)
	var dist := dv.length()
	if dist < 0.05: return true
	var step := minf(spd * dt, dist)
	var dir := dv / dist
	yaw = lerp_angle(yaw, atan2(dir.x, dir.z), 1.0 - exp(-12.0 * dt))
	var np := p + dir * step
	np.y = _gy(np.x, np.z, p.y)
	if not sys.is_walkable(np):
		return true   # never step onto water or blocked ground: treat as arrived
	global_position = np
	_walk_phase += step * (6.0 if spd < 3.0 else 3.4)
	_moving = true
	return step >= dist - 0.001

# ---------------------------------------------------------------- slow tick (scares, facts, following)
func _slow_tick() -> void:
	var p = sys.get_player()
	var pd := INF
	if p != null: pd = _player_dist()
	if p == null or gone or fade < 0.9: return
	# scare
	if scares and _scare_cd <= 0.0 and not (state in [S.REACT, S.FLEE, S.ALERT, S.HOP]):
		var n := _player_noise(p)
		var friend := bool(sys.st(cat_id).get("friend", false))
		var hit := false
		if friend: hit = (n >= 1.2 and pd < 2.5)
		else: hit = (n >= 1.2 and pd < 4.0) or (n >= 0.9 and pd < 2.0)
		if hit:
			scare_from((p as Node3D).global_position)
			return
	# follow (the Biscuit secret): carrying the item makes this cat trail the player
	if follow_item != "" and not (state in [S.REACT, S.FLEE, S.ALERT, S.LEAVE]):
		if GameState.has_item(follow_item):
			if following:
				_follow_move_t += 0.2
				if _follow_move_t >= 2.5 and pd < 2.5: sys.learn(cat_id, "secret", true)
			if not following and pd <= FOLLOW_NOTICE:
				following = true
				_follow_move_t = 0.0
				if state in [S.WANDER, S.TRAVEL, S.SIT, S.GROOM, S.NAP, S.IDLE, S.LOOK]: _enter(S.FOLLOW, 60.0)
		elif following:
			following = false
			_follow_move_t = 0.0
			_return_pending = true
			_return_timer = 1.5
			if state == S.FOLLOW: _enter(S.IDLE, 1.0)
	# facts: seen close enough in this slot
	if pd < 7.0 and not (state in [S.LEAVE]):
		sys.cat_seen(self)

# ---------------------------------------------------------------- fade
func _update_fade(dt: float) -> void:
	if fade != fade_goal:
		fade = move_toward(fade, fade_goal, dt / 0.9)
		_apply_fade()
		if fade <= 0.0 and fade_goal <= 0.0:
			if _free_on_fade:
				queue_free(); return
			if _fade_dest != Vector3.INF:
				global_position = Vector3(_fade_dest.x, _gy(_fade_dest.x, _fade_dest.z, _fade_dest.y), _fade_dest.z)
				_fade_dest = Vector3.INF
				_enter(S.IDLE, 1.0)
				fade_goal = 1.0

func _apply_fade() -> void:
	var e := smoothstep(0.0, 1.0, fade)
	_root.scale = Vector3.ONE * lerpf(0.7, 1.0, e)
	_body.visible = fade > 0.005
	var tr := 1.0 - e
	for m in _meshes:
		if is_instance_valid(m): (m as GeometryInstance3D).transparency = tr
	if _shadow:
		_shadow.visible = fade > 0.05
		_shadow.scale = Vector3(1.1, 1.0, 1.35) * (_model_scale / BASE_SCALE) * lerpf(0.6, 1.0, e)

# ---------------------------------------------------------------- pose
func _update_pose(dt: float) -> void:
	var k := 1.0 - exp(-9.0 * dt)
	var sitting_pose := state == S.SIT or state == S.GROOM
	_p_sit = lerpf(_p_sit, 1.0 if sitting_pose else 0.0, k)
	_p_nap = lerpf(_p_nap, 1.0 if state == S.NAP else 0.0, k)
	_p_alert = lerpf(_p_alert, 1.0 if (state == S.ALERT or state == S.REACT) else 0.0, k)
	_p_run = lerpf(_p_run, 1.0 if (state == S.FLEE or (state == S.TRAVEL and _speed > 3.0) or (state == S.FOLLOW and _moving and _speed > 3.0)) else 0.0, k)
	_p_groom = lerpf(_p_groom, 1.0 if state == S.GROOM else 0.0, k)
	_p_happy = lerpf(_p_happy, 1.0 if state == S.HOP else 0.0, k)
	_p_sniff = lerpf(_p_sniff, 1.0 if state == S.SNIFF else 0.0, k)
	_body.rotation.y = yaw
	# walk bob and stretch
	var bob := 0.0
	var run := _p_run
	if _moving:
		bob = absf(sin(_walk_phase)) * lerpf(0.035, 0.12, run)
	var breath := sin(_t * (2.0 if state != S.NAP else 1.2)) * (0.018 if state != S.NAP else 0.035)
	var react_stretch := 0.0
	if state == S.REACT:
		react_stretch = 0.18
	_rig.position.y = _y_off + bob + 0.07 * _p_sit - 0.015 * _p_nap
	_rig.rotation.x = -0.58 * _p_sit + 0.22 * run + (-0.18 * clampf(_vy / 3.4, -1.0, 1.0) if _y_off > 0.0 else 0.0)
	_rig.rotation.z = sin(_walk_phase * 0.5) * 0.05 * (1.0 if _moving else 0.0)
	var sy := 1.0 - 0.3 * _p_nap - 0.1 * _p_alert - 0.22 * _squash + react_stretch + breath + 0.08 * run
	var sxz := 1.0 + 0.12 * _p_nap + 0.12 * _squash - 0.5 * react_stretch + 0.06 * _p_alert - 0.03 * run
	_rig.scale = Vector3(sxz, sy, sxz + 0.06 * run)
	# models: sleepy face while napping, when happy, or for a blink
	_blink_in -= dt
	if _blink_in <= 0.0:
		_blink = 0.13
		_blink_in = _rng.randf_range(2.5, 6.0)
	_blink = maxf(0.0, _blink - dt)
	var closed := state == S.NAP or _blink > 0.0 or _p_happy > 0.5 or (_p_sniff > 0.5 and state == S.SNIFF and state_t < state_len * 0.5)
	(_models[0].root as Node3D).visible = not closed
	(_models[1].root as Node3D).visible = closed
	# head
	var ph := _p_sit
	var look_yaw := 0.0
	var look_pitch := 0.0
	var tgt := look_at_pos
	var pd := INF
	if tgt == Vector3.INF:
		var p = sys.get_player()
		if p != null:
			tgt = (p as Node3D).global_position
			pd = _flat(tgt, global_position)
	else:
		pd = _flat(tgt, global_position)
	if tgt != Vector3.INF and pd < 6.5 and state != S.NAP and state != S.FLEE:
		var want := wrapf(atan2(tgt.x - global_position.x, tgt.z - global_position.z) - yaw, -PI, PI)
		if absf(want) < 2.4:
			look_yaw = clampf(want, -0.9, 0.9) * lerpf(0.5, 1.0, _look_w)
		look_pitch = -0.1 * clampf(1.5 - pd * 0.2, 0.0, 1.0)
	var hy := lerpf(_head_yaw, look_yaw, 1.0 - exp(-5.0 * dt))
	_head_yaw = hy
	var groom_x := (0.32 + sin(_t * 11.0) * 0.2) * _p_groom
	var groom_z := sin(_t * 5.5) * 0.12 * _p_groom
	var shake := 0.0
	if state == S.SNIFF and _p_sniff < 0.5:
		shake = sin(state_t * 22.0) * 0.5 * (1.0 - state_t / maxf(state_len, 0.1))
	var hp := 0.55 * _p_nap + groom_x + 0.4 * ph * 0.7 + 0.42 * _p_sniff * (1.0 if state_len > 0.9 else 0.0) + look_pitch + sin(_t * 1.7) * 0.02
	hp -= 0.25 * _p_alert
	for m in _models:
		var head: Node3D = m.head
		if head:
			head.rotation = Vector3(hp, hy + shake, groom_z + 0.25 * _p_nap)
	# tail
	var rate := _tail_rate_for_state()
	_tail_cur_rate = lerpf(_tail_cur_rate, rate[0], k)
	_tail_cur_amp = lerpf(_tail_cur_amp, rate[1], k)
	var sway := sin(_t * _tail_cur_rate + float(absi(cat_id.hash()) % 7)) * _tail_cur_amp
	for m in _models:
		var tail: Node3D = m.tail
		if tail:
			tail.rotation = Vector3(-0.1 * _p_alert, sway, 0.0)
			tail.scale = Vector3.ONE * (1.0 + 0.45 * _p_alert)
	_ground_rig(_y_off + bob)

## Feet on the ground: the lowest point of the visible toy cat sits exactly on this node's ground height (plus hop and step bob).
func _ground_rig(lift: float) -> void:
	var idx := 1 if (_models[1].root as Node3D).visible else 0
	var low := INF
	for m in _model_meshes[idx]:
		var mi := m as MeshInstance3D
		if mi == null or mi.mesh == null: continue
		low = minf(low, _mesh_low_y(mi))
	if low == INF: return
	_rig.position.y += global_position.y + lift - low

func _mesh_low_y(mi: MeshInstance3D) -> float:
	var gt := mi.global_transform
	if mi.mesh is SphereMesh:
		var sm := mi.mesh as SphereMesh
		var b := gt.basis
		var ext := Vector3(b.x.y * sm.radius, b.y.y * sm.height * 0.5, b.z.y * sm.radius).length()
		return gt.origin.y - ext
	var wb: AABB = gt * mi.get_aabb()
	return wb.position.y

func _tail_rate_for_state() -> Array:
	var base: Array = TAIL.get(personality, [2.0, 0.3])
	var r: float = base[0]
	var a: float = base[1]
	match state:
		S.NAP: return [0.7, 0.07]
		S.HOP: return [8.0, 0.6]
		S.ALERT, S.REACT: return [9.0, 0.15]
		S.FLEE: return [3.0, 0.1]
		S.SIT, S.GROOM: return [r * 0.8, a * 1.1]
	return [r, a]

# ---------------------------------------------------------------- the one bubble
func _wanted_bubble() -> Array:
	if gone or fade < 0.7: return ["", {}]
	if state == S.REACT or state == S.FLEE or state == S.ALERT: return ["alert", {}]
	if _evt_t > 0.0: return [_evt_kind, _evt_data]
	if sys.ambient_id == cat_id:
		var fav := String(cdata.get("favourite", ""))
		if fav != "" and GameState.has_item(fav) and int(sys.st(cat_id).get("last_treat_day", 0)) != GameState.day:
			return ["want", {"item": fav}]
		if state == S.NAP: return ["zzz", {}]
		return ["name", {"text": sys.bubble_name(cat_id)}]
	return ["", {}]

func _update_bubble(dt: float) -> void:
	_evt_t = maxf(0.0, _evt_t - dt)
	var w := _wanted_bubble()
	var kind := String(w[0])
	var key := kind + (str(w[1]) if kind != "" else "")
	if key != _bub_key:
		_bub_key = key
		if kind == "":
			_bub_goal = 0.0
		else:
			if _bub != null: _bub.queue_free()
			_bub = CatFx.bubble(kind, w[1])
			add_child(_bub)
			_bub_scale = 0.0
			_bub_goal = 1.0
			_bub_age = 0.0
	if _bub == null: return
	_bub_scale = move_toward(_bub_scale, _bub_goal, dt / (0.2 if _bub_goal > _bub_scale else 0.16))
	if _bub_scale <= 0.0 and _bub_goal <= 0.0:
		_bub.queue_free()
		_bub = null
		return
	_bub_age += dt
	var e := smoothstep(0.0, 1.0, _bub_scale)
	var pop := 1.0 + 0.16 * sin(clampf(_bub_age / 0.28, 0.0, 1.0) * PI)
	var sc := Vector3.ONE * e * pop
	var wiggle := 0.0
	if _bub_key.begins_with("alert"): wiggle = sin(_t * 26.0) * 0.012 * clampf(1.2 - _bub_age, 0.0, 1.0)
	_bub.position = Vector3(wiggle, 1.2 + sin(_t * 2.2) * 0.02, 0)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		var d := cam.global_position - _bub.global_position
		if d.length() > 0.05:
			_bub.global_basis = Basis.looking_at(-d.normalized(), Vector3.UP) * Basis.from_scale(sc)
	else:
		_bub.scale = sc
	for hm in _bub.get_meta("pops", []):
		if is_instance_valid(hm):
			var a := clampf((_bub_age - 0.3) / 0.45, 0.0, 1.0)
			(hm as Node3D).scale = (hm as Node3D).get_meta("base") * (1.0 + 0.55 * sin(a * PI))

# ---------------------------------------------------------------- helpers
func _gy(x: float, z: float, fallback: float) -> float:
	return sys.ground_y(x, z, fallback) if sys else fallback

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _pp() -> Vector3:
	var p = sys.get_player() if sys else null
	return (p as Node3D).global_position if p != null else global_position + Vector3(0, 0, 10)

func _player_dist() -> float:
	var p = sys.get_player() if sys else null
	if p == null: return INF
	return _flat((p as Node3D).global_position, global_position)

func _player_noise(p) -> float:
	if p != null and p.has_method("noise_level"):
		return float(p.noise_level())
	return 0.0

func _face_point(pt: Vector3) -> void:
	yaw = atan2(pt.x - global_position.x, pt.z - global_position.z)
