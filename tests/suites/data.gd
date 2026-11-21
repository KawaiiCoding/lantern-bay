extends "res://tests/suite.gd"
## Data integrity: every table in Data is internally consistent, references things that exist, and is read by code.

func _hex_ok(v) -> bool:
	return typeof(v) == TYPE_STRING and Color.html_is_valid(v)

func _fish_spot_ids() -> Array:
	var fs := data_dict("FISH_SPOTS")
	return fs.keys() if not fs.is_empty() else FISHING_SPOTS

func _lantern_ids() -> Array:
	return data_dict("LANTERNS").keys()

## List of {level, id, value, text, ...} perks for a person, from either {level: [..]} or [{level, id}] shapes.
func perk_list(p: Dictionary) -> Array:
	var out: Array = []
	var perks = p.get("perks", [])
	if typeof(perks) == TYPE_ARRAY:
		for pk in perks:
			if typeof(pk) == TYPE_DICTIONARY: out.append(pk)
	elif typeof(perks) == TYPE_DICTIONARY:
		for lv in perks.keys():
			if typeof(perks[lv]) == TYPE_ARRAY:
				for pk in perks[lv]:
					if typeof(pk) == TYPE_DICTIONARY:
						var c: Dictionary = pk.duplicate()
						c["level"] = int(lv)
						out.append(c)
	return out

func perk_ids_known() -> Array:
	var ids: Array = []
	for pid in people_table().keys():
		for pk in perk_list(people_table()[pid]):
			ids.append("%s:%s" % [pid, str(pk.get("id", ""))])
	return ids

## Fish catchable under the given conditions (mirrors the GDD roll rules, reads only Data).
func fish_catchable(spot: String, slot: String, wx: String, lit: Array, perks: Array, tide: bool, allow_junk := false) -> Array:
	var out: Array = []
	var fish := data_dict("FISH")
	for id in fish.keys():
		var f: Dictionary = fish[id]
		if bool(f.get("junk", false)) and not allow_junk: continue
		if not (spot in f.get("spots", [])): continue
		var slots: Array = f.get("slots", [])
		if not slots.is_empty() and not (slot in slots): continue
		var wl: Array = f.get("weather", [])
		if not wl.is_empty() and not (wx in wl): continue
		var nl := str(f.get("needs_lantern", ""))
		if nl != "" and not (nl in lit): continue
		var np := str(f.get("needs_perk", ""))
		if np != "" and not (np in perks): continue
		if bool(f.get("low_tide", false)) and not tide: continue
		out.append(str(id))
	return out

# ------------------------------------------------------------------ FISH
func t_fish_table() -> void:
	var fish := data_dict("FISH")
	ok(fish.size() > 0, "Data.FISH is empty")
	var junk := 0
	for id in fish.keys():
		if bool(fish[id].get("junk", false)): junk += 1
	if fish.size() - junk != 18: warn("GDD 5.1: 18 species + the Old Boot; Data.FISH has %d species + %d junk" % [fish.size() - junk, junk])
	var lanterns := data_dict("LANTERNS")
	var spot_ids := _fish_spot_ids()
	var perks := perk_ids_known()
	var names := {}
	for id in fish.keys():
		var f: Dictionary = fish[id]
		var w := "FISH.%s" % id
		for k in ["name", "spots", "slots", "weather", "size", "rarity", "price", "body", "fin"]:
			if not f.has(k): fail("%s is missing '%s'" % [w, k])
		var nm := str(f.get("name", ""))
		ok(nm != "", w + " has an empty name")
		if names.has(nm): fail("%s: display name '%s' duplicates %s" % [w, nm, names[nm]])
		names[nm] = id
		var spots = f.get("spots", [])
		ok(typeof(spots) == TYPE_ARRAY and not spots.is_empty(), w + ": spots must be a non-empty Array")
		if typeof(spots) == TYPE_ARRAY:
			for s in spots:
				ok(str(s) in spot_ids, "%s: spot '%s' is not a fishing spot id (%s)" % [w, str(s), ", ".join(spot_ids)])
		for s in f.get("slots", []): ok(str(s) in SLOTS, "%s: bad slot '%s'" % [w, str(s)])
		for s in f.get("weather", []): ok(str(s) in WEATHERS, "%s: bad weather '%s'" % [w, str(s)])
		var sz = f.get("size", [])
		if typeof(sz) == TYPE_ARRAY and sz.size() == 2:
			ok(float(sz[0]) > 0.0 and float(sz[0]) < float(sz[1]), "%s: size range must satisfy 0 < min < max, got %s" % [w, str(sz)])
		else:
			fail(w + ": size must be [min, max]")
		var rarity := int(f.get("rarity", 0))
		ok(rarity >= 1 and rarity <= 4, "%s: rarity %d outside 1..4" % [w, rarity])
		ok(int(f.get("price", 0)) > 0, "%s: price must be positive (got %s)" % [w, str(f.get("price"))])
		ok(_hex_ok(f.get("body")), "%s: body colour '%s' is not a hex colour" % [w, str(f.get("body"))])
		ok(_hex_ok(f.get("fin")), "%s: fin colour '%s' is not a hex colour" % [w, str(f.get("fin"))])
		var nl := str(f.get("needs_lantern", ""))
		if nl != "": ok(lanterns.has(nl), "%s: needs_lantern '%s' is not in Data.LANTERNS" % [w, nl])
		var np := str(f.get("needs_perk", ""))
		if np != "" and not people_table().is_empty(): ok(np in perks, "%s: needs_perk '%s' is not a perk of any person in PEOPLE" % [w, np])
		if f.has("weight"): ok(float(f.weight) > 0.0, w + ": weight must be positive")
		if bool(f.get("low_tide", false)):
			var sl: Array = f.get("slots", [])
			ok(sl.is_empty() or "morning" in sl or "evening" in sl, "%s: low_tide fish with slots %s can never bite (low tide is morning/evening)" % [w, str(sl)])
		ok(str(f.get("hint", "x")) != "", w + ": empty hint")
	# price bands (GDD 6, yen): commons 120-240, uncommon 450-900, rare 1500-3000, legendary 5000
	for id in fish.keys():
		var f2: Dictionary = fish[id]
		if bool(f2.get("junk", false)): continue
		var pr := int(f2.get("price", 0)); var ra := int(f2.get("rarity", 1))
		if ra == 1 and (pr < 100 or pr > 260): warn("FISH.%s is common but sells for %d (GDD 6: 120-240)" % [id, pr])
		if ra == 2 and (pr < 400 or pr > 950): warn("FISH.%s is uncommon but sells for %d (GDD 6: 450-900)" % [id, pr])
		if ra == 3 and (pr < 1400 or pr > 3200): warn("FISH.%s is rare but sells for %d (GDD 6: 1,500-3,000)" % [id, pr])
	ok(int(data_const("GOLD_PRICE_MULT", 5)) == 5, "GDD: gold sells x5, Data.GOLD_PRICE_MULT is %s" % str(data_const("GOLD_PRICE_MULT")))
	near(float(data_const("GOLD_CHANCE", 0.01)), 0.01, 0.0001, "GDD: 1% gold variants, Data.GOLD_CHANCE")
	var psm = data_const("PRICE_SIZE_MULT", [1.0, 1.0])
	ok(typeof(psm) == TYPE_ARRAY and psm.size() == 2 and float(psm[0]) > 0.0 and float(psm[0]) <= float(psm[1]), "PRICE_SIZE_MULT must be [low, high] with 0 < low <= high")

