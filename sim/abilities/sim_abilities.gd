class_name SimAbilities
extends RefCounted
## The verbs. Each one acts on cells and entity properties, so they combine
## with materials and each other (GDD §5.3). Which character knows which verbs
## comes from SimArchetypes.

## New abilities go at the end: saves store cooldowns by this order.
enum Ability { FIREBOLT, RAIN, TELEPORT, SHOVE, STEAL, FROST, OIL_FLASK, MEND, CLEAVE, BLINK, HELP_UP, REVIVE, PICKPOCKET, SHOCKWAVE, LOW_BLOW }

const NAMES := ["Firebolt", "Rain", "Teleport", "Shove", "Steal", "Frost", "Oil Flask", "Mend", "Cleave", "Blink", "Help up", "Revive", "Pickpocket", "Shockwave", "Low Blow"]
const AP_COST := [2, 2, 2, 1, 1, 2, 1, 2, 2, 1, 1, 0, 0, 2, 1]
## Reach in cells. 1 means adjacent only (diagonals count).
const RANGE := [7, 7, 7, 1, 1, 6, 6, 5, 1, 4, 1, 1, 1, 5, 1]
## Turns until an ability can be used again by its user: 1 = once per turn,
## 3 = every third turn. In combat they count down at the start of the user's
## turn; outside combat every CombatRules.REALTIME_TICKS_PER_TURN ticks.
const COOLDOWN := [1, 2, 3, 1, 2, 2, 2, 3, 2, 2, 0, 0, 0, 2, 3]

const FIREBOLT_DAMAGE := 4
## Rain lays its whole puddle at once, like the Oil Flask: puddle-deep water
## on every cell of the disc, so it doesn't creep afterwards.
const RAIN_AMOUNT := 20
const RAIN_RADIUS := 2
const TELEPORT_MAX_MASS := 150
## Highest a Teleport can put its target above the ground below (cells): a
## drop from there hurts (up to 8 damage) but can't kill outright.
const TELEPORT_MAX_DROP := 3
const SHOVE_MAX_MASS := 120
const SHOVE_DISTANCE := 2
const FROST_DAMAGE := 2
const FROST_RADIUS := 1
## The flask splashes its whole puddle at once: puddle-deep oil on every cell
## of the disc, so it doesn't creep afterwards.
const OIL_FLASK_AMOUNT := 24
const OIL_FLASK_RADIUS := 2
const MEND_HEAL := 6
## Revive (outside combat only) brings a fallen ally back with this share of
## its max HP (percent, at least 1 HP).
const REVIVE_HP_PERCENT := 25
## Temperature levels the elements move a target by.
const FIREBOLT_HEAT := 2
const FROST_CHILL := 1
const RAIN_CHILL := 2
## Stagger from being shoved, and extra for slamming into something or being
## shoved off a ledge.
const SHOVE_STAGGER := 1
const IMPACT_STAGGER := 1
## Shockwave: a line from the caster toward the target this long (cells),
## staggering everyone on it (allies too). Walls stop it.
const SHOCKWAVE_LENGTH := 5
const SHOCKWAVE_STAGGER := 2
## Low Blow: a dirty trip on one adjacent character, enough to knock most
## people down by itself.
const LOW_BLOW_STAGGER := 3


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


## Ranged abilities need to see their target; adjacent ones don't, and
## Shockwave runs along the ground until something stops it.
static func needs_line_of_sight(ability: int) -> bool:
	return RANGE[ability] > 1 and ability != Ability.SHOCKWAVE


## The ground cells a line from `from` toward `toward` crosses, SHOCKWAVE_LENGTH
## long (not counting `from`), following the floor up and down a level and
## stopping at walls.
static func line_cells(grid: SimGrid, from: Vector3i, toward: Vector3i, length: int = SHOCKWAVE_LENGTH) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	var dx := toward.x - from.x
	var dz := toward.z - from.z
	var steps := maxi(absi(dx), absi(dz))
	if steps == 0:
		return cells
	var at := from
	for i in range(1, length + 1):
		# Integer steps along the line (rounded), so it is deterministic.
		var x := from.x + _div_round(dx * i, steps)
		var z := from.z + _div_round(dz * i, steps)
		var floor_cell: Variant = grid.floor_near(Vector3i(x, at.y, z), 1)
		if floor_cell == null:
			break
		at = floor_cell
		cells.append(at)
	return cells


