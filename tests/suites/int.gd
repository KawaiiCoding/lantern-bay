extends "res://tests/suite.gd"
## Integration: boots main.tscn and exercises the parts together. A test skips (with the reason) when a part it needs
## is missing, so this suite stays green-or-skipped while parts are still landing. Tests run in file order
## (names are numbered) and share one main instance; reset_world() puts the save back to a fresh game.

const GROUND_TOL := 0.03          # TEAM.md "Characters must look right": feet within 2-3 cm of the ground
const ITEM_TOL := 0.05
const DOWN := Vector3.DOWN

# ------------------------------------------------------------------ helpers
func _need(ids: Array) -> bool:
	for id in ids:
		if r.part(id) == null:
			skip("needs part '%s' (not loaded)" % id)
			return false
	return true

func _spot(name: String) -> Vector3:
	var isl: Node = r.part("island")
	if isl != null and isl.has_method("spot"): return isl.spot(name)
	return Vector3.ZERO

func _ground_y(x: float, z: float) -> float:
	var isl: Node = r.part("island")
	if isl != null and isl.has_method("ground_y"): return float(isl.ground_y(x, z))
	return NAN

func _nodes_by_script(suffix: String) -> Array:
	var out: Array = []
	if not is_instance_valid(r.main): return out
	for n in r.main.find_children("*", "Node3D", true, false):
		var s = n.get_script()
		if s != null and str(s.resource_path).ends_with(suffix): out.append(n)
	return out

func _teleport(p: Node3D, pos: Vector3) -> void:
	p.global_position = pos
	if p is CharacterBody3D: p.velocity = Vector3.ZERO

func _set_time(slot: String, minute_in_slot := 0.0) -> void:
	var start = {"morning": 6.0 * 60.0, "afternoon": 12.0 * 60.0, "evening": 18.0 * 60.0, "night": 22.0 * 60.0}
	gs.minute = float(start[slot]) + minute_in_slot

## First day (from 1) whose weather is `wx`.
func _day_with_weather(wx: String) -> int:
	for d in range(1, 400):
		if (gs.weather_on(d) if gs.has_method("weather_on") else weather_of_day(d)) == wx: return d
	return 0

## Lowest world-space y of a node's visible meshes (vertex exact), skipping blob shadows and flat decals.
func lowest_point(root: Node) -> Dictionary:
	var meshes: Array = []
	_collect_meshes(root, meshes)
	var cands: Array = []
	for mi in meshes:
		var box: AABB = mi.global_transform * mi.get_aabb()
		cands.append([box.position.y, mi])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var best = INF
	var best_mesh: Node = null
	for c in cands:
		if c[0] >= best: break
		var mi: MeshInstance3D = c[1]
		var faces: PackedVector3Array = mi.mesh.get_faces()
		var xf: Transform3D = mi.global_transform
		var low = c[0] if faces.is_empty() else INF
		for v in faces:
			var y: float = (xf * v).y
			if y < low: low = y
		if low < best:
			best = low; best_mesh = mi
	return {"y": best, "mesh": best_mesh, "count": meshes.size()}

