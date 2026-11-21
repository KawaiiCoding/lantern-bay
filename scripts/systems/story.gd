extends Node
## Story: the opening on a brand-new save. Six short cards over a slow camera drift across the real
## island at dawn, then Pip walks up and says hello (first goal: the pier, selling fish, Tuna Bites for
## Pancake). Sets GameState.flags["intro_done"] and hands control back.
## Never blocks: Skip (or Esc) ends it at any point; every exit path goes through _end(), which restores
## the player's camera, busy flag, pause and HUD. Missing parts are skipped.
## Auto-skipped (flag set, nothing shown) when a `test=` user arg is present, under the test runner
## (main loop has a script), or when the save already has progress.
## Preview: `godot --path . -- fresh=1 shot=/tmp/lb_intro.png wait=3` (wait=8, 14 for later cards).

const CARDS := [
	"The city never went dark, and it never let Mocha sleep. Eleven years of that.",
	"One night he left a note on his desk, packed one bag, and caught the last ferry out.",
	"He reached Lantern Bay at dawn. Six neighbours, a lot of cats, and a great deal of quiet.",
	"The lanterns along the bay have been dark for years. Nobody quite says why.",
	"They say the bay lights up when someone new truly settles in. Nobody has, lately.",
	"Mocha did not need much. A bed, a rod, and maybe one cat who did not hate him.",
]
const WELCOME := [
	"You made it! I am Pip, I run the shop. The cats run everything else. Welcome to Lantern Bay.",
	"Start at the end of the pier. Catch anything with fins and bring it to me. I pay in actual yen.",
	"There are Tuna Bites in your bag, on the house. Pancake, the shop cat, adores them. Walk slowly.",
	"And if a lantern ever glows again, come and tell me. It has been a while.",
]
const SHOT_SECONDS := 11.0       # one card's drift from its start pose to its end pose
const FOLLOW_RATE := 0.9         # camera smoothing toward the drifting pose (per second)
const LAYER := 22                # above the dialogue (15), so Skip stays on top

var main: Node
var active := false
var _layer: CanvasLayer
var _root: Control
var _catcher: Control
var _card: PanelContainer
var _text: Label
var _hint: Label
var _skip: Button
var _fade: ColorRect
var _cam: Camera3D
var _prev_cam: Camera3D
var _phase := ""                 # "cards", "return", "welcome", ""
var _i := -1
var _t := 0.0
var _poses: Array = []           # per card: [from_pos, from_look, to_pos, to_look]
var _look := Vector3.ZERO
var _opened_ms := 0
var _last_tap_ms := 0
var _held_pause := false
var _ended := false
var _return_t := 0.0
var _auto := 0.0                 # dev: `intro_auto=2.5` advances cards every N seconds (screenshots)

func setup(m) -> void:
	main = m
	# after main applied fresh=1 (it resets GameState after setup)
	call_deferred("_maybe_start")

