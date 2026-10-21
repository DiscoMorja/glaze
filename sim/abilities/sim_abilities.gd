class_name SimAbilities
extends RefCounted
## The verbs. Each one acts on cells and entity properties, so they combine
## with materials and each other (GDD §5.3). Which character knows which verbs
## comes from SimArchetypes.

## New abilities go at the end: saves store cooldowns by this order.
enum Ability {
	FIREBOLT, RAIN, TELEPORT, SHOVE, STEAL, FROST, OIL_FLASK, MEND, CLEAVE, BLINK, HELP_UP, REVIVE, PICKPOCKET, SHOCKWAVE, LOW_BLOW,
	KINDLE, OVERGROWTH, DRAIN, BLIGHT, DISTRACT, BACKSTAB, LOADED_SHOT, PINNING_SHOT,
	COMBUST, GLACIER, WELLSPRING, SHROUD, DREAD, BRACE, SMOKE_BOMB, SNARE,
}

const NAMES := ["Firebolt", "Rain", "Teleport", "Shove", "Steal", "Frost", "Oil Flask", "Mend", "Cleave", "Blink", "Help up", "Revive", "Pickpocket", "Shockwave", "Low Blow",
		"Kindle", "Overgrowth", "Drain", "Blight", "Distract", "Backstab", "Loaded Shot", "Pinning Shot",
		"Combust", "Glacier", "Wellspring", "Shroud", "Dread", "Brace", "Smoke Bomb", "Snare"]
const AP_COST := [2, 2, 2, 1, 1, 2, 1, 2, 2, 1, 1, 0, 0, 2, 1, 1, 2, 2, 2, 1, 2, 2, 2,
		2, 2, 2, 2, 2, 1, 1, 1]
## Reach in cells. 1 means adjacent only (diagonals count). Shots reach as far
## as the bow or sling in hand (AttackCommand.reach()), at most this.
const RANGE := [7, 7, 7, 1, 1, 6, 6, 5, 1, 4, 1, 1, 1, 5, 1, 6, 6, 5, 6, 6, 1, 7, 7,
		6, 6, 6, 6, 5, 1, 5, 1]
## Turns until an ability can be used again by its user: 1 = once per turn,
## 3 = every third turn. In combat they count down at the start of the user's
## turn; outside combat every CombatRules.REALTIME_TICKS_PER_TURN ticks.
const COOLDOWN := [1, 2, 3, 1, 2, 2, 2, 3, 2, 2, 0, 0, 0, 2, 3, 3, 2, 2, 3, 2, 2, 1, 2,
		3, 3, 3, 3, 3, 2, 3, 2]
## The school each ability belongs to (StatRules.School, -1 = everyone's) and
## the rank in it needed to use it. Ranks above that add potency.
## (StatRules.School order: FIRE 0, ICE 1, LIFE 2, DEATH 3, PSYCHIC 4,
## WARRIOR 5, ROGUE 6, RANGER 7.)
const SCHOOL := [0, 1, 4, 5, 6, 1, -1, 2, 5, 4, -1, -1, -1, 5, 6, 0, 2, 3, 3, 4, 6, 7, 7,
		0, 1, 2, 3, 4, 5, 6, 7]
const RANK := [1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0, 0, 0, 2, 1, 1, 1, 1, 2, 1, 2, 1, 1,
		2, 2, 2, 2, 2, 2, 1, 2]
## Abilities that come from an item instead of being known: carrying an item
## whose "casts" names the ability grants it, and each use spends one.
const FROM_ITEM := [Ability.OIL_FLASK]

