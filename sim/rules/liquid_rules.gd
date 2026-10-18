class_name LiquidRules
extends RefCounted
## Liquid transport: liquids fall when unsupported, otherwise spread to open
## neighbours with less liquid (and drain quickly off ledges). Reads the current
## grid and writes deltas, so results don't depend on iteration order. Only
## cells holding a liquid (and the cells they flow into) are visited.


const FLUIDS := [SimMaterials.Surface.WATER, SimMaterials.Surface.OIL, SimMaterials.Surface.POISON]


@warning_ignore("integer_division")
static func step(state: SimState) -> void:
	var grid := state.grid
	var now := [grid.surface_version, grid.solid_version]
	if now == grid.liquids_still_at:
		return  # settled (a calm sea), and nothing has changed since
	if not grid.has_any(SimGrid.FIELD_SURFACES):
		return
	var types := grid.surface_type
	var amounts := grid.surface_amount
	var active := SimGrid.indices_of(types, FLUIDS)
	if active.is_empty():
		grid.liquids_still_at = now
		return
	# Sparse: only cells that hold or receive something get entries.
	var delta := {}
	var next_types := {}
	var touched := {}

	for i in active:
		touched[i] = true
		var t: int = types[i]
		var amount: int = amounts[i]
		var c := grid.coord(i)

		var below := c + Vector3i.DOWN
		if not grid.is_solid(below):
			var bi := grid.index(below)
			if _can_receive(types, next_types, bi, t):
				delta[i] = delta.get(i, 0) - amount
				delta[bi] = delta.get(bi, 0) + amount
				next_types[bi] = t
				touched[bi] = true
				continue

		if amount < SimMaterials.min_spread(t):
			continue
		var viscosity := SimMaterials.viscosity(t)
		for n: Vector3i in SimGrid.NEIGHBORS_4:
			var nc := c + n
			if grid.is_solid(nc):
				continue
			var ni := grid.index(nc)
			if not _can_receive(types, next_types, ni, t):
				continue
			# A thick, shallow puddle doesn't creep onto dry, flat ground.
			if amount <= SimMaterials.puddle_hold(t) and grid.is_supported(nc) \
					and amounts[ni] == 0 and not next_types.has(ni):
				continue
			# Over a ledge the neighbour holds nothing for long, so drain as if it were empty.
			var diff: int = amount if not grid.is_supported(nc) else amount - amounts[ni]
			var flow := diff / viscosity
			if flow <= 0:
				continue
			delta[i] = delta.get(i, 0) - flow
			delta[ni] = delta.get(ni, 0) + flow
			next_types[ni] = t
			touched[ni] = true

	if delta.is_empty():
		grid.liquids_still_at = now
		return
	grid.edit_surfaces()
	types = grid.surface_type
	amounts = grid.surface_amount
	for i: int in touched:
		var d: int = delta.get(i, 0)
		if d == 0:
			continue
		var a: int = amounts[i] + d
		if a <= 0:
			grid.clear_surface(i)
		else:
			amounts[i] = a
			types[i] = next_types.get(i, types[i])


## Runs liquid steps (nothing else) until liquids stop moving, at most
## max_steps. Returns the steps run.
static func settle(state: SimState, max_steps: int) -> int:
	for i in max_steps:
		step(state)
		if state.grid.liquids_still_at == [state.grid.surface_version, state.grid.solid_version]:
			return i + 1
	return max_steps


## A cell can receive a liquid if it is empty or already holds the same liquid
## (including liquid scheduled to arrive this tick).
static func _can_receive(types: PackedByteArray, next_types: Dictionary, i: int, type: int) -> bool:
	var current: int = next_types.get(i, types[i])
	return current == SimMaterials.Surface.NONE or current == type
