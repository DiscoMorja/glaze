class_name EndTurnCommand
extends SimCommand
## Ends the current side's turn: the world advances, then the other side acts.

const TYPE := "end_turn"

var faction: int


func _init(p_faction: int = SimEntity.Faction.PLAYERS) -> void:
	faction = p_faction


func get_type() -> String:
	return TYPE


func validate(state: SimState) -> bool:
	return state.combat.active and state.combat.side == faction


func execute(state: SimState) -> void:
	CombatRules.end_side_turn(state)


func to_dict() -> Dictionary:
	return {"type": TYPE, "faction": faction}


static func from_dict(data: Dictionary) -> EndTurnCommand:
	return EndTurnCommand.new(data.faction)
