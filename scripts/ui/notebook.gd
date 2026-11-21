extends PanelContainer
## Notebook: the player's keepsake book. Tabs: Cats, People, Fish, Shore, Requests, Bag (+ Settings page behind
## the gear). Everything is read from GameState + Data defensively, so a missing field never breaks a page.
## Opened by the Hud (Notebook button, Tab key). Emits close_requested for its close button.

signal close_requested

const CatPortraits := preload("res://scripts/ui/hud/cat_portraits.gd")
const PEOPLE_FALLBACK := "res://scripts/systems/people/people_data.gd"
const CREDITS := "Music: Coffee Jazz by Aurec, Cozy Relax Jazz by Denis Pavlov Music (Pixabay)"

const TAB_DEFS := [
	["cats", "Cats", "cat"],
	["people", "People", "person"],
	["fish", "Fish", "fish"],
	["shore", "Shore", "shell"],
	["requests", "Requests", "note"],
	["bag", "Bag", "bag"],
]
const SPOT_NAMES := {"home": "the porch", "plaza": "the plaza", "shop": "Pip's shop", "shop_counter": "the shop counter",
	"pier": "the pier", "pier_end": "the pier end", "beach": "the beach", "hill": "the hill", "lighthouse": "the lighthouse",
	"rocks": "the rocks", "flats": "the tide flats", "porch": "the porch"}

var test_people := {}                # test hook: fake PEOPLE table

var _tab := "cats"
var _w := 524.0
var _h := 880.0
var _title: Label
var _tabs := {}                      # id -> TabButton
var _tab_row: HBoxContainer
var _scroll: ScrollContainer
var _list: VBoxContainer
var _portraits: Node

func _init() -> void:
	theme = Style.theme()
	add_theme_stylebox_override("panel", Style.panel_box(Style.CREAM, 28, 3, 14))
	set_meta("own_close", true)
	pivot_offset_ratio = Vector2(0.5, 0.5)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	# header: book icon, title, gear, close
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.custom_minimum_size.y = Style.MIN_TOUCH
	root.add_child(head)
	head.add_child(Style.spacer(0, 6))
	var bi := Style.icon("book", 42.0)
	bi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(bi)
	_title = Style.label("Notebook", 33, Style.INK, true)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title.clip_text = true
	head.add_child(_title)
	var gear := Style.icon_button("gear", "cream", 64.0)
	gear.pressed.connect(func() -> void: show_tab("settings" if _tab != "settings" else "cats"))
	head.add_child(gear)
	var close := Style.icon_button("close", "primary", 64.0)
	close.pressed.connect(func() -> void: close_requested.emit())
	head.add_child(close)

	# content
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = false
	root.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	_scroll.add_child(_list)

	# tabs at the bottom (thumb reach)
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 4)
	root.add_child(_tab_row)

	_portraits = CatPortraits.new()
	add_child(_portraits)

	GameState.catalog_changed.connect(_on_data_changed)
	GameState.bag_changed.connect(_on_data_changed)
	GameState.people_changed.connect(_on_data_changed)
	custom_minimum_size = Vector2(_w, _h)

func _enter_tree() -> void:
	_rebuild_tabs()
	_refresh()

func _on_data_changed() -> void:
	if is_inside_tree() and visible: _refresh()

## Size the book for the current screen (the Hud calls this before opening it).
func fit(vp: Vector2) -> void:
	_w = minf(vp.x - 16.0, 524.0)
	_h = minf(vp.y - 56.0, 880.0)
	custom_minimum_size = Vector2(_w, _h)
	size = custom_minimum_size

func show_tab(id: String) -> void:
	if id != "settings" and not _tab_visible(id): id = "cats"
	_tab = id
	if is_inside_tree(): _refresh()

# ------------------------------------------------------------------ tabs
func _tab_visible(id: String) -> bool:
	if id == "people": return not _people_defs().is_empty()
	for d in TAB_DEFS:
		if d[0] == id: return true
	return false

