class_name UseExitCommand
extends SimCommand
## A party member at a level exit (a mine mouth, a ladder; SimState.exits)
## takes the whole party through it, outside combat. The sim only notes the
## trip (state.pending_travel) and says so (LEVEL_EXIT); the host then bakes
## or wakes the level beyond and hands the party over (LevelTravel), and
## guests get the new level as a snapshot.

const TYPE := "use_exit"
## How near the exit cell the character must stand (cells, any direction).
const REACH := 1

var entity_id: int
var exit_cell: Vector3i


func _init(p_entity_id: int = -1, p_exit_cell: Vector3i = Vector3i.ZERO) -> void:
	entity_id = p_entity_id
	exit_cell = p_exit_cell


func get_type() -> String:
	return TYPE


func actor_id() -> int:
	return entity_id


## Why `e` can't go through the exit at `cell` ("" = it can), for the UI.
static func blocker(state: SimState, e: SimEntity, cell: Vector3i) -> String:
	if not state.exits.has(cell):
		return "No way through here"
	if e == null or not e.is_alive() or e.faction != SimEntity.Faction.PLAYERS:
		return "Pick a party member"
	if state.combat.active:
		return "Not during a fight"
	if not state.pending_travel.is_empty():
		return "Already on the way"
	if e.cell != cell and not SimAbilities.is_adjacent(e.cell, cell):
		return "Too far"
	return ""


func validate(state: SimState) -> bool:
	return blocker(state, state.get_entity(entity_id), exit_cell) == ""


func execute(state: SimState) -> void:
	var exit: Dictionary = state.exits[exit_cell]
	state.pending_travel = {"level": exit.level, "entry": exit.entry}
	for e in state.entities:
		if e.faction == SimEntity.Faction.PLAYERS:
			e.travel.clear()
	if not state.conversation.is_empty():
		SimDialogue.end(state)
	var event := state.emit_event(SimEvent.Type.LEVEL_EXIT, exit_cell, entity_id)
	event.text = exit.get("name", "")


func to_dict() -> Dictionary:
	return {"type": TYPE, "entity_id": entity_id, "exit_cell": exit_cell}


static func from_dict(data: Dictionary) -> UseExitCommand:
	return UseExitCommand.new(data.entity_id, data.exit_cell)