func _arg_has(prefix: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with(prefix): return true
	return false

func _should_play() -> bool:
	if bool(GameState.flags.get("intro_done", false)): return false
	if _arg_has("test=") or _arg_has("intro=0"): return false
	var ml = Engine.get_main_loop()
	if ml != null and ml.get_script() != null: return false   # tests/test_runner.gd
	# an older save with progress: never show the opening late
	if GameState.day > 1 or not GameState.fish_log.is_empty() or GameState.sparks > 0: return false
	return true

func _maybe_start() -> void:
	if not _should_play():
		if not bool(GameState.flags.get("intro_done", false)):
			GameState.flags["intro_done"] = true
			GameState.save_soon()
		return
	_start()

# ---------------------------------------------------------------- parts (all optional)
func _player() -> Node3D:
	var p = main.get("player") if main and is_instance_valid(main) else null
	return p if p is Node3D and is_instance_valid(p) else null

func _hud() -> Node:
	var h = main.get("hud") if main and is_instance_valid(main) else null
	return h if h and is_instance_valid(h) else null

func _people() -> Node:
	var s = main.get("systems") if main and is_instance_valid(main) else null
	if not (s is Dictionary): return null
	var p = s.get("people")
	return p if p and is_instance_valid(p) else null

func _spot(n: String, fallback: Vector3) -> Vector3:
	var p := Vector3.ZERO
	if main and main.has_method("spot"): p = main.spot(n)
	return fallback if p == Vector3.ZERO else p

func _ground(p: Vector3) -> float:
	var isl = main.get("island") if main else null
	if isl and is_instance_valid(isl) and isl.has_method("ground_y"): return float(isl.ground_y(p.x, p.z))
	return p.y

func _player_cam() -> Camera3D:
	var p := _player()
	if p == null: return null
	var c = p.get("camera")
	return c if c is Camera3D and is_instance_valid(c) else null

# ---------------------------------------------------------------- start
func _start() -> void:
	active = true
	_phase = "cards"
	var p := _player()
	if p and p.has_method("set_busy"): p.set_busy(true)
	if not GameState.paused:
		GameState.set_paused(true); _held_pause = true
	var h := _hud()
	if h and h.has_method("set_controls_visible"): h.set_controls_visible(false, true)
	if h is CanvasLayer: h.visible = false
	_set_side_layers(false)
	_build_poses()
	_build_camera()
	_build_ui()
	if not InputBridge.action_pressed.is_connected(_on_action):
		InputBridge.action_pressed.connect(_on_action)
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("intro_auto="): _auto = float(str(a).split("=")[1])
	_show_card(0)

## Goals chip and minimap draw on their own CanvasLayers: hide them while the cards play.
func _set_side_layers(on: bool) -> void:
	var s = main.get("systems") if main else null
	if not (s is Dictionary): return
	for id in ["goals", "minimap"]:
		var n = s.get(id)
		if n == null or not is_instance_valid(n): continue
		if n is CanvasLayer: n.visible = on
		for c in n.get_children():
			if c is CanvasLayer: c.visible = on

func _build_poses() -> void:
	var pier_end := _spot("pier_end", Vector3(0, 0, 14))
	var pier := _spot("pier", Vector3(0, 0, 6))
	var harbour := _spot("lantern_harbour", pier + Vector3(-2.6, 0, -0.6))
	var plaza := _spot("plaza", Vector3(0, 0, 2.5))
	var home := _spot("spawn", Vector3(-4, 0, -4.7))
	var pl := _player()
	if pl: home = pl.global_position
	harbour.y = _ground(harbour); plaza.y = _ground(plaza)
	var up := Vector3.UP
	_poses = [
		# 1. out at sea, the island small and asleep on the horizon
		[pier_end + Vector3(14, 7, 34), plaza + up * 1.0, pier_end + Vector3(6, 5.5, 27), plaza + up * 1.0],
		# 2. the ferry's line: gliding in along the pier
		[pier_end + Vector3(7, 4.5, 15), pier_end + up * 0.5, pier_end + Vector3(3, 3.5, 9), pier + up * 0.5],
		# 3. dawn over the town
		[pier + Vector3(-7, 6, 9), plaza + up * 1.0, pier + Vector3(-3, 7, 6), plaza + up * 1.0],
		# 4. the dark harbour lantern, close
		[harbour + Vector3(3.5, 2.4, 5), harbour + up * 1.4, harbour + Vector3(1.6, 2.0, 4.2), harbour + up * 1.5],
		# 5. high over the bay
		[plaza + Vector3(4, 16, 18), plaza, plaza + Vector3(-3, 19, 15), plaza],
		# 6. down to Mocha at home
		[home + Vector3(3.5, 4.5, 8.5), home + up * 0.8, home + Vector3(1.2, 3.2, 6.5), home + up * 0.8],
	]

func _build_camera() -> void:
	_prev_cam = get_viewport().get_camera_3d()
	_cam = Camera3D.new()
	_cam.name = "StoryCam"
	_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_cam.fov = 48.0
	_cam.near = 0.3; _cam.far = 260.0
	var pc := _player_cam()
	if pc and pc.attributes: _cam.attributes = null   # no tilt-shift on wide shots
	var parent: Node = main if main is Node3D else self
	parent.add_child(_cam)
	_cam.top_level = true
	var a: Array = _poses[0]
	_cam.global_position = a[0]
	_look = a[1]
	_cam.look_at(_look, Vector3.UP)
	_cam.make_current()

func _build_ui() -> void:
	_layer = CanvasLayer.new(); _layer.layer = LAYER
	add_child(_layer)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_root)
	# soft vignette: clear centre, warm dark edges
	var vg := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.42); gt.fill_to = Vector2(0.5, 1.12)
	gt.width = 256; gt.height = 256
	var g := Gradient.new()
	g.set_color(0, Color(0.16, 0.10, 0.08, 0.0)); g.set_offset(0, 0.45)
	g.set_color(1, Color(0.16, 0.10, 0.08, 0.62))
	gt.gradient = g
	vg.texture = gt
	vg.stretch_mode = TextureRect.STRETCH_SCALE
	vg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vg.set_anchors_preset(Control.PRESET_FULL_RECT)
	vg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(vg)
	# tap anywhere to continue
	_catcher = Control.new()
	_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_catcher.gui_input.connect(_on_gui_input)
	_root.add_child(_catcher)
	# the card: cream, ink border, centred near the bottom
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", Style.panel_box(Style.CREAM, 22, 3, 22))
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.anchor_left = 0.0; _card.anchor_right = 1.0; _card.anchor_top = 1.0; _card.anchor_bottom = 1.0
	_card.offset_left = 28; _card.offset_right = -28; _card.offset_top = -250; _card.offset_bottom = -96
	_root.add_child(_card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(vb)
	_text = Style.label("", 25, Style.INK, true)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.custom_minimum_size = Vector2(400, 0)
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_text)
	_hint = Style.label("", 16, Style.INK_SOFT, false)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_hint)
	# Skip, top right, always on top
	_skip = Style.button("Skip", "cream", 22)
	_skip.custom_minimum_size = Vector2(130, Style.MIN_TOUCH)
	_skip.anchor_left = 1.0; _skip.anchor_right = 1.0
	_skip.offset_left = -152; _skip.offset_right = -22; _skip.offset_top = 26; _skip.offset_bottom = 26 + Style.MIN_TOUCH
	_skip.pressed.connect(skip)
	_root.add_child(_skip)
	# dark at first: the city at night, then dawn
	_fade = ColorRect.new()
	_fade.color = Color(0.10, 0.07, 0.07, 1.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade)
	_root.move_child(_skip, -1)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 2.2).set_trans(Tween.TRANS_SINE)

