extends Node
## People system: the island's townsfolk. Exposed as main.systems["people"].
## Contract (docs/TEAM.md "Townsfolk"):
##   talk(id), give(id, item_id) -> bool, perk_value(perk, default), person_at(spot) -> id,
##   body(id) -> Node3D, best_gift(id) -> item id, person_name(id), level(id), forecast_fish() -> fish id.
## Content: Data.PEOPLE / PEOPLE_LEVELS / PEOPLE_POINTS when present, else people/people_data.gd (same shape).
## Perks: entries {level, id, value, text, gift_cosmetic?}; granted once per level into person_state.perks.
## Events: entries {level, title, lines, reward {item, n}?}; play once on the next talk after reaching the level.
## Self-test: `godot --path . -- test=people shot=/tmp/lb_people.png wait=3 fresh=1`

const PersonScr := preload("res://scripts/systems/people/person.gd")
const FallbackScr := preload("res://scripts/systems/people/people_data.gd")
const DialogueScr := preload("res://scripts/ui/dialogue.gd")
const BasketScr := preload("res://scripts/systems/town/basket.gd")

## Used when a perk entry carries no "value".
const DEFAULT_PERK_VALUES := {
	"shop_discount": 0.10, "gold_bonus": 0.2, "sell_bonus": 0.05, "special_bonus": 0.5, "bite_window": 0.1,
	"rare_bonus": 0.25, "shore_gold": 0.02, "flats_double": 2.0, "bottle_bonus": 2.0, "fish_forecast": 2.0,
}
## Perk ids other teams may ask for under a different name.
const PERK_ALIASES := {
	"bite_window_bonus": "bite_window", "shore_gold_bonus": "shore_gold", "gold_sell_bonus": "gold_bonus",
	"forecast": "fish_forecast", "rare_fish_bonus": "rare_bonus",
}
## Gift perks (Fern): perk id -> item. They fill the basket by the board (town/basket.gd); the perk value is the interval in days.
const PERK_GIFTS := BasketScr.GIFTS
## How each person dresses (data may override with "outfit" / "scale").
const LOOKS := {
	"pip": {"outfit": "apron", "scale": 0.9}, "maple": {"outfit": "smock", "scale": 0.95},
	"cotton": {"outfit": "scarf", "scale": 1.0}, "fern": {"outfit": "sunhat", "scale": 0.9},
	"moss": {"outfit": "beanie", "scale": 1.12}, "wen": {"outfit": "keeper", "scale": 1.0},
}
## Reactions when the data has none ("react": {love, like, neutral, dislike}).
const REACT := {
	"love": ["Oh. Oh, this is exactly right. How did you know?", "You remembered. I am going to be useless for the rest of the day.",
		"This is going somewhere I can see it every morning."],
	"like": ["That is kind of you. Thank you, Mocha.", "Nice. I know just the shelf for it.", "Thank you. That made the afternoon."],
	"neutral": ["Huh. Thank you. I will find a place for it.", "That is... thoughtful. In its way."],
	"dislike": ["Ah. Well. It is the thought that counts, and I am counting it.", "I will accept this and then quietly put it outside."],
}
const ALREADY_LINES := ["You already spoiled me today. Save it for tomorrow.", "One present a day, Mocha. I have a reputation."]
const PERK_TAG_COLOR := Color("f2c14e")
const NARRATION := ""   # speaker "" = narration (no name tag)

var main: Node
var dialogue: CanvasLayer
var nodes := {}                      # id -> person Node3D
var _cur_spot := {}                  # id -> spot name it is heading to / standing at
var _tick := 0.0
var _talking_id := ""
var _test := false
var _town_pip: Node3D
var _test_cam: Camera3D

# ---------------------------------------------------------------- setup
func setup(m) -> void:
	main = m
	_test = _arg("test") == "people"
	dialogue = DialogueScr.new()
	dialogue.name = "Dialogue"
	dialogue.main = main
	add_child(dialogue)
	dialogue.finished.connect(_on_dialogue_finished)
	_spawn_all()
	if not GameState.people_changed.is_connected(_on_people_changed):
		GameState.people_changed.connect(_on_people_changed)
	if not GameState.new_day.is_connected(_on_new_day):
		GameState.new_day.connect(_on_new_day)
	call_deferred("_late_setup")

## One frame after setup: main has applied fresh=1, town has built its Pip.
func _late_setup() -> void:
	_check_levels(true)
	_sync_town()
	_update_routines(true)
	if _test:
		_run_test()
	else:
		_morning(false)
		if _arg("talk") != "": _dev_talk(_arg("talk"))

## Dev: `-- intro=0 talk=moss shot=/tmp/x.png wait=4` walks Mocha up to a person and opens their talk.
func _dev_talk(id: String) -> void:
	var n := node(id)
	var pl := get_player()
	if n == null or pl == null: return
	await get_tree().create_timer(1.0).timeout
	if not is_instance_valid(n) or not is_instance_valid(pl): return
	var p := n.global_position + Vector3(0, 0, 1.6)
	var isl := _island()
	if isl and isl.has_method("is_walkable"):
		for k in 8:
			var q := n.global_position + Vector3(cos(PI * 0.5 + k * TAU / 8.0), 0, sin(PI * 0.5 + k * TAU / 8.0)) * 1.6
			if isl.is_walkable(q): p = q; break
	p.y = ground_y(p) + 0.05
	pl.global_position = p
	if pl.has_method("face"): pl.face(n.global_position)
	n.face_point(p)
	await get_tree().create_timer(0.6).timeout
	print("dev talk prompt: ", prompt_for(id))
	talk(id)
	for i in int(_arg("talk_next")):   # `talk_next=1` turns pages (to see the tip page)
		await get_tree().create_timer(0.8).timeout
		if is_instance_valid(dialogue) and dialogue.is_open(): dialogue._next()

func _spawn_all() -> void:
	var parent: Node = main if main is Node3D else self
	for raw in people().keys():
		var id := str(raw)
		var p: Dictionary = _look(id)
		var n: Node3D = PersonScr.new()
		parent.add_child(n)
		n.setup_person(id, p, self)
		nodes[id] = n
	_update_routines(true)

