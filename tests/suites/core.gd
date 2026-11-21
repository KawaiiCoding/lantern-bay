extends "res://tests/suite.gd"
## Core: GameState behaviour (clock, days, weather, money, bag, save/load, friendship). No other parts needed.

const DAY_SPAN_MIN := 1440.0 + 360.0   # minute value at which the next day starts (06:00 after midnight)

func t_clock_advances() -> void:
	reset_world()
	var m0: float = gs.minute
	var seen := [0]
	var cb := func(_d, _m): seen[0] += 1
	gs.time_changed.connect(cb)
	gs._process(10.0)
	gs.time_changed.disconnect(cb)
	var rate: float = (gs.DAY_END - gs.DAY_START) / gs.DAY_REAL_SECONDS
	near(gs.minute - m0, 10.0 * rate, 0.01, "10 s of play should advance the clock by 10 * 1.5 minutes")
	ok(seen[0] >= 1, "time_changed was not emitted by a tick")
	eq(gs.clock_text(), "%02d:%02d" % [int(gs.minute) / 60, int(gs.minute) % 60], "clock_text format")
	var rx := RegEx.create_from_string("^\\d\\d:\\d\\d$")
	ok(rx.search(gs.clock_text()) != null, "clock_text is not HH:MM: '%s'" % gs.clock_text())
	# paused: no movement
	var m1: float = gs.minute
	gs.set_paused(true)
	gs._process(30.0)
	eq(gs.minute, m1, "the clock must not move while paused")
	gs.set_paused(false)
	# day span: 06:00 -> 24:00 takes 720 s (12 real minutes)
	reset_world()
	var t := 0.0
	while gs.minute < gs.DAY_END and t < 2000.0:
		gs._process(1.0); t += 1.0
	near(t, 720.0, 2.0, "an island day (06:00 to 24:00) should take 12 real minutes")

func t_new_day_fires() -> void:
	reset_world()
	var days: Array = []
	var cb := func(d): days.append(d)
	gs.new_day.connect(cb)
	gs.day = 3
	gs.minute = DAY_SPAN_MIN - 0.5
	gs._process(1.0)
	gs.new_day.disconnect(cb)
	eq(gs.day, 4, "day should increment when the night ends")
	eq(days.size(), 1, "new_day should fire exactly once")
	if days.size() == 1: eq(days[0], 4, "new_day argument")
	eq(gs.minute, gs.DAY_START, "a new day starts at 06:00")
	# after midnight the clock runs 3x (fast-forward)
	reset_world()
	gs.minute = 1450.0
	gs._process(1.0)
	near(gs.minute - 1450.0, 1.5 * 3.0, 0.01, "after midnight time runs 3x")
	# crossing never skips a day when the step is large
	reset_world()
	gs.minute = DAY_SPAN_MIN - 1.0
	gs._process(5.0)
	eq(gs.day, 2, "a long frame across the day boundary must advance exactly one day")

func _wx(d: int) -> String:
	if gs.has_method("weather_on"): return gs.weather_on(d)
	return weather_of_day(d)

