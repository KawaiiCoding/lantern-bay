extends Node
## Goals: light-touch onboarding. One short line under the top bar says what to try next
## (Data.STARTER_GOALS, any order counts). For the first few goals a soft marker floats over
## the place to go, and disappears once Mocha is close. After the starter list it only shows
## the next lantern's spark progress. Tap the line to fold it away (remembered).

## Only the very first steps ever get a marker, and only after the player seems stuck for a while.
const MARKER_GOALS := ["catch_fish", "talk_pip", "sell"]
const STUCK_SECONDS := 40.0
const TARGET := {
	"catch_fish": "pier_end", "talk_pip": "shop_counter", "sell": "shop_counter",
	"request": "board", "lantern_harbour": "lantern_harbour",
}

var main: Node
var _layer: CanvasLayer
var _chip: PanelContainer
var _label: Label
var _marker: Node3D
var _current := ""
var _poll := 0.0
var _text := ""
var _stuck := 0.0
var _revealed := {}

func setup(m: Node) -> void:
	main = m
	_layer = CanvasLayer.new(); _layer.layer = 9; add_child(_layer)
	_chip = PanelContainer.new()
	# looks like a small paper task tag (mustard, dashed feel), never like a speech bubble or toast
	var sb := Style.panel_box(Color("f7e2a6"), 10, 2, 10, false)
	sb.border_color = Style.GOLD_DARK
	_chip.add_theme_stylebox_override("panel", sb)
	_chip.position = Vector2(14, 160)
	_chip.mouse_filter = Control.MOUSE_FILTER_STOP
	_chip.gui_input.connect(_on_chip_input)
	_layer.add_child(_chip)
	var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip.add_child(hb)
	var tag := Style.label("GOAL", 13, Color("fffaf2"), true)
	var tsb := StyleBoxFlat.new(); tsb.bg_color = Style.GOLD_DARK; tsb.set_corner_radius_all(6)
	tsb.content_margin_left = 6; tsb.content_margin_right = 6; tsb.content_margin_top = 1; tsb.content_margin_bottom = 1
	tag.add_theme_stylebox_override("normal", tsb)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(tag)
	_label = Style.label("", 17, Style.INK, false)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	hb.add_child(_label)
	_marker = _make_marker()
	_marker.visible = false
	main.add_child(_marker)
	_refresh(true)