func t_fish_spots_and_gates() -> void:
	var fs := data_dict("FISH_SPOTS")
	if fs.is_empty(): skip("Data.FISH_SPOTS not defined"); return
	for id in fs.keys(): ok(str(fs[id]) in SPOT_NAMES, "FISH_SPOTS.%s -> '%s' is not a valid island spot name" % [id, str(fs[id])])
	var gates := data_dict("SPOT_LANTERN")
	var lan := _lantern_ids()
	for sp in gates.keys():
		ok(str(sp) in SPOT_NAMES, "SPOT_LANTERN key '%s' is not a valid island spot name" % str(sp))
		ok(str(gates[sp]) in lan, "SPOT_LANTERN.%s -> '%s' is not in Data.LANTERNS" % [str(sp), str(gates[sp])])
	var odds := data_dict("WEATHER_ODDS")
	if not odds.is_empty():
		var sum := 0.0
		for k in odds.keys():
			ok(str(k) in WEATHERS, "WEATHER_ODDS has unknown weather '%s'" % str(k))
			sum += float(odds[k])
		near(sum, 1.0, 0.001, "WEATHER_ODDS must sum to 1")
		for w in WEATHERS: ok(odds.has(w), "WEATHER_ODDS is missing '%s'" % w)
	var wc = data_const("WEATHER_FOG_MAX_GAP", 14)
	ok(int(wc) >= 4, "WEATHER_FOG_MAX_GAP is %s (fog must not be forced every few days)" % str(wc))

func t_fish_catchable_everywhere() -> void:
	# GDD 11.7: every spot x slot x weather has a non-junk fish. Pier and beach from day 1; rocks once the harbour
	# lantern is lit; flats at low tide with the moss perk (low tide is morning or evening).
	var bad: Array = []
	for spot in ["pier", "beach"]:
		for slot in SLOTS:
			for wx in WEATHERS:
				if fish_catchable(spot, slot, wx, [], [], false).is_empty(): bad.append("%s/%s/%s" % [spot, slot, wx])
	ok(bad.is_empty(), "no catchable non-junk fish at (no lantern lit): " + ", ".join(bad.slice(0, 8)) + (" ..." if bad.size() > 8 else ""))
	var rocks_bad: Array = []
	for slot in SLOTS:
		for wx in WEATHERS:
			if fish_catchable("rocks", slot, wx, ["harbour"], [], false).is_empty(): rocks_bad.append("%s/%s" % [slot, wx])
	ok(rocks_bad.is_empty(), "no catchable non-junk fish at the rocks (harbour lit): " + ", ".join(rocks_bad.slice(0, 8)))
	if "flats" in _fish_spot_ids():
		var flats_bad: Array = []
		for slot in ["morning", "evening"]:
			for wx in WEATHERS:
				if fish_catchable("flats", slot, wx, ["harbour"], perk_ids_known(), true).is_empty(): flats_bad.append("%s/%s" % [slot, wx])
		ok(flats_bad.is_empty(), "no catchable non-junk fish on the flats at low tide with perks: " + ", ".join(flats_bad.slice(0, 8)))
	# day 1 is sunny; the first fishing session must have something besides sardines to find
	var morning := fish_catchable("pier", "morning", "sunny", [], [], false)
	ok(morning.size() >= 2, "pier / morning / sunny should offer at least 2 species for the first session, offers %s" % str(morning))

func t_fish_every_species_reachable() -> void:
	var fish := data_dict("FISH")
	var all_lit := _lantern_ids()
	var perks := perk_ids_known()
	for id in fish.keys():
		var found := false
		for spot in _fish_spot_ids():
			for slot in SLOTS:
				for wx in WEATHERS:
					var tide: bool = slot == "morning" or slot == "evening"
					if str(id) in fish_catchable(spot, slot, wx, all_lit, perks, tide, true): found = true
		ok(found, "FISH.%s can never be caught (no spot/slot/weather/lantern/perk combination allows it)" % id)

