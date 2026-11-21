extends Node3D
## Tiny interactable used only by the player self-test (`-- test=player`).
## Follows the Interactable contract from docs/TEAM.md.

var interact_radius := 2.0
var interact_priority := 0
var prompt := "Pet"
var color := Color("f2b880")

func _ready() -> void:
	add_to_group("interactable")
	var body := Toys.add(Toys.sphere(0.35), Toys.mat(color), Vector3(0, 0.35, 0), self, Vector3(1, 0.85, 1))
	body.name = "Body"

func get_prompt(_player) -> String:
	return prompt

func interact(player) -> void:
	print("[player test] interacted: ", prompt)
	var b: Node3D = get_node("Body")
	var tw := create_tween()
	tw.tween_property(b, "scale", Vector3(1.2, 0.65, 1.2), 0.08)
	tw.tween_property(b, "scale", Vector3(1, 0.85, 1), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if prompt == "Sit" and player.has_method("sit"):
		player.sit(true)
