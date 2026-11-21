extends Node
## Self-tests for the Cats system. Started by cats.gd when the user arg `test=cats*` is present.
##   godot --path . -- test=cats shot=/tmp/lb_cats.png wait=3 fresh=1         pet / sit / treat on 3 cats, screenshot
##   godot --path . -- test=cats_scare shot=/tmp/lb_cats_scare.png wait=2 fresh=1   nervous scamper + exclamation mark
##   godot --headless --path . -- test=cats_logic fresh=1                       every rule with asserts, then quits
## Needs fresh=1 (it changes hearts and the clock). Works without Island / Player / Hud (builds a tiny stage + stub Mocha).

class StubPlayer extends Node3D:
	var sitting := false
	var busy := false
	var riding := false
	var noise := 0.0
	var _walk: Node3D
	var _sit: Node3D
	func _ready() -> void:
		_walk = Toys.bear(self, false)
		_sit = Toys.bear(self, true)
		_sit.visible = false
		rotation.y = PI
	func noise_level() -> float: return noise
	func speed_ratio() -> float: return 0.0
	func carrying(item_id: String) -> bool: return GameState.has_item(item_id)
	func set_busy(b: bool) -> void: busy = b
	func sit(on: bool) -> void:
		sitting = on
		_walk.visible = not on
		_sit.visible = on
	func face(t: Vector3) -> void:
		var d := t - global_position
		if Vector2(d.x, d.z).length() > 0.01: rotation.y = atan2(d.x, d.z)

const CatActor := preload("res://scripts/systems/cats/cat_actor.gd")

var sys: Node
var player: Node3D
var stub: StubPlayer = null
var mode := ""
var checks := 0
var fails := 0
var _anchor := Vector3.ZERO
var _toward := Vector3(0, 0, 1)
var _right := Vector3(1, 0, 0)

func run(system: Node, m: String, args: Dictionary) -> void:
	sys = system
	mode = m
	GameState.toast.connect(func(t): print("[cats test] toast: ", t))
	await get_tree().process_frame
	await get_tree().process_frame
	if not args.has("fresh"):
		print("[cats test] refusing to run without fresh=1 (the test changes hearts and the clock)")
		get_tree().quit()
		return
	_prepare_world()
	match mode:
		"cats_logic": await _run_logic()
		"cats_scare": await _run_scare()
		_: await _run_shot()

# ---------------------------------------------------------------- stage
func _prepare_world() -> void:
	var main: Node = sys.main
	player = sys.get_player()
	if player == null:
		stub = StubPlayer.new()
		stub.name = "StubMocha"
		main.add_child(stub)
		main.set("player", stub)
		player = stub
	var cam := get_viewport().get_camera_3d()
	if main.get("island") == null:
		var ground := Toys.add(Toys.cyl(9.0, 9.0, 0.4, 48), Toys.mat(Color("a8d08f"), 0.95, 0.0), Vector3(0, -0.2, 0), main)
		ground.name = "CatsTestGround"
		Toys.add(Toys.cyl(2.8, 2.8, 0.05, 40), Toys.mat(Color("f3e2bf"), 0.95, 0.0), Vector3(0.4, 0.01, 0.6), main)
	if main.get("sky") == null:
		var sun := DirectionalLight3D.new()
		sun.rotation = Vector3(deg_to_rad(-52), deg_to_rad(28), 0)
		sun.light_energy = 1.1; sun.light_color = Color("fff1dc"); sun.shadow_enabled = true
		main.add_child(sun)
		var we := WorldEnvironment.new()
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR; env.background_color = Color("bfe3ef")
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("e9e4f2"); env.ambient_light_energy = 0.5
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		we.environment = env
		main.add_child(we)
	if cam == null:
		cam = Camera3D.new()
		cam.fov = 52
		main.add_child(cam)
		cam.position = Vector3(0, 2.9, 4.5)
		cam.look_at(Vector3(0, 0.55, 0.4), Vector3.UP)
		cam.current = true
	_anchor = player.global_position
	var to_cam := cam.global_position - _anchor
	to_cam.y = 0.0
	_toward = to_cam.normalized() if to_cam.length() > 0.1 else Vector3(0, 0, 1)
	_right = Vector3.UP.cross(_toward).normalized()
	# keep the clock inside one slot (morning) for the whole test
	GameState.day = 1
	GameState.minute = 8.0 * 60.0
	GameState.cats.clear()
	GameState.bag.clear()
	GameState.flags.clear()
	GameState.lanterns.clear()
	sys.sit_reward_time = 0.9