static func _div_round(a: int, b: int) -> int:
	return (a * 2 + (b if a >= 0 else -b)) / (b * 2)


## How far something put at `c` would fall before landing (cells).
static func drop_height(state: SimState, c: Vector3i) -> int:
	var levels := 0
	var below := c + Vector3i.DOWN
	while not state.grid.is_solid(below) and state.entity_at(below) == null:
		levels += 1
		below += Vector3i.DOWN
	return levels


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
					and drop_height(state, destination) <= TELEPORT_MAX_DROP
					and SimLos.has_line_of_sight(state.grid, caster.cell, destination))
		Ability.SHOVE:
			return other_victim and victim.mass <= SHOVE_MAX_MASS
		Ability.STEAL:
			return other_victim and (can_take_weapon(victim) or not victim.inventory.is_empty())
		Ability.MEND:
			return victim != null and victim.takes_turns() and victim.hp < victim.max_hp
		Ability.CLEAVE, Ability.LOW_BLOW:
			return other_victim and (ability == Ability.CLEAVE or victim.takes_turns())
		Ability.SHOCKWAVE:
			return target != caster.cell and not line_cells(state.grid, caster.cell, target).is_empty()
		Ability.BLINK:
			return SimPathfinder.is_standable(state, target, caster.id) and victim == null
		Ability.HELP_UP:
			return other_victim and victim.knocked_down and victim.faction == caster.faction
		Ability.PICKPOCKET:
			# Outside combat, someone else's item (not their weapon): another
			# side's, or your co-op partner's character.
			return (not state.combat.active and other_victim and victim.takes_turns()
					and not victim.inventory.is_empty()
					and (victim.faction != caster.faction or victim.owner != caster.owner))
		Ability.REVIVE:
			var corpse: SimEntity = state.corpse_at(target)
			return (not state.combat.active and corpse != null and corpse.faction == caster.faction
					and victim == null)  # nobody standing on the body
	return false


