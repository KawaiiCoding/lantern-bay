extends RefCounted
## Pure shop logic (no UI): what an item is worth, selling, buying, wearing cosmetics, Pip's daily special.
## Bag keys: "fish:<id>", "fish:<id>:gold", "shore:<id>", "shore:<id>:gold", "flower:<id>", "treat:<id>".
## (the "_gold" suffix is accepted on reading too). Perks from the People system are pushed in with set_mods().

const Dat := preload("res://scripts/systems/town/dat.gd")

const SPECIAL_SALT := 77000

static var discount := 0.0       # fraction off buy prices (shop_discount)
static var gold_bonus := 0.0     # extra fraction on gold items (gold_bonus)
static var sell_bonus := 0.0     # extra fraction on everything sold (sell_bonus)
static var special_bonus := 0.0  # added to the daily special multiplier (special_bonus)
static var request_sparks := 0   # extra sparks per finished request (spark_bonus)

static func set_mods(disc: float, gold: float, sell := 0.0, special := 0.0, req_sparks := 0) -> void:
	discount = clampf(disc, 0.0, 0.6)
	gold_bonus = clampf(gold, 0.0, 3.0)
	sell_bonus = clampf(sell, 0.0, 2.0)
	special_bonus = clampf(special, 0.0, 5.0)
	request_sparks = clampi(req_sparks, 0, 10)

static func gold_mult() -> int:
	return maxi(1, Dat.i("GOLD_PRICE_MULT", 5))

# ------------------------------------------------------------------ night market
const NIGHT_FROM := 21.0         # hour the market opens (GDD 5.4: 21:00-24:00, once the hill lantern is lit)
const NIGHT_ITEMS := ["shore:star_stone", "shore:moon_shell"]

static func night_mult() -> float:
	return maxf(1.0, Dat.f("NIGHT_MARKET_MULT", 1.5))

## True from 21:00 to midnight after the hill lantern is lit.
static func night_market_open() -> bool:
	return GameState.lanterns.has("hill") and GameState.hour() >= NIGHT_FROM

## Rare fish (rarity 3+), star stones, moon shells and anything gold pay the night market bonus.
static func night_item(kind: String, id: String, gold: bool) -> bool:
	if gold: return true
	if kind == "fish": return int(Dat.entry("FISH", id).get("rarity", 1)) >= 3
	return (kind + ":" + id) in NIGHT_ITEMS

# ------------------------------------------------------------------ keys
static func is_gold(key: String) -> bool:
	return (key.ends_with(":gold") or key.ends_with("_gold")) and (key.begins_with("fish:") or key.begins_with("shore:"))

## Split a bag key into kind / id / gold flag.
static func split(key: String) -> Dictionary:
	var p := key.split(":", true, 1)
	var rest: String = p[1] if p.size() > 1 else ""
	var gold := false
	if rest.ends_with(":gold"):
		rest = rest.trim_suffix(":gold"); gold = true
	elif rest.ends_with("_gold") and (p[0] == "fish" or p[0] == "shore"):
		rest = rest.trim_suffix("_gold"); gold = true
	return {"kind": p[0], "id": rest, "gold": gold}

static func gold_key(key: String) -> String:
	return key if is_gold(key) else key + ":gold"

static func shore_icon(id: String) -> String:
	if id.contains("bottle"): return "bottle"
	if id.contains("moon"): return "moon"
	if id.contains("star"): return "star"
	if id.contains("glass"): return "glass"
	if id.contains("wood"): return "wood"
	if id.contains("shell") or id.contains("sand_dollar"): return "shell"
	return "dot"

# ------------------------------------------------------------------ Pip's daily special
## Today's special species ("" until the player has caught something). Chosen once per day among species
## already caught and remembered in GameState.flags["special"].
static func special_id() -> String:
	var st: Variant = GameState.flags.get("special", null)
	if st is Dictionary and int(st.get("day", 0)) == GameState.day and str(st.get("id", "")) != "":
		return str(st.get("id", ""))
	var pool: Array = []
	for k in GameState.fish_log.keys():
		var e := Dat.entry("FISH", str(k))
		var lg: Variant = GameState.fish_log[k]
		if e.is_empty() or bool(e.get("junk", false)): continue
		if lg is Dictionary and int(lg.get("count", 0)) > 0: pool.append(str(k))
	if pool.is_empty(): return ""
	pool.sort()
	var rng := GameState.day_rng(SPECIAL_SALT)
	var id: String = pool[rng.randi() % pool.size()]
	GameState.flags["special"] = {"day": GameState.day, "id": id}
	return id