func _cat_at(id: String, offset: Vector3) -> Node3D:
	var p := _anchor + offset
	var a: Node3D = sys.spawn_test_cat(id, p, true)
	a.look_at_pos = (get_viewport().get_camera_3d().global_position)
	return a

func _keep_morning() -> void:
	GameState.minute = 8.0 * 60.0

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout
	_keep_morning()

# ---------------------------------------------------------------- shot test: pet / sit / treat
func _run_shot() -> void:
	var biscuit := _cat_at("biscuit", _toward * 0.45 + _right * 1.15)
	var mochi := _cat_at("mochi", _toward * 0.45 - _right * 1.15)
	var tofu := _cat_at("tofu", _toward * 1.3)
	GameState.add_item("treat:cream", 1)
	await _wait(1.0)
	print("[cats test] prompts: ", biscuit.get_prompt(player), " | ", mochi.get_prompt(player), " | ", tofu.get_prompt(player))
	biscuit.interact(player)                                   # pet
	await _wait(0.3)
	mochi.interact(player)                                     # sit (shy cat needs trust first)
	await _wait(0.3)
	tofu.interact(player)                                      # pet
	await _wait(0.4)
	print("[cats test] tofu prompt now: ", tofu.get_prompt(player))
	tofu.interact(player)                                      # give the cream cup
	await _wait(2.0)
	print("[cats test] hearts: biscuit=", sys.hearts("biscuit"), " mochi=", sys.hearts("mochi"), " tofu=", sys.hearts("tofu"))
	sys.stop_sit(true)

# ---------------------------------------------------------------- scare test (screenshot)
func _run_scare() -> void:
	var mochi := _cat_at("mochi", _toward * 1.6 + _right * 0.3)
	mochi.pinned = false
	var disco := _cat_at("disco", _toward * 0.2 - _right * 1.7)
	var biscuit := _cat_at("biscuit", _toward * 0.9 + _right * 1.5)
	mochi.look_at_pos = Vector3.INF
	disco.look_at_pos = Vector3.INF
	await _wait(1.0)
	stub_noise(1.5)
	print("[cats test] player is loud (noise 1.5); mochi near, biscuit is bold")
	await _wait(1.3)
	stub_noise(0.0)
	print("[cats test] mochi state=", mochi.state, " dist=", snappedf(Vector2(mochi.global_position.x - _anchor.x, mochi.global_position.z - _anchor.z).length(), 0.1))

func stub_noise(n: float) -> void:
	if stub != null: stub.noise = n

# ---------------------------------------------------------------- logic test
func _check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("[cats test] FAIL: ", msg)

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _run_logic() -> void:
	await _logic_schedule_pure()
	await _logic_schedule_live()
	await _logic_trust()
	await _logic_secret_rules()
	await _logic_follow()
	await _logic_scare()
	await _logic_sit_end()
	await _logic_friend_gifts()
	print("[cats test] logic: %d checks, %d failed" % [checks, fails])
	print("[cats test] RESULT: ", "PASS" if fails == 0 else "FAIL")
	GameState.reset()
	get_tree().quit(0 if fails == 0 else 1)

func _logic_schedule_pure() -> void:
	_check(sys.schedule_spot("disco", "morning", "sunny") == "", "disco is out only after dark")
	_check(sys.schedule_spot("disco", "evening", "sunny") == "lighthouse", "disco at the lighthouse in the evening")
	_check(sys.schedule_spot("captain", "night", "sunny") == "", "captain needs the hill lantern")
	GameState.lanterns["hill"] = true
	_check(sys.schedule_spot("captain", "night", "sunny") == "pier", "captain comes ashore once the hill lantern burns")
	GameState.lanterns.erase("hill")
	_check(sys.schedule_spot("ghost", "morning", "sunny") == "", "fog cat only in fog")
	_check(sys.schedule_spot("ghost", "morning", "fog") == "lighthouse", "fog cat at the lighthouse in fog")
	_check(sys.schedule_spot("mochi", "morning", "sunny") == "beach", "mochi on the beach")
	_check(sys.schedule_spot("mochi", "morning", "rain") == "shop", "mochi shelters at the shop in rain")
	_check(sys.schedule_spot("mochi", "night", "rain") == "", "mochi has no night haunt, rain or not")
	_check(sys.schedule_spot("saffron", "afternoon", "sunny") == "porch", "saffron sleeps on the porch when sunny")
	_check(sys.schedule_spot("saffron", "afternoon", "cloudy") == "home", "saffron at home when not sunny")
	_check(sys.schedule_spot("pancake", "night", "sunny") == "", "pancake is off duty at night")
	_check(sys.schedule_spot("nobody", "morning", "sunny") == "", "unknown cat id is ignored")

