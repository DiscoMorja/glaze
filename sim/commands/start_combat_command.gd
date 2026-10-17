class_name StartCombatCommand
extends SimCommand
## Switches the world to turn-based combat; players act first.

const TYPE := "start_combat"


func get_type() -> String:
	return TYPE


func validate(state: SimState) -> bool:
	return not state.combat.active


func execute(state: SimState) -> void:
	CombatRules.start(state)


static func from_dict(_data: Dictionary) -> StartCombatCommand:
	return StartCombatCommand.new()
