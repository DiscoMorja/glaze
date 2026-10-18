class_name SneakCommand
extends SimCommand
## Outside combat: a party member starts or stops sneaking. Sneaking walks at
## half speed and is only seen inside watchers' cones, at a shorter range
## (SimPerception).

const TYPE := "sneak"

var entity_id: int
var on: bool


func _init(p_entity_id: int = -1, p_on: bool = true) -> void:
	entity_id = p_entity_id
	on = p_on


func get_type() -> String:
	return TYPE


func actor_id() -> int:
	return entity_id


func validate(state: SimState) -> bool:
	var e := state.get_entity(entity_id)
	return not state.combat.active and e != null and e.is_alive() and e.takes_turns() and e.sneaking != on


func execute(state: SimState) -> void:
	state.get_entity(entity_id).sneaking = on


func to_dict() -> Dictionary:
	return {"type": TYPE, "entity_id": entity_id, "on": on}


static func from_dict(data: Dictionary) -> SneakCommand:
	return SneakCommand.new(data.entity_id, data.on)
