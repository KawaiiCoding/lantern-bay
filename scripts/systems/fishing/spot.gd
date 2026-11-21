extends Node3D
## One fishing spot (Interactable contract, docs/TEAM.md). Prompt "Fish".
## Rocks need lantern "harbour"; flats need low tide + a perk (see Fishing.spot_unlocked). While a session runs here the prompt mirrors the session.

var spot_id := ""
var fishing: Node
var interact_radius := 2.4
var interact_priority := 1

func _ready() -> void:
	add_to_group("interactable")

func unlocked() -> bool:
	if is_instance_valid(fishing) and fishing.has_method("spot_unlocked"): return fishing.spot_unlocked(spot_id)
	return spot_id != "rocks" or GameState.lanterns.has("harbour")

func get_prompt(_player) -> String:
	if not is_instance_valid(fishing): return ""
	if fishing.is_active():
		return fishing.active_prompt() if fishing.spot_name == spot_id else ""
	if not unlocked() or not fishing.can_start(): return ""
	return "Fish"

func interact(player) -> void:
	if is_instance_valid(fishing) and not fishing.is_active() and unlocked():
		fishing.begin(self, player)