func _look(id: String) -> Dictionary:
	var p := pdata(id).duplicate()
	var l: Dictionary = LOOKS.get(id, {})
	for k in l.keys():
		if not p.has(k): p[k] = l[k]
	return p

func _arg(k: String) -> String:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=", true, 1)
		if kv.size() == 2 and kv[0] == k: return kv[1]
	return ""

# ---------------------------------------------------------------- content access
func people() -> Dictionary:
	var d = Data.get("PEOPLE")
	if d is Dictionary and not d.is_empty(): return d
	return FallbackScr.PEOPLE

func pdata(id: String) -> Dictionary:
	var d = people().get(id, {})
	return d if d is Dictionary else {}

func person_name(id: String) -> String:
	return str(pdata(id).get("name", id.capitalize()))

func level(id: String) -> int:
	return GameState.person_level(id)

## Points for an action. Accepts "love"/"loved" style keys either way.
func _points(kind: String) -> int:
	var alt := {"love": "loved", "like": "liked", "dislike": "disliked", "loved": "love", "liked": "like", "disliked": "dislike"}
	for src in [Data.get("PEOPLE_POINTS"), FallbackScr.POINTS]:
		if src is Dictionary:
			if src.has(kind): return int(src[kind])
			if alt.has(kind) and src.has(alt[kind]): return int(src[alt[kind]])
	return 0

## Points needed to reach a level (for tests and UI).
func points_for_level(lv: int) -> int:
	if lv <= 0: return 0
	var th = Data.get("PEOPLE_LEVELS")
	if th is Array and th.size() >= lv: return int(th[lv - 1])
	return lv * 100

## Dictionary lookup that accepts int or String keys.
static func _dget(d, key, default = null):
	if not (d is Dictionary): return default
	if d.has(key): return d[key]
	if d.has(str(key)): return d[str(key)]
	if str(key).is_valid_int() and d.has(int(str(key))): return d[int(str(key))]
	return default

func _accent(id: String) -> Color:
	var s := str(pdata(id).get("accent", "f2c14e"))
	var c := Color(s) if Color.html_is_valid(s) else Color("f2c14e")
	# name tags need a mid-tone so cream text reads on them
	if c.get_luminance() > 0.75:
		var m := str(pdata(id).get("main", "f2c14e"))
		c = Color(m) if Color.html_is_valid(m) else Color("f2c14e")
	if c.get_luminance() > 0.75: c = c.darkened(0.3)
	return c

func _arr(v) -> Array:
	if v is Array: return v
	if v is PackedStringArray: return Array(v)
	if v is String and v != "": return [v]
	return []

# ---------------------------------------------------------------- world helpers
func get_player() -> Node3D:
	var p = main.get("player") if main and is_instance_valid(main) else null
	return p if p is Node3D and is_instance_valid(p) else null

func _island() -> Node:
	var i = main.get("island") if main and is_instance_valid(main) else null
	return i if i and is_instance_valid(i) else null

func _town() -> Node:
	var s = main.get("systems") if main and is_instance_valid(main) else null
	if not (s is Dictionary): return null
	var t = s.get("town")
	return t if t and is_instance_valid(t) else null

func ground_y(p: Vector3) -> float:
	var isl := _island()
	if isl and isl.has_method("ground_y"): return float(isl.ground_y(p.x, p.z))
	return p.y

func _spot_pos(name: String) -> Vector3:
	if main and main.has_method("spot"): return main.spot(name)
	return Vector3.ZERO

func _offset(id: String, spot: String) -> Vector3:
	if spot == "shop_counter": return Vector3.ZERO
	var h := float(abs(hash(id + spot)) % 1000) / 1000.0
	var a := h * TAU
	var r := 1.3 + h * 0.7
	# stay on walkable ground (the pier is narrow: never stand in the sea next to it)
	var isl := _island()
	if isl == null or not isl.has_method("is_walkable"): return Vector3(cos(a), 0, sin(a)) * r
	var base := _spot_pos(spot)
	for rr in [r, r * 0.7, 1.0]:
		for k in 8:
			var aa := a + k * TAU / 8.0
			var o: Vector3 = Vector3(cos(aa), 0, sin(aa)) * float(rr)
			if _walkable(isl, base + o) and _walkable(isl, base + o * 1.25): return o
	return Vector3(cos(a), 0, sin(a)) * r

func _walkable(isl: Node, p: Vector3) -> bool:
	return bool(isl.is_walkable(p))

func _shop_open_now(id: String) -> bool:
	var town := _town()
	if town and town.has_method("is_open"): return bool(town.is_open())
	var hrs = pdata(id).get("shop_hours", [])
	if hrs is Array and hrs.size() == 2:
		var h := GameState.hour()
		return h >= float(hrs[0]) and h < float(hrs[1])
	return false

func _spot_for(id: String) -> String:
	var p := pdata(id)
	if id == "pip" and _shop_open_now(id): return "shop_counter"
	var s = _dget(p.get("routine", {}), GameState.time_slot(), null)
	if s == null or str(s) == "": s = p.get("home", "plaza")
	return str(s)

func _update_routines(snap: bool) -> void:
	for id in nodes.keys():
		var n: Node3D = nodes[id]
		if not is_instance_valid(n) or n.hold_still: continue
		var sp := _spot_for(id)
		if not snap and _cur_spot.get(id, "") == sp: continue
		_cur_spot[id] = sp
		var pos := _spot_pos(sp) + _offset(id, sp)
		pos.y = ground_y(pos)
		n.walk_to(pos, snap)
		# at the counter, town's "Shop" wins ties; Talk/Give still works a step to the side
		n.interact_priority = -1 if sp == "shop_counter" else 1

