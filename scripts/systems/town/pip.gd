extends Node3D
## Pip, the shopkeeper: a small round bunny with an apron and round glasses, built from Toys primitives.
## Pure visual (the "Shop" interactable lives on the counter, the People system adds "Talk" on Pip himself).
## Idles with a slow breath, twitches an ear now and then, and turns to look at Mocha when he is near.

var rest_yaw := 0.0
var look_target := Callable()      # returns a Vector3 world position, or Vector3.INF for "nobody"
var _body: Node3D
var _head: Node3D
var _ears: Array[Node3D] = []
var _t := 0.0
var _twitch := 2.0
var _hop: Tween
var _base_y := 0.0

func _ready() -> void:
	set_meta("person_id", "pip")
	rotation.y = rest_yaw
	_base_y = position.y
	_build()

func _build() -> void:
	var fur := Toys.mat(Color("f6eee2"))
	var light := Toys.mat(Color("fffaf2"))
	var inner := Toys.mat(Color("f2b8c0"), 0.9, 0.0)
	var apron := Toys.mat(Color("7fbfc9"), 0.85, 0.0)
	var dark := Toys.mat(Color("3b2a24"), 0.2, 0.0)
	var blush := Toys.mat(Color("f2a0a6"), 0.9, 0.0)
	var frame := Toys.mat(Color("6b4a3a"), 0.4, 0.0)

	_body = Toys.group(Vector3.ZERO, self)
	Toys.add(Toys.sphere(0.46), fur, Vector3(0, 0.5, 0), _body, Vector3(1.0, 1.0, 0.9))
	Toys.add(Toys.sphere(0.4), apron, Vector3(0, 0.5, 0.25), _body, Vector3(0.95, 1.15, 0.36))
	Toys.add(Toys.torus(0.22, 0.28), apron, Vector3(0, 0.9, 0.02), _body)
	for s in [-1, 1]:
		Toys.add(Toys.capsule(0.1, 0.44), fur, Vector3(0.4 * s, 0.6, 0.2), _body, Vector3.ONE, Vector3(-1.0, 0, 0.3 * s))
		Toys.add(Toys.sphere(0.14), fur, Vector3(0.2 * s, 0.08, 0.1), _body, Vector3(1, 0.7, 1.3))

	_head = Toys.group(Vector3(0, 1.2, 0.05), _body)
	Toys.add(Toys.sphere(0.4), fur, Vector3.ZERO, _head, Vector3(1.1, 0.95, 0.98))
	Toys.add(Toys.sphere(0.12), light, Vector3(0, -0.07, 0.33), _head, Vector3(1.25, 0.8, 0.7))
	Toys.add(Toys.sphere(0.045), blush, Vector3(0, -0.03, 0.43), _head)
	for s in [-1, 1]:
		Toys.add(Toys.sphere(0.045), dark, Vector3(0.15 * s, 0.06, 0.37), _head)
		Toys.add(Toys.torus(0.07, 0.1), frame, Vector3(0.15 * s, 0.06, 0.375), _head, Vector3.ONE, Vector3(PI / 2, 0, 0))
		Toys.add(Toys.sphere(0.06), blush, Vector3(0.28 * s, -0.08, 0.29), _head, Vector3(1, 0.6, 0.4))
		var ear := Toys.group(Vector3(0.16 * s, 0.3, -0.02), _head)
		ear.rotation.z = -0.16 * s if s < 0 else -0.5
		Toys.add(Toys.capsule(0.1, 0.62), fur, Vector3(0, 0.3, 0), ear)
		Toys.add(Toys.capsule(0.055, 0.42), inner, Vector3(0, 0.3, 0.07), ear, Vector3(1, 1, 0.5))
		_ears.append(ear)
	Toys.add(Toys.capsule(0.012, 0.1), frame, Vector3(0, 0.07, 0.385), _head, Vector3.ONE, Vector3(0, 0, PI / 2))

func _process(dt: float) -> void:
	_t += dt
	if _body == null: return
	_body.scale = Vector3(1.0, 1.0 + sin(_t * 2.1) * 0.014, 1.0)
	_head.rotation.z = sin(_t * 0.9) * 0.03
	_twitch -= dt
	if _twitch <= 0.0 and _ears.size() == 2:
		_twitch = randf_range(2.5, 6.0)
		var ear: Node3D = _ears[randi() % 2]
		var base := ear.rotation.x
		var tw := create_tween()
		tw.tween_property(ear, "rotation:x", base - 0.35, 0.08)
		tw.tween_property(ear, "rotation:x", base, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var yaw := rest_yaw
	if look_target.is_valid():
		var tp: Variant = look_target.call()
		if tp is Vector3 and tp != Vector3.INF:
			var d: Vector3 = tp - global_position
			d.y = 0.0
			if d.length() < 7.0 and d.length() > 0.2:
				yaw = atan2(d.x, d.z)
				yaw = rest_yaw + clampf(angle_difference(rest_yaw, yaw), -1.1, 1.1)
	rotation.y = lerp_angle(rotation.y, yaw, minf(1.0, dt * 4.0))

## A little hop: used when the shop opens.
func perk_up() -> void:
	if _hop != null and _hop.is_valid(): _hop.kill()
	_hop = create_tween()
	_hop.tween_property(self, "position:y", _base_y + 0.18, 0.1).set_ease(Tween.EASE_OUT)
	_hop.tween_property(self, "position:y", _base_y, 0.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