# ------------------------------------------------------------------ CATS
func t_cats_table() -> void:
	var cats := data_dict("CATS")
	var fish := data_dict("FISH")
	var shop := data_dict("SHOP")
	var lanterns := data_dict("LANTERNS")
	var gates := data_dict("SPOT_LANTERN")
	ok(cats.size() > 0, "Data.CATS is empty")
	if cats.size() != 10: warn("GDD 5.2 promises 10 cats, Data.CATS has %d" % cats.size())
	var personalities := ["Shy", "Bold", "Lazy", "Curious", "Grumpy"]
	var names := {}
	var day_one := 0
	for id in cats.keys():
		var c: Dictionary = cats[id]
		var w := "CATS.%s" % id
		for k in ["name", "main", "personality", "haunts", "favourite", "secret", "rumour", "shy", "scares"]:
			if not c.has(k): fail("%s is missing '%s'" % [w, k])
		var nm := str(c.get("name", ""))
		ok(nm != "", w + ": empty name")
		if names.has(nm): fail("%s: name '%s' duplicates %s" % [w, nm, names[nm]])
		names[nm] = id
		ok(str(c.get("personality", "")) in personalities, "%s: personality '%s' not in %s" % [w, str(c.get("personality")), str(personalities)])
		ok(_hex_ok(c.get("main")), "%s: main colour '%s' invalid" % [w, str(c.get("main"))])
		var patch = c.get("patch", "")
		ok(str(patch) == "" or _hex_ok(patch), "%s: patch colour '%s' invalid" % [w, str(patch)])
		var haunts = c.get("haunts", {})
		ok(typeof(haunts) == TYPE_DICTIONARY and not haunts.is_empty(), w + ": haunts must be a non-empty Dictionary")
		if typeof(haunts) == TYPE_DICTIONARY:
			for slot in haunts.keys():
				ok(str(slot) in SLOTS, "%s: haunt slot '%s' is not a time slot" % [w, str(slot)])
				ok(str(haunts[slot]) in SPOT_NAMES, "%s: haunt '%s' (%s) is not a valid spot name" % [w, str(haunts[slot]), str(slot)])
		for key in ["rain_spot", "sun_spot", "secret_spot"]:
			if c.has(key): ok(str(c[key]) in SPOT_NAMES, "%s: %s '%s' is not a valid spot name" % [w, key, str(c[key])])
		for wx in c.get("weather_only", []): ok(str(wx) in WEATHERS, "%s: weather_only '%s' is not a weather" % [w, str(wx)])
		var nl := str(c.get("needs_lantern", ""))
		if nl != "": ok(lanterns.has(nl), "%s: needs_lantern '%s' is not in Data.LANTERNS" % [w, nl])
		if nl == "": day_one += 1
		var fav := str(c.get("favourite", ""))
		ok(item_problem(fav) == "", "%s: favourite '%s' invalid (%s)" % [w, fav, item_problem(fav)])
		if fav.begins_with("fish:") and fish.has(fav.substr(5)):
			ok(not bool(fish[fav.substr(5)].get("junk", false)), "%s: favourite is junk" % w)
		if fav.begins_with("treat:"): ok(shop.has(fav), "%s: favourite treat '%s' is not sold in Data.SHOP" % [w, fav])
		if c.has("gift"): ok(item_problem(str(c.gift)) == "", "%s: gift '%s' invalid (%s)" % [w, str(c.gift), item_problem(str(c.gift))])
		if c.has("treat_needs_pets"): ok(int(c.treat_needs_pets) >= 1 and int(c.treat_needs_pets) < cats.size(), "%s: treat_needs_pets %s is not achievable" % [w, str(c.treat_needs_pets)])
		if c.has("nap_skip_hours"): ok(float(c.nap_skip_hours) > 0.0 and float(c.nap_skip_hours) <= 6.0, "%s: nap_skip_hours %s out of range" % [w, str(c.nap_skip_hours)])
		ok(str(c.get("secret", "")) != "", w + ": empty secret")
		ok(str(c.get("rumour", "")) != "", w + ": empty rumour (shown for unknown cats)")
		ok(typeof(c.get("shy", false)) == TYPE_BOOL and typeof(c.get("scares", false)) == TYPE_BOOL, w + ": shy/scares must be bool")
		# a cat that haunts a gated spot must stay hidden until that gate's lantern is lit
		if typeof(haunts) == TYPE_DICTIONARY:
			var spots: Array = haunts.values()
			if c.has("rain_spot"): spots.append(c.rain_spot)
			if c.has("sun_spot"): spots.append(c.sun_spot)
			for sp in spots:
				if gates.has(str(sp)) and str(c.get("needs_lantern", "")) not in [str(gates[str(sp)]), "hill", "lighthouse"]:
					fail("%s haunts '%s' (gated by the %s lantern) but needs_lantern is '%s': the player cannot reach it on day 1" % [w, str(sp), str(gates[str(sp)]), nl])
	if cats.size() > 0 and int(data_const("CAT_MAX_HEARTS", 5)) != 5: warn("GDD: trust 0-5 hearts; CAT_MAX_HEARTS is %s" % str(data_const("CAT_MAX_HEARTS")))
	if day_one != 6: warn("GDD 5.2: 6 cats are available from day 1; %d have no needs_lantern" % day_one)
	var cap := int(data_const("CAT_DAILY_HEART_CAP", 3))
	ok(cap >= 2 and cap <= 4, "CAT_DAILY_HEART_CAP is %d (GDD: at most 3 hearts per cat per day)" % cap)

func t_cat_favourites_obtainable() -> void:
	var cats := data_dict("CATS")
	var all_lit := _lantern_ids()
	var perks := perk_ids_known()
	for id in cats.keys():
		var fav := str(cats[id].get("favourite", ""))
		if fav.begins_with("fish:"):
			var fid := fav.substr(5)
			var found := false
			for spot in _fish_spot_ids():
				for slot in SLOTS:
					for wx in WEATHERS:
						if fid in fish_catchable(spot, slot, wx, all_lit, perks, true): found = true
			ok(found, "CATS.%s favourite %s can never be caught" % [id, fav])

