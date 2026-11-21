extends PanelContainer
## ShopPanel: Pip's General Store. Two tabs.
##   Sell: every fish / shore item in the bag with its price, "Sell 1" and "Sell all" (gold sells x5).
##   Buy:  Data.SHOP grouped as treats, rods and cosmetics. Rods set GameState.rod_level, cosmetics go
##         into GameState.cosmetics (and "equipped"), treats go into the bag.
## Opened by the Town system (through main.hud.open_panel when the HUD exists). Emits `closed` when the
## player taps Close (or presses Escape). All money is shown as yen with a green paper note.

signal closed

const Dat := preload("res://scripts/systems/town/dat.gd")
const Eco := preload("res://scripts/systems/town/economy.gd")
const Yen := preload("res://scripts/systems/town/yen.gd")
const Kit := preload("res://scripts/systems/town/kit.gd")
const ItemIcon := preload("res://scripts/systems/town/item_icon.gd")

const PANEL_W := 504.0
const PANEL_H := 860.0

const GREETINGS := [
	"Pip: Sell, buy, or just stand there. All fine.",
	"Pip: Mind the cat on the doormat. He is staff.",
	"Pip: Good morning. Or whatever this is.",
	"Pip: Take your time. The shop is not going anywhere.",
]
const SALE_LINES := [
	"Pip nods. Efficient.",
	"Pip counts it twice, to be polite.",
	"Pip: Lovely. I will put it somewhere dramatic.",
	"Pip squints at it, then pays.",
]
const BIG_SALE_LINES := [
	"Pip says that is a suspiciously large haul.",
	"Pip pays up, visibly wounded.",
]
const GOLD_LINES := [
	"Pip holds it up to the light for a very long time.",
	"Pip goes quiet, then very polite.",
]
const NIGHT_GREETINGS := [
	"Pip comes down in a dressing gown. 'Make it quick.'",
	"Pip: It is night. I am open. Spiritually.",
	"Pip squints at the clock, then at you, then opens the till.",
]
const BUY_LINES := [
	"Pip: Excellent choice. He says that every time.",
	"Pip wraps it in paper you did not ask for.",
	"Pip: No refunds, but a lot of sympathy.",
]

var night := false                # set before adding: the bell was rung after hours
var _tab := "sell"
var _scroll: ScrollContainer
var _list: VBoxContainer
var _money: HBoxContainer
var _bubble: Label
var _tab_btns := {}
var _dirty := false
var _closing := false
var _rng := RandomNumberGenerator.new()

func _init(start_tab := "sell") -> void:
	_tab = start_tab if start_tab in ["sell", "buy"] else "sell"
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	add_theme_stylebox_override("panel", Kit.box(Kit.CREAM, 26, 3, 14))
	_rng.randomize()

func _ready() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	# header: title + money, close button
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var tcol := VBoxContainer.new()
	tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tcol.alignment = BoxContainer.ALIGNMENT_CENTER
	tcol.add_theme_constant_override("separation", 2)
	tcol.add_child(Kit.label("Pip's General Store", 28, Kit.INK, false, true))
	_money = Yen.row(GameState.coins, 24)
	tcol.add_child(_money)
	head.add_child(tcol)
	var close := Kit.button("Close", Kit.PEACH, 24, 88, 124)
	close.pressed.connect(_close)
	head.add_child(close)
	root.add_child(head)

	# tabs
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	for t in ["sell", "buy"]:
		var b := Kit.button("Sell" if t == "sell" else "Buy", Kit.CREAM, 26)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_set_tab.bind(t))
		_tab_btns[t] = b
		tabs.add_child(b)
	root.add_child(tabs)

	# list
	_scroll = Kit.scroll()
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	root.add_child(_scroll)

	# Pip's line
	var bub := Kit.card(Kit.ROW, 10, 16, 2)
	_bubble = Kit.label(_pick(NIGHT_GREETINGS if night else GREETINGS), 20, Kit.INK, true)
	_bubble.custom_minimum_size = Vector2(0, 52)
	_bubble.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bub.add_child(_bubble)
	root.add_child(bub)

	GameState.coins_changed.connect(_on_coins)
	GameState.bag_changed.connect(_queue_rebuild)
	_refresh_tabs()
	_rebuild()
	Kit.pop_in(self)

func _input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()

func _close() -> void:
	if _closing: return
	_closing = true
	closed.emit()

func _pick(lines: Array) -> String:
	return str(lines[_rng.randi() % lines.size()])

func _say(text: String) -> void:
	if _bubble == null: return
	_bubble.text = text
	_bubble.modulate.a = 0.2
	create_tween().tween_property(_bubble, "modulate:a", 1.0, 0.18)

