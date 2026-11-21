extends Node
## Renders small cat portraits (Toys.cat in a tiny SubViewport) once per cat into cached textures.
## request(cat_id, silhouette, target) fills `target.texture` as soon as it is ready; a silhouette is the
## same model drawn as one flat colour (for cats the player has not met). Needs to be inside the tree
## to render; skipped on headless runs (the Notebook keeps its drawn cat icon as a fallback).

const SIZE := 256
static var cache := {}              # "id:0|1" -> ImageTexture

var _vp: SubViewport
var _root: Node3D
var _queue: Array = []
var _cur := {}
var _wait := 0
var _ok := true

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		_ok = false
		set_process(false)
		return
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.gui_disable_input = true
	add_child(_vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff1e0")
	env.ambient_light_energy = 0.4
	we.environment = env
	_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("ffe9cc")
	sun.light_energy = 0.8
	sun.rotation_degrees = Vector3(-40, 30, 0)
	_vp.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(1.2, 1.9, 3.4)
	_vp.add_child(cam)
	cam.look_at(Vector3(0.0, 0.6, 0.15))
	cam.current = true
	_root = Node3D.new()
	_vp.add_child(_root)
	set_process(not _queue.is_empty())

## `fallback` (optional) is hidden once the texture is in place.
func request(cat_id: String, silhouette: bool, target: TextureRect, fallback: Control = null) -> void:
	var key := "%s:%d" % [cat_id, 1 if silhouette else 0]
	if cache.has(key):
		_apply(target, fallback, cache[key])
		return
	if not _ok: return
	if _cur.get("key", "") == key:
		_cur["targets"].append([target, fallback])
		return
	for q in _queue:
		if q["key"] == key:
			q["targets"].append([target, fallback])
			return
	_queue.append({"key": key, "id": cat_id, "sil": silhouette, "targets": [[target, fallback]]})
	set_process(true)

## Untyped on purpose: a card may have been freed (tab switched) while its portrait rendered.
func _apply(target, fallback, tex: Texture2D) -> void:
	if is_instance_valid(target): target.texture = tex
	if is_instance_valid(fallback): fallback.visible = false

func _process(_dt: float) -> void:
	if _cur.is_empty():
		if _queue.is_empty():
			set_process(false)
			return
		_cur = _queue.pop_front()
		_build_model(_cur["id"], _cur["sil"])
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_wait = 3
		return
	_wait -= 1
	if _wait > 0: return
	var img := _vp.get_texture().get_image()
	if img != null and not img.is_empty():
		var tex := ImageTexture.create_from_image(img)
		cache[_cur["key"]] = tex
		for t in _cur["targets"]:
			_apply(t[0], t[1], tex)
	_cur = {}
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()

func _build_model(cat_id: String, silhouette: bool) -> void:
	var def: Dictionary = Data.CATS.get(cat_id, {})
	var main := Color(str(def.get("main", "f2cf9c")))
	var patch_hex := str(def.get("patch", ""))
	var patch := Color(patch_hex) if patch_hex != "" else Color(0, 0, 0, 0)
	var holder := Node3D.new()
	holder.rotation.y = 0.42
	_root.add_child(holder)
	Toys.cat(holder, main, patch, false)
	if silhouette:
		var flat := StandardMaterial3D.new()
		flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flat.albedo_color = Color("b7a392")
		_flatten(holder, flat)

func _flatten(n: Node, m: Material) -> void:
	if n is MeshInstance3D:
		n.material_override = m
	for c in n.get_children():
		_flatten(c, m)
