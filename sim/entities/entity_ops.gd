class_name EntityOps
extends RefCounted
## Shared rules for changing entities: damage, death, placement and falling.

## What dealt damage. Presentation colours damage numbers by it.
enum Element { PHYSICAL, FIRE, FROST }

## Damage per level fallen beyond the first.
const FALL_DAMAGE_PER_LEVEL := 4
const COLLISION_DAMAGE := 2
## Props (barrels) sitting in fire take this much every tick.
const FIRE_DAMAGE_PER_TICK := 1
## One instance of burn damage: when fire starts under a character, for every
## burning cell it walks over, and at the start of each turn while burning.
const BURN_DAMAGE := 2
## Temperature levels: -2 Frozen, -1 Cold, 0 Normal, 1 Hot, 2 Burning.
const TEMP_MIN := -2
const TEMP_MAX := 2
## Turns Burning (turn-start fire damage) and Frozen (turn skipped) last
## before easing to Hot or Cold, which fade at the next turn start.
const BURN_TURNS := 3
const FREEZE_TURNS := 1
## Stagger from a physical hit by someone (an attack or ability), and from
## walking onto ice (per cell, in combat). Knocking a normal character down
## takes 3 (SimArchetypes.DEFAULT_STAGGER).
const HIT_STAGGER := 1
const ICE_STAGGER := 1
## Turns a character stays slowed after stepping in oil (this one and the next).
const SLOW_TURNS := 2


static func is_free(state: SimState, c: Vector3i) -> bool:
	return state.grid.in_bounds(c) and not state.grid.is_solid(c) and state.entity_at(c) == null


static func damage(state: SimState, e: SimEntity, amount: int, source_id: int = -1, element: Element = Element.PHYSICAL) -> void:
	if not e.is_alive() or amount <= 0:
		return
	e.hp = maxi(e.hp - amount, 0)
	var event := state.emit_event(SimEvent.Type.DAMAGED, e.cell, e.id, source_id, amount)
	event.element = element
	if e.takes_turns() and e.faction != SimEntity.Faction.NONE:
		_provoke(state, e, state.get_entity(source_id) if source_id >= 0 else null)
	if e.hp == 0:
		_die(state, e)
	elif element == Element.PHYSICAL and source_id >= 0:
		add_stagger(state, e, HIT_STAGGER, source_id)


## Hurting a fighter pulls it (and whoever hurt it) into a fight: the next one
## outside combat, the current one during combat.
static func _provoke(state: SimState, victim: SimEntity, source: SimEntity) -> void:
	for e: SimEntity in [victim, source]:
		if e == null or not e.takes_turns() or e.faction == SimEntity.Faction.NONE or e.in_combat:
			continue
		if state.combat.active:
			CombatRules.join(state, e)
		else:
			e.in_combat = true
			state.provoked = true


# --- Temperature --------------------------------------------------------------

## Moves an entity's temperature by `delta` levels (clamped to -2..2).
## Reaching Burning hits at once with burn damage; reaching Frozen ends its
## turn. Warming a frozen character on its own side's turn lets it act again.
static func change_temperature(state: SimState, e: SimEntity, delta: int, source_id: int = -1) -> void:
	if not e.is_alive() or not e.takes_turns():
		return
	var before := e.temperature
	var after := clampi(before + delta, TEMP_MIN, TEMP_MAX)
	if after == before:
		if after == TEMP_MAX and delta > 0:
			e.temp_turns = BURN_TURNS  # fed again: keeps burning
		return
	e.temperature = after
	state.emit_event(SimEvent.Type.TEMPERATURE, e.cell, e.id, source_id, after)
	if before == TEMP_MIN:
		state.emit_event(SimEvent.Type.THAWED, e.cell, e.id, source_id)
		if _on_own_turn(state, e):
			e.ap = maxi(e.ap, e.max_ap)
	if before == TEMP_MAX:
		state.emit_event(SimEvent.Type.EXTINGUISHED, e.cell, e.id, source_id)
	if after == TEMP_MAX:
		e.temp_turns = BURN_TURNS
		state.emit_event(SimEvent.Type.BURNING, e.cell, e.id, source_id)
		damage(state, e, BURN_DAMAGE, source_id, Element.FIRE)
	elif after == TEMP_MIN:
		e.temp_turns = FREEZE_TURNS
		e.ap = 0
		state.emit_event(SimEvent.Type.FROZEN, e.cell, e.id, source_id)


## Water cools an entity by `levels`, but never below Cold: only real cold
## (Frost) freezes. A burning character is still put out.
static func cool_with_water(state: SimState, e: SimEntity, levels: int, source_id: int = -1) -> void:
	var target := maxi(e.temperature - levels, TEMP_MIN + 1)
	if target < e.temperature:
		change_temperature(state, e, target - e.temperature, source_id)