func _day_with(weather: String) -> int:
	for d in range(1, 400):
		GameState.day = d
		if GameState.weather() == weather: return d
	return 1

func _ids_sorted() -> Array:
	var ids: Array = sys.present_ids()
	ids.sort()
	return ids

func _logic_schedule_live() -> void:
	for a in sys.actors.values(): a.queue_free()
	sys.actors.clear()
	_day_with("sunny")
	GameState.minute = 8.0 * 60.0
	sys.refresh_schedule(true)
	_check(_ids_sorted() == ["biscuit", "marmalade", "mochi", "pancake", "pepper", "tofu"], "sunny morning cast: %s" % [_ids_sorted()])
	GameState.minute = 13.0 * 60.0
	sys.refresh_schedule(true)
	_check(_ids_sorted() == ["biscuit", "marmalade", "mochi", "pancake", "pepper", "saffron", "tofu"], "sunny afternoon cast: %s" % [_ids_sorted()])
	_check(String(sys.get_cat("saffron").haunt) == "porch", "saffron placed on the porch")
	GameState.minute = 18.0 * 60.0
	sys.refresh_schedule(true)
	_check(_ids_sorted() == ["biscuit", "disco", "marmalade", "pancake", "pepper", "saffron", "tofu"], "sunny evening cast: %s" % [_ids_sorted()])
	await _wait(0.5)
	_check(not sys.is_present("mochi"), "mochi left in the evening")
	_day_with("fog")
	GameState.minute = 8.0 * 60.0
	sys.refresh_schedule(true)
	_check(sys.is_present("ghost"), "fog cat appears on a foggy day")
	_day_with("rain")
	sys.refresh_schedule(true)
	_check(sys.is_present("mochi") and String(sys.get_cat("mochi").haunt) == "shop", "mochi under the shop awning in rain")
	GameState.lanterns["hill"] = true
	sys.refresh_schedule(true)
	_check(sys.is_present("captain"), "captain present after the hill lantern")
	GameState.lanterns.erase("hill")
	for a in sys.actors.values(): a.queue_free()
	sys.actors.clear()
	GameState.day = 1
	_keep_morning()

func _logic_trust() -> void:
	var day := GameState.day
	var biscuit := _cat_at("biscuit", _toward * 1.0 + _right * 0.5)
	await _wait(1.2)
	# pet, once per day, debounced within a frame
	_check(biscuit.get_prompt(player) == "Pet", "bold cat can be petted at once")
	biscuit.interact(player)
	biscuit.interact(player)
	_check(sys.hearts("biscuit") == 1, "pet gives one heart (double press in one frame counts once)")
	_check(not sys.sit_active, "second press in the same frame did nothing")
	_check(biscuit.get_prompt(player) == "Sit with Mayor Biscuit", "after petting, the sit prompt follows")
	await _wait(0.4)
	# sit: first sit of the day = +1 heart; player stands, session ends
	biscuit.interact(player)
	_check(sys.sit_active and bool(player.get("sitting")), "sit starts a session and sits Mocha")
	await _wait(2.6)
	_check(sys.hearts("biscuit") == 2, "first sit of the day gives a heart (got %d)" % sys.hearts("biscuit"))
	player.call("sit", false)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not sys.sit_active, "session ends when Mocha stands up")
	biscuit.interact(player)
	await _wait(2.4)
	_check(sys.hearts("biscuit") == 2, "second sit the same day gives nothing")
	sys.stop_sit(true)
	_check(not bool(player.get("sitting")), "stop_sit stands Mocha up")
	# favourite treat
	GameState.add_item("fish:mackerel", 1)
	_check(biscuit.get_prompt(player) == "Give Mackerel", "favourite fish offered: %s" % biscuit.get_prompt(player))
	await get_tree().process_frame
	biscuit.interact(player)
	_check(sys.hearts("biscuit") == 4 and not GameState.has_item("fish:mackerel"), "favourite treat gives two hearts and is used up")
	_check("favourite" in sys.st("biscuit")["facts"], "favourite fact learned")
	_check(int(sys.st("biscuit")["last_treat_day"]) == day, "treat day recorded")
	# shy cat needs a sit first (spawned late: cats near a sitting Mocha join the session)
	var mochi := _cat_at("mochi", -_toward * 0.2 - _right * 1.2)
	await _wait(1.2)
	_check(mochi.get_prompt(player) == "Sit with Mochi", "shy cat at zero trust: sit, not pet (%s)" % mochi.get_prompt(player))
	mochi.interact(player)
	await _wait(2.8)
	_check(sys.hearts("mochi") == 1, "sit earned the shy cat's first heart")
	sys.stop_sit(true)
	await get_tree().process_frame
	_check(mochi.get_prompt(player) == "Pet", "now the shy cat can be petted")
	# wrong treat: hint, nothing consumed, learned only the hint
	var tofu := _cat_at("tofu", _toward * 1.0 - _right * 0.8)
	await _wait(1.2)
	GameState.add_item("treat:catnip", 1)
	GameState.add_item("treat:cream", 1)
	_check(tofu.get_prompt(player) == "Pet", "tofu pet first")
	await get_tree().process_frame
	tofu.interact(player)
	await _wait(0.3)
	_check(tofu.get_prompt(player) == "Give Cream Cup", "tofu favourite offered before wrong treat")
	tofu.interact(player)
	_check(sys.hearts("tofu") == 3, "tofu: pet + treat = 3 hearts (got %d)" % sys.hearts("tofu"))
	await _wait(0.3)
	tofu.interact(player)   # first sit offered next
	sys.stop_sit(true)
	await _wait(0.3)
	var gp: String = tofu.get_prompt(player)
	_check(gp == "Give Catnip Sprig" or gp.begins_with("Sit with"), "after treat: wrong treat or sit (%s)" % gp)
	# force the wrong-treat path directly
	var st_t: Dictionary = sys.st("tofu")
	st_t["last_sit_day"] = GameState.day
	await get_tree().process_frame
	_check(tofu.get_prompt(player) == "Give Catnip Sprig", "wrong treat prompt (%s)" % tofu.get_prompt(player))
	tofu.interact(player)
	_check(GameState.has_item("treat:catnip"), "wrong treat is not consumed")
	_check("favourite_hint" in sys.st("tofu")["facts"], "hint fact recorded")
	await _wait(0.2)
	_check(tofu.get_prompt(player) != "Give Catnip Sprig", "wrong treat not offered twice in a day")
	# hearts never exceed the max and never go below 0
	var mx: int = sys.max_hearts()
	sys.add_hearts("tofu", 20)
	_check(sys.hearts("tofu") == mx, "hearts capped at %d" % mx)
	sys.add_hearts("tofu", -50)
	_check(sys.hearts("tofu") == 0, "hearts floor at 0")
	# a new day makes everything available again
	GameState.day += 1
	_check(biscuit.get_prompt(player) == "Pet", "next day: pet again")
	GameState.day = day
	for a in sys.actors.values(): a.queue_free()
	sys.actors.clear()

