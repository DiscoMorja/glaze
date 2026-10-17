class_name TravelCommand
extends SimCommand
## Outside combat: sets an entity walking to a destination in real time. The
## walk itself happens in EntityRules, one cell per tick, so the world (and
## anyone watching) reacts while it is on the way.

const TYPE := "travel"

var entity_id: int
var destination: Vector3i


func _init(p_entity_id: int = -1, p_destination: Vector3i = Vector3i.ZERO) -> void:
	entity_id = p_entity_id
	destination = p_destination


func get_type() -> String:
	return TYPE


func validate(state: SimState) -> bool:
	var e := state.get_entity(entity_id)
	if state.combat.active or not CombatRules.can_act(state, e, 0) or e.cell == destination:
		return false
	return not SimPathfinder.find_path(state, e.cell, destination, e.id).is_empty()


func execute(state: SimState) -> void:
	var e := state.get_entity(entity_id)
	e.travel.assign(SimPathfinder.find_path(state, e.cell, destination, e.id))


func to_dict() -> Dictionary:
	return {"type": TYPE, "entity_id": entity_id, "destination": destination}


static func from_dict(data: Dictionary) -> TravelCommand:
	return TravelCommand.new(data.entity_id, data.destination)