static func execute(state: SimState, caster: SimEntity, ability: int, target: Vector3i, destination: Vector3i) -> void:
	CombatRules.spend(state, caster, AP_COST[ability])
	caster.cooldowns[ability] = COOLDOWN[ability]
	state.emit_event(SimEvent.Type.CAST, target, caster.id, -1, ability)
	var victim := state.entity_at(target)
	match ability:
		Ability.FIREBOLT:
			if victim != null:
				EntityOps.damage(state, victim, FIREBOLT_DAMAGE + caster.spell_power(), caster.id, EntityOps.Element.FIRE)
				EntityOps.change_temperature(state, victim, FIREBOLT_HEAT, caster.id)
			FireRules.ignite(state, target, false)  # the bolt already heated the victim
		Ability.RAIN:
			for c in splash_cells(state.grid, target, RAIN_RADIUS):
				var i := state.grid.index(c)
				if state.grid.fire[i] > 0:
					# Put out at once: the burning surface is washed away and steams.
					state.grid.set_fire(i, 0)
					state.grid.clear_surface(i)
					state.grid.add_gas_at(i, SimMaterials.Gas.STEAM, SimMaterials.STEAM_PER_EXTINGUISH)
					state.emit_event(SimEvent.Type.EXTINGUISHED, c)
				state.grid.add_surface(c, SimMaterials.Surface.WATER, RAIN_AMOUNT)
				var soaked := state.entity_at(c)
				if soaked != null:
					EntityOps.cool_with_water(state, soaked, RAIN_CHILL, caster.id)
		Ability.TELEPORT:
			var event := state.emit_event(SimEvent.Type.TELEPORTED, destination, victim.id, caster.id)
			event.cells.assign([victim.cell, destination])
			EntityOps.relocate(state, victim, destination)
		Ability.SHOVE:
			_shove(state, caster, victim)
		Ability.STEAL:
			_steal(state, caster, victim)
		Ability.FROST:
			_frost(state, caster, target)
		Ability.OIL_FLASK:
			var splash := splash_cells(state.grid, target, OIL_FLASK_RADIUS)
			for c in splash:
				state.grid.add_surface(c, SimMaterials.Surface.OIL, OIL_FLASK_AMOUNT)
			FireRules.catch_from_fire(state, splash)
		Ability.MEND:
			EntityOps.heal(state, victim, MEND_HEAL, caster.id)
		Ability.CLEAVE:
			_cleave(state, caster)
		Ability.SHOCKWAVE:
			var line := line_cells(state.grid, caster.cell, target)
			var wave := state.emit_event(SimEvent.Type.SHOCKWAVE, target, caster.id)
			wave.cells.assign(line)
			for c in line:
				var hit := state.entity_at(c)
				if hit != null and hit != caster:
					EntityOps.add_stagger(state, hit, SHOCKWAVE_STAGGER, caster.id)
		Ability.LOW_BLOW:
			EntityOps.add_stagger(state, victim, LOW_BLOW_STAGGER, caster.id)
		Ability.BLINK:
			var event := state.emit_event(SimEvent.Type.TELEPORTED, target, caster.id, caster.id)
			event.cells.assign([caster.cell, target])
			EntityOps.relocate(state, caster, target)
		Ability.HELP_UP:
			EntityOps.help_up(state, victim, caster.id)
		Ability.REVIVE:
			EntityOps.revive(state, state.corpse_at(target), caster.id)
		Ability.PICKPOCKET:
			_pickpocket(state, caster, victim)


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
	# Every cell it's pushed through acts on it, like walking would.
	var landed := victim.cell
	for c in path:
		victim.cell = c
		EntityOps.enter_cell(state, victim)
		if not victim.is_alive():
			return
	victim.cell = landed
	EntityOps.add_stagger(state, victim, SHOVE_STAGGER, caster.id)
	if hit_wall:
		state.emit_event(SimEvent.Type.COLLIDED, victim.cell, victim.id)
		EntityOps.damage(state, victim, EntityOps.COLLISION_DAMAGE)
		EntityOps.add_stagger(state, victim, IMPACT_STAGGER, caster.id)
	elif hit != null:
		state.emit_event(SimEvent.Type.COLLIDED, victim.cell, victim.id, hit.id)
		EntityOps.damage(state, victim, EntityOps.COLLISION_DAMAGE)
		EntityOps.damage(state, hit, EntityOps.COLLISION_DAMAGE)
		EntityOps.add_stagger(state, victim, IMPACT_STAGGER, caster.id)
	var height := victim.cell.y
	EntityOps.settle(state, victim)
	if victim.cell.y < height:
		EntityOps.add_stagger(state, victim, IMPACT_STAGGER, caster.id)  # shoved off a ledge
		EntityOps.enter_cell(state, victim)  # and lands in whatever is down there


## Lifts the victim's first item. Whoever sees it happen (the victim
## included, if it can see the thief) reacts: neutrals get suspicious, then
## hostile; enemies spot the thief and a fight starts.
static func _pickpocket(state: SimState, caster: SimEntity, victim: SimEntity) -> void:
	var item: String = victim.inventory.pop_front()
	caster.inventory.append(item)
	if victim.faction != caster.faction:
		CrimeRules.mark_stolen(caster, item, victim.pack if victim.pack > 0 else -victim.id)
	var event := state.emit_event(SimEvent.Type.PICKPOCKETED, victim.cell, victim.id, caster.id)
	event.text = item
	CrimeRules.commit(state, caster, victim, CrimeRules.Severity.PETTY)
	if victim.faction == SimEntity.Faction.ENEMIES and SimPerception.can_see(state, victim, caster):
		victim.in_combat = true  # caught in the act: the fight starts
		state.provoked = true


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
			EntityOps.damage(state, occupant, FROST_DAMAGE + caster.spell_power(), caster.id, EntityOps.Element.FROST)
			EntityOps.change_temperature(state, occupant, -FROST_CHILL, caster.id)


## Hits every entity adjacent to the caster, friend or foe.
static func _cleave(state: SimState, caster: SimEntity) -> void:
	var victims: Array[SimEntity] = []
	for e in state.entities:
		if e.is_alive() and e != caster and is_adjacent(caster.cell, e.cell):
			victims.append(e)
	for e in victims:
		state.emit_event(SimEvent.Type.ATTACKED, e.cell, e.id, caster.id)
		EntityOps.damage(state, e, caster.attack_damage(), caster.id)
