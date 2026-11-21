extends RefCounted
## Request board logic (no UI). Requests live in GameState.requests as plain dictionaries:
##   id, tpl (template index), kind ("fish_size"|"fish"|"shore"|"gold"), who (person id, e.g. "maple"), who_name,
##   text, reward (yen), sparks, done (bool), day (posted), item (species / shore id), count, cm, auto (bool).
## The board holds Data.REQUESTS_PER_DAY. Unfinished requests roll over, finished ones clear in the morning,
## and an untouched one is gently replaced after Data.REQUEST_EXPIRE_DAYS mornings.
## "auto" size requests (fish_size with auto_on_catch) are handed over the moment a fish is caught (see Town.on_catch):
## the bag stores no per-fish sizes, so they can not be completed from the bag.

const Dat := preload("res://scripts/systems/town/dat.gd")
const Eco := preload("res://scripts/systems/town/economy.gd")
const Yen := preload("res://scripts/systems/town/yen.gd")
const SALT := 91000

static func per_day() -> int:
	return clampi(Dat.i("REQUESTS_PER_DAY", 3), 1, 6)

static func expire_days() -> int:
	return maxi(1, Dat.i("REQUEST_EXPIRE_DAYS", 3))

static func friendship_points() -> int:
	return int(Dat.d("PEOPLE_POINTS").get("request", 60))

static func person_name(pid: String, fallback := "") -> String:
	var p := Dat.entry("PEOPLE", pid)
	var n := str(p.get("name", ""))
	return n if n != "" else (fallback if fallback != "" else pid.capitalize())

## Make sure the board exists for today. Cheap and safe to call any time. Returns the morning message
## ("" when nothing rolled).
static func ensure_today() -> String:
	_sanitize()
	if int(GameState.flags.get("req_day", 0)) == GameState.day and GameState.requests.size() > 0:
		return ""
	return roll_day()

static func _sanitize() -> void:
	var clean: Array = []
	for r in GameState.requests:
		if r is Dictionary and str(r.get("text", "")) != "" and str(r.get("kind", "")) != "":
			clean.append(r)
	if clean.size() != GameState.requests.size():
		GameState.requests = clean

## New morning: clear finished requests, replace expired ones, keep the rest, fill the board.
static func roll_day() -> String:
	var day := GameState.day
	var keep: Array = []
	var expired: Array = []
	for r in GameState.requests:
		if not (r is Dictionary): continue
		if bool(r.get("done", false)): continue
		if day - int(r.get("day", day)) >= expire_days():
			expired.append(r)
			continue
		keep.append(r)
	while keep.size() > per_day():
		keep.pop_front()
	var rng := GameState.day_rng(SALT)
	var guard := 0
	while keep.size() < per_day() and guard < 80:
		guard += 1
		var q := _make(rng, day, keep, guard)
		if not q.is_empty():
			keep.append(q)
	GameState.requests = keep
	GameState.flags["req_day"] = day
	GameState.catalog_changed.emit()
	GameState.save_soon()
	if not expired.is_empty():
		var who := str(expired[0].get("who_name", "Someone"))
		return "%s found one elsewhere. New notes are up." % who
	return "New notes on the request board."

# ------------------------------------------------------------------ generation
static func _make(rng: RandomNumberGenerator, day: int, existing: Array, attempt: int) -> Dictionary:
	var templates: Array = Dat.a("REQUEST_TEMPLATES")
	if templates.is_empty():
		return {}
	var total := 0.0
	for t in templates:
		total += float(t.get("weight", 4)) if t is Dictionary else 0.0
	if total <= 0.0: return {}
	var r := rng.randf() * total
	var idx := 0
	for i in templates.size():
		var t: Variant = templates[i]
		if not (t is Dictionary): continue
		r -= float(t.get("weight", 4))
		if r <= 0.0:
			idx = i
			break
	var tpl: Dictionary = templates[idx]
	var cap := int(tpl.get("max_active", 0))
	if cap > 0:
		var active := 0
		for e in existing:
			if e is Dictionary and int(e.get("tpl", -1)) == idx: active += 1
		if active >= cap: return {}
	var q := _from_template(idx, tpl, rng, day, existing.size())
	if q.is_empty(): return {}
	if _duplicate(q, existing, attempt > 20): return {}
	return q

