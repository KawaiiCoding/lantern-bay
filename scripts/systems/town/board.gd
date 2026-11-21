extends Node3D
## The request board in the world: a little wooden notice board with pinned papers and a bobbing marker
## above it while there are open requests. The "Read the board" interactable is a sibling (spot.gd).

var rest_yaw := 0.0
var _marker: Node3D
var _t := 0.0
var _show := false

func _ready() -> void:
	rotation.y = rest_yaw
	var wood := Toys.mat(Color("c98a5a"))
	var post := Toys.mat(Color("9a7058"))
	var roof := Toys.mat(Color("e58a94"))
	Toys.add(Toys.cyl(0.07, 0.09, 1.9), post, Vector3(-0.8, 0.95, 0), self)
	Toys.add(Toys.cyl(0.07, 0.09, 1.9), post, Vector3(0.8, 0.95, 0), self)
	Toys.add(Toys.box(1.9, 1.15, 0.12), wood, Vector3(0, 1.4, 0), self)
	var pr := PrismMesh.new(); pr.size = Vector3(2.3, 0.4, 0.55)
	Toys.add(pr, roof, Vector3(0, 2.2, 0), self)
	var papers := [
		[Vector3(-0.55, 1.55, 0.08), Color("fff6ea"), 0.08], [Vector3(0.0, 1.5, 0.08), Color("ffe3a8"), -0.06],
		[Vector3(0.55, 1.55, 0.08), Color("cfe8d8"), 0.05], [Vector3(-0.25, 1.05, 0.08), Color("fbc9d2"), -0.1],
		[Vector3(0.35, 1.05, 0.08), Color("d7e3ff"), 0.09],
	]
	var pins := [Color("e58a94"), Color("6fc2b6"), Color("f2c14e")]
	for i in papers.size():
		var p: Array = papers[i]
		var sheet := Toys.add(Toys.box(0.42, 0.5, 0.03), Toys.mat(p[1], 0.9, 0.012), p[0], self, Vector3.ONE, Vector3(0, 0, p[2]))
		Toys.add(Toys.sphere(0.035), Toys.mat(pins[i % pins.size()], 0.5, 0.01), Vector3(0, 0.2, 0.03), sheet)
		for k in 3:
			Toys.add(Toys.box(0.28 - k * 0.04, 0.025, 0.012), Toys.mat(Color("9a7a68"), 0.9, 0.0), Vector3(0, 0.07 - k * 0.1, 0.02), sheet)
	# marker: a gold exclamation mark
	_marker = Toys.group(Vector3(0, 2.95, 0), self)
	var gold := Toys.glow(Color("f2c14e"), 1.6)
	Toys.add(Toys.capsule(0.09, 0.42), gold, Vector3(0, 0.12, 0), _marker)
	Toys.add(Toys.sphere(0.09), gold, Vector3(0, -0.22, 0), _marker)
	_marker.visible = _show

func set_marker(on: bool) -> void:
	_show = on
	if _marker != null: _marker.visible = on

func _process(dt: float) -> void:
	_t += dt
	if _marker != null and _marker.visible:
		_marker.position.y = 2.95 + sin(_t * 3.0) * 0.1
		_marker.rotation.y += dt * 1.6
