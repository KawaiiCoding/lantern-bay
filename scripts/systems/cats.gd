extends Node
## Cats system (GDD 5.2): spawns one interactable cat node per cat whose schedule puts it on the island,
## runs the trust rules (pet / sit / treat, hearts 0..5, friend), the secrets and the porch gifts.
##
## Body and behaviours live in scripts/systems/cats/cat_actor.gd, visuals in cat_fx.gd.
## Self-test: `godot --path . -- test=cats shot=/tmp/lb_cats.png wait=3 fresh=1`
##   test=cats_logic runs every rule with asserts and quits; test=cats_scare shows the nervous scamper.
##
## Facts written to GameState.cat_state(id).facts (for the Notebook):
##   "haunt:<slot>" (morning/afternoon/evening/night) or "haunt:rain", "favourite", "favourite_hint", "secret".
## Public API: get_cat(id), is_present(id), present_ids(), hearts(id), is_friend(id), schedule_spot(id, slot, weather),
##   add_hearts(id, n), signals hearts_changed / friend_made / sit_changed.

signal hearts_changed(id: String, hearts: int)
signal friend_made(id: String)
signal sit_changed(active: bool)

const CatActor := preload("res://scripts/systems/cats/cat_actor.gd")
const TEST_PATH := "res://scripts/systems/cats/cats_test.gd"

const PORCH_CHANCE := 0.4          # chance a friend cat visits the porch (and leaves a gift) on a given morning
const PORCH_MAX_PER_DAY := 2
const SIT_INVITE_EVERY := 6.0      # GDD: every 6 s a nearby cat may wander closer while Mocha sits
const SIT_NEAR := 1.7
const INVITE_CHANCE := {"Bold": 0.8, "Curious": 0.7, "Lazy": 0.45, "Shy": 0.3, "Grumpy": 0.25}
const WRONG_HINTS := {
	"treat:cream": "something richer",
	"treat:catnip": "something greener",
	"treat:tuna_bites": "something fishier",
}

var main: Node = null
var actors := {}                   # cat id -> cat actor currently on the island
var sit_active := false
var sit_actor: Node3D = null       # the cat Mocha chose to sit with
var sit_time := 0.0
var sit_reward_time := 4.0         # seconds a cat must stay within reach for the first-sit-of-day heart
var test_mode := false             # tests spawn their own cats and skip the schedule

var _rng := RandomNumberGenerator.new()
var _player: Node3D = null
var _key := ""
var _eval_t := 0.0
var _pending := {}                 # cat id -> seconds until it reacts to a schedule change
var _sit_tick := 0.0
var _claim_frame := -1
var _wday := -1
var _wcache := "sunny"

# ---------------------------------------------------------------- setup
func setup(m) -> void:
	main = m
	_rng.randomize()
	if not GameState.new_day.is_connected(_on_new_day):
		GameState.new_day.connect(_on_new_day)
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=", true, 1)
		if kv.size() == 2: args[kv[0]] = kv[1]
	var test := String(args.get("test", ""))
	if test.begins_with("cats"):
		test_mode = true
		if ResourceLoader.exists(TEST_PATH):
			var scr = load(TEST_PATH)
			if scr != null and scr.can_instantiate():
				var t: Node = scr.new()
				t.name = "CatsTest"
				add_child(t)
				t.run(self, test, args)
		return
	refresh_schedule(true)

func _exit_tree() -> void:
	stop_sit(true)

func _process(dt: float) -> void:
	if not test_mode:
		_eval_t -= dt
		if _eval_t <= 0.0:
			_eval_t = 0.5
			refresh_schedule(false)
		_tick_pending(dt)
	_update_sit(dt)

# ---------------------------------------------------------------- environment helpers (all null-safe)
func get_player() -> Node3D:
	if is_instance_valid(_player): return _player
	_player = null
	if is_instance_valid(main):
		var p = main.get("player")
		if p is Node3D and is_instance_valid(p): _player = p
	return _player

func _island() -> Node:
	if is_instance_valid(main):
		var isl = main.get("island")
		if isl is Node and is_instance_valid(isl): return isl
	return null