const FIREBOLT_DAMAGE := 4
## Rain lays its whole puddle at once, like the Oil Flask: puddle-deep water
## on every cell of the disc, so it doesn't creep afterwards.
const RAIN_AMOUNT := 20
const RAIN_RADIUS := 2
## Highest a Teleport can put its target above the ground below (cells): a
## drop from there hurts (up to 8 damage) but can't kill outright.
const TELEPORT_MAX_DROP := 3
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
## Kindle: temperature levels it adds. A Hot character gains an extra AP at
## the start of its turn (CombatRules); a barrel of oil catches fire, a
## barrel of water steams.
const KINDLE_HEAT := 1
const KINDLE_STEAM := 40
## Overgrowth: a disc of vines (not a liquid: it stays put).
const OVERGROWTH_RADIUS := 2
const VINES_AMOUNT := 12
## Drain: death damage; the caster heals what it dealt.
const DRAIN_DAMAGE := 3
## Blight: water in this radius turns to poison, vines rot away; a corpse in
## the target cell bursts into poison gas over this radius.
const BLIGHT_RADIUS := 1
const BLIGHT_GAS := 30
## Distract: turns the target keeps its back to the caster (Mind shortens it,
## never below 1).
const DISTRACT_TURNS := 2
## Shots need a weapon with "ranged". Loaded Shot fires the first carried
## item with "ammo" (used up): "ignite" lights the target cell, "splash"
## ("water"/"oil") splashes that liquid over SHOT_SPLASH_RADIUS, "chill" cools
## the target a level.
const SHOT_SPLASH_RADIUS := 1
const SHOT_SPLASH_AMOUNT := 20
const SHOTS := [Ability.LOADED_SHOT, Ability.PINNING_SHOT]
## Combust: everyone Hot or Burning within this radius of the target bursts
## into flame: fire damage, and their cell catches fire.
const COMBUST_RADIUS := 3
const COMBUST_DAMAGE := 3
## Glacier: water within this radius freezes into ice at once, and everyone
## standing in it freezes solid.
const GLACIER_RADIUS := 2
## Wellspring: everyone standing in water within this radius heals.
const WELLSPRING_RADIUS := 3
const WELLSPRING_HEAL := 4
## Shroud: a heavy, lingering cloud of darkness (it blocks sight, SimLos).
const SHROUD_RADIUS := 2
const SHROUD_GAS := 60
## Dread: the target drops its off-hand item and, on its next turn, only runs
## from the caster (EntityOps.flee()). Counted like Pinned: the turn it is
## cast in and the next. Outside combat it runs at once.
const DREAD_TURNS := 2
const FLEE_CELLS := 4
## Brace (needs a shield in the off hand): extra armour and no shoving until
## the caster's next turn.
const BRACE_ARMOR := 2
## Smoke Bomb: thick smoke that hangs low (and blocks sight) until it thins.
const SMOKE_BOMB_RADIUS := 1
const SMOKE_BOMB_GAS := 80
## Snare: a hidden trap in an adjacent cell; the first opponent to step in
## takes this much stagger (EntityOps.enter_cell()).
const SNARE_STAGGER := 3


## Potency: the caster's rank in the ability's school above the rank it needs.
static func potency(caster: SimEntity, ability: int) -> int:
	var school: int = SCHOOL[ability]
	return maxi(0, StatRules.rank(caster, school) - RANK[ability]) if school >= 0 else 0


## Whether the caster's school rank is high enough for the ability.
static func has_rank(caster: SimEntity, ability: int) -> bool:
	return SCHOOL[ability] < 0 or StatRules.rank(caster, SCHOOL[ability]) >= RANK[ability]


## Index of the first carried item that grants `ability` (-1 = none).
static func granting_item(caster: SimEntity, ability: int) -> int:
	for i in caster.inventory.size():
		if SimItems.info(caster.inventory[i]).get("casts", "") == NAMES[ability]:
			return i
	return -1


## What the entity can try to use: the abilities it knows (FROM_ITEM ones only
## with the item), then those its items grant. Rank is checked by validate().
static func available(e: SimEntity) -> Array[int]:
	var result: Array[int] = []
	for ability in e.abilities:
		if not FROM_ITEM.has(ability) or granting_item(e, ability) >= 0:
			result.append(ability)
	for ability: int in FROM_ITEM:
		if not result.has(ability) and granting_item(e, ability) >= 0:
			result.append(ability)
	return result


