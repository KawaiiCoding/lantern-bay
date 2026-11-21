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
	["goals", "res://scripts/systems/goals.gd"],
	["hud", "res://scripts/ui/hud.gd"],
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

## Helper for systems: the spot position from the island (Vector3.ZERO if unknown).
func spot(name: String) -> Vector3:
	if island and island.has_method("spot"): return island.spot(name)
	return Vector3.ZERO
