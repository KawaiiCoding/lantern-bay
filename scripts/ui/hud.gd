extends CanvasLayer
## Hud (layer 10): top bar, toasts, virtual joystick, Action / Ride / Notebook buttons, modal panels.
##
## Public API (contract, see docs/TEAM.md):
##   set_action(text)            current prompt on the big Action button ("" = faded, still pressable)
##   set_place(text)             place name in the top bar
##   set_controls_visible(b)     joystick + buttons on/off (cutscenes, dialogue); keeps the top bar
##   open_panel(control)         modal, centered, dim backdrop, pops in, pauses time (GameState.set_paused)
##   close_panel()               removes the panel (does not free it unless it has meta "autofree")
##   open_notebook(tab)          "", cats, people, fish, shore, requests, bag, settings
## Closing: Escape / back key, tap on the dim backdrop (unless meta "sticky"), or the panel's own button.
## When Escape / backdrop closes a panel that has a `closed` signal, the Hud emits it so owners clean up.
## Signals: panel_opened(panel), panel_closed(panel).
##
## Touch: Action / Ride / Notebook are routed here from raw multi-touch events (one thumb on the stick,
## another on Action works). Keyboard still goes through InputBridge; the buttons mirror its state.

signal panel_opened(panel: Control)
signal panel_closed(panel: Control)

const Joystick := preload("res://scripts/ui/joystick.gd")
const RoundButton := preload("res://scripts/ui/hud/round_button.gd")
const Notebook := preload("res://scripts/ui/notebook.gd")

const M := 14.0                      # screen edge margin
const TOP_H := 76.0
const ACTION_D := 136.0
const RIDE_D := 96.0
const BOOK_D := 92.0
const TOAST_SECONDS := 2.2

var main: Node
var _inset := Vector4.ZERO           # safe-area insets: left, top, right, bottom (canvas units)

var _root: Control
var _joy: Joystick
var _top: PanelContainer
var _pills: HBoxContainer
var _btn_action: RoundButton
var _btn_ride: RoundButton
var _btn_book: RoundButton
var _fingers := {}                   # touch id -> RoundButton being held
var _controls_on := true

# top bar widgets
var _place_lbl: Label
var _day_lbl: Label
var _time_lbl: Label
var _weather_lbl: Label
var _weather_icon
var _money_pill: PanelContainer
var _money_lbl: Label
var _spark_pill: PanelContainer
var _spark_lbl: Label
var _clock_shown := ""
var _day_shown := -1
var _icon_shown := ""
var _money_shown := -1.0
var _money_tw: Tween
var _prompt := "\u0001"              # impossible value so the first set_action("") applies
var _action_tw: Tween

# toasts
var _toast_holder: Control
var _toast_center: HBoxContainer
var _toast_panel: PanelContainer
var _toast_label: Label
var _toasts: Array = []
var _toast_active := false
var _toast_skip := false             # tap on the toast = dismiss early
var _toast_recent := {}              # text -> msec when it was last queued (duplicate guard)
var _toast_start_ms := 0

# modal
var _modal: Control
var _dim: ColorRect
var _center: CenterContainer
var _panel: Control
var _panel_tw: Tween
var _was_paused := false
var _notebook: Control

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_inset = _safe_insets()
	_build()
	GameState.time_changed.connect(_on_time)
	GameState.coins_changed.connect(_on_coins)
	GameState.sparks_changed.connect(_on_sparks)
	GameState.toast.connect(_on_toast)
	InputBridge.action_pressed.connect(func() -> void: _btn_action.held = true)
	InputBridge.action_released.connect(func() -> void: _btn_action.held = false)
	InputBridge.ride_pressed.connect(_on_ride_signal)
	InputBridge.notebook_pressed.connect(_on_notebook_signal)
	set_action("")
	_refresh_all()
	_run_test()

func setup(main_node: Node) -> void:
	main = main_node

func _exit_tree() -> void:
	if _panel != null and is_instance_valid(_panel): GameState.set_paused(_was_paused)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _panel != null:
		_request_close()

# ------------------------------------------------------------------ public API
func set_action(text: String) -> void:
	if text == _prompt: return
	_prompt = text
	_btn_action.set_content(text, _action_icon(text))
	if _action_tw and _action_tw.is_valid(): _action_tw.kill()
	_action_tw = create_tween()
	_action_tw.tween_property(_btn_action, "modulate:a", 1.0 if text != "" else 0.4, 0.16)
	if text != "": Style.pop(_btn_action, 1.1)

func set_place(text: String) -> void:
	var t := text if text != "" else "Lantern Bay"
	if _place_lbl.text == t: return
	_place_lbl.text = t
	Style.pop(_top, 1.015)

func set_controls_visible(b: bool, topbar := false) -> void:
	_controls_on = b
	for c in [_joy, _btn_action, _btn_ride, _btn_book]:
		c.visible = b
	if topbar:
		_top.visible = b; _pills.visible = b
	if not b: _release_inputs()

func is_panel_open() -> bool:
	return _panel != null and is_instance_valid(_panel)

func get_open_panel() -> Control:
	return _panel if is_panel_open() else null

