extends Node
## Town system: Pip's General Store (counter) and the Request Board.
##   - The "Shop" interactable sits on the counter. Pip's body comes from the People system (a raccoon);
##     only when that system is missing do we build a small fallback Pip here (pip_node, test: `pip=1`).
##   - "Ring the bell" at night (the shop works at any hour, GDD 5.4). is_open() tells People when Pip is at the counter.
##   - Request board interactable at spot("board"). Requests live in GameState.requests (see town/requests.gd),
##     3 per day, unfinished ones roll over, finished ones clear each morning, untouched ones are replaced after
##     REQUEST_EXPIRE_DAYS. "auto" size requests are handed over the moment a fish is caught (on_catch).
##   - Panels open through main.hud.open_panel(c) when the HUD exists, otherwise through our own overlay.
##   - Fern's basket (town/basket.gd) stands beside the board; People fills it with her gift perks each morning.
##   - Night market (Data.NIGHT_MARKET_MULT): rare finds sell for more at Pip's 21:00-24:00 once the hill lantern is lit.
## People perks used: shop_discount, gold_bonus, sell_bonus, special_bonus, spark_bonus.
## Self-test: `-- test=town` (shop with a fake bag), `panel=buy`, `panel=board`, `panel=none`, `pip=1`.
##   `-- test=basket fresh=1 shot=/tmp/x.png wait=3`: Fern's basket (restock periods, take, save round trip) + night market prices.

const Dat := preload("res://scripts/systems/town/dat.gd")
const Eco := preload("res://scripts/systems/town/economy.gd")
const Requests := preload("res://scripts/systems/town/requests.gd")
const Stage := preload("res://scripts/systems/town/stage.gd")
const PipScript := preload("res://scripts/systems/town/pip.gd")
const BoardScript := preload("res://scripts/systems/town/board.gd")
const BasketScript := preload("res://scripts/systems/town/basket.gd")
const SpotScript := preload("res://scripts/systems/town/spot.gd")
const ShopPanel := preload("res://scripts/ui/shop_panel.gd")
const BoardPanel := preload("res://scripts/systems/town/board_panel.gd")

var main: Node
var pip_node: Node3D            # only set when we had to build a fallback Pip (the People system hides its own then)
var counter_node: Node3D        # the "Shop" interactable
var board_node: Node3D          # the board model
var board_spot: Node3D          # the "Read the board" interactable

var _root: Node3D
var _panel: Control
var _layer: CanvasLayer
var _via_hud := false
var _locked_player: Node
var _paused_by_me := false
var _checks_failed := 0
var _open_t := 0.0
var _seen_open := false
var _seen := {}                 # species id -> {"count", "best", "gold"}: fish_log snapshot for catch detection
var _handover: Array = []       # [{"id": request id, "key": bag key}]
var _flush_armed := false

func setup(m: Node) -> void:
	main = m
	_build_world()
	if not GameState.new_day.is_connected(_on_new_day):
		GameState.new_day.connect(_on_new_day)
	if not GameState.bag_changed.is_connected(_update_marker):
		GameState.bag_changed.connect(_update_marker)
	if not GameState.catalog_changed.is_connected(_scan_catches):
		GameState.catalog_changed.connect(_scan_catches)
	set_process(false)
	_boot.call_deferred()

# ------------------------------------------------------------------ world
func _plaza_dir(from: Vector3) -> Vector3:
	var d := Stage.spot(main, "plaza") - from
	d.y = 0.0
	return d if d.length() > 0.5 else Vector3(0, 0, 1)

func _player_pos() -> Vector3:
	var p := Stage.player(main)
	if p is Node3D and (p as Node3D).is_inside_tree():
		return (p as Node3D).global_position
	return Vector3.INF

func _place(p: Vector3) -> Vector3:
	p.y = Stage.ground_y(main, p.x, p.z) if Stage.island(main) != null else p.y
	return p