# ------------------------------------------------------------------ SHORE / SHOP / ROD / LANTERNS / REQUESTS
func t_shore_table() -> void:
	var shore := data_dict("SHORE")
	ok(shore.size() > 0, "Data.SHORE is empty")
	var wsum := {"beach": 0, "flats": 0}
	for id in shore.keys():
		var s: Dictionary = shore[id]
		var w := "SHORE.%s" % id
		ok(str(s.get("name", "")) != "", w + ": empty name")
		ok(str(s.get("where", "")) in ["beach", "flats"], "%s: where '%s' must be beach or flats" % [w, str(s.get("where"))])
		ok(int(s.get("weight", 0)) > 0, w + ": weight must be positive")
		var price := int(s.get("price", -1))
		if bool(s.get("bottle", false)): ok(price >= 0, w + ": price must be >= 0")
		else: ok(price > 0, "%s: price must be positive (got %d)" % [w, price])
		ok(_hex_ok(s.get("color")), "%s: colour '%s' invalid" % [w, str(s.get("color"))])
		if wsum.has(str(s.get("where", ""))): wsum[str(s.where)] += int(s.get("weight", 0))
	ok(wsum.beach > 0, "no beach items with a weight")
	ok(wsum.flats > 0, "no tide flats items with a weight")
	ok(int(data_const("SHORE_BEACH_DAILY", 14)) == 14, "GDD: 14 beach items per morning, Data says %s" % str(data_const("SHORE_BEACH_DAILY")))
	ok(int(data_const("SHORE_FLATS_DAILY", 6)) == 6, "GDD: 6 flats items per low tide, Data says %s" % str(data_const("SHORE_FLATS_DAILY")))
	near(float(data_const("SHORE_GOLD_CHANCE", 0.02)), 0.02, 0.0001, "GDD: 2% gold shells, Data.SHORE_GOLD_CHANCE")
	var notes = data_const("BOTTLE_NOTES", [])
	if typeof(notes) == TYPE_ARRAY:
		ok(notes.size() >= 12, "GDD: 12 bottle notes, Data.BOTTLE_NOTES has %d" % notes.size())
		for i in notes.size(): ok(str(notes[i]).length() > 10, "BOTTLE_NOTES[%d] is empty" % i)

func t_shop_table() -> void:
	var shop := data_dict("SHOP")
	ok(shop.size() > 0, "Data.SHOP is empty")
	var kinds := ["treat", "rod", "cosmetic"]
	var lan := _lantern_ids()
	for id in shop.keys():
		var s: Dictionary = shop[id]
		var w := "SHOP.%s" % id
		ok(str(s.get("name", "")) != "", w + ": empty name")
		ok(int(s.get("price", 0)) > 0, "%s: price must be positive" % w)
		var kind := str(s.get("kind", ""))
		ok(kind in kinds, "%s: kind '%s' not in %s" % [w, kind, str(kinds)])
		ok(str(id).begins_with({"treat": "treat:", "rod": "rod:", "cosmetic": "cos:"}.get(kind, "?")), "%s: id prefix does not match kind '%s'" % [w, kind])
		if s.has("needs_lantern"): ok(str(s.needs_lantern) in lan, "%s: needs_lantern '%s' is not in Data.LANTERNS" % [w, str(s.needs_lantern)])
		match kind:
			"rod":
				var lv := int(s.get("level", 0))
				ok(lv >= 2 and lv <= 3, "%s: rod level %d outside 2..3" % [w, lv])
				ok(str(id) == "rod:%d" % lv, "%s: id does not match level %d" % [w, lv])
				ok(data_dict("ROD").has(lv), "%s: Data.ROD has no entry for level %d" % [w, lv])
			"cosmetic":
				ok(str(s.get("slot", "")) in ["scarf", "hat", "paint"], "%s: slot '%s' unknown" % [w, str(s.get("slot"))])
				ok(_hex_ok(s.get("color")), "%s: colour invalid" % w)
	# GDD 6 (yen): treats 200-500, Sturdy Rod 4,000, Lighthouse Rod 15,000
	for tid in shop.keys():
		if str(shop[tid].get("kind", "")) == "treat" and (int(shop[tid].price) < 150 or int(shop[tid].price) > 600): warn("%s costs %d (GDD 5.4: treats 200-500)" % [tid, int(shop[tid].price)])
	if shop.has("rod:2") and int(shop["rod:2"].get("price", 0)) != 4000: warn("GDD 5.4: Sturdy Rod costs 4,000, Data has %s" % str(shop["rod:2"].get("price")))
	if shop.has("rod:3") and int(shop["rod:3"].get("price", 0)) != 15000: warn("GDD 5.4: Lighthouse Rod costs 15,000, Data has %s" % str(shop["rod:3"].get("price")))
	var items := data_dict("ITEMS")
	for id in items.keys():
		ok(str(id).contains(":"), "ITEMS.%s must be a prefixed bag id (flower:...)" % id)
		ok(str(items[id].get("name", "")) != "" and int(items[id].get("price", 0)) > 0, "ITEMS.%s needs a name and a positive price" % id)