func spot_pos(spot_name: String) -> Vector3:
	if is_instance_valid(main) and main.has_method("spot"):
		var v = main.spot(spot_name)
		if v is Vector3: return v
	return Vector3.ZERO

func ground_y(x: float, z: float, fallback := 0.0) -> float:
	var isl := _island()
	if isl != null and isl.has_method("ground_y"):
		var y = isl.ground_y(x, z)
		if y is float or y is int: return float(y)
	return fallback

func is_walkable(p: Vector3) -> bool:
	var isl := _island()
	if isl != null and isl.has_method("is_walkable"):
		return bool(isl.is_walkable(p))
	return true

## True when a straight walk from a to b stays on walkable ground (always true without an island).
func path_clear(a: Vector3, b: Vector3) -> bool:
	var isl := _island()
	if isl == null or not isl.has_method("is_walkable"): return true
	var d := Vector2(b.x - a.x, b.z - a.z).length()
	var steps := maxi(1, int(ceil(d / 0.8)))
	for i in range(1, steps + 1):
		var p := a.lerp(b, float(i) / float(steps))
		p.y = ground_y(p.x, p.z, p.y)
		if not is_walkable(p): return false
	return true

func crowded(p: Vector3, except: Node, radius: float) -> bool:
	for a in actors.values():
		if a == except or not is_instance_valid(a): continue
		if Vector2(a.global_position.x - p.x, a.global_position.z - p.z).length() < radius: return true
	return false

func cur_slot() -> String:
	return GameState.time_slot()

func cur_weather() -> String:
	if _wday != GameState.day:
		_wday = GameState.day
		_wcache = GameState.weather()
	return _wcache

func max_hearts() -> int:
	var v = Data.get("CAT_MAX_HEARTS")
	return clampi(int(v), 1, 10) if v != null else 5

func _save() -> void:
	if GameState.has_method("save_soon"): GameState.call("save_soon")

func _cdata(id: String) -> Dictionary:
	var d = Data.CATS.get(id, {})
	return d if typeof(d) == TYPE_DICTIONARY else {}

func _name(id: String) -> String:
	return String(_cdata(id).get("name", id.capitalize()))

# ---------------------------------------------------------------- state access (sanitised; JSON ints come back as floats)
func st(id: String) -> Dictionary:
	if GameState.cats.has(id) and typeof(GameState.cats[id]) != TYPE_DICTIONARY:
		GameState.cats.erase(id)
	var s: Dictionary = GameState.cat_state(id)
	if typeof(s.get("facts", null)) != TYPE_ARRAY: s["facts"] = []
	for k in ["hearts", "last_pet_day", "last_sit_day", "last_treat_day"]:
		s[k] = int(s.get(k, 0))
	s["friend"] = bool(s.get("friend", false))
	return s

func _peek(id: String) -> Dictionary:
	var s = GameState.cats.get(id, null)
	return s if typeof(s) == TYPE_DICTIONARY else {}

func hearts(id: String) -> int:
	return int(_peek(id).get("hearts", 0))

func is_friend(id: String) -> bool:
	return bool(_peek(id).get("friend", false))

func get_cat(id: String) -> Node3D:
	var a = actors.get(id, null)
	return a if is_instance_valid(a) else null

func is_present(id: String) -> bool:
	return get_cat(id) != null

func present_ids() -> Array:
	var out := []
	for id in actors.keys():
		if is_instance_valid(actors[id]): out.append(id)
	return out

# ---------------------------------------------------------------- hearts, friends, facts
func add_hearts(id: String, n: int, _why := "") -> int:
	var s := st(id)
	var before := int(s["hearts"])
	var after := clampi(before + n, 0, max_hearts())
	s["hearts"] = after
	var a = get_cat(id)
	if a != null: a.show_hearts(before, after, true)
	if after != before: hearts_changed.emit(id, after)
	if after >= max_hearts() and not bool(s["friend"]):
		_befriend(id)
	_save()
	return after - before