## Why `caster` can't use `ability` at all ("" = it can try), for the UI.
static func lacks(caster: SimEntity, ability: int) -> String:
	if FROM_ITEM.has(ability) and granting_item(caster, ability) < 0:
		return "Needs an item that casts it"
	if not has_rank(caster, ability):
		return "Needs %s %d" % [StatRules.SCHOOLS[SCHOOL[ability]].capitalize(), RANK[ability]]
	return ""


## Whether the entity holds a shield (armour in the off hand), for Brace.
static func has_shield(e: SimEntity) -> bool:
	return SimItems.amount(e.worn.get("off_hand", ""), "armor") > 0


## Living characters within `radius` of `target` (horizontally, at most a
## level up or down), in id order.
static func characters_near(state: SimState, target: Vector3i, radius: int) -> Array[SimEntity]:
	var result: Array[SimEntity] = []
	for e in state.entities:
		if e.is_alive() and e.takes_turns() and absi(e.cell.y - target.y) <= 1 and in_range(target, e.cell, radius):
			result.append(e)
	return result


## Who a Combust at `target` sets off: Hot or Burning, the caster aside.
static func combust_victims(state: SimState, caster: SimEntity, target: Vector3i) -> Array[SimEntity]:
	var result: Array[SimEntity] = []
	for e in characters_near(state, target, COMBUST_RADIUS):
		if e != caster and e.temperature >= EntityOps.TEMP_MAX - 1:
			result.append(e)
	return result


## Who a Wellspring at `target` heals: those standing in water.
static func in_water_near(state: SimState, target: Vector3i) -> Array[SimEntity]:
	var result: Array[SimEntity] = []
	for e in characters_near(state, target, WELLSPRING_RADIUS):
		if state.grid.surface_type[state.grid.index(e.cell)] == SimMaterials.Surface.WATER:
			result.append(e)
	return result


## Index of the first carried ammunition (-1 = none).
static func ammo_index(e: SimEntity) -> int:
	for i in e.inventory.size():
		if SimItems.has_property(e.inventory[i], "ammo"):
			return i
	return -1


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