static func _duplicate(q: Dictionary, existing: Array, relaxed: bool) -> bool:
	for e in existing:
		if not (e is Dictionary): continue
		if str(e.get("text", "")) == str(q.text): return true
		if str(e.get("kind", "")) == str(q.kind):
			if str(q.kind) == "gold" or str(q.kind) == "fish_size": return true
			if str(e.get("item", "")) == str(q.item): return true
		if not relaxed and str(e.get("who", "")) == str(q.who): return true
	return false

static func _span(v: Variant, lo_d: int, hi_d: int) -> Vector2i:
	var lo := lo_d; var hi := hi_d
	if v is Array and v.size() >= 2:
		lo = int(v[0]); hi = int(v[1])
	elif v is Array and v.size() == 1:
		lo = int(v[0]); hi = lo
	if hi < lo:
		var tmp := lo; lo = hi; hi = tmp
	return Vector2i(lo, hi)

## Reward: a point in the template's yen range (difficulty 0..1 pulls it up) plus extra (price based).
static func _reward(t: Dictionary, frac: float, rng: RandomNumberGenerator, extra := 0.0) -> int:
	var sp := _span(t.get("reward", null), 50, 100)
	var v := lerpf(sp.x, sp.y, clampf(frac, 0.0, 1.0) * 0.8 + rng.randf() * 0.2) + extra
	return maxi(10, int(round(v / 10.0)) * 10)

static func _fmt(text: String, args: Array) -> String:
	var need := text.count("%d") + text.count("%s")
	var a := args.duplicate()
	while a.size() < need: a.append("")
	while a.size() > need: a.pop_back()
	if need == 0: return text
	return text % a

static func _plural(name: String, n: int) -> String:
	var l := name.to_lower()
	if n == 1 or l.ends_with("glass") or l.ends_with("wood") or l.ends_with("s"): return l
	return l + "s"

static func _pick_weighted(rng: RandomNumberGenerator, ids: Array, weights: Array) -> String:
	var total := 0.0
	for w in weights: total += float(w)
	if ids.is_empty() or total <= 0.0: return ""
	var r := rng.randf() * total
	for k in ids.size():
		r -= float(weights[k])
		if r <= 0.0: return str(ids[k])
	return str(ids[ids.size() - 1])

## Species that may be asked for: caught before (pool "caught") or, with nothing caught, a common one that is open now.
static func _fish_pool(t: Dictionary) -> Array:
	var max_r := int(t.get("max_rarity", 2))
	var rocks_open := GameState.lanterns.has("harbour")
	var out: Array = []
	var pool_kind := str(t.get("pool", "caught"))
	for k in Dat.d("FISH").keys():
		var e := Dat.entry("FISH", str(k))
		if e.is_empty() or bool(e.get("junk", false)) or int(e.get("rarity", 1)) > max_r: continue
		var lg: Variant = GameState.fish_log.get(str(k), null)
		var caught := lg is Dictionary and int(lg.get("count", 0)) > 0
		if pool_kind == "caught" and caught:
			out.append(str(k))
	if out.is_empty():
		for k in Dat.d("FISH").keys():
			var e2 := Dat.entry("FISH", str(k))
			if e2.is_empty() or bool(e2.get("junk", false)) or int(e2.get("rarity", 1)) > 1: continue
			if str(e2.get("needs_lantern", "")) != "" or str(e2.get("needs_perk", "")) != "" or bool(e2.get("low_tide", false)): continue
			var ok := false
			for s in e2.get("spots", []):
				if str(s) != "rocks" or rocks_open: ok = true
			if ok and (e2.get("slots", []) as Array).is_empty() and (e2.get("weather", []) as Array).is_empty():
				out.append(str(k))
	return out