func _befriend(id: String) -> void:
	var s := st(id)
	s["friend"] = true
	var sp := int(Data.SPARK.get("cat_friend", 3))
	if sp > 0: GameState.add_sparks(sp, "")
	GameState.say("%s is your friend now. +%d spark%s." % [_name(id), sp, "" if sp == 1 else "s"])
	var a = get_cat(id)
	if a != null:
		a.burst_hearts(10)
		a.joy_hop(3)
	friend_made.emit(id)
	_save()

func learn(id: String, fact: String, announce := false) -> bool:
	var s := st(id)
	if fact in (s["facts"] as Array): return false
	GameState.learn_cat_fact(id, fact)
	if not (fact in (s["facts"] as Array)): (s["facts"] as Array).append(fact)
	var sp := int(Data.SPARK.get("new_cat_fact", 0))
	if sp > 0 and fact != "favourite_hint": GameState.add_sparks(sp, "")
	if announce: GameState.say("%s: a new note in your notebook." % _name(id))
	_save()
	return true

## Called by a cat actor (a few times a second) while Mocha can see it: learns haunt facts and observed secrets.
func cat_seen(a: Node3D) -> void:
	if not is_instance_valid(a) or bool(a.get("gone")) or float(a.get("fade")) < 0.9: return
	var id := String(a.get("cat_id"))
	var c := _cdata(id)
	var spot := String(a.get("haunt"))
	var rain_spot := String(c.get("rain_spot", ""))
	var key := "haunt:" + cur_slot()
	if cur_weather() == "rain" and rain_spot != "" and spot == rain_spot: key = "haunt:rain"
	learn(id, key)
	if _secret_seen(a, id, c, spot):
		learn(id, "secret", true)

## Secrets that are learned by noticing the cat in the right place and time (never explained up front).
func _secret_seen(a: Node3D, id: String, c: Dictionary, spot: String) -> bool:
	var slot := cur_slot()
	var w := cur_weather()
	match id:
		"tofu": return slot == "afternoon" and a.is_napping()
		"disco": return slot == "night"
		"pancake": return spot == "shop" and slot == "morning"
		"mochi": return w == "rain" and spot == String(c.get("rain_spot", ""))
		"pepper": return spot == "pier" and slot == "afternoon"
		"saffron": return w == "sunny" and spot == "porch"
		"ghost": return w == "fog"
		"captain": return slot == "night" and spot == "pier"
	return false

# ---------------------------------------------------------------- items, treats, rules, lines
func item_name(item_id: String) -> String:
	var tail := item_id.substr(item_id.find(":") + 1)
	if item_id.begins_with("fish:"):
		var f = Data.FISH.get(tail, {})
		if typeof(f) == TYPE_DICTIONARY: return String(f.get("name", tail.capitalize()))
	if item_id.begins_with("shore:"):
		var s = Data.SHORE.get(tail, {})
		if typeof(s) == TYPE_DICTIONARY: return String(s.get("name", tail.capitalize()))
	var sh = Data.SHOP.get(item_id, {})
	if typeof(sh) == TYPE_DICTIONARY and sh.has("name"): return String(sh["name"])
	return tail.replace("_", " ").capitalize()

## A shop treat in the bag that is not this cat's favourite and was not tried on it today ("" if none).
func wrong_treat(id: String, fav: String) -> String:
	var today := GameState.day
	if int(_peek(id).get("last_wrong_day", 0)) == today: return ""
	var keys := GameState.bag.keys()
	keys.sort()
	for k in keys:
		var key := String(k)
		if key.begins_with("treat:") and key != fav and GameState.has_item(key): return key
	return ""

func has_treat_rule(id: String) -> bool:
	return id == "marmalade" or String(_cdata(id).get("rule", "")) == "pet_all_others"

## Marmalade: accepts a treat only once every other cat that is around today has been petted today.
func treat_rule_ok(id: String) -> bool:
	if not has_treat_rule(id): return true
	return others_petted_today(id)

func others_petted_today(id: String) -> bool:
	for oid in Data.CATS.keys():
		if oid == id or not _around_today(String(oid)): continue
		if int(_peek(String(oid)).get("last_pet_day", 0)) != GameState.day: return false
	return true

