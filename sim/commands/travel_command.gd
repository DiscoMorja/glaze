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
## A route that came with the command (the host found it): replaying peers
## check it step by step instead of searching again.
var _given: Array[Vector3i] = []


func validate(state: SimState) -> bool:
	return may_walk(state) and not route(state).is_empty()


## Everything validate() checks except that a route exists (cheap: no search).
func may_walk(state: SimState) -> bool:
	var e := state.get_entity(entity_id)
	if state.combat.active or not CombatRules.can_act(state, e, 0) or e.cell == destination:
		return false
	return not too_far(e.cell, destination)


## Hands the command a route found elsewhere (a search spread over frames), so
## validate() and execute() only check it.
func set_route(cells: Array[Vector3i]) -> void:
	_given.assign(cells)
	_route_key = []


static func too_far(from: Vector3i, to: Vector3i) -> bool:
	return maxi(absi(to.x - from.x), absi(to.z - from.z)) > MAX_DISTANCE


func execute(state: SimState) -> void:
	state.get_entity(entity_id).travel.assign(route(state))
	if not state.conversation.is_empty() and state.conversation.talker == entity_id:
		SimDialogue.end(state)  # walking away ends the talk


## The cells the walk will take (empty if there is no way there).
func route(state: SimState) -> Array[Vector3i]:
	var e := state.get_entity(entity_id)
	var key := [state.get_instance_id(), state.tick, e.cell]
	if key != _route_key:
		var given := _from_here(state, e, _given)
		if not given.is_empty():
			_route = given
		else:
			_route = SimPathfinder.find_path(state, e.cell, destination, e.id, false, true, MAX_SEARCH_CELLS)
		_route_key = key
	return _route.duplicate()


## The part of `cells` that walks `e` from where it stands to the
## destination, each step to a neighbour it can walk to, or [] (cheap: no
## search). A walker that moved on while the route was found (a step or two
## along its last walk) picks it up from the farthest cell it stands on or
## next to.
func _from_here(state: SimState, e: SimEntity, cells: Array[Vector3i]) -> Array[Vector3i]:
	var none: Array[Vector3i] = []
	if cells.is_empty() or cells.back() != destination:
		return none
	var occupied := SimPathfinder.occupancy(state)
	var first := -1
	var next := SimPathfinder._neighbors(state.grid, occupied, e.cell, e.id)
	for i in range(cells.size() - 1, -1, -1):
		if cells[i] == e.cell:
			first = i + 1
			break
		if next.has(cells[i]):
			first = i
			break
	if first < 0 or first >= cells.size():
		return none
	var result := cells.slice(first)
	var at := e.cell
	for c in result:
		if not SimPathfinder._neighbors(state.grid, occupied, at, e.id).has(c):
			return none
		at = c
	return result


func actor_id() -> int:
	return entity_id


func to_dict() -> Dictionary:
	var data := {"type": TYPE, "entity_id": entity_id, "destination": destination}
	if not _route.is_empty():
		data["route"] = _route.duplicate()
	return data


static func from_dict(data: Dictionary) -> TravelCommand:
	var command := TravelCommand.new(data.entity_id, data.destination)
	command._given.assign(data.get("route", []))
	return command
