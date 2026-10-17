class_name FireRules
extends RefCounted
## Fire: burns flammable surfaces (producing smoke), spreads one cell per tick
## to neighbouring fuel, dies out without fuel, and turns water into steam.
## Spread decisions read a snapshot taken at the start of the pass.


## Sets a cell on fire at full intensity.
static func ignite(state: SimState, c: Vector3i) -> void:
	var i := state.grid.index(c)
	if state.grid.fire[i] == 0:
		state.emit_event(SimEvent.Type.IGNITED, c)
	state.grid.fire[i] = SimMaterials.FIRE_MAX


static func step(state: SimState) -> void:
	var grid := state.grid
	var fire := grid.fire
	var burning := SimGrid.indices_in_range(fire, SimMaterials.FIRE_MAX)
	if burning.is_empty():
		return
	var types := grid.surface_type.duplicate()
	var amounts := grid.surface_amount.duplicate()
	var next_fire := fire.duplicate()

	for i in burning:
		var f: int = fire[i]
		var c := grid.coord(i)
		var t: int = types[i]

		if t == SimMaterials.Surface.WATER:
			next_fire[i] = 0
			var left: int = amounts[i] - SimMaterials.WATER_PER_EXTINGUISH
			if left <= 0:
				grid.clear_surface(i)
			else:
				grid.surface_amount[i] = left
			grid.add_gas_at(i, SimMaterials.Gas.STEAM, SimMaterials.STEAM_PER_EXTINGUISH)
			state.emit_event(SimEvent.Type.EXTINGUISHED, c)
		elif SimMaterials.is_flammable(t) and amounts[i] > 0:
			next_fire[i] = SimMaterials.FIRE_MAX
			var fuel_left: int = amounts[i] - SimMaterials.OIL_BURN_PER_TICK
			if fuel_left <= 0:
				grid.clear_surface(i)
			else:
				grid.surface_amount[i] = fuel_left
			grid.add_gas_at(i, SimMaterials.Gas.SMOKE, SimMaterials.SMOKE_PER_BURN_TICK)
			for n: Vector3i in SimGrid.NEIGHBORS_6:
				var nc := c + n
				if grid.is_solid(nc):
					continue
				var ni := grid.index(nc)
				if next_fire[ni] > 0 or not SimMaterials.is_flammable(types[ni]) or amounts[ni] <= 0:
					continue
				next_fire[ni] = SimMaterials.FIRE_MAX
				state.emit_event(SimEvent.Type.IGNITED, nc)
		else:
			var remaining := f - SimMaterials.FIRE_DECAY
			next_fire[i] = maxi(remaining, 0)
			if remaining <= 0:
				state.emit_event(SimEvent.Type.BURNED_OUT, c)

		if next_fire[i] > 0:
			grid.temperature[i] = maxi(grid.temperature[i], SimMaterials.FIRE_TEMPERATURE)

	grid.fire = next_fire
