class_name UtilityAi
extends RefCounted
## Enemy AI that tries candidate actions on copies of the sim and picks the one
## whose outcome scores best for its side (GDD §5.5). It "sees" hazards and
## chain reactions because it runs the same rules as everyone else: each
## candidate is applied to a copy and compared against doing nothing. Casts
## change the world, so for them both sides of the comparison are advanced to
## the end of the turn first; moves and attacks are compared right away, with a
## hazard check on where the unit ends up.
##
## Returns one command at a time, so the host can replicate and animate each
## action. Ends the turn when nothing scores at least MIN_SCORE.

const W_DAMAGE := 10  ## per HP taken from an opponent
const W_KILL := 40
const W_FRIENDLY := 14  ## per HP lost on our own side, self included
const W_DISARM := 15  ## per point of attack damage taken off an opponent (lasts all fight)
const W_LOOT := 35  ## per item taken from an opponent (a skirmisher's whole point)
const W_HAZARD := 30  ## ending up standing in fire
const W_DISABLE := 35  ## an opponent knocked down or frozen (or an ally got back up)
const W_DISTANCE := 1  ## per cell away from where the unit wants to be
## Cells from the nearest opponent that ranged units try to keep.
const PREFERRED_RANGE := 5
## Melee units guard their casters: they stay within this many cells of the
## nearest ranged ally unless they end next to an opponent (an attack this
## turn), so players can't lure them away one by one by waiting.
const GUARD_RANGE := 4
const W_GUARD := 3  ## per cell beyond GUARD_RANGE
const MIN_SCORE := 1

const MAX_MOVE_CANDIDATES := 12
## Walk field reach (movement cost units: 10 per straight cell).
const WALK_FIELD_SLACK := 200
const WALK_FIELD_MAX := 1200
## Melee move priority for cells the walk field doesn't reach.
const UNREACHABLE_PENALTY := 100000
const MAX_FIRE_TARGETS := 10
const MAX_DROP_SPOTS := 4


static func next_command(state: SimState) -> SimCommand:
	var side := state.combat.side
	var baseline := state.duplicate_state()
	baseline.step_ticks(CombatRules.TICKS_PER_SIDE_TURN)
	var best: SimCommand = null
	var best_score := MIN_SCORE - 1
	var walk := walk_field(state, CombatRules.opponent_of(side))
	for e in CombatRules.fighters(state, side):
		if e.ap <= 0:
			continue
		for candidate in candidates(state, e, walk):
			if not candidate.validate(state):
				continue
			var value := score(state, baseline, e, candidate, walk)
			if value > best_score:
				best = candidate
				best_score = value
	if best == null:
		return EndTurnCommand.new(side)
	return best


## Walking cost from the fighters of `faction` to the cells around them (see
## SimPathfinder.distance_field), so units judge "close" by the way there, not
## through cliffs. Reaches a little past the furthest unit of the other side.
static func walk_field(state: SimState, faction: SimEntity.Faction) -> Dictionary:
	var sources: Array[Vector3i] = []
	for o in CombatRules.fighters(state, faction):
		sources.append(o.cell)
	var furthest := 0
	for e in CombatRules.fighters(state, CombatRules.opponent_of(faction)):
		for s in sources:
			furthest = maxi(furthest, SimPathfinder.distance(e.cell, s))
	var reach := mini(furthest * 2 + WALK_FIELD_SLACK, WALK_FIELD_MAX)
	return SimPathfinder.distance_field(state, sources, reach)


## Walking distance (cells) from c to the nearest opponent, from a walk field,
## or -1 if the field doesn't reach it. A unit's own cell is occupied in the
## field, so it is read through its neighbours.
@warning_ignore("integer_division")
static func walk_distance(walk: Dictionary, c: Vector3i) -> int:
	if walk.has(c):
		return walk[c] / SimPathfinder.COST_STRAIGHT
	var best := -1
	for d: Vector3i in SimPathfinder.DIRS_8:
		for dy: int in [0, 1, -1]:
			var n := c + d + Vector3i(0, dy, 0)
			if walk.has(n):
				var cost: int = walk[n] + SimPathfinder.step_cost(c, n)
				if best < 0 or cost < best:
					best = cost
	return best / SimPathfinder.COST_STRAIGHT if best >= 0 else -1