func _make_marker() -> Node3D:
	var g := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Style.GOLD; mat.emission_enabled = true; mat.emission = Style.GOLD; mat.emission_energy_multiplier = 0.8
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var d := MeshInstance3D.new()
	var p := PrismMesh.new(); p.size = Vector3(0.45, 0.5, 0.18)
	d.mesh = p; d.material_override = mat; d.rotation_degrees = Vector3(180, 0, 0)
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(d)
	var ring := MeshInstance3D.new()
	var t := TorusMesh.new(); t.inner_radius = 0.55; t.outer_radius = 0.68
	var rm := mat.duplicate(); rm.albedo_color = Color(Style.GOLD, 0.5); rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.mesh = t; ring.material_override = rm; ring.position = Vector3(0, -2.35, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(ring)
	return g

func _done(id: String) -> bool:
	match id:
		"catch_fish": return not GameState.fish_log.is_empty()
		"talk_pip":
			var st: Dictionary = GameState.people.get("pip", {})
			return int(st.get("last_talk_day", 0)) > 0 or int(st.get("points", 0)) > 0
		"pet_cat":
			for c in GameState.cats.values():
				if typeof(c) == TYPE_DICTIONARY and int(c.get("hearts", 0)) > 0: return true
			return false
		"sell": return bool(GameState.flags.get("sold_any", false))
		"request": return int(GameState.flags.get("requests_done", 0)) > 0
		"lantern_harbour": return GameState.lanterns.has("harbour")
	return bool(GameState.flags.get("goal_" + id, false))

func _next_goal() -> Dictionary:
	var list = Data.get("STARTER_GOALS")
	if typeof(list) != TYPE_ARRAY: return {}
	for g in list:
		if typeof(g) == TYPE_DICTIONARY and not _done(String(g.get("id", ""))): return g
	return {}

func _lantern_line() -> String:
	var best := ""; var best_cost := 1 << 30
	var lanterns = Data.get("LANTERNS")
	if typeof(lanterns) != TYPE_DICTIONARY: return ""
	for id in lanterns:
		if GameState.lanterns.has(id): continue
		var l: Dictionary = lanterns[id]
		var cost := int(l.get("cost", 0))
		if cost < best_cost:
			best_cost = cost; best = String(l.get("name", id))
	if best == "": return ""
	return "%s: %d / %d sparks" % [best, mini(GameState.sparks, best_cost), best_cost]

func _refresh(force := false) -> void:
	var g := _next_goal()
	var id := String(g.get("id", ""))
	var text := String(g.get("text", "")) if id != "" else _lantern_line()
	if id != _current and _current != "" and not force:
		Style.pop(_chip, 1.08)   # a little bounce when a goal is ticked off
	if id != _current: _stuck = 0.0
	_current = id
	if text != _text:
		_text = text
		_label.text = text
		_chip.reset_size()

func _process(dt: float) -> void:
	if not is_instance_valid(_chip): return
	_poll -= dt
	if _poll <= 0.0:
		_poll = 0.5
		_refresh()
	var folded := bool(GameState.flags.get("goal_chip_folded", false))
	var hud_ok := true
	if is_instance_valid(main) and is_instance_valid(main.hud) and main.hud.has_method("controls_visible"):
		hud_ok = main.hud.controls_visible()
	_chip.visible = _text != "" and not GameState.paused and hud_ok
	_chip.modulate.a = 0.55 if folded else 1.0
	if folded and _label.text != "...": _label.text = "..."
	elif not folded and _label.text != _text: _label.text = _text
	_apply_unlocks()
	# floating marker: first steps only, and only once the player has wandered for a while without doing it
	if not GameState.paused: _stuck += dt
	var show := false
	if _current in MARKER_GOALS and _stuck > STUCK_SECONDS and not folded and is_instance_valid(main) and is_instance_valid(main.player):
		var p: Vector3 = main.spot(TARGET.get(_current, ""))
		if p != Vector3.ZERO:
			var d: float = (main.player.global_position - p).length()
			show = d > 4.0
			var t := Time.get_ticks_msec() / 1000.0
			_marker.global_position = p + Vector3(0, 2.6 + sin(t * 2.4) * 0.12, 0)
			_marker.rotation.y = t * 1.2
	_marker.visible = show and not GameState.paused

# ---------------- things appear bit by bit ----------------
## Notebook button: after the first catch / cat heart / chat (or from day 2).
## Sparks counter: from the first spark. Moped: Pip lends it on day 2.
func _apply_unlocks() -> void:
	if not is_instance_valid(main) or not is_instance_valid(main.hud): return
	var hud: Node = main.hud
	var any_fact := false
	for c in GameState.cats.values():
		if typeof(c) == TYPE_DICTIONARY and not (c.get("facts", []) as Array).is_empty(): any_fact = true; break
	var book_ok := GameState.day >= 2 or any_fact or not GameState.fish_log.is_empty() or _done("pet_cat") or _done("talk_pip")
	var spark_ok := GameState.sparks > 0 or bool(GameState.flags.get("sparks_seen", false))
	if spark_ok: GameState.flags["sparks_seen"] = true
	if GameState.day >= 2 and not bool(GameState.flags.get("moped_unlocked", false)):
		GameState.flags["moped_unlocked"] = true
		GameState.say("Pip lent you an old moped. Tap the moped button to ride.")
		GameState.save_soon()
	var ride_ok := bool(GameState.flags.get("moped_unlocked", false))
	_gate(hud.get("_btn_book"), book_ok, "book")
	_gate(hud.get("_spark_pill"), spark_ok, "spark")
	_gate(hud.get("_btn_ride"), ride_ok, "ride")

func _gate(n, ok: bool, key: String) -> void:
	if not (n is Control) or not is_instance_valid(n): return
	if not ok:
		if n.visible: n.visible = false
		return
	if not _revealed.has(key):
		_revealed[key] = true
		if not n.visible:
			n.visible = true
			Style.pop(n, 1.25)   # appears with a little pop the first time

func _on_chip_input(e: InputEvent) -> void:
	var tap: bool = (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed)
	if tap:
		GameState.flags["goal_chip_folded"] = not bool(GameState.flags.get("goal_chip_folded", false))
		GameState.save_soon()
		_chip.accept_event()