## `item` picks what Pickpocket takes (-1 = the first item); see StatRules.can_pick().
static func validate(state: SimState, caster: SimEntity, ability: int, target: Vector3i, destination: Vector3i, item: int = -1) -> bool:
	if ability < 0 or ability >= NAMES.size() or not available(caster).has(ability) or not has_rank(caster, ability):
		return false
	if not CombatRules.can_act(state, caster, AP_COST[ability]):
		return false
	if caster.cooldown(ability) > 0:
		return false
	if not state.grid.in_bounds(target) or state.grid.is_solid(target):
		return false
	var self_target := (ability == Ability.MEND or ability == Ability.KINDLE or ability == Ability.BRACE) and target == caster.cell
	if not self_target and not can_reach(ability, caster.cell, target):
		return false
	if needs_line_of_sight(ability) and not SimLos.has_line_of_sight(state.grid, caster.cell, target):
		return false
	if SHOTS.has(ability) and not AttackCommand.in_reach(state, caster, target):
		return false  # needs a bow or sling, and the target within its range
	var victim := state.entity_at(target)
	var other_victim := victim != null and victim.id != caster.id
	match ability:
		Ability.FIREBOLT, Ability.RAIN, Ability.FROST, Ability.OIL_FLASK, Ability.OVERGROWTH, Ability.SHROUD, Ability.SMOKE_BOMB:
			return true
		Ability.COMBUST:
			return not combust_victims(state, caster, target).is_empty()
		Ability.GLACIER:
			for c in splash_cells(state.grid, target, GLACIER_RADIUS):
				if state.grid.surface_type[state.grid.index(c)] == SimMaterials.Surface.WATER:
					return true
			return false
		Ability.WELLSPRING:
			return not in_water_near(state, target).is_empty()
		Ability.DREAD:
			return other_victim and victim.takes_turns() and victim.faction != caster.faction
		Ability.BRACE:
			return target == caster.cell and has_shield(caster)
		Ability.SNARE:
			return (victim == null and not state.snares.has(target)
					and SimPathfinder.is_standable(state, target, caster.id))
		Ability.KINDLE:
			return victim != null
		Ability.DRAIN, Ability.DISTRACT, Ability.BACKSTAB, Ability.PINNING_SHOT:
			return other_victim and victim.takes_turns()
		Ability.LOADED_SHOT:
			return ammo_index(caster) >= 0 and not (victim != null and victim.id == caster.id)
		Ability.BLIGHT:
			var corpse := state.corpse_at(target)
			if corpse != null and not corpse.blighted:
				return true
			for c in splash_cells(state.grid, target, BLIGHT_RADIUS):
				var s: int = state.grid.surface_type[state.grid.index(c)]
				if s == SimMaterials.Surface.WATER or s == SimMaterials.Surface.VINES:
					return true
			return false
		Ability.TELEPORT:
			return (other_victim
					and victim.mass <= StatRules.teleport_limit(caster)
					and in_range(caster.cell, destination, RANGE[Ability.TELEPORT])
					and EntityOps.is_free(state, destination)
					and drop_height(state, destination) <= TELEPORT_MAX_DROP
					and SimLos.has_line_of_sight(state.grid, caster.cell, destination))
		Ability.SHOVE:
			return other_victim and victim.mass <= StatRules.shove_limit(caster)
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
			if item >= 0 and (other_victim and (item >= victim.inventory.size() or not StatRules.can_pick(caster, victim.inventory[item]))):
				return false
			return (not state.combat.active and other_victim and victim.takes_turns()
					and not victim.inventory.is_empty()
					and (victim.faction != caster.faction or victim.owner != caster.owner))
		Ability.REVIVE:
			var corpse: SimEntity = state.corpse_at(target)
			return (not state.combat.active and corpse != null and corpse.faction == caster.faction
					and victim == null)  # nobody standing on the body
	return false