func _logic_secret_rules() -> void:
	GameState.cats.clear()
	GameState.bag.clear()
	var m := _cat_at("marmalade", _toward * 1.0)
	await _wait(1.2)
	var sm: Dictionary = sys.st("marmalade")
	sm["hearts"] = 1
	sm["last_pet_day"] = GameState.day
	GameState.add_item("treat:catnip", 1)
	await get_tree().process_frame
	_check(m.get_prompt(player) == "Give Catnip Sprig", "marmalade offered catnip (%s)" % m.get_prompt(player))
	m.interact(player)
	_check(GameState.has_item("treat:catnip") and sys.hearts("marmalade") == 1, "marmalade refuses until everyone else was petted")
	_check(not ("secret" in sys.st("marmalade")["facts"]), "secret not learned on refusal")
	await _wait(0.2)
	for oid in Data.CATS.keys():
		if oid == "marmalade": continue
		if sys._around_today(String(oid)): sys.st(String(oid))["last_pet_day"] = GameState.day
	_check(sys.others_petted_today("marmalade"), "rule satisfied once every cat around today is petted")
	m.interact(player)
	_check(not GameState.has_item("treat:catnip") and sys.hearts("marmalade") == 3, "marmalade accepts after the rounds (hearts %d)" % sys.hearts("marmalade"))
	_check("secret" in sys.st("marmalade")["facts"], "marmalade secret learned")
	for a in sys.actors.values(): a.queue_free()
	sys.actors.clear()

func _logic_follow() -> void:
	GameState.cats.clear()
	GameState.bag.clear()
	var b: Node3D = sys.spawn_test_cat("biscuit", _anchor + _toward * 6.0 + _right * 4.0, false)
	await _wait(1.5)
	_check(not b.following, "no mackerel, no following")
	GameState.add_item("fish:mackerel", 1)
	await _wait(1.6)
	_check(b.following, "carrying a mackerel makes Biscuit follow")
	_check(_flat(b.global_position, _anchor) < 2.8, "Biscuit trots up to Mocha (%.1f m)" % _flat(b.global_position, _anchor))
	await _wait(3.2)
	_check("secret" in sys.st("biscuit")["facts"], "following reveals the secret")
	GameState.remove_item("fish:mackerel", 1)
	await _wait(0.6)
	_check(not b.following, "mackerel gone, Biscuit loses interest")
	for a in sys.actors.values(): a.queue_free()
	sys.actors.clear()