func open_notebook(tab := "") -> void:
	if _notebook == null:
		_notebook = Notebook.new()
		_notebook.close_requested.connect(_request_close)
	_notebook.fit(get_viewport().get_visible_rect().size)
	if tab != "": _notebook.show_tab(tab)
	open_panel(_notebook)

func open_panel(c: Control) -> void:
	if c == null or not is_instance_valid(c): return
	if _panel != null and is_instance_valid(_panel):
		if _panel == c: return
	else:
		_was_paused = GameState.paused
	if _panel_tw and _panel_tw.is_valid(): _panel_tw.kill()
	for ch in _center.get_children():
		_center.remove_child(ch)
	_panel = c
	if c.get_parent(): c.get_parent().remove_child(c)
	if c.custom_minimum_size == Vector2.ZERO and c.size != Vector2.ZERO:
		c.custom_minimum_size = c.size
	c.pivot_offset_ratio = Vector2(0.5, 0.5)
	c.modulate.a = 0.0
	c.scale = Vector2(0.9, 0.9)
	_center.add_child(c)
	_modal.visible = true
	_dim.modulate.a = 0.0
	GameState.set_paused(true)
	_release_inputs()
	_joy.enabled = false
	_panel_tw = create_tween().set_parallel(true)
	_panel_tw.tween_property(c, "modulate:a", 1.0, 0.16)
	_panel_tw.tween_property(c, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_panel_tw.tween_property(_dim, "modulate:a", 1.0, 0.2)
	panel_opened.emit(c)

func close_panel() -> void:
	if _panel == null: return
	var c := _panel
	_panel = null
	if _panel_tw and _panel_tw.is_valid(): _panel_tw.kill()
	GameState.set_paused(_was_paused)
	_joy.enabled = _controls_on
	if is_instance_valid(c):
		_panel_tw = create_tween().set_parallel(true)
		_panel_tw.tween_property(c, "modulate:a", 0.0, 0.12)
		_panel_tw.tween_property(c, "scale", Vector2(0.95, 0.95), 0.12)
		_panel_tw.tween_property(_dim, "modulate:a", 0.0, 0.14)
		_panel_tw.chain().tween_callback(_finish_close.bind(c))
		panel_closed.emit(c)
	else:
		_modal.visible = false
		panel_closed.emit(null)

func _finish_close(c: Control) -> void:
	if is_instance_valid(c):
		if c.get_parent() == _center: _center.remove_child(c)
		if bool(c.get_meta("autofree", false)): c.queue_free()
	if _panel == null: _modal.visible = false

## Escape / back / backdrop / own button: let the owner clean up through its `closed` signal when it has
## one, then make sure the panel is really gone (never a softlock).
func _request_close() -> void:
	if not is_panel_open(): return
	var p := _panel
	if p.has_signal("closed"): p.emit_signal("closed")
	if _panel == p: close_panel()

# ------------------------------------------------------------------ build
func _safe_insets() -> Vector4:
	if not (OS.get_name() in ["Android", "iOS"]): return Vector4.ZERO
	var win := Vector2(DisplayServer.window_get_size())
	var scr := Vector2(DisplayServer.screen_get_size())
	var safe := DisplayServer.get_display_safe_area()
	if win.x < 1.0 or scr.x < 1.0: return Vector4.ZERO
	var k := get_viewport().get_visible_rect().size.x / win.x
	return Vector4(safe.position.x * k, safe.position.y * k, (scr.x - safe.end.x) * k, (scr.y - safe.end.y) * k)

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_joy = Joystick.new()
	_joy.name = "Joystick"
	_root.add_child(_joy)

	_build_top()
	_build_buttons()
	_build_toast()
	_joy.blockers = [_top, _pills, _btn_book, _btn_action, _btn_ride, _toast_panel]
	_build_modal()

func _build_top() -> void:
	var left := M + _inset.x
	var top := M + _inset.y
	_top = PanelContainer.new()
	_top.name = "TopBar"
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.add_theme_stylebox_override("panel", Style.panel_box(Style.CREAM, 26, 3, 20))
	_top.anchor_right = 1.0
	_top.offset_left = left; _top.offset_right = -(M + _inset.z)
	_top.offset_top = top; _top.offset_bottom = top + TOP_H
	_top.custom_minimum_size.y = TOP_H
	_top.pivot_offset_ratio = Vector2(0.5, 0.5)
	_root.add_child(_top)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.add_child(hb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -3)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)
	_place_lbl = Style.label("Lantern Bay", 27, Style.INK, true)
	_place_lbl.clip_text = true
	_place_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vb.add_child(_place_lbl)
	_day_lbl = Style.label("Day 1", 19, Style.INK_SOFT)
	vb.add_child(_day_lbl)
	_weather_icon = Style.icon("sun", 46.0)
	_weather_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(_weather_icon)
	var vb2 := VBoxContainer.new()
	vb2.add_theme_constant_override("separation", -3)
	vb2.alignment = BoxContainer.ALIGNMENT_CENTER
	vb2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb2)
	_time_lbl = Style.label("06:00", 29, Style.INK, true)
	_time_lbl.custom_minimum_size.x = 82
	_time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb2.add_child(_time_lbl)
	_weather_lbl = Style.label("Sunny", 19, Style.INK_SOFT)
	_weather_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb2.add_child(_weather_lbl)

	# money + sparks pills under the bar
	_pills = HBoxContainer.new()
	_pills.name = "Pills"
	_pills.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pills.add_theme_constant_override("separation", 10)
	_pills.position = Vector2(left, top + TOP_H + 10.0)
	_root.add_child(_pills)
	var m := _pill("yen", Style.money(GameState.coins))
	_money_pill = m[0]; _money_lbl = m[1]
	var s := _pill("spark", str(GameState.sparks))
	_spark_pill = s[0]; _spark_lbl = s[1]
	_pills.add_child(_money_pill)
	_pills.add_child(_spark_pill)
	_money_shown = float(GameState.coins)