static func special_mult() -> float:
	return maxf(1.0, Dat.f("DAILY_SPECIAL_MULT", 2.0) + special_bonus)

# ------------------------------------------------------------------ describing and selling
## Everything the UI needs to draw one bag line: name, unit sell price (0 = not sold here), icon + colours.
static func describe(key: String) -> Dictionary:
	var sp := split(key)
	var kind: String = sp.kind
	var id: String = sp.id
	var gold: bool = sp.gold
	var out := {"kind": kind, "id": id, "gold": gold, "name": id.replace("_", " ").capitalize(), "price": 0, "icon": "dot",
		"c1": Color("c9b08a"), "c2": Color("9a7f5c"), "special": false}
	var base := 0.0
	match kind:
		"fish":
			var e := Dat.entry("FISH", id)
			out.name = str(e.get("name", out.name))
			base = float(e.get("price", 0))
			if gold: base *= gold_mult()
			out.icon = "fish"
			out.c1 = Dat.col(e.get("body", "a9c4d6"))
			out.c2 = Dat.col(e.get("fin", "6f8fa8"))
			if base > 0 and id == special_id():
				base *= special_mult()
				out.special = true
		"shore":
			var e2 := Dat.entry("SHORE", id)
			out.name = str(e2.get("name", out.name))
			base = float(e2.get("price", 0))
			if gold and base > 0: base = float(Dat.i("GOLD_SHELL_PRICE", int(base) * gold_mult()))
			out.icon = shore_icon(id)
			out.c1 = Dat.col(e2.get("color", "fbf3e6"))
			out.c2 = out.c1.darkened(0.25)
		"flower":
			var e4 := Dat.entry("ITEMS", key)
			out.name = str(e4.get("name", out.name))
			base = float(e4.get("price", 0))
			out.icon = "flower"
			out.c1 = Dat.col(e4.get("color", "f2a0b8"))
			out.c2 = out.c1.darkened(0.25)
		"treat":
			var e3 := Dat.entry("SHOP", key)
			out.name = str(e3.get("name", out.name))
			out.icon = "treat"
			out.c1 = Color("e7c48f"); out.c2 = Color("b98a52")
	if gold:
		out.name = "Gold " + str(out.name)
		out.c1 = Color("f2c14e"); out.c2 = Color("c9902c")
		base *= 1.0 + gold_bonus
	base *= 1.0 + sell_bonus
	if base > 0.0 and night_market_open() and night_item(kind, id, gold):
		base *= night_mult()
		out["night"] = true
	out.price = int(round(base))
	return out

static func unit_price(key: String) -> int:
	return int(describe(key).get("price", 0))

## Sell up to n of a bag key. Returns the yen earned (0 when nothing was sold).
static func sell(key: String, n: int) -> int:
	var price := unit_price(key)
	if price <= 0: return 0
	n = mini(n, int(GameState.bag.get(key, 0)))
	if n <= 0: return 0
	if not GameState.remove_item(key, n): return 0
	var total := price * n
	GameState.add_coins(total)
	GameState.flags["sold_any"] = true
	GameState.save_soon()
	return total

## Sellable bag keys: fish first, then shore finds, then flowers; most valuable first.
static func sellable_keys() -> Array:
	var keys: Array = []
	for k in GameState.bag.keys():
		var key := str(k)
		if int(GameState.bag.get(k, 0)) <= 0: continue
		if not (key.begins_with("fish:") or key.begins_with("shore:") or key.begins_with("flower:")): continue
		if unit_price(key) <= 0: continue
		keys.append(key)
	var rank := func(s: String) -> int:
		return 0 if s.begins_with("fish:") else (1 if s.begins_with("shore:") else 2)
	keys.sort_custom(func(a: String, b: String) -> bool:
		var fa: int = rank.call(a); var fb: int = rank.call(b)
		if fa != fb: return fa < fb
		var pa := unit_price(a); var pb := unit_price(b)
		if pa != pb: return pa > pb
		return a < b)
	return keys

# ------------------------------------------------------------------ buying
static func buy_price(id: String) -> int:
	var base := int(Dat.entry("SHOP", id).get("price", 0))
	return maxi(1, int(round(base * (1.0 - discount)))) if base > 0 else 0

