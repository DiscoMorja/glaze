class_name EntityRules
extends RefCounted
## Per-tick effects of the world on entities: standing in fire burns.


static func step(state: SimState) -> void:
	var grid := state.grid
	for e in state.entities:
		if e.is_alive() and grid.fire[grid.index(e.cell)] > 0:
			EntityOps.damage(state, e, EntityOps.FIRE_DAMAGE_PER_TICK)
