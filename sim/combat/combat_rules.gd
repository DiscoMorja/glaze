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
## Outside combat, this many ticks count as one turn for cooldowns (2 s at 4 Hz).
const REALTIME_TICKS_PER_TURN := 8


## Starts a fight. With everyone, every fighter in the level takes part (the
## arena, StartCombatCommand). Otherwise the fight is local: entities already
## marked in_combat (provoked or spotting) and their packs, plus the whole
## party. Returns false (and starts nothing) if no opponent of the party joins.
static func start(state: SimState, everyone: bool = true) -> bool:
	var combat := state.combat
	state.provoked = false
	var joined: Array[SimEntity] = []
	for e in state.entities:
		var side := e.faction == SimEntity.Faction.PLAYERS or e.faction == SimEntity.Faction.ENEMIES
		if side and e.is_alive() and e.takes_turns() and (everyone or e.in_combat or e.faction == SimEntity.Faction.PLAYERS):
			joined.append(e)
	for e in state.entities:
		e.in_combat = false
	for e in joined:
		_join_pack(state, e)
	if not _has_fighters(state, SimEntity.Faction.ENEMIES, true):
		for e in state.entities:
			e.in_combat = false
		return false
	for e in state.entities:
		e.travel.clear()
		e.sneaking = false  # no sneaking in a fight
	combat.active = true
	combat.side = SimEntity.Faction.PLAYERS
	combat.round_number = 1
	state.emit_event(SimEvent.Type.COMBAT_STARTED)
	_begin_side(state)
	return true


## Pulls an entity and its pack into the running fight (they act from their
## side's next turn).
static func join(state: SimState, e: SimEntity) -> void:
	if state.combat.active:
		_join_pack(state, e)


static func _join_pack(state: SimState, e: SimEntity) -> void:
	e.in_combat = true
	if e.pack <= 0:
		return
	for other in state.entities:
		if other.pack == e.pack and other.faction == e.faction and other.is_alive() and other.takes_turns():
			other.in_combat = true


static func end_side_turn(state: SimState) -> void:
	for e in fighters(state, state.combat.side):
		EntityOps.turn_end(state, e)
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


## Outside combat: starts a local fight when someone hurt a fighter of the
## other side (state.provoked), or when watchful entities (sight > 0) see an
## opponent within their sight range. Those entities and their packs fight;
## the rest of the world waits. Returns true if combat started.
static func check_start(state: SimState) -> bool:
	if state.combat.active:
		return false
	if fighters(state, SimEntity.Faction.PLAYERS).is_empty() or fighters(state, SimEntity.Faction.ENEMIES).is_empty():
		state.provoked = false
		for e in state.entities:
			e.in_combat = false
		return false
	var spotted := _mark_spotters(state, false)
	if not spotted and not state.provoked:
		return false
	return start(state, false)


## Marks every watcher that sees an opponent (one taking part in the fight, if
## a fight is on) as in_combat; the first sighting emits SPOTTED. Returns
## whether anyone was spotted.
static func _mark_spotters(state: SimState, fighting: bool) -> bool:
	var spotted := false
	var targets := {}
	for faction: SimEntity.Faction in [SimEntity.Faction.PLAYERS, SimEntity.Faction.ENEMIES]:
		var list: Array[SimEntity] = []
		for e in state.entities:
			if e.faction == faction and e.is_alive() and e.takes_turns() and (e.in_combat or not fighting):
				list.append(e)
		targets[faction] = list
	for watcher in state.entities:
		if watcher.sight <= 0 or watcher.in_combat or not watcher.is_alive() or not watcher.takes_turns():
			continue
		var opponent := opponent_of(watcher.faction)
		if not targets.has(opponent):
			continue
		for other: SimEntity in targets[opponent]:
			if SimPerception.can_see(state, watcher, other):
				if not spotted:
					state.emit_event(SimEvent.Type.SPOTTED, other.cell, other.id, watcher.id)
				spotted = true
				watcher.in_combat = true
				break
	return spotted


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
	for e in state.entities:
		e.in_combat = false
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


## Movement cost an entity can afford with its AP (Dexterity adds a little
## per AP; halved while slowed).
@warning_ignore("integer_division")
static func move_budget(e: SimEntity) -> int:
	var budget := e.ap * StatRules.move_per_ap(e)
	return budget / 2 if e.is_slowed() else budget


## AP a walk of `movement_cost` takes (for `e`: Dexterity makes AP go further).
@warning_ignore("integer_division")
static func move_ap_cost(movement_cost: int, e: SimEntity = null) -> int:
	var per_ap := StatRules.move_per_ap(e) if e != null else MOVE_COST_PER_AP
	return (movement_cost + per_ap - 1) / per_ap


## Living, turn-taking entities of a faction, in id order. During combat only
## those taking part in the fight.
static func fighters(state: SimState, faction: SimEntity.Faction) -> Array[SimEntity]:
	var result: Array[SimEntity] = []
	var fighting := state.combat.active
	for e in state.entities:
		if e.faction == faction and e.is_alive() and e.takes_turns() and (e.in_combat or not fighting):
			result.append(e)
	return result


static func _has_fighters(state: SimState, faction: SimEntity.Faction, joined_only: bool) -> bool:
	for e in state.entities:
		if e.faction == faction and e.is_alive() and e.takes_turns() and (e.in_combat or not joined_only):
			return true
	return false


static func opponent_of(faction: SimEntity.Faction) -> SimEntity.Faction:
	match faction:
		SimEntity.Faction.PLAYERS:
			return SimEntity.Faction.ENEMIES
		SimEntity.Faction.ENEMIES:
			return SimEntity.Faction.PLAYERS
	return SimEntity.Faction.NONE


static func _begin_side(state: SimState) -> void:
	var combat := state.combat
	state.emit_event(SimEvent.Type.TURN_STARTED, Vector3i.ZERO, -1, -1, combat.side)
	# Packs that see the fight join it (and act from their side's next turn).
	if _mark_spotters(state, true):
		for e in state.entities:
			if e.in_combat:
				_join_pack(state, e)
	for e in fighters(state, combat.side):
		e.ap = mini(e.ap + e.max_ap, AP_CAP)
		EntityOps.turn_start(state, e)