func _pill(icon_name: String, text: String) -> Array:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.pivot_offset_ratio = Vector2(0.5, 0.5)
	p.add_theme_stylebox_override("panel", Style.panel_box(Style.CREAM, 22, 3, 14))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var ic := Style.icon(icon_name, 36.0)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var l := Style.label(text, 27, Style.INK, true)
	l.custom_minimum_size.x = 40
	h.add_child(l)
	return [p, l]

func _build_buttons() -> void:
	_btn_action = RoundButton.new()
	_btn_action.name = "ActionButton"
	_btn_action.setup(ACTION_D, "primary")
	_root.add_child(_btn_action)
	_anchor_br(_btn_action, ACTION_D, 24.0, 44.0)

	_btn_ride = RoundButton.new()
	_btn_ride.name = "RideButton"
	_btn_ride.setup(RIDE_D, "mint")
	_btn_ride.set_icon("moped", Style.CREAM, RIDE_D * 0.56)
	_root.add_child(_btn_ride)
	_anchor_br(_btn_ride, RIDE_D, 24.0 + (ACTION_D - RIDE_D) * 0.5, 44.0 + ACTION_D + 14.0)

	_btn_book = RoundButton.new()
	_btn_book.name = "NotebookButton"
	_btn_book.setup(BOOK_D, "gold")
	_btn_book.set_icon("book", Color(0, 0, 0, 0), BOOK_D * 0.56)
	_root.add_child(_btn_book)
	_btn_book.anchor_left = 1.0; _btn_book.anchor_right = 1.0
	_btn_book.offset_right = -(M + _inset.z + 2.0)
	_btn_book.offset_left = _btn_book.offset_right - BOOK_D
	_btn_book.offset_top = M + _inset.y + TOP_H + 10.0
	_btn_book.offset_bottom = _btn_book.offset_top + BOOK_D

func _anchor_br(c: Control, d: float, right: float, bottom: float) -> void:
	c.anchor_left = 1.0; c.anchor_right = 1.0; c.anchor_top = 1.0; c.anchor_bottom = 1.0
	c.offset_right = -(right + _inset.z); c.offset_left = c.offset_right - d
	c.offset_bottom = -(bottom + _inset.w); c.offset_top = c.offset_bottom - d