## Town may build its own Pip (town.pip_node). Then we hide our mesh and follow theirs.
func _sync_town() -> void:
	var town := _town()
	_town_pip = null
	if town and "pip_node" in town:
		var pn = town.get("pip_node")
		var mine = nodes.get("pip")
		if pn is Node3D and is_instance_valid(pn) and is_instance_valid(mine) and pn != mine.body and pn != mine:
			_town_pip = pn
	if nodes.has("pip") and is_instance_valid(nodes["pip"]):
		nodes["pip"].set_body_hidden(_town_pip != null)

func _process(dt: float) -> void:
	_tick += dt
	_update_tags()
	if _town_pip and is_instance_valid(_town_pip) and nodes.has("pip") and is_instance_valid(nodes["pip"]):
		nodes["pip"].global_position = _town_pip.global_position
	if _test and is_instance_valid(_test_cam) and not _test_cam.current: _test_cam.make_current()
	if _tick < 0.5: return
	_tick = 0.0
	if not _test: _update_routines(false)
	_sync_town()

## Only the nearest person shows a name tag, so a crowd never becomes a wall of names.
func _update_tags() -> void:
	var pl := get_player()
	var best := ""
	var best_d := INF
	if pl:
		for id in nodes.keys():
			var n: Node3D = nodes[id]
			if not is_instance_valid(n): continue
			var d := n.global_position.distance_to(pl.global_position)
			if d < best_d: best_d = d; best = id
	for id in nodes.keys():
		if is_instance_valid(nodes[id]): nodes[id].show_tag = id == best

# ---------------------------------------------------------------- public API
func body(id: String) -> Node3D:
	var n := node(id)
	return n.body if n else null

func node(id: String) -> Node3D:
	var n = nodes.get(id)
	return n if n and is_instance_valid(n) else null

## Id of the person at (or walking to) a spot, "" if nobody.
func person_at(spot: String) -> String:
	for id in _cur_spot.keys():
		if _cur_spot[id] == spot: return id
	return ""

func _bag_match(item: String) -> String:
	if GameState.has_item(item): return item
	for k in GameState.bag.keys():
		if str(k).begins_with(item + ":") and int(GameState.bag[k]) > 0: return str(k)
	return ""

func _flowers_liked() -> bool:
	var v = Data.get("PEOPLE_FLOWERS_LIKED")
	return v == null or bool(v)

## Best gift in the bag for this person (loved first, then liked, flowers count as liked); "" if none.
func best_gift(id: String) -> String:
	var p := pdata(id)
	for key in ["loves", "likes"]:
		for it in _arr(p.get(key, [])):
			var k := _bag_match(str(it))
			if k != "": return k
	if _flowers_liked():
		var keys := GameState.bag.keys()
		keys.sort()
		for k in keys:
			if str(k).begins_with("flower:") and int(GameState.bag[k]) > 0 and _gift_kind(id, str(k)) == "like":
				return str(k)
	return ""

func _gift_kind(id: String, item: String) -> String:
	var p := pdata(id)
	for key in ["loves", "likes", "dislikes"]:
		for it in _arr(p.get(key, [])):
			var s := str(it)
			if item == s or item.begins_with(s + ":"):
				return {"loves": "love", "likes": "like", "dislikes": "dislike"}[key]
	if item.begins_with("flower:") and _flowers_liked(): return "like"
	return "neutral"

func item_name(item: String) -> String:
	var parts := item.split(":")
	if parts.size() < 2: return item.capitalize()
	var base := parts[0] + ":" + parts[1]
	var gold := parts.size() > 2 and parts[2] == "gold"
	var nm := ""
	var items = Data.get("ITEMS")
	if items is Dictionary and items.has(base): nm = str(items[base].get("name", ""))
	if nm == "":
		match parts[0]:
			"fish": nm = str(_dget(Data.FISH, parts[1], {}).get("name", ""))
			"shore": nm = str(_dget(Data.SHORE, parts[1], {}).get("name", ""))
			_: nm = str(_dget(Data.SHOP, base, {}).get("name", ""))
	if nm == "": nm = parts[1].replace("_", " ").capitalize()
	return ("Gold " if gold else "") + nm

func gave_today(id: String) -> bool:
	return int(GameState.person_state(id).get("last_gift_day", 0)) == GameState.day

## Prompt for the person interactable ("" while a dialogue is open).
func prompt_for(id: String) -> String:
	if is_instance_valid(dialogue) and dialogue.is_open(): return ""
	if not gave_today(id):
		var g := best_gift(id)
		if g != "": return "Give " + item_name(g)
	return "Talk"

func interact_with(id: String) -> void:
	if is_instance_valid(dialogue) and dialogue.is_open(): return
	if not gave_today(id):
		var g := best_gift(id)
		if g != "":
			give(id, g); return
	talk(id)

## Talk: a story event if one is due, else a fresh line for the level band.
## The first talk of the day gives friendship points.
func talk(id: String) -> void:
	if pdata(id).is_empty(): return
	var st := GameState.person_state(id)
	var lines: Array = []
	var ev := _due_event(id)
	if not ev.is_empty():
		lines = _event_dialogue(id, ev)
		var evs: Array = _arr(st.get("events", []))
		evs.append("lv%d" % int(ev.get("level", 0)))
		st["events"] = evs
		var got := _give_reward(id, ev.get("reward", {}))
		if got != "": lines.append({"who": "Gift", "text": got, "color": PERK_TAG_COLOR})
	else:
		lines = [_pick_line(id)]
	lines.append_array(_take_notes(id))
	if ev.is_empty():
		var tip := _tip_for(id)
		if tip != "": lines.append(tip)
	_open_dialogue(id, lines)
	if int(st.get("last_talk_day", 0)) != GameState.day:
		st["last_talk_day"] = GameState.day
		_add_points(id, _points("talk"), "talk")
	GameState.save_soon()