## How much better the world looks for e's side after `command` than after
## doing nothing. `baseline` is the current state advanced to the turn's end.
## `command` must already be valid for `state`. `walk` is the walk field to
## e's opponents (walk_field()); without it distances are straight lines.
static func score(state: SimState, baseline: SimState, e: SimEntity, command: SimCommand, walk: Dictionary = {}) -> int:
	var after := state.duplicate_state()
	command.execute(after)  # validated by the caller; skips a second path search
	CombatRules.check_end(after)
	if command is MoveCommand or (command is CastCommand and (command as CastCommand).ability == SimAbilities.Ability.BLINK):
		_follow_up(after, after.get_entity(e.id))
	var reference := state
	if command is CastCommand:
		after.step_ticks(CombatRules.TICKS_PER_SIDE_TURN)
		reference = baseline
	return _compare(reference, after, e, walk)


static func _compare(reference: SimState, after: SimState, e: SimEntity, walk: Dictionary = {}) -> int:
	var baseline := reference

	var opponent := CombatRules.opponent_of(e.faction)
	var value := 0
	for before in baseline.entities:
		var now := after.get_entity(before.id)
		var lost := before.hp - now.hp
		if before.faction == opponent:
			value += lost * W_DAMAGE
			value += (before.attack_damage() - now.attack_damage()) * W_DISARM
			value += (before.inventory.size() - now.inventory.size()) * W_LOOT
			if before.is_alive() and not now.is_alive():
				value += W_KILL
			if _disabled(now) and not _disabled(before):
				value += W_DISABLE
		elif before.faction == e.faction:
			value -= lost * W_FRIENDLY
			if before.is_alive() and not now.is_alive():
				value -= W_KILL
			if _disabled(before) != _disabled(now):
				value += W_DISABLE if _disabled(before) else -W_DISABLE
	value += _position_value(after, after.get_entity(e.id), walk) - _position_value(baseline, baseline.get_entity(e.id), walk)
	return value


## Out of the fight for now: knocked down or frozen.
static func _disabled(e: SimEntity) -> bool:
	return e.is_alive() and (e.knocked_down or e.is_frozen())


## Whether standing at c is asking to get burned: on fire, or on fuel with fire nearby.
@warning_ignore("integer_division")
static func _hazard_at(state: SimState, c: Vector3i) -> int:
	var grid := state.grid
	var i := grid.index(c)
	if grid.fire[i] > 0:
		return W_HAZARD
	if not SimMaterials.is_flammable(grid.surface_type[i]):
		return 0
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var n := c + Vector3i(dx, 0, dz)
			if grid.in_bounds(n) and grid.fire[grid.index(n)] > 0:
				return W_HAZARD / 2
	return 0


## The actions worth trying for one unit. `walk`: see score().
static func candidates(state: SimState, e: SimEntity, walk: Dictionary = {}) -> Array[SimCommand]:
	var result: Array[SimCommand] = []
	var opponents := CombatRules.fighters(state, CombatRules.opponent_of(e.faction))
	for o in opponents:
		if SimAbilities.is_adjacent(e.cell, o.cell):
			result.append(AttackCommand.new(e.id, o.id))
	var allies := CombatRules.fighters(state, e.faction)
	for ability in e.abilities:
		match ability:
			SimAbilities.Ability.FIREBOLT:
				for c in _fire_targets(state, e, opponents):
					result.append(CastCommand.new(e.id, ability, c))
			SimAbilities.Ability.SHOCKWAVE:
				for o in opponents:
					result.append(CastCommand.new(e.id, ability, o.cell))
			SimAbilities.Ability.SHOVE, SimAbilities.Ability.STEAL, SimAbilities.Ability.CLEAVE, SimAbilities.Ability.LOW_BLOW:
				for o in opponents:
					if SimAbilities.is_adjacent(e.cell, o.cell):
						result.append(CastCommand.new(e.id, ability, o.cell))
			SimAbilities.Ability.TELEPORT:
				for o in opponents:
					for spot in _drop_spots(state, e, o):
						result.append(CastCommand.new(e.id, ability, o.cell, spot))
			SimAbilities.Ability.FROST:
				for o in opponents:
					result.append(CastCommand.new(e.id, ability, o.cell))
			SimAbilities.Ability.MEND:
				for a in allies:
					if a.hp < a.max_hp:
						result.append(CastCommand.new(e.id, ability, a.cell))
			SimAbilities.Ability.RAIN:
				for a in allies:
					if state.grid.fire[state.grid.index(a.cell)] > 0:
						result.append(CastCommand.new(e.id, ability, a.cell))
			SimAbilities.Ability.BLINK:
				for c in _blink_spots(state, e, opponents):
					result.append(CastCommand.new(e.id, ability, c))
			SimAbilities.Ability.HELP_UP:
				for a in allies:
					if a.knocked_down and SimAbilities.is_adjacent(e.cell, a.cell):
						result.append(CastCommand.new(e.id, ability, a.cell))
	for c in _move_targets(state, e, opponents, walk):
		result.append(MoveCommand.new(e.id, c))
	return result


