extends "res://tests/suite.gd"
## Economy simulation: a scripted "average player" over SIM_DAYS island days, using the numbers in Data (formula level,
## no real time). Prints money and sparks per day so the designer can tune. Targets come from GDD 6 / 11.17.
## Assumptions are constants here; change them in one place when the design changes.

const SIM_DAYS := 14
const TRIALS := 300
# --- average-player assumptions (GDD 6: first session ~3 fish, 8 shore items, 1 request, hearts with 2-3 cats)
const FISH_DAY1 := 3
const FISH_LATER := 5
const SHORE_PER_DAY := 8
const FLATS_SHARE := 0.25          # share of shore picks from the tide flats (when the session overlaps a low tide)
const REQUESTS_DONE_PER_DAY := 1
const HEARTS_DAY1 := 3             # Pancake's welcome treat (+2) and a sit
const HEARTS_PER_DAY := 4          # sit + pet on two cats
const TREAT_FROM_DAY := 2          # buys one treat a day from day 2 (+2 hearts)
const PEOPLE_POINTS_PER_DAY := 160 # talks + a liked gift + a request, concentrated on 3 neighbours
const PEOPLE_FOCUS := 3
const SLOT_WEIGHTS := {"morning": 0.35, "afternoon": 0.35, "evening": 0.25, "night": 0.05}
# --- targets (median day) as [min_ok, max_ok]; GDD 6 and 11.17
const TARGETS := {"rod2": [2, 3], "harbour": [2, 3], "hill": [3, 6], "lighthouse": [9, 15]}

