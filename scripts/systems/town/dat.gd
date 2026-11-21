extends RefCounted
## Defensive reader for the Data autoload. The design director may rename or remove constants while we
## work, so nothing in the town/shore/lantern systems references Data.X directly: it goes through here.

static var _map: Dictionary = {}

static func c(key: String, default: Variant = null) -> Variant:
	if _map.is_empty():
		var s: Script = Data.get_script()
		if s != null:
			_map = s.get_script_constant_map()
	return _map.get(key, default)

static func d(key: String) -> Dictionary:
	var v: Variant = c(key, {})
	return v if v is Dictionary else {}

static func a(key: String) -> Array:
	var v: Variant = c(key, [])
	return v if v is Array else []

static func i(key: String, default := 0) -> int:
	var v: Variant = c(key, default)
	return int(v) if (v is int or v is float) else default

static func f(key: String, default := 0.0) -> float:
	var v: Variant = c(key, default)
	return float(v) if (v is int or v is float) else default

## One entry of a table, always a Dictionary.
static func entry(table: String, id: String) -> Dictionary:
	var e: Variant = d(table).get(id, {})
	return e if e is Dictionary else {}

static func col(hex: Variant, default := Color.WHITE) -> Color:
	if hex is Color: return hex
	if hex is String and hex != "": return Color.from_string(hex, default)
	return default

## Sparks awarded for an event (Data.SPARK).
static func spark(key: String, default := 1) -> int:
	var s: Dictionary = d("SPARK")
	var v: Variant = s.get(key, default)
	return int(v) if (v is int or v is float) else default
