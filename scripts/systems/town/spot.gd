extends Node3D
## Generic interactable (see the Interactable contract in docs/TEAM.md). The prompt and the action come from
## callables owned by a system, so the system decides when it is available.

var interact_radius := 2.0
var interact_priority := 0
var prompt_fn := Callable()
var act_fn := Callable()

func _ready() -> void:
	add_to_group("interactable")

func get_prompt(player: Variant) -> String:
	if prompt_fn.is_valid():
		return str(prompt_fn.call(player))
	return ""

func interact(player: Variant) -> void:
	if act_fn.is_valid():
		act_fn.call(player)