# ---------------------------------------------------------------- cards
func _show_card(i: int) -> void:
	_i = i
	_t = 0.0
	_opened_ms = Time.get_ticks_msec()
	_text.text = str(CARDS[i])
	_hint.text = "%d / %d    Tap to continue" % [i + 1, CARDS.size()]
	_card.modulate.a = 0.0
	_card.pivot_offset = Vector2(242, 77)
	_card.scale = Vector2(0.97, 0.97)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_card, "modulate:a", 1.0, 0.6 if i == 0 else 0.35).set_delay(0.9 if i == 0 else 0.0)
	tw.tween_property(_card, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if i == CARDS.size() - 1: _pip_walk_in()

func _advance() -> void:
	if _phase != "cards": return
	var now := Time.get_ticks_msec()
	if now - _opened_ms < 350 or now - _last_tap_ms < 150: return
	_last_tap_ms = now
	if _i + 1 < CARDS.size():
		_show_card(_i + 1)
	else:
		_to_player_camera()

func _on_gui_input(e: InputEvent) -> void:
	if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) \
			or (e is InputEventScreenTouch and e.pressed):
		_advance()
		_catcher.accept_event()

func _on_action() -> void:
	if _phase == "cards": _advance()

func _unhandled_input(e: InputEvent) -> void:
	if not active: return
	if e.is_action_pressed("ui_cancel"):
		skip(); get_viewport().set_input_as_handled()
	elif _phase == "cards" and e.is_action_pressed("ui_accept"):
		_advance(); get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- camera
func _process(dt: float) -> void:
	if not active or not is_instance_valid(_cam): return
	_t += dt
	if _auto > 0.0 and _phase == "cards" and _t > _auto:
		_opened_ms = 0; _last_tap_ms = 0; _advance()
	var to_pos: Vector3
	var to_look: Vector3
	var rate := FOLLOW_RATE
	if _phase == "cards" and _i >= 0 and _i < _poses.size():
		var p: Array = _poses[_i]
		var k := smoothstep(0.0, 1.0, clampf(_t / SHOT_SECONDS, 0.0, 1.0))
		to_pos = (p[0] as Vector3).lerp(p[2], k)
		to_look = (p[1] as Vector3).lerp(p[3], k)
		if _i == 0 and _t < 0.05: rate = 60.0
	elif _phase == "return":
		var pc := _player_cam()
		if pc == null:
			_start_welcome(); return
		to_pos = pc.global_position
		to_look = pc.global_position - pc.global_transform.basis.z * 11.0
		rate = 2.6
		_return_t += dt
		_cam.fov = lerpf(_cam.fov, pc.fov, 1.0 - exp(-rate * dt))
		if _cam.global_position.distance_to(to_pos) < 0.25 or _return_t > 3.0:
			_start_welcome(); return
	else:
		return
	var a := 1.0 - exp(-rate * dt)
	_cam.global_position = _cam.global_position.lerp(to_pos, a)
	_look = _look.lerp(to_look, a)
	if _cam.global_position.distance_to(_look) > 0.1:
		_cam.look_at(_look, Vector3.UP)

