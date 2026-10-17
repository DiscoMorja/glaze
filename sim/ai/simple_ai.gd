class_name SimpleAi
extends RefCounted
## Placeholder AI: walk toward the nearest opponent and hit it. Utility AI
## with lookahead replaces this later in M1.
##
## Returns one command at a time, so the host can replicate and animate each
## action. Ends the turn when no unit can do anything useful.


static func next_command(state: SimState) -> SimCommand:
	var side := state.combat.side
	for e in CombatRules.fighters(state, side):
		var command := _command_for(state, e)
		if command != null and command.validate(state):
			return command
	return EndTurnCommand.new(side)


static func _command_for(state: SimState, e: SimEntity) -> SimCommand:
	var target := _nearest_opponent(state, e)
	if target == null:
		return null
	if SimAbilities.is_adjacent(e.cell, target.cell):
		if e.ap < CombatRules.ATTACK_AP:
			return null
		return AttackCommand.new(e.id, target.id)
	var path := SimPathfinder.find_path(state, e.cell, target.cell, e.id, true)
	var reachable := SimPathfinder.affordable_prefix(e.cell, path, e.ap * CombatRules.MOVE_COST_PER_AP)
	if reachable.is_empty():
		return null
	return MoveCommand.new(e.id, reachable.back())


static func _nearest_opponent(state: SimState, e: SimEntity) -> SimEntity:
	var best: SimEntity = null
	var best_distance := 1 << 30
	for other in CombatRules.fighters(state, CombatRules.opponent_of(e.faction)):
		var d := SimPathfinder.distance(e.cell, other.cell)
		if d < best_distance:
			best = other
			best_distance = d
	return best
