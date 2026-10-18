class_name SimAbilities
extends RefCounted
## The verbs. Each one acts on cells and entity properties, so they combine
## with materials and each other (GDD §5.3). Which character knows which verbs
## comes from SimArchetypes.

enum Ability { FIREBOLT, RAIN, TELEPORT, SHOVE, STEAL, FROST, OIL_FLASK, MEND, CLEAVE, BLINK }

const NAMES := ["Firebolt", "Rain", "Teleport", "Shove", "Steal", "Frost", "Oil Flask", "Mend", "Cleave", "Blink"]
const AP_COST := [2, 2, 2, 1, 1, 2, 1, 2, 2, 1]
## Reach in cells. 1 means adjacent only (diagonals count).
const RANGE := [7, 7, 7, 1, 1, 6, 6, 5, 1, 4]
## Turns until an ability can be used again by its user: 1 = once per turn,
## 3 = every third turn. In combat they count down at the start of the user's
## turn; outside combat every CombatRules.REALTIME_TICKS_PER_TURN ticks.
const COOLDOWN := [1, 2, 3, 1, 2, 2, 2, 3, 2, 2]

const FIREBOLT_DAMAGE := 4
const RAIN_AMOUNT := 40
const RAIN_RADIUS := 1
const TELEPORT_MAX_MASS := 150
const SHOVE_MAX_MASS := 120
const SHOVE_DISTANCE := 2
const FROST_DAMAGE := 2
const FROST_RADIUS := 1
## The flask splashes its whole puddle at once: puddle-deep oil on every cell
## of the disc, so it doesn't creep afterwards.
const OIL_FLASK_AMOUNT := 24
const OIL_FLASK_RADIUS := 2
const MEND_HEAL := 6


static func all() -> Array[int]:
	var result: Array[int] = []
	for ability in NAMES.size():
		result.append(ability)
	return result


static func is_adjacent(a: Vector3i, b: Vector3i) -> bool:
	return a != b and absi(a.x - b.x) <= 1 and absi(a.z - b.z) <= 1 and absi(a.y - b.y) <= 1


## Horizontal circular range check (height is ignored).
## Ground cells a splash of `radius` around target covers: the disc's columns,
## each landing on its floor within a level of the target.
static func splash_cells(grid: SimGrid, target: Vector3i, radius: int) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dz * dz > radius * radius:
				continue
			var floor_cell: Variant = grid.floor_near(target + Vector3i(dx, 0, dz), 1)
			if floor_cell != null:
				cells.append(floor_cell)
	return cells


static func in_range(from: Vector3i, to: Vector3i, range_cells: int) -> bool:
	var dx := to.x - from.x
	var dz := to.z - from.z
	return dx * dx + dz * dz <= range_cells * range_cells


static func can_reach(ability: int, from: Vector3i, to: Vector3i) -> bool:
	var reach: int = RANGE[ability]
	return is_adjacent(from, to) if reach == 1 else in_range(from, to, reach)


## Ranged abilities need to see their target; adjacent ones don't.
static func needs_line_of_sight(ability: int) -> bool:
	return RANGE[ability] > 1


## Whether the victim's weapon can be stolen; otherwise Steal takes an item.
static func can_take_weapon(victim: SimEntity) -> bool:
	return victim.weapon != "" and victim.can_be_disarmed


static func validate(state: SimState, caster: SimEntity, ability: int, target: Vector3i, destination: Vector3i) -> bool:
	if ability < 0 or ability >= NAMES.size() or not caster.abilities.has(ability):
		return false
	if not CombatRules.can_act(state, caster, AP_COST[ability]):
		return false
	if caster.cooldown(ability) > 0:
		return false
	if not state.grid.in_bounds(target) or state.grid.is_solid(target):
		return false
	var self_target := ability == Ability.MEND and target == caster.cell
	if not self_target and not can_reach(ability, caster.cell, target):
		return false
	if needs_line_of_sight(ability) and not SimLos.has_line_of_sight(state.grid, caster.cell, target):
		return false
	var victim := state.entity_at(target)
	var other_victim := victim != null and victim.id != caster.id
	match ability:
		Ability.FIREBOLT, Ability.RAIN, Ability.FROST, Ability.OIL_FLASK:
			return true
		Ability.TELEPORT:
			return (other_victim
					and victim.mass <= TELEPORT_MAX_MASS
					and in_range(caster.cell, destination, RANGE[Ability.TELEPORT])
					and EntityOps.is_free(state, destination)
					and SimLos.has_line_of_sight(state.grid, caster.cell, destination))
		Ability.SHOVE:
			return other_victim and victim.mass <= SHOVE_MAX_MASS
		Ability.STEAL:
			return other_victim and (can_take_weapon(victim) or not victim.inventory.is_empty())
		Ability.MEND:
			return victim != null and victim.takes_turns() and victim.hp < victim.max_hp
		Ability.CLEAVE:
			return other_victim
		Ability.BLINK:
			return SimPathfinder.is_standable(state, target, caster.id) and victim == null
	return false


