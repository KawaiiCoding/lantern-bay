extends RefCounted
## Fish selection for the fishing system (GDD 5.1). Reads Data defensively: a designer may add,
## rename or drop fields at any time, so every lookup has a default.
##
## roll(spot_name, overrides, people) -> Dictionary
##   {id, name, cm, rarity, gold, price (yen, size + gold applied), trophy, body: Color, fin: Color, junk, size_t, min_cm, max_cm}

const RARITY_WEIGHT := {1: 60.0, 2: 24.0, 3: 7.0, 4: 1.6}
const SPOT_ALIAS := {"pier_end": "pier", "pier": "pier", "beach": "beach", "rocks": "rocks", "flats": "flats"}
const BIG_FISH_CM := 45.0          # "big fish" for the rain weight bonus

static func table(key: String) -> Dictionary:
	var v = Data.get(key)
	return v if typeof(v) == TYPE_DICTIONARY else {}

static func num(key: String, fallback: float) -> float:
	var v = Data.get(key)
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT: return float(v)
	return fallback

## Current rod stats (Data.ROD[rod_level]) with safe defaults.
static func rod() -> Dictionary:
	var rods := table("ROD")
	var lv := int(GameState.rod_level)
	var r = rods.get(lv, rods.get(str(lv), {}))
	if typeof(r) != TYPE_DICTIONARY: r = {}
	return {"bite_window": float(r.get("bite_window", 0.7)), "surge": float(r.get("surge", 1.0)),
		"rare_bonus": float(r.get("rare_bonus", 0.0))}

## "person:perk" -> GameState.has_perk(person, perk). Unknown API = locked.
static func has_perk(spec: String) -> bool:
	var parts := spec.split(":", true, 1)
	if parts.size() < 2 or not GameState.has_method("has_perk"): return false
	return bool(GameState.has_perk(parts[0], parts[1]))

static func pair(key: String, fallback: Vector2) -> Vector2:
	var v = Data.get(key)
	if typeof(v) == TYPE_ARRAY and v.size() >= 2: return Vector2(float(v[0]), float(v[1]))
	return fallback

## Island spot name -> FISH.spots id (inverts Data.FISH_SPOTS when present).
static func fish_spot_id(island_spot: String) -> String:
	var fs := table("FISH_SPOTS")
	for k in fs.keys():
		if str(fs[k]) == island_spot: return str(k)
	return str(SPOT_ALIAS.get(island_spot, island_spot))

static func perk(people: Node, perk_id: String) -> float:
	if is_instance_valid(people) and people.has_method("perk_value"):
		var v = people.perk_value(perk_id, 0.0)
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT: return float(v)
	return 0.0

static func _arr(f: Dictionary, key: String) -> Array:
	var v = f.get(key, [])
	if typeof(v) == TYPE_ARRAY: return v
	if typeof(v) == TYPE_STRING and v != "": return [v]
	return []

static func _size_range(f: Dictionary) -> Vector2:
	var s = f.get("size", [10, 30])
	if typeof(s) == TYPE_ARRAY and s.size() >= 2:
		var a := float(s[0]); var b := float(s[1])
		return Vector2(minf(a, b), maxf(maxf(a, b), minf(a, b) + 0.1))
	return Vector2(10, 30)

static func _color(v, fallback: Color) -> Color:
	if typeof(v) == TYPE_COLOR: return v
	if typeof(v) == TYPE_STRING and Color.html_is_valid(v): return Color(v)
	return fallback