## Could this cat appear on the island at some point today (weather, lantern)?
func _around_today(id: String) -> bool:
	var c := _cdata(id)
	if c.is_empty(): return false
	var wo = c.get("weather_only", [])
	if typeof(wo) == TYPE_ARRAY and not wo.is_empty() and not (cur_weather() in wo): return false
	var nl := String(c.get("needs_lantern", ""))
	if nl != "" and not GameState.lanterns.has(nl): return false
	var h = c.get("haunts", {})
	var has_haunt: bool = typeof(h) == TYPE_DICTIONARY and not (h as Dictionary).is_empty()
	return has_haunt or String(c.get("rain_spot", "")) != ""

func rule_hint(id: String) -> String:
	return "%s checks the treat, then you, then the rest of the island. Not yet." % _name(id)

func treat_line(personality: String, nm: String, item_nm: String) -> String:
	match personality:
		"Lazy": return "%s eats the %s without fully opening both eyes." % [nm, item_nm]
		"Shy": return "%s takes the %s very gently." % [nm, item_nm]
		"Curious": return "%s inspects the %s, then devours it." % [nm, item_nm]
		"Grumpy": return "%s eats the %s. This is not a compliment." % [nm, item_nm]
	return "%s accepts the %s as a tax payment." % [nm, item_nm]

func wrong_line(fav: String, nm: String, item_nm: String) -> String:
	var hint := String(WRONG_HINTS.get(fav, ""))
	if hint == "": hint = "something fresh from the water" if fav.begins_with("fish:") else "something else"
	return "%s sniffs the %s and walks off. It seems to want %s." % [nm, item_nm, hint]

func claim_interact() -> bool:
	var f := Engine.get_process_frames()
	if f == _claim_frame: return false
	_claim_frame = f
	return true

# ---------------------------------------------------------------- sitting (always ends cleanly)
func start_sit(actor: Node3D, player: Node3D) -> void:
	if not is_instance_valid(player): return
	if player.has_method("sit"): player.sit(true)
	if is_instance_valid(actor) and player.has_method("face"): player.face(actor.global_position)
	sit_active = true
	sit_actor = actor if is_instance_valid(actor) else null
	sit_time = 0.0
	_sit_tick = 0.0
	for a in actors.values():
		if is_instance_valid(a):
			a.near_sit_time = 0.0
			a.sit_credited = false
	if sit_actor != null: sit_actor.come_close(player.global_position, 1.15)
	sit_changed.emit(true)

## Ends a sit session. stand = true also asks the player to stand up (no-op if already standing).
func stop_sit(stand := true) -> void:
	var was := sit_active
	sit_active = false
	sit_actor = null
	var p := get_player()
	if stand and p != null and p.has_method("sit") and bool(p.get("sitting")):
		p.sit(false)
	for a in actors.values():
		if is_instance_valid(a):
			a.near_sit_time = 0.0
			a.sit_credited = false
	if was: sit_changed.emit(false)

func _update_sit(dt: float) -> void:
	if not sit_active: return
	var p := get_player()
	if p == null:
		stop_sit(false); return
	var sitting = p.get("sitting")
	if sitting != null and not bool(sitting):
		stop_sit(false); return   # Mocha stood up (move input or another system): nothing else to undo
	if sit_actor != null and (not is_instance_valid(sit_actor) or bool(sit_actor.get("gone"))):
		sit_actor = null
	if GameState.paused: return
	sit_time += dt
	_sit_tick += dt
	if _sit_tick >= SIT_INVITE_EVERY:
		_sit_tick = 0.0
		_invite_cats(p)
	for a in actors.values():
		if not is_instance_valid(a) or not a.available(): continue
		var d := Vector2(a.global_position.x - p.global_position.x, a.global_position.z - p.global_position.z).length()
		if d <= SIT_NEAR: a.near_sit_time += dt
		if a.near_sit_time >= sit_reward_time and not a.sit_credited:
			_sit_credit(a)

func _invite_cats(p: Node3D) -> void:
	for a in actors.values():
		if not is_instance_valid(a) or not a.available(): continue
		var d := Vector2(a.global_position.x - p.global_position.x, a.global_position.z - p.global_position.z).length()
		if d > 8.0 or a.near_sit_time > 0.0: continue
		var chance := float(INVITE_CHANCE.get(a.personality, 0.5))
		if a == sit_actor: chance = 1.0
		if _rng.randf() < chance: a.come_close(p.global_position)

