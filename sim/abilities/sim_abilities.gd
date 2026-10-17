class_name SimAbilities
extends RefCounted
## The starter verbs. Each one acts on cells and entity properties, so they
## combine with materials and each other (GDD §5.3).

enum Ability { FIREBOLT, RAIN, TELEPORT, SHOVE, STEAL }

const NAMES := ["Firebolt", "Rain", "Teleport", "Shove", "Steal"]
const AP_COST := [2, 2, 2, 1, 1]
## Reach in cells. 1 means adjacent only (diagonals count).
const RANGE := [7, 7, 7, 1, 1]

const FIREBOLT_DAMAGE := 4
const RAIN_AMOUNT := 40
const RAIN_RADIUS := 1
const TELEPORT_MAX_MASS := 150
const SHOVE_MAX_MASS := 120
const SHOVE_DISTANCE := 2


static func is_adjacent(a: Vector3i, b: Vector3i) -> bool:
	return a != b and absi(a.x - b.x) <= 1 and absi(a.z - b.z) <= 1 and absi(a.y - b.y) <= 1


## Horizontal circular range check (height is ignored).
static func in_range(from: Vector3i, to: Vector3i, range_cells: int) -> bool:
	var dx := to.x - from.x
	var dz := to.z - from.z
	return dx * dx + dz * dz <= range_cells * range_cells


static func can_reach(ability: int, from: Vector3i, to: Vector3i) -> bool:
	var reach: int = RANGE[ability]
	return is_adjacent(from, to) if reach == 1 else in_range(from, to, reach)


static func validate(state: SimState, caster: SimEntity, ability: int, target: Vector3i, destination: Vector3i) -> bool:
	if ability < 0 or ability >= NAMES.size():
		return false
	if not CombatRules.can_act(state, caster, AP_COST[ability]):
		return false
	if not state.grid.in_bounds(target) or not can_reach(ability, caster.cell, target):
		return false
	var victim := state.entity_at(target)
	var other_victim := victim != null and victim.id != caster.id
	match ability:
		Ability.FIREBOLT, Ability.RAIN:
			return not state.grid.is_solid(target)
		Ability.TELEPORT:
			return (other_victim
					and victim.mass <= TELEPORT_MAX_MASS
					and in_range(caster.cell, destination, RANGE[Ability.TELEPORT])
					and EntityOps.is_free(state, destination))
		Ability.SHOVE:
			return other_victim and victim.mass <= SHOVE_MAX_MASS
		Ability.STEAL:
			return other_victim and (victim.weapon != "" or not victim.inventory.is_empty())
	return false


static func execute(state: SimState, caster: SimEntity, ability: int, target: Vector3i, destination: Vector3i) -> void:
	CombatRules.spend(state, caster, AP_COST[ability])
	state.emit_event(SimEvent.Type.CAST, target, caster.id, -1, ability)
	var victim := state.entity_at(target)
	match ability:
		Ability.FIREBOLT:
			if victim != null:
				EntityOps.damage(state, victim, FIREBOLT_DAMAGE, caster.id)
			FireRules.ignite(state, target)
		Ability.RAIN:
			for c in state.grid.disc_cells(target, RAIN_RADIUS):
				state.grid.add_surface(c, SimMaterials.Surface.WATER, RAIN_AMOUNT)
		Ability.TELEPORT:
			var event := state.emit_event(SimEvent.Type.TELEPORTED, destination, victim.id, caster.id)
			event.cells.assign([victim.cell, destination])
			EntityOps.place(state, victim, destination)
		Ability.SHOVE:
			_shove(state, caster, victim)
		Ability.STEAL:
			_steal(state, caster, victim)


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


## Takes the victim's weapon if it has one, otherwise its first item.
static func _steal(state: SimState, caster: SimEntity, victim: SimEntity) -> void:
	var item: String
	if victim.weapon != "":
		item = victim.weapon
		victim.weapon = ""
	else:
		item = victim.inventory.pop_front()
	caster.inventory.append(item)
	var event := state.emit_event(SimEvent.Type.STOLEN, victim.cell, victim.id, caster.id)
	event.text = item
