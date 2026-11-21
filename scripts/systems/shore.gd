extends Node
## Shore system: daily beach combing (GDD 5.3).
##   - Each day SHORE_BEACH_DAILY items lie on the beaches. At each low tide window (06:00-09:00 and 18:00-21:00)
##     a fresh set of SHORE_FLATS_DAILY items appears on the tide flats; leftovers wash away when the tide returns.
##     Kinds and positions are seeded by GameState.day_rng, so a reload shows the same items; picked ones are
##     remembered in GameState.flags["shore"] = {"day": int, "picked": [idx...]} and never respawn.
##   - Pick up: pop + sparkles, "shore:<id>" into the bag, shore_log count, a spark for the first of a kind, and a 2%
##     gold variant for entries with can_gold ("shore:<id>:gold", also counted in shore_log["<id>_gold"]).
##     A message bottle holds BOTTLE_YEN and the next of Ines's notes (shown on a card that waits for a tap).
##   - People perks: shore_gold (gold chance), flats_double (flats items x), bottle_bonus (bottles wash up x as often).
##   - Toasts only for firsts and gold finds (no toast per shell).
## Self-test: `-- test=shore`.

const Dat := preload("res://scripts/systems/town/dat.gd")
const Stage := preload("res://scripts/systems/town/stage.gd")
const Yen := preload("res://scripts/systems/town/yen.gd")
const Kit := preload("res://scripts/systems/town/kit.gd")
const Pickup := preload("res://scripts/systems/town/shore_pickup.gd")

const SALT_BEACH := 31000
const SALT_FLATS := 32000
const SALT_EXTRA := 33000
const FALLBACK_NOTES := [
	"To whoever finds this: the bay is kinder than it looks. So are most of the people.",
	"The tide goes out twice a day. Most people only walk the flats in the morning.",
	"Rule of the bay: nothing here is urgent. Not even this note.",
]

var main: Node
var _root: Node3D
var _items := {}                    # idx -> Pickup node
var _planned_day := -1
var _sig := ""
var _tick := 0.0
var _showcase := false
var _note_layer: CanvasLayer
var _checks_failed := 0

func setup(m: Node) -> void:
	main = m
	_root = Node3D.new()
	_root.name = "ShoreRoot"
	if main != null: main.add_child(_root)
	else: add_child(_root)
	if not GameState.new_day.is_connected(_on_new_day):
		GameState.new_day.connect(_on_new_day)
	_boot.call_deferred()

func _boot() -> void:
	# one frame after setup (main may apply `fresh=1` right after the setup calls)
	var a := Stage.args()
	if str(a.get("test", "")) == "shore":
		_run_test(a)
		return
	_sync()

func _on_new_day(_d: int) -> void:
	_sync()

func _process(dt: float) -> void:
	_tick -= dt
	if _tick > 0.0: return
	_tick = 0.5
	if _signature() != _sig:
		_sync()

func _exit_tree() -> void:
	if _note_layer != null and is_instance_valid(_note_layer): _note_layer.queue_free()

## Day + low tide + which low tide window + perks that change the plan.
func _signature() -> String:
	return "%d|%s|%s|%s" % [GameState.day, str(GameState.low_tide()), _window(), str(_flats_mult())]

func _window() -> String:
	return "am" if GameState.hour() < 12.0 else "pm"

func _flats_mult() -> float:
	return maxf(1.0, Stage.perk(main, "flats_double", 1.0))

# ------------------------------------------------------------------ state
func _state() -> Dictionary:
	var v: Variant = GameState.flags.get("shore", null)
	var st: Dictionary = v if v is Dictionary else {}
	if int(st.get("day", 0)) != GameState.day or not (st.get("picked", null) is Array):
		st = {"day": GameState.day, "picked": []}
	GameState.flags["shore"] = st
	return st

func _is_picked(st: Dictionary, idx: int) -> bool:
	for v in st.get("picked", []):
		if int(v) == idx: return true
	return false

func _mark_picked(idx: int) -> void:
	var st := _state()
	if not _is_picked(st, idx):
		st["picked"].append(idx)