func t_rod_table() -> void:
	var rod := data_dict("ROD")
	for lv in [1, 2, 3]:
		ok(rod.has(lv), "Data.ROD has no entry for level %d (keys must be ints; fish code reads ROD[rod_level])" % lv)
	if rod.has(1) and rod.has(2) and rod.has(3):
		for k in ["bite_window", "surge", "rare_bonus"]:
			for lv in [1, 2, 3]: ok(rod[lv].has(k), "ROD[%d] is missing '%s'" % [lv, k])
		ok(float(rod[1].bite_window) < float(rod[2].bite_window) and float(rod[2].bite_window) <= float(rod[3].bite_window), "bite_window must grow with rod level")
		ok(float(rod[1].surge) > float(rod[2].surge) and float(rod[2].surge) >= float(rod[3].surge), "surge must fall (gentler) with rod level")
		near(float(rod[1].bite_window), 0.7, 0.001, "Rod 1 bite window (GDD 0.7 s)")
		near(float(rod[2].bite_window) - float(rod[1].bite_window), 0.15, 0.001, "Rod 2 adds 0.15 s (GDD)")
		ok(float(rod[3].rare_bonus) > 0.0, "Rod 3 should give a rare spot bonus")

func t_lanterns_table() -> void:
	var lan := data_dict("LANTERNS")
	ok(lan.size() > 0, "Data.LANTERNS is empty")
	var shop := data_dict("SHOP")
	for id in lan.keys():
		var l: Dictionary = lan[id]
		var w := "LANTERNS.%s" % id
		ok(str(l.get("name", "")) != "", w + ": empty name")
		ok(int(l.get("cost", 0)) > 0, w + ": cost must be positive")
		ok(str(l.get("spot", "")) in SPOT_NAMES, "%s: spot '%s' is not a valid spot name" % [w, str(l.get("spot"))])
		ok(str(l.get("unlocks", "")) != "", w + ": missing the unlock text")
		if l.has("after"): ok(lan.has(str(l.after)) and str(l.after) != str(id), "%s: after '%s' is not another lantern" % [w, str(l.after)])
		for sid in l.get("unlock_shop", []): ok(shop.has(str(sid)), "%s: unlock_shop '%s' is not in Data.SHOP" % [w, str(sid)])
	# the chain must be acyclic and start somewhere
	var roots := 0
	for id in lan.keys():
		var hops := 0
		var cur := str(id)
		while lan.get(cur, {}).has("after") and hops < 10:
			cur = str(lan[cur].after); hops += 1
		ok(hops < 10, "LANTERNS.%s: the 'after' chain loops" % id)
		if not lan[id].has("after"): roots += 1
	ok(roots >= 1, "no first lantern (every lantern has an 'after')")
	if lan.has("harbour") and int(lan.harbour.get("cost", 0)) != 12: warn("GDD 5.5: Harbour lantern costs 12 sparks, Data has %s" % str(lan.harbour.get("cost")))
	if lan.has("hill") and int(lan.hill.get("cost", 0)) != 25: warn("GDD 5.5: Hill lantern costs 25 sparks, Data has %s" % str(lan.hill.get("cost")))
	if lan.has("lighthouse") and int(lan.lighthouse.get("cost", 0)) != 40: warn("GDD 5.5: Lighthouse lamp costs 40 sparks, Data has %s" % str(lan.lighthouse.get("cost")))
	var spark := data_dict("SPARK")
	for k in spark.keys(): ok(int(spark[k]) >= 0, "SPARK.%s must be >= 0" % str(k))
	for k in ["new_fish", "cat_friend", "request", "new_shore"]: ok(spark.has(k), "SPARK is missing '%s'" % k)
	if int(spark.get("record", 0)) != 0: warn("GDD 5.5: new records pay no spark (SPARK.record = 0), Data has %s" % str(spark.get("record")))

func t_requests_table() -> void:
	var tpl = data_const("REQUEST_TEMPLATES", [])
	ok(typeof(tpl) == TYPE_ARRAY and tpl.size() > 0, "Data.REQUEST_TEMPLATES is empty")
	if typeof(tpl) != TYPE_ARRAY: return
	var kinds := {"fish_size": 1, "fish": 1, "shore": 2, "gold": 0}   # kind -> number of % placeholders in text
	var people := people_table()
	var shore := data_dict("SHORE")
	var fish := data_dict("FISH")
	# the biggest fish you can hold before / after the harbour lantern (non-junk)
	var early_max := 0.0
	var late_max := 0.0
	for id in fish.keys():
		var f: Dictionary = fish[id]
		if bool(f.get("junk", false)) or str(f.get("needs_perk", "")) != "": continue
		var mx := float(f.get("size", [0, 0])[1])
		var spots: Array = f.get("spots", [])
		if ("pier" in spots or "beach" in spots) and str(f.get("needs_lantern", "")) == "": early_max = maxf(early_max, mx)
		late_max = maxf(late_max, mx)
	var has_gold := false
	for i in tpl.size():
		var q: Dictionary = tpl[i]
		var w := "REQUEST_TEMPLATES[%d]" % i
		var kind := str(q.get("kind", ""))
		ok(kinds.has(kind), "%s: unknown kind '%s'" % [w, kind])
		if kind == "gold": has_gold = true
		var text := str(q.get("text", ""))
		var holes := text.count("%d") + text.count("%s")
		if kinds.has(kind): ok(holes == kinds[kind], "%s: text has %d placeholders, kind '%s' needs %d: %s" % [w, holes, kind, kinds[kind], text])
		var rw = q.get("reward", [])
		ok(typeof(rw) == TYPE_ARRAY and rw.size() == 2 and int(rw[0]) > 0 and int(rw[0]) <= int(rw[1]), "%s: reward must be [min, max] with 0 < min <= max" % w)
		for key in ["min_cm", "min_cm_late", "count"]:
			if q.has(key):
				var a = q[key]
				ok(typeof(a) == TYPE_ARRAY and a.size() == 2 and int(a[0]) > 0 and int(a[0]) <= int(a[1]), "%s: %s must be [min, max]" % [w, key])
		if kind == "fish_size" and q.has("min_cm"):
			ok(float(q.min_cm[1]) <= early_max, "%s: min_cm up to %s is above the biggest early fish (%s cm): impossible before the rocks" % [w, str(q.min_cm[1]), str(early_max)])
			if q.has("min_cm_late"): ok(float(q.min_cm_late[1]) <= late_max, "%s: min_cm_late up to %s is above the biggest fish (%s cm)" % [w, str(q.min_cm_late[1]), str(late_max)])
		if kind == "shore":
			ok(q.has("items") and not q.items.is_empty(), "%s: shore request needs an 'items' list" % w)
			for it in q.get("items", []): ok(shore.has(str(it)), "%s: item '%s' is not in Data.SHORE" % [w, str(it)])
		var who := str(q.get("who", ""))
		ok(who != "", w + ": missing who")
		if not people.is_empty() and who != "": ok(people.has(who), "%s: who '%s' is not a person id in Data.PEOPLE (friendship reward would go nowhere)" % [w, who])
	ok(has_gold, "no gold request template (GDD 5.4: Pip's gold request)")
	ok(int(data_const("REQUESTS_PER_DAY", 3)) == 3, "GDD: 3 requests per day")