## Weighted candidates for a spot right now. Returns Array of [id, weight].
static func candidates(spot_name: String, people: Node = null) -> Array:
	var spot: String = fish_spot_id(spot_name)
	var slot := str(GameState.time_slot())
	var weather := str(GameState.weather())
	var rare_bonus: float = rod().rare_bonus + perk(people, "rare_fish_bonus")
	var out := []
	var fish := table("FISH")
	for id in fish.keys():
		var f = fish[id]
		if typeof(f) != TYPE_DICTIONARY: continue
		var spots := _arr(f, "spots")
		if not spots.is_empty() and not (spot in spots): continue
		var slots := _arr(f, "slots")
		if not slots.is_empty() and not (slot in slots): continue
		var weathers := _arr(f, "weather")
		if not weathers.is_empty() and not (weather in weathers): continue
		var lantern := str(f.get("needs_lantern", ""))
		if lantern != "" and not GameState.lanterns.has(lantern): continue
		if bool(f.get("low_tide", false)) and GameState.has_method("low_tide") and not GameState.low_tide(): continue
		var need_perk := str(f.get("needs_perk", ""))
		if need_perk != "" and not has_perk(need_perk): continue
		var rarity := clampi(int(f.get("rarity", 1)), 1, 4)
		var rw := table("RARITY_WEIGHT")
		var w := float(rw.get(rarity, RARITY_WEIGHT.get(rarity, 10.0)))
		if bool(f.get("junk", false)): w = num("JUNK_WEIGHT", w * 0.35)
		if f.has("weight"): w = float(f.get("weight", w))
		if rarity >= 3: w *= 1.0 + maxf(rare_bonus, 0.0)
		if weather == "rain" and _size_range(f).y >= num("RAIN_BIG_MIN_CM", BIG_FISH_CM): w *= num("RAIN_BIG_WEIGHT_MULT", 1.5)
		if w > 0.0: out.append([str(id), w])
	return out

static func roll(spot_name: String, overrides: Dictionary = {}, people: Node = null) -> Dictionary:
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var fish := table("FISH")
	var id := str(overrides.get("fish", ""))
	if id == "" or not fish.has(id):
		var c := candidates(spot_name, people)
		if c.is_empty():   # nothing matches now: fall back to anything at this spot, then anything
			for k in fish.keys():
				if typeof(fish[k]) == TYPE_DICTIONARY: c.append([str(k), 1.0])
		var total := 0.0
		for e in c: total += float(e[1])
		var r := rng.randf() * total
		id = ""
		for e in c:
			r -= float(e[1])
			if r <= 0.0: id = e[0]; break
		if id == "" and not c.is_empty(): id = c[c.size() - 1][0]
	var f: Dictionary = fish.get(id, {}) if typeof(fish.get(id, {})) == TYPE_DICTIONARY else {}
	var sr := _size_range(f)
	# size curve (Data.SIZE_CURVE): >1 skews small so records stay rare; rain flattens it (bigger fish)
	var curve := num("SIZE_CURVE_RAIN", 1.2) if str(GameState.weather()) == "rain" else num("SIZE_CURVE", 1.8)
	var t := pow(rng.randf(), maxf(curve, 0.1))
	if overrides.get("big", "") != "": t = rng.randf_range(0.93, 1.0)
	var cm := snappedf(lerpf(sr.x, sr.y, t), 0.1)
	var junk := bool(f.get("junk", false))
	var gold := not junk and rng.randf() < num("GOLD_CHANCE", 0.01)
	if overrides.get("gold", "") != "": gold = overrides.get("gold") != "0"
	var pm := pair("PRICE_SIZE_MULT", Vector2(1.0, 1.0))
	var price := int(round(float(f.get("price", 10)) * lerpf(pm.x, pm.y, t)))
	if gold: price *= int(num("GOLD_PRICE_MULT", 5))
	return {"id": id, "name": str(f.get("name", id.capitalize() if id != "" else "Mystery Fish")), "cm": cm,
		"rarity": clampi(int(f.get("rarity", 1)), 1, 4), "gold": gold, "price": price,
		"trophy": not junk and t >= num("TROPHY_FRACTION", 0.9),
		"body": _color(f.get("body", ""), Color("a9c4d6")), "fin": _color(f.get("fin", ""), Color("6f8fa8")),
		"junk": junk, "size_t": clampf(t, 0.0, 1.0), "min_cm": sr.x, "max_cm": sr.y}
