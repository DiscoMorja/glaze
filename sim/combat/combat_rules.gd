class_name CombatRules
extends RefCounted
## Turn flow and action point (AP) economy. Divinity-style AP pool: units gain
## max_ap per turn and can bank up to AP_CAP. Outside combat nothing costs AP.

const AP_CAP := 6
## Sim ticks advanced at the end of each side's turn.
const TICKS_PER_SIDE_TURN := 4
## Movement cost units per AP (10 = one straight cell, so 2 cells per AP).
const MOVE_COST_PER_AP := 20
const ATTACK_AP := 2


static func start(state: SimState) -> void:
	var combat := state.combat
	combat.active = true
	combat.side = SimEntity.Faction.PLAYERS
	combat.round_number = 1
	state.emit_event(SimEvent.Type.COMBAT_STARTED)
	_begin_side(state)


static func end_side_turn(state: SimState) -> void:
	state.step_ticks(TICKS_PER_SIDE_TURN)
	if check_end(state):
		return
	var combat := state.combat
	if combat.side == SimEntity.Faction.PLAYERS:
		combat.side = SimEntity.Faction.ENEMIES
	else:
		combat.side = SimEntity.Faction.PLAYERS
		combat.round_number += 1
	_begin_side(state)


## Ends combat when one side has no living fighters. Returns true if it ended.
static func check_end(state: SimState) -> bool:
	var combat := state.combat
	if not combat.active:
		return false
	var players_alive := not fighters(state, SimEntity.Faction.PLAYERS).is_empty()
	var enemies_alive := not fighters(state, SimEntity.Faction.ENEMIES).is_empty()
	if players_alive and enemies_alive:
		return false
	combat.active = false
	var winner := SimEntity.Faction.PLAYERS if players_alive else SimEntity.Faction.ENEMIES
	state.emit_event(SimEvent.Type.COMBAT_ENDED, Vector3i.ZERO, -1, -1, winner)
	return true


## Whether an entity may take an action costing ap_cost right now.
static func can_act(state: SimState, e: SimEntity, ap_cost: int) -> bool:
	if e == null or not e.is_alive() or not e.takes_turns():
		return false
	if not state.combat.active:
		return true
	return e.faction == state.combat.side and e.ap >= ap_cost


static func spend(state: SimState, e: SimEntity, ap_cost: int) -> void:
	if state.combat.active:
		e.ap -= ap_cost


@warning_ignore("integer_division")
static func move_ap_cost(movement_cost: int) -> int:
	return (movement_cost + MOVE_COST_PER_AP - 1) / MOVE_COST_PER_AP


## Living, turn-taking entities of a faction, in id order.
static func fighters(state: SimState, faction: SimEntity.Faction) -> Array[SimEntity]:
	var result: Array[SimEntity] = []
	for e in state.entities:
		if e.faction == faction and e.is_alive() and e.takes_turns():
			result.append(e)
	return result


static func opponent_of(faction: SimEntity.Faction) -> SimEntity.Faction:
	match faction:
		SimEntity.Faction.PLAYERS:
			return SimEntity.Faction.ENEMIES
		SimEntity.Faction.ENEMIES:
			return SimEntity.Faction.PLAYERS
	return SimEntity.Faction.NONE


static func _begin_side(state: SimState) -> void:
	var combat := state.combat
	for e in fighters(state, combat.side):
		e.ap = mini(e.ap + e.max_ap, AP_CAP)
	state.emit_event(SimEvent.Type.TURN_STARTED, Vector3i.ZERO, -1, -1, combat.side)
