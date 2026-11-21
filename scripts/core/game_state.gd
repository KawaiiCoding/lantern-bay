extends Node
## GameState (autoload): the single source of truth + save/load + the island clock.
## Systems read/write through these helpers and listen to the signals. See docs/GDD.md.

signal time_changed(day: int, minute: float)
signal new_day(day: int)
signal coins_changed(coins: int)
signal bag_changed()
signal catalog_changed()
signal sparks_changed(sparks: int)
signal toast(text: String)
signal paused_changed(paused: bool)

const SAVE_PATH := "user://save.json"
const DAY_REAL_SECONDS := 720.0        # 12 real minutes per island day (06:00 -> 24:00)
const DAY_START := 6 * 60.0
const DAY_END := 24 * 60.0
const WEATHERS := ["sunny", "cloudy", "rain", "fog"]

var day := 1
var minute := DAY_START                # minutes since 00:00
var coins := 500                       # yen (shown as green paper money, never "coins")
var sparks := 0
var rod_level := 1
## item_id -> count (fish are stored as "fish:<id>", shore items as "shore:<id>", treats "treat:<id>")
var bag := {}
## fish_id -> {"count": int, "best_cm": float, "gold": int}
var fish_log := {}
## cat_id -> {"hearts": int, "facts": Array[String], "last_pet_day": int, "last_sit_day": int, "last_treat_day": int, "friend": bool}
var cats := {}
## shore_id -> count
var shore_log := {}
## Array of request dictionaries (see Town system)
var requests: Array = []
## person_id -> {"points": int, "last_talk_day": int, "last_gift_day": int, "seen_lines": Array, "perks": Array, "events": Array}
var people := {}
var lanterns := {}                     # lantern_id -> true
var cosmetics := {}                    # id -> true; "equipped": {...}
var flags := {}                        # free-form story / secret flags
var paused := false
var _save_timer := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_game()

func _process(dt: float) -> void:
	_save_timer += dt
	if _save_timer > 30.0:
		_save_timer = 0.0
		save_game()
	if paused:
		return
	var rate := (DAY_END - DAY_START) / DAY_REAL_SECONDS
	if minute >= DAY_END or minute < DAY_START:
		rate *= 3.0   # night after midnight plays faster
	minute += dt * rate
	if minute >= 24 * 60.0 + DAY_START:
		minute = DAY_START
		day += 1
		new_day.emit(day)
		save_game()
	time_changed.emit(day, minute)

# ---------------- time helpers
func hour() -> float: return fmod(minute, 1440.0) / 60.0
func clock_text() -> String:
	var m := int(fmod(minute, 1440.0))
	return "%02d:%02d" % [m / 60, m % 60]
func time_slot() -> String:
	var h := hour()
	if h >= 5.0 and h < 11.0: return "morning"
	if h >= 11.0 and h < 17.0: return "afternoon"
	if h >= 17.0 and h < 21.0: return "evening"
	return "night"
## Weather is fixed per day (same for everyone, survives reloads). Rules from Data:
## day 1 always sunny, no fog before WEATHER_FOG_MIN_DAY, fog forced after WEATHER_FOG_MAX_GAP days without it.
## `fog_gap_override` lets a perk (Wen's fog bell) shorten the gap; People sets it.
var fog_gap_override := 0
var _weather_cache := {}
func weather() -> String: return weather_on(day)
func weather_on(d: int) -> String:
	var gap: int = fog_gap_override if fog_gap_override > 0 else int(Data.get("WEATHER_FOG_MAX_GAP") if Data.get("WEATHER_FOG_MAX_GAP") != null else 14)
	var key := "%d:%d" % [d, gap]
	if _weather_cache.has(key): return _weather_cache[key]
	var odds: Dictionary = Data.get("WEATHER_ODDS") if Data.get("WEATHER_ODDS") != null else {"sunny": 0.5, "cloudy": 0.25, "rain": 0.2, "fog": 0.05}
	var fog_min := int(Data.get("WEATHER_FOG_MIN_DAY") if Data.get("WEATHER_FOG_MIN_DAY") != null else 4)
	var last_fog := 0
	var w := "sunny"
	for i in range(1, d + 1):
		if i == 1:
			w = "sunny"
		elif i >= fog_min and i - max(last_fog, fog_min - 1) >= gap:
			w = "fog"
		else:
			var r := _rand01(i * 7919 + 17)
			w = "sunny"
			var acc := 0.0
			for k in ["sunny", "cloudy", "rain", "fog"]:
				acc += float(odds.get(k, 0.0))
				if r < acc:
					w = k; break
			if w == "fog" and i < fog_min: w = "cloudy"
		if w == "fog": last_fog = i
	_weather_cache[key] = w
	return w