static func _from_template(idx: int, t: Dictionary, rng: RandomNumberGenerator, day: int, slot: int) -> Dictionary:
	var kind := str(t.get("kind", ""))
	var who_raw := str(t.get("who", "pip"))
	var pid := who_raw.to_lower().replace(" ", "_")
	var text := str(t.get("text", ""))
	var q := {"id": "d%d_%d_%d" % [day, slot, rng.randi() % 1000], "tpl": idx, "kind": kind, "who": pid,
		"who_name": person_name(pid, who_raw), "sparks": int(t.get("sparks", Dat.spark("request", 1))), "done": false,
		"day": day, "item": "", "count": 1, "cm": 0, "auto": false, "text": "", "reward": 0}
	match kind:
		"fish_size":
			var late := GameState.lanterns.has("harbour") and t.has("min_cm_late")
			var sp := _span(t.get("min_cm_late" if late else "min_cm", null), 30, 60)
			var cm := int(round(rng.randi_range(sp.x, sp.y) / 5.0)) * 5
			q.cm = cm
			q.auto = bool(t.get("auto_on_catch", false))
			q.text = _fmt(text, [cm])
			q.reward = _reward(t, float(cm - sp.x) / maxf(1.0, float(sp.y - sp.x)), rng)
		"fish":
			var ids: Array = _fish_pool(t)
			var ws: Array = []
			for k in ids: ws.append(4 - int(Dat.entry("FISH", str(k)).get("rarity", 1)))
			var fid := _pick_weighted(rng, ids, ws)
			if fid == "": return {}
			var fe := Dat.entry("FISH", fid)
			var fname := str(fe.get("name", fid.capitalize()))
			var vowel := fname.substr(0, 1).to_lower() in ["a", "e", "i", "o", "u"]
			var price := float(fe.get("price", 100))
			q.item = fid
			q.text = _fmt(text.replace("a %s", "an %s") if vowel else text, [fname])
			q.reward = _reward(t, 0.4, rng, price * float(t.get("reward_price_mult", 0.0)))
		"shore":
			var allowed: Array = []
			var listed: Variant = t.get("items", null)
			for k in Dat.d("SHORE").keys():
				var e2 := Dat.entry("SHORE", str(k))
				if bool(e2.get("bottle", false)) or int(e2.get("price", 0)) <= 0: continue
				if listed is Array and not (str(k) in listed): continue
				allowed.append(str(k))
			if allowed.is_empty(): return {}
			var ws2: Array = []
			for k in allowed: ws2.append(maxf(1.0, float(Dat.entry("SHORE", str(k)).get("weight", 1))))
			var sid := _pick_weighted(rng, allowed, ws2)
			var se := Dat.entry("SHORE", sid)
			var cs := _span(t.get("count", null), 2, 4)
			var n := rng.randi_range(cs.x, cs.y)
			q.item = sid
			q.count = n
			q.text = _fmt(text, [n, _plural(str(se.get("name", sid.capitalize())), n)])
			var frac := 0.5 * float(n - cs.x) / maxf(1.0, float(cs.y - cs.x)) + 0.5 * clampf(float(se.get("price", 50)) / 250.0, 0.0, 1.0)
			q.reward = _reward(t, frac, rng)
		"gold":
			q.text = _fmt(text, [])
			q.reward = _reward(t, 1.0, rng)
		_:
			return {}
	return q

# ------------------------------------------------------------------ checking and completing
static func _best_cm(id: String) -> float:
	var lg: Variant = GameState.fish_log.get(id, {})
	return float(lg.get("best_cm", 0.0)) if lg is Dictionary else 0.0

static func _cheapest_first(keys: Array) -> Array:
	keys.sort_custom(func(a: String, b: String) -> bool:
		var ga := 1 if Eco.is_gold(a) else 0
		var gb := 1 if Eco.is_gold(b) else 0
		if ga != gb: return ga < gb
		return Eco.unit_price(a) < Eco.unit_price(b))
	return keys

