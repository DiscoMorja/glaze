class_name FireRules
extends RefCounted
## Fire: burns flammable surfaces (producing smoke), spreads one cell per tick
## to neighbouring fuel, dies out without fuel, and turns water into steam.
## Spread decisions read a snapshot taken at the start of the pass.


## Most cells one ignition can light through a connected puddle.
const IGNITE_FLOOD_LIMIT := 2000


## Sets a cell on fire at full intensity. Lighting fuel sets the whole
## connected puddle (across steps of one level) alight at once.
static func ignite(state: SimState, c: Vector3i, burn_occupant: bool = true) -> void:
	_light(state, c, burn_occupant)
	var grid := state.grid
	if not _has_fuel(grid, c):
		return
	var seen := {c: true}
	var queue: Array[Vector3i] = [c]
	var head := 0
	while head < queue.size() and seen.size() < IGNITE_FLOOD_LIMIT:
		var current := queue[head]
		head += 1
		for n: Vector3i in SimGrid.NEIGHBORS_4:
			for dy: int in [0, 1, -1]:
				var nc := current + n + Vector3i(0, dy, 0)
				if seen.has(nc) or not _has_fuel(grid, nc):
					continue
				seen[nc] = true
				_light(state, nc)
				queue.append(nc)
				break


## Fuel just poured onto `cells` (a splash, a spill) catches at once where it
## touches fire, in the cell itself or a neighbour, and the fire runs through
## the whole connected puddle, instead of waiting for the next tick.
static func catch_from_fire(state: SimState, cells: Array[Vector3i]) -> void:
	var grid := state.grid
	for c in cells:
		if grid.fire[grid.index(c)] == 0 and _has_fuel(grid, c) and _fire_next_to(grid, c):
			ignite(state, c)


## Poison gas just released onto `cells` explodes at once where it touches fire.
static func catch_gas_from_fire(state: SimState, cells: Array[Vector3i]) -> void:
	var grid := state.grid
	for c in cells:
		if grid.gas_type[grid.index(c)] == SimMaterials.Gas.POISON and _fire_next_to(grid, c):
			GasRules.explode(state, c)
			return


static func _fire_next_to(grid: SimGrid, c: Vector3i) -> bool:
	if grid.fire[grid.index(c)] > 0:
		return true
	for n: Vector3i in SimGrid.NEIGHBORS_4:
		for dy: int in [0, 1, -1]:
			var nc := c + n + Vector3i(0, dy, 0)
			if grid.in_bounds(nc) and grid.fire[grid.index(nc)] > 0:
				return true
	return false


## Lights a cell; whoever stands there catches fire right away.
static func _light(state: SimState, c: Vector3i, burn_occupant: bool = true) -> void:
	var i := state.grid.index(c)
	if state.grid.gas_type[i] == SimMaterials.Gas.POISON:
		GasRules.explode(state, c)  # (which lights this cell again, gas-free)
		return
	var was_burning: bool = state.grid.fire[i] > 0
	if not was_burning:
		state.emit_event(SimEvent.Type.IGNITED, c)
	state.grid.set_fire(i, SimMaterials.FIRE_MAX)
	if not was_burning and burn_occupant:
		_burn_occupant(state, c)


static func _burn_occupant(state: SimState, c: Vector3i) -> void:
	var occupant := state.entity_at(c)
	if occupant != null:
		EntityOps.burn(state, occupant)


static func _has_fuel(grid: SimGrid, c: Vector3i) -> bool:
	if not grid.in_bounds(c) or grid.is_solid(c):
		return false
	var i := grid.index(c)
	return SimMaterials.is_flammable(grid.surface_type[i]) and grid.surface_amount[i] > 0


static func step(state: SimState) -> void:
	var grid := state.grid
	if grid.fire_cells.is_empty():
		return
	var fire := grid.fire
	var burning := grid.burning_cells()
	# Everyone reads the surfaces as they were at the start of the tick: fuel
	# used up is written after the loop (sparse, instead of copying the whole
	# surface arrays every tick on a big level).
	var types := grid.surface_type
	var amounts := grid.surface_amount
	var fuel_after := {}
	# Fire for next tick, sparse: cells absent here keep their current fire.
	var next_fire := {}
	grid.edit_heat()

	for i in burning:
		var f: int = fire[i]
		var c := grid.coord(i)
		var t: int = types[i]

		if t == SimMaterials.Surface.WATER:
			next_fire[i] = 0
			fuel_after[i] = maxi(amounts[i] - SimMaterials.WATER_PER_EXTINGUISH, 0)
			grid.add_gas_at(i, SimMaterials.Gas.STEAM, SimMaterials.STEAM_PER_EXTINGUISH)
			state.emit_event(SimEvent.Type.EXTINGUISHED, c)
		elif SimMaterials.is_flammable(t) and amounts[i] > 0:
			next_fire[i] = SimMaterials.FIRE_MAX
			fuel_after[i] = maxi(amounts[i] - SimMaterials.burn_rate(t), 0)
			grid.add_gas_at(i, SimMaterials.Gas.SMOKE, SimMaterials.SMOKE_PER_BURN_TICK)
			for n: Vector3i in SimGrid.NEIGHBORS_6:
				var nc := c + n
				if grid.is_solid(nc):
					continue
				var ni := grid.index(nc)
				if next_fire.get(ni, fire[ni]) > 0 or not SimMaterials.is_flammable(types[ni]) or amounts[ni] <= 0:
					continue
				next_fire[ni] = SimMaterials.FIRE_MAX
				state.emit_event(SimEvent.Type.IGNITED, nc)
		else:
			var remaining := f - SimMaterials.FIRE_DECAY
			next_fire[i] = maxi(remaining, 0)
			if remaining <= 0:
				state.emit_event(SimEvent.Type.BURNED_OUT, c)

		if next_fire.get(i, fire[i]) > 0:
			grid.set_temperature(i, maxi(grid.temperature[i], SimMaterials.FIRE_TEMPERATURE))

	var spent: Array = fuel_after.keys()
	spent.sort()
	for i: int in spent:
		if fuel_after[i] <= 0:
			grid.clear_surface(i)
		else:
			grid.edit_surfaces()
			grid.surface_amount[i] = fuel_after[i]

	var lit: Array[int] = []
	var blasts: Array[int] = []
	for i: int in next_fire:
		if fire[i] == 0 and next_fire[i] > 0:
			lit.append(i)
		grid.set_fire(i, next_fire[i])
		if next_fire[i] > 0 and grid.gas_type[i] == SimMaterials.Gas.POISON:
			blasts.append(i)
	# Fire spreading under someone sets them alight.
	lit.sort()
	for i in lit:
		_burn_occupant(state, grid.coord(i))
	blasts.sort()
	for i in blasts:
		GasRules.explode(state, grid.coord(i))