## Ranged units hang back at PREFERRED_RANGE instead of closing to melee.
static func is_ranged(e: SimEntity) -> bool:
	for ability in [SimAbilities.Ability.FIREBOLT, SimAbilities.Ability.TELEPORT, SimAbilities.Ability.MEND]:
		if e.abilities.has(ability):
			return true
	return false


## Blink destinations: free cells next to opponents, within blink range.
static func _blink_spots(state: SimState, e: SimEntity, opponents: Array[SimEntity]) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var reach: int = SimAbilities.RANGE[SimAbilities.Ability.BLINK]
	for o in opponents:
		for d: Vector3i in SimPathfinder.DIRS_8:
			var c := o.cell + d
			if result.size() >= MAX_DROP_SPOTS:
				return result
			if SimAbilities.in_range(e.cell, c, reach) and SimPathfinder.is_standable(state, c, e.id) and not result.has(c):
				result.append(c)
	return result


## After a move, spend leftover AP the obvious way (hit the weakest adjacent
## opponent, or firebolt the nearest visible one), so a move is valued by the
## actions it sets up.
static func _follow_up(state: SimState, e: SimEntity) -> void:
	while e.is_alive() and e.ap >= CombatRules.ATTACK_AP:
		var target: SimEntity = null
		for o in CombatRules.fighters(state, CombatRules.opponent_of(e.faction)):
			if SimAbilities.is_adjacent(e.cell, o.cell) and (target == null or o.hp < target.hp):
				target = o
		if target != null:
			if not state.apply_command(AttackCommand.new(e.id, target.id)):
				return
			continue
		if not e.abilities.has(SimAbilities.Ability.FIREBOLT):
			return
		var bolted := false
		for o in CombatRules.fighters(state, CombatRules.opponent_of(e.faction)):
			if state.apply_command(CastCommand.new(e.id, SimAbilities.Ability.FIREBOLT, o.cell)):
				bolted = true
				break
		if not bolted:
			return


## Higher is better: out of fire, and at the distance the unit likes to fight
## from. Melee units measure it by walking (the walk field) where they can, so
## a cliff edge above an opponent isn't "close".
static func _position_value(state: SimState, e: SimEntity, walk: Dictionary = {}) -> int:
	if not e.is_alive():
		return 0
	var value := -_hazard_at(state, e.cell)
	var distance := _nearest_opponent_distance(state, e)
	if not is_ranged(e) and not walk.is_empty():
		var walked := walk_distance(walk, e.cell)
		if walked >= 0:
			distance = walked
	if not is_ranged(e) and distance != 1:
		var guard := _nearest_caster_distance(state, e)
		if guard > GUARD_RANGE:
			value -= (guard - GUARD_RANGE) * W_GUARD
	if distance >= 0:
		var wanted := PREFERRED_RANGE if is_ranged(e) else 1
		value -= absi(distance - wanted) * W_DISTANCE
	return value


## Distance in cells to the nearest living ranged ally, or -1 if there is none.
@warning_ignore("integer_division")
static func _nearest_caster_distance(state: SimState, e: SimEntity) -> int:
	var best := -1
	for a in CombatRules.fighters(state, e.faction):
		if a.id == e.id or not is_ranged(a):
			continue
		var d := SimPathfinder.distance(e.cell, a.cell) / SimPathfinder.COST_STRAIGHT
		if best < 0 or d < best:
			best = d
	return best


## Distance in cells to the nearest living opponent, or -1 if there is none.
@warning_ignore("integer_division")
static func _nearest_opponent_distance(state: SimState, e: SimEntity) -> int:
	var best := -1
	for o in CombatRules.fighters(state, CombatRules.opponent_of(e.faction)):
		var d := SimPathfinder.distance(e.cell, o.cell) / SimPathfinder.COST_STRAIGHT
		if best < 0 or d < best:
			best = d
	return best