static func execute(state: SimState, caster: SimEntity, ability: int, target: Vector3i, destination: Vector3i) -> void:
	CombatRules.spend(state, caster, AP_COST[ability])
	caster.cooldowns[ability] = COOLDOWN[ability]
	state.emit_event(SimEvent.Type.CAST, target, caster.id, -1, ability)
	var victim := state.entity_at(target)
	match ability:
		Ability.FIREBOLT:
			if victim != null:
				EntityOps.damage(state, victim, FIREBOLT_DAMAGE, caster.id, EntityOps.Element.FIRE)
			FireRules.ignite(state, target)
		Ability.RAIN:
			for c in state.grid.disc_cells(target, RAIN_RADIUS):
				state.grid.add_surface(c, SimMaterials.Surface.WATER, RAIN_AMOUNT)
				var soaked := state.entity_at(c)
				if soaked != null:
					EntityOps.douse(state, soaked)
		Ability.TELEPORT:
			var event := state.emit_event(SimEvent.Type.TELEPORTED, destination, victim.id, caster.id)
			event.cells.assign([victim.cell, destination])
			EntityOps.place(state, victim, destination)
		Ability.SHOVE:
			_shove(state, caster, victim)
		Ability.STEAL:
			_steal(state, caster, victim)
		Ability.FROST:
			_frost(state, caster, target)
		Ability.OIL_FLASK:
			for c in splash_cells(state.grid, target, OIL_FLASK_RADIUS):
				state.grid.add_surface(c, SimMaterials.Surface.OIL, OIL_FLASK_AMOUNT)
		Ability.MEND:
			EntityOps.heal(state, victim, MEND_HEAL, caster.id)
		Ability.CLEAVE:
			_cleave(state, caster)
		Ability.BLINK:
			var event := state.emit_event(SimEvent.Type.TELEPORTED, target, caster.id, caster.id)
			event.cells.assign([caster.cell, target])
			EntityOps.place(state, caster, target)


## Pushes the victim up to SHOVE_DISTANCE cells away from the caster. Walls and
## other entities stop it (and hurt); ledges drop it.
static func _shove(state: SimState, caster: SimEntity, victim: SimEntity) -> void:
	var dir := Vector3i(signi(victim.cell.x - caster.cell.x), 0, signi(victim.cell.z - caster.cell.z))
	if dir == Vector3i.ZERO:
		return
	var path: Array[Vector3i] = []
	var hit_wall := false
	var hit: SimEntity = null
	for _i in SHOVE_DISTANCE:
		var next := victim.cell + dir
		if state.grid.is_solid(next):
			hit_wall = true
			break
		hit = state.entity_at(next)
		if hit != null:
			break
		victim.cell = next
		path.append(next)
		if not state.grid.is_supported(next) and state.entity_at(next + Vector3i.DOWN) == null:
			break  # over the edge

	var shoved := state.emit_event(SimEvent.Type.SHOVED, victim.cell, victim.id, caster.id)
	shoved.cells = path
	if hit_wall:
		state.emit_event(SimEvent.Type.COLLIDED, victim.cell, victim.id)
		EntityOps.damage(state, victim, EntityOps.COLLISION_DAMAGE)
	elif hit != null:
		state.emit_event(SimEvent.Type.COLLIDED, victim.cell, victim.id, hit.id)
		EntityOps.damage(state, victim, EntityOps.COLLISION_DAMAGE)
		EntityOps.damage(state, hit, EntityOps.COLLISION_DAMAGE)
	EntityOps.settle(state, victim)


## Takes the victim's weapon if it can be disarmed, otherwise its first item.
static func _steal(state: SimState, caster: SimEntity, victim: SimEntity) -> void:
	var item: String
	if can_take_weapon(victim):
		item = victim.weapon
		victim.weapon = ""
	else:
		item = victim.inventory.pop_front()
	caster.inventory.append(item)
	var event := state.emit_event(SimEvent.Type.STOLEN, victim.cell, victim.id, caster.id)
	event.text = item


## Chills an area: puts out fire, freezes water into ice right away, and nips
## anyone standing there.
static func _frost(state: SimState, caster: SimEntity, target: Vector3i) -> void:
	var grid := state.grid
	grid.edit_heat()
	for c in grid.disc_cells(target, FROST_RADIUS):
		var i := grid.index(c)
		grid.set_temperature(i, mini(grid.temperature[i], SimMaterials.CHILL_TEMPERATURE))
		if grid.fire[i] > 0:
			grid.set_fire(i, 0)
			state.emit_event(SimEvent.Type.EXTINGUISHED, c)
		if grid.surface_type[i] == SimMaterials.Surface.WATER:
			grid.edit_surfaces()
			grid.surface_type[i] = SimMaterials.Surface.ICE
			state.emit_event(SimEvent.Type.FROZE, c)
		var occupant := state.entity_at(c)
		if occupant != null:
			EntityOps.damage(state, occupant, FROST_DAMAGE, caster.id, EntityOps.Element.FROST)


## Hits every entity adjacent to the caster, friend or foe.
static func _cleave(state: SimState, caster: SimEntity) -> void:
	var victims: Array[SimEntity] = []
	for e in state.entities:
		if e.is_alive() and e != caster and is_adjacent(caster.cell, e.cell):
			victims.append(e)
	for e in victims:
		state.emit_event(SimEvent.Type.ATTACKED, e.cell, e.id, caster.id)
		EntityOps.damage(state, e, caster.attack_damage(), caster.id)