## Fire appears under an entity (lit, or spreading to it): a character heats
## up to Burning; a prop just takes burn damage.
static func burn(state: SimState, e: SimEntity, source_id: int = -1) -> void:
	if not e.is_alive():
		return
	if e.takes_turns():
		change_temperature(state, e, TEMP_MAX, source_id)
	else:
		damage(state, e, BURN_DAMAGE, source_id, Element.FIRE)


## Walking over a burning cell: an instance of burn damage and one level hotter.
static func walk_through_fire(state: SimState, e: SimEntity) -> void:
	damage(state, e, BURN_DAMAGE, -1, Element.FIRE)
	change_temperature(state, e, 1)


## Each tick spent standing in fire: one level hotter, and a burning
## character keeps burning.
static func stand_in_fire(state: SimState, e: SimEntity) -> void:
	change_temperature(state, e, 1)


# --- Stagger and knockdown -----------------------------------------------------

## Builds stagger (in combat); reaching the entity's stagger_max knocks it
## down. Stagger clears at the start of the entity's own turn, so knocking
## someone down takes hits landing within one round.
static func add_stagger(state: SimState, e: SimEntity, amount: int, source_id: int = -1) -> void:
	if not state.combat.active or not e.is_alive() or not e.takes_turns() or e.knocked_down or amount <= 0:
		return
	e.stagger += amount
	state.emit_event(SimEvent.Type.STAGGERED, e.cell, e.id, source_id, amount)
	if e.stagger >= e.stagger_max:
		e.stagger = 0
		e.knocked_down = true
		e.ap = 0
		state.emit_event(SimEvent.Type.KNOCKED_DOWN, e.cell, e.id, source_id)


## An ally gets a knocked-down character back on its feet; on its own side's
## turn it can act right away.
static func help_up(state: SimState, e: SimEntity, helper_id: int = -1) -> void:
	if not e.knocked_down:
		return
	e.knocked_down = false
	e.knocked_skipping = false
	if _on_own_turn(state, e):
		e.ap = maxi(e.ap, e.max_ap)
	state.emit_event(SimEvent.Type.STOOD_UP, e.cell, e.id, helper_id)


## Brings a fallen character back (Revive): REVIVE_HP_PERCENT of its max HP,
## statuses cleared.
@warning_ignore("integer_division")
static func revive(state: SimState, e: SimEntity, reviver_id: int = -1) -> void:
	if e == null or e.is_alive():
		return
	e.hp = maxi(1, e.max_hp * SimAbilities.REVIVE_HP_PERCENT / 100)
	e.temperature = 0
	e.temp_turns = 0
	e.stagger = 0
	e.slowed = 0
	e.knocked_down = false
	e.knocked_skipping = false
	e.travel.clear()
	state.emit_event(SimEvent.Type.REVIVED, e.cell, e.id, reviver_id, e.hp)


static func _on_own_turn(state: SimState, e: SimEntity) -> bool:
	return state.combat.active and state.combat.side == e.faction


# --- Turns -------------------------------------------------------------------

## Start of an entity's turn (real time: every REALTIME_TICKS_PER_TURN ticks):
## cooldowns and statuses count down, stagger clears, a knocked-down or frozen
## character skips the turn (staying down or frozen through it, so allies can
## still help it up or thaw it), burning deals its damage, Hot and Cold fade,
## and the ground underfoot applies (oil slows, water cools).
static func turn_start(state: SimState, e: SimEntity) -> void:
	e.tick_cooldowns()
	e.tick_statuses()
	if not e.is_alive():
		return
	e.stagger = 0
	var skip := e.knocked_down or e.is_frozen()
	if e.knocked_down:
		e.knocked_skipping = true
	if e.is_frozen():
		e.temp_turns -= 1
	_ease_temperature(state, e)
	if skip:
		e.ap = 0
		state.emit_event(SimEvent.Type.TURN_SKIPPED, e.cell, e.id)
	on_ground(state, e)


## End of an entity's turn: after sitting a turn out, a knocked-down character
## gets up and a frozen one whose freeze has run out thaws to Cold.
static func turn_end(state: SimState, e: SimEntity) -> void:
	if not e.is_alive():
		return
	if e.knocked_skipping:
		e.knocked_down = false
		e.knocked_skipping = false
		state.emit_event(SimEvent.Type.STOOD_UP, e.cell, e.id)
	if e.is_frozen() and e.temp_turns <= 0:
		e.temperature = TEMP_MIN + 1
		state.emit_event(SimEvent.Type.THAWED, e.cell, e.id)
		state.emit_event(SimEvent.Type.TEMPERATURE, e.cell, e.id, -1, e.temperature)