func t_weather_rules() -> void:
	reset_world()
	var odds: Dictionary = data_dict("WEATHER_ODDS")
	if odds.is_empty(): odds = {"sunny": 0.5, "cloudy": 0.25, "rain": 0.2, "fog": 0.05}
	var fog_min := int(data_const("WEATHER_FOG_MIN_DAY", 4))
	var fog_gap := int(data_const("WEATHER_FOG_MAX_GAP", 14))
	var counts := {"sunny": 0, "cloudy": 0, "rain": 0, "fog": 0}
	var days := 600
	var last_fog := 0
	var worst_gap := 0
	var fog_before_min := 0
	for d in range(1, days + 1):
		var a := _wx(d)
		if a != _wx(d): fail("weather for day %d is not deterministic" % d); break
		if not counts.has(a): fail("unknown weather '%s' on day %d" % [a, d]); break
		counts[a] += 1
		if a == "fog":
			if d < fog_min: fog_before_min += 1
			last_fog = d
		worst_gap = maxi(worst_gap, d - last_fog)
	eq(_wx(1), "sunny", "day 1 must always be sunny (GDD 4)")
	eq(fog_before_min, 0, "fog before day %d (WEATHER_FOG_MIN_DAY)" % fog_min)
	ok(worst_gap <= fog_gap + fog_min, "longest drought without fog is %d days (WEATHER_FOG_MAX_GAP is %d)" % [worst_gap, fog_gap])
	for w in counts.keys():
		near(float(counts[w]) / days, float(odds.get(w, 0.0)), 0.06 if w != "fog" else 0.04, "share of %s days (Data.WEATHER_ODDS)" % w)
	# a shorter fog gap (Wen's perk) must bring fog sooner
	if "fog_gap_override" in gs:
		gs.fog_gap_override = 7
		gs._weather_cache = {}
		var worst7 := 0
		var lf := 0
		for d in range(1, 200):
			if _wx(d) == "fog": lf = d
			worst7 = maxi(worst7, d - lf)
		ok(worst7 <= 7 + fog_min, "fog_gap_override=7: longest drought is %d days" % worst7)
		gs.fog_gap_override = 0
		gs._weather_cache = {}
	reset_world()

func t_tide_slots_and_rng() -> void:
	reset_world()
	var cases := {360.0: true, 539.0: true, 540.0: false, 720.0: false, 1079.0: false, 1080.0: true, 1259.0: true, 1260.0: false, 1500.0: false}
	for m in cases.keys():
		gs.minute = m
		eq(gs.low_tide(), cases[m], "low_tide at minute %s (%s)" % [str(m), gs.clock_text()])
	var slots := {360.0: "morning", 659.0: "morning", 660.0: "afternoon", 1019.0: "afternoon", 1020.0: "evening", 1259.0: "evening", 1260.0: "night", 1500.0: "night"}
	for m in slots.keys():
		gs.minute = m
		eq(gs.time_slot(), slots[m], "time_slot at minute %s" % str(m))
	gs.day = 5
	var r1: RandomNumberGenerator = gs.day_rng(11)
	var r2: RandomNumberGenerator = gs.day_rng(11)
	var r3: RandomNumberGenerator = gs.day_rng(12)
	eq(r1.randi(), r2.randi(), "day_rng(salt) must be reproducible")
	ok(gs.day_rng(11).randi() != r3.randi(), "day_rng with a different salt gave the same value")
	reset_world()

func t_new_game_start_state() -> void:
	reset_world()
	eq(gs.day, 1, "day on a new game")
	eq(gs.minute, gs.DAY_START, "clock on a new game (06:00)")
	eq(gs.coins, int(data_const("STARTING_YEN", 500)), "starting yen (Data.STARTING_YEN)")
	var sb = data_const("STARTING_BAG", {})
	if typeof(sb) == TYPE_DICTIONARY:
		for id in sb.keys():
			eq(int(gs.bag.get(id, 0)), int(sb[id]), "starting bag holds %s (Data.STARTING_BAG)" % str(id))
			eq(typeof(gs.bag.get(id, 0)), TYPE_INT, "starting bag count type")
		eq(gs.bag.size(), sb.size(), "starting bag has only the starting items")
	eq(gs.sparks, 0, "starting sparks")
	eq(gs.rod_level, 1, "starting rod")
	ok(gs.lanterns.is_empty() and gs.cats.is_empty() and gs.fish_log.is_empty() and gs.people.is_empty(), "a new game starts with empty logs")
	# no save on disk: load_game must give the same fresh start (first launch)
	gs.coins = 1; gs.bag = {}
	gs.load_game()
	eq(gs.coins, int(data_const("STARTING_YEN", 500)), "load_game with no save applies the starting yen")
	if typeof(sb) == TYPE_DICTIONARY and not sb.is_empty(): ok(not gs.bag.is_empty(), "load_game with no save applies the starting bag")
	reset_world()

