extends Node
## Lanterns system (GDD 5.5): long-term progression.
##   Each lantern in Data.LANTERNS sits at island.lantern_node(id) (fallback: the island spot, then a post we
##   build ourselves). Once GameState.sparks >= cost the player can "Light the lantern (X sparks)":
##   the sparks are spent, GameState.lanterns[id] = true, a warm light comes on with a short celebration
##   (sparkles, rings, light swell), a toast names what it unlocks, and island.refresh_unlocks() is called.
##   Lit lanterns stay lit after a reload (state lives in GameState.lanterns, saved automatically).
## Self-test: `-- test=lantern` (lights the first lantern; screenshot shows the glow).

const Dat := preload("res://scripts/systems/town/dat.gd")
const Stage := preload("res://scripts/systems/town/stage.gd")
const LanternSpot := preload("res://scripts/systems/town/lantern_spot.gd")
const Kit := preload("res://scripts/systems/town/kit.gd")

var main: Node
var _root: Node3D
var _spots := {}                 # lantern id -> LanternSpot
var _locked_player: Node
var _card_layer: CanvasLayer
var _checks_failed := 0

func setup(m: Node) -> void:
	main = m
	_root = Node3D.new()
	_root.name = "LanternsRoot"
	if main != null: main.add_child(_root)
	else: add_child(_root)
	_boot.call_deferred()

func _boot() -> void:
	# after main may have applied `fresh=1`
	_build_all()
	if str(Stage.args().get("test", "")) == "lantern":
		_run_test(Stage.args())

func _exit_tree() -> void:
	_unlock_player()
	if _card_layer != null and is_instance_valid(_card_layer): _card_layer.queue_free()

func _build_all() -> void:
	for id in Dat.d("LANTERNS").keys():
		_make(str(id))

func _make(id: String) -> void:
	if _spots.has(id) and is_instance_valid(_spots[id]): return
	var info := Dat.entry("LANTERNS", id)
	var host: Node3D = null
	var isl := Stage.island(main)
	if isl != null and isl.has_method("lantern_node"):
		var n: Variant = isl.lantern_node(id)
		if n is Node3D and is_instance_valid(n): host = n
	var pos := Vector3.ZERO
	if host != null and host.is_inside_tree():
		pos = host.global_position
		pos.y = Stage.ground_y(main, pos.x, pos.z) if isl != null and isl.has_method("ground_y") else pos.y
	else:
		host = null
		pos = Stage.spot(main, str(info.get("spot", "lantern_" + id)))
	if host == null and pos == Vector3.ZERO:
		push_warning("lanterns: no place for lantern '%s'" % id)
		return
	var own_post := host == null
	if own_post:
		host = Node3D.new()
		host.name = "Lantern_" + id
		host.position = pos
		_root.add_child(host)
	var spot := LanternSpot.new()
	spot.name = "LanternSpot_" + id
	spot.lantern_id = id
	spot.cost = maxi(0, int(info.get("cost", 10)))
	spot.lname = str(info.get("name", id.capitalize() + " Lantern"))
	spot.unlocks = str(info.get("unlocks", ""))
	spot.after = str(info.get("after", ""))
	spot.after_name = str(Dat.entry("LANTERNS", spot.after).get("name", spot.after.capitalize())).trim_suffix(" Lantern").to_lower() + " lantern" if spot.after != "" else ""
	spot.system = self
	spot.main = main
	spot.position = pos
	_root.add_child(spot)
	spot.attach(host, own_post)
	spot.set_lit(GameState.lanterns.has(id), false)
	_spots[id] = spot

func is_lit(id: String) -> bool:
	return GameState.lanterns.has(id)

## Spend the sparks and light a lantern. Called by the lantern's interactable.
func light(spot: Node) -> void:
	var id: String = spot.lantern_id
	if GameState.lanterns.has(id) or spot.lit: return
	if GameState.sparks < spot.cost: return
	if spot.after != "" and not GameState.lanterns.has(spot.after): return
	GameState.add_sparks(-spot.cost, "")
	GameState.lanterns[id] = true
	spot.set_lit(true, true)
	_hold_player(spot)
	var isl := Stage.island(main)
	if isl != null and isl.has_method("refresh_unlocks"):
		isl.refresh_unlocks()
	var title: String = "%s is lit" % spot.lname
	var txt: String = spot.unlocks
	get_tree().create_timer(1.5).timeout.connect(func() -> void: _show_card(title, txt))
	GameState.catalog_changed.emit()
	GameState.save_soon()