func _to_player_camera() -> void:
	_phase = "return"
	_return_t = 0.0
	var tw := create_tween()
	tw.tween_property(_card, "modulate:a", 0.0, 0.3)
	_catcher.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _restore_camera() -> void:
	var pc := _player_cam()
	if pc: pc.make_current()
	elif is_instance_valid(_prev_cam): _prev_cam.make_current()
	if is_instance_valid(_cam): _cam.queue_free()
	_cam = null

# ---------------------------------------------------------------- Pip's welcome
func _pip_node() -> Node3D:
	var pe := _people()
	if pe == null or not pe.has_method("node"): return null
	var n = pe.node("pip")
	return n if n is Node3D and is_instance_valid(n) else null

func _pip_walk_in() -> void:
	var n := _pip_node()
	var pl := _player()
	if n == null or pl == null or not n.has_method("walk_to"): return
	var me := pl.global_position
	var start := me + Vector3(2.8, 0, 2.2)
	start.y = _ground(start)
	var stop := me + Vector3(1.0, 0, 1.15)
	stop.y = _ground(stop)
	n.walk_to(start, true)
	n.walk_to(stop, false)
	if pl.has_method("face"): pl.face(stop)

func _start_welcome() -> void:
	if _phase == "welcome" or _ended: return
	_phase = "welcome"
	_restore_camera()
	var hud := _hud()
	if hud is CanvasLayer: hud.visible = true
	if is_instance_valid(_catcher): _catcher.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(_card): _card.visible = false
	var n := _pip_node()
	var pl := _player()
	if n and pl:
		var stop := pl.global_position + Vector3(1.0, 0, 1.15)
		stop.y = _ground(stop)
		if n.global_position.distance_to(stop) > 0.4 and n.has_method("walk_to"): n.walk_to(stop, true)
		if n.has_method("face_point"): n.face_point(pl.global_position)
		if pl.has_method("face"): pl.face(n.global_position)
		if n.has_method("wave"): n.wave()
	var pe := _people()
	var dlg = pe.get("dialogue") if pe else null
	if dlg == null or not is_instance_valid(dlg) or not dlg.has_method("open"):
		_end(); return
	if n and n.has_method("set_talking"): n.set_talking(true)
	var accent := Color("e0a64a")
	if pe.has_method("_accent"): accent = pe._accent("pip")
	var nm := "Pip"
	if pe.has_method("person_name"): nm = str(pe.person_name("pip"))
	dlg.open(nm, WELCOME.duplicate(), accent, _end)

# ---------------------------------------------------------------- skip / end
func skip() -> void:
	if not active or _ended: return
	if _phase == "welcome":
		var pe := _people()
		var dlg = pe.get("dialogue") if pe else null
		if dlg and is_instance_valid(dlg) and dlg.has_method("is_open") and dlg.is_open():
			dlg.close()   # calls _end through the dialogue's callback
			return
	_end()

func _end() -> void:
	if _ended: return
	_ended = true
	active = false
	_phase = ""
	GameState.flags["intro_done"] = true
	GameState.save_soon()
	_restore_camera()
	var n := _pip_node()
	if n and n.has_method("set_talking"): n.set_talking(false)
	# Pip heads back to the counter on the routine's next tick
	var pe := _people()
	if pe and "_cur_spot" in pe and pe._cur_spot is Dictionary: pe._cur_spot.erase("pip")
	if InputBridge.action_pressed.is_connected(_on_action):
		InputBridge.action_pressed.disconnect(_on_action)
	if is_instance_valid(_layer):
		var tw := create_tween()
		tw.tween_property(_root, "modulate:a", 0.0, 0.25)
		tw.tween_callback(_layer.queue_free)
	# give control back next frame, so the same tap does not trigger the player
	call_deferred("_release")

func _release() -> void:
	var p := _player()
	if p and p.has_method("set_busy"): p.set_busy(false)
	if _held_pause: GameState.set_paused(false)
	_held_pause = false
	var h := _hud()
	if h is CanvasLayer: h.visible = true
	if h and h.has_method("set_controls_visible"): h.set_controls_visible(true, true)
	_set_side_layers(true)

func _exit_tree() -> void:
	if active and not _ended:
		_ended = true; active = false
		if _held_pause: GameState.set_paused(false)