func t_start_state_data() -> void:
	var bag = data_const("STARTING_BAG", {})
	if typeof(bag) == TYPE_DICTIONARY:
		for id in bag.keys():
			ok(item_problem(str(id)) == "", "STARTING_BAG.%s invalid (%s)" % [str(id), item_problem(str(id))])
			ok(int(bag[id]) > 0, "STARTING_BAG.%s count must be positive" % str(id))
	ok(int(data_const("STARTING_YEN", 500)) >= 0, "STARTING_YEN must be >= 0")
	var goals = data_const("STARTER_GOALS", [])
	if typeof(goals) == TYPE_ARRAY:
		var ids := {}
		for g in goals:
			ok(typeof(g) == TYPE_DICTIONARY and str(g.get("id", "")) != "" and str(g.get("text", "")) != "", "STARTER_GOALS entry needs id and text: %s" % str(g))
			if typeof(g) == TYPE_DICTIONARY:
				ok(not ids.has(str(g.get("id"))), "STARTER_GOALS duplicate id '%s'" % str(g.get("id")))
				ids[str(g.get("id"))] = true

# ------------------------------------------------------------------ PEOPLE
func t_people_table() -> void:
	var people := people_table()
	if people.is_empty(): skip("no Data.PEOPLE (and no fallback table) yet"); return
	var lv = data_const("PEOPLE_LEVELS", null)
	if typeof(lv) != TYPE_ARRAY: fail("Data.PEOPLE_LEVELS is not defined: GameState.person_level would use the 100-points-per-level fallback")
	if data_const("PEOPLE", null) == null: warn("Data.PEOPLE is not in data.gd yet: validating the People team's fallback table")
	if not people.has("pip"): fail("PEOPLE must contain 'pip' (the shop keeper, contract)")
	var pts := data_dict("PEOPLE_POINTS")
	for k in ["talk", "loved", "liked", "neutral", "disliked", "request"]:
		ok(pts.has(k), "PEOPLE_POINTS is missing '%s'" % k)
	if people.size() != 6: warn("GDD 5.6: six neighbours, Data.PEOPLE has %d" % people.size())
	var shop := data_dict("SHOP")
	for id in people.keys():
		var p: Dictionary = people[id]
		var w := "PEOPLE.%s" % id
		ok(str(id) == str(id).to_lower(), w + ": ids must be lower case")
		for k in ["name", "role", "home", "routine"]:
			if not p.has(k): fail("%s is missing '%s'" % [w, k])
		ok(str(p.get("name", "")) != "", w + ": empty name")
		ok(str(p.get("home", "")) in SPOT_NAMES, "%s: home '%s' is not a valid spot name" % [w, str(p.get("home"))])
		var routine = p.get("routine", {})
		if typeof(routine) == TYPE_DICTIONARY:
			for slot in routine.keys():
				ok(str(slot) in SLOTS, "%s: routine slot '%s' is not a time slot" % [w, str(slot)])
				var spot = routine[slot]
				if typeof(spot) == TYPE_ARRAY:
					for sp in spot: ok(str(sp) in SPOT_NAMES, "%s: routine spot '%s' invalid" % [w, str(sp)])
				else:
					ok(str(spot) in SPOT_NAMES, "%s: routine %s spot '%s' is not a valid spot name" % [w, str(slot), str(spot)])
			for slot in SLOTS: ok(routine.has(slot), "%s: routine has no '%s' entry (the person would vanish)" % [w, slot])
		else:
			fail(w + ": routine must be a Dictionary slot -> spot")
		var seen := {}
		for list_key in ["loves", "likes", "dislikes"]:
			var lst = p.get(list_key, [])
			ok(typeof(lst) == TYPE_ARRAY, "%s.%s must be an Array" % [w, list_key])
			if typeof(lst) != TYPE_ARRAY: continue
			for item in lst:
				var prob := item_problem(str(item))
				ok(prob == "", "%s.%s: '%s' (%s)" % [w, list_key, str(item), prob])
				if seen.has(str(item)): fail("%s: '%s' is in both %s and %s" % [w, str(item), seen[str(item)], list_key])
				seen[str(item)] = list_key
		for col in ["main", "accent", "extra"]:
			if p.has(col): ok(_hex_ok(p[col]), "%s.%s: colour '%s' invalid" % [w, col, str(p[col])])
		# dialogue bands: "0","3","6","9" (new shape) or low/mid/high (fallback shape)
		var lines = p.get("lines", {})
		if typeof(lines) == TYPE_DICTIONARY:
			var bands: Array = ["0", "3", "6", "9"] if lines.has("0") else ["low", "mid", "high"]
			for band in bands:
				ok(typeof(lines.get(band, null)) == TYPE_ARRAY and not lines[band].is_empty(), "%s.lines[%s] must be a non-empty Array" % [w, band])
				for ln in lines.get(band, []):
					ok(str(ln).strip_edges() != "", "%s.lines[%s] has an empty line" % [w, band])
					if str(ln).length() > 260: warn("%s.lines[%s]: a line is %d chars (may overflow the dialogue box): %s..." % [w, band, str(ln).length(), str(ln).left(30)])
		else:
			fail(w + ": lines must be a Dictionary of bands")
		var prev_lv := 0
		var perk_levels := {}
		for pk in perk_list(p):
			var lvl := int(pk.get("level", 0))
			ok(lvl >= 1 and lvl <= 10, "%s: perk '%s' level %d outside 1..10" % [w, str(pk.get("id")), lvl])
			ok(str(pk.get("id", "")) != "", "%s: perk at level %d has no id" % [w, lvl])
			ok(str(pk.get("text", "")) != "", "%s: perk '%s' has no text (shown on the perk card)" % [w, str(pk.get("id"))])
			ok(typeof(pk.get("value", 0)) in [TYPE_INT, TYPE_FLOAT], "%s: perk '%s' needs a numeric value" % [w, str(pk.get("id"))])
			if pk.has("gift_cosmetic"): ok(shop.has(str(pk.gift_cosmetic)), "%s: gift_cosmetic '%s' is not in Data.SHOP" % [w, str(pk.gift_cosmetic)])
			var key := "%s@%d" % [str(pk.get("id")), lvl]
			ok(not perk_levels.has(key), "%s: perk '%s' defined twice at level %d" % [w, str(pk.get("id")), lvl])
			perk_levels[key] = true
		var evs = p.get("events", [])
		var ev_levels := {}
		if typeof(evs) == TYPE_ARRAY:
			for ev in evs:
				ok(typeof(ev) == TYPE_DICTIONARY and int(ev.get("level", 0)) >= 1 and int(ev.get("level", 0)) <= 10, "%s: event needs a level 1..10" % w)
				if typeof(ev) != TYPE_DICTIONARY: continue
				ok(typeof(ev.get("lines", null)) == TYPE_ARRAY and ev.lines.size() >= 2, "%s: event level %s needs at least 2 lines" % [w, str(ev.get("level"))])
				ok(not ev_levels.has(int(ev.get("level", 0))), "%s: two events at level %s" % [w, str(ev.get("level"))])
				ev_levels[int(ev.get("level", 0))] = true
				if ev.has("reward"):
					ok(typeof(ev.reward) == TYPE_DICTIONARY and item_problem(str(ev.reward.get("item", ""))) == "" and int(ev.reward.get("n", 0)) > 0, "%s: event reward invalid: %s" % [w, str(ev.reward)])
		var gifts = p.get("react", null)
		if gifts != null and typeof(gifts) == TYPE_DICTIONARY:
			for band in ["love", "like", "neutral", "dislike"]:
				ok(typeof(gifts.get(band, null)) == TYPE_ARRAY and not gifts[band].is_empty(), "%s.react.%s must be a non-empty Array" % [w, band])
	if typeof(lv) == TYPE_ARRAY:
		ok(lv.size() == 10, "Data.PEOPLE_LEVELS should have 10 thresholds, has %d" % lv.size())
		for i in range(1, lv.size()): ok(int(lv[i]) > int(lv[i - 1]), "PEOPLE_LEVELS must be strictly increasing at index %d" % i)