static func _lit(id: String) -> bool:
	return GameState.lanterns.has(id)

## Listed in the shop right now? (gift-only items are never listed; lantern-gated items appear once it is lit)
static func listed(id: String) -> bool:
	var e := Dat.entry("SHOP", id)
	if e.is_empty() or bool(e.get("hidden", false)): return false
	var nl := str(e.get("needs_lantern", ""))
	if nl != "" and not _lit(nl): return false
	var lan := Dat.d("LANTERNS")
	for lid in lan.keys():
		var info: Variant = lan[lid]
		if not (info is Dictionary): continue
		var shop_ids: Variant = info.get("unlock_shop", [])
		if shop_ids is Array and id in shop_ids and not _lit(str(lid)): return false
	return true

static func shop_ids() -> Array:
	var ids: Array = []
	for k in Dat.d("SHOP").keys():
		if listed(str(k)): ids.append(str(k))
	var order := {"treat": 0, "rod": 1, "cosmetic": 2}
	ids.sort_custom(func(a, b) -> bool:
		var ea := Dat.entry("SHOP", str(a)); var eb := Dat.entry("SHOP", str(b))
		var oa: int = order.get(str(ea.get("kind", "")), 3); var ob: int = order.get(str(eb.get("kind", "")), 3)
		if oa != ob: return oa < ob
		var la := int(ea.get("level", 0)); var lb := int(eb.get("level", 0))
		if la != lb: return la < lb
		var pa := int(ea.get("price", 0)); var pb := int(eb.get("price", 0))
		if pa != pb: return pa < pb
		return str(a) < str(b))
	return ids

static func owned(id: String) -> bool:
	var e := Dat.entry("SHOP", id)
	match str(e.get("kind", "")):
		"rod": return GameState.rod_level >= int(e.get("level", 2))
		"cosmetic": return GameState.cosmetics.has(id)
	return false

## "" when the item can be bought right now, else a short reason.
static func lock_reason(id: String) -> String:
	var e := Dat.entry("SHOP", id)
	if str(e.get("kind", "")) == "rod":
		var lv := int(e.get("level", 2))
		if GameState.rod_level < lv - 1:
			var prev := ""
			for k in Dat.d("SHOP").keys():
				var pe := Dat.entry("SHOP", str(k))
				if str(pe.get("kind", "")) == "rod" and int(pe.get("level", 0)) == lv - 1:
					prev = str(pe.get("name", ""))
			return "Needs the %s first." % prev if prev != "" else "Needs the previous rod first."
	return ""

static func _equipped() -> Dictionary:
	var v: Variant = GameState.cosmetics.get("equipped", null)
	if not (v is Dictionary):
		v = {}
		GameState.cosmetics["equipped"] = v
	return v

static func is_equipped(id: String) -> bool:
	var e := Dat.entry("SHOP", id)
	return str(_equipped().get(str(e.get("slot", "misc")), "")) == id

static func equip(id: String, on := true) -> void:
	var e := Dat.entry("SHOP", id)
	var slot := str(e.get("slot", "misc"))
	var eq := _equipped()
	if on:
		eq[slot] = id
	elif str(eq.get(slot, "")) == id:
		eq.erase(slot)
	GameState.catalog_changed.emit()
	GameState.save_soon()

## Buy one. Returns {"ok": bool, "msg": String}.
static func buy(id: String) -> Dictionary:
	var e := Dat.entry("SHOP", id)
	if e.is_empty() or not listed(id):
		return {"ok": false, "msg": "Pip does not stock that."}
	var kind := str(e.get("kind", ""))
	var name := str(e.get("name", id))
	if owned(id):
		return {"ok": false, "msg": "You already have the %s." % name}
	var why := lock_reason(id)
	if why != "":
		return {"ok": false, "msg": why}
	var price := buy_price(id)
	if GameState.coins < price or not GameState.spend(price):
		return {"ok": false, "msg": "Pip taps the counter. Not quite enough yet."}
	match kind:
		"rod":
			GameState.rod_level = clampi(int(e.get("level", 2)), 1, 3)
		"cosmetic":
			GameState.cosmetics[id] = true
			equip(id, true)
		_:
			GameState.add_item(id, 1)
	GameState.save_soon()
	return {"ok": true, "msg": "%s, yours." % name}
