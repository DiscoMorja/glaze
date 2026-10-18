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
## Turns a character keeps burning (turn-start damage) after catching fire.
const BURN_TURNS := 3
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


## Fire reaches an entity: a character catches fire (burning for BURN_TURNS)
## and takes an instance of burn damage; a prop just takes the damage.
static func burn(state: SimState, e: SimEntity, source_id: int = -1) -> void:
	if not e.is_alive():
		return
	if e.takes_turns():
		if e.burning == 0:
			state.emit_event(SimEvent.Type.BURNING, e.cell, e.id)
		e.burning = BURN_TURNS
	damage(state, e, BURN_DAMAGE, source_id, Element.FIRE)


## Standing in fire keeps a character burning; one whose fire had gone out
## catches fire again.
static func keep_burning(state: SimState, e: SimEntity) -> void:
	if e.burning == 0:
		burn(state, e)
	else:
		e.burning = BURN_TURNS


## Water puts a burning character out.
static func douse(state: SimState, e: SimEntity) -> void:
	if e.burning > 0:
		e.burning = 0
		state.emit_event(SimEvent.Type.EXTINGUISHED, e.cell, e.id)


## Start of an entity's turn (real time: every REALTIME_TICKS_PER_TURN ticks):
## statuses count down, burning deals its damage, and the ground underfoot
## applies (oil slows, water douses).
static func turn_start(state: SimState, e: SimEntity) -> void:
	e.tick_cooldowns()
	e.tick_statuses()
	if e.burning > 0 and e.is_alive():
		e.burning -= 1
		damage(state, e, BURN_DAMAGE, -1, Element.FIRE)
	on_ground(state, e)


## Effects of the surface an entity steps onto or stands in: oil slows, water
## douses fire.
static func on_ground(state: SimState, e: SimEntity) -> void:
	if not e.is_alive():
		return
	var surface: int = state.grid.surface_type[state.grid.index(e.cell)]
	if surface == SimMaterials.Surface.WATER:
		douse(state, e)
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
static func place(state: SimState, e: SimEntity, c: Vector3i) -> void:
	e.cell = c
	settle(state, e)


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