func _rebuild_tabs() -> void:
	for c in _tab_row.get_children():
		_tab_row.remove_child(c)
		c.queue_free()
	_tabs.clear()
	var defs: Array = []
	for d in TAB_DEFS:
		if _tab_visible(d[0]): defs.append(d)
	var tw := (_w - 28.0 - 4.0 * float(defs.size() - 1)) / float(maxi(defs.size(), 1))
	for d in defs:
		var b := TabButton.new()
		b.setup(d[0], d[1], d[2], tw)
		b.pressed.connect(show_tab.bind(d[0]))
		_tab_row.add_child(b)
		_tabs[d[0]] = b

func _refresh() -> void:
	if _tab != "settings" and not _tab_visible(_tab): _tab = "cats"
	for id in _tabs:
		_tabs[id].set_selected(id == _tab)
	_title.text = "Settings" if _tab == "settings" else "Notebook"
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_scroll.scroll_vertical = 0
	match _tab:
		"cats": _page_cats()
		"people": _page_people()
		"fish": _page_fish()
		"shore": _page_shore()
		"requests": _page_requests()
		"bag": _page_bag()
		"settings": _page_settings()

## Inner width available to cards (panel minus margins, scroll bar).
func _cw() -> float:
	return _w - 28.0 - 16.0

# ------------------------------------------------------------------ small builders
func _card(bg := Style.CREAM_DEEP, border := 2, margin := 12, radius := 20) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_theme_stylebox_override("panel", Style.panel_box(bg, radius, border, margin, false))
	return p