@warning_ignore("integer_division")
static func execute(state: SimState, caster: SimEntity, ability: int, target: Vector3i, destination: Vector3i, item: int = -1) -> void:
	CombatRules.spend(state, caster, AP_COST[ability])
	if FROM_ITEM.has(ability):
		caster.inventory.remove_at(granting_item(caster, ability))
	caster.cooldowns[ability] = COOLDOWN[ability]
	state.emit_event(SimEvent.Type.CAST, target, caster.id, -1, ability)
	var victim := state.entity_at(target)
	match ability:
		Ability.FIREBOLT:
			if victim != null:
				EntityOps.damage(state, victim, FIREBOLT_DAMAGE + caster.spell_power() + potency(caster, ability), caster.id, EntityOps.Element.FIRE)
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
				if state.grid.surface_type[i] == SimMaterials.Surface.POISON:
					state.grid.edit_surfaces()
					state.grid.surface_type[i] = SimMaterials.Surface.WATER  # rain washes poison clean
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
			EntityOps.heal(state, victim, MEND_HEAL + StatRules.heal_cast_bonus(caster) + potency(caster, ability), caster.id)
		Ability.CLEAVE:
			_cleave(state, caster)
		Ability.SHOCKWAVE:
			var line := line_cells(state.grid, caster.cell, target)
			var wave := state.emit_event(SimEvent.Type.SHOCKWAVE, target, caster.id)
			wave.cells.assign(line)
			for c in line:
				var hit := state.entity_at(c)
				if hit != null and hit != caster:
					EntityOps.add_stagger(state, hit, SHOCKWAVE_STAGGER + potency(caster, ability) / 2, caster.id)
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
			_pickpocket(state, caster, victim, maxi(item, 0))
		Ability.KINDLE:
			_kindle(state, caster, victim)
		Ability.OVERGROWTH:
			var grown: Array[Vector3i] = []
			for c in splash_cells(state.grid, target, OVERGROWTH_RADIUS):
				if state.grid.surface_type[state.grid.index(c)] == SimMaterials.Surface.NONE:
					state.grid.add_surface(c, SimMaterials.Surface.VINES, VINES_AMOUNT)
					grown.append(c)
			var event := state.emit_event(SimEvent.Type.GREW, target, caster.id)
			event.cells.assign(grown)
			FireRules.catch_from_fire(state, grown)
			for c in grown:
				var caught := state.entity_at(c)
				if caught != null:
					EntityOps.slow_if_in_oil(state, caught)
		Ability.DRAIN:
			var before := victim.hp
			EntityOps.damage(state, victim, DRAIN_DAMAGE + caster.spell_power() + potency(caster, ability), caster.id, EntityOps.Element.DEATH)
			EntityOps.heal(state, caster, before - victim.hp, caster.id)
		Ability.BLIGHT:
			_blight(state, caster, target)
		Ability.DISTRACT:
			victim.distracted = maxi(1, DISTRACT_TURNS - victim.mind / 4)
			victim.facing = SimPerception.facing_toward(caster.cell, victim.cell, victim.facing)  # its back to the caster
			state.emit_event(SimEvent.Type.DISTRACTED, victim.cell, victim.id, caster.id, victim.distracted)
		Ability.BACKSTAB:
			var behind := StatRules.is_behind(caster, victim)
			var hit := StatRules.hit_damage(caster, victim)
			state.emit_event(SimEvent.Type.ATTACKED, victim.cell, victim.id, caster.id)
			EntityOps.damage(state, victim, hit * 2 if behind else hit, caster.id)
		Ability.LOADED_SHOT:
			_loaded_shot(state, caster, target, victim)
		Ability.PINNING_SHOT:
			state.emit_event(SimEvent.Type.ATTACKED, victim.cell, victim.id, caster.id)
			EntityOps.damage(state, victim, StatRules.hit_damage(caster, victim), caster.id)
			if victim.is_alive():
				victim.pinned = EntityOps.PIN_TURNS
				state.emit_event(SimEvent.Type.PINNED, victim.cell, victim.id, caster.id)
		Ability.COMBUST:
			var victims := combust_victims(state, caster, target)
			var burst := state.emit_event(SimEvent.Type.COMBUSTED, target, caster.id)
			for e in victims:
				burst.cells.append(e.cell)
			for e in victims:
				EntityOps.damage(state, e, COMBUST_DAMAGE + caster.spell_power() + potency(caster, ability), caster.id, EntityOps.Element.FIRE)
				FireRules.ignite(state, e.cell)
		Ability.GLACIER:
			_glacier(state, caster, target)
		Ability.WELLSPRING:
			var healed := in_water_near(state, target)
			var spring := state.emit_event(SimEvent.Type.WELLSPRING, target, caster.id)
			for e in healed:
				spring.cells.append(e.cell)
			for e in healed:
				EntityOps.heal(state, e, WELLSPRING_HEAL + StatRules.heal_cast_bonus(caster) + potency(caster, ability), caster.id)
		Ability.SHROUD, Ability.SMOKE_BOMB:
			var shroud := ability == Ability.SHROUD
			var gas := SimMaterials.Gas.DARKNESS if shroud else SimMaterials.Gas.SMOKE
			var cells := splash_cells(state.grid, target, SHROUD_RADIUS if shroud else SMOKE_BOMB_RADIUS)
			for c in cells:
				state.grid.add_gas(c, gas, SHROUD_GAS if shroud else SMOKE_BOMB_GAS)
			var cloud := state.emit_event(SimEvent.Type.CLOUDED, target, caster.id, -1, gas)
			cloud.cells.assign(cells)
		Ability.DREAD:
			_dread(state, caster, victim)
		Ability.BRACE:
			caster.braced = 1
			state.emit_event(SimEvent.Type.BRACED, caster.cell, caster.id)
		Ability.SNARE:
			state.snares[target] = caster.id
			state.emit_event(SimEvent.Type.SNARE_SET, target, caster.id)