## "X is lit" card with what it unlocks. Waits for a tap (no toast: the text is too long to read in passing).
func _show_card(title: String, text: String) -> void:
	if not is_inside_tree(): return
	if _card_layer != null and is_instance_valid(_card_layer): _card_layer.queue_free()
	var layer := CanvasLayer.new()
	layer.layer = 30
	layer.name = "LanternCard"
	add_child(layer)
	_card_layer = layer
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(holder)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_TOP_WIDE)
	center.offset_top = 120.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(456, 0)
	card.add_theme_stylebox_override("panel", Kit.box(Color("fff4d8"), 22, 3, 18))
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)
	col.add_child(Kit.label(title, 26, Kit.INK, false, true))
	if text != "":
		var body := Kit.label(text, 22, Kit.INK, true)
		body.custom_minimum_size.x = 400
		col.add_child(body)
	var ok := Kit.button("Lovely", Kit.GREEN, 24, 88, 0.0)
	ok.pressed.connect(func() -> void:
		if is_instance_valid(layer): layer.queue_free())
	col.add_child(ok)
	card.pivot_offset = Vector2(228, 90)
	card.scale = Vector2(0.88, 0.88)
	card.modulate.a = 0.0
	var tw := card.create_tween().set_parallel(true)
	tw.tween_property(card, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", 1.0, 0.15)

## Mocha pauses to watch the light come on (always released by the timer or when this node leaves the tree).
func _hold_player(spot: Node3D) -> void:
	var p := Stage.player(main)
	if p == null or not p.has_method("set_busy"): return
	if p.has_method("face"): p.face(spot.global_position)
	p.set_busy(true)
	_locked_player = p
	get_tree().create_timer(1.8).timeout.connect(_unlock_player)

func _unlock_player() -> void:
	if _locked_player != null and is_instance_valid(_locked_player) and _locked_player.has_method("set_busy"):
		_locked_player.set_busy(false)
	_locked_player = null

# ------------------------------------------------------------------ self-test
func _check(name: String, ok: bool) -> void:
	if not ok: _checks_failed += 1
	print("[lantern test] %s %s" % ["PASS" if ok else "FAIL", name])

func _run_test(a: Dictionary) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not a.has("fresh"):
		print("[lantern test] note: pass fresh=1 so the test does not touch your real save")
	var ids: Array = Dat.d("LANTERNS").keys()
	if ids.is_empty() or not _spots.has(str(ids[0])):
		print("[lantern test] FAIL no lantern to test")
		return
	var id := str(ids[0])
	var spot: Node3D = _spots[id]
	Stage.ensure(main, spot.global_position, Vector3(0, 3.8, 7.0))
	var cost: int = spot.cost
	GameState.sparks = maxi(0, cost - 1)
	_check("prompt hidden while you cannot afford it", spot.get_prompt(null) == "")
	GameState.add_sparks(1, "")
	_check("prompt shows the cost once you can", spot.get_prompt(null) == "Light the lantern (%d sparks)" % cost)
	GameState.sparks = cost + 3
	spot.interact(null)
	_check("lighting spends the sparks", GameState.sparks == 3)
	_check("lantern is remembered as lit", GameState.lanterns.has(id) and spot.lit)
	_check("prompt is gone once lit", spot.get_prompt(null) == "")
	spot.interact(null)
	_check("lighting twice does nothing", GameState.sparks == 3)
	# reload: rebuild from state
	for k in _spots.keys():
		var s: Node = _spots[k]
		if is_instance_valid(s): s.queue_free()
	_spots.clear()
	await get_tree().process_frame
	_build_all()
	_check("lit lanterns stay lit after a reload", _spots.has(id) and _spots[id].lit)
	if ids.size() > 1 and _spots.has(str(ids[1])):
		_check("other lanterns stay dark", not _spots[str(ids[1])].lit)
	# hold the camera on the glow for the screenshot (a fresh celebration)
	GameState.lanterns.erase(id)
	GameState.sparks = cost
	_spots[id].set_lit(false, false)
	await get_tree().create_timer(0.3).timeout
	_spots[id].interact(null)
	print("[lantern test] done, failures: %d" % _checks_failed)