func _summary(left: String, right := "") -> Control:
	var c := _card(Color("e3efe6"), 2, 14, 18)
	var h := HBoxContainer.new()
	c.add_child(h)
	var l := Style.label(left, 22, Style.INK, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	h.add_child(l)
	if right != "": h.add_child(Style.label(right, 20, Style.INK_SOFT, true))
	return c

func _wrap_label(text: String, size: int, color: Color, width: float, bold := false) -> Label:
	var l := Style.label(text, size, color, bold)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	return l

func _note(text: String) -> Control:
	var c := _card(Style.CREAM_DEEP, 2, 18, 20)
	var l := _wrap_label(text, 20, Style.INK_SOFT, _cw() - 40.0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(l)
	return c

func _pretty(s: String) -> String:
	return s.replace("_", " ").replace(":", " ").capitalize()

func _hex(s: Variant, fallback: Color) -> Color:
	return Color.from_string(str(s), fallback)

func _cm(v: float) -> String:
	var r := snappedf(v, 0.1)
	return ("%d cm" % int(r)) if is_equal_approx(r, roundf(r)) else ("%.1f cm" % r)

## Name, icon and tint for a bag/catalog item id ("fish:sardine", "shore:shell_white", "treat:cream", "flower:sea_pink").
func _item(item_id: String) -> Dictionary:
	var parts := item_id.split(":", true, 1)
	var kind := parts[0]
	var key := parts[1] if parts.size() > 1 else parts[0]
	var gold := key.ends_with(":gold")
	if gold: key = key.trim_suffix(":gold")
	var out := {"name": _pretty(key), "icon": "bag", "tint": Color(0, 0, 0, 0), "group": "Other"}
	match kind:
		"fish":
			var f: Dictionary = Data.FISH.get(key, {})
			out = {"name": str(f.get("name", _pretty(key))), "icon": "fish", "tint": _hex(f.get("body", "8cc3d6"), Color("8cc3d6")), "group": "Fish"}
		"shore":
			var s: Dictionary = Data.SHORE.get(key, {})
			out = {"name": str(s.get("name", _pretty(key))), "icon": _shore_icon(key), "tint": _hex(s.get("color", "f6b8c4"), Color("f6b8c4")), "group": "Shore"}
		"treat":
			var t: Dictionary = Data.SHOP.get(item_id, {})
			out = {"name": str(t.get("name", _pretty(key))), "icon": "paw", "tint": Color("f2cf9c"), "group": "Treats"}
		"flower":
			var fl: Dictionary = Data.get("ITEMS").get(item_id, {}) if Data.get("ITEMS") is Dictionary else {}
			out = {"name": str(fl.get("name", _pretty(key))), "icon": "flower", "tint": _hex(fl.get("color", "f2a0b8"), Color("f2a0b8")), "group": "Gifts"}
		_:
			var o: Dictionary = Data.SHOP.get(item_id, {})
			if o.is_empty() and Data.get("ITEMS") is Dictionary: o = Data.get("ITEMS").get(item_id, {})
			out["name"] = str(o.get("name", _pretty(key)))
	if gold:
		out["name"] = "Gold " + str(out["name"])
		out["tint"] = Style.GOLD
	return out

func _shore_icon(id: String) -> String:
	if id.contains("glass"): return "glass"
	if id.contains("wood"): return "wood"
	if id.contains("star"): return "star"
	if id.contains("bottle"): return "bottle"
	if id.contains("dollar"): return "dollar"
	return "shell"

func _item_name(item_id: String) -> String:
	return str(_item(item_id).get("name", item_id))

# ------------------------------------------------------------------ Cats
func _cat_met(st: Dictionary) -> bool:
	if int(st.get("hearts", 0)) > 0 or bool(st.get("friend", false)): return true
	if st.get("facts", []) is Array and not (st.get("facts", []) as Array).is_empty(): return true
	for k in ["last_pet_day", "last_sit_day", "last_treat_day"]:
		if int(st.get(k, 0)) > 0: return true
	return false

func _page_cats() -> void:
	var met := 0
	var friends := 0
	var ids: Array = Data.CATS.keys()
	for id in ids:
		var st = GameState.cats.get(id, {})
		if st is Dictionary and _cat_met(st):
			met += 1
			if bool(st.get("friend", false)) or int(st.get("hearts", 0)) >= int(Data.CAT_MAX_HEARTS): friends += 1
	_list.add_child(_summary("Met %d of %d cats" % [met, ids.size()], "Friends %d" % friends))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_list.add_child(grid)
	var cw := (_cw() - 10.0) * 0.5
	for id in ids:
		grid.add_child(_cat_card(str(id), Data.CATS[id], cw))

func _cat_card(id: String, def: Dictionary, card_w: float) -> Control:
	var st = GameState.cats.get(id, {})
	if not (st is Dictionary): st = {}
	var met := _cat_met(st)
	var hearts := clampi(int(st.get("hearts", 0)), 0, int(Data.CAT_MAX_HEARTS))
	var friend := bool(st.get("friend", false)) or hearts >= int(Data.CAT_MAX_HEARTS)
	var card := _card(Color("fff3d4") if friend else Style.CREAM_DEEP, 3 if friend else 2, 12, 22)
	card.custom_minimum_size.x = card_w
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var inner := card_w - 24.0 - 6.0
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	card.add_child(vb)

	vb.add_child(_portrait(id, def, met))
	var name_l := Style.label(str(def.get("name", _pretty(id))) if met else "???", 23, Style.INK, true)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.clip_text = true
	vb.add_child(name_l)
	if not met:
		var r := _wrap_label(str(def.get("rumour", "Nobody knows much about this one.")), 18, Style.INK_SOFT, inner)
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(r)
		return card

	var sub := HBoxContainer.new()
	sub.alignment = BoxContainer.ALIGNMENT_CENTER
	sub.add_theme_constant_override("separation", 8)
	sub.add_child(Style.label(str(def.get("personality", "")), 18, Style.INK_SOFT))
	if friend: sub.add_child(Style.chip("Friend", Style.GOLD, Style.INK, 16))
	vb.add_child(sub)
	var hh := Style.hearts(hearts, int(Data.CAT_MAX_HEARTS), 27.0, 2)
	hh.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(hh)
	vb.add_child(Style.spacer(4))
	for line in _cat_fact_lines(id, def, st):
		vb.add_child(_fact_row(line[0], line[1], inner))
	return card

func _portrait(id: String, def: Dictionary, met: bool) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(124, 124)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var disc := Panel.new()
	disc.set_anchors_preset(Control.PRESET_FULL_RECT)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("dcefec") if met else Style.CREAM_SHADE
	sb.border_color = Style.INK; sb.set_border_width_all(3)
	sb.set_corner_radius_all(62); sb.set_corner_detail(16)
	disc.add_theme_stylebox_override("panel", sb)
	holder.add_child(disc)
	var tint := _hex(def.get("main", "f2cf9c"), Color("f2cf9c")) if met else Color("b7a392")
	var fallback := Style.icon("cat", 80.0, tint)
	fallback.position = Vector2(22, 26)
	holder.add_child(fallback)
	var tr := TextureRect.new()
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(tr)
	if _portraits and _portraits.has_method("request"):
		_portraits.request(id, not met, tr, fallback)
	return holder

func _fact_row(icon_name: String, text: String, width: float) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var ic := Style.icon(icon_name, 20.0)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ic.custom_minimum_size.y = 24.0
	h.add_child(ic)
	var dim := icon_name == "lock"
	h.add_child(_wrap_label(text, 17, Style.INK_SOFT if dim else Style.INK, width - 26.0))
	return h

## [[icon, text], ...] of what the player has noticed about a cat.
func _cat_fact_lines(id: String, def: Dictionary, st: Dictionary) -> Array:
	var facts: Array = st.get("facts", []) if st.get("facts", []) is Array else []
	var out: Array = []
	var haunts: Array = []
	var has_fav := false
	var has_secret := false
	var hint := false
	for f in facts:
		var fs := str(f)
		if fs.begins_with("haunt:"):
			var slot := fs.substr(6)
			var hs: Dictionary = def.get("haunts", {})
			var sp := ""
			if slot == "rain": sp = _spot(str(def.get("rain_spot", ""))) + " in rain"
			elif hs.has(slot): sp = _spot(str(hs[slot]))
			if sp != "" and not (sp in haunts): haunts.append(sp)
		elif fs == "favourite":
			has_fav = true
		elif fs == "favourite_hint":
			hint = true
		elif fs == "secret":
			has_secret = true
		else:
			out.append(["check", fs])        # free-form note written by a system
	if not haunts.is_empty(): out.push_front(["check", "Seen: " + ", ".join(haunts) + "."])
	if has_fav: out.append(["check", "Favourite: %s." % _item_name(str(def.get("favourite", "")))])
	elif hint: out.append(["check", "Has a favourite treat."])
	if has_secret: out.append(["check", str(def.get("secret", ""))])
	if not (has_fav and has_secret):
		out.append(["lock", "More to notice..."])
	return out

func _spot(s: String) -> String:
	return str(SPOT_NAMES.get(s, _pretty(s).to_lower())) if s != "" else "somewhere"

# ------------------------------------------------------------------ People
func _people_defs() -> Dictionary:
	if not test_people.is_empty(): return test_people
	var d = Data.get("PEOPLE")
	if d is Dictionary and not d.is_empty(): return d
	if ResourceLoader.exists(PEOPLE_FALLBACK):
		var scr = load(PEOPLE_FALLBACK)
		if scr is Script:
			var pd = scr.get_script_constant_map().get("PEOPLE")
			if pd is Dictionary: return pd
	return {}

func _level_bounds(lv: int, pts: int) -> Array:
	var th = Data.get("PEOPLE_LEVELS")
	if th is Array and not th.is_empty():
		var prev := int(th[lv - 1]) if lv > 0 and lv - 1 < th.size() else 0
		var nxt := int(th[lv]) if lv < th.size() else -1
		return [prev, nxt]
	return [lv * 100, (lv + 1) * 100 if lv < 10 else -1]

func _page_people() -> void:
	var defs := _people_defs()
	if defs.is_empty():
		_list.add_child(_note("Nobody to meet yet."))
		return
	var close_ones := 0
	for id in defs:
		if GameState.person_level(str(id)) >= 5: close_ones += 1
	_list.add_child(_summary("Townsfolk: %d" % defs.size(), "Close friends %d" % close_ones))
	for id in defs:
		if defs[id] is Dictionary: _list.add_child(_person_card(str(id), defs[id]))

func _person_card(id: String, def: Dictionary) -> Control:
	var st := GameState.person_state(id)
	var lv := GameState.person_level(id)
	var pts := int(st.get("points", 0))
	var card := _card(Style.CREAM_DEEP, 2, 14, 22)
	var w := _cw() - 28.0 - 6.0
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	card.add_child(vb)
	# row 1: avatar, name + role, level chip
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	vb.add_child(top)
	top.add_child(_avatar(str(def.get("name", _pretty(id))), _hex(def.get("main", "f2cf9c"), Color("f2cf9c"))))
	var nv := VBoxContainer.new()
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.add_theme_constant_override("separation", -1)
	top.add_child(nv)
	var nm := Style.label(str(def.get("name", _pretty(id))), 25, Style.INK, true)
	nm.clip_text = true
	nv.add_child(nm)
	nv.add_child(_wrap_label(str(def.get("role", "")), 17, Style.INK_SOFT, w - 64.0 - 12.0 - 90.0))
	var chip := Style.chip("Level %d" % lv, Style.GOLD if lv >= 5 else Style.CREAM_SHADE, Style.INK, 17)
	chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(chip)
	# row 2: hearts (one per level) + progress to the next level
	var hh := Style.hearts(lv, 10, 23.0, 0)
	vb.add_child(hh)
	var bounds := _level_bounds(lv, pts)
	var prog := HBoxContainer.new()
	prog.add_theme_constant_override("separation", 10)
	vb.add_child(prog)
	if int(bounds[1]) >= 0:
		prog.add_child(Style.bar(float(pts - int(bounds[0])), float(int(bounds[1]) - int(bounds[0])), Style.SUCCESS, 16.0))
		var pl := Style.label("%d / %d" % [pts, int(bounds[1])], 17, Style.INK_SOFT, true)
		pl.custom_minimum_size.x = 92
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		prog.add_child(pl)
	else:
		prog.add_child(Style.bar(1.0, 1.0, Style.GOLD, 16.0))
		var pl2 := Style.label("Best friends", 17, Style.INK_SOFT, true)
		pl2.custom_minimum_size.x = 92
		pl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		prog.add_child(pl2)
	# likes
	vb.add_child(_wrap_label(_likes_text(def, st), 18, Style.INK, w))
	# perks
	for e in _perk_rows(def, lv):
		vb.add_child(_fact_row("lock" if not e[0] else "check", e[1], w))
	return card

func _avatar(nm: String, col: Color) -> Control:
	var c := Panel.new()
	c.custom_minimum_size = Vector2(64, 64)
	c.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = col; sb.border_color = Style.INK; sb.set_border_width_all(3)
	sb.set_corner_radius_all(32); sb.set_corner_detail(12)
	c.add_theme_stylebox_override("panel", sb)
	var light := col.get_luminance() > 0.62
	var l := Style.label(nm.substr(0, 1).to_upper(), 32, Style.INK if light else Style.CREAM, true)
	if not light:
		l.add_theme_constant_override("outline_size", 5)
		l.add_theme_color_override("font_outline_color", col.darkened(0.4))
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	c.add_child(l)
	return c

func _likes_text(def: Dictionary, st: Dictionary) -> String:
	if int(st.get("last_gift_day", 0)) <= 0: return "Likes: ???"
	var names: Array = []
	var arr = def.get("loves", [])
	if arr is Array:
		for it in arr: names.append(_item_name(str(it)))
	return "Loves: " + (", ".join(names) if not names.is_empty() else "???")

## First sentence only, so perk lines stay scannable.
func _short(text: String) -> String:
	var i := text.find(". ")
	return text.substr(0, i + 1) if i > 0 else text

## [[unlocked, text], ...]: every unlocked perk plus a tease of the next locked one.
## Data.PEOPLE[id].perks is an Array of {level, id, value, text} (a Dictionary level -> entries also works).
func _perk_entries(def: Dictionary) -> Array:
	var entries: Array = []
	var pk = def.get("perks", [])
	var raw: Array = []
	if pk is Array:
		for e in pk: raw.append([int(e.get("level", 0)) if e is Dictionary else 0, e])
	elif pk is Dictionary:
		for k in pk.keys():
			if not str(k).is_valid_int(): continue
			var v = pk[k]
			for e in (v if v is Array else [v]): raw.append([int(str(k)), e])
	for r in raw:
		var e = r[1]
		var text := ""
		if e is Dictionary: text = str(e.get("text", e.get("desc", _pretty(str(e.get("id", ""))))))
		elif e is String: text = _pretty(e)
		if text != "" and int(r[0]) > 0: entries.append([int(r[0]), _short(text)])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	return entries

func _perk_rows(def: Dictionary, lv: int) -> Array:
	var out: Array = []
	var teased := false
	for e in _perk_entries(def):
		if int(e[0]) <= lv:
			out.append([true, "Level %d: %s" % [e[0], e[1]]])
		elif not teased:
			teased = true
			out.append([false, "Level %d: %s" % [e[0], e[1]]])
	return out

# ------------------------------------------------------------------ Fish
func _page_fish() -> void:
	var ids: Array = Data.FISH.keys()
	var seen := 0
	var golds := 0
	for id in ids:
		var e = GameState.fish_log.get(id, null)
		if e is Dictionary and int(e.get("count", 0)) > 0:
			seen += 1
			golds += int(e.get("gold", 0))
	_list.add_child(_summary("Caught %d of %d kinds" % [seen, ids.size()], "Gold %d" % golds if golds > 0 else ""))
	for id in ids:
		_list.add_child(_fish_row(str(id), Data.FISH[id]))

func _fish_row(id: String, def: Dictionary) -> Control:
	var e = GameState.fish_log.get(id, {})
	if not (e is Dictionary): e = {}
	var count := int(e.get("count", 0))
	var known := count > 0
	var gold := int(e.get("gold", 0))
	var card := _card(Style.CREAM_DEEP if known else Color("f1e6d3"), 2, 12, 20)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	card.add_child(h)
	var tint := _hex(def.get("body", "8cc3d6"), Color("8cc3d6")) if known else Color("c9b8a4")
	var ic := Style.icon("fish", 58.0, tint)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	h.add_child(vb)
	var nm := Style.label(str(def.get("name", _pretty(id))) if known else "???", 23, Style.INK, true)
	nm.clip_text = true
	vb.add_child(nm)
	if known:
		var sub := HBoxContainer.new()
		sub.add_theme_constant_override("separation", 8)
		var stars := HBoxContainer.new()
		stars.add_theme_constant_override("separation", 0)
		for i in int(def.get("rarity", 1)):
			stars.add_child(Style.icon("star", 18.0))
		sub.add_child(stars)
		sub.add_child(Style.label("Best " + _cm(float(e.get("best_cm", 0.0))), 18, Style.INK_SOFT))
		vb.add_child(sub)
	else:
		vb.add_child(Style.label("Not caught yet", 18, Style.INK_SOFT))
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 2)
	h.add_child(right)
	if known:
		var cl := Style.label("x%d" % count, 28, Style.INK, true)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.add_child(cl)
		if gold > 0:
			var ch := Style.chip("Gold x%d" % gold, Style.GOLD, Style.INK, 16)
			ch.size_flags_horizontal = Control.SIZE_SHRINK_END
			right.add_child(ch)
	return card

# ------------------------------------------------------------------ Shore
func _page_shore() -> void:
	var total := 0
	var kinds := 0
	var ids: Array = Data.SHORE.keys()
	for k in GameState.shore_log.keys(): total += int(GameState.shore_log[k])
	for id in ids:
		if int(GameState.shore_log.get(id, 0)) > 0: kinds += 1
	_list.add_child(_summary("Found %d kinds" % kinds, "%d items" % total))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_list.add_child(grid)
	var cw := (_cw() - 10.0) * 0.5
	for id in ids:
		grid.add_child(_shore_tile(str(id), Data.SHORE[id], cw))
	# anything else a system logged (gold variants, special finds)
	for k in GameState.shore_log.keys():
		if not Data.SHORE.has(k) and int(GameState.shore_log[k]) > 0:
			grid.add_child(_shore_tile(str(k), {"name": _pretty(str(k)), "color": "f2c14e"}, cw))

func _shore_tile(id: String, def: Dictionary, card_w: float) -> Control:
	var n := int(GameState.shore_log.get(id, 0))
	var known := n > 0
	var card := _card(Color("fff3d4") if known else Color("f1e6d3"), 2, 12, 20)
	card.custom_minimum_size.x = card_w
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	card.add_child(h)
	var tint := _hex(def.get("color", "f6b8c4"), Color("f6b8c4")) if known else Color("c9b8a4")
	var ic := Style.icon(_shore_icon(id), 52.0, tint)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 0)
	h.add_child(vb)
	var nm := _wrap_label(str(def.get("name", _pretty(id))) if known else "???", 19, Style.INK, card_w - 24.0 - 6.0 - 52.0 - 10.0, true)
	vb.add_child(nm)
	vb.add_child(Style.label("x%d" % n if known else "Not found", 22 if known else 17, Style.INK if known else Style.INK_SOFT, known))
	return card

