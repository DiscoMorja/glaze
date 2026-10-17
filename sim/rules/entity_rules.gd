class_name EntityRules
extends RefCounted
## Per-tick effects on entities: standing in fire burns. Outside combat,
## entities walk their travel queue one cell per tick and cooldowns count down
## every CombatRules.REALTIME_TICKS_PER_TURN ticks.


static func step(state: SimState) -> void:
	var grid := state.grid
	if not state.combat.active:
		for e in state.entities:
			if e.is_alive() and not e.travel.is_empty():
				_walk(state, e)
		if state.tick % CombatRules.REALTIME_TICKS_PER_TURN == CombatRules.REALTIME_TICKS_PER_TURN - 1:
			for e in state.entities:
				e.tick_cooldowns()
	for e in state.entities:
		if e.is_alive() and grid.fire[grid.index(e.cell)] > 0:
			EntityOps.damage(state, e, EntityOps.FIRE_DAMAGE_PER_TICK)


## One step along the travel queue. If someone stands in the way, the rest of
## the route is planned again around them; if that fails the walk stops.
static func _walk(state: SimState, e: SimEntity) -> void:
	var next: Vector3i = e.travel[0]
	if not SimPathfinder.is_standable(state, next, e.id):
		var detour := SimPathfinder.find_path(state, e.cell, e.travel.back(), e.id)
		if detour.is_empty():
			e.travel.clear()
			return
		e.travel.assign(detour)
		next = e.travel[0]
	e.travel.pop_front()
	e.cell = next
	var moved := state.emit_event(SimEvent.Type.MOVED, next, e.id)
	moved.cells.assign([next])
	if state.grid.surface_type[state.grid.index(next)] == SimMaterials.Surface.ICE:
		e.travel.clear()
		state.emit_event(SimEvent.Type.SLIPPED, next, e.id)