## Give an item. Once per day per person. Returns true when the gift was handed over.
func give(id: String, item_id: String) -> bool:
	if pdata(id).is_empty(): return false
	var st := GameState.person_state(id)
	if gave_today(id):
		_open_dialogue(id, [ALREADY_LINES[GameState.day % ALREADY_LINES.size()]])
		return false
	var key := _bag_match(item_id)
	if key == "" or not GameState.remove_item(key):
		return false
	var kind := _gift_kind(id, key)
	st["last_gift_day"] = GameState.day
	var pool := _arr(_dget(pdata(id).get("react", {}), kind, []))
	if pool.is_empty(): pool = REACT.get(kind, REACT["neutral"])
	_open_dialogue(id, [str(pool[randi() % pool.size()])])
	var pts := _points(kind)
	var n := node(id)
	if n:
		match kind:
			"love": n.pop_text("Loves it  +%d" % pts, Color("f2a0a6"))
			"like": n.pop_text("Likes it  +%d" % pts, Color("fff1b8"))
	if pts != 0: GameState.add_friendship(id, pts, "gift")
	GameState.save_soon()
	return true

## Active numeric value of a perk: best unlocked value per person, summed across people.
## Accepts aliases (bite_window_bonus = bite_window, forecast = fish_forecast, ...).
func perk_value(perk: String, default = 0.0):
	var ids := [perk]
	if PERK_ALIASES.has(perk): ids.append(PERK_ALIASES[perk])
	for k in PERK_ALIASES.keys():
		if PERK_ALIASES[k] == perk: ids.append(k)
	var total := 0.0
	var found := false
	for raw in people().keys():
		var id := str(raw)
		var owned := _arr(GameState.person_state(id).get("perks", []))
		var lv := level(id)
		var best := -INF
		for e in _perk_entries(id):
			if e.id in ids and e.id in owned and e.level <= lv:
				best = maxf(best, float(e.value))
		if best != -INF:
			total += best; found = true
	return total if found else default

func has_any_perk(perk: String) -> bool:
	return perk_value(perk, null) != null

# ---------------------------------------------------------------- lines
func _band_lines(id: String, lv: int) -> Array:
	var ls = pdata(id).get("lines", [])
	if ls is Array: return ls
	if not (ls is Dictionary): return []
	var named := {"low": [0, 3], "mid": [4, 7], "high": [8, 10]}
	for k in named.keys():
		if ls.has(k) and lv >= named[k][0] and lv <= named[k][1]: return _arr(ls[k])
	var best_k := -1
	for k in ls.keys():
		if str(k).is_valid_int() and int(str(k)) <= lv and int(str(k)) > best_k: best_k = int(str(k))
	if best_k >= 0: return _arr(_dget(ls, best_k, []))
	var out: Array = []
	for k in ls.keys(): out.append_array(_arr(ls[k]))
	return out

## A line from the current band, never repeating a seen line while unseen ones remain.
func _pick_line(id: String) -> String:
	var pool := _band_lines(id, level(id))
	if pool.is_empty(): pool = _band_lines(id, 0)
	if pool.is_empty(): return "Nice day for it."
	var st := GameState.person_state(id)
	var seen: Array = _arr(st.get("seen_lines", []))
	var unseen := pool.filter(func(l): return not (str(l) in seen))
	var line := ""
	if not unseen.is_empty():
		line = str(unseen[randi() % unseen.size()])
	else:
		var last := str(st.get("last_line", ""))
		var others := pool.filter(func(l): return str(l) != last)
		if others.is_empty(): others = pool
		line = str(others[randi() % others.size()])
	if not (line in seen): seen.append(line)
	st["seen_lines"] = seen
	st["last_line"] = line
	return line

## Story events, normalised to [{level, title, lines, reward}].
func _events(id: String) -> Array:
	var ev = pdata(id).get("events", [])
	var out: Array = []
	if ev is Array:
		for e in ev:
			if e is Dictionary: out.append(e)
	elif ev is Dictionary:
		for k in ev.keys():
			if not str(k).is_valid_int(): continue
			var v = ev[k]
			if v is Dictionary:
				var d: Dictionary = v.duplicate(); d["level"] = int(str(k)); out.append(d)
			elif v is Array:
				out.append({"level": int(str(k)), "lines": v})
	return out

## Lowest reached story event not yet played ({} if none).
func _due_event(id: String) -> Dictionary:
	var lv := level(id)
	var done := _arr(GameState.person_state(id).get("events", []))
	var best := {}
	for e in _events(id):
		var el := int(e.get("level", 99))
		if el <= lv and not ("lv%d" % el in done) and not _arr(e.get("lines", [])).is_empty():
			if best.is_empty() or el < int(best.get("level", 99)): best = e
	return best

## Event lines as dialogue entries: narration has the event title as its tag, quoted lines are spoken.
func _event_dialogue(id: String, ev: Dictionary) -> Array:
	var out: Array = []
	var title := str(ev.get("title", ""))
	for raw in _arr(ev.get("lines", [])):
		var t := str(raw).strip_edges()
		if t.begins_with("Mocha: "):
			out.append(t)
		elif t.begins_with("\"") and t.ends_with("\"") and t.count("\"") == 2:
			out.append(t.substr(1, t.length() - 2))
		elif t.begins_with("\""):
			out.append(t)
		else:
			out.append({"who": title, "text": t, "color": Color("b8a48c"), "narration": true})
	return out

## Adds an event reward to the bag; returns a short line for the dialogue ("" if nothing).
func _give_reward(_id: String, r) -> String:
	if not (r is Dictionary) or r.is_empty(): return ""
	var parts: Array = []
	var item := str(r.get("item", ""))
	var n := int(r.get("n", 1))
	if item != "" and n > 0:
		GameState.add_item(item, n)
		parts.append(item_name(item) + ("" if n == 1 else " x%d" % n))
	var yen := int(r.get("yen", 0))
	if yen > 0:
		GameState.add_coins(yen)
		parts.append("%d yen" % yen)
	return "" if parts.is_empty() else "Added to your bag: %s." % ", ".join(parts)

func _take_notes(id: String) -> Array:
	var st := GameState.person_state(id)
	var out: Array = []
	for t in _arr(st.get("notes", [])): out.append(_perk_line(str(t)))
	st["notes"] = []
	return out

