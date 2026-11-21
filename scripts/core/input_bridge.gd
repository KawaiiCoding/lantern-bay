extends Node
## InputBridge (autoload): one place for movement + buttons, from keyboard or the touch HUD.
## Player reads `move` (Vector2, length 0..1; x = right, y = down/screen-forward toward camera).
## Touch HUD writes `touch_move` and calls press()/release(). Keyboard: WASD/arrows, E/Space, R, Tab.

signal action_pressed
signal action_released
signal ride_pressed
signal notebook_pressed

var touch_move := Vector2.ZERO
var move := Vector2.ZERO
var action_held := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bind("move_left", [KEY_A, KEY_LEFT]); _bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("move_up", [KEY_W, KEY_UP]); _bind("move_down", [KEY_S, KEY_DOWN])
	_bind("action", [KEY_E, KEY_SPACE]); _bind("ride", [KEY_R]); _bind("notebook", [KEY_TAB])
	_bind("sneak", [KEY_SHIFT])

func _bind(action: String, keys: Array) -> void:
	if not InputMap.has_action(action): InputMap.add_action(action)
	for k in keys:
		var e := InputEventKey.new(); e.physical_keycode = k
		InputMap.action_add_event(action, e)

func _process(_dt: float) -> void:
	var k := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if Input.is_action_pressed("sneak"): k *= 0.45
	move = k if k.length() > 0.05 else touch_move

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("action"): press()
	elif e.is_action_released("action"): release()
	elif e.is_action_pressed("ride"): ride_pressed.emit()
	elif e.is_action_pressed("notebook"): notebook_pressed.emit()

func press() -> void:
	action_held = true; action_pressed.emit()
func release() -> void:
	action_held = false; action_released.emit()