## Freezes all the water in a wide area at once, and whoever stands in it.
static func _glacier(state: SimState, caster: SimEntity, target: Vector3i) -> void:
	var grid := state.grid
	var frozen: Array[Vector3i] = []
	for c in splash_cells(grid, target, GLACIER_RADIUS):
		var i := grid.index(c)
		if grid.surface_type[i] != SimMaterials.Surface.WATER:
			continue
		grid.edit_surfaces()
		grid.surface_type[i] = SimMaterials.Surface.ICE
		grid.edit_heat()
		grid.set_temperature(i, mini(grid.temperature[i], SimMaterials.CHILL_TEMPERATURE))
		if grid.fire[i] > 0:
			grid.set_fire(i, 0)
		frozen.append(c)
		state.emit_event(SimEvent.Type.FROZE, c)
	for c in frozen:
		var caught := state.entity_at(c)
		if caught != null:
			EntityOps.change_temperature(state, caught, EntityOps.TEMP_MIN - caught.temperature, caster.id)


## The victim's nerve breaks: what it holds in its off hand falls into its
## pack (no wearing it again until the fight is over) and it runs: on its
## next turn in combat, at once outside.
static func _dread(state: SimState, caster: SimEntity, victim: SimEntity) -> void:
	var held := EquipRules.worn(victim, EquipRules.OFF)
	if held != "":
		victim.inventory.append_array(EquipRules.put(victim, EquipRules.OFF, ""))
	var event := state.emit_event(SimEvent.Type.DREADED, victim.cell, victim.id, caster.id)
	event.text = held
	victim.dread_from = caster.cell
	if state.combat.active:
		victim.dread = DREAD_TURNS
	else:
		EntityOps.flee(state, victim, caster.cell, FLEE_CELLS + potency(caster, Ability.DREAD))


## Heats the target a level; a barrel's contents react: oil catches fire,
## water boils off as steam.
static func _kindle(state: SimState, caster: SimEntity, victim: SimEntity) -> void:
	if victim.takes_turns():
		EntityOps.change_temperature(state, victim, KINDLE_HEAT, caster.id)
	elif victim.contents_surface == SimMaterials.Surface.OIL and victim.contents_amount > 0:
		FireRules.ignite(state, victim.cell)
	elif victim.contents_surface == SimMaterials.Surface.WATER and victim.contents_amount > 0:
		state.grid.add_gas(victim.cell, SimMaterials.Gas.STEAM, KINDLE_STEAM)


## Rots what is there: water turns to poison, vines wither, and a corpse
## bursts into a cloud of poison gas (once).
static func _blight(state: SimState, caster: SimEntity, target: Vector3i) -> void:
	var grid := state.grid
	var cells := splash_cells(grid, target, BLIGHT_RADIUS)
	var event := state.emit_event(SimEvent.Type.BLIGHTED, target, caster.id)
	event.cells.assign(cells)
	for c in cells:
		var i := grid.index(c)
		if grid.surface_type[i] == SimMaterials.Surface.WATER:
			grid.edit_surfaces()
			grid.surface_type[i] = SimMaterials.Surface.POISON
		elif grid.surface_type[i] == SimMaterials.Surface.VINES:
			grid.clear_surface(i)
	var corpse := state.corpse_at(target)
	if corpse != null and not corpse.blighted:
		corpse.blighted = true
		for c in cells:
			grid.add_gas(c, SimMaterials.Gas.POISON, BLIGHT_GAS)
		FireRules.catch_gas_from_fire(state, cells)