# ------------------------------------------------------------------ tabs and rebuilding
func _set_tab(t: String) -> void:
	if _tab == t: return
	_tab = t
	_scroll.scroll_vertical = 0
	_refresh_tabs()
	_rebuild()

func _refresh_tabs() -> void:
	for t in _tab_btns.keys():
		var b: Button = _tab_btns[t]
		Kit.restyle(b, Kit.PEACH if t == _tab else Kit.CREAM)

func _on_coins(c: int) -> void:
	if _money != null:
		Yen.set_amount(_money, c)
		_money.pivot_offset = Vector2(0, _money.size.y * 0.5)
		var tw := create_tween()
		tw.tween_property(_money, "scale", Vector2(1.12, 1.12), 0.07)
		tw.tween_property(_money, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _tab == "buy": _queue_rebuild()

func _queue_rebuild() -> void:
	if _dirty: return
	_dirty = true
	_rebuild_now.call_deferred()

func _rebuild_now() -> void:
	_dirty = false
	_rebuild()

func _rebuild() -> void:
	if _list == null or not is_inside_tree(): return
	var keep := _scroll.scroll_vertical
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	if _tab == "sell": _build_sell()
	else: _build_buy()
	_restore_scroll.call_deferred(keep)

func _restore_scroll(v: int) -> void:
	if is_instance_valid(_scroll):
		await get_tree().process_frame
		if is_instance_valid(_scroll): _scroll.scroll_vertical = v

func _note_card(text: String) -> Control:
	var card := Kit.card(Kit.ROW, 16, 20, 2)
	var l := Kit.label(text, 22, Kit.SOFT, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(l)
	return card

func _header(text: String) -> Control:
	var l := Kit.label(text, 20, Kit.SOFT)
	l.custom_minimum_size.y = 28
	return l

# ------------------------------------------------------------------ sell tab
func _mult_text() -> String:
	return ("%.1f" % Eco.special_mult()).trim_suffix(".0")

func _special_card() -> Control:
	var sid := Eco.special_id()
	var info := Eco.describe("fish:" + sid)
	var card := Kit.card(Kit.HILITE, 10, 18, 2)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	card.add_child(h)
	var ic := ItemIcon.new("fish", info.c1, info.c2)
	ic.custom_minimum_size = Vector2(44, 44)
	h.add_child(ic)
	h.add_child(Kit.label("Today Pip pays x%s for %s." % [_mult_text(), str(info.name)], 20, Kit.INK, true))
	return card

func _build_sell() -> void:
	var keys := Eco.sellable_keys()
	if Eco.special_id() != "":
		_list.add_child(_special_card())
	if keys.is_empty():
		_list.add_child(_note_card("Your bag has nothing Pip wants right now. Fish, or comb the shore, and come back."))
		return
	for key in keys:
		_list.add_child(_sell_row(str(key)))

func _sell_row(key: String) -> Control:
	var info := Eco.describe(key)
	var count := int(GameState.bag.get(key, 0))
	var price := int(info.price)
	var gold: bool = info.gold
	var card := Kit.card(Kit.HILITE if gold else Kit.ROW, 12, 20, 2)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	card.add_child(h)
	h.add_child(ItemIcon.new(info.icon, info.c1, info.c2, gold))

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 2)
	mid.add_child(Kit.label(str(info.name), 22, Kit.INK, true, true))
	var sub := HBoxContainer.new()
	sub.add_theme_constant_override("separation", 8)
	sub.add_child(Kit.label("x%d" % count, 20, Kit.SOFT))
	sub.add_child(Yen.row(price, 20))
	mid.add_child(sub)
	if bool(info.special):
		mid.add_child(Kit.chip("Special x%s" % _mult_text(), Kit.GOLD, Kit.INK, 15))
	h.add_child(mid)

	var one := Kit.button("Sell 1\n%s" % Yen.fmt(price), Kit.GREEN, 20, 88, 104 if count > 1 else 236)
	one.pressed.connect(_sell.bind(key, 1))
	h.add_child(one)
	if count > 1:
		var all := Kit.button("Sell all\n%s" % Yen.fmt(price * count), Kit.GREEN, 20, 88, 124)
		all.pressed.connect(_sell.bind(key, count))
		h.add_child(all)
	return card

func _sell(key: String, n: int) -> void:
	var info := Eco.describe(key)
	var got := Eco.sell(key, n)
	if got <= 0:
		_say("Pip shrugs. That one is not for sale.")
		return
	var head := "Sold %d %s for %s." % [n, str(info.name), Yen.fmt(got)] if n > 1 else "Sold %s for %s." % [str(info.name), Yen.fmt(got)]
	var quip := _pick(GOLD_LINES) if bool(info.gold) else (_pick(BIG_SALE_LINES) if got >= 3000 else _pick(SALE_LINES))
	if bool(info.special): quip = "Pip pays the special rate, wincing."
	_say(head + "\n" + quip)
	_queue_rebuild()

# ------------------------------------------------------------------ buy tab
func _build_buy() -> void:
	var ids := Eco.shop_ids()
	if ids.is_empty():
		_list.add_child(_note_card("The shelves are empty today. Pip says it is a mood."))
		return
	var last_kind := ""
	for id in ids:
		var e := Dat.entry("SHOP", str(id))
		var kind := str(e.get("kind", "other"))
		if kind != last_kind:
			last_kind = kind
			var titles := {"treat": "Treats for cats", "rod": "Rods", "cosmetic": "Cosmetics"}
			_list.add_child(_header(str(titles.get(kind, "More"))))
		_list.add_child(_buy_row(str(id), e))

func _buy_icon(id: String, e: Dictionary) -> Control:
	var kind := str(e.get("kind", ""))
	var col := Dat.col(e.get("color", "c9b08a"))
	match kind:
		"treat": return ItemIcon.new("treat", Color("e7c48f"), Color("b98a52"))
		"rod": return ItemIcon.new("rod", Color("c98a5a"), col.darkened(0.05) if e.has("color") else Color("8fd3a4"))
		"cosmetic":
			var slot := str(e.get("slot", ""))
			var k := "scarf" if slot == "scarf" else ("cap" if slot == "hat" else ("paint" if slot == "paint" else "dot"))
			return ItemIcon.new(k, col, col.darkened(0.3))
	return ItemIcon.new("dot", col, col.darkened(0.3))

func _buy_row(id: String, e: Dictionary) -> Control:
	var kind := str(e.get("kind", ""))
	var price := Eco.buy_price(id)
	var owned := Eco.owned(id)
	var afford := GameState.coins >= price
	var card := Kit.card(Kit.ROW, 12, 20, 2)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	card.add_child(h)
	h.add_child(_buy_icon(id, e))

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 2)
	mid.add_child(Kit.label(str(e.get("name", id)), 22, Kit.INK, true, true))
	var desc := str(e.get("desc", ""))
	var lock := Eco.lock_reason(id)
	if kind == "treat":
		desc = "You have %d." % int(GameState.bag.get(id, 0))
	elif kind == "cosmetic" and desc == "":
		desc = "Worn by Mocha."
	if lock != "" and not owned: desc = lock
	if desc != "":
		mid.add_child(Kit.label(desc, 18, Kit.SOFT, true))
	if not owned or kind == "treat":
		var pr := Yen.row(price, 22, Kit.INK if afford else Kit.PINK)
		mid.add_child(pr)
	h.add_child(mid)

	var btn: Button
	if kind == "rod" and owned:
		btn = Kit.button("Owned", Kit.GREEN, 22, 88, 124)
		Kit.set_enabled(btn, false)
	elif kind == "rod" and lock != "":
		btn = Kit.button("Locked", Kit.GREEN, 22, 88, 124)
		Kit.set_enabled(btn, false)
	elif kind == "cosmetic" and owned:
		var on := Eco.is_equipped(id)
		btn = Kit.button("Take off" if on else "Wear", Kit.CREAM if on else Kit.PEACH, 22, 88, 124)
		btn.pressed.connect(_wear.bind(id, not on))
	else:
		btn = Kit.button("Buy", Kit.GREEN, 24, 88, 124)
		Kit.set_enabled(btn, afford)
		btn.pressed.connect(_buy.bind(id))
	h.add_child(btn)
	return card

func _buy(id: String) -> void:
	var e := Dat.entry("SHOP", id)
	var res := Eco.buy(id)
	if bool(res.ok):
		var extra := ""
		match str(e.get("kind", "")):
			"rod": extra = " Fish will notice."
			"cosmetic": extra = " Mocha is wearing it already."
			"treat": extra = " The cats have been told."
		_say(str(res.msg) + extra + "\n" + _pick(BUY_LINES))
	else:
		_say(str(res.msg))
	_queue_rebuild()

func _wear(id: String, on: bool) -> void:
	Eco.equip(id, on)
	var name := str(Dat.entry("SHOP", id).get("name", id))
	_say(("Mocha puts on the %s." if on else "Mocha takes off the %s.") % name)
	_queue_rebuild()