# ------------------------------------------------------------------ planning (deterministic per day)
## [ids, weights] for the beach or the flats.
func _pool(flats: bool) -> Array:
	var ids: Array = []
	var ws: Array = []
	var bottle_mult := maxf(1.0, Stage.perk(main, "bottle_bonus", 1.0))
	for k in Dat.d("SHORE").keys():
		var e := Dat.entry("SHORE", str(k))
		var here := str(e.get("where", "beach"))
		if (here == "flats") != flats: continue
		var w := maxf(0.0, float(e.get("weight", 1)))
		if bool(e.get("bottle", false)): w *= bottle_mult
		ids.append(str(k)); ws.append(w)
	return [ids, ws]

func _pick(rng: RandomNumberGenerator, pool: Array) -> String:
	var ids: Array = pool[0]
	var ws: Array = pool[1]
	var total := 0.0
	for w in ws: total += float(w)
	if ids.is_empty() or total <= 0.0: return ""
	var r := rng.randf() * total
	for i in ids.size():
		r -= float(ws[i])
		if r <= 0.0: return str(ids[i])
	return str(ids[ids.size() - 1])

func _point(rng: RandomNumberGenerator, flats: bool) -> Vector3:
	var isl := Stage.island(main)
	var fn := "random_flats_point" if flats else "random_beach_point"
	var p := Vector3.ZERO
	var got := false
	if isl != null and isl.has_method(fn):
		var v: Variant = isl.call(fn, rng)
		if v is Vector3:
			p = v
			got = true
	if not got:
		var c := Stage.spot(main, "flats" if flats else "beach")
		var ang := rng.randf() * TAU
		var rad := sqrt(rng.randf()) * (3.5 if flats else 5.5)
		p = c + Vector3(cos(ang) * rad * 1.5, 0.0, sin(ang) * rad)
	p.y = Stage.ground_y(main, p.x, p.z) if isl != null else p.y     # rest exactly on the sand
	return p

func _plan_group(salt: int, first_idx: int, count: int, flats: bool, win: String, gold_chance: float) -> Array:
	var rng := GameState.day_rng(salt)
	var pool := _pool(flats)
	var out: Array = []
	var placed: Array = []
	for i in count:
		var id := _pick(rng, pool)
		var gold_roll := rng.randf()
		var pos := _point(rng, flats)
		for attempt in 5:
			var clash := false
			for q in placed:
				if (q as Vector3).distance_to(pos) < 1.0: clash = true
			if not clash: break
			pos = _point(rng, flats)
		placed.append(pos)
		if id == "": continue
		var gold := gold_roll < gold_chance and bool(Dat.entry("SHORE", id).get("can_gold", false))
		out.append({"idx": first_idx + i, "id": id, "gold": gold, "pos": pos, "flats": flats, "win": win})
	return out

func _make_plan() -> Array:
	if _showcase:
		return _showcase_plan()
	var gold_chance := Dat.f("SHORE_GOLD_CHANCE", 0.02) + Stage.perk(main, "shore_gold", 0.0)
	var beach_n := maxi(0, Dat.i("SHORE_BEACH_DAILY", 14))
	var flats_n := maxi(0, Dat.i("SHORE_FLATS_DAILY", 6))
	var extra_n := int(round(flats_n * (_flats_mult() - 1.0)))
	var win := _window()
	var plan: Array = []
	plan.append_array(_plan_group(SALT_BEACH, 0, beach_n, false, "", gold_chance))
	# one fresh flats set per low tide window (am: 100.., pm: 130..), extras from perks (200.., 230..)
	var base := 100 if win == "am" else 130
	plan.append_array(_plan_group(SALT_FLATS + (0 if win == "am" else 1), base, flats_n, true, win, gold_chance))
	if extra_n > 0:
		plan.append_array(_plan_group(SALT_EXTRA + (0 if win == "am" else 1), base + 100, extra_n, true, win, gold_chance))
	return plan