func _build_world() -> void:
	_root = Node3D.new()
	_root.name = "TownRoot"
	if main != null: main.add_child(_root)
	else: add_child(_root)

	var cpos := _place(Stage.spot(main, "shop_counter"))
	var toward := _plaza_dir(cpos).normalized()
	var counter := SpotScript.new()
	counter.name = "ShopCounter"
	counter.position = cpos + toward * 0.9
	counter.interact_radius = 2.5
	counter.interact_priority = 2
	counter.prompt_fn = func(_p: Variant) -> String:
		if panel_open(): return ""
		return "Shop" if is_open() else "Ring the bell"
	counter.act_fn = func(_p: Variant) -> void: open_shop()
	_root.add_child(counter)
	counter_node = counter

	var bpos := _place(Stage.spot(main, "board"))
	var bdir := _plaza_dir(bpos).normalized()
	var board := BoardScript.new()
	board.name = "RequestBoard"
	board.position = bpos
	board.rest_yaw = atan2(bdir.x, bdir.z)
	_root.add_child(board)
	board_node = board

	var bs := SpotScript.new()
	bs.name = "BoardSpot"
	bs.position = bpos + bdir * 0.9
	bs.interact_radius = 2.4
	bs.interact_priority = 1
	bs.prompt_fn = func(_p: Variant) -> String: return "" if panel_open() else "Read the board"
	bs.act_fn = func(_p: Variant) -> void: open_board()
	_root.add_child(bs)
	board_spot = bs

	var east := Vector3.UP.cross(bdir).normalized()   # to the right of the board as you face it (the shop is on the other side)
	var basket := BasketScript.new()
	basket.name = "FernBasket"
	basket.position = _place(bpos + bdir * 0.2 + east * 1.7)
	_root.add_child(basket)

## Pip's body normally comes from the People system. Without it (or with pip=1 in a test) we build a small one.
func _maybe_build_pip() -> void:
	var forced := str(Stage.args().get("pip", "")) == "1"
	var pe := Stage.system(main, "people")
	var has_pip := false
	if pe != null and not forced:
		if pe.has_method("body"):
			var b: Variant = pe.body("pip")
			has_pip = b is Node3D and is_instance_valid(b)
		elif "nodes" in pe:
			var nd: Variant = pe.get("nodes")
			has_pip = nd is Dictionary and nd.has("pip")
	if has_pip: return
	var cpos := _place(Stage.spot(main, "shop_counter"))
	var toward := _plaza_dir(cpos).normalized()
	var pip := PipScript.new()
	pip.name = "Pip"
	pip.position = cpos
	pip.rest_yaw = atan2(toward.x, toward.z)
	pip.look_target = _player_pos
	_root.add_child(pip)
	pip_node = pip

func _boot() -> void:
	# Runs one frame after setup, i.e. after main may have applied `fresh=1`.
	_maybe_build_pip()
	_refresh_mods()
	Requests.ensure_today()
	_snapshot_catches()
	_update_marker()
	var a := Stage.args()
	if str(a.get("test", "")) in ["town", "shop", "board"]:
		_run_test(a)
	elif str(a.get("test", "")) == "basket":
		_run_basket_test(a)

## True while Pip stands at the counter (06:00-21:00). At night the shop still works: you ring the bell.
func is_open() -> bool:
	return GameState.time_slot() != "night"

func _on_new_day(_d: int) -> void:
	_refresh_mods()
	var msg := Requests.roll_day()
	_update_marker()
	if msg != "": GameState.say(msg)

func _update_marker() -> void:
	if board_node == null or not is_instance_valid(board_node): return
	var unseen := int(GameState.flags.get("board_seen", 0)) != GameState.day and Requests.open_count() > 0
	board_node.set_marker(unseen or Requests.completable_count() > 0)

func _refresh_mods() -> void:
	Eco.set_mods(Stage.perk(main, "shop_discount", 0.0), Stage.perk(main, "gold_bonus", 0.0),
		Stage.perk(main, "sell_bonus", 0.0), Stage.perk(main, "special_bonus", 0.0), int(Stage.perk(main, "spark_bonus", 0.0)))

# ------------------------------------------------------------------ catches (auto size requests)
func _snapshot_catches() -> void:
	_seen.clear()
	for k in GameState.fish_log.keys():
		var e: Variant = GameState.fish_log[k]
		if e is Dictionary:
			_seen[str(k)] = {"count": int(e.get("count", 0)), "best": float(e.get("best_cm", 0.0)), "gold": int(e.get("gold", 0))}