# ------------------------------------------------------------------ Requests
func _page_requests() -> void:
	var reqs: Array = []
	for r in GameState.requests:
		if r is Dictionary: reqs.append(r)
	if reqs.is_empty():
		_list.add_child(_note("No requests right now. The board by the shop has new ones every morning."))
		return
	var done := 0
	for r in reqs:
		if bool(r.get("done", false)): done += 1
	_list.add_child(_summary("Done %d of %d" % [done, reqs.size()], "New ones each morning"))
	for r in reqs:
		_list.add_child(_request_row(r))

func _request_row(r: Dictionary) -> Control:
	var done := bool(r.get("done", false))
	var card := _card(Color("e3efe6") if done else Style.CREAM_DEEP, 2, 14, 20)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	card.add_child(h)
	var ic := Style.icon("check" if done else "note", 44.0)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 4)
	h.add_child(vb)
	var who := str(r.get("who_name", ""))
	if who == "":
		var pid := str(r.get("who", ""))
		var pd = _people_defs().get(pid, {})
		who = str(pd.get("name", _pretty(pid))) if pd is Dictionary and pid != "" else ""
	var text := str(r.get("text", "..."))
	vb.add_child(_wrap_label(text, 20, Style.INK_SOFT if done else Style.INK, _cw() - 28.0 - 6.0 - 44.0 - 12.0, true))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	vb.add_child(line)
	var reward := int(r.get("reward", r.get("yen", 0)))
	if reward > 0:
		line.add_child(Style.icon("yen", 26.0))
		line.add_child(Style.label(Style.money(reward), 20, Style.INK, true))
	var sp := int(r.get("sparks", 0))
	if sp > 0:
		line.add_child(Style.icon("spark", 24.0))
		line.add_child(Style.label("%d" % sp, 20, Style.INK, true))
	if done: line.add_child(Style.label("Done", 19, Style.SUCCESS_DARK, true))
	elif who != "": line.add_child(Style.label("for " + who, 18, Style.INK_SOFT))
	return card