func _perk_line(text: String) -> Dictionary:
	return {"who": "New perk", "text": text, "color": PERK_TAG_COLOR}

func _open_dialogue(id: String, lines: Array) -> void:
	if not is_instance_valid(dialogue): return
	_talking_id = id
	var n := node(id)
	if n: n.set_talking(true)
	dialogue.open(person_name(id), lines, _accent(id))

func _on_dialogue_finished() -> void:
	var n := node(_talking_id)
	if n: n.set_talking(false)
	_talking_id = ""

# ---------------------------------------------------------------- practical tips
## One short, practical tip per talk (last page), about what the player has not done yet.
## Each tip: {id, text, done (already followed), at (spots where it fits best), info (true = once is enough)}.
## A followed tip never shows again; an info tip shows once; an unfollowed one may come back after 2 days.
const TIP_REPEAT_DAYS := 2
const TIP_MAX := 110

func _any_cat(field: String) -> bool:
	for c in GameState.cats.values():
		if c is Dictionary and int(c.get(field, 0)) > 0: return true
	return false

func _shore_has(ids: Array) -> bool:
	for k in GameState.shore_log.keys():
		var base := str(k).split(":")[0]
		if base in ids or str(k) in ids: return true
	return false

func _tips(id: String) -> Array:
	var fished := not GameState.fish_log.is_empty()
	var harbour_cost := int(_dget(_dget(Data.LANTERNS, "harbour", {}), "cost", 12))
	match id:
		"moss": return [
			{"id": "moss_pier", "done": fished, "at": ["pier", "pier_end"],
				"text": "Fish off the end of the pier. Little dips are teasing. Tap when the bobber goes right under."},
			{"id": "moss_shadow", "info": true, "done": not fished, "at": ["pier", "pier_end", "beach"],
				"text": "Watch the shadow. Big shadow, big fish. Small one? Reel in and cast again. Costs you nothing."},
			{"id": "moss_rain", "info": true, "done": false, "at": [],
				"text": "Rain is when the big ones bite. They get greedy when the sky is busy. Bring a hat."},
			{"id": "moss_dusk", "info": true, "done": not fished, "at": ["pier"],
				"text": "Morning and evening fish differently. Same pier, different crowd. Try both before you judge it."},
		]
		"maple": return [
			{"id": "maple_slow", "done": _any_cat("hearts"), "at": ["plaza", "beach"],
				"text": "Walk slowly near cats. A small push on the stick. Trot at them and the shy ones just leave."},
			{"id": "maple_treat", "done": _any_cat("last_treat_day"), "at": [],
				"text": "Every cat has a favourite treat. Pancake would sell the shop for Tuna Bites. Pip stocks them."},
			{"id": "maple_sit", "done": _any_cat("last_sit_day"), "at": ["plaza"],
				"text": "Sit near a cat and do nothing. Hardest thing in the world. They come closer, eventually."},
		]
		"pip": return [
			{"id": "pip_sell", "done": bool(GameState.flags.get("sold_any", false)), "at": ["shop_counter", "shop"],
				"text": "I buy fish, shells, sea glass. Most of what the sea coughs up, really. Not boots. Usually."},
			{"id": "pip_board", "done": int(GameState.flags.get("requests_done", 0)) > 0, "at": ["shop_counter", "shop"],
				"text": "The request board by the shop changes every morning. Neighbours pay well, and they remember."},
			{"id": "pip_special", "info": true, "done": not fished, "at": [],
				"text": "Check the board for my daily special. One fish sells for double that day. Plan around it."},
		]
		"fern": return [
			{"id": "fern_beach", "done": not GameState.shore_log.is_empty(), "at": ["beach", "board"],
				"text": "The beach refills every morning. Shells, sea glass, the odd bottle. Pick it all up once."},
			{"id": "fern_flats", "done": _shore_has(["sand_dollar", "razor_shell", "moon_shell", "star_stone"]), "at": ["beach"],
				"text": "Low tide is six to nine, morning and evening. The flats open up. Sand dollars, if you are quick."},
			{"id": "fern_bottle", "done": _shore_has(["bottle"]), "at": ["beach"],
				"text": "Find a bottle, read the note. Ines wrote them. They know more than they let on."},
		]
		"wen": return [
			{"id": "wen_weather", "info": true, "done": false, "at": [],
				"text": "Weather sets the day here. Rain for big fish, fog for strange things. Look up before you plan."},
			{"id": "wen_fog", "info": true, "done": GameState.day < 2, "at": ["lighthouse"],
				"text": "A low mist on the evening horizon means fog tomorrow. Fog days are worth getting up for."},
			{"id": "wen_order", "done": GameState.lanterns.has("lighthouse"), "at": ["lighthouse"],
				"text": "My lamp is the last one. Harbour first, then the hill. Ines was particular about the order."},
		]
		"cotton": return [
			{"id": "cotton_sparks", "done": GameState.sparks > 0 or GameState.lanterns.size() > 0, "at": [],
				"text": "Every first is a spark. A new fish, a new shell, a cat who decides you are fine."},
			{"id": "cotton_lantern", "done": GameState.lanterns.has("harbour"), "at": ["board", "plaza"],
				"text": "%d sparks lights the Harbour Lantern, by the pier. Walk up to it once you have them." % harbour_cost},
		]
	return []

## The tip for this talk ("" if none is helpful right now). Records it as shown.
func _tip_for(id: String) -> String:
	var st := GameState.person_state(id)
	var shown: Dictionary = st.get("tips", {}) if st.get("tips") is Dictionary else {}
	var here := str(_cur_spot.get(id, ""))
	var best := {}
	var best_score := -INF
	for t in _tips(id):
		if bool(t.get("done", false)): continue
		var tid := str(t.get("id", ""))
		var text := str(t.get("text", ""))
		if tid == "" or text == "" or text.length() > TIP_MAX: continue
		var score := 0.0
		if shown.has(tid):
			if bool(t.get("info", false)): continue
			if GameState.day - int(shown[tid]) < TIP_REPEAT_DAYS: continue
			score -= 10.0
		if here in _arr(t.get("at", [])): score += 2.0
		if tid == "moss_rain" and GameState.weather() == "rain": score += 3.0
		if score > best_score: best_score = score; best = t
	if best.is_empty(): return ""
	shown[str(best.id)] = GameState.day
	st["tips"] = shown
	return str(best.text)

