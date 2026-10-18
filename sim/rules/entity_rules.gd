class_name EntityRules
extends RefCounted
## Per-tick effects on entities: standing in fire keeps characters burning and
## damages props. Outside combat,
## entities walk their travel queue one cell per tick (every other tick while
## slowed), and cooldowns and statuses count down every
## CombatRules.REALTIME_TICKS_PER_TURN ticks.


static func step(state: SimState) -> void:
	var grid := state.grid
	if not state.combat.active:
		for e in state.entities:
			var half_speed := e.slowed > 0 or StatRules.is_overloaded(e) or (e.sneaking and e.thievery < StatRules.SNEAK_FAST_RANK)
			if e.is_alive() and not e.travel.is_empty() and (not half_speed or state.tick % 2 == 0):
				_walk(state, e)
		SimPerception.look_around(state)
		CrimeRules.step(state)
		if state.tick % CombatRules.REALTIME_TICKS_PER_TURN == CombatRules.REALTIME_TICKS_PER_TURN - 1:
			for e in state.entities:
				EntityOps.turn_end(state, e)
				EntityOps.turn_start(state, e)
	for e in state.entities:
		if not e.is_alive() or grid.fire[grid.index(e.cell)] == 0:
			continue
		if e.takes_turns():
			EntityOps.stand_in_fire(state, e)
		else:
			EntityOps.damage(state, e, EntityOps.FIRE_DAMAGE_PER_TICK, -1, EntityOps.Element.FIRE)


## One step along the travel queue. If someone stands in the way, the rest of
## the route is planned again around them; if that fails the walk stops.
static func _walk(state: SimState, e: SimEntity) -> void:
	var next: Vector3i = e.travel[0]
	if not SimPathfinder.is_standable(state, next, e.id):
		var detour := SimPathfinder.find_path(state, e.cell, e.travel.back(), e.id, false, true, TravelCommand.MAX_SEARCH_CELLS)
		if detour.is_empty():
			e.travel.clear()
			return
		e.travel.assign(detour)
		next = e.travel[0]
	e.travel.pop_front()
	e.facing = SimPerception.facing_toward(e.cell, next, e.facing)
	e.cell = next
	var moved := state.emit_event(SimEvent.Type.MOVED, next, e.id)
	moved.cells.assign([next])
	EntityOps.enter_cell(state, e)
