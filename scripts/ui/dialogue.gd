extends CanvasLayer
## Dialogue box: bottom panel, name tag, typewriter text, tap (or Action) to continue.
## Portrait-free. Modal while open: pauses island time, locks the player, hides HUD controls,
## and always gives all of that back on every exit path (finish, close(), freed).
##
## open(speaker, lines, accent := Color(), on_done := Callable())
##   lines: Array of String ("Mocha: text" = spoken by Mocha) or {"who": name, "text": t, "color": Color}.
## add_lines(lines) appends to an open dialogue. is_open(), close().

signal finished

const FALLBACK_CREAM := Color("fffaf2")
const FALLBACK_INK := Color("6b4a3a")
const MOCHA_COLOR := Color("6fc2b6")
const CPS := 70.0                   # typewriter characters per second (tap completes the page)
const PAGE_MAX := 110               # characters per page; longer lines are split into pages

var main: Node
var cream := FALLBACK_CREAM
var ink := FALLBACK_INK
var _font: Font

var _root: Control
var _catcher: Control
var _panel: PanelContainer
var _tag: PanelContainer
var _tag_label: Label
var _text: Label
var _arrow: Polygon2D
var _queue: Array = []
var _speaker := ""
var _accent := Color("f2c14e")
var _on_done := Callable()
var _open := false
var _typing := false
var _chars := 0.0
var _opened_ms := 0
var _last_tap_ms := 0
var _t := 0.0
var _held_busy := false
var _held_pause := false
var _was_paused := false
var _hid_controls := false
var _tw: Tween

func _init() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	_load_style()
	_build()
	if not InputBridge.action_pressed.is_connected(_on_action):
		InputBridge.action_pressed.connect(_on_action)

func _exit_tree() -> void:
	if _open: _release(true)

func _load_style() -> void:
	var path := "res://scripts/ui/style.gd"
	if not ResourceLoader.exists(path): return
	var scr = load(path)
	if scr == null or not (scr is Script): return
	var cm: Dictionary = scr.get_script_constant_map()
	for k in ["CREAM", "PAPER", "PANEL", "BG"]:
		if cm.has(k) and cm[k] is Color: cream = cm[k]; break
	for k in ["INK", "TEXT", "FG"]:
		if cm.has(k) and cm[k] is Color: ink = cm[k]; break
	for k in ["FONT", "FONT_BOLD"]:
		if cm.has(k) and cm[k] is Font: _font = cm[k]; break
	if _font == null:
		for md in scr.get_script_method_list():
			if str(md.get("name", "")) == "font":
				var f = scr.font(true)
				if f is Font: _font = f
				break

func _box(bg: Color, radius: int, border: int, pad: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.border_color = ink
	sb.set_border_width_all(border)
	sb.content_margin_left = pad; sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.75; sb.content_margin_bottom = pad * 0.75
	sb.shadow_color = Color(ink, 0.25); sb.shadow_size = 6; sb.shadow_offset = Vector2(0, 4)
	sb.anti_aliasing = true
	return sb

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)
	_catcher = Control.new()
	_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_catcher.gui_input.connect(_on_gui_input)
	_root.add_child(_catcher)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.anchor_left = 0.0; _panel.anchor_right = 1.0; _panel.anchor_top = 1.0; _panel.anchor_bottom = 1.0
	_panel.offset_left = 16; _panel.offset_right = -16; _panel.offset_top = -244; _panel.offset_bottom = -36
	_panel.add_theme_stylebox_override("panel", _box(cream, 26, 4, 26))
	_root.add_child(_panel)
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 18)
	_panel.add_child(m)
	_text = Label.new()
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_text.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	_text.add_theme_color_override("font_color", ink)
	_text.add_theme_font_size_override("font_size", 25)
	_text.add_theme_constant_override("line_spacing", 4)
	if _font: _text.add_theme_font_override("font", _font)
	m.add_child(_text)

	_tag = PanelContainer.new()
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag.anchor_top = 1.0; _tag.anchor_bottom = 1.0
	_tag.offset_left = 36; _tag.offset_top = -272; _tag.offset_bottom = -218
	_root.add_child(_tag)
	_tag_label = Label.new()
	_tag_label.add_theme_font_size_override("font_size", 24)
	_tag_label.add_theme_color_override("font_color", cream)
	_tag_label.add_theme_color_override("font_outline_color", ink)
	_tag_label.add_theme_constant_override("outline_size", 6)
	if _font: _tag_label.add_theme_font_override("font", _font)
	_tag.add_child(_tag_label)

	_arrow = Polygon2D.new()
	_arrow.polygon = PackedVector2Array([Vector2(-11, -6), Vector2(11, -6), Vector2(0, 7)])
	_arrow.color = ink
	_root.add_child(_arrow)

# ---------------------------------------------------------------- API
func is_open() -> bool: return _open

func open(speaker: String, lines: Array, accent := Color(0, 0, 0, 0), on_done := Callable()) -> void:
	if lines.is_empty():
		if on_done.is_valid(): on_done.call()
		return
	if _open:
		# already talking: just append (and chain the callback)
		add_lines(lines)
		if on_done.is_valid():
			var prev := _on_done
			_on_done = func():
				if prev.is_valid(): prev.call()
				on_done.call()
		return
	_speaker = speaker
	if accent.a > 0.0: _accent = accent
	_on_done = on_done
	_queue = lines.duplicate()
	_open = true
	_opened_ms = Time.get_ticks_msec()
	_hold()
	_root.visible = true
	_root.modulate.a = 0.0
	_panel.position.y += 0.0
	if _tw and _tw.is_valid(): _tw.kill()
	_tw = create_tween()
	_tw.tween_property(_root, "modulate:a", 1.0, 0.15)
	_next()