# ------------------------------------------------------------------ Bag
func _page_bag() -> void:
	var groups := {}
	var total := 0
	for k in GameState.bag.keys():
		var n := int(GameState.bag[k])
		if n <= 0: continue
		total += n
		var it := _item(str(k))
		var g := str(it["group"])
		if not groups.has(g): groups[g] = []
		groups[g].append([str(k), n, it])
	if total == 0:
		_list.add_child(_note("Your bag is empty. For now."))
		return
	_list.add_child(_summary("%d items" % total, "Sell at Pip's shop"))
	for g in ["Fish", "Shore", "Treats", "Gifts", "Other"]:
		if not groups.has(g): continue
		var hl := Style.label(g, 22, Style.INK_SOFT, true)
		_list.add_child(hl)
		var arr: Array = groups[g]
		arr.sort_custom(func(a: Array, b: Array) -> bool: return str(a[2]["name"]) < str(b[2]["name"]))
		for e in arr:
			_list.add_child(_bag_row(e[2], int(e[1])))

func _bag_row(it: Dictionary, n: int) -> Control:
	var card := _card(Style.CREAM_DEEP, 2, 10, 18)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	card.add_child(h)
	var ic := Style.icon(str(it["icon"]), 46.0, it["tint"])
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var nm := Style.label(str(it["name"]), 23, Style.INK, true)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nm.clip_text = true
	h.add_child(nm)
	var cl := Style.label("x%d" % n, 28, Style.INK, true)
	cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(cl)
	return card