func low_tide() -> bool:
	var h := hour()
	return (h >= 6.0 and h < 9.0) or (h >= 18.0 and h < 21.0)
## Deterministic 0..1 for a seed (daily spawns, weather).
func _rand01(seed: int) -> float:
	var r := RandomNumberGenerator.new(); r.seed = seed
	return r.randf()
func day_rng(salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new(); r.seed = day * 104729 + salt
	return r

func set_paused(p: bool) -> void:
	if paused == p: return
	paused = p
	paused_changed.emit(p)

# ---------------- economy / bag
func add_coins(n: int) -> void:
	coins = max(0, coins + n); coins_changed.emit(coins)
func spend(n: int) -> bool:
	if n < 0 or coins < n: return false
	add_coins(-n); return true
func add_item(id: String, n := 1) -> void:
	bag[id] = int(bag.get(id, 0)) + n
	if bag[id] <= 0: bag.erase(id)
	bag_changed.emit()
func has_item(id: String, n := 1) -> bool: return int(bag.get(id, 0)) >= n
func remove_item(id: String, n := 1) -> bool:
	if not has_item(id, n): return false
	add_item(id, -n); return true
func add_sparks(n: int, why := "") -> void:
	sparks += n; sparks_changed.emit(sparks)
	if why != "": say("+%d spark%s: %s" % [n, "" if n == 1 else "s", why])

func say(text: String) -> void: toast.emit(text)

# ---------------- cats
func cat_state(id: String) -> Dictionary:
	if not cats.has(id):
		cats[id] = {"hearts": 0, "facts": [], "last_pet_day": 0, "last_sit_day": 0, "last_treat_day": 0, "friend": false}
	return cats[id]
func learn_cat_fact(id: String, fact: String) -> void:
	var s := cat_state(id)
	if not (fact in s.facts):
		s.facts.append(fact); catalog_changed.emit()

# ---------------- townsfolk
signal people_changed()
signal person_leveled(id: String, level: int)
func person_state(id: String) -> Dictionary:
	if not people.has(id):
		people[id] = {"points": 0, "last_talk_day": 0, "last_gift_day": 0, "seen_lines": [], "perks": [], "events": []}
	return people[id]
## Friendship level 0..10 from points (Data.PEOPLE_LEVELS thresholds when present, else 100 points per level).
func person_level(id: String) -> int:
	var pts := int(person_state(id).points)
	var th: Array = Data.get("PEOPLE_LEVELS") if Data.get("PEOPLE_LEVELS") != null else []
	if th.is_empty():
		return clampi(pts / 100, 0, 10)
	var lv := 0
	for i in th.size():
		if pts >= int(th[i]): lv = i + 1
	return min(lv, 10)
func add_friendship(id: String, n: int, why := "") -> void:
	var before := person_level(id)
	var st := person_state(id)
	st.points = max(0, int(st.points) + n)
	people_changed.emit()
	var after := person_level(id)
	if after > before:
		person_leveled.emit(id, after)   # People explains it inside the dialogue (no toast on top)
## True when a person's perk is unlocked (perk ids defined in Data.PEOPLE[id].perks).
func has_perk(id: String, perk: String) -> bool:
	return perk in person_state(id).perks

# ---------------- save / load
func to_dict() -> Dictionary:
	return {"v": 1, "day": day, "minute": minute, "coins": coins, "sparks": sparks, "rod_level": rod_level, "bag": bag,
		"fish_log": fish_log, "cats": cats, "shore_log": shore_log, "requests": requests, "lanterns": lanterns,
		"cosmetics": cosmetics, "flags": flags, "people": people}
## Saving is automatic and safe: every 30 s, after important moments (systems call save_soon()),
## when the app goes to the background or closes. Writes to a temp file, then swaps it in, and keeps
## the previous save as a backup, so a crash mid-write never loses progress.
func save_soon() -> void:
	_save_timer = 29.2   # saves within ~1 s, batching several events into one write

func save_game() -> void:
	var tmp := SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("save failed: %s" % FileAccess.get_open_error()); return
	f.store_string(JSON.stringify(to_dict()))
	f.close()
	var dir := DirAccess.open("user://")
	if dir == null: return
	if dir.file_exists("save.json"):
		dir.remove("save.bak.json")
		dir.rename("save.json", "save.bak.json")
	dir.rename("save.json.tmp", "save.json")
	_save_timer = 0.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_PREDELETE:
		save_game()

func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path): return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return null
	var d = JSON.parse_string(f.get_as_text())
	return d if typeof(d) == TYPE_DICTIONARY else null