func _sit_credit(a: Node3D) -> void:
	a.sit_credited = true
	var id := String(a.cat_id)
	var s := st(id)
	if int(s["last_sit_day"]) == GameState.day: return
	s["last_sit_day"] = GameState.day
	add_hearts(id, 1, "sit")
	var nm := _name(id)
	if a.shy or String(a.personality) == "Grumpy":
		GameState.say("%s edges closer, and stays." % nm)
	else:
		GameState.say("%s settles in beside you." % nm)

# ---------------------------------------------------------------- schedule
## Spot name this cat should be at (""= not on the island). Uses haunts by slot, rain_spot, weather_only, needs_lantern.
func schedule_spot(id: String, slot := "", weather := "") -> String:
	if slot == "": slot = cur_slot()
	if weather == "": weather = cur_weather()
	var c := _cdata(id)
	if c.is_empty(): return ""
	var wo = c.get("weather_only", [])
	if typeof(wo) == TYPE_ARRAY and not wo.is_empty() and not (weather in wo): return ""
	var nl := String(c.get("needs_lantern", ""))
	if nl != "" and not GameState.lanterns.has(nl): return ""
	var h = c.get("haunts", {})
	var haunts: Dictionary = h if typeof(h) == TYPE_DICTIONARY else {}
	var spot := String(haunts.get(slot, ""))
	var rain_spot := String(c.get("rain_spot", ""))
	if weather == "rain" and rain_spot != "":
		if spot != "" or haunts.is_empty(): spot = rain_spot
	var secret := String(c.get("secret", "")).to_lower()
	if spot == "home" and weather == "sunny" and secret.contains("porch") and secret.contains("sunny"):
		spot = "porch"
	if slot == "morning" and is_friend(id) and id in visiting_friends(weather):
		spot = "porch"
	return spot

func _visit_roll(id: String) -> float:
	return GameState.day_rng(int(absi(id.hash()) % 9973) + 313).randf()

## Up to two friend cats that visit the porch this morning (same roll drives the gift).
func visiting_friends(weather := "") -> Array:
	if weather == "": weather = cur_weather()
	var out := []
	for id in Data.CATS.keys():
		var cid := String(id)
		if not is_friend(cid) or _visit_roll(cid) >= PORCH_CHANCE: continue
		var c := _cdata(cid)
		var wo = c.get("weather_only", [])
		if typeof(wo) == TYPE_ARRAY and not wo.is_empty() and not (weather in wo): continue
		var nl := String(c.get("needs_lantern", ""))
		if nl != "" and not GameState.lanterns.has(nl): continue
		out.append(cid)
	out.sort_custom(func(a, b): return _visit_roll(String(a)) < _visit_roll(String(b)))
	return out.slice(0, PORCH_MAX_PER_DAY)

func home_for(id: String, spot: String) -> Vector3:
	var base := spot_pos(spot)
	var h := absi(id.hash())
	var ang := float(h % 628) / 100.0
	var rad := 1.5 + float((h >> 4) % 14) / 10.0
	for i in 8:
		var a := ang + float(i) * 0.9
		var p := base + Vector3(cos(a), 0, sin(a)) * rad
		p.y = ground_y(p.x, p.z, base.y)
		if is_walkable(p): return p
	base.y = ground_y(base.x, base.z, base.y)
	return base

func refresh_schedule(force := false) -> void:
	if not is_instance_valid(main): return
	var lk := ",".join(PackedStringArray(GameState.lanterns.keys())) if not GameState.lanterns.is_empty() else ""
	var key := "%d|%s|%s|%s|%s" % [GameState.day, cur_slot(), cur_weather(), lk, ",".join(PackedStringArray(visiting_friends()))]
	var first := _key == ""
	if key == _key and not force: return
	_key = key
	for id in Data.CATS.keys():
		var cid := String(id)
		if first or force:
			_apply_cat(cid, first)
		else:
			_pending[cid] = _rng.randf_range(0.0, 7.0)   # stagger so the whole island does not move at once