## Test layout: one of everything (plus two gold) in tidy rows in front of the camera.
func _showcase_plan() -> Array:
	var list: Array = []
	for k in Dat.d("SHORE").keys(): list.append({"id": str(k), "gold": false})
	list.append({"id": "shell_pink", "gold": true})
	list.append({"id": "moon_shell", "gold": true})
	var c := Stage.spot(main, "beach")
	var out: Array = []
	var per_row := 6
	for i in list.size():
		var col := i % per_row
		var row := i / per_row
		var e: Dictionary = list[i]
		var info := Dat.entry("SHORE", str(e.id))
		var pos := c + Vector3((col - (per_row - 1) * 0.5) * 1.15, 0, row * 1.15 - 0.3)
		pos.y = Stage.ground_y(main, pos.x, pos.z) if Stage.island(main) != null else pos.y
		out.append({"idx": i, "id": e.id, "gold": e.gold, "pos": pos,
			"flats": str(info.get("where", "beach")) == "flats", "win": _window()})
	return out

# ------------------------------------------------------------------ spawning
func _sync() -> void:
	_sig = _signature()
	var st := _state()
	if _planned_day != GameState.day:
		_clear_all()
		_planned_day = GameState.day
	var low := GameState.low_tide()
	var win := _window()
	var plan := _make_plan()
	var wanted := {}
	for e in plan:
		var idx := int(e.idx)
		var want := not _is_picked(st, idx)
		if bool(e.flats) and (not low or str(e.win) != win): want = false
		if want: wanted[idx] = true
		var have := _items.has(idx) and is_instance_valid(_items[idx])
		if want and not have: _spawn(e)
	# anything on the map that is no longer wanted (tide came in, perk changed) goes away
	for idx in _items.keys():
		if not wanted.has(idx): _despawn(int(idx))

func _spawn(e: Dictionary) -> void:
	var p := Pickup.new()
	p.item_id = str(e.id)
	p.gold = bool(e.gold)
	p.idx = int(e.idx)
	p.flats = bool(e.flats)
	p.shore = self
	p.position = e.pos
	_root.add_child(p)
	_items[int(e.idx)] = p

func _despawn(idx: int) -> void:
	var p: Variant = _items.get(idx, null)
	_items.erase(idx)
	if p != null and is_instance_valid(p):
		p.vanish()

func _clear_all() -> void:
	for idx in _items.keys():
		var p: Variant = _items[idx]
		if p != null and is_instance_valid(p): p.queue_free()
	_items.clear()

func item_count() -> int:
	var n := 0
	for idx in _items.keys():
		if is_instance_valid(_items[idx]): n += 1
	return n

# ------------------------------------------------------------------ collecting
## Called by a pickup when it is taken.
func collect(p: Node) -> void:
	var id: String = p.item_id
	var gold: bool = p.gold
	_mark_picked(int(p.idx))
	_items.erase(int(p.idx))
	var info := Dat.entry("SHORE", id)
	var iname := str(info.get("name", id.replace("_", " ").capitalize()))
	var shown := ("Gold " + iname) if gold else iname
	var seen := int(GameState.shore_log.get(id, 0))
	GameState.shore_log[id] = seen + 1
	if gold:
		GameState.shore_log[id + "_gold"] = int(GameState.shore_log.get(id + "_gold", 0)) + 1
	var bottle := bool(info.get("bottle", false))
	if bottle:
		_open_bottle(Dat.i("BOTTLE_YEN", 800))
	else:
		GameState.add_item("shore:" + id + (":gold" if gold else ""), 1)
	if seen == 0:
		GameState.add_sparks(Dat.spark("new_shore", 1), "" if bottle else "new find, %s" % shown)
	elif gold:
		GameState.say("%s! Pip will want this." % shown)
	GameState.catalog_changed.emit()
	GameState.save_soon()

## The next of Ines's notes (in order; after the last, a random one). Also remembers which were read.
func _open_bottle(yen: int) -> void:
	var notes: Array = Dat.a("BOTTLE_NOTES")
	if notes.is_empty(): notes = FALLBACK_NOTES
	var idx := int(GameState.flags.get("bottle_idx", 0))
	var pick := idx if idx < notes.size() else randi() % notes.size()
	GameState.flags["bottle_idx"] = idx + 1
	var read: Array = []
	var v: Variant = GameState.flags.get("bottle_notes", null)
	if v is Array: read = v
	var seen_it := false
	for r in read:
		if int(r) == pick: seen_it = true
	if not seen_it: read.append(pick)
	GameState.flags["bottle_notes"] = read
	GameState.add_coins(yen)
	_show_note(str(notes[pick]), yen)

