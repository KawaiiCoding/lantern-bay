extends PanelContainer
## Request board panel: today's requests as cards with a Complete button (enabled when the bag satisfies
## the request). Completing consumes the items and pays yen + sparks (see requests.gd).

signal closed
signal completed(req: Dictionary)

const Dat := preload("res://scripts/systems/town/dat.gd")
const Yen := preload("res://scripts/systems/town/yen.gd")
const Kit := preload("res://scripts/systems/town/kit.gd")
const Requests := preload("res://scripts/systems/town/requests.gd")
const Eco := preload("res://scripts/systems/town/economy.gd")
const ItemIcon := preload("res://scripts/systems/town/item_icon.gd")

const PANEL_W := 504.0
const PANEL_H := 860.0

const PINNED := [
	"Pinned neatly. Someone used a lot of tape.",
	"New notes appear overnight. Nobody admits to it.",
	"The board is mostly polite. Mostly.",
]

var _list: VBoxContainer
var _scroll: ScrollContainer
var _bubble: Label
var _closing := false
var _dirty := false

func _init() -> void:
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	add_theme_stylebox_override("panel", Kit.box(Kit.CREAM, 26, 3, 14))

func _ready() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var tcol := VBoxContainer.new()
	tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tcol.alignment = BoxContainer.ALIGNMENT_CENTER
	tcol.add_theme_constant_override("separation", 2)
	tcol.add_child(Kit.label("Request Board", 30, Kit.INK, false, true))
	tcol.add_child(Kit.label("New ones every morning.", 18, Kit.SOFT))
	head.add_child(tcol)
	var close := Kit.button("Close", Kit.PEACH, 24, 88, 124)
	close.pressed.connect(_close)
	head.add_child(close)
	root.add_child(head)

	_scroll = Kit.scroll()
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 12)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	root.add_child(_scroll)

	var bub := Kit.card(Kit.ROW, 10, 16, 2)
	_bubble = Kit.label(str(PINNED[randi() % PINNED.size()]), 20, Kit.INK, true)
	_bubble.custom_minimum_size = Vector2(0, 52)
	_bubble.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bub.add_child(_bubble)
	root.add_child(bub)

	GameState.bag_changed.connect(_queue_rebuild)
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
	var any := false
	_list.add_child(_special_card())
	for r in GameState.requests:
		if r is Dictionary:
			any = true
			_list.add_child(_card(r))
	if not any:
		var card := Kit.card(Kit.ROW, 16, 20, 2)
		var l := Kit.label("Nothing is pinned up right now. Come back in the morning.", 22, Kit.SOFT, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(l)
		_list.add_child(card)
	_restore.call_deferred(keep)

func _restore(v: int) -> void:
	if is_instance_valid(_scroll):
		await get_tree().process_frame
		if is_instance_valid(_scroll): _scroll.scroll_vertical = v

## Pip's daily special, shown on the board.
func _special_card() -> Control:
	var sid := Eco.special_id()
	var card := Kit.card(Kit.HILITE, 10, 18, 2)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	card.add_child(h)
	if sid == "":
		h.add_child(Kit.label("Pip's special starts once you have caught something.", 20, Kit.SOFT, true))
		return card
	var info := Eco.describe("fish:" + sid)
	var ic := ItemIcon.new("fish", info.c1, info.c2)
	ic.custom_minimum_size = Vector2(44, 44)
	h.add_child(ic)
	var m := ("%.1f" % Eco.special_mult()).trim_suffix(".0")
	h.add_child(Kit.label("Pip's special today: %s, paid at x%s." % [str(info.name), m], 20, Kit.INK, true))
	return card

func _card(req: Dictionary) -> Control:
	var done := bool(req.get("done", false))
	var pr := Requests.progress(req)
	var can: bool = pr.ok
	var card := Kit.card(Kit.MINTY if done else (Kit.HILITE if can else Kit.ROW), 12, 20, 2)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	card.add_child(h)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 3)
	col.add_child(Kit.label("From %s" % str(req.get("who_name", "someone")), 18, Kit.SOFT))
	col.add_child(Kit.label(str(req.get("text", "")), 22, Kit.INK, true, true))
	var rw := HBoxContainer.new()
	rw.add_theme_constant_override("separation", 10)
	rw.add_child(Yen.row(int(req.get("reward", 0)), 20))
	var sp := int(req.get("sparks", 0))
	if sp > 0:
		rw.add_child(Kit.label("+%d spark%s" % [sp, "" if sp == 1 else "s"], 18, Color("b8860b")))
	col.add_child(rw)
	col.add_child(Kit.label(str(pr.label), 18, Kit.INK if (can or done) else Kit.SOFT, true))
	h.add_child(col)

	var btn := Kit.button("Done" if done else "Complete", Kit.GREEN, 22, 88, 132)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.disabled = not can
	btn.pressed.connect(_complete.bind(req))
	h.add_child(btn)
	return card

func _complete(req: Dictionary) -> void:
	var msg := Requests.complete(req)
	if msg == "":
		_bubble.text = "Not quite yet. The list is patient."
		return
	_bubble.text = msg
	completed.emit(req)
	_queue_rebuild()
