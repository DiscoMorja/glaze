class_name TravelCommand
extends SimCommand
## Outside combat: sets an entity walking to a destination in real time. The
## walk itself happens in EntityRules, one cell per tick, so the world (and
## anyone watching) reacts while it is on the way.

const TYPE := "travel"
## Farthest walk one command can order (cells along x or z); click again on
## the way for longer trips. Keeps the route search (and its preview) cheap.
const MAX_DISTANCE := 40
## Cells the route search may settle before giving up (detours included).
const MAX_SEARCH_CELLS := 5000

var entity_id: int
var destination: Vector3i


func _init(p_entity_id: int = -1, p_destination: Vector3i = Vector3i.ZERO) -> void:
	entity_id = p_entity_id
	destination = p_destination


func get_type() -> String:
	return TYPE


## Last route found, so validate() and execute() (or a preview) search once.
## Keyed by the state, its tick and the walker's cell.
var _route: Array[Vector3i] = []
var _route_key: Array = []


func validate(state: SimState) -> bool:
	var e := state.get_entity(entity_id)
	if state.combat.active or not CombatRules.can_act(state, e, 0) or e.cell == destination:
		return false
	if too_far(e.cell, destination):
		return false
	return not route(state).is_empty()


static func too_far(from: Vector3i, to: Vector3i) -> bool:
	return maxi(absi(to.x - from.x), absi(to.z - from.z)) > MAX_DISTANCE


func execute(state: SimState) -> void:
	state.get_entity(entity_id).travel.assign(route(state))


## The cells the walk will take (empty if there is no way there).
func route(state: SimState) -> Array[Vector3i]:
	var e := state.get_entity(entity_id)
	var key := [state.get_instance_id(), state.tick, e.cell]
	if key != _route_key:
		_route = SimPathfinder.find_path(state, e.cell, destination, e.id, false, true, MAX_SEARCH_CELLS)
		_route_key = key
	return _route.duplicate()


func to_dict() -> Dictionary:
	return {"type": TYPE, "entity_id": entity_id, "destination": destination}


static func from_dict(data: Dictionary) -> TravelCommand:
	return TravelCommand.new(data.entity_id, data.destination)