func add_lines(lines: Array) -> void:
	for l in lines: _queue.append(l)

func close() -> void:
	if not _open: return
	_queue.clear()
	_finish()

# ---------------------------------------------------------------- flow
func _next() -> void:
	if _queue.is_empty():
		_finish(); return
	var l = _queue.pop_front()
	var who := _speaker
	var col := _accent
	var txt := ""
	var narration := false
	if l is Dictionary:
		who = str(l.get("who", _speaker)); txt = str(l.get("text", ""))
		if l.get("color") is Color: col = l.get("color")
		narration = bool(l.get("narration", false))
	else:
		txt = str(l)
		if txt.begins_with("Mocha: "):
			who = "Mocha"; col = MOCHA_COLOR; txt = txt.substr(7)
	var pages := split_pages(txt)
	if pages.size() > 1:
		txt = pages[0]
		for i in range(pages.size() - 1, 0, -1):
			_queue.push_front({"who": who, "text": pages[i], "color": col, "narration": narration})
	_tag_label.text = who
	_tag.visible = who != ""
	_text.add_theme_color_override("font_color", ink.lightened(0.22) if narration else ink)
	_tag.add_theme_stylebox_override("panel", _box(col.darkened(0.05), 18, 4, 18))
	_tag.reset_size()
	_text.text = txt
	_text.visible_characters = 0
	_chars = 0.0
	_typing = true
	# little squish on the panel for each new line
	_panel.pivot_offset = _panel.size * 0.5
	var tw := create_tween()
	tw.tween_property(_panel, "scale", Vector2(1.015, 0.985), 0.05)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Split text into pages of at most PAGE_MAX characters, preferring sentence ends, then word gaps.
static func split_pages(t: String) -> Array:
	var out: Array = []
	var rest := t.strip_edges()
	while rest.length() > PAGE_MAX:
		var cut := -1
		for i in range(PAGE_MAX, int(PAGE_MAX * 0.45), -1):
			var ch := rest[i - 1]
			if (ch == "." or ch == "?" or ch == "!" or ch == ";") and (i >= rest.length() or rest[i] == " " or rest[i] == "\""):
				cut = i if i >= rest.length() or rest[i] != "\"" else i + 1
				break
		if cut == -1:
			cut = rest.rfind(" ", PAGE_MAX)
			if cut <= 0: cut = PAGE_MAX
		out.append(rest.substr(0, cut).strip_edges())
		rest = rest.substr(cut).strip_edges()
	if rest != "": out.append(rest)
	return out

func _finish() -> void:
	_open = false
	_typing = false
	var cb := _on_done
	_on_done = Callable()
	if _tw and _tw.is_valid(): _tw.kill()
	_tw = create_tween()
	_tw.tween_property(_root, "modulate:a", 0.0, 0.12)
	_tw.tween_callback(func(): if not _open: _root.visible = false)
	# give control back on the next frame, so the same tap does not re-trigger the player
	call_deferred("_release", false)
	finished.emit()
	if cb.is_valid(): cb.call()

func _advance() -> void:
	if not _open: return
	var now := Time.get_ticks_msec()
	if now - _opened_ms < 250 or now - _last_tap_ms < 120: return
	_last_tap_ms = now
	if _typing:
		_typing = false
		_text.visible_characters = -1
	else:
		_next()

func _on_gui_input(e: InputEvent) -> void:
	if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) \
			or (e is InputEventScreenTouch and e.pressed):
		_advance()
		_catcher.accept_event()

func _on_action() -> void:
	if _open: _advance()

func _unhandled_input(e: InputEvent) -> void:
	if _open and e.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _process(dt: float) -> void:
	if not _open: return
	_t += dt
	if _typing:
		var n := _text.get_total_character_count()
		_chars += dt * CPS
		_text.visible_characters = int(_chars)
		if int(_chars) >= n:
			_typing = false
			_text.visible_characters = -1
	var r := _panel.get_global_rect()
	_arrow.visible = not _typing
	_arrow.position = Vector2(r.end.x - 38, r.end.y - 28 + sin(_t * 6.0) * 3.0)

# ---------------------------------------------------------------- modal hold / release
func _player() -> Node:
	var p = main.get("player") if main and is_instance_valid(main) else null
	return p if p and is_instance_valid(p) else null

func _hud() -> Node:
	var h = main.get("hud") if main and is_instance_valid(main) else null
	return h if h and is_instance_valid(h) else null

func _hold() -> void:
	var p := _player()
	if p and p.has_method("set_busy") and not bool(p.get("busy")):
		p.set_busy(true); _held_busy = true
	_was_paused = GameState.paused
	if not _was_paused:
		GameState.set_paused(true); _held_pause = true
	var h := _hud()
	if h and h.has_method("set_controls_visible"):
		h.set_controls_visible(false); _hid_controls = true

func _release(_immediate: bool) -> void:
	if _open: return   # a new dialogue opened in between: keep holding
	var p := _player()
	if _held_busy and p and p.has_method("set_busy"): p.set_busy(false)
	_held_busy = false
	if _held_pause: GameState.set_paused(false)
	_held_pause = false
	var h := _hud()
	if _hid_controls and h and h.has_method("set_controls_visible"): h.set_controls_visible(true)
	_hid_controls = false