func _collect_meshes(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and c.mesh != null and c.is_visible_in_tree():
			var skip_it = false
			var nm = str(c.name).to_lower()
			if nm.contains("shadow") or nm.contains("blob") or nm.contains("outline_only"): skip_it = true
			elif c.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and c.get_aabb().size.y * absf(c.global_transform.basis.get_scale().y) < 0.05: skip_it = true
			if not skip_it: out.append(c)
		_collect_meshes(c, out)

## World y of the surface a character stands on: the node's own surface_y/seat_y when it exposes one,
## else island.ground_y, plus a downward ray (so benches, piers and walls count as ground).
func _surface_candidates(n: Node3D, x: float, z: float) -> Array:
	var out: Array = []
	for key in ["surface_y", "seat_y"]:
		var v = n.get(key)
		if typeof(v) == TYPE_FLOAT and not is_nan(v) and v != 0.0: out.append(["own " + key, float(v)])
	var gy = _ground_y(x, z)
	if not is_nan(gy): out.append(["island.ground_y", gy])
	var space = n.get_world_3d().direct_space_state
	var q = PhysicsRayQueryParameters3D.create(Vector3(x, 30.0, z), Vector3(x, -10.0, z))
	var ex: Array[RID] = []
	for c in r.main.find_children("*", "CollisionObject3D", true, false):
		if c is CharacterBody3D: ex.append(c.get_rid())
	q.exclude = ex
	var hit = space.intersect_ray(q)
	if not hit.is_empty(): out.append(["ray", float(hit.position.y)])
	return out

## Characters currently in the world: {label, node}.
func characters() -> Array:
	var out: Array = []
	var p: Node = r.part("player")
	if p != null: out.append({"label": "player", "node": p})
	for n in _nodes_by_script("cats/cat_actor.gd"): out.append({"label": str(n.name), "node": n})
	var seen = {}
	for n in r.main.get_tree().get_nodes_in_group("people"):
		if n is Node3D and r.main.is_ancestor_of(n):
			out.append({"label": "person:" + str(n.name), "node": n}); seen[n] = true
	for n in _nodes_by_script("town/pip.gd"):
		if not seen.has(n): out.append({"label": "pip_model", "node": n})
	return out

# ------------------------------------------------------------------ boot
func t_01_boot_no_errors() -> void:
	reset_world()
	var m = await r.fresh_main()
	if m == null: return
	await r.wait_frames(30)
	var present: Array = []
	var missing: Array = []
	var parts = m.get_script().get_script_constant_map().get("PARTS", null)
	if typeof(parts) == TYPE_ARRAY:
		for pp in parts:
			var id: String = pp[0]
			var path: String = pp[1]
			if r.part(id) != null: present.append(id)
			elif ResourceLoader.exists(path): fail("part '%s' exists at %s but did not load into main (parse error or can_instantiate false)" % [id, path])
			else: missing.append(id)
	note("parts present: %s | not written yet: %s" % [", ".join(present), ", ".join(missing)])
	ok(is_instance_valid(m.get("player")) or r.part("player") == null, "main.player is invalid")
	# every present part must have had setup(main) called without errors: engine errors fail this test via the logger

func t_02_reboot_is_clean() -> void:
	reset_world()
	for i in 2:
		var m = await r.fresh_main()
		if m == null: return
		await r.wait_frames(10)
	var m2 = r.main
	ok(is_instance_valid(m2) and m2.get_child_count() > 0, "main has no children after a reboot")
	# the old instance is gone: only one Main in the tree
	var mains = 0
	for c in r.root.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("scripts/main.gd"): mains += 1
	eq(mains, 1, "number of Main nodes after rebooting twice")

func t_03_main_has_no_orphans_on_free() -> void:
	# freeing main must not leave autoload signal connections pointing at freed nodes (checked by a clean frame afterwards)
	reset_world()
	var m = await r.fresh_main()
	if m == null: return
	await r.wait_frames(5)
	r.main.queue_free()
	await r.wait_frames(3)
	r.main = null
	# autoload signals fire into the void: any stale callable would raise an engine error here
	gs.say("qa ping")
	gs.add_coins(1)
	gs.add_item("fish:sardine"); gs.remove_item("fish:sardine")
	gs.catalog_changed.emit()
	gs.people_changed.emit()
	gs._process(1.0)
	await r.wait_frames(5)
	reset_world()

# ------------------------------------------------------------------ world
func t_10_island_spots() -> void:
	reset_world()
	await r.ensure_main()
	if not _need(["island"]): return
	var isl: Node = r.part("island")
	var pts = {}
	for n in SPOT_NAMES:
		var p: Vector3 = isl.spot(n)
		if p == Vector3.ZERO: fail("island.spot('%s') is Vector3.ZERO (missing spot)" % n); continue
		if is_nan(p.x) or is_nan(p.y) or is_nan(p.z) or is_inf(p.x) or is_inf(p.z): fail("island.spot('%s') is not finite: %s" % [n, str(p)]); continue
		pts[n] = p
	var names = pts.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			var d: float = pts[names[i]].distance_to(pts[names[j]])
			if d < 0.05: fail("spots '%s' and '%s' are the same point %s" % [names[i], names[j], str(pts[names[i]])])
			elif d < 0.6 and not ((names[i] == "shop" and names[j] == "shop_counter") or (names[i] == "home" and names[j] == "porch")):
				warn("spots '%s' and '%s' are only %.2f m apart" % [names[i], names[j], d])
	var unknown: Vector3 = isl.spot("definitely_not_a_spot")
	ok(unknown == Vector3.ZERO, "island.spot of an unknown name should be Vector3.ZERO, got %s" % str(unknown))
	if isl.has_method("ground_y"):
		for n in pts.keys():
			var p2: Vector3 = pts[n]
			var gy = _ground_y(p2.x, p2.z)
			if absf(gy - p2.y) > 0.25: warn("spot '%s' y=%.2f but ground_y there is %.2f" % [n, p2.y, gy])
	else:
		warn("island has no ground_y(x, z) (contract)")
	if isl.has_method("random_beach_point") and isl.has_method("random_flats_point"):
		var rng = RandomNumberGenerator.new(); rng.seed = 7
		for fn in ["random_beach_point", "random_flats_point"]:
			var distinct = {}
			for i in 25:
				var q: Vector3 = isl.call(fn, rng)
				if is_nan(q.x) or is_nan(q.z) or q == Vector3.ZERO: fail("%s returned %s" % [fn, str(q)]); break
				distinct[Vector2(snappedf(q.x, 0.1), snappedf(q.z, 0.1))] = true
				var gyy = _ground_y(q.x, q.z)
				if not is_nan(gyy) and absf(gyy - q.y) > 0.3: warn("%s: y=%.2f but ground_y=%.2f at %s" % [fn, q.y, gyy, str(q)]); break
			ok(distinct.size() >= 10, "%s gives only %d distinct points in 25 draws" % [fn, distinct.size()])
	else:
		warn("island is missing random_beach_point / random_flats_point (contract)")

func t_11_spots_have_ground() -> void:
	reset_world()
	await r.ensure_main()
	if not _need(["island"]): return
	await r.wait_frames(3)
	var isl: Node = r.part("island")
	var space: PhysicsDirectSpaceState3D = isl.get_world_3d().direct_space_state
	var bad: Array = []
	for n in SPOT_NAMES:
		var p: Vector3 = isl.spot(n)
		if p == Vector3.ZERO: continue
		var q = PhysicsRayQueryParameters3D.create(p + Vector3(0, 3, 0), p + Vector3(0, -3, 0))
		var hit = space.intersect_ray(q)
		if hit.is_empty(): bad.append("%s (no collider under %s)" % [n, str(p)])
		elif absf(float(hit.position.y) - p.y) > 0.6: bad.append("%s (collider at y=%.2f, spot y=%.2f)" % [n, hit.position.y, p.y])
	ok(bad.is_empty(), "spots without walkable ground: " + "; ".join(bad))

func t_12_gates_follow_lanterns() -> void:
	reset_world()
	await r.ensure_main()
	if not _need(["island"]): return
	var isl: Node = r.part("island")
	if not isl.has_method("is_walkable") or not isl.has_method("refresh_unlocks"): skip("island has no is_walkable/refresh_unlocks"); return
	var gates = data_dict("SPOT_LANTERN")
	var before = {}
	for sp in gates.keys():
		var p: Vector3 = isl.spot(str(sp))
		if p == Vector3.ZERO: continue
		before[sp] = isl.is_walkable(p)
	# light everything, then the gated spots must be open
	for id in data_dict("LANTERNS").keys(): gs.lanterns[id] = true
	isl.refresh_unlocks()
	await r.wait_frames(3)
	for sp in before.keys():
		var p2: Vector3 = isl.spot(str(sp))
		ok(isl.is_walkable(p2), "spot '%s' should be walkable once the %s lantern is lit" % [str(sp), str(gates[sp])])
	if not before.is_empty():
		var closed = 0
		for sp in before.keys():
			if not before[sp]: closed += 1
		if closed == 0: warn("no gated spot was closed before its lantern was lit (is_walkable returns true everywhere?)")
	reset_world()
	isl.refresh_unlocks()

# ------------------------------------------------------------------ player
func t_20_player_spawns_on_ground() -> void:
	reset_world()
	await r.fresh_main()
	if not _need(["island", "player"]): return
	await r.wait_frames(40)
	var p: CharacterBody3D = r.part("player")
	var pos = p.global_position
	ok(not is_nan(pos.x) and not is_nan(pos.y), "player position is NaN")
	ok(pos.y > -2.0, "player fell through the world (y=%.2f)" % pos.y)
	ok(p.is_on_floor(), "player is not on the floor after 40 frames (y=%.2f)" % pos.y)
	var gy = _ground_y(pos.x, pos.z)
	if not is_nan(gy): ok(absf(pos.y - gy) < 0.3, "player y=%.2f but ground_y=%.2f" % [pos.y, gy])
	var sp = _spot("spawn")
	if sp != Vector3.ZERO: ok(Vector2(pos.x - sp.x, pos.z - sp.z).length() < 6.0, "player starts %.1f m from the spawn spot" % Vector2(pos.x - sp.x, pos.z - sp.z).length())
	ok(not bool(p.get("busy")), "player starts busy")
	ok(not bool(p.get("riding")) and not bool(p.get("sitting")), "player starts riding or sitting")
	ok(p.get_node_or_null("Camera3D") != null or p.get("camera") != null, "player has no camera")

func t_21_player_moves_with_joystick() -> void:
	reset_world()
	await r.ensure_main()
	if not _need(["island", "player"]): return
	var p: CharacterBody3D = r.part("player")
	var start = _spot("spawn")
	var best = 0.0
	var best_dir = Vector2.ZERO
	for dir in [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]:
		if start != Vector3.ZERO: _teleport(p, start + Vector3(0, 0.1, 0))
		await r.wait_frames(10)
		var a = p.global_position
		ib.touch_move = dir
		await r.wait_sec(1.0)
		ib.touch_move = Vector2.ZERO
		var d = Vector2(p.global_position.x - a.x, p.global_position.z - a.z).length()
		if d > best: best = d; best_dir = dir
		if best > 2.0: break
	ok(best > 1.5, "player barely moves with touch_move set for 1 s (best %.2f m; walk speed is ~4.2 m/s)" % best)
	# a small push is a quiet sneak: slower and quieter than a full push
	if best > 1.5 and p.has_method("noise_level"):
		await r.wait_frames(15)
		ib.touch_move = best_dir
		await r.wait_sec(0.6)
		var full_noise: float = p.noise_level()
		var full_ratio: float = p.speed_ratio()
		ib.touch_move = best_dir * 0.3
		await r.wait_sec(0.6)
		var sneak_noise: float = p.noise_level()
		var sneak_ratio: float = p.speed_ratio()
		ib.touch_move = Vector2.ZERO
		ok(sneak_noise < full_noise, "sneak noise_level (%.2f) should be lower than full push (%.2f)" % [sneak_noise, full_noise])
		ok(sneak_ratio < full_ratio, "sneak speed_ratio (%.2f) should be lower than full push (%.2f)" % [sneak_ratio, full_ratio])
		ok(full_ratio >= 0.0 and full_ratio <= 1.0001, "speed_ratio outside 0..1: %.2f" % full_ratio)
	ok(p.global_position.y > -2.0, "player fell off the world while walking (y=%.2f)" % p.global_position.y)

func t_22_player_ride_toggle() -> void:
	reset_world()
	await r.ensure_main()
	if not _need(["island", "player"]): return
	var p: CharacterBody3D = r.part("player")
	var sp = _spot("spawn")
	if sp != Vector3.ZERO: _teleport(p, sp + Vector3(0, 0.1, 0))
	await r.wait_frames(10)
	ib.ride_pressed.emit()
	await r.wait_frames(3)
	ok(bool(p.get("riding")), "ride_pressed did not start riding")
	ib.ride_pressed.emit()
	await r.wait_frames(3)
	ok(not bool(p.get("riding")), "ride_pressed again did not stop riding")
	# not while busy
	p.set_busy(true)
	ib.ride_pressed.emit()
	await r.wait_frames(3)
	ok(not bool(p.get("riding")), "player started riding while busy")
	p.set_busy(false)
	ok(not bool(p.get("busy")), "set_busy(false) did not clear busy")

func t_23_interactables_follow_contract() -> void:
	reset_world()
	await r.ensure_main()
	if not _need(["player"]): return
	await r.wait_frames(10)
	var p: Node = r.part("player")
	var nodes = r.main.get_tree().get_nodes_in_group("interactable")
	if nodes.is_empty(): skip("no interactables in the world yet"); return
	var kinds = {}
	for n in nodes:
		var label = "%s (%s)" % [str(n.name), str(n.get_script().resource_path.get_file()) if n.get_script() != null else n.get_class()]
		ok(n is Node3D, "%s: interactable must be a Node3D" % label)
		ok(n.has_method("get_prompt"), "%s: missing get_prompt(player)" % label)
		ok(n.has_method("interact"), "%s: missing interact(player)" % label)
		var rad = n.get("interact_radius")
		ok(typeof(rad) in [TYPE_FLOAT, TYPE_INT], "%s: interact_radius must be a number (got %s)" % [label, type_string(typeof(rad))])
		if typeof(rad) in [TYPE_FLOAT, TYPE_INT]: ok(float(rad) > 0.2 and float(rad) < 15.0, "%s: interact_radius %s is out of range" % [label, str(rad)])
		if n.has_method("get_prompt"):
			var pr = n.get_prompt(p)
			ok(typeof(pr) == TYPE_STRING, "%s: get_prompt must return a String, got %s" % [label, type_string(typeof(pr))])
			if typeof(pr) == TYPE_STRING and str(pr).length() > 28: warn("%s: prompt '%s' is long for the action button" % [label, pr])
			var pr_null = n.get_prompt(null)   # robustness: must not crash with no player
			ok(typeof(pr_null) == TYPE_STRING, "%s: get_prompt(null) must return a String" % label)
			if typeof(pr) == TYPE_STRING and str(pr).contains("coin"): fail("%s: prompt says coins: '%s'" % [label, pr])
		if n is Node3D:
			var gp: Vector3 = (n as Node3D).global_position
			ok(not is_nan(gp.x) and not is_nan(gp.y), "%s: position is NaN" % label)
		kinds[str(n.get_script().resource_path.get_file()) if n.get_script() != null else n.get_class()] = true
	note("%d interactables from: %s" % [nodes.size(), ", ".join(kinds.keys())])

func t_24_interaction_finder_sets_prompt() -> void:
	reset_world()
	await r.ensure_main()
	if not _need(["player", "hud"]): return
	var p: Node3D = r.part("player")
	var hud: Node = r.part("hud")
	_set_time("morning")
	await r.wait_frames(10)
	# stand next to the first interactable that offers a prompt and expect the HUD action button to show it
	var target: Node3D = null
	var want = ""
	for n in r.main.get_tree().get_nodes_in_group("interactable"):
		if n is Node3D and n.has_method("get_prompt"):
			var pr: String = str(n.get_prompt(p))
			if pr != "":
				target = n; want = pr; break
	if target == null: skip("no interactable offers a prompt right now"); return
	_teleport(p, target.global_position + Vector3(0.6, 0.2, 0.0))
	await r.wait_sec(0.5)
	var tgt = p.get("target")
	ok(tgt != null, "player.target is empty next to '%s' (prompt '%s')" % [str(target.name), want])
	var shown = null
	for k in ["action_text", "_action_text", "action_label"]:
		var v = hud.get(k)
		if typeof(v) == TYPE_STRING: shown = v
	if shown != null and tgt != null: ok(str(shown) != "", "HUD action button is empty although player.target is set (%s)" % str(tgt.name))

# ------------------------------------------------------------------ panels: no softlocks
func _panel_state_ok(label: String) -> void:
	ok(not gs.paused, "%s: GameState.paused is still true" % label)
	var p: Node = r.part("player")
	if p != null: ok(not bool(p.get("busy")), "%s: player.busy is still true" % label)

func t_30_notebook_opens_and_closes() -> void:
	reset_world()
	await r.ensure_main()
	if not _need(["hud"]): return
	var hud: Node = r.part("hud")
	if not hud.has_method("open_notebook"): skip("hud has no open_notebook"); return
	var tabs = ["", "today", "cats", "fish", "shore", "people", "requests", "bag"]
	for tab in tabs:
		var m0: float = gs.minute
		hud.open_notebook(tab)
		await r.wait_frames(6)
		ok(gs.paused, "notebook tab '%s': time must pause while it is open (GDD 4)" % tab)
		ok(hud.is_panel_open(), "notebook tab '%s': hud.is_panel_open() is false after open_notebook" % tab)
		await r.wait_sec(0.25)
		near(gs.minute, m0, 0.01, "notebook tab '%s': the clock moved while paused" % tab)
		hud.close_panel()
		await r.wait_sec(0.35)
		_panel_state_ok("notebook tab '%s' closed" % tab)
		ok(not hud.is_panel_open(), "notebook tab '%s': panel still open after close_panel" % tab)
	# toggling with the Tab key: open, then the same key closes (or at least a close path exists)
	ib.notebook_pressed.emit()
	await r.wait_frames(8)
	var opened: bool = hud.is_panel_open()
	ok(opened, "InputBridge.notebook_pressed did not open the notebook")
	if opened:
		ib.notebook_pressed.emit()
		await r.wait_sec(0.4)
		if hud.is_panel_open():
			hud.close_panel()
			await r.wait_sec(0.35)
			warn("pressing the notebook key again does not close the notebook (only hud.close_panel does)")
	_panel_state_ok("notebook via key")
	# open twice in a row, close once
	hud.open_notebook("cats"); hud.open_notebook("fish")
	await r.wait_frames(5)
	hud.close_panel()
	await r.wait_sec(0.35)
	_panel_state_ok("double open then one close")
	hud.close_panel()   # closing when nothing is open must be harmless
	await r.wait_frames(3)
	_panel_state_ok("close with nothing open")

func t_31_shop_and_board_panels() -> void:
	reset_world()
	await r.ensure_main()
	if not _need(["hud", "town", "player"]): return
	var town: Node = r.part("town")
	var hud: Node = r.part("hud")
	if not town.has_method("open_shop"): skip("town has no open_shop"); return
	for tab in ["sell", "buy"]:
		town.open_shop(tab)
		await r.wait_frames(8)
		ok(town.panel_open(), "town.open_shop('%s'): panel_open() is false" % tab)
		ok(gs.paused, "shop '%s' open: time must pause" % tab)
		town.close_panel()
		await r.wait_sec(0.4)
		_panel_state_ok("shop '%s' closed" % tab)
		ok(not town.panel_open(), "shop '%s': panel still open after close_panel" % tab)
	town.open_board()
	await r.wait_frames(8)
	ok(town.panel_open(), "town.open_board(): panel_open() is false")
	town.close_panel()
	await r.wait_sec(0.4)
	_panel_state_ok("board closed")
	# shop opened over the notebook, then everything closed
	hud.open_notebook("bag")
	await r.wait_frames(5)
	town.open_shop("sell")
	await r.wait_frames(5)
	town.close_panel()
	await r.wait_sec(0.4)
	if hud.is_panel_open(): hud.close_panel()
	await r.wait_sec(0.4)
	_panel_state_ok("shop over notebook")
	town.close_panel()   # harmless when nothing is open
	await r.wait_frames(3)
	_panel_state_ok("town.close_panel with nothing open")

func t_32_every_panel_closes_via_ui_signal() -> void:
	# the panels' own close buttons must work: emit the close signals the HUD/town listen to
	reset_world()
	await r.ensure_main()
	if not _need(["hud", "town"]): return
	var town: Node = r.part("town")
	var hud: Node = r.part("hud")
	town.open_shop("sell")
	await r.wait_frames(8)
	var panel = town.get("_panel")
	if panel == null: skip("town._panel not accessible"); return
	if panel.has_signal("closed"): panel.emit_signal("closed")
	await r.wait_sec(0.5)
	ok(not town.panel_open(), "shop panel did not close when it emitted 'closed'")
	_panel_state_ok("shop closed by its own signal")
	hud.open_notebook("cats")
	await r.wait_frames(8)
	var nb = hud.get("_notebook")
	if nb != null and nb.has_signal("close_requested"):
		nb.emit_signal("close_requested")
		await r.wait_sec(0.5)
		ok(not hud.is_panel_open(), "notebook did not close when it emitted close_requested")
		_panel_state_ok("notebook closed by its own signal")
	else:
		hud.close_panel(); await r.wait_sec(0.4)

# ------------------------------------------------------------------ shop economy (pure logic)
func _eco() -> Script:
	var path = "res://scripts/systems/town/economy.gd"
	return load(path) if ResourceLoader.exists(path) else null

func t_40_shop_buy_sell_math() -> void:
	reset_world()
	var eco = _eco()
	if eco == null: skip("economy.gd not written yet"); return
	eco.set_mods(0.0, 0.0)
	var fish = data_dict("FISH")
	var base = int(fish["sardine"].price)
	# sell
	gs.add_item("fish:sardine", 3)
	var c0: int = gs.coins
	var got: int = eco.sell("fish:sardine", 2)
	eq(got, base * 2, "selling 2 sardines pays 2 x price")
	eq(gs.coins, c0 + base * 2, "coins after selling")
	eq(int(gs.bag.get("fish:sardine", 0)), 1, "bag after selling 2 of 3")
	eq(eco.sell("fish:sardine", 5), base, "selling more than carried only sells what you have")
	eq(eco.sell("fish:sardine", 1), 0, "selling an item you do not have pays nothing")
	ok(not gs.bag.has("fish:sardine"), "sold-out item must leave the bag")
	# gold
	gs.add_item("fish:sardine_gold", 1)
	var gold_mult = int(data_const("GOLD_PRICE_MULT", 5))
	eq(eco.unit_price("fish:sardine_gold"), base * gold_mult, "gold fish price is price x GOLD_PRICE_MULT")
	# items that must not be sellable
	gs.add_item("treat:cream", 1)
	eq(eco.sell("treat:cream", 1), 0, "treats are not sellable")
	eq(int(gs.bag.get("treat:cream", 0)), 1, "a refused sale must not remove the item")
	# buy
	gs.coins = 1000
	var tuna_price = int(data_dict("SHOP")["treat:tuna_bites"].price)
	var before_bag: int = int(gs.bag.get("treat:tuna_bites", 0))
	var res: Dictionary = eco.buy("treat:tuna_bites")
	ok(bool(res.get("ok", false)), "buying a treat with enough yen failed: %s" % str(res))
	eq(gs.coins, 1000 - tuna_price, "coins after buying a treat")
	eq(int(gs.bag.get("treat:tuna_bites", 0)), before_bag + 1, "treat in the bag after buying")
	gs.coins = tuna_price - 1
	res = eco.buy("treat:tuna_bites")
	ok(not bool(res.get("ok", true)), "buying without enough yen must fail")
	eq(gs.coins, tuna_price - 1, "a failed purchase must not take yen")
	ok(str(res.get("msg", "")) != "", "a failed purchase needs a message for the player")
	res = eco.buy("treat:does_not_exist")
	ok(not bool(res.get("ok", true)), "buying an unknown id must fail")
	# discount perk
	eco.set_mods(0.10, 0.0)
	var disc: int = eco.buy_price("treat:cream")
	eq(disc, int(round(500 * 0.9)) if int(data_dict("SHOP")["treat:cream"].price) == 500 else disc, "10% discount on a treat")
	ok(disc < int(data_dict("SHOP")["treat:cream"].price), "a shop_discount perk must lower prices")
	eco.set_mods(0.0, 0.0)
	reset_world()

func t_41_rods_and_cosmetics() -> void:
	reset_world()
	var eco = _eco()
	if eco == null: skip("economy.gd not written yet"); return
	eco.set_mods(0.0, 0.0)
	var shop = data_dict("SHOP")
	gs.coins = 1000000
	# rod 3 is locked before rod 2 and before its lantern
	var res: Dictionary = eco.buy("rod:3")
	ok(not bool(res.get("ok", true)), "rod 3 must not be buyable before rod 2")
	eq(gs.rod_level, 1, "rod level after a refused purchase")
	res = eco.buy("rod:2")
	ok(bool(res.get("ok", false)), "buying rod 2 with plenty of yen failed: %s" % str(res))
	eq(gs.rod_level, 2, "rod level after buying rod 2")
	eq(gs.coins, 1000000 - int(shop["rod:2"].price), "yen after buying rod 2")
	res = eco.buy("rod:2")
	ok(not bool(res.get("ok", true)), "rod 2 must not be buyable twice")
	var need = shop.get("rod:3", {}).get("needs_lantern", "")
	if need != "":
		var before: int = gs.coins
		res = eco.buy("rod:3")
		ok(not bool(res.get("ok", true)) and gs.rod_level == 2, "rod 3 needs the %s lantern but could be bought without it" % need)
		eq(gs.coins, before, "refused rod 3 purchase must not take yen")
		gs.lanterns[need] = true
		res = eco.buy("rod:3")
		ok(bool(res.get("ok", false)), "rod 3 should be buyable once the %s lantern is lit: %s" % [need, str(res)])
		eq(gs.rod_level, 3, "rod level after buying rod 3")
	# hidden items are never listed
	if eco.has_method("shop_ids"):
		for id in eco.shop_ids():
			ok(not bool(shop.get(str(id), {}).get("hidden", false)), "hidden item '%s' is listed in the shop" % str(id))
			var nl = str(shop.get(str(id), {}).get("needs_lantern", ""))
			ok(nl == "" or gs.lanterns.has(nl), "'%s' is listed before the %s lantern is lit" % [str(id), nl])
	# cosmetics: buy, wear, take off, persist
	gs.coins = 1000000
	res = eco.buy("cos:scarf_mint")
	ok(bool(res.get("ok", false)), "buying a scarf failed: %s" % str(res))
	ok(gs.cosmetics.has("cos:scarf_mint"), "scarf not in GameState.cosmetics after buying")
	ok(eco.is_equipped("cos:scarf_mint"), "a bought cosmetic should be worn")
	eco.equip("cos:scarf_mint", false)
	ok(not eco.is_equipped("cos:scarf_mint"), "equip(false) did not take it off")
	res = eco.buy("cos:scarf_mint")
	ok(not bool(res.get("ok", true)), "cosmetic bought twice")
	gs.save_game()
	var d = read_json_file("user://save.json")
	ok(typeof(d) == TYPE_DICTIONARY and d.get("cosmetics", {}).has("cos:scarf_mint") and int(d.get("rod_level", 0)) >= 2, "purchases are not in save.json")
	reset_world()

# ------------------------------------------------------------------ fishing / shore / lantern flows
func t_50_fishing_auto_run_catches_a_fish() -> void:
	reset_world()
	await r.fresh_main()
	if not _need(["fishing", "player"]): return
	var f: Node = r.part("fishing")
	var p: Node3D = r.part("player")
	var spots = f.get("spots")
	if typeof(spots) != TYPE_DICTIONARY or spots.is_empty(): skip("fishing has no spots yet"); return
	var key = "pier_end" if spots.has("pier_end") else str(spots.keys()[0])
	var sp: Node3D = spots[key]
	_set_time("morning", 30.0)
	await r.wait_frames(5)
	f.set("_test", {"result": "catch", "nibbles": "0"})   # the system's own autopilot (same as `-- test=fishing`)
	if not is_nan(_ground_y(0, 0)) and _spot("pier_end") != Vector3.ZERO: _teleport(p, _spot("pier_end") + Vector3(0, 0.1, 0))
	else: _teleport(p, sp.global_position + Vector3(0, 0.1, 0))
	await r.wait_frames(5)
	var logged_before = gs.fish_log.size()
	f.begin(sp, p)
	ok(f.is_active(), "fishing.begin() did not start a session")
	ok(bool(p.get("busy")), "player must be busy while fishing")
	var finished: bool = await r.wait_until(func(): return not f.is_active() or (f.ui != null and f.ui.card_open()), 40.0)
	ok(finished, "the fishing auto-run did not reach the catch card within 40 s (state %s)" % str(f.get("state")))
	await r.wait_sec(0.5)
	ok(gs.fish_log.size() > logged_before, "no entry in fish_log after a caught fish")
	var any_fish = false
	for k in gs.bag.keys():
		if str(k).begins_with("fish:"): any_fish = true
	ok(any_fish, "the caught fish is not in the bag")
	for id in gs.fish_log.keys():
		var e: Dictionary = gs.fish_log[id]
		ok(float(e.get("best_cm", 0.0)) > 0.0 and int(e.get("count", 0)) >= 1, "fish_log['%s'] looks wrong: %s" % [id, str(e)])
	# close the card the way the player would and make sure control comes back
	if f.ui != null and f.ui.card_open():
		ib.press(); ib.release()
		await r.wait_sec(0.5)
		if f.ui.card_open(): f.ui.close_card(); await r.wait_sec(0.5)
	f.set("_test", {})
	await r.wait_sec(0.5)
	ok(not f.is_active(), "fishing is still active after the card closed")
	ok(not bool(p.get("busy")), "player.busy stayed true after fishing finished (softlock)")
	ok(not gs.paused, "GameState.paused stayed true after fishing finished")

func t_51_fishing_cancel_and_miss_release_the_player() -> void:
	reset_world()
	await r.ensure_main()
	if not _need(["fishing", "player"]): return
	var f: Node = r.part("fishing")
	var p: Node3D = r.part("player")
	var spots = f.get("spots")
	if typeof(spots) != TYPE_DICTIONARY or spots.is_empty(): skip("fishing has no spots yet"); return
	var sp: Node3D = spots[spots.keys()[0]]
	_set_time("morning", 30.0)
	for result in ["miss", "cancel"]:
		await r.wait_sec(1.2)   # fishing cooldown
		f.set("_test", {"result": result, "nibbles": "1"})
		_teleport(p, sp.global_position + Vector3(0, 0.1, 0))
		await r.wait_frames(3)
		f.begin(sp, p)
		var done: bool = await r.wait_until(func(): return not f.is_active() or (f.ui != null and f.ui.card_open()), 30.0)
		if not done:
			# the player walks away to cancel (the system watches InputBridge.move)
			ib.touch_move = Vector2(1, 0)
			done = await r.wait_until(func(): return not f.is_active(), 3.0)
			ib.touch_move = Vector2.ZERO
		ok(done, "fishing '%s' never ended" % result)
		if f.ui != null and f.ui.card_open(): f.ui.close_card()
		await r.wait_sec(0.6)
		ok(not bool(p.get("busy")), "player.busy stayed true after a '%s' session (softlock)" % result)
	f.set("_test", {})
	# walking away mid-session cancels it
	await r.wait_sec(1.2)
	f.set("_test", {})
	_teleport(p, sp.global_position + Vector3(0, 0.1, 0))
	await r.wait_frames(3)
	f.begin(sp, p)
	await r.wait_sec(0.5)
	ib.touch_move = Vector2(0, 1)
	await r.wait_sec(1.0)
	ib.touch_move = Vector2.ZERO
	await r.wait_sec(0.5)
	ok(not bool(p.get("busy")) or f.is_active(), "player.busy is true although no fishing session is active")

func t_52_shore_pickup_counts_and_saves() -> void:
	reset_world()
	await r.fresh_main()
	if not _need(["shore", "player"]): return
	var shore: Node = r.part("shore")
	var p: Node3D = r.part("player")
	_set_time("morning", 10.0)
	await r.wait_sec(1.0)
	var items = _nodes_by_script("town/shore_pickup.gd")
	if items.is_empty(): skip("no shore items spawned (no island / beach yet?)"); return
	var daily = int(data_const("SHORE_BEACH_DAILY", 14))
	var beach_items = 0
	for it in items:
		if str(data_dict("SHORE").get(str(it.get("item_id")), {}).get("where", "beach")) == "beach": beach_items += 1
	ok(beach_items >= daily - 2 and beach_items <= daily + 2, "morning beach items: %d (Data.SHORE_BEACH_DAILY is %d)" % [beach_items, daily])
	var it: Node3D = items[0]
	var id = str(it.get("item_id"))
	_teleport(p, it.global_position + Vector3(0.3, 0.2, 0.0))
	await r.wait_frames(5)
	var prompt: String = it.get_prompt(p)
	ok(prompt != "", "a shore item next to the player offers no prompt")
	var count_before = int(gs.shore_log.get(id, 0))
	var n_before: int = shore.item_count()
	var sparks_before: int = gs.sparks
	it.interact(p)
	await r.wait_frames(3)
	eq(int(gs.shore_log.get(id, 0)), count_before + 1, "shore_log count for %s after pickup" % id)
	var in_bag = false
	for k in gs.bag.keys():
		if str(k).begins_with("shore:" + id): in_bag = true
	ok(in_bag or bool(data_dict("SHORE").get(id, {}).get("bottle", false)), "picked-up item shore:%s is not in the bag" % id)
	eq(shore.item_count(), n_before - 1, "items left on the shore after one pickup")
	ok(gs.sparks > sparks_before, "the first find of a kind should give a spark (SPARK.new_shore)")
	# autosave within a few seconds
	var wrote: bool = await r.wait_until(func():
		var d = read_json_file("user://save.json")
		return typeof(d) == TYPE_DICTIONARY and int(d.get("shore_log", {}).get(id, 0)) == count_before + 1, 4.0)
	ok(wrote, "the pickup was not saved to save.json within 4 s (save_soon missing?)")
	await r.wait_sec(0.5)
	if is_instance_valid(it) and it.is_inside_tree():
		ok(not it.is_visible_in_tree() or str(it.get_prompt(p)) == "", "the picked-up item still offers a prompt / is still visible")

func t_53_lantern_lighting() -> void:
	reset_world()
	await r.fresh_main()
	if not _need(["lanterns", "player"]): return
	var spots = _nodes_by_script("town/lantern_spot.gd")
	if spots.is_empty(): skip("no lantern spots built"); return
	var p: Node3D = r.part("player")
	var spot: Node3D = null
	for s in spots:
		if str(s.get("lantern_id")) == "harbour": spot = s
	if spot == null: spot = spots[0]
	var id = str(spot.get("lantern_id"))
	var cost = int(spot.get("cost"))
	_teleport(p, spot.global_position + Vector3(0.5, 0.2, 0.5))
	await r.wait_frames(5)
	gs.sparks = cost - 1
	eq(str(spot.get_prompt(p)), "", "lantern prompt should be hidden while you cannot afford it (%d < %d)" % [gs.sparks, cost])
	gs.sparks = cost + 2
	ok(str(spot.get_prompt(p)) != "", "lantern prompt should show once you have %d sparks" % cost)
	spot.interact(p)
	await r.wait_frames(5)
	ok(gs.lanterns.has(id), "lantern '%s' not in GameState.lanterns after lighting" % id)
	eq(gs.sparks, 2, "sparks after lighting (cost %d)" % cost)
	var again: int = gs.sparks
	spot.interact(p)
	eq(gs.sparks, again, "lighting twice must not spend sparks again")
	var opened = await r.wait_until(func(): return not bool(p.get("busy")), 4.0)
	ok(opened, "player.busy stayed true after the lantern moment (softlock)")
	var isl: Node = r.part("island")
	if isl != null and isl.has_method("is_walkable"):
		for sp in data_dict("SPOT_LANTERN").keys():
			if str(data_dict("SPOT_LANTERN")[sp]) == id and _spot(str(sp)) != Vector3.ZERO:
				ok(isl.is_walkable(_spot(str(sp))), "after lighting '%s' the gated spot '%s' is still not walkable" % [id, str(sp)])
	var saved: bool = await r.wait_until(func():
		var dd = read_json_file("user://save.json")
		return typeof(dd) == TYPE_DICTIONARY and dd.get("lanterns", {}).has(id), 4.5)
	ok(saved, "the lit lantern was not saved to save.json within 4.5 s (save_soon missing after lighting?)")
	reset_world()

# ------------------------------------------------------------------ cats / people vs Data
func t_60_cat_cast_matches_schedule() -> void:
	reset_world()
	await r.fresh_main()
	if not _need(["island", "cats"]): return
	var cats: Node = r.part("cats")
	if not cats.has_method("present_ids"): skip("cats has no present_ids()"); return
	var data = data_dict("CATS")
	var wx_days = {}
	for wx in WEATHERS:
		var d = _day_with_weather(wx)
		if d > 0: wx_days[wx] = d
	var problems: Array = []
	for slot in SLOTS:
		for wx in wx_days.keys():
			gs.day = wx_days[wx]
			_set_time(slot, 20.0)
			if cats.has_method("refresh_schedule"): cats.refresh_schedule(true)
			await r.wait_sec(0.5)
			var expect: Array = []
			for id in data.keys():
				var c: Dictionary = data[id]
				var nl = str(c.get("needs_lantern", ""))
				if nl != "" and not gs.lanterns.has(nl): continue
				var wo: Array = c.get("weather_only", [])
				if not wo.is_empty() and not (wx in wo): continue
				var spot = ""
				if wx == "rain" and c.has("rain_spot"): spot = str(c.rain_spot)
				elif wx == "sunny" and c.has("sun_spot") and c.get("haunts", {}).has(slot): spot = str(c.sun_spot)
				else: spot = str(c.get("haunts", {}).get(slot, ""))
				if spot != "": expect.append(str(id))
			var got: Array = cats.present_ids()
			got.sort(); expect.sort()
			if got != expect: problems.append("%s/%s: expected %s, cats on the island %s" % [slot, wx, str(expect), str(got)])
	ok(problems.is_empty(), "cat cast differs from Data.CATS haunts (%d): %s" % [problems.size(), " | ".join(problems.slice(0, 3))])
	gs.lanterns = {"harbour": true, "hill": true}
	gs.day = _day_with_weather("fog") if _day_with_weather("fog") > 0 else 10
	_set_time("evening", 10.0)
	cats.refresh_schedule(true)
	await r.wait_sec(0.5)
	if _day_with_weather("fog") > 0: ok("ghost" in cats.present_ids(), "Fog the cat should appear on a fog day once the harbour lantern is lit (present: %s)" % str(cats.present_ids()))
	reset_world()

func t_61_people_follow_routines() -> void:
	reset_world()
	await r.fresh_main()
	if not _need(["people"]): return
	var pe: Node = r.part("people")
	if not pe.has_method("person_at"): skip("people has no person_at(spot)"); return
	var table = people_table()
	if table.is_empty(): skip("no PEOPLE data"); return
	var tp = 0
	for slot in SLOTS:
		_set_time(slot, 20.0)
		await r.wait_sec(0.6)
		for id in table.keys():
			var want = table[id].get("routine", {}).get(slot, "")
			if typeof(want) == TYPE_ARRAY and not want.is_empty(): want = want[0]
			if str(want) == "": continue
			var nodes = pe.get("nodes")
			if typeof(nodes) == TYPE_DICTIONARY and nodes.has(id):
				tp += 1
				var n: Node3D = nodes[id]
				ok(is_instance_valid(n) and n.is_inside_tree(), "person '%s' is not in the tree at %s" % [id, slot])
	ok(tp > 0, "people system has no person nodes")
	# talking: the contract says talk(id) / give(id, item) exist and never leave the player busy
	if pe.has_method("talk"):
		var p: Node = r.part("player")
		var pts_before: int = int(gs.person_state("pip").points)
		pe.talk("pip")
		await r.wait_sec(0.6)
		var dlg = pe.get("dialogue")
		if dlg != null and dlg.has_method("close"): dlg.close()
		await r.wait_sec(0.6)
		if dlg != null and dlg.get("active") == true: warn("dialogue still active 1.2 s after talk() and close()")
		if p != null: ok(not bool(p.get("busy")), "player.busy stayed true after talking to Pip (softlock)")
		gs.set_paused(false)
		ok(int(gs.person_state("pip").points) >= pts_before, "talking to Pip reduced his friendship points")
	reset_world()

# ------------------------------------------------------------------ time / weather / days
func t_70_slot_and_weather_sweep_has_no_errors() -> void:
	reset_world()
	await r.fresh_main()
	if r.main == null: return
	var n = 0
	for wx in WEATHERS:
		var d = _day_with_weather(wx)
		if d == 0: continue
		for slot in SLOTS:
			gs.day = d
			_set_time(slot, 5.0)
			await r.wait_frames(6)
			n += 1
	ok(n >= 12, "only %d weather/slot combinations could be visited" % n)
	# low tide on and off
	for m in [370.0, 600.0, 1100.0, 1300.0]:
		gs.minute = m
		await r.wait_frames(4)

func t_71_new_day_flow() -> void:
	reset_world()
	await r.fresh_main()
	if r.main == null: return
	await r.wait_frames(5)
	var days = [gs.day]
	var cb = func(d): days.append(d)
	gs.new_day.connect(cb)
	for i in 3:
		gs.minute = 1799.0
		gs._process(1.0)
		await r.wait_sec(0.4)
	gs.new_day.disconnect(cb)
	eq(gs.day, 4, "three overnight rollovers")
	eq(days.size(), 4, "new_day fires once per rollover")
	var shore = r.part("shore")
	if shore != null and not _nodes_by_script("town/shore_pickup.gd").is_empty():
		_set_time("morning", 10.0)
		await r.wait_sec(0.5)
		ok(shore.item_count() >= int(data_const("SHORE_BEACH_DAILY", 14)) - 2, "a new day should respawn the beach items (have %d)" % shore.item_count())
	var town = r.part("town")
	if town != null:
		ok(gs.requests.size() <= int(data_const("REQUESTS_PER_DAY", 3)), "more than REQUESTS_PER_DAY requests: %d" % gs.requests.size())
		if town.has_method("open_board"):
			town.open_board(); await r.wait_sec(0.5)
			ok(gs.requests.size() >= 1, "no requests on the board on day %d" % gs.day)
			ok(gs.requests.size() <= int(data_const("REQUESTS_PER_DAY", 3)), "board has %d requests (max %d)" % [gs.requests.size(), int(data_const("REQUESTS_PER_DAY", 3))])
			for q in gs.requests:
				ok(typeof(q) == TYPE_DICTIONARY, "a request is not a Dictionary: %s" % str(q))
			town.close_panel(); await r.wait_sec(0.4)
	_panel_state_ok("after the new-day flow")

func t_72_save_load_reload_main() -> void:
	# play a bit, save, tear everything down, boot main again: state is restored and no errors
	reset_world()
	await r.fresh_main()
	if r.main == null: return
	gs.coins = 777; gs.sparks = 5; gs.day = 3
	gs.add_item("fish:crab", 2)
	gs.shore_log["shell_white"] = 3
	gs.lanterns["harbour"] = true
	gs.save_game()
	var m = await r.fresh_main()
	if m == null: return
	gs.load_game()
	await r.wait_frames(10)
	eq(gs.coins, 777, "yen after reboot + load")
	eq(gs.day, 3, "day after reboot + load")
	eq(int(gs.bag.get("fish:crab", 0)), 2, "bag after reboot + load")
	ok(gs.lanterns.has("harbour"), "lantern after reboot + load")
	var spots = _nodes_by_script("town/lantern_spot.gd")
	for s in spots:
		if str(s.get("lantern_id")) == "harbour": ok(bool(s.get("lit")), "harbour lantern is not lit after loading a save with it lit")
	reset_world()

func t_73_soak_does_not_leak() -> void:
	reset_world()
	await r.fresh_main()
	if r.main == null: return
	await r.wait_sec(1.0)
	var nodes_before = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans_before = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for i in 4:
		for slot in SLOTS:
			_set_time(slot, 5.0)
			await r.wait_sec(0.25)
		gs.minute = 1799.0
		gs._process(1.0)
		await r.wait_sec(0.3)
	await r.wait_sec(1.0)
	var nodes_after = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans_after = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	note("nodes %d -> %d, orphans %d -> %d over 4 simulated days" % [nodes_before, nodes_after, orphans_before, orphans_after])
	ok(nodes_after <= nodes_before * 1.25 + 40, "node count grew from %d to %d over 4 days (leak?)" % [nodes_before, nodes_after])
	ok(orphans_after <= orphans_before + 25, "orphan nodes grew from %d to %d (nodes removed from the tree but never freed)" % [orphans_before, orphans_after])
	reset_world()

# ------------------------------------------------------------------ characters look right (TEAM.md, owner binding)
func _check_grounded(samples_by_label: Dictionary, label_prefix: String) -> void:
	for label in samples_by_label.keys():
		var offs: Array = samples_by_label[label].offsets
		if offs.is_empty(): continue
		var first: float = float(offs[0])
		var sorted = offs.duplicate(); sorted.sort()
		var median: float = float(sorted[sorted.size() / 2])
		var worst: float = 0.0
		for o in offs:
			if absf(float(o)) > absf(worst): worst = float(o)
		var info: String = samples_by_label[label].info
		if absf(first) > GROUND_TOL:
			fail("%s%s: off the ground at spawn by %+.3f m (%s; %s)" % [label_prefix, label, first, "floating" if first > 0 else "sunk", info])
		elif absf(median) > GROUND_TOL:
			fail("%s%s: median offset while wandering %+.3f m (%s; worst %+.3f; %s)" % [label_prefix, label, median, "floating" if median > 0 else "sunk", worst, info])
		elif absf(worst) > GROUND_TOL * 4.0:
			warn("%s%s: momentary offset %+.3f m while moving (%s)" % [label_prefix, label, worst, info])

func _sample_characters(store: Dictionary) -> void:
	for c in characters():
		var n: Node3D = c.node
		if not is_instance_valid(n) or not n.is_inside_tree() or not n.is_visible_in_tree(): continue
		var low = lowest_point(n)
		if low.mesh == null: continue
		var gp = n.global_position
		var cands = _surface_candidates(n, gp.x, gp.z)
		if cands.is_empty(): continue
		# the surface they stand on: the candidate closest to the lowest mesh point (ground_y, a bench via ray, own surface_y)
		var best_off = INF
		var best_name = ""
		for cand in cands:
			var off: float = float(low.y) - float(cand[1])
			if absf(off) < absf(best_off): best_off = off; best_name = str(cand[0])
		var key: String = c.label
		if not store.has(key): store[key] = {"offsets": [], "info": ""}
		store[key].offsets.append(best_off)
		store[key].info = "lowest mesh %s at y=%.3f vs %s" % [str(low.mesh.name), float(low.y), best_name]

func t_80_characters_stand_on_ground() -> void:
	reset_world()
	await r.fresh_main()
	if not _need(["island", "player"]): return
	var samples = {}
	var visited = 0
	# several times of day so cats and townsfolk are out in different places
	for slot in SLOTS:
		_set_time(slot, 15.0)
		await r.wait_sec(0.8)
		var per = {}
		_sample_characters(per)                      # at spawn / right after the schedule moved them
		for k in 5:
			await r.wait_sec(0.4)                    # ~2 s of wandering
			_sample_characters(per)
		for label in per.keys():
			var key: String = "%s@%s" % [label, slot]
			samples[key] = per[label]
			visited += 1
	if visited == 0: skip("no character to measure yet"); return
	note("measured %d character/time-of-day combinations (tolerance %.0f cm)" % [visited, GROUND_TOL * 100.0])
	_check_grounded(samples, "")

func t_81_player_grounded_walking_and_riding() -> void:
	reset_world()
	await r.ensure_main()
	if not _need(["island", "player"]): return
	var p: CharacterBody3D = r.part("player")
	var sp = _spot("spawn")
	if sp != Vector3.ZERO: _teleport(p, sp + Vector3(0, 0.1, 0))
	await r.wait_sec(0.6)
	var samples = {}
	for mode in ["standing", "walking", "riding", "sitting"]:
		match mode:
			"walking": ib.touch_move = Vector2(0, -1)
			"riding":
				ib.touch_move = Vector2.ZERO
				ib.ride_pressed.emit()
				await r.wait_frames(10)
				ib.touch_move = Vector2(1, 0)
			"sitting":
				ib.touch_move = Vector2.ZERO
				if p.get("riding"): ib.ride_pressed.emit(); await r.wait_frames(6)
				if p.has_method("sit"): p.sit(true)
				await r.wait_sec(0.5)
		var per = {}
		for i in 4:
			await r.wait_sec(0.3)
			var low = lowest_point(p)
			var gp = p.global_position
			var cands = _surface_candidates(p, gp.x, gp.z)
			if low.mesh == null or cands.is_empty(): continue
			var best_off = INF
			for cand in cands:
				var off: float = float(low.y) - float(cand[1])
				if absf(off) < absf(best_off): best_off = off
			if not per.has("player"): per["player"] = {"offsets": [], "info": "mode %s, lowest mesh %s" % [mode, str(low.mesh.name)]}
			per["player"].offsets.append(best_off)
		for k in per.keys(): samples["%s (%s)" % [k, mode]] = per[k]
		if mode == "sitting" and p.has_method("sit"): p.sit(false)
	ib.touch_move = Vector2.ZERO
	if p.get("riding"): ib.ride_pressed.emit()
	if samples.is_empty(): skip("player has no measurable mesh"); return
	_check_grounded(samples, "")

func t_82_shore_items_rest_on_ground() -> void:
	reset_world()
	await r.fresh_main()
	if not _need(["island", "shore"]): return
	_set_time("morning", 10.0)
	await r.wait_sec(1.0)
	var items = _nodes_by_script("town/shore_pickup.gd")
	if items.is_empty(): skip("no shore items spawned"); return
	var bad: Array = []
	var worst = 0.0
	for it in items:
		if not it.is_visible_in_tree(): continue
		var low = lowest_point(it)
		if low.mesh == null: continue
		var gp: Vector3 = it.global_position
		var gy = _ground_y(gp.x, gp.z)
		if is_nan(gy): continue
		var off: float = float(low.y) - gy
		if absf(off) > absf(worst): worst = off
		if absf(off) > ITEM_TOL: bad.append("%s(%s) %+.3f" % [str(it.name), str(it.get("item_id")), off])
	note("%d shore items, worst offset %+.3f m" % [items.size(), worst])
	ok(bad.is_empty(), "shore items not resting on the ground (tolerance %.0f cm, %d of %d): %s" % [ITEM_TOL * 100.0, bad.size(), items.size(), ", ".join(bad.slice(0, 6))])

func t_83_characters_face_where_they_walk() -> void:
	reset_world()
	await r.ensure_main()
	if not _need(["player"]): return
	var p: CharacterBody3D = r.part("player")
	var sp = _spot("spawn")
	if sp != Vector3.ZERO: _teleport(p, sp + Vector3(0, 0.1, 0))
	await r.wait_sec(0.5)
	var rig: Node3D = p.get_node_or_null("Rig")
	if rig == null: skip("player has no 'Rig' node to read the facing from"); return
	var results: Array = []
	for dir in [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]:
		var a = p.global_position
		ib.touch_move = dir
		await r.wait_sec(0.9)
		var v = p.global_position - a
		v.y = 0.0
		var fwd = -rig.global_transform.basis.z   # Godot convention; the rig may use +Z (checked below)
		fwd.y = 0.0
		if v.length() < 0.8: continue
		var d1 = fwd.normalized().dot(v.normalized())
		var d2 = (-fwd).normalized().dot(v.normalized())
		results.append([dir, d1, d2])
		ib.touch_move = Vector2.ZERO
		await r.wait_sec(0.3)
	ib.touch_move = Vector2.ZERO
	if results.is_empty(): skip("player did not move far enough to judge the facing"); return
	# the rig faces +Z or -Z consistently: the same sign must win in every direction, and clearly
	var pos = 0; var neg = 0
	for res in results:
		if res[1] > 0.6: neg += 1
		if res[2] > 0.6: pos += 1
	ok(pos == results.size() or neg == results.size(), "Mocha does not face the direction he walks consistently: %s" % str(results))