# ---------------------------------------------------------------- friendship + perks
func _add_points(id: String, pts: int, why: String) -> void:
	var n := node(id)
	if n and pts > 0 and why == "talk": n.pop_text("+%d" % pts)
	GameState.add_friendship(id, pts, why)

## Normalised perk entries: [{id, value, text, level, cosmetic}]. Accepts an Array of
## {level, id, ...} or a Dictionary {level: entry or [entries]}.
func _perk_entries(id: String) -> Array:
	var out: Array = []
	var pk = pdata(id).get("perks", [])
	var raw: Array = []
	if pk is Array:
		for e in pk:
			if e is Dictionary: raw.append([int(e.get("level", 99)), e])
	elif pk is Dictionary:
		for k in pk.keys():
			if not str(k).is_valid_int(): continue
			var v = pk[k]
			for e in (v if v is Array else [v]): raw.append([int(str(k)), e])
	for pair in raw:
		var lv: int = pair[0]
		var e = pair[1]
		if e is String and e != "": e = {"id": e}
		if not (e is Dictionary) or str(e.get("id", "")) == "": continue
		var pid := str(e.get("id"))
		out.append({"id": pid, "value": e.get("value", DEFAULT_PERK_VALUES.get(pid, 1.0)), "level": lv,
			"text": str(e.get("text", e.get("desc", ""))), "cosmetic": str(e.get("gift_cosmetic", ""))})
	return out

func _on_people_changed() -> void:
	call_deferred("_check_levels", false)

## Grant every perk for the levels reached (once each). silent: no toasts (loading a save).
func _check_levels(silent: bool) -> void:
	var changed := false
	for raw_id in people().keys():
		var id := str(raw_id)
		var st := GameState.person_state(id)
		var lv := level(id)
		var toast_perk := false
		var perks := _arr(st.get("perks", []))
		var granted := _arr(st.get("perk_levels", []))
		var notes := _arr(st.get("notes", []))
		for e in _perk_entries(id):
			if e.level > lv: continue
			var key := "%d:%s" % [e.level, e.id]
			if key in granted: continue
			granted.append(key)
			if not (e.id in perks): perks.append(e.id)
			if e.cosmetic != "": GameState.cosmetics[e.cosmetic] = true
			changed = true
			if silent: continue
			var text: String = e.text if e.text != "" else "%s: %s." % [person_name(id), e.id.replace("_", " ").capitalize()]
			var n := node(id)
			if n: n.pop_text("New perk", PERK_TAG_COLOR)
			if is_instance_valid(dialogue) and dialogue.is_open() and _talking_id == id:
				dialogue.add_lines([_perk_line(text)])   # explained right here, no toast on top
			else:
				if notes.is_empty(): toast_perk = true
				notes.append(text)
		if toast_perk: GameState.say("%s has a new perk for you." % person_name(id))
		# story event hint (the event itself plays on the next talk)
		var hinted := _arr(st.get("event_hints", []))
		for e in _events(id):
			var el := int(e.get("level", 99))
			var tag := "lv%d" % el
			if el <= lv and not (tag in hinted):
				hinted.append(tag)
				changed = true
				if not silent and not toast_perk and not (tag in _arr(st.get("events", []))):
					GameState.say("%s has something to tell you." % person_name(id))
		st["perks"] = perks; st["perk_levels"] = granted; st["notes"] = notes; st["event_hints"] = hinted
	_apply_world_perks()
	if changed: GameState.save_soon()

## Perks that change GameState directly. fog_bell (Wen): a foggy day at least every N days.
func _apply_world_perks() -> void:
	if "fog_gap_override" in GameState:
		var fb = perk_value("fog_bell", null)
		if fb != null: GameState.set("fog_gap_override", int(round(float(fb))))

# ---------------------------------------------------------------- daily
func _on_new_day(_d: int) -> void:
	_morning(true)
	_update_routines(false)

## Morning: forecast + perk gifts, once per day (also after loading a save in the morning).
func _morning(_from_signal: bool) -> void:
	if int(GameState.flags.get("people_morning_day", 0)) == GameState.day: return
	GameState.flags["people_morning_day"] = GameState.day
	_forecast()
	_perk_gifts()
	GameState.save_soon()

## Fern's basket by the board: each gift perk adds its item once per period (the perk value is the number of days).
func _perk_gifts() -> void:
	var who := ""
	for perk in PERK_GIFTS.keys():
		var id := BasketScr.holder(str(perk))
		if id == "": continue
		var every := maxi(1, int(round(float(perk_value(str(perk), 1.0)))))
		if BasketScr.put_if_due(str(perk), every): who = id
	if who != "" and BasketScr.first_time():
		GameState.say("%s left something in the basket by the board." % person_name(who))

## Today's forecast from whoever holds fish_forecast (Captain Moss). Stores flags.forecast_fish.
func _forecast() -> void:
	var who := ""
	for raw in people().keys():
		var id := str(raw)
		if GameState.has_perk(id, "fish_forecast") or GameState.has_perk(id, "forecast"): who = id; break
	if who == "": return
	var fid := forecast_fish()
	if fid == "": return
	GameState.flags["forecast_day"] = GameState.day
	GameState.flags["forecast_fish"] = fid
	var f: Dictionary = Data.FISH.get(fid, {})
	var spots := _arr(f.get("spots", []))
	var spot := str(spots[0]) if not spots.is_empty() else "pier"
	var place: String = {"pier": "the pier", "beach": "the beach", "rocks": "the rocks", "flats": "the flats"}.get(spot, spot)
	var slots := _arr(f.get("slots", []))
	var when := "today" if slots.is_empty() else ("tonight" if str(slots[0]) == "night" else "this " + str(slots[0]))
	GameState.say("%s: %s at %s %s." % [person_name(who).trim_prefix("Captain "), str(f.get("name", fid)), place, when])

