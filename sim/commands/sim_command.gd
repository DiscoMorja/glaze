class_name SimCommand
extends RefCounted
## Base for every action applied to the sim (CLAUDE.md rule 2). The host
## validates and executes commands; clients only send them. Commands must be
## serializable via to_dict() and rebuilt with SimCommandRegistry.from_dict().


func get_type() -> String:
	return ""


func validate(_state: SimState) -> bool:
	return true


func execute(_state: SimState) -> void:
	pass


## The entity acting (whose player must own it), or -1 for world commands.
func actor_id() -> int:
	return -1


func to_dict() -> Dictionary:
	return {"type": get_type()}


static func _is_open_cell(state: SimState, c: Vector3i) -> bool:
	return state.grid.in_bounds(c) and not state.grid.is_solid(c)