func _tick_pending(dt: float) -> void:
	for id in _pending.keys():
		_pending[id] = float(_pending[id]) - dt
		if float(_pending[id]) <= 0.0:
			_pending.erase(id)
			_apply_cat(String(id), false)

func _apply_cat(id: String, initial: bool) -> void:
	var spot := schedule_spot(id)
	var a = get_cat(id)
	if a == null: actors.erase(id)
	if spot == "":
		if a != null: _remove_actor(id)
		return
	if a == null:
		_spawn(id, spot, initial)
	elif String(a.haunt) != spot:
		a.set_haunt(spot, home_for(id, spot))

func _spawn(id: String, spot: String, initial: bool) -> Node3D:
	var data := _cdata(id)
	if data.is_empty(): return null
	var a: Node3D = CatActor.new()
	add_child(a)
	a.setup(self, id, data)
	a.haunt = spot
	var home := home_for(id, spot)
	var from := home
	var walk_in := false
	var p := get_player()
	if not initial and p != null:
		var away := Vector3(home.x - p.global_position.x, 0, home.z - p.global_position.z)
		if away.length() < 16.0:
			if away.length() < 0.1: away = Vector3.RIGHT
			from = home + away.normalized() * 7.0
			from.y = ground_y(from.x, from.z, home.y)
			walk_in = is_walkable(from) and path_clear(from, home)
	a.spawn_at(home, from, walk_in, initial)
	actors[id] = a
	return a

func _remove_actor(id: String) -> void:
	var a = get_cat(id)
	actors.erase(id)
	if a == null: return
	if sit_actor == a: sit_actor = null
	var p := get_player()
	var walk := false
	var away: Vector3 = a.global_position
	if p != null:
		var dv := Vector3(a.global_position.x - p.global_position.x, 0, a.global_position.z - p.global_position.z)
		if dv.length() < 18.0:
			if dv.length() < 0.1: dv = Vector3.RIGHT
			away = a.global_position + dv.normalized() * 8.0
			away.y = ground_y(away.x, away.z, a.global_position.y)
			walk = is_walkable(away) and path_clear(a.global_position, away)
	a.leave(away, walk)

## Test helper: a cat at an exact position, bypassing the schedule.
func spawn_test_cat(id: String, pos: Vector3, pin := true) -> Node3D:
	var old = get_cat(id)
	if old != null: old.queue_free()
	var a := _spawn(id, "", true)
	if a == null: return null
	a.pinned = pin
	a.home = pos
	a.global_position = Vector3(pos.x, ground_y(pos.x, pos.z, pos.y), pos.z)
	return a

# ---------------------------------------------------------------- new day: porch visits and gifts
func _on_new_day(_day: int) -> void:
	_eval_t = 0.0
	give_gifts()

## Each morning up to two friend cats may leave a gift at the porch: a random shore item straight into the bag.
func give_gifts() -> int:
	if int(GameState.flags.get("cat_gift_day", 0)) == GameState.day: return 0
	GameState.flags["cat_gift_day"] = GameState.day
	var given := 0
	for id in visiting_friends():
		var item := _pick_gift(String(id))
		if item == "": continue
		GameState.add_item("shore:" + item, 1)
		GameState.say("%s left a gift on the porch: %s." % [_name(String(id)), item_name("shore:" + item)])
		given += 1
	if given > 0: _save()
	return given

func _pick_gift(id: String) -> String:
	var rng := GameState.day_rng(int(absi(id.hash()) % 7919) + 4001)
	var pool := []
	var total := 0.0
	for k in Data.SHORE.keys():
		var it = Data.SHORE[k]
		if typeof(it) != TYPE_DICTIONARY: continue
		if bool(it.get("bottle", false)) or String(it.get("where", "beach")) != "beach": continue
		var w := maxf(0.1, float(it.get("weight", 1)))
		pool.append([String(k), w])
		total += w
	if pool.is_empty(): return ""
	var r := rng.randf() * total
	for e in pool:
		r -= float(e[1])
		if r <= 0.0: return String(e[0])
	return String(pool[0][0])