# ------------------------------------------------------------------ Settings
func _page_settings() -> void:
	var music = get_node_or_null("/root/Music")
	var card := _card(Style.CREAM_DEEP, 2, 16, 22)
	_list.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	card.add_child(vb)
	vb.add_child(Style.label("Music", 28, Style.INK, true))
	if music == null or not music.has_method("set_enabled"):
		vb.add_child(_wrap_label("Music is not available in this build.", 19, Style.INK_SOFT, _cw() - 40.0))
	else:
		var on: bool = music.enabled()
		var tg := Style.button("Music: On" if on else "Music: Off", "primary" if on else "ghost", 26)
		tg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tg.pressed.connect(func() -> void:
			music.set_enabled(not music.enabled())
			_refresh())
		vb.add_child(tg)
		var vh := HBoxContainer.new()
		vb.add_child(vh)
		var vl := Style.label("Volume", 22, Style.INK, true)
		vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vh.add_child(vl)
		var pct := Style.label("%d%%" % int(round(float(music.volume()) * 100.0)), 22, Style.INK_SOFT, true)
		vh.add_child(pct)
		var sl := Style.slider(float(music.volume()))
		sl.value_changed.connect(func(v: float) -> void:
			music.set_volume(v)
			pct.text = "%d%%" % int(round(v * 100.0)))
		vb.add_child(sl)
	var about := _card(Style.CREAM_DEEP, 2, 16, 22)
	_list.add_child(about)
	var ab := VBoxContainer.new()
	ab.add_theme_constant_override("separation", 8)
	about.add_child(ab)
	ab.add_child(Style.label("Saving", 28, Style.INK, true))
	ab.add_child(_wrap_label("Your game saves by itself. Nothing to press, nothing to lose.", 20, Style.INK, _cw() - 40.0))
	var cr := _wrap_label(CREDITS, 17, Style.INK_SOFT, _cw() - 20.0)
	cr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.add_child(cr)