## Today's likely rare fish (weather-matched first, reachable spots only), "" if none fits.
func forecast_fish() -> String:
	var wx := GameState.weather()
	var picks: Array = []
	var weather_picks: Array = []
	var spot_lantern = Data.get("SPOT_LANTERN")
	for fid in Data.FISH.keys():
		var f: Dictionary = Data.FISH[fid]
		if int(f.get("rarity", 1)) < 3 or f.get("junk", false): continue
		var need := str(f.get("needs_lantern", ""))
		if need != "" and not GameState.lanterns.has(need): continue
		var reachable := false
		for s in _arr(f.get("spots", [])):
			var lan := str(_dget(spot_lantern, str(s), "")) if spot_lantern is Dictionary else ""
			if lan == "" or GameState.lanterns.has(lan): reachable = true
		if not reachable: continue
		var w := _arr(f.get("weather", []))
		if not w.is_empty() and not (wx in w): continue
		picks.append(fid)
		if not w.is_empty(): weather_picks.append(fid)
	var pool := weather_picks if not weather_picks.is_empty() else picks
	if pool.is_empty(): return ""
	pool.sort()
	var rng := GameState.day_rng(4242)
	return str(pool[rng.randi() % pool.size()])

# ---------------------------------------------------------------- self-test (-- test=people)
var _test_fail := 0

func _ok(cond: bool, what: String) -> void:
	print("[people test] %s: %s" % ["ok" if cond else "FAIL", what])
	if not cond: _test_fail += 1

func _to_level(id: String, lv: int) -> void:
	var need := points_for_level(lv) - int(GameState.person_state(id).points)
	if need > 0: GameState.add_friendship(id, need, "test")

func _close_and_wait() -> void:
	if is_instance_valid(dialogue): dialogue.close()
	await get_tree().process_frame
	await get_tree().process_frame

func _run_test() -> void:
	await get_tree().create_timer(0.2).timeout
	var center := _spot_pos("plaza") if _island() else Vector3.ZERO
	_build_test_world(center)
	_layout_test(center)
	var pl := get_player()
	GameState.bag.clear(); GameState.bag_changed.emit()
	# --- prompts
	_ok(prompt_for("cotton") == "Talk", "prompt is Talk with an empty bag")
	GameState.add_item("shore:moon_shell")
	GameState.add_item("fish:old_boot")
	_ok(prompt_for("cotton") == "Give Moon Shell", "prompt offers a loved gift: '%s'" % prompt_for("cotton"))
	_ok(prompt_for("maple") == "Talk", "no gift prompt when nothing liked is carried")
	GameState.add_item("flower:sea_pink")
	_ok(prompt_for("moss").begins_with("Give"), "flowers count as liked: '%s'" % prompt_for("moss"))
	GameState.remove_item("flower:sea_pink")
	# --- talk + seen lines
	talk("pip")
	_ok(dialogue.is_open(), "talk opens the dialogue")
	_ok(prompt_for("pip") == "", "no prompt while the dialogue is open")
	_ok(int(GameState.person_state("pip").points) == _points("talk"), "first talk of the day gives points")
	await _close_and_wait()
	_ok(not GameState.paused and (pl == null or not bool(pl.get("busy"))), "closing releases pause and busy")
	talk("pip"); await _close_and_wait()
	_ok(int(GameState.person_state("pip").points) == _points("talk"), "second talk the same day gives no points")
	var seen: Array = GameState.person_state("pip").seen_lines
	_ok(seen.size() == 2 and seen[0] != seen[1], "talk does not repeat seen lines")
	# --- gifts: failure, success, once per day
	_ok(not give("fern", "shore:star_stone"), "giving an item not in the bag fails")
	_ok(not dialogue.is_open(), "failed give does not open a dialogue")
	var before := int(GameState.person_state("pip").points)
	_ok(give("pip", "fish:old_boot"), "Pip takes the boot (disliked)")
	_ok(int(GameState.person_state("pip").points) == maxi(0, before + _points("dislike")), "disliked gift points")
	await _close_and_wait()
	GameState.add_item("shore:star_stone")
	_ok(prompt_for("pip") == "Talk", "no Give prompt after a gift today")
	_ok(not give("pip", "shore:star_stone") and GameState.has_item("shore:star_stone"), "second gift the same day is refused, item kept")
	await _close_and_wait()
	# --- level ups, perks, events, rewards
	_to_level("moss", 5)
	await get_tree().process_frame
	_ok(GameState.has_perk("moss", "fish_forecast"), "Moss level 5 grants fish_forecast")
	_ok(is_equal_approx(float(perk_value("bite_window_bonus", 0.0)), 0.05), "bite_window_bonus alias = %s" % perk_value("bite_window_bonus", 0.0))
	GameState.flags.erase("people_morning_day")
	_morning(false)
	_ok(str(GameState.flags.get("forecast_fish", "")) != "", "forecast picked %s" % GameState.flags.get("forecast_fish", ""))
	_to_level("pip", 5)
	await get_tree().process_frame
	_ok(is_equal_approx(float(perk_value("shop_discount", 0.0)), 0.10), "Pip lv5 shop_discount = %s" % perk_value("shop_discount", 0.0))
	_ok(is_equal_approx(float(perk_value("flats_double", 0.0)), 0.0), "flats_double stays default while locked")
	_to_level("cotton", 2)
	await get_tree().process_frame
	_ok(GameState.cosmetics.has("cos:scarf_oat") or not pdata("cotton").has("perks"), "Cotton's scarf lands in the wardrobe")
	_to_level("maple", 4)
	await get_tree().process_frame
	_ok(level("maple") == 4 and not _due_event("maple").is_empty(), "Maple level 4 has her story event due")
	talk("maple")
	_ok(dialogue.is_open() and _due_event("maple").is_empty(), "story event plays once")
	await _close_and_wait()
	_to_level("fern", 4)
	await get_tree().process_frame
	var had := int(GameState.bag.get("flower:sea_pink", 0))
	talk("fern")
	_ok(int(GameState.bag.get("flower:sea_pink", 0)) > had or _events("fern").is_empty(), "event reward added to the bag")
	_ok(not _arr(GameState.person_state("fern").get("notes", [])).size(), "perk notes delivered in the dialogue")
	await _close_and_wait()
	_ok(not GameState.paused and (pl == null or not bool(pl.get("busy"))), "everything released after the loop")
	_ok(body("maple") != null, "body(maple) returns a mesh")
	if pdata("wen").has("perks") and "fog_gap_override" in GameState:
		_to_level("wen", 10)
		await get_tree().process_frame
		_ok(int(GameState.get("fog_gap_override")) == int(round(float(perk_value("fog_bell", 0.0)))) and int(GameState.get("fog_gap_override")) > 0, "Wen's fog bell sets fog_gap_override = %s" % GameState.get("fog_gap_override"))
		GameState.set("fog_gap_override", 0)
		await _close_and_wait()
	print("[people test] done, %d failure(s)" % _test_fail)
	# --- the screenshot: Cotton gets her gift, people wave at Mocha
	_layout_test(center)
	if nodes.has(_arg("view")):
		# close-up: everyone else steps aside, Mocha stands off camera, the subject waves
		for id in nodes.keys():
			if id != _arg("view"): nodes[id].walk_to(center + Vector3(-12, 0, -12), true)
		if pl: pl.global_position = center + Vector3(30, 0.05, 30)
		var tp := center + Vector3(5.5, 0, 5.5)
		tp.y = ground_y(tp)
		nodes[_arg("view")].walk_to(tp, true)
		nodes[_arg("view")].set_facing(float(_arg("angle")) if _arg("angle").is_valid_float() else 0.25)
		if is_instance_valid(_test_cam):
			_test_cam.global_position = tp + Vector3(0.9, 1.0, 5.6)
			_test_cam.look_at(tp + Vector3(0, 0.95, 0))
		await get_tree().create_timer(1.2).timeout
		nodes[_arg("view")].wave()
		return
	await get_tree().create_timer(0.2).timeout
	give("cotton", "shore:moon_shell")
	for id in ["moss", "wen", "fern"]:
		if nodes.has(id): nodes[id].wave()