# ------------------------------------------------------------------ text hygiene
func _is_emoji_codepoint(c: int) -> bool:
	if c <= 0x2000: return false
	if c >= 0x2010 and c <= 0x2015: return false      # hyphens and dashes
	if c >= 0x2018 and c <= 0x201F: return false      # typographic quotes
	if c == 0x2022 or c == 0x2026 or c == 0x2212: return false   # bullet, ellipsis, minus
	return true

func _scan_strings(v, path: String, out: Array) -> void:
	match typeof(v):
		TYPE_STRING, TYPE_STRING_NAME:
			var s := str(v)
			for i in s.length():
				if _is_emoji_codepoint(s.unicode_at(i)):
					out.append("%s has U+%04X in '%s'" % [path, s.unicode_at(i), s.left(40)])
					break
		TYPE_DICTIONARY:
			for k in v.keys():
				_scan_strings(k, path + ".<key>", out)
				_scan_strings(v[k], path + "." + str(k), out)
		TYPE_ARRAY:
			for i in v.size(): _scan_strings(v[i], "%s[%d]" % [path, i], out)

func t_no_emoji_in_data() -> void:
	var out: Array = []
	var consts: Dictionary = dt.get_script().get_script_constant_map()
	for k in consts.keys(): _scan_strings(consts[k], "Data." + str(k), out)
	var people_fb = r.const_of("res://scripts/systems/people/people_data.gd", "PEOPLE", {})
	_scan_strings(people_fb, "PeopleData.PEOPLE", out)
	ok(out.is_empty(), "emoji / symbol characters in data (%d): %s" % [out.size(), "; ".join(out.slice(0, 5))])

func t_no_emoji_in_source() -> void:
	var rx := RegEx.create_from_string("[\\x{2001}-\\x{10FFFF}]")
	var hits: Array = []
	var files: Dictionary = r.sources(true)
	for path in files.keys():
		var text: String = files[path]
		for m in rx.search_all(text):
			var c := m.get_string().unicode_at(0)
			if _is_emoji_codepoint(c):
				var line := text.count("\n", 0, m.get_start()) + 1
				hits.append("%s:%d U+%04X" % [str(path).replace("res://", ""), line, c])
	ok(hits.is_empty(), "emoji / symbol characters in source (%d): %s" % [hits.size(), "; ".join(hits.slice(0, 8))])
	note("scanned %d .gd/.tscn files" % files.size())

