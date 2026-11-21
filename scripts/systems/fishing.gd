extends Node
## Fishing (GDD 5.1): spot interactables, cast, wait + nibbles, bite, reel minigame, catch card, rewards.
## Owns scripts/systems/fishing.gd, scripts/systems/fishing/*, scripts/ui/fishing_ui.gd.
##
## Flow: IDLE -> CASTING -> WAITING (0-3 nibbles) -> BITE (tap window) -> REELING -> LANDING -> CARD -> IDLE.
## Every exit path goes through _finish(), which always calls player.set_busy(false).
##
## Self-test (keeps QA honest):
##   godot --path . -- test=fishing shot=/tmp/lb_fish.png wait=6 fresh=1
##   options: spot=pier_end|beach|rocks  fish=<id>  gold=1  big=1  result=catch|snap|miss|eager|cancel
##   saves <shot>_reel.png mid-reel and <shot>_card.png on the catch card.

const FishRoll := preload("res://scripts/systems/fishing/fish_roll.gd")
const Fx := preload("res://scripts/systems/fishing/fx.gd")
const Sfx := preload("res://scripts/systems/fishing/sfx.gd")
const SpotNode := preload("res://scripts/systems/fishing/spot.gd")
const FishingUI := preload("res://scripts/ui/fishing_ui.gd")

enum S { IDLE, CASTING, WAITING, BITE, REELING, LANDING, CARD, ENDING }
const SPOTS := ["pier_end", "beach", "rocks", "flats"]
## Used only when there is no island (self-test stage).
const FALLBACK_SPOTS := {"pier_end": Vector3(0, 0.5, -2.6), "beach": Vector3(-3, 0.12, 1.6), "rocks": Vector3(3.5, 0.4, 1.4), "flats": Vector3(-4.5, 0.12, 3.5)}
const RELEASE_AT := 0.36           # cast: when the bobber leaves the rod
const FLY_TIME := 0.55
const LANDING_TIME := 0.7
## Relaxed tuning (owner): generous bite windows, few fake-outs, calm fights.
const RELAX_WINDOW_BONUS := 0.3     # added to Data.ROD bite_window (Lv1 0.7 -> 1.0, Lv2 1.15, Lv3 1.2)
const MAX_NIBBLES := 2
const REEL_HOLD := Vector2(2.4, 4.4) # seconds of holding for small .. big fish (fights ~3-6 s with easing)
const SURGE_WARN := 0.45            # telegraph before each surge
const SNAP_AFTER := 1.4             # seconds held at 100% tension before the line goes
const SOFT_RED := Color("c4504a")

var main: Node
var ui: CanvasLayer
var sfx: Node
var spots := {}
var state: int = S.IDLE
var spot_name := ""
var player: Node3D

var _t := 0.0
var _cool := 0.0
var _press_frame := -1
var _test := {}
var _auto_hold := false
var _stand_in: Node3D
var _paused_by_us := false
var _pending_toasts: Array = []

# session geometry
var _rig: Node3D
var _rod := {}
var _bobber: Node3D
var _shadow: MeshInstance3D
var _line: MeshInstance3D
var _jump_fish: Node3D
var _origin := Vector3.ZERO
var _fwd := Vector3.FORWARD
var _right := Vector3.RIGHT
var _target := Vector3.ZERO
var _water_y := 0.0
var _tip := Vector3.ZERO
var _hand := Vector3.ZERO
var _line_end := Vector3.ZERO
var _cast_from := Vector3.ZERO
var _rod_elev := 0.6
var _rod_bend := 0.0
var _slack := 0.5
var _cam_tw: Tween
var _cam_base := Vector2.ZERO

# fish + wait timeline
var _fish := {}
var _info := {}
var _wait := 4.0
var _nibbles: Array = []
var _nibble_i := 0
var _nibble_t := -1.0
var _nibble_plipped := false
var _shadow_ang := 0.0
var _shadow_r := 3.0
var _shadow_pos := Vector3.ZERO
var _shadow_prev := Vector3.ZERO
var _bite_window := 0.7
var _misses := 0
var _shadow_start_r := 3.2
var _shadow_fade := 0.0
var _test_eager_done := false

# reel
var _prog := 0.0
var _tension := 0.0
var _surge_in := 1.5
var _surge_left := 0.0
var _warn_left := 0.0
var _strength := 1.0
var _hold_time := 3.0
var _tick := 0.0
var _ripple_t := 0.0
var _fish_pos := Vector3.ZERO
var _fish_lat := 0.0
var _fish_dir := 1.0
var _shot_reel_done := false
var _over_t := 0.0

# ---------------------------------------------------------------- setup
func setup(m: Node) -> void:
	main = m
	sfx = Sfx.new(); sfx.name = "FishingSfx"; add_child(sfx)
	ui = FishingUI.new(); ui.name = "FishingUI"; add_child(ui)
	ui.card_closed.connect(_on_card_closed)
	if not InputBridge.action_pressed.is_connected(_on_action_pressed):
		InputBridge.action_pressed.connect(_on_action_pressed)
	for n in SPOTS: _make_spot(n)
	_test = _parse_args()
	if _test.get("test", "") == "fishing": _run_test.call_deferred()

func _island() -> Node:
	var isl = main.get("island") if is_instance_valid(main) else null
	return isl if is_instance_valid(isl) else null

func _hud() -> Node:
	var h = main.get("hud") if is_instance_valid(main) else null
	return h if is_instance_valid(h) else null