# ------------------------------------------------------------------ note card (waits for a tap)
func _show_note(text: String, yen: int) -> void:
	if _note_layer != null and is_instance_valid(_note_layer):
		_note_layer.queue_free()
	var layer := CanvasLayer.new()
	layer.layer = 30
	layer.name = "BottleNote"
	add_child(layer)
	_note_layer = layer
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(holder)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_TOP_WIDE)
	center.offset_top = 110.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(456, 0)
	card.add_theme_stylebox_override("panel", Kit.box(Color("f8ecd0"), 22, 3, 18))
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)
	col.add_child(Kit.label("A message in a bottle", 20, Kit.SOFT, false, true))
	var body := Kit.label(text, 24, Kit.INK, true)
	body.custom_minimum_size.x = 400
	col.add_child(body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(Yen.row(yen, 22))
	row.add_child(Kit.label("was tucked inside.", 20, Kit.SOFT))
	col.add_child(row)
	var keep := Kit.button("Keep it", Kit.GREEN, 24, 88, 0.0)
	keep.pressed.connect(_dismiss_note.bind(layer))
	col.add_child(keep)
	card.pivot_offset = Vector2(228, 100)
	card.rotation = -0.03
	card.scale = Vector2(0.85, 0.85)
	card.modulate.a = 0.0
	var tw := card.create_tween().set_parallel(true)
	tw.tween_property(card, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", 1.0, 0.15)

func _dismiss_note(layer: CanvasLayer) -> void:
	if not is_instance_valid(layer): return
	if layer == _note_layer: _note_layer = null
	layer.queue_free()

# ------------------------------------------------------------------ self-test
func _check(name: String, ok: bool) -> void:
	if not ok: _checks_failed += 1
	print("[shore test] %s %s" % ["PASS" if ok else "FAIL", name])

func _count(flats: bool) -> int:
	var n := 0
	for idx in _items.keys():
		var p: Variant = _items[idx]
		if is_instance_valid(p) and bool(p.flats) == flats and not bool(p._taken): n += 1
	return n

## Lowest mesh point of a pickup relative to its origin (metres), to prove it rests on the sand.
func _min_y(p: Node3D) -> float:
	var inv := p.global_transform.affine_inverse()
	var best := INF
	var stack: Array = [p._vis]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children(): stack.append(c)
		if cur is MeshInstance3D and (cur as MeshInstance3D).mesh != null:
			var mi := cur as MeshInstance3D
			var box: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
			best = minf(best, box.position.y)
	return best

func _run_test(a: Dictionary) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not a.has("fresh"):
		print("[shore test] note: pass fresh=1 so the test does not touch your real save")
	Stage.ensure(main, Stage.spot(main, "beach") + Vector3(0, 0, 0.4), Vector3(0, 4.4, 5.4))
	var snap := {"coins": GameState.coins, "bag": GameState.bag.duplicate(true), "log": GameState.shore_log.duplicate(true),
		"sparks": GameState.sparks, "day": GameState.day, "minute": GameState.minute, "flags": GameState.flags.duplicate(true)}
	GameState.minute = GameState.DAY_START
	_sync()
	await get_tree().create_timer(0.6).timeout
	var beach_n := Dat.i("SHORE_BEACH_DAILY", 14)
	var flats_n := Dat.i("SHORE_FLATS_DAILY", 6)
	_check("daily beach items spawn (%d)" % beach_n, _count(false) == beach_n)
	_check("tide flats items spawn at low tide (%d)" % flats_n, _count(true) == int(round(flats_n * _flats_mult())))
	var worst := 0.0
	for idx in _items.keys():
		var y := _min_y(_items[idx])
		worst = maxf(worst, absf(y - 0.0))
	_check("every pickup rests on the sand (lowest point within 2 cm, worst %.3f)" % worst, worst <= 0.02)
	# pick one up
	var first: Node = null
	for idx in _items.keys():
		if not bool(_items[idx].flats): first = _items[idx]; break
	var sparks0 := GameState.sparks
	var id: String = first.item_id
	var key := "shore:" + id + (":gold" if first.gold else "")
	var before_idx := int(first.idx)
	var is_bottle := bool(Dat.entry("SHORE", id).get("bottle", false))
	first.interact(null)
	_check("pick up adds to the bag (or opens a bottle)", GameState.has_item(key) or is_bottle)
	_check("pick up counts in shore_log", int(GameState.shore_log.get(id, 0)) == 1)
	_check("first of a kind gives a spark", GameState.sparks == sparks0 + Dat.spark("new_shore", 1))
	_check("pickup prompt is gone once taken", first.get_prompt(null) == "")
	var total_before := item_count()
	# reload: nothing taken respawns
	_clear_all(); _planned_day = -1; _sync()
	_check("picked items do not respawn after a reload", not _items.has(before_idx) and item_count() == total_before)
	# tides: flats are covered at high tide, a fresh set appears at the evening low tide
	var morning_ids: Array = []
	for idx in _items.keys():
		if bool(_items[idx].flats): morning_ids.append(int(idx))
	GameState.minute = 12.0 * 60.0
	_sync()
	await get_tree().create_timer(0.6).timeout
	_check("flats are covered at high tide", _count(true) == 0)
	GameState.minute = 18.5 * 60.0
	_sync()
	await get_tree().create_timer(0.1).timeout
	var evening_ok := _count(true) > 0
	for idx in _items.keys():
		if bool(_items[idx].flats) and int(idx) in morning_ids: evening_ok = false
	_check("a fresh set of flats items appears at the evening low tide", evening_ok)
	# gold + bottle
	var g := Pickup.new()
	g.item_id = "shell_white"; g.gold = true; g.idx = 900
	var gold_before := int(GameState.bag.get("shore:shell_white:gold", 0))
	collect(g)
	_check("gold variant goes into the bag as :gold", int(GameState.bag.get("shore:shell_white:gold", 0)) == gold_before + 1 and int(GameState.shore_log.get("shell_white_gold", 0)) == 1)
	g.free()
	GameState.flags.erase("bottle_idx")
	var notes: Array = Dat.a("BOTTLE_NOTES")
	var b := Pickup.new()
	b.item_id = "bottle"; b.idx = 901
	var coins0 := GameState.coins
	collect(b)
	_check("bottle pays BOTTLE_YEN and opens a note", GameState.coins == coins0 + Dat.i("BOTTLE_YEN", 800) and _note_layer != null and not GameState.has_item("shore:bottle"))
	_check("the first bottle holds the first note", notes.is_empty() or int(GameState.flags.get("bottle_idx", 0)) == 1 and (GameState.flags.get("bottle_notes", []) as Array).has(0))
	_check("the note card waits for a tap", _note_layer != null and is_instance_valid(_note_layer))
	b.free()
	# new day: everything resets
	var d0 := GameState.day
	GameState.day += 1
	GameState.minute = GameState.DAY_START
	_sync()
	await get_tree().create_timer(0.1).timeout
	_check("a new day spawns a fresh set", _count(false) == beach_n and int(_state().day) == d0 + 1 and (_state().picked as Array).is_empty())
	# restore + showcase for the screenshot
	GameState.day = int(snap.day); GameState.minute = float(snap.minute)
	GameState.coins = int(snap.coins); GameState.bag = snap.bag; GameState.shore_log = snap.log
	GameState.sparks = int(snap.sparks); GameState.flags = snap.flags
	GameState.minute = GameState.DAY_START
	GameState.bag_changed.emit()
	if _note_layer != null and is_instance_valid(_note_layer): _note_layer.queue_free()
	_note_layer = null
	_showcase = true
	_clear_all(); _planned_day = -1
	_sync()
	if a.has("note"):
		_open_bottle(Dat.i("BOTTLE_YEN", 800))
	print("[shore test] done, failures: %d" % _checks_failed)