## {"ok": bool, "have": int, "need": int, "label": String, "take": {bag_key: count}}
static func progress(req: Dictionary) -> Dictionary:
	var kind := str(req.get("kind", ""))
	var res := {"ok": false, "have": 0, "need": 1, "label": "", "take": {}}
	match kind:
		"fish_size":
			var cm := int(req.get("cm", 0))
			if bool(req.get("auto", false)):
				res.label = "Catch one over %d cm. It is handed over by itself." % cm
			else:
				# no per-fish sizes in the bag: count a species when your record for it is long enough
				var keys: Array = []
				for k in GameState.bag.keys():
					var key := str(k)
					if not key.begins_with("fish:") or int(GameState.bag.get(k, 0)) <= 0: continue
					var sp := Eco.split(key)
					if bool(Dat.entry("FISH", str(sp.id)).get("junk", false)): continue
					if _best_cm(str(sp.id)) >= cm: keys.append(key)
				var have := 0
				for key in keys: have += int(GameState.bag.get(key, 0))
				res.have = have
				if not keys.is_empty():
					var pick: String = _cheapest_first(keys)[0]
					res.take = {pick: 1}
					res.ok = true
					res.label = "Ready: %s" % str(Eco.describe(pick).get("name", pick))
				else:
					res.label = "Nothing in your bag is that big yet."
		"fish":
			var fid := str(req.get("item", ""))
			var keys2: Array = []
			for key in ["fish:" + fid, "fish:" + fid + ":gold", "fish:" + fid + "_gold"]:
				if int(GameState.bag.get(key, 0)) > 0: keys2.append(key)
			var have2 := 0
			for key in keys2: have2 += int(GameState.bag.get(key, 0))
			res.have = have2
			if not keys2.is_empty():
				res.take = {_cheapest_first(keys2)[0]: 1}
				res.ok = true
				res.label = "Ready: you have one."
			else:
				res.label = "Not in your bag yet."
		"shore":
			var need := maxi(1, int(req.get("count", 1)))
			var key2 := "shore:" + str(req.get("item", ""))
			var have3 := int(GameState.bag.get(key2, 0))
			res.need = need
			res.have = mini(have3, need)
			res.ok = have3 >= need
			if res.ok: res.take = {key2: need}
			res.label = "Have %d of %d" % [res.have, need]
		"gold":
			var gk: Array = []
			for k in GameState.bag.keys():
				if Eco.is_gold(str(k)) and int(GameState.bag.get(k, 0)) > 0: gk.append(str(k))
			res.have = gk.size()
			if not gk.is_empty():
				res.take = {_cheapest_first(gk)[0]: 1}
				res.ok = true
				res.label = "Ready: a gold find."
			else:
				res.label = "No gold items yet."
	if bool(req.get("done", false)):
		res.ok = false
		res.label = "Done"
	return res

static func completable_count() -> int:
	var n := 0
	for r in GameState.requests:
		if r is Dictionary and progress(r).ok: n += 1
	return n

static func open_count() -> int:
	var n := 0
	for r in GameState.requests:
		if r is Dictionary and not bool(r.get("done", false)): n += 1
	return n

## Pays out and marks done. Returns the short result line.
static func _finish(req: Dictionary) -> String:
	var reward := int(req.get("reward", 0))
	var sp := int(req.get("sparks", 0)) + Eco.request_sparks
	GameState.add_coins(reward)
	if sp > 0: GameState.add_sparks(sp, "")
	req["done"] = true
	GameState.flags["requests_done"] = int(GameState.flags.get("requests_done", 0)) + 1
	var pid := str(req.get("who", ""))
	if pid != "" and GameState.has_method("add_friendship"):
		var table := Dat.d("PEOPLE")
		if table.is_empty() or table.has(pid):
			GameState.add_friendship(pid, friendship_points(), "request")
	GameState.catalog_changed.emit()
	GameState.save_soon()
	var who := str(req.get("who_name", pid.capitalize()))
	var extra := (", +%d spark%s" % [sp, "" if sp == 1 else "s"]) if sp > 0 else ""
	return "%s is happy. +%s%s." % [who, Yen.fmt(reward), extra]

## Hand in a request from the bag. Returns the result line, or "" when it could not be completed.
static func complete(req: Dictionary) -> String:
	if bool(req.get("done", false)): return ""
	var pr := progress(req)
	if not pr.ok: return ""
	for k in pr.take.keys():
		if not GameState.has_item(str(k), int(pr.take[k])): return ""
	for k in pr.take.keys():
		GameState.remove_item(str(k), int(pr.take[k]))
	return _finish(req)

## An auto size request met by a catch: take that fish from the bag and pay. "" if it no longer applies.
static func complete_auto(req: Dictionary, bag_key: String) -> String:
	if bool(req.get("done", false)) or not bool(req.get("auto", false)): return ""
	if not GameState.has_item(bag_key, 1): return ""
	GameState.remove_item(bag_key, 1)
	return _finish(req)
