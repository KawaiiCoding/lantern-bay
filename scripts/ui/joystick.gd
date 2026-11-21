extends Control
## Floating virtual joystick. Appears where the thumb touches in the left 60% of the screen, follows the
## drag with a knob and writes InputBridge.touch_move (x right, y down, length 0..1; small push = sneak).
## Works with real touch (multi-touch safe: it tracks one finger by index) and with the mouse on desktop.
## The Hud gives it `blockers` (controls a touch must not start on) and toggles `enabled`.

const RADIUS := 66.0
const KNOB := 31.0
const ZONE := 0.6              # left share of the screen where a touch starts the stick
const DEADZONE := 0.12

static var _used_once := false  # the idle hint ring fades away after the first use

var enabled := true : set = _set_enabled
var blockers: Array = []        # Controls that swallow touches (top bar, buttons)

var _finger := -2               # -2 = none
var _origin := Vector2.ZERO
var _knob := Vector2.ZERO
var _appear := 0.0              # 0..1, drawn size/alpha of the stick
var _tween: Tween
var _hint := 1.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _used_once: _hint = 0.0

func _set_enabled(v: bool) -> void:
	enabled = v
	if not v: cancel()
	queue_redraw()

## Pointer events normalised: {"id", "pos", "type": down|move|up}. Touch always; mouse only when the
## project does not already emulate touch from the mouse (avoids double events).
static func parse(e: InputEvent) -> Dictionary:
	if e is InputEventScreenTouch:
		return {"id": e.index, "pos": e.position, "type": "down" if e.pressed else "up"}
	if e is InputEventScreenDrag:
		return {"id": e.index, "pos": e.position, "type": "move"}
	if Input.is_emulating_touch_from_mouse(): return {}
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.device != InputEvent.DEVICE_ID_EMULATION:
		return {"id": 99, "pos": e.position, "type": "down" if e.pressed else "up"}
	if e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and e.device != InputEvent.DEVICE_ID_EMULATION:
		return {"id": 99, "pos": e.position, "type": "move"}
	return {}

func _input(e: InputEvent) -> void:
	var p := parse(e)
	if p.is_empty(): return
	var id: int = p["id"]
	var pos: Vector2 = p["pos"] - global_position
	match p["type"]:
		"down":
			if _finger == -2 and enabled and is_visible_in_tree() and _can_start(p["pos"]):
				_begin(id, pos)
		"move":
			if id == _finger: _drag(pos)
		"up":
			if id == _finger: _end()

func _can_start(screen_pos: Vector2) -> bool:
	if screen_pos.x > get_viewport_rect().size.x * ZONE: return false
	for b in blockers:
		if is_instance_valid(b) and b is Control and b.is_visible_in_tree() and b.get_global_rect().grow(6.0).has_point(screen_pos):
			return false
	return true

func _begin(id: int, pos: Vector2) -> void:
	_finger = id
	_origin = pos
	_knob = pos
	_used_once = true
	_fade_to(1.0, 0.12)
	_set_hint(0.0)
	_emit()
	queue_redraw()

func _drag(pos: Vector2) -> void:
	_knob = _origin + (pos - _origin).limit_length(RADIUS)
	_emit()
	queue_redraw()

func _end() -> void:
	_finger = -2
	_knob = _origin
	InputBridge.touch_move = Vector2.ZERO
	_fade_to(0.0, 0.18)
	queue_redraw()

func cancel() -> void:
	if _finger != -2: _end()
	else: InputBridge.touch_move = Vector2.ZERO

func _emit() -> void:
	var d := (_knob - _origin) / RADIUS
	var l := d.length()
	if l < DEADZONE:
		InputBridge.touch_move = Vector2.ZERO
	else:
		# remap deadzone..1 -> 0..1 so a gentle push is a quiet sneak, a full push is a full walk
		InputBridge.touch_move = d.normalized() * clampf((l - DEADZONE) / (1.0 - DEADZONE), 0.0, 1.0)

func _fade_to(v: float, t: float) -> void:
	if _tween and _tween.is_valid(): _tween.kill()
	if not is_inside_tree():
		_appear = v; return
	_tween = create_tween()
	_tween.tween_method(_set_appear, _appear, v, t).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _set_appear(v: float) -> void:
	_appear = v
	queue_redraw()

func _set_hint(v: float) -> void:
	if not is_inside_tree():
		_hint = v; return
	var tw := create_tween()
	tw.tween_method(func(x: float) -> void:
		_hint = x
		queue_redraw(), _hint, v, 0.4)

func _exit_tree() -> void:
	if InputBridge: InputBridge.touch_move = Vector2.ZERO

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		cancel()

func _draw() -> void:
	# faint "touch here" ring for brand-new players
	if _hint > 0.01 and enabled and _appear < 0.01:
		var c := Vector2(RADIUS + 46.0, size.y - RADIUS - 84.0)
		draw_arc(c, RADIUS, 0.0, TAU, 48, Color(Style.CREAM, 0.30 * _hint), 5.0, true)
		draw_circle(c, KNOB * 0.8, Color(Style.CREAM, 0.20 * _hint), true, -1.0, true)
	if _appear < 0.01: return
	var k := 0.86 + 0.14 * _appear
	var a := _appear
	# base: soft cream disc with an ink ring
	draw_circle(_origin + Vector2(0, 4), RADIUS * k, Color(Style.SHADOW, 0.18 * a), true, -1.0, true)
	draw_circle(_origin, RADIUS * k, Color(Style.CREAM, 0.34 * a), true, -1.0, true)
	draw_arc(_origin, RADIUS * k, 0.0, TAU, 56, Color(Style.INK, 0.55 * a), 3.0, true)
	# knob
	var kp := _knob if _finger != -2 else _origin
	draw_circle(kp + Vector2(0, 4), KNOB * k, Color(Style.SHADOW, 0.35 * a), true, -1.0, true)
	draw_circle(kp, KNOB * k, Color(Style.PRIMARY, 0.95 * a), true, -1.0, true)
	draw_arc(kp, KNOB * k, 0.0, TAU, 40, Color(Style.INK, 0.9 * a), 3.0, true)
	draw_arc(kp, KNOB * k - 9.0, deg_to_rad(200.0), deg_to_rad(285.0), 12, Color(1, 1, 1, 0.5 * a), 4.0, true)
