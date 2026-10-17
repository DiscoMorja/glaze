class_name EntityOps
extends RefCounted
## Shared rules for changing entities: damage, death, placement and falling.

## Damage per level fallen beyond the first.
const FALL_DAMAGE_PER_LEVEL := 4
const COLLISION_DAMAGE := 2
const FIRE_DAMAGE_PER_TICK := 1


static func is_free(state: SimState, c: Vector3i) -> bool:
	return state.grid.in_bounds(c) and not state.grid.is_solid(c) and state.entity_at(c) == null


static func damage(state: SimState, e: SimEntity, amount: int, source_id: int = -1) -> void:
	if not e.is_alive() or amount <= 0:
		return
	e.hp = maxi(e.hp - amount, 0)
	state.emit_event(SimEvent.Type.DAMAGED, e.cell, e.id, source_id, amount)
	if e.hp == 0:
		_die(state, e)


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