func _logic_scare() -> void:
	GameState.cats.clear()
	GameState.bag.clear()
	var mochi: Node3D = sys.spawn_test_cat("mochi", _anchor + _toward * 1.6, false)
	var biscuit: Node3D = sys.spawn_test_cat("biscuit", _anchor + _right * 1.8 + _toward * 0.5, false)
	await _wait(1.2)
	var start := mochi.global_position
	stub_noise(1.5)
	await _wait(0.5)
	_check(int(mochi.state) in [CatActor.S.REACT, CatActor.S.FLEE], "loud player within 4 m startles the shy cat (state %d)" % int(mochi.state))
	_check(mochi.get_prompt(player) == "", "a scared cat offers no prompt")
	await _wait(1.8)
	var moved := _flat(mochi.global_position, start)
	_check(moved > 4.5 and moved < 7.5, "scampered about 6 m away (%.1f m)" % moved)
	_check(int(biscuit.state) != CatActor.S.FLEE and int(biscuit.state) != CatActor.S.REACT, "bold cat does not care")
	stub_noise(0.0)
	await _wait(5.5)
	_check(int(mochi.state) != CatActor.S.ALERT and int(mochi.state) != CatActor.S.FLEE, "calms down after a few seconds (state %d)" % int(mochi.state))
	_check(mochi.get_prompt(player) != "" or _flat(mochi.global_position, player.global_position) > 2.0, "interactable again when calm and close")
	for a in sys.actors.values(): a.queue_free()
	sys.actors.clear()

func _logic_sit_end() -> void:
	GameState.cats.clear()
	var c := _cat_at("tofu", _toward * 1.0)
	sys.st("tofu")["last_pet_day"] = GameState.day
	await _wait(1.2)
	c.interact(player)
	_check(sys.sit_active, "sit session started")
	# the cat leaves mid-session: the session must survive without a target and still end cleanly
	sys._remove_actor("tofu")
	await get_tree().process_frame
	_check(sys.sit_actor == null, "session drops the departed cat")
	sys.stop_sit(true)
	_check(not sys.sit_active and not bool(player.get("sitting")), "sit ends cleanly")
	await _wait(1.2)
	_check(sys.get_cat("tofu") == null, "departed cat is gone")

func _logic_friend_gifts() -> void:
	for a in sys.actors.values(): a.queue_free()
	sys.actors.clear()
	GameState.cats.clear()
	GameState.bag.clear()
	GameState.flags.clear()
	var before := GameState.sparks
	var tofu := _cat_at("tofu", _toward * 1.0)
	await _wait(1.0)
	var s: Dictionary = sys.st("tofu")
	s["hearts"] = 4
	s["last_pet_day"] = 0
	var heard := []
	sys.friend_made.connect(func(id): heard.append(id))
	tofu.interact(player)
	_check(sys.is_friend("tofu") and sys.hearts("tofu") == 5, "5 hearts makes a friend")
	_check(heard == ["tofu"], "friend_made signal fired once")
	_check(GameState.sparks == before + int(Data.SPARK.get("cat_friend", 3)), "friend spark reward")
	# more friends so a morning visit is likely, then find a day with a visitor
	for id in ["biscuit", "pancake", "pepper", "saffron"]:
		var fs: Dictionary = sys.st(id)
		fs["hearts"] = 5
		fs["friend"] = true
	var found := -1
	for d in range(2, 80):
		GameState.day = d
		if not sys.visiting_friends().is_empty():
			found = d; break
	_check(found > 0, "some morning has a visiting friend")
	GameState.day = found
	GameState.flags.erase("cat_gift_day")
	var items_before := _shore_items()
	var n: int = sys.give_gifts()
	_check(n >= 1 and _shore_items() == items_before + n, "gift: %d shore item(s) landed in the bag" % n)
	_check(sys.give_gifts() == 0, "one gift round per day")
	_keep_morning()
	GameState.minute = 8.0 * 60.0
	sys.refresh_schedule(true)
	var visitor: String = String(sys.visiting_friends()[0])
	var vc: Node3D = sys.get_cat(visitor)
	_check(vc != null and String(vc.haunt) == "porch", "visiting friend waits on the porch in the morning (%s)" % visitor)

func _shore_items() -> int:
	var n := 0
	for k in GameState.bag.keys():
		if String(k).begins_with("shore:"): n += int(GameState.bag[k])
	return n
