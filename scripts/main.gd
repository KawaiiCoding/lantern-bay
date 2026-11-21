extends Node3D
## Main: wires the game together. Each part lives in its own script (owned by one team member).
## A part whose script is missing or broken is skipped, so the game always boots.
##
## Order: SkyCycle -> Island -> Player -> systems -> Hud.
## Every part is a Node with an optional `setup(main)` called after all parts exist.
## Shared references: main.island, main.player, main.hud, main.sky.

var island: Node3D
var player: Node3D
var hud: CanvasLayer
var sky: Node
var systems := {}

const PARTS := [
	["sky", "res://scripts/world/sky_cycle.gd"],
	["island", "res://scripts/world/island.gd"],
	["player", "res://scripts/player/player.gd"],
	["cats", "res://scripts/systems/cats.gd"],
	["fishing", "res://scripts/systems/fishing.gd"],
	["shore", "res://scripts/systems/shore.gd"],
	["people", "res://scripts/systems/people.gd"],
	["town", "res://scripts/systems/town.gd"],
	["lanterns", "res://scripts/systems/lanterns.gd"],
	["story", "res://scripts/systems/story.gd"],
	["goals", "res://scripts/systems/goals.gd"],
	["hud", "res://scripts/ui/hud.gd"],
	["minimap", "res://scripts/ui/minimap.gd"],
]

func _ready() -> void:
	var nodes := []
	for p in PARTS:
		var id: String = p[0]
		var path: String = p[1]
		if not ResourceLoader.exists(path):
			push_warning("part missing: " + path); continue
		var scr = load(path)
		if scr == null or not scr.can_instantiate():
			push_error("part failed to load: " + path); continue
		var n: Node = scr.new()
		n.name = id.capitalize().replace(" ", "")
		add_child(n)
		match id:
			"sky": sky = n
			"island": island = n
			"player": player = n
			"hud": hud = n
			_: systems[id] = n
		nodes.append(n)
	for n in nodes:
		if n.has_method("setup"): n.setup(self)
	_safety_floor()
	# test hook: `godot --path . -- shot=out.png wait=3` saves a screenshot after N seconds and quits
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=", true, 1)
		if kv.size() == 2: args[kv[0]] = kv[1]
	if args.has("fresh"): GameState.reset()
	# `time=21:30` jumps the island clock (for screenshots / testing evenings and nights)
	if args.has("time"):
		var hm: PackedStringArray = String(args["time"]).split(":")
		GameState.minute = float(hm[0]) * 60.0 + (float(hm[1]) if hm.size() > 1 else 0.0)
	# `speed=20` makes the clock run faster (watch a whole day go by)
	if args.has("speed"): Engine.time_scale = float(args["speed"])
	if args.has("shot"):
		await get_tree().create_timer(float(args.get("wait", "2"))).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args["shot"])
		get_tree().quit()

## Never fall through the world: a solid slab under the whole map (just below the ground surface),
## and if Mocha somehow ends up below it, he is put back on the last safe ground he stood on.
var _last_safe := Vector3.ZERO
var _safe_timer := 0.0
func _safety_floor() -> void:
	var b := StaticBody3D.new(); b.name = "SafetyFloor"
	var c := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = Vector3(400, 1.0, 400)
	c.shape = sh; b.add_child(c); b.position = Vector3(0, -0.52, 0)
	add_child(b)
	if is_instance_valid(player): _last_safe = player.global_position

func _physics_process(dt: float) -> void:
	if not is_instance_valid(player) or not (player is CharacterBody3D): return
	var p: Vector3 = player.global_position
	var ground := 0.0
	if is_instance_valid(island) and island.has_method("ground_y"): ground = island.ground_y(p.x, p.z)
	if p.y < ground - 0.6 or p.y < -1.5:
		var back := _last_safe if _last_safe != Vector3.ZERO else spot("spawn")
		player.global_position = back + Vector3(0, 0.3, 0)
		player.velocity = Vector3.ZERO
		return
	_safe_timer += dt
	if _safe_timer > 0.5 and player.is_on_floor() and absf(p.y - ground) < 0.3:
		_safe_timer = 0.0
		_last_safe = p

## Things between the camera and Mocha (lamp posts, trees, roofs) fade to see-through so he is never hidden.
var _faded := {}          # GeometryInstance3D -> true
var _fade_timer := 0.0
func _process(dt: float) -> void:
	_fade_timer -= dt
	if _fade_timer > 0.0: return
	_fade_timer = 0.15
	var cam := get_viewport().get_camera_3d()
	if cam == null or not is_instance_valid(player): return
	var from := cam.global_position
	var to: Vector3 = player.global_position + Vector3(0, 0.8, 0)
	var hits := {}
	var space := get_world_3d().direct_space_state
	var ex: Array[RID] = []
	if player is CollisionObject3D: ex.append(player.get_rid())
	for i in 6:   # walk through up to 6 blockers along the line
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.exclude = ex
		var r := space.intersect_ray(q)
		if r.is_empty(): break
		var col: Object = r.collider
		if col is CollisionObject3D:
			ex.append(col.get_rid())
			var root: Node = col
			for g in _geoms(root): hits[g] = true
			if root.get_parent() is Node3D and not (root.get_parent() == island):
				for g in _geoms(root.get_parent()): hits[g] = true
	for g in hits:
		if is_instance_valid(g): g.transparency = 0.7
	for g in _faded.keys():
		if not hits.has(g) and is_instance_valid(g): g.transparency = 0.0
	_faded = hits

func _geoms(n: Node) -> Array:
	var out := []
	if n is GeometryInstance3D: out.append(n)
	for c in n.get_children():
		if c is GeometryInstance3D: out.append(c)
	return out

## Helper for systems: the spot position from the island (Vector3.ZERO if unknown).
func spot(name: String) -> Vector3:
	if island and island.has_method("spot"): return island.spot(name)
	return Vector3.ZERO