func t_money_never_negative() -> void:
	reset_world()
	eq(gs.coins, int(data_const("STARTING_YEN", 500)), "starting coins")
	var got := [0]
	var cb := func(c): got[0] = c
	gs.coins_changed.connect(cb)
	gs.add_coins(100)
	eq(gs.coins, 600, "add_coins(100)")
	eq(got[0], 600, "coins_changed payload")
	gs.add_coins(-10000)
	eq(gs.coins, 0, "add_coins below zero must clamp to 0")
	gs.coins_changed.disconnect(cb)
	gs.coins = 50
	ok(not gs.spend(51), "spend more than owned must fail")
	eq(gs.coins, 50, "failed spend must not change coins")
	ok(gs.spend(50), "spend exactly what is owned must succeed")
	eq(gs.coins, 0, "coins after spending everything")
	ok(not gs.spend(1), "spend with 0 coins must fail")
	eq(typeof(gs.coins), TYPE_INT, "coins stays an int")
	gs.coins = 10
	var before: int = gs.coins
	gs.spend(-5)
	if gs.coins > before: warn("spend(-5) GAINED coins (%d -> %d): guard against negative prices in GameState.spend" % [before, gs.coins])
	reset_world()

func t_bag_add_remove() -> void:
	reset_world()
	var fired := [0]
	var cb := func(): fired[0] += 1
	gs.bag_changed.connect(cb)
	gs.add_item("fish:sardine")
	gs.add_item("fish:sardine", 2)
	eq(gs.bag.get("fish:sardine", 0), 3, "bag count after adds")
	ok(gs.has_item("fish:sardine", 3), "has_item(3)")
	ok(not gs.has_item("fish:sardine", 4), "has_item(4) must be false")
	ok(not gs.has_item("fish:nothing"), "has_item on missing id")
	ok(not gs.remove_item("fish:sardine", 4), "removing more than owned must fail")
	eq(gs.bag.get("fish:sardine", 0), 3, "a failed remove must not change the count")
	ok(gs.remove_item("fish:sardine", 2), "remove 2")
	eq(gs.bag.get("fish:sardine", 0), 1, "count after removing 2")
	ok(gs.remove_item("fish:sardine"), "remove last")
	ok(not gs.bag.has("fish:sardine"), "an item at 0 must be erased from the bag")
	ok(not gs.remove_item("fish:sardine"), "removing from an empty slot must fail")
	ok(fired[0] >= 4, "bag_changed should fire on every change (fired %d)" % fired[0])
	gs.bag_changed.disconnect(cb)
	for k in gs.bag.keys(): ok(int(gs.bag[k]) > 0, "non-positive count stored for " + str(k))
	eq(typeof(gs.bag.get("x", 0)), TYPE_INT, "default count type")
	gs.add_item("treat:cream", 2)
	eq(typeof(gs.bag["treat:cream"]), TYPE_INT, "bag counts are ints")
	reset_world()

func t_sparks_and_say() -> void:
	reset_world()
	var toasts: Array = []
	var cb := func(t): toasts.append(t)
	gs.toast.connect(cb)
	var sp := [0]
	var cb2 := func(n): sp[0] = n
	gs.sparks_changed.connect(cb2)
	gs.add_sparks(2, "first catch")
	gs.add_sparks(1)
	gs.toast.disconnect(cb)
	gs.sparks_changed.disconnect(cb2)
	eq(gs.sparks, 3, "sparks total")
	eq(sp[0], 3, "sparks_changed payload")
	eq(toasts.size(), 1, "only add_sparks with a reason should toast")
	if toasts.size() > 0: ok(str(toasts[0]).contains("2") and str(toasts[0]).contains("first catch"), "spark toast text: " + str(toasts[0]))
	reset_world()