func _build_toast() -> void:
	_toast_holder = Control.new()
	_toast_holder.name = "Toasts"
	_toast_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_holder.anchor_right = 1.0
	_toast_holder.offset_top = M + _inset.y + TOP_H + 10.0 + BOOK_D + 8.0
	_toast_holder.offset_bottom = _toast_holder.offset_top + 140.0
	add_child(_toast_holder)
	_toast_center = HBoxContainer.new()
	_toast_center.alignment = BoxContainer.ALIGNMENT_CENTER
	_toast_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_toast_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_holder.add_child(_toast_center)
	_toast_panel = PanelContainer.new()
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_STOP        # tap to dismiss
	_toast_panel.gui_input.connect(_on_toast_input)
	_toast_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_toast_panel.add_theme_stylebox_override("panel", Style.panel_box(Style.CREAM, 24, 3, 20))
	_toast_center.add_child(_toast_panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.add_child(h)
	var ic := Style.icon("spark", 30.0)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	_toast_label = Style.label("", 23, Style.INK, true)
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	h.add_child(_toast_label)
	_toast_center.visible = false

func _build_modal() -> void:
	_modal = Control.new()
	_modal.name = "Modal"
	_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.visible = false
	_modal.gui_input.connect(_on_modal_input)
	add_child(_modal)
	_dim = ColorRect.new()
	_dim.color = Style.DIM
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(_dim)
	_center = CenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(_center)

func _on_modal_input(e: InputEvent) -> void:
	# a tap on the dim backdrop (outside the panel) closes it
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if not is_panel_open() or bool(_panel.get_meta("sticky", false)): return
		if _panel.get_global_rect().has_point(e.position): return
		_request_close()

# ------------------------------------------------------------------ input routing
func _input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel") and is_panel_open():
		get_viewport().set_input_as_handled()
		_request_close()
		return
	var p := Joystick.parse(e)
	if p.is_empty(): return
	var id: int = p["id"]
	var pos: Vector2 = p["pos"]
	match p["type"]:
		"down":
			if not _controls_on or is_panel_open() or _fingers.has(id): return
			for b in [_btn_action, _btn_ride, _btn_book]:
				if b.hit(pos):
					_fingers[id] = b
					_press(b)
					break
		"up":
			if _fingers.has(id):
				var b = _fingers[id]
				_fingers.erase(id)
				_release(b, b.hit(pos))

func _press(b: Control) -> void:
	if b == _btn_action:
		InputBridge.press()
	elif b == _btn_ride:
		b.held = true
		InputBridge.ride_pressed.emit()
	else:
		b.held = true

func _release(b: Control, inside: bool) -> void:
	if b == _btn_action:
		if InputBridge.action_held: InputBridge.release()
		b.held = false
	elif b == _btn_ride:
		b.held = false
	else:
		b.held = false
		if inside: InputBridge.notebook_pressed.emit()

## Drop every held button / the stick (panel opened, controls hidden).
func _release_inputs() -> void:
	if _joy: _joy.cancel()
	for id in _fingers.keys():
		var b = _fingers[id]
		if b == _btn_action and InputBridge.action_held: InputBridge.release()
		b.held = false
	_fingers.clear()
	if InputBridge.action_held: InputBridge.release()
	for b in [_btn_action, _btn_ride, _btn_book]:
		if b: b.held = false

func _on_ride_signal() -> void:
	if _btn_ride.held: return          # came from our own touch
	_btn_ride.held = true              # keyboard: a quick visual press
	get_tree().create_timer(0.12).timeout.connect(func() -> void:
		if is_instance_valid(_btn_ride) and not _fingers.values().has(_btn_ride): _btn_ride.held = false)

func _on_notebook_signal() -> void:
	if is_panel_open():
		if _panel == _notebook: _request_close()
	elif _controls_on:
		open_notebook()

func _process(_dt: float) -> void:
	var riding := false
	if main and is_instance_valid(main):
		var pl = main.get("player")
		if pl and is_instance_valid(pl): riding = bool(pl.get("riding"))
	_btn_ride.set_badge(riding)

# ------------------------------------------------------------------ top bar updates
func _refresh_all() -> void:
	_on_time(GameState.day, GameState.minute)
	_money_lbl.text = Style.money(GameState.coins)
	_spark_lbl.text = str(GameState.sparks)

func _on_time(day: int, _minute: float) -> void:
	var clock := GameState.clock_text()
	if clock != _clock_shown:
		_clock_shown = clock
		_time_lbl.text = clock
		_update_weather_icon()
	if day != _day_shown:
		_day_shown = day
		_day_lbl.text = "Day %d" % day
		_update_weather_icon()

func _update_weather_icon() -> void:
	var w := GameState.weather()
	var h := GameState.hour()
	var night := h >= 19.5 or h < 5.5
	var key: String = {"sunny": "sun", "cloudy": "cloud", "rain": "rain", "fog": "fog"}.get(w, "sun")
	if w == "sunny" and night: key = "moon"
	if key == _icon_shown: return
	_icon_shown = key
	_weather_icon.set_kind(key)
	_weather_lbl.text = {"sunny": "Sunny", "cloudy": "Cloudy", "rain": "Rain", "fog": "Fog"}.get(w, "Clear")
	if night and w == "sunny": _weather_lbl.text = "Clear"

func _on_coins(c: int) -> void:
	if _money_tw and _money_tw.is_valid(): _money_tw.kill()
	var from := _money_shown
	_money_tw = create_tween()
	_money_tw.tween_method(_set_money_label, from, float(c), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if float(c) > from: Style.pop(_money_pill, 1.1)

func _set_money_label(v: float) -> void:
	_money_shown = v
	_money_lbl.text = Style.money(int(round(v)))

func _on_sparks(n: int) -> void:
	_spark_lbl.text = str(n)
	Style.pop(_spark_pill, 1.12)

func _action_icon(text: String) -> String:
	var w := text.strip_edges().to_lower().get_slice(" ", 0)
	match w:
		"pet": return "hand"
		"fish", "cast", "reel": return "fish"
		"pick", "collect", "grab": return "shell"
		"shop", "sell", "buy": return "bag"
		"talk", "read", "chat": return "note"
	return ""

# ------------------------------------------------------------------ toasts
## One at a time, queued, never replaced mid-read. Stay 1.5 s + 0.06 s per character (2.5 .. 6 s).
## Duplicates within 10 s are dropped, at most one toast starts every 1.5 s, a tap dismisses early.
const TOAST_MIN := 2.5
const TOAST_MAX := 6.0
const TOAST_GAP_MS := 1500
const TOAST_DUPLICATE_MS := 10000

static func toast_seconds(text: String) -> float:
	return clampf(1.5 + 0.06 * float(text.length()), TOAST_MIN, TOAST_MAX)

func _on_toast(text: String) -> void:
	text = text.strip_edges()
	if text == "": return
	var now := Time.get_ticks_msec()
	if _toast_recent.has(text) and now - int(_toast_recent[text]) < TOAST_DUPLICATE_MS: return
	_toast_recent[text] = now
	for k in _toast_recent.keys():
		if now - int(_toast_recent[k]) > TOAST_DUPLICATE_MS: _toast_recent.erase(k)
	if _toasts.size() >= 3: _toasts.pop_front()        # only waiting ones are dropped, the one on screen is never cut
	_toasts.append(text)
	if not _toast_active: _run_toasts()

func _run_toasts() -> void:
	_toast_active = true
	while not _toasts.is_empty():
		var wait := _toast_start_ms + TOAST_GAP_MS - Time.get_ticks_msec()
		if wait > 0:
			await get_tree().create_timer(float(wait) / 1000.0).timeout
			if not is_inside_tree(): return
		var t: String = _toasts.pop_front()
		await _show_toast(t)
		if not is_inside_tree(): return
		await get_tree().create_timer(0.2).timeout      # a breath between two toasts
		if not is_inside_tree(): return
	_toast_active = false

func _show_toast(text: String) -> void:
	_toast_start_ms = Time.get_ticks_msec()
	_toast_skip = false
	var maxw := minf(get_viewport().get_visible_rect().size.x - 120.0, 400.0)
	_toast_label.text = text
	var w := Style.text_width(text, 23)
	_toast_label.custom_minimum_size.x = minf(w + 2.0, maxw)
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if w > maxw else TextServer.AUTOWRAP_OFF
	_toast_panel.reset_size()
	_toast_center.visible = true
	_toast_center.modulate.a = 0.0
	_toast_center.position.y = -28.0
	var tin := create_tween().set_parallel(true)
	tin.tween_property(_toast_center, "modulate:a", 1.0, 0.18)
	tin.tween_property(_toast_center, "position:y", 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var left := toast_seconds(text)
	while left > 0.0 and not _toast_skip:
		await get_tree().process_frame
		if not is_inside_tree(): return
		left -= get_process_delta_time()
	var tout := create_tween().set_parallel(true)
	tout.tween_property(_toast_center, "modulate:a", 0.0, 0.2)
	tout.tween_property(_toast_center, "position:y", -18.0, 0.2)
	await tout.finished
	_toast_center.visible = false

func _on_toast_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_toast_skip = true

# ------------------------------------------------------------------ self test
## godot --path . -- test=ui shot=/tmp/lb_ui.png wait=2 fresh=1        notebook open on Cats
##     extra: tab=people|cats|fish|shore|requests|bag|settings   open=0 (plain HUD)   test=icons (icon sheet)
## godot --path . -- test=uiloop       behaviour loop with synthetic touch / keys; prints ok/FAIL lines, exits 0 or 1
func _run_test() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=", true, 1)
		if kv.size() == 2: args[kv[0]] = kv[1]
	var t: String = args.get("test", "")
	if t == "uiloop":
		_run_loop_test()
		return
	if t != "ui" and t != "icons": return
	GameState._save_timer = -1.0e9          # never write the fake state to the save file
	await get_tree().create_timer(0.4).timeout
	if get_viewport().get_camera_3d() == null:
		_test_backdrop()
	if t == "icons":
		_test_icon_sheet()
		return
	_test_fake_state()
	set_place("Harbour Pier")
	set_action("Pet")
	if str(args.get("action", "")) != "": set_action(str(args["action"]))
	GameState.say("Pip says that is a suspiciously large fish.")
	if str(args.get("open", "1")) != "0":
		await get_tree().create_timer(0.2).timeout
		open_notebook(str(args.get("tab", "cats")))

func _test_backdrop() -> void:
	var cl := CanvasLayer.new()
	cl.layer = -5
	add_child(cl)
	var g := Gradient.new()
	g.colors = PackedColorArray([Color("a9d1ee"), Color("ffd7c2"), Color("a9d99a"), Color("8fc78a")])
	g.offsets = PackedFloat32Array([0.0, 0.38, 0.5, 1.0])
	var gt := GradientTexture2D.new()
	gt.gradient = g; gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(0, 1); gt.width = 8; gt.height = 256
	var tr := TextureRect.new()
	tr.texture = gt; tr.stretch_mode = TextureRect.STRETCH_SCALE; tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(tr)

func _test_fake_state() -> void:
	GameState.day = 3
	GameState.minute = 9.0 * 60.0 + 42.0
	GameState.coins = 12480
	GameState.sparks = 7
	GameState.cats = {
		"biscuit": {"hearts": 3, "facts": ["favourite", "haunt:morning", "haunt:night"], "last_pet_day": 3, "last_sit_day": 2, "last_treat_day": 0, "friend": false},
		"tofu": {"hearts": 5, "facts": ["secret", "favourite", "haunt:afternoon", "haunt:evening"], "last_pet_day": 3, "last_sit_day": 1, "last_treat_day": 2, "friend": true},
		"pancake": {"hearts": 1, "facts": [], "last_pet_day": 3, "last_sit_day": 0, "last_treat_day": 0, "friend": false},
		"pepper": {"hearts": 0, "facts": [], "last_pet_day": 0, "last_sit_day": 0, "last_treat_day": 0, "friend": false},
	}
	GameState.fish_log = {
		"sardine": {"count": 5, "best_cm": 17.4, "gold": 0},
		"mackerel": {"count": 2, "best_cm": 38.0, "gold": 1},
		"flounder": {"count": 1, "best_cm": 31.5, "gold": 0},
		"sea_bream": {"count": 3, "best_cm": 44.2, "gold": 0},
		"tuna": {"count": 1, "best_cm": 141.0, "gold": 0},
	}
	GameState.shore_log = {"shell_white": 7, "shell_pink": 3, "glass_green": 2, "driftwood": 1}
	GameState.requests = [
		{"who": "maple", "text": "Maple wants any fish over 40 cm.", "done": false, "reward": 120},
		{"who": "cotton", "text": "Cotton needs 3 Green Sea Glass for a mobile.", "done": true, "reward": 70},
		{"who": "pip", "text": "Pip needs a Mackerel for the shop window.", "done": false, "reward": 95},
	]
	GameState.bag = {"fish:sardine": 3, "fish:mackerel": 1, "shore:shell_white": 4, "shore:glass_green": 2, "treat:cream": 1, "treat:tuna_bites": 2}
	GameState.people = {"pip": {"points": 140, "last_talk_day": 3, "last_gift_day": 2, "seen_lines": [], "perks": [], "events": []},
		"maple": {"points": 40, "last_talk_day": 3, "last_gift_day": 0, "seen_lines": [], "perks": [], "events": []}}
	GameState.catalog_changed.emit()
	GameState.bag_changed.emit()
	GameState.people_changed.emit()
	GameState.coins_changed.emit(GameState.coins)
	GameState.sparks_changed.emit(GameState.sparks)
	_clock_shown = ""; _icon_shown = ""
	_refresh_all()

func _test_icon_sheet() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 50
	add_child(cl)
	var bg := ColorRect.new()
	bg.color = Style.CREAM
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(bg)
	var names := ["yen", "clock", "sun", "moon", "cloud", "rain", "fog", "cat", "fish", "shell", "bag", "book", "moped", "hand", "paw",
		"heart", "heart_off", "spark", "star", "check", "close", "person", "note", "lock", "gear", "glass", "wood", "bottle", "flower", "dollar"]
	var grid := GridContainer.new()
	grid.columns = 6
	grid.position = Vector2(16, 10)
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 8)
	cl.add_child(grid)
	for n in names:
		var v := VBoxContainer.new()
		v.add_child(Style.icon(n, 64.0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.add_child(Style.icon(n, 28.0)); row.add_child(Style.icon(n, 18.0))
		v.add_child(row)
		v.add_child(Style.label(n, 16, Style.INK_SOFT))
		grid.add_child(v)
	var bx := HBoxContainer.new()
	bx.position = Vector2(20, 690)
	bx.add_theme_constant_override("separation", 14)
	cl.add_child(bx)
	bx.add_child(Style.button("Primary", "primary", 24, 88))
	bx.add_child(Style.button("Mint", "mint", 24, 88))
	var dis := Style.button("Disabled", "gold", 24, 88)
	dis.disabled = true
	bx.add_child(dis)
	var bx2 := HBoxContainer.new()
	bx2.position = Vector2(20, 800)
	bx2.add_theme_constant_override("separation", 14)
	cl.add_child(bx2)
	bx2.add_child(Style.button("Cream", "cream", 24, 88))
	bx2.add_child(Style.icon_button("close", "cream"))
	bx2.add_child(Style.icon_button("gear", "mint"))
	bx2.add_child(Style.chip("Friend", Style.GOLD))
	bx2.add_child(Style.hearts(3, 5, 28.0))

# ------------------------------------------------------------------ behaviour loop test
var _t_pass := 0
var _t_fail := 0

func _check(cond: bool, what: String) -> void:
	if cond:
		_t_pass += 1
		print("  ok    ", what)
	else:
		_t_fail += 1
		printerr("  FAIL  ", what)

func _touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx; e.position = pos; e.pressed = pressed
	get_viewport().push_input(e, true)

func _drag(idx: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx; e.position = pos
	get_viewport().push_input(e, true)

func _click(pos: Vector2) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT; e.position = pos; e.global_position = pos; e.pressed = down
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		get_viewport().push_input(e, true)
		await get_tree().process_frame

func _key(code: Key, pressed := true) -> void:
	var e := InputEventKey.new()
	e.keycode = code; e.physical_keycode = code; e.pressed = pressed
	get_viewport().push_input(e, true)

func _frames(n := 2) -> void:
	for i in n: await get_tree().process_frame

func _run_loop_test() -> void:
	GameState._save_timer = -1.0e9
	await get_tree().create_timer(0.5).timeout
	print("UILOOP start")
	var ac := _btn_action.get_global_rect().get_center()
	var rc := _btn_ride.get_global_rect().get_center()
	var bc := _btn_book.get_global_rect().get_center()
	var counts := {"press": 0, "release": 0, "ride": 0, "nb": 0}
	InputBridge.action_pressed.connect(func() -> void: counts["press"] += 1)
	InputBridge.action_released.connect(func() -> void: counts["release"] += 1)
	InputBridge.ride_pressed.connect(func() -> void: counts["ride"] += 1)

	# joystick: full push, gentle push, release
	_touch(0, Vector2(110, 560), true); _drag(0, Vector2(110 + 80, 560)); await _frames()
	_check(InputBridge.touch_move.x > 0.95 and absf(InputBridge.touch_move.y) < 0.05, "stick: full push right = (1,0)")
	_drag(0, Vector2(110 + 30, 560)); await _frames()
	_check(InputBridge.touch_move.length() > 0.1 and InputBridge.touch_move.length() < 0.6, "stick: small push = sneak (%.2f)" % InputBridge.touch_move.length())
	_touch(0, Vector2(140, 560), false); await _frames()
	_check(InputBridge.touch_move == Vector2.ZERO, "stick: release zeroes touch_move")
	# stick must not start on the top bar or in the right 40%
	_touch(0, Vector2(80, 40), true); _drag(0, Vector2(160, 40)); await _frames()
	_check(InputBridge.touch_move == Vector2.ZERO, "stick: ignores touches on the top bar")
	_touch(0, Vector2(80, 40), false)
	_touch(0, Vector2(400, 400), true); _drag(0, Vector2(470, 400)); await _frames()
	_check(InputBridge.touch_move == Vector2.ZERO, "stick: ignores touches in the right 40%")
	_touch(0, Vector2(400, 400), false)

	# action hold, released off the button
	_touch(1, ac, true); await _frames()
	_check(InputBridge.action_held and counts["press"] == 1 and _btn_action.held, "action: press holds")
	_touch(1, Vector2(30, 900), false); await _frames()
	_check(not InputBridge.action_held and counts["release"] == 1 and not _btn_action.held, "action: release anywhere lets go (held=%s releases=%d btn=%s)" % [InputBridge.action_held, counts["release"], _btn_action.held])

	# two thumbs: stick (finger 0) + action (finger 1)
	_touch(0, Vector2(120, 600), true); _drag(0, Vector2(120, 520)); await _frames()
	_touch(1, ac, true); await _frames()
	_check(InputBridge.touch_move.y < -0.9 and InputBridge.action_held, "multi-touch: steer + hold action together")
	_touch(1, ac, false); _touch(0, Vector2(120, 520), false); await _frames()
	_check(InputBridge.touch_move == Vector2.ZERO and not InputBridge.action_held, "multi-touch: both released cleanly")

	# ride
	_touch(2, rc, true); await _frames(); _touch(2, rc, false); await _frames()
	_check(counts["ride"] == 1, "ride: one ride_pressed per tap")

	# prompt text
	set_action("Pet Biscuit"); await _frames(30)
	_check(_btn_action.modulate.a > 0.95, "prompt: visible with text")
	set_action(""); await get_tree().create_timer(0.3).timeout
	_check(_btn_action.modulate.a < 0.6, "prompt: faded when empty")
	_touch(1, ac, true); await _frames()
	_check(InputBridge.action_held, "prompt: faded button still presses (fishing needs it)")
	_touch(1, ac, false); await _frames()

	# notebook: button opens, tab switch, close button, escape, key
	var was_paused := GameState.paused
	_touch(3, bc, true); await _frames(); _touch(3, bc, false); await _frames(4)
	_check(is_panel_open() and GameState.paused, "notebook: button opens + pauses time")
	_check(not _joy.enabled, "notebook: stick disabled while open")
	_touch(1, ac, true); await _frames()
	_check(not InputBridge.action_held, "notebook: action ignored while a panel is open")
	_touch(1, ac, false)
	await get_tree().create_timer(0.4).timeout
	var fish_tab = _notebook._tabs.get("fish")
	await _click(fish_tab.get_global_rect().get_center())
	await _frames(2)
	_check(_notebook._tab == "fish", "notebook: tapping the Fish tab switches page")
	await _click(_notebook._tabs["bag"].get_global_rect().get_center())
	_check(_notebook._tab == "bag", "notebook: Bag tab")
	_notebook.show_tab("settings"); await _frames()
	_check(_notebook._tab == "settings", "notebook: settings page")
	_notebook.show_tab("cats"); await _frames()
	_key(KEY_ESCAPE); await _frames(3)
	_check(not is_panel_open() and GameState.paused == was_paused, "notebook: Escape closes + restores pause")
	await get_tree().create_timer(0.3).timeout
	_check(not _modal.visible, "notebook: modal hidden after the close animation")
	_key(KEY_TAB); _key(KEY_TAB, false); await _frames(3)
	_check(is_panel_open(), "notebook: Tab key opens")
	_key(KEY_TAB); _key(KEY_TAB, false); await _frames(3)
	_check(not is_panel_open(), "notebook: Tab key closes")
	open_notebook("cats"); await get_tree().create_timer(0.4).timeout
	var close_btn: Control = _notebook.get_child(0).get_child(0).get_child(4)
	await _click(close_btn.get_global_rect().get_center()); await _frames(3)
	_check(not is_panel_open(), "notebook: close button closes")

	# generic panel with a `closed` signal: Escape and backdrop tap both emit it and close
	var dummy := PanelContainer.new()
	dummy.custom_minimum_size = Vector2(300, 300)
	dummy.add_child(Style.label("Dummy panel", 28))
	var got := {"closed": 0}
	dummy.add_user_signal("closed")
	dummy.connect("closed", func() -> void: got["closed"] += 1; close_panel())
	open_panel(dummy); await get_tree().create_timer(0.35).timeout
	_check(is_panel_open() and dummy.get_parent() != null, "panel: open_panel shows a custom panel")
	_key(KEY_ESCAPE); await _frames(3)
	_check(got["closed"] == 1 and not is_panel_open(), "panel: Escape emits `closed` and closes")
	await get_tree().create_timer(0.3).timeout
	open_panel(dummy); await get_tree().create_timer(0.35).timeout
	await _click(Vector2(6, 6)); await _frames(3)
	_check(got["closed"] == 2 and not is_panel_open(), "panel: tap on the backdrop closes")
	await get_tree().create_timer(0.3).timeout
	var stuck := PanelContainer.new()
	stuck.custom_minimum_size = Vector2(200, 200)
	open_panel(stuck); await get_tree().create_timer(0.3).timeout
	_key(KEY_ESCAPE); await _frames(3)
	_check(not is_panel_open(), "panel: a panel without a close signal still closes on Escape")
	await get_tree().create_timer(0.3).timeout
	# replace one panel with another, then close
	open_panel(dummy); await _frames(2); open_panel(stuck); await _frames(2)
	_check(get_open_panel() == stuck and dummy.get_parent() == null, "panel: opening a second panel replaces the first")
	close_panel(); await get_tree().create_timer(0.3).timeout
	_check(not is_panel_open() and GameState.paused == was_paused, "panel: close_panel restores pause")
	dummy.queue_free(); stuck.queue_free()

	# controls hidden (dialogue / cutscene): nothing reacts, held input is dropped
	_touch(1, ac, true); await _frames()
	set_controls_visible(false); await _frames()
	_check(not InputBridge.action_held and not _btn_action.held, "controls hidden: held action is released")
	_touch(1, ac, false)
	_touch(1, ac, true); await _frames()
	_check(not InputBridge.action_held, "controls hidden: touches ignored")
	_touch(1, ac, false)
	set_controls_visible(true); await _frames()
	_touch(1, ac, true); await _frames()
	_check(InputBridge.action_held, "controls shown again: works")
	_touch(1, ac, false); await _frames()

	# toasts: queued one at a time, duration 1.5 s + 0.06 s/char (2.5..6), duplicates dropped, tap dismisses
	_check(is_equal_approx(toast_seconds("Hi"), 2.5) and is_equal_approx(toast_seconds("x".repeat(40)), 3.9) and is_equal_approx(toast_seconds("x".repeat(200)), 6.0), "toast: duration formula 1.5 + 0.06/char, clamped 2.5..6")
	_check(GameState.toast.is_connected(_on_toast), "toast: wired to GameState.toast")
	GameState.toast.disconnect(_on_toast)          # isolate from toasts the live world raises meanwhile
	var guard := 0
	while (_toast_active or not _toasts.is_empty()) and guard < 900:
		await get_tree().process_frame
		guard += 1
	await get_tree().create_timer(1.6).timeout
	_on_toast("First toast."); _on_toast("Second toast."); _on_toast("First toast.")
	_on_toast("Third, with a long sentence so that the toast has to wrap onto a second line to stay inside the screen.")
	await get_tree().create_timer(0.6).timeout
	_check(_toast_center.visible and _toast_label.text == "First toast.", "toast: first one shows (vis=%s text=%s active=%s q=%s)" % [_toast_center.visible, _toast_label.text, _toast_active, _toasts])
	_check(_toasts.size() == 2, "toast: duplicate within 10 s dropped, others queued (%d waiting)" % _toasts.size())
	await get_tree().create_timer(1.6).timeout
	_check(_toast_label.text == "First toast.", "toast: still on screen after 2.2 s (min 2.5 s, never cut for a newer one)")
	await get_tree().create_timer(1.6).timeout
	_check(_toast_label.text == "Second toast.", "toast: next one follows")
	await get_tree().create_timer(3.4).timeout
	_check(_toast_label.text.begins_with("Third") and _toast_panel.size.x <= 540.0, "toast: long text wraps inside the screen (w=%d)" % int(_toast_panel.size.x))
	await _click(_toast_panel.get_global_rect().get_center())
	await get_tree().create_timer(0.7).timeout
	_check(not _toast_center.visible and not _toast_active, "toast: tap dismisses early, queue drained")
	GameState.toast.connect(_on_toast)

	# money count-up and place name
	GameState.add_coins(1250); await get_tree().create_timer(0.8).timeout
	_check(_money_lbl.text == Style.money(GameState.coins), "top bar: money shows %s" % _money_lbl.text)
	set_place("Plaza"); _check(_place_lbl.text == "Plaza", "top bar: place name")
	_check(Style.money(1250) == "¥1,250" and Style.money(0) == "¥0" and Style.money(1234567) == "¥1,234,567" and Style.money(-4500) == "-¥4,500", "Style.money formats thousands")

	print("UILOOP %d ok, %d failed" % [_t_pass, _t_fail])
	get_tree().quit(1 if _t_fail > 0 else 0)
