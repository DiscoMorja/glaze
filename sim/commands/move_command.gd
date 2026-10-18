class_name MoveCommand
extends SimCommand
## Walks an entity to a destination along SimPathfinder's path. Every burning
## cell walked over hurts and heats you a level; every ice cell staggers you
## (enough of it knocks you down, ending the walk); oil slows you (moves cost
## double AP); water cools you a level.

const TYPE := "move"

var entity_id: int
var destination: Vector3i


func _init(p_entity_id: int = -1, p_destination: Vector3i = Vector3i.ZERO) -> void:
	entity_id = p_entity_id
	destination = p_destination


func get_type() -> String:
	return TYPE


func validate(state: SimState) -> bool:
	var e := state.get_entity(entity_id)
	if not CombatRules.can_act(state, e, 0) or e.cell == destination:
		return false
	var path := path_for(state, e, destination)
	if path.is_empty():
		return false
	return not state.combat.active or ap_cost(e, e.cell, path) <= e.ap


func execute(state: SimState) -> void:
	var e := state.get_entity(entity_id)
	var path := path_for(state, e, destination)
	CombatRules.spend(state, e, ap_cost(e, e.cell, path))
	var walked: Array[Vector3i] = []
	var start := e.cell
	for c in path:
		e.facing = SimPerception.facing_toward(e.cell, c, e.facing)
		e.cell = c
		walked.append(c)
		EntityOps.enter_cell(state, e)
		if not e.is_alive() or e.knocked_down or e.is_frozen():
			break
	var moved := state.emit_event(SimEvent.Type.MOVED, e.cell, e.id)
	moved.cells = walked
	moved.amount = SimPathfinder.movement_cost(start, walked)


## The path a move takes: around hazards when that is affordable, otherwise
## the cheapest path straight through them.
static func path_for(state: SimState, e: SimEntity, to: Vector3i) -> Array[Vector3i]:
	var safe := SimPathfinder.find_path(state, e.cell, to, e.id)
	if not state.combat.active or (not safe.is_empty() and ap_cost(e, e.cell, safe) <= e.ap):
		return safe
	var direct := SimPathfinder.find_path(state, e.cell, to, e.id, false, false)
	return direct if not direct.is_empty() else safe


## AP for walking path; double while slowed.
static func ap_cost(e: SimEntity, from: Vector3i, path: Array[Vector3i]) -> int:
	var cost := SimPathfinder.movement_cost(from, path)
	return CombatRules.move_ap_cost(cost * 2 if e.is_slowed() else cost)


func actor_id() -> int:
	return entity_id


func to_dict() -> Dictionary:
	return {"type": TYPE, "entity_id": entity_id, "destination": destination}


static func from_dict(data: Dictionary) -> MoveCommand:
	return MoveCommand.new(data.entity_id, data.destination)