# ================================================================== tab button
class TabButton extends Button:
	var id := ""
	var selected := false
	var _icon: Control
	var _lbl: Label

	func setup(tab_id: String, text: String, icon_name: String, width: float) -> void:
		id = tab_id
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(width, Style.MIN_TOUCH)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var vb := VBoxContainer.new()
		vb.set_anchors_preset(Control.PRESET_FULL_RECT)
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_theme_constant_override("separation", 0)
		add_child(vb)
		_icon = Style.icon(icon_name, 36.0)
		_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(_icon)
		var fs := 16
		while fs > 13 and Style.text_width(text, fs) > width - 6.0: fs -= 1
		_lbl = Style.label(text, fs, Style.INK, true)
		_lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(_lbl)
		Style.squish(self)
		set_selected(false)

	func set_selected(s: bool) -> void:
		selected = s
		var kind := "primary" if s else "cream"
		add_theme_stylebox_override("normal", Style.box(kind, "normal", 22))
		add_theme_stylebox_override("hover", Style.box(kind, "hover", 22))
		add_theme_stylebox_override("pressed", Style.box(kind, "pressed", 22))
		add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		_lbl.add_theme_color_override("font_color", Style.CREAM if s else Style.INK)
		_lbl.add_theme_constant_override("outline_size", 4 if s else 0)
		_lbl.add_theme_color_override("font_outline_color", Style.PRIMARY_DARK)
		_icon.tint = Style.CREAM if s else Color(0, 0, 0, 0)
		_icon.queue_redraw()
