extends RefCounted
## Base class for test suites (tests/suites/*.gd). Test methods are named t_<name> and may await.
## Assertions never throw: they record a failure on the runner and return the condition, so a test
## can keep going or bail out with `if not ok(...): return`.

const SPOT_NAMES := ["home", "porch", "plaza", "shop", "shop_counter", "board", "pier", "pier_end", "beach", "rocks",
	"lighthouse", "hill", "flats", "lantern_harbour", "lantern_hill", "spawn"]
const FISHING_SPOTS := ["pier", "beach", "rocks"]
const SLOTS := ["morning", "afternoon", "evening", "night"]
const WEATHERS := ["sunny", "cloudy", "rain", "fog"]

var r                          # the runner (SceneTree)
var gs: Node
var dt: Node
var ib: Node
var _consts := {}

func setup(runner) -> void:
	r = runner
	gs = r.gs
	dt = r.dt
	ib = r.ib

# ------------------------------------------------------------------ assertions
func ok(cond: bool, msg: String) -> bool:
	if not cond: r.cur_fails.append(msg)
	return cond

func eq(actual, expected, msg: String) -> bool:
	var same: bool = (actual == expected) if typeof(actual) == typeof(expected) or (_is_num(actual) and _is_num(expected)) else false
	if not same: r.cur_fails.append("%s: expected %s, got %s" % [msg, str(expected), str(actual)])
	return same

func near(actual: float, expected: float, eps: float, msg: String) -> bool:
	var same: bool = absf(actual - expected) <= eps
	if not same: r.cur_fails.append("%s: expected %s (+/-%s), got %s" % [msg, str(expected), str(eps), str(actual)])
	return same

func fail(msg: String) -> void:
	r.cur_fails.append(msg)

func warn(msg: String) -> void:
	r.cur_warns.append(msg)

func note(msg: String) -> void:
	r.cur_notes.append(msg)

func skip(reason: String) -> void:
	r.cur_skip = reason

## Treat engine errors raised during this test as warnings (for tests that probe bad input on purpose).
func demote_errors(label: String) -> void:
	for e in r.logger.take_errors(): warn("%s: %s" % [label, str(e)])

func expect_error(substr: String) -> void:
	r.allow_errors.append(substr)

func _is_num(v) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT

# ------------------------------------------------------------------ data access
func data_const(key: String, default = null):
	if _consts.is_empty():
		var s: Script = dt.get_script()
		if s != null: _consts = s.get_script_constant_map()
	return _consts.get(key, default)

func data_dict(key: String) -> Dictionary:
	var v = data_const(key, {})
	return v if typeof(v) == TYPE_DICTIONARY else {}

## Townsfolk table: Data.PEOPLE when the design director added it, else the People team's fallback table.
func people_table() -> Dictionary:
	var d = data_const("PEOPLE", null)
	if typeof(d) == TYPE_DICTIONARY and not d.is_empty(): return d
	var fb = r.const_of("res://scripts/systems/people/people_data.gd", "PEOPLE", {})
	return fb if typeof(fb) == TYPE_DICTIONARY else {}

func people_levels() -> Array:
	var d = data_const("PEOPLE_LEVELS", null)
	if typeof(d) == TYPE_ARRAY: return d
	var fb = r.const_of("res://scripts/systems/people/people_data.gd", "LEVELS", null)
	return fb if typeof(fb) == TYPE_ARRAY else []

## "" when id is a valid bag/shop item id, else the reason. Bag ids: fish:<id>, shore:<id>, treat:<id>
## (fish/shore may end in _gold); shop ids (treat:, rod:, cos:) must exist in Data.SHOP.
func item_problem(id: String) -> String:
	var base := id
	if (id.begins_with("fish:") or id.begins_with("shore:")) and id.ends_with("_gold"): base = id.trim_suffix("_gold")
	if base.begins_with("fish:"):
		return "" if data_dict("FISH").has(base.substr(5)) else "no such fish"
	if base.begins_with("shore:"):
		return "" if data_dict("SHORE").has(base.substr(6)) else "no such shore item"
	if data_dict("SHOP").has(base): return ""
	if data_dict("ITEMS").has(base): return ""
	return "not a fish:/shore: id and not in SHOP or ITEMS"

## Weather names for a day, without disturbing the clock (restores gs.day).
func weather_of_day(d: int) -> String:
	var keep: int = gs.day
	gs.day = d
	var w: String = gs.weather()
	gs.day = keep
	return w

# ------------------------------------------------------------------ deep compare (save round trips)
## Collects differences between `before` and `after`; an int that came back as a float is reported.
func deep_diff(before, after, path: String, out: Array) -> void:
	var tb := typeof(before)
	var ta := typeof(after)
	if tb == TYPE_INT and ta == TYPE_FLOAT:
		out.append("%s: int %s came back as float" % [path, str(before)])
		return
	if tb == TYPE_FLOAT and ta == TYPE_INT:
		if absf(float(before) - float(after)) > 1e-6: out.append("%s: %s != %s" % [path, str(before), str(after)])
		return
	if tb != ta:
		out.append("%s: type %s -> %s" % [path, type_string(tb), type_string(ta)])
		return
	match tb:
		TYPE_DICTIONARY:
			for k in before.keys():
				if not after.has(k): out.append("%s.%s: missing after load" % [path, str(k)]); continue
				deep_diff(before[k], after[k], path + "." + str(k), out)
			for k in after.keys():
				if not before.has(k): out.append("%s.%s: appeared after load" % [path, str(k)])
		TYPE_ARRAY:
			if before.size() != after.size():
				out.append("%s: array size %d -> %d" % [path, before.size(), after.size()]); return
			for i in before.size(): deep_diff(before[i], after[i], "%s[%d]" % [path, i], out)
		TYPE_FLOAT:
			if absf(before - after) > 1e-6: out.append("%s: %s -> %s" % [path, str(before), str(after)])
		_:
			if before != after: out.append("%s: %s -> %s" % [path, str(before), str(after)])

## True when every value is plain JSON data (Dictionary with String keys, Array, String, int, float, bool).
func plain_data_problems(v, path: String, out: Array) -> void:
	match typeof(v):
		TYPE_DICTIONARY:
			for k in v.keys():
				if typeof(k) != TYPE_STRING: out.append("%s: non-String key %s (%s)" % [path, str(k), type_string(typeof(k))])
				plain_data_problems(v[k], path + "." + str(k), out)
		TYPE_ARRAY:
			for i in v.size(): plain_data_problems(v[i], "%s[%d]" % [path, i], out)
		TYPE_STRING, TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_NIL, TYPE_STRING_NAME:
			pass
		_:
			out.append("%s: not plain data (%s)" % [path, type_string(typeof(v))])

func reset_world() -> void:
	gs.reset()
	gs.set_paused(false)
	ib.touch_move = Vector2.ZERO

func read_json_file(path: String):
	if not FileAccess.file_exists(path): return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return null
	return JSON.parse_string(f.get_as_text())

func write_text_file(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text); f.close()