func t_cat_state_and_facts() -> void:
	reset_world()
	var s: Dictionary = gs.cat_state("biscuit")
	for k in ["hearts", "facts", "last_pet_day", "last_sit_day", "last_treat_day", "friend"]:
		ok(s.has(k), "cat_state default is missing '%s'" % k)
	eq(typeof(s.get("hearts")), TYPE_INT, "hearts is an int")
	var changed := [0]
	var cb := func(): changed[0] += 1
	gs.catalog_changed.connect(cb)
	gs.learn_cat_fact("biscuit", "haunt:pier")
	gs.learn_cat_fact("biscuit", "haunt:pier")
	gs.catalog_changed.disconnect(cb)
	eq(gs.cat_state("biscuit").facts.size(), 1, "a fact must be stored once")
	eq(changed[0], 1, "catalog_changed fires once per new fact")
	ok(gs.cat_state("biscuit") is Dictionary and gs.cats.has("biscuit"), "cat_state registers the cat in gs.cats")
	reset_world()

func _populate() -> void:
	gs.day = 7; gs.minute = 700.5; gs.coins = 1234; gs.sparks = 11; gs.rod_level = 2
	gs.bag = {"fish:sardine": 3, "shore:shell_white": 2, "treat:cream": 1}
	gs.fish_log = {"sardine": {"count": 2, "best_cm": 17.5, "gold": 1}, "tuna": {"count": 1, "best_cm": 120.0, "gold": 0}}
	gs.cats = {"biscuit": {"hearts": 3, "facts": ["haunt:pier", "likes:fish:mackerel"], "last_pet_day": 6, "last_sit_day": 5, "last_treat_day": 0, "friend": false},
		"tofu": {"hearts": 5, "facts": [], "last_pet_day": 7, "last_sit_day": 7, "last_treat_day": 4, "friend": true}}
	gs.shore_log = {"shell_white": 4, "moon_shell": 1}
	gs.requests = [{"id": 1, "kind": "fish_size", "who": "maple", "min_cm": 40, "reward": 120, "done": false}]
	gs.people = {"pip": {"points": 130, "last_talk_day": 6, "last_gift_day": 3, "seen_lines": ["a", "b"], "perks": ["shop_discount"], "events": [4]}}
	gs.lanterns = {"harbour": true}
	gs.cosmetics = {"cos:cap": true, "equipped": {"hat": "cos:cap"}}
	gs.flags = {"met_pip": true, "visits": 3}

func _blank_in_memory() -> void:
	gs.day = 1; gs.minute = gs.DAY_START; gs.coins = 500; gs.sparks = 0; gs.rod_level = 1
	gs.bag = {}; gs.fish_log = {}; gs.cats = {}; gs.shore_log = {}; gs.requests = []; gs.lanterns = {}
	gs.cosmetics = {}; gs.flags = {}; gs.people = {}

func t_save_roundtrip() -> void:
	reset_world()
	_populate()
	var snap: Dictionary = gs.to_dict().duplicate(true)
	var problems: Array = []
	plain_data_problems(snap, "save", problems)
	ok(problems.is_empty(), "save data must be plain JSON data: " + "; ".join(problems.slice(0, 4)))
	gs.save_game()
	ok(FileAccess.file_exists("user://save.json"), "save.json was not written")
	ok(not FileAccess.file_exists("user://save.json.tmp"), "save.json.tmp left behind (the swap is not atomic)")
	_blank_in_memory()
	gs.load_game()
	var after: Dictionary = gs.to_dict()
	var diffs: Array = []
	deep_diff(snap, after, "save", diffs)
	if not diffs.is_empty():
		var ints: Array = []; var other: Array = []
		for d in diffs:
			if str(d).contains("came back as float"): ints.append(d)
			else: other.append(d)
		if not other.is_empty(): fail("round trip mismatch (%d): %s" % [other.size(), "; ".join(other.slice(0, 5))])
		if not ints.is_empty(): fail("ints came back as floats after load (%d) - normalise in GameState.load_game: %s" % [ints.size(), "; ".join(ints.slice(0, 6))])
	for k in ["day", "coins", "sparks", "rod_level"]:
		eq(typeof(gs.get(k)), TYPE_INT, "gs.%s type after load" % k)
	near(gs.minute, 700.5, 0.001, "minute after load")
	# a second save keeps the previous one as backup
	gs.save_game()
	ok(FileAccess.file_exists("user://save.bak.json"), "save.bak.json was not created by the second save")
	reset_world()