func load_game() -> void:
	var d = _read(SAVE_PATH)
	if d == null: d = _read("user://save.bak.json")   # fall back to the previous good save
	if d == null:
		_apply_start()   # brand new game
		return
	d = _ints(d)
	day = max(1, _num(d.get("day"), 1)); minute = float(_num(d.get("minute"), DAY_START)); coins = max(0, _num(d.get("coins"), 500))
	sparks = max(0, _num(d.get("sparks"), 0)); rod_level = clampi(_num(d.get("rod_level"), 1), 1, 3)
	bag = _dict(d, "bag"); fish_log = _dict(d, "fish_log"); cats = _dict(d, "cats"); shore_log = _dict(d, "shore_log")
	var rq = d.get("requests", [])
	requests = rq if typeof(rq) == TYPE_ARRAY else []
	lanterns = _dict(d, "lanterns"); cosmetics = _dict(d, "cosmetics"); flags = _dict(d, "flags"); people = _dict(d, "people")
	# JSON numbers come back as float: normalise counts
	for k in bag.keys():
		bag[k] = int(bag[k])
		if bag[k] <= 0: bag.erase(k)
	for k in shore_log.keys(): shore_log[k] = int(shore_log[k])
	if minute < 0.0 or minute > 1440.0 + DAY_START: minute = DAY_START

## A number from a save value, or the default when missing / null / not a number.
func _num(v, default):
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT: return int(v) if typeof(default) == TYPE_INT else float(v)
	return default

## JSON turns every number into a float: turn whole numbers back into ints everywhere (nested too).
## Fractional values (sizes in cm, the clock) stay floats.
func _ints(v):
	match typeof(v):
		TYPE_FLOAT:
			return int(v) if is_finite(v) and v == floor(v) and absf(v) < 1e15 else v
		TYPE_DICTIONARY:
			var o := {}
			for k in v: o[k] = _ints(v[k])
			return o
		TYPE_ARRAY:
			var a := []
			for x in v: a.append(_ints(x))
			return a
	return v

func _dict(d: Dictionary, key: String) -> Dictionary:
	var v = d.get(key, {})
	return v if typeof(v) == TYPE_DICTIONARY else {}

func _apply_start() -> void:
	coins = int(Data.get("STARTING_YEN") if Data.get("STARTING_YEN") != null else 500)
	var sb = Data.get("STARTING_BAG")
	if typeof(sb) == TYPE_DICTIONARY:
		for k in sb: bag[k] = int(sb[k])

func reset() -> void:
	for f in ["save.json", "save.bak.json", "save.json.tmp"]:
		if FileAccess.file_exists("user://" + f): DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + f))
	day = 1; minute = DAY_START; coins = 500; sparks = 0; rod_level = 1
	bag = {}; fish_log = {}; cats = {}; shore_log = {}; requests = []; lanterns = {}; cosmetics = {}; flags = {}; people = {}
	_weather_cache = {}
	_apply_start()