## Watches fish_log for new catches. The size comes from the fishing system's current roll when available,
## else from a new personal best (the only case where the log reveals it).
func _scan_catches() -> void:
	for k in GameState.fish_log.keys():
		var e: Variant = GameState.fish_log[k]
		if not (e is Dictionary): continue
		var id := str(k)
		var prev: Dictionary = _seen.get(id, {"count": 0, "best": 0.0, "gold": 0})
		var cnt := int(e.get("count", 0))
		if cnt <= int(prev.count):
			continue
		var best := float(e.get("best_cm", 0.0))
		var gold := int(e.get("gold", 0)) > int(prev.gold)
		_seen[id] = {"count": cnt, "best": best, "gold": int(e.get("gold", 0))}
		var cm := 0.0
		var fs := Stage.system(main, "fishing")
		if fs != null:
			var f: Variant = fs.get("_fish")
			if f is Dictionary and str(f.get("id", "")) == id: cm = float(f.get("cm", 0.0))
		if cm <= 0.0 and (int(prev.count) == 0 or best > float(prev.best) + 0.001):
			cm = best
		on_catch(id, cm, gold)

## A fish was just caught. A matching auto size request takes it (once the catch card is closed).
## Returns true when a request will take it. Can also be called directly by the fishing system.
func on_catch(fish_id: String, cm: float, gold := false, junk := false) -> bool:
	if junk or gold or cm <= 0.0: return false
	if bool(Dat.entry("FISH", fish_id).get("junk", false)): return false
	for r in GameState.requests:
		if not (r is Dictionary): continue
		if bool(r.get("done", false)) or str(r.get("kind", "")) != "fish_size" or not bool(r.get("auto", false)): continue
		if cm < float(r.get("cm", 0)): continue
		var rid := str(r.get("id", ""))
		for h in _handover:
			if str(h.id) == rid: return true
		_handover.append({"id": rid, "key": "fish:" + fish_id})
		_arm_flush()
		return true
	return false

func _arm_flush() -> void:
	if _flush_armed or not is_inside_tree(): return
	_flush_armed = true
	get_tree().create_timer(0.7).timeout.connect(_flush_handover)

func _flush_handover() -> void:
	_flush_armed = false
	if _handover.is_empty(): return
	if GameState.paused or panel_open():      # wait until the catch card (or a panel) is closed
		_arm_flush()
		return
	var todo := _handover.duplicate()
	_handover.clear()
	for h in todo:
		for r in GameState.requests:
			if r is Dictionary and str(r.get("id", "")) == str(h.id):
				var msg := Requests.complete_auto(r, str(h.key))
				if msg != "": GameState.say(msg)
	_update_marker()

# ------------------------------------------------------------------ panels
func panel_open() -> bool:
	return _panel != null and is_instance_valid(_panel) and _panel.is_inside_tree() and _panel.is_visible_in_tree()

func open_shop(tab := "sell") -> void:
	if panel_open(): return
	_refresh_mods()
	if Eco.night_market_open() and int(GameState.flags.get("night_market_day", 0)) != GameState.day:
		GameState.flags["night_market_day"] = GameState.day
		GameState.say("Night market: rare finds pay x%s tonight." % str(snappedf(Eco.night_mult(), 0.01)))
	var p := ShopPanel.new(tab)
	p.night = not is_open()
	p.closed.connect(close_panel)
	_show_panel(p)
	if pip_node != null and pip_node.has_method("perk_up"): pip_node.perk_up()

func open_board() -> void:
	if panel_open(): return
	Requests.ensure_today()
	_refresh_mods()
	GameState.flags["board_seen"] = GameState.day
	var p := BoardPanel.new()
	p.closed.connect(close_panel)
	p.completed.connect(func(_r: Dictionary) -> void: _update_marker())
	_show_panel(p)
	_update_marker()

func _show_panel(c: Control) -> void:
	_release()
	_panel = c
	_lock_player()
	var hud := Stage.hud(main)
	if hud != null and hud.has_method("open_panel"):
		_via_hud = true
		hud.open_panel(c)
	else:
		_via_hud = false
		_open_overlay(c)
	_open_t = 0.0
	_seen_open = false
	set_process(true)