func t_save_corrupt_falls_back_to_backup() -> void:
	reset_world()
	gs.day = 3; gs.coins = 111; gs.save_game()
	gs.day = 4; gs.coins = 222; gs.save_game()
	expect_error("Parse JSON failed")   # JSON.parse_string logs the malformed text; GameState handles it
	for junk in ["{ this is not json", "", "[1, 2, 3]", "{\"day\": 9, \"coins\": 5", "garbage\tgarbage"]:
		write_text_file("user://save.json", junk)
		_blank_in_memory()
		gs.load_game()
		var label: String = "corrupt save.json " + junk.c_escape().left(24)
		eq(gs.day, 3, label + ": day should come from save.bak.json")
		eq(gs.coins, 111, label + ": coins should come from save.bak.json")
	# both corrupt: defaults, no crash
	write_text_file("user://save.json", "garbage")
	write_text_file("user://save.bak.json", "more garbage")
	_blank_in_memory()
	gs.load_game()
	eq(gs.day, 1, "both saves corrupt: day falls back to 1")
	eq(gs.coins, 500, "both saves corrupt: default coins")
	# no files at all
	gs.reset()
	_blank_in_memory()
	gs.load_game()
	eq(gs.day, 1, "no save: day 1")
	reset_world()

func t_save_wrong_types_do_not_crash() -> void:
	reset_world()
	# valid JSON, wrong shapes (hand-edited or from another version): must not crash or leave an invalid state
	write_text_file("user://save.json", JSON.stringify({"day": "x", "coins": null, "bag": 5, "requests": "zzz", "cats": [1], "minute": -50, "rod_level": 99, "unknown_key": 1}))
	_blank_in_memory()
	gs.load_game()
	demote_errors("load_game with wrong field types")
	if gs.day < 1: warn("a bad save left day = %s (should stay >= 1)" % str(gs.day))
	if gs.coins < 0: warn("a bad save left coins = %s" % str(gs.coins))
	ok(gs.rod_level >= 1 and gs.rod_level <= 3, "rod_level must be clamped 1..3 (got %s)" % str(gs.rod_level))
	ok(typeof(gs.bag) == TYPE_DICTIONARY and typeof(gs.requests) == TYPE_ARRAY and typeof(gs.cats) == TYPE_DICTIONARY, "container types must survive a bad save")
	if gs.minute < gs.DAY_START or gs.minute > DAY_SPAN_MIN: warn("a bad save left minute = %s (should be clamped into the day)" % str(gs.minute))
	reset_world()

func t_save_soon_writes_within_a_few_seconds() -> void:
	reset_world()
	gs.coins = 4321
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))
	gs.save_soon()
	var wrote: bool = await r.wait_until(func(): return FileAccess.file_exists("user://save.json"), 4.0)
	ok(wrote, "save_soon() did not write save.json within 4 s")
	if wrote:
		await r.wait_frames(2)
		var d = read_json_file("user://save.json")
		ok(typeof(d) == TYPE_DICTIONARY and int(d.get("coins", 0)) == 4321, "save.json does not contain the latest coins")
	reset_world()