func _people() -> Node:
	if not is_instance_valid(main): return null
	var sys = main.get("systems")
	if typeof(sys) == TYPE_DICTIONARY and sys.has("people") and is_instance_valid(sys["people"]): return sys["people"]
	return null

func _spot_pos(n: String) -> Vector3:
	var isl := _island()
	if isl and isl.has_method("spot"):
		var p = isl.spot(n)
		if p is Vector3 and p != Vector3.ZERO: return p
	return FALLBACK_SPOTS.get(n, Vector3.ZERO)

func _make_spot(n: String) -> void:
	var s: Node3D = SpotNode.new()
	s.spot_id = n; s.fishing = self; s.name = "FishSpot_" + n
	if n == "flats": s.interact_priority = 0   # shore combing shares the flats
	s.position = _spot_pos(n)
	add_child(s)
	spots[n] = s

# ---------------------------------------------------------------- contract helpers for spots
func is_active() -> bool: return state != S.IDLE

## Rocks need the harbour lantern (Data.SPOT_LANTERN); flats fishing needs low tide + perk moss:secret_spot.
func spot_unlocked(id: String) -> bool:
	var need := str(FishRoll.table("SPOT_LANTERN").get(id, "harbour" if id == "rocks" else ""))
	if need != "" and not GameState.lanterns.has(need): return false
	if id == "flats":
		if not (GameState.has_method("low_tide") and GameState.low_tide()): return false
		if not FishRoll.has_perk("moss:secret_spot"): return false
	return true
func can_start() -> bool: return state == S.IDLE and _cool <= 0.0

func active_prompt() -> String:
	match state:
		S.CASTING, S.WAITING: return "Hook"
		S.BITE: return "Hook!"
		S.REELING: return "Reel"
	return ""

# ---------------------------------------------------------------- session start
func begin(sp: Node3D, p: Node3D) -> void:
	if not can_start() or not is_instance_valid(sp): return
	player = p if is_instance_valid(p) else null
	spot_name = str(sp.get("spot_id"))
	_press_frame = Engine.get_process_frames()
	_auto_hold = false
	_shot_reel_done = false
	_test_eager_done = false
	_misses = 0
	_pending_toasts.clear()
	if player and player.has_method("set_busy"): player.set_busy(true)
	_origin = player.global_position if player else sp.global_position
	_water_y = _find_water_y()
	_fwd = _water_dir(sp.global_position, _origin)
	_right = _fwd.cross(Vector3.UP).normalized()
	_target = _origin + _fwd * randf_range(3.6, 4.6)
	_target.y = _water_y
	if player:
		if player.has_method("face"): player.face(_target)
		else: player.rotation.y = atan2(_fwd.x, _fwd.z)
	_fish = FishRoll.roll(spot_name, _test, _people())
	_build_rig()
	_set_state(S.CASTING)
	_rod_elev = 0.7
	sfx.play("whoosh", 1.0, -4.0)

func _find_water_y() -> float:
	var isl := _island()
	if isl:
		for k in ["sea_level", "water_level", "water_y", "SEA_LEVEL", "WATER_Y", "WATER_LEVEL"]:
			var v = isl.get(k)
			if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT: return float(v)
	return 0.0

## Direction from the spot toward open water: sample the island around us, prefer low, unwalkable ground
## away from the town centre.
func _water_dir(spot_pos: Vector3, from: Vector3) -> Vector3:
	var isl := _island()
	var center := Vector3.ZERO
	if isl and isl.has_method("spot"):
		var c = isl.spot("plaza")
		if c is Vector3: center = c
	var away := spot_pos - center; away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
	var best := away
	var best_score := -INF
	for i in 32:
		var a := TAU * i / 32.0
		var d := Vector3(sin(a), 0, cos(a))
		var score := d.dot(away) * 0.6
		if isl:
			for r in [2.5, 4.0, 5.5]:
				var q: Vector3 = from + d * r
				if isl.has_method("ground_y"):
					var gy = isl.ground_y(q.x, q.z)
					if (typeof(gy) == TYPE_FLOAT or typeof(gy) == TYPE_INT) and float(gy) < _water_y - 0.05: score += 1.0
				if isl.has_method("is_walkable"):
					var w = isl.is_walkable(q)
					if w is bool and not w: score += 0.6
		if score > best_score:
			best_score = score; best = d
	return best