## Firebolt targets: opponents themselves, fuel next to them (oil, oil barrels)
## and anything already in range near them. Closest to an opponent first.
static func _fire_targets(state: SimState, e: SimEntity, opponents: Array[SimEntity]) -> Array[Vector3i]:
	var grid := state.grid
	var ability := SimAbilities.Ability.FIREBOLT
	var seen := {}
	var result: Array[Vector3i] = []
	for o in opponents:
		var spots: Array[Vector3i] = [o.cell]
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				for dy in range(-1, 2):
					var c := o.cell + Vector3i(dx, dy, dz)
					if not grid.in_bounds(c) or grid.is_solid(c):
						continue
					var fuel: bool = SimMaterials.is_flammable(grid.surface_type[grid.index(c)])
					var occupant := state.entity_at(c)
					var barrel: bool = occupant != null and not occupant.takes_turns() and SimMaterials.is_flammable(occupant.contents_surface)
					if fuel or barrel:
						spots.append(c)
		for c in spots:
			if seen.has(c) or not SimAbilities.can_reach(ability, e.cell, c) or not SimLos.has_line_of_sight(grid, e.cell, c):
				continue
			seen[c] = true
			result.append(c)
			if result.size() >= MAX_FIRE_TARGETS:
				return result
	return result


## Teleport destinations that hurt: burning cells, and high in the air above
## the target (it falls back down).
static func _drop_spots(state: SimState, e: SimEntity, target: SimEntity) -> Array[Vector3i]:
	var grid := state.grid
	var result: Array[Vector3i] = []
	var top := Vector3i(target.cell.x, target.cell.y + SimAbilities.TELEPORT_MAX_DROP, target.cell.z)
	if grid.in_bounds(top) and EntityOps.is_free(state, top):
		result.append(top)
	var reach: int = SimAbilities.RANGE[SimAbilities.Ability.TELEPORT]
	for i in grid.burning_cells():
		if result.size() >= MAX_DROP_SPOTS:
			break
		var c := grid.coord(i)
		if SimAbilities.in_range(e.cell, c, reach) and EntityOps.is_free(state, c):
			result.append(c)
	return result


## Move destinations: cells next to opponents, a step along the path to the
## nearest one, a safe cell if standing in fire, and (for ranged units) cells
## at a good distance with sight of an opponent.
static func _move_targets(state: SimState, e: SimEntity, opponents: Array[SimEntity], walk: Dictionary = {}) -> Array[Vector3i]:
	var budget := CombatRules.move_budget(e) if state.combat.active else 1 << 20
	var reach := SimPathfinder.reachable(state, e.cell, budget, e.id)
	var grid := state.grid
	var scored := []  # [priority, cell]
	for c: Vector3i in reach:
		var nearest := 1 << 30
		var sees := false
		for o in opponents:
			nearest = mini(nearest, SimPathfinder.distance(c, o.cell))
			if not sees and SimLos.has_line_of_sight(grid, c, o.cell):
				sees = true
		var in_fire := grid.fire[grid.index(c)] > 0
		var priority: int
		if is_ranged(e):
			if not sees:
				continue
			priority = absi(nearest - PREFERRED_RANGE * SimPathfinder.COST_STRAIGHT)
		elif walk.has(c):
			priority = walk[c]  # by the way there, not as the crow flies
		elif not walk.is_empty():
			priority = nearest + UNREACHABLE_PENALTY
		else:
			priority = nearest
		if in_fire:
			priority += 1000
		scored.append([priority, reach[c], c])
	scored.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return a[0] < b[0]
		if a[1] != b[1]:
			return a[1] < b[1]
		return grid.index(a[2]) < grid.index(b[2]))

	var result: Array[Vector3i] = []
	for entry in scored:
		if result.size() >= MAX_MOVE_CANDIDATES:
			break
		result.append(entry[2])

	# Toward the nearest opponent when nobody is reachable this turn.
	var target: SimEntity = null
	var best_distance := 1 << 30
	for o in opponents:
		var d := SimPathfinder.distance(e.cell, o.cell)
		if d < best_distance:
			target = o
			best_distance = d
	if target != null:
		var path := SimPathfinder.find_path(state, e.cell, target.cell, e.id, true)
		var step := SimPathfinder.affordable_prefix(e.cell, path, budget)
		if not step.is_empty() and not result.has(step.back()):
			result.append(step.back())
	return result