func _open_overlay(c: Control) -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 40
	_layer.name = "TownOverlay"
	add_child(_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.12, 0.07, 0.04, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(center)
	center.add_child(c)
	if not GameState.paused:
		GameState.set_paused(true)
		_paused_by_me = true

func close_panel() -> void:
	_release()
	GameState.save_soon()

## Idempotent teardown: closes whatever is open, hands control back to the player, unpauses.
func _release() -> void:
	var c := _panel
	_panel = null
	if c != null and is_instance_valid(c):
		if _via_hud:
			var hud := Stage.hud(main)
			if hud != null and hud.has_method("close_panel"): hud.close_panel()
		if is_instance_valid(c): c.queue_free()
	_via_hud = false
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	_layer = null
	if _paused_by_me:
		GameState.set_paused(false)
		_paused_by_me = false
	_unlock_player()
	set_process(false)

func _lock_player() -> void:
	var p := Stage.player(main)
	if p != null and p.has_method("set_busy"):
		p.set_busy(true)
		_locked_player = p

func _unlock_player() -> void:
	if _locked_player != null and is_instance_valid(_locked_player) and _locked_player.has_method("set_busy"):
		_locked_player.set_busy(false)
	_locked_player = null

func _process(dt: float) -> void:
	# If somebody else closed or hid our panel (the HUD backdrop, a scene change), hand everything back.
	if _panel == null: return
	_open_t += dt
	if panel_open():
		_seen_open = true
	elif _seen_open or _open_t > 1.0:
		_release()

func _exit_tree() -> void:
	_release()

# ------------------------------------------------------------------ self-test
func _check(name: String, ok: bool) -> void:
	if not ok: _checks_failed += 1
	print("[town test] %s %s" % ["PASS" if ok else "FAIL", name])

func _run_test(a: Dictionary) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not a.has("fresh"):
		print("[town test] note: pass fresh=1 so the fake bag does not touch your real save")
	var focus := Stage.spot(main, "shop_counter")
	Stage.ensure(main, focus + (Stage.spot(main, "board") - focus) * 0.35, Vector3(0, 5.5, 8.5))
	if str(a.get("pip", "")) == "1" and pip_node == null:
		_maybe_build_pip()
	_refresh_mods()
	await _run_logic_checks()
	# fake state for the screenshot
	GameState.coins = 12450
	GameState.bag = {"fish:mackerel": 3, "fish:sardine": 5, "fish:sea_bream": 1, "fish:crab:gold": 1, "fish:tuna": 1,
		"shore:shell_white": 6, "shore:shell_pink": 2, "shore:glass_blue": 2, "shore:star_stone": 1,
		"shore:driftwood": 3, "shore:shell_pink:gold": 1, "flower:sea_pink": 2, "treat:cream": 1}
	GameState.fish_log = {"mackerel": {"count": 3, "best_cm": 44.0, "gold": 0}, "sardine": {"count": 5, "best_cm": 20.0, "gold": 0},
		"sea_bream": {"count": 1, "best_cm": 38.0, "gold": 0}, "tuna": {"count": 1, "best_cm": 120.0, "gold": 0}, "crab": {"count": 1, "best_cm": 14.0, "gold": 1}}
	GameState.flags.erase("special")
	GameState.requests = []
	GameState.flags.erase("req_day")
	Requests.ensure_today()
	GameState.bag_changed.emit()
	_update_marker()
	match str(a.get("panel", "shop")):
		"board": open_board()
		"buy": open_shop("buy")
		"none": pass
		_: open_shop("sell")
	await get_tree().create_timer(0.4).timeout
	print("[town test] done, failures: %d" % _checks_failed)

func _run_logic_checks() -> void:
	GameState.coins = 20000
	GameState.bag = {"fish:mackerel": 3, "fish:sardine": 5, "fish:crab:gold": 1, "shore:shell_white": 4, "shore:shell_pink:gold": 1}
	GameState.fish_log = {"mackerel": {"count": 3, "best_cm": 44.0, "gold": 0}, "sardine": {"count": 5, "best_cm": 20.0, "gold": 0}}
	GameState.cosmetics = {}
	GameState.rod_level = 1
	GameState.lanterns = {}
	GameState.flags.erase("special")
	Eco.set_mods(0.0, 0.0)
	# special
	var sp := Eco.special_id()
	_check("a daily special is picked among caught species", sp in ["mackerel", "sardine"])
	_check("the special is stable for the day", Eco.special_id() == sp)
	var base := int(Dat.entry("FISH", sp).get("price", 0))
	_check("special pays the special multiplier", Eco.unit_price("fish:" + sp) == int(round(base * Eco.special_mult())))
	# sell
	var other := "sardine" if sp == "mackerel" else "mackerel"
	var c0 := GameState.coins
	var got := Eco.sell("fish:" + other, 1)
	_check("sell one fish pays its unit price", got == int(Dat.entry("FISH", other).get("price", 0)) and GameState.coins == c0 + got)
	_check("selling more than you carry sells what you have", Eco.sell("shore:shell_white", 99) == 4 * Eco.unit_price("shore:shell_white") and not GameState.bag.has("shore:shell_white"))
	_check("gold fish sell at the gold multiplier", Eco.unit_price("fish:crab:gold") == int(Dat.entry("FISH", "crab").get("price", 0)) * Eco.gold_mult())
	_check("gold shore items sell at the gold shell price", Eco.unit_price("shore:shell_pink:gold") == Dat.i("GOLD_SHELL_PRICE", 1200))
	_check("old _gold keys still read as gold", Eco.is_gold("shore:shell_pink_gold") and Eco.unit_price("shore:shell_pink_gold") == Eco.unit_price("shore:shell_pink:gold"))
	_check("selling what you do not have pays nothing", Eco.sell("fish:tuna", 1) == 0)
	Eco.set_mods(0.0, 0.5, 0.1)
	_check("perks: gold bonus and sell bonus raise prices", Eco.unit_price("shore:shell_pink:gold") == int(round(Dat.i("GOLD_SHELL_PRICE", 1200) * 1.5 * 1.1)))
	Eco.set_mods(0.0, 0.0)
	# buy
	var ids := Eco.shop_ids()
	_check("shop lists items, never hidden ones", ids.size() > 0 and not ("cos:scarf_oat" in ids))
	_check("lantern-gated items stay unlisted until the lantern is lit", not ("rod:3" in ids))
	var r := Eco.buy("treat:tuna_bites")
	_check("buy a treat", bool(r.ok) and int(GameState.bag.get("treat:tuna_bites", 0)) == 1)
	r = Eco.buy("rod:3")
	_check("rod 3 cannot be bought before its lantern", not bool(r.ok) and GameState.rod_level == 1)
	GameState.lanterns["lighthouse"] = true
	r = Eco.buy("rod:3")
	_check("rod 3 needs rod 2 first", not bool(r.ok) and GameState.rod_level == 1)
	r = Eco.buy("rod:2")
	_check("buy rod 2", bool(r.ok) and GameState.rod_level == 2)
	r = Eco.buy("rod:2")
	_check("cannot buy rod 2 twice", not bool(r.ok))
	GameState.coins = 10
	r = Eco.buy("rod:3")
	_check("too poor to buy", not bool(r.ok) and GameState.rod_level == 2)
	GameState.coins = 20000
	Eco.set_mods(0.1, 0.0)
	_check("shop discount lowers buy prices", Eco.buy_price("cos:scarf_mint") == int(round(1500 * 0.9)))
	Eco.set_mods(0.0, 0.0)
	r = Eco.buy("cos:scarf_mint")
	_check("buy a cosmetic and wear it", bool(r.ok) and GameState.cosmetics.has("cos:scarf_mint") and Eco.is_equipped("cos:scarf_mint"))
	Eco.equip("cos:scarf_mint", false)
	_check("take a cosmetic off", not Eco.is_equipped("cos:scarf_mint"))
	GameState.lanterns = {}
	# requests: generate, fail, succeed
	GameState.flags.erase("req_day")
	GameState.requests = []
	GameState.day = 1
	Requests.ensure_today()
	_check("board has REQUESTS_PER_DAY requests", GameState.requests.size() == Requests.per_day())
	var kinds_ok := true
	for q in GameState.requests:
		if str(q.get("text", "")).contains("%") or int(q.get("reward", 0)) <= 0 or str(q.get("who_name", "")) == "": kinds_ok = false
	_check("requests have text, a giver and a reward", kinds_ok)
	for q in GameState.requests:
		var req: Dictionary = q
		var before := GameState.coins
		var sp0 := GameState.sparks
		var pts0 := int(GameState.person_state(str(req.who)).get("points", 0)) if GameState.has_method("person_state") else 0
		GameState.bag = {}
		_check("'%s' is not complete with an empty bag" % str(req.get("text", "")), Requests.complete(req) == "" and GameState.coins == before)
		if bool(req.auto):
			var rid := str(req.id)
			var seen_toast := false
			_check("auto size request ignores a too small fish", not on_catch("sardine", float(req.cm) - 1.0))
			GameState.bag = {"fish:sardine": 1}
			_check("auto size request takes a big enough catch", on_catch("sardine", float(req.cm) + 3.0))
			await get_tree().create_timer(1.0).timeout
			_check("auto size request paid out and the fish was taken", bool(req.done) and GameState.coins == before + int(req.reward) and not GameState.bag.has("fish:sardine"))
			_check("auto size request gave a spark", GameState.sparks >= sp0 + int(req.sparks))
			continue
		_give_for(req)
		var pr := Requests.progress(req)
		_check("request becomes ready once the bag satisfies it (%s)" % str(req.kind), bool(pr.ok))
		var msg := Requests.complete(req)
		_check("request completes: yen + sparks", msg != "" and GameState.coins == before + int(req.reward) and GameState.sparks == sp0 + int(req.sparks) + Eco.request_sparks and bool(req.done))
		_check("request gave friendship", int(GameState.person_state(str(req.who)).get("points", 0)) >= pts0)
		_check("completing twice does nothing", Requests.complete(req) == "")
	# rollover and expiry
	GameState.requests[0]["done"] = true
	GameState.requests[1]["done"] = false
	var kept_text := str(GameState.requests[1].text)
	GameState.day += 1
	Requests.roll_day()
	var still := false
	for q in GameState.requests:
		if str(q.get("text", "")) == kept_text: still = true
	_check("unfinished requests roll over, finished ones clear", still and GameState.requests.size() == Requests.per_day())
	GameState.day += Requests.expire_days()
	var msg2 := Requests.roll_day()
	var kept_after := false
	for q in GameState.requests:
		if str(q.get("text", "")) == kept_text: kept_after = true
	_check("an untouched request is replaced after the expiry days", not kept_after and msg2.contains("found one elsewhere"))
	GameState.day = 1
	GameState.requests = []
	GameState.flags.erase("req_day")
	GameState.flags.erase("special")
	GameState.bag = {}
	GameState.coins = 500
	GameState.sparks = 0
	GameState.rod_level = 1
	GameState.cosmetics = {}
	GameState.lanterns = {}

func _run_basket_test(a: Dictionary) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not a.has("fresh"): print("[town test] note: pass fresh=1 so the test does not touch your real save")
	GameState._save_timer = -1.0e9          # never write the fake state to the save file
	var pe := Stage.system(main, "people")
	_check("the People system is there", pe != null and pe.has_method("_morning"))
	if pe == null: return
	GameState.bag = {}
	GameState.flags.erase("basket")
	GameState.day = 10
	var fern := GameState.person_state("fern")
	fern["perks"] = []
	fern["points"] = 0
	var bk: Node3D = null
	for c in _root.get_children():
		if c.name == "FernBasket": bk = c
	_check("the basket stands next to the board", bk != null and bk.global_position.distance_to(Stage.spot(main, "board")) < 3.5)
	pe.set("_tick", 0.0)
	GameState.flags.erase("people_morning_day"); pe._morning(false)
	_check("no gift perk, nothing in the basket", BasketScript.items().is_empty() and not BasketScript.unlocked())
	# Fern level 10 with all three gift perks
	fern["points"] = 1300
	fern["perks"] = ["daily_flower", "catnip_gift", "moonflower"]
	GameState.flags.erase("people_morning_day"); pe._morning(false)
	_check("first morning stocks a flower, catnip and a moonflower", BasketScript.items() == ["flower:sea_pink", "treat:catnip", "flower:moonflower"])
	GameState.flags.erase("people_morning_day"); pe._morning(false)
	_check("the same day never restocks twice", BasketScript.items().size() == 3 and not GameState.has_item("flower:sea_pink"))
	await get_tree().create_timer(0.7).timeout
	_check("interactable prompt lists the basket", bk != null and bk.get_prompt(null) == "Take from basket" and bk.is_in_group("interactable"))
	# the saved state survives JSON (numbers come back as floats)
	var back: Variant = JSON.parse_string(JSON.stringify(GameState.flags))
	GameState.flags = GameState._ints(back)
	GameState.flags.erase("people_morning_day"); pe._morning(false)
	_check("after a save round trip the stock is intact and not doubled", BasketScript.items().size() == 3 and not BasketScript.put_if_due("daily_flower", 1))
	bk.interact(null)
	_check("taking moves everything into the bag", GameState.has_item("flower:sea_pink") and GameState.has_item("treat:catnip") and GameState.has_item("flower:moonflower") and BasketScript.items().is_empty())
	_check("an empty basket offers nothing", bk.get_prompt(null) == "")
	var got: Array = []
	for d in range(11, 19):
		GameState.day = d
		GameState.flags.erase("people_morning_day"); pe._morning(false)
		got.append(BasketScript.items().duplicate())
		BasketScript.take_all()
	var flowers := 0
	var catnip := 0
	var moons := 0
	for g in got:
		if "flower:sea_pink" in g: flowers += 1
		if "treat:catnip" in g: catnip += 1
		if "flower:moonflower" in g: moons += 1
	_check("days 11-18: a flower daily (%d), catnip every 3 days (%d), a moonflower every 7 (%d)" % [flowers, catnip, moons], flowers == 8 and catnip == 2 and moons == 1)
	GameState.day = 20
	GameState.flags.erase("people_morning_day"); pe._morning(false)
	var tm := GameState.minute
	GameState.lanterns = {}
	GameState.minute = 22.0 * 60.0
	var plain := Eco.unit_price("fish:tuna")
	GameState.lanterns = {"harbour": true, "hill": true}
	var night := Eco.unit_price("fish:tuna")
	GameState.minute = 12.0 * 60.0
	var day_price := Eco.unit_price("fish:tuna")
	_check("night market: x%s at 22:00 with the hill lantern for rare fish only (%d vs %d)" % [str(Eco.night_mult()), night, day_price],
		night == int(round(day_price * Eco.night_mult())) and plain == day_price and Eco.unit_price("fish:sardine") == int(Dat.entry("FISH", "sardine").get("price", 0)))
	GameState.minute = 22.0 * 60.0
	_check("night market: sardines pay the normal price", Eco.unit_price("fish:sardine") == int(Dat.entry("FISH", "sardine").get("price", 0)))
	GameState.minute = tm
	GameState.lanterns = {}
	# screenshot: a stocked basket by the board
	GameState.day = 30
	GameState.flags.erase("basket")
	GameState.flags.erase("people_morning_day"); pe._morning(false)
	await get_tree().create_timer(0.7).timeout
	if bk != null:
		var cam := Camera3D.new()
		cam.fov = 40
		main.add_child(cam)
		var at := bk.global_position
		cam.look_at_from_position(at + Vector3(2.0, 4.5, 6.5), at + Vector3(-0.5, 0.5, 0.0))
		cam.current = true
	print("[town test] done, failures: %d" % _checks_failed)

func _give_for(req: Dictionary) -> void:
	match str(req.get("kind", "")):
		"fish_size":
			GameState.bag["fish:tuna"] = 1
			GameState.fish_log["tuna"] = {"count": 1, "best_cm": 300.0, "gold": 0}
		"fish": GameState.bag["fish:" + str(req.get("item", ""))] = 1
		"shore": GameState.bag["shore:" + str(req.get("item", ""))] = int(req.get("count", 1))
		"gold": GameState.bag["fish:crab:gold"] = 1