func _num(key: String, default: float) -> float:
	var v = data_const(key, default)
	return float(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else default

func _eligible(spot: String, slot: String, wx: String, lit: Dictionary) -> Array:
	var out: Array = []
	var fish := data_dict("FISH")
	var rw := data_dict("RARITY_WEIGHT")
	for id in fish.keys():
		var f: Dictionary = fish[id]
		if not (spot in f.get("spots", [])): continue
		var sl: Array = f.get("slots", [])
		if not sl.is_empty() and not (slot in sl): continue
		var wl: Array = f.get("weather", [])
		if not wl.is_empty() and not (wx in wl): continue
		var nl := str(f.get("needs_lantern", ""))
		if nl != "" and not lit.has(nl): continue
		if str(f.get("needs_perk", "")) != "" or bool(f.get("low_tide", false)): continue
		var rar := clampi(int(f.get("rarity", 1)), 1, 4)
		var w := float(f.get("weight", rw.get(rar, 10)))
		if bool(f.get("junk", false)): w = _num("JUNK_WEIGHT", 8.0)
		if wx == "rain" and float(f.size[1]) >= _num("RAIN_BIG_MIN_CM", 45.0): w *= _num("RAIN_BIG_WEIGHT_MULT", 1.5)
		out.append([str(id), w])
	return out

func _pick(items: Array, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for e in items: total += float(e[1])
	var x := rng.randf() * total
	for e in items:
		x -= float(e[1])
		if x <= 0.0: return str(e[0])
	return str(items[items.size() - 1][0]) if not items.is_empty() else ""

func _slot(rng: RandomNumberGenerator) -> String:
	var x := rng.randf()
	for s in SLOT_WEIGHTS.keys():
		x -= float(SLOT_WEIGHTS[s])
		if x <= 0.0: return s
	return "morning"

## One simulated player. Returns per-day arrays and the day each milestone was reached (0 = not reached).
func _simulate(seed_v: int, scale := 1.0) -> Dictionary:
	var rng := RandomNumberGenerator.new(); rng.seed = seed_v
	var fish := data_dict("FISH")
	var shore := data_dict("SHORE")
	var lan := data_dict("LANTERNS")
	var spark := data_dict("SPARK")
	var pr: Array = data_const("PRICE_SIZE_MULT", [1.0, 1.0])
	var gold_chance := _num("GOLD_CHANCE", 0.01)
	var gold_mult := _num("GOLD_PRICE_MULT", 5.0)
	var curve := _num("SIZE_CURVE", 1.0)
	var curve_rain := _num("SIZE_CURVE_RAIN", 1.0)
	var trophy_f := _num("TROPHY_FRACTION", 0.9)
	var gold_shore := _num("SHORE_GOLD_CHANCE", 0.02)
	var gold_shell_price := _num("GOLD_SHELL_PRICE", 1200.0)
	var bottle_yen := _num("BOTTLE_YEN", 800.0)
	var lv_pts: Array = data_const("PEOPLE_LEVELS", [30, 80, 150, 240, 350, 480, 640, 830, 1050, 1300])
	var rod2_price := float(data_dict("SHOP").get("rod:2", {}).get("price", 4000))
	var rod3_price := float(data_dict("SHOP").get("rod:3", {}).get("price", 15000))
	var treat_avg := 0.0
	var tn := 0
	for id in data_dict("SHOP").keys():
		if str(data_dict("SHOP")[id].get("kind", "")) == "treat": treat_avg += float(data_dict("SHOP")[id].price); tn += 1
	treat_avg = treat_avg / maxf(1.0, tn)
	var req_avg := 0.0
	var rn := 0
	for q in data_const("REQUEST_TEMPLATES", []):
		if str(q.get("kind", "")) == "gold": continue
		req_avg += (float(q.reward[0]) + float(q.reward[1])) * 0.5; rn += 1
	req_avg = req_avg / maxf(1.0, rn)
	var coins := _num("STARTING_YEN", 500.0)
	var earned := 0.0                     # sparks earned in total
	var balance := 0.0                    # sparks available (lanterns spend them)
	var lit := {}
	var seen_fish := {}; var seen_trophy := {}; var seen_gold := {}; var seen_shore := {}
	var hearts := 0.0; var friends := 0
	var ppts := 0.0; var lvl5_done := 0
	var out := {"coins": [], "income": [], "sparks": [], "fish_inc": [], "shore_inc": [], "day_hit": {}}
	for day in range(1, SIM_DAYS + 1):
		var wx: String = gs.weather_on(day) if gs.has_method("weather_on") else weather_of_day(day)
		var inc_fish := 0.0
		var inc_shore := 0.0
		var sp_gain := 0.0
		var n_fish := int(round((FISH_DAY1 if day == 1 else FISH_LATER) * scale))
		for i in n_fish:
			var spot := "pier"
			if lit.has("harbour") and rng.randf() < 0.5: spot = "rocks"
			var cand := _eligible(spot, _slot(rng), wx, lit)
			if cand.is_empty(): continue
			var id := _pick(cand, rng)
			var f: Dictionary = fish[id]
			var t := pow(rng.randf(), curve_rain if wx == "rain" else curve)
			var price := float(f.price) * lerpf(float(pr[0]), float(pr[1]), t)
			var is_gold := rng.randf() < gold_chance and not bool(f.get("junk", false))
			if is_gold:
				price *= gold_mult
				if not seen_gold.has(id): seen_gold[id] = true; sp_gain += float(spark.get("gold", 1))
			inc_fish += price
			if not bool(f.get("junk", false)):
				if not seen_fish.has(id): seen_fish[id] = true; sp_gain += float(spark.get("new_fish", 1))
				if t >= trophy_f and not seen_trophy.has(id): seen_trophy[id] = true; sp_gain += float(spark.get("trophy", 1))
		var pool_beach: Array = []; var pool_flats: Array = []
		for id in shore.keys():
			var e: Array = [str(id), float(shore[id].weight)]
			if str(shore[id].where) == "flats": pool_flats.append(e)
			else: pool_beach.append(e)
		for i in int(round(SHORE_PER_DAY * scale)):
			var from_flats := rng.randf() < FLATS_SHARE
			var sid := _pick(pool_flats if from_flats else pool_beach, rng)
			var s: Dictionary = shore[sid]
			if bool(s.get("bottle", false)): inc_shore += bottle_yen
			elif bool(s.get("can_gold", false)) and rng.randf() < gold_shore: inc_shore += gold_shell_price
			else: inc_shore += float(s.price)
			if not seen_shore.has(sid): seen_shore[sid] = true; sp_gain += float(spark.get("new_shore", 1))
		var inc_req := 0.0
		for i in int(round(REQUESTS_DONE_PER_DAY * scale)):
			inc_req += req_avg * rng.randf_range(0.7, 1.3)
			sp_gain += float(spark.get("request", 1))
		# cats
		hearts += (HEARTS_DAY1 if day == 1 else HEARTS_PER_DAY) * scale
		var spend := 0.0
		if day >= TREAT_FROM_DAY:
			spend += treat_avg; hearts += 2.0
		while hearts >= 5.0:
			hearts -= 5.0; friends += 1; sp_gain += float(spark.get("cat_friend", 3))
		# neighbours
		ppts += PEOPLE_POINTS_PER_DAY * scale / PEOPLE_FOCUS
		if lvl5_done < PEOPLE_FOCUS and lv_pts.size() >= 5 and ppts >= float(lv_pts[4]):
			lvl5_done = PEOPLE_FOCUS; sp_gain += float(spark.get("person_level5", 2)) * PEOPLE_FOCUS
		var inc := inc_fish + inc_shore + inc_req
		coins += inc - spend
		earned += sp_gain; balance += sp_gain
		out.coins.append(coins); out.income.append(inc); out.sparks.append(earned)
		out.fish_inc.append(inc_fish); out.shore_inc.append(inc_shore)
		var hd: Dictionary = out.day_hit
		if not hd.has("rod2") and coins >= rod2_price: hd["rod2"] = day
		if not hd.has("rod3") and coins >= rod3_price: hd["rod3"] = day
		# light lanterns in order when the balance allows (sparks are spent)
		var progressed := true
		while progressed:
			progressed = false
			for id in lan.keys():
				if lit.has(id): continue
				var after := str(lan[id].get("after", ""))
				if after != "" and not lit.has(after): continue
				if balance >= float(lan[id].cost):
					balance -= float(lan[id].cost); lit[id] = true; hd[str(id)] = day; progressed = true
	return out

func _median(a: Array) -> float:
	if a.is_empty(): return 0.0
	var b := a.duplicate(); b.sort()
	return float(b[b.size() / 2])

func _pct(a: Array, q: float) -> float:
	if a.is_empty(): return 0.0
	var b := a.duplicate(); b.sort()
	return float(b[clampi(int(q * (b.size() - 1)), 0, b.size() - 1)])

func t_average_player_pacing() -> void:
	var lan := data_dict("LANTERNS")
	if data_dict("FISH").is_empty() or lan.is_empty(): skip("Data not ready"); return
	var runs: Array = []
	for i in TRIALS: runs.append(_simulate(1000 + i))
	var days := {}
	for key in ["rod2", "rod3"] + lan.keys():
		var arr: Array = []
		for r_ in runs: arr.append(int(r_.day_hit.get(key, 99)))
		days[key] = arr
	note("assumptions: day1 %d fish / later %d, %d shore items, %d request/day, treat from day %d; %d trials" % [FISH_DAY1, FISH_LATER, SHORE_PER_DAY, REQUESTS_DONE_PER_DAY, TREAT_FROM_DAY, TRIALS])
	note("day |  yen at end (median) | income/day | sparks earned (median)")
	for d in SIM_DAYS:
		var c: Array = []; var inc: Array = []; var sp: Array = []
		for r_ in runs: c.append(r_.coins[d]); inc.append(r_.income[d]); sp.append(r_.sparks[d])
		note("%3d | %8d | %6d | %5.1f" % [d + 1, int(_median(c)), int(_median(inc)), _median(sp)])
	var inc1: Array = []; var fi1: Array = []; var si1: Array = []; var sp1: Array = []
	for r_ in runs: inc1.append(r_.income[0]); fi1.append(r_.fish_inc[0]); si1.append(r_.shore_inc[0]); sp1.append(r_.sparks[0])
	note("day 1: fish ~%d yen, shore ~%d yen (GDD: ~500 and ~400), sparks ~%.1f (GDD: about 9 of 12)" % [int(_median(fi1)), int(_median(si1)), _median(sp1)])
	for key in days.keys():
		var arr: Array = days[key]
		note("%-10s median day %s  (p10 %s, p90 %s)" % [key, str(int(_median(arr))), str(int(_pct(arr, 0.1))), str(int(_pct(arr, 0.9)))])
	for key in TARGETS.keys():
		if not days.has(key): continue
		var m := int(_median(days[key]))
		var lo: int = TARGETS[key][0]; var hi: int = TARGETS[key][1]
		if m < lo: fail("%s reached on day %d (median), target day %d-%d. Too early (GDD 11.17: flag anything hit on day 1)" % [key, m, lo, hi])
		elif m > hi: fail("%s reached on day %d (median), target day %d-%d. Too slow: raise income / sparks or lower the cost" % [key, m, lo, hi])
	var s1 := _median(sp1)
	if s1 < 5.0 or s1 > 11.9: warn("day-1 sparks %.1f; GDD says about 9 of the first 12" % s1)
	var f1 := _median(fi1); var sh1 := _median(si1)
	if f1 < 250.0 or f1 > 900.0: warn("day-1 fish income ~%d yen (GDD ~500)" % int(f1))
	if sh1 < 200.0 or sh1 > 800.0: warn("day-1 shore income ~%d yen (GDD ~400)" % int(sh1))

func t_pacing_is_robust_for_slow_and_fast_players() -> void:
	if data_dict("FISH").is_empty(): skip("Data not ready"); return
	var results := {}
	for pair in [["casual (half the activity)", 0.5], ["dedicated (double)", 2.0]]:
		var arr_h: Array = []
		for i in 100:
			var s := _simulate(5000 + i, float(pair[1]))
			arr_h.append(int(s.day_hit.get("harbour", 99)))
		results[pair[0]] = int(_median(arr_h))
	note("harbour lantern median day: %s" % str(results))
	var casual: int = results["casual (half the activity)"]
	var dedicated: int = results["dedicated (double)"]
	ok(casual <= 8, "a casual player lights the harbour lantern only on day %d (should still be within the first week)" % casual)
	ok(dedicated >= 1, "")
	if dedicated < 2: warn("a dedicated player lights the harbour lantern on day %d" % dedicated)

func t_fish_value_matches_gdd_bands() -> void:
	# expected sale value of a pier catch on a sunny morning, by rarity
	var cand := _eligible("pier", "morning", "sunny", {})
	if cand.is_empty(): skip("no pier fish"); return
	var total := 0.0
	var ev := 0.0
	var fish := data_dict("FISH")
	var pr: Array = data_const("PRICE_SIZE_MULT", [1.0, 1.0])
	var mid := (float(pr[0]) + float(pr[1])) * 0.5
	for e in cand:
		total += float(e[1]); ev += float(e[1]) * float(fish[e[0]].price) * mid
	var mean := ev / total
	note("expected pier fish value on a sunny morning: %d yen (before gold and specials)" % int(mean))
	ok(mean > 100.0 and mean < 1500.0, "mean pier fish value %d yen is outside the 100-1500 band (GDD: commons 120-240, uncommon 450-900)" % int(mean))