## A hit with the bow or sling, and whatever the arrow carries.
static func _loaded_shot(state: SimState, caster: SimEntity, target: Vector3i, victim: SimEntity) -> void:
	var ammo: String = caster.inventory[ammo_index(caster)]
	caster.inventory.remove_at(ammo_index(caster))
	var shot := state.emit_event(SimEvent.Type.ITEM_USED, target, caster.id, caster.id)
	shot.text = ammo
	if victim != null:
		state.emit_event(SimEvent.Type.ATTACKED, victim.cell, victim.id, caster.id)
		EntityOps.damage(state, victim, StatRules.hit_damage(caster, victim), caster.id)
	var splash: String = SimItems.info(ammo).get("splash", "")
	if splash != "":
		var surface := SimMaterials.Surface.WATER if splash == "water" else SimMaterials.Surface.OIL
		var cells := splash_cells(state.grid, target, SHOT_SPLASH_RADIUS)
		for c in cells:
			state.grid.add_surface(c, surface, SHOT_SPLASH_AMOUNT)
			var soaked := state.entity_at(c)
			if soaked != null and surface == SimMaterials.Surface.WATER:
				EntityOps.cool_with_water(state, soaked, 1, caster.id)
		FireRules.catch_from_fire(state, cells)
	if SimItems.amount(ammo, "chill") > 0 and victim != null and victim.is_alive():
		EntityOps.change_temperature(state, victim, -SimItems.amount(ammo, "chill"), caster.id)
	if SimItems.has_property(ammo, "ignite"):
		FireRules.ignite(state, target, victim == null or not victim.is_alive())
		if victim != null and victim.is_alive():
			EntityOps.change_temperature(state, victim, FIREBOLT_HEAT, caster.id)


## Pushes the victim up to SHOVE_DISTANCE cells away from the caster. Walls and
## other entities stop it (and hurt); ledges drop it.
@warning_ignore("integer_division")
static func _shove(state: SimState, caster: SimEntity, victim: SimEntity) -> void:
	var dir := Vector3i(signi(victim.cell.x - caster.cell.x), 0, signi(victim.cell.z - caster.cell.z))
	if dir == Vector3i.ZERO:
		return
	if victim.braced > 0:
		state.emit_event(SimEvent.Type.BRACED, victim.cell, victim.id, caster.id)  # it holds its ground
		return
	var path: Array[Vector3i] = []
	var hit_wall := false
	var hit: SimEntity = null
	for _i in SHOVE_DISTANCE + potency(caster, Ability.SHOVE) / 2:
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


## Lifts an item: the victim's first, or one a skilled thief chose. Whoever sees it happen (the victim
## included, if it can see the thief) reacts: neutrals get suspicious, then
## hostile; enemies spot the thief and a fight starts.
static func _pickpocket(state: SimState, caster: SimEntity, victim: SimEntity, index: int) -> void:
	var item: String = victim.inventory[index]
	victim.inventory.remove_at(index)
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
		elif grid.surface_type[i] == SimMaterials.Surface.VINES:
			grid.clear_surface(i)  # frost kills the vines
		var occupant := state.entity_at(c)
		if occupant != null:
			EntityOps.damage(state, occupant, FROST_DAMAGE + caster.spell_power() + potency(caster, Ability.FROST), caster.id, EntityOps.Element.FROST)
			EntityOps.change_temperature(state, occupant, -FROST_CHILL, caster.id)


## Hits every entity adjacent to the caster, friend or foe.
static func _cleave(state: SimState, caster: SimEntity) -> void:
	var victims: Array[SimEntity] = []
	for e in state.entities:
		if e.is_alive() and e != caster and is_adjacent(caster.cell, e.cell):
			victims.append(e)
	for e in victims:
		state.emit_event(SimEvent.Type.ATTACKED, e.cell, e.id, caster.id)
		EntityOps.damage(state, e, StatRules.hit_damage(caster, e) + potency(caster, Ability.CLEAVE), caster.id)