func _layout_test(center: Vector3) -> void:
	var layout := {"wen": Vector3(0.0, 0, -2.9), "moss": Vector3(-1.25, 0, -1.7), "maple": Vector3(1.2, 0, -1.7),
		"cotton": Vector3(-0.62, 0, -0.35), "fern": Vector3(0.66, 0, -0.35), "pip": Vector3(0.0, 0, 0.9)}
	var i := 0
	for id in nodes.keys():
		var n: Node3D = nodes[id]
		n.hold_still = true
		var p: Vector3 = center + layout.get(id, Vector3(-2.5 + i * 1.0, 0, 1.5))
		p.y = ground_y(p)
		n.walk_to(p, true)
		n.set_facing(0.0)
		i += 1
	var pl := get_player()
	if pl:
		pl.global_position = center + Vector3(-1.55, 0.05, 2.0)
		if pl.has_method("face"): pl.face(center + Vector3(0.4, 0, -1.2))

func _build_test_world(center: Vector3) -> void:
	var root := Node3D.new(); root.name = "PeopleTestWorld"
	(main if main is Node3D else self).add_child(root)
	root.global_position = center
	if _island() == null:
		var ground := StaticBody3D.new()
		var cs := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = Vector3(40, 1, 40)
		cs.shape = bx; cs.position = Vector3(0, -0.5, 0); ground.add_child(cs); root.add_child(ground)
		Toys.add(Toys.cyl(9.0, 9.4, 0.4, 48), Toys.mat(Color("bfe3a8"), 0.95, 0.0), Vector3(0, -0.2, 0), root)
		Toys.add(Toys.cyl(14.0, 14.0, 0.2, 48), Toys.mat(Color("8fd0e0"), 0.3, 0.0), Vector3(0, -0.35, 0), root)
		Toys.add(Toys.cyl(3.4, 3.4, 0.06, 40), Toys.mat(Color("f2e3c4"), 0.95, 0.0), Vector3(0, 0.0, -0.6), root)
		Toys.tree(root, Vector3(-3.4, 0, -4.2), 1.1)
		Toys.tree(root, Vector3(3.6, 0, -3.8), 0.9, Color("a8d49a"))
	if main.get("sky") == null:
		var env := WorldEnvironment.new(); var e := Environment.new()
		e.background_mode = Environment.BG_COLOR; e.background_color = Color("cfe9f2")
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color("fff1e0"); e.ambient_light_energy = 0.7
		e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.environment = e; root.add_child(env)
		var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, -30, 0); sun.light_energy = 1.2
		sun.light_color = Color("fff3e0"); sun.shadow_enabled = true; root.add_child(sun)
	var cam := Camera3D.new(); cam.fov = 42
	root.add_child(cam)
	cam.global_position = center + Vector3(0, 4.3, 10.4)
	cam.look_at(center + Vector3(0, 0.55, -1.3))
	var v := _arg("view")
	if v == "close":   # `view=close`: the back rows, for look-dev
		cam.global_position = center + Vector3(0, 2.2, 4.2)
		cam.look_at(center + Vector3(0, 1.0, -1.6))
	elif nodes.has(v):   # `view=<person id>`: a ground-level close-up (checks feet on the ground)
		cam.fov = 30
	cam.make_current()
	_test_cam = cam   # kept current every frame during the test
	if main.get("hud") == null:
		var cl := CanvasLayer.new(); cl.layer = 12; root.add_child(cl)
		var lab := Label.new(); lab.position = Vector2(20, 24); lab.size = Vector2(500, 120)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.add_theme_color_override("font_color", Color("6b4a3a")); lab.add_theme_font_size_override("font_size", 20)
		cl.add_child(lab)
		GameState.toast.connect(func(t): lab.text = t)