static func _ease_temperature(state: SimState, e: SimEntity) -> void:
	if e.temperature == TEMP_MAX:
		damage(state, e, BURN_DAMAGE, -1, Element.FIRE)
		if not e.is_alive():
			return
		e.temp_turns -= 1
		if e.temp_turns <= 0:
			e.temperature = TEMP_MAX - 1
			state.emit_event(SimEvent.Type.EXTINGUISHED, e.cell, e.id)
			state.emit_event(SimEvent.Type.TEMPERATURE, e.cell, e.id, -1, e.temperature)
	elif e.temperature == TEMP_MIN:
		pass  # thaws at the end of the skipped turn (turn_end())
	elif e.temperature != 0:
		e.temperature = 0
		state.emit_event(SimEvent.Type.TEMPERATURE, e.cell, e.id, -1, 0)


## Effects of the surface an entity steps onto or stands in: oil slows, water
## cools by a level (down to Cold at most).
static func on_ground(state: SimState, e: SimEntity) -> void:
	if not e.is_alive():
		return
	var surface: int = state.grid.surface_type[state.grid.index(e.cell)]
	if surface == SimMaterials.Surface.WATER:
		cool_with_water(state, e, 1)
	slow_if_in_oil(state, e)


## Standing in oil slows a character (again) for SLOW_TURNS.
static func slow_if_in_oil(state: SimState, e: SimEntity) -> void:
	if not e.is_alive() or not e.takes_turns():
		return
	if state.grid.surface_type[state.grid.index(e.cell)] != SimMaterials.Surface.OIL:
		return
	if e.slowed == 0:
		state.emit_event(SimEvent.Type.SLOWED, e.cell, e.id)
	e.slowed = maxi(e.slowed, SLOW_TURNS)


static func heal(state: SimState, e: SimEntity, amount: int, source_id: int = -1) -> void:
	var healed := mini(amount, e.max_hp - e.hp)
	if not e.is_alive() or healed <= 0:
		return
	e.hp += healed
	state.emit_event(SimEvent.Type.HEALED, e.cell, e.id, source_id, healed)


## Moves an entity to a cell, then lets it fall until something holds it up.
## No cell effects (level setup, tests); moves in play use relocate().
static func place(state: SimState, e: SimEntity, c: Vector3i) -> void:
	e.cell = c
	settle(state, e)


## Moves an entity in play (teleported, blinked): it lands like place() and
## then gets whatever is in the cell it ends up in (see enter_cell()).
static func relocate(state: SimState, e: SimEntity, c: Vector3i) -> void:
	place(state, e, c)
	enter_cell(state, e)


## What a cell does to whoever arrives in it, however they got there (walking,
## shoved, teleported, falling): fire hurts and heats a level, water cools,
## oil slows, ice staggers (in combat). Every kind of movement goes through
## this, so the interactions are the same for all of them.
static func enter_cell(state: SimState, e: SimEntity) -> void:
	if not e.is_alive():
		return
	var i := state.grid.index(e.cell)
	if state.grid.fire[i] > 0:
		walk_through_fire(state, e)
		if not e.is_alive():
			return
	on_ground(state, e)
	if state.grid.surface_type[i] == SimMaterials.Surface.ICE:
		add_stagger(state, e, ICE_STAGGER)


@warning_ignore("integer_division")
static func settle(state: SimState, e: SimEntity) -> void:
	var levels := 0
	while true:
		var below := e.cell + Vector3i.DOWN
		if state.grid.is_solid(below) or state.entity_at(below) != null:
			break
		e.cell = below
		levels += 1
	if levels > 0:
		state.emit_event(SimEvent.Type.FELL, e.cell, e.id, -1, levels)
		damage(state, e, (levels - 1) * FALL_DAMAGE_PER_LEVEL)


@warning_ignore("integer_division")
static func _die(state: SimState, e: SimEntity) -> void:
	e.ap = 0
	state.emit_event(SimEvent.Type.DIED, e.cell, e.id)
	if e.contents_surface == SimMaterials.Surface.NONE or e.contents_amount <= 0:
		return
	var cells := state.grid.disc_cells(e.cell, 1)
	var each := e.contents_amount / cells.size()
	for c in cells:
		state.grid.add_surface(c, e.contents_surface, each)
	state.emit_event(SimEvent.Type.SPILLED, e.cell, e.id, -1, e.contents_surface)
	e.contents_amount = 0
	FireRules.catch_from_fire(state, cells)
