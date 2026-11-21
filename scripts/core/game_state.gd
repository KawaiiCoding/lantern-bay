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
var coins := 50
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
func weather() -> String:
	var r := _rand01(day * 7919 + 17)
	if r < 0.5: return "sunny"
	if r < 0.75: return "cloudy"
	if r < 0.95: return "rain"
	return "fog"
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
	if coins < n: return false
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

# ---------------- save / load
func to_dict() -> Dictionary:
	return {"v": 1, "day": day, "minute": minute, "coins": coins, "sparks": sparks, "rod_level": rod_level, "bag": bag,
		"fish_log": fish_log, "cats": cats, "shore_log": shore_log, "requests": requests, "lanterns": lanterns,
		"cosmetics": cosmetics, "flags": flags}
func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(to_dict()))
func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH): return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY: return
	day = int(d.get("day", 1)); minute = float(d.get("minute", DAY_START)); coins = int(d.get("coins", 50))
	sparks = int(d.get("sparks", 0)); rod_level = int(d.get("rod_level", 1))
	bag = d.get("bag", {}); fish_log = d.get("fish_log", {}); cats = d.get("cats", {}); shore_log = d.get("shore_log", {})
	requests = d.get("requests", []); lanterns = d.get("lanterns", {}); cosmetics = d.get("cosmetics", {}); flags = d.get("flags", {})
	# JSON numbers come back as float: normalise bag counts
	for k in bag.keys(): bag[k] = int(bag[k])
func reset() -> void:
	if FileAccess.file_exists(SAVE_PATH): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	day = 1; minute = DAY_START; coins = 50; sparks = 0; rod_level = 1
	bag = {}; fish_log = {}; cats = {}; shore_log = {}; requests = []; lanterns = {}; cosmetics = {}; flags = {}