## String literals of one source line (handles escapes; stops at a # comment outside strings).
func string_literals(line: String) -> Array:
	var out: Array = []
	var i := 0
	var n := line.length()
	while i < n:
		var c := line[i]
		if c == "#": break
		if c == "\"" or c == "'":
			var q := c
			var j := i + 1
			var buf := ""
			while j < n and line[j] != q:
				if line[j] == "\\" and j + 1 < n: buf += line[j + 1]; j += 2
				else: buf += line[j]; j += 1
			out.append(buf)
			i = j + 1
		else:
			i += 1
	return out

func t_no_coins_wording_in_ui() -> void:
	# GDD 11.19: yen only. A string literal with a space and the word coin(s) is player-facing text.
	var rx := RegEx.create_from_string("\\b[Cc]oins?\\b")
	var hits: Array = []
	var files: Dictionary = r.sources(false)
	for path in files.keys():
		var p := str(path)
		if p.begins_with("res://tests/") or p.begins_with("res://tools/"): continue
		var ln := 0
		for line in str(files[path]).split("\n"):
			ln += 1
			if not line.contains("oin"): continue
			for lit in string_literals(line):
				if lit.contains(" ") and rx.search(lit) != null and not lit.contains("%d coins_changed"):
					hits.append("%s:%d '%s'" % [p.replace("res://", ""), ln, lit.left(50)])
	ok(hits.is_empty(), "player-facing text says 'coins' (use yen) (%d): %s" % [hits.size(), "; ".join(hits.slice(0, 6))])

func t_text_not_too_long_for_ui() -> void:
	var long_names: Array = []
	for table in ["FISH", "SHORE", "SHOP", "CATS", "LANTERNS", "PEOPLE", "ITEMS"]:
		var d := data_dict(table)
		for id in d.keys():
			var nm := str(d[id].get("name", ""))
			if nm.length() > 24: long_names.append("%s.%s '%s'" % [table, id, nm])
	ok(long_names.is_empty(), "names longer than 24 chars: " + ", ".join(long_names))

# ------------------------------------------------------------------ wiring: data that nothing reads
func _code_sources() -> Dictionary:
	var out := {}
	var all: Dictionary = r.sources(false)
	for p in all.keys():
		var ps := str(p)
		if ps.begins_with("res://tests/") or ps.begins_with("res://tools/") or ps == "res://scripts/core/data.gd": continue
		out[ps] = all[p]
	return out

func t_data_constants_are_used() -> void:
	var code := _code_sources()
	var unused: Array = []
	var consts: Dictionary = dt.get_script().get_script_constant_map()
	for k in consts.keys():
		var rx := RegEx.create_from_string("\\b%s\\b" % str(k))
		var used := false
		for p in code.keys():
			if rx.search(code[p]) != null: used = true; break
		if not used: unused.append(str(k))
	ok(unused.is_empty(), "Data constants that no code reads (%d): %s" % [unused.size(), ", ".join(unused)])

func t_data_fields_are_read() -> void:
	# every key used by a Data table entry must be read somewhere ("key" literal or .key access), else a designed rule is ignored
	var code := _code_sources()
	var keys := {}
	var tables := ["FISH", "CATS", "SHORE", "SHOP", "LANTERNS", "PEOPLE", "ITEMS"]
	for t in tables:
		var d := data_dict(t)
		for id in d.keys():
			if typeof(d[id]) != TYPE_DICTIONARY: continue
			for k in d[id].keys(): keys["%s.%s" % [t, str(k)]] = str(k)
	var tpl = data_const("REQUEST_TEMPLATES", [])
	if typeof(tpl) == TYPE_ARRAY:
		for q in tpl:
			if typeof(q) == TYPE_DICTIONARY:
				for k in q.keys(): keys["REQUEST_TEMPLATES.%s" % str(k)] = str(k)
	for pid in people_table().keys():
		for pk in perk_list(people_table()[pid]):
			for k in pk.keys(): keys["PEOPLE.perks.%s" % str(k)] = str(k)
		var evs = people_table()[pid].get("events", [])
		if typeof(evs) == TYPE_ARRAY:
			for ev in evs:
				if typeof(ev) == TYPE_DICTIONARY:
					for k in ev.keys(): keys["PEOPLE.events.%s" % str(k)] = str(k)
	var blob := ""
	for p in code.keys(): blob += "\n" + str(code[p])
	var dead: Array = []
	for label in keys.keys():
		var k: String = keys[label]
		if blob.contains("\"%s\"" % k) or blob.contains("'%s'" % k) or RegEx.create_from_string("\\.%s\\b" % k).search(blob) != null: continue
		dead.append(label)
	ok(dead.is_empty(), "Data fields no code reads (%d): %s" % [dead.size(), ", ".join(dead)])

func t_people_perks_are_wired() -> void:
	var people := people_table()
	if people.is_empty(): skip("no PEOPLE yet"); return
	var code := _code_sources()
	var dead: Array = []
	var seen := {}
	for pid in people.keys():
		for pk in perk_list(people[pid]):
			var id := str(pk.get("id", ""))
			if id == "" or seen.has(id) or pk.has("gift_cosmetic"): continue
			seen[id] = true
			var others := 0
			var in_people := 0
			for p in code.keys():
				var n: int = str(code[p]).count("\"%s\"" % id)
				if n == 0: continue
				if str(p).ends_with("systems/people.gd"): in_people += n
				elif not str(p).ends_with("people_data.gd"): others += n
			if others == 0 and in_people < 2: dead.append(id)
	ok(dead.is_empty(), "perks that no system reads (GDD 11.14 says every perk is measurable): " + ", ".join(dead))