func t_person_level_thresholds() -> void:
	reset_world()
	var id := "qa_person"
	var th: Array = []
	var from_data = data_const("PEOPLE_LEVELS", null)
	if typeof(from_data) == TYPE_ARRAY: th = from_data
	if th.is_empty():
		gs.people[id] = {"points": 0, "last_talk_day": 0, "last_gift_day": 0, "seen_lines": [], "perks": [], "events": []}
		for p in [0, 99, 100, 199, 200, 999, 1000, 5000]:
			gs.people[id].points = p
			eq(gs.person_level(id), clampi(p / 100, 0, 10), "fallback person_level at %d points (100 per level)" % p)
		note("Data.PEOPLE_LEVELS not defined yet: checked the 100-points-per-level fallback")
	else:
		ok(th.size() == 10, "Data.PEOPLE_LEVELS should list 10 thresholds (levels 1..10), has %d" % th.size())
		var prev := -1
		for i in th.size():
			ok(int(th[i]) > prev, "PEOPLE_LEVELS must be strictly increasing (index %d)" % i)
			prev = int(th[i])
		gs.person_state(id)
		for i in th.size():
			gs.people[id].points = int(th[i])
			eq(gs.person_level(id), mini(i + 1, 10), "person_level at threshold %d (%d points)" % [i, int(th[i])])
			gs.people[id].points = maxi(0, int(th[i]) - 1)
			eq(gs.person_level(id), i, "person_level one point below threshold %d" % i)
		gs.people[id].points = 99999999
		eq(gs.person_level(id), 10, "person_level is capped at 10")
		if int(th[0]) <= 0: warn("PEOPLE_LEVELS[0] is %d: level 1 would be free at 0 points" % int(th[0]))
	gs.people[id].points = 0
	eq(gs.person_level(id), 0, "0 points is level 0")
	reset_world()

func t_friendship_levelup_toast() -> void:
	reset_world()
	var id := "qa_person"
	var th: Array = []
	var from_data = data_const("PEOPLE_LEVELS", null)
	if typeof(from_data) == TYPE_ARRAY: th = from_data
	var first: int = int(th[0]) if th.size() > 0 else 100
	var second: int = int(th[1]) if th.size() > 1 else 200
	var toasts: Array = []
	var cb := func(t): toasts.append(str(t))
	gs.toast.connect(cb)
	var changed := [0]
	var cb2 := func(): changed[0] += 1
	gs.people_changed.connect(cb2)
	gs.add_friendship(id, 1)
	eq(toasts.size(), 0, "a tiny friendship gain below level 1 must not toast")
	gs.add_friendship(id, first - 1)
	eq(gs.person_level(id), 1, "level after reaching the first threshold")
	eq(toasts.size(), 1, "reaching level 1 must toast exactly once")
	if toasts.size() > 0: ok(toasts[0].contains("1") and toasts[0] != "", "level-up toast should name the level: '%s'" % toasts[0])
	toasts.clear()
	gs.add_friendship(id, 1)
	eq(toasts.size(), 0, "staying inside a level must not toast")
	gs.add_friendship(id, second + 100000)
	eq(toasts.size(), 1, "jumping several levels at once must toast once")
	var lv: int = gs.person_level(id)
	if toasts.size() > 0: ok(toasts[0].contains(str(lv)), "toast should show the final level %d: '%s'" % [lv, toasts[0]])
	toasts.clear()
	gs.add_friendship(id, -99999999)
	eq(int(gs.person_state(id).points), 0, "friendship points never go below 0")
	eq(toasts.size(), 0, "losing points must not toast")
	ok(changed[0] >= 4, "people_changed should fire on every friendship change (fired %d)" % changed[0])
	gs.toast.disconnect(cb)
	gs.people_changed.disconnect(cb2)
	eq(typeof(gs.person_state(id).points), TYPE_INT, "points is an int")
	ok(not gs.has_perk(id, "nonexistent_perk"), "has_perk on an unknown perk")
	reset_world()

func t_pause_signal() -> void:
	reset_world()
	var got: Array = []
	var cb := func(p): got.append(p)
	gs.paused_changed.connect(cb)
	gs.set_paused(true)
	gs.set_paused(true)
	gs.set_paused(false)
	gs.paused_changed.disconnect(cb)
	eq(got, [true, false], "paused_changed fires once per actual change")
	ok(not gs.paused, "paused is false at the end")
	reset_world()