func _build_rig() -> void:
	_free_rig()
	_rig = Node3D.new(); _rig.name = "FishingRig"
	add_child(_rig)
	_rod = Fx.rod(_rig)
	_bobber = Fx.bobber(_rig)
	_bobber.visible = false
	_line = Fx.line_mesh(_rig)
	_shadow = Fx.shadow(_rig)
	_shadow.visible = false
	_rod_bend = 0.0
	_slack = 0.3
	_update_rig(0.0)
	_line_end = _tip
	_rod.root.scale = Vector3(0.01, 0.01, 0.01)
	_rod.root.create_tween().tween_property(_rod.root, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _free_rig() -> void:
	if is_instance_valid(_rig): _rig.queue_free()
	_rig = null; _rod = {}; _bobber = null; _shadow = null; _line = null; _jump_fish = null

func _set_state(s: int) -> void:
	state = s
	_t = 0.0
	if not _test.is_empty(): print("[fishing test] state ", S.keys()[s], " fish=", _fish.get("id", ""), " ", _fish.get("cm", 0.0), "cm")

# ---------------------------------------------------------------- frame
func _process(dt: float) -> void:
	_cool = maxf(0.0, _cool - dt)
	if state == S.IDLE: return
	if state != S.CARD and not is_instance_valid(_rig):
		_finish(); return
	if player and not is_instance_valid(player): player = null
	_t += dt
	match state:
		S.CASTING: _tick_cast(dt)
		S.WAITING: _tick_wait(dt)
		S.BITE: _tick_bite(dt)
		S.REELING: _tick_reel(dt)
		S.LANDING: _tick_landing(dt)
		S.ENDING: _tick_ending(dt)
		S.CARD:
			if not ui.card_open() and _t > 2.0 and not is_instance_valid(ui.card): _on_card_closed()   # watchdog
	if is_instance_valid(_rig): _update_rig(dt)
	var hud := _hud()
	if hud and hud.has_method("set_action") and state != S.CARD: hud.set_action(active_prompt())

func _on_action_pressed() -> void:
	if Engine.get_process_frames() == _press_frame: return   # the press that started the session
	match state:
		S.WAITING:
			var free_recast: bool = Data.get("RECAST_FREE") != false
			var close := _nibble_t >= 0.0 or (not free_recast and _shadow_r < 1.4)
			if close: _scare()
			else: _end("Reeled in.", "plop")
		S.BITE: _start_reel()
		S.CARD:
			if ui.card_open() and ui._card_t > 0.45: ui.close_card()

# ---------------------------------------------------------------- cast
func _tick_cast(_dt: float) -> void:
	var t := _t
	if t < 0.24:
		_rod_elev = lerpf(0.7, 1.95, ease(t / 0.24, 0.5))          # swing back over the shoulder
	elif t < RELEASE_AT:
		_rod_elev = lerpf(1.95, 0.3, ease((t - 0.24) / (RELEASE_AT - 0.24), 2.2))   # whip forward
	else:
		_rod_elev = lerpf(_rod_elev, 0.5, 0.15)
	if t < RELEASE_AT:
		_bobber.visible = true
		_bobber.global_position = _tip + Vector3.DOWN * 0.12
		_cast_from = _bobber.global_position
		_slack = 0.0
	else:
		var f := clampf((t - RELEASE_AT) / FLY_TIME, 0.0, 1.0)
		var p := _cast_from.lerp(_target, f) + Vector3.UP * sin(PI * f) * 1.7
		_bobber.global_position = p
		_bobber.rotation.x = f * TAU
		_slack = 0.1
		if f >= 1.0:
			_bobber.rotation = Vector3.ZERO
			sfx.play("plop", randf_range(0.95, 1.05), -3.0)
			Fx.ripple(_rig, _target, 0.1, 0.8, 0.8)
			Fx.ripple(_rig, _target, 0.05, 0.45, 0.6)
			_start_wait(false)

# ---------------------------------------------------------------- wait + nibbles
## linger = the same fish stays close after a missed bite, so a retry comes quickly.
func _start_wait(linger: bool) -> void:
	_set_state(S.WAITING)
	var testing := not _test.is_empty()
	var fw := FishRoll.pair("FISH_WAIT", Vector2(2.0, 8.0))
	var max_nib := mini(int(FishRoll.pair("FISH_NIBBLES", Vector2(0, 3)).y), MAX_NIBBLES)
	var n := 0
	if linger:
		_wait = randf_range(1.5, 3.0)
		n = 1 if randf() < 0.3 else 0
		_shadow_start_r = maxf(_shadow_r, 1.6)
	else:
		_wait = randf_range(fw.x, maxf(fw.x, fw.y))
		var r := randf()                     # mostly 0-1 fake-outs, sometimes 2
		n = 0 if r < 0.45 else (1 if r < 0.85 else 2)
		_shadow_ang = randf() * TAU
		_shadow_start_r = 3.2
	n = mini(n, max_nib)
	if testing:
		_wait = 0.8
		n = int(_test.get("nibbles", "1"))
	n = mini(n, int(_wait / 0.7))
	_nibbles = []
	for i in n:
		_nibbles.append(lerpf(0.3, 0.86, (i + randf_range(0.25, 0.75)) / maxf(n, 1)) * _wait)
	if n > 0: _nibbles[n - 1] = minf(_nibbles[n - 1], _wait - 0.5)
	_nibble_i = 0
	_nibble_t = -1.0
	_shadow_r = _shadow_start_r
	_shadow_fade = 1.0 if linger else 0.0
	_slack = 0.6

func _tick_wait(dt: float) -> void:
	var p := clampf(_t / _wait, 0.0, 1.0)
	var r := lerpf(_shadow_start_r, 0.95, ease(p, 0.7))
	var r_eff := r
	_shadow_fade = minf(1.0, _shadow_fade + dt / 0.8)
	if _nibble_t >= 0.0:
		_nibble_t += dt
		var k := clampf(_nibble_t / 0.5, 0.0, 1.0)
		r_eff = lerpf(r, 0.3, sin(PI * k))
		if not _nibble_plipped and _nibble_t > 0.2:
			_nibble_plipped = true
			sfx.play("plip", randf_range(0.95, 1.1), -5.0)
			Fx.ripple(_rig, _target, 0.06, 0.35, 0.5, 0.6)
		if _nibble_t > 0.5: _nibble_t = -1.0
	_shadow_r = r_eff
	_shadow_ang += dt * 0.9 / maxf(r, 0.8)
	_shadow_prev = _shadow_pos
	_shadow_pos = _target + Vector3(cos(_shadow_ang), 0, sin(_shadow_ang)) * r_eff
	_shadow_pos.y = _water_y + 0.03
	if _nibble_i < _nibbles.size() and _t >= float(_nibbles[_nibble_i]):
		_nibble_i += 1
		_nibble_t = 0.0
		_nibble_plipped = false
		if _test.get("result", "") == "eager" and not _test_eager_done:
			_test_eager_done = true
			_on_action_pressed.call_deferred()
	if InputBridge.move.length() > 0.45 or (_test.get("result", "") == "cancel" and _t > 0.4):
		_end("Reeled in.", "plop"); return
	if _t >= _wait: _start_bite()

## Tapped on a nibble: this fish flees ("Too eager."). The line stays in; another fish wanders over.
func _scare() -> void:
	sfx.play("splash", 1.4, -10.0)
	Fx.ripple(_rig, _shadow_pos, 0.1, 0.7, 0.6, 0.7)
	ui.flash("Too eager.", SOFT_RED)
	_misses = 0
	_fish = FishRoll.roll(spot_name, _test, _people())
	_start_wait(false)
	if _test.get("result", "") == "eager": _test["result"] = "cancel"

# ---------------------------------------------------------------- bite
func _start_bite() -> void:
	_set_state(S.BITE)
	var rod := FishRoll.rod()
	# relaxed base: Lv1 commons get >= 1.0 s, rares >= 0.8 s; rod upgrades and perks still add on top
	_bite_window = float(rod.bite_window) + RELAX_WINDOW_BONUS + FishRoll.perk(_people(), "bite_window_bonus")
	if int(_fish.get("rarity", 1)) >= 3:
		_bite_window = maxf(_bite_window - FishRoll.num("BITE_WINDOW_RARE_PENALTY", 0.2), 0.8)
	else:
		_bite_window = maxf(_bite_window, 1.0)
	sfx.play("plunge", 1.0, -3.0); sfx.play("splash", 1.0, -8.0)
	Fx.splash(_rig, _target, 6, 0.6)
	_nudge(0.02)
	Input.vibrate_handheld(40)
	_slack = 0.0
	var cam := get_viewport().get_camera_3d()
	if cam: ui.show_bite(cam.unproject_position(_target))
	else: ui.show_bite(get_viewport().get_visible_rect().size * 0.5)
	ui.set_catcher(true)

func _tick_bite(_dt: float) -> void:
	_shadow_prev = _shadow_pos
	_shadow_pos = _shadow_pos.lerp(_target + Vector3(0, 0.03, 0), 0.3)
	if not _test.is_empty() and _test.get("result", "") != "miss" and _t > 0.25: _start_reel(); return
	if _t > _bite_window: _miss()

## Missed the bite: "It swam off." The shadow lingers nearby and tries again soon (3rd miss: it leaves).
func _miss() -> void:
	ui.hide_bite(); ui.set_catcher(false)
	sfx.play("miss", 1.0, -6.0)
	Fx.ripple(_rig, _target, 0.1, 0.6, 0.6, 0.6)
	_misses += 1
	if _misses >= 3:
		_end("It swam off.", ""); return
	ui.flash("It swam off.", SOFT_RED)
	_shadow_ang = atan2(_shadow_pos.z - _target.z, _shadow_pos.x - _target.x) + 0.6
	_shadow_r = 1.8
	_start_wait(true)

# ---------------------------------------------------------------- reel
func _start_reel() -> void:
	if state != S.BITE: return
	_set_state(S.REELING)
	_misses = 0
	ui.hide_bite()
	ui.flash("Hooked!", Color("4f8f88"))
	sfx.play("splash", 1.2, -8.0)
	var rod := FishRoll.rod()
	var cm := float(_fish.get("cm", 20.0))
	var rar := int(_fish.get("rarity", 1))
	_strength = (0.45 + 0.55 * clampf(cm / 120.0, 0.0, 1.2) + 0.1 * (rar - 1)) * float(rod.surge)
	# most fights 3-6 s (owner); bigger fish take longer. Part of each fight is spent easing off.
	var frac := clampf(0.5 * float(_fish.get("size_t", 0.5)) + 0.5 * clampf(cm / 120.0, 0.0, 1.0), 0.0, 1.0)
	_hold_time = lerpf(REEL_HOLD.x, REEL_HOLD.y, frac) + 0.25 * (rar - 1)
	if _fish.get("junk", false):
		_strength = 0.25; _hold_time = REEL_HOLD.x
	if not _test.is_empty(): _hold_time *= 4.0 if _test.get("result", "") == "snap" else 0.6
	_prog = 0.06
	_tension = 0.1
	_over_t = 0.0
	_surge_left = 0.0; _warn_left = 0.0
	_surge_in = randf_range(0.9, 1.5)
	_fish_pos = _target
	_fish_lat = 0.0
	_ripple_t = 0.0
	ui.show_reel(_fish)

func _tick_reel(dt: float) -> void:
	var junk: bool = _fish.get("junk", false)
	# self-test autopilot: reel while calm, ease off for surges
	if not _test.is_empty():
		if _test.get("result", "") == "snap": _auto_hold = true
		elif _warn_left > 0.0 or _surge_left > 0.0 or _tension > 0.7: _auto_hold = false
		elif _tension < 0.4: _auto_hold = true
	var held := InputBridge.action_held or _auto_hold
	# surges: telegraph (shadow tugs, line wiggles, "!") -> gentle surge -> calm
	if _surge_left > 0.0:
		_surge_left -= dt
		if _surge_left <= 0.0: _surge_in = randf_range(1.4, 2.6) / (0.8 + 0.2 * _strength)
	elif _warn_left > 0.0:
		_warn_left -= dt
		if _warn_left <= 0.0:
			_surge_left = randf_range(0.5, 0.8)
			_fish_dir = -_fish_dir
			sfx.play("splash", randf_range(0.95, 1.1), -9.0)
			Fx.splash(_rig, _fish_pos, 4, 0.4 + 0.2 * _strength)
			Input.vibrate_handheld(20)
	elif not junk:
		_surge_in -= dt
		if _surge_in <= 0.0 and _prog < 0.95:
			_warn_left = SURGE_WARN
			sfx.play("warn", 1.0, -10.0)
	var surging := _surge_left > 0.0
	if held:
		_prog += dt / _hold_time * (0.5 if surging else 1.0)
		_tension += dt * 0.16 * (0.6 + 0.5 * _strength)
		if surging: _tension += dt * 0.55 * _strength
		_tick -= dt
		if _tick <= 0.0:
			_tick = 0.09
			sfx.play("tick", 0.85 + _tension * 0.5, -12.0)
	else:
		_tension -= dt * 1.3          # letting go calms things fast
		_prog -= dt * (0.01 + (0.04 * _strength if surging else 0.0))
	_tension = clampf(_tension, 0.0, 1.0)
	_prog = clampf(_prog, 0.0, 1.0)
	# the line only snaps after a long, sustained 100%
	if _tension >= 0.999 and held: _over_t += dt
	else: _over_t = maxf(0.0, _over_t - dt * 2.0)
	ui.set_reel(_prog, _tension, _warn_left > 0.0, surging, held)
	# fish in the water: comes closer with progress, zigzags, tugs before a surge
	var shore := _origin + _fwd * 1.3
	shore.y = _water_y
	var base := _target.lerp(shore, _prog * 0.85)
	var want_lat := sin(_t * 1.3) * 0.45 + (_fish_dir * 0.7 if surging else 0.0)
	_fish_lat = lerpf(_fish_lat, want_lat, 1.0 - exp(-(3.5 if surging else 2.0) * dt))
	_shadow_prev = _shadow_pos
	_fish_pos = base + _right * _fish_lat
	if _warn_left > 0.0: _fish_pos += _right * sin(_t * 38.0) * 0.07 - _fwd * 0.05   # the tug
	_fish_pos.y = _water_y
	_shadow_pos = _fish_pos + Vector3(0, 0.03, 0)
	_ripple_t -= dt
	if _ripple_t <= 0.0:
		_ripple_t = 0.25 if surging else 0.45
		Fx.ripple(_rig, _fish_pos, 0.1, 0.5 if not surging else 0.75, 0.6, 0.6)
	if not _shot_reel_done and _prog > 0.45:
		_shot_reel_done = true
		if not _test.is_empty(): _test_shot("reel")
	if _over_t >= SNAP_AFTER: _snap(); return
	if _prog >= 1.0: _land()

func _snap() -> void:
	sfx.play("snap", 1.0, -6.0)
	_nudge(0.025)
	Input.vibrate_handheld(40)
	Fx.ripple(_rig, _fish_pos, 0.1, 0.8, 0.7, 0.7)
	ui.hide_reel()
	ui.set_catcher(false)
	_end("The line snapped.", "")

# ---------------------------------------------------------------- landing + rewards
func _land() -> void:
	_set_state(S.LANDING)
	ui.hide_reel()
	ui.set_catcher(false)
	sfx.play("splash", 0.9, -6.0); sfx.play("catch", 1.0, -4.0)
	Fx.splash(_rig, _fish_pos, 9, 0.9)
	_nudge(0.025)
	Input.vibrate_handheld(30)
	_info = _award()
	var gold: bool = _fish.get("gold", false)
	var body: Color = Color("f2c14e") if gold else _fish.get("body", Color("a9c4d6"))
	var fin: Color = Color("d99a30") if gold else _fish.get("fin", Color("6f8fa8"))
	var holder := Node3D.new(); holder.top_level = true
	_rig.add_child(holder)
	holder.global_position = _fish_pos
	Toys.fish(holder, body, fin, clampf(0.5 + float(_fish.get("cm", 20.0)) / 120.0, 0.5, 1.4))
	_jump_fish = holder
	if _shadow: _shadow.visible = false

func _tick_landing(_dt: float) -> void:
	var f := clampf(_t / LANDING_TIME, 0.0, 1.0)
	var to := _hand + Vector3.UP * 0.5 + _fwd * 0.4
	if is_instance_valid(_jump_fish):
		_jump_fish.global_position = _fish_pos.lerp(to, ease(f, 0.8)) + Vector3.UP * sin(PI * f) * 1.6
		_jump_fish.rotation = Vector3(sin(f * 9.0) * 0.6, atan2(_right.x, _right.z), f * TAU)
		_line_end = _jump_fish.global_position
	if f >= 1.0:
		_set_state(S.CARD)
		if is_instance_valid(_rig): _rig.visible = false
		var hud := _hud()
		if hud:
			if hud.has_method("set_action"): hud.set_action("")
			if hud.has_method("set_controls_visible"): hud.set_controls_visible(false)
		if not GameState.paused:
			GameState.set_paused(true); _paused_by_us = true
		sfx.play("sparkle", 1.0, -6.0 if not _fish.get("gold", false) else 0.0)
		ui.show_card(_info)
		if not _test.is_empty(): _test_card_shot()

## Updates the log/bag immediately (and saves); toasts + sparks wait until the card closes.
func _award() -> Dictionary:
	var id := str(_fish.get("id", ""))
	var cm := float(_fish.get("cm", 0.0))
	var gold: bool = _fish.get("gold", false)
	var junk: bool = _fish.get("junk", false)
	var name := str(_fish.get("name", "Fish"))
	var raw = GameState.fish_log.get(id)
	var entry: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	var count := int(entry.get("count", 0))
	var best := float(entry.get("best_cm", 0.0))
	var first := count <= 0
	var record := not first and cm > best
	entry["count"] = count + 1
	entry["best_cm"] = maxf(best, cm)
	entry["gold"] = int(entry.get("gold", 0)) + (1 if gold else 0)
	if id != "":
		GameState.fish_log[id] = entry
		GameState.add_item("fish:%s%s" % [id, ":gold" if gold else ""])
	if GameState.has_signal("catalog_changed"): GameState.catalog_changed.emit()
	_save()
	var spark := FishRoll.table("SPARK")
	var trophy: bool = _fish.get("trophy", false)
	var first_trophy := trophy and not bool(entry.get("trophy", false))
	if trophy: entry["trophy"] = true
	_pending_toasts.clear()
	if not junk:
		if first and int(spark.get("new_fish", 1)) > 0:
			_pending_toasts.append(["spark", int(spark.get("new_fish", 1)), "first " + name])
		if first_trophy and int(spark.get("trophy", 0)) > 0:
			_pending_toasts.append(["spark", int(spark.get("trophy", 0)), "trophy " + name])
		elif record and not first and int(spark.get("record", 0)) > 0:
			_pending_toasts.append(["spark", int(spark.get("record", 0)), name + " record"])
		if gold and int(spark.get("gold", 0)) > 0:
			_pending_toasts.append(["spark", int(spark.get("gold", 0)), "gold " + name])
	var spark_total := 0
	for e in _pending_toasts: spark_total += int(e[1])
	_pending_toasts.append(["say", _dry_line(first, record, gold, junk, int(_fish.get("rarity", 1)), float(_fish.get("size_t", 0.0)))])
	return {"id": id, "name": ("Gold " + name) if gold else name, "cm": cm, "rarity": int(_fish.get("rarity", 1)), "gold": gold,
		"price": int(_fish.get("price", 10)), "body": _fish.get("body", Color("a9c4d6")), "fin": _fish.get("fin", Color("6f8fa8")),
		"record": record, "first": first, "prev_best": best, "junk": junk, "trophy": trophy, "sparks": spark_total}

func _dry_line(first: bool, record: bool, gold: bool, junk: bool, rarity: int, size_t: float) -> String:
	var pool: Array
	if gold: pool = ["It is gold. Nobody can explain this.", "Pip will want to see this. From a distance."]
	elif junk: pool = ["Someone out there is missing a boot.", "Not a fish. It still counts, apparently."]
	elif record or (first and size_t > 0.8): pool = ["Pip will not believe this.", "Pip says that is a suspiciously large fish."]
	elif rarity >= 3: pool = ["The cats will hear about this.", "Rare. Try to act normal."]
	elif first: pool = ["A new one for the notebook.", "Never met one of those before."]
	else: pool = ["A perfectly good fish.", "Small, but sincere.", "The sea gives, modestly."]
	return pool[randi() % pool.size()]

func _on_card_closed() -> void:
	if state != S.CARD: return
	for e in _pending_toasts:
		if e[0] == "spark": GameState.add_sparks(int(e[1]))      # the card already showed "+n spark"
		elif e[0] == "say": GameState.say(str(e[1]))
	if not _pending_toasts.is_empty(): _save()
	_pending_toasts.clear()
	_finish()

func _save() -> void:
	if GameState.has_method("save_soon"): GameState.save_soon()
	elif GameState.has_method("save_game"): GameState.save_game()

# ---------------------------------------------------------------- ending
## Show a word, reel the line in, then _finish() (which frees the player).
func _end(msg: String, snd: String) -> void:
	if state == S.ENDING or state == S.IDLE: return
	if msg != "": ui.flash(msg, SOFT_RED if msg != "Reeled in." else Color("6b4a3a"))
	if snd != "": sfx.play(snd)
	ui.hide_bite(); ui.hide_reel(); ui.set_catcher(false)
	_set_state(S.ENDING)

func _tick_ending(_dt: float) -> void:
	var f := clampf(_t / 0.4, 0.0, 1.0)
	if is_instance_valid(_bobber) and _bobber.visible:
		_bobber.global_position = _bobber.global_position.lerp(_tip + Vector3.DOWN * 0.12, f)
	_rod_elev = lerpf(_rod_elev, 1.1, 0.2)
	if _t > 0.5:
		if is_instance_valid(_rod.get("root")):
			var r: Node3D = _rod.root
			r.create_tween().tween_property(r, "scale", Vector3(0.01, 0.01, 0.01), 0.12)
		_finish()

## The single exit: always frees the player, the UI and time.
func _finish() -> void:
	var rig := _rig
	_rig = null
	if is_instance_valid(rig):
		get_tree().create_timer(0.15).timeout.connect(func() -> void: if is_instance_valid(rig): rig.queue_free())
	_rod = {}; _bobber = null; _shadow = null; _line = null; _jump_fish = null
	state = S.IDLE
	_t = 0.0
	_cool = 0.45
	_auto_hold = false
	if is_instance_valid(ui):
		ui.hide_bite(); ui.hide_reel(); ui.set_catcher(false)
		if ui.card_open(): ui.close_card()
	if _paused_by_us:
		_paused_by_us = false
		GameState.set_paused(false)
	var hud := _hud()
	if hud:
		if hud.has_method("set_controls_visible"): hud.set_controls_visible(true)
		if hud.has_method("set_action"): hud.set_action("")
	if is_instance_valid(player) and player.has_method("set_busy"): player.set_busy(false)
	player = null

func _exit_tree() -> void:
	if state != S.IDLE: _finish()

# ---------------------------------------------------------------- rig update
func _update_rig(dt: float) -> void:
	if _rod.is_empty(): return
	var base := player.global_position if is_instance_valid(player) else _origin
	_hand = base + Vector3.UP * 0.78 + _right * 0.42 + _fwd * 0.32
	var k := 1.0 - exp(-10.0 * dt) if dt > 0.0 else 1.0
	var elev_goal := _rod_elev
	var bend_goal := 0.06
	match state:
		S.WAITING:
			elev_goal = 0.55 + sin(_t * 1.3) * 0.03 - (0.06 if _nibble_t >= 0.0 else 0.0)
			bend_goal = 0.08
		S.BITE:
			elev_goal = 0.45; bend_goal = 0.45
		S.REELING:
			elev_goal = 0.95 - _tension * 0.3 - (0.12 if _surge_left > 0.0 else 0.0)
			bend_goal = 0.15 + _tension * 0.5 + (0.15 if _surge_left > 0.0 else 0.0)
		S.LANDING:
			elev_goal = 1.2; bend_goal = 0.2
	if state != S.CASTING and state != S.ENDING: _rod_elev = lerpf(_rod_elev, elev_goal, k)
	_rod_bend = lerpf(_rod_bend, bend_goal, k)
	var e := _rod_elev
	var d1 := (_fwd * cos(e) + Vector3.UP * sin(e) + _right * 0.22).normalized()
	var grip := _hand - d1 * 0.2           # cork sits in the paw, butt pokes out behind
	var joint := grip + d1 * float(_rod.butt_len)
	var toward := _line_end - joint
	var d2 := d1
	if toward.length() > 0.05: d2 = d1.slerp(toward.normalized(), clampf(_rod_bend, 0.0, 0.85)).normalized()
	_tip = joint + d2 * float(_rod.tip_len)
	Fx.place(_rod.butt, grip, joint)
	Fx.place(_rod.tip, joint, _tip)

	# bobber + line end
	if is_instance_valid(_bobber):
		match state:
			S.WAITING:
				var dip := 0.0
				if _nibble_t >= 0.2 and _nibble_t < 0.36: dip = 0.035 * sin(PI * (_nibble_t - 0.2) / 0.16)
				_bobber.global_position = _target + Vector3.UP * (sin(_t * 2.4) * 0.02 - dip)
				_bobber.rotation.z = sin(_t * 1.7) * 0.08
			S.BITE:
				_bobber.global_position = _target + Vector3(randf_range(-0.03, 0.03), -0.3, randf_range(-0.03, 0.03))
			S.REELING, S.LANDING:
				_bobber.visible = false
		if state == S.CASTING or state == S.WAITING or state == S.BITE or state == S.ENDING:
			_line_end = _bobber.global_position + Vector3.UP * 0.12
	if state == S.REELING: _line_end = _fish_pos + Vector3.DOWN * 0.1

	# line
	if is_instance_valid(_line):
		var slack_goal := _slack
		if state == S.REELING: slack_goal = 0.04 * (1.0 - _tension)
		elif state == S.LANDING: slack_goal = 0.0
		var dist := _tip.distance_to(_line_end)
		var cam := get_viewport().get_camera_3d()
		var cam_pos := cam.global_position if cam else _hand + Vector3(0, 6, 6)
		Fx.draw_line(_line, _tip, _line_end, slack_goal * dist * 0.25, cam_pos, 0.03)

	# shadow
	if is_instance_valid(_shadow):
		var show := state == S.WAITING or state == S.BITE or state == S.REELING
		_shadow.visible = show
		if show:
			var cm := float(_fish.get("cm", 20.0))
			var length := clampf(0.6 + cm / 100.0 * 1.4, 0.7, 3.0)   # exaggerated: size hints at size
			var heading := _shadow_pos - _shadow_prev
			if heading.length() < 0.0005: heading = _fwd
			var alpha := 0.7
			if state == S.WAITING: alpha = _shadow_fade * 0.6
			elif state == S.BITE: alpha = 0.8
			Fx.set_shadow(_shadow, Vector3(_shadow_pos.x, _water_y + 0.03, _shadow_pos.z), heading, length, alpha)

# ---------------------------------------------------------------- juice
func _nudge(amount: float) -> void:
	amount = minf(amount, 0.03)      # owner: never more than a tiny nudge
	var cam := get_viewport().get_camera_3d()
	if cam == null: return
	if _cam_tw and _cam_tw.is_valid():
		_cam_tw.kill()
		cam.h_offset = _cam_base.x; cam.v_offset = _cam_base.y
	else:
		_cam_base = Vector2(cam.h_offset, cam.v_offset)
	_cam_tw = cam.create_tween()
	for i in 5:
		var a := amount * (1.0 - i / 5.0)
		_cam_tw.tween_property(cam, "h_offset", _cam_base.x + randf_range(-a, a), 0.035)
		_cam_tw.parallel().tween_property(cam, "v_offset", _cam_base.y + randf_range(-a, a), 0.035)
	_cam_tw.tween_property(cam, "h_offset", _cam_base.x, 0.05)
	_cam_tw.parallel().tween_property(cam, "v_offset", _cam_base.y, 0.05)

# ---------------------------------------------------------------- self-test (-- test=fishing)
func _parse_args() -> Dictionary:
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv: PackedStringArray = s.split("=", true, 1)
		if kv.size() == 2: a[kv[0]] = kv[1]
	if a.get("test", "") != "fishing": return {}
	return a

func _run_test() -> void:
	await get_tree().create_timer(0.2).timeout
	var sp_name := str(_test.get("spot", "pier_end"))
	if not spots.has(sp_name): sp_name = "pier_end"
	if sp_name == "rocks": GameState.lanterns["harbour"] = true
	_ensure_test_stage()
	var sp: Node3D = spots[sp_name]
	sp.position = _spot_pos(sp_name)
	var p: Node3D = null
	var mp = main.get("player") if is_instance_valid(main) else null
	if is_instance_valid(mp): p = mp
	else: p = _stand_in
	if p:
		p.global_position = sp.global_position + Vector3(0, 0.05, 0)
		if p is CharacterBody3D: p.velocity = Vector3.ZERO
	await get_tree().process_frame
	print("[fishing test] start at ", sp_name, " result=", _test.get("result", "catch"))
	begin(sp, p)
	if get_viewport().get_camera_3d() == null:
		var cam := Camera3D.new(); cam.fov = 45.0
		add_child(cam)
		var cp := _origin - _fwd * 4.5 + Vector3.UP * 4.0 + _right * 1.6
		cam.global_transform = Transform3D(Basis.looking_at((_origin + _fwd * 2.2) - cp, Vector3.UP), cp)
		cam.current = true
	elif is_instance_valid(mp) and mp.has_method("setup") and mp.get("camera") != null:
		pass   # the follow camera catches up on its own
	var watch := 0.0
	while state != S.IDLE and state != S.CARD and watch < 20.0:
		await get_tree().process_frame
		watch += get_process_delta_time()
	print("[fishing test] ended in state ", S.keys()[state], " busy=", p.get("busy") if p else "n/a")

func _ensure_test_stage() -> void:
	var root: Node = main if is_instance_valid(main) else get_parent()
	if _island() == null:
		var w := Node3D.new(); w.name = "FishingTestStage"; add_child(w)
		var body := StaticBody3D.new(); w.add_child(body)
		var deck := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(1.4, 0.3, 4.2)
		deck.shape = bs; deck.position = Vector3(0, 0.35, -0.9); body.add_child(deck)
		var sand := CollisionShape3D.new(); var ss := BoxShape3D.new(); ss.size = Vector3(10, 0.6, 7)
		sand.shape = ss; sand.position = Vector3(0, -0.18, 4.5); body.add_child(sand)
		var rk := CollisionShape3D.new(); var rs := BoxShape3D.new(); rs.size = Vector3(1.6, 0.8, 1.6)
		rk.shape = rs; rk.position = Vector3(3.5, 0.0, 1.4); body.add_child(rk)
		Toys.add(Toys.box(80, 0.04, 80), Toys.mat(Color("8fcfe0"), 0.25, 0.0), Vector3(0, -0.02, 0), w)
		Toys.add(Toys.box(10, 0.6, 7), Toys.mat(Color("f3e2bf"), 0.95, 0.0), Vector3(0, -0.18, 4.5), w)
		Toys.add(Toys.box(1.4, 0.3, 4.2), Toys.mat(Color("c9a882")), Vector3(0, 0.35, -0.9), w)
		for z in [0.8, -0.9, -2.6]:
			for x in [-0.6, 0.6]:
				Toys.add(Toys.cyl(0.09, 0.09, 1.0), Toys.mat(Color("9a7058")), Vector3(x, 0.0, z), w)
		Toys.add(Toys.sphere(0.8), Toys.mat(Color("b9b4c4")), Vector3(3.5, 0.0, 1.4), w, Vector3(1.1, 0.5, 1.0))
		Toys.tree(w, Vector3(-3.5, 0.1, 5.5))
		Toys.tree(w, Vector3(3.2, 0.1, 6.0), 0.8)
	if not is_instance_valid(main) or main.get("sky") == null:
		var sun := DirectionalLight3D.new(); sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(35), 0)
		sun.light_energy = 1.1; sun.light_color = Color("fff1dc"); sun.shadow_enabled = true
		add_child(sun)
		var we := WorldEnvironment.new(); var env := Environment.new()
		env.background_mode = Environment.BG_COLOR; env.background_color = Color("bfe3ef")
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("e9e4f2"); env.ambient_light_energy = 0.5
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		we.environment = env
		add_child(we)
	var mp = main.get("player") if is_instance_valid(main) else null
	if not is_instance_valid(mp) and _stand_in == null:
		_stand_in = Node3D.new(); _stand_in.name = "FishingStandIn"
		add_child(_stand_in)
		Toys.bear(_stand_in)
	if root == null: return

func _test_shot(suffix: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var base := str(_test.get("shot", "/tmp/lb_fish.png"))
	var path := base.get_basename() + "_" + suffix + ".png"
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(path)
		print("[fishing test] saved ", path)

func _test_card_shot() -> void:
	await get_tree().create_timer(0.5).timeout
	_test_shot("card")
