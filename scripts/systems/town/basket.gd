extends Node3D
## Fern's basket next to the request board (perks daily_flower, catnip_gift, moonflower). Interactable: "Take ...".
## State lives in GameState.flags["basket"] = {"stock": {item id: 1}, "last": {perk id: day it was last stocked}, "told": bool}
## so it survives saves. People refills it each morning through put_if_due() (one item per perk per period, the perk value
## is the number of days); the basket never piles up, an untouched flower just waits.

const Eco := preload("res://scripts/systems/town/economy.gd")

## perk id -> bag item that perk leaves in the basket.
const GIFTS := {"daily_flower": "flower:sea_pink", "catnip_gift": "treat:catnip", "moonflower": "flower:moonflower"}

var interact_radius := 1.7
var interact_priority := 3

var _vis: Node3D
var _marker: Node3D
var _sig := "?"
var _poll := 0.0
var _t := 0.0

# ------------------------------------------------------------------ state (static: People and the tests use these too)
static func _data() -> Dictionary:
	var d: Variant = GameState.flags.get("basket", null)
	if not (d is Dictionary):
		d = {}
		GameState.flags["basket"] = d
	if not (d.get("stock", null) is Dictionary): d["stock"] = {}
	if not (d.get("last", null) is Dictionary): d["last"] = {}
	return d

## Who holds a perk right now ("" = nobody). Reads the saved state only, so it never creates people entries.
static func holder(perk: String) -> String:
	for id in GameState.people.keys():
		var st: Variant = GameState.people[id]
		if st is Dictionary and st.get("perks", []) is Array and perk in st.get("perks", []): return str(id)
	return ""

## True once any gift perk is unlocked (before that there is no basket to see).
static func unlocked() -> bool:
	for perk in GIFTS.keys():
		if holder(str(perk)) != "": return true
	return false

## Stock the perk's item when `every` days have passed since the last time. Returns true when something was added.
static func put_if_due(perk: String, every: int) -> bool:
	if not GIFTS.has(perk): return false
	var d := _data()
	var last := int(d.last.get(perk, -999))
	if GameState.day - last < maxi(1, every): return false
	d.last[perk] = GameState.day
	d.stock[str(GIFTS[perk])] = 1
	return true

## First time the basket gets anything: tell the player where it is (once).
static func first_time() -> bool:
	var d := _data()
	if bool(d.get("told", false)): return false
	d["told"] = true
	return true

## Item ids waiting in the basket, in GIFTS order.
static func items() -> Array:
	var out: Array = []
	var stock: Dictionary = _data().stock
	for perk in GIFTS.keys():
		var it := str(GIFTS[perk])
		if int(stock.get(it, 0)) > 0: out.append(it)
	return out

## Move everything into the bag. Returns the item ids taken.
static func take_all() -> Array:
	var got := items()
	var stock: Dictionary = _data().stock
	for it in got:
		stock.erase(it)
		GameState.add_item(str(it), 1)
	if not got.is_empty(): GameState.save_soon()
	return got

static func item_name(item: String) -> String:
	return str(Eco.describe(item).get("name", item))

# ------------------------------------------------------------------ interactable
func _ready() -> void:
	add_to_group("interactable")
	_build()
	_refresh()

func get_prompt(_player: Variant) -> String:
	if not visible: return ""
	var got := items()
	if got.is_empty(): return ""
	return "Take " + item_name(str(got[0])) if got.size() == 1 else "Take from basket"

func interact(_player: Variant) -> void:
	var got := take_all()
	if got.is_empty(): return
	var names: Array = []
	for it in got: names.append(item_name(str(it)))
	GameState.say("Took " + ", ".join(names) + ".")
	_refresh()
	if _vis != null:
		_vis.scale = Vector3.ONE * 1.18
		create_tween().tween_property(_vis, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ------------------------------------------------------------------ look
func _process(dt: float) -> void:
	_t += dt
	_poll -= dt
	if _poll <= 0.0:
		_poll = 0.5
		_refresh()
	if _marker != null and _marker.visible:
		_marker.position.y = 0.95 + sin(_t * 3.0) * 0.06
		_marker.rotation.y += dt * 1.6

func _refresh() -> void:
	var sig := "%s|%s" % [str(unlocked()), ",".join(PackedStringArray(items()))]
	if sig == _sig: return
	_sig = sig
	visible = unlocked()
	_build()

func _build() -> void:
	if _vis != null and is_instance_valid(_vis):
		remove_child(_vis)
		_vis.queue_free()
	_vis = Toys.group(Vector3.ZERO, self)
	var wicker := Toys.mat(Color("c99a5b"), 0.9, 0.02)
	var dark := Toys.mat(Color("a9783f"), 0.9, 0.02)
	Toys.add(Toys.cyl(0.34, 0.27, 0.3, 14), wicker, Vector3(0, 0.15, 0), _vis)
	Toys.add(Toys.torus(0.31, 0.37), dark, Vector3(0, 0.3, 0), _vis, Vector3(1, 0.8, 1))   # rim
	for i in 3:   # woven bands follow the taper (radius 0.27 at the foot, 0.34 at the rim)
		var y := 0.06 + i * 0.08
		var rc := 0.27 + y / 0.3 * 0.07 + 0.006
		Toys.add(Toys.torus(rc - 0.014, rc + 0.014), dark, Vector3(0, y, 0), _vis, Vector3(1, 0.7, 1))
	Toys.add(Toys.torus(0.285, 0.315), dark, Vector3(0, 0.3, 0), _vis, Vector3.ONE, Vector3(PI * 0.5, 0, 0))   # handle arch
	var got := items()
	var n := 0
	for it in got:
		_add_gift(str(it), n)
		n += 1
	_marker = Toys.group(Vector3(0, 0.95, 0), _vis)
	Toys.add(Toys.sphere(0.07, 10), Toys.glow(Color("f2c14e"), 1.6), Vector3.ZERO, _marker, Vector3(1, 1.4, 1))
	_marker.visible = not got.is_empty()

## One item sticking out of the basket: flowers on stems, catnip as green leaves, moonflower as a pale glow.
func _add_gift(item: String, slot: int) -> void:
	var info := Eco.describe(item)
	var col: Color = info.get("c1", Color("f2a0b8"))
	var ox := (slot - 0.5) * 0.2
	if item.begins_with("treat:"):
		var leaf := Toys.mat(Color("8fca7e"), 0.9, 0.012)
		for i in 4:
			var a := i * TAU / 4.0 + slot
			Toys.add(Toys.sphere(0.09, 8), leaf, Vector3(ox + cos(a) * 0.1, 0.4 + 0.06 * (i % 2), sin(a) * 0.1), _vis, Vector3(1, 0.6, 1))
		return
	var head := Toys.glow(col, 1.2) if item.contains("moon") else Toys.mat(col, 0.9, 0.012)
	for i in 3:
		var a := i * TAU / 3.0 + slot * 0.8
		var x := ox + cos(a) * 0.12
		var z := sin(a) * 0.12
		Toys.add(Toys.cyl(0.01, 0.012, 0.3, 5), Toys.mat(Color("7fb87a"), 0.9, 0.0), Vector3(x, 0.45, z), _vis)
		Toys.add(Toys.sphere(0.075, 10), head, Vector3(x, 0.62 + 0.03 * i, z), _vis, Vector3(1, 0.7, 1))
